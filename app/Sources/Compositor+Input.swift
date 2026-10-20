import AVFoundation
import CoreVideo
import Metal
import simd

/// The compositor a composition holding an HLG, PQ or wide-gamut source is
/// built with (`CompositionBuilder.convertsSources`, spec §11 GR-15 as
/// amended after T3-1's H1 stop). It answers AVFoundation's two colour
/// properties true, so every source frame arrives native and honestly
/// labelled on every path, and runs step 0 (`encodeInputs`); its composition
/// is BT.709 — BT.2020/HLG in an HLG project, every one of whose compositions
/// it builds (spec §11 HD-2) — so a frame it composes is labelled for what it
/// holds. Every
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
/// primaries, or the sRGB transfer — or whose layer carries its media's
/// Camera Log (`input`, spec §11 GR-16: a maker's log curve, or a `lut`
/// media's table), which decides before the labels; and only in a
/// `ConvertingCompositor`. Every other source is sampled exactly as before.
///
/// Why a pass and not arithmetic inside the sample: a conversion in a
/// 25-tap blur would run once per tap (+3.06 ms at 4K, the tier-3 brief),
/// the pass once per pixel. It runs before `encodeMattes`, so a matte
/// member, a canvas layer, a shadow's silhouette and a dissolve's half all
/// sample the converted texture, and the chroma key, Color's four and the
/// grade (steps 3–4d) see converted values.
///
/// The pass is the shadow pass's full-frame quad (`framejob_shadow_vertex`)
/// and `framejob_input_fragment`, which READS the source texel at its own
/// pixel (the target is the frame's coded size), blending off.

/// The input pass's uniform block, mirrored FIELD FOR FIELD by
/// `InputUniforms` in `Compositor.metal` under `LayerUniforms`' layout
/// contract: scalars only, a multiple of 16 bytes (28 floats, 112 bytes).
struct InputUniforms {
    /// 1 HLG, 2 PQ, 3 wide-gamut SDR, 4 sRGB, 5 Apple Log (and Apple Log 2),
    /// 6 S-Log3, 7 V-Log, 8 a LUT, 9 SDR into an HLG project (`kInputHLG`…
    /// in the shader).
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
    /// Camera log's scale on scene light, 0.42^2.4/0.18 (spec §11 GR-16).
    var exposure: Float = 0
    /// Camera log's code domain: the maker's signal is `codeScale·s +
    /// codeOffset` of the decoded signal s.
    var codeScale: Float = 0
    var codeOffset: Float = 0
    /// Source → BT.709, row-major.
    var m00: Float = 1, m01: Float = 0, m02: Float = 0
    var m10: Float = 0, m11: Float = 1, m12: Float = 0
    var m20: Float = 0, m21: Float = 0, m22: Float = 1
    /// 1 in an HLG project (spec §11 HD-2): the shader's HLG ending, every
    /// arm written as HLG-encoded BT.2020 (the matrix is then source →
    /// BT.2020). 0 in an SDR project, whose arms are exactly as before.
    var output: Float = 0
    /// The lift's SDR white over HLG's nominal peak, 203/1000 (HD-3).
    var liftScale: Float = 0
    /// BT.2100's nominal system gamma, the lift's inverse OOTF (1.2).
    var ootfGamma: Float = 0
    /// BT.2390's EETF for a PQ media above 1,000 cd/m² (HD-13 (c)): the PQ
    /// signal of its peak (0 = no EETF), the target's signal over it, and
    /// the knee KS = 1.5·maxLum − 0.5.
    var eetfSourcePQ: Float = 0
    var eetfMaxLum: Float = 0
    var eetfKnee: Float = 0
    /// The lift's decode toe (HD-13 (a)): Core Media 709's γ curve is drawn
    /// by Core Graphics with ColorSync's slope limit, `max(s/16, s^γ)`, so an
    /// SDR arm's decode in an HLG project is too (1/16; 0 elsewhere).
    var decodeToe: Float = 0

    static let hlg: Float = 1, pq: Float = 2, sdrWide: Float = 3, srgb: Float = 4
    static let appleLog: Float = 5, slog3: Float = 6, vlog: Float = 7, lut: Float = 8
    static let sdr: Float = 9

