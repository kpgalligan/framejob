import AVFoundation
import Foundation

// E9: one AVAssetReader, several AVAssetReaderAudioMixOutputs — one per timeline track (or
// bus), each over its own composition tracks with its own audio mix (taps and ramps). Do the
// sub-mixes come out in one pass, and do they sum to the full mix? This is what true track or
// bus processing in the EXPORT, and single-pass stems, would read.

setvbuf(stdout, nil, _IOLBF, 0)
let media = makeMedia()
let specs = [
    TrackSpec(url: media.a, at: 0, from: 0, duration: 20, legs: [Leg(start: 0, duration: 20, from: 0.5, to: 0.5)]),
    TrackSpec(url: media.b, at: 2, from: 0, duration: 16, legs: [
        Leg(start: 0, duration: 6, from: 1, to: 1), Leg(start: 6, duration: 4, from: 1, to: 0.25),
        Leg(start: 10, duration: 8, from: 0.25, to: 0.25)]),
    TrackSpec(url: media.a, at: 5, from: 5, duration: 10, legs: [
        Leg(start: 0, duration: 5, from: 0, to: 0), Leg(start: 5, duration: 1, from: 0, to: 0.7),
        Leg(start: 6, duration: 9, from: 0.7, to: 0.7)]),
]
let seconds = 20
let full = readMix(build(specs, seconds: seconds), seconds: seconds)

// "Timeline track X" = composition tracks 1001 and 1003; "timeline track Y" = 1002.
let b = build(specs, seconds: seconds)
let tracks = b.composition.tracks(withMediaType: .audio)
let groups: [[CMPersistentTrackID]] = [[1001, 1003], [1002]]
let reader = try! AVAssetReader(asset: b.composition)
var outputs: [AVAssetReaderAudioMixOutput] = []
for g in groups {
    let out = AVAssetReaderAudioMixOutput(audioTracks: tracks.filter { g.contains($0.trackID) }, audioSettings: floatStereo)
    let mix = AVMutableAudioMix()
    mix.inputParameters = b.mix.inputParameters.filter { g.contains($0.trackID) }
    out.audioMix = mix
    precondition(reader.canAdd(out))
    reader.add(out)
    outputs.append(out)
}
precondition(reader.startReading())
var subs = [[[Float]]](repeating: [[Float]](repeating: [Float](repeating: 0, count: 48000 * seconds), count: 2), count: groups.count)
var done = [Bool](repeating: false, count: groups.count)
var buffers = [Int](repeating: 0, count: groups.count)
let t0 = Date()
while done.contains(false) {
    for (k, out) in outputs.enumerated() where !done[k] {
        guard let sb = out.copyNextSampleBuffer() else { done[k] = true; continue }
        buffers[k] += 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sb).seconds
        let n = CMSampleBufferGetNumSamples(sb)
        let block = CMSampleBufferGetDataBuffer(sb)!
        var data = [Float](repeating: 0, count: n * 2)
        _ = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * 8, destination: $0.baseAddress!) }
        let base = Int((pts * 48000).rounded())
        for i in 0..<n where base + i < 48000 * seconds { subs[k][0][base + i] = data[2 * i]; subs[k][1][base + i] = data[2 * i + 1] }
    }
}
print("reader status \(reader.status.rawValue) (2 = completed), \(String(format: "%.2f", Date().timeIntervalSince(t0))) s, buffers per output \(buffers)")
var e = 0.0, s = 0.0, worst: Float = 0
for c in 0..<2 { for i in 0..<(48000 * seconds) {
    let d = subs[0][c][i] + subs[1][c][i] - full[c][i]
    e += Double(d * d); s += Double(full[c][i] * full[c][i]); worst = max(worst, abs(d))
} }
print(String(format: "sub-mix X + sub-mix Y vs the full mix: error/signal %.1f dB, worst sample %.2e", 10 * log10(max(e, 1e-30) / s), worst))
// Each sub-mix against the taps' own record of its tracks times their envelopes.
for (k, g) in groups.enumerated() {
    var e2 = 0.0, s2 = 0.0
    for i in (48000 * 1)..<(48000 * 19) {
        var want: Float = 0
        for (j, spec) in specs.enumerated() where g.contains(CMPersistentTrackID(1001 + j)) {
            let lo = Int(spec.at * 48000), hi = Int((spec.at + spec.duration) * 48000)
            if i >= lo && i < hi { want += envelope(spec.legs, at: Double(i) / 48000) * b.records[j].store[0][i] }
        }
        let d = Double(subs[k][0][i] - want)
        e2 += d * d; s2 += Double(want * want)
    }
    print(String(format: "sub-mix %d (tracks %@) vs its tracks' taps x envelopes: error/signal %.1f dB", k, g.map(String.init).joined(separator: "+"), 10 * log10(max(e2, 1e-30) / s2)))
}
