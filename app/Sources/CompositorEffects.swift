import Metal

/// The M3 effect block of `LayerUniforms`: filters, reflection, spotlight and
/// the nest clip rectangle (spec §4.2, §7.3), plus the one extra draw a
/// reflection needs.
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
/// **Ranges.** The core already refuses anything out of range —
/// `check_video` in `edit_props.rs` names the dotted key, `clamp_video` in
/// `actions.rs` bounds the action path — so the clamps here are not
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

    /// The rectangle a layer flattened out of a nest is clipped to.
    ///
    /// **CANVAS pixels, absolute, origin at the canvas's top-left corner, y
    /// down** — not the canvas-centre-relative frame a layer's own `x`/`y`
    /// use, and not source pixels. A nest clips its flattened layers to ITS
    /// canvas rectangle, and those layers each carry the nest clip's
    /// transform folded into their own (contract §4), so the canvas is the
    /// only frame all of them share. It is also the space `[[position]]`
    /// arrives in, so the shader's test needs no conversion at all.
    ///
    /// Nothing sets this yet: `evaluate.rs` emits `null` for every layer until
    /// nests land. It is implemented now because a half-implemented clip is
    /// worse than none — a nest that drew outside its own canvas would look
    /// like a compositor bug rather than a missing feature.
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

    /// The layer fragment stage, specialized on `kGatherFilters`.
    ///
    /// The shader declares that constant with no default, which means the
    /// UNSPECIALIZED function cannot build a pipeline at all — Metal refuses
    /// it at validation. So this is the only way the fragment function is ever
    /// made, and both of the renderer's layer pipelines come through here.
    static func layerFragment(_ library: MTLLibrary, gather: Bool) -> MTLFunction? {
        let values = MTLFunctionConstantValues()
        var flag = gather
        values.setConstantValue(&flag, type: .bool, index: 0)
        return try? library.makeFunction(
            name: "reelcut_layer_fragment", constantValues: values)
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
