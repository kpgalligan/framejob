// Road map "audio-sync", AS-1 and AS-2 (spec §11 SY-1..SY-10) — Synchronize Audio's
// arithmetic, measured through the app's own `AudioSyncMatch` and
// `AudioSync` with no document, no window and no disk.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, by
// `swift_build.build` (`audio_sync_proof.py` builds and runs it). One process,
// no arguments; the answer is one JSON object on stdout, `{"rows": [...]}`,
// each row `{"id", "pass", "detail", "instrument"}`.
//
// Every array is made here from a seeded LCG, so a run is the same run. No
// expected number is read back from the code under test: each is written as
// the arithmetic the spec states (delta = snap(zeroA − zeroN + lag·6000)).
//
//   P1  delta arithmetic: five placements of a mover whose sound is the
//       anchor's shifted by a known number of buckets, each delta, start and
//       lag against its hand-worked value at 30 fps.
//   P2  the anchor rule (SY-2): pictures first, then earliest start, then
//       rearmost track, then lowest id; a named anchor wins; a named stranger
//       is nil.
//   P3  the FFT correlation equals a brute-force sum on short arrays, and a
//       known lag is recovered from a peaks envelope 9 dB quieter.
//   P4  the thresholds (SY-3) at their boundaries; unrelated arrays are not
//       confident; two equal 300-bucket arrays have no runner-up and plan to
//       "too little room"; a runner-up ≤ 0 is ratio +∞ and confident.
//   P5  drift (SY-7) on smooth arrays stretched by known ratios, within
//       ±5 ppm, including 100 ppm at exactly `driftMinimumOverlapBuckets`;
//       one bucket under it is not measured; a mover that sounds only in its
//       first 3,000 of 15,000 buckets is not measured (the span rule); a
//       6,000-bucket overlap where only the two end windows can match is not
//       measured, naming 2 windows (the count rule, checked first).
//   P6  the refusals (SY-4): before 0, windows that never meet, two clips on
//       one track, a neighbour on the mover's track; a neighbour that only
//       abuts the new window is not refused; a silent anchor is named once,
//       and not against the movers, and a silent mover is named alone.
//   P7  correction (SY-6, SY-10): a +1,000 ppm mover (it lengthens) and a
//       −1,000 ppm one (it shortens): the set_speed rate within 5 ppm of s/k,
//       keep_pitch false, delta the hand-worked snap(zeroA + 6000·c − S + I·k)
//       — the centre-line delta printed as a control at least 2 frames away —
//       and the ops in SY-10's order; a neighbour abutting the old end with
//       delta 0 is refused, the same neighbour 10 frames later is not.
//   P8  SY-8's boundaries (4.99 vs 5.0 ms, a drift just over, exactly at and
//       just under 3× its uncertainty, a new speed
//       0.0019 vs 0.0021 from ×1), a 20 ppm drift left with its note; a
//       reading at speed 1/k with the drifted onsets makes no op, one at
//       ×0.9999 is set to within 5 ppm of 1/k; `rateProblem` at ×2, ×1.002,
//       ×1.0021, ×0.998, ×0.9979.
import Foundation

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1500)),
                 "instrument": instrument])
}

struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func signed() -> Float { Float(next() * 2 - 1) }
}

func randomArray(_ count: Int, seed: UInt64) -> [Float] {
    var lcg = LCG(state: seed)
    return (0..<count).map { _ in lcg.signed() }
}

/// `mover[m] = anchor[m + shift]` where that exists, fresh noise elsewhere:
/// the mover's sound at bucket m is the anchor's at m + shift, so lag = shift.
func shifted(_ anchor: [Float], by shift: Int, count: Int, seed: UInt64) -> [Float] {
    var lcg = LCG(state: seed)
    return (0..<count).map { m in
        let a = m + shift
        return a >= 0 && a < anchor.count ? anchor[a] : lcg.signed()
    }
}

let fps = Fps(num: 30, den: 1)
let bucket: Ticks = 6000

/// A reading whose in point is `(start − zero)·speed`, so that its zero is
/// `start − in/speed` as `AudioSync.read` writes it.
func reading(
    _ clip: UInt32, track: Int, start: Ticks, end: Ticks, zero: Ticks, video: Bool = false,
    onsets: [Float] = [], neighbours: [AudioSync.Neighbour] = [], speed: Double = 1
) -> AudioSync.Reading {
    AudioSync.Reading(
        clip: clip, media: clip + 100, trackIndex: track, start: start, end: end, zero: zero,
        hasVideo: video, onsets: onsets, neighbours: neighbours, speed: speed,
        sourceIn: Ticks((Double(start - zero) * speed).rounded()))
}

