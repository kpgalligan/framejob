import Foundation

/// A word selection planned into one cut (road map "creator-jobs" TX3a, spec
/// §11 TX-31, TX-32): the selection widened over the words the cut would
/// take, the range snapped as `ripple_delete_ranges` snaps it, the clip counts
/// the cut leaves and passes through, and the first refusal. Pure.
///
/// **Snapping.** Each bound goes to its nearest frame, the core's own snap,
/// so what is sent is on the grid and the core keeps it — but never past a
/// word start it must keep on its side: the start never after the first cut
/// word's start, the end never after the next shown word's start; past one,
/// the bound is that start's frame floor. TX1's read places a word in the
/// clip that holds its start (TX-10), so a start rounded past the cut word's
/// start would leave it in the transcript as a sliver, and an end rounded past
/// the next word's start would drop that word — and the next cut would take
/// its sound.
///
/// **Widening (TX-32).** A shown word outside the selection whose extent
/// `[onset, max(end, onset + 1))` meets the selection's UNSNAPPED cut is added,
/// with every token between, unless it plays on a locked track; again until
/// nothing is added. The onset, not the corrected start, so the next word of
/// the same instance — whose onset is where the cut ends — is never taken.
///
/// **Refusals, in order (TX-32).** A selected word that cannot be cut, in
/// TX-11's own sentence; a read word on a locked track (every track, Words
/// from ignored) whose corrected extent `[start, max(end, start + 1))` meets
/// the snapped range; and a cut whose PEAK clip count — what `check_caps` sees
/// after `clear_range`'s second split — passes the ceiling. The core's own
/// checks stay the backstop (`CaptionLayout.swift`'s and `ShotSplit`'s
/// precedent).
extension TranscriptCut {

    enum Refusal: Equatable {
        case notEditable(String)
        case locked(track: String)
        case ceiling(clips: Int)

        var sentence: String {
            switch self {
            case .notEditable(let why): return why
            case .locked(let track):
                return "Track \(track) is locked and has words in this cut: unlock it to cut here."
            case .ceiling(let clips):
                return "This cut would make \(clips) clips; a project holds at most "
                    + "\(Int(RC_MAX_CLIPS)). Lock a track that needs no cut, such as a music bed, "
                    + "or cut less."
            }
        }
    }

    struct Plan: Equatable {
        let selection: ClosedRange<Int>
        /// Snapped to the canvas's frames, as the core snaps it.
        let range: Range
        let clipsAfter: Int
        let clipsPeak: Int
        let refusal: Refusal?
    }

    /// Whether `track` of the edited container is locked.
    private static func locked(_ track: UInt32, in container: ProjectSnapshot) -> Bool {
        container.track(track)?.locked == true
    }

    /// TX-32's widening, to a fixpoint.
    static func widen(
        _ selection: ClosedRange<Int>, table: Table, container: ProjectSnapshot
    ) -> ClosedRange<Int> {
        var current = selection
        while true {
            let range = table.cut(current)
            guard range.end > range.start else { return current }
            func takes(_ token: Int) -> Bool {
                let e = table.edges(token)
                return e.onset < range.end && max(e.end, e.onset + 1) > range.start
                    && !locked(table.word(token).track, in: container)
            }
            var low = current.lowerBound
            var token = current.lowerBound - 1
            while token >= 0, table.reachBefore[token] > range.start {
                if takes(token) { low = token }
                token -= 1
            }
            var high = current.upperBound
            token = current.upperBound + 1
            while token < table.shown.count, table.onsetAfter[token] < range.end {
                if takes(token) { high = token }
                token += 1
            }
            if low == current.lowerBound, high == current.upperBound { return current }
            current = low...high
        }
    }

