import Foundation

/// What `export`'s answer carries beyond the resolved settings: facts about
/// the file that was written, read off the `Exporter` once it has finished
/// (`AgentServer+Export.swift`'s `exportProject` adds them to its result).
extension AgentServer {

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
    /// It is read off the `Exporter` this stack still holds, after the
    /// semaphore the completion signalled: `Exporter.finish` publishes the
    /// report before it calls back, and it is documented there as never
    /// cleared, so both consumers (this and the progress sheet) read it after
    /// their completion has fired.
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
    /// when there was none. Read off the `Exporter` after the completion,
    /// as `loudnessResult` is: `Exporter.finish` publishes it before the
    /// unpin, and only the next `export` clears it. A failed export answers
    /// as it did.
    static func graphicWarningsResult(_ warnings: [ExportGraphicWarning]) -> [[String: Any]]? {
        guard !warnings.isEmpty else { return nil }
        return warnings.map {
            ["name": $0.name, "frame": $0.frame ?? NSNull(), "message": $0.message] as [String: Any]
        }
    }
}