    /// A curve's kind: Apple Log 2 is Apple Log's curve (its gamut differs).
    static func kind(of curve: LogCurve) -> Float {
        switch curve {
        case .appleLog, .appleLog2: return appleLog
        case .slog3: return slog3
        case .vlog: return vlog
        }
    }

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
    /// A 1³ lattice bound at `texture(1)` when the conversion is not a LUT,
    /// so the slot is never empty.
    private let noLUT: MTLTexture
    private var targets: [Size: [MTLTexture]] = [:]
    /// How many of each size's targets this frame holds (the first n).
    private var taken: [Size: Int] = [:]
    /// `taken` of each of the last `keepFrames` frames, oldest first.
    private var recent: [[Size: Int]] = []
    /// This frame's converted sources, by composition track id.
    private var byTrack: [Int: MTLTexture] = [:]
    private var passes = 0

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let vertex = library.makeFunction(name: "framejob_shadow_vertex"),
            let fragment = library.makeFunction(name: "framejob_input_fragment"),
            let pipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job input", vertex: vertex, fragment: fragment,
                    blending: false))
        else { return nil }
        let lattice = MTLTextureDescriptor()
        lattice.textureType = .type3D
        lattice.pixelFormat = .rgba16Float
        lattice.usage = [.shaderRead]
        guard let noLUT = device.makeTexture(descriptor: lattice) else { return nil }
        self.device = device
        self.pipeline = pipeline
        self.noLUT = noLUT
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
    /// when no encoder could be made. `lut` is a `.lut` conversion's lattice
    /// (spec §11 GR-16), sampled at `texture(1)`; `fullRange` is the source
    /// media's range flag, which a log curve's code domain follows (GR-22);
    /// `peak` a PQ media's effective peak, where the PQ arm's shoulder ends
    /// (spec §11 HD-12); `output` the project's dynamic range (HD-2).
    func encode(
        _ conversion: InputConversion, premultiplied: Bool, from source: MTLTexture,
        into target: MTLTexture, buffer: MTLCommandBuffer, lut: MTLTexture? = nil,
        fullRange: Bool = false, peak: UInt32? = nil, output: CanvasOutput = .sdr
    ) -> Bool {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return false
        }
        encoder.label = "Frame Job input"
        encoder.setRenderPipelineState(pipeline)
        var u = conversion.uniforms(
            premultiplied: premultiplied, fullRange: fullRange, peak: peak, output: output)
        encoder.setFragmentBytes(&u, length: MemoryLayout<InputUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(lut ?? noLUT, index: 1)
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
    /// converted texture to every draw of that track. A layer's `input` (its
    /// media's Camera Log, spec §11 GR-16) decides before the frame's labels;
    /// a LUT is found through the URLs its document published, and one that
    /// cannot be drawn leaves the source unconverted. A track's range flag
    /// comes from the instruction (`fullRangeTracks`, GR-22), and a PQ
    /// media's peak from the same `input` (spec §11 HD-12). In an HLG project
    /// (`output`, spec §11 HD-2) the choice is `choose(input:buffer:output:)`'s.
    func encodeInputs(
        layers: [RecipeLayer], request: AVAsynchronousVideoCompositionRequest,
        buffer: MTLCommandBuffer, live: inout [CVMetalTexture], output: CanvasOutput
    ) throws {
        var seen = Set<Int>()
        for layer in layers {
            guard case .track(let id) = layer.source, seen.insert(id).inserted,
                let frame = request.sourceFrame(byTrackID: CMPersistentTrackID(id))
            else { continue }
            let conversion = InputConversion.choose(
                input: layer.input, buffer: frame, output: output)
            guard let conversion else { continue }
            var lut: MTLTexture?
            if case .lut(let media) = conversion {
                let urls = RecipeSource.shared.lookURLs(
                    for: request.videoCompositionInstruction as? RecipeInstruction)
                guard let url = urls[media], let lattice = looks.luts.texture(at: url) else {
                    continue
                }
                lut = lattice
            }
            guard let source = texture(from: frame, live: &live) else { continue }
            let fullRange = (request.videoCompositionInstruction as? RecipeInstruction)?
                .fullRangeTracks.contains(id) == true
            guard let target = inputs.target(width: source.width, height: source.height),
                inputs.encode(
                    conversion, premultiplied: Self.declaresPremultipliedAlpha(frame),
                    from: source, into: target, buffer: buffer, lut: lut, fullRange: fullRange,
                    peak: layer.input?.peak, output: output)
            else { throw InputError.noTarget }
            inputs.record(target, trackID: id)
        }
    }
}
