import AVFoundation
import Foundation

// E8: what reading the composed mix costs with real (AAC) sources — the offline premix's render
// time per minute of programme, and the reader's time to first buffer when it starts mid-way
// (option c's seek). N tracks, each the owner's 30.4 s recording repeated to 10 minutes, a
// pass-through tap on each (the metering build's), a volume ramp on each.

setvbuf(stdout, nil, _IOLBF, 0)
let rode = URL(fileURLWithPath: CommandLine.arguments[2])
let minutes = 10.0
let asset = AVURLAsset(url: rode)
let src = asset.tracks(withMediaType: .audio)[0]
let clip = src.timeRange.duration.seconds

func composition(tracks n: Int) -> Built {
    let comp = AVMutableComposition()
    var params: [AVAudioMixInputParameters] = []
    var records: [TapRecord] = []
    for k in 0..<n {
        let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID(1001 + k))!
        var at = Double(k) * 0.37  // staggered so the tracks are not identical
        while at < minutes * 60 {
            let d = min(clip, minutes * 60 - at)
            try! t.insertTimeRange(CMTimeRange(start: .zero, duration: cmTime(d)), of: src, at: cmTime(at))
            at += d
        }
        let p = AVMutableAudioMixInputParameters(track: t)
        p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0.5, timeRange: CMTimeRange(start: .zero, duration: cmTime(minutes * 60)))
        let r = TapRecord(name: "\(k)", seconds: 1)
        p.audioTapProcessor = makeRecordingTap(r)
        params.append(p); records.append(r)
    }
    let mix = AVMutableAudioMix(); mix.inputParameters = params
    return Built(composition: comp, mix: mix, records: records)
}

func read(_ b: Built, from start: Double, seconds: Double?) -> (total: Double, first: Double) {
    let reader = try! AVAssetReader(asset: b.composition)
    reader.timeRange = CMTimeRange(start: cmTime(start), duration: seconds.map(cmTime) ?? .positiveInfinity)
    let out = AVAssetReaderAudioMixOutput(audioTracks: b.composition.tracks(withMediaType: .audio), audioSettings: floatStereo)
    out.audioMix = b.mix
    reader.add(out)
    let t0 = Date()
    reader.startReading()
    var first = -1.0
    while let _ = out.copyNextSampleBuffer() { if first < 0 { first = Date().timeIntervalSince(t0) } }
    return (Date().timeIntervalSince(t0), first)
}

for n in [1, 4, 8] {
    let b = composition(tracks: n)
    let whole = read(b, from: 0, seconds: nil)
    var firsts: [Double] = []
    for start in [61.3, 300.0, 487.9] { firsts.append(read(b, from: start, seconds: 0.2).first * 1000) }
    print(String(format: "%d AAC track(s), %.0f min: whole read %.2f s = %.0fx real time; time to first buffer from 61.3/300/487.9 s: %.1f / %.1f / %.1f ms",
                 n, minutes, whole.total, minutes * 60 / whole.total, firsts[0], firsts[1], firsts[2]))
}
