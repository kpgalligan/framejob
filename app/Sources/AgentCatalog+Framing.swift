import Foundation

/// The catalog row of `reframe_clip` (road map "creator-jobs" VR2a2 and VR2b1,
/// spec §11 VR-26…VR-28), spliced in last by `creatorTools()`, after
/// `switch_angle`'s. Its `subjects` is the app's to fill
/// (`AgentCatalog+Declarations.swift`), so the row describes the eight other
/// arguments.
extension AgentServer {

    func framingTools() -> [[String: Any]] {
        [
            // UI path: Clip ▸ Follow Subject… (road map creator-jobs VR2b2, spec §11
            // VR-29), this op with `replace: true` on each selected clip and a
            // "Backgrounds" track as `backdrop`. The tool fills `subjects` from the
            // analysis cache (AgentServer+Framing.swift).
            opTool(
                "reframe_clip",
                "Frames one clip on the current canvas — for a vertical or square version of "
                    + "a landscape recording. follow subject, face, person or salient follows "
                    + "what Frame Job finds in the clip on this Mac (faces, then people, then "
                    + "salient regions for subject): the window eases onto the subject and "
                    + "moves only when it leaves a dead zone, cuts hard at each shot change, "
                    + "holds a lost subject for 1 s and then follows another or eases over "
                    + "0.8 s to where_empty, returns once a subject has been seen for 0.6 s, "
                    + "and frames two people together when both fit. center holds the window "
                    + "on the picture's centre, fit shows the whole picture for the whole clip, "
                    + "and keep rescales the clip from the canvas it was made for "
                    + "(from_width × from_height) as Change Canvas does, its actions' "
                    + "positions and scales with it. The framing is composed into the clip: "
                    + "into its position and scale, and into every action end that moves or "
                    + "scales it, so an existing zoom or pan keeps working inside the new "
                    + "framing. Its moves are written as actions in the gaps between the "
                    + "clip's own actions, shifted up to 0.5 s earlier to clear one, or else "
                    + "carried by the action they overlap along that action's curve; a cut "
                    + "splits the action it lands in (a linear one plays exactly as before, "
                    + "an eased one is eased again on each side), except a speed action or "
                    + "one running past the clip's end, which carries the cut instead. "
                    + "replace first removes every position and scale from the clip's actions "
                    + "and fits the picture. One undo step, \"Reframe Clip\"; the answer's "
                    + "cached is false when an analysis ran first. The tool analyses the "
                    + "clip's window (± 1 s; shots, faces and subjects, as get_media_analysis "
                    + "does) and waits up to 60 s; past that nothing changes and the answer "
                    + "is analyzing {media, covered} with a note: the analysis carries on, so "
                    + "call reframe_clip again to apply. Refused, nothing changed, in this "
                    + "order: a follow other than keep on a text, shape, graphic or "
                    + "adjustment clip; a clip with no picture, or a crop or scale leaving "
                    + "none; a nest clip, then a still or image clip, with a following kind; "
                    + "unless keep, a clip on a matte track or cut by a matte, then a turned "
                    + "clip (a rotation, an action turning it, a spin); with backdrop "
                    + "where a copy would be made, a nest clip or a track not behind the "
                    + "clip's; last, a following kind with nothing found in the clip. Inside "
                    + "a nest (scope) the nest's canvas is the canvas. Clip ▸ Follow Subject… "
                    + "is this op with replace: true on each selected clip and a "
                    + "\"Backgrounds\" track as backdrop.",
                [
                    "clip": "The clip to frame: a clip with a picture, upright.",
                    "follow": "subject, face, person or salient (follow what is found), "
                        + "center, fit or keep.",
                    "zoom": "How tight, 1–4 times the scale that fills the canvas; default 1. "
                        + "Read by the following kinds and center; refused outside 1–4.",
                    "where_empty": "What a following kind shows where there is nothing to "
                        + "follow: fit (the whole picture, the default) or center.",
                    "from_width": "keep only: the width of the canvas the clip was placed "
                        + "on. Default the current canvas's.",
                    "from_height": "keep only: the height of the canvas the clip was placed "
                        + "on. Default the current canvas's.",
                    "backdrop": "A track behind the clip's for a blurred copy of it, made "
                        + "when the framing shows the whole picture anywhere (fit, or a "
                        + "following kind's fit spans). When that track is locked, a matte or "
                        + "holds a clip over the clip's span, the copy goes on a new back-most "
                        + "track instead. Absent: no copy. The copy keeps the clip's speed "
                        + "actions, so a ramped clip's copy shows the same frames.",
                    "replace": "true: before framing, remove x, y and scale from every action "
                        + "end on the clip (an action left with nothing is removed; volume and "
                        + "every other key stay) and fit the picture to the canvas, so the "
                        + "framing replaces the clip's own moves. Default false: the framing "
                        + "is composed into them. Not read by keep.",
                ]),
        ]
    }
}
