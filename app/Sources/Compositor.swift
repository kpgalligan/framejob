import AVFoundation
import AppKit
import CoreVideo
import Metal
import MetalPerformanceShaders

/// One `AVVideoComposition` instruction, carrying the `RecipeSource` slot the
/// frames inside it must be read from (spec §7.5).
///
/// The key is why this type exists instead of `AVVideoCompositionInstruction`:
/// `AVFoundation` instantiates ONE compositor object per player item and hands
/// it nothing about the document, so with a process-wide "current project" two
/// open windows would render each other's frames. The key travels on the
/// instruction, which the request hands back, so a document can only ever read
/// its own recipe. `mediaURLs` rides along for the same reason — an `image`
/// layer names a media id and only the document knows the file.
final class RecipeInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    /// True: a transition changes every frame inside its instruction, so
    /// AVFoundation must not reuse one composed frame across the range.
    let containsTweening: Bool = true
    // `nonisolated(unsafe)`: the protocol is `Sendable` and `NSValue` is not,
    // but this array is built once in `init` and never mutated, which is the
    // exact case the attribute exists for.
    nonisolated(unsafe) let requiredSourceTrackIDs: [NSValue]?
    /// Never a passthrough: every frame goes through the Metal pipeline, even
    /// a single full-frame layer, so opacity and colour edits show without a
    /// composition rebuild (§7.6).
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    /// The document's `RecipeSource` slot (`RecipeSource.swift`) — or an
    /// export's own, which is a fresh one. It names the project a frame is
    /// composed from AND, since phase 7, the `RecipeOptions` that project is
    /// asked with, so an option never has to be threaded through the
    /// instruction.
    let recipeKey: Int
    /// Media id → file, for `image` layers. Same map `CompositionBuilder`
    /// resolved the composition's assets from.
    let mediaURLs: [UInt32: URL]
    /// Composition video track id → the source orientation code
    /// (`CompositionBuilder.orientationCode`) of whatever that track is
    /// showing across THIS instruction. Per instruction because an
    /// instruction boundary falls wherever the visible clips change (§7.2),
    /// so within one, a track shows exactly one clip.
    let sourceOrientations: [Int: Int]
    /// Clips whose media file is gone (spec §5.6). A `track` layer with no
    /// source frame is normally just a gap, so the compositor cannot tell the
    /// two apart on its own — the plan can, because it knows which media each
    /// clip's segment came from and `urls` says which of those resolved.
    /// These get the slate instead of nothing.
    let missingClips: Set<UInt32>
    /// Composition video track ids whose segment across THIS instruction is a
    /// full-range media (spec §11 GR-22): a log curve's code domain follows
    /// it. Per instruction for `sourceOrientations`' reason; empty when no
    /// segment converts with a log curve.
    let fullRangeTracks: Set<Int>

    init(
        timeRange: CMTimeRange, requiredTrackIDs: [Int], recipeKey: Int,
        mediaURLs: [UInt32: URL], sourceOrientations: [Int: Int],
        missingClips: Set<UInt32>, fullRangeTracks: Set<Int> = []
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = requiredTrackIDs.map {
            NSNumber(value: CMPersistentTrackID($0))
        }
        self.recipeKey = recipeKey
        self.mediaURLs = mediaURLs
        self.sourceOrientations = sourceOrientations
        self.missingClips = missingClips
        self.fullRangeTracks = fullRangeTracks
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("RecipeInstruction does not support NSCoder")
    }
}

/// Why a frame could not be composed. Every one is reported through
/// `request.finish(with:)` — AVFoundation then drops that frame and keeps
/// playing, which is the whole point: a compositor that throws or traps takes
/// the player down with it.
enum CompositorError: LocalizedError {
    case metalUnavailable
    case noPixelBuffer
    case noDestinationTexture

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: return "Metal is not available on this system."
        case .noPixelBuffer: return "The render context ran out of pixel buffers."
        case .noDestinationTexture: return "The frame buffer could not be used as a texture."
        }
    }
}

/// The custom compositor (spec §7.5): one Metal pipeline, one pass per layer,
/// back to front, source-over into the destination.
///
/// AVFoundation creates this object itself (`customVideoCompositorClass`), so
/// it can take no arguments — everything per-document arrives on the
/// instruction. Requests are served on one serial queue and every exit path
/// answers the request exactly once.
class Compositor: NSObject, AVVideoCompositing {

    /// `defaults write com.kgalligan.FrameJob FrameJobCompositorTiming -bool YES`
    /// turns on the per-frame timing log — the measurement M1 step 5 is
    /// verified with ("playback stays at 60 fps on a 1080p source").
    static let timingDefaultsKey = "FrameJobCompositorTiming"

    private static let timingEnabled = UserDefaults.standard.bool(forKey: timingDefaultsKey)

    /// The one documented GCD seam on this side (app/CLAUDE.md): AVFoundation
    /// calls `startRequest` from its own threads and expects the work to be
    /// asynchronous, and a serial queue is what keeps GPU submission ordered.
    private let renderQueue = DispatchQueue(
        label: "com.kgalligan.framejob.compositor", qos: .userInitiated)

    private let renderer: MetalRenderer?
    private let lock = NSLock()
    private var renderContext: AVVideoCompositionRenderContext?
    private var cancelled = false
    private var frames = 0
    private var totalSeconds = 0.0
    private var worstSeconds = 0.0

    override init() {
        renderer = MetalRenderer()
        super.init()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("Compositor does not support NSCoder")
    }

    // MARK: - AVVideoCompositing

