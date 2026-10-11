import AVFoundation
import CoreVideo
import Metal

/// The routed dissolve (spec §11 MT-8, §7.5): a `cross_dissolve` or `zoom`
/// with a nested half — a layer's `dissolve`, which the core decides — is
/// drawn as two halves, each alone and unweighted into a destination-sized
/// pool target cleared transparent, then laid on the pass in one full-frame
/// draw as (1 − p)·out + p·in, a zoom's halves scaled there about their
/// anchors. `encodeLayers` is the one walk over a layer list both passes
/// make — the canvas's in `render` and a matte group's members in
/// `encodeMattes` — and `drawLayer` the one per-layer draw under it, so a
/// half is everything its layers draw: shadows, reflections, mattes cutting
/// it, and any routed dissolve inside it, one level deeper.
///
/// A timeline pair of clips that are not nest clips is not routed and keeps
/// the per-layer weight correction (MT-3); a frame with no routed dissolve
/// takes no target and draws exactly as before.

/// The dissolve mix's uniform block, mirroring `DissolveUniforms` in
/// `Compositor.metal` FIELD FOR FIELD under `LayerUniforms`' layout
/// contract: scalars only, 12 floats, 48 bytes.
struct DissolveUniforms {
    var progress: Float = 0
    /// 1 for a routed zoom, whose halves the mix scales.
    var zoom: Float = 0
    var canvasPerDestX: Float = 1
    var canvasPerDestY: Float = 1
    var canvasWidth: Float = 0
    var canvasHeight: Float = 0
    /// Canvas pixels, top-left frame.
    var outAnchorX: Float = 0
    var outAnchorY: Float = 0
    var inAnchorX: Float = 0
    var inAnchorY: Float = 0
    var reserved0: Float = 0
    var reserved1: Float = 0
}

/// Why a routed dissolve could not be composed.
enum DissolveError: LocalizedError {
    case noTarget

    var errorDescription: String? {
        switch self {
        case .noTarget: return "A dissolve's offscreen half could not be made."
        }
    }
}

extension MetalRenderer {

    /// Draws `layers`, back to front, onto `pass`. A run of layers that are
    /// halves of one routed dissolve at chain depth `depth` — contiguous,
    /// out before in, as the core lists them — is drawn as two halves and
    /// mixed (`encodeDissolve`); every other layer is drawn as it stands.
    /// `all` is the recipe's whole layer list, where a transition's partner
    /// is looked up. Every throw leaves every pass it opened, and `pass`,
    /// suspended.
    func encodeLayers(
        _ layers: [RecipeLayer], depth: Int, among all: [RecipeLayer],
        coverage: MatteCoverage, canvas: RecipeCanvas, pass: inout DestinationPass,
        request: AVAsynchronousVideoCompositionRequest, instruction: RecipeInstruction?,
        live: inout [CVMetalTexture]
    ) throws {
        let destination = CGSize(width: pass.target.width, height: pass.target.height)
        var index = 0
        while index < layers.count {
            let layer = layers[index]
            guard layer.dissolve.count > depth else {
                index += 1
                // An adjustment clip grades what is behind it rather than
                // drawing a picture (spec §11 GR-6, `Compositor+Adjustment.swift`).
                if layer.isAdjustment {
                    guard let matte = coverage.texture(for: layer) else {
                        pass.suspend()
                        throw MatteError.unordered
                    }
                    try drawAdjustment(
                        layer, matte: matte, canvas: canvas,
                        urls: RecipeSource.shared.lookURLs(for: instruction), pass: &pass)
                    continue
                }
                guard
                    let prepared = prepare(
                        layer, among: all, canvas: canvas, destination: destination,
                        request: request, instruction: instruction, live: &live)
                else { continue }
                // The mattes cutting this layer, or the placeholder (MT-3).
                guard let matte = coverage.texture(for: layer) else {
                    pass.suspend()
                    throw MatteError.unordered
                }
                try drawLayer(layer, prepared, matte: matte, canvas: canvas, pass: &pass)
                continue
            }
            let id = layer.dissolve[depth].id
            var end = index + 1
            while end < layers.count, layers[end].dissolve.count > depth,
                layers[end].dissolve[depth].id == id
            {
                end += 1
            }
            try encodeDissolve(
                Array(layers[index..<end]), depth: depth, among: all, coverage: coverage,
                canvas: canvas, pass: &pass, request: request, instruction: instruction,
                live: &live)
            index = end
        }
    }

