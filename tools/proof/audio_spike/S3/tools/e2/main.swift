import Foundation

// E2: a track's dynamics run per composition track against the same chain run on the
// track's sum. REF = chain(Σ cᵢ·G·xᵢ); PER = Σ chain(cᵢ·G·xᵢ) (the tap applying the envelope
// before the chain); PRE = Σ cᵢ·chain(G·xᵢ) (the chain where today's PreEffects tap is, told
// the clip's static gain G as AP2 plans, with fades and the crossfade after it).

let args = CommandLine.arguments
let rodePath = args.count > 1 ? args[1] : ""
let sr = 48000

func seconds(_ s: Double) -> Int { Int(s * Double(sr)) }

/// A clip of `source` placed at [start, end) on a timeline of `total` samples, with its
/// crossfade gains: fading in over [fadeInStart, fadeInEnd) and out over [fadeOutStart,
/// fadeOutEnd) on the constant-power law (`audio_crossfade.rs`: sin in, cos out, linear p).
struct Placed {
    var signal: [Float]   // the clip's samples on the timeline (0 outside it)
    var gain: [Float]     // its crossfade term
}
func place(_ source: [Float], from: Int, at start: Int, end: Int, total: Int,
           fadeIn: (Int, Int)?, fadeOut: (Int, Int)?) -> Placed {
    var s = [Float](repeating: 0, count: total)
    var g = [Float](repeating: 0, count: total)
    for t in start..<min(end, total) {
        let i = from + (t - start)
        if i >= 0 && i < source.count { s[t] = source[i] }
        var gain: Float = 1
        if let f = fadeIn, t < f.1 {
            let p = Double(t - f.0) / Double(f.1 - f.0)
            gain *= Float(sin(max(0, min(1, p)) * Double.pi / 2))
        }
        if let f = fadeOut, t >= f.0 {
            let p = Double(t - f.0) / Double(f.1 - f.0)
            gain *= Float(cos(max(0, min(1, p)) * Double.pi / 2))
        }
        g[t] = gain
    }
    return Placed(signal: s, gain: g)
}

func stereo(_ x: [Float]) -> [[Float]] { [x, x] }

struct Report {
    let name: String
    let ref: [[Float]], per: [[Float]], pre: [[Float]]
    let region: Range<Int>
}

func rmsDB(_ c: [[Float]], _ r: Range<Int>) -> Double {
    var s = 0.0
    for ch in c { for i in r { s += Double(ch[i]) * Double(ch[i]) } }
    let ms = s / Double(r.count * c.count)
    return ms > 0 ? 10 * log10(ms) : -200
}

func compare(_ name: String, _ a: [[Float]], _ ref: [[Float]], region: Range<Int>) -> String {
    // 50 ms RMS level error, windows inside the region where REF is above −50 dBFS.
    let w = seconds(0.05)
    var worst = 0.0
    var settled = 0.0
    var i = region.lowerBound
    while i + w <= region.upperBound {
        let lr = rmsDB(ref, i..<(i + w))
        if lr > -50 {
            let err = abs(rmsDB(a, i..<(i + w)) - lr)
            worst = max(worst, err)
            if err > 0.5 { settled = Double(i + w - region.lowerBound) / Double(sr) }
        }
        i += w
    }
    // Momentary loudness (400 ms, 100 ms hop) over windows that touch the region.
    let ma = loudnessSeries(a[0], a[1], window: 0.4, hop: 0.1)
    let mr = loudnessSeries(ref[0], ref[1], window: 0.4, hop: 0.1)
    var worstM = 0.0
    for k in 0..<min(ma.count, mr.count) {
        let end = seconds(0.4) + k * seconds(0.1)
        let start = end - seconds(0.4)
        if end > region.lowerBound && start < region.upperBound && mr[k] > -60 {
            worstM = max(worstM, abs(ma[k] - mr[k]))
        }
    }
    // Error energy against the reference's, over the region.
    var e = 0.0, s = 0.0
    for c in 0..<2 { for j in region { let d = Double(a[c][j] - ref[c][j]); e += d * d; s += Double(ref[c][j]) * Double(ref[c][j]) } }
    let esr = e > 0 ? 10 * log10(e / s) : -300
    let sliceA = a.map { Array($0[region]) }
    return String(format: "%@ true peak %+.2f dBTP | worst 50 ms level err %.2f dB (>0.5 dB until +%.2f s) | worst momentary err %.2f LU | error/signal %.1f dB",
                  name, truePeakDB(sliceA), worst, settled, worstM, esr)
}

