import AppKit

/// The agent's silence tool: the read half of Remove Silences.
///
/// `detect_silence` is an APP-STATE tool, not an op — it changes nothing and
/// registers no undo step. It exists because the detection is Swift's (the
/// waveform peaks the package caches are not in the model, and the core does
/// no sample work at all — spec §7), so an agent that could only call
/// `ripple_delete_ranges` would have to invent the ranges from nothing. The
/// pair is deliberate and mirrors the sheet exactly: `detect_silence` is what
/// `SilenceSheetController` shows in its live readout, and
/// `ripple_delete_ranges` is what its Remove button sends.
///
/// It stays on the MAIN thread, and so out of `AgentServer.offMainTools`,
/// because that set's criterion is "waits for something the main thread has
/// to deliver or must not be doing", not "touches the disk":
/// `consolidate_media` copies whole media libraries on main and says why, and
/// `import_captions` parses a file on main for the same reason. Reading a few
/// hundred KB of `cache/peaks/<id>.bin` and making one arithmetic pass over
/// it waits on nothing and has no completion to deliver, and being off main
/// would cost an `onMain` hop for every document touch — which is where the
/// real bugs in this file's neighbours have been.
extension AgentServer {

    /// The longest a duration argument may be, `snappedTick`'s own ±9.0e15:
    /// past it `refine`'s `run.start + padding` overflows. Finding 1 above.
    /// Not private: `AgentCatalog+Audio` PUBLISHES it as both durations'
    /// `maximum`, so the bound a caller reads and the bound the handler
    /// enforces are one number (the second sceptic pass, road map 4 §8).
    static let durationCeiling = 9_000_000_000_000_000

