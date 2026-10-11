import CoreGraphics
import Metal

/// A layer's uniform block (§7.5): `uniforms(for:…)`, the partner box a
/// dissolving pair's correction reads, and the canvas background's clear
/// colour. Split out of `Compositor.swift` for size, as
/// `Compositor+Shadow.swift` and `Compositor+Matte.swift` were.
extension MetalRenderer {
    // MARK: - Uniforms

    /// The per-layer block. Placement is §5.3's rule expressed in the shader's
    /// terms: the anchor is the canvas centre plus (x, y) — `canvasAnchor` in
    /// `ProjectSnapshot.swift` computes the same point for the overlay — and
    /// the crop is applied in place around it.
    ///
    /// `destination` is the size of the buffer this frame is being drawn
    /// into, which is `AVVideoComposition.renderSize` and is the CANVAS's size
    /// on every path but one: `Playback.previewComposition` scales it for
    /// Preview Quality (phase 8a). The three fragment stages that measure a
    /// fragment in canvas pixels need the ratio to convert `[[position]]`, and
    /// `canvasPerDest*` is where they read it — see that pair in
    /// `LayerUniforms`. It is asked of the destination TEXTURE rather than of
    /// the recipe, because the texture is the thing `[[position]]` is actually
    /// in and no second opinion can drift from it.
    func uniforms(
        for layer: RecipeLayer, canvas: RecipeCanvas, destination: CGSize,
        partner: RecipeLayer? = nil
    ) -> LayerUniforms? {
        guard layer.drawnOpacity > 0 else { return nil }
        var u = LayerUniforms()
        u.canvasWidth = Float(max(1, canvas.width))
        u.canvasHeight = Float(max(1, canvas.height))
        u.canvasPerDestX = u.canvasWidth / Float(max(1, destination.width))
        u.canvasPerDestY = u.canvasHeight / Float(max(1, destination.height))
        u.anchorX = Float(Double(canvas.width) / 2 + layer.x)
        u.anchorY = Float(Double(canvas.height) / 2 + layer.y)
        u.scale = Float(max(layer.scale, 0.0001))
        u.rotation = Float(layer.rotation * .pi / 180)
        u.cropL = Float(max(0, layer.crop.l))
        u.cropT = Float(max(0, layer.crop.t))
        u.cropR = Float(max(0, layer.crop.r))
        u.cropB = Float(max(0, layer.crop.b))
        u.cornerRadius = Float(max(0, layer.cornerRadius))
        u.opacity = Float(min(max(layer.drawnOpacity, 0), 1))
        u.brightness = Float(layer.color.brightness)
        u.contrast = Float(layer.color.contrast)
        u.saturation = Float(layer.color.saturation)
        u.hue = Float(layer.color.hue * .pi / 180)
        u.apply(tone: layer.color)
        u.apply(wheels: layer.wheels)
        u.apply(curves: layer.curves)
        u.apply(look: layer.look)
        if let chroma = layer.chroma {
            u.chromaEnabled = 1
            u.chromaKeyR = Float(chroma.key.count > 0 ? chroma.key[0] : 0)
            u.chromaKeyG = Float(chroma.key.count > 1 ? chroma.key[1] : 1)
            u.chromaKeyB = Float(chroma.key.count > 2 ? chroma.key[2] : 0)
            u.chromaTolerance = Float(max(0, chroma.tolerance))
            u.chromaSoftness = Float(max(0, chroma.softness))
            u.chromaSpill = Float(min(max(chroma.spill, 0), 1))
        }
        // How this layer combines with what is already on the canvas (format
        // version 6). One line, and NO transition special case: the CORE
        // already emitted `normal` for any layer inside an overlap
        // (`recipe.rs::layer`), so by the time a recipe reaches here the
        // question is settled. A reader who knows about the dissolve's weight
        // divisor — which is the algebraic inverse of a fixed-function
        // destination factor and which any programmable blend would
        // invalidate — will come looking for the guard right here; it is one
        // layer down, in the description every renderer reads, so preview,
        // `render_frame` and both export writers cannot disagree about it.
        // Adding a second opinion here would be a rule with two owners.
        u.blendMode = Float(layer.blend.shaderCode)
        // The M3 effect block and the obscured regions after it, all in
        // `CompositorEffects.swift`.
        u.apply(filters: layer.filters)
        u.apply(reflection: layer.reflection)
        u.apply(spotlight: layer.spotlight)
        u.apply(clipRect: layer.clipRect)
        u.apply(obscure: layer.obscure)
        if let transition = layer.transition {
            u.transitionKind = TransitionCode.code(transition.kind)
            u.transitionProgress = Float(min(max(transition.progress, 0), 1))
            u.transitionIncoming = transition.isIncoming ? 1 : 0
            let direction = TransitionCode.direction(transition.kind)
            u.transitionDirX = direction.x
            u.transitionDirY = direction.y
            if !transition.isIncoming, let partner = partner,
                let box = MetalRenderer.partnerBox(
                    partner, canvas: canvas, progress: transition.progress)
            {
                u.partnerMinX = Float(box.minX)
                u.partnerMinY = Float(box.minY)
                u.partnerMaxX = Float(box.maxX)
                u.partnerMaxY = Float(box.maxY)
                u.partnerAlpha = Float(min(max(partner.drawnOpacity, 0), 1))
            }
        }
        return u
    }

