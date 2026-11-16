#if FRAMEJOB_DEV_TOOLS
import Foundation

/// `cache_ledger`, a DEV TOOL (spec §11 #552): what the cache ledger's dev
/// side holds for one document's cache folder (`CacheLedgerDev`) — the
/// publishes of each cache writer that met a save and waited it out, and the
/// gates — and the arming of those gates. It mirrors no edit and nothing in
/// the app shows it. `save_hold_proof.py` drives it.
///
/// It runs on MAIN (it is not in `devOffMainTools`) and answers at once: it
/// never waits for a writer, so a proof polls it between its own calls.
extension AgentServer {

    func cacheLedger(_ a: [String: Any]) throws -> String {
        let writers = try stringsArg(a, "gate")
        let seconds = try doubleArg(a, "seconds")
        if let seconds, !(seconds > 0 && seconds <= 600) {
            throw ToolError(message: "seconds must be above 0 and at most 600.")
        }
        if seconds != nil, writers == nil {
            throw ToolError(message: "seconds bounds the gates gate arms: name gate with it.")
        }
        let document = try target(a)
        guard let cache = document.intendedCacheDirectory else {
            throw ToolError(message: "The project has no cache folder.")
        }
        let dev = CacheLedgerDev.shared
        if let writers {
            dev.arm(writers, in: cache, seconds: seconds ?? CacheLedgerDev.defaultBound)
        }
        return try jsonResult([
            "ok": true,
            "cache": cache.standardizedFileURL.path,
            "save_waits": dev.saveWaits(in: cache),
            "gate": dev.gateStates(in: cache).mapValues(\.rawValue),
        ])
    }

    func cacheLedgerTool() -> [String: Any] {
        tool(
            "cache_ledger",
            "DEV TOOL (absent from Distribution builds). The cache ledger's dev side for a "
                + "project's cache folder (spec #552). Every cache file is published through "
                + "the ledger under its writer's name: thumbs, peaks, loudness, sync-features, "
                + "speech (the media passes), device-transcript, ramp-audio, isolated, voiced "
                + "(the offline audio renders, by folder) and analysis/<kind>/<media>. Answers "
                + "{ok, cache (the folder), save_waits: {writer: n} (publishes that found a "
                + "save of the package in flight and waited it out, since launch), gate: "
                + "{writer: armed | waiting | save | timeout | disarmed}} and returns at once. "
                + "With gate it first replaces the folder's armed set: each named writer's "
                + "next publish is held (waiting) until a save of that folder is inside its "
                + "-RCDevSaveHold (save), seconds pass (timeout) or a later call leaves it out "
                + "(disarmed); a gate is one-shot, and [] disarms them all. On a launch "
                + "without -RCDevSaveHold no save ever releases a gate. Without gate it only "
                + "answers.",
            [
                "gate": [
                    "type": "array", "items": ["type": "string"],
                    "description": "The writers to arm, replacing the armed set; [] disarms.",
                ],
                "seconds": [
                    "type": "number",
                    "description": "How long each armed writer waits at its gate (60); only "
                        + "with gate.",
                ],
            ])
    }
}
#endif
