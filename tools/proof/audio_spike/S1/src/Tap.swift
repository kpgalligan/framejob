import AVFoundation
import CryptoKit
import Foundation
import MediaToolbox

/// One tap's state. Everything the process callback writes is a stored scalar
/// or a preallocated buffer — the harness itself must not allocate there.
final class TapCtx {
    let stage: Stage?
    let armSource: Bool
    /// Pass a callback with no valid time through untouched (no stage runs).
    var skipInvalid = false
    /// Reset the stage when a callback carries StartOfStream, as AudioTap does.
    var resetOnStart = false
    var pendingReset = false
    /// Callback indices whose flags carried StartOfStream / EndOfStream (first 16).
    var sosAt: [Int] = Array(repeating: -1, count: 16)
    var sosCount = 0
    var prepareError: String?
    var prepared = false
    var channels = 0, sampleRate = 0.0, maxFrames = 0
    var formatFlags: UInt32 = 0, bits: UInt32 = 0
    var callbacks = 0, minFrames = Int.max, maxSeen = 0, totalFrames = 0
    var prepareCalls = 0
    var first = RTCounts(), steady = RTCounts(), source = RTCounts()
    var errors = 0
    var lastStatus: Int32 = 0
    var prepareThread: UInt64 = 0, processThread: UInt64 = 0, processThreads = 0
    var stageNanos: UInt64 = 0
    var invalidTimes = 0
    let before = UnsafeMutablePointer<Int>.allocate(capacity: 5)
    let after = UnsafeMutablePointer<Int>.allocate(capacity: 5)
    /// Per-callback frame counts (first 100 000).
    let sizes = UnsafeMutablePointer<Int32>.allocate(capacity: 100_000)
    /// Per-callback start time in samples (for the preview's alignment).
    let starts = UnsafeMutablePointer<Int64>.allocate(capacity: 100_000)
    /// Optional capture of the tap's OUTPUT (planar → interleaved), for the
    /// preview path where nothing else hands it back.
    var capture: UnsafeMutablePointer<Float>?
    var captureCap = 0
    var captured = 0

    init(stage: Stage?, armSource: Bool = false) {
        self.stage = stage
        self.armSource = armSource
    }

    deinit {
        before.deallocate(); after.deallocate(); sizes.deallocate(); starts.deallocate()
        capture?.deallocate()
    }

    func prepare(channels: Int, sampleRate: Double, maxFrames: Int, flags: UInt32, bits: UInt32) {
        prepareCalls += 1
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        prepareThread = tid
        self.channels = channels
        self.sampleRate = sampleRate
        self.maxFrames = maxFrames
        formatFlags = flags
        self.bits = bits
        let float = flags & kAudioFormatFlagIsFloat != 0
        let planar = flags & kAudioFormatFlagIsNonInterleaved != 0
        guard float, planar, bits == 32 else {
            prepareError = "unexpected format flags \(flags) bits \(bits)"
            return
        }
        if let stage {
            prepareError = stage.prepare(channels: channels, sampleRate: sampleRate, maxFrames: maxFrames)
        }
        prepared = prepareError == nil
    }

    func process(_ list: UnsafeMutableAudioBufferListPointer, frames: Int, start: Int64) {
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        if tid != processThread { processThreads += 1; processThread = tid }
        if callbacks < 100_000 {
            sizes[callbacks] = Int32(frames)
            starts[callbacks] = start
        }
        minFrames = min(minFrames, frames)
        maxSeen = max(maxSeen, frames)
        totalFrames += frames
        if pendingReset, let stage { stage.reset(); pendingReset = false }
        if let stage, prepared, frames > 0, !(skipInvalid && start < 0) {
            RTCheck.read(before)
            RTCheck.arm()
            let t0 = mach_absolute_time()
            let st = stage.process(list, frames: frames)
            let t1 = mach_absolute_time()
            RTCheck.disarm()
            RTCheck.read(after)
            stageNanos += (t1 - t0) * UInt64(timebase.numer) / UInt64(timebase.denom)
            if callbacks == 0 { first.add(before: before, after: after) } else {
                steady.add(before: before, after: after)
            }
            if st != 0 { errors += 1; lastStatus = st }
        }
        if let capture, frames > 0 {
            let ch = list.count
            for i in 0..<frames where captured + ch <= captureCap {
                for c in 0..<ch {
                    capture[captured + c] = list[c].mData?.assumingMemoryBound(to: Float.self)[i] ?? 0
                }
                captured += ch
            }
        }
        callbacks += 1
    }

    var sizeSummary: String {
        let n = min(callbacks, 100_000)
        var counts: [Int32: Int] = [:]
        for i in 0..<n { counts[sizes[i], default: 0] += 1 }
        let top = counts.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key)×\($0.value)" }
        return "callbacks \(callbacks), frames min \(minFrames) max \(maxSeen) [\(top.joined(separator: " "))], prepare maxFrames \(maxFrames)"
    }
}

