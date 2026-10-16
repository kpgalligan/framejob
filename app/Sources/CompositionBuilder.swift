import AVFoundation
import AppKit

/// The AVFoundation objects one composition plan turns into, kept together
/// with the plan JSON they were built from. `Playback` and `Exporter` both
/// hold one of these; the `planJSON` is what the next edit is string-compared
/// against to decide rebuild-versus-refresh (§7.6, §11).
struct BuiltComposition {
    let composition: AVComposition
    /// `AVVideoComposition(configuration: videoConfiguration)` — handed out
    /// as is wherever nothing about it is to change.
    let videoComposition: AVVideoComposition
    /// What `videoComposition` was built from (#91). A variant — Preview
    /// Quality's size, an export row's rate — is this value with one field
    /// changed, never a `mutableCopy()` of the composition.
    let videoConfiguration: AVVideoComposition.Configuration
    let audioMix: AVAudioMix
    /// The EXACT bytes `rc_project_composition_plan` returned. Compared as a
    /// string, never re-encoded and never decoded first — a re-encode can
    /// reorder keys and make an identical plan look structural.
    let planJSON: String
    /// One entry per audio track on a METERING build, empty otherwise: the
    /// sink that track's tap writes its levels into, and the envelope the
    /// reader multiplies them by. They ride here rather than in a fourth
    /// process-wide mirror beside `RecipeSource`, `AudioDSPSource` and
    /// `ReverseSource` because, unlike those three, nothing on the far side of
    /// a `recipeKey` needs them: the only reader is the `Playback` that
    /// asked for the build and already holds this object, so the sinks' life
    /// is exactly the composition's and no lock is involved at all.
    let meters: [LevelMeterTrack]
}

/// Plan JSON → `AVMutableComposition` + an `AVVideoComposition` built from an
/// `AVVideoComposition.Configuration` + `AVMutableAudioMix` (spec §7.2). Pure
/// translation: every decision was already made in Rust, and nothing here
/// consults the project.
///
/// Runs on the rebuild queue in `Playback.swift`, never on the main thread —
/// opening asset tracks touches the disk.
enum CompositionBuilder {

    /// Why a build gave up. All four mean "this plan cannot be played", and
    /// the caller shows an alert; a media file that is merely MISSING is not
    /// one of them — its segments become empty ranges and the compositor
    /// draws a slate over them (§5.6).
    enum BuildError: LocalizedError {
        case noDevice
        case trackCreationFailed(Int)
        case trackIDMismatch(requested: Int, got: Int)
        case insertFailed(clip: UInt32, underlying: any Error)

        var errorDescription: String? {
            switch self {
            case .noDevice:
                return "Could not create a composition track."
            case .trackCreationFailed(let id):
                return "Could not create composition track \(id)."
            case .trackIDMismatch(let requested, let got):
                return "Composition track \(requested) came back as \(got)."
            case .insertFailed(let clip, let underlying):
                return "Clip \(clip) could not be placed: \(underlying.localizedDescription)"
            }
        }
    }

