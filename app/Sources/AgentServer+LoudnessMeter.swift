import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `loudness_meter` — a dev tool (road map "audio" AP7, spec §11 AU-77): the
/// live loudness meter's reading of a project's editor window, read while
/// `play_preview` plays it, and its Reset. What `audio_ap7_proof.py` checks
/// the meter against an export with. It mirrors no edit: the meter's column
/// (View ▸ Loudness Meter) and its Reset button are view state.
///
/// It runs on MAIN (it is not in `devOffMainTools`): `LiveLoudness` is
/// main-thread state, and the answer takes no wait.
extension AgentServer {

    func loudnessMeter(_ a: [String: Any]) throws -> String {
        let reset = try boolArg(a, "reset") ?? false
        let document = try target(a)
        guard let editor = editor(document) else {
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            throw ToolError(
                message: "The project \(name) has no window: loudness_meter reads only its "
                    + "editor window's meter.")
        }
        let playback = editor.playback
        if reset { playback.loudness.reset(.manual) }
        let reading = playback.loudness.reading
        func level(_ value: Double?) -> Any {
            guard let value else { return NSNull() }
            return value.isFinite ? value : (value < 0 ? "-inf" : "inf")
        }
        return try jsonResult([
            "measuring": reading.measuring,
            "rate": Double(playback.rate),
            "momentary_lufs": level(reading.momentaryLUFS),
            "short_term_lufs": level(reading.shortTermLUFS),
            "integrated_lufs": level(reading.integratedLUFS),
            "true_peak_dbtp": level(reading.truePeakDBTP),
            "from_frame": reading.fromFrame.map { $0 as Any } ?? NSNull(),
            "to_frame": reading.toFrame.map { $0 as Any } ?? NSNull(),
            "sample_rate": reading.sampleRate.map { $0 as Any } ?? NSNull(),
            "resets": reading.resets,
            "last_reset": reading.lastReset.map { $0.rawValue as Any } ?? NSNull(),
            "tracks_approximate": reading.tracksApproximate,
        ])
    }

    // MARK: - Catalog

    func loudnessMeterTool() -> [String: Any] {
        tool(
            "loudness_meter",
            "DEV TOOL (absent from Distribution builds). Answer the live loudness meter of a "
                + "project's editor window (View ▸ Loudness Meter; spec AU-70..AU-77): the true "
                + "mix as the preview plays it, measured only at ×1. measuring (frames summed "
                + "within the last 0.15 s), rate (the transport's), momentary_lufs (the last "
                + "400 ms block), short_term_lufs (the last 3 s), integrated_lufs (BS.1770-4 "
                + "gated, since the last reset), true_peak_dbtp (the 4× true-peak maximum since "
                + "the reset), from_frame and to_frame (the frames measured, [from, to), at "
                + "sample_rate, the taps' rate), resets (how many since the window opened) and "
                + "last_reset (manual, jump or overrun), and tracks_approximate (the build runs "
                + "track compressors or limiters, which the preview runs approximately, spec "
                + "AU-153). A level is null where there is none "
                + "and \"-inf\" for digital silence; the frames and rate are null before "
                + "anything is measured. reset: true resets the meter first, as the column's "
                + "Reset does. Refused, changing nothing: a project with no editor window.",
            [
                "reset": [
                    "type": "boolean",
                    "description": "Reset the meter (reason manual) before answering. Default "
                        + "false.",
                ]
            ])
    }
}
#endif