/// A smooth signal: Gaussian bumps (σ 2 buckets) at seeded moments.
struct Bumps {
    var at: [Double] = []
    var amp: [Double] = []
    init(seed: UInt64, length: Double) {
        var lcg = LCG(state: seed)
        var t = 0.0
        while t < length {
            t += 4 + lcg.next() * 16
            at.append(t)
            amp.append(0.2 + lcg.next())
        }
    }
    /// Samples `f(m·k + c)` for m in 0..<count.
    func sample(count: Int, k: Double, c: Double) -> [Float] {
        var out = [Double](repeating: 0, count: count)
        for (t, a) in zip(at, amp) {
            let centre = (t - c) / k
            let low = max(0, Int(centre - 12))
            let high = min(count - 1, Int(centre + 12))
            guard low <= high else { continue }
            for m in low...high {
                let d = Double(m) * k + c - t
                out[m] += a * exp(-d * d / 8)
            }
        }
        let mean = out.reduce(0, +) / Double(max(count, 1))
        return out.map { Float($0 - mean) }
    }
}

func describe(_ plan: AudioSync.Plan) -> String {
    switch plan {
    case .refused(let problems):
        return "refused: " + problems.map { $0.description }.joined(separator: " | ")
    case .planned(let anchor, let synced, let ops):
        let parts = synced.map {
            "clip \($0.clip) lag \($0.lag) delta \($0.delta) start \($0.start) "
                + "r \(String(format: "%.3f", $0.correlation))"
        }
        return "planned: anchor \(anchor), \(parts.joined(separator: "; ")), \(ops.count) op(s)"
    }
}

func refusal(_ plan: AudioSync.Plan) -> String? {
    if case .refused(let problems) = plan {
        return problems.map { $0.description }.joined(separator: " ")
    }
    return nil
}

// MARK: - P1 delta arithmetic

do {
    let anchor = randomArray(3000, seed: 11)
    // (zeroA, startA, zeroN, startN, shift k, expected delta) — each worked
    // by hand: zeroA − zeroN + k·6000, rounded to the nearest 20 000.
    let table: [(Ticks, Ticks, Ticks, Ticks, Int, Ticks)] = [
        (600_000, 600_000, 0, 0, 300, 2_400_000),  // 600 000 + 1 800 000, on a frame
        (600_000, 600_000, 0, 0, 301, 2_400_000),  // 2 406 000 = frame 120.3 → 120
        (6_000_000, 6_000_000, 0, 0, -250, 4_500_000),  // 6 000 000 − 1 500 000
        (0, 0, 600_000, 1_200_000, 400, 1_800_000),  // a trimmed mover: −600 000 + 2 400 000
        (0, 0, 0, 0, 33, 200_000),  // 198 000 = frame 9.9 → 10
    ]
    var good = true
    var notes: [String] = []
    for (index, entry) in table.enumerated() {
        let (zeroA, startA, zeroN, startN, shift, expected) = entry
        let mover = shifted(anchor, by: shift, count: 3000, seed: 100 + UInt64(index))
        let input = AudioSync.Input(
            readings: [
                reading(1, track: 0, start: startA, end: startA + 3000 * bucket, zero: zeroA,
                        video: true, onsets: anchor),
                reading(2, track: 1, start: startN, end: startN + 2500 * bucket, zero: zeroN,
                        onsets: mover),
            ], problems: [], anchor: nil, fps: fps)
        let plan = AudioSync.plan(input)
        guard case .planned(let anchorClip, let synced, let ops) = plan, let one = synced.first
        else {
            good = false
            notes.append("case \(index): \(describe(plan))")
            continue
        }
        let lagOK = abs(one.lag - Ticks(shift) * bucket) <= 600
        let ok = anchorClip == 1 && one.clip == 2 && one.delta == expected
            && one.start == startN + expected && lagOK && ops.count == (expected != 0 ? 1 : 0)
        if !ok { good = false }
        notes.append(
            "case \(index): k \(shift) delta \(one.delta) (want \(expected)) start \(one.start) "
                + "lag \(one.lag) (want \(Ticks(shift) * bucket) ±600)")
    }
    row("P1", good, notes.joined(separator: "; "))
}

// MARK: - P2 the anchor rule