    /// Builds everything an `AVPlayerItem` (or an export session) needs.
    ///
    /// `urls` maps media ids to files — `mediaURL(for:)`'s output for every
    /// entry in the project; a missing id is a missing file and its segments
    /// are left as empty time. `recipeKey` is the `RecipeSource` slot the
    /// compositor reads this document's frame recipes from, and travels on
    /// every instruction so two open documents can never read each other's.
    ///
    /// **`metering` is the preview's alone.** It is passed true by
    /// `Playback.startRebuild` and by nothing else, so an export and a
    /// rendered frame build exactly the audio path they built before the level
    /// meter existed — which is what lets "with `mono` off the export is
    /// byte-identical to a pre-phase export" be a claim about the mono fold
    /// and nothing else. A metering build gives EVERY audio track a tap, the
    /// inert ones included, because a meter that lights only on the tracks
    /// that happen to carry a compressor is worse than no meter.
    static func build(
        plan: CompositionPlan, planJSON: String, urls: [UInt32: URL], recipeKey: Int,
        metering: Bool = false
    ) throws -> BuiltComposition {
        let composition = AVMutableComposition()
        var assets: [UInt32: AVURLAsset] = [:]
        var reversedAssets: [UInt32: AVURLAsset] = [:]

        // Which clips play backwards, and which are still waiting for the file
        // that lets them. `Source::Media.reversed` is deliberately absent from
        // the plan — the core does no pixel work, so reversal changes neither
        // the plan nor the recipe (§11) — so it arrives beside the plan, from
        // the document, exactly as the audio DSP below does.
        let reverse = ReverseSource.shared.resolution(for: recipeKey)

        var videoTracks: [AVMutableCompositionTrack] = []
        for planTrack in plan.videoTracks {
            let track = try makeTrack(in: composition, mediaType: .video, id: planTrack.id)
            try fill(
                track, segments: planTrack.segments, mediaType: .video, urls: urls,
                reverse: reverse, assets: &assets, reversedAssets: &reversedAssets)
            videoTracks.append(track)
        }

        try addPlaceholderIfNeeded(to: composition, plan: plan)

        // The sample-level audio settings the plan cannot carry (pan, the
        // compressor, noise reduction). Resolved once per build and frozen
        // into the taps: they are not in the plan, so `Playback` treats a
        // change to them as structural and rebuilds, exactly as it already
        // does for a volume change — volume IS in the plan, as ramps.
        let dsp = AudioDSPSource.shared.parameters(for: recipeKey)
        // A non-48 kHz source's audio is read from its 48 kHz copy (SY-23).
        let audioURLs = Self.audioURLs(
            plan: plan, urls: urls, reverse: reverse, assets: &assets)
        var audioAssets = assets.filter { audioURLs[$0.key] == urls[$0.key] }
        let (inputParameters, meters) = try addAudioTracks(
            to: composition, plan: plan, urls: audioURLs, reverse: reverse, dsp: dsp,
            metering: metering, assets: &audioAssets, reversedAssets: &reversedAssets)

        // Source orientation is read once per media and then attached per
        // instruction, so the compositor can turn a rotated source's sampling
        // without knowing anything about assets.
        let codes = orientationCodes(plan: plan, urls: urls, assets: &assets)
        let missing = missingClips(plan: plan, urls: urls, reverse: reverse)
        let fullRange = fullRangeMedia(plan: plan, urls: urls, assets: &assets)

        let size = plan.renderSizeCG
        let ranges = instructionRanges(plan, ending: composition.duration)
        let instructions = zip(plan.instructions, ranges).map { instruction, range in
            RecipeInstruction(
                timeRange: range,
                // PITFALL, and not a bug: AVFoundation reads an EMPTY
                // `requiredSourceTrackIDs` as "every source track is
                // required" rather than "none". Harmless here — the
                // compositor takes only the tracks the frame recipe names,
                // so an over-broad requirement costs nothing but a decoder
                // that stays warm — and the plan emits `[]` for stretches
                // covered entirely by text, shape and image clips.
                requiredTrackIDs: instruction.requiredTrackIDs,
                recipeKey: recipeKey, mediaURLs: urls,
                sourceOrientations: trackOrientations(
                    plan: plan, instruction: instruction, codes: codes),
                missingClips: missing,
                fullRangeTracks: fullRangeTracks(
                    plan: plan, instruction: instruction, media: fullRange))
        }
        // Per composition (spec §11 GR-15 as amended): one holding an HLG, PQ
        // or wide-gamut source, or a media with Camera Log (GR-16, the plan's
        // segment `input`), is converting — `ConvertingCompositor`, its
        // frames BT.709 — and every other is built exactly as before.
        let converts = convertsSources(videoTracks) || plan.convertsMedia
        let videoConfiguration = AVVideoComposition.Configuration(
            colorPrimaries: converts ? AVVideoColorPrimaries_ITU_R_709_2 : nil,
            colorTransferFunction: converts ? AVVideoTransferFunction_ITU_R_709_2 : nil,
            colorYCbCrMatrix: converts ? AVVideoYCbCrMatrix_ITU_R_709_2 : nil,
            customVideoCompositorClass: converts ? ConvertingCompositor.self : Compositor.self,
            frameDuration: frameDuration(plan.fps),
            instructions: instructions, renderScale: 1,
            renderSize: size.width >= 1 && size.height >= 1
                ? size : CGSize(width: 1920, height: 1080))

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters

        return BuiltComposition(
            composition: composition,
            videoComposition: AVVideoComposition(configuration: videoConfiguration),
            videoConfiguration: videoConfiguration, audioMix: audioMix, planJSON: planJSON,
            meters: meters)
    }

    // MARK: - The media-less timeline

    /// Bundled one-frame black movie — see `addPlaceholderIfNeeded`.
    private static let placeholderName = "Blank"

