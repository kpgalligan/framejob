import Foundation

/// The cached waveform, the plan's mix envelope, and how to ask either about a
/// moment — the arithmetic every reader of "how loud is this, there?" shares.
///
/// `cache/peaks/<media id>.bin` is one 32-bit float per 1/100 s of SOURCE
/// time: the largest magnitude the file reaches anywhere inside that bucket,
/// taken across every channel, PRE-FADER and deliberately unclamped
/// (`MediaImporter.peaks`, which says why max and not RMS). It is written by a
/// fire-and-forget task at open and import, so "not on disk yet" is an
/// ordinary answer and never means silence.
///
/// **Everything here was `private static` inside `SilenceDetector` until road
/// map 2 phase 5c.** Normalise Clip needs the same question answered — the
/// loudest the file gets over the window a clip actually plays — and the
/// scouts' warning was specific: the app ALREADY carries two project-time →
/// source-time conversions that disagree. `TimelineView.sourceTime` multiplies
/// by `clip.speed`, rounding the rate a second time; the one here divides the
/// plan segment's own `sourceDuration` by its `duration`, which IS the rate the
/// composition plays at, exactly. A third copy would have made it three, so the
/// four pieces moved out here instead and `SilenceDetector` calls them:
///
/// 1. `bucketTicks` — how much source time one float covers;
/// 2. `sourceTick` — project time under a segment, at the plan's resolved rate;
/// 3. `bucketIndex` — the floor, spelled out for negatives;
/// 4. the reversed mirror inside `peak`.
///
/// The mirror is the piece a reader is most likely to drop. A reversed clip's
/// `in` point is measured in the REVERSED stream, and the only peaks file that
/// exists is of the forward one — nothing ever generates peaks for
/// `cache/reversed/…`, which is not a media entry at all — so the window is
/// mirrored about the media's model duration, the pivot `ReverseRenderer`
/// renders against. Without it a reversed clip is measured against the wrong
/// end of its own file, which reads as a plausible number and is simply wrong.
///
/// **`envelope` arrived the same way, one phase later.** It is the plan's
/// piecewise-linear mix gain at a tick — the OTHER half of every level this app
/// computes, since a peak bucket is pre-fader and the level anyone means is
/// `peak × envelope`. Phase 5's meter wrote a second copy of it beside
/// `SilenceDetector`'s and its own doc admitted as much; the consolidation
/// merged the two here. Both readers ask the same question, the rule `audio.rs`
/// expresses by making a mute and a solo a ZERO envelope, and neither may grow
/// a private copy of the search again.
///
/// Nothing here is AppKit and nothing here decides anything: it is arithmetic
/// over a plan segment, an array of floats and a pair of ticks.
enum MediaPeaks {

    // MARK: - The grid

    /// One bucket of the peaks cache, in ticks of SOURCE time. Exactly 6000,
    /// and written as the division rather than as the number because
    /// `peakBucketsPerSecond` and `perSecond` each have exactly one home.
    static var bucketTicks: Ticks {
        ReelTime.perSecond / Ticks(MediaImporter.peakBucketsPerSecond)
    }

    // MARK: - Reading the cache

    /// One media's peaks read at most once, however many segments cite it.
    ///
    /// `loadPeaks` is a whole-file `Data(contentsOf:)` and a forty-minute
    /// screencast is a megabyte of floats, so a timeline with a dozen clips off
    /// one recording must not read it a dozen times. A failure is remembered as
    /// well as a success — `pending` is what a caller reports as "still
    /// analysing" — because a missing file is a fact about this moment, not an
    /// error to retry inside one pass.
    ///
    /// It is a class rather than a struct on purpose: it is a cache, two
    /// callers share one, and a value type would have made "did that read land
    /// in MY copy?" a question anyone extending this has to ask.
    final class Loader {
        private let cacheDirectory: URL?
        private var loaded: [UInt32: [Float]] = [:]
        /// Media whose `cache/peaks/<id>.bin` was asked for and was not there.
        private(set) var pending: Set<UInt32> = []

        /// nil is a document with nowhere to keep caches, which answers every
        /// media as pending — the same answer as a cache that has not been
        /// written yet, and the correct one.
        init(cacheDirectory: URL?) {
            self.cacheDirectory = cacheDirectory
        }

        func peaks(for media: UInt32) -> [Float]? {
            if let cached = loaded[media] { return cached }
            if pending.contains(media) { return nil }
            guard let cacheDirectory = cacheDirectory,
                  let read = MediaImporter.loadPeaks(for: media, in: cacheDirectory)
            else {
                pending.insert(media)
                return nil
            }
            loaded[media] = read
            return read
        }
    }

    // MARK: - Asking about a window

    /// The loudest bucket the project span `[from, to)` of `segment` reads, or
    /// 0 when it falls outside the file the cache was built from.
    ///
    /// `reversedPivot` is the media's model duration when the clip plays
    /// backwards and nil when it does not — `reversedPivot(for:in:)` is how a
    /// caller works it out. Both ends of the window land INSIDE buckets, so the
    /// answer can take in up to 10 ms of neighbouring source at each end: an
    /// overestimate, which is the conservative direction for both callers (a
    /// span is judged too loud to cut rather than cut wrongly; a clip is
    /// normalised a shade quiet rather than into clipping).
    static func peak(
        _ peaks: [Float], over segment: PlanSegment, from: Ticks, to: Ticks,
        reversedPivot: Ticks?
    ) -> Float {
        guard
            let range = window(
                of: segment, from: from, to: to, reversedPivot: reversedPivot,
                bucketTicks: bucketTicks, count: peaks.count)
        else { return 0 }
        var loudest: Float = 0
        for index in range { loudest = max(loudest, peaks[index]) }
        return loudest
    }

