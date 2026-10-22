import Foundation

/// What a finished export's answer carries: the resolved settings and the
/// facts about the file that was written, read off the queue's job once it
/// has finished — `export_status`'s `done` answer
/// (`AgentServer+ExportStatus.swift`), which since spec §11 #326 is what
/// `export` itself answered before it returned at once.
extension AgentServer {

    /// The `done` answer's keys, exactly the ones `export` answered when it
    /// blocked to the file. `bytes` is the file's size as read at the finish.
    static func exportResult(
        settings: ExportSettings, burnInTimecode: Bool, path: String, bytes: Int,
        loudness: ExportLoudness?, graphicWarnings: [ExportGraphicWarning]
    ) -> [String: Any] {
        var result: [String: Any] = [
            "ok": true,
            "path": path,
            "bytes": bytes,
            "preset": settings.preset,
            "container": settings.container,
            "codec": settings.codec,
            "width": settings.width,
            "height": settings.height,
            "fps": [settings.fps.num, settings.fps.den],
            "start": settings.start,
            "duration": settings.duration,
            // Not one of the resolved settings — the core never saw it — but
            // it is a fact about the file that was written, and every other
            // key here is one too.
            //
            // What it establishes is exactly one link and not the chain: this
            // is `options.burnInTimecode`, the local decoded a few lines up,
            // so a caller reading it back knows the argument was READ rather
            // than dropped in argument reading — the failure `boolArg`'s
            // refusal covers from the other side. It does NOT say the writer
            // used it; only a pixel can say that, and
            // `tools/proof/phase7_proof.py` is where one does.
            "burn_in_timecode": burnInTimecode,
        ]
        // The picture an HLG project's file was written as (`hlg`, `pq` or
        // `sdr`); absent for every SDR project and audio row.
        if let color = settings.color {
            result["dynamic_range"] = color
        }
        if let measured = loudnessResult(loudness) {
            result["loudness"] = measured
        }
        if let warned = graphicWarningsResult(graphicWarnings) {
            result["graphic_warnings"] = warned
        }
        return result
    }

    /// What the export's sound MEASURED, for the result — nil, and then the
    /// key is simply absent, wherever `Exporter` published no report: a
    /// format that holds no audio track at all (GIF and APNG), and a
    /// timeline with no sound in it, which is the case a caller actually
    /// meets. A missing `loudness` is therefore "there was nothing to
    /// measure", never "the measurement was skipped".
    ///
    /// This is `detect_silence`'s posture applied to the writer: the numbers
    /// are read back off the file's own mix rather than repeated from the
    /// request, so a caller can check that a −14 LUFS export actually landed
    /// at −14, which is what makes phase 5's ±0.5 LU claim a claim anyone can
    /// test over MCP. `target` is what was ASKED for and is absent when
    /// nothing was — every export measures itself and reports, normalised or
    /// not.
    ///
    /// It is read off the queue's job (`ExportQueueController.Job.loudness`),
    /// which `finished` copies from the `Exporter` before dropping it:
    /// `Exporter.finish` publishes the report before it calls back, so every
    /// consumer (this, the queue's row and the progress sheet) reads it after
    /// the completion has fired.
    ///
    /// Every level goes through `jsonLevel`: a silent programme measures
    /// −∞ dBTP, and `JSONSerialization` throws on an infinity — which would
    /// report a successful export as a failed tool call.
    static func loudnessResult(_ report: ExportLoudness?) -> [String: Any]? {
        guard let report = report else { return nil }
        var measured: [String: Any] = [
            // The same sentence the progress sheet's last line shows, so the
            // two consumers of one measurement cannot describe it differently.
            "summary": report.summary,
            "true_peak_dbtp": jsonLevel(report.truePeakDBTP),
            "sample_peak_dbfs": jsonLevel(report.measured.samplePeakDBFS + report.gainDB),
            "gain_db": report.gainDB,
            "ceiling_dbtp": jsonLevel(report.ceiling),
            "capped_by_peak": report.cappedByPeak,
        ]
        // Absent rather than null, and for a reason worth the line: a
        // programme shorter than one 400 ms gating block, or one whose every
        // block fell under the standard's absolute gate, HAS no integrated
        // loudness. `summary` says so in words.
        if let integrated = report.integratedLUFS, integrated.isFinite {
            measured["integrated_lufs"] = integrated
        }
        if let target = report.target {
            measured["target_lufs"] = target
        }
        return measured
    }

    /// Each distinct warning the export's graphics gave while the file was
    /// drawn (G-24 (c)), `[{name, frame, message}]` — `frame` the graphic's
    /// own, null when it has none — or nil, and then the key is absent,
    /// when there was none. Read off the queue's job after the completion,
    /// as `loudnessResult` is: `Exporter.finish` publishes it before the
    /// unpin. A failed export answers as it did.
    static func graphicWarningsResult(_ warnings: [ExportGraphicWarning]) -> [[String: Any]]? {
        guard !warnings.isEmpty else { return nil }
        return warnings.map {
            ["name": $0.name, "frame": $0.frame ?? NSNull(), "message": $0.message] as [String: Any]
        }
    }
}