    /// Gives a timeline of nothing but graphics, text, shapes and images a
    /// video track to tick against — for the preview's item and the exports.
    ///
    /// Those layers need no decoding, so §7.2 gives them no composition
    /// track — and a composition with no track renders nothing offline. An
    /// empty edit does not rescue it: AVFoundation reports a composition
    /// built only from `insertEmptyTimeRange` as duration ZERO (measured),
    /// the video composition's instructions then cover more than the
    /// composition does, and both `AVAssetExportSession` and
    /// `AVAssetImageGenerator` fail — the export with a bare "Operation
    /// Stopped". So the placeholder has to be REAL content: one 16×16 black
    /// frame, time-scaled across the whole duration the way a freeze frame is
    /// (§7.2's still idiom). The compositor never samples it — the recipe
    /// names no track for these layers — so it costs one decoded 16×16 frame
    /// and contributes no pixels.
    ///
    /// Its track id is one past the plan's own numbering, so it can never
    /// collide with a track a recipe names. If the resource is missing the
    /// composition keeps no track: exports fail and the preview's item does
    /// not play — never a crash (road map 10 §10.8).
    private static func addPlaceholderIfNeeded(
        to composition: AVMutableComposition, plan: CompositionPlan
    ) throws {
        guard plan.videoTracks.isEmpty, plan.duration > 0,
            let url = Bundle.main.url(forResource: placeholderName, withExtension: "mp4")
        else { return }
        let asset = AVURLAsset(url: url)
        guard let source = firstTrack(of: asset, mediaType: .video) else { return }
        let track = try makeTrack(
            in: composition, mediaType: .video, id: placeholderTrackID(plan))
        let frame = CMTimeRange(start: .zero, duration: timeRange(of: source).duration)
        try track.insertTimeRange(frame, of: source, at: .zero)
        track.scaleTimeRange(
            CMTimeRange(start: .zero, duration: frame.duration),
            toDuration: time(plan.duration))
    }

    // MARK: - Tracks

    /// Creates one composition track with the plan's id as its
    /// `preferredTrackID`, and REFUSES if AVFoundation hands back a
    /// different one. The recipe names its sources by that id (§7.2), so a
    /// silently renumbered track would render an empty canvas with no error
    /// anywhere — the failure this check exists to make loud.
    static func makeTrack(
        in composition: AVMutableComposition, mediaType: AVMediaType, id: Int
    ) throws -> AVMutableCompositionTrack {
        let requested = CMPersistentTrackID(id)
        guard let track = composition.addMutableTrack(
            withMediaType: mediaType, preferredTrackID: requested)
        else {
            throw BuildError.trackCreationFailed(id)
        }
        guard track.trackID == requested else {
            throw BuildError.trackIDMismatch(requested: id, got: Int(track.trackID))
        }
        return track
    }