    /// The bucket-index range a project span `[from, to)` of `segment` covers
    /// in a cache built at `bucketTicks` per bucket over `count` buckets, or
    /// nil when it falls outside the file the cache was built from —
    /// `peak`'s lines 115–128 generalised over the bucket size, so
    /// `MediaSpeech.speechMax` can ask the same question of the 32 ms Silero
    /// grid without a second copy of the reversed-mirror arithmetic.
    static func window(
        of segment: PlanSegment, from: Ticks, to: Ticks, reversedPivot: Ticks?,
        bucketTicks: Ticks, count: Int
    ) -> ClosedRange<Int>? {
        guard segment.duration > 0, segment.sourceDuration > 0, count > 0 else { return nil }
        let first = sourceTick(segment, at: from)
        let last = max(first, sourceTick(segment, at: to) - 1)

        var lo = first
        var hi = last
        if let pivot = reversedPivot {
            lo = pivot - last
            hi = pivot - first
        }

        let lower = max(0, bucketIndex(lo, bucket: bucketTicks))
        let upper = min(count - 1, bucketIndex(hi, bucket: bucketTicks))
        guard lower <= upper else { return nil }
        return lower...upper
    }

    /// The pivot a reversed clip's window is mirrored about, or nil when the
    /// clip plays forwards.
    ///
    /// `reversed` is deliberately NOT in the plan (a reversed clip and a
    /// forward one must produce byte-identical plan JSON, or the
    /// rebuild-vs-refresh test breaks), so it is read back off the clip — which
    /// answers nil for a clip inside a nest, because `Project::clip` searches
    /// the top level only. Such a clip is measured unmirrored while the nest
    /// is CLOSED — a recorded limit, not a bug, and one with an escape since
    /// road map 2's phase 9: OPEN the nest (⌘↓) and the scoped view puts that
    /// clip at the top level, where the pivot is found. The limit is
    /// conditional now, not permanent; this sentence used to say no op could
    /// address it, which was true until an op could name a nested clip.
    static func reversedPivot(for segment: PlanSegment, in snapshot: ProjectSnapshot) -> Ticks? {
        guard snapshot.clip(segment.clip)?.source.isReversed == true else { return nil }
        return snapshot.media(segment.media)?.duration
    }

    /// Source time under a project tick, at the rate the plan resolved:
    /// `sourceDuration / duration` IS the speed, exactly, with no second
    /// rounding of `clip.speed` here.
    static func sourceTick(_ segment: PlanSegment, at t: Ticks) -> Ticks {
        guard segment.duration > 0 else { return segment.sourceIn }
        let offset =
            Double(t - segment.start) * Double(segment.sourceDuration) / Double(segment.duration)
        guard offset.isFinite else { return segment.sourceIn }
        return segment.sourceIn + TimelineLayout.ticks(clamping: offset.rounded(.down))
    }

    /// `floor(tick / bucket)`, correct for a negative tick — which a mirrored
    /// reversed window produces when the clip runs past the media's start.
    /// Swift's integer division truncates toward zero, so the negative half
    /// has to be spelled out.
    static func bucketIndex(_ tick: Ticks, bucket: Ticks = MediaPeaks.bucketTicks) -> Int {
        guard bucket > 0 else { return 0 }
        let quotient = tick >= 0 ? tick / bucket : -((-tick + bucket - 1) / bucket)
        return Int(max(min(quotient, Ticks(Int.max)), Ticks(Int.min)))
    }

    // MARK: - Asking the plan

    /// The mix envelope at a project tick, interpolated piecewise-linearly from
    /// one track's plan ramps: the gain the mix is applying there, with
    /// `volume`, the fades, volume actions and ducking already folded in by
    /// `audio.rs`.
    ///
    /// 1 when a track carries no ramps at all — a video track's `ramps` is nil —
    /// which is the same thing `audio.rs` means by an unmodified track. A tick
    /// before the first ramp reads that ramp's `from`, and one past the last
    /// reads its `to`, so the answer is defined over the whole timeline and not
    /// only over the extent the ramps cover.
    ///
    /// Binary search rather than a scan, because a long timeline's envelope has
    /// a ramp per fade edge and the meter asks this thirty times a second per
    /// track.
    ///
    /// **This is the app's ONE spelling of the mix rule** (the type's doc says
    /// why it is here rather than in either caller): `SilenceDetector` asks it
    /// what a moment SOUNDS like, multiplying a pre-fader peak bucket by it, and
    /// `LevelMeter` asks it what a metered track's pre-fader BUFFER becomes in
    /// the mix. Because the core expresses a mute and a solo as a zero envelope,
    /// both get silencing for free and neither carries a Swift copy of
    /// `audio.rs`'s `silenced` to drift from the original.
    static func envelope(_ ramps: [PlanRamp]?, at t: Ticks) -> Double {
        guard let ramps = ramps, !ramps.isEmpty else { return 1 }
        var low = 0
        var high = ramps.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if ramps[mid].start <= t {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard found >= 0 else { return ramps[0].from }
        let ramp = ramps[found]
        guard ramp.duration > 0 else { return ramp.to }
        guard t < ramp.start + ramp.duration else { return ramp.to }
        let fraction = Double(t - ramp.start) / Double(ramp.duration)
        return ramp.from + (ramp.to - ramp.from) * fraction
    }
}