do {
    let late = reading(3, track: 0, start: 600_000, end: 6_000_000, zero: 0, video: true)
    let early = reading(5, track: 1, start: 0, end: 6_000_000, zero: 0)
    let lateSound = reading(3, track: 0, start: 600_000, end: 6_000_000, zero: 0)
    let rearTie = reading(5, track: 1, start: 0, end: 6_000_000, zero: 0)
    let frontTie = reading(3, track: 2, start: 0, end: 6_000_000, zero: 0)
    let idHigh = reading(7, track: 1, start: 0, end: 6_000_000, zero: 0)
    let idLow = reading(4, track: 1, start: 0, end: 6_000_000, zero: 0)
    let cases: [(String, UInt32?, UInt32?)] = [
        ("pictures first", AudioSync.chooseAnchor([early, late], named: nil)?.clip, 3),
        ("earliest start", AudioSync.chooseAnchor([lateSound, early], named: nil)?.clip, 5),
        ("rearmost track", AudioSync.chooseAnchor([frontTie, rearTie], named: nil)?.clip, 5),
        ("lowest id", AudioSync.chooseAnchor([idHigh, idLow], named: nil)?.clip, 4),
        ("named", AudioSync.chooseAnchor([early, late], named: 5)?.clip, 5),
        ("named stranger", AudioSync.chooseAnchor([early, late], named: 9)?.clip, nil),
    ]
    let failed = cases.filter { $0.1 != $0.2 }
    row(
        "P2", failed.isEmpty,
        cases.map { "\($0.0): \($0.1.map(String.init) ?? "nil") (want "
            + "\($0.2.map(String.init) ?? "nil"))" }.joined(separator: "; "))
}

// MARK: - P3 correlation against brute force, and a known lag

do {
    let x = randomArray(400, seed: 21)
    let y = randomArray(250, seed: 22)
    let fast = AudioSyncMatch.crossCorrelation(x, y)
    var worst = 0.0
    var scale = 0.0
    for index in 0..<(x.count + y.count - 1) {
        let lag = index - (y.count - 1)
        var sum = 0.0
        for m in 0..<y.count where m + lag >= 0 && m + lag < x.count {
            sum += Double(x[m + lag]) * Double(y[m])
        }
        worst = max(worst, abs(sum - fast[index]))
        scale = max(scale, abs(sum))
    }
    let bruteOK = fast.count == 649 && worst <= 1e-4 * max(scale, 1)

    // A peaks envelope: a floor, and bursts that rise at seeded moments; the
    // mover is the same envelope 313 buckets later and 9 dB down.
    var lcg = LCG(state: 31)
    var peaks = [Float](repeating: 0.002, count: 6000)
    var index = 0
    while index < peaks.count {
        index += 5 + Int(lcg.next() * 60)
        let length = 3 + Int(lcg.next() * 25)
        let level = Float(0.05 + lcg.next() * 0.9)
        for k in index..<min(index + length, peaks.count) {
            peaks[k] = level * Float(1 - 0.5 * Double(k - index) / Double(length))
        }
        index += length
    }
    let quieter = (0..<5800).map { m -> Float in
        let a = m - 313
        return a >= 0 ? peaks[a] * 0.3548 : 0.002 * 0.3548
    }
    let match = AudioSyncMatch.match(
        anchor: AudioSyncMatch.onsets(peaks), mover: AudioSyncMatch.onsets(quieter))
    // The mover's sound at m is the anchor's at m − 313: lag −313.
    let lagOK = match.map { abs($0.lag - -313) <= 0.5 && $0.correlation >= 0.9 && $0.isConfident }
        ?? false
    row(
        "P3", bruteOK && lagOK,
        "FFT vs brute force over 649 lags: worst |Δ| \(String(format: "%.2e", worst)) of scale "
            + "\(String(format: "%.1f", scale)) (≤ 1e-4 of it); peaks lag "
            + "\(match.map { String(format: "%.3f", $0.lag) } ?? "nil") (want −313 ±0.5), r "
            + "\(match.map { String(format: "%.3f", $0.correlation) } ?? "nil"), confident "
            + "\(match?.isConfident ?? false)")
}

// MARK: - P4 thresholds

