import Foundation

/// The nest walls and the frame-grid snap: a pure move out of
/// `SilenceDetector.swift`, road map 4's toll 1, landed first and alone. The
/// file that took on the voice model needed the room, and these five
/// functions plus `NestExtent` are the piece of the detector that answers
/// only to the SNAPSHOT — no plan, no peaks, no model — so the cut cost
/// nothing but visibility: `excludingNests`, `overlap`, `merged`,
/// `snapUpToFrame` and `snapDownToFrame` widen `private` to internal, since
/// an extension member in another file cannot see another file's `private`.
extension SilenceDetector {

    // MARK: - The walls

    /// Every run cut into the pieces that lie OUTSIDE every nest clip, with
    /// the nests that took a cut's worth of quiet away named alongside.
    ///
    /// A piece may end exactly where a nest begins, and that is safe:
    /// `clear_range` cuts its bounds with `split_under_playhead`, which
    /// splits only what a tick falls STRICTLY inside, so a bound on a nest
    /// clip's own edge splits nothing and the ripple then moves the whole
    /// nest clip left — a move, not a cut into it. Nor can the op weld two
    /// pieces back together across a nest: it merges spans that overlap or
    /// TOUCH, and these are a nest clip's whole length apart.
    ///
    /// The second answer is the sheet's, and it names a nest only when the
    /// quiet inside it was long enough to have BEEN a cut — a stray bucket
    /// of room tone behind a wall is not something to explain.
    static func excludingNests(
        _ runs: [Span], _ nests: [NestExtent], minLength: Ticks
    ) -> ([Span], [UInt32]) {
        guard !nests.isEmpty else { return (runs, []) }
        var walled: Set<UInt32> = []
        for nest in nests {
            for run in runs where overlap(run, nest.span) >= max(1, minLength) {
                walled.insert(nest.clip)
            }
        }
        // Merged first, so two nest clips that abut do not leave a
        // zero-length piece between them.
        let walls = merged(nests.map { $0.span })
        var out: [Span] = []
        for run in runs {
            var start = run.start
            for wall in walls {
                if wall.end <= start { continue }
                if wall.start >= run.end { break }
                if wall.start > start { out.append(Span(start: start, end: wall.start)) }
                start = wall.end
                if start >= run.end { break }
            }
            if start < run.end { out.append(Span(start: start, end: run.end)) }
        }
        return (out, walled.sorted())
    }

    /// The length two spans share, or 0.
    static func overlap(_ a: Span, _ b: Span) -> Ticks {
        max(0, min(a.end, b.end) - max(a.start, b.start))
    }

    /// Overlapping and touching spans folded together, in start order — the
    /// same rule `edit_time.rs`'s `union` applies to the ranges the op is
    /// finally handed.
    static func merged(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for span in spans.sorted(by: { $0.start < $1.start }) where span.end > span.start {
            guard let last = out.last, span.start <= last.end else {
                out.append(span)
                continue
            }
            out[out.count - 1] = Span(start: last.start, end: max(last.end, span.end))
        }
        return out
    }

    // MARK: - Frame snapping, directionally

    /// The core has `snap_up_to_frame` / `snap_down_to_frame` (the directional
    /// pair phase 1 added for exactly this), but neither crosses the FFI —
    /// `rc_time_snap_to_frame` is the whole C surface for time. So the two are
    /// composed here from the two pieces Swift DOES have, `ReelTime.snapToFrame`
    /// and `Fps.frameDuration`, rather than re-deriving a grid: the nearest
    /// boundary is asked for, and when it fell the wrong way the neighbouring
    /// one is asked for instead.
    static func snapUpToFrame(_ t: Ticks, fps: Fps) -> Ticks {
        let nearest = ReelTime.snapToFrame(t, fps: fps)
        guard nearest < t else { return nearest }
        return ReelTime.snapToFrame(nearest + max(fps.frameDuration, 1), fps: fps)
    }

    static func snapDownToFrame(_ t: Ticks, fps: Fps) -> Ticks {
        let nearest = ReelTime.snapToFrame(t, fps: fps)
        guard nearest > t else { return nearest }
        return ReelTime.snapToFrame(nearest - max(fps.frameDuration, 1), fps: fps)
    }
}
