import AVFoundation
import CoreVideo
import Metal

/// The M3 effect block of `LayerUniforms`: filters, reflection, spotlight and
/// the nest clip rectangle (spec §4.2, §7.3), plus phase 3c's obscured
/// regions and the one extra draw a reflection needs.
///
/// Split out of `Compositor.swift` for size, not for layering — these are the
/// same uniform block and the same pipeline, and the layout contract at the
/// top of `Compositor.metal` still governs every field they touch. What lives
/// here is the translation from the recipe's values to the shader's, and the
/// argument for each choice of units.
///
/// **The unit rule, once, for everything below.** Every length a layer owns is
/// in SOURCE pixels — the crop, the corner radius, the shadow's blur and
/// distance — so that scaling the layer scales the effect with it and nothing
/// looks pasted on. The spotlight's box and feather, the reflection's gap and
/// the filters' radii all follow that rule, and the shader converts. The one
/// exception is `clip_rect`, which is in CANVAS pixels because it belongs to
/// the nest and not to the layer; it is called out again where it is filled.
///
/// **What `amount` buys, in numbers.** Two of these effects turn a 0…1
/// strength into a LENGTH, and the shader's constants are the only statement
/// of the conversion, so here it is once in prose. A blur —
/// a `FilterKind.blur` or an `ObscureKind.blur` region alike — puts its outer
/// tap ring at `amount × 24` source pixels (`kBlurMaxRadius`, thirteen taps,
/// two staggered hexagons). A pixelate — `FilterKind.pixelate` or an
/// `ObscureKind.pixelate` region — snaps the sampling point to blocks of
/// `1 + amount × 63` source pixels a side (`mix(1, kPixelateMaxBlock, amount)`
/// with `kPixelateMaxBlock` = 64), so **amount 1 is a flat 64 × 64 SOURCE
/// pixel block** and amount 0 is a block of one pixel, which is no
/// pixelation at all and which the shader skips. The obscure block reaches
/// those two maxima through `kObscureMaxBlur` and `kObscureMaxBlock`, which
/// are aliases of them: an obscured region at amount 1 is exactly the same
/// filter at amount 1, and a later divergence is one line in the shader.
///
/// Two consequences worth knowing before measuring a frame. The block grid is
/// anchored at the TEXTURE origin and not at the region's corner, so blocks
/// inside a region are full-size and stable when the region moves while the
/// region's own edge cuts the blocks it crosses — measure "flat blocks of the
/// expected size" in a region's interior. And thirteen taps at a 24-pixel
/// radius is a SOFT blur; the shader's tap-count budget says why it is not
/// wider, and it is why a region's default kind is `pixelate`.
///
/// **Ranges.** The core already refuses anything out of range —
/// `check_video` in `props_check.rs` names the dotted key, `clamp_video` in
/// `actions_clamp.rs` bounds the action path — so the clamps here are not
/// validation. They are the last line between a recipe from some future
/// version and a garbage uniform, and they cost nothing.
extension LayerUniforms {

    /// The filter slots, in order. Anything past the fourth is dropped: the
    /// uniform block carries four (kind, amount) pairs and `MAX_FILTERS` in
    /// `model.rs` is four for exactly that reason, so a fifth filter could
    /// only be silently ignored either here or there.
    mutating func apply(filters: [FilterProps]) {
        for (index, filter) in filters.prefix(FilterProps.max).enumerated() {
            setFilter(
                index, kind: Float(filter.kind.shaderCode), amount: unit(filter.amount))
        }
    }

    /// The mirrored copy below the layer. This fills the numbers on BOTH
    /// draws — the layer's own and the reflection's — and leaves
    /// `reflectionPass` at 0; only `MetalRenderer.encodeReflection` raises it,
    /// which is what makes the extra draw the mirrored one.
    mutating func apply(reflection: ReflectionProps?) {
        guard let reflection = reflection else { return }
        reflectionOpacity = unit(reflection.opacity)
        reflectionHeight = unit(reflection.height)
        // Source pixels, like the crop it hangs below. Negative would push the
        // reflection up INTO the layer, which no control offers and the model
        // refuses (`video.reflection.gap` is `at_least` 0).
        reflectionGap = Float(max(reflection.gap, 0))
        reflectionFalloff = unit(reflection.falloff)
    }

