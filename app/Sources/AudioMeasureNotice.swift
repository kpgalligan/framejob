import Foundation

extension Notification.Name {
    /// Posted by `AudioMeasureDoor.land` (object: the document) when a measured
    /// press of Normalize, Enhance Voice or Match Audio left a clip away from
    /// its target or skipped one (spec §11 AU-169); `userInfo["notice"]` is the
    /// `AudioMeasureNotice` the inspector's foot shows. Never a refusal: no
    /// "Refused: ", no beep of its own.
    static let projectDocumentDidNote = Notification.Name("FrameJobProjectDocumentDidNote")
}

/// The app's own sentence for a measured press (spec §11 AU-169): which clips
/// it left away from the target, how far and the likely cause, and which it
/// skipped and why — the facts `normalize_clip`, `enhance_voice` and
/// `match_audio` answer as `limited_by`, `note` and `skipped`, written for a
/// person. `text` is the inspector's foot; `detail` its tooltip, every clip
/// on a line of its own. Pure: the door reads the names and the action
/// limiters from the project the press measured (`make(_:in:changed:)`).
struct AudioMeasureNotice: Equatable {
    let text: String
    let detail: String

    /// What a press's plan says, before it lands: the command's name, its
    /// target (`reference`: Match's, the reference's measured loudness), the
    /// rows of the clips it set and the clips it skipped.
    struct Facts {
        let command: String
        let targetLUFS: Double
        var reference = false
        let rows: [AudioNormalize.LoudnessResult]
        let skipped: [AudioNormalize.Problem]
    }

    /// `facts` over `snapshot`, the project the press read (the door's stale
    /// test has passed): each clip named by `label`, and the clips an
    /// action's end turns a limiter on for (`ProcessedLoudness.endLimiterOn`).
    static func make(_ facts: Facts, in snapshot: ProjectSnapshot, changed: Bool)
        -> AudioMeasureNotice?
    {
        let ids = facts.rows.map(\.clip) + facts.skipped.map(\.clip)
        var labels: [UInt32: String] = [:]
        for id in ids where labels[id] == nil {
            if let clip = snapshot.clip(id) { labels[id] = label(clip, in: snapshot) }
        }
        let ends = Set(facts.rows.map(\.clip).filter {
            ProcessedLoudness.endLimiterOn(snapshot.clip($0))
        })
        return make(facts, labels: labels, endLimiters: ends, changed: changed)
    }

    /// A clip as a person finds it: its name in curly quotes and its start as
    /// m:ss, the Match Audio sheet's clock, so two cuts of one recording read
    /// apart.
    static func label(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> String {
        "“\(snapshot.name(of: clip))” (\(clock(clip.start)))"
    }

    static func clock(_ ticks: Int64) -> String {
        let seconds = max(0, Int(ticks / ReelTime.perSecond))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// AU-169 (d): nil when no row has a limit and nothing was skipped. A row
    /// with a limit is away from the target (`limited_by` set, the tools'
    /// rule); `changed` false is a press that changed nothing (every clip
    /// skipped, or already where the plan puts it). An id with no label
    /// reads "clip N".
    static func make(
        _ facts: Facts, labels: [UInt32: String], endLimiters: Set<UInt32>, changed: Bool
    ) -> AudioMeasureNotice? {
        let off = facts.rows.filter { $0.limit != nil }
        guard !off.isEmpty || !facts.skipped.isEmpty else { return nil }
        let target = facts.targetLUFS
        let shown = (facts.reference ? "the reference's " : "") + AudioEnhance.lufs(target)
        func name(_ clip: UInt32) -> String { labels[clip] ?? "clip \(clip)" }
        func distance(_ row: AudioNormalize.LoudnessResult) -> String {
            let gap = abs(row.resultLUFS - target)
            return gap < 0.05 ? "less than 0.1 LU" : String(format: "%.1f LU", gap)
        }
        /// "short" or "over", and with `of` the words before the target.
        func side(_ row: AudioNormalize.LoudnessResult, of: Bool = false) -> String {
            row.resultLUFS < target ? (of ? "short of" : "short") : "over"
        }
        func cause(_ row: AudioNormalize.LoudnessResult) -> String {
            let held = AudioNormalize.actionLimiterHeld(
                row, endLimiter: endLimiters.contains(row.clip), targetLUFS: target)
            switch row.limit {
            case .maxGain? where held:
                return " at the \(AudioNormalize.maxGainName) ceiling, likely because a limiter "
                    + "an action's end turns on holds the sound down."
            case .maxGain?:
                return ", with its volume at the \(AudioNormalize.maxGainName) ceiling."
            case .verifyRenders?, nil:
                return ", likely because a limiter holds the sound down harder as the volume "
                    + "rises."
            }
        }
        /// One clip's whole account: "“A” (0:12) is 13.6 LU short of −16.0 LUFS, …".
        func line(_ row: AudioNormalize.LoudnessResult) -> String {
            "\(name(row.clip)) is \(distance(row)) \(side(row, of: true)) \(shown)\(cause(row))"
        }
        var sentences: [String] = []
        if !changed { sentences.append("\(facts.command) changed nothing.") }
        if off.count == 1, let row = off.first {
            sentences.append(
                changed
                    ? "\(facts.command) left \(name(row.clip)) \(distance(row)) "
                        + "\(side(row, of: true)) \(shown)\(cause(row))"
                    : line(row))
        } else if let furthest = off.max(by: {
            // The first of the furthest on a tie: `max(by:)` keeps the
            // earlier of two equal elements.
            abs($0.resultLUFS - target) < abs($1.resultLUFS - target)
        }) {
            let lead = changed
                ? "\(facts.command) left \(off.count) clips away from \(shown)"
                : "\(off.count) clips are away from \(shown)"
            sentences.append(
                "\(lead); the furthest, \(name(furthest.clip)), is \(distance(furthest)) "
                    + "\(side(furthest))\(cause(furthest))")
        }
        if let skip = facts.skipped.first {
            let who = changed && off.isEmpty ? facts.command : "It"
            sentences.append(
                facts.skipped.count == 1
                    ? "\(who) skipped \(name(skip.clip)): \(skip.reason)"
                    : "\(who) skipped \(facts.skipped.count) clips, the first "
                        + "\(name(skip.clip)): \(skip.reason)")
        }
        let text = sentences.joined(separator: " ")
        guard off.count + facts.skipped.count > 1 else {
            return AudioMeasureNotice(text: text, detail: text)
        }
        let lines = off.map(line) + facts.skipped.map { "Skipped \(name($0.clip)): \($0.reason)" }
        return AudioMeasureNotice(text: text, detail: ([text] + lines).joined(separator: "\n"))
    }
}
