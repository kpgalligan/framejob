import CoreGraphics
import Metal

/// The adjustment pass (spec §11 GR-6): an adjustment clip has no picture of
/// its own, so its layer is not drawn from a texture. `encodeLayers` hands it
/// here instead of to `prepare`, and the eighth pipeline,
/// `framejob_adjust_fragment`, reads the target it is drawing into through
/// `[[color(0)]]` — everything already drawn behind the clip in its
/// container, the canvas background included — and writes it back graded by
/// the layer's colour, tone, wheels, curves, look and point filters, by
/// `mix(dst, graded, w)`, `w` the layer's opacity (its strength) times the
/// matte coverage sampled as step 7c samples it, times its qualifier's `q`
/// (spec §11 GR-13: `QualifierUniforms` at fragment `buffer(1)`, read from
/// the destination before the grade). One full-frame quad, the shadow pass's vertex
/// stage; the clip's stored transform, crop, shadow and the rest do nothing.
/// A layer the recipe marks `selection` (Show Selection) writes `q` × the
/// coverage as opaque grey instead, even when its grade is neutral or its
/// strength 0. A blurred qualifier (spec §11 GR-35) reads `q` from the
/// selection map `Compositor+Selection.swift` makes, bound at `texture(0)`
/// with `blurred` set; every other pass binds the placeholder there, unread.
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

    /// The adjustment source's qualifier; `.none` for any other layer.
    var qualifier: ColorQualifier {
        if case .adjustment(let qualifier, _) = source { return qualifier }
        return .none
    }

    /// Whether the recipe marked this adjustment layer for Show Selection.
    var isSelection: Bool {
        if case .adjustment(_, true) = source { return true }
        return false
    }

    /// An adjustment layer that would change nothing: its colour neutral (all
    /// thirteen keys, which Show Ungraded writes so), its wheels neutral (all
    /// nine, GR-11, which Show Ungraded writes so too), its six curves the
    /// identity (GR-12, GR-32, the same), no look that draws
    /// (Show Ungraded removes a look, GR-7; a LUT look whose file is missing
    /// or refused draws nothing, GR-8) and no point filter with an amount
    /// above 0. It draws nothing, so the frame is byte-identical to one
    /// without the clip (GR-6, GR-4). A qualifier alone changes nothing
    /// (GR-13): it narrows a grade, and there is none.
    func isNeutralAdjustment(drawsLook: Bool) -> Bool {
        let point: Set<FilterKind> = [.sepia, .noir, .vignette, .invert]
        return color.isIdentity && wheels.isNeutral && curves.isIdentity && !drawsLook
            && !filters.contains { point.contains($0.kind) && $0.amount > 0 }
    }
}

extension MetalRenderer {

    /// The adjustment pipeline: the shadow pass's full-frame quad and
    /// `framejob_adjust_fragment`, blending OFF, into the working format.
    static func adjustPipeline(
        device: MTLDevice, library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertex = library.makeFunction(name: "framejob_shadow_vertex"),
            let fragment = library.makeFunction(name: "framejob_adjust_fragment")
        else { return nil }
        return try? device.makeRenderPipelineState(
            descriptor: pipelineDescriptor(
                label: "Frame Job adjustment", vertex: vertex, fragment: fragment, blending: false))
    }

    /// One adjustment layer graded into `pass`, `matte` the coverage cutting
    /// it (the 1×1 placeholder when nothing does), `urls` where a LUT look's
    /// file is found (`RecipeSource.lookURLs(for:)`). Draws nothing when the
    /// layer has no drawn opacity or would change nothing — unless it is
    /// marked `selection`, which always draws (GR-13). The chroma key is
    /// off: it opens a hole in a layer's own picture, and there is none. The
    /// pass's own pipeline is bound again after the draw, so the next layer
    /// inherits the state `DestinationPass.open()` promises. A blurred
    /// qualifier's map is made first, after the neutral guard, which breaks
    /// the pass (GR-35); an unblurred one never touches it.
    func drawAdjustment(
        _ layer: RecipeLayer, matte: MTLTexture, canvas: RecipeCanvas, urls: [UInt32: URL],
        pass: inout DestinationPass
    ) throws {
        let destination = CGSize(width: pass.target.width, height: pass.target.height)
        let look = looks.lattice(for: layer.look, urls: urls)
        let selection = layer.isSelection
        guard selection || !layer.isNeutralAdjustment(drawsLook: look != nil),
            var u = uniforms(
                for: layer, canvas: canvas, destination: destination, ignoringOpacity: selection)
        else { return }
        var q = QualifierUniforms(layer.qualifier, selection: selection)
        u.chromaEnabled = 0
        if look == nil { u.lookEnabled = 0 }
        let curves = looks.curves.texture(for: layer.curves)
        if curves === looks.curves.placeholder {
            u.curvesEnabled = 0
            u.hueCurvesEnabled = 0
        }
        var selectionTexture = placeholder
        if blurSupported,
            let sigma = layer.qualifier.selectionSigma(canvasPerDest: u.canvasPerDestX),
            let map = selectionMap(q, sigma: sigma, pass: &pass)
        {
            q.blurred = 1
            selectionTexture = map
        }
        guard let encoder = pass.open() else { throw MatteError.noTarget }
        encoder.setRenderPipelineState(adjustPipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&q, length: MemoryLayout<QualifierUniforms>.stride, index: 1)
        encoder.setFragmentTexture(selectionTexture, index: 0)
        encoder.setFragmentTexture(matte, index: 1)
        encoder.setFragmentTexture(look ?? looks.placeholder, index: 2)
        encoder.setFragmentTexture(curves, index: 3)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setRenderPipelineState(pass.pipeline)
    }
}
