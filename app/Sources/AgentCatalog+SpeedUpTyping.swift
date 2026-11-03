import Foundation

/// The catalog row of `speed_up_typing` (spec §11 CU-91…CU-93; road map "creator-jobs" CU9b),
/// spliced in after `add_shortcut_overlays`' by `creatorTools()`.
extension AgentServer {

    func speedUpTypingTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second"
        return [
            // It mirrors Clip ▸ Speed Up Typing… (`SpeedUpTypingSheetController`),
            // one undo step "Speed Up Typing". No `scope` key: the clips are
            // looked up in the container set_scope has open.
            tool(
                "speed_up_typing",
                "Plays the typing in screen recordings faster, as ONE undo step \"Speed Up "
                    + "Typing\" — Clip ▸ Speed Up Typing…. A typing stretch is a run of at "
                    + "least 3 typed keys each under 1 s apart, read from the clips' cursor "
                    + "files and placed through each clip's speed and ramps. From each stretch "
                    + "is taken away every span of speech of every clip with sound under it, on "
                    + "any track, and each recorded shortcut with its overlay (its clip on a "
                    + "track named \"Shortcuts\", else 1.5 s), so speech and shortcut overlays "
                    + "always play at normal speed. The pieces of all the clips are joined "
                    + "where they meet, a piece shorter than shortest seconds is left alone "
                    + "(short counts them), and each kept piece is sped by retime_range at rate "
                    + "on every unlocked track, keeping 0.3 s at normal speed at each end, so "
                    + "everything after it moves up in step. Its sound is sped too, its pitch "
                    + "kept with keep_pitch. A media with sound under a stretch whose speech "
                    + "has not been saved gets its spans from on-device speech detection in "
                    + "the same step (speech_saved); while detection runs the call is refused "
                    + "— try again in a moment. Refused, whole and before anything changes: a "
                    + "clip that is not a media clip, whose media has no cursor file or whose "
                    + "file is missing, or that plays reversed; a rate or shortest out of "
                    + "range; any range retime_range would refuse (a locked track after it, a "
                    + "transition, a linked clip …), naming it. Answers stretches, short, "
                    + "ranges [{from, to, sped_to}] in container ticks before the edit, saved "
                    + "(ticks), speech_saved and, when a clip with sound is now above the audio "
                    + "ceiling, audio_left_out and audio_note; with nothing to speed, ok with a "
                    + "note and no undo step.",
                [
                    "clip": [
                        "type": "integer",
                        "description": "A screen recording's media clip — exactly one of clip "
                            + "and clips.",
                    ],
                    "clips": [
                        "type": "array", "items": ["type": "integer"],
                        "description": "Media clips whose media have cursor files — exactly "
                            + "one of clip and clips. Halves of a split recording are joined.",
                    ],
                    "rate": [
                        "type": "number",
                        "description": "How much faster a stretch plays: 2–8, 4 by default.",
                    ],
                    "shortest": [
                        "type": "number",
                        "description": "The shortest stretch sped up, in seconds: 1–30, 3 by "
                            + "default.",
                    ],
                    "keep_pitch": [
                        "type": "boolean",
                        "description": "Keep the sped sound's pitch: true by default.",
                    ],
                    "from": [
                        "type": "integer",
                        "description": "Speed only typing at or after this container time, "
                            + "\(ticks).",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Speed only typing before this container time, "
                            + "\(ticks); must be after from.",
                    ],
                ]),
        ]
    }
}
