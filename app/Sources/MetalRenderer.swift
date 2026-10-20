import AVFoundation
import AppKit
import CoreVideo
import Metal
import MetalPerformanceShaders

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
    /// fragment stages compiled from `framejob_layer_blend_fragment`, which
    /// reads the destination through `[[color(0)]]` and computes the
    /// combination itself. Built with `blending: false`, which is the whole
    /// correctness argument — see `pipelineDescriptor`.
    ///
    /// Ten pipelines from eight fragment functions: plain, plain + gather,
    /// blend, blend + gather, the shadow, the matte resolve, the dissolve mix,
    /// the adjustment pass (`Compositor+Adjustment.swift`, spec §11 GR-6), the
    /// selection map (`Compositor+Selection.swift`, spec §11 GR-35) and the
    /// input pass (`Compositor+Input.swift`, spec §11 GR-15).
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
    let adjustPipeline: MTLRenderPipelineState
    /// The blurred qualifier's map pass (spec §11 GR-35, `Compositor+Selection.swift`).
    let qualifierMapPipeline: MTLRenderPipelineState
    let looks: LookTextures
    /// Step 0's pass, its targets and this frame's conversions (spec §11 GR-15).
    let inputs: InputStage
    /// An HLG project's lift of every layer Frame Job draws (spec §11 HD-13 (f)).
    private let lift: LayerLift
    let sampler: MTLSamplerState
    let textureCache: CVMetalTextureCache
    /// Bound where the shader ignores the texture (the slate): an unbound draw is undefined.
    let placeholder: MTLTexture
    let renderers: LayerRenderers
    /// Whether this device can run `MPSImageGaussianBlur`. Every Mac the app
    /// supports can, but the check is free and a `false` here degrades to a
    /// hard-edged shadow instead of to a dropped frame.
    let blurSupported: Bool
    /// The one shared offscreen pair, sized to the canvas — see `encodeShadow`
    /// for why canvas-sized and why one pair. Nil until the first shadow is
    /// drawn, so a project without shadows allocates nothing, and replaced
    /// when the canvas size changes.
    var shadowSurfaces: ShadowSurfaces?
    /// The blurred qualifier's map and its pair, sized to the destination —
    /// see `Compositor+Selection.swift`. Nil until the first blurred qualifier
    /// is drawn, and replaced when the destination's size changes.
    var qualifierSurfaces: QualifierSurfaces?
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
            let vertexFunction = library.makeFunction(name: "framejob_layer_vertex"),
            let fragmentFunction = MetalRenderer.layerFragment(library, gather: false),
            let gatherFunction = MetalRenderer.layerFragment(library, gather: true),
            let blendFunction = MetalRenderer.layerFragment(
                library, name: "framejob_layer_blend_fragment", gather: false),
            let blendGatherFunction = MetalRenderer.layerFragment(
                library, name: "framejob_layer_blend_fragment", gather: true),
            let shadowVertex = library.makeFunction(name: "framejob_shadow_vertex"),
            let shadowFragment = library.makeFunction(name: "framejob_shadow_fragment"),
            let resolveFragment = library.makeFunction(name: "framejob_matte_resolve_fragment"),
            let dissolveFragment = library.makeFunction(name: "framejob_dissolve_fragment")
        else { return nil }

        guard
            let pipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job layer", vertex: vertexFunction,
                    fragment: fragmentFunction)),
            let gatherPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job layer, gathering", vertex: vertexFunction,
                    fragment: gatherFunction)),
            // Blending OFF on both blend states: the fragment stage returns
            // the finished pixel, and a fixed-function pass over it would
            // blend the frame twice. Metal accepts the pipeline either way and
            // says nothing — see `pipelineDescriptor`.
            let blendPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job layer, blending", vertex: vertexFunction,
                    fragment: blendFunction, blending: false)),
            let blendGatherPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job layer, blending and gathering", vertex: vertexFunction,
                    fragment: blendGatherFunction, blending: false)),
            let shadowPipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job shadow", vertex: shadowVertex, fragment: shadowFragment)),
            let matteResolvePipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.matteResolveDescriptor(
                    vertex: shadowVertex, fragment: resolveFragment)),
            let dissolvePipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job dissolve", vertex: shadowVertex, fragment: dissolveFragment)),
            let adjustPipeline = MetalRenderer.adjustPipeline(device: device, library: library),
            let qualifierMapPipeline = MetalRenderer.qualifierMapPipeline(
                device: device, library: library),
            let looks = LookTextures(device: device, library: library),
            let inputs = InputStage(device: device, library: library),
            let lift = LayerLift(device: device, library: library)
        else { return nil }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        // Clamp: a crop window on the edge never wraps a row from the other side.
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        else { return nil }

        // Asked for both source and destination textures, so both usages.
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
        self.adjustPipeline = adjustPipeline
        self.qualifierMapPipeline = qualifierMapPipeline
        self.looks = looks
        self.inputs = inputs
        self.lift = lift
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
    /// alpha. Every pipeline but the matte resolve (`matteResolveDescriptor`)
    /// comes through here, and four take it as written — a shadow is just another
    /// layer, drawn under its own, and the mix lays its premultiplied pair source-over.
    ///
    /// **`blending: false` is for a programmable-blend pipeline, and it is a
    /// correctness requirement rather than an optimisation.**
    /// `framejob_layer_blend_fragment` reads the destination itself and returns
    /// the finished pixel, so leaving the fixed-function stage on would blend
    /// that finished pixel into the destination a SECOND time. Metal builds
    /// the pipeline either way — no error, no validation warning, no log —
    /// and at alpha 1 the double blend is invisible, because
    /// `oneMinusSourceAlpha` is 0 and the second pass is the identity. It only
    /// shows on a TRANSLUCENT blended layer. Nothing in the toolchain enforces
    /// this and no opaque test catches it, which is why the proof carries a
    /// partial-opacity check (B6) whose only job is to fail when this line is
    /// wrong.
    static func pipelineDescriptor(
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

    /// `texture`, a layer Frame Job drew, lifted into an HLG project's working
    /// space (`LayerLift`); nil when it could not be.
    func lifted(_ texture: MTLTexture) -> MTLTexture? {
        lift.lifted(texture, queue: commandQueue)
    }

    /// The canvas background as the frame is cleared to it: HD-3's lift of it
    /// in an HLG project (spec §11 HD-13 (f)), as it stands in an SDR one.
    private func background(_ canvas: RecipeCanvas) -> RGBA {
        let c = canvas.background
        guard canvas.output == .hlg, c.count >= 3 else { return c }
        let lifted = InputConversions.liftSDR(SIMD3<Float>(Float(c[0]), Float(c[1]), Float(c[2])))
        return [Double(lifted.x), Double(lifted.y), Double(lifted.z)] + c.dropFirst(3)
    }

    /// Drops the `CVMetalTexture`s wrapping the previous render context's pixel buffers.
    func flushPixelBufferTextures() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    /// Composes one frame: clear to the canvas background, then one pass per
    /// recipe layer back to front (`encodeLayers`) — plus, for a layer that
    /// has a shadow, the three passes `encodeShadow` puts in front of it, and
    /// for a routed dissolve its two halves and their mix (MT-8).
    func render(
        recipe: FrameRecipe?, into destination: CVPixelBuffer,
        request: AVAsynchronousVideoCompositionRequest, instruction: RecipeInstruction?,
        converts: Bool
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
        // Step 0, before anything samples a source; only in a converting
        // composition (spec §11 GR-15).
        inputs.beginFrame()
        defer { inputs.endFrame() }
        if converts, let recipe = recipe {
            try encodeInputs(
                layers: recipe.layers, request: request, buffer: buffer, live: &live,
                output: canvas.output)
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
            buffer: buffer, target: target, clear: clearColor(background(canvas)),
            pipeline: pipeline, sampler: sampler)
        // Opened eagerly: a recipe with no layers still has to CLEAR the
        // destination, a recycled pixel buffer holding an old frame.
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
}
