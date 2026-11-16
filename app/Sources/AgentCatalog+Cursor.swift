import Foundation

/// The catalog rows of `set_media_cursor` and `get_cursor_events` (spec §11
/// CU-50, CU-53; road map "creator-jobs" CU5), spliced in last by
/// `creatorTools()`.
extension AgentServer {

    func cursorTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second"
        return [
            // It mirrors the Media tab's Cursor section ▸ Locate… and Remove
            // (`MediaPane+Cursor.swift`), one undo step each.
            opTool(
                "set_media_cursor",
                "Attaches, moves or removes a screen recording's cursor file — the .fjcursor "
                    + "Frame Job writes beside each recorded movie, from which it draws the "
                    + "pointer, its clicks and its path — the Media tab's Cursor section ▸ "
                    + "Locate… (undo \"Locate Cursor File\") and Remove (\"Remove Cursor "
                    + "File\"). cursor is {path, bookmark?, in_picture}, the media's cursor "
                    + "as get_project shows it, or null to forget the file (the file itself is "
                    + "kept). The file is checked as Locate… checks it: it must open as a "
                    + "cursor file, its movie_size must be the movie's width × height, and "
                    + "in_picture must be the file's own (true when the movie's picture "
                    + "already shows the pointer), each refused in its own sentence. Refused "
                    + "too: an empty path, and a media that is not a video with a picture. "
                    + "Consolidate Media copies the file into the package beside its movie, "
                    + "and opening a moved package finds it there.",
                [
                    "media": "The video media's id.",
                    "cursor": "{path, bookmark?, in_picture}, or null to remove it.",
                ]),
            // A read with no menu: nothing in the app lists a recording's
            // events. No `scope` key; a clip is looked up in the container
            // set_scope has open, as get_media_analysis looks it up.
            tool(
                "get_cursor_events",
                "Answers what a screen recording's cursor file holds — its clicks, scrolls, "
                    + "shortcuts, typing stretches and, asked for, its path — read ON THIS MAC "
                    + "from the media's .fjcursor (get_project's media[].cursor). With media, "
                    + "times are the file's own SOURCE ticks (time \"media\"); with clip, "
                    + "they are ticks from the clip's start (time \"clip\", through its speed "
                    + "and ramp), and each click and scroll also has q [qx, qy]: its position "
                    + "in the clip's region frame — an offset in source pixels from the center "
                    + "of the clip's cropped picture, the frame add_zoom_action's region "
                    + "takes, so a region around a click is {x: qx, y: qy, w, h}. x and y are "
                    + "the movie's own pixels from its top-left; size is [w, h]. clicks "
                    + "[{t, button (0 left, 1 right, 2 other), down (1 press, 0 release), "
                    + "count, x, y, q?}], scrolls [{t, x, y, dx, dy (points), q?}] (each a "
                    + "single wheel event), shortcuts [{t, keys, code}], typing [{from, to, "
                    + "marks}] (stretches of typing, each overlapping the window), path "
                    + "{smoothing, t, x, y} sampled 10 times a second at the clip's smoothing "
                    + "(0 for media) unless smoothing is given. Rows of every kind and path "
                    + "samples count together: an answer holds at most "
                    + "\(CursorEventsAnswer.pageSize), and next is then the first time left "
                    + "out — call again with from: next. A clip that plays reversed is "
                    + "refused (ask with its media), as is a media with no cursor file or "
                    + "one whose file is missing. It edits nothing and makes no undo step.",
                [
                    "media": [
                        "type": "integer",
                        "description": "The recording whose events to read, in its own source "
                            + "ticks — exactly one of media and clip.",
                    ],
                    "clip": [
                        "type": "integer",
                        "description": "A media clip of a recording: its events in clip time, "
                            + "with q — exactly one of media and clip.",
                    ],
                    "from": [
                        "type": "integer",
                        "description": "Where to start, \(ticks), in the answer's time: 0 by "
                            + "default.",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Where to stop (not included), \(ticks): the media's or "
                            + "the clip's duration by default; must be after from.",
                    ],
                    "kinds": [
                        "type": "array",
                        "items": [
                            "type": "string",
                            "enum": CursorEventsAnswer.Kind.allCases.map(\.rawValue),
                        ],
                        "description": "Which to answer: clicks, scrolls, shortcuts and typing "
                            + "by default; add path for the pointer's path.",
                    ],
                    "smoothing": [
                        "type": "number",
                        "description": "The path's smoothing, 0–1 (path only): the clip's own "
                            + "Cursor ▸ Smoothing by default, else 0, the raw path.",
                    ],
                ]),
        ]
    }
}
