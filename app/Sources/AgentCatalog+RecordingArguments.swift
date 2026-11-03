import Foundation

/// `record_screen`'s arguments: each one's kind, bounds and description,
/// the properties `recordingTools()` publishes for its one row. A pure
/// move out of `AgentCatalog+Recording.swift` under road map
/// "creator-jobs" CU0a's toll U4, each line dedented by the eight spaces
/// the literal sat at there.
extension AgentServer {

    /// `record_screen`'s properties, in the catalog's order.
    func recordScreenArguments() -> [String: Any] {
        [
            "seconds": [
                "type": "number", "minimum": 1, "maximum": 600,
                "description": "How long to record, 1…600 s. The call returns after "
                    + "the recording has finished, been probed and landed.",
            ],
            "source": [
                "type": "string",
                "enum": AgentServer.RecordingSourceKind.allCases.map(\.rawValue),
                "description": "What is recorded: screen (default) — a display or a "
                    + "window — voice_over, the default microphone alone with no "
                    + "picture (the panel's Microphone Only), or camera, a camera "
                    + "alone (see camera; with screen, camera records one beside the "
                    + "screen). With voice_over, "
                    + "display, window, system_audio, show_clicks, size, "
                    + "include_framejob_windows, keys, cursor and microphone: false are "
                    + "refused by name; with camera, display, window, system_audio, "
                    + "show_clicks, size, include_framejob_windows, keys, cursor and rate "
                    + "are; "
                    + "camera and camera_format are refused with voice_over.",
            ],
            "camera": [
                "type": "string",
                "description": "With source camera, which camera to record alone; with "
                    + "source screen (the default), a camera to record BESIDE the screen, "
                    + "landing on a Camera track in front of it in the bottom-right "
                    + "corner. A device's unique id, or its name in any case; trimmed, "
                    + "and blank means none. With source camera, absent means the "
                    + "default camera — the system's preferred camera, else the "
                    + "first built-in, else the first; with source screen, absent means "
                    + "no camera. One no connected camera carries is refused naming "
                    + "every camera connected. Refused with source voice_over.",
            ],
            "camera_format": [
                "type": "string",
                "description": "With source camera, or with camera beside the screen, "
                    + "the format to record at, as "
                    + "camera.format spells it (1920x1080@30), or WIDTHxHEIGHT for that "
                    + "size's highest rate, or best; any case. Absent, blank or null means "
                    + "best — the camera's best format. A format the camera lacks is "
                    + "refused, naming its formats. Refused with source voice_over, and "
                    + "with source screen without camera.",
            ],
            "display": [
                "type": "integer", "minimum": 0,
                "description": "Which display, as an index into the shareable "
                    + "displays with 0 the MAIN display (default 0). Frame Job's own "
                    + "windows are left out of a display recording unless "
                    + "include_framejob_windows is true, so by default the app's "
                    + "panel and editor are not in the picture. Exclusive with "
                    + "window.",
            ],
            "window": [
                "type": "integer", "minimum": 0,
                "description": "A CGWindowID to record on its own — that window's "
                    + "frame, at its own size — instead of a display. Exclusive with "
                    + "display; an id that names no shareable window is refused by "
                    + "name.",
            ],
            "microphone": [
                "type": "boolean",
                "description": "Record the DEFAULT microphone to a second file beside "
                    + "the movie (default false). Needs the Microphone grant, which "
                    + "only the panel can ask for; without it the call is refused "
                    + "with the grant's status word (notDetermined, denied or "
                    + "restricted) in the sentence.",
            ],
            "system_audio": [
                "type": "boolean",
                "description": "Capture what the system plays — every application but "
                    + "Frame Job, so the timeline can play meanwhile and not be in "
                    + "it — as the movie's one stereo 48 kHz track (default true). "
                    + "false writes a movie with no audio track, and has_audio "
                    + "reports false.",
            ],
            "show_clicks": [
                "type": "boolean",
                "description": "Show each mouse click (default false). With cursor "
                    + "in_picture the stream draws a circle around each click into the "
                    + "movie; with cursor separate the recording's screen clips land "
                    + "with click ripples on (video.cursor.clicks ripple), drawn by Frame "
                    + "Job from the cursor file.",
            ],
            // The recorder panel's Cursor popup (spec §11 CU-31, CU-36).
            "cursor": [
                "type": "string", "enum": RecordingCursor.allCases.map(\.rawValue),
                "description": "Where the pointer goes: separate — not in the movie; "
                    + "the cursor file records it and Frame Job draws it on the clip, "
                    + "where the Cursor section restyles it — or in_picture, burned into "
                    + "the movie by the system as before. Absent means the source's "
                    + "default: separate for a display, in_picture for a window. Refused "
                    + "with source voice_over and camera.",
            ],
            // The recorder panel's Include Frame Job windows checkbox.
            "include_framejob_windows": [
                "type": "boolean",
                "description": "Put Frame Job's own windows — the editor, the preview — "
                    + "in a DISPLAY recording (default false, which leaves them out). "
                    + "Frame Job's own sound stays out either way, and with window it "
                    + "changes nothing: that window is recorded on its own.",
            ],
            // The recorder panel's Record shortcuts checkbox (spec §11 CU-60, CU-62).
            "keys": [
                "type": "string", "enum": RecordingKeys.allCases.map(\.rawValue),
                "description": "Which keys go into the recording's cursor files: off "
                    + "(default) or shortcuts — each shortcut pressed with cmd or ctrl, or "
                    + "with opt and an arrow, delete, forward delete, return, enter, tab or "
                    + "esc, spelled (cmd+shift+4), and a time-only mark for every other "
                    + "key, never which key was typed; nothing while an app holds secure "
                    + "input. Needs the Input Monitoring grant, which only the panel can "
                    + "ask for; without it the call is refused naming the System Settings "
                    + "pane. Refused with source voice_over and camera.",
            ],
            "rate": [
                "type": "integer", "enum": [30, 60],
                "description": "The capture's frame rate, 30 or 60 (default 60) — the "
                    + "most frames a second the file may hold — and the canvas rate "
                    + "of a new project the recording opens as. The file's own fps "
                    + "is whatever the screen did. Refused with source camera, which "
                    + "records at the camera's own format's rate.",
            ],
            "size": [
                "type": "string", "enum": RecordingResolution.allCases.map { $0.rawValue },
                "description": "nominal (default) records the display's POINT size; "
                    + "best its PIXEL size, twice the points on a Retina display. An "
                    + "odd dimension is rounded up to even by the encoder.",
            ],
            "place": [
                "type": "boolean",
                "description": "Put the clip (and the microphone's) on the timeline at "
                    + "the playhead (default true), in ONE undo step with the media. "
                    + "false adds the media to the list and no clip — import_media's "
                    + "shape — and the answer carries no clip or mic_clip id. For a "
                    + "NEW project the picture is the document, so its clips — one "
                    + "per segment, the first at 0 — are on the timeline whatever "
                    + "place says, and the answer notes it.",
            ],
            "enhance": [
                "type": "boolean",
                "description": "Run enhance_voice over the microphone's clips once they "
                    + "land and their sound is analysed, as its own undo step (default "
                    + "false); the answer gains enhance or enhance_error. Refused "
                    + "without microphone: true (or source voice_over), and with "
                    + "place: false.",
            ],
            "path": [
                "type": "string",
                "description": "A FOLDER to record into instead of ~/Movies/Frame Job "
                    + "Recordings, created if it does not exist. The file's name is "
                    + "always the dated one — this names the folder, never the file — "
                    + "and the answer's path is the file that was written. Trimmed; "
                    + "an empty or blank string means the default folder.",
            ],
        ]
    }
}