    /// The spotlight region. Its centre and box are SOURCE pixels measured
    /// from the centre of the CROPPED rectangle, which is the frame the
    /// corner radius and the crop already use — so a spotlight stays over the
    /// same part of the picture when the layer is scaled, moved or rotated.
    mutating func apply(spotlight: SpotlightProps?) {
        guard let spotlight = spotlight else { return }
        spotEnabled = 1
        spotShape = spotlight.shape == .ellipse ? 1 : 0
        spotX = Float(spotlight.x)
        spotY = Float(spotlight.y)
        // The box is `above` zero in the core; the floor here keeps a
        // degenerate one from dividing by nothing in the ellipse's distance.
        spotW = Float(max(spotlight.width, 0.001))
        spotH = Float(max(spotlight.height, 0.001))
        spotFeather = Float(max(spotlight.feather, 0))
        spotDim = unit(spotlight.dim)
        // 1 is "no zoom", so the range starts there rather than at 0, and
        // stops at `SPOT_ZOOM_MAX` — past 2× the region is only softer,
        // because the pixels come from the same decoded frame either way.
        spotZoom = clamp(spotlight.zoom, 1, 2)
    }

    /// The obscured regions: up to four boxes on the layer whose contents are
    /// blurred or pixelated (phase 3c).
    ///
    /// The geometry is the spotlight's, field for field — SOURCE pixels
    /// measured from the centre of the CROPPED rectangle — so a region rides
    /// with its layer through scale, move and rotation and stays on the face
    /// it was put on. `apply(spotlight:)` above argues that frame; this is the
    /// same one, which is why the two share `SpotShape` and the shader shares
    /// one `regionMask`.
    ///
    /// Anything past the fourth is dropped, as a fifth filter is: the uniform
    /// block carries four region slots and `MAX_OBSCURE` is four for exactly
    /// that reason, so the core refuses a fifth by name and `clamp_video`
    /// truncates the evaluated path before this is ever reached.
    mutating func apply(obscure: [ObscureProps]) {
        guard !obscure.isEmpty else { return }
        obscureEnabled = 1
        for (index, region) in obscure.prefix(ObscureProps.max).enumerated() {
            setObscure(index, region)
        }
    }

    /// The rectangle a layer flattened out of a nest is clipped to.
    ///
    /// **CANVAS pixels, absolute, origin at the canvas's top-left corner, y
    /// down** — not the canvas-centre-relative frame a layer's own `x`/`y`
    /// use, and not source pixels. A nest clips its flattened layers to ITS
    /// canvas rectangle, and those layers each carry the nest clip's
    /// transform folded into their own (contract §4), so the canvas is the
    /// only frame all of them share.
    ///
    /// **It is NOT the space `[[position]]` arrives in**, which this comment
    /// claimed until phase 8d and which was true only while the destination
    /// was always the canvas. The fragment stage converts, through
    /// `LayerUniforms.canvasPerDestX` / `Y`; at Half a nest rendered as a
    /// rectangle magnified about the canvas origin and at Quarter it vanished.
    /// Nothing here changes for it — the rectangle is written in the frame the
    /// core emits it in, and the conversion is the shader's.
    mutating func apply(clipRect: RecipeClipRect?) {
        guard let clipRect = clipRect else { return }
        clipEnabled = 1
        clipX = Float(clipRect.x)
        clipY = Float(clipRect.y)
        clipW = Float(max(clipRect.w, 0))
        clipH = Float(max(clipRect.h, 0))
        clipRotation = Float(clipRect.rotation * .pi / 180)
    }

    /// Writes one slot. The four are separate scalars rather than an array
    /// because the layout contract admits nothing else, and neither language
    /// can index a struct's fields — so both sides spell the four out, this
    /// switch here and `filterSlot` in the shader.
    private mutating func setFilter(_ index: Int, kind: Float, amount: Float) {
        switch index {
        case 0:
            filterKind0 = kind
            filterAmount0 = amount
        case 1:
            filterKind1 = kind
            filterAmount1 = amount
        case 2:
            filterKind2 = kind
            filterAmount2 = amount
        default:
            filterKind3 = kind
            filterAmount3 = amount
        }
    }

