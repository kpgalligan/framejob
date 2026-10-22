import Foundation

#if FRAMEJOB_DEV_TOOLS
/// `graphic_memory` — a dev tool (issue #127, spec §11 G-37): the graphic
/// rasters' one memory budget, what the sessions hold ahead and what the
/// documents keep, read out of `GraphicPrefetch.memoryReport`. What
/// `graphic_memory_proof.py` measures the budget and the kept frames with.
///
/// It runs OFF MAIN (`devOffMainTools`): it touches no AppKit state, and
/// `GraphicPrefetch` takes its own lock. It needs no project.
///
/// **The argument is read and refused before anything moves.** `pressure`
/// sets a SIMULATED memory-pressure level first (`setPressure(_:simulated:)`),
/// which holds against the system's real events until the tool sets
/// `normal`; that clears the simulation and applies the last real level.
/// Every answer resets the held peaks to the current totals, and the count of
/// marked frames a trim pushed out (`ahead_evicted`, G-38) to 0.
extension AgentServer {

    func graphicMemory(_ a: [String: Any]) throws -> String {
        let levels = MemoryPressure.allCases.map(\.rawValue)
        var level: MemoryPressure?
        if let raw = try stringArg(a, "pressure") {
            guard let found = MemoryPressure(rawValue: raw) else {
                throw ToolError(
                    message: "pressure must be one of \(levels.joined(separator: ", ")) "
                        + "(got \"\(raw)\").")
            }
            level = found
        }
        if let level { GraphicPrefetch.shared.setPressure(level, simulated: true) }
        let report = GraphicPrefetch.shared.memoryReport(resettingPeaks: true)
        return try jsonResult([
            "physical_bytes": report.physicalBytes,
            "budget_bytes": report.budgetBytes,
            "pressure": report.pressure.rawValue,
            "held_bytes": report.heldBytes,
            "held_peak_bytes": report.heldPeakBytes,
            "held_peak_entries": report.heldPeakEntries,
            "kept_bytes": report.keptBytes,
            "kept_frames": report.keptFrames,
            "kept_hits": report.keptHits,
            "ahead_bytes": report.aheadBytes,
            "ahead_evicted": report.aheadEvicted,
            "pass_activity": report.passActivity,
            "image_cache_bytes": report.imageCacheBytes,
            "image_cache_limit": report.imageCacheLimit,
        ])
    }

    // MARK: - Catalog

    func graphicMemoryTool() -> [String: Any] {
        tool(
            "graphic_memory",
            "DEV TOOL (absent from Distribution builds). Answer the graphic rasters' one memory "
                + "budget (spec G-37) and what fills it: physical_bytes, budget_bytes (a quarter "
                + "of physical memory at normal pressure, an eighth at warning, 0 at critical), "
                + "pressure (the level in force), held_bytes (every session's rasters held "
                + "ahead now), held_peak_bytes and held_peak_entries (the highest totals since "
                + "the last answer; each answer resets them to the current ones), kept_bytes and "
                + "kept_frames (the graphic frames the documents keep) and kept_hits (requests "
                + "the kept frames answered since launch), ahead_bytes (the kept frames a "
                + "background pass drew ahead and the compositor has not yet passed, spec G-38), "
                + "ahead_evicted (those a trim pushed out while still ahead, since the last "
                + "answer; each answer resets it) and pass_activity (whether a running background "
                + "pass holds Frame Job's App Nap opt-out), image_cache_bytes and "
                + "image_cache_limit (the engine's decoded-image cache of PNG and JPEG assets, "
                + "spec G-39: the bytes its copies hold, and its limit, a sixteenth of "
                + "budget_bytes, 0 when its switch is on). Needs no project. pressure first "
                + "sets a simulated memory-pressure level, which holds against the system's own "
                + "until pressure normal clears it. Refused, changing nothing: any other "
                + "pressure value.",
            [
                "pressure": [
                    "type": "string", "enum": MemoryPressure.allCases.map(\.rawValue),
                    "description": "Simulate this memory-pressure level before answering; "
                        + "normal clears the simulation. Omit to change nothing.",
                ]
            ])
    }
}
#endif
