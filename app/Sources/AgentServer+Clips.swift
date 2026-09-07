import AppKit

/// The agent's clip and action tools: one per row of the clip half of spec §6
/// (and of the op table in the module doc of `core/src/edit.rs`), with the
/// same name and the same argument names.
///
/// Every handler is the canonical shape — `target(a)`, validate the ids
/// against the snapshot, build the typed `ReelOp`, `performGroupedEdit`,
/// `jsonResult` — and carries a comment naming the UI path it mirrors
/// (app/CLAUDE.md's agent-parity rule). No op JSON is written here: the typed
/// builders in `ReelCore.swift` are the only place that spells one.
extension AgentServer {

    // MARK: - Patch vocabularies

    /// The keys each patch accepts, from the §5.2 property groups. Used to
    /// refuse an unknown key BY NAME rather than let the core's lenient serde
    /// drop it — a silently ignored typo leaves a model believing it made an
    /// edit it did not.
    static let videoPatchKeys: Set<String> = [
        "x", "y", "scale", "rotation", "opacity", "crop", "corner_radius", "shadow", "color",
        "chroma", "filters", "reflection", "spotlight",
    ]
    static let audioPatchKeys: Set<String> = [
        "volume", "muted", "fade_in", "fade_out", "duck", "mono", "keep_pitch", "pan",
        "compressor", "noise_reduction",
    ]
    static let textPatchKeys: Set<String> = [
        "content", "font", "size", "color", "align", "valign", "line_spacing", "tracking",
        "outline", "backdrop", "width",
    ]
    static let shapePatchKeys: Set<String> = [
        "kind", "width", "height", "stroke", "fill", "arrow_start", "arrow_end", "radius",
        "from", "to",
    ]
    /// The fifth patch's two keys: a clip's own name and its label
    /// (`ClipPatch`, spec §5.2's `name` and `label`).
    static let clipPatchKeys: Set<String> = ["name", "label"]

