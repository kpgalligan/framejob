import AVFoundation
import CoreVideo
import Metal

extension MetalRenderer {
    // MARK: - Sources

    enum LayerSource {
        /// Texture, its source size in the layer's own space, whether it is
        /// premultiplied, and the source orientation code (0 for everything
        /// this app rasterized itself).
        case textured(MTLTexture, CGSize, premultiplied: Bool, orientation: Int)
        case slate(CGSize)
        case absent
    }

    /// The layer's texture. In an HLG project (`output`, spec §11 HD-13 (f))
    /// a layer Frame Job drew — a still, text, a shape or a graphic — is its
    /// lift (`lifted`); a video track's frame was converted at step 0, and the
    /// missing-media slate is not lifted.
    func source(
        for layer: RecipeLayer, request: AVAsynchronousVideoCompositionRequest,
        instruction: RecipeInstruction?, live: inout [CVMetalTexture], output: CanvasOutput
    ) -> LayerSource {
        func lifting(_ texture: MTLTexture, _ size: CGSize) -> LayerSource {
            guard output == .hlg else {
                return .textured(texture, size, premultiplied: true, orientation: 0)
            }
            guard let lifted = lifted(texture) else { return .absent }
            return .textured(lifted, size, premultiplied: true, orientation: 0)
        }
        switch layer.source {
        case .track(let id):
            // Step 0's converted texture when the frame needed one (spec §11
            // GR-15, `Compositor+Input.swift`); the frame's own otherwise.
            guard let buffer = request.sourceFrame(byTrackID: CMPersistentTrackID(id)),
                let texture = inputs.converted(trackID: id) ?? texture(from: buffer, live: &live)
            else {
                // No frame is a gap — unless the clip's FILE is gone, which
                // spec §5.6 draws as a slate. The core cannot see a
                // filesystem (`evaluate.rs`), so this is where the `missing`
                // source it would otherwise have emitted comes from.
                if instruction?.missingClips.contains(layer.clip) == true {
                    return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360))
                }
                return .absent
            }
            let orientation = instruction?.sourceOrientations[id] ?? 0
            // The recipe's `source_size` is the DISPLAY size, and the buffer
            // is the coded one: for a quarter-turned source the two are
            // transposed, and the fragment stage turns the sampling to match.
            let coded = CGSize(width: texture.width, height: texture.height)
            let size = layer.sourceSizeCG
                ?? (orientation & 1 != 0
                    ? CGSize(width: coded.height, height: coded.width) : coded)
            return .textured(
                texture, size, premultiplied: Self.declaresPremultipliedAlpha(buffer),
                orientation: orientation)
        case .image(let media):
            guard let url = instruction?.mediaURLs[media],
                let rendered = renderers.image(url: url, media: media)
            else { return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360)) }
            return lifting(rendered.texture, rendered.size)
        case .text(let hash, let props, let reveal):
            guard let rendered = renderers.text(props, hash: hash, reveal: reveal)
            else { return .absent }
            return lifting(rendered.texture, rendered.size)
        case .shape(let hash, let props):
            guard let rendered = renderers.shape(props, hash: hash) else { return .absent }
            return lifting(rendered.texture, rendered.size)
        case .graphic(let name, _, let frame, let props, let ctx):
            let size = layer.sourceSizeCG ?? CGSize(width: 640, height: 360)
            guard let drawn = renderers.graphic(name: name, frame: frame, propsJSON: props,
                ctxJSON: ctx, size: size, recipeKey: instruction?.recipeKey ?? 0) else { return .slate(size) }
            return lifting(drawn.texture, drawn.size)
        case .missing:
            return .slate(layer.sourceSizeCG ?? CGSize(width: 640, height: 360))
        case .adjustment: return .absent  // graded by `drawAdjustment`, never sampled
        }
    }

    /// Wraps a pixel buffer as a texture through the `CVMetalTextureCache` —
    /// zero-copy, because both sides are the same IOSurface — in the Metal
    /// format of the buffer's own pixel format; nil for one with none.
    func texture(from buffer: CVPixelBuffer, live: inout [CVMetalTexture]) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0,
            let format = Self.metalFormat(for: CVPixelBufferGetPixelFormatType(buffer))
        else { return nil }
        var wrapper: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, buffer, nil, format, width, height, 0,
            &wrapper)
        guard status == kCVReturnSuccess, let wrapper = wrapper,
            let texture = CVMetalTextureGetTexture(wrapper)
        else { return nil }
        live.append(wrapper)
        return texture
    }
}
