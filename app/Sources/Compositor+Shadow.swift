import Metal
import MetalPerformanceShaders

/// A layer's drop shadow (§7.5): the mask pass, the blur and the shadow draw
/// `MetalRenderer.render` encodes in front of a shadowed layer, and the
/// offscreen pair they share. Split out of `Compositor.swift` for size.
extension MetalRenderer {
    /// The canvas-sized mask and its blurred pair.
    struct ShadowSurfaces {
        let mask: MTLTexture
        let blurred: MTLTexture
    }

    // MARK: - Shadows

    /// One layer's drop shadow, encoded BEFORE the layer's own pass (§7.5).
    /// Three steps:
    ///
    /// 1. the layer is drawn again, into the shared mask texture, with
    ///    `shadowMask = 1` — which makes the fragment stage return coverage
    ///    instead of colour. It is the SAME vertex and fragment pair, so the
    ///    silhouette matches the layer's placement, rotation, crop, corner
    ///    radius, chroma hole, transition weight and own opacity exactly, by
    ///    construction rather than by two pieces of code agreeing to — which
    ///    is also why a half-transparent layer casts a half-strength shadow;
    /// 2. `MPSImageGaussianBlur` blurs that mask into its pair;
    /// 3. a full-canvas quad samples the blurred pair, displaced by the
    ///    shadow's (distance, angle) and tinted with its colour, blended into
    ///    the destination with the same premultiplied source-over as any
    ///    layer. The caller then draws the layer itself on top.
    ///
    /// **Why the offscreen textures are CANVAS-sized and not layer-sized.**
    /// The mask comes out of the layer pipeline, whose vertex stage works in
    /// canvas coordinates: the anchor is the canvas centre plus the clip's
    /// (x, y), rotation turns about that anchor, and a push, slide or zoom
    /// transition offsets the quad by a fraction of the CANVAS. A layer-sized
    /// target would need every one of those restated in a second coordinate
    /// space — a duplicate of the vertex stage, which would silently disagree
    /// with the original the first time a transition moved a quad. It would
    /// also have to be padded by `distance + 3σ` on all four sides and
    /// re-padded for every layer, which is the per-layer allocation the 8 ms
    /// budget cannot pay for. One canvas-sized pair is allocated on the first
    /// shadowed frame and reused by every shadowed layer of every frame
    /// after. What the choice costs is coverage that falls outside the canvas,
    /// which is not in the mask: that only shows on a layer hanging off the
    /// edge, and the blur's `.clamp` edge mode is the closer of the two
    /// approximations available there.
    ///
    /// The pair is reused WITHIN a frame too. Two shadowed layers mean two
    /// mask passes into the same texture, which is safe because the passes of
    /// one command buffer execute in order and Metal inserts the
    /// write-after-read barrier for a device-allocated texture; the price is
    /// that two shadows cannot overlap on the GPU. That is the right trade at
    /// two or three shadows in a frame, and the reason to revisit it is
    /// thirty.
    ///
    /// **`maskState` is the layer's specialization WITHOUT its blend.** The
    /// mask is a question about the layer's SHAPE, which no blend mode
    /// changes, so it takes the gather specialization alone.
    ///
    /// **It is defensive rather than load-bearing, and that was MEASURED —
    /// the obvious fear about it is wrong.** The fear, which this comment
    /// used to state as fact: step 1 draws coverage into a mask texture
    /// cleared to transparent black, so a `multiply` over that empty
    /// destination would be 0 everywhere and the shadow of every blended
    /// layer would silently vanish. It does not. That is true of a NAIVE
    /// `src · dst` and false of the premultiplied composite the shader
    /// actually runs, whose `(1 - ab)·src` term carries the source through an
    /// empty destination untouched: at `ab` = 0 the whole formula reduces to
    /// `src` exactly, for all eight modes, `add` included. It is the same
    /// property that lets a corner radius and a nest's clip rectangle work —
    /// a fully transparent fragment leaves the destination alone — read from
    /// the other side.
    ///
    /// So a build that passes `state` here renders every shadow correctly:
    /// the mutant that does it fails NO check in `phase6_proof.py`, which is
    /// the whole finding. (Named checks and not a fraction — a score goes
    /// stale the next time the script grows, and this one already had.) The separation stays
    /// because it costs nothing, because it says what the mask pass means,
    /// and because a future formula without that term would make the hazard
    /// real again — not because it is holding a bug back today.
    ///
    /// **The shadow's own DRAW stays fixed-function source-over**, on
    /// `shadowPipeline`, whatever the layer's mode. A shadow is light falling
    /// on the backdrop, not the layer's ink: a screened layer casting a
    /// screened shadow would brighten what is behind it twice, and a
    /// difference-blended one would cast a shadow that inverts the frame. It
    /// also keeps the shadow of a blended layer identical to the shadow of the
    /// same layer at `normal`, which is what the proof measures (B4).
    ///
    /// (The third member of that family, the REFLECTION, goes the other way
    /// and inherits the blend — `encodeReflection` says why.)
    func encodeShadow(
        _ shadow: ShadowProps, uniforms: LayerUniforms, texture: MTLTexture, matte: MTLTexture,
        look: MTLTexture, canvas: RecipeCanvas, maskState: MTLRenderPipelineState,
        pass: inout DestinationPass
    ) {
        func component(_ index: Int) -> Float {
            index < shadow.color.count ? Float(min(max(shadow.color[index], 0), 1))
                : (index == 3 ? 1 : 0)
        }
        // §5.2's Color is RGBA and the inspector's `opacity` is a separate
        // control, so a translucent shadow colour multiplies the two rather
        // than one of them silently winning.
        let opacity = Float(min(max(shadow.opacity, 0), 1)) * component(3)
        guard opacity > 0 else { return }

        // `blur` is a RADIUS in SOURCE pixels; MPS wants a standard deviation
        // in canvas pixels. Two conversions, both deliberate:
        //   · × the layer's scale, because every other length on this layer
        //     (the corner radius, the crop) is in source pixels, and a shadow
        //     that did not grow with its layer would look pasted on;
        //   · ÷ 2, the CSS `box-shadow` and Core Graphics convention — a
        //     Gaussian of σ = r/2 keeps essentially all of its weight inside
        //     ±r, so the shadow reaches about as far as the number says.
        let sigma = min(
            Float(max(shadow.blur, 0)) * uniforms.scale * 0.5, MetalRenderer.maxShadowSigma)
        guard
            let silhouette = shadowSilhouette(
                uniforms: uniforms, texture: texture, matte: matte, look: look, sigma: sigma,
                canvas: canvas, maskState: maskState, pass: &pass),
            let encoder = pass.open()
        else { return }

        var u = ShadowUniforms()
        u.canvasWidth = uniforms.canvasWidth
        u.canvasHeight = uniforms.canvasHeight
        // The layer's, not the mask pass's: this quad is drawn into the
        // DESTINATION, and everything it works in — the mask's coordinates
        // and the offset below — is canvas pixels.
        u.canvasPerDestX = uniforms.canvasPerDestX
        u.canvasPerDestY = uniforms.canvasPerDestY
        // The model's angle is DEGREES, 0 pointing right and increasing
        // COUNTER-CLOCKWISE (`model.rs`), while the canvas is y-DOWN — so the
        // y term carries the minus sign that turns a counter-clockwise angle
        // into a y-down displacement. Checked against the default shadow:
        // 315° gives (+0.71, +0.71), which in this space is down-and-right,
        // which is what `Shadow::default` says it is.
        let radians = Float(shadow.angle) * .pi / 180
        // Distance is source pixels too, and scaled the same way — but NOT
        // rotated by the layer's rotation: the direction is a property of the
        // light, in canvas space, so every shadow in a frame falls the same
        // way however its layer is turned.
        let distance = Float(max(shadow.distance, 0)) * uniforms.scale
        u.offsetX = distance * cos(radians)
        u.offsetY = -distance * sin(radians)
        u.colorR = component(0)
        u.colorG = component(1)
        u.colorB = component(2)
        u.opacity = opacity

        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<ShadowUniforms>.stride, index: 0)
        encoder.setFragmentTexture(silhouette, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        // Back to the layer pipeline, so the caller's own draw needs no state
        // change of its own and an unshadowed layer costs what it always did.
        encoder.setRenderPipelineState(pipeline)
    }

