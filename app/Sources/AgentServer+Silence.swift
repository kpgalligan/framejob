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
        let settings = try silenceSettings(
            a, document, scope: clips == nil ? input.defaultScope : .selected)
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
        ]
        // Two things worth a sentence rather than a silent zero, because both
        // read as "there is no dead air here" and neither is that.
        if outcome.clips.isEmpty {
            result["note"] =
                settings.scope == .selected
                ? "None of those clips plays any sound, so nothing was analysed."
                : "Nothing in this timeline is audible, so nothing was analysed."
        } else if !outcome.pendingMedia.isEmpty {
            // The peaks cache is written by a fire-and-forget task at open
            // (`ProjectDocument.generateCaches`), so a project opened seconds
            // ago or a just-relinked movie has none yet. The detector treats
            // a media with no peaks as NEVER quiet — proposing to delete a
            // whole clip because its waveform has not landed is the one
            // failure this feature must not have — so the honest report is
            // "ask again in a moment", not a short list.
            result["pending_peaks"] = outcome.pendingMedia.map { Int($0) }
            result["note"] =
                "The waveform is still being analysed for \(outcome.pendingMedia.count) media "
                + "file(s). Nothing inside them is proposed for removal; call again in a moment."
        }
        result["project"] = summary(document)
        return try jsonResult(result)
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
        _ a: [String: Any], _ document: ProjectDocument, scope: SilenceDetector.Scope
    ) throws -> SilenceDetector.Settings {
        var settings = SilenceDetector.Settings(scope: scope)
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
        // Both lengths go through `optionalTimeArg`, so they land on the
        // frame grid like every other tick that reaches this side. A
        // duration does not have to be on the grid the way a position does,
        // but the spans this produces are snapped to it anyway, and one
        // reader for every time argument is what keeps the snapping rule from
        // drifting into a second copy.
        if let minLength = try optionalTimeArg(a, "min_length", document) {
            guard minLength >= 0 else {
                throw ToolError(message: "min_length must not be negative.")
            }
            settings.minLength = minLength
        }
        if let padding = try optionalTimeArg(a, "padding", document) {
            guard padding >= 0 else {
                throw ToolError(message: "padding must not be negative.")
            }
            settings.padding = padding
        }
        return settings
    }
}
