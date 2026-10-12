import Metal

/// The destination render pass, as a value that can be suspended and resumed.
///
/// One encoder for the whole frame is the fast path and stays the fast path:
/// it is created once, every layer draws into it, and an unshadowed frame
/// never touches anything else here. A shadow, though, has to render its mask
/// into a DIFFERENT texture and then run an MPS kernel, and neither can be
/// encoded while a render encoder is open — so the shadow sequence suspends
/// the pass and the next `open()` resumes it with `.load` in place of
/// `.clear`. That costs a store and a load of the canvas per shadowed layer,
/// which is the standing price of doing the blur in the same command buffer;
/// the alternative, one offscreen texture per shadowed layer so every mask
/// could be rendered up front, is the allocation the budget refuses.
struct DestinationPass {
    let buffer: MTLCommandBuffer
    let target: MTLTexture
    let clear: MTLClearColor
    let pipeline: MTLRenderPipelineState
    let sampler: MTLSamplerState
    private var encoder: MTLRenderCommandEncoder?
    /// False only before the very first `open()`. The first pass CLEARS —
    /// the destination is a recycled pixel buffer and holds an old frame —
    /// and every resumption after it loads what has been drawn so far.
    private var cleared = false

    /// Spelled out because the private members above would otherwise make the
    /// memberwise initializer private too.
    init(
        buffer: MTLCommandBuffer, target: MTLTexture, clear: MTLClearColor,
        pipeline: MTLRenderPipelineState, sampler: MTLSamplerState
    ) {
        self.buffer = buffer
        self.target = target
        self.clear = clear
        self.pipeline = pipeline
        self.sampler = sampler
    }

    /// The open encoder, opening one if the pass is suspended. A newly opened
    /// encoder carries the layer pipeline and the shared sampler, so a caller
    /// that has not changed either draws straight into it.
    mutating func open() -> MTLRenderCommandEncoder? {
        if let encoder = encoder { return encoder }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = cleared ? .load : .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = clear
        guard let opened = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        opened.setRenderPipelineState(pipeline)
        opened.setFragmentSamplerState(sampler, index: 0)
        encoder = opened
        cleared = true
        return opened
    }

    /// Ends the encoder if one is open. Also how the frame is finished: the
    /// command buffer must have no open encoder when it is committed.
    mutating func suspend() {
        encoder?.endEncoding()
        encoder = nil
    }
}
