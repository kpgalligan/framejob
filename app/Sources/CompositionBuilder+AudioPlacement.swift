import AVFoundation

/// Where `fill` puts an audio segment's media on its composition track: the
/// plan's place, moved by the leads that make up for what plays it late
/// (spec §11 SY-24, SY-25).
extension CompositionBuilder {

    /// The leads one composition audio track's media is placed with.
    struct AudioShift: Equatable {
        /// Media placed this much EARLIER on the whole track.
        let trackLead: Ticks
        /// A time-scaled segment reads its source this much earlier.
        let scaledSourceLead: Ticks

        static let none = AudioShift(trackLead: 0, scaledSourceLead: 0)

        /// The noise reducer's one analysis window, 512 samples at 48 kHz
        /// (SY-25): the stage's output lags its input by exactly that, and a
        /// tap cannot read ahead, so the track's media goes in that much
        /// earlier instead.
        static let noiseReductionLead: Ticks =
            Ticks(AudioNoiseReductionStage.window) * ReelTime.perSecond / 48_000

        /// The varispeed unit's lead, 46 samples at 48 kHz (SY-24): a
        /// time-scaled segment played `off` comes out that much late at every
        /// rate measured, so it reads its source that much earlier.
        static let varispeedSourceLead: Ticks = 575

        /// The shift for one composition track: the noise lead when its tap
        /// runs noise reduction, and the varispeed lead when its segments
        /// play `off` (a plan audio track holds one pitch name, SY-26).
        static func of(segments: [PlanSegment], usesNoiseReduction: Bool) -> AudioShift {
            AudioShift(
                trackLead: usesNoiseReduction ? noiseReductionLead : 0,
                scaledSourceLead: segments.compactMap(\.pitch).first == "off"
                    ? varispeedSourceLead : 0)
        }
    }

    /// One segment's insert: `[sourceIn, sourceIn + sourceDuration)` of its
    /// source placed at `at` and, when the segment is time-scaled, scaled to
    /// `duration`.
    struct AudioPlacement: Equatable {
        let at: Ticks
        let sourceIn: Ticks
        let sourceDuration: Ticks
        let duration: Ticks
    }

    /// `segment` moved by `shift`. A lead that would put the insert before
    /// the track's 0 or before the source's 0 cuts the segment's head
    /// instead — that much timeline, and its share of source — so the rest
    /// still lands where it belongs. Nil when nothing of it is left.
    /// `.none` answers the segment unchanged.
    static func placement(of segment: PlanSegment, shift: AudioShift) -> AudioPlacement? {
        let start = segment.start
        let duration = segment.duration
        let sourceIn = segment.sourceIn
        let sourceDuration = segment.sourceDuration
        guard duration > 0, sourceDuration > 0 else { return nil }
        let lead = segment.isTimeScaled ? shift.scaledSourceLead : 0
        let at0 = start - shift.trackLead
        let in0 = sourceIn - lead
        // Timeline ticks to cut: enough to bring `at` to 0, and enough that
        // the source read starts at or after 0 (ceil(−in0·T/U)).
        let sourceCut: Ticks = in0 < 0
            ? (-in0 * duration + sourceDuration - 1) / sourceDuration : 0
        let cut = max(0, -at0, sourceCut)
        // Its share of source, floored (exactly `cut` when unscaled).
        let sourceShare = sourceDuration == duration ? cut : cut * sourceDuration / duration
        let placed = AudioPlacement(
            at: at0 + cut, sourceIn: in0 + sourceShare,
            sourceDuration: sourceDuration - sourceShare, duration: duration - cut)
        guard placed.sourceDuration > 0, placed.duration > 0 else { return nil }
        return placed
    }
}