    /// The clips a cut of `range` leaves (TX-32): `total` (every clip the
    /// core counts), plus one per unlocked-track clip of the container
    /// running from before the range to after it, less one per one wholly
    /// inside it.
    static func clipsAfter(cutting range: Range, container: ProjectSnapshot, total: Int) -> Int {
        guard range.end > range.start else { return total }
        var count = total
        for clip in container.clips where !locked(clip.track, in: container) {
            if clip.start < range.start, clip.end > range.end {
                count += 1
            } else if clip.start >= range.start, clip.end <= range.end {
                count -= 1
            }
        }
        return count
    }

    /// The count `check_caps` sees after `clear_range`'s second split
    /// (`core/src/edit_time.rs`, `clear_range`): `total`, plus one per
    /// unlocked-track clip of the container cut at the range's start, plus
    /// one per one cut at its end.
    static func clipsPeak(cutting range: Range, container: ProjectSnapshot, total: Int) -> Int {
        guard range.end > range.start else { return total }
        var count = total
        for clip in container.clips where !locked(clip.track, in: container) {
            if clip.start < range.start, range.start < clip.end { count += 1 }
            if clip.start < range.end, range.end < clip.end { count += 1 }
        }
        return count
    }

    /// The range snapped as the core snaps it: each bound to its nearest
    /// frame, clamped to 0; then the start no later than `first`'s frame
    /// floor when it passes `first`, the earliest cut word's start, and the
    /// end no later than `next`'s when it passes `next`, the start of the
    /// shown word after the cut.
    static func snapped(
        _ range: Range, from first: Ticks? = nil, keeping next: Ticks? = nil, fps: Fps
    ) -> Range {
        var start = max(0, ReelTime.snapToFrame(range.start, fps: fps))
        if let first, start > first { start = max(0, TimelineTranscript.frameFloor(first, fps: fps)) }
        var end = max(0, ReelTime.snapToFrame(range.end, fps: fps))
        if let next, end > next { end = max(0, TimelineTranscript.frameFloor(next, fps: fps)) }
        return Range(start: start, end: max(end, start))
    }

    /// The cut of `selection`, snapped, its words' starts inside it and the
    /// next shown word's outside.
    static func snappedCut(_ selection: ClosedRange<Int>, table: Table, fps: Fps) -> Range {
        let after = selection.upperBound + 1
        let next = after < table.shown.count ? table.word(after).start : nil
        let first = selection.map { table.word($0).start }.min()
        return snapped(table.cut(selection), from: first, keeping: next, fps: fps)
    }

    /// A person's selection planned: widened, its range snapped, counted,
    /// and refused in TX-32's order.
    static func plan(
        _ selection: ClosedRange<Int>, table: Table, container: ProjectSnapshot, total: Int,
        fps: Fps, ceiling: Int = Int(RC_MAX_CLIPS)
    ) -> Plan {
        let widened = widen(selection, table: table, container: container)
        let range = snappedCut(widened, table: table, fps: fps)
        let after = clipsAfter(cutting: range, container: container, total: total)
        let peak = clipsPeak(cutting: range, container: container, total: total)
        var refusal: Refusal?
        if let word = widened.lazy.map(table.word).first(where: { !$0.editable }) {
            refusal = .notEditable(word.why ?? "This word cannot be cut.")
        } else if range.end > range.start,
            let index = table.all.indices.first(where: { index in
                let word = table.all[index]
                let e = table.allEdges[index]
                return locked(word.track, in: container) && e.start < range.end
                    && max(e.end, e.start + 1) > range.start
            })
        {
            let row = container.track(table.all[index].track)
            let name = row.map { $0.name.isEmpty ? "\($0.id)" : $0.name } ?? "\(table.all[index].track)"
            refusal = .locked(track: name)
        } else if peak > ceiling {
            refusal = .ceiling(clips: peak)
        }
        return Plan(
            selection: widened, range: range, clipsAfter: after, clipsPeak: peak, refusal: refusal)
    }

    /// One token's cut as the tab would cut it selected alone: the widened
    /// run of one, snapped. No count, no refusal.
    static func wordCut(_ token: Int, table: Table, container: ProjectSnapshot, fps: Fps) -> Range {
        snappedCut(widen(token...token, table: table, container: container), table: table, fps: fps)
    }
}