do {
    typealias M = AudioSyncMatch.Match
    let boundary: [(String, M, Bool)] = [
        ("r 0.25, runner-up 0.125", M(lag: 0, correlation: 0.25, runnerUp: 0.125), true),
        ("r 0.2499, runner-up 0.125", M(lag: 0, correlation: 0.2499, runnerUp: 0.125), false),
        ("ratio exactly 1.5", M(lag: 0, correlation: 0.375, runnerUp: 0.25), true),
        ("ratio under 1.5", M(lag: 0, correlation: 0.375, runnerUp: 0.2501), false),
        ("runner-up −0.1", M(lag: 0, correlation: 0.9, runnerUp: -0.1), true),
        ("no runner-up", M(lag: 0, correlation: 0.9, runnerUp: nil), false),
    ]
    var good = true
    var notes: [String] = []
    for (name, match, want) in boundary {
        if match.isConfident != want { good = false }
        notes.append("\(name): ratio \(match.ratio) confident \(match.isConfident) (want \(want))")
    }
    let infinite = M(lag: 0, correlation: 0.9, runnerUp: -0.1).ratio == .infinity
    if !infinite { good = false }

    let unrelated = AudioSyncMatch.match(
        anchor: randomArray(3000, seed: 41), mover: randomArray(3000, seed: 42))
    let unrelatedOK = unrelated.map { !$0.isConfident } ?? false
    if !unrelatedOK { good = false }
    notes.append(
        "unrelated: r \(unrelated.map { String(format: "%.3f", $0.correlation) } ?? "nil") ratio "
            + "\(unrelated.map { String(format: "%.2f", $0.ratio) } ?? "nil") confident "
            + "\(unrelated?.isConfident ?? true)")

    let equal = randomArray(300, seed: 43)
    let same = AudioSyncMatch.match(anchor: equal, mover: equal)
    let sameOK = same.map { $0.runnerUp == nil && !$0.isConfident } ?? false
    let plan = AudioSync.plan(
        AudioSync.Input(
            readings: [
                reading(1, track: 0, start: 0, end: 300 * bucket, zero: 0, video: true,
                        onsets: equal),
                reading(2, track: 1, start: 0, end: 300 * bucket, zero: 0, onsets: equal),
            ], problems: [], anchor: nil, fps: fps))
    let roomOK = refusal(plan)?.contains("clip 2: too little room to compare its sound with "
        + "clip 1's") ?? false
    if !sameOK || !roomOK { good = false }
    notes.append(
        "equal 300: runner-up \(same.map { $0.runnerUp.map { String($0) } ?? "nil" } ?? "no match") "
            + "confident \(same?.isConfident ?? true); \(describe(plan))")
    row("P4", good, notes.joined(separator: "; "))
}

// MARK: - P5 drift

do {
    let signal = Bumps(seed: 51, length: 16_500)
    let anchor = signal.sample(count: 16_000, k: 1, c: 0)
    let minimum = AudioSyncMatch.driftMinimumOverlapBuckets
    // (name, ppm asked, offset c, overlap): the mover's bucket m is the
    // anchor's m·k + c, so lag = a − (a − c)/k and the drift is (1 − 1/k)·1e6.
    let cases: [(String, Double, Double, Range<Int>)] = [
        ("+200 ppm over 15 000", 200, 50, 50..<15_000),
        ("−150 ppm over 15 000", -150, 50, 50..<15_000),
        ("0 ppm over 15 000", 0, 50, 50..<15_000),
        ("+100 ppm at exactly the minimum", 100, 1000, 1000..<(1000 + minimum)),
    ]
    var good = true
    var notes: [String] = []
    for (name, asked, c, overlap) in cases {
        let k = 1 + asked * 1e-6
        let mover = signal.sample(count: 16_000, k: k, c: c)
        let want = (1 - 1 / k) * 1e6
        let answer = AudioSyncMatch.drift(anchor: anchor, mover: mover, lag: c, overlap: overlap)
        guard case .measured(let drift) = answer else {
            good = false
            notes.append("\(name): \(answer)")
            continue
        }
        let wantMs = want * 1e-6 * Double(overlap.count) * 10
        let ok = abs(drift.ppm - want) <= 5 && abs(drift.milliseconds - wantMs) <= 5e-6
            * Double(overlap.count) * 10
        if !ok { good = false }
        notes.append(
            "\(name): \(String(format: "%.2f", drift.ppm)) ppm (want "
                + "\(String(format: "%.2f", want)) ±5), \(String(format: "%.3f", drift.milliseconds)) "
                + "ms (want \(String(format: "%.3f", wantMs))), ±"
                + "\(String(format: "%.3f", drift.errorMilliseconds)) ms over \(drift.windows) windows")
    }
    let short = AudioSyncMatch.drift(
        anchor: anchor, mover: signal.sample(count: 16_000, k: 1.0001, c: 1000), lag: 1000,
        overlap: 1000..<(1000 + minimum - 1))
    if case .measured = short { good = false }
    notes.append("one bucket under the minimum: \(short)")

    // Sound only in the mover's first 3,000 buckets: the windows that match
    // sit at the overlap's start, too close together for a line.
    var early = signal.sample(count: 16_000, k: 1, c: 50)
    for m in 3000..<early.count { early[m] = 0 }
    let narrow = AudioSyncMatch.drift(anchor: anchor, mover: early, lag: 50, overlap: 50..<15_000)
    if narrow != .notMeasured(
        "the windows that matched cover too little of the overlap to measure drift.") {
        good = false
    }
    notes.append("sound in the first 3,000 of 15,000 only: \(narrow)")

    // A 6,000-bucket overlap [1000, 7000) at lag 1000 whose mover sounds only
    // in its first and last 350 buckets: windows [0, 2000) and [4000, 6000)
    // of it can match; every other window's ±100 search stays ≥ 50 buckets
    // clear of the sound. The two windows span 4,000 ≥ (6000 − 2000)/2, so
    // the span rule would pass: the note must be the count's.
    var ends = signal.sample(count: 16_000, k: 1, c: 1000)
    for m in ends.indices where !(m < 350 || (m >= 5650 && m < 6000)) { ends[m] = 0 }
    let two = AudioSyncMatch.drift(
        anchor: anchor, mover: ends, lag: 1000, overlap: 1000..<(1000 + minimum))
    if two != .notMeasured("only 2 of the overlap's windows matched; drift needs at least 3.") {
        good = false
    }
    notes.append("only the two end windows can match: \(two)")
    row("P5", good, notes.joined(separator: "; "))
}

