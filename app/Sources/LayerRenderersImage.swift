import AppKit
import Metal

/// The STILL half of `LayerRenderers`: the `image` entry point, the two
/// ways a decoded still is drawn (`renderImage`, `renderHDRImage`) and the
/// one 16-bit-float bitmap a still is drawn into (`halfFloatBitmap`, with its
/// layout `halfFloatBitmapInfo`).
///
/// A pure move out of `LayerRenderers.swift` (clean-up 3, #322's toll): the
/// draws are `private` here, which is where every caller of them is. The
/// bitmap and its layout are internal (#363): `StillGainMap.linearBitmap`
/// draws into the same bitmap, and `DeepStillFrame` and `WaveformAnalyzer`
/// read the same layout. The cache, `bitmap`, `upload` and `maxTextureSide`
/// stay with the type, as they do for `LayerRenderersText.swift`.
extension LayerRenderers {

    /// The texture for an `image` recipe layer, decoded with ImageIO and
    /// cached by path. Bounded by `maxTextureSide`: a 60-megapixel HEIC is
    /// scaled down once here rather than on every frame. An HLG or PQ still
    /// (`StillColor.read`) is drawn by `renderHDRImage`; when either answers
    /// nil — every SDR still, after a header read — today's lines run, so an
    /// HDR still is never drawn worse than before (spec §11 HD-19 (a)). In an
    /// HLG project (`output`) a still with a gain map is drawn from its HDR
    /// rendition by `renderGainMapImage` first (HD-22 (b)); every other still
    /// draws the same texture in both outputs, an HLG project's under its own
    /// key (`hlg:`, HD-22 (f)), and the SDR key is unchanged.
    func image(url: URL, media: UInt32, output: CanvasOutput) -> Rendered? {
        cached("image:" + (output == .hlg ? "hlg:" : "") + "\(media):" + url.path) {
            if let hdr = StillColor.read(url, maxPixelSize: LayerRenderers.maxTextureSide),
                let rendered = self.renderHDRImage(hdr.image, conversion: hdr.conversion)
            {
                return rendered
            }
            if output == .hlg,
                let hdr = StillGainMap.decodeHDR(url, maxPixelSize: LayerRenderers.maxTextureSide),
                let rendered = self.renderGainMapImage(hdr)
            {
                return rendered
            }
            guard let image = MediaImporter.decodeImage(
                url, maxPixelSize: LayerRenderers.maxTextureSide)
            else { return nil }
            return self.renderImage(image)
        }
    }

    /// A still drawn at its own size. A decoded image deeper than 8 bits a
    /// component (a 16-bit PNG or TIFF, a 10-bit HEIC) is drawn into a
    /// `halfFloatBitmap` in sRGB and uploaded `rgba16Float`, so its levels reach
    /// the 16-bit-float compositor (spec §11 PR-6); every other still takes the
    /// 8-bit path byte for byte.
    private func renderImage(_ image: CGImage) -> Rendered? {
        let size = CGSize(width: image.width, height: image.height)
        let deep = image.bitsPerComponent > 8
        if deep {
            let deepSpace = CGColorSpace(name: CGColorSpace.sRGB)
            guard size.width >= 1, size.height >= 1, let deepSpace,
                let context = LayerRenderers.halfFloatBitmap(size, space: deepSpace)
            else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return upload(context, size: size, pixelFormat: .rgba16Float)
        }
        guard size.width >= 1, size.height >= 1, let context = LayerRenderers.bitmap(size)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return upload(context, size: size)
    }

    /// An HLG or PQ still (spec §11 HD-19 (a)) drawn in its own colour space,
    /// so Core Graphics converts nothing and the bitmap holds the file's codes,
    /// into a `halfFloatBitmap` and uploaded `rgba16Float`, carrying its arm.
    private func renderHDRImage(_ image: CGImage, conversion: InputConversion) -> Rendered? {
        let size = CGSize(width: image.width, height: image.height)
        guard size.width >= 1, size.height >= 1, let space = image.colorSpace,
            let context = LayerRenderers.halfFloatBitmap(size, space: space)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard var rendered = upload(context, size: size, pixelFormat: .rgba16Float)
        else { return nil }
        rendered.conversion = conversion
        return rendered
    }

    /// A gain-map still's HDR rendition (spec §11 HD-22 (b)) drawn into
    /// `StillGainMap.linearBitmap` with no tone mapping (an EDR target headroom
    /// of 0), so the full gain lands above 1.0; encoded to PQ in place, uploaded
    /// `rgba16Float` and carrying step 0's `.pq(.bt2020)` arm and its own peak.
    private func renderGainMapImage(_ image: CGImage) -> Rendered? {
        let size = CGSize(width: image.width, height: image.height)
        guard size.width >= 1, size.height >= 1,
            let context = StillGainMap.linearBitmap(size)
        else { return nil }
        _ = context.setEDRTargetHeadroom(0)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        let peak = StillGainMap.encodePQ(context)
        guard var rendered = upload(context, size: size, pixelFormat: .rgba16Float)
        else { return nil }
        rendered.conversion = .pq(.bt2020)
        rendered.peak = peak
        return rendered
    }

    /// RGBA, 16-bit half float, premultiplied, little-endian: `rgba16Float`'s
    /// bytes and 64RGBAHalf's layout.
    static let halfFloatBitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGBitmapInfo.byteOrder16Little.rawValue

    /// A 16-bit-float premultiplied RGBA bitmap context (`halfFloatBitmapInfo`)
    /// in `space`: sRGB for a still deeper than 8 bits a component (spec §11
    /// PR-6), an HDR still's own space (HD-19 (a)), extended-linear BT.2020
    /// for a gain-map still's rendition (`StillGainMap.linearBitmap`, HD-22).
    /// The same size guard as `bitmap(_:)`.
    static func halfFloatBitmap(_ size: CGSize, space: CGColorSpace) -> CGContext? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0, width <= maxTextureSide, height <= maxTextureSide
        else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
            space: space, bitmapInfo: halfFloatBitmapInfo)
    }
}
