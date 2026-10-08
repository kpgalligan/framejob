import AVFoundation
import CoreVideo
import Metal

/// The matte pass (spec §11 MT-3, MT-6): every matte the recipe lists drawn
/// into a destination-sized target BEFORE the destination pass opens, and
/// each distinct set of mattes a layer is cut by resolved into one
/// destination-sized `r8Unorm` coverage, which the layer stage samples at
/// `texture(1)`. Split out of `Compositor.swift` for size, as
/// `Compositor+Shadow.swift` was; `render` calls `encodeMattes` once per
/// frame and reads its answer per layer.
///
/// A matte never suspends the destination pass, the way a shadow does: it is
/// all encoded before that pass opens, deepest container first (the order
/// the recipe lists them in), so a layer drawn into an outer matte can
/// already be cut by an inner one.

/// The matte resolve pass's uniform block, mirroring `MatteUniforms` in
/// `Compositor.metal` FIELD FOR FIELD under `LayerUniforms`' layout
/// contract: scalars only, a multiple of 16 bytes.
struct MatteUniforms {
    /// A `TrackMatte.shaderCode`.
    var mode: Float = 0
    var reserved0: Float = 0
    var reserved1: Float = 0
    var reserved2: Float = 0
}

/// Why a matted frame could not be composed.
enum MatteError: LocalizedError {
    case noTarget
    /// A layer is cut by a matte that is not drawn before it is needed. A
    /// recipe from the core never says so — the list is deepest container
    /// first and a matte track is nobody's target (MT-2) — so it fails the
    /// frame rather than draw a picture the recipe did not describe.
    case unordered

    var errorDescription: String? {
        switch self {
        case .noTarget: return "A matte's offscreen target could not be made."
        case .unordered: return "A layer is cut by a matte that is not drawn before it."
        }
    }
}

/// The destination-sized targets the matte pass draws into, kept from frame
/// to frame (MT-6): a project with no matte allocates nothing, and the first
/// matted frame allocates what it needs — at 3840×2160, 33.2 MB per matte
/// composite and 8.3 MB per coverage. Emptied when the destination size
/// changes; it grows with the most mattes one frame has needed, and no cap
/// is set. One renderer serves one serial render queue and waits for each
/// frame's GPU work, so a target is free again by the next frame.
final class MattePool {
    private let device: MTLDevice
    private var width = 0
    private var height = 0
    private var composites: [MTLTexture] = []
    private var coverages: [MTLTexture] = []

    init(device: MTLDevice) {
        self.device = device
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("MattePool does not support NSCoder")
    }

    /// Makes the pool's targets `width` × `height`, dropping any of another
    /// size.
    func fit(width: Int, height: Int) {
        guard width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        composites = []
        coverages = []
    }

    /// The `index`th matte composite target, premultiplied BGRA.
    func composite(_ index: Int) -> MTLTexture? {
        target(index, in: &composites, format: .bgra8Unorm)
    }

    /// The `index`th coverage target, one channel.
    func coverage(_ index: Int) -> MTLTexture? {
        target(index, in: &coverages, format: .r8Unorm)
    }

    private func target(
        _ index: Int, in list: inout [MTLTexture], format: MTLPixelFormat
    ) -> MTLTexture? {
        while list.count <= index {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: max(1, width), height: max(1, height),
                mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let made = device.makeTexture(descriptor: descriptor) else { return nil }
            list.append(made)
        }
        return list[index]
    }
}

/// What the matte pass answers: the coverage each layer's fragment stage
/// samples at `texture(1)`.
struct MatteCoverage {
    let placeholder: MTLTexture
    fileprivate(set) var byCut: [[Int]: MTLTexture] = [:]

    init(placeholder: MTLTexture) {
        self.placeholder = placeholder
    }

    /// The layer's coverage: the 1×1 white placeholder for a layer no matte
    /// cuts (MT0's route), the resolved product for one that is cut, and nil
    /// only for a cut set the pass did not resolve — which a recipe from the
    /// core never asks for, and `render` fails the frame on (`unordered`).
    func texture(for layer: RecipeLayer) -> MTLTexture? {
        guard let cut = layer.matte?.cut, !cut.isEmpty else { return placeholder }
        return byCut[cut]
    }
}

extension MetalRenderer {

