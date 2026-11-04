import Foundation

/// Make Vertical's step (spec §11 VR-34) and its summary (VR-35): `opening` is the canvas and
/// the "Backgrounds" track, `plan` the whole step on one `SwitchAngle.Trial`, each op TRIED
/// on the trial's handle and only its answer deciding the clip's entry. The classes are
/// `VerticalVersion.swift`'s; step (6), the word caption tracks re-paged on the new canvas, is
/// `CaptionRelayout`'s (VR-40 (f)). Throws only the core's invalid input. Names no `rc_*`.
extension VerticalVersion {

    /// What the step did to one clip, and why when it did less than asked.
    struct Entry: Equatable {
        let clip: UInt32
        let treatment: Treatment
        let reason: String?
    }

    /// The step: its ops and the handle they make, the new size, one entry per classed clip
    /// in id order, whether Backgrounds is kept, the further tracks the core made behind it,
    /// and VR-27 (f)'s counts over the framed clips.
    struct Plan {
        let ops: [ReelOp]
        let project: ReelProject
        let width: Int
        let height: Int
        let entries: [Entry]
        let backgrounds: Bool
        let moreTracks: Int
        let reEased: Int
        let carried: Int
        /// Step (6)'s caption tracks, re-laid and kept; nil with `captions` false.
        let captions: CaptionRelayout.Outcome?
    }

    enum Answer {
        case plan(Plan)
        case refused(String)
    }

    enum Opening {
        case opened(SwitchAngle.Trial, backgrounds: UInt32)
        case refused(String)
    }

    /// VR-34 (1)–(2): `set_canvas` with no rescale, then `add_track` "Backgrounds" at the back,
    /// both required. The core's own error for either (the track cap is one: "too many
    /// tracks") stops the step as its refusal does, in its own words.
    static func opening(_ project: ReelProject, width: Int, height: Int) throws -> Opening {
        var trial = SwitchAngle.Trial(project: project)
        func required(_ op: ReelOp) -> String? {
            do { return try trial.require(op) } catch { return error.localizedDescription }
        }
        if let why = required(.setCanvas(width: width, height: height, rescaleClips: false)) {
            return .refused("Make Vertical was refused at set_canvas: \(why)")
        }
        let known = Set(trial.project.snapshot.tracks.map(\.id))
        if let why = required(.addTrack(index: 0, name: backgroundsName)) {
            return .refused("Make Vertical was refused at add_track: \(why)")
        }
        guard let track = trial.project.snapshot.tracks.first(where: { !known.contains($0.id) })
        else { return .refused("Make Vertical was refused at add_track: no track was added.") }
        return .opened(trial, backgrounds: track.id)
    }