    /// Walks one plan track's segments in order behind a CURSOR.
    ///
    /// The cursor is not a convenience: `scaleTimeRange` shifts everything
    /// AFTER the scaled range along the track, so a segment inserted at the
    /// absolute `start` the plan computed — a start that assumes the earlier
    /// segments kept their unscaled lengths — drifts by the accumulated
    /// scaling of every speed change before it. Appending at the cursor and
    /// scaling the range we just appended keeps composition time equal to
    /// timeline time at every step.
    ///
    /// **A reversed clip reads from another file entirely.** `reverse.ready`
    /// names the pre-rendered backwards copy of the segment's media, which is
    /// the same length as the forward one, so the segment's `source_in` and
    /// `source_duration` — measured in the reversed stream by the core's own
    /// convention (`Source::Media` in `model.rs`) — index straight into it
    /// with no arithmetic. The substitution is per CLIP and not per media: one
    /// movie can be forward on one track and backwards on another, and only
    /// the second reads the reversal.
    ///
    /// **A reversed clip with no file yet gets empty time.** It cannot get the
    /// forward asset: that would play the clip in the wrong direction with
    /// nothing on screen to say so, which is precisely the bug the pre-render
    /// exists to fix. `missingClips` then makes it draw §5.6's slate.
    ///
    /// **A video insert past the end of its source track holds the track's
    /// last frame** (road map 3's R0 surprise). ScreenCaptureKit ends the
    /// video track at the last screen change — 2.16 s of a 5.2 s recording —
    /// the media record takes the asset's duration, the audio's, and
    /// `insertTimeRange` takes a range the track does not cover WITHOUT
    /// clamping (5 s of a 1 s track reads back as one 5 s segment): picture
    /// at 0.99 s and BLACK from 3 s, measured in the built app. `heldTail`
    /// splits such a request into what the track covers and its last frame
    /// stretched over the rest — §7.2's freeze idiom inside one segment,
    /// BEFORE the speed step below, which scales the `sourceDuration` it
    /// always did. Video only; a covered range takes the one insert it always took.
    ///
    /// **An audio track's media goes in where `placement(of:shift:)` says**:
    /// the plan's place moved by the track's leads (SY-24, SY-25). Video
    /// passes `.none`, which places every segment exactly where the plan does.
    static func fill(
        _ track: AVMutableCompositionTrack, segments: [PlanSegment], mediaType: AVMediaType,
        urls: [UInt32: URL], reverse: ReverseResolution, assets: inout [UInt32: AVURLAsset],
        reversedAssets: inout [UInt32: AVURLAsset], shift: AudioShift = .none
    ) throws {
        var cursor: Ticks = 0
        for segment in segments {
            guard let place = placement(of: segment, shift: shift) else { continue }
            if place.at > cursor {
                track.insertEmptyTimeRange(
                    CMTimeRange(start: time(cursor), duration: time(place.at - cursor)))
                cursor = place.at
            }

            guard let source = resolveSource(
                for: segment, mediaType: mediaType, urls: urls, reverse: reverse,
                assets: &assets, reversedAssets: &reversedAssets)
            else {
                // Missing media, unreadable media, or a reverse that has not
                // been rendered: hold the place with empty time so every later
                // segment keeps its timeline position, and let the compositor
                // draw the slate the recipe asks for.
                let end = max(cursor, segment.start + segment.duration - shift.trackLead)
                if end > cursor {
                    track.insertEmptyTimeRange(
                        CMTimeRange(start: time(cursor), duration: time(end - cursor)))
                }
                cursor = end
                continue
            }

            let requested = CMTimeRange(
                start: time(place.sourceIn), duration: time(place.sourceDuration))
            do {
                if mediaType == .video, let tail = heldTail(segment, of: source) {
                    if tail.covered > 0 {
                        try track.insertTimeRange(
                            CMTimeRange(start: requested.start, duration: time(tail.covered)),
                            of: source, at: time(cursor))
                    }
                    let at = cursor + tail.covered
                    try track.insertTimeRange(tail.hold, of: source, at: time(at))
                    track.scaleTimeRange(
                        CMTimeRange(start: time(at), duration: tail.hold.duration),
                        toDuration: time(segment.sourceDuration - tail.covered))
                } else {
                    try track.insertTimeRange(requested, of: source, at: time(cursor))
                }
            } catch {
                throw BuildError.insertFailed(clip: segment.clip, underlying: error)
            }
            if segment.isTimeScaled {
                // Speed, and the freeze-frame idiom (one source frame
                // stretched to the still's whole length, §7.2).
                track.scaleTimeRange(
                    CMTimeRange(start: time(cursor), duration: time(place.sourceDuration)),
                    toDuration: time(place.duration))
            }
            cursor = place.at + place.duration
        }
    }

    /// The asset track a segment reads from, cached per media id so a clip
    /// split into twenty segments opens its file once.
    static func sourceTrack(
        for media: UInt32, mediaType: AVMediaType, urls: [UInt32: URL],
        assets: inout [UInt32: AVURLAsset]
    ) -> AVAssetTrack? {
        guard let url = urls[media] else { return nil }
        return assetTrack(at: url, key: media, mediaType: mediaType, assets: &assets)
    }

