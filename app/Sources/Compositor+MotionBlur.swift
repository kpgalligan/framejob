import CoreGraphics
import Metal

/// Motion blur drawn (spec §11 CU-117, road map creator-jobs CU11b): a recipe layer whose
/// `blur` lists N sub-frame placements is drawn N times — each sample at its own placement,
/// everything else the layer's own — into one destination-sized pool target cleared
/// transparent, each draw weighted 1/N by the blend colour, so the target holds the mean of
/// the N premultiplied samples. That mean is then laid on the pass ONCE with the layer's blend
/// mode (`framejob_motion_blur_fragment`), so a blended clip blends its averaged picture and
/// not each sample. `drawLayer` sends a blurred layer here as its first statement, so a blur on
/// the canvas, in a matte group and in a routed dissolve's half all draw this way. A layer
/// whose `blur` is null never reaches this file. Which layers blur, and N, are the core's
/// (CU-111, CU-112); nothing here re-derives them.

/// The composite's uniform block, mirroring `MotionBlurUniforms` in `Compositor.metal` FIELD
/// FOR FIELD under `LayerUniforms`' layout contract: scalars only, 4 floats, 16 bytes.
struct MotionBlurUniforms {
    /// The layer's `BlendMode.shaderCode`.
    var blendMode: Float = 0
    var reserved0: Float = 0
    var reserved1: Float = 0
    var reserved2: Float = 0
}

/// Why a motion-blurred layer could not be composed.
enum MotionBlurError: LocalizedError {
    case noTarget

    var errorDescription: String? {
        switch self {
        case .noTarget: return "A motion-blurred layer's offscreen target could not be made."
        }
    }
}

/// Motion blur's three pipelines: the two accumulating layer pipelines (plain and gathering)
/// and the composite.
final class MotionBlurPipelines {
    /// The plain layer fragment with source factors `blendColor` (RGB) and `blendAlpha`
    /// (alpha) and destination factors `one`: each draw adds its premultiplied colour × the
    /// encoder's blend colour, which `drawBlurred` sets to 1/N.
    let accumulate: MTLRenderPipelineState
    /// The same with the gathering specialization (`kGatherFilters`), for a layer whose filters
    /// or regions read neighbouring pixels (`RecipeLayer.needsGather`).
    let accumulateGather: MTLRenderPipelineState
    /// The full-frame quad that lays the accumulated target on the pass with the layer's blend;
    /// blending OFF, since the fragment returns the finished pixel
    /// (`MetalRenderer.pipelineDescriptor`'s programmable-blend rule).
    let composite: MTLRenderPipelineState

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let vertex = library.makeFunction(name: "framejob_layer_vertex"),
            let plain = MetalRenderer.layerFragment(library, gather: false),
            let gathering = MetalRenderer.layerFragment(library, gather: true),
            let quad = library.makeFunction(name: "framejob_shadow_vertex"),
            let fragment = library.makeFunction(name: "framejob_motion_blur_fragment"),
            let accumulate = try? device.makeRenderPipelineState(
                descriptor: Self.accumulating(
                    label: "Frame Job motion blur, accumulating", vertex: vertex,
                    fragment: plain)),
            let accumulateGather = try? device.makeRenderPipelineState(
                descriptor: Self.accumulating(
                    label: "Frame Job motion blur, accumulating and gathering", vertex: vertex,
                    fragment: gathering)),
            let composite = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job motion blur, composite", vertex: quad, fragment: fragment,
                    blending: false))
        else { return nil }
        self.accumulate = accumulate
        self.accumulateGather = accumulateGather
        self.composite = composite
    }

    /// The accumulate pipeline for a layer that does or does not gather.
    func accumulateState(gather: Bool) -> MTLRenderPipelineState {
        gather ? accumulateGather : accumulate
    }

    /// `MetalRenderer.pipelineDescriptor`'s layer descriptor with the accumulating factors.
    private static func accumulating(label: String, vertex: MTLFunction, fragment: MTLFunction)
        -> MTLRenderPipelineDescriptor
    {
        let descriptor = MetalRenderer.pipelineDescriptor(
            label: label, vertex: vertex, fragment: fragment)
        let attachment = descriptor.colorAttachments[0]!
        attachment.sourceRGBBlendFactor = .blendColor
        attachment.sourceAlphaBlendFactor = .blendAlpha
        attachment.destinationRGBBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        return descriptor
    }
}

