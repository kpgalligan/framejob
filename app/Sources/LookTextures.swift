import Foundation
import Metal

/// The look bake's split-tone block, mirroring `LookBakeUniforms` in
/// `Compositor.metal` FIELD FOR FIELD under `LayerUniforms`' layout contract —
/// four scalar floats, 16 bytes.
struct LookBakeUniforms {
    var shadowHue: Float = 0
    var shadowAmount: Float = 0
    var highlightHue: Float = 0
    var highlightAmount: Float = 0
}

/// Looks' lattices (spec §11 GR-7): each `LookDefinition` the recipe
/// publishes, baked once on the GPU into a 33³ `rgba16Float` 3D texture by
/// `reelcut_look_bake` — the identity lattice through the layer stage's own
/// colour adjust, tone and split tone — and kept in a least-recently-used
/// cache of eight, which a project's looks fit with room for a gallery's.
/// Step 4d samples the texture bound at `texture(2)`.
///
/// **The placeholder** is a 2³ identity lattice: bound on every draw whose
/// layer has no look, because a draw through a fragment that names
/// `texture(2)` must have one there, and an identity so that even a stray
/// sample would change nothing. A bake that fails answers it too, so a look
/// that cannot be baked draws ungraded rather than not at all.
///
/// Baking is synchronous on its own queue: the first frame that needs a new
/// definition waits for the bake (GR5a's record measures it), and every
/// later one reads the cache. The cache is guarded by one lock, because the
/// preview's and an export's compositors render on their own queues.
final class LookTextures {
    static let latticeSize = 33
    static let capacity = 8

    let placeholder: MTLTexture
    /// Imported LUTs' lattices (spec §11 GR-8), cached by file.
    let luts: LutTextures
    /// The curves' strips (spec §11 GR-12), cached by the curves: grade
    /// textures keyed by a definition, beside the looks'.
    let curves: CurveTextures
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let lock = NSLock()
    private var cache: [LookDefinition: MTLTexture] = [:]
    /// Least recently used first.
    private var order: [LookDefinition] = []

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let function = library.makeFunction(name: "reelcut_look_bake"),
            let pipeline = try? device.makeComputePipelineState(function: function),
            let queue = device.makeCommandQueue(),
            let placeholder = LookTextures.identity(device: device),
            let curves = CurveTextures(device: device)
        else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.placeholder = placeholder
        self.luts = LutTextures(device: device)
        self.curves = curves
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("LookTextures does not support NSCoder")
    }

    /// The lattice to bind for a layer's look: the cached bake of its
    /// definition, baked now on a miss; the placeholder for no look.
    func texture(for look: RecipeLook?) -> MTLTexture {
        guard let look = look, look.amount > 0 else { return placeholder }
        let key = look.definition
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return hit
        }
        // A failed bake caches the placeholder, so the frame after it does not
        // wait on the GPU again (the definition draws unchanged until evicted).
        let baked = bake(key) ?? placeholder
        cache[key] = baked
        order.append(key)
        while order.count > LookTextures.capacity {
            cache[order.removeFirst()] = nil
        }
        return baked
    }

    /// The lattice to bind for a layer's look, built-in or LUT; nil when
    /// there is no look (or its amount is 0) or when a LUT look cannot be
    /// drawn — its media has no file in `urls` (missing), or the file is
    /// refused or unreadable — which draws the layer ungraded (GR-8 choice
    /// 5). `urls` is `RecipeSource.lookURLs(for:)`'s answer.
    func lattice(for look: RecipeLook?, urls: [UInt32: URL]) -> MTLTexture? {
        guard let look = look, look.amount > 0 else { return nil }
        guard let media = look.media else { return texture(for: look) }
        return urls[media].flatMap { luts.texture(at: $0) }
    }

    /// One definition baked into a `size`³ lattice, or nil when the GPU
    /// could not. Waits for the GPU.
    func bake(_ definition: LookDefinition, size: Int = latticeSize) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard size >= 2, let lattice = device.makeTexture(descriptor: descriptor),
            let buffer = queue.makeCommandBuffer(),
            let encoder = buffer.makeComputeCommandEncoder()
        else { return nil }
        lattice.label = "Reelcut look"
        var u = LookTextures.uniforms(definition.color)
        var b = LookBakeUniforms(
            shadowHue: Float(definition.split.shadowHue),
            shadowAmount: Float(definition.split.shadowAmount),
            highlightHue: Float(definition.split.highlightHue),
            highlightAmount: Float(definition.split.highlightAmount))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(lattice, index: 0)
        encoder.setBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setBytes(&b, length: MemoryLayout<LookBakeUniforms>.stride, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: size, height: size, depth: size),
            threadsPerThreadgroup: MTLSize(width: 4, height: 4, depth: 4))
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        return buffer.status == .completed ? lattice : nil
    }

    /// The definition's colour as the layer block the bake reads: Color's
    /// four (hue in radians, as `uniforms(for:)` writes it) and tone's nine
    /// with `toneEnabled`; everything else neutral, the chroma key off.
    static func uniforms(_ color: ColorAdjust) -> LayerUniforms {
        var u = LayerUniforms()
        u.brightness = Float(color.brightness)
        u.contrast = Float(color.contrast)
        u.saturation = Float(color.saturation)
        u.hue = Float(color.hue * .pi / 180)
        u.apply(tone: color)
        return u
    }

    /// The 2³ identity lattice: texel (r, g, b) holds (r, g, b, 1), each 0 or
    /// 1, written from the CPU as half floats (0x0000 and 0x3C00).
    private static func identity(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba16Float
        descriptor.width = 2
        descriptor.height = 2
        descriptor.depth = 2
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let one: UInt16 = 0x3C00
        var texels: [UInt16] = []
        for b in 0..<2 {
            for g in 0..<2 {
                for r in 0..<2 {
                    texels += [r == 1 ? one : 0, g == 1 ? one : 0, b == 1 ? one : 0, one]
                }
            }
        }
        let written: Bool = texels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, 2, 2, 2), mipmapLevel: 0, slice: 0,
                withBytes: base, bytesPerRow: 16, bytesPerImage: 32)
            return true
        }
        guard written else { return nil }
        texture.label = "Reelcut look placeholder"
        return texture
    }
}
