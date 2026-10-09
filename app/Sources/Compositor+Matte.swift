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

/// The destination-sized targets the matte pass draws into (spec §11 MT-6,
/// MT-9): at 3840×2160, 33.2 MB per matte composite and 8.3 MB per coverage.
/// A frame is one `render` call, bracketed by `beginFrame` and `endFrame`.
/// Within it a composite is taken and given back as `MattePlan` says, so a
/// later matte draws into one an earlier matte no longer needs; a coverage is
/// the `index`th cut set's and outlives the destination pass. Between frames
/// the pool keeps, of each kind, the most any of the last `keepFrames` frames
/// held at once, and releases the rest when a frame ends. A frame that needs
/// more targets gets them. A routed dissolve's two halves take composites
/// from the same pool (MT-8, `Compositor+Dissolve.swift`). Emptied when the
/// destination size changes. One
/// renderer serves one serial render queue and waits for each frame's GPU
/// work, so every target is free again by the next frame.
final class MattePool {
    /// How many frames, the current one included, the pool's size answers to.
    static let keepFrames = 30

    private let device: MTLDevice
    private var width = 0
    private var height = 0
    private var composites: [MTLTexture] = []
    /// Per composite, whether this frame holds it.
    private var taken: [Bool] = []
    private var coverages: [MTLTexture] = []
    /// What this frame has held at once: composites, coverages.
    private var peak = (composites: 0, coverages: 0)
    /// `peak` of each of the last `keepFrames` frames, oldest first.
    private var recent: [(composites: Int, coverages: Int)] = []

    init(device: MTLDevice) {
        self.device = device
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("MattePool does not support NSCoder")
    }

    /// Starts a frame `width` × `height`: a size change drops every target,
    /// and every composite is free.
    func beginFrame(width: Int, height: Int) {
        if width != self.width || height != self.height {
            self.width = width
            self.height = height
            composites = []
            coverages = []
        }
        taken = Array(repeating: false, count: composites.count)
        peak = (0, 0)
    }

    /// A free composite target, premultiplied BGRA: the lowest free index,
    /// made when none is free. Nil only when Metal cannot make one.
    func takeComposite() -> MTLTexture? {
        let index: Int
        if let free = taken.firstIndex(of: false) {
            index = free
        } else {
            guard let made = makeTarget(format: .bgra8Unorm) else { return nil }
            composites.append(made)
            taken.append(false)
            index = composites.count - 1
        }
        taken[index] = true
        peak.composites = max(peak.composites, taken.filter { $0 }.count)
        return composites[index]
    }

    /// Gives `texture` back to this frame's free composites.
    func giveComposite(_ texture: MTLTexture) {
        guard let index = composites.firstIndex(where: { $0 === texture }) else { return }
        taken[index] = false
    }

    /// The `index`th coverage target, one channel.
    func coverage(_ index: Int) -> MTLTexture? {
        while coverages.count <= index {
            guard let made = makeTarget(format: .r8Unorm) else { return nil }
            coverages.append(made)
        }
        peak.coverages = max(peak.coverages, index + 1)
        return coverages[index]
    }

    /// Ends the frame: keeps, of each kind, the most any of the last
    /// `keepFrames` frames held, and releases the targets past it.
    func endFrame() {
        recent.append(peak)
        let window = MattePool.keepFrames
        if recent.count > window { recent.removeFirst(recent.count - window) }
        trim(&composites, to: recent.map(\.composites).max() ?? 0)
        trim(&coverages, to: recent.map(\.coverages).max() ?? 0)
        taken = Array(repeating: false, count: composites.count)
        peak = (0, 0)
    }

    /// The targets the pool holds now: composites, coverages.
    var held: (composites: Int, coverages: Int) {
        (composites.count, coverages.count)
    }

    private func trim(_ list: inout [MTLTexture], to count: Int) {
        if list.count > count { list.removeLast(list.count - count) }
    }

    private func makeTarget(format: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: max(1, width), height: max(1, height),
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
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
    /// matte cuts, in the order `MattePlan` gives (spec §11 MT-9). A layer
    /// whose `into` names a group is drawn into that group's composite with
    /// the ordinary layer pipelines, so every one of its own properties
    /// shapes the matte (MT-4); it is never drawn on the canvas, which
    /// `render` decides. A cut set the plan never resolves stays nil, and
    /// `render` fails the frame on it (`unordered`).
    func encodeMattes(
        recipe: FrameRecipe, canvas: RecipeCanvas, target: MTLTexture,
        buffer: MTLCommandBuffer, request: AVAsynchronousVideoCompositionRequest,
        instruction: RecipeInstruction?, live: inout [CVMetalTexture]
    ) throws -> MatteCoverage {
        var coverage = MatteCoverage(placeholder: placeholder)
        guard !recipe.mattes.isEmpty else { return coverage }
        let plan = MattePlan(
            groups: recipe.mattes.map(\.group),
            cuts: recipe.layers.compactMap { layer in
                guard let cut = layer.matte?.cut, !cut.isEmpty else { return nil }
                return cut
            })
        var composites: [Int: (texture: MTLTexture, mode: TrackMatte)] = [:]

        for (group, step) in zip(recipe.mattes, plan.steps) {
            let members = recipe.layers.filter { $0.matte?.into == step.group }
            // Each member's coverage, resolved at an earlier step — the list
            // is deepest container first — and checked before the pass opens:
            // a throw never leaves an encoder open.
            guard members.allSatisfy({ coverage.texture(for: $0) != nil }) else {
                throw MatteError.unordered
            }
            guard let composite = mattePool.takeComposite() else { throw MatteError.noTarget }
            // A pass of its own, cleared transparent, drawn exactly as the
            // destination pass draws its layers (`encodeLayers`) — a shadow
            // suspends it the same way, and a routed dissolve among the
            // members is two halves mixed here (MT-8) — so nothing on this
            // side has an opinion about a matte layer's blend, shadow or
            // reflection: the core cleared them.
            var pass = DestinationPass(
                buffer: buffer, target: composite,
                clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                pipeline: pipeline, sampler: sampler)
            guard pass.open() != nil else { throw MatteError.noTarget }
            try encodeLayers(
                members, depth: 0, among: recipe.layers, coverage: coverage, canvas: canvas,
                pass: &pass, request: request, instruction: instruction, live: &live)
            pass.suspend()
            composites[step.group] = (composite, group.mode)
            for cut in step.resolve {
                try resolve(cut, composites, into: &coverage, buffer)
            }
            // A composite no later resolve reads goes back to the pool, so the
            // next step may draw into it; Metal orders that clear after the
            // resolves above, which read it, in this one command buffer.
            for released in step.release {
                if let given = composites.removeValue(forKey: released) {
                    mattePool.giveComposite(given.texture)
                }
            }
        }
        return coverage
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
