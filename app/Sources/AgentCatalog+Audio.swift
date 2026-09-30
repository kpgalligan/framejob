import Foundation

// MARK: - Catalog: audio

/// The catalog's AUDIO half: `detect_silence` and `normalize_clip`, the two
/// composite tools road map 2's phases 3 and 5 added — neither is an op, and
/// both read the same cached waveform `SilenceDetector` and `AudioNormalize`
/// share.
///
/// A pure move out of `AgentCatalog+Clips.swift`, road map 4's toll 2, landed
/// first and alone. `AgentCatalog+Files.swift`'s header is the model: the two
/// rows came here whole, in their existing order, with their bodies
/// untouched, and are spliced back in at the SAME point in the catalog's
/// array — between `ripple_delete_ranges` and `lift_range` — so `tools/list`
/// is byte-identical before and after the cut. `ticks` and `clipsProperty`
/// are the two hoisted locals these rows read; both arrive as arguments
/// rather than a second spelling here.
extension AgentServer {

    /// The audio rows of `catalogJSON()`'s array, in their order.
    func audioTools(ticks: String, clipsProperty: [String: Any]) -> [[String: Any]] {
        return [
            tool(
                "detect_silence",
                "Finds the quiet stretches of the timeline and REPORTS them, changing nothing "
                    + "— the read half of Clip ▸ Remove Silences…, whose Remove button sends "
                    + "the answer to ripple_delete_ranges. In voice mode (the default) a "
                    + "moment is quiet when the cached Silero VAD probability over it is under "
                    + "voice_confidence; a clip whose source window holds no voice anywhere, and "
                    + "every file when the model cannot be used, is judged by level — each 10 ms "
                    + "of the cached waveform times the audio envelope against threshold_db. "
                    + "In either mode a moment whose envelope alone puts full scale at or "
                    + "under threshold_db is quiet, so volume, fades, ducking, mute and "
                    + "another track's solo all count. A run quieter than threshold_db and at "
                    + "least min_length long is a candidate; it then loses padding at each end, "
                    + "and its bounds snap INWARD to the frame grid — which can leave a frame of "
                    + "room tone, where outward would clip the attack of the next word. A moment "
                    + "no clip in scope covers is not a candidate at all: a hole in the timeline "
                    + "is not dead air. The result reports the scope and mode it used, and names "
                    + "any media whose analysis is still running rather than counting it silent — "
                    + "the waveform, or in voice mode the speech. judged_by_level_clips names each "
                    + "clip judged by level, and proposed_by_mix_clips each clip a range is "
                    + "proposed inside only because the mix turns it down while its analysis is "
                    + "still running.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Analyse only these clips — the sheet's Selected "
                            + "clips scope. Omit to take the sheet's own opening rule: the "
                            + "project's current selection when it holds anything with sound, "
                            + "every audible clip otherwise. The result says which ran.",
                    ],
                    "mode": [
                        "type": "string", "enum": ["voice", "level"],
                        "description": "voice (the default) judges by the cached Silero VAD "
                            + "probability, falling back to level over any clip whose own "
                            + "source window holds no voice; level is today's rule alone. "
                            + "voice is refused when the voice model could not be used this "
                            + "process — the result names it and omitting mode falls back to "
                            + "level with a note instead.",
                    ],
                    "voice_confidence": [
                        "type": "number", "minimum": 0.1, "maximum": 0.9,
                        "description": "In voice mode, the Silero probability at or above "
                            + "which a moment counts as speech. Default 0.5. Refused outside "
                            + "voice mode.",
                    ],
                    "threshold_db": [
                        "type": "number", "maximum": 0,
                        "description": "Quieter than this counts as silence, in dBFS in the "
                            + "mix. Default -40.",
                    ],
                    // Both durations publish the bound the handler enforces
                    // (`AgentServer.durationCeiling`), which the argument
                    // GATE cannot: it reads names, never values, so a caller
                    // reading the schema saw no ceiling at all until the
                    // second sceptic pass (road map 4 §8).
                    "min_length": [
                        "type": "integer", "minimum": 0,
                        "maximum": AgentServer.durationCeiling,
                        "description": "The shortest quiet run worth cutting, \(ticks) "
                            + "Default 0.5 s (300000). From 0 to "
                            + "\(AgentServer.durationCeiling).",
                    ],
                    "padding": [
                        "type": "integer", "minimum": 0,
                        "maximum": AgentServer.durationCeiling,
                        "description": "Left at each end of every candidate, \(ticks) "
                            + "Default 0.1 s (60000). From 0 to "
                            + "\(AgentServer.durationCeiling).",
                    ],
                ]),
            tool(
                "normalize_clip",
                "Sets each clip's audio volume so its own loudest moment lands at peak_db — "
                    + "the Normalize button in the Clip tab's Volume section, and Clip ▸ "
                    + "Normalize. The level is measured from the clip's cached waveform over "
                    + "the part of it that actually plays, which is PRE-FADER: it knows "
                    + "nothing about the volume, fades, ducking, mute or solo already on the "
                    + "clip, because normalise is a statement about the material and not "
                    + "about the mix. Three things follow, and each is a decision rather than "
                    + "an accident. It REPLACES volume rather than multiplying it, so a "
                    + "second call changes nothing (and comes back as \"made no change\", "
                    + "which is that working). It writes the clip's BASE volume even when the "
                    + "playhead is inside an action, since it is about the whole clip — a "
                    + "clip whose volume is animated is normalised underneath and then "
                    + "overridden for the action's span. And it leaves muted alone: a mute is "
                    + "a switch, not a level. Each clip gets its OWN gain, so this does not "
                    + "match levels across a selection. One undo step however many clips. "
                    + "The model's volume ceiling is 4×, so a clip quieter than about "
                    + "-13 dBFS cannot reach -1: it is still normalised, as loud as it goes, "
                    + "and result_db says where it landed. A clip that plays no sound, one "
                    + "that is silent over the part that plays, and one whose waveform has "
                    + "not been analysed yet are each reported by name under skipped and the "
                    + "rest are still normalised.",
                [
                    "clips": clipsProperty,
                    "peak_db": [
                        "type": "number", "minimum": -60, "maximum": 0,
                        "description": "Where the loudest moment should land, in dBFS. "
                            + "Default -1, which is what the button uses: hot enough to use "
                            + "the format, with a decibel of room for the inter-sample peaks "
                            + "a lossy encoder can add. Above 0 is a request to clip and is "
                            + "refused rather than clamped.",
                    ],
                ], required: ["clips"]),
        ]
    }
}
