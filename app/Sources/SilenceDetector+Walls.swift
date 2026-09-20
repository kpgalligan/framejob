import Foundation

/// The nest walls and the frame-grid snap: a pure move out of
/// `SilenceDetector.swift`, road map 4's toll 1, landed first and alone. The
/// file that took on the voice model needed the room, and these five
/// functions plus `NestExtent` are the piece of the detector that answers
/// only to the SNAPSHOT — no plan, no peaks, no model — so the cut cost
/// nothing but visibility: `excludingNests`, `overlap`, `merged`,
/// `snapUpToFrame` and `snapDownToFrame` widen `private` to internal, since
/// an extension member in another file cannot see another file's `private`.
///
/// `refine` came the same way and for the same reason, as road map 4's toll
/// for the reader review's fixes: it is the third thing here that answers to
/// the SNAPSHOT alone (a run, the two lengths and the frame grid), it calls
/// both snaps, and it widens to internal beside them.
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

    /// The span around every OVERLAP on every unlocked track — the material
    /// a candidate may not reach into, or the transition is destroyed
    /// (road map 5, E1).
    ///
    /// **Every unlocked track, not the detector's scope**, because
    /// `ripple_delete_ranges` cuts every unlocked track: a cut proposed from
    /// the voice on track 3 shifts the pair on track 1 too, and the nest
    /// walls are built the same way for the same reason.
    ///
    /// **A wall is the overlap WIDENED by its own length on each side** —
    /// `[B.start − ov, A.end + ov]` with `ov = A.end − B.start` — snapped
    /// OUTWARD to the frame grid, and that is where it differs from a nest
    /// wall, which can be exact. A nest clip's edges are places a cut splits
    /// nothing; an overlap's edges lie strictly INSIDE the other clip, so an
    /// exact wall is not enough. A quiet run ending exactly at `B.start`
    /// survives a wall of exactly `[B.start, A.end]`; `clear_range` then
    /// splits A at `B.start` and the shift moves A's `ov`-long tail and B
    /// together, leaving that tail wholly underneath B — an overlap longer
    /// than half the shorter clip, which neither `ripple_delete_ranges` nor
    /// `validate` checks. Widened, the nearest legal cut leaves each clip at
    /// least `2·ov` across the overlap, which is exactly the half rule's own
    /// bound.
    ///
    /// The transition's `audio` flag is deliberately NOT consulted. The
    /// cases that matter are not about the crossfade making the overlap
    /// quiet — `max(cos, sin) ≥ 0.707`, so a two-voice overlap is never
    /// quiet from the fade alone — but about a pair where only one clip has
    /// sound, and about handles pulled out of material Remove Silences had
    /// already judged quiet, which is the common case since that is where a
    /// person adds a transition after cutting. Neither depends on the flag.
    static func overlapWalls(_ snapshot: ProjectSnapshot) -> [Span] {
        var walls: [Span] = []
        let fps = snapshot.canvas.fps
        for track in snapshot.tracks where !track.locked {
            let ordered = snapshot.clips(onTrack: track.id)
            for (earlier, later) in zip(ordered, ordered.dropFirst()) {
                let start = max(earlier.start, later.start)
                let end = min(earlier.end, later.end)
                let width = end - start
                guard width > 0 else { continue }
                walls.append(
                    Span(
                        start: snapDownToFrame(max(0, start - width), fps: fps),
                        end: snapUpToFrame(end + width, fps: fps)))
            }
        }
        return walls
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

    /// Length filter, then padding, then the frame grid — in that order,
    /// because the minimum is about the RUN the ear heard and the padding is
    /// about the CUT that replaces it.
    ///
    /// Both bounds snap INWARD: up for the start, down for the end. Inward is
    /// the conservative direction for an edit that deletes material — it can
    /// leave a frame of room tone, which is inaudible, where outward would
    /// clip the attack of the next word, which is not. A frame at 30 fps is
    /// 20 000 ticks against a bucket's 6 000, so nearest-snapping could move a
    /// cut by more than the detection resolution, and in the wrong direction
    /// half the time.
    static func refine(_ runs: [Span], settings: Settings, fps: Fps) -> [Span] {
        var out: [Span] = []
        for run in runs {
            guard run.length >= settings.minLength else { continue }
            let padded = Span(
                start: run.start + settings.padding, end: run.end - settings.padding)
            guard padded.end > padded.start else { continue }
            let snapped = Span(
                start: snapUpToFrame(padded.start, fps: fps),
                end: snapDownToFrame(padded.end, fps: fps))
            guard snapped.start >= 0, snapped.end > snapped.start else { continue }
            out.append(snapped)
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
