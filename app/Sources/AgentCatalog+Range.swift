import Foundation

// MARK: - Catalog: range and time

/// The catalog's RANGE AND TIME rows: `lift_range`, `insert_time` and
/// `close_gap`, three op tools whose arguments the core's table supplies
/// (`opTool`), so what is here is their prose and each argument's sentence.
///
/// A pure move out of `AgentCatalog+Clips.swift`, which stood at 592 lines
/// against the ~600 cap with `lift_range`'s `tracks` about to add a sentence
/// (spec §11 #602), landed first and alone. `AgentCatalog+Audio.swift`'s
/// header is the model: the three rows came here whole, in their existing
/// order, with their bodies untouched, and are spliced back in at the SAME
/// point in the catalog's array — after `audioTools` and before `set_speed` —
/// so `tools/list` is byte-identical before and after the cut. `ticks` and
/// `trackDescription` are the two hoisted locals these rows read; both arrive
/// as arguments rather than a second spelling here.
extension AgentServer {

    /// The range and time rows of `catalogJSON()`'s array, in their order.
    func rangeTools(ticks: String, trackDescription: String) -> [[String: Any]] {
        [
            opTool(
                "lift_range",
                "Cuts a time range out and LEAVES the hole — ⌫ with an in/out range and nothing "
                    + "selected. Every unlocked clip is split at both bounds and the middles "
                    + "removed, and nothing moves: every clip after the range keeps the moment "
                    + "it had, which is what makes this the safe cut when a mix or a caption "
                    + "track is already timed. Refused, nothing cut, when a piece left is too short "
                    + "for its transition. Use ripple_delete_range to close the hole instead.",
                ["from": "Range start, \(ticks)", "to": "Range end, \(ticks)"]),
            opTool(
                "insert_time",
                "Opens a gap: every unlocked clip starting at or after `at` moves right by "
                    + "`length`. Straddling clips are left in place, so this makes room without "
                    + "cutting anything — split first if you want the gap inside a clip. Every "
                    + "marker at or after `at` moves right by `length` too.",
                [
                    "at": "Where the gap opens, \(ticks)",
                    "length": "How much room, \(ticks)",
                ]),
            opTool(
                "close_gap",
                "Closes the empty span on `track` that contains `at` — double-clicking a gap in "
                    + "a lane, or Clip ▸ Close Gap. The gap is bounded by the nearest clip "
                    + "edges on that track, and everything from its far side slides left by its "
                    + "length across every unlocked track. Nothing changes when `at` is on a "
                    + "clip, when the track is locked, when there is no clip after the gap, or "
                    + "when the shift would break the overlap rule — a gap closes fully or not "
                    + "at all.",
                [
                    "track": trackDescription,
                    "at": "A time inside the gap, \(ticks)",
                ]),
        ]
    }
}
