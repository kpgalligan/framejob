import AppKit

/// The agent's six action tools — `add_action`, `add_zoom_action`,
/// `add_speed_ramp`, `set_action`, `set_action_end` and `remove_action`: the
/// action rows of
/// spec §6 (and of the op table in the module doc of `core/src/edit.rs`),
/// with the same names and the same argument names.
///
/// A pure move out of `AgentServer+Clips.swift` (issue batch B87 phase 2),
/// which stood over app/CLAUDE.md's ~600-line cap with `set_action_end`'s
/// graphic door to land. The seam is the one the file had already drawn:
/// `// MARK: - Actions` came here whole, with its bodies untouched.
extension AgentServer {

    // MARK: - Actions

    /// `add_action` — ⌥⌘K (`EditorViewController+Inspector`'s
    /// `addActionAtPlayheadCommand`) and the Clip tab's action lane's `+`.
    /// `at` is CLIP time, not project time: it is measured from the clip's own
    /// start (spec §5.4).
    func addAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        return try addedActionResult(
            document, clip, "Add Action",
            [.addAction(clip: clip.id, at: at, duration: duration)])
    }

    /// `add_zoom_action` — the canvas's `Z` rubber band
    /// (`ZoomRegionSession`, `EditorViewController+ZoomRegion.swift`) and the
    /// Clip tab's action lane, whose zoom-in button arms the same mode and
    /// whose zoom-out button ("Zoom Back") sends this with a null region.
    ///
    /// One op rather than `add_action` + `set_action_end` because the
    /// arithmetic that turns a rectangle into a scale and an offset belongs
    /// in the core (`core/src/edit_zoom.rs`'s module doc has the equation),
    /// and because a gesture must be one undo step.
    ///
    /// **`region` is REQUIRED here and optional in the op**, which is the one
    /// place the distinction can be made. The core's envelope reads an absent
    /// optional and an explicit null identically — the crate has no
    /// tri-state argument idiom, which `set_clip` settled in phase 2 — so a
    /// forgotten rectangle would silently become a zoom BACK, the opposite
    /// edit. Requiring the key means a caller says `null` on purpose.
    ///
    /// **The region goes to the core UNREAD** (deepening D1·5,
    /// `archive/roadmap-7.md` §2.5). It is the one op ARGUMENT that
    /// is a caller-authored object, and `edit_zoom.rs`'s `ZoomRegion` reads
    /// it the way a patch is read: an unknown member is named beside the four
    /// the region takes, a missing one is named (there is no defensible
    /// default for any of them), a wrong-typed one is named by its path, and
    /// a four-number LIST is refused rather than read positionally. The
    /// hand reader that used to do all of that member by member is gone with
    /// it.
    func addZoomAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let region = try zoomRegionArg(a, "region")
        let fit = try enumArg(a, "fit", ZoomFit.self)
        let curve = try enumArg(a, "curve", Curve.self)
        // The undo step's NAME is the one thing left that reads the region,
        // and it reads only whether it is a null: a zoom back and a zoom to
        // a rectangle are different edits to a person looking at the Edit
        // menu. What the object CONTAINS is the core's.
        return try addedActionResult(
            document, clip, region is NSNull ? "Zoom Back" : "Zoom to Region",
            [
                .addZoomActionRaw(
                    clip: clip.id, at: at, duration: duration, region: region, fit: fit,
                    curve: curve)
            ])
    }

    /// `add_speed_ramp` — Clip ▸ Speed Ramp… (`SpeedRampSheetController`,
    /// spec §11 SR-24): a speed ramp preset in one step. `from` and `to` are
    /// CLIP time, like `add_action`'s `at`.
    ///
    /// One op rather than `add_action` + `set_action_end` (SR-25), for
    /// `add_zoom_action`'s reasons: the base rate, the overlap and the rate
    /// that fits are the core's reads (D2-1), and a preset is one undo step.
    /// The undo step is named for the shape, as the sheet names it.
    func addSpeedRamp(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let shape = try requiredEnumArg(a, "shape", SpeedRampShape.self)
        guard let rate = try doubleArg(a, "rate") else {
            throw ToolError(message: "Missing required argument: rate")
        }
        let from = try optionalTimeArg(a, "from", document)
        let to = try optionalTimeArg(a, "to", document)
        let curve = try enumArg(a, "curve", Curve.self)
        let hold = try doubleArg(a, "hold")
        return try addedActionResult(
            document, clip, shape.displayName,
            [
                .addSpeedRamp(
                    clip: clip.id, shape: shape, rate: rate, from: from, to: to, curve: curve,
                    hold: hold)
            ])
    }

    /// The tail every action-adding tool shares: run the ops, then report the
    /// action the clip GAINED. Actions are not top-level ids, so
    /// `created(from:to:)` cannot see them, and the new one is the difference
    /// between the clip's action ids before and after.
    private func addedActionResult(
        _ document: ProjectDocument, _ clip: ClipSnapshot, _ actionName: String,
        _ ops: [ReelOp]
    ) throws -> String {
        let before = clip.actions.map { $0.id }
        // The landing is read BEFORE the edit, like `editResult`'s: how a call
        // was addressed is a fact about the CALL, and reading it back off a
        // view the edit could itself have moved would answer about the wrong
        // thing. It matters here for the same reason it matters there — under
        // phase 9's rule the ABSENCE of `scope` in a result means "this landed
        // on the document", so these two tools (`add_action`, `add_zoom_action`)
        // would otherwise report a nested edit as a document one.
        let landing = scopeLanding(ops, document)
        let snapshot = try performGroupedEdit(document, actionName, ops)
        // Read back through `idScope`, not the top level: inside a scope the
        // clip that just gained an action is one of the nest's, and the
        // timeline's array has never heard of it — which would answer with an
        // empty list and report no new action at all.
        let after = try idScope(document).clip(clip.id)?.actions.map { $0.id } ?? []
        var result: [String: Any] = ["ok": true, "clip": Int(clip.id)]
        let added = after.filter { !before.contains($0) }.map { Int($0) }
        if !added.isEmpty { result["new_actions"] = added }
        // Empty unless the edit took a clip with sound above the ceiling,
        // which only `add_speed_ramp` of these tools can (SR-21 (e)).
        result.merge(
            SpeedAudioDrop.answerFields(from: snapshot, to: document.project.snapshot)
        ) { _, new in new }
        result.merge(landing) { _, new in new }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// `add_zoom_action`'s `region`, forwarded to the core UNREAD — the
    /// argument half of `rawPatchArg`, and the same one line of judgement
    /// (deepening D1·5).
    ///
    /// It reads NOTHING about the value. The core's `ZoomRegion` is the one
    /// validator of what a region may be, and it answers with the member's
    /// own path (`bad value at "region.width": invalid type: string "wide",
    /// expected f64`), where the hand reader here read the four members one
    /// at a time and had to spell what a region takes itself. An explicit
    /// `NSNull` is forwarded as it was written: the op reads a `null` as
    /// absent and both mean a zoom BACK.
    ///
    /// **The ABSENT key is the one thing left**, and unlike `rawPatchArg`'s
    /// it is not merely a mistake about the call — it is the distinction the
    /// core cannot make. An absent optional and an explicit null are one
    /// thing to the envelope, so a forgotten rectangle would be a zoom back
    /// rather than an error; the handler above says why the tool draws a
    /// line the op does not.
    private func zoomRegionArg(_ a: [String: Any], _ key: String) throws -> Any {
        guard let raw = a[key] else {
            throw ToolError(
                message: "Missing required argument: \(key) — the rectangle to zoom to, as "
                    + "{x, y, width, height} in SOURCE pixels, where x and y are its CENTRE "
                    + "measured from the centre of the clip's cropped rect. Pass null to zoom "
                    + "BACK to the clip's own scale and position.")
        }
        return raw
    }

    /// `set_action` — the Clip tab's action lane: the selected action's
    /// Start, Length and Curve in its detail row, and dragging a band's body
    /// (move) or its outer 5 pt (resize) in that lane or on the timeline's
    /// action lane (spec §11 CI-11). An action running past its clip's end
    /// can be re-curved there (the detail row's Curve popup), moved earlier
    /// or shortened, never taken further out (spec §11 SR-22, #338).
    func setAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let action = try actionArg(a, "action", clip)
        let start = try optionalTimeArg(a, "start", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let curve = try enumArg(a, "curve", Curve.self)
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

    /// `set_action_end` — every inspector field written with an action
    /// SELECTED (spec §11 CI-2, `InspectorBinding.ops(video:for:)`). The patch
    /// is the action's END state, merged; a key set to null is REMOVED from
    /// it — the UI path of a null is a section header's Clear, a keyed row's
    /// × and its menu's "Remove from action N" (`InspectorBinding.clearOps`,
    /// spec §11 CI-9). A patch naming `speed` is the Clip tab's Speed section's
    /// Rate with the action selected (`VideoPane.rateOps`, spec §11 SR-21 (a)).
    ///
    /// **The patch goes to the core UNREAD** (deepening D1·5,
    /// `archive/roadmap-7.md` §2.5) — the LAST door of the six, and
    /// the one that used to check the most: `checkActionPatch` walked three
    /// allowed-key sets, `checkVideoEnums` and `checkTextEnums` ran here
    /// alone, and `patchArg`'s round trip decoded the whole thing through
    /// `ActionPatch`. The core walks it group by group now
    /// (`edit_action.rs`'s `check_end_patch` over `patch.rs`), so every
    /// refusal carries the group in its path — `unknown key
    /// "video.filters[1].kindd" in an action end patch` — and three things
    /// that used to LAND do not: a wrong-typed value one level down (a
    /// number where `shadow` belongs read as "clear the shadow"), a
    /// three-element colour (`withOpaqueColors` filled in the alpha), and a
    /// one-key nested object, which REPLACED what the end state held and now
    /// merges into it.
    ///
    /// Two refusals are still made away from `patch.rs` and both are about
    /// this OP: `video.motion` and `text.words` are not animation targets
    /// (`edit_action.rs`), and an empty patch is the core's identity answer
    /// rather than this side's "nothing to change".
    ///
    /// **`schema` is the app's to fill** (spec §11 G-34 (c), G-4). When the
    /// patch names `graphic` and the clip — found in the call's scope, so a
    /// nest's clip is the nest's — is a graphic clip, `graphicEndSchema`
    /// sends the CURRENT revision's schema of the module it is drawn by, read
    /// as `set_graphic` reads it. Otherwise none goes, and the core answers:
    /// `clip N is not a graphic clip` for any other clip (asked before the
    /// schema), and for a value whose module is missing or does not compile,
    /// `graphic.props.<key> needs its module's schema to animate, and none
    /// came with the op` — while a `null` still removes, so a stale key can
    /// leave an end whose module is broken. Nothing here writes a sentence of
    /// its own.
    func setActionEnd(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let action = try actionArg(a, "action", clip)
        let patch = try rawPatchArg(a, "patch")
        // `off` (CI-14) is the caller's own choice; its refusals are the core's.
        let off = try stringsArg(a, "off") ?? []
        let schema = graphicEndSchema(patch, clip, document)
        return try editResult(
            document, "Action End",
            [
                .setActionEndRaw(
                    clip: clip.id, action: action.id, patch: patch,
                    off: off, schema: schema)
            ])
    }

    /// The schema `set_action_end` sends with a graphic end patch: the
    /// CURRENT revision's, of the module `clip` is drawn by, read through
    /// `compiledModule` as `setGraphic` reads it — or nil when the patch
    /// names no `graphic` (any value, a `null` included), the clip is not a
    /// graphic, or the module is missing or does not compile. It never
    /// throws and reads nothing of the patch beyond the key's presence: what
    /// a missing schema means is the core's sentence to say (D2-1).
    func graphicEndSchema(
        _ patch: Any, _ clip: ClipSnapshot, _ document: ProjectDocument
    ) -> [String: Any]? {
        guard let fields = patch as? [String: Any], fields["graphic"] != nil,
            let name = clip.graphic?.name
        else { return nil }
        return try? compiledModule(named: name, document).schema
    }

    /// `remove_action` — the action lane's trash button, and ⌫ with an
    /// action selected.
    func removeAction(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clip = try clipArg(a, "clip", document)
        let action = try actionArg(a, "action", clip)
        return try editResult(
            document, "Remove Action", [.removeAction(clip: clip.id, action: action.id)])
    }

}
