import Foundation

// MARK: - Catalog: audio

/// The catalog's AUDIO half: `detect_silence` and `normalize_clip`, the two
/// composite tools road map 2's phases 3 and 5 added, `sync_audio`, the
/// third (road map "audio-sync", AS-1), `detect_fillers`, the fourth (road
/// map "cut-by-transcript" CT-2), and `transcribe_for_fillers`, the fifth
/// (CT-3) — none of the five is an op. The first two read the cached waveform
/// `SilenceDetector` and `AudioNormalize` share; `AudioSync` reads its sync
/// features and samples instead (AS-3, AS-4); `FillerDetector` reads the
/// cached cloud transcript's filler words (TR-9), and `FillerTranscription`
/// makes one (TR-10).
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
        // sync_audio's speech floor and placement radius, in seconds, from
        // the constants, as `AudioSync.rule(_:)` prints the radius.
        func seconds(_ frames: Int) -> Double {
            Double(Ticks(frames) * SyncFeatures.frameTicks) / Double(ReelTime.perSecond)
        }
        let speechFloor = String(format: "%g", seconds(AudioSyncMatch.minimumSpeechFrames))
        let radius = String(format: "%.0f", seconds(AudioSyncMatch.placementRadiusFrames))
        let shortest = String(format: "%g", seconds(AudioSyncMatch.minimumStretchFrames))
        // The refinement's and drift's numbers (SY-20, SY-21), from the constants.
        let rate = Double(SyncFeatures.sampleRate)
        let reach = String(format: "%g", Double(AudioSyncPHAT.reachSamples) / rate * 1000)
        let region = String(format: "%g", Double(AudioSyncPHAT.maximumRegionSamples) / rate)
        let least = String(format: "%g", Double(AudioSyncPHAT.minimumRegionSamples) / rate)
        let band = String(format: "%g–%g Hz", AudioSyncPHAT.lowHertz, AudioSyncPHAT.highHertz)
        let driftOverlap = String(format: "%g", seconds(AudioSyncMatch.driftMinimumOverlapFrames))
        let driftWindow = String(format: "%g", seconds(AudioSyncMatch.driftWindowFrames))
        // detect_fillers' vocabulary, from the one list (TR-8).
        let fillers = FillerWords.assemblyAI.sorted().joined(separator: ", ")
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
                    + "still running. A nest clip is a wall: no candidate reaches into one, and "
                    + "protected_nests names each nest clip a quiet run of at least min_length "
                    + "crossed — set_scope into it and call again to look for any dead air "
                    + "inside.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Analyze only these clips — the sheet's Selected "
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
                "Sets each clip's audio volume so its integrated loudness lands at "
                    + "target_lufs (mode \"loudness\", the default), or so its own loudest "
                    + "moment lands at peak_db (mode \"peak\", the default only when peak_db "
                    + "is given without a mode) — the Normalize button in the Clip tab's "
                    + "Volume section, and Clip ▸ Normalize, which follow the mode chosen in "
                    + "that section's Normalize row (Loudness unless changed). The level is measured from the clip's "
                    + "cached waveform (peak) or loudness cache (BS.1770-4 gated, as the "
                    + "export plays it: a mono clip as dual mono, a stereo clip through its own "
                    + "channel pick, mono and pan) over the part of it that actually plays, which is "
                    + "PRE-FADER: it knows nothing about the volume, fades, ducking, mute or "
                    + "solo already on the clip, because normalize is a statement about the "
                    + "material and not about the mix. Three things follow, and each is a "
                    + "decision rather than an accident. It REPLACES volume rather than "
                    + "multiplying it, so a second call changes nothing (and comes back as "
                    + "\"made no change\", which is that working). It writes the clip's BASE "
                    + "volume even when the playhead is inside an action, since it is about the "
                    + "whole clip — a clip whose volume is animated is normalized underneath "
                    + "and then overridden for the action's span. And it leaves muted alone: a "
                    + "mute is a switch, not a level. In peak mode each clip gets its OWN gain "
                    + "to the same peak, so it does not match levels across a selection; in "
                    + "loudness mode each clip is taken to the one target, which does. One undo "
                    + "step however many clips. The model's volume ceiling is "
                    + "\(AudioNormalize.maxGainName), so a clip quieter than about "
                    + String(format: "%.0f", AudioNormalize.quietestReachableDB)
                    + " dBFS cannot reach -1: it is still normalized, as loud as it goes, "
                    + "and result_db says where it landed. In loudness mode a clip whose true "
                    + "peak would pass -1 dBTP at the target, or that already has a limiter, "
                    + "gets the clip's true-peak limiter in the same edit (set_audio's "
                    + "limiter: its own kept with the ceiling at most -1 dBTP, else the "
                    + "default), and the volume is the one that reaches the target through it; "
                    + "each row's limiter says what the clip has after the edit (null for a "
                    + "volume alone), limited_by is max_gain when the volume ceiling stopped it "
                    + "short (else null), result_lufs says where it lands, "
                    + "result_true_peak_dbtp is held at the limiter's ceiling, and "
                    + "measured_lufs and true_peak_dbtp are the Volume section's Loudness "
                    + "readout. In loudness mode a clip with an active EQ, a hum notch, voice "
                    + "isolation, noise reduction, a gate, a de-esser, a leveler, a compressor "
                    + "or a voice effect is measured THROUGH that processing, and so is one where "
                    + "the end of an action switches any of those but the voice effect on, or "
                    + "sets the limiter (on, or off): its "
                    + "window is rendered "
                    + "offline as the export plays it, pre-fader (waiting for its isolation or "
                    + "voice render; seconds on a long clip), the volume is solved on what comes "
                    + "out and, with a limiter on the clip or at an action's end, checked by "
                    + "render to within 0.1 LU (turning the clip's limiter on at -1 dBTP when a "
                    + "volume the check moves to would put the true peak past it); "
                    + "processed_lufs is that measurement and renders the renders it took (null "
                    + "and 0 for a clip measured off the loudness cache alone, whose "
                    + "true_peak_dbtp is the material's; a rendered clip's is the processed "
                    + "one). A solved volume within 0.05 dB of the clip's own is kept, so a "
                    + "second call still changes nothing. Such a clip is skipped by name when "
                    + "its reversed copy is still being made, its processing cannot be "
                    + "rendered, or it is under -70 LUFS after it; and if the project changes "
                    + "while it measures nothing changes and the call says so. A clip that "
                    + "plays no sound, one that is silent (or under -70 LUFS, or plays under "
                    + "0.4 s) over the part that plays, and one whose waveform or loudness has "
                    + "not been analyzed yet are each reported by name under skipped and the "
                    + "rest are still normalized.",
                [
                    "clips": clipsProperty,
                    "peak_db": [
                        "type": "number", "minimum": -60, "maximum": 0,
                        "description": "Peak mode only: where the loudest moment should land, "
                            + "in dBFS. Default -1, which is what the button uses in Peak mode: "
                            + "hot enough to use the format, with a decibel of room for the "
                            + "inter-sample peaks a lossy encoder can add. Above 0 is a request "
                            + "to clip and is refused rather than clamped; refused with mode "
                            + "\"loudness\".",
                    ],
                    "mode": [
                        "type": "string", "enum": ["peak", "loudness"],
                        "description": "\"loudness\" (the default) takes each clip's integrated "
                            + "loudness to target_lufs under a -1 dBTP true-peak ceiling, turning "
                            + "the clip's limiter on when the peak needs it; \"peak\" (the "
                            + "default when only peak_db is given) takes each clip's loudest "
                            + "moment to peak_db.",
                    ],
                    "target_lufs": [
                        "type": "number", "minimum": -50, "maximum": -5,
                        "description": "Loudness mode only: the integrated loudness each clip "
                            + "should land at, in LUFS. Default -16; -14 is YouTube's playback "
                            + "reference and -23 EBU R 128's. Outside -50 to -5 is refused "
                            + "rather than clamped; refused with mode \"peak\".",
                    ],
                ], required: ["clips"]),
            // Road map "audio" AP6 (spec §11 AU-60…AU-65): Clip ▸ Enhance
            // Voice's and the Volume section's Enhance Voice button's mirror,
            // a composite like normalize_clip.
            tool(
                "enhance_voice",
                "Sets each clip up for speech from its own measurements, in one undo step — "
                    + "Clip ▸ Enhance Voice, and the Enhance Voice button in the Clip tab's "
                    + "Volume section (which use the Normalize row's Target). It measures, "
                    + "before any of the clip's settings: the integrated loudness L and true "
                    + "peak (the Volume section's Loudness readout), and over each 10 ms the "
                    + "clip plays whether it is speech (the media's saved speech spans, else its "
                    + "cached Silero VAD) or a pause. Then it writes ordinary settings, each one "
                    + "visible and changeable in its section: always the EQ's Rumble Cut "
                    + "high-pass (80 Hz, 24 dB/octave; the EQ's other slots kept); when the "
                    + "pauses are noisy — their floor (median loudness) less than "
                    + String(format: "%g", -AudioEnhance.noisyGapDB)
                    + " dB under L — voice isolation at "
                    + String(format: "%g", IsolationCache.defaultAmount)
                    + " with noise reduction off, and the gate, opening "
                    + String(format: "%g", AudioEnhance.gateAbovePausePeakDB)
                    + " dB above the pauses' median true peak (threshold_db re L, held to -40 "
                    + "… -6); with quiet pauses isolation, noise reduction and the gate are off, "
                    + "and with under 0.5 s of pause they are left as they are; the leveler at "
                    + "its defaults when the speech's short-term loudness range (3 s windows of "
                    + "the speech alone at a 0.1 s hop, EBU Tech 3342's gating, the 95th "
                    + "percentile less the 10th; speech_range_lu) is over "
                    + String(format: "%g", AudioEnhance.levellerRangeLU)
                    + " LU, else off, and left as it is with under 3 s of speech; the de-esser "
                    + "at its defaults when at least "
                    + String(format: "%g", AudioEnhance.sibilanceShare * 100)
                    + " % of the speech has its 6 kHz band within 10 dB of L, else off; a "
                    + "compressor whose threshold is the speech's median true peak (dBFS, 3:1) "
                    + "with makeup that gives back what it takes; the limiter (the clip's own "
                    + "kept, its ceiling at most -1 dBTP, else the default); and the volume "
                    + "that takes the clip to target_lufs, solved on the clip rendered offline "
                    + "through those very settings as the export plays it, pre-fader (the "
                    + "limiter told the volume and checked by render to within 0.1 LU, up to "
                    + "three times) — normalize_clip's loudness mode measures a processed clip "
                    + "the same way, so normalize_clip at the same target afterwards changes "
                    + "nothing. The render waits for the clip's isolation render and takes "
                    + "seconds on a long clip (the menu and the button show the Measuring Sound "
                    + "sheet meanwhile); if the project changes while it measures, nothing "
                    + "changes and the call says so. It overwrites exactly those keys of "
                    + "set_audio (eq, isolation, noise_reduction, gate, leveller, de_esser, "
                    + "compressor, limiter, volume) and leaves every other one (hum, channels, pan, mono, "
                    + "fades, duck, mute). Like normalize_clip it writes BASE settings even with "
                    + "the playhead inside an action, nothing it chooses depends on what it "
                    + "writes, and a solved volume within 0.05 dB of the clip's own is kept, so "
                    + "a second call changes nothing (\"made no change\"). Each row of enhanced "
                    + "gives the measurements (speech_range_lu null under 3 s of speech), set "
                    + "(exactly the keys written), reasons (one "
                    + "sentence per rule: the measurement, the threshold, what it set), "
                    + "processed_lufs (the loudness through the new settings, before the "
                    + "volume), renders, and the volume's figures, result_lufs and "
                    + "result_true_peak_dbtp being the last render's. A clip that plays no "
                    + "sound, is a nest, plays under 0.4 s, is under -70 LUFS, has under 1 s of "
                    + "speech, whose loudness or speech has not been analyzed yet, whose "
                    + "reversed copy is still being made, whose processing cannot be rendered, "
                    + "or that is under -70 LUFS after its processing is reported by name under "
                    + "skipped and the rest are still enhanced.",
                [
                    "clips": clipsProperty,
                    "target_lufs": [
                        "type": "number", "minimum": -50, "maximum": -5,
                        "description": "The integrated loudness each clip should land at, in "
                            + "LUFS. Default -16; -14 is YouTube's playback reference and -23 "
                            + "EBU R 128's. Outside -50 to -5 is refused rather than clamped.",
                    ],
                ], required: ["clips"]),
            // Road map "audio" AP12 (spec §11 AU-120…AU-128): Clip ▸ Match
            // Audio…'s mirror, a composite like enhance_voice.
            tool(
                "match_audio",
                "Matches clips to a reference clip's loudness and tone, in one undo step — Clip "
                    + "▸ Match Audio… (whose sheet picks the reference among the selected clips "
                    + "and has a Loudness and an EQ box). The reference is rendered once as it "
                    + "plays (its settings, its limiter and its volume; no fades, ducks or "
                    + "mute) and its integrated loudness T read. loudness (default true) is "
                    + "normalize_clip's loudness mode at target T for every clip: the volume, "
                    + "and the limiter when the peaks need it (ceiling -1 dBTP), solved on the "
                    + "clip rendered through its new settings. eq (default true) matches the "
                    + "tone: each clip is rendered with its EQ's shelves and bands off (its "
                    + "high- and low-pass kept), and both clips' average spectra are measured "
                    + "over their speech only (the media's saved speech spans, else its cached "
                    + "Silero VAD; at least \(SpeechSpectrumMeter.minimumFrames) "
                    + "\(SpeechSpectrumMeter.fftSize)-point frames, about 1 s) in "
                    + "\(SpeechSpectrumMeter.bandIndices.count) third-octave bands from 79 Hz "
                    + "to 12.7 kHz; the difference, over the bands where both are within "
                    + String(format: "%g", AudioMatchFit.contentRangeDB)
                    + " dB of their loudest (at least \(AudioMatchFit.minimumBands)), less its "
                    + "average (the level is loudness's), smoothed, is fitted by the EQ's low "
                    + "shelf, three bands and high shelf (gains within ±"
                    + String(format: "%g", AudioMatchFit.maxGainDB)
                    + " dB, Q 0.5–4, a band only where the difference is at least "
                    + String(format: "%g", AudioMatchFit.minimumBellDB)
                    + " dB), which replace the clip's own five (its high- and low-pass and hum "
                    + "kept, bypass off). It writes only volume, limiter and eq of set_audio, "
                    + "BASE settings even inside an action, and a second call changes nothing "
                    + "(\"made no change\"). Each row of matched gives set (exactly the keys "
                    + "written), eq and eq_fit_rms_db (how far the fitted EQ is from the "
                    + "difference, dB RMS), and normalize_clip's figures for the volume "
                    + "(measured_lufs, processed_lufs, result_lufs, result_true_peak_dbtp, "
                    + "limited_by) and renders. The renders take seconds on a long clip; if the "
                    + "project changes meanwhile, nothing changes and the call says so. A "
                    + "reference that plays no sound, is a nest, plays under 0.4 s, is under "
                    + "-70 LUFS, has not been analyzed yet or (with eq) has under 1 s of speech "
                    + "or under \(AudioMatchFit.minimumBands) third-octave bands within "
                    + "\(Int(AudioMatchFit.contentRangeDB)) dB of its loudest "
                    + "is refused by name; a clip that cannot be matched for one of those "
                    + "reasons, shares under \(AudioMatchFit.minimumBands) such bands with the "
                    + "reference, or is the reference, is reported under skipped and the rest are "
                    + "still matched.",
                [
                    "reference": [
                        "type": "integer",
                        "description": "The clip whose loudness and tone the others take; it "
                            + "is not changed.",
                    ],
                    "clips": clipsProperty,
                    "loudness": [
                        "type": "boolean",
                        "description": "Match the loudness (volume and limiter). Default true.",
                    ],
                    "eq": [
                        "type": "boolean",
                        "description": "Match the tone (the EQ's shelves and bands). Default "
                            + "true. With loudness and eq both false the call is refused.",
                    ],
                ], required: ["reference", "clips"]),
            // Road map "audio-sync" AS-1 (spec §11 SY-1..SY-5): Clip ▸
            // Synchronize Audio's mirror, a composite like the two above.
            tool(
                "sync_audio",
                "Lines up clips that play sound by their sound — Clip ▸ Synchronize Audio. "
                    + "One clip, the anchor, stays where it is; every other clip moves along "
                    + "its own track by a whole number of frames so its sound plays at the "
                    + "same moment as the anchor's. The match is made on each file's cached "
                    + "sound features (26 MFCCs per 16 ms, standardized, so gain, microphone "
                    + "and room do not matter) by cross-correlation summed over the "
                    + "coefficients; a lag's confidence is its z-score against every lag. When "
                    + "both stretches hold at least \(speechFloor) s of speech by the cached "
                    + "Silero VAD "
                    + "(probability ≥ \(String(format: "%g", AudioSyncMatch.speechProbability))), "
                    + "only their speech frames are compared (matched_on \"speech\", else "
                    + "\"sound\"). The clips' PLAYED windows (their trims) are searched first, "
                    + "and the whole files only when that chooses nothing and a clip is "
                    + "trimmed. A search's match is CONFIDENT when its best candidate's "
                    + "confidence is at least \(String(format: "%g", AudioSyncMatch.confidentZ)) "
                    + "and \(String(format: "%g", AudioSyncMatch.confidentMargin)) above the "
                    + "next, and applies (once the waveforms confirm it, below); else it is "
                    + "WEAK when the best peak within "
                    + "\(radius) s of "
                    + "where the clip already sits has confidence at least "
                    + "\(String(format: "%g", AudioSyncMatch.plausibleZ)), and a weak match "
                    + "that would move anything is NOT applied unless accept_weak is true: the "
                    + "answer is moved: false, weak naming those clips, each row's move, and a "
                    + "note. Pass accept_weak: true only after the person has agreed to that "
                    + "weak match, naming the move — a weak match can be unrelated sound. "
                    + "Otherwise the call is refused, "
                    + "naming each search's candidates as the move each would make and its "
                    + "confidence, so a caller can move the clip near one and call again. A "
                    + "clip that would start before 0 is trimmed at its head instead, by just "
                    + "that much, and starts at 0 (the anchor never moves or trims). All or "
                    + "nothing, one undo step: when any clip cannot be matched — no sound, "
                    + "still being analyzed, under \(shortest) s, playing more than 0.2% away from ×1, "
                    + "at a rate other than its speed, reversed, or ramping its speed (a speed "
                    + "action changes its rate over its length), two clips on one track, no "
                    + "match chosen, waveforms that do not line up at it, a trim that would "
                    + "leave under a frame, never playing "
                    + "beside the anchor or overlapping another clip on its track — nothing "
                    + "moves and every reason is named. Over at least "
                    + "\(driftOverlap) s of overlap the clock drift between the two is measured "
                    + "as a line through many \(driftWindow) s windows, each matched on the "
                    + "features and then refined by GCC-PHAT on the samples, and CORRECTED "
                    + "with set_speed (keep_pitch false, "
                    + "a resample) so the clip's sound stays under the anchor's along the "
                    + "whole overlap — unless it is under 5 ms or under 3× its uncertainty "
                    + "(drift_error_ms), or would need a speed more than 0.2% from ×1, when "
                    + "it is left and "
                    + "drift_note says why. Each match's offset is then refined below a frame "
                    + "by GCC-PHAT on the files' cached 8 kHz samples, over the \(band) "
                    + "speech band and at most \(region) s of the overlap (the files' overlap "
                    + "at the match when the played overlap is under \(least) s), within "
                    + "±\(reach) ms of the match. EITHER tier needs a clear peak there "
                    + "(confidence ≥ \(String(format: "%g", AudioSyncPHAT.clearZ))): a match "
                    + "whose waveforms do not line up, or that shares too little sound to "
                    + "check, is refused as not one recording — features alone can match two "
                    + "takes of similar words. The refinement never changes the confidence, "
                    + "and the move stays a whole number of frames. The answer reports each moved "
                    + "clip's offset (anchor source minus clip source at the overlap's center, "
                    + "refined, in ticks), coarse_offset (the match before the refinement), "
                    + "refined (\"phat\" or \"coarse\"), refine_confidence (the PHAT peak's "
                    + "z-score; null when none ran), delta, new start, "
                    + "confidence (the chosen lag's z-score), search (\"played\" or "
                    + "\"whole\"), chosen_by (\"confidence\" or \"placement\", the weak tier), "
                    + "matched_on (\"speech\" or \"sound\"), candidates "
                    + "([{offset, delta, confidence}]), trimmed (the ticks cut off its head, "
                    + "0 when none), speed (after the command), drift_ppm, drift_ms, "
                    + "drift_error_ms, drift_on (\"features\" or \"phat\": which points the "
                    + "line was fitted through), drift_windows, drift_corrected and "
                    + "residual_ms (the error left when "
                    + "corrected, the drift itself when not); every answer also carries weak "
                    + "(the clip ids of its weak moves, [] when none). A second call answers "
                    + "moved: false and \"already in sync\".",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 2,
                        "description": "The clips to line up, at least two, each on its own "
                            + "track.",
                    ],
                    "anchor": [
                        "type": "integer",
                        "description": "The clip that stays put; one of clips. Default: "
                            + "among the clips with pictures (all of them when none has), "
                            + "the earliest start, then the rearmost track, then the lowest "
                            + "id.",
                    ],
                    "accept_weak": [
                        "type": "boolean",
                        "description": "Apply a weak match — the Weak match sheet's Apply. "
                            + "Default false: a weak match answers moved: false, weak naming "
                            + "its clips, and the move each would make, and nothing changes. "
                            + "Pass true only after the person has agreed to that move.",
                    ],
                ], required: ["clips"]),
            // Road map "cut-by-transcript" CT-2 (spec §11 TR-4, TR-7, TR-9):
            // the read half of Clip ▸ Remove Filler Words… (CT-3), a
            // composite like `detect_silence`.
            tool(
                "detect_fillers",
                "Finds the filler words (\(fillers)) in the timeline's speech and REPORTS "
                    + "them as ranges, changing nothing — the read half of Clip ▸ Remove Filler "
                    + "Words…: feed ranges to ripple_delete_ranges to cut them in one undo "
                    + "step, as that sheet's Remove does. It reads only a cached AssemblyAI "
                    + "transcript that asked for filler words (spec §11 TR-7), never "
                    + "the network. Each run of consecutive fillers is widened outward to the "
                    + "32 ms Silero grid but never into the words beside it, then its edges "
                    + "snap inward to the frame grid (TR-9). A filler is dropped whole, and "
                    + "named under dropped with the reason, when it is too short once on both "
                    + "grids, when it overlaps a word of another clip on any unlocked track "
                    + "(the ripple cuts every unlocked track, in scope or not), when it crosses "
                    + "a nest clip, and when it reaches an overlap between two clips on one "
                    + "unlocked track, with a stored transition or without one, or the area "
                    + "around it, as wide again as the overlap on each side. fillers lists each "
                    + "kept run with its clip, words and range; ranges merges them. A clip on a "
                    + "locked track is not read and is named under locked, since "
                    + "ripple_delete_ranges neither cuts nor moves a locked track. Media with "
                    + "no such transcript are named under needs_transcript: "
                    + "transcribe_for_fillers makes one for a media (a paid upload).",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Read only these clips. Omit to read the project's "
                            + "current selection when it holds a clip with speech from a "
                            + "media file, every clip otherwise. The result's scope says "
                            + "which ran.",
                    ],
                ]),
            // CT-3 (spec §11 TR-10): the Transcribe button of Clip ▸ Remove
            // Filler Words…' rows, an app-state composite run off main.
            tool(
                "transcribe_for_fillers",
                "Re-transcribes ONE media with AssemblyAI so its filler words can be found — "
                    + "the Transcribe button beside a file in Clip ▸ Remove Filler Words…. It "
                    + "keeps the media's previous request (its language, speaker labels and "
                    + "vocabulary; detection, no speakers and no vocabulary when it has none), "
                    + "adds filler words, and always uploads again (a paid upload), even over a "
                    + "transcript that is current for captions. It only writes the media's "
                    + "transcript cache: no caption is placed and no undo step is made. The "
                    + "answer has ready (whether detect_fillers can now read the media), "
                    + "uploaded, cached, audio_seconds, engine, language and, when there is "
                    + "something to say, note. A media that already has a transcript made with "
                    + "filler words makes no request and answers ready true, uploaded []. "
                    + "Refused for a document with nowhere to keep its transcript cache, a "
                    + "media whose file is missing and a media no clip plays from its file. "
                    + ModelKey.assemblyAI.catalogClause
                    + ".",
                [
                    "media": [
                        "type": "integer",
                        "description": "The media to transcribe, as get_project lists it — one "
                            + "of detect_fillers' needs_transcript.",
                    ]
                ], required: ["media"]),
        ]
    }
}