    /// The incoming half of a dissolving pair, as the canvas-space box the
    /// shader tests a fragment against (see `partnerAlpha` in
    /// `LayerUniforms`).
    ///
    /// nil — "assume it covers nothing", the conservative reading — whenever
    /// the box would not be the honest answer: a rotated or corner-rounded
    /// partner is not an axis-aligned rectangle, and a partner whose source
    /// size only the text renderer knows has no box here at all. The
    /// correction is then simply not applied and that pixel keeps the old
    /// behaviour, which is right for a partner that does not cover it.
    /// A clipped partner is refused for the same reason a rounded one is: the
    /// nest rectangle cuts coverage the box would claim, and over-claiming is
    /// the one direction that shows — the outgoing layer would be brightened
    /// where nothing is coming in to darken it. A partner with a REFLECTION
    /// needs no such guard: a reflection only ever adds coverage below the
    /// box, so the box under-claims, which is the reading this function
    /// already returns nil to get.
    private static func partnerBox(
        _ partner: RecipeLayer, canvas: RecipeCanvas, progress: Double
    ) -> CGRect? {
        guard partner.rotation == 0, partner.cornerRadius == 0, partner.clipRect == nil,
            let size = partner.sourceSizeCG, size.width > 0, size.height > 0
        else { return nil }
        let anchor = CGPoint(
            x: Double(canvas.width) / 2 + partner.x, y: Double(canvas.height) / 2 + partner.y)
        var scale = partner.scale
        // A zoom transition scales the incoming layer in the VERTEX stage;
        // the box has to follow or it would claim cover the partner does not
        // have yet.
        if partner.transition?.kind == .zoom {
            scale *= 0.75 + 0.25 * min(max(progress, 0), 1)
        }
        let full = CGSize(width: size.width * scale, height: size.height * scale)
        let rect = CGRect(
            x: anchor.x - full.width / 2 + partner.crop.l * scale,
            y: anchor.y - full.height / 2 + partner.crop.t * scale,
            width: max(0, full.width - (partner.crop.l + partner.crop.r) * scale),
            height: max(0, full.height - (partner.crop.t + partner.crop.b) * scale))
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// The canvas background as a PREMULTIPLIED clear colour — the attachment
    /// holds premultiplied pixels, so a translucent background must be
    /// pre-scaled or the first layer blends against too much colour.
    func clearColor(_ rgba: RGBA) -> MTLClearColor {
        func component(_ index: Int) -> Double {
            index < rgba.count ? min(max(rgba[index], 0), 1) : (index == 3 ? 1 : 0)
        }
        let alpha = component(3)
        return MTLClearColor(
            red: component(0) * alpha, green: component(1) * alpha, blue: component(2) * alpha,
            alpha: alpha)
    }
}
