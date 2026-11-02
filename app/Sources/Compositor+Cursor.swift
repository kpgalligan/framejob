import Metal

// The cursor drawn as part of its clip's layer (road map creator-jobs CU3a2, spec §11 CU-33,
// CU-37): the layer's uniform block's cursor group and the sprite bound at `texture(5)`, which
// `layerSample` composites over the source texel before the grade. Asks only `CursorTracks`'
// `ready`, never waits: a track not landed yet draws the layer without its cursor (CU-37 (a)).
// Names no `rc_*` (CJ-8 (l)).

extension MetalRenderer {
    /// Fills `uniforms`' cursor block for `layer` and answers the texture for `texture(5)`:
    /// the sprite, or `placeholder` when no sprite is drawn. A layer with no `cursor`, a key that
    /// published no cursor files (CU-37 (d)), a track not ready, a state the core refuses, or a
    /// frame with neither a sprite nor a ripple leaves `cursorEnabled` 0, so it draws exactly what
    /// it drew before (CU-33 (h)).
    func cursorSprite(
        for layer: RecipeLayer, instruction: RecipeInstruction?, output: CanvasOutput,
        uniforms: inout LayerUniforms
    ) -> MTLTexture {
        guard let cursor = layer.cursor,
              let file = RecipeSource.shared.cursorFiles(for: instruction)[cursor.media],
              let track = CursorTracks.shared.ready(url: file.url, smoothing: cursor.smoothing)
        else { return placeholder }
        let props = cursor.props
        let state: CursorState
        do {
            state = try track.state(
                at: Self.cursorTime(cursor, file: file),
                props: CursorStateProps(
                    smoothing: cursor.smoothing, hideIdle: cursor.hideIdle, scale: props.scale,
                    ripples: props.clicks == .ripple))
        } catch {
            return placeholder
        }
        var sprite = placeholder
        var drawsSprite = false
        // The recorded image (CU-33 (c)); Frame Job's arrow, and a null image's, are CU4's.
        if props.show, props.style == .recorded, state.visible, let image = state.image,
           let texture = cursorSprites.texture(
            track: track, id: image.id, output: output, lift: { self.lifted($0) })
        {
            sprite = texture
            drawsSprite = true
            uniforms.cursorX = Float(state.x - image.hotX)
            uniforms.cursorY = Float(state.y - image.hotY)
            uniforms.cursorW = Float(image.w)
            uniforms.cursorH = Float(image.h)
            uniforms.cursorOpacity = Float(min(max(state.opacity, 0), 1))
        }
        // Ripples (CU-33 (d)): the core answers them newest first; drawn oldest first.
        let ripples = props.clicks == .ripple ? Array(state.ripples.prefix(4).reversed()) : []
        if !ripples.isEmpty {
            let slots: [(WritableKeyPath<LayerUniforms, Float>,
                         WritableKeyPath<LayerUniforms, Float>,
                         WritableKeyPath<LayerUniforms, Float>)] = [
                (\.ripple0X, \.ripple0Y, \.ripple0Phase), (\.ripple1X, \.ripple1Y, \.ripple1Phase),
                (\.ripple2X, \.ripple2Y, \.ripple2Phase), (\.ripple3X, \.ripple3Y, \.ripple3Phase),
            ]
            for (ripple, slot) in zip(ripples, slots) {
                uniforms[keyPath: slot.0] = Float(ripple.x)
                uniforms[keyPath: slot.1] = Float(ripple.y)
                uniforms[keyPath: slot.2] = Float(min(max(ripple.phase, 0), 1))
            }
            uniforms.rippleCount = Float(ripples.count)
            uniforms.rippleRadius = Float(24 * props.clickSize * state.pxPerPoint)
            let colour = Self.rippleColour(props.clickColor)
            // An HLG project lifts the ring's colour as it lifts every colour Frame Job
            // draws (CU-33 (e), HD-3); an SDR one draws it as stored.
            let rgb = output == .hlg ? InputConversions.liftSDR(colour.rgb) : colour.rgb
            uniforms.rippleR = rgb.x
            uniforms.rippleG = rgb.y
            uniforms.rippleB = rgb.z
            uniforms.rippleA = colour.alpha
        }
        guard drawsSprite || !ripples.isEmpty else { return placeholder }
        uniforms.cursorEnabled = 1
        return sprite
    }

    /// The source tick the cursor file is read at (CU-33 (f)): the recipe's `at` forward; for
    /// a reversed clip the forward stamp of the frame shown, `pivot − at − frame`, at least 0.
    static func cursorTime(_ cursor: RecipeCursor, file: CursorFile) -> Ticks {
        guard cursor.reversed else { return cursor.at }
        return max(0, ReverseMirror.mirrored(cursor.at, about: file.pivot) - file.frame)
    }

    /// The recipe's normalised `#rrggbb` or `#rrggbbaa` as straight RGBA in 0…1; anything else
    /// is `#ffffffcc`, the default (CU-30).
    static func rippleColour(_ text: String) -> (rgb: SIMD3<Float>, alpha: Float) {
        let fallback = (rgb: SIMD3<Float>(1, 1, 1), alpha: Float(0xcc) / 255)
        guard text.hasPrefix("#") else { return fallback }
        let hex = text.dropFirst()
        guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else {
            return fallback
        }
        let full = hex.count == 8 ? value : (value << 8) | 0xff
        func channel(_ shift: UInt32) -> Float { Float((full >> shift) & 0xff) / 255 }
        return (SIMD3<Float>(channel(24), channel(16), channel(8)), channel(0))
    }
}
