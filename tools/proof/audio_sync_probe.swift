// Road map "audio-sync", AS-1 (spec §11 SY-1..SY-5) — Synchronize Audio's
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
//   P5  drift (SY-5) on smooth arrays stretched by known ratios, within
//       ±50 ppm, including 100 ppm at exactly `driftMinimumOverlapBuckets`;
//       one bucket under it is not measured.
//   P6  the refusals (SY-4): before 0, windows that never meet, two clips on
//       one track, a neighbour on the mover's track; a neighbour that only
//       abuts the new window is not refused; a silent anchor is named once,
//       and not against the movers, and a silent mover is named alone.
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

func reading(
    _ clip: UInt32, track: Int, start: Ticks, end: Ticks, zero: Ticks, video: Bool = false,
    onsets: [Float] = [], neighbours: [AudioSync.Neighbour] = []
) -> AudioSync.Reading {
    AudioSync.Reading(
        clip: clip, media: clip + 100, trackIndex: track, start: start, end: end, zero: zero,
        hasVideo: video, onsets: onsets, neighbours: neighbours)
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
        let ok = abs(drift.ppm - want) <= 50 && abs(drift.milliseconds - wantMs) <= 50e-6
            * Double(overlap.count) * 10
        if !ok { good = false }
        notes.append(
            "\(name): \(String(format: "%.1f", drift.ppm)) ppm (want "
                + "\(String(format: "%.1f", want)) ±50), \(String(format: "%.2f", drift.milliseconds)) "
                + "ms (want \(String(format: "%.2f", wantMs)))")
    }
    let short = AudioSyncMatch.drift(
        anchor: anchor, mover: signal.sample(count: 16_000, k: 1.0001, c: 1000), lag: 1000,
        overlap: 1000..<(1000 + minimum - 1))
    if case .measured = short { good = false }
    notes.append("one bucket under the minimum: \(short)")
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

let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
    ?? Data("{}".utf8)
FileHandle.standardOutput.write(data)
exit(0)
