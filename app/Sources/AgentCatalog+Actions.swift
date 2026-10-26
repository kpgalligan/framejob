import Foundation

// MARK: - Catalog: actions

/// The catalog's six ACTION rows — `add_action`, `add_zoom_action`,
/// `add_speed_ramp`, `set_action`, `set_action_end` and `remove_action` — the
/// tools that animate
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
                    + "zoom, and what the canvas's Z mode and the Zoom to Region button in "
                    + "the Clip tab's action lane both send. Over `duration` starting at `at`, the clip's scale, x and y "
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
                "add_speed_ramp",
                "Makes a speed ramp preset on a MEDIA clip in one step, out of ordinary speed "
                    + "actions (actions whose end names a speed) — what Clip ▸ Speed Ramp… "
                    + "sends. ramp_up and ramp_down are ONE action over the span, ramping from "
                    + "the base rate (the rate the clip plays at `from` before the edit, which "
                    + "after an earlier speed action is that action's end rate) to `rate` and "
                    + "holding it after. speed_dip and speed_burst are TWO actions: one ramping "
                    + "to `rate` at the start of the span and one ramping back to the base rate "
                    + "at its end, holding `rate` between them for `hold` of the span. Up and "
                    + "burst need a rate above the base rate, down and dip one below it. `from` "
                    + "and `to` are CLIP time, measured from the clip's own start; give both or "
                    + "neither (the whole clip). The clip keeps its start and length and plays "
                    + "more or less source. Refused when the span runs past the clip's end, when "
                    + "it overlaps any action on the clip (one inside a dip's or a burst's hold "
                    + "included), for a dip or a burst under two frames, for a rate on the wrong "
                    + "side of the base rate, and when the clip would read past the end of its "
                    + "media, naming the largest rate that fits. One undo step; the new actions' "
                    + "ids come back as new_actions. Above ×12 the clip's audio is left out, and "
                    + "the answer carries audio_left_out and audio_note. "
                    + "Captions on a Captions track wholly inside a clip with sound are "
                    + "re-timed with it in the same step: captions_retimed lists them, and "
                    + "captions_removed those whose speech it no longer plays.",
                [
                    "clip": clipDescription,
                    "shape": "ramp_up, ramp_down, speed_dip or speed_burst.",
                    "rate": "The target rate (1 = normal speed), clamped to ×0.1–×1000; "
                        + "above the base rate for ramp_up and speed_burst, below it for "
                        + "ramp_down and speed_dip.",
                    "from": "Where the span starts, in CLIP time, \(ticks) Give it with `to`.",
                    "to": "Where the span ends, in CLIP time, \(ticks) Give it with `from`; "
                        + "both absent is the whole clip.",
                    "curve": "How every new action eases. Default ease_in_out.",
                    "hold": "speed_dip and speed_burst only: how much of the span the hold at "
                        + "`rate` takes, 0 to 0.9 (clamped). Default 0.5; 0 makes the two ramps "
                        + "meet.",
                ]),
            opTool(
                "set_action",
                "Moves or re-times an action, or changes its easing curve. Same overlap checks "
                    + "as add_action. Refused when the action would then end past the clip's "
                    + "end and later than it ended before, so an action already running past "
                    + "the clip's end (a trim can leave one there) can still be re-curved, "
                    + "moved earlier or shortened. When the action's end names a speed, the "
                    + "change moves how much source the clip reads, and one that would read "
                    + "past the end of its media is refused, naming the latest clip end that "
                    + "fits. "
                    + "Captions on a Captions track wholly inside a clip with sound are "
                    + "re-timed with it in the same step: captions_retimed lists them, and "
                    + "captions_removed those whose speech it no longer plays.",
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
                    + "set_video / set_audio / set_text — a colour is FOUR numbers here too, and "
                    + "it ramps in OKLab with straight alpha, as a graphic colour does; "
                    + "video.chroma.key's three numbers do too. A "
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
                    + "blends in OKLab, as interpolateColors does, with straight alpha. A string, "
                    + "a boolean and an enum switch to the end's value when the action ENDS. An "
                    + "image (asset) prop switches to the end's image when the action ENDS; \"\" "
                    + "names no image there (null removes the prop from the end). A prop its "
                    + "module marks animate: false is refused: set it with set_graphic. A prop the clip "
                    + "holds no value for starts from the module's current default, written into "
                    + "the clip in the same undo step. "
                    + "graphic.props.<key>: null removes that prop from the end, "
                    + "graphic: null the whole group. get_project shows kinds beside props; the "
                    + "app writes it and ignores one you send, so an end read back can be sent "
                    + "again. While the module is missing or does not compile a prop value is "
                    + "refused (needs its module's schema) — get_graphic says why — and a null "
                    + "still removes. speed, a number beside the groups, is a MEDIA clip's rate "
                    + "(×0.1–×1000, clamped): the clip ramps from the rate in force to it along "
                    + "the curve and holds it after; the clip keeps its start and length and "
                    + "plays more or less source, and an end rate that would read past the end "
                    + "of its media is refused, naming the largest end rate that fits. speed: "
                    + "null removes it. Above ×12 the clip's audio is left out, and the answer "
                    + "carries audio_left_out and audio_note. With speed in the patch, "
                    + "captions on a Captions track wholly inside a clip with sound are "
                    + "re-timed with it in the same step: captions_retimed lists them, and "
                    + "captions_removed those whose speech it no longer plays.",
                [
                    "clip": clipDescription,
                    "action": "Action id.",
                    "patch": "{video?: {...}, audio?: {...}, text?: {...}, graphic?: {props: "
                        + "{...}}, speed?: number} — the properties the animation ends at.",
                    "off": "\"group.key\" paths (video.shadow, text.width) to switch OFF at the "
                        + "end — stored as null, where a null in patch removes. Optional keys "
                        + "only; never graphic.",
                ]),
            opTool(
                "remove_action",
                "Removes an animation span. The clip keeps its base properties. Removing one "
                    + "whose end names a speed is refused when the clip would then read past the "
                    + "end of its media, naming the latest clip end that fits. "
                    + "Captions on a Captions track wholly inside a clip with sound are "
                    + "re-timed with it in the same step: captions_retimed lists them, and "
                    + "captions_removed those whose speech it no longer plays.",
                ["clip": clipDescription, "action": "Action id."]),
        ]
    }
}