// MARK: - P6 refusals

do {
    let anchor = randomArray(3000, seed: 61)
    var good = true
    var notes: [String] = []
    func expect(_ name: String, _ plan: AudioSync.Plan, refusedWith words: String?) {
        let said = refusal(plan)
        let ok = words.map { said?.contains($0) ?? false } ?? (said == nil)
        if !ok { good = false }
        notes.append("\(name): \(describe(plan))")
    }
    let late = shifted(anchor, by: 300, count: 3000, seed: 62)
    let early = shifted(anchor, by: -300, count: 3000, seed: 63)
    let far = shifted(anchor, by: 2000, count: 3000, seed: 64)

    // Before 0: lag −300 from an anchor at 0 puts the mover at −1 800 000.
    expect(
        "before 0",
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 0, end: 18_000_000, zero: 0, video: true,
                            onsets: anchor),
                    reading(2, track: 1, start: 0, end: 18_000_000, zero: 0, onsets: early),
                ], problems: [], anchor: nil, fps: fps)),
        refusedWith: "clip 2: would have to start 3.00 s before the timeline begins.")
    // Never meeting: the anchor plays its first 2 s, the mover its first 1 s,
    // which lands at 20 s.
    expect(
        "windows never meet",
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 0, end: 1_200_000, zero: 0, video: true,
                            onsets: anchor),
                    reading(2, track: 1, start: 0, end: 600_000, zero: 0, onsets: far),
                ], problems: [], anchor: nil, fps: fps)),
        refusedWith: "clip 2: once lined up it would not play at any moment clip 1 plays.")
    // Same track.
    expect(
        "same track",
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 600_000, end: 18_600_000, zero: 600_000,
                            video: true, onsets: anchor),
                    reading(2, track: 0, start: 20_000_000, end: 38_000_000, zero: 20_000_000,
                            onsets: late),
                ], problems: [], anchor: nil, fps: fps)),
        refusedWith: "clip 1 and clip 2 are on one track")
    // A neighbour: the mover lands on [2 400 000, 20 400 000).
    func withNeighbour(_ start: Ticks, _ end: Ticks) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 600_000, end: 18_600_000, zero: 600_000,
                            video: true, onsets: anchor),
                    reading(2, track: 1, start: 0, end: 18_000_000, zero: 0, onsets: late,
                            neighbours: [AudioSync.Neighbour(clip: 99, start: start, end: end)]),
                ], problems: [], anchor: nil, fps: fps))
    }
    expect("neighbour overlapped", withNeighbour(20_000_000, 21_000_000),
           refusedWith: "clip 2: would overlap clip 99 on its track.")
    expect("neighbour abutting after", withNeighbour(20_400_000, 21_000_000), refusedWith: nil)
    expect("neighbour abutting before", withNeighbour(1_000_000, 2_400_000),
           refusedWith: nil)
    // Silence is the silent clip's own problem, named on it alone.
    let quiet = [Float](repeating: 0, count: 3000)
    func silence(anchor first: [Float], mover second: [Float]) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 600_000, end: 18_600_000, zero: 600_000,
                            video: true, onsets: first),
                    reading(2, track: 1, start: 0, end: 18_000_000, zero: 0, onsets: second),
                    reading(3, track: 2, start: 0, end: 18_000_000, zero: 0, onsets: late),
                ], problems: [], anchor: nil, fps: fps))
    }
    let silentAnchor = silence(anchor: quiet, mover: late)
    if refusal(silentAnchor) != "clip 1: has no sound that rises anywhere to line up by." {
        good = false
    }
    notes.append("silent anchor: \(describe(silentAnchor))")
    let silentMover = silence(anchor: anchor, mover: quiet)
    if refusal(silentMover) != "clip 2: has no sound that rises anywhere to line up by." {
        good = false
    }
    notes.append("silent mover: \(describe(silentMover))")
    row("P6", good, notes.joined(separator: "; "))
}

