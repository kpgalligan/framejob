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

    /// The document's `RecipeSource` slot (`ReelCore.swift`).
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

    init(
        timeRange: CMTimeRange, requiredTrackIDs: [Int], recipeKey: Int,
        mediaURLs: [UInt32: URL], sourceOrientations: [Int: Int],
        missingClips: Set<UInt32>
    ) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = requiredTrackIDs.map {
            NSNumber(value: CMPersistentTrackID($0))
        }
        self.recipeKey = recipeKey
        self.mediaURLs = mediaURLs
        self.sourceOrientations = sourceOrientations
        self.missingClips = missingClips
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
final class Compositor: NSObject, AVVideoCompositing {

    /// `defaults write com.kgalligan.Reelcut ReelcutCompositorTiming -bool YES`
    /// turns on the per-frame timing log — the measurement M1 step 5 is
    /// verified with ("playback stays at 60 fps on a 1080p source").
    static let timingDefaultsKey = "ReelcutCompositorTiming"

    private static let timingEnabled = UserDefaults.standard.bool(forKey: timingDefaultsKey)

    /// The one documented GCD seam on this side (app/CLAUDE.md): AVFoundation
    /// calls `startRequest` from its own threads and expects the work to be
    /// asynchronous, and a serial queue is what keeps GPU submission ordered.
    private let renderQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.compositor", qos: .userInitiated)

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

