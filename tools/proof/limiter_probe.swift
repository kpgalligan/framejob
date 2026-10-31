import AppKit
import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox

// The clip limiter's probe (road map "audio" AP2, spec §11 AU-20..AU-25),
// compiled with app/Sources through swift_build. Arguments: the fixtures
// folder, a scratch folder. Prints one "ok"/"FAIL" line per row, each row's
// name first (L1, L3..L9), for limiter_probe.py to score; L2's outputs are
// written as raw Float32 and listed on "L2DATA <name> <ceiling dB> <file>"
// lines for the script's own meters.

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}
func f3(_ x: Double?) -> String { x.map { String(format: "%.3f", $0) } ?? "nil" }
func dB(_ x: Double) -> Double { 20 * log10(x) }

// MARK: - Signals

func readF32(_ name: String) -> [Float] {
    guard let data = try? Data(contentsOf: fixtures.appendingPathComponent(name)) else { return [] }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}
func writeF32(_ samples: [Float], _ name: String) -> String {
    let url = scratch.appendingPathComponent(name)
    samples.withUnsafeBytes { try? Data($0).write(to: url) }
    return url.path
}

/// The stage over whole channels, cut into blocks by `pattern` (cycled) and
/// at every settings change, as the tap cuts a buffer at a clip's span.
/// `latency` zeros are fed after the end so the tail comes out.
func drive(
    _ stage: AudioLimiterStage, _ input: [[Float]], pattern: [Int],
    settings: (Int) -> AudioLimiterSettings?, changes: [Int] = []
) -> [[Float]] {
    let length = input.map(\.count).max() ?? 0
    let total = length + AudioLimiterStage.latency
    let buffers = input.map { channel -> UnsafeMutablePointer<Float> in
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: total)
        buffer.initialize(repeating: 0, count: total)
        channel.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress!, count: $0.count) }
        return buffer
    }
    let pointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(
        capacity: max(1, buffers.count))
    defer {
        pointers.deallocate()
        buffers.forEach { $0.deallocate() }
    }
    var position = 0
    var turn = 0
    while position < total {
        var size = min(pattern[turn % pattern.count], total - position)
        turn += 1
        if let next = changes.first(where: { $0 > position && $0 < position + size }) {
            size = next - position
        }
        for c in buffers.indices { pointers[c] = buffers[c] + position }
        stage.process(
            UnsafeMutableBufferPointer(start: pointers, count: buffers.count),
            count: buffers.count, frames: size, settings: settings(position))
        position += size
    }
    return buffers.map { Array(UnsafeBufferPointer(start: $0, count: total)) }
}

/// One fresh stage, one pattern, one settings for the whole run.
func limited(
    _ input: [[Float]], _ settings: AudioLimiterSettings?, pattern: [Int] = [512],
    maxFrames: Int = 4096
) -> [[Float]] {
    let stage = AudioLimiterStage(
        channelCount: input.count, sampleRate: 48_000, maxFrames: maxFrames)
    return drive(stage, input, pattern: pattern, settings: { _ in settings })
}

/// The output with the stage's delay removed: sample n of the input's time.
func aligned(_ output: [Float], length: Int) -> [Float] {
    Array(output[AudioLimiterStage.latency..<(AudioLimiterStage.latency + length)])
}

func settings(_ ceilingDb: Double, volume: Double = 1, release: Double = 0.1)
    -> AudioLimiterSettings
{
    AudioLimiterSettings(ceilingDb: ceilingDb, volume: volume, releaseSeconds: release)
}

func gained(_ x: [Float], _ g: Float) -> [Float] { x.map { $0 * g } }

let crest = readF32("crest.f32")
let rode = readF32("rode.f32")
guard crest.count > 48_000, rode.count > 48_000 else {
    check("L0", "fixtures read", false, "crest \(crest.count), rode \(rode.count)")
    exit(1)
}

// MARK: - L1 latency

