import Foundation

// Match Audio's probe (road map "audio" AP12, spec §11 AU-124…AU-127),
// compiled with app/Sources through swift_build. No arguments. Prints one
// "ok"/"FAIL" line per check, each row's name first (P1–P9), for
// audio_ap12_probe.py to score. Nothing renders: the speech spectrum is fed
// synthetic buffers, the fit synthetic curves made by the EQ's own response.

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}
func f3(_ x: Double?) -> String { x.map { String(format: "%.3f", $0) } ?? "nil" }
func list(_ xs: [Double]) -> String { xs.map { String(format: "%.2f", $0) }.joined(separator: " ") }

let bands = SpeechSpectrumMeter.bandIndices.count
let rate = SpeechSpectrumMeter.sampleRate
func band(_ n: Int) -> Int { n - SpeechSpectrumMeter.bandIndices.lowerBound }

/// Interleaved stereo of `frames`, each channel from its own function of the frame.
func stereo(_ frames: Int, _ left: (Int) -> Float, _ right: (Int) -> Float) -> [Float] {
    var out = [Float](repeating: 0, count: 2 * frames)
    for f in 0..<frames {
        out[2 * f] = left(f)
        out[2 * f + 1] = right(f)
    }
    return out
}
func sine(_ hz: Double, _ amplitude: Double) -> (Int) -> Float {
    { Float(amplitude * sin(2 * Double.pi * hz * Double($0) / rate)) }
}
func meter(_ buffer: [Float], speech: [Bool], chunk: Int = 1000) -> SpeechSpectrumMeter {
    let m = SpeechSpectrumMeter(speech: speech)
    let frames = buffer.count / 2
    var at = 0
    buffer.withUnsafeBufferPointer { p in
        while at < frames {
            let take = min(chunk, frames - at)
            m.feed(p.baseAddress! + 2 * at, frames: take)
            at += take
        }
    }
    return m
}

/// Seeded white in [−1, 1] (xorshift), then Paul Kellet's pink filter.
struct Pink {
    var state: UInt64
    var b = [Double](repeating: 0, count: 7)
    mutating func white() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 2_000_001) / 1_000_000 - 1
    }
    mutating func next() -> Float {
        let w = white()
        b[0] = 0.99886 * b[0] + w * 0.0555179
        b[1] = 0.99332 * b[1] + w * 0.0750759
        b[2] = 0.96900 * b[2] + w * 0.1538520
        b[3] = 0.86650 * b[3] + w * 0.3104856
        b[4] = 0.55000 * b[4] + w * 0.5329522
        b[5] = -0.7616 * b[5] - w * 0.0168980
        let out = b[0] + b[1] + b[2] + b[3] + b[4] + b[5] + b[6] + w * 0.5362
        b[6] = w * 0.115926
        return Float(out * 0.11)
    }
}

let allSpeech = [Bool](repeating: true, count: 10_000)

// MARK: - P1 a band level

