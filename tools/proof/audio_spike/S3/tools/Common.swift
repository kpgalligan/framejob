import AVFoundation
import Foundation
import MediaToolbox
import os

// Spike S3's composition fixture: test media written as 48 kHz LPCM WAV, a composition of
// several audio tracks with volume ramps (the app's shape: one input-parameter block per
// track, ramps held from 0, a tap per track), and a tap that records what it saw.

let workDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func writeWav(_ name: String, channels: [[Float]]) -> URL {
    let url = workDir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: AVAudioChannelCount(channels.count))!
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: channels.count, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try! AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let n = channels[0].count
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
    buf.frameLength = AVAudioFrameCount(n)
    for c in 0..<channels.count {
        channels[c].withUnsafeBufferPointer { src in
            buf.floatChannelData![c].update(from: src.baseAddress!, count: n)
        }
    }
    try! file.write(from: buf)
    return url
}

/// The media: A, stereo tone bursts (440 Hz left, 550 Hz right, 0.5 s on / 0.5 s off) with a
/// one-sample click every whole second; B, mono pink-ish noise; both 20 s.
func makeMedia() -> (a: URL, b: URL, aSamples: [[Float]], bSamples: [Float]) {
    let n = 48000 * 20
    var l = [Float](repeating: 0, count: n), r = l
    for i in 0..<n {
        let t = Double(i) / 48000
        let on = (Int(t * 2) % 2) == 0
        if on {
            l[i] = Float(0.5 * sin(2 * Double.pi * 440 * t))
            r[i] = Float(0.4 * sin(2 * Double.pi * 550 * t))
        }
        if i % 48000 == 0 { l[i] = 0.9; r[i] = 0.9 }
    }
    var b = [Float](repeating: 0, count: n)
    var s: UInt64 = 0x1234_5678
    var b0 = 0.0, b1 = 0.0, b2 = 0.0
    for i in 0..<n {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        let white = Double(Int64(bitPattern: s) >> 11) / Double(1 << 52)
        b0 = 0.99765 * b0 + white * 0.0990460
        b1 = 0.96300 * b1 + white * 0.2965164
        b2 = 0.57000 * b2 + white * 1.0526913
        b[i] = Float((b0 + b1 + b2 + white * 0.1848) * 0.04)
    }
    return (writeWav("a_stereo.wav", channels: [l, r]), writeWav("b_mono.wav", channels: [b]), [l, r], b)
}

/// One volume ramp, as the app sets it (`CompositionBuilder.volumeLegs`): seconds.
struct Leg { let start: Double; let duration: Double; let from: Float; let to: Float }

/// The envelope AVFoundation is handed, evaluated the way `MediaPeaks.envelope` does:
/// inside a leg, linear; between legs, the previous leg's end; before the first, its start.
func envelope(_ legs: [Leg], at t: Double) -> Float {
    guard let first = legs.first else { return 1 }
    if t < first.start { return first.from }
    var last = first.from
    for leg in legs {
        if t < leg.start { return last }
        if t < leg.start + leg.duration {
            let u = Float((t - leg.start) / leg.duration)
            return leg.from + (leg.to - leg.from) * u
        }
        last = leg.to
    }
    return last
}

/// What one tap saw: every callback's thread, composition time, frame count, and the
/// samples it handed on, stored by composition sample index.
final class TapRecord: @unchecked Sendable {
    let name: String
    var lock = os_unfair_lock()
    var calls: [(thread: UInt64, start: Double, frames: Int, host: UInt64, flags: UInt32)] = []
    var channels = 0
    var store: [[Float]]
    let capacity: Int
    init(name: String, seconds: Int) {
        self.name = name
        capacity = 48000 * seconds
        store = [[Float]](repeating: [Float](repeating: 0, count: capacity), count: 2)
    }
}

var tapThreadNames: [UInt64: String] = [:]

func currentThreadID() -> UInt64 {
    var tid: UInt64 = 0
    pthread_threadid_np(nil, &tid)
    return tid
}