    /// 32BGRA, Metal-compatible: the format the shader samples and the only
    /// one this pipeline understands. AVFoundation converts anything else —
    /// which is also how HDR sources arrive tone-mapped to SDR (§7.5).
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
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
        let recipe = RecipeSource.shared.recipe(
            for: instruction?.recipeKey ?? 0,
            at: CompositionBuilder.ticks(request.compositionTime))
        do {
            try renderer.render(
                recipe: recipe, into: destination, request: request, instruction: instruction)
            request.finish(withComposedVideoFrame: destination)
        } catch {
            // A frame that will not compose is dropped, not fatal: the player
            // shows the previous frame and playback continues.
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
            NSLog("[reelcut] compositor: %.2f ms average, %.2f ms worst over 120 frames",
                average, worst)
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

// MARK: - Uniforms

/// The per-layer uniform block, laid out to match `LayerUniforms` in
/// `app/Resources/Shaders/Compositor.metal` FIELD FOR FIELD.
///
/// LAYOUT CONTRACT: every member is a scalar `Float`, so both compilers lay
/// the struct out sequentially with 4-byte alignment and no padding can drift
/// between them. Never introduce a `SIMD2`/`SIMD4` member here (or a vector
/// type there) — the alignment rules for vectors differ from Swift's and the
/// mismatch shows up as a frame of garbage, not as a compile error. Add
/// fields at the END, in groups of four (the struct is deliberately a
/// multiple of 16 bytes), and mirror them in the shader in the same order.
struct LayerUniforms {
    var canvasWidth: Float = 1
    var canvasHeight: Float = 1
    var anchorX: Float = 0
    var anchorY: Float = 0
    var sourceWidth: Float = 1
    var sourceHeight: Float = 1
    var scale: Float = 1
    var rotation: Float = 0
    var cropL: Float = 0
    var cropT: Float = 0
    var cropR: Float = 0
    var cropB: Float = 0
    var cornerRadius: Float = 0
    var opacity: Float = 1
    var brightness: Float = 0
    var contrast: Float = 0
    var saturation: Float = 0
    var hue: Float = 0
    var chromaEnabled: Float = 0
    var chromaKeyR: Float = 0
    var chromaKeyG: Float = 0
    var chromaKeyB: Float = 0
    var chromaTolerance: Float = 0
    var chromaSoftness: Float = 0
    var chromaSpill: Float = 0
    var transitionKind: Float = 0
    var transitionProgress: Float = 0
    var transitionIncoming: Float = 0
    var transitionDirX: Float = 0
    var transitionDirY: Float = 0
    var premultiplied: Float = 0
    var slate: Float = 0
    /// 0…3 clockwise quarter turns from the texture's coded orientation to the
    /// display orientation the model measured (`CompositionBuilder`
    /// classifies the source's `preferredTransform`).
    var sourceQuarterTurns: Float = 0
    var sourceMirrored: Float = 0
    /// The transition partner's canvas-space box and its own alpha, for the
    /// OUTGOING half of a dissolve. The shader divides this layer's weight by
    /// the attenuation the incoming pass is about to apply, which is what
    /// keeps a dissolve's total weight at 1 instead of dipping to 0.75 in the
    /// middle. An empty box (all zeros) means "assume no cover", which is the
    /// conservative reading and the pre-fix behaviour.
    var partnerMinX: Float = 0
    var partnerMinY: Float = 0
    var partnerMaxX: Float = 0
    var partnerMaxY: Float = 0
    var partnerAlpha: Float = 0
    /// 1 = this pass is the shadow MASK pass: the fragment stage returns the
    /// layer's coverage instead of its colour so `MPSImageGaussianBlur` has a
    /// clean silhouette to work on (see `encodeShadow`). Every input to the
    /// alpha still applies, which is why the mask is drawn by the layer
    /// pipeline itself and not by a simpler one that would drift out of step
    /// with it.
    var shadowMask: Float = 0
    // The M3 effect block — filters, reflection, spotlight and the nest clip
    // rectangle — and, after it, phase 3c's obscured regions.
    // `CompositorEffects.swift` fills every one of these and is where each
    // field's meaning, units and range are argued; the declarations live here
    // because the layout contract above governs the whole struct and a reader
    // checking it against `Compositor.metal` has to see all 104 fields in one
    // list.
    //
    // The M3 block's 28 begin with the four floats that used to be
    // `reserved0…3`; the obscure block's 36 restore a padding tail of three.
    // 40 + 28 + 36 = 104 floats = 416 bytes, and 416 is 26 × 16.
    var filterKind0: Float = 0
    var filterKind1: Float = 0
    var filterKind2: Float = 0
    var filterKind3: Float = 0
    var filterAmount0: Float = 0
    var filterAmount1: Float = 0
    var filterAmount2: Float = 0
    var filterAmount3: Float = 0
    var reflectionPass: Float = 0
    var reflectionOpacity: Float = 0
    var reflectionHeight: Float = 0
    var reflectionGap: Float = 0
    var reflectionFalloff: Float = 0
    var spotEnabled: Float = 0
    var spotShape: Float = 0
    var spotX: Float = 0
    var spotY: Float = 0
    var spotW: Float = 0
    var spotH: Float = 0
    var spotFeather: Float = 0
    var spotDim: Float = 0
    var spotZoom: Float = 1
    var clipEnabled: Float = 0
    var clipX: Float = 0
    var clipY: Float = 0
    var clipW: Float = 0
    var clipH: Float = 0
    var clipRotation: Float = 0
    // The obscured regions (phase 3c). Four slots of eight fields, laid out
    // REGION-MAJOR — all of region 0, then region 1 — where the filter block
    // above is field-major. A filter's record is two fields, so field-major
    // happened to fall into runs of four there; an eight-field record laid out
    // field-major would give thirty-two lines no reader could line up against
    // the shader's, and reading the two lists side by side is the ONLY way
    // this contract is ever checked.
    //
    // Each slot repeats `ObscureProps`'s own field order, which is
    // `ObscureRegion`'s in `model_regions.rs`, which is the spotlight block's
    // above: shape, centre, size, feather, then the two that say what the
    // region does. `obscureEnabled` is the `spotEnabled` / `clipEnabled`
    // precedent — one uniform read in the fragment stage's effect gate
    // instead of four kind codes, and that gate's shape was measured.
    var obscureEnabled: Float = 0
    var obscure0Shape: Float = 0
    var obscure0X: Float = 0
    var obscure0Y: Float = 0
    var obscure0W: Float = 0
    var obscure0H: Float = 0
    var obscure0Feather: Float = 0
    var obscure0Kind: Float = 0
    var obscure0Amount: Float = 0
    var obscure1Shape: Float = 0
    var obscure1X: Float = 0
    var obscure1Y: Float = 0
    var obscure1W: Float = 0
    var obscure1H: Float = 0
    var obscure1Feather: Float = 0
    var obscure1Kind: Float = 0
    var obscure1Amount: Float = 0
    var obscure2Shape: Float = 0
    var obscure2X: Float = 0
    var obscure2Y: Float = 0
    var obscure2W: Float = 0
    var obscure2H: Float = 0
    var obscure2Feather: Float = 0
    var obscure2Kind: Float = 0
    var obscure2Amount: Float = 0
    var obscure3Shape: Float = 0
    var obscure3X: Float = 0
    var obscure3Y: Float = 0
    var obscure3W: Float = 0
    var obscure3H: Float = 0
    var obscure3Feather: Float = 0
    var obscure3Kind: Float = 0
    var obscure3Amount: Float = 0
    // The padding tail, back after the M3 block consumed the last one. Three
    // floats, so the next field to land can be added on its own; a fourth
    // needs three companions again.
    var reserved0: Float = 0
    var reserved1: Float = 0
    var reserved2: Float = 0
}

/// The shadow pass's uniform block, mirroring `ShadowUniforms` in
/// `Compositor.metal` FIELD FOR FIELD under the same layout contract as
/// `LayerUniforms` — scalars only, added at the end, a multiple of 16 bytes.
///
/// Separate from `LayerUniforms` because the shadow draw is a full-canvas quad
/// that samples a mask: it shares none of the layer block's placement fields,
/// and keeping it apart costs `LayerUniforms` one float rather than six.
struct ShadowUniforms {
    var canvasWidth: Float = 1
    var canvasHeight: Float = 1
    /// The displacement in CANVAS pixels, y down, resolved from the model's
    /// (distance, angle) by `encodeShadow`.
    var offsetX: Float = 0
    var offsetY: Float = 0
    var colorR: Float = 0
    var colorG: Float = 0
    var colorB: Float = 0
    /// The shadow's opacity with the shadow colour's own alpha folded in.
    var opacity: Float = 0
}

/// `TransitionKind` (§5.2) as the shader's code plus its direction vector.
/// Four push directions collapse to one code and four vectors, which is why
/// the shader has eight branches and not eleven.
enum TransitionCode {
    static func code(_ kind: TransitionKind) -> Float {
        switch kind {
        case .crossDissolve: return 1
        case .fadeBlack: return 2
        case .fadeWhite: return 3
        case .pushLeft, .pushRight, .pushUp, .pushDown: return 4
        case .slide: return 5
        case .wipe: return 6
        case .zoom: return 7
        }
    }

    /// The direction the OUTGOING layer leaves in (and the incoming arrives
    /// from the opposite edge). For a wipe it is the direction the edge
    /// sweeps.
    static func direction(_ kind: TransitionKind) -> (x: Float, y: Float) {
        switch kind {
        case .pushLeft: return (-1, 0)
        case .pushRight: return (1, 0)
        case .pushUp: return (0, -1)
        case .pushDown: return (0, 1)
        // Slide: the incoming clip travels leftward in from the right edge.
        case .slide: return (-1, 0)
        case .wipe: return (1, 0)
        case .crossDissolve, .fadeBlack, .fadeWhite, .zoom: return (0, 0)
        }
    }
}

/// The destination render pass, as a value that can be suspended and resumed.
///
/// One encoder for the whole frame is the fast path and stays the fast path:
/// it is created once, every layer draws into it, and an unshadowed frame
/// never touches anything else here. A shadow, though, has to render its mask
/// into a DIFFERENT texture and then run an MPS kernel, and neither can be
/// encoded while a render encoder is open — so the shadow sequence suspends
/// the pass and the next `open()` resumes it with `.load` in place of
/// `.clear`. That costs a store and a load of the canvas per shadowed layer,
/// which is the standing price of doing the blur in the same command buffer;
/// the alternative, one offscreen texture per shadowed layer so every mask
/// could be rendered up front, is the allocation the budget refuses.
private struct DestinationPass {
    let buffer: MTLCommandBuffer
    let target: MTLTexture
    let clear: MTLClearColor
    let pipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState
    private var encoder: MTLRenderCommandEncoder?
    /// False only before the very first `open()`. The first pass CLEARS —
    /// the destination is a recycled pixel buffer and holds an old frame —
    /// and every resumption after it loads what has been drawn so far.
    private var cleared = false

    /// Spelled out because the private members above would otherwise make the
    /// memberwise initializer private too.
    init(
        buffer: MTLCommandBuffer, target: MTLTexture, clear: MTLClearColor,
        pipeline: MTLRenderPipelineState, sampler: MTLSamplerState
    ) {
        self.buffer = buffer
        self.target = target
        self.clear = clear
        self.pipeline = pipeline
        self.sampler = sampler
    }

    /// The open encoder, opening one if the pass is suspended. A newly opened
    /// encoder carries the layer pipeline and the shared sampler, so a caller
    /// that has not changed either draws straight into it.
    mutating func open() -> MTLRenderCommandEncoder? {
        if let encoder = encoder { return encoder }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = cleared ? .load : .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = clear
        guard let opened = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        opened.setRenderPipelineState(pipeline)
        opened.setFragmentSamplerState(sampler, index: 0)
        encoder = opened
        cleared = true
        return opened
    }

    /// Ends the encoder if one is open. Also how the frame is finished: the
    /// command buffer must have no open encoder when it is committed.
    mutating func suspend() {
        encoder?.endEncoding()
        encoder = nil
    }
}

// MARK: - The Metal side

/// Device, pipeline and caches for the compositor. Split out so `Compositor`
/// stays a protocol implementation and so a machine with no Metal device
/// degrades to "every frame finishes with an error" instead of trapping in
/// `init`.
final class MetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// The same layer fragment stage compiled WITH the two filters that
    /// gather neighbouring pixels — see `kGatherFilters` in the shader for the
    /// measurement that made this a second pipeline instead of a branch, and
    /// `Collection.needsGather` for which layers get it.
    private let gatherPipeline: MTLRenderPipelineState
    /// The full-canvas quad that draws one blurred mask as a shadow (§7.5).
    private let shadowPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    /// Bound wherever the shader ignores the texture (the missing-media
    /// slate), because a draw with no texture bound is undefined.
    private let placeholder: MTLTexture
    private let renderers: LayerRenderers
    /// Whether this device can run `MPSImageGaussianBlur`. Every Mac the app
    /// supports can, but the check is free and a `false` here degrades to a
    /// hard-edged shadow instead of to a dropped frame.
    private let blurSupported: Bool
    /// The one shared offscreen pair, sized to the canvas — see `encodeShadow`
    /// for why canvas-sized and why one pair. Nil until the first shadow is
    /// drawn, so a project without shadows allocates nothing, and replaced
    /// when the canvas size changes.
    private var shadowSurfaces: ShadowSurfaces?
    /// `MPSImageGaussianBlur` bakes its sigma in at init, so a kernel built
    /// per frame would build a new one on every tick of the blur slider.
    /// Keyed by sigma quantized to a quarter pixel — finer than anyone can
    /// see — and emptied wholesale once it grows past a handful, which is all
    /// a dragged slider ever leaves behind.
    private var blurKernels: [Int: MPSImageGaussianBlur] = [:]

    /// The canvas-sized mask and its blurred pair.
    private struct ShadowSurfaces {
        let mask: MTLTexture
        let blurred: MTLTexture
    }

    /// The sigma cap. The core only enforces `blur >= 0` (`props_check.rs`), so
    /// an agent is free to ask for 100 000, and MPS would take the GPU with
    /// it. The inspector's slider stops at 200 source pixels — σ = 100 at 1×
    /// — so the cap only bites on a layer scaled past 1× at maximum blur.
    private static let maxShadowSigma: Float = 100
    /// Below this the Gaussian is narrower than a pixel: skip MPS entirely and
    /// let the shadow draw sample the unblurred mask, which is what a
    /// `blur: 0` shadow means anyway.
    private static let minShadowSigma: Float = 0.5

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else { return nil }
        // The app target compiles `Compositor.metal` into the bundle's default
        // library; the bundle form is tried first so the shader still loads in
        // a test host where the app is not the main bundle.
        let library = (try? device.makeDefaultLibrary(bundle: Bundle.main))
            ?? device.makeDefaultLibrary()
        guard let library = library,
            let vertexFunction = library.makeFunction(name: "reelcut_layer_vertex"),
            let fragmentFunction = MetalRenderer.layerFragment(library, gather: false),
            let gatherFunction = MetalRenderer.layerFragment(library, gather: true),
            let shadowVertex = library.makeFunction(name: "reelcut_shadow_vertex"),
            let shadowFragment = library.makeFunction(name: "reelcut_shadow_fragment")
        else { return nil }

        guard
            let pipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut layer", vertex: vertexFunction,
                    fragment: fragmentFunction)),
            let gatherPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut layer, gathering", vertex: vertexFunction,
                    fragment: gatherFunction)),
            let shadowPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut shadow", vertex: shadowVertex, fragment: shadowFragment))
        else { return nil }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        // Clamp, so a crop window that lands exactly on the edge never wraps
        // a row of pixels around from the other side.
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        else { return nil }

        // The cache is asked for both source and destination textures, so it
        // is created with both usages.
        var cache: CVMetalTextureCache?
        let usage = MTLTextureUsage([.shaderRead, .renderTarget]).rawValue
        CVMetalTextureCacheCreate(
            kCFAllocatorDefault, [kCVMetalTextureUsage: usage] as CFDictionary, device, nil,
            &cache)
        guard let cache = cache else { return nil }

        let placeholderDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        placeholderDescriptor.usage = [.shaderRead]
        placeholderDescriptor.storageMode = .managed
        guard let placeholder = device.makeTexture(descriptor: placeholderDescriptor)
        else { return nil }
        var white: UInt32 = 0xFFFF_FFFF
        placeholder.replace(
            region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white,
            bytesPerRow: 4)

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.gatherPipeline = gatherPipeline
        self.shadowPipeline = shadowPipeline
        self.sampler = sampler
        self.textureCache = cache
        self.placeholder = placeholder
        self.renderers = LayerRenderers(device: device)
        self.blurSupported = MPSSupportsMTLDevice(device)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("MetalRenderer does not support NSCoder")
    }

    /// The compositor's ONE blend mode, in descriptor form: source-over on
    /// PREMULTIPLIED colour, so the source factor is one and not source alpha.
    /// Both pipelines are built from this — a shadow is just another layer,
    /// drawn under its own.
    private static func pipelineDescriptor(
        label: String, vertex: MTLFunction, fragment: MTLFunction
    ) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return descriptor
    }

    /// Drops the `CVMetalTexture`s wrapping the previous render context's
    /// pixel buffers.
    func flushPixelBufferTextures() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    /// Composes one frame: clear to the canvas background, then one pass per
    /// recipe layer back to front — plus, for a layer that has a shadow, the
    /// three passes `encodeShadow` puts in front of it.
    func render(
        recipe: FrameRecipe?, into destination: CVPixelBuffer,
        request: AVAsynchronousVideoCompositionRequest, instruction: RecipeInstruction?
    ) throws {
        // Every CVMetalTexture stays alive until the GPU is done with it —
        // dropping the wrapper early invalidates the MTLTexture inside it and
        // renders black.
        var live: [CVMetalTexture] = []
        guard let target = texture(from: destination, live: &live) else {
            throw CompositorError.noDestinationTexture
        }

        let canvas = recipe?.canvas ?? RecipeCanvas(
            width: target.width, height: target.height, background: [0, 0, 0, 1])
        guard let buffer = commandQueue.makeCommandBuffer() else {
            throw CompositorError.noDestinationTexture
        }
        // One encoder for the whole frame, as before — but a shadowed layer
        // has to interrupt it (`encodeShadow`), so the pass is a value that
        // can be suspended and resumed rather than one long-lived encoder.
        var pass = DestinationPass(
            buffer: buffer, target: target, clear: clearColor(canvas.background),
            pipeline: pipeline, sampler: sampler)
        // Opened eagerly: a recipe with no layers at all still has to CLEAR
        // the destination, which is a recycled pixel buffer holding an old
        // frame, not a blank one.
        guard pass.open() != nil else { throw CompositorError.noDestinationTexture }

        let layers = recipe?.layers ?? []
        for layer in layers {
            let partner = layer.transition.flatMap { transition in
                layers.first { $0.clip == transition.partner }
            }
            guard var uniforms = self.uniforms(for: layer, canvas: canvas, partner: partner)
            else { continue }
            let texture: MTLTexture
            switch source(for: layer, request: request, instruction: instruction, live: &live) {
            case .textured(let resolved, let size, let premultiplied, let orientation):
                texture = resolved
                uniforms.sourceWidth = Float(size.width)
                uniforms.sourceHeight = Float(size.height)
                uniforms.premultiplied = premultiplied ? 1 : 0
                uniforms.sourceQuarterTurns = Float(orientation & 3)
                uniforms.sourceMirrored = orientation & 4 != 0 ? 1 : 0
            case .slate(let size):
                texture = placeholder
                uniforms.sourceWidth = Float(size.width)
                uniforms.sourceHeight = Float(size.height)
                uniforms.slate = 1
            case .absent:
                // A composition track with no frame at this time: a gap, not
                // an error. Nothing to draw.
                continue
            }
            // A blur or a sharpen — a filter's, or an obscured region's —
            // needs the fragment stage compiled WITH the tap loop, which is a
            // whole second pipeline rather than a branch: the shader's
            // `kGatherFilters` has the measurement. Every other layer, which
            // is nearly all of them, keeps the pipeline the pass is already
            // carrying and changes no state at all. The predicate belongs to
            // the LAYER and not to its filter list, because a region that
            // blurs gathers exactly as a blur filter does — and both gather
            // sites in the shader are compiled out of the other pipeline, so
            // getting this wrong renders the region plain and silently.
            let state = layer.needsGather ? gatherPipeline : pipeline
            if let shadow = layer.shadow {
                encodeShadow(
                    shadow, uniforms: uniforms, texture: texture, canvas: canvas,
                    state: state, pass: &pass)
            }
            // Cheap when the pass is already open, which for an unshadowed
            // layer it always is: the encoder, the pipeline state and the
            // sampler are exactly the ones the previous layer left behind.
            guard let encoder = pass.open() else {
                throw CompositorError.noDestinationTexture
            }
            if state !== pipeline { encoder.setRenderPipelineState(state) }
            if layer.reflection != nil {
                encodeReflection(uniforms: uniforms, texture: texture, encoder: encoder)
            }
            encoder.setVertexBytes(
                &uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            // Back to the pass's own pipeline, so the next layer inherits the
            // state `DestinationPass.open()` promises.
            if state !== pipeline { encoder.setRenderPipelineState(pipeline) }
        }

        pass.suspend()
        buffer.commit()
        // The pixel buffer is handed to AVFoundation the moment this returns,
        // so the GPU must be finished with it. Waiting on the serial render
        // queue also paces submission: one frame in flight, no unbounded
        // queue growth when the GPU falls behind.
        buffer.waitUntilCompleted()
    }

    // MARK: - Sources

    private enum LayerSource {
        /// Texture, its source size in the layer's own space, whether it is
        /// premultiplied, and the source orientation code (0 for everything
        /// this app rasterized itself).
        case textured(MTLTexture, CGSize, premultiplied: Bool, orientation: Int)
        case slate(CGSize)
        case absent
    }

    private func source(
        for layer: RecipeLayer, request: AVAsynchronousVideoCompositionRequest,
        instruction: RecipeInstruction?, live: inout [CVMetalTexture]
    ) -> LayerSource {
        switch layer.source {
        case .track(let id):
            guard let buffer = request.sourceFrame(byTrackID: CMPersistentTrackID(id)),
                let texture = texture(from: buffer, live: &live)
            else {
                // No frame is a gap — unless the clip's FILE is gone, which
                // spec §5.6 draws as a slate. The core cannot see a
                // filesystem (`evaluate.rs`), so this is where the `missing`
                // source it would otherwise have emitted comes from.
                if instruction?.missingClips.contains(layer.clip) == true {
                    return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360))
                }
                return .absent
            }
            let orientation = instruction?.sourceOrientations[id] ?? 0
            // The recipe's `source_size` is the DISPLAY size, and the buffer
            // is the coded one: for a quarter-turned source the two are
            // transposed, and the fragment stage turns the sampling to match.
            let coded = CGSize(width: texture.width, height: texture.height)
            let size = layer.sourceSizeCG
                ?? (orientation & 1 != 0
                    ? CGSize(width: coded.height, height: coded.width) : coded)
            return .textured(texture, size, premultiplied: false, orientation: orientation)
        case .image(let media):
            guard let url = instruction?.mediaURLs[media],
                let rendered = renderers.image(url: url, media: media)
            else { return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360)) }
            return .textured(
                rendered.texture, rendered.size, premultiplied: true, orientation: 0)
        case .text(let hash, let props, let reveal):
            guard let rendered = renderers.text(props, hash: hash, reveal: reveal)
            else { return .absent }
            return .textured(
                rendered.texture, rendered.size, premultiplied: true, orientation: 0)
        case .shape(let hash, let props):
            guard let rendered = renderers.shape(props, hash: hash) else { return .absent }
            return .textured(
                rendered.texture, rendered.size, premultiplied: true, orientation: 0)
        case .missing:
            return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360))
        }
    }

    /// Wraps a pixel buffer as a texture through the `CVMetalTextureCache` —
    /// zero-copy, because both sides are the same IOSurface.
    private func texture(from buffer: CVPixelBuffer, live: inout [CVMetalTexture]) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        var wrapper: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm, width, height, 0,
            &wrapper)
        guard status == kCVReturnSuccess, let wrapper = wrapper,
            let texture = CVMetalTextureGetTexture(wrapper)
        else { return nil }
        live.append(wrapper)
        return texture
    }

    // MARK: - Shadows

    /// One layer's drop shadow, encoded BEFORE the layer's own pass (§7.5).
    /// Three steps:
    ///
    /// 1. the layer is drawn again, into the shared mask texture, with
    ///    `shadowMask = 1` — which makes the fragment stage return coverage
    ///    instead of colour. It is the SAME vertex and fragment pair, so the
    ///    silhouette matches the layer's placement, rotation, crop, corner
    ///    radius, chroma hole, transition weight and own opacity exactly, by
    ///    construction rather than by two pieces of code agreeing to — which
    ///    is also why a half-transparent layer casts a half-strength shadow;
    /// 2. `MPSImageGaussianBlur` blurs that mask into its pair;
    /// 3. a full-canvas quad samples the blurred pair, displaced by the
    ///    shadow's (distance, angle) and tinted with its colour, blended into
    ///    the destination with the same premultiplied source-over as any
    ///    layer. The caller then draws the layer itself on top.
    ///
    /// **Why the offscreen textures are CANVAS-sized and not layer-sized.**
    /// The mask comes out of the layer pipeline, whose vertex stage works in
    /// canvas coordinates: the anchor is the canvas centre plus the clip's
    /// (x, y), rotation turns about that anchor, and a push, slide or zoom
    /// transition offsets the quad by a fraction of the CANVAS. A layer-sized
    /// target would need every one of those restated in a second coordinate
    /// space — a duplicate of the vertex stage, which would silently disagree
    /// with the original the first time a transition moved a quad. It would
    /// also have to be padded by `distance + 3σ` on all four sides and
    /// re-padded for every layer, which is the per-layer allocation the 8 ms
    /// budget cannot pay for. One canvas-sized pair is allocated on the first
    /// shadowed frame and reused by every shadowed layer of every frame
    /// after. What the choice costs is coverage that falls outside the canvas,
    /// which is not in the mask: that only shows on a layer hanging off the
    /// edge, and the blur's `.clamp` edge mode is the closer of the two
    /// approximations available there.
    ///
    /// The pair is reused WITHIN a frame too. Two shadowed layers mean two
    /// mask passes into the same texture, which is safe because the passes of
    /// one command buffer execute in order and Metal inserts the
    /// write-after-read barrier for a device-allocated texture; the price is
    /// that two shadows cannot overlap on the GPU. That is the right trade at
    /// two or three shadows in a frame, and the reason to revisit it is
    /// thirty.
    private func encodeShadow(
        _ shadow: ShadowProps, uniforms: LayerUniforms, texture: MTLTexture,
        canvas: RecipeCanvas, state: MTLRenderPipelineState, pass: inout DestinationPass
    ) {
        func component(_ index: Int) -> Float {
            index < shadow.color.count ? Float(min(max(shadow.color[index], 0), 1))
                : (index == 3 ? 1 : 0)
        }
        // §5.2's Color is RGBA and the inspector's `opacity` is a separate
        // control, so a translucent shadow colour multiplies the two rather
        // than one of them silently winning.
        let opacity = Float(min(max(shadow.opacity, 0), 1)) * component(3)
        guard opacity > 0 else { return }

        // `blur` is a RADIUS in SOURCE pixels; MPS wants a standard deviation
        // in canvas pixels. Two conversions, both deliberate:
        //   · × the layer's scale, because every other length on this layer
        //     (the corner radius, the crop) is in source pixels, and a shadow
        //     that did not grow with its layer would look pasted on;
        //   · ÷ 2, the CSS `box-shadow` and Core Graphics convention — a
        //     Gaussian of σ = r/2 keeps essentially all of its weight inside
        //     ±r, so the shadow reaches about as far as the number says.
        let sigma = min(
            Float(max(shadow.blur, 0)) * uniforms.scale * 0.5, MetalRenderer.maxShadowSigma)
        guard
            let silhouette = shadowSilhouette(
                uniforms: uniforms, texture: texture, sigma: sigma, canvas: canvas,
                state: state, pass: &pass),
            let encoder = pass.open()
        else { return }

        var u = ShadowUniforms()
        u.canvasWidth = uniforms.canvasWidth
        u.canvasHeight = uniforms.canvasHeight
        // The model's angle is DEGREES, 0 pointing right and increasing
        // COUNTER-CLOCKWISE (`model.rs`), while the canvas is y-DOWN — so the
        // y term carries the minus sign that turns a counter-clockwise angle
        // into a y-down displacement. Checked against the default shadow:
        // 315° gives (+0.71, +0.71), which in this space is down-and-right,
        // which is what `Shadow::default` says it is.
        let radians = Float(shadow.angle) * .pi / 180
        // Distance is source pixels too, and scaled the same way — but NOT
        // rotated by the layer's rotation: the direction is a property of the
        // light, in canvas space, so every shadow in a frame falls the same
        // way however its layer is turned.
        let distance = Float(max(shadow.distance, 0)) * uniforms.scale
        u.offsetX = distance * cos(radians)
        u.offsetY = -distance * sin(radians)
        u.colorR = component(0)
        u.colorG = component(1)
        u.colorB = component(2)
        u.opacity = opacity

        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<ShadowUniforms>.stride, index: 0)
        encoder.setFragmentTexture(silhouette, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        // Back to the layer pipeline, so the caller's own draw needs no state
        // change of its own and an unshadowed layer costs what it always did.
        encoder.setRenderPipelineState(pipeline)
    }

    /// Steps 1 and 2 of `encodeShadow`: the coverage pass into the shared mask
    /// and the blur into its pair. Returns the texture the shadow draw should
    /// sample — the blurred one normally, the mask itself for a `blur: 0`
    /// shadow or a device MPS will not run on — or nil when the offscreen pair
    /// cannot be had, in which case the layer renders without a shadow rather
    /// than not at all.
    ///
    /// Leaves the destination pass SUSPENDED: neither a second render pass nor
    /// an MPS kernel can be encoded while a render encoder is open, which is
    /// the reason `DestinationPass` exists.
    private func shadowSilhouette(
        uniforms: LayerUniforms, texture: MTLTexture, sigma: Float, canvas: RecipeCanvas,
        state: MTLRenderPipelineState, pass: inout DestinationPass
    ) -> MTLTexture? {
        let width = max(1, canvas.width)
        let height = max(1, canvas.height)
        guard let surfaces = shadowPair(width: width, height: height) else { return nil }

        pass.suspend()
        var u = uniforms
        u.shadowMask = 1
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = surfaces.mask
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = pass.buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        // The layer's OWN specialization, so a blurred layer casts the
        // silhouette its blur actually leaves — the mask is only correct by
        // construction while it is the same fragment stage as the layer.
        encoder.setRenderPipelineState(state)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setVertexBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        guard sigma >= MetalRenderer.minShadowSigma, let blur = blurKernel(sigma: sigma) else {
            return surfaces.mask
        }
        blur.encode(
            commandBuffer: pass.buffer, sourceTexture: surfaces.mask,
            destinationTexture: surfaces.blurred)
        return surfaces.blurred
    }

    /// The shared offscreen pair at the canvas size, allocated on first use
    /// and whenever the canvas changes size. Both are allocated together: a
    /// shadow with no blur leaves the second one idle, which is the cheaper
    /// mistake to make.
    private func shadowPair(width: Int, height: Int) -> ShadowSurfaces? {
        if let surfaces = shadowSurfaces, surfaces.mask.width == width,
            surfaces.mask.height == height
        {
            return surfaces
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        // Rendered into, sampled by the shadow pass, and written by MPS (which
        // takes a compute path for some sigmas and a render path for others,
        // so both usages have to be there).
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        // GPU-only: nothing on the CPU ever reads a shadow mask.
        descriptor.storageMode = .private
        guard let mask = device.makeTexture(descriptor: descriptor),
            let blurred = device.makeTexture(descriptor: descriptor)
        else { return nil }
        mask.label = "Reelcut shadow mask"
        blurred.label = "Reelcut shadow blur"
        let surfaces = ShadowSurfaces(mask: mask, blurred: blurred)
        shadowSurfaces = surfaces
        return surfaces
    }

    private func blurKernel(sigma: Float) -> MPSImageGaussianBlur? {
        guard blurSupported else { return nil }
        let key = Int((sigma * 4).rounded())
        if let hit = blurKernels[key] { return hit }
        if blurKernels.count >= 16 { blurKernels.removeAll() }
        let kernel = MPSImageGaussianBlur(device: device, sigma: Float(key) / 4)
        // The mask is a canvas-sized WINDOW on a layer that may run past the
        // canvas edge, so the coverage just outside it is unknown rather than
        // absent. Clamping the edge assumes it continues, which is right for
        // the full-bleed layer that is the common case; `.zero` would fade
        // every such shadow out along the frame border.
        kernel.edgeMode = .clamp
        blurKernels[key] = kernel
        return kernel
    }

    // MARK: - Uniforms

    /// The per-layer block. Placement is §5.3's rule expressed in the shader's
    /// terms: the anchor is the canvas centre plus (x, y) — `canvasAnchor` in
    /// `ProjectSnapshot.swift` computes the same point for the overlay — and
    /// the crop is applied in place around it.
    private func uniforms(
        for layer: RecipeLayer, canvas: RecipeCanvas, partner: RecipeLayer? = nil
    ) -> LayerUniforms? {
        guard layer.opacity > 0 else { return nil }
        var u = LayerUniforms()
        u.canvasWidth = Float(max(1, canvas.width))
        u.canvasHeight = Float(max(1, canvas.height))
        u.anchorX = Float(Double(canvas.width) / 2 + layer.x)
        u.anchorY = Float(Double(canvas.height) / 2 + layer.y)
        u.scale = Float(max(layer.scale, 0.0001))
        u.rotation = Float(layer.rotation * .pi / 180)
        u.cropL = Float(max(0, layer.crop.l))
        u.cropT = Float(max(0, layer.crop.t))
        u.cropR = Float(max(0, layer.crop.r))
        u.cropB = Float(max(0, layer.crop.b))
        u.cornerRadius = Float(max(0, layer.cornerRadius))
        u.opacity = Float(min(max(layer.opacity, 0), 1))
        u.brightness = Float(layer.color.brightness)
        u.contrast = Float(layer.color.contrast)
        u.saturation = Float(layer.color.saturation)
        u.hue = Float(layer.color.hue * .pi / 180)
        if let chroma = layer.chroma {
            u.chromaEnabled = 1
            u.chromaKeyR = Float(chroma.key.count > 0 ? chroma.key[0] : 0)
            u.chromaKeyG = Float(chroma.key.count > 1 ? chroma.key[1] : 1)
            u.chromaKeyB = Float(chroma.key.count > 2 ? chroma.key[2] : 0)
            u.chromaTolerance = Float(max(0, chroma.tolerance))
            u.chromaSoftness = Float(max(0, chroma.softness))
            u.chromaSpill = Float(min(max(chroma.spill, 0), 1))
        }
        // The M3 effect block and the obscured regions after it, all in
        // `CompositorEffects.swift`.
        u.apply(filters: layer.filters)
        u.apply(reflection: layer.reflection)
        u.apply(spotlight: layer.spotlight)
        u.apply(clipRect: layer.clipRect)
        u.apply(obscure: layer.obscure)
        if let transition = layer.transition {
            u.transitionKind = TransitionCode.code(transition.kind)
            u.transitionProgress = Float(min(max(transition.progress, 0), 1))
            u.transitionIncoming = transition.isIncoming ? 1 : 0
            let direction = TransitionCode.direction(transition.kind)
            u.transitionDirX = direction.x
            u.transitionDirY = direction.y
            if !transition.isIncoming, let partner = partner,
                let box = MetalRenderer.partnerBox(
                    partner, canvas: canvas, progress: transition.progress)
            {
                u.partnerMinX = Float(box.minX)
                u.partnerMinY = Float(box.minY)
                u.partnerMaxX = Float(box.maxX)
                u.partnerMaxY = Float(box.maxY)
                u.partnerAlpha = Float(min(max(partner.opacity, 0), 1))
            }
        }
        return u
    }

    /// The incoming half of a dissolving pair, as the canvas-space box the
    /// shader tests a fragment against (see `partnerAlpha` in
    /// `LayerUniforms`).
    ///
    /// nil — "assume it covers nothing", the conservative reading — whenever
    /// the box would not be the honest answer: a rotated or corner-rounded
    /// partner is not an axis-aligned rectangle, and a partner whose source
    /// size only the text renderer knows has no box here at all. The
    /// correction is then simply not applied and that pixel keeps the old
    /// behaviour, which is right for a partner that does not cover it.
    /// A clipped partner is refused for the same reason a rounded one is: the
    /// nest rectangle cuts coverage the box would claim, and over-claiming is
    /// the one direction that shows — the outgoing layer would be brightened
    /// where nothing is coming in to darken it. A partner with a REFLECTION
    /// needs no such guard: a reflection only ever adds coverage below the
    /// box, so the box under-claims, which is the reading this function
    /// already returns nil to get.
    private static func partnerBox(
        _ partner: RecipeLayer, canvas: RecipeCanvas, progress: Double
    ) -> CGRect? {
        guard partner.rotation == 0, partner.cornerRadius == 0, partner.clipRect == nil,
            let size = partner.sourceSizeCG, size.width > 0, size.height > 0
        else { return nil }
        let anchor = CGPoint(
            x: Double(canvas.width) / 2 + partner.x, y: Double(canvas.height) / 2 + partner.y)
        var scale = partner.scale
        // A zoom transition scales the incoming layer in the VERTEX stage;
        // the box has to follow or it would claim cover the partner does not
        // have yet.
        if partner.transition?.kind == .zoom {
            scale *= 0.75 + 0.25 * min(max(progress, 0), 1)
        }
        let full = CGSize(width: size.width * scale, height: size.height * scale)
        let rect = CGRect(
            x: anchor.x - full.width / 2 + partner.crop.l * scale,
            y: anchor.y - full.height / 2 + partner.crop.t * scale,
            width: max(0, full.width - (partner.crop.l + partner.crop.r) * scale),
            height: max(0, full.height - (partner.crop.t + partner.crop.b) * scale))
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// The canvas background as a PREMULTIPLIED clear colour — the attachment
    /// holds premultiplied pixels, so a translucent background must be
    /// pre-scaled or the first layer blends against too much colour.
    private func clearColor(_ rgba: RGBA) -> MTLClearColor {
        func component(_ index: Int) -> Double {
            index < rgba.count ? min(max(rgba[index], 0), 1) : (index == 3 ? 1 : 0)
        }
        let alpha = component(3)
        return MTLClearColor(
            red: component(0) * alpha, green: component(1) * alpha, blue: component(2) * alpha,
            alpha: alpha)
    }
}
