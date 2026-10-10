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

    /// The render context's buffers: 16-bit float, so a blend or a deep
    /// source keeps more than 256 levels a channel (spec §11 PR-1). The
    /// working format of every target a layer pipeline draws into follows it
    /// (`MetalRenderer.workingFormat`), and the export reader reads it.
    static let outputPixelFormat: OSType = kCVPixelFormatType_64RGBAHalf
    /// What every video source is decoded to: 16-bit float, so a 10-bit source
    /// keeps its levels; the layer stage clamps its values (spec §11 PR-2).
    static let sourcePixelFormat: OSType = kCVPixelFormatType_64RGBAHalf

    /// Metal-compatible `sourcePixelFormat`, sampled through `texture(from:)`.
    /// AVFoundation converts anything else, and HDR still arrives tone-mapped
    /// to SDR (`supportsHDRSourceFrames` is not implemented, so false; §7.5).
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.sourcePixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

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
        // The key is the whole ask: `RecipeSource.recipe(for:at:)` reads the
        // project AND that key's `RecipeOptions` under one hold, so a burn-in
        // an export asked for arrives here without this file, the
        // instruction or `CompositionBuilder` carrying a flag of its own
        // (spec §7.3). Do not read the two halves separately.
        let recipe = RecipeSource.shared.recipe(
            for: instruction?.recipeKey ?? 0,
            at: CompositionBuilder.ticks(request.compositionTime))
        do {
            try renderer.render(
                recipe: recipe, into: destination, request: request, instruction: instruction)
            request.finish(withComposedVideoFrame: destination)
            WaveformTaps.shared.offer(destination, key: instruction?.recipeKey ?? 0)
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
struct DestinationPass {
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
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    /// The same layer fragment stage compiled WITH the two filters that
    /// gather neighbouring pixels — see `kGatherFilters` in the shader for the
    /// measurement that made this a second pipeline instead of a branch, and
    /// `Collection.needsGather` for which layers get it.
    private let gatherPipeline: MTLRenderPipelineState
    /// The two blend specializations (format version 6): the same two
    /// fragment stages compiled from `reelcut_layer_blend_fragment`, which
    /// reads the destination through `[[color(0)]]` and computes the
    /// combination itself. Built with `blending: false`, which is the whole
    /// correctness argument — see `pipelineDescriptor`.
    ///
    /// Seven pipelines, then, from five fragment functions: plain, plain +
    /// gather, blend, blend + gather, the shadow, the matte resolve
    /// (`Compositor+Matte.swift`) and the dissolve mix
    /// (`Compositor+Dissolve.swift`). `pipelineState(gather: blend:)` picks
    /// one of the first four per layer.
    private let blendPipeline: MTLRenderPipelineState
    private let blendGatherPipeline: MTLRenderPipelineState
    /// The full-canvas quad that draws one blurred mask as a shadow (§7.5).
    let shadowPipeline: MTLRenderPipelineState
    /// The matte resolve pass and the matte pass's targets (spec §11 MT-6,
    /// `Compositor+Matte.swift`).
    let matteResolvePipeline: MTLRenderPipelineState
    let mattePool: MattePool
    /// The routed dissolve's mix (spec §11 MT-8, `Compositor+Dissolve.swift`).
    let dissolvePipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    /// Bound wherever the shader ignores the texture (the missing-media
    /// slate), because a draw with no texture bound is undefined.
    let placeholder: MTLTexture
    private let renderers: LayerRenderers
    /// Whether this device can run `MPSImageGaussianBlur`. Every Mac the app
    /// supports can, but the check is free and a `false` here degrades to a
    /// hard-edged shadow instead of to a dropped frame.
    let blurSupported: Bool
    /// The one shared offscreen pair, sized to the canvas — see `encodeShadow`
    /// for why canvas-sized and why one pair. Nil until the first shadow is
    /// drawn, so a project without shadows allocates nothing, and replaced
    /// when the canvas size changes.
    var shadowSurfaces: ShadowSurfaces?
    /// `MPSImageGaussianBlur` bakes its sigma in at init, so a kernel built
    /// per frame would build a new one on every tick of the blur slider.
    /// Keyed by sigma quantized to a quarter pixel — finer than anyone can
    /// see — and emptied wholesale once it grows past a handful, which is all
    /// a dragged slider ever leaves behind.
    var blurKernels: [Int: MPSImageGaussianBlur] = [:]

    /// The sigma cap. The core only enforces `blur >= 0` (`props_check.rs`), so
    /// an agent is free to ask for 100 000, and MPS would take the GPU with
    /// it. The inspector's slider stops at 200 source pixels — σ = 100 at 1×
    /// — so the cap only bites on a layer scaled past 1× at maximum blur.
    static let maxShadowSigma: Float = 100
    /// Below this the Gaussian is narrower than a pixel: skip MPS entirely and
    /// let the shadow draw sample the unblurred mask, which is what a
    /// `blur: 0` shadow means anyway.
    static let minShadowSigma: Float = 0.5

    /// The Metal format a pixel buffer of `pixelFormat` is wrapped as: 32BGRA
    /// as `bgra8Unorm`, 64RGBAHalf as `rgba16Float`, anything else nil.
    static func metalFormat(for pixelFormat: OSType) -> MTLPixelFormat? {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA: return .bgra8Unorm
        case kCVPixelFormatType_64RGBAHalf: return .rgba16Float
        default: return nil
        }
    }

    /// The working format (spec §11 PR-1): the attachment of every layer,
    /// blend, shadow and dissolve pipeline, and so of every target they draw
    /// into — the destination, each matte composite and dissolve half, and
    /// the shadow pair. The coverage stays `r8Unorm`.
    static let workingFormat: MTLPixelFormat =
        metalFormat(for: Compositor.outputPixelFormat) ?? .bgra8Unorm

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
            let blendFunction = MetalRenderer.layerFragment(
                library, name: "reelcut_layer_blend_fragment", gather: false),
            let blendGatherFunction = MetalRenderer.layerFragment(
                library, name: "reelcut_layer_blend_fragment", gather: true),
            let shadowVertex = library.makeFunction(name: "reelcut_shadow_vertex"),
            let shadowFragment = library.makeFunction(name: "reelcut_shadow_fragment"),
            let resolveFragment = library.makeFunction(name: "reelcut_matte_resolve_fragment"),
            let dissolveFragment = library.makeFunction(name: "reelcut_dissolve_fragment")
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
            // Blending OFF on both blend states: the fragment stage returns
            // the finished pixel, and a fixed-function pass over it would
            // blend the frame twice. Metal accepts the pipeline either way and
            // says nothing — see `pipelineDescriptor`.
            let blendPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut layer, blending", vertex: vertexFunction,
                    fragment: blendFunction, blending: false)),
            let blendGatherPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut layer, blending and gathering", vertex: vertexFunction,
                    fragment: blendGatherFunction, blending: false)),
            let shadowPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut shadow", vertex: shadowVertex, fragment: shadowFragment)),
            let matteResolvePipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.matteResolveDescriptor(
                    vertex: shadowVertex, fragment: resolveFragment)),
            let dissolvePipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut dissolve", vertex: shadowVertex, fragment: dissolveFragment))
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
        self.blendPipeline = blendPipeline
        self.blendGatherPipeline = blendGatherPipeline
        self.shadowPipeline = shadowPipeline
        self.matteResolvePipeline = matteResolvePipeline
        self.mattePool = MattePool(device: device)
        self.dissolvePipeline = dissolvePipeline
        self.sampler = sampler
        self.textureCache = cache
        self.placeholder = placeholder
        self.renderers = LayerRenderers(device: device)
        self.blurSupported = MPSSupportsMTLDevice(device)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("MetalRenderer does not support NSCoder")
    }

    /// The compositor's FIXED-FUNCTION blend, in descriptor form: source-over
    /// on PREMULTIPLIED colour, so the source factor is one and not source
    /// alpha. The five layer and shadow pipelines and the dissolve mix come
    /// through here (the matte resolve has its own, `matteResolveDescriptor`)
    /// and four take it as written — a shadow is just another layer, drawn
    /// under its own, and the mix lays its premultiplied pair source-over.
    ///
    /// **`blending: false` is for a programmable-blend pipeline, and it is a
    /// correctness requirement rather than an optimisation.**
    /// `reelcut_layer_blend_fragment` reads the destination itself and returns
    /// the finished pixel, so leaving the fixed-function stage on would blend
    /// that finished pixel into the destination a SECOND time. Metal builds
    /// the pipeline either way — no error, no validation warning, no log —
    /// and at alpha 1 the double blend is invisible, because
    /// `oneMinusSourceAlpha` is 0 and the second pass is the identity. It only
    /// shows on a TRANSLUCENT blended layer. Nothing in the toolchain enforces
    /// this and no opaque test catches it, which is why the proof carries a
    /// partial-opacity check (B6) whose only job is to fail when this line is
    /// wrong.
    private static func pipelineDescriptor(
        label: String, vertex: MTLFunction, fragment: MTLFunction, blending: Bool = true
    ) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = workingFormat
        descriptor.colorAttachments[0].isBlendingEnabled = blending
        guard blending else { return descriptor }
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return descriptor
    }

    /// One of the four layer pipelines. Two independent specializations, so
    /// four states rather than a hierarchy: `gather` is a function constant
    /// (`kGatherFilters`, whose measurement is in the shader) and `blend`
    /// picks the entry point that reads the destination.
    func pipelineState(gather: Bool, blend: Bool) -> MTLRenderPipelineState {
        switch (gather, blend) {
        case (false, false): return pipeline
        case (true, false): return gatherPipeline
        case (false, true): return blendPipeline
        case (true, true): return blendGatherPipeline
        }
    }

    /// Drops the `CVMetalTexture`s wrapping the previous render context's
    /// pixel buffers.
    func flushPixelBufferTextures() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    /// Composes one frame: clear to the canvas background, then one pass per
    /// recipe layer back to front (`encodeLayers`) — plus, for a layer that
    /// has a shadow, the three passes `encodeShadow` puts in front of it, and
    /// for a routed dissolve its two halves and their mix (MT-8).
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
        mattePool.beginFrame(width: target.width, height: target.height)
        defer { mattePool.endFrame() }

        let canvas = recipe?.canvas ?? RecipeCanvas(
            width: target.width, height: target.height, background: [0, 0, 0, 1])
        guard let buffer = commandQueue.makeCommandBuffer() else {
            throw CompositorError.noDestinationTexture
        }
        // Every matte, before the destination pass opens (spec §11 MT-6).
        var coverage = MatteCoverage(placeholder: placeholder)
        if let recipe = recipe {
            coverage = try encodeMattes(
                recipe: recipe, canvas: canvas, target: target, buffer: buffer, request: request,
                instruction: instruction, live: &live)
        }
        let layers = recipe?.layers ?? []
        // A layer drawn into a matte is never drawn on the canvas (MT-1).
        let canvasLayers = layers.filter { $0.matte?.into == nil }
        // Each canvas layer's coverage, checked before the pass opens, so a
        // throw leaves no encoder open.
        guard canvasLayers.allSatisfy({ coverage.texture(for: $0) != nil }) else {
            throw MatteError.unordered
        }
        // One encoder for the whole frame, as before — but a shadowed layer
        // or a routed dissolve has to interrupt it, so the pass is a value
        // that can be suspended and resumed rather than one long-lived one.
        var pass = DestinationPass(
            buffer: buffer, target: target, clear: clearColor(canvas.background),
            pipeline: pipeline, sampler: sampler)
        // Opened eagerly: a recipe with no layers at all still has to CLEAR
        // the destination, which is a recycled pixel buffer holding an old
        // frame, not a blank one.
        guard pass.open() != nil else { throw CompositorError.noDestinationTexture }
        try encodeLayers(
            canvasLayers, depth: 0, among: layers, coverage: coverage, canvas: canvas,
            pass: &pass, request: request, instruction: instruction, live: &live)
        pass.suspend()
        buffer.commit()
        // The pixel buffer is handed to AVFoundation the moment this returns,
        // so the GPU must be finished with it. Waiting on the serial render
        // queue also paces submission: one frame in flight, no unbounded
        // queue growth when the GPU falls behind.
        buffer.waitUntilCompleted()
    }

    // MARK: - Sources

    enum LayerSource {
        /// Texture, its source size in the layer's own space, whether it is
        /// premultiplied, and the source orientation code (0 for everything
        /// this app rasterized itself).
        case textured(MTLTexture, CGSize, premultiplied: Bool, orientation: Int)
        case slate(CGSize)
        case absent
    }

    func source(
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
            return .textured(
                texture, size, premultiplied: Self.declaresPremultipliedAlpha(buffer),
                orientation: orientation)
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
        case .graphic(let name, _, let frame, let props, let ctx):
            let size = layer.sourceSizeCG ?? CGSize(width: 640, height: 360)
            guard let drawn = renderers.graphic(name: name, frame: frame, propsJSON: props,
                ctxJSON: ctx, size: size, recipeKey: instruction?.recipeKey ?? 0) else { return .slate(size) }
            return .textured(drawn.texture, drawn.size, premultiplied: true, orientation: 0)
        case .missing:
            return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360))
        }
    }

    /// Wraps a pixel buffer as a texture through the `CVMetalTextureCache` —
    /// zero-copy, because both sides are the same IOSurface — in the Metal
    /// format of the buffer's own pixel format; nil for one with none.
    private func texture(from buffer: CVPixelBuffer, live: inout [CVMetalTexture]) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0,
            let format = Self.metalFormat(for: CVPixelBufferGetPixelFormatType(buffer))
        else { return nil }
        var wrapper: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, format, width, height, 0,
            &wrapper)
        guard status == kCVReturnSuccess, let wrapper = wrapper,
            let texture = CVMetalTextureGetTexture(wrapper)
        else { return nil }
        live.append(wrapper)
        return texture
    }
}
