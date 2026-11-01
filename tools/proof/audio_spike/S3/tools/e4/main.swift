import AVFoundation
import Foundation

// E4: can the true mix be rebuilt from the per-track PreEffects taps (each times the plan's
// envelope) accurately enough for BS.1770? Against AVFoundation's own mix
// (AVAssetReaderAudioMixOutput, the export's read). Then: what a PostEffects tap sees, and how
// an AVPlayer calls the taps (threads, timestamps, gaps) — what a real-time sum would need.

let seconds = 20
let media = makeMedia()

let specs = [
    // T1: A at 0-20 s, held at 0.5.
    TrackSpec(url: media.a, at: 0, from: 0, duration: 20, legs: [Leg(start: 0, duration: 20, from: 0.5, to: 0.5)]),
    // T2: B (mono) at 2-18 s: 1.0, a ramp to 0.25 over 6-10 s, and a JUMP to 0.8 at 12 s.
    TrackSpec(url: media.b, at: 2, from: 0, duration: 16, legs: [
        Leg(start: 0, duration: 6, from: 1, to: 1), Leg(start: 6, duration: 4, from: 1, to: 0.25),
        Leg(start: 10, duration: 2, from: 0.25, to: 0.25), Leg(start: 12, duration: 6, from: 0.8, to: 0.8)]),
    // T3: A again at 5-15 s from source 5 s — sample-aligned with T1, so CORRELATED — fading
    // in over 5-6 s to 0.7.
    TrackSpec(url: media.a, at: 5, from: 5, duration: 10, legs: [
        Leg(start: 0, duration: 5, from: 0, to: 0), Leg(start: 5, duration: 1, from: 0, to: 0.7),
        Leg(start: 6, duration: 9, from: 0.7, to: 0.7)]),
]

func rebuild(from records: [TapRecord], monoGain: Float, range: Range<Int>) -> [[Float]] {
    var out = [[Float]](repeating: [Float](repeating: 0, count: 48000 * seconds), count: 2)
    for (k, r) in records.enumerated() {
        let legs = specs[k].legs
        let lo = Int(specs[k].at * 48000), hi = Int((specs[k].at + specs[k].duration) * 48000)
        for i in max(lo, range.lowerBound)..<min(hi, range.upperBound) {
            let g = envelope(legs, at: Double(i) / 48000) * (r.channels == 1 ? monoGain : 1)
            out[0][i] += g * r.store[0][i]
            out[1][i] += g * r.store[1][i]
        }
    }
    return out
}

func errorReport(_ name: String, _ a: [[Float]], _ ref: [[Float]], _ range: Range<Int>) {
    var e = 0.0, s = 0.0, worst: Float = 0, worstAt = 0
    for c in 0..<2 { for i in range {
        let d = a[c][i] - ref[c][i]
        e += Double(d * d); s += Double(ref[c][i] * ref[c][i])
        if abs(d) > worst { worst = abs(d); worstAt = i }
    } }
    let la = loudnessSeries(Array(a[0][range]), Array(a[1][range]), window: 0.4, hop: 0.1)
    let lr = loudnessSeries(Array(ref[0][range]), Array(ref[1][range]), window: 0.4, hop: 0.1)
    let sa = loudnessSeries(Array(a[0][range]), Array(a[1][range]), window: 3, hop: 0.1)
    let sref = loudnessSeries(Array(ref[0][range]), Array(ref[1][range]), window: 3, hop: 0.1)
    var dm = 0.0, ds = 0.0
    for k in 0..<min(la.count, lr.count) where lr[k] > -70 { dm = max(dm, abs(la[k] - lr[k])) }
    for k in 0..<min(sa.count, sref.count) where sref[k] > -70 { ds = max(ds, abs(sa[k] - sref[k])) }
    print(String(format: "  %@: error/signal %.1f dB, worst sample error %.2e at %.4f s; momentary max |dLU| %.4f, short-term max |dLU| %.4f",
                 name, 10 * log10(max(e, 1e-30) / s), worst, Double(worstAt) / 48000, dm, ds))
}

