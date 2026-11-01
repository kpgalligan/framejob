import AVFoundation

/// The held last frame (`heldTail`, `oneFrame`) and the builder's keyed and
/// `timeRange` reads of a track (`timeRange(of:)`, `convertsSources`, `keyed`),
/// with `missingClips`, the clips the compositor slates.
///
/// A pure move out of `CompositionBuilder.swift` (road map "creator-jobs"
/// CJ0c, T6): the declarations came here whole, in their existing order, with
/// their bodies untouched, so this file now carries the app's one `timeRange`
/// deprecation warning (`tools/proof/gate.py`'s `TYPECHECK_BASELINE` names it
/// here). **The toll is visibility**: `heldTail` and `missingClips` are
/// internal rather than private because their callers, `fill` and `build`,
/// stayed in `CompositionBuilder.swift`. `oneFrame` stays `private`: only
/// `heldTail` calls it.
extension CompositionBuilder {

    // MARK: - The held last frame

    /// A video segment whose source range runs past the end of `source`, as
    /// the TICKS of it the track covers (zero once the in point is past the
    /// end) and the track's last frame, `[end − oneFrame, end)` in the track's
    /// own timescale with `oneFrame` rounded DOWN into it, so the window never
    /// starts before that frame does. The covered end is floored onto the tick grid, so
    /// `fill` stays in ticks and the remainder is at least one tick; a duration that rounds
    /// UP onto the tick grid makes a one-tick hold, measured byte-identical to the plain
    /// insert, and the floor must stay a floor because a round would put `covered` past the
    /// track. Nil (the ordinary insert) when the track covers the range or is too coarse.
    static func heldTail(
        _ segment: PlanSegment, of source: AVAssetTrack
    ) -> (covered: Ticks, hold: CMTimeRange)? {
        let extent = timeRange(of: source)
        let asked = segment.sourceIn + segment.sourceDuration
        guard extent.end.isNumeric, time(asked) > extent.end else { return nil }
        let frame = CMTimeConvertScale(
            oneFrame(of: source), timescale: extent.end.timescale, method: .roundTowardZero)
        let hold = CMTimeRange(start: max(extent.start, extent.end - frame), end: extent.end)
        guard hold.duration > .zero else { return nil }
        let floored = CMTimeConvertScale(
            extent.end, timescale: CMTimeScale(ReelTime.perSecond), method: .roundTowardZero)
        return (min(segment.sourceDuration, max(0, floored.value - segment.sourceIn)), hold)
    }

    /// **The one synchronous `timeRange` read in the app**, on `firstTrack`'s
    /// terms: the deprecated getter stays, funnelled here so the placeholder,
    /// `heldTail` and `fillSilence` cost one warning between them and not one each.
    static func timeRange(of track: AVAssetTrack) -> CMTimeRange {
        track.timeRange
    }

    /// One frame of `track`: `minFrameDuration` when the file states one, else
    /// `1 / nominalFrameRate`, else 1/30 — its SMALLEST claim, since a window
    /// longer than the last frame shows the frame before it first. Read by
    /// KEY, deliberately: the Objective-C getters are not deprecated
    /// (`AVAssetTrack.h`, `AVF_DEPRECATED_FOR_SWIFT_ONLY`), only Swift's
    /// spelling is, for an `async` `load` confined to `MediaImporter.swift`,
    /// and the baseline counts deprecations per USE SITE — two named reads
    /// would be two new warnings. Measured, the keyed value is the named one.
    private static func oneFrame(of track: AVAssetTrack) -> CMTime {
        let minimum = (keyed(track, "minFrameDuration") as? NSValue)?.timeValue ?? .invalid
        if minimum.isNumeric, minimum > .zero { return minimum }
        let nominal = (keyed(track, "nominalFrameRate") as? NSNumber)?.floatValue ?? 0
        if nominal > 0, nominal < 100_000 {
            return CMTime(value: 1000, timescale: CMTimeScale((nominal * 1000).rounded()))
        }
        return CMTime(value: 1, timescale: 30)
    }

    /// True when any format description of `tracks` answers an
    /// `InputConversion` whose `startsConversion` is true. Read by KEY, for
    /// `oneFrame`'s reason; a composition track lists every inserted
    /// source's description (measured, M5).
    static func convertsSources(_ tracks: [AVMutableCompositionTrack]) -> Bool {
        tracks.contains { track in
            (keyed(track, "formatDescriptions") as? [CMFormatDescription] ?? []).contains {
                InputConversion.choose(for: $0)?.startsConversion == true
            }
        }
    }

    /// A property by key; nil, not an exception, for one the SDK dropped.
    static func keyed(_ track: AVAssetTrack, _ key: String) -> Any? {
        track.responds(to: NSSelectorFromString(key)) ? track.value(forKey: key) : nil
    }

    /// The clips whose media file did not resolve, so the compositor can draw
    /// spec §5.6's slate for them instead of the gap an absent source frame
    /// otherwise means. Video segments only: an `image` layer names its media
    /// directly and already slates itself, and an audio-only clip puts nothing
    /// on the canvas.
    ///
    /// A reversed clip whose backwards copy has not been rendered joins them:
    /// its file is there, but the frames it is meant to play are not, and a
    /// slate says that where playing the clip forwards would not. The pending
    /// set is unioned whole rather than filtered against the video tracks —
    /// the compositor only ever consults this for a layer that names a
    /// composition track, so an audio-only clip in it is inert.
    static func missingClips(
        plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution
    ) -> Set<UInt32> {
        var missing = reverse.pending
        for planTrack in plan.videoTracks {
            for segment in planTrack.segments where urls[segment.media] == nil {
                missing.insert(segment.clip)
            }
        }
        return missing
    }
}
