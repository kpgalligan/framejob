import AppKit

/// The agent's clip tools: one per row of the clip half of spec §6
/// (and of the op table in the module doc of `core/src/edit.rs`), with the
/// same name and the same argument names.
///
/// Every handler is the canonical shape — `target(a)`, validate the ids
/// against the snapshot, build the `ReelOp`, `performGroupedEdit`,
/// `jsonResult` — and carries a comment naming the UI path it mirrors
/// (app/CLAUDE.md's agent-parity rule). No op JSON is written here: the
/// factories in `ReelOps.swift` are the only place that spells one, the RAW
/// factories every patch handler below reaches for included.
/// The five action tools are `AgentServer+Actions.swift`'s (a pure move, issue batch B87 phase 2).
extension AgentServer {

    /// The five property groups `paste_attributes` can be told to carry —
    /// `Kind::Groups`' values in `core/src/op_table.rs`, spelled as the wire
    /// spells them and in its order: the four patch groups, then `graphic`
    /// (spec §11 G-32). A refusal here names this list; the catalog's enum is
    /// printed from the core's, and the clip-catalog proof compares the two.
    static let attributeGroups: [String] = ["video", "audio", "text", "shape", "graphic"]

    // MARK: - Placing clips

    /// `add_clip` — dragging a Media-tab row onto a track
    /// (`MediaPane.drop(_:on:target:)` with `MediaDropTarget.track`), and the
    /// first clip of a project opened from a movie (spec §1).
    func addClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let media = try mediaArg(a, "media", document)
        let at = try timeArg(a, "at", document)
        return try editResult(
            document, "Add Clip", [.addClip(track: track.id, media: media.id, at: at)])
    }

    /// `add_text_clip` — Clip ▸ Add Text (`EditorViewController.addTextClip:`,
    /// M2). The default content and duration are the core's, so an omitted
    /// argument gives exactly what the menu gives.
    func addTextClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let text = newClipPatchArg(a, "text", shorthand: "content")
        return try editResult(
            document, "Add Text",
            [.addTextClipRaw(track: track.id, at: at, duration: duration, text: text)])
    }

    /// `add_shape_clip` — the toolbar's Add Shape menu
    /// (`EditorViewController.showAddShapeMenu:` → `addShapeClip:`, M2).
    ///
    /// `shape` is OPTIONAL, as the op table says: omitted, what lands is the
    /// core's default rectangle — the same clip the menu's Rectangle item
    /// makes. It used to be a required kind name here, which put the op's
    /// own default out of reach and left the box and the paint needing a
    /// following `set_shape`.
    func addShapeClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let shape = newClipPatchArg(a, "shape", shorthand: "kind")
        return try editResult(
            document, "Add Shape",
            [.addShapeClipRaw(track: track.id, at: at, duration: duration, shape: shape)])
    }

    /// `add_text_clip`'s `text` and `add_shape_clip`'s `shape`: the
    /// `set_text` / `set_shape` PATCH each op documents (`core/src/edit.rs`),
    /// forwarded to the core unread, with a bare string accepted as shorthand
    /// for `{"<shorthand>": …}` — `content` for the words of a title, `kind`
    /// for the geometry of a shape.
    ///
    /// **The shorthand is the one thing this reads**, and it is kept
    /// deliberately (spec kpgalligan/reelcut#1's Out of Scope): it cannot be
    /// ambiguous — a JSON string is never a JSON object, and there is only
    /// one thing a caller who writes bare words or a bare kind name can mean
    /// — and a string is what both tools declared for their whole lives, so
    /// no existing caller has to be rewritten. It PRODUCES a whole patch,
    /// which is then forwarded; it is not a lenient reading of one, and the
    /// value inside it is the core's to judge, so a bare `"square"` comes
    /// back as ``bad value at "kind" in a shape patch: unknown variant
    /// `square` `` rather than as a sentence written here.
    ///
    /// Everything else goes on whole, `Any` and not `[String: Any]`, so that
    /// a number or a list where the patch belongs is refused by the CORE in
    /// the words that name the group (`text patch must be a json object, not
    /// 5`). An explicit `null` goes on whole too, rather than being stripped
    /// here — `Option<Value>` reads one as ABSENT (`core/src/edit.rs`), which
    /// is the op envelope's rule for every optional argument, so the clip
    /// lands on the core's Title preset or its default rectangle. nil is the
    /// key being missing, and that is the only thing this answers about.
    private func newClipPatchArg(
        _ a: [String: Any], _ key: String, shorthand: String
    ) -> Any? {
        guard let raw = a[key] else { return nil }
        if let words = raw as? String { return [shorthand: words] }
        return raw
    }

    /// `insert_clip` — Edit ▸ Insert at Playhead
    /// (`EditorViewController.insertMediaAtPlayhead:`) and an ⌥-drop from the
    /// Media tab. The split, the room and the placement are ONE core op, so
    /// this is one undo step exactly as the menu command is.
    func insertClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let media = try mediaArg(a, "media", document)
        let at = try timeArg(a, "at", document)
        return try editResult(
            document, "Insert", [.insertClip(track: track.id, media: media.id, at: at)])
    }

    /// `overwrite_clip` — Edit ▸ Overwrite at Playhead
    /// (`EditorViewController.overwriteMediaAtPlayhead:`) and a ⇧⌥-drop from the
    /// Media tab.
    func overwriteClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let media = try mediaArg(a, "media", document)
        let at = try timeArg(a, "at", document)
        return try editResult(
            document, "Overwrite", [.overwriteClip(track: track.id, media: media.id, at: at)])
    }

    // MARK: - Moving and trimming

    /// `move_clip` — the timeline's clip drag (`ClipDragSession`). The overlap
    /// rule lives in the core, so a move that would stack three clips is a
    /// refusal with a message rather than something to check here.
    func moveClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let delta = try timeArg(a, "delta", document)
        var track: TrackSnapshot?
        if let raw = a["track"], !(raw is NSNull) {
            track = try trackArg(a, "track", document)
        }
        return try editResult(
            document, "Move Clip", [.moveClip(clips: clips, delta: delta, track: track?.id)])
    }

    /// `trim_start` — dragging a clip's left edge (`TrimSession`) and W
    /// (`EditorViewController+Timeline.trimToPlayhead(.start)`).
    func trimStart(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let to = try timeArg(a, "to", document)
        return try editResult(document, "Trim Start", [.trimStart(clip: clip.id, to: to)])
    }

    /// `trim_end` — dragging a clip's right edge, and E.
    func trimEnd(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let to = try timeArg(a, "to", document)
        return try editResult(document, "Trim End", [.trimEnd(clip: clip.id, to: to)])
    }

    /// `rate_stretch` — ⌥-dragging a clip's END edge
    /// (`TrimSession.isRateStretch`). Media sources only; the core makes any
    /// other kind an ERROR rather than a refusal precisely so this call gets a
    /// message it can correct from (spec §6).
    func rateStretch(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let toEnd = try timeArg(a, "to_end", document)
        return try editResult(
            document, "Rate Stretch", [.rateStretch(clip: clip.id, toEnd: toEnd)])
    }

    /// `slip` — ⌥⇧-dragging a clip's BODY (`SlipSession`). `delta` is
    /// timeline ticks and the source moves by `delta × speed`; the clip does
    /// not move at all. A source with no window to slip is an ERROR rather
    /// than a refusal, for the reason `rate_stretch`'s is (spec §6).
    func slip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let delta = try timeArg(a, "delta", document)
        return try editResult(document, "Slip", [.slip(clip: clip.id, delta: delta)])
    }

    /// `roll` — ⌥⇧-dragging a clip's EDGE (`RollSession`). The predecessor is
    /// whatever ends exactly at this clip's start; with a gap or an overlap
    /// there instead, the core refuses and the caller gets its sentence
    /// (spec §11 #88).
    func roll(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let to = try timeArg(a, "to", document)
        return try editResult(document, "Roll", [.roll(clip: clip.id, to: to)])
    }

    /// `split` — ⌘K / T (`splitAtPlayheadCommand`). With no `clips` the core
    /// splits every unlocked clip under the playhead, which is what the menu
    /// command does with an empty selection; `at` defaults to the playhead for
    /// the same reason.
    func split(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try optionalClipsArg(a, "clips", document)
        let at = try optionalTimeArg(a, "at", document) ?? document.playhead
        return try editResult(document, "Split", [.split(clips: clips, at: at)])
    }

    // MARK: - Removing time

    /// `delete` — ⌫ (`deleteSelection`). The gaps stay.
    func deleteClips(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        return try editResult(document, "Delete", [.delete(clips: clips)])
    }

    /// `ripple_delete` — ⌘⌫ with a selection (`rippleDeleteSelection`).
    func rippleDelete(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        return try editResult(document, "Ripple Delete", [.rippleDelete(clips: clips)])
    }

    /// `ripple_delete_range` — ⌘⌫ with NO selection and an in/out range set,
    /// the other half of `rippleDeleteSelection`.
    func rippleDeleteRange(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let from = try timeArg(a, "from", document)
        let to = try timeArg(a, "to", document)
        guard to > from else {
            throw ToolError(message: "to must be after from (got \(from) and \(to)).")
        }
        return try editResult(
            document, "Ripple Delete", [.rippleDeleteRange(from: from, to: to)])
    }

    /// `ripple_delete_ranges` — the commit of Clip ▸ Remove Silences…
    /// (`SilenceSheetController`), which is where a caller gets forty cuts
    /// to make and needs them to be one undo step. Its undo name is that
    /// sheet's, "Remove Silences", on this path and on the menu's alike, so
    /// one assertion covers both.
    ///
    /// It is NOT N `ripple_delete_range` calls: the core merges the pairs —
    /// touching as well as overlapping — and cuts the survivors right to
    /// left, so two ranges that meet make one shift rather than two. The
    /// ranges are read exactly as any other time is, snapped to the frame
    /// grid, and a reversed pair is the same range.
    ///
    /// `detect_silence` produces the list this takes; nothing stops a caller
    /// writing its own.
    func rippleDeleteRanges(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        guard let ranges = try rangesArg(a, "ranges", document) else {
            throw ToolError(
                message: "Missing required argument: ranges (an array of [from, to] pairs, "
                    + "each a time in ticks). detect_silence returns them in this shape.")
        }
        // An empty list is the core's IDENTITY — "nothing to do" — which
        // says only that the project is already in that state. No rule
        // refused it, so the ARGUMENT is what is named here.
        guard !ranges.isEmpty else {
            throw ToolError(message: "ranges is empty — name at least one [from, to] pair.")
        }
        return try editResult(
            document, "Remove Silences", [.rippleDeleteRanges(ranges: ranges)])
    }

    /// `lift_range` — ⌫ with an in/out range and NOTHING selected
    /// (`deleteSelection`), the counterpart of `ripple_delete_range`'s ⌘⌫.
    func liftRange(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let from = try timeArg(a, "from", document)
        let to = try timeArg(a, "to", document)
        guard to > from else {
            throw ToolError(message: "to must be after from (got \(from) and \(to)).")
        }
        return try editResult(document, "Lift", [.liftRange(from: from, to: to)])
    }

    /// `insert_time` — the gap-opening edit of spec §4.4. It has no menu
    /// command of its own yet; the agent is its first caller, and the ops are
    /// the same ones a future insert gesture will build.
    func insertTime(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let at = try timeArg(a, "at", document)
        let length = try timeArg(a, "length", document)
        guard length > 0 else {
            throw ToolError(message: "length must be more than one frame of ticks.")
        }
        return try editResult(document, "Insert Time", [.insertTime(at: at, length: length)])
    }

    /// `close_gap` — double-clicking an empty span in a lane, and Clip ▸
    /// Close Gap with the playhead in one
    /// (`EditorViewController.closeGapAtPlayhead:`).
    func closeGap(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let at = try timeArg(a, "at", document)
        return try editResult(document, "Close Gap", [.closeGap(track: track.id, at: at)])
    }

    // MARK: - Speed and stills

    /// `set_speed` — Clip ▸ Speed… (`SpeedSheetController`) and the Speed section's Fit to.
    func setSpeed(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let rate = try doubleArg(a, "rate"), duration = try optionalTimeArg(a, "duration", document)
        if let rate, !(rate.isFinite && rate > 0) {
            throw ToolError(message: "rate must be a positive number (1 = normal speed).")
        }
        let keepPitch = try boolArg(a, "keep_pitch")
        return try editResult(document, "Speed", [
            .setSpeed(clip: clip.id, rate: rate, duration: duration, keepPitch: keepPitch)])
    }

    /// `set_reversed` — Clip ▸ Reverse. Media sources only, and nothing on the
    /// timeline moves: the core changes one boolean and the app substitutes a
    /// pre-rendered reversed asset for that media's segments (spec §11).
    ///
    /// `reversed` is required rather than a toggle on purpose: an agent that
    /// cannot see the current value would otherwise have to read the project
    /// back to know which way it just flipped it.
    func setReversed(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        guard let reversed = try boolArg(a, "reversed") else {
            throw ToolError(message: "reversed must be true or false.")
        }
        return try editResult(
            document, "Reverse", [.setReversed(clip: clip.id, reversed: reversed)])
    }

    /// `freeze_frame` — ⇧⌘F (`freezeSelection`): a split, an inserted gap, and
    /// a `still` clip filling it.
    func freezeFrame(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let at = try optionalTimeArg(a, "at", document) ?? document.playhead
        let duration = try optionalTimeArg(a, "duration", document)
        return try editResult(
            document, "Freeze Frame", [.freezeFrame(clip: clip.id, at: at, duration: duration)])
    }

    /// `detach_audio` — ⌥⌘D (`detachSelectionAudio`): the audio moves to its
    /// own clip on the track below, inserting one when there is none.
    func detachAudio(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        return try editResult(document, "Detach Audio", [.detachAudio(clip: clip.id)])
    }

    /// `duplicate` — ⌘D (`duplicateSelection`): copies land after the
    /// originals' span, ready for a `move_clip`.
    func duplicateClips(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        return try editResult(document, "Duplicate", [.duplicate(clips: clips)])
    }

    /// `paste` — ⌘V (`EditorViewController+Clipboard.pasteClips`). The app's
    /// Copy writes this payload to `NSPasteboard.general`; an agent builds one
    /// itself, which is why the catalog entry spells the two places it differs
    /// from `get_project`'s clips (a `track` is a depth, media travels by
    /// path). `at` defaults to the playhead, the way the menu command uses it.
    func pasteClips(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let at = try optionalTimeArg(a, "at", document) ?? document.playhead
        var track: TrackSnapshot?
        if let raw = a["track"], !(raw is NSNull) {
            track = try trackArg(a, "track", document)
        }
        let payload = try pastePayloadArg(a)
        return try editResult(
            document, "Paste", [.paste(at: at, track: track?.id, payload: payload)])
    }

    /// The Copy payload `paste` and `paste_attributes` both take, read the
    /// same way so the two tools cannot drift on what a payload is.
    ///
    /// The payload's own shape is the core's to police — `edit_paste.rs` names
    /// what was wrong in a message the call returns in band — so only the two
    /// things a model gets wrong before the core ever sees them are checked
    /// here: a payload that is not an object, and one with no clips in it
    /// (which `paste` answers with "no change", the least useful reply of the
    /// three, and `paste_attributes` with an error that names no key).
    private func pastePayloadArg(_ a: [String: Any]) throws -> [String: Any] {
        guard let payload = a["payload"] as? [String: Any] else {
            throw ToolError(
                message: "payload must be a JSON object — {\"clips\": [...], \"media\": [...]}, "
                    + "what Copy puts on the pasteboard.")
        }
        guard let clips = payload["clips"] as? [Any], !clips.isEmpty else {
            throw ToolError(
                message: "payload.clips must be a non-empty array of clip objects, each with a "
                    + "track DEPTH (0 = front-most) in place of its track id.")
        }
        return payload
    }

    /// `paste_attributes` — ⌥⌘V, Edit ▸ Paste Attributes
    /// (`EditorViewController+Clipboard.pasteAttributes`), which sends no
    /// `groups` and gets the default (each of video, audio, text and shape
    /// both clips have), and Edit ▸ Paste Graphic Properties
    /// (`pasteGraphicProps`): `groups: ["graphic"]` with `skip_missing`. The
    /// payload's EARLIEST clip is read; each group replaces the target's.
    ///
    /// `groups` is checked here against the five names, because the core
    /// refuses a misspelt one as serde's envelope error, which names the
    /// variant but not the argument; an EMPTY list is refused too, since the
    /// core answers it "no change". What travels, what a target keeps and
    /// its "clip N has no … properties" errors are the core's
    /// (`edit_paste_attributes.rs`), in band, as `paste`'s are.
    func pasteAttributes(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let payload = try pastePayloadArg(a)
        let groups = try stringsArg(a, "groups")
        let skip = try boolArg(a, "skip_missing")
        let known = Self.attributeGroups.joined(separator: ", ")
        if let groups = groups {
            guard !groups.isEmpty else {
                throw ToolError(
                    message: "groups is empty — name at least one of \(known), or leave it "
                        + "out to paste each of video, audio, text and shape both clips have.")
            }
            if let unknown = groups.first(where: { !Self.attributeGroups.contains($0) }) {
                throw ToolError(
                    message: "groups contains \"\(unknown)\" — each must be one of \(known).")
            }
        }
        return try editResult(
            document, "Paste Attributes",
            [.pasteAttributes(clips: clips, payload: payload, groups: groups, skipMissing: skip)])
    }

    // MARK: - Grouping

    /// `nest` — ⌘G (`EditorViewController+Nest.nestSelection`). The core
    /// decides the track, the span and the nest's canvas; the only thing
    /// checked here is the one argument it cannot answer usefully for, an
    /// empty `clips` list, which `clipsArg` already refuses.
    func nestClips(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let name = try stringArg(a, "name")
        return try editResult(document, "Nest", [.nest(clips: clips, name: name)])
    }

    /// `unnest` — ⇧⌘G (`EditorViewController+Nest.unnestSelection`).
    ///
    /// The "not a nest clip" case is left to the core rather than pre-checked
    /// against the snapshot: it is the core's error to word, and a check here
    /// would be a second copy of the rule that could drift from it. What IS
    /// checked is the id, through `clipArg`, so an unknown one is named the
    /// same way every other clip argument names it.
    func unnestClips(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        return try editResult(document, "Un-nest", [.unnest(clip: clip.id)])
    }

    // MARK: - Properties

    /// `set_video` — the Video tab (`VideoPane` through `InspectorBinding`)
    /// and every canvas gesture (`CanvasMoveSession` and its siblings).
    ///
    /// **The inspector's redirect is deliberately NOT mirrored here**: with
    /// an action SELECTED (spec §11 CI-2) the panes — and, since CI-13, the
    /// canvas gestures — write `set_action_end` instead, because that is
    /// what editing an action's end state means. The agent still chooses —
    /// `set_video` changes the clip's BASE props, `set_action_end` an
    /// action's end state.
    ///
    /// **The patch goes to the core UNREAD** (deepening D1·3,
    /// `archive/reelcut-roadmap-7.md` §2.3). Decoding the object into a
    /// `VideoPatch`, checking an allowed-key set, reading `motion` by hand
    /// and checking four closed enums are all `core/src/patch.rs`'s now, and
    /// its refusals name the dotted path (array indices included) and the
    /// value sent. Two things an agent sees change with it: a nested object
    /// MERGES where the decode-and-re-encode replaced it (a one-key `shadow`
    /// patch keeps the colour and the offset, a `motion` naming only `in`
    /// keeps the stored `out`), and a colour must be four numbers, since
    /// nothing fills in an alpha on the way past any more.
    ///
    /// What is left is what the core cannot know: which document, which
    /// clips, and that `patch` was passed at all.
    func setVideo(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try rawPatchArg(a, "patch")
        return try editResult(
            document, "Video Properties", [.setVideoRaw(clips: clips, patch: patch)])
    }

    /// `set_audio` — the Audio tab (`AudioPane`) and the timeline's fade
    /// handles (`FadeHandleSession`).
    ///
    /// **The patch goes to the core UNREAD**, as `set_video`'s does (D1·4
    /// after D1·3, `archive/reelcut-roadmap-7.md` §2.4). Its group holds no
    /// enum at all, so what the forwarding buys here is the nested object: a
    /// `duck` or a `compressor` MERGES now instead of being replaced from
    /// defaults, and a misspelt key inside one is
    /// `unknown key "duck.levl" in an audio patch` instead of a dropped key
    /// and a duck the caller did not write.
    func setAudio(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try rawPatchArg(a, "patch")
        return try editResult(
            document, "Audio Properties", [.setAudioRaw(clips: clips, patch: patch)])
    }

    /// `set_text` — the Text tab (`TextPane`) and the canvas's inline text
    /// editing (`PreviewCanvasView.commitTextEditing`).
    ///
    /// **The patch goes to the core UNREAD** (D1·4). The one closed
    /// vocabulary this door used to check by hand went with it — `bad value
    /// at "animation.kind" in a text patch: unknown variant `fade`` is the
    /// core's sentence now — and so did
    /// the alpha `withOpaqueColors` used to fill into a three-component
    /// `color`, `outline.color` or `backdrop.color`. The animation's `in` and
    /// `out` are snapped to the frame grid by the core (D1·2), which is the
    /// same promise the inspector's own stepper made.
    func setText(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try rawPatchArg(a, "patch")
        return try editResult(
            document, "Text Properties", [.setTextRaw(clips: clips, patch: patch)])
    }

    /// `set_shape` — the Shape tab (`ShapePane`) and the canvas's endpoint and
    /// box handles (`CanvasEndpointSession`, `CanvasScaleSession`).
    ///
    /// **The patch goes to the core UNREAD** (D1·4), and this is the door
    /// that lost the most: `shapePatchArg` read all eleven keys by hand,
    /// three-state `stroke` and `fill` included, and `gradientArg` read the
    /// gradient and every stop under it, because `ShapePatch` is the one
    /// patch that is not `Codable`. The core walks all of it against
    /// `ShapeProps`' own template, so `gradient.stops[1].att` is named by its
    /// INDEX and the three-component stop colour that reader accepted is
    /// refused by length.
    func setShape(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try rawPatchArg(a, "patch")
        return try editResult(
            document, "Shape Properties", [.setShapeRaw(clips: clips, patch: patch)])
    }

    /// `set_clip` — the clip's own name and label: the inline rename over the
    /// timeline's name strip (double-click, `TimelineView+Rename.swift`), the
    /// Clip tab's header field (`ClipSelectionHeaderView` in `ClipPane.swift`,
    /// where a name is also CLEARED — the inline editor drops an empty
    /// commit), Clip ▸ Rename… ⇧⌘R and Clip ▸ Label ▸
    /// (`EditorViewController+Identity.swift`).
    ///
    /// **The patch goes to the core UNREAD** (D1·4). Both keys are
    /// three-state strings (`ClipPatch`), and for a `String??` field a value
    /// of the wrong type decodes as `.some(nil)` — a CLEAR — which is why
    /// this door needed a hand check of its own that `patchArg` could not
    /// make (measured: `{"label": 7}` read as "remove the label"). The core
    /// reads the two keys itself and answers `"label" in a clip patch must be
    /// a string or null, not 7`. The label's VALUE is still not policed: the
    /// core stores a colour name unvalidated, the policy `add_marker`'s
    /// `color` already has, so a project from a newer build still opens here.
    func setClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try rawPatchArg(a, "patch")
        return try editResult(
            document, "Clip Properties", [.setClipRaw(clips: clips, patch: patch)])
    }

    /// `set_enabled` — the per-clip video/audio switches of spec §5.2, the two
    /// halves Detach Audio flips. No UI control carries them yet; the op is
    /// the same one `detach_audio` writes.
    func setEnabled(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let video = try boolArg(a, "video")
        let audio = try boolArg(a, "audio")
        guard video != nil || audio != nil else {
            throw ToolError(message: "set_enabled needs video, audio, or both.")
        }
        return try editResult(
            document, "Clip Enabled", [.setEnabled(clip: clip.id, video: video, audio: audio)])
    }

    /// `set_transition` — Clip ▸ Transition ▸ (`setTransitionKindCommand`) and
    /// the Video tab's transition row. The transition is INTO the clip and its
    /// duration is the overlap with the clip before it; `kind: null` clears
    /// it.
    func setTransition(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        guard let raw = a["kind"] else {
            throw ToolError(
                message: "set_transition needs kind — one of "
                    + TransitionKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                    + ", or null to clear it.")
        }
        var kind: TransitionKind?
        if !(raw is NSNull) {
            guard let name = raw as? String, let parsed = TransitionKind(rawValue: name) else {
                throw ToolError(
                    message: "kind must be one of "
                        + TransitionKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + ", or null.")
            }
            kind = parsed
        }
        return try editResult(
            document, kind == nil ? "Remove Transition" : "Set Transition",
            [.setTransition(clip: clip.id, kind: kind)])
    }

    /// `set_transition_duration` — the Video tab's transition length field.
    /// It MOVES the clip so the overlap equals `duration`, subject to the
    /// overlap rule, which is why a too-long value is a refusal.
    func setTransitionDuration(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let duration = try timeArg(a, "duration", document)
        guard duration > 0 else {
            throw ToolError(
                message: "duration must be positive — clear a transition with set_transition "
                    + "and kind null.")
        }
        return try editResult(
            document, "Transition Duration",
            [.setTransitionDuration(clip: clip.id, duration: duration)])
    }

}
