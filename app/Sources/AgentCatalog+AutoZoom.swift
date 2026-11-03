import Foundation

/// The catalog row of `auto_zoom` (spec §11 CU-76; road map "creator-jobs" CU7), spliced in
/// after the cursor rows by `creatorTools()`.
extension AgentServer {

    func autoZoomTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second"
        return [
            // It mirrors Clip ▸ Auto Zoom… (`AutoZoomSheetController`), one
            // undo step "Auto Zoom". No `scope` key: the clips are looked up
            // in the container set_scope has open.
            tool(
                "auto_zoom",
                "Plans screencast zooms from screen recordings' cursor files and applies them "
                    + "as ONE undo step \"Auto Zoom\" — Clip ▸ Auto Zoom…. Each zoom is an "
                    + "ordinary action (add_zoom_action's shape). A visit starts at a down click "
                    + "(or, with typing, a typing stretch, aimed at the last click before it): "
                    + "a zoom-in arriving lead seconds before it, a pan for each later click "
                    + "outside the zoomed region's inner 60 %, with follow a 0.5 s pan when the "
                    + "pointer stays outside the inner 70 % for 0.3 s, and a 0.8 s zoom back "
                    + "stay seconds after the last activity (or at a scroll burst). A click "
                    + "within stay of the last joins the visit; a zoom back that would end "
                    + "under 1 s before the next zoom-in becomes a pan. The region has the "
                    + "canvas's aspect at zoom × the clip's scale, kept inside the picture. "
                    + "Halves of a split are planned as one: every zoom back ends at the first "
                    + "half's placement, nothing straddles a cut, and a zoom held across a cut "
                    + "sets the later half's base (bases_set) unless it has an action of its "
                    + "own there, when the visit closes at the cut (closed_at_cut). A planned "
                    + "zoom meeting an action already on the clip is dropped (dropped); with "
                    + "replace the clips' existing zooms are removed first (replaced) and never "
                    + "any other action. Refused: a clip that is not a media clip, whose media "
                    + "has no cursor file or whose file is missing, that plays reversed, has no "
                    + "picture, or is placed smaller than the canvas (nest it and call "
                    + "auto_zoom inside the nest with set_scope). Answers visits, added, "
                    + "replaced, dropped, closed_at_cut, bases_set and actions [{clip, at, "
                    + "duration, kind}] (at in clip ticks; kind in, pan, follow or back); with "
                    + "nothing to zoom, ok with a note and no undo step.",
                [
                    "clip": [
                        "type": "integer",
                        "description": "A screen recording's media clip — exactly one of clip "
                            + "and clips.",
                    ],
                    "clips": [
                        "type": "array", "items": ["type": "integer"],
                        "description": "Media clips whose media have cursor files — exactly "
                            + "one of clip and clips.",
                    ],
                    "zoom": [
                        "type": "number",
                        "description": "How far in, × the clip's own scale: 1.25–4, 2 by "
                            + "default.",
                    ],
                    "lead": [
                        "type": "number",
                        "description": "Arrive this many seconds before the click: 0.2–2, "
                            + "0.6 by default.",
                    ],
                    "stay": [
                        "type": "number",
                        "description": "Stay this many seconds after the last activity: "
                            + "0.5–10, 2.5 by default.",
                    ],
                    "follow": [
                        "type": "boolean",
                        "description": "Follow the pointer while zoomed: true by default.",
                    ],
                    "typing": [
                        "type": "boolean",
                        "description": "Zoom on typing stretches too: true by default.",
                    ],
                    "replace": [
                        "type": "boolean",
                        "description": "Remove the clips' existing zooms first: false by "
                            + "default.",
                    ],
                    "from": [
                        "type": "integer",
                        "description": "Plan only clicks and typing at or after this "
                            + "container time, \(ticks); with replace, remove only zooms "
                            + "meeting [from, to).",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Plan only before this container time, \(ticks); "
                            + "must be after from.",
                    ],
                ]),
        ]
    }
}
