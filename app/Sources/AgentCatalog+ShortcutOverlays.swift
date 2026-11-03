import Foundation

/// The catalog row of `add_shortcut_overlays` (spec §11 CU-84; road map "creator-jobs" CU8),
/// spliced in after `auto_zoom`'s by `creatorTools()`.
extension AgentServer {

    func shortcutOverlayTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second"
        return [
            // It mirrors Clip ▸ Add Shortcut Overlays
            // (`EditorViewController+ShortcutOverlays.swift`), one undo step
            // "Add Shortcut Overlays". No `scope` key: the clips are looked
            // up in the container set_scope has open.
            tool(
                "add_shortcut_overlays",
                "Places one Keyboard keys graphic clip per keyboard shortcut recorded in screen "
                    + "recordings' cursor files, at the moment it was pressed, as ONE undo step "
                    + "\"Add Shortcut Overlays\" — Clip ▸ Add Shortcut Overlays. Only shortcuts "
                    + "are recorded (Record shortcuts in the recorder), never typed keys. Each "
                    + "press inside a clip's played window is placed through the clip's speed "
                    + "and ramps, snapped to the frame grid. An overlay lasts duration seconds "
                    + "and never less than (10 × keycaps + 25) frames, the time the template "
                    + "needs to press its last key and exit. The same shortcut pressed again "
                    + "before its overlay ends extends it to duration after the last press, "
                    + "labelled ×2, ×3 … (merged counts them); a different shortcut pressed "
                    + "sooner ends the earlier overlay where it starts, waiting until the "
                    + "earlier one has had its minimum — and if that is more than 0.5 s after "
                    + "its press it is dropped (dropped counts them). Overlays never overlap. "
                    + "They go on the front-most track named \"Shortcuts\" when it is in front "
                    + "of every clip's track, unlocked, shown, not a matte and free over their "
                    + "span; otherwise on a new \"Shortcuts\" track at the front (new_track). "
                    + "The project's graphics/ module whose text equals the bundled "
                    + "keyboard-keys template is reused; otherwise the template is copied in "
                    + "once (written), and only when something is placed. Refused: a clip that "
                    + "is not a media clip, whose media has no cursor file or whose file is "
                    + "missing, or that plays reversed. Answers added, dropped, merged, track, "
                    + "new_track, module, written and overlays [{at, duration, keys, label}] (at "
                    + "in container ticks); with no shortcut in the clips' played windows, ok "
                    + "with a note and no undo step.",
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
                    "duration": [
                        "type": "number",
                        "description": "How long each overlay shows, in seconds: 0.5–10, 1.5 "
                            + "by default (never less than the template's minimum).",
                    ],
                    "position": [
                        "type": "string", "enum": ShortcutOverlaySettings.positions,
                        "description": "Where the keycaps sit: bottom (the default), center "
                            + "or top.",
                    ],
                    "theme": [
                        "type": "string", "enum": ShortcutOverlaySettings.themes,
                        "description": "The keycaps' look: dark (the default) or light.",
                    ],
                    "from": [
                        "type": "integer",
                        "description": "Place only shortcuts at or after this container "
                            + "time, \(ticks).",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Place only shortcuts before this container time, "
                            + "\(ticks); must be after from.",
                    ],
                ]),
        ]
    }
}
