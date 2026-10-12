import AVFoundation
import CoreVideo
import Metal
import simd

/// The compositor a composition holding an HLG, PQ or wide-gamut source is
/// built with (`CompositionBuilder.convertsSources`, spec §11 GR-15 as
/// amended after T3-1's H1 stop). It answers AVFoundation's two colour
/// properties true, so every source frame arrives native and honestly
/// labelled on every path, and runs step 0 (`encodeInputs`); its composition
/// is BT.709, so a frame it composes is labelled for what it holds. Every
/// other composition keeps `Compositor`, which answers both false, so an
/// SDR-only project keeps today's pixels and labels by construction. No
/// stored property and no initializer: AVFoundation instantiates the class.
final class ConvertingCompositor: Compositor {
    override var canConformColorOfSourceFrames: Bool { true }
    override var supportsHDRSourceFrames: Bool { true }
}

/// Step 0, the input pass (spec §11 GR-15): a per-source pass BEFORE the
/// layer stage that converts a source frame once per frame into a pooled
/// `rgba16Float` target, which every draw of that track then samples in
/// place of the frame's own texture (`source(for:…)`, `Compositor+Sources
/// .swift`). It runs only for a frame whose labels `InputConversion.choose`
/// answers non-nil — HLG, PQ, an SDR transfer with BT.2020 or P3 D65
/// primaries, or the sRGB transfer — and only in a `ConvertingCompositor`;
/// every other source is sampled exactly as before.
///
/// Why a pass and not arithmetic inside the sample: a conversion in a
/// 25-tap blur would run once per tap (+3.06 ms at 4K, the tier-3 brief),
/// the pass once per pixel. It runs before `encodeMattes`, so a matte
/// member, a canvas layer, a shadow's silhouette and a dissolve's half all
/// sample the converted texture, and the chroma key, Color's four and the
/// grade (steps 3–4d) see converted values.
///
/// The pass is the shadow pass's full-frame quad (`reelcut_shadow_vertex`)
/// and `reelcut_input_fragment`, which READS the source texel at its own
/// pixel (the target is the frame's coded size), blending off.

/// The input pass's uniform block, mirrored FIELD FOR FIELD by
/// `InputUniforms` in `Compositor.metal` under `LayerUniforms`' layout
/// contract: scalars only, a multiple of 16 bytes (24 floats, 96 bytes).
struct InputUniforms {
    /// 1 HLG, 2 PQ, 3 wide-gamut SDR, 4 sRGB (`kInputHLG`… in the shader).
    var kind: Float = 0
    var premultiplied: Float = 0
    var systemGamma: Float = 0
    var hlgGain: Float = 0
    var knee: Float = 0
    var white: Float = 0
    /// PQ's cd/m² over the reference white: 10000/203.
    var nitsScale: Float = 0
    /// The encode: 1/2.4, or 256/502 for an sRGB source (Core Media's
    /// BT.709 profile).
    var encodePower: Float = 0
    /// 2.4, a wide-gamut SDR source's decode.
    var decodePower: Float = 0
    var reserved0: Float = 0
    var reserved1: Float = 0
    var reserved2: Float = 0
    /// Source → BT.709, row-major.
    var m00: Float = 1, m01: Float = 0, m02: Float = 0
    var m10: Float = 0, m11: Float = 1, m12: Float = 0
    var m20: Float = 0, m21: Float = 0, m22: Float = 1
    var reserved3: Float = 0
    var reserved4: Float = 0
    var reserved5: Float = 0

    static let hlg: Float = 1, pq: Float = 2, sdrWide: Float = 3, srgb: Float = 4

    /// Writes `matrix` (simd, column-major) into the row-major fields.
    mutating func setMatrix(_ matrix: simd_float3x3) {
        m00 = matrix[0][0]; m01 = matrix[1][0]; m02 = matrix[2][0]
        m10 = matrix[0][1]; m11 = matrix[1][1]; m12 = matrix[2][1]
        m20 = matrix[0][2]; m21 = matrix[1][2]; m22 = matrix[2][2]
    }
}

/// Why a frame with a converted source could not be composed.
enum InputError: LocalizedError {
    case noTarget

    var errorDescription: String? {
        "A converted source's target could not be made or drawn."
    }
}

/// The input pass's pipeline, its targets and this frame's conversions.
///
/// The pool is `MattePool`'s policy per size: targets are keyed by their
/// size (a source's coded size, which differs between sources), every
/// target is free at the start of a frame, and at its end the pool keeps,
/// for each size, the most any of the last `keepFrames` frames held. A
/// frame is one `render` call; `render` waits for its command buffer, so a
/// target is never reused while the GPU still reads it.
final class InputStage {
    static let keepFrames = MattePool.keepFrames