// ---- Part 1: the reader's mix against the taps' rebuild ---------------------------------
print("== Part 1: AVAssetReaderAudioMixOutput mix vs the mix rebuilt from PreEffects taps")
// The mono rule first: a composition holding only T2.
do {
    let mono = build([specs[1]], seconds: seconds)
    let mix = readMix(mono, seconds: seconds)
    let r = mono.records[0]
    var num = 0.0, den = 0.0
    for i in (48000 * 3)..<(48000 * 5) {
        num += Double(mix[0][i] * r.store[0][i]); den += Double(r.store[0][i] * r.store[0][i])
    }
    var lrDiff: Float = 0
    for i in 0..<(48000 * seconds) { lrDiff = max(lrDiff, abs(mix[0][i] - mix[1][i])) }
    print(String(format: "  mono track read as stereo: L = %.6f x tap sample (env 1.0); max |L-R| %.2e; tap channels %d",
                 num / den, lrDiff, r.channels))
}
let b1 = build(specs, seconds: seconds)
let truth = readMix(b1, seconds: seconds)
for r in b1.records {
    let threads = Set(r.calls.map { $0.thread })
    let sizes = Set(r.calls.map { $0.frames })
    print("  \(r.name): \(r.calls.count) calls, channels \(r.channels), threads \(threads.count), frame sizes \(sizes.sorted().prefix(5)), first t \(r.calls.first?.start ?? -9), invalid-time calls \(r.calls.filter { $0.start < 0 }.count)")
}
let allThreads = Set(b1.records.flatMap { $0.calls.map { $0.thread } })
print("  reader: all taps on \(allThreads.count) thread(s)")
let whole = 0..<(48000 * seconds)
let rebuilt = rebuild(from: b1.records, monoGain: 1, range: whole)
errorReport("rebuilt vs reader mix, 0-20 s", rebuilt, truth, whole)
errorReport("  away from the 12 s jump (0-11.9 s)", rebuilt, truth, 0..<(48000 * 119 / 10))
errorReport("  the jump's 100 ms (12.0-12.1 s)", rebuilt, truth, (48000 * 12)..<(48000 * 121 / 10))
// Integrated (ungated mean) loudness both ways.
func meanLUFS(_ x: [[Float]]) -> Double {
    let kl = kWeighted(x[0]), kr = kWeighted(x[1])
    var s = 0.0
    for i in 0..<kl.count { s += kl[i] * kl[i] + kr[i] * kr[i] }
    return -0.691 + 10 * log10(s / Double(kl.count))
}
print(String(format: "  whole-programme (ungated) loudness: reader %.3f LUFS, rebuilt %.3f LUFS", meanLUFS(truth), meanLUFS(rebuilt)))
// Today's meter: per-track peaks x envelope, SUMMED, per 4096 frames, against the mix's peak.
do {
    var worstOver = 0.0, meanOver = 0.0, blocks = 0
    var start = 0
    while start + 4096 <= 48000 * seconds {
        var sumPeak: Float = 0
        for (k, r) in b1.records.enumerated() {
            let lo = Int(specs[k].at * 48000), hi = Int((specs[k].at + specs[k].duration) * 48000)
            guard start >= lo && start < hi else { continue }
            var p: Float = 0
            for i in start..<(start + 4096) { p = max(p, abs(r.store[0][i]), abs(r.store[1][i])) }
            sumPeak += p * envelope(specs[k].legs, at: Double(start) / 48000)
        }
        var mixPeak: Float = 0
        for i in start..<(start + 4096) { mixPeak = max(mixPeak, abs(truth[0][i]), abs(truth[1][i])) }
        if mixPeak > 1e-4 {
            let over = 20 * log10(Double(sumPeak / mixPeak))
            worstOver = max(worstOver, over); meanOver += over; blocks += 1
        }
        start += 4096
    }
    print(String(format: "  today's meter (sum of per-track peaks x env) over the true mix peak: mean %+.2f dB, worst %+.2f dB over %d blocks", meanOver / Double(blocks), worstOver, blocks))
}

// ---- Part 2: what a PostEffects tap sees --------------------------------------------------
print("== Part 2: PostEffects taps")
do {
    let post = build(specs, seconds: seconds, postEffects: true)
    _ = readMix(post, seconds: seconds)
    let r1 = post.records[0]
    // Does track 1's PostEffects tap carry the volume (0.5) and only its own track?
    var num = 0.0, den = 0.0, other = 0.0, otherDen = 0.0
    for i in (48000 * 3)..<(48000 * 4) {  // T1 and T2 both sound here; T3 not yet
        num += Double(r1.store[0][i] * media.aSamples[0][i]); den += Double(media.aSamples[0][i] * media.aSamples[0][i])
        other += Double(r1.store[0][i] * media.bSamples[i - 96000]); otherDen += Double(media.bSamples[i - 96000] * media.bSamples[i - 96000])
    }
    print(String(format: "  track 1001 PostEffects tap: projection on its own source %.4f (volume 0.5 => post-fader if 0.5), on track 1002's source %.4f", num / den, other / otherDen))
    let r2 = post.records[1]
    var g6 = 0.0, g6d = 0.0
    for i in (48000 * 9)..<(48000 * 9 + 4800) { g6 += Double(r2.store[0][i] * media.bSamples[i - 96000]); g6d += Double(media.bSamples[i - 96000] * media.bSamples[i - 96000]) }
    print(String(format: "  track 1002 PostEffects tap at 9.0-9.1 s: gain %.4f (envelope there %.4f)", g6 / g6d, envelope(specs[1].legs, at: 9.05)))
}

