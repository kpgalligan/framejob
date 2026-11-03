import Foundation

/// `get_media_analysis {kind: "sound_events"}`'s own fields (spec §11 FC-33;
/// road map "creator-jobs" FC3), from captured values on the server thread:
/// `window` and `hop` in ticks, `groups` (each its `name`, `labels`,
/// `first_class` and applied `threshold`, null while weak), `count` and
/// `windows`, one row per COVERED window whose start `source` (k × hop, the
/// forward media's source ticks) lies in [from, to): `source` and the six
/// groups' confidences, rounded to 4 decimals in the answer only
/// (`answerNumber`; null where Sound Analysis gave none); with `clip` also
/// `clip_time` and `timeline`. Past 512 KiB of JSON it is refused as faces'
/// samples are, naming the `source` of the first row that does not fit.
extension AgentServer {

    static func soundEventsFields(_ call: AnalysisCall) throws -> [String: Any] {
        let grid = call.kind.grid(of: call.media)
        guard
            let marker = AnalysisStore.readMarker(
                .soundEvents, media: call.media.id, in: call.cacheDir),
            let window = grid.indices(from: call.from, to: call.to),
            let data = AnalysisStore.readPayload(
                .soundEvents, media: call.media.id, file: SoundEvents.payloadName,
                in: call.cacheDir)
        else {
            return try soundEventsAnswer(
                [], indices: [], grid: grid, clip: call.clip, from: call.from, to: call.to)
        }
        guard let windows = SoundEvents.decode(data) else {
            throw ToolError(
                message: "The sound events of media \(call.media.id) could not be read: its "
                    + "\(SoundEvents.payloadName) is not a windows file this build reads. "
                    + "Remove its cache/analysis/sound_events files to make them again.")
        }
        let covered = AnalysisStore.merged(marker.ranges)
        let indices = window.filter { k in
            k < windows.count && covered.contains { $0.contains(k) }
        }
        return try soundEventsAnswer(
            windows, indices: indices, grid: grid, clip: call.clip, from: call.from, to: call.to)
    }

    /// Pure: the rows for windows `indices` (covered, inside the window),
    /// rounded, capped.
    static func soundEventsAnswer(
        _ windows: [SoundEvents.Window], indices: [Int], grid: AnalysisGrid,
        clip: AnalysisClipTimes?, from: Ticks, to: Ticks
    ) throws -> [String: Any] {
        let rows = indices.map { k -> [String: Any] in
            let source = grid.ticks(of: k)
            var row: [String: Any] = ["source": source]
            for group in SoundEvents.Group.allCases {
                row[group.rawValue] = answerNumber(windows[k].value(group))
            }
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
                message: "The sound event windows from \(from) to \(to) come to "
                    + "\(encoded.count) bytes of JSON, more than the \(analysisAnswerCap) an "
                    + "answer holds; call with to at most \(fits) from from \(from).")
        }
        let groups = SoundEvents.Group.allCases.map { group -> [String: Any] in
            let threshold = SoundEvents.thresholds[group]
            return [
                "name": group.rawValue, "labels": SoundEvents.labels[group] ?? [],
                "first_class": threshold != nil,
                "threshold": threshold.map { $0 as Any } ?? NSNull(),
            ]
        }
        return [
            "window": SoundEvents.windowTicks, "hop": SoundEvents.hopTicks, "groups": groups,
            "count": rows.count, "windows": rows,
        ]
    }
}