do {
    var impulse = [Float](repeating: 0, count: 4_000)
    impulse[0] = 0.5
    let out = limited([impulse], settings(0))[0]
    let at = out.firstIndex { $0 != 0 }
    let rest = out.enumerated().allSatisfy { $0.offset == 158 || $0.element == 0 }
    check("L1", "an impulse under the ceiling comes out 158 samples late, unchanged",
          at == 158 && out[158] == 0.5 && rest,
          "first non-zero at \(at.map(String.init) ?? "none"), value \(at.map { out[$0] } ?? 0)")
    let shift = CompositionBuilder.AudioShift.of(
        segments: [], usesNoiseReduction: true, usesLimiter: true)
    check("L1", "latency = lookahead + taps − 2 = 158; lead 1,975 ticks; with NR 8,375",
          AudioLimiterStage.latency == 158
            && AudioLimiterStage.lookahead + AudioLimiterStage.taps - 2 == 158
            && CompositionBuilder.AudioShift.limiterLead == 1_975 && shift.trackLead == 8_375
            && CompositionBuilder.AudioShift.of(
                segments: [], usesNoiseReduction: false, usesLimiter: false) == .none,
          "lead \(CompositionBuilder.AudioShift.limiterLead), both \(shift.trackLead)")
}

// MARK: - L2 the ceiling: outputs for the script's meters

func emit(_ name: String, _ ceilingDb: Double, _ channels: [[Float]], length: Int) {
    for (index, channel) in channels.enumerated() {
        let file = channels.count == 1 ? "\(name).f32" : "\(name)-\(index).f32"
        let path = writeF32(Array(channel.prefix(length + AudioLimiterStage.latency)), file)
        print("L2DATA \(name)\(channels.count == 1 ? "" : "-\(index)") \(ceilingDb) \(path)")
    }
}

let rodeHot = gained(rode, Float(pow(10, 28.0 / 20)))
for ceiling in [-1.0, -3.0, 0.0] {
    emit("crest\(Int(ceiling))", ceiling, limited([crest], settings(ceiling)), length: crest.count)
    emit("rode\(Int(ceiling))", ceiling, limited([rodeHot], settings(ceiling)), length: rode.count)
}
// Stereo: one gain for both channels.
do {
    let n = min(crest.count, rode.count)
    emit("stereo-1", -1, limited([Array(crest.prefix(n)), Array(rodeHot.prefix(n))], settings(-1)),
         length: n)
}

/// A project of one audio clip of the owner's recording, its `audio` given.
func project(audio: String) -> ReelProject? {
    let json = """
        {"version": \(RC_FORMAT_VERSION),
         "canvas": {"width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1]},
         "media": [{"id": 1, "path": "/fixtures/rode.m4a", "kind": "audio",
                    "duration": 18000000, "has_video": false, "has_audio": true}],
         "tracks": [{"id": 3, "name": "Track 1"}],
         "clips": [{"id": 2, "track": 3, "start": 0, "duration": 6000000,
                    "source": {"kind": "media", "media": 1, "in": 0}, "audio": \(audio)}],
         "next_id": 10}
        """
    do {
        return try ReelProject.from(json: json)
    } catch {
        print("  note the probe project does not open: \(error)")
        return nil
    }
}

