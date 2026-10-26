import Foundation

/// The caption clips a speed or ramp edit re-times in the same undo step
/// (#341, spec §11 SR-27, the owner's option B): every caption on a caption
/// track lying wholly inside a clip with sound whose source map the edit
/// changed is placed again through the old and the new `SourceMap`, cut back
/// to abut a caption that stayed, or removed when the clip no longer plays its
/// speech.
///
/// **No rate is computed here** (spec §11 D2-1): every time goes clip tick →
/// the old map's source tick → the new map's clip tick, through
/// `SourceMap`'s two readings alone, and the core's own answer to the edit
/// says which clips changed. **A plan is checked before it is offered**: the
/// edit and the re-time are tried together on the same handle and every
/// planned start, duration, word count and removal read back; on any mismatch
/// the plan is `.none` and the edit goes alone, as it did before SR-27.
///
/// Every door appends `ops` AFTER the edit's own, in one step: the Speed and
/// Speed Ramp sheets and the inspector (`SpeedAudioDrop.commit`), the live
/// gestures' end (`EditorViewController.timelineLiveEnded`), ⌫ Remove Action,
/// and the six op tools (`AgentServer.retimingEditResult`).
enum CaptionRetime {
    struct Plan {
        static let none = Plan(ops: [], retimed: [], removed: [])
        /// Unscoped, appended AFTER the edit's ops.
        let ops: [ReelOp]
        /// Ascending: captions whose start, duration or words changed.
        let retimed: [UInt32]
        /// Ascending.
        let removed: [UInt32]

        var isEmpty: Bool { retimed.isEmpty && removed.isEmpty }

        /// The step's name: the edit's own, or "<name> and Re-time Captions".
        func undoName(_ name: String) -> String {
            isEmpty ? name : "\(name) and Re-time Captions"
        }

        /// The keys an op tool's answer gains, each only when non-empty.
        var answerFields: [String: Any] {
            var fields: [String: Any] = [:]
            if !retimed.isEmpty { fields["captions_retimed"] = retimed.map { Int($0) } }
            if !removed.isEmpty { fields["captions_removed"] = removed.map { Int($0) } }
            return fields
        }
    }

    /// One caption's new place. `words` is a word page's new timings (clip
    /// time, relative to `start`), nil for a subtitle; `content` the page's
    /// cut content, nil when it is unchanged.
    struct Placement: Equatable {
        let start: Ticks
        let end: Ticks
        let words: [TextWord]?
        let content: String?
    }

    /// The gate (SR-27 (a)): `SpeedAudioDrop.mayCross` widened by the two
    /// action-timing ops, which move a ramp without naming a rate.
    static func mayRetime(_ ops: [ReelOp]) -> Bool {
        ops.contains {
            ["set_speed", "rate_stretch", "add_speed_ramp", "set_action", "remove_action"]
                .contains($0.name)
                || ($0.name == "set_action_end"
                    && ($0.args["patch"] as? [String: Any])?["speed"] != nil)
        }
    }

    /// A clip whose speech captions can be made from: `Transcriber.jobs`'
    /// eligibility — a media source, not reversed, media with sound, its
    /// audio enabled.
    static func speaks(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard case .media(let media, _, let reversed) = clip.source, !reversed else {
            return false
        }
        return snapshot.media(media)?.hasAudio == true && clip.enabled.audio
    }

    /// The tracks whose clips may be re-timed: named as `CaptionLayout`
    /// names a caption track, holding at least one clip, only text clips,
    /// and not locked.
    static func captionTracks(in snapshot: ProjectSnapshot) -> [UInt32] {
        snapshot.tracks.compactMap { track -> UInt32? in
            guard !track.locked, CaptionLayout.isCaptionTrackName(track.name) else { return nil }
            let clips = snapshot.clips.filter { $0.track == track.id }
            guard !clips.isEmpty else { return nil }
            for clip in clips {
                guard case .text = clip.source else { return nil }
            }
            return track.id
        }
    }