    /// Writes one region slot, for the same reason `setFilter` above spells
    /// its four out: neither language can index a struct's fields, and the
    /// layout contract admits nothing but scalars. The shader's half is
    /// `obscureSlot`, and the eight assignments below are in the block's own
    /// order so the two read as the same list.
    ///
    /// The clamps are the last line between a recipe from some future version
    /// and a garbage uniform, not validation — `check_video` refuses these
    /// ranges by name and `clamp_video` bounds the action path. The floor on
    /// the box is the one that matters: a zero half-size divides by nothing in
    /// the ellipse's distance, exactly as it would for the spotlight.
    private mutating func setObscure(_ index: Int, _ region: ObscureProps) {
        let shape: Float = region.shape == .ellipse ? 1 : 0
        let x = Float(region.x)
        let y = Float(region.y)
        let w = Float(max(region.width, 0.001))
        let h = Float(max(region.height, 0.001))
        let feather = Float(max(region.feather, 0))
        let kind = Float(region.kind.shaderCode)
        let amount = unit(region.amount)
        switch index {
        case 0:
            obscure0Shape = shape
            obscure0X = x
            obscure0Y = y
            obscure0W = w
            obscure0H = h
            obscure0Feather = feather
            obscure0Kind = kind
            obscure0Amount = amount
        case 1:
            obscure1Shape = shape
            obscure1X = x
            obscure1Y = y
            obscure1W = w
            obscure1H = h
            obscure1Feather = feather
            obscure1Kind = kind
            obscure1Amount = amount
        case 2:
            obscure2Shape = shape
            obscure2X = x
            obscure2Y = y
            obscure2W = w
            obscure2H = h
            obscure2Feather = feather
            obscure2Kind = kind
            obscure2Amount = amount
        default:
            obscure3Shape = shape
            obscure3X = x
            obscure3Y = y
            obscure3W = w
            obscure3H = h
            obscure3Feather = feather
            obscure3Kind = kind
            obscure3Amount = amount
        }
    }
}

extension RecipeLayer {

    /// True when anything on this layer reaches for neighbouring pixels, and
    /// so needs the fragment stage compiled with the tap loop: a blur or
    /// sharpen filter, or an obscured region that blurs.
    ///
    /// It lives on the LAYER because the answer stopped being a property of
    /// the filter list the moment a region could blur. Both of the shader's
    /// gather sites are written `kGatherFilters && …`, so a region blur asked
    /// for on the plain pipeline does not blur — it renders the region
    /// untouched, with nothing logged.
    var needsGather: Bool {
        filters.needsGather || obscure.contains { $0.kind == .blur }
    }

    /// True when this layer must be drawn by the fragment stage that READS
    /// the destination — `framejob_layer_blend_fragment`, on a pipeline with
    /// fixed-function blending disabled (format version 6).
    ///
    /// `normal` is not merely the default here, it is the fast path: the
    /// general formula in `blendPremultiplied` reduces algebraically to the
    /// fixed-function factors at `normal`, so a layer that says `normal` gets
    /// exactly the pixels it always got, from exactly the pipeline it always
    /// used, and a project that has never heard of blend modes touches none
    /// of this. The recipe also arrives at `normal` for any layer inside a
    /// TRANSITION, which the core decides (`recipe.rs::layer`) — so this
    /// predicate needs no clause about overlaps either.
    var needsBlend: Bool {
        blend != .normal
    }

    /// The opacity this layer is DRAWN at, which the compositor reads
    /// wherever it read `opacity` (spec §11 W-16): `opacity`, times
    /// `1 − amount` when the source is a text page whose pause dim is the
    /// layer's (`LayerRenderers.wordDim(of:reveal:)` — a timed page with no
    /// backdrop) and the amount is above 0. In every other case it is
    /// `opacity` ITSELF, returned and never multiplied by 1, so a layer with
    /// no dim reaches the shader with the bits it always had.
    var drawnOpacity: Double {
        guard case .text(_, let props, let reveal) = source else { return opacity }
        let dim = LayerRenderers.wordDim(of: props, reveal: reveal)
        guard dim.onLayer, dim.amount > 0 else { return opacity }
        return opacity * (1 - dim.amount)
    }
}

