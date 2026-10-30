import AVFoundation
import Foundation

// E6: stems as one multitrack movie. AVAssetWriter writes several audio inputs; read back by
// AVURLAsset (each track decoded alone and compared with its source), and the enabled flags
// and alternate groups a player obeys. ffprobe is run on the files by the caller.

setvbuf(stdout, nil, _IOLBF, 0)
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let n = 48000 * 10

func stem(_ k: Int) -> [Float] {  // interleaved stereo
    var out = [Float](repeating: 0, count: n * 2)
    var s: UInt64 = 99
    for i in 0..<n {
        let t = Double(i) / 48000
        var v: Float = 0
        switch k {
        case 0: v = Float(0.3 * sin(2 * Double.pi * 440 * t))
        case 1:
            s = s &* 6364136223846793005 &+ 1442695040888963407
            v = Float(Double(Int64(bitPattern: s) >> 11) / Double(1 << 52) * 0.2)
        default: v = (i % 4800 == 0) ? 0.8 : 0
        }
        out[2 * i] = v; out[2 * i + 1] = v * 0.5
    }
    return out
}
let stems = (0..<3).map(stem)
let names = ["Dialogue", "Music", "Effects"]

func sampleBuffer(_ data: [Float], from: Int, frames: Int) -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
        mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
    var fmt: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
    var block: CMBlockBuffer?
    let bytes = frames * 8
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    data.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress! + from * 8, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes) }
    var sb: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmt!, sampleCount: frames, presentationTimeStamp: CMTime(value: CMTimeValue(from), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sb)
    return sb!
}

enum Codec { case aac, lpcm16, lpcm24 }
func settings(_ c: Codec) -> [String: Any] {
    switch c {
    case .aac: return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000]
    case .lpcm16, .lpcm24:
        return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: c == .lpcm16 ? 16 : 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false]
    }
}

/// Writes `tracks` (each interleaved stereo float) as one movie; `enabled[i]` false marks a
/// track disabled; `group` puts the given track indices in one alternate group.
func write(_ name: String, type: AVFileType, codec: Codec, tracks: [[Float]], titles: [String], enabled: [Bool], group: [Int]? = nil) -> URL {
    let url = dir.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let writer = try! AVAssetWriter(outputURL: url, fileType: type)
    var inputs: [AVAssetWriterInput] = []
    for (k, _) in tracks.enumerated() {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings(codec))
        input.expectsMediaDataInRealTime = false
        input.marksOutputTrackAsEnabled = enabled[k]
        let title = AVMutableMetadataItem()
        title.identifier = type == .mov ? .quickTimeUserDataTrackName : .commonIdentifierTitle
        title.value = titles[k] as NSString
        title.dataType = kCMMetadataBaseDataType_UTF8 as String
        input.metadata = [title]
        input.languageCode = "eng"
        precondition(writer.canAdd(input), "cannot add input \(k)")
        writer.add(input)
        inputs.append(input)
    }
    if let group = group {
        let g = AVAssetWriterInputGroup(inputs: group.map { inputs[$0] }, defaultInput: inputs[group[0]])
        precondition(writer.canAdd(g), "cannot add group")
        writer.add(g)
    }
    precondition(writer.startWriting(), "start \(String(describing: writer.error))")
    writer.startSession(atSourceTime: .zero)
    // Interleave: 4800 frames at a time across all inputs.
    var pos = 0
    while pos < n {
        for (k, input) in inputs.enumerated() {
            while !input.isReadyForMoreMediaData { usleep(500) }
            input.append(sampleBuffer(tracks[k], from: pos, frames: min(4800, n - pos)))
        }
        pos += 4800
    }
    inputs.forEach { $0.markAsFinished() }
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    precondition(writer.status == .completed, "\(name): \(String(describing: writer.error))")
    return url
}