    /// One caption's new place (SR-27 (d)), or nil when it is removed: a
    /// subtitle whose source lies wholly outside the new window, a word page
    /// that keeps no word, or one whose snapped end is not after its snapped
    /// start. The new window is `[sourceIn, sourceIn + sourceLength]`.
    static func place(
        _ caption: ClipSnapshot, from old: SourceMap, clipStart oldStart: Ticks,
        to new: SourceMap, clipStart newStart: Ticks, fps: Fps
    ) -> Placement? {
        let low = Double(new.sourceIn)
        let high = Double(new.sourceIn + new.sourceLength)
        func source(_ t: Ticks) -> Double { old.source(atClip: Double(t - oldStart)) }
        func timeline(_ s: Double) -> Double {
            new.clip(atSource: min(max(s, low), high)) + Double(newStart)
        }
        func snap(_ t: Double) -> Ticks { ReelTime.snapToFrame(Ticks(t.rounded()), fps: fps) }
        let end = caption.start + caption.duration
        let words = caption.text?.words ?? []
        var kept = words
        var content: String?
        if words.isEmpty {
            guard source(end) > low, source(caption.start) < high else { return nil }
        } else {
            let count = words.prefix { source(caption.start + $0.start) < high }.count
            guard count > 0 else { return nil }
            if count < words.count {
                kept = Array(words.prefix(count))
                content = prefix(of: caption.text?.content ?? "", tokens: count)
            }
        }
        let start = snap(timeline(source(caption.start)))
        let finish = snap(timeline(source(end)))
        guard finish > start else { return nil }
        guard !words.isEmpty else {
            return Placement(start: start, end: finish, words: nil, content: nil)
        }
        // A word at or after the page's old start never lands before its
        // snapped new start; one before it (W-3's "already said") keeps its
        // mapped time.
        func relative(_ t: Ticks) -> Ticks {
            let r = Ticks((timeline(source(caption.start + t)) - Double(start)).rounded())
            return t >= 0 ? max(r, 0) : r
        }
        let placed = kept.map { TextWord(start: relative($0.start), end: relative($0.end)) }
        return Placement(start: start, end: finish, words: placed, content: content)
    }

    /// `content` through its `tokens`-th whitespace token (W-2's count).
    private static func prefix(of content: String, tokens: Int) -> String {
        let all = content.split(whereSeparator: \.isWhitespace)
        guard tokens > 0, tokens <= all.count else { return content }
        return String(content[..<all[tokens - 1].endIndex])
    }

    /// The re-time `ops` make on `project` — the container the ops address
    /// (a scoped view's handle inside a nest) — checked against the core's
    /// own answer, or `.none`.
    static func plan(_ ops: [ReelOp], on project: ReelProject) -> Plan {
        guard mayRetime(ops), case .applied(let after)? = try? project.applying(ops) else {
            return .none
        }
        let before = project.snapshot
        let now = after.snapshot
        let fps = before.canvas.fps
        let frame = max(fps.frameDuration, 1)
        let edited = editedClips(before: before, after: now, project, after)
        guard !edited.isEmpty else { return .none }
        let tracks = Set(captionTracks(in: before))
        var placed: [UInt32: Placement?] = [:]
        for caption in before.clips.sorted(by: { $0.id < $1.id })
        where tracks.contains(caption.track) {
            let end = caption.start + caption.duration
            guard let still = now.clip(caption.id), still.start == caption.start,
                still.duration == caption.duration,
                let owner = edited.first(where: { owner in
                    owner.start <= caption.start && end <= owner.start + owner.duration
                }),
                let old = project.sourceMap(owner.id), let new = after.sourceMap(owner.id),
                let newStart = now.clip(owner.id)?.start
            else { continue }
            let place = place(
                caption, from: old, clipStart: owner.start, to: new, clipStart: newStart, fps: fps)
            if let place, unchanged(place, caption) { continue }
            placed[caption.id] = .some(place)
        }
        let kept = cutBack(placed, on: before, after: now, frame: frame)
        let planned = Plan(
            ops: retimeOps(kept, before, frame),
            retimed: kept.filter { $0.value != nil }.keys.sorted(),
            removed: kept.filter { $0.value == nil }.keys.sorted())
        guard !planned.isEmpty, holds(planned, kept, ops, on: project, before) else {
            return .none
        }
        return planned
    }

    /// `ops` with the re-time `plan` makes on `project` appended, under the
    /// step's name: the edit alone, under `name`, when nothing re-times.
    static func withRetime(
        _ name: String, _ ops: [ReelOp], on project: ReelProject
    ) -> (name: String, ops: [ReelOp]) {
        let planned = plan(ops, on: project)
        return (planned.undoName(name), ops + planned.ops)
    }

    /// The clips the edit changed (SR-27 (b)), lowest id first: in both
    /// answers, speaking before the edit, and with their map's points or
    /// their start moved.
    private static func editedClips(
        before: ProjectSnapshot, after now: ProjectSnapshot, _ old: ReelProject,
        _ new: ReelProject
    ) -> [ClipSnapshot] {
        before.clips.sorted { $0.id < $1.id }.filter { clip in
            guard speaks(clip, in: before), let moved = now.clip(clip.id),
                let was = old.sourceMap(clip.id), let now = new.sourceMap(clip.id)
            else { return false }
            return was.points != now.points || moved.start != clip.start
        }
    }

