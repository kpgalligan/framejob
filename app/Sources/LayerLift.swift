import Metal

/// An HLG project's lift of every layer Frame Job draws (spec §11 HD-2,
/// HD-13 (f)): a text, caption, burn-in, shape, still or graphic texture —
/// premultiplied SDR from `LayerRenderers` — is run once through step 0's
/// own `.sdr` arm (`framejob_input_fragment` with
/// `InputConversion.sdr.uniforms(premultiplied: true, output: .hlg)`, HD-3's
/// lift) into a private `rgba16Float` texture of its size, which every draw
/// of that layer then samples in its place (`source(for:…)`,
/// `Compositor+Sources.swift`). Lifted at upload, not per sample, for step
/// 0's own reason: a 25-tap blur would repeat the lift 25 times. An HLG or PQ
/// still (spec §11 HD-19 (a)) is run through its OWN arm instead, in an HLG
/// project and in an SDR one (GR-15's HDR→SDR), so the pass takes the
/// conversion, the output and a PQ still's peak (spec §11 HD-20 (b)), and an
/// entry is a hit only when its source, its conversion, its output and its
/// peak are all four the asked ones.
///
/// The cache is a least-recently-used pool of `LayerRenderers.cacheLimit +
/// LayerRenderers.graphicCacheLimit` entries — the two pools' sizes, so every
/// texture they hold can have its lift held too — keyed by the source
/// texture's identity. Each entry holds its source strongly, so an identity
/// is never reused for another texture while its lift is held; a source
/// `LayerRenderers` re-renders is a new texture and a new entry, and the old
/// one ages out; one asked again in another conversion, output or peak is
/// made again and replaces its entry. An SDR project reaches this class only for an
/// HDR still. One instance per `MetalRenderer`, called from its render queue.
final class LayerLift {
    static let limit = LayerRenderers.cacheLimit + LayerRenderers.graphicCacheLimit

    private struct Entry {
        let source: MTLTexture
        let conversion: InputConversion
        let output: CanvasOutput
        let peak: UInt32?
        let lifted: MTLTexture
    }

    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    /// A 1³ lattice bound at `texture(1)`: the SDR arm samples no LUT, but the
    /// slot is never left empty (`InputStage`'s rule).
    private let noLUT: MTLTexture
    private var entries: [ObjectIdentifier: Entry] = [:]
    /// Least recently used first.
    private var order: [ObjectIdentifier] = []

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let vertex = library.makeFunction(name: "framejob_shadow_vertex"),
            let fragment = library.makeFunction(name: "framejob_input_fragment"),
            let pipeline = try? device.makeRenderPipelineState(
                descriptor: MetalRenderer.pipelineDescriptor(
                    label: "Frame Job layer lift", vertex: vertex, fragment: fragment,
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

    /// `texture` run through `conversion`'s arm for a project of `output` —
    /// by default HD-3's lift into HLG — from the pool or made now on a
    /// command buffer of its own on `queue`, waited for before it is returned;
    /// nil only when Metal cannot make the target or the pass. `peak` is a PQ
    /// still's effective peak, its layer's `input.peak` (spec §11 HD-20 (b));
    /// nil is unknown (1,000 cd/m², HD-6).
    func lifted(
        _ texture: MTLTexture, conversion: InputConversion = .sdr, output: CanvasOutput = .hlg,
        peak: UInt32? = nil, queue: MTLCommandQueue
    ) -> MTLTexture? {
        let key = ObjectIdentifier(texture)
        if let hit = entries[key], hit.source === texture, hit.conversion == conversion,
            hit.output == output, hit.peak == peak
        {
            touch(key)
            return hit.lifted
        }
        // The working format, `rgba16Float` (spec §11 PR-1), the pipeline's own.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalRenderer.workingFormat, width: max(1, texture.width),
            height: max(1, texture.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor),
            let buffer = queue.makeCommandBuffer()
        else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "Frame Job layer lift"
        encoder.setRenderPipelineState(pipeline)
        var u = conversion.uniforms(premultiplied: true, peak: peak, output: output)
        encoder.setFragmentBytes(&u, length: MemoryLayout<InputUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(noLUT, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }
        entries[key] = Entry(
            source: texture, conversion: conversion, output: output, peak: peak, lifted: target)
        touch(key)
        while order.count > Self.limit, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        return target
    }

    /// Moves `key` to the most-recent end.
    private func touch(_ key: ObjectIdentifier) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}