do {
    let frames = SpeechSpectrumMeter.fftSize + 19 * SpeechSpectrumMeter.hop
    let tone = meter(stereo(frames, sine(1000, 0.5), { _ in 0 }), speech: allSpeech)
    let levels = tone.finish() ?? []
    let expected = 10 * log10(0.5 * 0.5 / 2)
    check("P1", "frame count", tone.counted == 20, "\(tone.counted) frames for \(frames)")
    check("P1", "1 kHz sine at amplitude 0.5 in one channel reads its mean square",
          levels.count == bands && abs(levels[band(0)] - expected) <= 0.05,
          "\(f3(levels.count == bands ? levels[band(0)] : nil)) dB, expected \(f3(expected))")
    check("P1", "the Hann window keeps it out of the neighbouring bands",
          levels.count == bands && levels[band(-1)] < expected - 60
              && levels[band(1)] < expected - 60,
          "800 Hz \(f3(levels.count == bands ? levels[band(-1)] : nil)), 1.26 kHz "
              + "\(f3(levels.count == bands ? levels[band(1)] : nil))")
    let width = rate / Double(SpeechSpectrumMeter.fftSize)
    var edges = true
    var detail = ""
    for (i, n) in SpeechSpectrumMeter.bandIndices.enumerated() {
        let bins = SpeechSpectrumMeter.bandBins[i]
        let low = SpeechSpectrumMeter.centre(n) * pow(2, -1.0 / 6)
        let high = SpeechSpectrumMeter.centre(n) * pow(2, 1.0 / 6)
        let good = Double(bins.lowerBound) * width >= low
            && Double(bins.lowerBound - 1) * width < low
            && Double(bins.upperBound - 1) * width < high
            && Double(bins.upperBound) * width >= high
            && (i + 1 == bands || SpeechSpectrumMeter.bandBins[i + 1].lowerBound == bins.upperBound)
        if !good {
            edges = false
            detail = "band \(n): bins \(bins)"
        }
    }
    check("P1", "bin edges [c·2^(−1/6), c·2^(1/6)), contiguous", edges, detail)
    var pink = Pink(state: 0x9E37_79B9_7F4A_7C15)
    var other = Pink(state: 0xD1B5_4A32_D192_ED03)
    let noise = stereo(20 * Int(rate), { _ in pink.next() }, { _ in other.next() })
    let pinkLevels = meter(noise, speech: allSpeech).finish() ?? []
    let mid = Array(pinkLevels.dropFirst(1).dropLast(1))
    let mean = mid.isEmpty ? 0 : mid.reduce(0, +) / Double(mid.count)
    let spread = mid.map { abs($0 - mean) }.max() ?? .infinity
    check("P1", "pink noise reads flat 100 Hz–10 kHz within ±1.5 dB",
          pinkLevels.count == bands && spread <= 1.5,
          "largest departure \(f3(spread)) dB: \(list(mid.map { $0 - mean }))")
}

// MARK: - P2 speech gating

do {
    // 3 s of 1 kHz (speech), 0.5 s of silence, 3 s of 4 kHz (pause).
    let a = 144_000
    let gap = 24_000
    let frames = a + gap + 144_000
    let buffer = stereo(
        frames, { f in f < a ? sine(1000, 0.5)(f) : f < a + gap ? 0 : sine(4000, 0.5)(f) },
        { f in f < a ? sine(1000, 0.5)(f) : f < a + gap ? 0 : sine(4000, 0.5)(f) })
    let mask = (0..<(frames / 480 + 1)).map { $0 < 300 }
    let gated = meter(buffer, speech: mask)
    let levels = gated.finish() ?? []
    check("P2", "only frames whose centre step is speech count", gated.counted == 35,
          "\(gated.counted) frames, expected 35")
    check("P2", "the pause's 4 kHz tone is not in the spectrum",
          levels.count == bands && levels[band(6)] < levels[band(0)] - 60,
          "1 kHz \(f3(levels.count == bands ? levels[band(0)] : nil)), 4 kHz "
              + "\(f3(levels.count == bands ? levels[band(6)] : nil))")
    let tone = stereo(80_000, sine(1000, 0.5), sine(1000, 0.5))
    let eleven = meter(tone, speech: (0..<200).map { $0 < 94 })
    let twelve = meter(tone, speech: (0..<200).map { $0 < 103 })
    check("P2", "under 12 frames of speech is nil", eleven.finish() == nil
              && twelve.finish() != nil,
          "\(eleven.counted) frames nil: \(eleven.finish() == nil); \(twelve.counted) frames "
              + "nil: \(twelve.finish() == nil)")
}

// MARK: - P3 weights and the level removed

/// The probe's own arithmetic for AU-125's curve.
func expectedCurve(_ reference: [Double], _ target: [Double]) -> ([Double], [Double]) {
    let rTop = reference.max()!, tTop = target.max()!
    var w: [Double] = []
    var d: [Double] = []
    for b in 0..<reference.count {
        let inside = reference[b] >= rTop - 50 && target[b] >= tTop - 50
        w.append(inside ? 1 : 0)
        d.append(reference[b] - target[b])
    }
    var sum = 0.0
    var n = 0.0
    for b in d.indices where w[b] > 0 {
        sum += d[b]
        n += 1
    }
    let m = sum / n
    var c: [Double] = []
    for b in d.indices { c.append(w[b] > 0 ? d[b] - m : 0) }
    let k = c.count
    var s: [Double] = []
    for b in 0..<k {
        if b == 0 {
            s.append((2 * c[0] + c[1]) / 3)
        } else if b == k - 1 {
            s.append((2 * c[b] + c[b - 1]) / 3)
        } else {
            s.append((c[b - 1] + 2 * c[b] + c[b + 1]) / 4)
        }
    }
    return (s, w)
}