func run(_ name: String, clips: [Placed], gainG: Float, chain: ([[Float]]) -> [[Float]], region: Range<Int>) {
    let total = clips[0].signal.count
    let ones = [Float](repeating: gainG, count: total)
    var sum = [[Float]](repeating: [Float](repeating: 0, count: total), count: 2)
    var per = sum, pre = sum
    for c in clips {
        let x = scale(stereo(c.signal), ones)          // G·x
        let cx = scale(x, c.gain)                      // c·G·x
        sum = add(sum, cx)
        per = add(per, chain(cx))
        pre = add(pre, scale(chain(x), c.gain))
    }
    let ref = chain(sum)
    let refPeak = truePeakDB(ref.map { Array($0[region]) })
    let inPeak = truePeakDB(sum.map { Array($0[region]) })
    print("== \(name)")
    print(String(format: "   input sum true peak %+.2f dBTP; REF (chain on the sum) true peak %+.2f dBTP", inPeak, refPeak))
    print("   " + compare("PER (chain per comp track, envelope first):", per, ref, region: region))
    print("   " + compare("PRE (chain before the envelope, as today):  ", pre, ref, region: region))
}

let limiter: ([[Float]]) -> [[Float]] = { limit($0, ceilingDB: -1) }

/// A linear, time-invariant track stage: a 2nd-order Butterworth high-pass at 80 Hz, then an
/// RBJ peaking EQ of +6 dB at 3 kHz, Q 1 (what AP3 would put on a voice track).
func rbj(_ kind: String, f0: Double, q: Double, gainDB: Double = 0) -> Biquad {
    let w0 = 2 * Double.pi * f0 / sampleRate, alpha = sin(w0) / (2 * q), cw = cos(w0)
    if kind == "hp" {
        let a0 = 1 + alpha
        return Biquad([(1 + cw) / 2 / a0, -(1 + cw) / a0, (1 + cw) / 2 / a0], [1, -2 * cw / a0, (1 - alpha) / a0])
    }
    let A = pow(10, gainDB / 40), a0 = 1 + alpha / A
    return Biquad([(1 + alpha * A) / a0, -2 * cw / a0, (1 - alpha * A) / a0], [1, -2 * cw / a0, (1 - alpha / A) / a0])
}
let eq: ([[Float]]) -> [[Float]] = { channels in
    channels.map { c in
        var hp = rbj("hp", f0: 80, q: 0.7071), pk = rbj("pk", f0: 3000, q: 1, gainDB: 6)
        return c.map { Float(pk.run(hp.run(Double($0)))) }
    }
}
let defaultComp = AudioCompressorSettings(thresholdDB: -18, ratio: 3, attackSeconds: 0.010, releaseSeconds: 0.200, makeupDB: 0)
let heavyComp = AudioCompressorSettings(thresholdDB: -30, ratio: 6, attackSeconds: 0.005, releaseSeconds: 0.100, makeupDB: 0)
let compD: ([[Float]]) -> [[Float]] = { compress($0, settings: defaultComp) }
let compH: ([[Float]]) -> [[Float]] = { compress($0, settings: heavyComp) }

// ---- T1: two tones, a 2 s constant-power crossfade -------------------------------------
do {
    let total = seconds(10)
    let a = (0..<total).map { Float(0.9 * sin(2 * Double.pi * 440 * Double($0) / Double(sr))) }
    let b = (0..<total).map { Float(0.9 * sin(2 * Double.pi * 660 * Double($0) / Double(sr))) }
    let xa = place(a, from: 0, at: 0, end: seconds(6), total: total, fadeIn: nil, fadeOut: (seconds(4), seconds(6)))
    let xb = place(b, from: seconds(4), at: seconds(4), end: total, total: total, fadeIn: (seconds(4), seconds(6)), fadeOut: nil)
    let region = seconds(4)..<seconds(6)
    run("T1 tones, EQ (high-pass 80 Hz + peak +6 dB at 3 kHz): linear", clips: [xa, xb], gainG: 1, chain: eq, region: region)
    run("T1 tones 440/660 Hz at -0.9 dBFS, 2 s crossfade, limiter -1 dBTP", clips: [xa, xb], gainG: 1, chain: limiter, region: region)
    run("T1 tones, compressor default (-18 dB, 3:1, 10/200 ms)", clips: [xa, xb], gainG: 1, chain: compD, region: region)
    run("T1 tones, compressor heavy (-30 dB, 6:1, 5/100 ms)", clips: [xa, xb], gainG: 1, chain: compH, region: region)
}