func decode(_ track: AVAssetTrack, asset: AVAsset) -> [Float] {
    let reader = try! AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: floatStereo)
    reader.add(out); reader.startReading()
    var data: [Float] = []
    while let sb = out.copyNextSampleBuffer() {
        let k = CMSampleBufferGetNumSamples(sb)
        let block = CMSampleBufferGetDataBuffer(sb)!
        var tmp = [Float](repeating: 0, count: k * 2)
        _ = tmp.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: k * 8, destination: $0.baseAddress!) }
        data += tmp
    }
    return data
}

/// The source that best explains a decoded track, its gain and the residual (dB), after
/// finding the decoded track's alignment against that source (AAC adds priming).
func identify(_ d: [Float]) -> String {
    var best = (k: -1, snr: -999.0, lag: 0)
    for (k, s) in stems.enumerated() {
        for lag in [0, 1024, 2048, 2112, -1024, -2112] {
            var e = 0.0, p = 0.0
            for i in stride(from: 96000, to: min(n, d.count / 2) - 4800, by: 1) {
                let j = i + lag
                guard j >= 0 && j < n else { continue }
                let a = Double(d[2 * i]), b = Double(s[2 * j])
                e += (a - b) * (a - b); p += b * b
            }
            let snr = 10 * log10(p / max(e, 1e-30))
            if snr > best.snr { best = (k, snr, lag) }
        }
    }
    return String(format: "%@ (SNR %.1f dB, lag %d)", names[best.k], best.snr, best.lag)
}

func report(_ url: URL) {
    let asset = AVURLAsset(url: url)
    let tracks = asset.tracks(withMediaType: .audio)
    print("  \(url.lastPathComponent): \(tracks.count) audio tracks, duration \(String(format: "%.3f", asset.duration.seconds)) s")
    for t in tracks {
        let title = t.metadata.first { $0.identifier == .quickTimeUserDataTrackName || $0.commonKey == .commonKeyTitle }?.stringValue ?? "-"
        let d = decode(t, asset: asset)
        print("    track \(t.trackID): enabled \(t.isEnabled), title \(title), lang \(t.languageCode ?? "-"), \(d.count / 2) frames, holds \(identify(d))")
    }
    // What a player plays: taps on each track of an AVPlayer item, muted, 1 s.
    let item = AVPlayerItem(asset: asset)
    var records: [TapRecord] = []
    var params: [AVAudioMixInputParameters] = []
    for t in tracks {
        let p = AVMutableAudioMixInputParameters(track: t)
        let r = TapRecord(name: "\(t.trackID)", seconds: 11)
        p.audioTapProcessor = makeRecordingTap(r)
        params.append(p); records.append(r)
    }
    let mix = AVMutableAudioMix(); mix.inputParameters = params
    item.audioMix = mix
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    var w = 0
    while item.status != .readyToPlay && w < 100 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)); w += 1 }
    player.play()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    player.pause()
    print("    AVPlayer pulls (tap calls per track in 1 s): \(records.map { "\($0.name):\($0.calls.count)" }.joined(separator: " "))")
}

let mixdown = (0..<(n * 2)).map { i in stems[0][i] + stems[1][i] + stems[2][i] }
var urls: [URL] = []
urls.append(write("stems_aac.mov", type: .mov, codec: .aac, tracks: stems, titles: names, enabled: [true, true, true]))
urls.append(write("stems_lpcm24.mov", type: .mov, codec: .lpcm24, tracks: stems, titles: names, enabled: [true, true, true]))
urls.append(write("stems_aac.mp4", type: .mp4, codec: .aac, tracks: stems, titles: names, enabled: [true, true, true]))
urls.append(write("mix_plus_stems_disabled.mov", type: .mov, codec: .aac, tracks: [mixdown] + stems, titles: ["Mix"] + names, enabled: [true, false, false, false]))
urls.append(write("mix_plus_stems_altgroup.mov", type: .mov, codec: .aac, tracks: [mixdown] + stems, titles: ["Mix"] + names, enabled: [true, false, false, false], group: [0, 1, 2, 3]))
for u in urls { report(u) }