    private static func unchanged(_ place: Placement, _ caption: ClipSnapshot) -> Bool {
        place.start == caption.start && place.end == caption.start + caption.duration
            && place.content == nil && (place.words == nil || place.words == caption.text?.words)
    }

    /// SR-27 (e): on its track a re-timed caption is cut back to abut a
    /// caption that was not re-timed, at that caption's place AFTER the edit
    /// (`now`: the edit may move it); one whose new start such a caption
    /// covers, or left under a frame, is removed.
    private static func cutBack(
        _ placed: [UInt32: Placement?], on before: ProjectSnapshot, after now: ProjectSnapshot,
        frame: Ticks
    ) -> [UInt32: Placement?] {
        var kept = placed
        for (id, place) in placed {
            guard let place, let track = before.clip(id)?.track else { continue }
            let fixed = now.clips.filter { $0.track == track && !placed.keys.contains($0.id) }
            let covered = fixed.contains {
                $0.start <= place.start && place.start < $0.start + $0.duration
            }
            let cut = fixed.map(\.start).filter { $0 > place.start && $0 < place.end }.min()
            if covered || cut.map({ $0 - place.start < frame }) == true {
                kept[id] = .some(nil)
            } else if let cut {
                kept[id] = .some(Placement(
                    start: place.start, end: cut, words: place.words, content: place.content))
            }
        }
        return kept
    }

    /// SR-27 (f): one `delete`; a one-frame stub of every caption whose
    /// start or end changes, before any move; the moves, earlier ones
    /// ascending and later ones descending, so a moved stub never lands on
    /// one not yet moved; the trims to the new ends; `set_text` where the
    /// words or the content changed.
    private static func retimeOps(
        _ kept: [UInt32: Placement?], _ before: ProjectSnapshot, _ frame: Ticks
    ) -> [ReelOp] {
        var ops: [ReelOp] = []
        let removed = kept.filter { $0.value == nil }.keys.sorted()
        if !removed.isEmpty { ops.append(.delete(clips: removed)) }
        let moves: [Move] = kept.compactMap { id, place in
            guard let place, let caption = before.clip(id) else { return nil }
            return Move(id: id, caption: caption, place: place)
        }.sorted { $0.from < $1.from }
        let stubbed = moves.filter { $0.place.start != $0.from || $0.place.end != $0.to }
        ops += stubbed.map { .trimEnd(clip: $0.id, to: $0.from + frame) }
        let earlier = stubbed.filter { $0.place.start < $0.from }
        let later = stubbed.filter { $0.place.start > $0.from }.sorted { $0.from > $1.from }
        ops += (earlier + later).map { .moveClip(clips: [$0.id], delta: $0.place.start - $0.from) }
        ops += stubbed.map { .trimEnd(clip: $0.id, to: $0.place.end) }
        for move in moves {
            let words = move.place.words.flatMap { $0 == move.caption.text?.words ? nil : $0 }
            guard words != nil || move.place.content != nil else { continue }
            ops.append(.setText(
                clips: [move.id], patch: TextPatch(content: move.place.content, words: words)))
        }
        return ops
    }

    private struct Move {
        let id: UInt32
        let caption: ClipSnapshot
        let place: Placement
        var from: Ticks { caption.start }
        var to: Ticks { caption.start + caption.duration }
    }

    /// SR-27 (g): the edit and the re-time tried together, and the plan's
    /// own numbers read back — every start, duration and word count, and
    /// every removal gone.
    private static func holds(
        _ plan: Plan, _ kept: [UInt32: Placement?], _ ops: [ReelOp], on project: ReelProject,
        _ before: ProjectSnapshot
    ) -> Bool {
        guard case .applied(let tried)? = try? project.applying(ops + plan.ops) else {
            return false
        }
        let snapshot = tried.snapshot
        guard plan.removed.allSatisfy({ snapshot.clip($0) == nil }) else { return false }
        for id in plan.retimed {
            guard let place = kept[id] ?? nil, let clip = snapshot.clip(id) else { return false }
            let count = place.words?.count ?? before.clip(id)?.text?.words.count ?? 0
            guard clip.start == place.start, clip.duration == place.end - place.start,
                clip.text?.words.count == count
            else { return false }
        }
        return true
    }
}