    /// Steps 1 and 2 of `encodeShadow`: the coverage pass into the shared mask
    /// and the blur into its pair. Returns the texture the shadow draw should
    /// sample — the blurred one normally, the mask itself for a `blur: 0`
    /// shadow or a device MPS will not run on — or nil when the offscreen pair
    /// cannot be had, in which case the layer renders without a shadow rather
    /// than not at all.
    ///
    /// Leaves the destination pass SUSPENDED: neither a second render pass nor
    /// an MPS kernel can be encoded while a render encoder is open, which is
    /// the reason `DestinationPass` exists.
    private func shadowSilhouette(
        uniforms: LayerUniforms, texture: MTLTexture, matte: MTLTexture, look: MTLTexture,
        sigma: Float, canvas: RecipeCanvas, maskState: MTLRenderPipelineState,
        pass: inout DestinationPass
    ) -> MTLTexture? {
        let width = max(1, canvas.width)
        let height = max(1, canvas.height)
        guard let surfaces = shadowPair(width: width, height: height) else { return nil }

        pass.suspend()
        var u = uniforms
        u.shadowMask = 1
        // The mask target is CANVAS sized (`shadowPair` above), so this one
        // pass's `[[position]]` really is in canvas pixels however small the
        // destination is — the conversion the layer stage now makes must be
        // the identity here, or the silhouette would be drawn through a
        // preview's scale factor while the mask it lands in kept its own. It
        // is written rather than left to `uniforms`, because what makes it
        // right is the descriptor eight lines below and not the recipe.
        u.canvasPerDestX = 1
        u.canvasPerDestY = 1
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = surfaces.mask
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = pass.buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return nil
        }
        // The layer's OWN gather specialization, so a blurred layer casts the
        // silhouette its blur actually leaves — the mask is only correct by
        // construction while it is the same fragment stage as the layer. Its
        // BLEND is deliberately not carried over; `encodeShadow` argues that.
        encoder.setRenderPipelineState(maskState)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setVertexBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        // The layer's matte coverage, so the silhouette — and the shadow — is
        // the cut-out shape (spec §11 MT-3). It is sampled at the canvas-
        // normalised position, so this canvas-sized pass reads it right.
        encoder.setFragmentTexture(matte, index: 1)
        // The layer's look (GR-7): the mask pass returns coverage, so it is
        // never sampled, but the fragment names `texture(2)`.
        encoder.setFragmentTexture(look, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        guard sigma >= MetalRenderer.minShadowSigma, let blur = blurKernel(sigma: sigma) else {
            return surfaces.mask
        }
        blur.encode(
            commandBuffer: pass.buffer, sourceTexture: surfaces.mask,
            destinationTexture: surfaces.blurred)
        return surfaces.blurred
    }