    /// VR-34 on `project`, the top-level timeline. `missing`: media pictures whose media has
    /// no URL in `document.mediaURLs()` (kept, not followed). `subjects` per clip, read by the
    /// following kinds only.
    static func plan(
        _ project: ReelProject, settings: VerticalSettings, subjects: [UInt32: [String: Any]],
        missing: Set<UInt32>
    ) throws -> Answer {
        let old = project.snapshot
        let size = settings.shape.size(from: old.canvas)
        var trial: SwitchAngle.Trial
        let backgrounds: UInt32
        switch try opening(project, width: size.width, height: size.height) {
        case .refused(let why): return .refused(why)
        case .opened(let opened, let track):
            trial = opened
            backgrounds = track
        }
        let roles = classify(project)
        // Step (6)'s survey is of the OLD snapshot, so step (3) leaves its tracks alone.
        let survey = settings.captions ? CaptionRelayout.survey(old) : nil
        let relaid = Set(survey?.recognised.map(\.track) ?? [])
        var entries: [UInt32: Entry] = [:]
        var framed: Set<UInt32> = []
        var moreTracks = 0
        var reEased = 0
        var carried = 0

        // (3) Each picture, nest and other clip, from the old canvas.
        for (id, role) in roles {
            guard let clip = old.clip(id), !relaid.contains(clip.track) else { continue }
            var follow = FramingFollow.keep
            var note: String?
            switch role {
            case .picture:
                if case .media = clip.source {
                    if settings.follow.follows, missing.contains(id) {
                        note = "its media file is missing, so it is kept as placed"
                    } else {
                        follow = settings.follow
                    }
                } else {
                    follow = .center
                    note = "it is a still picture, so it is centred"
                }
            case .nest:
                follow = .center
                note = "it is a nest, so it is centred"
            case .other:
                break
            case .backdrop, .shapePlate, .imagePlate:
                continue
            }
            func op(_ follow: FramingFollow) -> ReelOp {
                let following = follow.follows
                return .reframeClip(
                    clip: id, follow: follow, zoom: settings.zoom,
                    whereEmpty: following ? settings.whereEmpty : nil,
                    fromWidth: UInt32(old.canvas.width), fromHeight: UInt32(old.canvas.height),
                    backdrop: backgrounds, subjects: following ? subjects[id] : nil)
            }
            let prior = trial.project
            var next = prior
            var used = follow
            var refusedWhy: String?
            switch try prior.applying(op(follow)) {
            case .applied(let made):
                next = made
                trial.ops.append(op(follow))
            case .identity:
                break
            case .refused(let refusal):
                guard follow != .keep else {
                    return .refused(
                        "Make Vertical was refused at reframe_clip for clip \(id): "
                            + refusal.reason)
                }
                refusedWhy = refusal.reason
                used = .keep
                switch try prior.applying(op(.keep)) {
                case .applied(let made):
                    next = made
                    trial.ops.append(op(.keep))
                case .identity:
                    break
                case .refused(let again):
                    return .refused(
                        "Make Vertical was refused at reframe_clip for clip \(id): "
                            + again.reason)
                }
            }
            trial.project = next
            moreTracks += next.snapshot.tracks.count - prior.snapshot.tracks.count
            if let refusedWhy {
                entries[id] = Entry(clip: id, treatment: .notFollowed, reason: refusedWhy)
                continue
            }
            if used != .keep {
                framed.insert(id)
                let counted = FollowSubject.counts(
                    before: prior, after: next, clip: id, replace: false)
                reEased += counted.reEased
                carried += counted.carried
            }
            if let note {
                entries[id] = Entry(clip: id, treatment: .notFollowed, reason: note)
            } else if role == .other {
                entries[id] = Entry(clip: id, treatment: .kept, reason: nil)
            } else {
                entries[id] = followedEntry(clip, prior: prior, next: next)
            }
        }

        // (4) The backdrops and the plates, at the new canvas.
        let newFill = { (clip: ClipSnapshot) -> Double in
            fill(old.sourceSize(of: clip) ?? .zero, width: size.width, height: size.height)
        }
        for (id, role) in roles {
            guard let clip = old.clip(id) else { continue }
            let op: ReelOp
            let treatment: Treatment
            switch role {
            case .backdrop(let partner) where framed.contains(partner):
                op = .delete(clips: [id])
                treatment = .removed
            case .backdrop, .imagePlate:
                op = .setVideo(clips: [id], patch: VideoPatch(x: 0, y: 0, scale: newFill(clip)))
                treatment = .refilled
            case .shapePlate:
                op = .setShape(
                    clips: [id],
                    patch: ShapePatch(width: Double(size.width), height: Double(size.height)))
                treatment = .refilled
            case .picture, .nest, .other:
                continue
            }
            if let why = try trial.require(op) {
                return .refused("Make Vertical was refused at \(op.name) for clip \(id): \(why)")
            }
            entries[id] = Entry(clip: id, treatment: treatment, reason: nil)
        }

        // (5) Backgrounds goes when nothing landed on it.
        let kept = !trial.project.snapshot.clips(onTrack: backgrounds).isEmpty
        if !kept, let why = try trial.require(.removeTrack(track: backgrounds)) {
            return .refused("Make Vertical was refused at remove_track: \(why)")
        }

        // (6) The word caption tracks re-paged on the new canvas; a track the re-lay keeps
        // takes step (3)'s `keep`, so no clip is left without a reframe or an entry.
        var captions: CaptionRelayout.Outcome?
        if let survey {
            var outcome = try CaptionRelayout.relay(survey.recognised, on: &trial)
            let unlaid = Set(outcome.kept.map(\.track))
            for (id, _) in roles {
                guard let clip = old.clip(id), unlaid.contains(clip.track) else { continue }
                let op = ReelOp.reframeClip(
                    clip: id, follow: .keep, zoom: settings.zoom,
                    fromWidth: UInt32(old.canvas.width), fromHeight: UInt32(old.canvas.height),
                    backdrop: kept ? backgrounds : nil)
                if let why = try trial.require(op) {
                    return .refused(
                        "Make Vertical was refused at reframe_clip for clip \(id): \(why)")
                }
                entries[id] = Entry(clip: id, treatment: .kept, reason: nil)
            }
            outcome.kept = survey.kept + outcome.kept
            captions = outcome
        }
        return .plan(
            Plan(
                ops: trial.ops, project: trial.project, width: size.width, height: size.height,
                entries: entries.keys.sorted().compactMap { entries[$0] }, backgrounds: kept,
                moreTracks: moreTracks, reEased: reEased, carried: carried,
                captions: captions))
    }

