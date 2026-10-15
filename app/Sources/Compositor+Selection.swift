import Metal
import MetalPerformanceShaders

/// The qualifier's cleanup blur (spec §11 GR-35): the selection map an
/// adjustment pass reads when its qualifier is blurred.
///
/// `drawAdjustment` asks for it only when a range is on, the blur is above 0,
/// the σ in destination pixels is at least `minShadowSigma` and MPS runs on
/// the device (`ColorQualifier.selectionSigma`); every other adjustment pass
/// is the inline one, with no pass break and no allocation, byte-identical
/// to the pass before the key existed.
///
/// The sequence is the shadow's (`Compositor+Shadow.swift`): the destination
/// pass is SUSPENDED, because neither a second render pass nor an MPS kernel
/// can be encoded while its encoder is open; `framejob_qualifier_map_fragment`
/// renders q of every pixel of the target into the map; `MPSImageGaussianBlur`
/// (`.clamp`, the shadow's kernel cache, σ quantised to a quarter pixel)
/// blurs it into its pair; and the adjustment draw that follows reopens the
/// pass with `.load` and reads the blurred q at `texture(0)`. Only q is in
/// the map: the matte coverage is multiplied after, unblurred, so a matte
/// track's edge stays its own.
///
/// **Why the pair is DESTINATION-sized.** The map is read at the adjustment
/// fragment's own `[[position]]`, which is in destination pixels, and every
/// target a pass draws into — `render`'s destination, `encodeMattes`'
/// composites, `encodeDissolve`'s halves — is the destination's size
/// (`MattePool`). One pair serves every blurred adjustment layer of every
/// frame, as the shadow's does, allocated on the first one drawn and
/// replaced when the destination's size changes: 2 × 16.6 MB at 4K in
/// `r16Float`, held per renderer.
extension MetalRenderer {
    /// The q map and its blurred pair, `r16Float`, the destination's size.
    struct QualifierSurfaces {
        let map: MTLTexture
        let blurred: MTLTexture
    }

    /// The map pass's pipeline: the shadow pass's full-frame quad and
    /// `framejob_qualifier_map_fragment`, blending off, into `r16Float`.
    static func qualifierMapPipeline(
        device: MTLDevice, library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertex = library.makeFunction(name: "framejob_shadow_vertex"),
            let fragment = library.makeFunction(name: "framejob_qualifier_map_fragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Frame Job selection map"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .r16Float
        descriptor.colorAttachments[0].isBlendingEnabled = false
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The map pass and its blur, encoded into `buffer`: q of every pixel of
    /// `target` rendered into `surfaces.map` (cleared, drawn, ended), then
    /// `blur` from it into `surfaces.blurred`. Returns the texture the
    /// adjustment pass should read — `blurred`, or `map` when `blur` is nil.
    /// Static, so `tree_bench.swift` times the app's own encoding.
    static func encodeSelectionMap(
        _ q: QualifierUniforms, from target: MTLTexture, into surfaces: QualifierSurfaces,
        pipeline: MTLRenderPipelineState, blur: MPSImageGaussianBlur?, buffer: MTLCommandBuffer
    ) -> MTLTexture {
        var q = q
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = surfaces.map
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1)
        if let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&q, length: MemoryLayout<QualifierUniforms>.stride, index: 0)
            encoder.setFragmentTexture(target, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        guard let blur else { return surfaces.map }
        blur.encode(
            commandBuffer: buffer, sourceTexture: surfaces.map,
            destinationTexture: surfaces.blurred)
        return surfaces.blurred
    }

    /// The blurred selection of `pass`'s target for `q`, at `sigma`
    /// destination pixels: the pass suspended, the pair taken (or made at the
    /// target's size), and `encodeSelectionMap` run with the shared kernel.
    /// Nil, the pass untouched, when the pair cannot be made, in which case
    /// the caller draws the inline pass; otherwise the pass is left
    /// suspended, and the caller's `open()` resumes it with `.load`. A σ
    /// below `minShadowSigma` skips MPS and answers the unblurred map.
    func selectionMap(
        _ q: QualifierUniforms, sigma: Float, pass: inout DestinationPass
    ) -> MTLTexture? {
        guard let surfaces = selectionPair(width: pass.target.width, height: pass.target.height)
        else { return nil }
        pass.suspend()
        let blur = sigma >= MetalRenderer.minShadowSigma ? blurKernel(sigma: sigma) : nil
        return MetalRenderer.encodeSelectionMap(
            q, from: pass.target, into: surfaces, pipeline: qualifierMapPipeline, blur: blur,
            buffer: pass.buffer)
    }

    /// The shared pair at `width` × `height`, allocated on first use and
    /// whenever the destination's size changes. Rendered into, read by the
    /// adjustment pass, and written by MPS (whose compute path needs
    /// `shaderWrite`); GPU-only.
    private func selectionPair(width: Int, height: Int) -> QualifierSurfaces? {
        if let surfaces = qualifierSurfaces, surfaces.map.width == width,
            surfaces.map.height == height
        {
            return surfaces
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r16Float, width: max(1, width), height: max(1, height),
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let map = device.makeTexture(descriptor: descriptor),
            let blurred = device.makeTexture(descriptor: descriptor)
        else { return nil }
        map.label = "Frame Job selection map"
        blurred.label = "Frame Job selection blur"
        let surfaces = QualifierSurfaces(map: map, blurred: blurred)
        qualifierSurfaces = surfaces
        return surfaces
    }
}
