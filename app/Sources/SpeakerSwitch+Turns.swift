import Foundation

/// Who speaks when, as `reframe_clip {follow: speaker}` is handed it (road map
/// "creator-jobs" VR6a, spec §11 VR-60 (c)): SW-21's labels and SW-22 (a)–(e)
/// read exactly as `shots` reads them, but on the labels themselves, not on
/// angles, so the framing and Switch by Speaker agree about who is talking.
///
/// - the crosstalk bridge and the nobody bridge (`bridgedRuns`, SW-22 (a));
/// - a person run of at least `minTurn` starts that microphone's turn, a
///   crosstalk run of at least `crosstalkMin` one turn per microphone active
///   at any of its crosstalk steps; nobody and shorter runs hold;
/// - each start at `snap(onset − lead)`, never before the last start or the
///   range's start; the first start is the range's start;
/// - each turn ends at the next start, the last at the range's end, so the
///   turns tile the range (crosstalk turns share one span).
///
/// Pure (SW-25): reads no document, file or clock.
extension SpeakerSwitch {
    /// One microphone's turn: `mic` is its TRACK, `[from, to)` range ticks.
    struct Turn: Equatable {
        let mic: UInt32
        let from: Ticks
        let to: Ticks
    }

    /// The turns of `input`'s read microphones over its range (this file's
    /// doc); empty when no run qualifies.
    static func turns(_ input: Input) -> [Turn] {
        let step = stepTicks
        guard step > 0, input.to > input.from else { return [] }
        let count = Int((input.to - input.from) / step)
        let microphones = input.microphones.filter { $0.level.count == count }
        let settings = input.settings
        func ticks(_ seconds: Double) -> Ticks {
            Ticks((seconds * Double(ReelTime.perSecond)).rounded())
        }
        let sets = activeSets(microphones, settings: settings)
        let steps = labels(microphones, settings: settings)
        let order = microphones.map(\.track)

        var starts: [(mics: [UInt32], start: Ticks)] = []
        for run in bridgedRuns(steps, settings: settings) {
            let length = Ticks(run.end - run.start) * step
            var mics: [UInt32] = []
            switch run.label {
            case .nobody: break
            case .person(let mic):
                if length >= ticks(settings.minTurn) { mics = [mic] }
            case .crosstalk:
                guard length >= ticks(settings.crosstalkMin) else { break }
                var active = Set<UInt32>()
                for k in run.start..<min(run.end, sets.count) where sets[k].count >= 2 {
                    active.formUnion(sets[k])
                }
                mics = order.filter { active.contains($0) }
            }
            guard !mics.isEmpty, mics != starts.last?.mics else { continue }
            let at = max(
                starts.last?.start ?? input.from, input.from,
                ReelTime.snapToFrame(
                    input.from + Ticks(run.start) * step - ticks(settings.lead), fps: input.fps))
            if starts.last?.start == at {
                starts.removeLast()
                if starts.last?.mics == mics { continue }
            }
            starts.append((mics, at))
        }
        guard !starts.isEmpty else { return [] }
        starts[0].start = input.from
        var out: [Turn] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? min(starts[index + 1].start, input.to) : input.to
            guard end > start.start else { continue }
            for mic in start.mics { out.append(Turn(mic: mic, from: start.start, to: end)) }
        }
        return out
    }
}