    /// One file's track of a kind, through a caller-owned cache. `key` is the
    /// media id in every case; the caller keeps FORWARD and REVERSED assets in
    /// separate dictionaries, so the same movie can be open both ways at once
    /// without either eviction touching the other.
    static func assetTrack(
        at url: URL, key: UInt32, mediaType: AVMediaType, assets: inout [UInt32: AVURLAsset]
    ) -> AVAssetTrack? {
        let asset: AVURLAsset
        if let cached = assets[key] {
            asset = cached
        } else {
            asset = AVURLAsset(
                url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            assets[key] = asset
        }
        return firstTrack(of: asset, mediaType: mediaType)
    }

    /// **The one synchronous track lookup in the app.**
    ///
    /// `tracks(withMediaType:)` (and `preferredTransform` in
    /// `orientationCodes`) are deprecated in favour of the async `loadTracks`
    /// — deliberately not taken: `async`/`await` is confined to
    /// `MediaImporter.swift` (app/CLAUDE.md), and this and `ReverseRenderer`
    /// both run on their own queues where blocking is the point. Funnelling
    /// every caller through here is what keeps that trade to a single
    /// deprecation warning rather than one per call site.
    static func firstTrack(of asset: AVAsset, mediaType: AVMediaType) -> AVAssetTrack? {
        DecoderSupport.enable()
        return asset.tracks(withMediaType: mediaType).first
    }

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
    private static func heldTail(
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
    /// terms: the deprecated getter stays, funnelled here so the placeholder
    /// and `heldTail` cost one warning between them and not one each.
    private static func timeRange(of track: AVAssetTrack) -> CMTimeRange {
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

    // MARK: - Source orientation

    /// One orientation code per media with a video track, read from the
    /// source's `preferredTransform`.
    ///
    /// This exists because a CUSTOM compositor gets RAW decoded frames: unlike
    /// the built-in one, nothing applies the preferred transform for us, and a
    /// portrait phone clip — whose model size is the DISPLAY size the importer
    /// probed (§7.7) — would otherwise render sideways and squashed. The code
    /// travels to the shader, which turns the sampling coordinates.
    private static func orientationCodes(
        plan: CompositionPlan, urls: [UInt32: URL], assets: inout [UInt32: AVURLAsset]
    ) -> [UInt32: Int] {
        var codes: [UInt32: Int] = [:]
        for planTrack in plan.videoTracks {
            for segment in planTrack.segments where codes[segment.media] == nil {
                guard let track = sourceTrack(
                    for: segment.media, mediaType: .video, urls: urls, assets: &assets)
                else { continue }
                codes[segment.media] = orientationCode(track.preferredTransform)
            }
        }
        return codes
    }

    /// The composition tracks an instruction needs, mapped to the orientation
    /// of whatever each is showing across it. An instruction boundary falls
    /// wherever the visible clips change (§7.2), so a track shows exactly one
    /// segment inside one instruction and this lookup is exact rather than a
    /// per-track approximation.
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
    private static func missingClips(
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

    private static func trackOrientations(
        plan: CompositionPlan, instruction: PlanInstruction, codes: [UInt32: Int]
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for trackID in instruction.requiredTrackIDs {
            guard let planTrack = plan.videoTracks.first(where: { $0.id == trackID }),
                let segment = planTrack.segments.first(where: {
                    instruction.start >= $0.start && instruction.start < $0.start + $0.duration
                }),
                let code = codes[segment.media], code != 0
            else { continue }
            result[trackID] = code
        }
        return result
    }

    /// A preferred transform as `quarterTurns | (mirrored ? 4 : 0)`, the
    /// encoding `Compositor.metal`'s `orientedUV` undoes.
    ///
    /// Only the four quarter turns and a horizontal mirror are classified —
    /// which is every transform a camera or an editor actually writes. A
    /// transform that is something else (a shear, an arbitrary angle) falls
    /// back to the nearest of them rather than refusing the file, and the
    /// frame is at worst turned wrong, never dropped.
    static func orientationCode(_ transform: CGAffineTransform) -> Int {
        let mirrored = transform.a * transform.d - transform.b * transform.c < 0
        // A reflection is one mirror away from a rotation: undo the mirror,
        // then classify what is left.
        let a = mirrored ? -transform.a : transform.a
        let b = mirrored ? -transform.b : transform.b
        let c = transform.c
        let d = transform.d
        func near(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) < 0.001 }
        var turns = 0
        if near(a, 0), near(b, 1), near(c, -1), near(d, 0) {
            turns = 1
        } else if near(a, -1), near(b, 0), near(c, 0), near(d, -1) {
            turns = 2
        } else if near(a, 0), near(b, -1), near(c, 1), near(d, 0) {
            turns = 3
        }
        return turns | (mirrored ? 4 : 0)
    }

    // MARK: - Time

    /// Ticks as a `CMTime` at the project's own timescale. NEVER through
    /// `CMTime(seconds:)`: 600 000 divides every frame duration exactly
    /// (§5.1) and a round trip through Double seconds does not, which shows
    /// up as a one-frame drift an hour into a timeline.
    static func time(_ ticks: Ticks) -> CMTime {
        CMTime(value: ticks, timescale: CMTimeScale(ReelTime.perSecond))
    }

    /// A `CMTime` back as ticks — the same conversion in the other
    /// direction, and the ONE implementation of it: the compositor converts
    /// `compositionTime` with this, and `MediaImporter` a probed duration.
    /// Through the timescale, never through `seconds`, for the same reason.
    static func ticks(_ time: CMTime) -> Ticks {
        guard time.isNumeric else { return 0 }
        let scaled = CMTimeConvertScale(
            time, timescale: CMTimeScale(ReelTime.perSecond), method: .roundHalfAwayFromZero)
        return scaled.value
    }

    /// One frame as a `CMTime`, exact for the /1001 rates too.
    static func frameDuration(_ fps: Fps) -> CMTime {
        guard fps.num > 0, fps.den > 0 else { return CMTime(value: 1, timescale: 30) }
        return CMTime(value: CMTimeValue(fps.den), timescale: CMTimeScale(fps.num))
    }
}