do {
    var reference = [Double](repeating: 0, count: bands)
    reference[0] = -60
    var target = [Double](repeating: -10, count: bands)
    target[5] = -4
    target[bands - 1] = -70
    let got = AudioMatchFit.target(reference: reference, target: target)
    let (curve, weights) = expectedCurve(reference, target)
    check("P3", "weights: 1 where both are within 50 dB of their loudest",
          got?.weights == weights,
          "got \(got.map { list($0.weights) } ?? "nil")")
    let error = got.map { g in zip(g.curve, curve).map { abs($0 - $1) }.max() ?? 0 } ?? .infinity
    check("P3", "the weighted mean of D removed before the smoothing", error < 1e-9,
          "largest difference \(error); got \(got.map { list($0.curve) } ?? "nil")")
    var narrow = [Double](repeating: -80, count: bands)
    for b in 0..<11 { narrow[b] = 0 }
    check("P3", "under 12 weighted bands is nil",
          AudioMatchFit.target(reference: narrow, target: [Double](repeating: 0, count: bands))
              == nil && AudioMatchFit.contentBands(narrow) == 11)
}

// MARK: - P4 the smoothing

do {
    let zero = [Double](repeating: 0, count: bands)
    var inside = zero
    inside[10] = -8
    let m = 8.0 / Double(bands)
    let curve = AudioMatchFit.target(reference: zero, target: inside)?.curve ?? []
    let want: [Double] = [-m, 2 - m, 4 - m, 2 - m, -m]
    let got = curve.count == bands ? Array(curve[8...12]) : []
    check("P4", "[1, 2, 1]/4 inside",
          got.count == 5 && zip(got, want).allSatisfy { abs($0 - $1) < 1e-9 },
          "bands 8–12: \(list(got)), expected \(list(want))")
    var end = zero
    end[0] = -8
    let edge = AudioMatchFit.target(reference: zero, target: end)?.curve ?? []
    let wantEdge = [(16 - 3 * m) / 3, 2 - m]
    check("P4", "(2, 1)/3 at the ends",
          edge.count == bands && abs(edge[0] - wantEdge[0]) < 1e-9
              && abs(edge[1] - wantEdge[1]) < 1e-9,
          "bands 0–1: \(list(Array(edge.prefix(2)))), expected \(list(wantEdge))")
}

// MARK: - P5, P6, P7 the fit

let ones = [Double](repeating: 1, count: bands)
func describe(_ eq: EqProps) -> String {
    func s(_ x: EqShelfProps?) -> String { x.map { "\(Int($0.frequency)) \($0.gainDb)" } ?? "-" }
    func b(_ x: EqBandProps?) -> String {
        x.map { "\(Int($0.frequency)) \($0.gainDb) q\($0.q)" } ?? "-"
    }
    return "ls[\(s(eq.lowShelf))] b1[\(b(eq.band1))] b2[\(b(eq.band2))] b3[\(b(eq.band3))] "
        + "hs[\(s(eq.highShelf))]"
}

do {
    let c = SpeechSpectrumMeter.centre
    let known = EqProps(
        lowShelf: EqShelfProps(frequency: c(-9), gainDb: 3),
        band1: EqBandProps(frequency: c(-6), gainDb: -4, q: 2),
        band2: EqBandProps(frequency: c(0), gainDb: 3, q: 0.8),
        band3: EqBandProps(frequency: c(6), gainDb: -2.5, q: 1.4),
        highShelf: EqShelfProps(frequency: c(8), gainDb: -3))
    let fit = AudioMatchFit.fit(curve: AudioMatchFit.model(known), weights: ones)
    check("P5", "a known five-slot EQ on the grid recovered to rms ≤ 0.1 dB", fit.rmsDB <= 0.1,
          "rms \(f3(fit.rmsDB)): \(describe(fit.slots))")
}

do {
    let off = EqProps(
        lowShelf: EqShelfProps(frequency: 250, gainDb: 4),
        band2: EqBandProps(frequency: 2500, gainDb: 3, q: 1),
        highShelf: EqShelfProps(frequency: 4000, gainDb: -5))
    let fit = AudioMatchFit.fit(curve: AudioMatchFit.model(off), weights: ones)
    check("P6", "an off-grid curve fitted to rms ≤ 0.5 dB", fit.rmsDB <= 0.5,
          "rms \(f3(fit.rmsDB)): \(describe(fit.slots))")
}

