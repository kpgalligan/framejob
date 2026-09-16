import AVFoundation

/// The time ranges of the video composition's instructions — the plan's own
/// ticks, with ONE correction at the end.
///
/// An `extension CompositionBuilder` in its own file because the base file is
/// at the ~600-line cap (app/CLAUDE.md).
extension CompositionBuilder {
    /// One `CMTimeRange` per plan instruction, in order, each exactly the
    /// plan's ticks — except that the LAST one ends where the COMPOSITION
    /// ends when the two differ by less than one tick.
    ///
    /// **The instructions must cover the composition exactly, in both
    /// directions.** Past its end, `AVAssetImageGenerator` and an export fail
    /// (`addPlaceholderIfNeeded`'s doc measured that); short of it,
    /// `AVVideoComposition.isValid` reports an empty time range at the end and
    /// `AVPlayer` DRAWS NO VIDEO AT ALL — no frame, no error, no failed item —
    /// while the generator renders every frame. So a preview can be black
    /// everywhere while `render_frame` and an export look right.
    ///
    /// The sub-tick difference comes from `fill`'s held last frame: a clip that
    /// runs past the end of its source's video track holds that track's last
    /// frame, inserted in the SOURCE's timescale (600 for a screen recording)
    /// and scaled to a duration in ticks, and AVFoundation reports the
    /// composition's duration at a nanosecond timescale, rounded. Measured on
    /// two recordings at a 28.172 fps canvas: the plan ends at 7858867/600000 s,
    /// the composition at 13098111667/1000000000 s — a third of a nanosecond
    /// later — and the preview was black at every playhead position until this
    /// ran. `tools/proof/preview_validity_probe.py` rebuilds that project from
    /// ffmpeg-made files and measures both halves.
    ///
    /// Bounded to under one tick so it only ever absorbs that rounding. A real
    /// difference — a track ending in an empty edit, which AVFoundation leaves
    /// out of the composition's duration — keeps the plan's ranges, since
    /// moving an instruction boundary by a whole frame would be the wrong
    /// repair for it. The new range is kept only if its end comes back EQUAL
    /// to the composition's, because `CMTimeRange(start:end:)` subtracts across
    /// two timescales and a rounded end would be no better than the old one.
    static func instructionRanges(
        _ plan: CompositionPlan, ending end: CMTime
    ) -> [CMTimeRange] {
        var ranges = plan.instructions.map { instruction in
            CMTimeRange(
                start: time(instruction.start), duration: time(max(1, instruction.duration)))
        }
        guard let last = plan.instructions.last, end.isNumeric else { return ranges }
        let planEnd = last.start + max(1, last.duration)
        // Compared, never subtracted: `CMTimeCompare` is exact across
        // timescales, and a subtraction would round the difference being
        // measured.
        guard end != time(planEnd), end > time(planEnd - 1), end < time(planEnd + 1),
            end > time(last.start)
        else { return ranges }
        let aligned = CMTimeRange(start: time(last.start), end: end)
        guard CMTimeRangeGetEnd(aligned) == end else { return ranges }
        ranges[ranges.count - 1] = aligned
        return ranges
    }
}
