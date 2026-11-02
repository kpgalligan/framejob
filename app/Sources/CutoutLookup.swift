import Foundation

// The cutout's lookup (road map creator-jobs CO2a2, spec §11 CO-24, CO-26): which analysed mask a
// cut-out layer draws at a composition time. Pure: no Metal, no file read, names no `rc_*`
// (CJ-8 (l)); `Compositor+Cutout.swift` asks it, `CutoutMasks.swift` holds what it reads.

/// The plan's picture segments and the reversed clips' pivots of one project handle, decoded
/// once per handle (`CutoutMasks.plan(for:project:)`).
struct CutoutPlan {
    /// Composition video track id → its segments with a duration, sorted by start.
    let segments: [Int: [PlanSegment]]
    /// A reversed clip (top level and inside nests) → its media's model duration T, the pivot.
    let pivots: [UInt32: Ticks]
    /// A clip and media → the hull `[lower, upper)` of the segments' source ticks, in the
    /// stream each segment reads.
    private let hulls: [ClipMedia: (lower: Ticks, upper: Ticks)]

    private struct ClipMedia: Hashable {
        let clip: UInt32
        let media: UInt32
    }

    init(project: ReelProject) {
        self.init(plan: project.plan, snapshot: project.snapshot)
    }

    init(plan: CompositionPlan?, snapshot: ProjectSnapshot) {
        var segments: [Int: [PlanSegment]] = [:]
        var hulls: [ClipMedia: (lower: Ticks, upper: Ticks)] = [:]
        for track in plan?.videoTracks ?? [] {
            let drawn = track.segments.filter { $0.duration > 0 }
            segments[track.id, default: []] += drawn
            for segment in drawn {
                let key = ClipMedia(clip: segment.clip, media: segment.media)
                let lower = segment.sourceIn
                let upper = segment.sourceIn + max(segment.sourceDuration, 0)
                if let hull = hulls[key] {
                    hulls[key] = (min(hull.lower, lower), max(hull.upper, upper))
                } else {
                    hulls[key] = (lower, upper)
                }
            }
        }
        for (id, list) in segments {
            segments[id] = list.sorted { $0.start < $1.start }
        }
        var pivots: [UInt32: Ticks] = [:]
        for clip in snapshot.clips + snapshot.nests.flatMap(\.clips) {
            if let pivot = ReverseMirror.pivot(for: clip, in: snapshot) { pivots[clip.id] = pivot }
        }
        self.segments = segments
        self.pivots = pivots
        self.hulls = hulls
    }

    /// The segment of composition track `track` that covers `t`: `start ≤ t < start +
    /// duration`; nil in a gap.
    func covering(track: Int, at t: Ticks) -> PlanSegment? {
        guard let list = segments[track] else { return nil }
        var low = 0, high = list.count
        while low < high {
            let mid = (low + high) / 2
            if list[mid].start <= t { low = mid + 1 } else { high = mid }
        }
        // The last segment starting at or before `t`: segments of one track do not overlap.
        guard low > 0, t < list[low - 1].start + list[low - 1].duration else { return nil }
        return list[low - 1]
    }

    /// The clip's window in FORWARD source ticks: the hull of its segments of `media`, mirrored
    /// about the pivot for a reversed clip (spec §11 CO-26). nil when the plan draws none.
    func window(clip: UInt32, media: UInt32) -> ClosedRange<Ticks>? {
        guard let hull = hulls[ClipMedia(clip: clip, media: media)], hull.lower <= hull.upper
        else { return nil }
        let played = hull.lower...hull.upper
        guard let pivot = pivots[clip] else { return played }
        return ReverseMirror.mirrored(played, about: pivot)
    }
}

enum CutoutLookup {