// MARK: - P7 correction

/// "name(arg=value, …)" for each op, keys sorted.
func opList(_ ops: [ReelOp]) -> String {
    ops.map { op in
        op.name + "(" + op.args.keys.sorted().map { "\($0)=\(op.args[$0]!)" }
            .joined(separator: ", ") + ")"
    }.joined(separator: ", ")
}

do {
    // The anchor plays f(a) for a in [0, 8000) from 150 s (zeroA 90 000 000,
    // in 0). The mover's file is 20,000 buckets, silent for its first 12,000
    // (so the in point lies far ahead of the overlap, which is what makes the
    // pivot matter) and then f(m·k − 12000). It is trimmed to in I =
    // 3 000 000 (5 s) and starts at S = 3 000 000 (zero 0), d = 117 s.
    let signal = Bumps(seed: 71, length: 8_100)
    let anchorOnsets = signal.sample(count: 8_000, k: 1, c: 0)
    let zeroA: Ticks = 90_000_000
    let c = -12_000.0
    let frame: Ticks = 20_000
    let anchor = reading(
        1, track: 0, start: zeroA, end: zeroA + 48_000_000, zero: zeroA, video: true,
        onsets: anchorOnsets)
    func moverFile(_ k: Double) -> [Float] {
        var file = signal.sample(count: 20_000, k: k, c: c)
        for m in 0..<12_000 { file[m] = 0 }
        return file
    }
    var good = true
    var notes: [String] = []
    // (name, k, the hand-worked delta, the centre-line delta, the ops' names
    // in SY-10's order). delta = snap(zeroA + 6000·c − S + I·k) =
    // snap(15 000 000 + 3 000 000·k):
    //   k 1.001: 18 003 000 = frame 900.15 → 18 000 000 (0.35 frame from an edge);
    //   k 0.999: 17 997 000 = frame 899.85 → 18 000 000 (0.35 frame from an edge).
    // The centre-line delta (aMid 4000, lag 4000 − 16000/k, zeroN 0):
    //   k 1.001: 114 000 000 − 95 904 096 = 18 095 904 → 18 100 000 (5 frames off);
    //   k 0.999: 114 000 000 − 96 096 096 = 17 903 904 → 17 900 000 (5 frames off).
    let cases: [(String, Double, Ticks, Ticks, [String])] = [
        ("+1000 ppm (lengthens)", 1.001, 18_000_000, 18_100_000, ["move_clip", "set_speed"]),
        ("−1000 ppm (shortens)", 0.999, 18_000_000, 17_900_000, ["set_speed", "move_clip"]),
    ]
    for (name, k, want, centreLine, order) in cases {
        let moverOnsets = moverFile(k)
        let mover = reading(
            2, track: 1, start: 3_000_000, end: 120_000_000, zero: 0, onsets: moverOnsets)
        let coarse = AudioSyncMatch.match(anchor: anchorOnsets, mover: moverOnsets)
        let coarseDelta = coarse.map {
            ReelTime.snapToFrame(zeroA + Ticks(($0.lag * 6000).rounded()), fps: fps)
        }
        let plan = AudioSync.plan(
            AudioSync.Input(readings: [anchor, mover], problems: [], anchor: nil, fps: fps))
        let control = abs(centreLine - want) >= 2 * frame
        guard case .planned(_, let synced, let ops) = plan, let one = synced.first else {
            good = false
            notes.append("\(name): \(describe(plan))")
            continue
        }
        let speedOp = ops.first { $0.name == "set_speed" }
        let rate = speedOp?.args["rate"] as? Double ?? .nan
        let keep = speedOp?.args["keep_pitch"] as? Bool
        let moveDelta = ops.first { $0.name == "move_clip" }?.args["delta"] as? Ticks
        let rateOK = abs(rate * k - 1) <= 5e-6
        let ok = rateOK && keep == false && one.delta == want && moveDelta == want
            && ops.map { $0.name } == order && one.correction == .apply(speed: rate) && control
        if !ok { good = false }
        notes.append(
            "\(name): rate \(String(format: "%.7f", rate)) (want 1/k "
                + "\(String(format: "%.7f", 1 / k)) ±5 ppm), keep_pitch \(keep.map(String.init) ?? "nil"), "
                + "delta \(one.delta) (want \(want)), duration \(one.duration); ops \(opList(ops)) "
                + "(want \(order)); control: centre-line delta \(centreLine), AS-1 delta "
                + "\(coarseDelta.map(String.init) ?? "nil") (r "
                + "\(coarse.map { String(format: "%.3f", $0.correlation) } ?? "nil"), q "
                + "\(coarse.map { String(format: "%.2f", $0.ratio) } ?? "nil")), drift \(one.drift)")
    }
    // The neighbour: k 1.001 at S 21 000 000 (zero 18 000 000, I 3 000 000)
    // puts delta at snap(3 000) = 0; d 117 000 000 grows to about
    // 117 120 000, so a neighbour from the old end 138 000 000 is overlapped
    // and one 10 frames later (138 200 000) is not.
    let moverOnsets = moverFile(1.001)
    func withNeighbour(_ at: Ticks) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    anchor,
                    reading(
                        2, track: 1, start: 21_000_000, end: 138_000_000, zero: 18_000_000,
                        onsets: moverOnsets,
                        neighbours: [AudioSync.Neighbour(clip: 99, start: at, end: 150_000_000)]),
                ], problems: [], anchor: nil, fps: fps))
    }
    let abutting = withNeighbour(138_000_000)
    let later = withNeighbour(138_000_000 + 10 * frame)
    if refusal(abutting) != "clip 2: would overlap clip 99 on its track." { good = false }
    if case .planned(_, let synced, let ops) = later,
       synced.first?.delta == 0, ops.map({ $0.name }) == ["set_speed"] {
        notes.append("neighbour 10 frames later: \(describe(later)), ops \(opList(ops))")
    } else {
        good = false
        notes.append("neighbour 10 frames later: \(describe(later))")
    }
    notes.append("neighbour abutting the old end, delta 0: \(describe(abutting))")
    row("P7", good, notes.joined(separator: "; "))
}