/// A tap that fetches its source, records it, and hands it on untouched.
func makeRecordingTap(_ record: TapRecord, postEffects: Bool = false) -> MTAudioProcessingTap {
    let context = Unmanaged.passRetained(record).toOpaque()
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: context,
        init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
        finalize: { tap in Unmanaged<TapRecord>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
        prepare: { tap, _, format in
            let r = Unmanaged<TapRecord>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            r.channels = Int(format.pointee.mChannelsPerFrame)
        },
        unprepare: nil,
        process: { tap, numberFrames, _, bufferList, framesOut, flagsOut in
            let r = Unmanaged<TapRecord>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            var range = CMTimeRange()
            guard MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut, &range, framesOut) == noErr else {
                framesOut.pointee = 0; return
            }
            let frames = Int(framesOut.pointee)
            let start = range.start.isNumeric ? range.start.seconds : -1
            os_unfair_lock_lock(&r.lock)
            r.calls.append((currentThreadID(), start, frames, mach_absolute_time(), flagsOut.pointee))
            if start >= 0 {
                let base = Int((start * 48000).rounded())
                let list = UnsafeMutableAudioBufferListPointer(bufferList)
                for c in 0..<min(list.count, 2) {
                    guard let data = list[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for i in 0..<frames where base + i >= 0 && base + i < r.capacity {
                        r.store[c][base + i] = data[i]
                    }
                }
                if list.count == 1 {  // mono: mirror, so the record always has two channels
                    for i in 0..<frames where base + i >= 0 && base + i < r.capacity { r.store[1][base + i] = r.store[0][base + i] }
                }
            }
            os_unfair_lock_unlock(&r.lock)
        })
    var tap: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks,
        postEffects ? kMTAudioProcessingTapCreationFlag_PostEffects : kMTAudioProcessingTapCreationFlag_PreEffects, &tap)
    precondition(status == noErr && tap != nil, "tap create failed \(status)")
    return tap!
}

func cmTime(_ s: Double) -> CMTime { CMTime(value: CMTimeValue((s * 48000).rounded()), timescale: 48000) }

/// One composition track's recipe: the file, where it sits, its ramps.
struct TrackSpec {
    let url: URL
    let at: Double        // composition start, seconds
    let from: Double      // source start
    let duration: Double
    let legs: [Leg]
}

struct Built {
    let composition: AVMutableComposition
    let mix: AVMutableAudioMix
    let records: [TapRecord]
}

func build(_ specs: [TrackSpec], seconds: Int, taps: Bool = true, postEffects: Bool = false) -> Built {
    let composition = AVMutableComposition()
    var params: [AVAudioMixInputParameters] = []
    var records: [TapRecord] = []
    for (k, spec) in specs.enumerated() {
        let asset = AVURLAsset(url: spec.url)
        let source = asset.tracks(withMediaType: .audio)[0]
        let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID(1001 + k))!
        try! track.insertTimeRange(CMTimeRange(start: cmTime(spec.from), duration: cmTime(spec.duration)), of: source, at: cmTime(spec.at))
        let p = AVMutableAudioMixInputParameters(track: track)
        for leg in spec.legs {
            p.setVolumeRamp(fromStartVolume: leg.from, toEndVolume: leg.to,
                            timeRange: CMTimeRange(start: cmTime(leg.start), duration: cmTime(leg.duration)))
        }
        let record = TapRecord(name: "track \(1001 + k)", seconds: seconds)
        if taps { p.audioTapProcessor = makeRecordingTap(record, postEffects: postEffects) }
        records.append(record)
        params.append(p)
    }
    let mix = AVMutableAudioMix()
    mix.inputParameters = params
    return Built(composition: composition, mix: mix, records: records)
}

let floatStereo: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
    AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false,
]

/// The export's read: the whole composition through AVAssetReaderAudioMixOutput, float
/// stereo, from `start`. Returns the two channels indexed from composition 0.
func readMix(_ built: Built, seconds: Int, start: Double = 0) -> [[Float]] {
    let reader = try! AVAssetReader(asset: built.composition)
    reader.timeRange = CMTimeRange(start: cmTime(start), duration: .positiveInfinity)
    let output = AVAssetReaderAudioMixOutput(audioTracks: built.composition.tracks(withMediaType: .audio), audioSettings: floatStereo)
    output.audioMix = built.mix
    reader.add(output)
    precondition(reader.startReading())
    var out = [[Float]](repeating: [Float](repeating: 0, count: 48000 * seconds), count: 2)
    while let sample = output.copyNextSampleBuffer() {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        let n = CMSampleBufferGetNumSamples(sample)
        let block = CMSampleBufferGetDataBuffer(sample)!
        var data = [Float](repeating: 0, count: n * 2)
        _ = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * 8, destination: $0.baseAddress!) }
        let base = Int((pts * 48000).rounded())
        for i in 0..<n where base + i < out[0].count && base + i >= 0 {
            out[0][base + i] = data[2 * i]; out[1][base + i] = data[2 * i + 1]
        }
    }
    precondition(reader.status == .completed, "reader \(reader.status.rawValue) \(String(describing: reader.error))")
    return out
}
