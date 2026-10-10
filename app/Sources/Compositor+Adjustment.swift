import CoreGraphics
import Metal

/// The adjustment pass (spec §11 GR-6): an adjustment clip has no picture of
/// its own, so its layer is not drawn from a texture. `encodeLayers` hands it
/// here instead of to `prepare`, and the eighth pipeline,
/// `reelcut_adjust_fragment`, reads the target it is drawing into through
/// `[[color(0)]]` — everything already drawn behind the clip in its
/// container, the canvas background included — and writes it back graded by
/// the layer's colour, tone, look and point filters, by `mix(dst, graded, w)`,
/// `w` the layer's opacity (its strength) times the matte coverage sampled
/// as step 7c samples it. One full-frame quad, the shadow pass's vertex
/// stage; the clip's stored transform, crop, shadow and the rest do nothing.
///
/// **Blending is OFF** (`pipelineDescriptor`'s doc, the B6 lesson): the
/// fragment returns the finished pixel, and a fixed-function pass over it
/// would blend the frame twice — invisible over an opaque destination, so
/// the proof reads the ALPHA channel over a translucent one (A1). Alpha is
/// preserved: the grade works on the un-premultiplied destination and is
/// premultiplied back by the destination's own alpha.
extension RecipeLayer {
    /// Whether this layer is an adjustment clip's.
    var isAdjustment: Bool {
        if case .adjustment = source { return true }
        return false
    }

    /// An adjustment layer that would change nothing: its colour neutral (all
    /// thirteen keys, which Show Ungraded writes so), no look (which Show
    /// Ungraded removes, GR-7) and no point filter with an amount above 0. It
    /// draws nothing, so the frame is byte-identical to one without the clip
    /// (GR-6, GR-4).
    var isNeutralAdjustment: Bool {
        let point: Set<FilterKind> = [.sepia, .noir, .vignette, .invert]
        return color.isIdentity && look == nil
            && !filters.contains { point.contains($0.kind) && $0.amount > 0 }
    }
}

extension MetalRenderer {

    /// The adjustment pipeline: the shadow pass's full-frame quad and
    /// `reelcut_adjust_fragment`, blending OFF, into the working format.
    static func adjustPipeline(
        device: MTLDevice, library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertex = library.makeFunction(name: "reelcut_shadow_vertex"),
            let fragment = library.makeFunction(name: "reelcut_adjust_fragment")
        else { return nil }
        return try? device.makeRenderPipelineState(
            descriptor: pipelineDescriptor(
                label: "Reelcut adjustment", vertex: vertex, fragment: fragment, blending: false))
    }

    /// One adjustment layer graded into `pass`, `matte` the coverage cutting
    /// it (the 1×1 placeholder when nothing does). Draws nothing when the
    /// layer has no drawn opacity or would change nothing. The chroma key is
    /// off: it opens a hole in a layer's own picture, and there is none. The
    /// pass's own pipeline is bound again after the draw, so the next layer
    /// inherits the state `DestinationPass.open()` promises.
    func drawAdjustment(
        _ layer: RecipeLayer, matte: MTLTexture, canvas: RecipeCanvas,
        pass: inout DestinationPass
    ) throws {
        let destination = CGSize(width: pass.target.width, height: pass.target.height)
        guard !layer.isNeutralAdjustment,
            var u = uniforms(for: layer, canvas: canvas, destination: destination)
        else { return }
        u.chromaEnabled = 0
        guard let encoder = pass.open() else { throw MatteError.noTarget }
        encoder.setRenderPipelineState(adjustPipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(matte, index: 1)
        encoder.setFragmentTexture(looks.texture(for: layer.look), index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setRenderPipelineState(pass.pipeline)
    }
}