    /// The shared offscreen pair at the canvas size, allocated on first use
    /// and whenever the canvas changes size. Both are allocated together: a
    /// shadow with no blur leaves the second one idle, which is the cheaper
    /// mistake to make. In the working format, because the silhouette pass
    /// draws with a layer pipeline (spec §11 PR-1).
    private func shadowPair(width: Int, height: Int) -> ShadowSurfaces? {
        if let surfaces = shadowSurfaces, surfaces.mask.width == width,
            surfaces.mask.height == height
        {
            return surfaces
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: MetalRenderer.workingFormat, width: width, height: height,
            mipmapped: false)
        // Rendered into, sampled by the shadow pass, and written by MPS (which
        // takes a compute path for some sigmas and a render path for others,
        // so both usages have to be there).
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        // GPU-only: nothing on the CPU ever reads a shadow mask.
        descriptor.storageMode = .private
        guard let mask = device.makeTexture(descriptor: descriptor),
            let blurred = device.makeTexture(descriptor: descriptor)
        else { return nil }
        mask.label = "Reelcut shadow mask"
        blurred.label = "Reelcut shadow blur"
        let surfaces = ShadowSurfaces(mask: mask, blurred: blurred)
        shadowSurfaces = surfaces
        return surfaces
    }

    private func blurKernel(sigma: Float) -> MPSImageGaussianBlur? {
        guard blurSupported else { return nil }
        let key = Int((sigma * 4).rounded())
        if let hit = blurKernels[key] { return hit }
        if blurKernels.count >= 16 { blurKernels.removeAll() }
        let kernel = MPSImageGaussianBlur(device: device, sigma: Float(key) / 4)
        // The mask is a canvas-sized WINDOW on a layer that may run past the
        // canvas edge, so the coverage just outside it is unknown rather than
        // absent. Clamping the edge assumes it continues, which is right for
        // the full-bleed layer that is the common case; `.zero` would fade
        // every such shadow out along the frame border.
        kernel.edgeMode = .clamp
        blurKernels[key] = kernel
        return kernel
    }
}
