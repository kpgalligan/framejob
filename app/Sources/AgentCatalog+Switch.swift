import Foundation

/// The catalog rows of `copy_pieces` and `switch_angle` (road map
/// "creator-jobs" SW1, spec §11 SW-11…SW-15), spliced in last by
/// `creatorTools()`, after `switch_layout`'s.
extension AgentServer {

    func switchTools() -> [[String: Any]] {
        let ticks = "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000"
        return [
            // The primitive Clip ▸ Switch Angle ▸ (`switchAngle` in
            // EditorViewController+SwitchAngle.swift) writes with: one per
            // angle clip the shot's span crosses.
            opTool(
                "copy_pieces",
                "Copies pieces of a clip onto another track at the same project times — the "
                    + "op Clip ▸ Switch Angle ▸ writes with. Each piece is exactly what two "
                    + "splits at its range's ends would leave in the middle: the same source "
                    + "frames at the same times (speed, a ramp, reversal, a graphic's own "
                    + "timeline, timed words and actions cut as split cuts them), so a piece "
                    + "of a synced camera angle shows that angle's own frame at every time. "
                    + "Pieces get fresh ids, no transition and no link. One undo step, \"Copy "
                    + "Pieces\". Each range's ends are snapped to the frame grid and a reversed "
                    + "pair is the same range; a range empty on the grid is skipped. Refused, "
                    + "nothing changed, in this order: a nest clip, a range outside the clip, "
                    + "two ranges that overlap (touching is fine), a locked destination, and a "
                    + "destination holding a clip over a range (naming that clip and its ends). "
                    + "Inside a nest (scope) the times and tracks are the nest's.",
                [
                    "clip": "The clip to copy pieces of.",
                    "track": "The track the pieces land on; it must be free over every range.",
                    "ranges": "[[from, to], …] project times, \(ticks), inside the clip and "
                        + "not overlapping. At least one pair.",
                    "video": "Set each piece's picture on (true) or off (false). Default: the "
                        + "clip's own.",
                    "audio": "Set each piece's sound on (true) or off (false). Default: the "
                        + "clip's own.",
                ]),
            // It mirrors Clip ▸ Switch Angle ▸ (`switchAngle` in
            // EditorViewController+SwitchAngle.swift), through the same planner
            // (SwitchAngle.swift). An app-state composite of ordinary ops: no
            // `scope`, one undo step.
            tool(
                "switch_angle",
                "Re-picks one shot from another camera angle — the mirror of Clip ▸ Switch "
                    + "Angle ▸. An angle is a TRACK whose video clips (media with a picture; a "
                    + "clip with its picture off or on a hidden track still counts) cover the "
                    + "shot's whole span. The shot is deleted and the angle copied over the same "
                    + "span with copy_pieces, one piece per angle clip the span crosses (where "
                    + "two angle clips overlap, the later one takes over at its own start), "
                    + "each with the shot's video and audio switches; the clips either side are "
                    + "trimmed back to their old edges, so a dissolve on either edge is re-formed "
                    + "with its kind, curve and audio shape. The shot's grade, punch-in, actions "
                    + "and other settings do NOT carry. One undo step, \"Switch Angle\", or "
                    + "\"Switch Angle (transition removed)\" when an edge's dissolve could not be "
                    + "re-formed against a short piece and was dropped. Works in the container "
                    + "set_scope has open. Answers {ok, step, pieces (the new clip ids in time "
                    + "order), transitions_removed (0–2), project}. Refused, nothing changed: "
                    + "the angle is the shot's own track, the shot's track is locked, the shot "
                    + "is linked (Detach Audio's pair), the angle does not cover the shot "
                    + "(naming the first uncovered tick), or a step of the sequence is refused "
                    + "or an edge is held short by a speed ramp (in its own sentence).",
                [
                    "clip": [
                        "type": "integer",
                        "description": "The shot to re-pick: a clip on the program track.",
                    ],
                    "angle": [
                        "type": "integer",
                        "description": "The id of the track to re-pick it from.",
                    ],
                ], required: ["clip", "angle"]),
            // It mirrors Clip ▸ Switch by Speaker… (`showSwitchBySpeakerSheet` in
            // EditorViewController+SwitchSpeaker.swift, the sheet
            // SwitchSpeakerSheetController), through the same SpeakerSwitch.read, plan and
            // edit (SW-23, SW-26). An app-state composite of ordinary ops: no `scope`, one
            // undo step.
            tool(
                "switch_by_speaker",
                "Cuts a Program track from synced cameras, showing whoever talks on each "
                    + "microphone — the mirror of Clip ▸ Switch by Speaker…. Run sync_audio first: "
                    + "it trusts the clips' placement. It reads the SELECTED clips (set_selection): "
                    + "an angle is a track holding a selected video clip; by default the "
                    + "microphones are the tracks holding a selected sound-only clip, else each "
                    + "camera is its own, paired front to back, and the one angle no speaker uses "
                    + "is the wide. The range is from/to, else the In–Out range, else the selected "
                    + "angle clips' extent. It reads each microphone's loudness and speech caches "
                    + "(made at import; a pending one is refused as still being analysed) and "
                    + "cuts a shot `lead` before each new speaker's turn, holds through short "
                    + "replies (min_turn) and silence, shows the wide during crosstalk and merges "
                    + "shots under min_shot. It writes, as ONE undo step \"Switch by Speaker\": a "
                    + "new track \"Program\" directly in front of the front-most angle (or, with "
                    + "track, that track cleared over the range), one copy_pieces per angle clip "
                    + "a shot crosses (picture on, sound off), the angle tracks hidden — or, "
                    + "when an angle track holds clips outside the range or a clip without a "
                    + "picture, its clips split at the "
                    + "range's ends with their pictures off inside — and, with mute_cameras, the "
                    + "cameras' own sound off inside the range (never on a microphone's track). "
                    + "Nothing outside the range changes and the microphones are never edited. "
                    + "Works in the container set_scope has open. ONE MICROPHONE FOR EVERYONE "
                    + "(the faces mode): when one microphone is shared by two or more angles — "
                    + "the default when the selection holds exactly one microphone — who talks "
                    + "is decided while the microphone hears speech by whose mouth moves most "
                    + "in each camera's on-device face analysis (the largest face; 1.5× the next "
                    + "camera's, else crosstalk); a named wide takes no part, and min_shot "
                    + "defaults to 3. Faces it still has to find are found first: the call "
                    + "waits up to 60 s, and past that is refused with what it covered kept — "
                    + "call again to continue. Answers {ok, applied, step "
                    + "(only when applied), track (the Program track; null when not applied and no "
                    + "track named), shots [{angle, start, end}], ops (the count), added (clips), "
                    + "speakers [{mic, angle}], wide, mute_cameras, mode (\"microphones\" or "
                    + "\"faces\"), note (in the faces mode: faces guess, check the cuts), "
                    + "project}. Refused, nothing "
                    + "changed, naming every reason at once: fewer than two angles or more than "
                    + "nine, a speaker without a microphone or an angle, one microphone for two "
                    + "speakers (outside the faces mode), a microphone still being analysed or "
                    + "with no speech, a camera whose faces are still being found or show no "
                    + "mouth that can be read, a faces analysis that failed, was stopped or did "
                    + "not finish within the wait, a project changed while it waited, a stretch "
                    + "no angle covers, more clips than the project may hold (raise min_shot), a "
                    + "track that cannot take the shots (locked, holding a selected clip, not in "
                    + "front of the angles, nothing in the range, or a clip that is not a piece "
                    + "of an angle), or an angle clip linked by Detach Audio (Attach Audio first).",
                [
                    "speakers": [
                        "type": "array", "minItems": 1,
                        "items": [
                            "type": "object",
                            "properties": [
                                "mic": ["type": "integer", "description": "The microphone's track id."],
                                "angle": [
                                    "type": "integer",
                                    "description": "The angle track that shows this person.",
                                ],
                            ],
                            "required": ["mic", "angle"],
                            "additionalProperties": false,
                        ],
                        "description": "Who is who: one {mic, angle} per person, track ids. A "
                            + "camera's detached sound may be named as a mic; one mic named for "
                            + "two or more angles is the faces mode. Default: the pairing the "
                            + "selection implies (with exactly one microphone, every angle with "
                            + "it).",
                    ],
                    "wide": [
                        "type": ["integer", "null"],
                        "description": "The wide angle, which opens the cut and shows during "
                            + "crosstalk (while nobody talks the current shot holds); null for "
                            + "none. Default: the one angle no speaker uses, when exactly one is "
                            + "left; none in the faces mode. Named without speakers, a speaker on "
                            + "it who shares a microphone takes no part.",
                    ],
                    "from": [
                        "type": "integer",
                        "description": "The range's start, \(Self.switchTicks); with to. Snapped "
                            + "to the frame grid.",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "The range's end, after from; with from.",
                    ],
                    "min_shot": [
                        "type": "number", "minimum": 0.5, "maximum": 30,
                        "description": "Seconds: a shorter shot merges into a neighbour. "
                            + "Default 2; 3 in the faces mode.",
                    ],
                    "min_turn": [
                        "type": "number", "minimum": 0.2, "maximum": 10,
                        "description": "Seconds: a shorter turn (a reply) starts no shot. "
                            + "Default 1.",
                    ],
                    "lead": [
                        "type": "number", "minimum": 0, "maximum": 1,
                        "description": "Seconds a cut comes before the new speaker's first word. "
                            + "Default 0.2.",
                    ],
                    "crosstalk": [
                        "type": "string", "enum": ["wide", "hold"],
                        "description": "What a second or more of crosstalk shows: the wide, or "
                            + "hold the current speaker. Default wide.",
                    ],
                    "bleed_db": [
                        "type": "number", "minimum": 3, "maximum": 40,
                        "description": "dB below a speaker's own level that is the other "
                            + "person's voice bleeding in, never a turn. Default 15.",
                    ],
                    "dominance_db": [
                        "type": "number", "minimum": 0, "maximum": 30,
                        "description": "dB by which one active microphone must lead every other "
                            + "to count alone. Default 8.",
                    ],
                    "wide_after": [
                        "type": ["number", "null"], "minimum": 2, "maximum": 600,
                        "description": "Seconds: once one person has held the screen this long, "
                            + "cut to the wide for min_shot. null (the default) is off.",
                    ],
                    "mute_cameras": [
                        "type": "boolean",
                        "description": "Switch the cameras' own sound off inside the range. "
                            + "Default: on when no microphone is a camera.",
                    ],
                    "track": [
                        "type": "integer",
                        "description": "Replace the shots on this track (an earlier Program "
                            + "track) instead of adding one: unlocked, in front of the angles, "
                            + "holding no selected clip, and holding only pieces of the angles "
                            + "over the range.",
                    ],
                    "apply": [
                        "type": "boolean",
                        "description": "false answers the shots and the op count without "
                            + "editing. Default true.",
                    ],
                ]),
        ]
    }

    private static let switchTicks =
        "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000"
}