    /// The source tick a segment shows at composition tick `t`: `sourceIn + (t − start) ·
    /// sourceDuration / duration`, rounded to the nearest tick, halves away from 0 (CO-24).
    /// Exact: the product is taken at full width.
    static func sourceTick(_ s: PlanSegment, at t: Ticks) -> Ticks {
        guard s.duration > 0 else { return s.sourceIn }
        let offset = t - s.start
        let negative = (offset < 0) != (s.sourceDuration < 0)
        let product = offset.magnitude.multipliedFullWidth(by: s.sourceDuration.magnitude)
        let divisor = UInt64(s.duration)
        guard product.high < divisor else { return s.sourceIn }
        let (quotient, remainder) = divisor.dividingFullWidth(product)
        let rounded = remainder >= divisor - remainder ? quotient + 1 : quotient
        let step = Ticks(clamping: rounded)
        return s.sourceIn + (negative ? -step : step)
    }

    /// Each mask's end — the pts of the pack frame after it, else its pts plus one grid frame
    /// (rounded) — with its slot, sorted by end (CO-24's reversed slot).
    static func ends(of pack: MaskPack, grid: AnalysisGrid) -> [(end: Int64, slot: Int)] {
        let frame = Int64(grid.frameTicks.rounded())
        return pack.masks.enumerated().map { slot, mask in
            (end: after(mask.pts, in: pack) ?? mask.pts + frame, slot: slot)
        }.sorted { $0.end != $1.end ? $0.end < $1.end : $0.slot < $1.slot }
    }

    /// The slot of the mask drawn for `sourceTick` of a segment's stream, `pivot` its clip's T
    /// when it plays reversed; nil for a miss (CO-24): no frame shown at or before the tick, or
    /// the frame shown and the tick's grid index not in one coverage range.
    static func slot(
        pack: MaskPack, ends: [(end: Int64, slot: Int)], coverage: [ClosedRange<Int>],
        grid: AnalysisGrid, sourceTick: Ticks, pivot: Ticks?
    ) -> Int? {
        // A reversed stream shows forward frame f over [T − end(f), T − pts(f)), so the frame
        // under reversed tick s is the one shown at forward tick T − s − 1.
        let query = pivot.map { ReverseMirror.mirrored(sourceTick, about: $0) - 1 } ?? sourceTick
        guard let f = pack.shown(at: query) else { return nil }
        let frame = pack.frames[f]
        let queried = grid.index(of: query)
        guard let range = coverage.first(where: { $0.contains(Int(frame.index)) }),
            range.contains(queried)
        else { return nil }
        guard pivot != nil else { return Int(frame.slot) }
        let target =
            f + 1 < pack.frames.count
            ? pack.frames[f + 1].pts : frame.pts + Int64(grid.frameTicks.rounded())
        return nearest(target, in: ends)
    }

    /// Whether any run of the pack inside `window` (forward source ticks, `[lower, upper)`)
    /// found a subject (spec §11 CO-5, CO-26).
    static func subjectFound(
        pack: MaskPack, window: ClosedRange<Ticks>, coverage: [ClosedRange<Int>],
        grid: AnalysisGrid
    ) -> Bool {
        guard let indices = grid.indices(from: window.lowerBound, to: window.upperBound)
        else { return false }
        return AnalysisMasks.runs(pack, window: indices, coverage: coverage, grid: grid)
            .contains(where: \.subjectFound)
    }

    /// The first pack frame's pts after `pts`; nil when none is.
    private static func after(_ pts: Int64, in pack: MaskPack) -> Int64? {
        let index = pack.shown(at: pts).map { $0 + 1 } ?? 0
        return index < pack.frames.count ? pack.frames[index].pts : nil
    }

    /// The slot whose end is nearest `target`, a tie to the larger end (the earlier in the
    /// reversed stream); nil when `ends` is empty.
    private static func nearest(_ target: Int64, in ends: [(end: Int64, slot: Int)]) -> Int? {
        guard !ends.isEmpty else { return nil }
        var low = 0, high = ends.count
        while low < high {
            let mid = (low + high) / 2
            if ends[mid].end < target { low = mid + 1 } else { high = mid }
        }
        // `low` is the first end ≥ target; the candidate before it is below.
        guard low > 0 else { return ends[low].slot }
        guard low < ends.count else { return ends[ends.count - 1].slot }
        let above = ends[low], below = ends[low - 1]
        return above.end - target <= target - below.end ? above.slot : below.slot
    }
}
