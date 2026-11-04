import Foundation

/// The catalog row of `reframe_clip` (road map "creator-jobs" VR2a2 and VR2b1,
/// spec §11 VR-26…VR-28), spliced in last by `creatorTools()`, after
/// `switch_angle`'s. Its `subjects` is the app's to fill
/// (`AgentCatalog+Declarations.swift`), so the row describes the eight other
/// arguments. Then `make_vertical_version` (road map "creator-jobs" VR3a, spec §11
/// VR-36), the tool that runs `reframe_clip` on every picture of a vertical copy, and
/// `relay_captions` (VR4a, VR-45), its caption step on its own.
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
            // UI path: File ▸ Make Vertical Version… (road map creator-jobs VR3b, spec §11
            // VR-39: EditorViewController+VerticalVersion.swift and
            // VerticalVersionSheetController.swift), spec §11 VR-30…VR-37. The step is
            // VerticalVersion.plan; the copy is ProjectDocument.verticalCopy; the handler
            // AgentServer+VerticalVersion.swift.
            tool(
                "make_vertical_version",
                "Makes a vertical (9:16), 4:5 or square (1:1) version of the top-level timeline "
                    + "— what File ▸ Make Vertical Version… does. The new canvas keeps the old "
                    + "short side, even (from 1920 × 1080: 1080 × 1920, 1080 × 1350, "
                    + "1080 × 1080). Each top-level clip with a picture is treated by what it "
                    + "is: a clip that fills the old frame on one side is reframed with "
                    + "reframe_clip from the old canvas (a movie clip follows its subject with "
                    + "follow, shown whole on a blurred copy where nothing is found; a still "
                    + "picture or a nest is centred); a clip the core will not frame (on a "
                    + "matte track, rotated, spinning) and a movie whose file is missing are "
                    + "kept as placed and listed; a graphic exactly the old canvas's size is "
                    + "re-sized to the new canvas (set_graphic), its position and its action "
                    + "ends' positions by the two sides' ratios, its scale kept; every other "
                    + "clip (a title, a picture-in-picture, a shape, a graphic of another size) "
                    + "is kept as placed, rescaled from the old canvas; an existing \"Blurred Background\" copy is removed when its "
                    + "clip is followed, else re-filled; a full-frame shape plate or an image "
                    + "named \"Background\" is re-filled. The blurred copies go on a new "
                    + "\"Backgrounds\" track at the back, removed when none is needed. With "
                    + "copy (the default) a NEW project opens, named \"<name> (9:16)\", "
                    + "\"(4:5)\" or \"(1:1)\", holding the step as its one undo step \"Make "
                    + "Vertical\" and carrying the project's caches and analysis; the project "
                    + "you name never changes. With copy false the step is applied to the "
                    + "project you name as one undo step \"Make Vertical\". The tool analyses "
                    + "the movie clips on this Mac first (as reframe_clip does) and waits up to "
                    + "60 s; past that nothing is made and the answer is analyzing {media, "
                    + "covered} with a note: call make_vertical_version again. Refused, "
                    + "nothing made: inside a nest; path without copy; a path another open "
                    + "project holds or where anything exists; a shape the canvas already has; "
                    + "the core's own sentence for the canvas, the Backgrounds track or a clip "
                    + "even keep cannot reframe. Answers {ok, canvas {width, height}, cached "
                    + "(false when an analysis ran), clips [{clip, treatment (followed, whole, "
                    + "kept, refilled, removed, resized or not_followed), reason?}], "
                    + "backgrounds, more_tracks, re_eased, moves_carried, summary, captions "
                    + "{relaid, kept} (as relay_captions answers them; absent with captions "
                    + "false), graphics {resized, updated [names], listed [{name, reason}]}, "
                    + "project, and for a copy carried {files, bytes, seconds} and saved (with "
                    + "path)}. With captions (the default) each word caption track is re-paged "
                    + "on the new canvas from its own words, as relay_captions does, and a "
                    + "caption track it cannot re-lay is kept as placed and listed. In a copy, "
                    + "the project's own older copies of the bundled lower-third, title-card, "
                    + "callout, bar-chart, counter and kinetic-type templates (known by their "
                    + "text, not their name) are rewritten with the current template, which "
                    + "fits a tall canvas, the old text kept as the module's previous revision "
                    + "(updated); with copy false nothing is rewritten and they are listed. A "
                    + "module that sizes itself by the canvas's height is listed either way.",
                [
                    "shape": [
                        "type": "string", "enum": VerticalShape.allCases.map(\.rawValue),
                        "description": "The new shape: 9:16, 4:5 or 1:1.",
                    ],
                    "follow": [
                        "type": "string",
                        "enum": FollowSubject.follows.map(\.rawValue),
                        "description": "What a movie clip follows: subject (the default), face, "
                            + "person or salient, or center to hold the picture's centre.",
                    ],
                    "zoom": [
                        "type": "number",
                        "description": "How tight, 1–4 times the scale that fills the new "
                            + "canvas; default 1.",
                    ],
                    "where_empty": [
                        "type": "string", "enum": FramingWhereEmpty.allCases.map(\.rawValue),
                        "description": "What a followed clip shows where nothing is found: fit "
                            + "(the whole picture on a blurred copy, the default) or center.",
                    ],
                    "copy": [
                        "type": "boolean",
                        "description": "true (the default): open the version as a new project. "
                            + "false: apply it to the project you name.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "With copy only: where to save the new project, an "
                            + "absolute path; .framejob is added when missing. Nothing may "
                            + "exist there yet. Without it the copy opens untitled.",
                    ],
                    "captions": [
                        "type": "boolean",
                        "description": "true (the default): re-page each word caption track "
                            + "on the new canvas from its own words. false: leave the caption "
                            + "tracks to you, kept as placed like any other clip.",
                    ],
                ], required: ["shape"]),
            // UI path: File ▸ Re-lay Captions for This Canvas (road map creator-jobs VR4a,
            // spec §11 VR-45: EditorViewController+RelayCaptions.swift). The plan is
            // CaptionRelayout.plan; the handler AgentServer+VerticalVersion.swift.
            tool(
                "relay_captions",
                "Re-lays the word captions for the current canvas — what File ▸ Re-lay "
                    + "Captions for This Canvas does — after set_canvas, or for captions laid "
                    + "on another canvas. It acts in the container set_scope has open (the "
                    + "timeline, or the open nest at the nest's size). Every track named "
                    + "Captions or Captions N holding only text clips is looked at: a track "
                    + "whose pages are all in one caption style Frame Job makes (Highlight, "
                    + "Pill, Karaoke, Build or One Word, with its slide, fill and dim looks; "
                    + "recognised by the page's font and word_style) is re-paged from the "
                    + "words its pages hold — every hand correction kept — by the same pager "
                    + "that made them, each page staying inside its clip, then put back at "
                    + "the same place in the stack with the same name, hidden and locked as "
                    + "before. A track is kept as placed, and listed with its reason, when it "
                    + "is a matte track, holds a page with no word timings (Subtitles pages "
                    + "included), holds a page none of whose words starts inside it, holds a "
                    + "page in a style Frame Job does not make, has pages in more than one "
                    + "style, or would not fit (the clip ceiling). One undo step \"Re-lay "
                    + "Captions\". Refused with nothing to re-lay: \"relay_captions found no "
                    + "caption track it can re-lay: \" and each kept track with its reason. "
                    + "Answers {ok, relaid [{track (the new track), replaced (the old one), "
                    + "name, style, pages}], kept [{track, name, reason}], project}.",
                [:]),
        ]
    }
}
