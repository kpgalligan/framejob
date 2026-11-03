import Foundation

/// The catalog row of `switch_layout` (road map "creator-jobs" CO6, spec §11
/// CO-60…CO-66), spliced in by `creatorTools()` after `speed_up_typing`'s.
extension AgentServer {

    func layoutTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000. "
            + "Rounded to the project's frame grid."
        return [
            // It mirrors Clip ▸ Camera Layout ▸ (`switchCameraLayout` in
            // EditorViewController+Layout.swift): the menu sends this one op at
            // the playhead.
            opTool(
                "switch_layout",
                "Lays out a camera clip and the screen recording behind it at a time — what "
                    + "Clip ▸ Camera Layout ▸ and the Picture sub-tab's Layout section send at "
                    + "the playhead. One undo step, \"Camera Layout\". The answer's focus is the "
                    + "[x, y] sent as the camera crop's centre, or null when none was. corner "
                    + "puts the camera in a corner box (a quarter of the canvas "
                    + "wide, a third tall, 5 % in from the edges) square, rounded or as a "
                    + "circle, the screen at its full placement (as Add Clip places it); "
                    + "side_by_side puts the screen fitted in the left two-thirds and the "
                    + "camera cropped to fill the right third, with margins and a small "
                    + "radius; stacked puts the screen across the top and the camera filling "
                    + "the rest below; camera_full fills the canvas with the camera; "
                    + "screen_only hides the camera (opacity 0) where it is. Each role gets one "
                    + "layout action at `at` (all six of x, y, scale, crop, corner_radius and "
                    + "opacity), eased over 0.5 s by default; at a clip's first frame the "
                    + "layout becomes its base and a one-frame action marks the cut. A layout "
                    + "action already starting at `at` is replaced, and one still easing at "
                    + "`at` is shortened to end there. The layout HOLDS: every later clip on "
                    + "the camera's track, and on the screen's, that starts before the next "
                    + "switch on that track (or `through`, or the track's end) takes it as its "
                    + "base, keeping its own actions. Refused, nothing changed, naming the "
                    + "clip: a camera or screen with no picture or not playing at `at`, a "
                    + "screen not on a track behind the camera's, no screen for side_by_side "
                    + "or stacked, a nest clip as the camera for rounded or circle, and a "
                    + "clip in the reach holding a zoom or another action that moves it after "
                    + "`at` — a screen still at its full placement is not asked in corner, "
                    + "camera_full and screen_only, since its zooms keep playing. Send nest: "
                    + "true to nest that role's clips first, in the same step, so the layout "
                    + "moves the nest and the zoom stays inside it (refused when one of them is "
                    + "already laid out). Inside a nest (scope) the nest's canvas is the canvas.",
                [
                    "camera": "The camera clip's id: a clip with a picture playing at `at`.",
                    "screen": "The screen clip's id, on a track behind the camera's. Absent: "
                        + "the clip playing at `at` on the front-most visible, non-matte track "
                        + "behind the camera's; none lays out the camera alone (refused for "
                        + "side_by_side and stacked).",
                    "layout": "corner, side_by_side, stacked, camera_full or screen_only.",
                    "shape": "corner only: square (the default), rounded or circle.",
                    "corner": "corner only: bottom_right (the default), bottom_left, top_right "
                        + "or top_left.",
                    "at": "When the switch starts, in project time (the container's inside a "
                        + "scope), \(ticks)",
                    "duration": "How long the switch eases, \(ticks) Default 0.5 s (300000), "
                        + "clamped to the clip and to its next layout action.",
                    "curve": "How the switch eases. Default ease_in_out.",
                    "focus": "[x, y]: the point of the camera's picture a crop is centred on, "
                        + "in the camera MEDIA's source pixels from the picture's centre, y "
                        + "down; clamped inside the picture. Omitted or null, the tool fills it "
                        + "as the menu does: the mean centroid of the camera clip's person "
                        + "masks when they are cached for every frame it plays (analyze_cutout's "
                        + "centroid, less the media's centre), else nothing, which centres the "
                        + "crop. A filled focus is dropped when nest: true nests the camera, "
                        + "since the nest clip is not the media; a focus you send is sent as "
                        + "given.",
                    "nest": "true: nest a role's clips first when one of them zooms or moves "
                        + "after `at`, instead of refusing. Default false.",
                    "through": "Where the layout stops holding, \(ticks) After `at`; the "
                        + "reach ends there if it is earlier than the next switch.",
                ]),
        ]
    }
}