// MARK: - P8 the decision and the band

do {
    typealias D = AudioSyncMatch.Drift
    func fit(ms: Double, rate: Double, error: Double) -> AudioSyncMatch.DriftAnswer {
        .measured(
            D(ppm: rate * 1e6, milliseconds: ms, rate: rate, intercept: 0,
              errorMilliseconds: error, windows: 10))
    }
    var good = true
    var notes: [String] = []
    func expect(_ name: String, _ got: AudioSync.Correction, _ want: AudioSync.Correction) {
        if got != want { good = false }
        notes.append("\(name): \(got)")
    }
    func applies(_ name: String, _ got: AudioSync.Correction, _ want: Double) {
        if case .apply(let speed) = got, abs(speed - want) <= 1e-12 {
            notes.append("\(name): \(got)")
        } else {
            good = false
            notes.append("\(name): \(got) (want apply ×\(want))")
        }
    }
    let one = AudioSync.correction
    expect("4.99 ms", one(fit(ms: 4.99, rate: 1e-4, error: 0.1), 1),
           .leave(note: "a drift of 4.99 ms over the overlap is under the 5 ms Synchronize "
               + "Audio corrects."))
    applies("5.0 ms ±1", one(fit(ms: 5.0, rate: 1e-4, error: 1.0), 1), 1 - 1e-4)
    // max(5, 3 × error): at 5 ms with ±1.7 the 3× test (5.1) is the one that bites.
    expect("5.0 ms ±1.7", one(fit(ms: 5.0, rate: 1e-4, error: 1.7), 1),
           .leave(note: "a drift of 5.00 ms over the overlap is under 3 times its "
               + "uncertainty (±1.70 ms), so it cannot be told from no drift."))
    applies("30 ms ±9.99 (just over 3×)", one(fit(ms: 30, rate: 2e-4, error: 9.99), 1),
            1 - 2e-4)
    applies("30 ms ±10 (exactly 3×)", one(fit(ms: 30, rate: 2e-4, error: 10), 1), 1 - 2e-4)
    expect("30 ms ±10.01 (just under 3×)", one(fit(ms: 30, rate: 2e-4, error: 10.01), 1),
           .leave(note: "a drift of 30.00 ms over the overlap is under 3 times its "
               + "uncertainty (±10.01 ms), so it cannot be told from no drift."))
    expect("−30 ms ±10.01", one(fit(ms: -30, rate: -2e-4, error: 10.01), 1),
           .leave(note: "a drift of -30.00 ms over the overlap is under 3 times its "
               + "uncertainty (±10.01 ms), so it cannot be told from no drift."))
    applies("new speed 0.0019 from ×1", one(fit(ms: 100, rate: 0.0019, error: 0.1), 1), 1 - 0.0019)
    expect("new speed 0.0021 from ×1", one(fit(ms: 100, rate: 0.0021, error: 0.1), 1),
           .leave(note: "correcting it would play the clip at ×0.9979, beyond the 0.2% "
               + "Synchronize Audio corrects."))
    // 20 ppm over a 6,000-bucket overlap: 20e-6 × 60 000 ms = 1.2 ms.
    expect("20 ppm", one(fit(ms: 1.2, rate: 20e-6, error: 0.3), 1),
           .leave(note: "a drift of 1.20 ms over the overlap is under the 5 ms Synchronize "
               + "Audio corrects."))
    expect("not measured", one(.notMeasured("x"), 1), .leave(note: nil))

    // A mover whose file holds f(m·k − 4000) (k 1.001), already playing at
    // 1/k: on its timeline grid its bucket j is the anchor's j − 4000, so it
    // is in sync where zeroN = zeroA − 24 000 000 = 12 000 000 — no op.
    let signal = Bumps(seed: 81, length: 16_500)
    let anchorOnsets = signal.sample(count: 16_000, k: 1, c: 0)
    let k = 1.001
    let drifted = signal.sample(count: 20_000, k: k, c: -4000)
    let anchor = reading(
        1, track: 0, start: 36_000_000, end: 132_000_000, zero: 36_000_000, video: true,
        onsets: anchorOnsets)
    func resync(_ speed: Double) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    anchor,
                    reading(
                        2, track: 1, start: 15_000_000, end: 15_000_000 + 117_120_000,
                        zero: 12_000_000, onsets: drifted, speed: speed),
                ], problems: [], anchor: nil, fps: fps))
    }
    let settled = resync(1 / k)
    if case .planned(_, let synced, let ops) = settled, ops.isEmpty,
       case .leave = synced.first?.correction {
        notes.append("at 1/k: \(describe(settled)), drift \(synced.first!.drift)")
    } else {
        good = false
        notes.append("at 1/k: \(describe(settled)) (want no op)")
    }
    let near = resync(0.9999)
    if case .planned(_, _, let ops) = near,
       let rate = ops.first(where: { $0.name == "set_speed" })?.args["rate"] as? Double,
       abs(rate * k - 1) <= 5e-6 {
        notes.append("at ×0.9999: \(opList(ops)) (want rate 1/k ±5 ppm)")
    } else {
        good = false
        notes.append("at ×0.9999: \(describe(near)) (want a set_speed to 1/k ±5 ppm)")
    }

    let band: [(Double, Bool)] = [(2, false), (1.002, true), (1.0021, false), (0.998, true),
                                  (0.9979, false)]
    for (rate, inside) in band {
        let problem = AudioSync.rateProblem(rate)
        if (problem == nil) != inside { good = false }
        notes.append("×\(rate): \(problem ?? "matched")")
    }
    if AudioSync.rateProblem(2) != "plays at ×2; Synchronize Audio lines up clips playing at "
        + "×1 or within 0.2% of it." {
        good = false
    }
    row("P8", good, notes.joined(separator: "; "))
}

let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(data)
exit(0)
