import Foundation

/// The leveller's curve (spec §11 AU-66 (b), (c)): the material's level per
/// 10 ms played step relative to the clip's loudness L, made ahead of time
/// from the clip's `ClipLoudness` reading and its speech mask, so the tap
/// only looks it up. It does not depend on the target or the limits, only on
/// the reading, the mask, L and the response.
///
/// **Phrases.** A step is SPEECH when the mask holds and its loudness is at
/// least −70 LUFS. A BREAK is a run of at least `breakSteps` non-speech steps
/// (0.5 s); a PHRASE runs from a speech step to the last speech step before
/// the next break, and it is LONG with at least `minimumPhraseSteps` speech
/// steps (1 s).
///
/// **A long phrase's level.** For each of its steps k, u_k is the loudness of
/// the mean energy over the phrase's speech steps within `windowHalfSteps` of
/// k (a 3 s window, speech only, truncated at the phrase's edges, so it never
/// reaches across a break), less L; r is `smooth(u)` over the response's
/// half, forward then backward, which is zero-phase: a change is anticipated
/// as much as it is followed.
///
/// **Everything else takes a neighbour's.** A short phrase takes the previous
/// long phrase's last r, else the next one's first; steps before the first
/// long phrase take its first r, steps after the last its last. A break
/// between two phrases holds the first's last r and, over its last
/// `glideSteps` (0.25 s), moves linearly in dB to the second's first r,
/// reaching it at the second's first speech step. No long phrase: no curve.
///
/// **Its time.** `segments` hold the timeline ticks the steps were played at:
/// segment s's step k is `[start + k·step, start + (k + 1)·step)`, its value
/// `values[first + k]`. `value(atTick:)` is linear between step centres
/// within a segment, held past a segment's ends, and the nearest segment's
/// outside all of them.
final class AudioLevellerCurve: Equatable {
    static let breakSteps = 50
    static let minimumPhraseSteps = 100
    static let windowHalfSteps = 150
    static let glideSteps = 25
    /// A step is speech only at or above this, LUFS (AU-66 (c)).
    static let speechFloorLUFS = -70.0

    /// A run of steps played contiguously, in timeline ticks.
    struct Segment: Equatable {
        let start: Ticks
        /// The index of its first step in `values`.
        let first: Int
        let count: Int
    }

    let segments: [Segment]
    /// r_k, dB re L, one per played step.
    let values: [Float]

    init(segments: [Segment], values: [Float]) {
        self.segments = segments
        self.values = values
    }

    static func == (a: AudioLevellerCurve, b: AudioLevellerCurve) -> Bool {
        a === b || (a.segments == b.segments && a.values == b.values)
    }

    // MARK: - Making it