extension Collection where Element == FilterProps {

    /// True when any filter in the list reaches for neighbouring pixels, and
    /// so needs the fragment stage compiled with the tap loop.
    ///
    /// Pixelate is NOT one of them: it moves the sampling coordinate but still
    /// takes a single sample, so it costs the plain pipeline nothing to carry
    /// and measures the same as no filter at all.
    var needsGather: Bool {
        contains { $0.kind == .blur || $0.kind == .sharpen }
    }
}

extension MetalRenderer {

    /// A layer fragment stage, specialized on `kGatherFilters`.
    ///
    /// The shader declares that constant with no default, which means the
    /// UNSPECIALIZED function cannot build a pipeline at all — Metal refuses
    /// it at validation. So this is the only way a layer fragment function is
    /// ever made, and all FOUR of the renderer's layer pipelines come through
    /// here: two entry points × two specializations.
    ///
    /// `name` defaults to the plain entry point rather than being required,
    /// because the gather flag is the axis that has always been here and the
    /// blend entry point is the exception; the two call sites that want it
    /// name it, which is also what makes them findable.
    static func layerFragment(
        _ library: MTLLibrary, name: String = "framejob_layer_fragment", gather: Bool
    ) -> MTLFunction? {
        let values = MTLFunctionConstantValues()
        var flag = gather
        values.setConstantValue(&flag, type: .bool, index: 0)
        return try? library.makeFunction(name: name, constantValues: values)
    }