do {
    let steep = EqProps(
        lowShelf: EqShelfProps(frequency: 200, gainDb: 20),
        highShelf: EqShelfProps(frequency: 3000, gainDb: -20))
    let fit = AudioMatchFit.fit(curve: AudioMatchFit.model(steep), weights: ones)
    let s = fit.slots
    let gains = [s.lowShelf?.gainDb, s.band1?.gainDb, s.band2?.gainDb, s.band3?.gainDb,
                 s.highShelf?.gainDb].compactMap { $0 }
    check("P7", "a ±20 dB curve held at ±12 dB",
          !gains.isEmpty && gains.allSatisfy { abs($0) <= 12 } && gains.contains { abs($0) == 12 },
          describe(s))
    let freqs = [s.lowShelf?.frequency, s.band1?.frequency, s.band2?.frequency,
                 s.band3?.frequency, s.highShelf?.frequency].compactMap { $0 }
    let qs = [s.band1?.q, s.band2?.q, s.band3?.q].compactMap { $0 }
    func on(_ x: Double, _ step: Double) -> Bool { abs((x / step).rounded() * step - x) < 1e-9 }
    check("P7", "rounded: f to 1 Hz, gain to 0.1 dB, Q to 0.01",
          freqs.allSatisfy { on($0, 1) } && gains.allSatisfy { on($0, 0.1) }
              && qs.allSatisfy { on($0, 0.01) } && s.highPass == nil && s.lowPass == nil
              && !s.bypass)
    let flat = AudioMatchFit.fit(curve: [Double](repeating: 0, count: bands), weights: ones)
    let tiny = AudioMatchFit.fit(
        curve: AudioMatchFit.model(EqProps(band1: EqBandProps(frequency: 1000, gainDb: 0.04))),
        weights: ones)
    check("P7", "a flat or 0.04 dB curve sets no slot",
          flat.slots == EqProps() && flat.rmsDB < 1e-9 && tiny.slots == EqProps(),
          "flat \(describe(flat.slots)) rms \(flat.rmsDB); tiny \(describe(tiny.slots))")
}

// MARK: - P8 the write and the trials