// The stage is told the clip's base volume (AU-22), read through the one
// derivation the preview and the export share: material ×8 at volume 4 under
// −1 dBTP, the fader applied after.
do {
    let parameters = project(
        audio: #"{"volume": 4, "limiter": {"ceiling_db": -1, "release": 60000}}"#)
        .map { AudioDSPParameters(snapshot: $0.snapshot) }
    let told = parameters?.dsp(for: 2).limiter
    let material = gained(rode, 8)
    var out = limited([material], told)[0]
    for i in out.indices { out[i] *= 4 }
    emit("told-gain", -1, [out], length: material.count)
    print("  note L2 told ceiling \(told.map { String($0.ceiling) } ?? "nil") (want "
          + "\(pow(10, -1.0 / 20) / 4))")
}

// MARK: - L3 block sizes

do {
    let n = min(crest.count, rode.count)
    let input = [Array(rodeHot.prefix(n)), Array(crest.prefix(n))]
    let changes = Array(stride(from: 12_000, to: n, by: 12_000))
    func at(_ position: Int) -> AudioLimiterSettings? {
        switch (position / 12_000) % 3 {
        case 0: return settings(-1)
        case 1: return nil
        default: return settings(-6, volume: 2, release: 0.02)
        }
    }
    func run(_ pattern: [Int]) -> [[Float]] {
        let stage = AudioLimiterStage(channelCount: 2, sampleRate: 48_000, maxFrames: 4096)
        return drive(stage, input, pattern: pattern, settings: at, changes: changes)
    }
    let reference = run([512])
    var detail: [String] = []
    var same = true
    for pattern in [[4096], [1, 1023, 333, 691, 4096, 7, 2048, 17, 512]] {
        let other = run(pattern)
        let equal = other == reference
        same = same && equal
        detail.append("\(pattern.count == 1 ? "4096" : "irregular") \(equal ? "equal" : "DIFFERS")")
    }
    check("L3", "512, 4096 and irregular blocks byte-identical, settings changing at cuts",
          same, detail.joined(separator: ", "))
}

// MARK: - L4 reset

do {
    let stage = AudioLimiterStage(channelCount: 1, sampleRate: 48_000, maxFrames: 4096)
    _ = drive(stage, [crest], pattern: [512], settings: { _ in settings(-6) })
    stage.reset()
    let after = drive(stage, [rodeHot], pattern: [512], settings: { _ in settings(-1) })
    let fresh = limited([rodeHot], settings(-1))
    check("L4", "after reset() the stage gives a fresh stage's bytes", after == fresh,
          after == fresh ? "" : "first difference at "
            + "\(zip(after[0], fresh[0]).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1)")
}

// MARK: - L5 nil settings

do {
    let noise = gained(crest, 4)
    let out = limited([noise], nil)[0]
    let delayed = [Float](repeating: 0, count: 158) + noise
    check("L5", "nil settings: an exact 158-sample delay of a signal far over full scale",
          out == delayed, "peak in \(noise.map { abs($0) }.max() ?? 0)")
}

// MARK: - L6 release

do {
    var input = [Float](repeating: 0, count: 0)
    input += crest.prefix(9_600)  // 0.2 s over the ceiling
    let quiet = (0..<(3 * 48_000)).map { Float(0.05 * sin(2 * Double.pi * 1000 * Double($0) / 48_000)) }
    input += quiet
    let out = aligned(limited([input], settings(-6, release: 0.1))[0], length: input.count)
    var exactFrom = input.count
    for n in stride(from: input.count - 1, through: 0, by: -1) {
        if out[n] != input[n] { break }
        exactFrom = n
    }
    let afterBurst = Double(exactFrom - 9_600) / 48_000
    let limitedDuring = (100..<9_600).contains { out[$0] != input[$0] }
    check("L6", "the gain releases to exactly 1: the output equals the input from then on",
          exactFrom > 9_600 && afterBurst <= 2.0 && limitedDuring,
          String(format: "exact from %.3f s after the burst (release 100 ms)", afterBurst))
}

// MARK: - L7 the preview against the reader

/// A tap around the product's `AudioTapContext`, capturing what it hands on.
final class CaptureTap {
    let context: AudioTapContext
    let capacity = 48_000 * 8
    let samples: UnsafeMutablePointer<Float>
    var captured = 0
    var starts: [Int64] = Array(repeating: 0, count: 20_000)
    var sizes: [Int] = Array(repeating: 0, count: 20_000)
    var callbacks = 0

    init(track: AudioTrackDSP) {
        context = AudioTapContext(track: track, isolation: nil, meter: nil)
        samples = .allocate(capacity: capacity)
    }
    deinit { samples.deallocate() }
}

func makeTap(_ state: CaptureTap) -> MTAudioProcessingTap? {
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: Unmanaged.passRetained(state).toOpaque(),
        init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
        finalize: { tap in
            Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        },
        prepare: { tap, maxFrames, format in
            let state = Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            state.context.prepare(
                channelCount: Int(format.pointee.mChannelsPerFrame),
                sampleRate: format.pointee.mSampleRate, maxFrames: Int(maxFrames),
                formatFlags: format.pointee.mFormatFlags,
                bitsPerChannel: format.pointee.mBitsPerChannel)
        },
        unprepare: { tap in
            Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue().context.unprepare()
        },
        process: { tap, numberFrames, _, list, framesOut, flagsOut in
            let state = Unmanaged<CaptureTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            var range = CMTimeRange()
            guard MTAudioProcessingTapGetSourceAudio(
                tap, numberFrames, list, flagsOut, &range, framesOut) == noErr
            else {
                framesOut.pointee = 0
                return
            }
            let frames = Int(framesOut.pointee)
            let start = flagsOut.pointee & MTAudioProcessingTapFlags(
                kMTAudioProcessingTapFlag_StartOfStream) != 0
            state.context.process(list, frames: frames, time: range.start, startOfStream: start)
            guard state.callbacks < state.starts.count else { return }
            state.starts[state.callbacks] = range.start.isNumeric
                ? CMTimeConvertScale(range.start, timescale: 48_000, method: .roundTowardZero).value
                : -1
            state.sizes[state.callbacks] = frames
            state.callbacks += 1
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard let data = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                state.captured + frames <= state.capacity
            else { return }
            (state.samples + state.captured).update(from: data, count: frames)
            state.captured += frames
        })
    var tap: MTAudioProcessingTap?
    guard MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
        == noErr
    else { return nil }
    return tap
}

