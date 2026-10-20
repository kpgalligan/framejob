import Metal

/// The output pass (spec §11 HD-14 (b)): one full-frame quad after the last
/// layer, `framejob_output_fragment` reading the finished destination through
/// `[[color(0)]]` and writing it back as the picture the key asked for — the
/// SDR version (HD-4: HLG → display light → × 1000/203 → BT.2020 to BT.709 →
/// GR-15's gamut lift → the shoulder at `OutputTransform.sdrKnee` → Core
/// Media 709's encode with its toe) or PQ (display light at 1,000 cd/m² →
/// ST 2084). Drawn only when `OutputTransform.uniforms(for:)` answers a block,
/// so an HLG master and every SDR project's frame are the bytes they were.
///
/// The shadow pass's vertex stage and the adjustment pass's shape: **blending
/// OFF** (`pipelineDescriptor`'s doc, the B6 lesson), the fragment returning
/// the finished pixel, un-premultiplied in and premultiplied back by the
/// destination's own alpha. The pass's own pipeline is bound again after the
/// draw, so the encoder is left in the state `DestinationPass.open()` promises.
extension MetalRenderer {

    /// The output pipeline: the shadow pass's full-frame quad and
    /// `framejob_output_fragment`, blending OFF, into the working format.
    static func outputPipeline(
        device: MTLDevice, library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        guard let vertex = library.makeFunction(name: "framejob_shadow_vertex"),
            let fragment = library.makeFunction(name: "framejob_output_fragment")
        else { return nil }
        return try? device.makeRenderPipelineState(
            descriptor: pipelineDescriptor(
                label: "Frame Job output", vertex: vertex, fragment: fragment, blending: false))
    }

    /// The finished frame in `pass` drawn as `canvas` asks (HD-14 (b)); nothing
    /// when it asks for no pass.
    func encodeOutput(_ canvas: RecipeCanvas, pass: inout DestinationPass) throws {
        guard var u = OutputTransform.uniforms(for: canvas) else { return }
        guard let encoder = pass.open() else { throw CompositorError.noDestinationTexture }
        encoder.setRenderPipelineState(outputPipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<OutputUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setRenderPipelineState(pass.pipeline)
    }
}