    /// The render context's buffers: 16-bit float, so a blend or a deep
    /// source keeps more than 256 levels a channel (spec §11 PR-1). The
    /// working format of every target a layer pipeline draws into follows it
    /// (`MetalRenderer.workingFormat`), and the export reader reads it.
    static let outputPixelFormat: OSType = kCVPixelFormatType_64RGBAHalf
    /// What every video source is decoded to: 16-bit float, so a 10-bit source
    /// keeps its levels; the layer stage clamps its values (spec §11 PR-2).
    static let sourcePixelFormat: OSType = kCVPixelFormatType_64RGBAHalf

    /// Metal-compatible `sourcePixelFormat`, sampled through `texture(from:)`.
    /// AVFoundation converts any other pixel format; for a
    /// `ConvertingCompositor` not colour: an HDR or wide-gamut frame arrives
    /// native and labelled, and step 0 converts it (spec §11 GR-15, §7.5).
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.sourcePixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    /// Today's answers, stated: AVFoundation conforms every source to the
    /// composition's colour, so an SDR-only project keeps its pixels and
    /// labels. A composition holding an HLG, PQ or wide-gamut source is built
    /// with `ConvertingCompositor` instead (`Compositor+Input.swift`, spec
    /// §11 GR-15 as amended), which answers both true and runs step 0.
    var canConformColorOfSourceFrames: Bool { false }
    /// False here; true in `ConvertingCompositor` (see above).
    var supportsHDRSourceFrames: Bool { false }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    /// A new context means new pixel buffers, so every `CVMetalTexture`
    /// wrapping a buffer from the OLD context is stale — the cache is flushed
    /// rather than left to age out, because those textures pin IOSurfaces the
    /// old context is trying to release.
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock()
        renderContext = newRenderContext
        lock.unlock()
        renderer?.flushPixelBufferTextures()
    }

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self = self else {
                asyncVideoCompositionRequest.finishCancelledRequest()
                return
            }
            guard !self.isCancelled else {
                asyncVideoCompositionRequest.finishCancelledRequest()
                return
            }
            self.serve(asyncVideoCompositionRequest)
        }
    }

    /// Flushes the queue: the cancelled flag makes every request already
    /// queued answer `finishCancelledRequest`, and the empty `sync` waits for
    /// the one in flight. AVFoundation calls this on a seek and at teardown,
    /// and requires that no request be left unanswered.
    func cancelAllPendingVideoCompositionRequests() {
        setCancelled(true)
        renderQueue.sync {}
        setCancelled(false)
    }

    // MARK: - Serving one frame

    private func serve(_ request: AVAsynchronousVideoCompositionRequest) {
        let started = CFAbsoluteTimeGetCurrent()
        guard let renderer = renderer else {
            request.finish(with: CompositorError.metalUnavailable)
            return
        }
        guard let destination = request.renderContext.newPixelBuffer() else {
            request.finish(with: CompositorError.noPixelBuffer)
            return
        }
        let instruction = request.videoCompositionInstruction as? RecipeInstruction
        let key = instruction?.recipeKey ?? 0
        let ticks = CompositionBuilder.ticks(request.compositionTime)
        // A playing preview's prefetch follows the frame asked for (G-36 (d)).
        GraphicPrefetch.shared.reach(key, ticks: ticks)
        // The key is the whole ask: `RecipeSource.recipe(for:at:)` reads the
        // project AND that key's `RecipeOptions` under one hold, so a burn-in
        // an export asked for arrives here without this file, the
        // instruction or `CompositionBuilder` carrying a flag of its own
        // (spec §7.3). Do not read the two halves separately.
        let recipe = RecipeSource.shared.recipe(for: key, at: ticks)
        do {
            try renderer.render(
                recipe: recipe, into: destination, request: request, instruction: instruction,
                converts: canConformColorOfSourceFrames)
            request.finish(withComposedVideoFrame: destination)
            #if FRAMEJOB_DEV_TOOLS
            PlaybackTrials.shared.served(
                key, ticks: ticks, seconds: CFAbsoluteTimeGetCurrent() - started,
                buffer: destination)
            #endif
            WaveformTaps.shared.offer(
                destination, key: instruction?.recipeKey ?? 0,
                signal: ScopeSignal(canvas: recipe?.canvas))
        } catch {
            // A frame that will not compose is dropped: the player shows the last one.
            request.finish(with: error)
        }
        record(CFAbsoluteTimeGetCurrent() - started)
    }

    // MARK: - Timing log

    /// Averages over a two-second window (120 frames) and reports the worst
    /// frame in it, which is the number that matters — an 8 ms budget with a
    /// 40 ms outlier every second still stutters (§7.5).
    private func record(_ seconds: Double) {
        guard Compositor.timingEnabled else { return }
        lock.lock()
        frames += 1
        totalSeconds += seconds
        worstSeconds = max(worstSeconds, seconds)
        let due = frames >= 120
        let average = totalSeconds / Double(max(frames, 1)) * 1000
        let worst = worstSeconds * 1000
        if due {
            frames = 0
            totalSeconds = 0
            worstSeconds = 0
        }
        lock.unlock()
        if due {
            // Step 0's passes over the same window (spec §11 GR-15): 0 for a
            // frame with no converted source. Appended, so the line's prefix
            // stays what the proofs' timing pattern reads.
            let passes = renderer?.inputs.takePassCount() ?? 0
            NSLog("[framejob] compositor: %.2f ms average, %.2f ms worst over 120 frames, "
                + "%ld input passes", average, worst, passes)
        }
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func setCancelled(_ value: Bool) {
        lock.lock()
        cancelled = value
        lock.unlock()
    }
}
