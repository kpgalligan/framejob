import Foundation

/// Synchronize Audio's weak tier (road map "audio-sync-2", AS-3; spec §11
/// SY-18, SY-19): which planned moves were chosen only near where the mover
/// sits, and the words the menu's Weak match sheet and `sync_audio`'s
/// not-applied answer put them in.
///
/// Pure, as `AudioSync.plan` is. ONE tier decision, `weakMoves`, serves both
/// callers, so the menu and the tool cannot disagree about whether a plan
/// may apply without asking. A weak match is never applied silently — the
/// owner's "Unrelated clips are never moved silently" — because AS-3's
/// calibration showed noise near a placement reaching the z of the owner's
/// first pair (SY-14's stop), a pair SY-28 found to be two takes, not one
/// recording. A weak match is offered at all only when GCC-PHAT confirms it
/// (SY-29).
extension AudioSync {

    /// The movers of `synced` chosen by placement (the weak tier) whose plan
    /// changes something — a delta, a trim or a corrected drift — in input
    /// order. A weak mover already in place is not asked about.
    static func weakMoves(_ synced: [Synced]) -> [Synced] {
        synced.filter { row in
            guard row.chosenBy == .placement else { return false }
            if case .apply = row.correction { return true }
            return row.delta != 0 || row.trimmed > 0
        }
    }

    /// The Weak match sheet's message and detail: "Weak match: move
    /// “record.aifc” 0.77 s earlier (trimming 0.77 s off its head)?", then
    /// the anchor, each confidence and the rule it fell short of. `names` maps
    /// a clip id to the name the timeline shows; an id missing from it reads
    /// "clip N".
    static func weakQuestion(_ weak: [Synced], anchor: UInt32, names: [UInt32: String])
        -> (message: String, detail: String) {
        func name(_ clip: UInt32) -> String { names[clip] ?? "clip \(clip)" }
        let items = weak.map { row -> String in
            // A mover listed only for its drift correction does not move.
            if let speed = speedOnly(row) {
                return "play “\(name(row.clip))” at " + speed + ", correcting its drift"
            }
            let direction = row.delta < 0 ? "earlier" : "later"
            return "move “\(name(row.clip))” " + seconds(abs(row.delta)) + " s " + direction
                + trimming(row)
        }
        let message = "Weak match: " + items.joined(separator: "; ") + "?"
        let confidences = weak.map { String(format: "%.2f", $0.confidence) }
            .joined(separator: ", ")
        let detail = (weak.count == 1 ? "Its sound matches" : "Their sound matches")
            + " “\(name(anchor))” with confidence \(confidences): " + rule(weak.count)
            + " Cancel leaves everything as it is."
        return (message, detail)
    }

    /// `sync_audio`'s note when weak moves were not applied: each move as
    /// the clip, its signed delta, any trim and its confidence, then the rule
    /// and how to apply it — once the person has agreed (SY-19).
    static func weakNote(_ weak: [Synced]) -> String {
        let items = weak.map { row -> String in
            if let speed = speedOnly(row) {
                return "clip \(row.clip) would play at " + speed + ", correcting its drift, "
                    + "confidence " + String(format: "%.2f", row.confidence)
            }
            let signed = String(format: "%+.2f", Double(row.delta) / Double(ReelTime.perSecond))
                .replacingOccurrences(of: "-", with: "−")
            return "clip \(row.clip) would move by \(signed) s" + trimming(row)
                + ", confidence " + String(format: "%.2f", row.confidence)
        }
        return "Weak match, nothing moved: " + items.joined(separator: "; ") + " — "
            + rule(weak.count) + " Call sync_audio again with accept_weak: true to apply "
            + (weak.count == 1 ? "it" : "them") + ", once the person has agreed to "
            + (weak.count == 1 ? "that move." : "those moves.")
    }

    // MARK: - The words

    /// "under the 10 a match needs to apply on its own, and the best match
    /// within 3 s of where it sits now." — printed from the constants.
    private static func rule(_ count: Int) -> String {
        let radius = Double(Ticks(AudioSyncMatch.placementRadiusFrames) * SyncFeatures.frameTicks)
            / Double(ReelTime.perSecond)
        return "under the " + String(format: "%g", AudioSyncMatch.confidentZ)
            + " a match needs to apply on its own, and the best match within "
            + String(format: "%.0f", radius) + " s of where "
            + (count == 1 ? "it sits" : "each sits") + " now."
    }

    /// "×1.0004" when `row` changes only its speed (no delta, no trim, its
    /// drift corrected), else nil.
    private static func speedOnly(_ row: Synced) -> String? {
        guard row.delta == 0, row.trimmed == 0, case .apply(let speed) = row.correction
        else { return nil }
        return "×" + String(format: "%g", speed)
    }

    /// " (trimming 0.77 s off its head)" when the move trims, else "".
    private static func trimming(_ row: Synced) -> String {
        row.trimmed > 0 ? " (trimming " + seconds(row.trimmed) + " s off its head)" : ""
    }

    private static func seconds(_ ticks: Ticks) -> String {
        String(format: "%.2f", Double(ticks) / Double(ReelTime.perSecond))
    }
}
