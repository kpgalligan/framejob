import Foundation

/// Who is active on each step (SW-21) and the shots those turns make (SW-22).
/// Pure; `SpeakerSwitch.swift` says what the switch is.
extension SpeakerSwitch {
    static var stepTicks: Ticks { MediaPeaks.bucketTicks }

    /// The nearest-rank percentile `sorted[⌈p·n⌉ − 1]`; nil for no values.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count) - 1e-9).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    // MARK: - SW-21

    /// One label per step. Every microphone's series must be the same length.
    static func labels(_ microphones: [Microphone], settings: Settings) -> [Label] {
        activeSets(microphones, settings: settings).map { active in
            switch active.count {
            case 0: return .nobody
            case 1: return .person(active[0])
            default: return .crosstalk
            }
        }
    }

    /// The microphone tracks active on each step (SW-21), a dominant one alone.
    static func activeSets(_ microphones: [Microphone], settings: Settings) -> [[UInt32]] {
        let count = microphones.map(\.level.count).min() ?? 0
        let threshold = settings.voiceThreshold
        // P and F per microphone; a microphone with no speech is never active.
        let gauges: [(p: Double, f: Double)?] = microphones.map { mic in
            var speech: [Double] = []
            var quiet: [Double] = []
            for k in 0..<count where mic.covered[k] {
                if mic.voice[k] >= threshold { speech.append(mic.level[k]) } else {
                    quiet.append(mic.level[k])
                }
            }
            guard let p = percentile(speech, 0.9) else { return nil }
            return (p, percentile(quiet, 0.1) ?? -.infinity)
        }
        var out: [[UInt32]] = []
        out.reserveCapacity(count)
        for k in 0..<count {
            var active: [(track: UInt32, over: Double)] = []
            for (index, mic) in microphones.enumerated() {
                guard let gauge = gauges[index], mic.covered[k], mic.voice[k] >= threshold
                else { continue }
                let level = mic.level[k]
                guard level >= gauge.p - settings.bleedDB,
                    level >= gauge.f + settings.floorMarginDB
                else { continue }
                active.append((mic.track, level - gauge.p))
            }
            if active.count >= 2, let top = active.max(by: { $0.over < $1.over }),
                active.allSatisfy({ $0.track == top.track
                    || top.over - $0.over >= settings.dominanceDB })
            {
                active = [top]
            }
            out.append(active.map(\.track))
        }
        return out
    }

    // MARK: - SW-22

    struct Run: Equatable { var label: Label; var start: Int; var end: Int }

    /// Maximal runs of equal labels, in step indices.
    static func runs(_ labels: [Label]) -> [Run] {
        var out: [Run] = []
        for (k, label) in labels.enumerated() {
            if var last = out.last, last.label == label {
                last.end = k + 1
                out[out.count - 1] = last
            } else {
                out.append(Run(label: label, start: k, end: k + 1))
            }
        }
        return out
    }

    /// SW-22 (a), the crosstalk half: each maximal stretch of non-crosstalk runs lying between two
    /// crosstalk runs, shorter than `bridge` in total, becomes crosstalk; the runs it joins merge.
    static func bridgingCrosstalk(_ runs: [Run], under bridge: Ticks) -> [Run] {
        var out: [Run] = []
        var index = 0
        while index < runs.count {
            let run = runs[index]
            if run.label != .crosstalk, var last = out.last, last.label == .crosstalk,
                let next = runs[index...].firstIndex(where: { $0.label == .crosstalk }),
                Ticks(runs[next].start - run.start) * stepTicks < bridge
            {
                last.end = runs[next].end
                out[out.count - 1] = last
                index = next + 1
                continue
            }
            out.append(run)
            index += 1
        }
        return out
    }

    static func shots(
        labels: [Label], from: Ticks, to: Ticks, fps: Fps, pairing: Pairing,
        angles: [AngleTrack], settings: Settings
    ) -> [Shot] {
        let step = stepTicks
        func ticks(_ seconds: Double) -> Ticks { Ticks((seconds * Double(ReelTime.perSecond)).rounded()) }
        func snap(_ t: Ticks) -> Ticks { ReelTime.snapToFrame(t, fps: fps) }
        guard to > from, let front = angles.first?.track else { return [] }
        let wide = pairing.wide.flatMap { w in angles.contains { $0.track == w } ? w : nil }

        // (a), (b): the turns.
        let turns = bridgedRuns(labels, settings: settings)

        // (c), (d), (e): the starts.
        var starts: [(angle: UInt32, start: Ticks)] = []
        if let wide { starts.append((wide, from)) }
        for turn in turns {
            let length = Ticks(turn.end - turn.start) * step
            let angle: UInt32?
            switch turn.label {
            case .nobody: angle = nil
            case .person(let mic):
                angle = length >= ticks(settings.minTurn)
                    ? pairing.speakers.first(where: { $0.mic == mic })?.angle : nil
            case .crosstalk:
                angle = length >= ticks(settings.crosstalkMin) && settings.crosstalk == .wide
                    ? wide : nil
            }
            guard let angle, angle != starts.last?.angle else { continue }
            let at = max(
                starts.last?.start ?? from, from,
                snap(from + Ticks(turn.start) * step - ticks(settings.lead)))
            if starts.last?.start == at {
                starts.removeLast()
                if starts.last?.angle == angle { continue }
            }
            starts.append((angle, at))
        }
        if starts.isEmpty { starts.append((front, from)) }
        starts[0].start = from
        var tiled = tile(starts, to: to)

        // (f) the wide after a person has held the screen `wide_after`.
        if let wide, let after = settings.wideAfter, after > 0 {
            var out: [Shot] = []
            for shot in tiled {
                guard shot.angle != wide else {
                    out.append(shot)
                    continue
                }
                var held = shot.start
                while true {
                    let cut = snap(held + ticks(after))
                    guard cut > held, cut < shot.end else { break }
                    let back = min(shot.end, snap(cut + ticks(settings.minShot)))
                    out.append(Shot(angle: shot.angle, start: held, end: cut))
                    out.append(Shot(angle: wide, start: cut, end: back))
                    held = back
                    if back >= shot.end { break }
                }
                if held < shot.end { out.append(Shot(angle: shot.angle, start: held, end: shot.end)) }
            }
            tiled = out
        }

        // (g) every uncovered piece handed on; (h) the merges.
        let covered = handOff(tiled, angles: angles, wide: wide)
        return merged(covered, angles: angles, minShot: ticks(settings.minShot))
    }