final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }

func loadTrack(_ asset: AVAsset) -> AVAssetTrack? {
    let box = TrackBox()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.track = (try? await asset.loadTracks(withMediaType: .audio))?.first
        done.signal()
    }
    done.wait()
    return box.track
}

func segment(duration: Ticks) -> PlanSegment {
    let json = """
        {"clip": 2, "media": 1, "source_in": 0, "source_duration": \(duration),
         "start": 0, "duration": \(duration)}
        """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(PlanSegment.self, from: Data(json.utf8))
}

do {
    let rodeURL = fixtures.appendingPathComponent("rode.m4a")
    let asset = AVURLAsset(url: rodeURL)
    let parameters = project(
        audio: #"{"volume": 16, "limiter": {"ceiling_db": -1, "release": 60000}}"#)
        .map { AudioDSPParameters(snapshot: $0.snapshot) } ?? .empty
    let span: Ticks = 10 * 600_000
    let track = AudioTrackDSP(segments: [segment(duration: span)], parameters: parameters)
    let composition = AVMutableComposition()
    guard let source = loadTrack(asset),
        let target = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
        check("L7", "the composition builds", false)
        exit(1)
    }
    try? target.insertTimeRange(
        CMTimeRange(start: .zero, duration: CMTime(value: span, timescale: 600_000)),
        of: source, at: .zero)
    func mix(_ state: CaptureTap) -> AVAudioMix {
        let input = AVMutableAudioMixInputParameters(track: target)
        input.audioTapProcessor = makeTap(state)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        return mix
    }
    // The export's path: a reader over the same composition and mix.
    let reading = CaptureTap(track: track)
    if let reader = try? AVAssetReader(asset: composition) {
        let output = AVAssetReaderAudioMixOutput(audioTracks: [target], audioSettings: nil)
        output.audioMix = mix(reading)
        reader.add(output)
        reader.startReading()
        while output.copyNextSampleBuffer() != nil {}
    }
    // The preview's: a muted player.
    let previewing = CaptureTap(track: track)
    let item = AVPlayerItem(asset: composition)
    item.audioMix = mix(previewing)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    player.volume = 0
    player.play()
    RunLoop.main.run(until: Date().addingTimeInterval(5))
    player.pause()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    // The reader's capture by sample position.
    var exported = [Float](repeating: .nan, count: reading.capacity)
    var position = 0
    for k in 0..<reading.callbacks {
        let start = reading.starts[k] >= 0 ? Int(reading.starts[k]) : -1
        let frames = reading.sizes[k]
        if start >= 0, start + frames <= exported.count {
            for i in 0..<frames { exported[start + i] = reading.samples[position + i] }
        }
        position += frames
    }
    var compared = 0
    var differ = 0
    var offset = 0
    let window = 188_416
    for k in 0..<previewing.callbacks {
        let frames = previewing.sizes[k]
        defer { offset += frames }
        guard offset + frames <= previewing.captured else { break }
        let start = Int(previewing.starts[k])
        guard start >= 0, start + frames <= window else { continue }
        for i in 0..<frames where previewing.samples[offset + i] != exported[start + i] {
            differ += 1
        }
        compared += frames
    }
    // Not silence: the limited material comes through at about its pre-fader
    // ceiling (0.891 / 16).
    var loudest: Float = 0
    for i in 0..<min(window, exported.count) where !exported[i].isNaN {
        loudest = max(loudest, abs(exported[i]))
    }
    check("L7", "the muted player's tap output equals the reader's, sample for sample, "
            + "within the first 4 s, and it is sound", compared >= 100_000 && differ == 0
            && loudest > 0.02,
          "compared \(compared), differ \(differ), loudest \(loudest); reader "
            + "\(reading.callbacks) callbacks, player \(previewing.callbacks)")
}