    /// `detect_silence` — Clip ▸ Remove Silences…
    /// (`SilenceSheetController`, whose four controls are these four
    /// arguments and whose live "N cuts · removes M:SS" line is this
    /// result). Nothing is edited: feed `ranges` to `ripple_delete_ranges`
    /// to make the cut, which is what that sheet's button does.
    ///
    /// Quiet is measured IN THE MIX — the peak bucket times the plan's audio
    /// envelope at that tick — so a clip turned down, faded, ducked, muted or
    /// silenced by another track's solo is quiet here exactly as it is in the
    /// speakers. A tick no clip in scope covers is not a candidate at all: a
    /// hole in the timeline is not dead air to be removed.
    func detectSilence(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try optionalClipsArg(a, "clips", document)
        // `clips` is the sheet's scope popup, spelled as the thing an agent
        // actually has: ids. Naming any runs the popup's "Selected clips"
        // over exactly those — `read` takes a selection override for this
        // very reason — and omitting the key takes the sheet's own opening
        // rule, which is the document's selection when it holds anything
        // with sound and everything audible otherwise. The result reports
        // which of the two answered, because "nothing was found" and
        // "nothing was looked at" are different answers and no caller can
        // tell them apart from an empty list.
        guard let input = SilenceDetector.read(from: document, selection: clips.map { Set($0) })
        else {
            throw ToolError(
                message: "The project's audio plan could not be read, so there is nothing to "
                    + "measure silence against.")
        }
        let (settings, modeNote) = try silenceSettings(
            a, scope: clips == nil ? input.defaultScope : .selected,
            voiceAvailable: input.voiceAvailable)
        let outcome = SilenceDetector.detect(input, settings: settings)

        var result: [String: Any] = [
            "ok": true,
            "ranges": outcome.spans.map { [$0.start, $0.end] },
            "count": outcome.spans.count,
            "removes": outcome.removed,
            "scope": outcome.scope.rawValue,
            "clips": outcome.clips.map { Int($0) },
            "threshold_db": settings.thresholdDB,
            "min_length": settings.minLength,
            "padding": settings.padding,
            "mode": outcome.mode.rawValue,
            "voice_confidence": settings.voiceConfidence,
            "judged_by_level": outcome.judgedByLevel.map { Int($0) },
        ]
        var notes: [String] = []
        if let modeNote { notes.append(modeNote) }
        // Two things worth a sentence rather than a silent zero, because both
        // read as "there is no dead air here" and neither is that.
        if outcome.clips.isEmpty {
            notes.append(
                settings.scope == .selected
                ? "None of those clips plays any sound, so nothing was analysed."
                : "Nothing in this timeline is audible, so nothing was analysed.")
        }
        // Both waiters fold into ONE key, `pending_peaks` — the union of what
        // the level test and the voice test are each still waiting on — so a
        // caller that only ever read that key still knows to call again.
        let pendingPeaks = Set(outcome.pendingMedia)
        let pendingUnion = outcome.mode == .voice
            ? pendingPeaks.union(outcome.voicePending) : pendingPeaks
        if !pendingUnion.isEmpty {
            result["pending_peaks"] = pendingUnion.sorted().map { Int($0) }
            // "Nothing inside them is proposed for removal" is a PROMISE about
            // the ranges in this same reply, so it is made only about the
            // media it holds for. A media with no peaks is never quiet in
            // LEVEL mode, so there it holds for every waiter; in VOICE mode a
            // media whose waveform is missing but whose speech has landed is
            // judged by the model and spans inside it ARE proposed — and the
            // sentence used to deny exactly the ranges it was printed beside
            // (the reader review, road map 4 §8, R3·1).
            let waiter = outcome.mode == .voice ? Set(outcome.voicePending) : pendingPeaks
            // And the promise is made about what this ANSWER shows, not about
            // the mode: the gain FLOOR is asked before either cache
            // (`SilenceDetector.isQuiet`), so a clip the mix has turned down,
            // faded, ducked or muted is quiet with nothing on disk at all and
            // its spans are right here (the reader review, road map 4 §8,
            // finding 2). Whatever the answer proposes inside is dropped from
            // the promise and counted in its own clause.
            let proposedInside = waiter.intersection(outcome.proposedMedia)
            let blocked = waiter.subtracting(proposedInside)
            let waveformOnly = pendingUnion.subtracting(waiter)
            var waiting =
                "Analysis is still running for \(pendingUnion.count) media file(s); call "
                + "again in a moment."
            if !blocked.isEmpty {
                waiting += blocked.count == pendingUnion.count
                    ? " Nothing inside them is proposed for removal."
                    : " Nothing inside \(blocked.count) of them is proposed for removal."
            }
            if !proposedInside.isEmpty {
                waiting +=
                    " \(Self.subject(proposedInside.count, of: pendingUnion.count, verb: "hold")) "
                    + "spans that ARE proposed here: the mix turns them down far enough to be "
                    + "quiet before either cache is asked."
            }
            if !waveformOnly.isEmpty {
                // The mirror image of the promise above, and it needs the
                // same intersection (the reader review's second sceptic pass,
                // road map 4 §8). "Spans inside them ARE proposed here" is a
                // claim about ranges in this very reply, so a waveform waiter
                // the answer proposes NOTHING inside — every clip of it holds
                // no voice, so the missing waveform blocks the lot — must not
                // be told it has them.
                let proposedHere = waveformOnly.intersection(outcome.proposedMedia)
                let silentHere = waveformOnly.subtracting(proposedHere)
                let ending: String
                if silentHere.isEmpty {
                    ending = ", so spans inside them ARE proposed here."
                } else if proposedHere.isEmpty {
                    ending = ", and nothing inside them is proposed here."
                } else {
                    ending =
                        ", so spans inside \(proposedHere.count) of them ARE proposed here "
                        + "and nothing inside the other \(silentHere.count) is."
                }
                waiting +=
                    " For \(Self.subject(waveformOnly.count, of: pendingUnion.count)) it is the "
                    + "WAVEFORM that has not landed, which in voice mode decides only a clip "
                    + "holding no voice" + ending
                // And where those spans are the FLOOR's rather than the
                // model's, say so: a clip of a by-level media is proposed
                // without its waveform only because the mix already turned it
                // down. No `voicePending` arm is needed here — a voice waiter
                // is in `waiter` above and never in `waveformOnly`.
                if !proposedHere.intersection(outcome.judgedByLevel).isEmpty {
                    waiting +=
                        " A clip there that holds no voice is proposed only where the mix "
                        + "already turns it down far enough to be quiet."
                }
            }
            notes.append(waiting)
        }
        if !outcome.voicePending.isEmpty {
            result["voice_pending"] = outcome.voicePending.map { Int($0) }
        }
        if !outcome.judgedByLevel.isEmpty {
            notes.append(
                "\(outcome.judgedByLevel.count) media file(s) hold no voice in at least one "
                    + "clip and were judged by level there.")
        }
        if !notes.isEmpty { result["note"] = notes.joined(separator: " ") }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// "that file" / "them" / "2 of them", so a clause about SOME of the
    /// waiters never says "the rest" of a sentence that was not printed
    /// (the reader review, road map 4 §8, finding 4). `verb` is the third
    /// person the clause needs when the subject is what HOLDS something.
    private static func subject(_ count: Int, of total: Int, verb: String? = nil) -> String {
        let noun = count == total ? (count == 1 ? "that file" : "them") : "\(count) of them"
        guard let verb else { return noun }
        return noun == "that file" ? "That file \(verb)s" : "\(noun) \(verb)"
    }

    /// The three numbers, read in the sheet's own units and refused by name.
    ///
    /// The sheet clamps its controls to `Settings`' published ranges because
    /// a slider must land somewhere; a tool does not, and clamping an
    /// argument silently would report a detection the caller did not ask
    /// for. What is refused here is what is not a level or not a length at
    /// all — everything else is passed through and named back in the result,
    /// so a caller reading `threshold_db` sees what actually ran.
    private func silenceSettings(
        _ a: [String: Any], scope: SilenceDetector.Scope, voiceAvailable: Bool
    ) throws -> (SilenceDetector.Settings, String?) {
        var settings = SilenceDetector.Settings(scope: scope)
        var note: String?
        if let modeString = try stringArg(a, "mode") {
            guard let mode = SilenceDetector.Mode(rawValue: modeString) else {
                throw ToolError(
                    message: "mode must be \"voice\" or \"level\".")
            }
            if mode == .voice, !voiceAvailable {
                throw ToolError(
                    message: "The voice model could not be used; call with mode: \"level\".")
            }
            settings.mode = mode
        } else if !voiceAvailable {
            settings.mode = .level
            note = "The voice model could not be used, so quiet is judged by level."
        }
        if let voiceConfidence = try doubleArg(a, "voice_confidence") {
            guard settings.mode == .voice else {
                throw ToolError(
                    message: "voice_confidence only applies in mode: \"voice\".")
            }
            guard voiceConfidence.isFinite,
                SilenceDetector.Settings.voiceConfidenceRange.contains(voiceConfidence)
            else {
                throw ToolError(
                    message: "voice_confidence must be a number in "
                        + "\(SilenceDetector.Settings.voiceConfidenceRange.lowerBound)…"
                        + "\(SilenceDetector.Settings.voiceConfidenceRange.upperBound).")
            }
            settings.voiceConfidence = voiceConfidence
        }
        if let thresholdDB = try doubleArg(a, "threshold_db") {
            // Above full scale every bucket of every recording counts as
            // quiet and the whole timeline comes back as one candidate.
            // Peaks are unclamped and a hot source really does read over
            // 1.0, so this is a caller's mistake — a level in gain, or a
            // sign forgotten — rather than an impossible number.
            guard thresholdDB.isFinite, thresholdDB <= 0 else {
                throw ToolError(
                    message: "threshold_db must be a level at or below 0 dBFS (full scale); "
                        + "the default is \(SilenceDetector.Settings.defaultThresholdDB).")
            }
            settings.thresholdDB = thresholdDB
        }
        // Both lengths are DURATIONS, and a duration is not a position: they
        // are read as given, by the whole-number reader, and are NOT snapped
        // to the frame grid. The sheet's own two fields are not snapped
        // either (`SilenceSheetController.silenceSettings`'
        // `ReelTime.ticks(seconds:)`) and this tool exists to mirror it; the
        // frame rule stays where it belongs, on the span BOUNDS `refine`
        // produces, so no sub-frame time reaches an op from here. Going
        // through `optionalTimeArg` cost that mirror at the DEFAULT rate:
        // at 30 fps it ran `padding: 30000` — the sheet's own 0.05 s — as
        // 40000, ran `min_length: 45000` as 40000, and dropped
        // `padding: 9999` to 0, cutting the material the caller asked to
        // keep (the reader review, road map 4 §8, R1·1).
        //
        // What `optionalTimeArg` DID carry and a duration still needs is its
        // CEILING: `refine` adds the padding to a run's start, and a padding
        // at `Int64.max` overflowed and killed the app rather than answering
        // (the reader review, road map 4 §8, finding 1). The bound is
        // `snappedTick`'s own ±9.0e15, refused in a sentence naming the
        // argument. The sheet's two fields cannot reach it — they clamp to
        // `minLengthRange` and `paddingRange` — so the guard belongs here,
        // on the one caller that is not a slider.
        if let minLength = try intArg(a, "min_length") {
            guard minLength >= 0, minLength <= Self.durationCeiling else {
                throw ToolError(
                    message: "min_length must be a length in ticks (600000 per second) from 0 "
                        + "to \(Self.durationCeiling).")
            }
            settings.minLength = Ticks(minLength)
        }
        if let padding = try intArg(a, "padding") {
            guard padding >= 0, padding <= Self.durationCeiling else {
                throw ToolError(
                    message: "padding must be a length in ticks (600000 per second) from 0 "
                        + "to \(Self.durationCeiling).")
            }
            settings.padding = Ticks(padding)
        }
        return (settings, note)
    }
}
