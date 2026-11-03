import Foundation

/// `get_media_analysis {kind: "subjects"}`'s own fields (spec §11 VR-14; road
/// map "creator-jobs" VR1), from captured values on the server thread: `rate`
/// (samples a second), `count` and `samples`, one row per COVERED sample of
/// the window — `source` the sample's instant `ticks(k)`, `frame` the pts of
/// the frame it read (null: none within one sample interval), `people` and
/// `salient`, each `[{box: [x, y, w, h], confidence}]` (0…1, top-left, display
/// orientation, in CJ-31's order); with `clip` also `clip_time` and `timeline`.
/// Every float goes out through `answerNumber` (`faces`' rounding, CJ-34).
/// `samples` past 512 KiB of JSON is refused as `faces`' are, naming the
/// largest `to` that fits: the `source` of the first row that does not.
extension AgentServer {

    static func subjectsFields(_ call: AnalysisCall) throws -> [String: Any] {
        let grid = call.kind.grid(of: call.media)
        let empty: [String: Any] = [
            "rate": AnalysisSubjects.rate, "count": 0, "samples": [] as [Any],
        ]
        guard
            let marker = AnalysisStore.readMarker(
                .subjects, media: call.media.id, in: call.cacheDir),
            let window = grid.indices(from: call.from, to: call.to),
            let data = AnalysisStore.readPayload(
                .subjects, media: call.media.id, file: AnalysisSubjects.payloadName,
                in: call.cacheDir)
        else { return empty }
        guard let decoded = AnalysisSubjects.decode(data) else {
            throw ToolError(
                message: "The subjects of media \(call.media.id) could not be read: its "
                    + "\(AnalysisSubjects.payloadName) is not a samples file this build reads. "
                    + "Remove its cache/analysis/subjects files to make them again.")
        }
        let covered = AnalysisStore.merged(marker.ranges)
        let indices = window.filter { k in
            k < decoded.samples.count && covered.contains { $0.contains(k) }
        }
        return try subjectsAnswer(
            decoded.samples, indices: indices, grid: grid, clip: call.clip, from: call.from,
            to: call.to)
    }

    /// Pure: the rows for samples `indices` (covered, inside the window),
    /// rounded, capped.
    static func subjectsAnswer(
        _ samples: [AnalysisSubjects.Sample], indices: [Int], grid: AnalysisGrid,
        clip: AnalysisClipTimes?, from: Ticks, to: Ticks
    ) throws -> [String: Any] {
        func boxes(_ list: [AnalysisSubjects.Box]) -> [[String: Any]] {
            list.map { box in
                [
                    "box": [box.x, box.y, box.width, box.height].map(answerNumber),
                    "confidence": answerNumber(box.confidence),
                ]
            }
        }
        let rows = indices.map { k -> [String: Any] in
            let sample = samples[k]
            let source = grid.ticks(of: k)
            var row: [String: Any] = [
                "source": source, "frame": sample.pts >= 0 ? sample.pts as Any : NSNull(),
                "people": boxes(sample.subjects.people),
                "salient": boxes(sample.subjects.salient),
            ]
            if let clip {
                let time = clip.clipTime(ofSource: source)
                row["clip_time"] = time
                row["timeline"] = clip.start + time
            }
            return row
        }
        let encoded = try JSONSerialization.data(withJSONObject: rows)
        if encoded.count > analysisAnswerCap {
            var size = 2
            var fits = from
            for row in rows {
                size += (try JSONSerialization.data(withJSONObject: row)).count + 1
                if size > analysisAnswerCap {
                    fits = (row["source"] as? Ticks) ?? from
                    break
                }
            }
            throw ToolError(
                message: "The subject samples from \(from) to \(to) come to \(encoded.count) "
                    + "bytes of JSON, more than the \(analysisAnswerCap) an answer holds; call "
                    + "with to at most \(fits) from from \(from).")
        }
        return ["rate": AnalysisSubjects.rate, "count": rows.count, "samples": rows]
    }
}
