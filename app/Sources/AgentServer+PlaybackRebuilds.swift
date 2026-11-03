import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `playback_rebuilds` — a dev tool (road map "creator-jobs" SW0, spec §11 SW-1): a project's
/// editor window's preview rebuilds since the last reset, each with its `built_ms` and
/// `landed_ms` from `PlaybackRebuildLog`. What `rebuild_log_proof.py` and SW-S2 (b)
/// (`creator_spike/angles_spike.py`) time a structural edit's rebuild with. It mirrors no edit:
/// the log is a measurement, and nothing in the app shows it.
///
/// It runs on MAIN (it is not in `devOffMainTools`): the log is main-thread state, and the
/// answer takes no wait.
extension AgentServer {

    func playbackRebuilds(_ a: [String: Any]) throws -> String {
        let reset = try boolArg(a, "reset") ?? false
        let document = try target(a)
        guard let editor = editor(document) else {
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            throw ToolError(
                message: "The project \(name) has no window: playback_rebuilds reads only its "
                    + "editor window's rebuilds.")
        }
        let playback = editor.playback
        let log = playback.rebuildLog
        if reset { log.reset() }
        // Written by hand so the keys keep the documented order (`JSONSerialization` keeps
        // none) and each time prints rounded to 0.1 ms.
        func ms(_ value: Double?) -> String {
            guard let value, value.isFinite else { return "null" }
            return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
        let rows = log.entries.map {
            "{\"generation\":\($0.generation),\"built_ms\":\(ms($0.builtMs)),"
                + "\"landed_ms\":\(ms($0.landedMs))}"
        }
        let text = "{\"count\":\(log.count),\"rebuilding\":\(playback.rebuilding),"
            + "\"rebuilds\":[\(rows.joined(separator: ","))]}"
        return try callResult(content: [["type": "text", "text": text]], isError: false)
    }

    // MARK: - Catalog

    func playbackRebuildsTool() -> [String: Any] {
        tool(
            "playback_rebuilds",
            "DEV TOOL (absent from Distribution builds). Answer a project's editor window's "
                + "preview rebuilds (spec SW-1): a structural edit (one that changes the "
                + "composition plan or the audio DSP) builds a new player item off the main "
                + "thread and lands it with a restore seek. count (rebuilds built since the "
                + "last reset; the list keeps the last 256), rebuilding (a rebuild in flight), "
                + "and rebuilds, oldest first, each {generation, built_ms, landed_ms}: "
                + "milliseconds from the rebuild's start to its build and to the first seek "
                + "landing after it, rounded to 0.1; landed_ms is null until it lands. A "
                + "rebuild superseded by a newer one before it built is never an entry. reset: "
                + "true empties the list and the count first. The dev-only launch default "
                + "-RCDevRebuildHold <s> delays each rebuild's landing by s seconds. Refused, "
                + "changing nothing: a project with no editor window.",
            [
                "reset": [
                    "type": "boolean",
                    "description": "Empty the list and zero the count before answering. "
                        + "Default false.",
                ]
            ])
    }
}
#endif
