import Foundation

/// What Clip ▸ Follow Subject… frames (spec §11 VR-29; road map "creator-jobs" VR2b2): each
/// selected clip with a moving picture `reframe_clip`'d with `replace: true` and a "Backgrounds"
/// track as its `backdrop`, as one undo step "Follow Subject". The sheet is
/// `FollowSubjectSheetController`, the door `EditorViewController+FollowSubject.swift`.
///
/// Swift copies none of VR-26's or VR-27's rules: the plan TRIES each op on the container's
/// handle through `SwitchAngle.Trial` and lists the core's own sentence for a refusal; the
/// subjects are `FramingSubjects.read`'s, over `FramingAnalysis.windows`. Names no `rc_*`.
struct FollowSubjectSettings: Equatable {
    /// One of `FollowSubject.follows`.
    var follow: FramingFollow
    /// Times the scale that fills the canvas, inside `zoomRange` (the sheet shows 100–400 %).
    var zoom: Double
    var whereEmpty: FramingWhereEmpty

    static let followKey = "FrameJobFollowKind"
    static let whereEmptyKey = "FrameJobFollowWhereEmpty"
    static let zoomRange: ClosedRange<Double> = 1...4

    /// VR-29 (c): Follow and Where Empty as remembered, an absent or unknown value read as
    /// `subject` / `fit`; Zoom is never remembered, so it is the caller's.
    static func remembered(_ defaults: UserDefaults, zoom: Double) -> FollowSubjectSettings {
        let kind = defaults.string(forKey: followKey).flatMap(FramingFollow.init(rawValue:))
        let empty = defaults.string(forKey: whereEmptyKey).flatMap(FramingWhereEmpty.init(rawValue:))
        return FollowSubjectSettings(
            follow: kind.flatMap { FollowSubject.follows.contains($0) ? $0 : nil } ?? .subject,
            zoom: zoom, whereEmpty: empty ?? .fit)
    }

    /// Writes each remembered key whose value changed from `opened`, and no other.
    func remember(changedFrom opened: FollowSubjectSettings, in defaults: UserDefaults) {
        if follow != opened.follow {
            defaults.set(follow.rawValue, forKey: Self.followKey)
        }
        if whereEmpty != opened.whereEmpty {
            defaults.set(whereEmpty.rawValue, forKey: Self.whereEmptyKey)
        }
    }

    /// The clip's `reframe_clip` (VR-29 (e)): `zoom` for every follow, `where_empty` and
    /// `subjects` for the following kinds only, always `replace: true`.
    func op(clip: UInt32, backdrop: UInt32, subjects: [String: Any]?) -> ReelOp {
        let following = follow.follows
        return .reframeClip(
            clip: clip, follow: follow, zoom: zoom, whereEmpty: following ? whereEmpty : nil,
            backdrop: backdrop, replace: true, subjects: following ? subjects : nil)
    }
}

enum FollowSubject {
    static let actionName = "Follow Subject"
    static let backgroundsName = "Backgrounds"
    /// The sheet's Follow pop-up, in order: Subject, Faces, People, Salient Region, Center.
    static let follows: [FramingFollow] = [.subject, .face, .person, .salient, .center]

    /// What Follow would write: the ops, the clips framed, the ones already framed this way, the
    /// refused with the core's sentence, whether Backgrounds is kept, how many more tracks the
    /// core made behind it, and VR-27 (f)'s counts summed over the framed clips.
    struct Plan {
        let ops: [ReelOp]
        let framed: [UInt32]
        let unchanged: [UInt32]
        let refused: [(clip: UInt32, reason: String)]
        let backgrounds: Bool
        let moreTracks: Int
        let reEased: Int
        let carried: Int
    }

    enum Answer {
        case plan(Plan)
        case refused(String)
    }

    /// VR-29 (a): the selected clips `FramingAnalysis.qualifies` takes, in id order.
    static func targets(_ selection: Set<UInt32>, in project: ReelProject) -> [UInt32] {
        let snapshot = project.snapshot
        return selection.sorted().filter { id in
            snapshot.clip(id).map { FramingAnalysis.qualifies($0, in: snapshot) } ?? false
        }
    }

