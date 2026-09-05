import AVFoundation
import AppKit
import CoreVideo
import Metal

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
/// fields at the END, in pairs, and mirror them in the shader in the same
/// order.
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
    /// Padding: keeps the block a multiple of 16 bytes. Spend these before
    /// growing the struct.
    var reserved0: Float = 0
    var reserved1: Float = 0
    var reserved2: Float = 0
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

// MARK: - The Metal side

/// Device, pipeline and caches for the compositor. Split out so `Compositor`
/// stays a protocol implementation and so a machine with no Metal device
/// degrades to "every frame finishes with an error" instead of trapping in
/// `init`.
final class MetalRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureCache: CVMetalTextureCache
    /// Bound wherever the shader ignores the texture (the missing-media
    /// slate), because a draw with no texture bound is undefined.
    private let placeholder: MTLTexture
    private let renderers: LayerRenderers

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
            let fragmentFunction = library.makeFunction(name: "reelcut_layer_fragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Reelcut layer"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Source-over on PREMULTIPLIED colour: the fragment stage always
        // outputs `rgb * a`, so the source factor is one, not source alpha.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
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
        self.sampler = sampler
        self.textureCache = cache
        self.placeholder = placeholder
        self.renderers = LayerRenderers(device: device)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("MetalRenderer does not support NSCoder")
    }

    /// Drops the `CVMetalTexture`s wrapping the previous render context's
    /// pixel buffers.
    func flushPixelBufferTextures() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    /// Composes one frame: clear to the canvas background, then one pass per
    /// recipe layer back to front.
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
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor(canvas.background)

        guard let buffer = commandQueue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { throw CompositorError.noDestinationTexture }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)

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
            encoder.setVertexBytes(
                &uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
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
        case .text(let hash, let props):
            guard let rendered = renderers.text(props, hash: hash) else { return .absent }
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
    private static func partnerBox(
        _ partner: RecipeLayer, canvas: RecipeCanvas, progress: Double
    ) -> CGRect? {
        guard partner.rotation == 0, partner.cornerRadius == 0,
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