    private struct Size: Hashable {
        let width: Int
        let height: Int
    }

    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private var targets: [Size: [MTLTexture]] = [:]
    /// How many of each size's targets this frame holds (the first n).
    private var taken: [Size: Int] = [:]
    /// `taken` of each of the last `keepFrames` frames, oldest first.
    private var recent: [[Size: Int]] = []
    /// This frame's converted sources, by composition track id.
    private var byTrack: [Int: MTLTexture] = [:]
    private var passes = 0

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let vertex = library.makeFunction(name: "reelcut_shadow_vertex"),
            let fragment = library.makeFunction(name: "reelcut_input_fragment"),
            let pipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Reelcut input", vertex: vertex, fragment: fragment,
                    blending: false))
        else { return nil }
        self.device = device
        self.pipeline = pipeline
    }

    /// Starts a frame: every target free, no source converted.
    func beginFrame() {
        taken = [:]
        byTrack = [:]
    }

    /// Ends the frame: keeps, per size, the most any of the last
    /// `keepFrames` frames held, and releases the rest.
    func endFrame() {
        recent.append(taken)
        if recent.count > Self.keepFrames { recent.removeFirst(recent.count - Self.keepFrames) }
        for size in Array(targets.keys) {
            let keep = recent.map { $0[size] ?? 0 }.max() ?? 0
            if keep == 0 {
                targets[size] = nil
            } else if let held = targets[size], held.count > keep {
                targets[size] = Array(held.prefix(keep))
            }
        }
        taken = [:]
        byTrack = [:]
    }

    /// The converted texture of composition track `trackID` this frame, or
    /// nil when its source was not converted.
    func converted(trackID: Int) -> MTLTexture? {
        byTrack[trackID]
    }

    /// A free `rgba16Float` target `width` × `height`, made when none is free;
    /// nil only when Metal cannot make one.
    func target(width: Int, height: Int) -> MTLTexture? {
        let size = Size(width: width, height: height)
        let index = taken[size] ?? 0
        var held = targets[size] ?? []
        if index >= held.count {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: MetalRenderer.workingFormat, width: max(1, width),
                height: max(1, height), mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let made = device.makeTexture(descriptor: descriptor) else { return nil }
            held.append(made)
            targets[size] = held
        }
        taken[size] = index + 1
        return held[index]
    }

    /// Records `texture` as track `trackID`'s source for the rest of the frame.
    func record(_ texture: MTLTexture, trackID: Int) {
        byTrack[trackID] = texture
    }

    /// One conversion of `source` into `target`, encoded on `buffer`; false
    /// when no encoder could be made.
    func encode(
        _ conversion: InputConversion, premultiplied: Bool, from source: MTLTexture,
        into target: MTLTexture, buffer: MTLCommandBuffer
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.label = "Reelcut input"
        encoder.setRenderPipelineState(pipeline)
        var u = conversion.uniforms(premultiplied: premultiplied)
        encoder.setFragmentBytes(&u, length: MemoryLayout<InputUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        passes += 1
        return true
    }

    /// The passes encoded since the last call (the timing log's count).
    func takePassCount() -> Int {
        defer { passes = 0 }
        return passes
    }
}

extension MetalRenderer {
    /// Step 0 for one frame: each distinct composition track the recipe's
    /// layers draw from whose frame needs a conversion is converted once,
    /// before any matte or layer is drawn; `source(for:…)` then hands the
    /// converted texture to every draw of that track.
    func encodeInputs(
        layers: [RecipeLayer], request: AVAsynchronousVideoCompositionRequest,
        buffer: MTLCommandBuffer, live: inout [CVMetalTexture]
    ) throws {
        var seen = Set<Int>()
        for layer in layers {
            guard case .track(let id) = layer.source, seen.insert(id).inserted,
                let frame = request.sourceFrame(byTrackID: CMPersistentTrackID(id))
            else { continue }
            guard let conversion = InputConversion.choose(for: frame) else { continue }
            guard let source = texture(from: frame, live: &live) else { continue }
            guard let target = inputs.target(width: source.width, height: source.height),
                inputs.encode(
                    conversion, premultiplied: Self.declaresPremultipliedAlpha(frame),
                    from: source, into: target, buffer: buffer)
            else { throw InputError.noTarget }
            inputs.record(target, trackID: id)
        }
    }
}