    /// VR-29 (b): 1 (fill, the owner's answer), or 1.25 when the first clip's media is within
    /// 1 % of the canvas's aspect.
    static func defaultZoom(_ clips: [UInt32], in snapshot: ProjectSnapshot) -> Double {
        guard let first = clips.first, let clip = snapshot.clip(first),
            let media = snapshot.media(for: clip), media.width > 0, media.height > 0,
            snapshot.canvas.width > 0, snapshot.canvas.height > 0
        else { return 1 }
        let picture = Double(media.width) / Double(media.height)
        let canvas = Double(snapshot.canvas.width) / Double(snapshot.canvas.height)
        return abs(picture / canvas - 1) <= 0.01 ? 1.25 : 1
    }

    /// Each clip's `subjects`, read from the store over that clip's own windows, as
    /// `reframe_clip`'s tool reads them. Reads files only: any thread.
    static func subjects(_ clips: [UInt32], in project: ReelProject, cacheDir: URL)
        -> [UInt32: [String: Any]]
    {
        var out: [UInt32: [String: Any]] = [:]
        for clip in clips {
            guard let entry = FramingAnalysis.windows(clips: [clip], in: project).first,
                let media = project.snapshot.media(entry.media)
            else { continue }
            out[clip] = FramingSubjects.read(
                media: media, windows: entry.windows, cacheDir: cacheDir)
        }
        return out
    }

    /// VR-29 (e) on `project`, the handle of the container being edited. Throws only the core's
    /// invalid input.
    static func plan(
        _ clips: [UInt32], subjects: [UInt32: [String: Any]], settings: FollowSubjectSettings,
        project: ReelProject
    ) throws -> Answer {
        var trial = SwitchAngle.Trial(project: project)
        let known = Set(project.snapshot.tracks.map(\.id))
        if let why = try trial.require(.addTrack(index: 0, name: backgroundsName)) {
            return .refused("Follow Subject was refused at add_track: \(why)")
        }
        guard let track = trial.project.snapshot.tracks.first(where: { !known.contains($0.id) })
        else { return .refused("Follow Subject was refused at add_track: no track was added.") }

        var framed: [UInt32] = []
        var unchanged: [UInt32] = []
        var refused: [(clip: UInt32, reason: String)] = []
        var moreTracks = 0
        var reEased = 0
        var carried = 0
        for clip in clips {
            let op = settings.op(clip: clip, backdrop: track.id, subjects: subjects[clip])
            let prior = trial.project
            switch try prior.applying(op) {
            case .applied(let next):
                trial.project = next
                trial.ops.append(op)
                framed.append(clip)
                moreTracks += next.snapshot.tracks.count - prior.snapshot.tracks.count
                let counted = counts(before: prior, after: next, clip: clip)
                reEased += counted.reEased
                carried += counted.carried
            case .identity:
                unchanged.append(clip)
            case .refused(let refusal):
                refused.append((clip, refusal.reason))
            }
        }
        guard !framed.isEmpty else {
            return .plan(
                Plan(
                    ops: [], framed: [], unchanged: unchanged, refused: refused,
                    backgrounds: false, moreTracks: 0, reEased: 0, carried: 0))
        }
        let backgrounds = !trial.project.snapshot.clips(onTrack: track.id).isEmpty
        if !backgrounds, let why = try trial.require(.removeTrack(track: track.id)) {
            return .refused("Follow Subject was refused at remove_track: \(why)")
        }
        return .plan(
            Plan(
                ops: trial.ops, framed: framed, unchanged: unchanged, refused: refused,
                backgrounds: backgrounds, moreTracks: moreTracks, reEased: reEased,
                carried: carried))
    }

