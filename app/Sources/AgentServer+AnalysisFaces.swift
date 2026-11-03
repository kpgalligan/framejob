import Foundation

/// `get_media_analysis {kind: "faces"}`'s own fields (spec §11 CJ-34; road map
/// "creator-jobs" CJ3), from captured values on the server thread: `rate`
/// (samples a second), `count` and `samples`, one row per COVERED sample of
/// the window — `source` the sample's instant `ticks(k)`, `frame` the pts of
/// the frame it read (null: none within one sample interval), `faces` in
/// CJ-31's order, each `box` [x, y, w, h] (0…1, top-left, display
/// orientation), `confidence`, `roll`, `yaw` and, with landmarks,
/// `mouth_gap` and `mouth_width`; with `clip` also `clip_time` and `timeline`.
/// Every float is rounded to 4 decimals in the answer only (`answerValue`,
/// written as a decimal number; the cache stays raw). `samples` past 512 KiB of JSON is refused as `cuts`
/// is, naming the largest `to` that fits: the `source` of the first row that
/// does not.
extension AgentServer {

    static func facesFields(_ call: AnalysisCall) throws -> [String: Any] {
        let grid = call.kind.grid(of: call.media)
        let empty: [String: Any] = ["rate": AnalysisFaces.rate, "count": 0, "samples": [] as [Any]]
        guard let marker = AnalysisStore.readMarker(.faces, media: call.media.id, in: call.cacheDir),
            let window = grid.indices(from: call.from, to: call.to),
            let data = AnalysisStore.readPayload(
                .faces, media: call.media.id, file: AnalysisFaces.payloadName, in: call.cacheDir)
        else { return empty }
        guard let decoded = AnalysisFaces.decode(data) else {
            throw ToolError(
                message: "The faces of media \(call.media.id) could not be read: its "
                    + "\(AnalysisFaces.payloadName) is not a samples file this build reads. "
                    + "Remove its cache/analysis/faces files to make them again.")
        }
        let covered = AnalysisStore.merged(marker.ranges)
        let indices = window.filter { k in
            k < decoded.samples.count && covered.contains { $0.contains(k) }
        }
        return try facesAnswer(
            decoded.samples, indices: indices, grid: grid, clip: call.clip,
            landmarks: AnalysisFaces.landmarks, from: call.from, to: call.to)
    }

    /// Pure: the rows for samples `indices` (covered, inside the window),
    /// rounded, capped.
    static func facesAnswer(
        _ samples: [AnalysisFaces.Sample], indices: [Int], grid: AnalysisGrid,
        clip: AnalysisClipTimes?, landmarks: Bool, from: Ticks, to: Ticks
    ) throws -> [String: Any] {
        let number = answerNumber
        let rows = indices.map { k -> [String: Any] in
            let sample = samples[k]
            let source = grid.ticks(of: k)
            var row: [String: Any] = [
                "source": source, "frame": sample.pts >= 0 ? sample.pts as Any : NSNull(),
                "faces": sample.faces.map { face -> [String: Any] in
                    var out: [String: Any] = [
                        "box": [face.x, face.y, face.width, face.height].map(number),
                        "confidence": number(face.confidence), "roll": number(face.roll),
                        "yaw": number(face.yaw),
                    ]
                    if landmarks {
                        out["mouth_gap"] = number(face.mouthGap)
                        out["mouth_width"] = number(face.mouthWidth)
                    }
                    return out
                },
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
                message: "The face samples from \(from) to \(to) come to \(encoded.count) bytes "
                    + "of JSON, more than the \(analysisAnswerCap) an answer holds; call with to "
                    + "at most \(fits) from from \(from).")
        }
        return ["rate": AnalysisFaces.rate, "count": rows.count, "samples": rows]
    }

    /// A Float32 as an answer writes it (faces', sound events'): `answerValue`
    /// as an `NSDecimalNumber`, NaN as null. `JSONSerialization` prints a
    /// Double to 17 significant figures, so the rounded value goes out as the
    /// decimal its shortest form spells, read with a "." separator whatever
    /// the Mac's locale.
    static func answerNumber(_ value: Float) -> Any {
        answerValue(value).map {
            NSDecimalNumber(string: String($0), locale: Locale(identifier: "en_US_POSIX"))
        } ?? NSNull()
    }

    /// A Float32 as the answer prints it: nil for NaN, else rounded to 4
    /// decimals as a Double (≤ 0.4 px of a 4K frame's width).
    static func answerValue(_ value: Float) -> Double? {
        guard value.isFinite else { return nil }
        return (Double(value) * 10_000).rounded() / 10_000
    }
}