// MARK: - L8 the model against the stage

func decode(_ url: URL) -> [Float]? {
    let asset = AVURLAsset(url: url)
    guard let track = loadTrack(asset), let reader = try? AVAssetReader(asset: asset) else {
        return nil
    }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false])
    reader.add(output)
    guard reader.startReading() else { return nil }
    var samples: [Float] = []
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        _ = chunk.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                       destination: $0.baseAddress!)
        }
        samples += chunk
    }
    return reader.status == .completed ? samples : nil
}

final class ResultBox: @unchecked Sendable { var value = false }

do {
    let rodeURL = fixtures.appendingPathComponent("rode.m4a")
    guard let material = decode(rodeURL) else {
        check("L8", "the owner's recording decodes", false)
        exit(1)
    }
    let duration = Ticks((Double(material.count) / 48_000 * 600_000).rounded(.up))
    let media = MediaSnapshot(id: 1, path: rodeURL.path, kind: .audio, duration: duration,
                              hasVideo: false, hasAudio: true)
    let dir = scratch.appendingPathComponent("loudness", isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let done = DispatchSemaphore(value: 0)
    let box = ResultBox()
    Task.detached {
        box.value = await MediaImporter.loudness(
            for: media, url: rodeURL, stamp: MediaImporter.CacheStamp.stamp(for: media, url: rodeURL),
            into: dir)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 120)
    guard let cache = MediaImporter.loadLoudness(for: 1, in: dir) else {
        check("L8", "the loudness cache builds", false)
        exit(1)
    }
    let whole = Ticks(Double(material.count) / 48_000 * 600_000)
    let read = ClipLoudness.reading(
        cache, segments: [segment(duration: whole)], pivots: [nil], matrix: .identity)
    let reading = AudioNormalize.LoudnessReading(
        clip: 2, media: 1, lufs: read.lufs ?? .nan, truePeak: read.truePeak, steps: read.steps,
        stepPeaks: read.stepPeaks, limiter: nil)
    let plan = AudioNormalize.plan(
        AudioNormalize.LoudnessInput(readings: [reading], problems: []), targetLUFS: -16)
    guard let row = plan.normalized.first, let limiter = row.limiter else {
        check("L8", "Normalize turns the limiter on for the owner's recording", false)
        exit(1)
    }
    let volume = row.volume
    let told = AudioLimiterSettings(
        ceilingDb: limiter.ceilingDb, volume: volume,
        releaseSeconds: Double(limiter.release) / 600_000)
    var out = aligned(limited([material], told)[0], length: material.count)
    for i in out.indices { out[i] *= Float(volume) }
    var stereo = [Float](repeating: 0, count: out.count * 2)
    for i in out.indices {
        stereo[2 * i] = out[i]
        stereo[2 * i + 1] = out[i]
    }
    var stage: Double?
    if let meter = LoudnessMeter(sampleRate: 48_000, channelCount: 2) {
        stereo.withUnsafeBufferPointer { meter.feed($0.baseAddress!, frames: out.count) }
        stage = meter.finish().integratedLUFS
    }
    emit("rode-normalized", limiter.ceilingDb, [out + [Float](repeating: 0, count: 158)],
         length: out.count)
    let gap = (stage ?? .nan) - row.resultLUFS
    check("L8", "the model's loudness against the stage's on the owner's recording ≤ 0.3 LU",
          abs(gap) <= 0.3,
          "model \(f3(row.resultLUFS)), stage \(f3(stage)), gap \(f3(gap)); volume "
            + "\(String(format: "%.4f", volume)), measured \(f3(read.lufs)) LUFS, "
            + "TP \(f3(dB(read.truePeak))) dBTP, limited_by \(row.limit?.rawValue ?? "null")")
}

// MARK: - L9 the default mode

do {
    let stored = UserDefaults.standard.object(forKey: NormalizeChoice.modeKey)
    check("L9", "with no stored choice Normalize's mode is Loudness",
          stored == nil && NormalizeChoice.mode == .loudness,
          "stored \(String(describing: stored)), mode \(NormalizeChoice.mode.rawValue)")
}