    /// SW-22 (a): a short stretch between two crosstalk runs is crosstalk, then a short nobody
    /// between two equal labels takes the label; (b) the runs left are the turns.
    static func bridgedRuns(_ labels: [Label], settings: Settings) -> [Run] {
        let step = stepTicks
        let bridge = Ticks((settings.bridge * Double(ReelTime.perSecond)).rounded())
        var turns = bridgingCrosstalk(runs(labels), under: bridge)
        var index = 1
        while index + 1 < turns.count {
            let gap = turns[index]
            if gap.label == .nobody, turns[index - 1].label == turns[index + 1].label,
                Ticks(gap.end - gap.start) * step < bridge
            {
                turns[index - 1].end = turns[index + 1].end
                turns.removeSubrange(index...(index + 1))
            } else {
                index += 1
            }
        }
        return turns
    }

    /// Starts to shots tiling `[starts[0].start, to)`, empty ones dropped.
    static func tile(_ starts: [(angle: UInt32, start: Ticks)], to: Ticks) -> [Shot] {
        var out: [Shot] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? min(starts[index + 1].start, to) : to
            if end > start.start { out.append(Shot(angle: start.angle, start: start.start, end: end)) }
        }
        return coalesced(out)
    }

    static func coalesced(_ shots: [Shot]) -> [Shot] {
        var out: [Shot] = []
        for shot in shots where shot.end > shot.start {
            if let last = out.last, last.angle == shot.angle, last.end == shot.start {
                out[out.count - 1] = Shot(angle: last.angle, start: last.start, end: shot.end)
            } else {
                out.append(shot)
            }
        }
        return out
    }

    /// (g): each shot's uncovered pieces go to the wide, else the shot
    /// before's angle, else the front-most angle covering there.
    static func handOff(_ shots: [Shot], angles: [AngleTrack], wide: UInt32?) -> [Shot] {
        func track(_ id: UInt32) -> AngleTrack? { angles.first { $0.track == id } }
        func reachOf(_ id: UInt32?, _ t: Ticks) -> Ticks? {
            id.flatMap(track).flatMap { reach($0, from: t) }
        }
        var out: [Shot] = []
        for (index, shot) in shots.enumerated() {
            let before = index > 0 ? shots[index - 1].angle : nil
            var t = shot.start
            while t < shot.end {
                if let end = reachOf(shot.angle, t) {
                    let stop = min(end, shot.end)
                    out.append(Shot(angle: shot.angle, start: t, end: stop))
                    t = stop
                    continue
                }
                let back = track(shot.angle)?.clips.map(\.start).filter { $0 > t }.min() ?? shot.end
                let uncovered = min(back, shot.end)
                while t < uncovered {
                    let choice: (UInt32, Ticks)?
                    if let w = wide, let end = reachOf(w, t) {
                        choice = (w, end)
                    } else if let b = before, let end = reachOf(b, t) {
                        choice = (b, end)
                    } else {
                        choice = angles.lazy.compactMap { a in reach(a, from: t).map { (a.track, $0) } }
                            .first
                    }
                    guard let (angle, end) = choice else {
                        // No angle covers: SW-24 refuses this; keep the shot's own.
                        let next = angles.flatMap(\.clips).map(\.start).filter { $0 > t }.min()
                        let stop = min(next ?? uncovered, uncovered)
                        out.append(Shot(angle: shot.angle, start: t, end: stop))
                        t = stop
                        continue
                    }
                    let stop = min(end, uncovered)
                    out.append(Shot(angle: angle, start: t, end: stop))
                    t = stop
                }
            }
        }
        return coalesced(out)
    }

    /// Whether `angle` covers `[start, end)` whole.
    static func covers(_ angle: UInt32, _ start: Ticks, _ end: Ticks, in angles: [AngleTrack]) -> Bool {
        guard let track = angles.first(where: { $0.track == angle }) else { return false }
        guard let reached = reach(track, from: start) else { return false }
        return reached >= end
    }

    /// (h): the earliest short shot that can merge does, until none can.
    static func merged(_ shots: [Shot], angles: [AngleTrack], minShot: Ticks) -> [Shot] {
        var out = coalesced(shots)
        while true {
            var done = true
            for (i, shot) in out.enumerated() where shot.end - shot.start < minShot {
                let intoBefore = i > 0 && covers(out[i - 1].angle, shot.start, shot.end, in: angles)
                let intoAfter = i + 1 < out.count
                    && covers(out[i + 1].angle, shot.start, shot.end, in: angles)
                if intoBefore {
                    let b = out[i - 1]
                    out[i - 1] = Shot(angle: b.angle, start: b.start, end: shot.end)
                } else if intoAfter {
                    let a = out[i + 1]
                    out[i + 1] = Shot(angle: a.angle, start: shot.start, end: a.end)
                } else {
                    continue
                }
                out.remove(at: i)
                out = coalesced(out)
                done = false
                break
            }
            if done { return out }
        }
    }
}