// ---- Part 3: an AVPlayer's taps -----------------------------------------------------------
print("== Part 3: AVPlayer, PreEffects recording taps, isMuted = true")
let b3 = build(specs, seconds: seconds)
let item = AVPlayerItem(asset: b3.composition)
item.audioMix = b3.mix
let player = AVPlayer(playerItem: item)
player.isMuted = true
func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
var readyWait = 0
while item.status != .readyToPlay && readyWait < 100 { wait(0.05); readyWait += 1 }
let t0 = mach_absolute_time()
player.play()
wait(4.0)
player.pause()
wait(0.3)
let firstCalls = b3.records.map { $0.calls.count }
var seekDone = false
player.seek(to: cmTime(9.0), toleranceBefore: .zero, toleranceAfter: .zero) { _ in seekDone = true }
while !seekDone { wait(0.01) }
player.play()
wait(3.0)
player.pause()
wait(0.3)
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
func ms(_ h: UInt64) -> Double { Double(h - t0) * Double(tb.numer) / Double(tb.denom) / 1e6 }
for (k, r) in b3.records.enumerated() {
    let threads = Set(r.calls.map { $0.thread })
    let sizes = Set(r.calls.map { $0.frames })
    let valid = r.calls.filter { $0.start >= 0 }
    print("  \(r.name): \(r.calls.count) calls (\(firstCalls[k]) before the seek), threads \(threads.count), frame sizes \(sizes.sorted()), invalid-time calls \(r.calls.count - valid.count), t range \(String(format: "%.3f", valid.first?.start ?? -1))-\(String(format: "%.3f", valid.last?.start ?? -1)) s")
}
let playerThreads = Set(b3.records.flatMap { $0.calls.map { $0.thread } })
print("  player: all taps on \(playerThreads.count) thread(s) in total")
// Cycles: group every call by host time order; is the order T1,T2,T3 with equal start times?
var merged: [(track: Int, start: Double, frames: Int, host: UInt64, thread: UInt64)] = []
for (k, r) in b3.records.enumerated() { for c in r.calls { merged.append((k, c.start, c.frames, c.host, c.thread)) } }
merged.sort { $0.host < $1.host }
var aligned = 0, misaligned = 0
var i = 0
var cycleSamples: [String] = []
while i < merged.count {
    var j = i
    while j + 1 < merged.count && merged[j + 1].track > merged[j].track { j += 1 }
    let group = merged[i...j]
    let starts = Set(group.map { $0.start })
    if starts.count == 1 { aligned += 1 } else { misaligned += 1 }
    if cycleSamples.count < 4 || (starts.count != 1 && cycleSamples.count < 8) {
        cycleSamples.append(group.map { String(format: "T%d@%.4f/%d", $0.track + 1, $0.start, $0.frames) }.joined(separator: " "))
    }
    i = j + 1
}
print("  cycles (calls grouped T1→T2→T3 by host order): \(aligned) with one start time, \(misaligned) with differing starts")
for c in cycleSamples { print("    \(c)") }
// Callbacks ahead of the playhead: the first valid call's lead over wall time from play().
if let first = merged.first(where: { $0.start >= 0 }) {
    print(String(format: "  first valid tap call at +%.1f ms after play(), for t = %.4f s", ms(first.host), first.start))
}
// The rebuilt mix from the PLAYER's taps against the reader's, over what was played.
let played1 = (48000 / 2)..<(48000 * 3)
let played2 = (48000 * 9 + 48000 / 2)..<(48000 * 11)
let rebuiltP = rebuild(from: b3.records, monoGain: 1, range: 0..<(48000 * seconds))
errorReport("player-tap rebuild vs reader mix, 0.5-3.0 s", rebuiltP, truth, played1)
errorReport("player-tap rebuild vs reader mix, 9.5-11.0 s (after the seek; the ramp runs here)", rebuiltP, truth, played2)