    /// One routed dissolve: `block` split by role at `depth`, each half drawn
    /// into its own pool target (even an empty half, cleared), then the two
    /// mixed onto `pass` with `dissolvePipeline`.
    private func encodeDissolve(
        _ block: [RecipeLayer], depth: Int, among all: [RecipeLayer],
        coverage: MatteCoverage, canvas: RecipeCanvas, pass: inout DestinationPass,
        request: AVAsynchronousVideoCompositionRequest, instruction: RecipeInstruction?,
        live: inout [CVMetalTexture]
    ) throws {
        let halves = [
            block.filter { !$0.dissolve[depth].isIncoming },
            block.filter { $0.dissolve[depth].isIncoming },
        ]
        pass.suspend()
        guard let outgoing = mattePool.takeComposite() else { throw DissolveError.noTarget }
        defer { mattePool.giveComposite(outgoing) }
        guard let incoming = mattePool.takeComposite() else { throw DissolveError.noTarget }
        defer { mattePool.giveComposite(incoming) }
        // Metal orders each target's clear after any earlier read of it in
        // this command buffer: a pool target is hazard-tracked (MT-9).
        for (half, target) in zip(halves, [outgoing, incoming]) {
            var drawn = DestinationPass(
                buffer: pass.buffer, target: target,
                clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0),
                pipeline: pipeline, sampler: sampler)
            guard drawn.open() != nil else { throw DissolveError.noTarget }
            defer { drawn.suspend() }
            try encodeLayers(
                half, depth: depth + 1, among: all, coverage: coverage, canvas: canvas,
                pass: &drawn, request: request, instruction: instruction, live: &live)
        }

        guard let encoder = pass.open() else { throw DissolveError.noTarget }
        let entry = block[0].dissolve[depth]
        var u = DissolveUniforms()
        u.progress = Float(min(max(entry.progress, 0), 1))
        u.zoom = entry.kind == .zoom ? 1 : 0
        u.canvasWidth = Float(max(1, canvas.width))
        u.canvasHeight = Float(max(1, canvas.height))
        u.canvasPerDestX = u.canvasWidth / Float(max(1, pass.target.width))
        u.canvasPerDestY = u.canvasHeight / Float(max(1, pass.target.height))
        // Each half's anchor from its first layer; an empty half draws
        // nothing, so its anchor is never read.
        if let anchor = halves[0].first?.dissolve[depth].anchor, anchor.count >= 2 {
            u.outAnchorX = Float(anchor[0])
            u.outAnchorY = Float(anchor[1])
        }
        if let anchor = halves[1].first?.dissolve[depth].anchor, anchor.count >= 2 {
            u.inAnchorX = Float(anchor[0])
            u.inAnchorY = Float(anchor[1])
        }
        encoder.setRenderPipelineState(dissolvePipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<DissolveUniforms>.stride, index: 0)
        encoder.setFragmentTexture(outgoing, index: 0)
        encoder.setFragmentTexture(incoming, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        // Back to the pass's own pipeline, so the next layer inherits the
        // state `DestinationPass.open()` promises.
        encoder.setRenderPipelineState(pass.pipeline)
    }

    /// One layer drawn onto `pass`: its shadow, then its reflection and
    /// itself, `texture(1)` bound to the mattes cutting it. A layer that
    /// needs a neighbourhood filter or a blend mode takes its own pipeline
    /// state for the draw (`pipelineState(gather:blend:)`), its shadow's
    /// mask the same specialization without the blend.
    func drawLayer(
        _ layer: RecipeLayer, _ prepared: PreparedLayer, matte: MTLTexture,
        canvas: RecipeCanvas, pass: inout DestinationPass
    ) throws {
        var uniforms = prepared.uniforms
        let state = pipelineState(gather: layer.needsGather, blend: layer.needsBlend)
        // The look's lattice, or the placeholder (spec §11 GR-7, GR-8), and
        // the curves' strip, or its placeholder (GR-12): every draw through
        // the layer fragments binds `texture(2)` and `texture(3)`, the
        // shadow's mask pass and the reflection's included.
        let look = prepared.look
        if let shadow = layer.shadow {
            encodeShadow(
                shadow, uniforms: uniforms, texture: prepared.texture, matte: matte, look: look,
                curves: prepared.curves, canvas: canvas,
                maskState: pipelineState(gather: layer.needsGather, blend: false), pass: &pass)
        }
        guard let encoder = pass.open() else { throw MatteError.noTarget }
        if state !== pipeline { encoder.setRenderPipelineState(state) }
        encoder.setFragmentTexture(matte, index: 1)
        encoder.setFragmentTexture(look, index: 2)
        encoder.setFragmentTexture(prepared.curves, index: 3)
        if layer.reflection != nil {
            encodeReflection(uniforms: uniforms, texture: prepared.texture, encoder: encoder)
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(prepared.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        if state !== pipeline { encoder.setRenderPipelineState(pipeline) }
    }
}
