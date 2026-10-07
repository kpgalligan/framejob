import Foundation

// MARK: - Catalog: actions

/// The catalog's five ACTION rows — `add_action`, `add_zoom_action`,
/// `set_action`, `set_action_end` and `remove_action` — the tools that animate
/// a clip, built with `opTool` as the clip rows beside them are.
///
/// A pure move out of `AgentCatalog+Clips.swift` (issue batch B87 phase 2),
/// which stood over app/CLAUDE.md's ~600-line cap with `set_action_end`'s
/// graphic prose to land. `// MARK: Actions` came here whole, with its rows
/// untouched, and so did the one hoisted local only they read,
/// `zoomRegionDescription`. `clipAndActionTools` appends these rows to its
/// array LAST, where the literal held them, so the catalog's order is
/// unchanged.
extension AgentServer {

    /// The action rows of `catalogJSON()`'s array, in its order.
    func actionTools(ticks: String, clipDescription: String) -> [[String: Any]] {
        // `add_zoom_action`'s region, the one argument whose own MEMBERS the
        // core declares and refuses by name (`core/src/edit_zoom.rs`), so the
        // four of them arrive printed, required and closed, and what is left
        // to say here is the frame they are measured in. The sentence says
        // what each member means, which is why the per-member descriptions
        // this hand-written property used to carry are not missed: a
        // region's members are part of a VALUE, not arguments of the op.
        let zoomRegionDescription =
            "The rectangle to zoom to, in SOURCE pixels: x and y are its "
            + "CENTRE measured from the centre of the clip's cropped rect — the frame "
            + "video.spotlight and video.obscure use — and width and height its size. "
            + "null is a zoom BACK to the clip's own scale and position; the key is "
            + "required so a forgotten rectangle cannot become that by accident."
        return [

            // MARK: Actions

            opTool(
                "add_action",
                "Adds an animation span to a clip: over `duration` starting at `at`, the clip's "
                    + "properties ease from whatever they are to the span's END state. The end "
                    + "state starts EMPTY — nothing changes until set_action_end fills it in. "
                    + "`at` is CLIP time, measured from the clip's own start, not the "
                    + "timeline's. Refused when it would overlap another action or run past the "
                    + "clip's end. The new action's id comes back as new_actions.",
                [
                    "clip": clipDescription,
                    "at": "Where the animation starts, in CLIP time, \(ticks)",
                    "duration": "How long it runs \(ticks) Default 1 s (600000).",
                ]),
            opTool(
                "add_zoom_action",
                "Adds an animation that zooms the picture to a rectangle — the screencast "
                    + "zoom, and what the canvas's Z mode and the Video tab's Zoom to Region… "
                    + "both send. Over `duration` starting at `at`, the clip's scale, x and y "
                    + "ease to the values that bring `region` to the canvas: `fit` shows the "
                    + "whole region, `fill` covers the whole canvas, both measured THROUGH the "
                    + "clip's rotation. `region: null` is a zoom BACK — the end state is the "
                    + "clip's own base scale, x and y. `at` is CLIP time, measured from the "
                    + "clip's own start. Rotation and crop are read from the clip as it is at "
                    + "`at`, and the scale is clamped to the layer maximum with the position "
                    + "computed from the clamped value, so a region too small to fill the "
                    + "canvas still lands centred. Refused when it would overlap another "
                    + "action or run past the clip's end; an error on a clip with no picture. "
                    + "The new action's id comes back as new_actions, and set_action_end adds "
                    + "to what the same action animates.",
                [
                    "clip": clipDescription,
                    "at": "Where the zoom starts, in CLIP time, \(ticks)",
                    "duration": "How long it runs \(ticks) Default 1 s (600000).",
                    "region": zoomRegionDescription,
                    "fit": "fit shows the whole region (the default); fill covers "
                        + "the whole canvas, cropping whatever the region's shape does not "
                        + "match.",
                    "curve": "How the zoom eases. Default ease_in_out, not linear: "
                        + "a zoom that starts and stops abruptly is the thing this exists "
                        + "to avoid.",
                ]),
            opTool(
                "set_action",
                "Moves or re-times an action, or changes its easing curve. Same overlap checks "
                    + "as add_action.",
                [
                    "clip": clipDescription,
                    "action": "Action id (get_project lists each clip's actions).",
                    "start": "New start in CLIP time, \(ticks)",
                    "duration": "New length, \(ticks)",
                    "curve": "How the values ease from start to end.",
                ]),
            opTool(
                "set_action_end",
                "Sets what an action animates TO. The patch is the action's end state and MERGES "
                    + "into it key by key at every depth (a one-key shadow keeps the rest of it); "
                    + "a key set to null is REMOVED from the end state, so that property stops "
                    + "being animated. Groups are video, audio and text, with the same keys as "
                    + "set_video / set_audio / set_text — a colour is FOUR numbers here too, and a "
                    + "bad key or value is refused by its path with the group in it "
                    + "(video.filters[1].kind), though values are NOT range-checked: an animation "
                    + "may aim past what a stored property could hold. Two keys are refused: "
                    + "video.motion, a preset anchored to the clip's two ends rather than a value "
                    + "to ramp between (set it with set_video), and text.words, whose times belong "
                    + "to speech. A GRAPHIC clip's props are a fourth group, graphic: {props: "
                    + "{<key>: <value>}}, keyed by its module's schema and checked as set_graphic "
                    + "checks them, min and max included, against the module as graphics/ holds it "
                    + "NOW; the app reads that schema, so never send one. A number and a colour "
                    + "ramp along the curve: a number arrives with decimals (64 to 129 is 96.5 "
                    + "halfway), so a module that needs a whole number rounds it, and a colour "
                    + "blends channel by channel with straight alpha. A string, a boolean and an "
                    + "enum switch to the end's value when the action ENDS. An image (asset) prop "
                    + "is refused: set it with set_graphic. A prop the clip holds no value for "
                    + "starts from the module's current default, written into the clip in the same "
                    + "undo step. graphic.props.<key>: null removes that prop from the end, "
                    + "graphic: null the whole group. get_project shows kinds beside props; the "
                    + "app writes it and ignores one you send, so an end read back can be sent "
                    + "again. While the module is missing or does not compile a prop value is "
                    + "refused (needs its module's schema) — get_graphic says why — and a null "
                    + "still removes.",
                [
                    "clip": clipDescription,
                    "action": "Action id.",
                    "patch": "{video?: {...}, audio?: {...}, text?: {...}, graphic?: {props: "
                        + "{...}}} — the properties the animation ends at.",
                    "off": "\"group.key\" paths (video.shadow, text.width) to switch OFF at the "
                        + "end — stored as null, where a null in patch removes. Optional keys "
                        + "only; never graphic.",
                ]),
            opTool(
                "remove_action",
                "Removes an animation span. The clip keeps its base properties.",
                ["clip": clipDescription, "action": "Action id."]),
        ]
    }
}