    /// A media picture framed with a following kind or `center`: whole only when the op added
    /// a blurred copy AND the framing F is the same at the clip's start, its last tick and
    /// every action's two ends; otherwise followed, with why it is not wholly followed.
    private static func followedEntry(
        _ clip: ClipSnapshot, prior: ReelProject, next: ReelProject
    ) -> Entry {
        let known = Set(prior.snapshot.clips.map(\.id))
        let blurred = next.snapshot.clips.contains {
            !known.contains($0.id) && $0.name == blurredName
        }
        var constant = false
        if blurred, let now = next.snapshot.clip(clip.id) {
            var times = [now.start, now.start + max(0, now.duration - 1)]
            for action in now.actions {
                times += [now.start + action.start, now.start + action.endTime]
            }
            let frames = times.map {
                FollowSubject.framing(before: prior, after: next, clip: clip.id, at: $0)
            }
            if let first = frames.first ?? nil {
                constant = frames.allSatisfy { frame in
                    guard let frame else { return false }
                    return abs(frame.k - first.k) <= 1e-6 && abs(frame.dx - first.dx) <= 1e-6
                        && abs(frame.dy - first.dy) <= 1e-6
                }
            }
        }
        if constant { return Entry(clip: clip.id, treatment: .whole, reason: nil) }
        let reasons = [
            blurred ? "it is shown whole on a blurred copy where no subject is found" : nil,
            motionNote(clip),
        ].compactMap { $0 }
        return Entry(
            clip: clip.id, treatment: .followed,
            reason: reasons.isEmpty ? nil : reasons.joined(separator: " and "))
    }

    /// VR-35: the counts, then one line per entry with a reason.
    static func summary(_ plan: Plan) -> String {
        func count(_ treatment: Treatment) -> Int {
            plan.entries.filter { $0.treatment == treatment }.count
        }
        var text = "Makes a \(plan.width) × \(plan.height) version."
        let followed = count(.followed)
        if followed > 0 { text += " Follows \(counted(followed, "clip"))." }
        let whole = count(.whole)
        if whole > 0 { text += " Shows \(counted(whole, "clip")) whole on a blurred copy." }
        let kept = count(.kept)
        if kept > 0 { text += " Keeps \(counted(kept, "clip")) as placed." }
        let refilled = count(.refilled)
        if refilled > 0 { text += " Re-fills \(counted(refilled, "background"))." }
        let removed = count(.removed)
        if removed > 0 {
            text += " Removes \(removed) blurred \(removed == 1 ? "copy" : "copies") the "
                + "framing replaces."
        }
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
        if let relaid = plan.captions?.relaid.count, relaid > 0 {
            text += " Re-lays \(counted(relaid, "caption track")) for the new canvas."
        }
        var lines = [text]
        for entry in plan.entries {
            guard let reason = entry.reason else { continue }
            let why = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            switch entry.treatment {
            case .notFollowed: lines.append("Clip \(entry.clip) is not followed: \(why).")
            default: lines.append("Clip \(entry.clip) is followed, but \(why).")
            }
        }
        lines += (plan.captions?.kept ?? []).map(CaptionRelayout.keptLine)
        return lines.joined(separator: "\n")
    }

    /// VR-39 (d)'s pending summary, while the analysis is still to be made.
    static func pendingSummary(files: Int, width: Int, height: Int) -> String {
        "Finds the faces, people and shot changes in \(counted(files, "file")) on this Mac "
            + "first, then makes a \(width) × \(height) version."
    }

    /// The answer's keys every door shares (VR-36): `canvas`, `clips` in id order,
    /// `backgrounds`, `more_tracks`, `re_eased`, `moves_carried` and `summary`.
    static func answerFields(_ plan: Plan) -> [String: Any] {
        let clips: [[String: Any]] = plan.entries.map { entry in
            var row: [String: Any] = [
                "clip": Int(entry.clip), "treatment": entry.treatment.rawValue,
            ]
            if let reason = entry.reason { row["reason"] = reason }
            return row
        }
        var fields: [String: Any] = [
            "canvas": ["width": plan.width, "height": plan.height],
            "clips": clips,
            "backgrounds": plan.backgrounds,
            "more_tracks": plan.moreTracks,
            "re_eased": plan.reEased,
            "moves_carried": plan.carried,
            "summary": summary(plan),
        ]
        if let captions = plan.captions {
            fields["captions"] = CaptionRelayout.answerFields(captions)
        }
        return fields
    }

    private static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