    /// VR-27 (f), for `clip` between two handles of its container: re-eased, an action in both
    /// whose duration shrank and whose after curve is not linear; carried, an action with the
    /// same id and span in both across which — under `replace` — the AFTER handle's video
    /// scale, x or y differs by more than 1e-6, or — composed (`replace: false`, Make
    /// Vertical's step, spec §11 VR-34) — the framing F (`framing`) differs by more than 1e-6
    /// between the action's two ends.
    static func counts(
        before: ReelProject, after: ReelProject, clip: UInt32, replace: Bool = true
    ) -> (reEased: Int, carried: Int) {
        guard let old = before.snapshot.clip(clip), let new = after.snapshot.clip(clip) else {
            return (0, 0)
        }
        var reEased = 0
        var carried = 0
        for action in new.actions {
            guard let was = old.actions.first(where: { $0.id == action.id }) else { continue }
            if action.duration < was.duration, action.curve != .linear { reEased += 1 }
            guard action.start == was.start, action.duration == was.duration else { continue }
            let (a, b) = (new.start + action.start, new.start + action.endTime)
            let from: [Double]?
            let to: [Double]?
            if replace {
                from = placement(after, clip, at: a)
                to = placement(after, clip, at: b)
            } else {
                from = framing(before: before, after: after, clip: clip, at: a)
                    .map { [$0.k, $0.dx, $0.dy] }
                to = framing(before: before, after: after, clip: clip, at: b)
                    .map { [$0.k, $0.dx, $0.dy] }
            }
            if let from, let to, zip(from, to).contains(where: { abs($0 - $1) > 1e-6 }) {
                carried += 1
            }
        }
        return (reEased, carried)
    }

    /// The framing F at project time `t` from both handles' evaluated video (spec §11 VR-34):
    /// k = s′/s, dx = x′ − k·x, dy = y′ − k·y; nil when either answers no video or s is 0.
    static func framing(before: ReelProject, after: ReelProject, clip: UInt32, at t: Ticks)
        -> (k: Double, dx: Double, dy: Double)?
    {
        guard let was = placement(before, clip, at: t), let now = placement(after, clip, at: t),
            was[0] != 0
        else { return nil }
        let k = now[0] / was[0]
        return (k, now[1] - k * was[1], now[2] - k * was[2])
    }

    /// The clip's evaluated video (scale, x, y) at project time `t`; nil when the core answers
    /// no video group.
    private static func placement(_ project: ReelProject, _ clip: UInt32, at t: Ticks)
        -> [Double]?
    {
        guard let video = project.clipState(clip, at: t)?["video"] as? [String: Any] else {
            return nil
        }
        func value(_ key: String, _ fallback: Double) -> Double {
            (video[key] as? NSNumber)?.doubleValue ?? fallback
        }
        return [value("scale", 1), value("x", 0), value("y", 0)]
    }

    /// VR-29 (g): the counts, then one line per clip already framed or refused. With nothing
    /// framed, only the lines.
    static func summary(_ plan: Plan) -> String {
        var lines: [String] = []
        if !plan.framed.isEmpty {
            var text = "Frames \(counted(plan.framed.count, "clip"))."
            if plan.backgrounds { text += " Adds a Backgrounds track for the blurred copy." }
            if plan.moreTracks > 0 {
                text += " Adds \(plan.moreTracks) more \(plan.moreTracks == 1 ? "track" : "tracks")"
                    + " behind it where clips overlap."
            }
            if plan.reEased > 0 { text += " \(counted(plan.reEased, "action")) re-eased at a cut." }
            if plan.carried > 0 {
                text += " \(counted(plan.carried, "action")) "
                    + (plan.carried == 1 ? "carries" : "carry") + " a framing move."
            }
            lines.append(text)
        }
        lines += plan.unchanged.map { "Clip \($0) is already framed this way." }
        lines += plan.refused.map { "Clip \($0.clip): \($0.reason)" }
        return lines.joined(separator: "\n")
    }

    /// VR-29 (g)'s pending summary, while the analysis is still to be made.
    static func pendingSummary(files: Int, clips: Int) -> String {
        "Finds the faces, people and shot changes in \(counted(files, "file")) on this Mac "
            + "first, then frames \(counted(clips, "clip"))."
    }

    /// The Analyzing sheet's row for one request: the file, then what is found in it.
    static func rowName(_ request: AnalysisRequest) -> String {
        let what: String
        switch request.kind {
        case .shots: what = "Shot changes"
        case .faces: what = "Faces"
        case .subjects: what = "People and salient regions"
        default: what = request.kind.rawValue
        }
        return "\(request.media.name) — \(what)"
    }

    private static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