do {
    let current = EqProps(
        highPass: EqPassProps(frequency: 80, slope: 24),
        lowShelf: EqShelfProps(frequency: 120, gainDb: 6),
        band2: EqBandProps(frequency: 3000, gainDb: 4, q: 2),
        lowPass: EqPassProps(frequency: 10_000), bypass: true)
    let fit = AudioMatchFit.Fit(
        slots: EqProps(
            lowShelf: EqShelfProps(frequency: 200, gainDb: 2),
            band1: EqBandProps(frequency: 1000, gainDb: -3, q: 1)),
        rmsDB: 0.2)
    let applied = AudioMatchFit.applied(fit, to: current)
    check("P8", "applied: tonal slots replaced, passes kept, bypass off",
          applied == EqProps(
              highPass: current.highPass, lowShelf: fit.slots.lowShelf, band1: fit.slots.band1,
              lowPass: current.lowPass, bypass: false),
          describe(applied))
    let trial = AudioMatchFit.trialEQ(current)
    check("P8", "trialEQ: tonal slots off, passes kept, bypass off",
          trial == EqProps(highPass: current.highPass, lowPass: current.lowPass, bypass: false),
          describe(trial))
    check("P8", "no EQ: applied is the fit's slots, trialEQ empty",
          AudioMatchFit.applied(fit, to: nil) == fit.slots && AudioMatchFit.trialEQ(nil) == EqProps())

    // The plan writes eq, volume and the limiter only: hum and the rest untouched.
    let reading = ClipLoudness.Reading(
        lufs: -20, truePeak: 0.1, playedTicks: 600_000, steps: [], stepPeaks: [],
        stepSources: [], stepHighs: [])
    let audio = AudioProps(eq: current, hum: HumProps())
    let target = AudioMatch.Target(
        clip: 2, media: 1,
        loudness: AudioNormalize.LoudnessReading(clip: 2, media: 1, lufs: -30, truePeak: 0.05),
        speech: nil, current: audio)
    let reference = AudioMatch.Reference(clip: 1, media: 1, loudness: reading, speech: nil)
    func planned(loudness: Bool, eq: Bool) -> AudioMatch.Plan {
        let input = AudioMatch.Input(
            reference: reference, targets: [target], problems: [], loudness: loudness, eq: eq)
        let outcome = AudioMatchRun.Outcome(
            referenceLUFS: -20, fits: [2: fit],
            loudness: LoudnessMeasureRun.Outcome(
                input: AudioNormalize.LoudnessInput(readings: [target.loudness], problems: []),
                solved: [:]),
            problems: [], refusal: nil)
        return AudioMatch.plan(input, outcome: outcome)
    }
    func keys(_ plan: AudioMatch.Plan) -> Set<String> {
        Set(plan.matched.first?.set.dictionary.keys.map { $0 } ?? [])
    }
    let both = planned(loudness: true, eq: true)
    let row = both.matched.first
    check("P8", "both: one set_audio of eq and volume, at the reference's loudness",
          both.ops.count == 1 && keys(both) == ["eq", "volume"] && row?.eq == applied
              && abs((row?.loudness?.resultLUFS ?? 0) + 20) < 1e-9 && both.targetLUFS == -20,
          "keys \(keys(both).sorted()), result \(f3(row?.loudness?.resultLUFS))")
    check("P8", "Loudness off writes the EQ only; EQ off the volume only",
          keys(planned(loudness: false, eq: true)) == ["eq"]
              && keys(planned(loudness: true, eq: false)) == ["volume"]
              && planned(loudness: false, eq: true).targetLUFS == nil)

    // The reference renders the press's own project: its volume as it is.
    var project = ReelProject.new(width: 640, height: 360, fps: .thirty)
    project = (try? project?.applying(.addMedia(descriptor: MediaDescriptor(
        path: "/tmp/ap12-probe.wav", kind: .audio, duration: 10 * ReelTime.perSecond,
        hasVideo: false, hasAudio: true))))?.project
    let media = project?.snapshot.media.first?.id ?? 0
    let track = project?.snapshot.tracks.first?.id ?? 0
    project = (try? project?.applying(.addClip(track: track, media: media, at: 0)))?.project
    let clip = project?.snapshot.clips.first?.id ?? 0
    project = (try? project?.applying(.setAudio(clips: [clip], patch: AudioPatch(volume: 0.5))))?
        .project
    let rendered = project.flatMap {
        AudioMatchRun.referenceProject(base: $0, scope: nil, clip: clip)
    }
    check("P8", "the reference renders at its own volume, no trial edit",
          project != nil && rendered?.snapshot.clip(clip)?.audio?.volume == 0.5,
          "volume \(f3(rendered?.snapshot.clip(clip)?.audio?.volume))")
}

// MARK: - P9 a one-sided tilt through `target` then `fit`

do {
    let flat = [Double](repeating: -20, count: bands)
    let shelf = AudioMatchFit.model(EqProps(highShelf: EqShelfProps(frequency: 4000, gainDb: -6)))
    let tilted = zip(flat, shelf).map { $0 + $1 }
    let mean = shelf.reduce(0, +) / Double(bands)
    let made = AudioMatchFit.target(reference: flat, target: tilted)
    let fit = made.map { AudioMatchFit.fit(curve: $0.curve, weights: $0.weights) }
    let s = fit?.slots
    let bells = [s?.band1?.gainDb, s?.band2?.gainDb, s?.band3?.gainDb].compactMap { $0 }
    let good = s.map { s in
        abs((s.highShelf?.frequency ?? 0) - 4000) <= 500
            && abs((s.highShelf?.gainDb ?? 0) - 6) <= 0.3
            && abs(s.lowShelf?.gainDb ?? 0) <= 0.5 && bells.allSatisfy { abs($0) <= 0.5 }
    } ?? false
    check("P9", "a high shelf at 4 kHz −6 dB alone is matched by a +6 dB shelf",
          good && (fit?.rmsDB ?? .infinity) <= 0.1,
          "shelf mean \(f3(mean)) dB; rms \(f3(fit?.rmsDB)): \(s.map(describe) ?? "nil")")
}