    /// The curve of `reading` over the segments it walked (the clip's first
    /// media's, any order), with `speech` its steps' mask and `level` L; nil
    /// with no long phrase, or a reading whose steps the segments do not
    /// account for.
    static func make(
        reading: ClipLoudness.Reading, segments: [PlanSegment], speech: [Bool], level: Double,
        response: Ticks
    ) -> AudioLevellerCurve? {
        let step = ClipLoudness.stepTicks
        guard step > 0 else { return nil }
        var spans: [Segment] = []
        var first = 0
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let count = Int(segment.duration / step)
            spans.append(Segment(start: segment.start, first: first, count: count))
            first += count
        }
        guard first == reading.steps.count,
            let r = relative(
                steps: reading.steps, speech: speech, level: level, response: response)
        else { return nil }
        return AudioLevellerCurve(
            segments: spans.filter { $0.count > 0 }, values: r.map { Float($0) })
    }

    /// r per step (AU-66 (c)); nil when no phrase has `minimumPhraseSteps`
    /// speech steps.
    static func relative(steps: [Double], speech: [Bool], level: Double, response: Ticks)
        -> [Double]?
    {
        let n = min(steps.count, speech.count)
        guard n > 0, level.isFinite else { return nil }
        let isSpeech = (0..<n).map {
            speech[$0] && StepLoudness.loudness(steps[$0]) >= speechFloorLUFS
        }
        // The phrases: each speech step joins the open phrase unless a break
        // lies between them.
        var phrases: [(first: Int, last: Int, speech: Int)] = []
        for k in 0..<n where isSpeech[k] {
            if let open = phrases.last, k - open.last - 1 < breakSteps {
                phrases[phrases.count - 1] = (open.first, k, open.speech + 1)
            } else {
                phrases.append((k, k, 1))
            }
        }
        guard phrases.contains(where: { $0.speech >= minimumPhraseSteps }) else { return nil }
        let tau = Double(response) / 2 / Double(ClipLoudness.stepTicks)
        var r = [Double](repeating: 0, count: n)
        // Each long phrase's own r; each phrase's first and last value.
        var ends: [(first: Double, last: Double)?] = []
        for phrase in phrases {
            guard phrase.speech >= minimumPhraseSteps else {
                ends.append(nil)
                continue
            }
            // Prefix sums of the phrase's speech energy and count.
            let width = phrase.last - phrase.first + 1
            var energy = [Double](repeating: 0, count: width + 1)
            var counted = [Int](repeating: 0, count: width + 1)
            for j in 0..<width {
                let k = phrase.first + j
                energy[j + 1] = energy[j] + (isSpeech[k] ? steps[k] : 0)
                counted[j + 1] = counted[j] + (isSpeech[k] ? 1 : 0)
            }
            var u = [Double](repeating: 0, count: width)
            for j in 0..<width {
                let low = max(0, j - windowHalfSteps)
                let high = min(width - 1, j + windowHalfSteps)
                let speechCount = counted[high + 1] - counted[low]
                let mean = speechCount > 0 ? (energy[high + 1] - energy[low]) / Double(speechCount) : 0
                u[j] = StepLoudness.loudness(max(mean, 1e-20)) - level
            }
            let smoothed = smooth(u, tau: tau)
            for j in 0..<width { r[phrase.first + j] = smoothed[j] }
            ends.append((smoothed[0], smoothed[width - 1]))
        }
        // A short phrase takes the previous long phrase's last r, else the
        // next one's first.
        var value: [(first: Double, last: Double)] = []
        var previous: Double?
        for (index, end) in ends.enumerated() {
            if let end {
                value.append(end)
                previous = end.last
                continue
            }
            let taken = previous ?? ends[index...].lazy.compactMap { $0?.first }.first ?? 0
            value.append((taken, taken))
            for k in phrases[index].first...phrases[index].last { r[k] = taken }
        }
        // Before the first phrase and after the last, held.
        for k in 0..<phrases[0].first { r[k] = value[0].first }
        for k in (phrases[phrases.count - 1].last + 1)..<n { r[k] = value[value.count - 1].last }
        // Each break: A's last held, then a 0.25 s glide reaching B's first at
        // B's first speech step.
        for index in 1..<phrases.count {
            let from = value[index - 1].last
            let to = value[index].first
            let start = phrases[index - 1].last + 1
            let next = phrases[index].first
            for k in start..<next {
                let m = next - k
                r[k] = m >= glideSteps
                    ? from : from + (to - from) * Double(glideSteps - m) / Double(glideSteps)
            }
        }
        return r
    }

    /// A one-pole of time constant `tau` steps run forward, then backward
    /// over the forward pass, each pass primed with its first input: a
    /// zero-phase smoothing.
    static func smooth(_ u: [Double], tau: Double) -> [Double] {
        guard let head = u.first else { return [] }
        let a = tau > 0 ? 1 - exp(-1 / tau) : 1
        var forward = u
        var y = head
        for k in 0..<u.count {
            y += (u[k] - y) * a
            forward[k] = y
        }
        var backward = forward
        var z = forward[forward.count - 1]
        for k in stride(from: forward.count - 1, through: 0, by: -1) {
            z += (forward[k] - z) * a
            backward[k] = z
        }
        return backward
    }

    // MARK: - Reading it

    /// The step index (into `values`) whose centre is at or before `tick`,
    /// the next one in the same segment, and the fraction between them;
    /// held at a segment's ends and at the nearest segment outside all.
    func position(atTick tick: Double) -> (index: Int, next: Int, fraction: Double) {
        guard !segments.isEmpty else { return (0, 0, 0) }
        let step = Double(ClipLoudness.stepTicks)
        // The last segment starting at or before `tick`, else the first.
        var low = 0
        var high = segments.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Double(segments[middle].start) <= tick { low = middle } else { high = middle - 1 }
        }
        var s = segments[low]
        let end = Double(s.start) + Double(s.count) * step
        // Past this one's end and nearer the next one's start: the next.
        if tick >= end, low + 1 < segments.count,
            Double(segments[low + 1].start) - tick < tick - end {
            s = segments[low + 1]
        }
        let p = (tick - Double(s.start)) / step - 0.5
        if p <= 0 { return (s.first, s.first, 0) }
        let lastIndex = s.first + s.count - 1
        if p >= Double(s.count - 1) { return (lastIndex, lastIndex, 0) }
        let whole = Int(p)
        return (s.first + whole, s.first + whole + 1, p - Double(whole))
    }

    /// r at `tick`, dB re L: linear between step centres.
    func value(atTick tick: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let at = position(atTick: tick)
        let a = Double(values[at.index])
        return a + (Double(values[at.next]) - a) * at.fraction
    }
}
