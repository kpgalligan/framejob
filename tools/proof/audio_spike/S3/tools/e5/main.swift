import AVFoundation
import CoreAudio
import Foundation
import Synchronization

// E5: the preview's audio played by AVAudioEngine instead of the AVPlayer — the composition read
// through AVAssetReaderAudioMixOutput (the export's read, taps and ramps included) into a ring,
// an AVAudioSourceNode pulling it (where a master chain would run), the AVPlayer kept for the
// picture and started at the same host time with setRate(_:time:atHostTime:). Measured: reader
// prefill and player seek latency, the engine-vs-player offset at each start, its drift over a
// 60 s run, underruns, for three player clock set-ups. The engine's output is at volume 0.

setvbuf(stdout, nil, _IOLBF, 0)
let total = 120.0
let media = makeMedia()

// A 64x64 H.264 picture, 120 s at 30 fps, so the player has a video track as the app's does.
func makeVideo() -> URL {
    let url = workDir.appendingPathComponent("v.mov")
    if FileManager.default.fileExists(atPath: url.path) { return url }
    let writer = try! AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 64])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
    for f in 0..<Int(total * 30) {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: 30))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    return url
}
let videoURL = makeVideo()

/// Builds the 120 s composition: video, and two audio tracks with taps and ramps — A (stereo)
/// six times over at 0.5, B (mono) six times over with a 1 -> 0.25 ramp each 20 s.
func makeComposition() -> Built {
    var built = build([], seconds: 1)
    let composition = built.composition
    let vAsset = AVURLAsset(url: videoURL)  // held: a track whose asset is gone cannot be inserted
    let v = vAsset.tracks(withMediaType: .video)[0]
    let vt = composition.addMutableTrack(withMediaType: .video, preferredTrackID: 1)!
    do { try vt.insertTimeRange(v.timeRange, of: v, at: .zero) } catch { print("video insert failed: \(error), range \(v.timeRange)"); exit(1) }
    var params: [AVAudioMixInputParameters] = []
    var records: [TapRecord] = []
    for (k, url) in [media.a, media.b].enumerated() {
        let srcAsset = AVURLAsset(url: url)
        let src = srcAsset.tracks(withMediaType: .audio)[0]
        let t = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID(1001 + k))!
        for rep in 0..<6 {
            try! t.insertTimeRange(CMTimeRange(start: .zero, duration: cmTime(20)), of: src, at: cmTime(Double(rep) * 20))
        }
        let p = AVMutableAudioMixInputParameters(track: t)
        if k == 0 {
            p.setVolumeRamp(fromStartVolume: 0.5, toEndVolume: 0.5, timeRange: CMTimeRange(start: .zero, duration: cmTime(total)))
        } else {
            for rep in 0..<6 {
                p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0.25, timeRange: CMTimeRange(start: cmTime(Double(rep) * 20), duration: cmTime(20)))
            }
        }
        let r = TapRecord(name: "t\(k)", seconds: 1)  // the store is 1 s: these taps only log
        p.audioTapProcessor = makeRecordingTap(r)
        params.append(p); records.append(r)
    }
    let mix = AVMutableAudioMix(); mix.inputParameters = params
    built = Built(composition: composition, mix: mix, records: records)
    return built
}

// ---- the ring ---------------------------------------------------------------------------
final class Ring: @unchecked Sendable {
    let capacity: Int
    let data: UnsafeMutablePointer<Float>
    let written = Atomic<Int>(0)
    let read = Atomic<Int>(0)
    init(frames: Int) { capacity = frames; data = .allocate(capacity: frames * 2); data.initialize(repeating: 0, count: frames * 2) }
    deinit { data.deallocate() }
    var available: Int { written.load(ordering: .acquiring) - read.load(ordering: .relaxed) }
    func write(_ src: UnsafePointer<Float>, frames: Int) -> Int {
        let w = written.load(ordering: .relaxed), r = read.load(ordering: .acquiring)
        let n = min(frames, capacity - (w - r))
        for i in 0..<n { let at = (w + i) % capacity; data[2 * at] = src[2 * i]; data[2 * at + 1] = src[2 * i + 1] }
        written.store(w + n, ordering: .releasing)
        return n
    }
    func pull(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        let rd = read.load(ordering: .relaxed), w = written.load(ordering: .acquiring)
        let n = min(frames, w - rd)
        for i in 0..<n { let at = (rd + i) % capacity; l[i] = data[2 * at]; r[i] = data[2 * at + 1] }
        read.store(rd + n, ordering: .releasing)
        return n
    }
}

