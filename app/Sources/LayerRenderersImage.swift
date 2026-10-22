import AppKit
import Metal

/// The STILL half of `LayerRenderers`: the `image` entry point, the two
/// ways a decoded still is drawn (`renderImage`, `renderHDRImage`) and the
/// two 16-bit-float bitmaps only a still uses (`deepBitmap`, `hdrBitmap`).
///
/// A pure move out of `LayerRenderers.swift` (clean-up 3, #322's toll): all
/// five members live in this one file, so nothing widened — `private` on an
/// extension member reaches its own file, which is where every caller of the
/// private four now is. The cache, `bitmap`, `upload` and `maxTextureSide`
/// stay with the type, as they do for `LayerRenderersText.swift`.
extension LayerRenderers {

    /// The texture for an `image` recipe layer, decoded with ImageIO and
    /// cached by path. Bounded by `maxTextureSide`: a 60-megapixel HEIC is
    /// scaled down once here rather than on every frame. An HLG or PQ still
    /// (`StillColor.read`) is drawn by `renderHDRImage`; when either answers
    /// nil — every SDR still, after a header read — today's lines run, so an
    /// HDR still is never drawn worse than before (spec §11 HD-19 (a)). The
    /// key is unchanged: the texture is the file's codes in both outputs.
    func image(url: URL, media: UInt32) -> Rendered? {
        cached("image:\(media):" + url.path) {
            if let hdr = StillColor.read(url, maxPixelSize: LayerRenderers.maxTextureSide),
                let rendered = self.renderHDRImage(hdr.image, conversion: hdr.conversion)
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
    /// component (a 16-bit PNG or TIFF, a 10-bit HEIC) is drawn into `deepBitmap` and
    /// uploaded `rgba16Float`, so its levels reach the 16-bit-float compositor
    /// (spec §11 PR-6); every other still takes the 8-bit path byte for byte.
    private func renderImage(_ image: CGImage) -> Rendered? {
        let size = CGSize(width: image.width, height: image.height)
        let deep = image.bitsPerComponent > 8
        if deep {
            guard size.width >= 1, size.height >= 1,
                let context = LayerRenderers.deepBitmap(size)
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
    /// into `hdrBitmap` and uploaded `rgba16Float`, carrying its arm.
    private func renderHDRImage(_ image: CGImage, conversion: InputConversion) -> Rendered? {
        let size = CGSize(width: image.width, height: image.height)
        guard size.width >= 1, size.height >= 1, let space = image.colorSpace,
            let context = LayerRenderers.hdrBitmap(size, space: space)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard var rendered = upload(context, size: size, pixelFormat: .rgba16Float)
        else { return nil }
        rendered.conversion = conversion
        return rendered
    }

    /// A 16-bit-float premultiplied RGBA bitmap context in sRGB, for a still
    /// deeper than 8 bits a component only (spec §11 PR-6); its bytes are
    /// `rgba16Float`'s. The same size guard as `bitmap(_:)`.
    private static func deepBitmap(_ size: CGSize) -> CGContext? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0, width <= maxTextureSide, height <= maxTextureSide,
            let deepSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
            space: deepSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue)
    }

    /// A 16-bit-float premultiplied RGBA bitmap context in an HDR still's own
    /// space (spec §11 HD-19 (a)); `deepBitmap`'s layout and size guard.
    private static func hdrBitmap(_ size: CGSize, space own: CGColorSpace) -> CGContext? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0, width <= maxTextureSide, height <= maxTextureSide
        else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
            space: own,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue)
    }
}