    /// A layer's reflection: ONE extra draw of the same pipeline, the same
    /// texture and the same uniform block, with `reflectionPass` raised —
    /// encoded into the destination immediately before the layer's own draw,
    /// so the mirrored copy ends up underneath it.
    ///
    /// **Why this is not an offscreen pass.** Everything a reflection needs is
    /// expressible in the vertex stage: the mirrored quad is the cropped
    /// rectangle, flipped about its own bottom edge, moved down by the gap and
    /// cut to `reflectionHeight`, and the sampling coordinate runs bottom-up
    /// across it. So the reflection is drawn from the source texture directly,
    /// with no intermediate to allocate, no encoder to suspend and resume, and
    /// — the part that matters — no second copy of the placement math that
    /// could drift out of step with the original. A shadow needs the offscreen
    /// texture because a blur cannot be done in one pass; a mirror can.
    ///
    /// The consequence to know: the reflection is a mirror of the LAYER, not
    /// of the composed frame under it, and it is drawn before the layer rather
    /// than after everything. A reflection therefore never picks up what sits
    /// on top of its own layer, which is the same trade every real-time
    /// reflection makes.
    ///
    /// **A reflection INHERITS its layer's blend mode** (format version 6),
    /// and that is the deliberate answer rather than the free one, though it
    /// happens to also be free: this draw uses whatever pipeline the caller
    /// has already bound, which is the layer's own. It is a mirror of the
    /// layer's ink, so it should meet the backdrop the way the ink does — a
    /// screened layer's reflection screens, a multiplied one multiplies. That
    /// is the opposite of the choice a SHADOW makes (`encodeShadow`), and the
    /// two are opposite for the same reason: a shadow is light falling on the
    /// backdrop and belongs to the scene, a reflection is the layer seen
    /// again and belongs to the layer.
    func encodeReflection(
        uniforms: LayerUniforms, texture: MTLTexture, encoder: MTLRenderCommandEncoder
    ) {
        // A reflection with no height or no opacity is a draw of nothing. The
        // shader would reach the same answer a few million fragments later.
        guard uniforms.reflectionOpacity > 0, uniforms.reflectionHeight > 0 else { return }
        var u = uniforms
        u.reflectionPass = 1
        // Never a shadow caster: `encodeShadow` has already drawn the layer's
        // own silhouette, and a second one from the mirrored quad would put a
        // shadow under the reflection, which no light does.
        u.shadowMask = 0
        encoder.setVertexBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// One recipe layer made ready to draw: its uniform block, with the
    /// source's size, premultiplication and orientation filled in, and the
    /// texture its fragment stage samples. nil is "draw nothing" — a layer
    /// with no drawn opacity, or a track with no frame at this time.
    func prepare(
        _ layer: RecipeLayer, among layers: [RecipeLayer], canvas: RecipeCanvas,
        destination: CGSize, request: AVAsynchronousVideoCompositionRequest,
        instruction: RecipeInstruction?, live: inout [CVMetalTexture]
    ) -> PreparedLayer? {
        let partner = layer.transition.flatMap { transition in
            layers.first { $0.clip == transition.partner }
        }
        guard
            var uniforms = self.uniforms(
                for: layer, canvas: canvas, destination: destination, partner: partner)
        else { return nil }
        let texture: MTLTexture
        switch source(for: layer, request: request, instruction: instruction, live: &live) {
        case .textured(let resolved, let size, let premultiplied, let orientation):
            texture = resolved
            uniforms.sourceWidth = Float(size.width)
            uniforms.sourceHeight = Float(size.height)
            uniforms.premultiplied = premultiplied ? 1 : 0
            uniforms.sourceQuarterTurns = Float(orientation & 3)
            uniforms.sourceMirrored = orientation & 4 != 0 ? 1 : 0
        case .slate(let size):
            texture = placeholder
            uniforms.sourceWidth = Float(size.width)
            uniforms.sourceHeight = Float(size.height)
            uniforms.slate = 1
        case .absent:
            // A composition track with no frame at this time: a gap, not
            // an error. Nothing to draw.
            return nil
        }
        // The look's lattice (GR-7, GR-8): a LUT's file is found through the
        // URLs its document last published, never the instruction's alone. A
        // look that cannot be drawn — a LUT missing or refused — draws the
        // layer ungraded, with `lookEnabled` 0 and the placeholder bound.
        let urls = layer.look?.media == nil ? [:] : RecipeSource.shared.lookURLs(for: instruction)
        let look = looks.lattice(for: layer.look, urls: urls)
        if look == nil { uniforms.lookEnabled = 0 }
        // The curves' strip (GR-12, GR-32): the placeholder for none — or for
        // a strip that could not be uploaded, which draws the layer uncurved,
        // tone and hue alike.
        let curves = looks.curves.texture(for: layer.curves)
        if curves === looks.curves.placeholder {
            uniforms.curvesEnabled = 0
            uniforms.hueCurvesEnabled = 0
        }
        return PreparedLayer(
            uniforms: uniforms, texture: texture, look: look ?? looks.placeholder, curves: curves)
    }

    /// True only when the buffer's `kCVImageBufferAlphaChannelModeKey`
    /// attachment equals `kCVImageBufferAlphaChannelMode_PremultipliedAlpha`;
    /// absent or anything else is straight (spec §11 G-35 (b)). Asked of each
    /// video frame, so a premultiplied movie — another app's, or an
    /// `hevc_alpha` export from before G-35 — is divided by its alpha once,
    /// in `layerSample`, and an unlabelled one draws as it always did.
    static func declaresPremultipliedAlpha(_ buffer: CVPixelBuffer) -> Bool {
        guard let mode = CVBufferCopyAttachment(buffer, kCVImageBufferAlphaChannelModeKey, nil)
        else { return false }
        return CFEqual(mode, kCVImageBufferAlphaChannelMode_PremultipliedAlpha)
    }
}

/// What `MetalRenderer.prepare` hands `render`: a layer's uniform block,
/// the texture it samples, its look's lattice and its curves' strip (each
/// the placeholder for none).
struct PreparedLayer {
    var uniforms: LayerUniforms
    let texture: MTLTexture
    let look: MTLTexture
    let curves: MTLTexture
}

/// `value` into 0…1 as a `Float`. Spelled out once because the effect block
/// clamps a dozen fractions and `Float(min(max(x, 0), 1))` twelve times over
/// hides which of them are fractions and which are not.
private func unit(_ value: Double) -> Float {
    Float(min(max(value, 0), 1))
}

/// The same, for a range that is not 0…1.
private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Float {
    Float(min(max(value, lower), upper))
}