// ---- one play session: a reader thread feeding a ring -----------------------------------
final class Session: @unchecked Sendable {
    let ring = Ring(frames: 48000 * 2)
    let t0: Double
    let cancelled = Atomic<Bool>(false)
    let finished = Atomic<Bool>(false)
    let firstBufferNs = Atomic<UInt64>(0)
    // Render-thread state and log.
    let playing = Atomic<Bool>(false)
    let startHost = Atomic<UInt64>(0)
    var consumed = 0
    let logCount = Atomic<Int>(0)
    let logHost: UnsafeMutablePointer<UInt64> = .allocate(capacity: 100_000)
    let logComp: UnsafeMutablePointer<Double> = .allocate(capacity: 100_000)
    let underruns = Atomic<Int>(0)
    init(t0: Double, built: Built) {
        self.t0 = t0
        let thread = Thread { [self] in
            let reader = try! AVAssetReader(asset: built.composition)
            reader.timeRange = CMTimeRange(start: cmTime(t0), duration: .positiveInfinity)
            let out = AVAssetReaderAudioMixOutput(audioTracks: built.composition.tracks(withMediaType: .audio), audioSettings: floatStereo)
            out.audioMix = built.mix
            reader.add(out)
            reader.startReading()
            var tmp = [Float](repeating: 0, count: 48000 * 2)
            while !cancelled.load(ordering: .relaxed), let sb = out.copyNextSampleBuffer() {
                if firstBufferNs.load(ordering: .relaxed) == 0 { firstBufferNs.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed) }
                let n = CMSampleBufferGetNumSamples(sb)
                let block = CMSampleBufferGetDataBuffer(sb)!
                _ = tmp.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * 8, destination: $0.baseAddress!) }
                var done = 0
                while done < n && !cancelled.load(ordering: .relaxed) {
                    done += tmp.withUnsafeBufferPointer { ring.write($0.baseAddress! + 2 * done, frames: n - done) }
                    if done < n { usleep(2000) }
                }
            }
            reader.cancelReading()
            finished.store(true, ordering: .releasing)
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }
}

let current = Atomic<Int>(0)  // index into `sessions`, 0 = none
nonisolated(unsafe) var sessions: [Session?] = [nil]

var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func hostToSeconds(_ h: UInt64) -> Double { Double(h) * Double(tb.numer) / Double(tb.denom) / 1e9 }
func secondsToHost(_ s: Double) -> UInt64 { UInt64(s * 1e9 * Double(tb.denom) / Double(tb.numer)) }

let engine = AVAudioEngine()
let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
let source = AVAudioSourceNode(format: format) { _, timestamp, frameCount, abl -> OSStatus in
    let list = UnsafeMutableAudioBufferListPointer(abl)
    let l = list[0].mData!.assumingMemoryBound(to: Float.self)
    let r = list[1].mData!.assumingMemoryBound(to: Float.self)
    let frames = Int(frameCount)
    l.initialize(repeating: 0, count: frames); r.initialize(repeating: 0, count: frames)
    let index = current.load(ordering: .acquiring)
    guard index > 0, let s = sessions[index], s.playing.load(ordering: .acquiring) else { return noErr }
    let ts = timestamp.pointee
    var offset = 0
    let start = s.startHost.load(ordering: .relaxed)
    if ts.mHostTime < start {
        offset = Int((hostToSeconds(start - ts.mHostTime) * 48000).rounded())
        if offset >= frames { return noErr }
    }
    let comp = s.t0 + Double(s.consumed) / 48000
    let got = s.ring.pull(l + offset, r + offset, frames: frames - offset)
    if got < frames - offset { s.underruns.add(1, ordering: .relaxed) }
    // The master insert would run here, on l and r.
    let k = s.logCount.load(ordering: .relaxed)
    if k < 100_000 {
        s.logHost[k] = ts.mHostTime + secondsToHost(Double(offset) / 48000)
        s.logComp[k] = comp
        s.logCount.store(k + 1, ordering: .releasing)
    }
    s.consumed += got
    return noErr
}
engine.attach(source)
engine.connect(source, to: engine.mainMixerNode, format: format)
engine.mainMixerNode.outputVolume = 0
try! engine.start()
print(String(format: "engine: output presentation latency %.1f ms, IO buffer %.1f ms", engine.outputNode.presentationLatency * 1000,
             Double(engine.outputNode.outputFormat(forBus: 0).sampleRate) > 0 ? 0 : 0))

func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

func defaultOutputUID() -> String {
    var id = AudioObjectID(0); var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    var uid: Unmanaged<CFString>?; size = UInt32(MemoryLayout<CFString?>.size)
    addr.mSelector = kAudioDevicePropertyDeviceUID
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid)
    return uid!.takeRetainedValue() as String
}