    /// The four property groups `paste_attributes` can be told to carry —
    /// `Group` in `core/src/edit_props.rs`, spelled as the wire spells it, in
    /// the order the core checks them (and so the order its range errors
    /// come back in). The catalog's `groups` enum reads this list, so the
    /// two cannot disagree.
    static let attributeGroups: [String] = ["video", "audio", "text", "shape"]

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
        let text = try textArg(a, "text")
        return try editResult(
            document, "Add Text",
            [.addTextClip(track: track.id, at: at, duration: duration, text: text)])
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
        let shape = try shapeArg(a, "shape")
        return try editResult(
            document, "Add Shape",
            [.addShapeClip(track: track.id, at: at, duration: duration, shape: shape)])
    }

    /// `add_text_clip`'s `text`: the `set_text` PATCH the op documents
    /// (`core/src/edit.rs`), with a bare string accepted as shorthand for
    /// `{"content": …}`.
    ///
    /// **Why keep the shorthand.** It cannot be ambiguous — a JSON string is
    /// never a JSON object, and `content` is the only thing a caller who
    /// writes bare words can mean — and a string is what this tool declared
    /// for its whole life, so no existing caller has to be rewritten to get
    /// the fix. What it replaces was worse than either half: the string was
    /// the ONLY accepted form, and the object the op documents was read with
    /// `stringArg`, which answered nil for it and dropped it in silence, so
    /// a fully specified title arrived as the Title placeholder.
    private func textArg(_ a: [String: Any], _ key: String) throws -> TextPatch? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        if let words = raw as? String { return TextPatch(content: words) }
        guard raw is [String: Any] else {
            throw ToolError(
                message: "\(key) must be the words, or a set_text patch object — e.g. "
                    + "\"Chapter One\" or {\"content\": \"Chapter One\", \"size\": 96}.")
        }
        return try patchArg(a, key, TextPatch.self, allowed: Self.textPatchKeys)
    }

    /// `add_shape_clip`'s `shape`, the same way: the `set_shape` patch the
    /// op documents, with a bare kind name as shorthand for `{"kind": …}` —
    /// which is the only form the tool used to take, and which the Add Shape
    /// menu still means.
    private func shapeArg(_ a: [String: Any], _ key: String) throws -> ShapePatch? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        if let name = raw as? String {
            guard let kind = ShapeKind(rawValue: name) else {
                throw ToolError(
                    message: "\(key) must be one of "
                        + ShapeKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + ", or a set_shape patch object (got \"\(name)\").")
            }
            return ShapePatch(kind: kind)
        }
        guard raw is [String: Any] else {
            throw ToolError(
                message: "\(key) must be a kind name, or a set_shape patch object — e.g. "
                    + "\"arrow\" or {\"kind\": \"arrow\", \"width\": 400}.")
        }
        return try shapePatchArg(a, key)
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
    /// there instead, the core refuses and the caller is told nothing
    /// changed.
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

    /// `set_speed` — Clip ▸ Speed… (`SpeedSheetController`). Media sources
    /// only, and the core clamps the rate to ×0.1–×10.
    func setSpeed(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        guard let rate = try doubleArg(a, "rate"), rate.isFinite, rate > 0 else {
            throw ToolError(message: "rate must be a positive number (1 = normal speed).")
        }
        return try editResult(
            document, "Speed",
            [.setSpeed(clip: clip.id, rate: rate, keepPitch: try boolArg(a, "keep_pitch"))])
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
    /// (`EditorViewController+Clipboard.pasteAttributes`): the payload's
    /// EARLIEST clip's property groups onto the selection (at one start the
    /// front-most, then the lower id), each group replacing the target's
    /// whole group. The menu command sends no `groups`, so it gets
    /// the default rule — every group both clips have.
    ///
    /// `groups` is checked here against the four names, because the core
    /// refuses a misspelt one as serde's envelope error, which names the
    /// variant but not the argument; an EMPTY list is refused too, since the
    /// core answers it with "no change" and a caller who wrote `[]` meant
    /// something. Which groups travel by default, what a target keeps, and
    /// the "clip N has no audio properties" refusals are the core's
    /// (`edit_paste.rs`) and come back in band, as `paste`'s do.
    func pasteAttributes(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let payload = try pastePayloadArg(a)
        let groups = try stringsArg(a, "groups")
        let known = Self.attributeGroups.joined(separator: ", ")
        if let groups = groups {
            guard !groups.isEmpty else {
                throw ToolError(
                    message: "groups is empty — name at least one of \(known), or leave it "
                        + "out to paste every group both clips have.")
            }
            if let unknown = groups.first(where: { !Self.attributeGroups.contains($0) }) {
                throw ToolError(
                    message: "groups contains \"\(unknown)\" — each must be one of \(known).")
            }
        }
        return try editResult(
            document, "Paste Attributes",
            [.pasteAttributes(clips: clips, payload: payload, groups: groups)])
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
    /// the playhead inside an action the panes write `set_action_end` instead,
    /// because that is what dragging a handle inside an animated span means.
    /// The agent says which it wants — `set_video` changes the clip's BASE
    /// props, `set_action_end` an action's end state.
    func setVideo(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try patchArg(a, "patch", VideoPatch.self, allowed: Self.videoPatchKeys)
        try Self.checkVideoEnums(a["patch"] as? [String: Any] ?? [:], "patch")
        guard !patch.isEmpty else {
            throw ToolError(message: "patch names nothing to change.")
        }
        return try editResult(document, "Video Properties", [.setVideo(clips: clips, patch: patch)])
    }

    /// The two string ENUMS a video patch can carry, checked by hand.
    ///
    /// `patchArg`'s round-trip test catches a value the patch could not read,
    /// but only at the top level, and its own doc says why it cannot recurse:
    /// one level down every field has a real default, so a value that decoded
    /// TO that default is indistinguishable from a value that was absent.
    /// `filters[].kind` and `spotlight.shape` are exactly that case and the
    /// worst version of it — `ProjectSnapshot` decodes both leniently, on
    /// purpose, so that a file naming a filter this build has never heard of
    /// still opens rather than blanking the whole project. The cost is that
    /// `{"kind": "glow"}` reaches the core as `blur`: not a nuance dropped but
    /// a DIFFERENT filter applied, and the caller told it worked (measured).
    ///
    /// So the closed sets are checked here, against the enums themselves —
    /// no new list to fall out of step with, and the refusal names the value.
    private static func checkVideoEnums(_ object: [String: Any], _ path: String) throws {
        if let filters = object["filters"] as? [[String: Any]] {
            let known = FilterKind.allCases.map { $0.rawValue }
            for (i, filter) in filters.enumerated() {
                guard let kind = filter["kind"] else { continue }
                guard let name = kind as? String, FilterKind(rawValue: name) != nil else {
                    throw ToolError(
                        message: "\(path).filters[\(i)].kind is not a filter — it must "
                            + "be one of " + known.joined(separator: ", ") + ".")
                }
            }
        }
        if let spotlight = object["spotlight"] as? [String: Any], let shape = spotlight["shape"] {
            let known = SpotShape.allCases.map { $0.rawValue }
            guard let name = shape as? String, SpotShape(rawValue: name) != nil else {
                throw ToolError(
                    message: "\(path).spotlight.shape is not a shape — it must be one of "
                        + known.joined(separator: ", ") + ".")
            }
        }
    }

    /// `set_audio` — the Audio tab (`AudioPane`) and the timeline's fade
    /// handles (`FadeHandleSession`).
    func setAudio(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try patchArg(a, "patch", AudioPatch.self, allowed: Self.audioPatchKeys)
        guard !patch.isEmpty else {
            throw ToolError(message: "patch names nothing to change.")
        }
        return try editResult(document, "Audio Properties", [.setAudio(clips: clips, patch: patch)])
    }

    /// `set_text` — the Text tab (`TextPane`) and the canvas's inline text
    /// editing (`PreviewCanvasView.commitTextEditing`).
    func setText(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try patchArg(a, "patch", TextPatch.self, allowed: Self.textPatchKeys)
        guard !patch.isEmpty else {
            throw ToolError(message: "patch names nothing to change.")
        }
        return try editResult(document, "Text Properties", [.setText(clips: clips, patch: patch)])
    }

    /// `set_shape` — the Shape tab (`ShapePane`) and the canvas's endpoint and
    /// box handles (`CanvasEndpointSession`, `CanvasScaleSession`).
    func setShape(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try shapePatchArg(a, "patch")
        guard !patch.isEmpty else {
            throw ToolError(message: "patch names nothing to change.")
        }
        return try editResult(document, "Shape Properties", [.setShape(clips: clips, patch: patch)])
    }

    /// `set_clip` — the clip's own name and label: the inline rename over the
    /// timeline's name strip (double-click, `TimelineView+Rename.swift`), the
    /// Clip tab's header field (`ClipSelectionHeaderView` in `ClipPane.swift`,
    /// where a name is also CLEARED — the inline editor drops an empty
    /// commit), Clip ▸ Rename… ⇧⌘R and Clip ▸ Label ▸
    /// (`EditorViewController+Identity.swift`).
    ///
    /// Read through `patchArg` like the other four patches, then one check of
    /// its own: both keys are three-state strings (`ClipPatch`), and
    /// for a `String??` field a value of the wrong type decodes as
    /// `.some(nil)` — a CLEAR — which the round trip in `patchArg` cannot
    /// tell from a real null (measured: `{"label": 7}` read as "remove the
    /// label"). The label's VALUE is not policed beyond its type: the core
    /// stores a colour name unvalidated, the policy `add_marker`'s `color`
    /// already has, so a project from a newer build still opens here.
    func setClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try patchArg(a, "patch", ClipPatch.self, allowed: Self.clipPatchKeys)
        try Self.checkClipPatchTypes(a["patch"] as? [String: Any] ?? [:], "patch")
        guard !patch.isEmpty else {
            throw ToolError(message: "patch names nothing to change.")
        }
        return try editResult(document, "Clip Properties", [.setClip(clips: clips, patch: patch)])
    }

    /// The type check `patchArg` cannot make for a `String??` field: each of
    /// the clip patch's keys, when present, is a string or null and nothing
    /// else. Runs AFTER `patchArg`, so an unknown key is still that function's
    /// error, named the same way it is for every other patch.
    private static func checkClipPatchTypes(_ object: [String: Any], _ path: String) throws {
        for key in clipPatchKeys.sorted() {
            guard let value = object[key], !(value is NSNull), !(value is String) else { continue }
            throw ToolError(
                message: "\(path).\(key) must be a string, or null to clear it.")
        }
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

    // MARK: - Actions

    /// `add_action` — ⌥⌘K (`EditorViewController+Inspector`'s
    /// `addActionAtPlayheadCommand`) and the Video tab's Add Action button.
    /// `at` is CLIP time, not project time: it is measured from the clip's own
    /// start (spec §5.4).
    func addAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let before = clip.actions.map { $0.id }
        try performGroupedEdit(
            document, "Add Action", [.addAction(clip: clip.id, at: at, duration: duration)])
        // Actions are not top-level ids, so `created(from:to:)` cannot see
        // them; the new one is whatever the clip gained.
        let after = document.project.snapshot.clip(clip.id)?.actions.map { $0.id } ?? []
        var result: [String: Any] = ["ok": true, "clip": Int(clip.id)]
        let added = after.filter { !before.contains($0) }.map { Int($0) }
        if !added.isEmpty { result["new_actions"] = added }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// `set_action` — dragging an action's band in the Video tab's action
    /// table, and its curve popup.
    func setAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let action = try actionArg(a, "action", clip)
        let start = try optionalTimeArg(a, "start", document)
        let duration = try optionalTimeArg(a, "duration", document)
        var curve: Curve?
        if let name = try stringArg(a, "curve") {
            guard let parsed = Curve(rawValue: name) else {
                throw ToolError(
                    message: "curve must be one of "
                        + Curve.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + " (got \"\(name)\").")
            }
            curve = parsed
        }
        guard start != nil || duration != nil || curve != nil else {
            throw ToolError(message: "set_action needs start, duration or curve.")
        }
        return try editResult(
            document, "Action",
            [
                .setAction(
                    clip: clip.id, action: action.id, start: start, duration: duration,
                    curve: curve)
            ])
    }

    /// `set_action_end` — every inspector field written while the playhead is
    /// inside an action (`InspectorBinding.ops(video:for:)`). The patch is the
    /// action's END state, merged; a key set to null is REMOVED from it.
    func setActionEnd(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let action = try actionArg(a, "action", clip)
        try checkActionPatch(a, "patch")
        let patch = try patchArg(
            a, "patch", ActionPatch.self, allowed: ["video", "audio", "text"])
        guard !patch.isEmpty else {
            throw ToolError(
                message: "patch names nothing to change — it takes video, audio and/or text "
                    + "objects, e.g. {\"video\": {\"scale\": 0.6}}.")
        }
        return try editResult(
            document, "Action End",
            [.setActionEnd(clip: clip.id, action: action.id, patch: patch)])
    }

    /// `remove_action` — the Video tab's action-row Remove button.
    func removeAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let action = try actionArg(a, "action", clip)
        return try editResult(
            document, "Remove Action", [.removeAction(clip: clip.id, action: action.id)])
    }

    // MARK: - Patch decoding

    /// The nested half of `set_action_end`'s validation: the top level is
    /// checked by `patchArg`, each group's keys here.
    private func checkActionPatch(_ a: [String: Any], _ key: String) throws {
        guard let object = a[key] as? [String: Any] else {
            throw ToolError(
                message: "\(key) must be a JSON object with video, audio and/or text groups, "
                    + "e.g. {\"video\": {\"opacity\": 0}}")
        }
        let groups: [(String, Set<String>)] = [
            ("video", Self.videoPatchKeys), ("audio", Self.audioPatchKeys),
            ("text", Self.textPatchKeys),
        ]
        for (name, allowed) in groups {
            guard let raw = object[name], !(raw is NSNull) else { continue }
            guard let nested = raw as? [String: Any] else {
                throw ToolError(message: "\(key).\(name) must be a JSON object.")
            }
            let unknown = nested.keys.filter { !allowed.contains($0) }.sorted()
            if let first = unknown.first {
                throw ToolError(
                    message: "Unknown \(key).\(name) key \"\(first)\" — allowed keys are "
                        + allowed.sorted().joined(separator: ", ") + ".")
            }
            // An action's end state carries the same video patch `set_video`
            // does, so it carries the same two lenient enums.
            if name == "video" { try Self.checkVideoEnums(nested, "\(key).\(name)") }
        }
    }

    /// `ShapePatch` is the one patch that is not `Codable` (it never appears
    /// inside an action's end patch — spec §5.4 covers video, audio and text
    /// only), so it is built by hand. `stroke` and `fill` are three-state, the
    /// way `ShapePatch` spells it: absent leaves the paint alone, null clears
    /// it, an object or a colour sets it.
    private func shapePatchArg(_ a: [String: Any], _ key: String) throws -> ShapePatch {
        guard let object = a[key] as? [String: Any] else {
            throw ToolError(
                message: "\(key) must be a JSON object of the shape properties to change, "
                    + "e.g. {\"kind\": \"arrow\"}")
        }
        let unknown = object.keys.filter { !Self.shapePatchKeys.contains($0) }.sorted()
        if let first = unknown.first {
            throw ToolError(
                message: "Unknown \(key) key \"\(first)\" — allowed keys are "
                    + Self.shapePatchKeys.sorted().joined(separator: ", ") + ".")
        }
        var patch = ShapePatch()
        if let name = try stringArg(object, "kind") {
            guard let kind = ShapeKind(rawValue: name) else {
                throw ToolError(
                    message: "kind must be one of "
                        + ShapeKind.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + " (got \"\(name)\").")
            }
            patch.kind = kind
        }
        patch.width = try doubleArg(object, "width")
        patch.height = try doubleArg(object, "height")
        patch.radius = try doubleArg(object, "radius")
        patch.arrowStart = try boolArg(object, "arrow_start")
        patch.arrowEnd = try boolArg(object, "arrow_end")
        if let raw = object["stroke"] {
            if raw is NSNull {
                patch.stroke = .some(nil)
            } else {
                guard let stroke = raw as? [String: Any], let width = try doubleArg(stroke, "width")
                else {
                    throw ToolError(
                        message: "stroke must be null or {\"width\": 6, \"color\": "
                            + "[r, g, b, a]}.")
                }
                patch.stroke = .some(
                    StrokeProps(width: width, color: try requiredColorArg(stroke, "color")))
            }
        }
        if let raw = object["fill"] {
            if raw is NSNull {
                patch.fill = .some(nil)
            } else {
                patch.fill = .some(try requiredColorArg(object, "fill"))
            }
        }
        patch.from = try unitPoint(object, "from")
        patch.to = try unitPoint(object, "to")
        return patch
    }

    /// A `from` / `to` endpoint: unit coordinates in the shape's box, for
    /// lines and arrows only (spec §5.2).
    private func unitPoint(_ object: [String: Any], _ key: String) throws -> [Double]? {
        guard let raw = object[key], !(raw is NSNull) else { return nil }
        guard let array = raw as? [Any], array.count == 2 else {
            throw ToolError(
                message: "\(key) must be [x, y] in unit coordinates of the shape's box "
                    + "(0,0 is its top-left corner).")
        }
        var point: [Double] = []
        for value in array {
            guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else {
                throw ToolError(message: "\(key) must contain two numbers.")
            }
            point.append(number)
        }
        return point
    }
}