enum TapFactory {
    static func make(_ ctx: TapCtx) -> MTAudioProcessingTap? {
        let info = Unmanaged.passRetained(ctx).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: info,
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<TapCtx>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                let ctx = Unmanaged<TapCtx>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                ctx.prepare(
                    channels: Int(format.pointee.mChannelsPerFrame),
                    sampleRate: format.pointee.mSampleRate, maxFrames: Int(maxFrames),
                    flags: format.pointee.mFormatFlags, bits: format.pointee.mBitsPerChannel)
            },
            unprepare: { _ in },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let ctx = Unmanaged<TapCtx>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue()
                var range = CMTimeRange()
                if ctx.armSource {
                    RTCheck.read(ctx.before); RTCheck.arm()
                }
                let st = MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferListInOut, flagsOut, &range, numberFramesOut)
                if ctx.armSource {
                    RTCheck.disarm(); RTCheck.read(ctx.after)
                    ctx.source.add(before: ctx.before, after: ctx.after)
                }
                guard st == noErr else { numberFramesOut.pointee = 0; return }
                if flagsOut.pointee & MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_StartOfStream) != 0, ctx.sosCount < 16 {
                    ctx.sosAt[ctx.sosCount] = ctx.callbacks
                    ctx.pendingReset = ctx.resetOnStart
                    ctx.sosCount += 1
                }
                var start: Int64 = -1
                if range.start.isNumeric {
                    start = Int64((range.start.seconds * ctx.sampleRate).rounded())
                } else {
                    ctx.invalidTimes += 1
                }
                ctx.process(
                    UnsafeMutableAudioBufferListPointer(bufferListInOut),
                    frames: Int(numberFramesOut.pointee), start: start)
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
            == noErr
        else {
            Unmanaged<TapCtx>.fromOpaque(info).release()
            return nil
        }
        return tap
    }
}

struct Source {
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: CMTime
    let channels: Int

    init(_ path: String) {
        asset = AVURLAsset(url: URL(fileURLWithPath: path))
        track = asset.tracks(withMediaType: .audio)[0]
        duration = asset.duration
        let fd = track.formatDescriptions.first.map { $0 as! CMAudioFormatDescription }
        channels = Int(fd.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 1)
    }

    func composition() -> (AVMutableComposition, AVMutableCompositionTrack) {
        let comp = AVMutableComposition()
        let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try! t.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        return (comp, t)
    }
}

struct ReadResult {
    var samples: [Float]  // interleaved
    var channels: Int
    var ctx: TapCtx?
    var sha: String {
        samples.withUnsafeBytes { SHA256.hash(data: $0) }.map { String(format: "%02x", $0) }
            .joined().prefix(16).description
    }
}

/// Reads `source` through the export's path: an AVMutableComposition, an
/// AVMutableAudioMix whose one input carries the tap, and an
/// AVAssetReaderAudioMixOutput in interleaved 32-bit float at 48 kHz.
func readThroughTap(_ source: Source, stage: Stage?, tap: Bool = true, armSource: Bool = false) -> ReadResult {
    let (comp, track) = source.composition()
    var ctx: TapCtx?
    let mix = AVMutableAudioMix()
    if tap {
        let c = TapCtx(stage: stage, armSource: armSource)
        ctx = c
        let p = AVMutableAudioMixInputParameters(track: track)
        p.audioTapProcessor = TapFactory.make(c)
        mix.inputParameters = [p]
    }
    let reader = try! AVAssetReader(asset: comp)
    let out = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false, AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: source.channels])
    if tap { out.audioMix = mix }
    reader.add(out)
    reader.startReading()
    var samples: [Float] = []
    samples.reserveCapacity(Int(source.duration.seconds * 48000 + 48000) * source.channels)
    while let sb = out.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
        var length = 0
        var ptr: UnsafeMutablePointer<CChar>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
        ptr!.withMemoryRebound(to: Float.self, capacity: length / 4) { f in
            samples.append(contentsOf: UnsafeBufferPointer(start: f, count: length / 4))
        }
    }
    if reader.status == .failed { print("reader failed: \(String(describing: reader.error))") }
    return ReadResult(samples: samples, channels: source.channels, ctx: ctx)
}

func writeF32(_ samples: [Float], _ path: String) {
    samples.withUnsafeBytes { try! Data($0).write(to: URL(fileURLWithPath: path)) }
}

/// Runs a stage offline over interleaved input, cut into blocks by `pattern`
/// (cycled), and returns interleaved output.
func runOffline(_ stage: Stage, input: [Float], channels: Int, pattern: [Int], rate: Double = 48000) -> [Float] {
    let cap = max(4096, pattern.max() ?? 4096)
    if let e = stage.prepare(channels: channels, sampleRate: rate, maxFrames: cap) {
        print("offline prepare \(stage.name): \(e)")
        return []
    }
    let buf = PlanarBuffers(channels: channels, capacity: cap)
    let frames = input.count / channels
    var out = [Float](repeating: 0, count: input.count)
    var pos = 0, k = 0
    while pos < frames {
        let n = min(pattern[k % pattern.count], frames - pos)
        k += 1
        buf.setFrames(n)
        for c in 0..<channels {
            for i in 0..<n { buf.data[c][i] = input[(pos + i) * channels + c] }
        }
        let st = stage.process(buf.abl, frames: n)
        if st != 0 { print("offline \(stage.name) status \(st)"); return [] }
        for c in 0..<channels {
            let d = buf.abl[c].mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<n { out[(pos + i) * channels + c] = d[i] }
        }
        pos += n
    }
    return out
}

func sha(_ x: [Float]) -> String {
    x.withUnsafeBytes { SHA256.hash(data: $0) }.map { String(format: "%02x", $0) }.joined().prefix(16).description
}
