import Foundation

/// `get_media_analysis {kind: "masks"}`'s own fields (spec §11 CO-14; road map
/// "creator-jobs" CO1), from captured values on the server thread: the pack's
/// `mask_size` (the size Vision answered for the media), `frames` held in the
/// window, `subject_found`, `count` and `runs` — never pixels. A run is a
/// maximal span of consecutive pack frames inside the window and one coverage
/// range whose masks' `found` agree (`AnalysisMasks.runs`). `runs` past 512 KiB
/// of JSON is refused as `cuts` is, naming the largest `to` that fits; a pack
/// that does not read is refused naming why (packs are written only through a
/// `.partial` and a rename, so that is hand damage).
extension AgentServer {

    static func masksFields(_ call: AnalysisCall) throws -> [String: Any] {
        let grid = AnalysisGrid(media: call.media)
        let marker = AnalysisStore.readMarker(.masks, media: call.media.id, in: call.cacheDir)
        let url = AnalysisStore.payloadURL(
            .masks, media: call.media.id, file: MaskPack.fileName, in: call.cacheDir)
        guard let marker, let window = grid.indices(from: call.from, to: call.to),
            FileManager.default.fileExists(atPath: url.path)
        else {
            return ["mask_size": NSNull(), "frames": 0, "subject_found": false, "count": 0,
                    "runs": [] as [Any]]
        }
        let pack: MaskPack
        do {
            pack = try MaskPack(contentsOf: url)
        } catch {
            throw ToolError(
                message: "The masks of media \(call.media.id) could not be read: "
                    + "\(error.localizedDescription). Remove its cache/analysis/masks files to "
                    + "make them again.")
        }
        let runs = AnalysisMasks.runs(pack, window: window, coverage: marker.ranges, grid: grid)
        let rows = runs.map { run -> [String: Any] in
            ["from": run.from, "to": run.to, "subject_found": run.subjectFound,
             "frames": run.frames]
        }
        let encoded = try JSONSerialization.data(withJSONObject: rows)
        if encoded.count > analysisAnswerCap {
            var size = 2
            var fits = call.from
            for row in rows {
                size += (try JSONSerialization.data(withJSONObject: row)).count + 1
                if size > analysisAnswerCap {
                    fits = (row["from"] as? Int64) ?? call.from
                    break
                }
            }
            throw ToolError(
                message: "The mask runs from \(call.from) to \(call.to) come to "
                    + "\(encoded.count) bytes of JSON, more than the \(analysisAnswerCap) an "
                    + "answer holds; call with to at most \(fits) from from \(call.from).")
        }
        return [
            "mask_size": [pack.width, pack.height], "frames": runs.reduce(0) { $0 + $1.frames },
            "subject_found": runs.contains(where: \.subjectFound), "count": runs.count,
            "runs": rows,
        ]
    }
}
