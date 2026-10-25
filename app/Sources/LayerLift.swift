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
    /// Step 0's pass; the SDR arm samples no LUT, and the pass binds its
    /// empty lattice in the slot.
    private let pass: InputPass
    private var entries = LRUCache<ObjectIdentifier, Entry>(limit: LayerLift.limit)

    init?(device: MTLDevice, library: MTLLibrary) {
        guard let pass = InputPass(device: device, library: library, label: "Frame Job layer lift")
        else { return nil }
        self.device = device
        self.pass = pass
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
        if let hit = entries.value(for: key, where: {
            $0.source === texture && $0.conversion == conversion
                && $0.output == output && $0.peak == peak
        }) {
            return hit.lifted
        }
        guard let target = InputPass.target(
                device: device, width: texture.width, height: texture.height),
            let buffer = queue.makeCommandBuffer(),
            pass.encode(
                conversion, premultiplied: true, from: texture, into: target, buffer: buffer,
                peak: peak, output: output)
        else { return nil }
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }
        entries.insert(
            Entry(
                source: texture, conversion: conversion, output: output, peak: peak,
                lifted: target),
            for: key)
        return target
    }
}
