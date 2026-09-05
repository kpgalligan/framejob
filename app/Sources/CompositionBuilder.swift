import AVFoundation
import AppKit

/// The AVFoundation objects one composition plan turns into, kept together
/// with the plan JSON they were built from. `Playback` and `Exporter` both
/// hold one of these; the `planJSON` is what the next edit is string-compared
/// against to decide rebuild-versus-refresh (§7.6, §11).
struct BuiltComposition {
    let composition: AVComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVAudioMix
    /// The EXACT bytes `rc_project_composition_plan` returned. Compared as a
    /// string, never re-encoded and never decoded first — a re-encode can
    /// reorder keys and make an identical plan look structural.
    let planJSON: String
}

/// Plan JSON → `AVMutableComposition` + `AVMutableVideoComposition` +
/// `AVMutableAudioMix` (spec §7.2). Pure translation: every decision was
/// already made in Rust, and nothing here consults the project.
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
    static func build(
        plan: CompositionPlan, planJSON: String, urls: [UInt32: URL], recipeKey: Int
    ) throws -> BuiltComposition {
        let composition = AVMutableComposition()
        var assets: [UInt32: AVURLAsset] = [:]

        for planTrack in plan.videoTracks {
            let track = try makeTrack(in: composition, mediaType: .video, id: planTrack.id)
            try fill(track, from: planTrack, mediaType: .video, urls: urls, assets: &assets)
        }

        try addPlaceholderIfNeeded(to: composition, plan: plan)

        var inputParameters: [AVAudioMixInputParameters] = []
        for planTrack in plan.audioTracks {
            let track = try makeTrack(in: composition, mediaType: .audio, id: planTrack.id)
            try fill(track, from: planTrack, mediaType: .audio, urls: urls, assets: &assets)
            inputParameters.append(audioParameters(for: track, plan: planTrack))
        }

        // Source orientation is read once per media and then attached per
        // instruction, so the compositor can turn a rotated source's sampling
        // without knowing anything about assets.
        let codes = orientationCodes(plan: plan, urls: urls, assets: &assets)
        let missing = missingClips(plan: plan, urls: urls)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = frameDuration(plan.fps)
        let size = plan.renderSizeCG
        videoComposition.renderSize =
            size.width >= 1 && size.height >= 1 ? size : CGSize(width: 1920, height: 1080)
        videoComposition.renderScale = 1
        videoComposition.customVideoCompositorClass = Compositor.self
        videoComposition.instructions = plan.instructions.map { instruction in
            RecipeInstruction(
                timeRange: CMTimeRange(
                    start: time(instruction.start), duration: time(max(1, instruction.duration))),
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
                missingClips: missing)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters

        return BuiltComposition(
            composition: composition, videoComposition: videoComposition, audioMix: audioMix,
            planJSON: planJSON)
    }

    // MARK: - The media-less timeline

    /// Bundled one-frame black movie — see `addPlaceholderIfNeeded`.
    private static let placeholderName = "Blank"

    /// Gives a timeline of nothing but text, shapes and images a video track
    /// to tick against.
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
    /// composition is left as it was: the caller still refuses, which is the
    /// old behaviour rather than a crash.
    private static func addPlaceholderIfNeeded(
        to composition: AVMutableComposition, plan: CompositionPlan
    ) throws {
        guard plan.videoTracks.isEmpty, plan.duration > 0,
            let url = Bundle.main.url(forResource: placeholderName, withExtension: "mp4")
        else { return }
        let asset = AVURLAsset(url: url)
        guard let source = asset.tracks(withMediaType: .video).first else { return }
        let id = (plan.audioTracks.map(\.id).max() ?? 0) + 1
        let track = try makeTrack(in: composition, mediaType: .video, id: id)
        let frame = CMTimeRange(start: .zero, duration: source.timeRange.duration)
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
    private static func makeTrack(
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
    private static func fill(
        _ track: AVMutableCompositionTrack, from planTrack: PlanTrack, mediaType: AVMediaType,
        urls: [UInt32: URL], assets: inout [UInt32: AVURLAsset]
    ) throws {
        var cursor: Ticks = 0
        for segment in planTrack.segments {
            if segment.start > cursor {
                track.insertEmptyTimeRange(
                    CMTimeRange(start: time(cursor), duration: time(segment.start - cursor)))
                cursor = segment.start
            }
            guard segment.duration > 0 else { continue }

            let source = sourceTrack(
                for: segment.media, mediaType: mediaType, urls: urls, assets: &assets)
            guard let source = source else {
                // Missing (or unreadable) media: hold the place with empty
                // time so every later segment keeps its timeline position,
                // and let the compositor draw the slate the recipe asks for.
                track.insertEmptyTimeRange(
                    CMTimeRange(start: time(cursor), duration: time(segment.duration)))
                cursor = segment.start + segment.duration
                continue
            }

            do {
                try track.insertTimeRange(
                    CMTimeRange(
                        start: time(segment.sourceIn), duration: time(segment.sourceDuration)),
                    of: source, at: time(cursor))
            } catch {
                throw BuildError.insertFailed(clip: segment.clip, underlying: error)
            }
            if segment.isTimeScaled {
                // Speed, and the freeze-frame idiom (one source frame
                // stretched to the still's whole length, §7.2).
                track.scaleTimeRange(
                    CMTimeRange(start: time(cursor), duration: time(segment.sourceDuration)),
                    toDuration: time(segment.duration))
            }
            cursor = segment.start + segment.duration
        }
    }

    /// The asset track a segment reads from, cached per media id so a clip
    /// split into twenty segments opens its file once.
    ///
    /// `tracks(withMediaType:)` (and `preferredTransform` in
    /// `orientationCodes`) are deprecated in favour of the async `loadTracks`
    /// — deliberately not taken: `async`/`await` is confined to
    /// `MediaImporter.swift` (app/CLAUDE.md), and this runs on the rebuild
    /// queue where blocking is the point. Those two deprecation warnings are
    /// that trade, and they are the only ones in this file.
    private static func sourceTrack(
        for media: UInt32, mediaType: AVMediaType, urls: [UInt32: URL],
        assets: inout [UInt32: AVURLAsset]
    ) -> AVAssetTrack? {
        let asset: AVURLAsset
        if let cached = assets[media] {
            asset = cached
        } else {
            guard let url = urls[media] else { return nil }
            asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            assets[media] = asset
        }
        return asset.tracks(withMediaType: mediaType).first
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
    private static func missingClips(
        plan: CompositionPlan, urls: [UInt32: URL]
    ) -> Set<UInt32> {
        var missing: Set<UInt32> = []
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

    // MARK: - Audio

    /// One input-parameter block per composition audio track: the plan's
    /// piecewise-linear envelope as volume ramps, plus the time-pitch
    /// algorithm its segments asked for.
    ///
    /// `mono` is NOT expressed here. `AVMutableAudioMixInputParameters` has
    /// no channel-fold control — the only ways are an
    /// `AVAudioMixInputParameters` audio tap or an `AVAssetReader`
    /// re-render, both out of scope for M2 — so a clip with `mono: true`
    /// plays in stereo for now. Spec §7.2 says so explicitly; the flag is
    /// still carried in the plan so the day this grows a tap, nothing in
    /// Rust changes.
    private static func audioParameters(
        for track: AVMutableCompositionTrack, plan: PlanTrack
    ) -> AVAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        if let pitch = plan.segments.compactMap({ $0.pitch }).first {
            switch pitch {
            case "spectral": parameters.audioTimePitchAlgorithm = .spectral
            case "off": parameters.audioTimePitchAlgorithm = .varispeed
            case "time_domain": parameters.audioTimePitchAlgorithm = .timeDomain
            default: break
            }
        }
        for ramp in plan.ramps ?? [] where ramp.duration > 0 {
            parameters.setVolumeRamp(
                fromStartVolume: Float(ramp.from), toEndVolume: Float(ramp.to),
                timeRange: CMTimeRange(start: time(ramp.start), duration: time(ramp.duration)))
        }
        return parameters
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