extension MetalRenderer {
    /// `layer` drawn at its N sub-frame placements and laid on `pass` once (CU-117 (b), (c)).
    /// `prepared` is the layer prepared once — its texture, look, curves, cutout and cursor —
    /// and `matte` the coverage cutting it. Every throw leaves `pass` and the target suspended.
    func drawBlurred(
        _ layer: RecipeLayer, _ prepared: PreparedLayer, blur: RecipeBlur, matte: MTLTexture,
        canvas: RecipeCanvas, pass: inout DestinationPass
    ) throws {
        let count = blur.samples.count
        pass.suspend()
        guard let target = mattePool.takeComposite() else { throw MotionBlurError.noTarget }
        defer { mattePool.giveComposite(target) }
        var drawn = DestinationPass(
            buffer: pass.buffer, target: target,
            clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
            pipeline: motionBlur.accumulateState(gather: layer.needsGather), sampler: sampler)
        guard let encoder = drawn.open() else { throw MotionBlurError.noTarget }
        let weight = Float(1) / Float(count)
        encoder.setBlendColor(red: weight, green: weight, blue: weight, alpha: weight)
        // The textures every layer draw binds (`drawLayer`).
        encoder.setFragmentTexture(matte, index: 1)
        encoder.setFragmentTexture(prepared.look, index: 2)
        encoder.setFragmentTexture(prepared.curves, index: 3)
        encoder.setFragmentTexture(prepared.cutout, index: 4)
        encoder.setFragmentTexture(prepared.cursor, index: 5)
        for (index, sample) in blur.samples.enumerated() {
            var uniforms = Self.sampleUniforms(
                prepared.uniforms, sample, index: index, count: count, canvas: canvas)
            if layer.reflection != nil {
                encodeReflection(uniforms: uniforms, texture: prepared.texture, encoder: encoder)
            }
            encoder.setVertexBytes(
                &uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
            encoder.setFragmentBytes(
                &uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
            encoder.setFragmentTexture(prepared.texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        drawn.suspend()

        guard let out = pass.open() else { throw MotionBlurError.noTarget }
        out.setRenderPipelineState(motionBlur.composite)
        var u = MotionBlurUniforms()
        u.blendMode = Float(layer.blend.shaderCode)
        out.setFragmentBytes(&u, length: MemoryLayout<MotionBlurUniforms>.stride, index: 0)
        out.setFragmentTexture(target, index: 0)
        out.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        // Back to the pass's own pipeline, so the next layer inherits the state
        // `DestinationPass.open()` promises.
        out.setRenderPipelineState(pass.pipeline)
    }

    /// Sample `index` of `count`'s block (CU-117 (b), (g)): `base` with the sample's placement —
    /// the anchor W/2 + x, H/2 + y, the scale floored at 0.0001, the rotation in radians and its
    /// clip rectangle, none clearing the clip — and, when the cursor travels, the cursor at this
    /// sample's own point along it with `cursorSamples` 0, so each sample draws it sharp and the
    /// N samples average it. Nothing else changes.
    static func sampleUniforms(
        _ base: LayerUniforms, _ sample: RecipeBlurSample, index: Int, count: Int,
        canvas: RecipeCanvas
    ) -> LayerUniforms {
        var u = base
        u.anchorX = Float(Double(canvas.width) / 2 + sample.x)
        u.anchorY = Float(Double(canvas.height) / 2 + sample.y)
        u.scale = Float(max(sample.scale, 0.0001))
        u.rotation = Float(sample.rotation * .pi / 180)
        u.clipEnabled = 0
        u.clipX = 0
        u.clipY = 0
        u.clipW = 0
        u.clipH = 0
        u.clipRotation = 0
        u.apply(clipRect: sample.clipRect)
        if u.cursorSamples > 0.5 {
            let along = (Double(index) + 0.5) / Double(max(count, 1))
            u.cursorX = Float(Double(u.cursorX) + Double(u.cursorTravelX) * along)
            u.cursorY = Float(Double(u.cursorY) + Double(u.cursorTravelY) * along)
            u.cursorSamples = 0
        }
        return u
    }
}