    /// The resolve pipeline: the shadow pass's full-frame quad and
    /// `reelcut_matte_resolve_fragment`, into `r8Unorm`, with source factor
    /// ZERO and destination factor `sourceColor` — the coverage is cleared
    /// to 1 and each matte's value multiplies into it.
    static func matteResolveDescriptor(
        vertex: MTLFunction, fragment: MTLFunction
    ) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Reelcut matte resolve"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .r8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .zero
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .zero
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .sourceColor
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .sourceColor
        return descriptor
    }

    /// Encodes every matte `recipe.mattes` lists into `buffer`, ahead of the
    /// destination pass, and resolves the coverage of every layer that a
    /// matte cuts. A layer whose `into` names a group is drawn into that
    /// group's composite with the ordinary layer pipelines, so every one of
    /// its own properties shapes the matte (MT-4); it is never drawn on the
    /// canvas, which `render` decides.
    func encodeMattes(
        recipe: FrameRecipe, canvas: RecipeCanvas, target: MTLTexture,
        buffer: MTLCommandBuffer, request: AVAsynchronousVideoCompositionRequest,
        instruction: RecipeInstruction?, live: inout [CVMetalTexture]
    ) throws -> MatteCoverage {
        var coverage = MatteCoverage(placeholder: placeholder)
        guard !recipe.mattes.isEmpty else { return coverage }
        mattePool.fit(width: target.width, height: target.height)
        let destination = CGSize(width: target.width, height: target.height)
        var composites: [Int: (texture: MTLTexture, mode: TrackMatte)] = [:]

        for (index, group) in recipe.mattes.enumerated() {
            let members = recipe.layers.filter { $0.matte?.into == group.group }
            // An inner matte cutting a member is drawn already: the list is
            // deepest container first.
            for member in members {
                try resolve(member.matte?.cut ?? [], composites, into: &coverage, buffer)
            }
            // Each member's coverage, resolved above, read before the pass
            // opens: a throw never leaves an encoder open.
            let cuts: [MTLTexture] = try members.map {
                guard let matte = coverage.texture(for: $0) else { throw MatteError.unordered }
                return matte
            }
            guard let composite = mattePool.composite(index) else { throw MatteError.noTarget }
            // A pass of its own, cleared transparent, drawn exactly as the
            // destination pass draws a layer — a shadow suspends it the same
            // way — so nothing on this side has an opinion about a matte
            // layer's blend, shadow or reflection: the core cleared them.
            var pass = DestinationPass(
                buffer: buffer, target: composite,
                clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                pipeline: pipeline, sampler: sampler)
            guard pass.open() != nil else { throw MatteError.noTarget }
            for (member, matte) in zip(members, cuts) {
                guard
                    let prepared = prepare(
                        member, among: recipe.layers, canvas: canvas, destination: destination,
                        request: request, instruction: instruction, live: &live)
                else { continue }
                try draw(member, prepared, matte: matte, canvas: canvas, pass: &pass)
            }
            pass.suspend()
            composites[group.group] = (composite, group.mode)
        }

        // The canvas layers' cut sets, now every matte is drawn.
        for layer in recipe.layers where layer.matte?.into == nil {
            try resolve(layer.matte?.cut ?? [], composites, into: &coverage, buffer)
        }
        return coverage
    }

    /// One layer drawn into a matte's composite, in the steps `render` draws
    /// a layer on the canvas with: its shadow, then its reflection and
    /// itself, `texture(1)` bound to the mattes cutting it.
    private func draw(
        _ layer: RecipeLayer, _ prepared: PreparedLayer, matte: MTLTexture,
        canvas: RecipeCanvas, pass: inout DestinationPass
    ) throws {
        var uniforms = prepared.uniforms
        let state = pipelineState(gather: layer.needsGather, blend: layer.needsBlend)
        if let shadow = layer.shadow {
            encodeShadow(
                shadow, uniforms: uniforms, texture: prepared.texture, matte: matte,
                canvas: canvas, maskState: pipelineState(gather: layer.needsGather, blend: false),
                pass: &pass)
        }
        guard let encoder = pass.open() else { throw MatteError.noTarget }
        if state !== pipeline { encoder.setRenderPipelineState(state) }
        encoder.setFragmentTexture(matte, index: 1)
        if layer.reflection != nil {
            encodeReflection(uniforms: uniforms, texture: prepared.texture, encoder: encoder)
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(prepared.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        if state !== pipeline { encoder.setRenderPipelineState(pipeline) }
    }

    /// One cut set's coverage, resolved once per frame: a pass cleared to 1
    /// with each matte's mode multiplied in. An empty set is the placeholder
    /// and encodes nothing.
    private func resolve(
        _ cut: [Int], _ composites: [Int: (texture: MTLTexture, mode: TrackMatte)],
        into coverage: inout MatteCoverage, _ buffer: MTLCommandBuffer
    ) throws {
        guard !cut.isEmpty, coverage.byCut[cut] == nil else { return }
        // Every matte in the set is drawn already, checked before the pass
        // opens so that a throw never leaves an encoder open.
        let mattes: [(texture: MTLTexture, mode: TrackMatte)] = try cut.map {
            guard let matte = composites[$0] else { throw MatteError.unordered }
            return matte
        }
        guard let texture = mattePool.coverage(coverage.byCut.count) else {
            throw MatteError.noTarget
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 1, green: 1, blue: 1, alpha: 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw MatteError.noTarget
        }
        encoder.setRenderPipelineState(matteResolvePipeline)
        for matte in mattes {
            var u = MatteUniforms()
            u.mode = matte.mode.shaderCode
            encoder.setFragmentBytes(&u, length: MemoryLayout<MatteUniforms>.stride, index: 0)
            encoder.setFragmentTexture(matte.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        coverage.byCut[cut] = texture
    }
}
