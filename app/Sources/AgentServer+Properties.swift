import AppKit

/// The agent's eight property tools — `set_video`, `set_audio`, `set_text`,
/// `set_shape`, `set_clip`, `set_enabled`, `set_transition` and
/// `set_transition_duration`: the property rows of spec §6 (and of the op
/// table in the module doc of `core/src/edit.rs`), with the same names and
/// the same argument names.
///
/// A pure move out of `AgentServer+Clips.swift` (#333's toll), which stood
/// over app/CLAUDE.md's ~600-line cap. The seam is the one the file history
/// had named: `// MARK: - Properties` came here whole, with its bodies untouched.
extension AgentServer {

    // MARK: - Properties

    /// `set_video` — the Picture and Color sub-tabs (`VideoPane`, `InspectorBinding`)
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
    /// `archive/roadmap-7.md` §2.3). Decoding the object into a
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
    /// after D1·3, `archive/roadmap-7.md` §2.4). Its group holds no
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
    /// the Clip tab's Transition section's transition row. The transition is
    /// INTO the clip and its duration is the overlap with the clip before it;
    /// `kind: null` clears it.
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

    /// `set_transition_duration` — the Clip tab's Transition section's length
    /// field.
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