func run(config: String, seconds playFor: [Double], at starts: [Double]) {
    print("== \(config)")
    let built = makeComposition()         // what the reader plays
    let playerBuilt = makeComposition()   // the player's own, so no tap object is shared
    let item = AVPlayerItem(asset: playerBuilt.composition)
    item.audioMix = playerBuilt.mix
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = false
    if config.contains("muted") { player.isMuted = true }
    var w = 0
    while item.status != .readyToPlay && w < 200 { wait(0.02); w += 1 }
    if config.contains("disabled") {
        for t in item.tracks where t.assetTrack?.mediaType == .audio { t.isEnabled = false }
    }
    if config.contains("sourceClock") {
        var clock: CMClock?
        CMAudioDeviceClockCreate(allocator: nil, deviceUID: defaultOutputUID() as CFString, clockOut: &clock)
        player.sourceClock = clock
    }
    for (k, t0) in starts.enumerated() {
        player.pause()
        let old = current.load(ordering: .relaxed)
        current.store(0, ordering: .releasing)
        if old > 0, let s = sessions[old] { s.cancelled.store(true, ordering: .relaxed); while !s.finished.load(ordering: .acquiring) { usleep(1000) } }
        let tReq = DispatchTime.now().uptimeNanoseconds
        let s = Session(t0: t0, built: built)
        sessions.append(s)
        var seekDoneNs: UInt64 = 0
        player.seek(to: cmTime(t0), toleranceBefore: .zero, toleranceAfter: .zero) { _ in seekDoneNs = DispatchTime.now().uptimeNanoseconds }
        while s.ring.available < 4800 || seekDoneNs == 0 { wait(0.002) }
        let readyNs = DispatchTime.now().uptimeNanoseconds
        let prefillMs = Double(s.firstBufferNs.load(ordering: .relaxed) - tReq) / 1e6
        let seekMs = Double(seekDoneNs - tReq) / 1e6
        // Both start at one host time 60 ms ahead.
        let startHost = mach_absolute_time() + secondsToHost(0.060)
        s.startHost.store(startHost, ordering: .relaxed)
        s.playing.store(true, ordering: .releasing)
        current.store(sessions.count - 1, ordering: .releasing)
        player.setRate(1, time: cmTime(t0), atHostTime: CMClockMakeHostTimeFromSystemUnits(startHost))
        var samples: [(host: Double, offsetMs: Double)] = []
        let end = Date().addingTimeInterval(playFor[k])
        while Date() < end {
            wait(0.05)
            let n = s.logCount.load(ordering: .acquiring)
            guard n > 0, let timebase = item.timebase else { continue }
            let host = s.logHost[n - 1], comp = s.logComp[n - 1]
            let playerT = CMSyncConvertTime(CMClockMakeHostTimeFromSystemUnits(host), from: CMClockGetHostTimeClock(), to: timebase).seconds
            samples.append((hostToSeconds(host), (comp - playerT) * 1000))
        }
        // Drift: least squares slope of the offset over the run, in ppm; skip the first second.
        let steady = samples.filter { $0.host - (samples.first?.host ?? 0) > 1.0 }
        var slope = 0.0
        if steady.count > 10 {
            let mx = steady.map { $0.host }.reduce(0, +) / Double(steady.count)
            let my = steady.map { $0.offsetMs }.reduce(0, +) / Double(steady.count)
            var sxy = 0.0, sxx = 0.0
            for p in steady { sxy += (p.host - mx) * (p.offsetMs - my); sxx += (p.host - mx) * (p.host - mx) }
            slope = sxy / sxx * 1000  // ms per s -> ppm (ms/s = 1000 ppm)
        }
        let offs = samples.map { $0.offsetMs }
        print(String(format: "  start at %5.1f s: reader first buffer %6.1f ms, ring 100 ms full at %6.1f ms, player seek done %6.1f ms; offset first %+.3f ms, last %+.3f ms, min %+.3f max %+.3f; drift %+.2f ppm over %.0f s; underruns %d",
                     t0, prefillMs, Double(readyNs - tReq) / 1e6, seekMs, offs.first ?? .nan, offs.last ?? .nan, offs.min() ?? .nan, offs.max() ?? .nan,
                     slope, playFor[k], s.underruns.load(ordering: .relaxed)))
    }
    player.pause()
    let old = current.load(ordering: .relaxed)
    current.store(0, ordering: .releasing)
    if old > 0, let s = sessions[old] { s.cancelled.store(true, ordering: .relaxed); while !s.finished.load(ordering: .acquiring) { usleep(1000) } }
    print("  tap calls per track: reader \(built.records.map { $0.calls.count }), player \(playerBuilt.records.map { $0.calls.count })")
}

// Reader speed: the whole 120 s composition read as fast as it goes (the offline premix's cost).
do {
    let built = makeComposition()
    let t = Date()
    _ = readMix(built, seconds: Int(total) + 1)
    let elapsed = Date().timeIntervalSince(t)
    print(String(format: "reader throughput: 120 s composition (2 tapped tracks + video) read in %.2f s = %.0fx real time", elapsed, total / elapsed))
}

let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "all"
let plan = ([60.0, 6, 6, 6], [2.0, 70, 95, 40])
if mode == "all" || mode == "muted" { run(config: "player audio enabled + muted, default clock", seconds: plan.0, at: plan.1) }
if mode == "all" || mode == "disabled" { run(config: "player audio tracks disabled, default clock", seconds: plan.0, at: plan.1) }
if mode == "all" || mode == "clock" { run(config: "player audio tracks disabled + sourceClock = output device clock", seconds: plan.0, at: plan.1) }
engine.stop()