// ---- T2: the owner's speech, two takes, a 1 s crossfade, clip gain +26 dB --------------
if !rodePath.isEmpty {
    let v = readMono(rodePath)
    let total = seconds(31)
    // Speech in both takes across the overlap: A plays source 0-1.75 s (its loudest word at 1 s),
    // B plays source 13 s on from 0.75 s (speech at 13-14 s), crossfading over 0.75-1.75 s.
    let xa = place(v, from: 0, at: 0, end: seconds(1.75), total: total, fadeIn: nil, fadeOut: (seconds(0.75), seconds(1.75)))
    let xb = place(v, from: seconds(13), at: seconds(0.75), end: seconds(14), total: total, fadeIn: (seconds(0.75), seconds(1.75)), fadeOut: nil)
    let region = seconds(0.75)..<seconds(1.75)
    // +29 dB: the gain that takes this recording to -16 LUFS (AP2's target), peaks then near +10 dBFS.
    let g: Float = Float(pow(10, 29.0 / 20))
    run("T2 speech x2, EQ (linear)", clips: [xa, xb], gainG: g, chain: eq, region: region)
    run("T2 speech x2 (Rode, +29 dB), 1 s crossfade, limiter -1 dBTP", clips: [xa, xb], gainG: g, chain: limiter, region: region)
    run("T2 speech x2, compressor default", clips: [xa, xb], gainG: g, chain: compD, region: region)
    run("T2 speech x2, compressor heavy", clips: [xa, xb], gainG: g, chain: compH, region: region)

    // ---- T3: a hard cut where the track's clips change composition track (pitch or format
    // split): no overlap, the chain's state does not carry across the cut. A: source 0-3 s,
    // B: source 19-30 s from 3 s; speech on both sides of the cut.
    let ca = place(v, from: 0, at: 0, end: seconds(3), total: total, fadeIn: nil, fadeOut: nil)
    let cb = place(v, from: seconds(19), at: seconds(3), end: seconds(14), total: total, fadeIn: nil, fadeOut: nil)
    let after = seconds(3)..<seconds(5)
    run("T3 speech, hard cut at 3 s across two comp tracks, limiter (region 3-5 s)", clips: [ca, cb], gainG: g, chain: limiter, region: after)
    run("T3 speech, hard cut, compressor default (region 3-5 s)", clips: [ca, cb], gainG: g, chain: compD, region: after)
    run("T3 speech, hard cut, compressor heavy (region 3-5 s)", clips: [ca, cb], gainG: g, chain: compH, region: after)

    // ---- T4: a nest playing a voice and a music bed at once (two comp tracks of one
    // timeline track for the whole span): bus processing.
    var bed = [Float](repeating: 0, count: total)
    var rng = SystemRandomNumberGenerator()
    var b0 = 0.0, b1 = 0.0, b2 = 0.0
    for i in 0..<total {  // pink-ish noise (Kellet's economy filter), then a 4 Hz pulse
        let white = Double.random(in: -1...1, using: &rng)
        b0 = 0.99765 * b0 + white * 0.0990460
        b1 = 0.96300 * b1 + white * 0.2965164
        b2 = 0.57000 * b2 + white * 1.0526913
        let pink = (b0 + b1 + b2 + white * 0.1848) * 0.05
        let pulse = 0.6 + 0.4 * sin(2 * Double.pi * 2 * Double(i) / Double(sr))
        bed[i] = Float(pink * pulse * 1.5)
    }
    let vb = place(v, from: 0, at: 0, end: seconds(30), total: total, fadeIn: nil, fadeOut: nil)
    let mb = place(bed, from: 0, at: 0, end: seconds(30), total: total, fadeIn: nil, fadeOut: nil)
    let whole = seconds(1)..<seconds(29)
    print(String(format: "   (T4 bed RMS %.1f dBFS)", rmsDB(stereo(bed), whole)))
    // The voice carries +29 dB; the bed is already at level. G is per clip here, so scale first.
    let vbG = Placed(signal: vb.signal.map { $0 * g }, gain: vb.gain)
    run("T4 nest bus: voice (+29 dB) and bed together 30 s, limiter -1 dBTP", clips: [vbG, mb], gainG: 1, chain: limiter, region: whole)
    run("T4 nest bus, compressor default", clips: [vbG, mb], gainG: 1, chain: compD, region: whole)
    run("T4 nest bus, compressor heavy", clips: [vbG, mb], gainG: 1, chain: compH, region: whole)
}
