import Foundation

/// Make Vertical's step (spec §11 VR-34): `opening` is the canvas and the "Backgrounds" track,
/// `plan` the whole step on one `SwitchAngle.Trial`, each op TRIED on the trial's handle and
/// only its answer deciding the clip's entry. The classes are `VerticalVersion.swift`'s; step
/// 3b, the camera layouts re-laid, is `VerticalVersion+Layouts.swift`'s (VR-53 (d)); step (6),
/// the word caption tracks re-paged on the new canvas, is `CaptionRelayout`'s (VR-40 (f)); the
/// summary is `VerticalVersion+Summary.swift`'s; `follow: speaker`'s clips and turns are
/// `VerticalVersion+Speaker.swift`'s (VR-64). Throws only the core's invalid input. Names no
/// `rc_*`.
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
        /// The clips followed by their cursor, in id order (spec §11 VR-52).
        let cursor: [UInt32]
        /// Step 3b's re-laid switches, in time order, then camera id (spec §11 VR-54).
        let relaid: [Relaid]
        /// The clips framed by who is talking, in id order (spec §11 VR-64 (f)).
        let speaker: [SpeakerFraming]
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
    /// following kinds and `speaker` only: the analysis's, or for a picture whose media has a
    /// cursor file its cursor's (`FramingCursor`, VR-51), followed by `cursor` with `replace:
    /// true`, or shown whole (`fit`) when it is absent. With `speaker` a speaker clip's subjects
    /// carry their `turns` (`withTurns`, VR-64 (d)); it is framed `speaker` with its own
    /// microphones, every other analysed picture `face`, a refused `speaker` retried as `face`.
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
        var cursor: [UInt32] = []
        let speakers = speakerClips(project, settings: settings, missing: missing)
        let speakerOf = Dictionary(uniqueKeysWithValues: speakers.map { ($0.clip, $0) })
        var speaker: [SpeakerFraming] = []
        var moreTracks = 0
        var reEased = 0
        var carried = 0

        // (3b) The camera layouts re-laid first; what they changed is done (VR-53 (d)).
        let done: Set<UInt32>
        let layouts: [Relaid]
        switch try relay(roles, old: old, width: size.width, height: size.height, trial: &trial) {
        case .refused(let why): return .refused(why)
        case .done(let changed, let made, let switches):
            done = changed
            layouts = switches
            entries.merge(made) { _, new in new }
        }

        // (3) Each picture, nest and other clip, from the old canvas.
        for (id, role) in roles where !done.contains(id) {
            guard let clip = old.clip(id), !relaid.contains(clip.track) else { continue }
            var follow = FramingFollow.keep
            var note: String?
            switch role {
            case .picture:
                if case .media = clip.source {
                    if analyses(settings.follow), missing.contains(id) {
                        note = "its media file is missing, so it is kept as placed"
                    } else if analyses(settings.follow), old.media(for: clip)?.cursor != nil {
                        follow = subjects[id] == nil ? .fit : .cursor
                        if follow == .fit {
                            note = "its cursor file could not be read, so it is shown whole"
                        }
                    } else if settings.follow == .speaker {
                        follow = speakerOf[id] == nil ? .face : .speaker
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
            case .backdrop, .shapePlate, .imagePlate, .graphic, .layoutCamera, .layoutScreen,
                .layoutPiece:
                continue
            }
            func op(_ follow: FramingFollow) -> ReelOp {
                let own = follow == .speaker ? speakerOf[id] : nil
                var read = follow.readsSubjects ? subjects[id] : nil
                if follow != .speaker { read?["turns"] = nil }
                return .reframeClip(
                    clip: id, follow: follow, zoom: settings.zoom,
                    whereEmpty: analyses(follow) ? settings.whereEmpty : nil,
                    fromWidth: UInt32(old.canvas.width), fromHeight: UInt32(old.canvas.height),
                    backdrop: backgrounds, replace: follow == .cursor ? true : nil,
                    mics: own?.mics, micFaces: own?.micFaces, subjects: read)
            }
            let prior = trial.project
            var next = prior
            var used = follow
            var refusedWhy: String?
            var speakerWhy: String?
            // VR-34's retry, VR-64 (c)'s first: speaker → face → keep, a refused keep stopping.
            tried: while true {
                switch try prior.applying(op(used)) {
                case .applied(let made):
                    next = made
                    trial.ops.append(op(used))
                    break tried
                case .identity:
                    break tried
                case .refused(let refusal):
                    guard used != .keep else {
                        return .refused(
                            "Make Vertical was refused at reframe_clip for clip \(id): "
                                + refusal.reason)
                    }
                    if used == .speaker {
                        speakerWhy = refusal.reason
                        used = .face
                    } else {
                        refusedWhy = refusal.reason
                        used = .keep
                    }
                }
            }
            trial.project = next
            moreTracks += next.snapshot.tracks.count - prior.snapshot.tracks.count
            if let refusedWhy {
                entries[id] = Entry(clip: id, treatment: .notFollowed, reason: refusedWhy)
                continue
            }
            if used == .cursor { cursor.append(id) }
            if used == .speaker, let own = speakerOf[id] {
                let matched = own.micFaces ?? subjects[id].flatMap {
                    project.speakerMatch(clip: id, mics: own.mics, subjects: $0)?.assignment
                }
                speaker.append(SpeakerFraming(clip: id, mics: own.mics, faces: matched ?? []))
            }
            if used != .keep {
                framed.insert(id)
                let counted = FollowSubject.counts(
                    before: prior, after: next, clip: id, replace: used == .cursor)
                reEased += counted.reEased
                carried += counted.carried
            }
            if let note {
                entries[id] = Entry(clip: id, treatment: .notFollowed, reason: note)
            } else if role == .other {
                entries[id] = Entry(clip: id, treatment: .kept, reason: nil)
            } else if let speakerWhy {
                // VR-64 (c): followed on its faces, saying why not by who is talking.
                let base = followedEntry(clip, prior: prior, next: next)
                let reasons = [
                    "it follows its faces, not who is talking, because " + speakerWhy, base.reason,
                ].compactMap { $0 }
                entries[id] = Entry(
                    clip: id, treatment: .followed, reason: reasons.joined(separator: " and "))
            } else {
                entries[id] = followedEntry(clip, prior: prior, next: next)
            }
        }

        // (4) The backdrops and the plates, at the new canvas; a canvas-size graphic re-sized
        // to it (VR-42).
        let newFill = { (clip: ClipSnapshot) -> Double in
            fill(old.sourceSize(of: clip) ?? .zero, width: size.width, height: size.height)
        }
        for (id, role) in roles where !done.contains(id) {
            guard let clip = old.clip(id) else { continue }
            let ops: [ReelOp]
            let treatment: Treatment
            switch role {
            case .backdrop(let partner) where framed.contains(partner):
                ops = [.delete(clips: [id])]
                treatment = .removed
            case .backdrop, .imagePlate:
                ops = [.setVideo(clips: [id], patch: VideoPatch(x: 0, y: 0, scale: newFill(clip)))]
                treatment = .refilled
            case .shapePlate:
                ops = [
                    .setShape(
                        clips: [id],
                        patch: ShapePatch(width: Double(size.width), height: Double(size.height))),
                ]
                treatment = .refilled
            case .graphic:
                ops = graphicOps(clip, from: old.canvas, width: size.width, height: size.height)
                treatment = .resized
            case .picture, .nest, .other, .layoutCamera, .layoutScreen, .layoutPiece:
                continue
            }
            for op in ops {
                if let why = try trial.require(op) {
                    return .refused(
                        "Make Vertical was refused at \(op.name) for clip \(id): \(why)")
                }
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
                captions: captions, cursor: cursor.sorted(), relaid: layouts,
                speaker: speaker.sorted { $0.clip < $1.clip }))
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
}
