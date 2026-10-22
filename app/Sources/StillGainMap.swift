import CoreGraphics
import Foundation
import ImageIO

/// A still with an HDR gain map (spec §11 HD-22, #322): an iPhone HDR photo,
/// or any HEIC whose first image carries an ISO 21496-1 or Apple HDR gain map
/// over an SDR base no HDR label claims (`StillColor` answers nil for it).
///
/// In an HLG project only, `LayerRenderers` draws such a still from ImageIO's
/// HDR decode instead of its base: the rendition, in 16-bit-float
/// extended-linear BT.2020 with 1.0 at the base's white (203 cd/m², BT.2408,
/// HD-3's SDR white), the full gain applied, then encoded here to SMPTE ST
/// 2084 PQ and run through step 0's `.pq(.bt2020)` arm at the rendition's
/// own peak. In an SDR project, and in every thumbnail, the base is drawn as
/// before (HD-22 (d)).
///
/// M2 (HD-22 (a)) measured the decode: `decodeHDR` is today's still decode
/// (`MediaCacheFiles.decodeImage`: ImageIO's thumbnail with the transform,
/// bounded) plus `kCGImageSourceDecodeToHDR`, the only route that both bounds
/// and orients the rendition, so neither is redone by hand.
enum StillGainMap {
    /// Whether the still at `url` carries a gain map: its first image answers
    /// the ISO 21496-1 or the Apple HDR gain-map lookup. False for an
    /// unreadable file. A header read; no pixel is decoded.
    static func hasGainMap(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return [kCGImageAuxiliaryDataTypeISOGainMap, kCGImageAuxiliaryDataTypeHDRGainMap]
            .contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }
    }

    /// The still's HDR rendition, decoded as every still is (its longest side
    /// at most `maxPixelSize`, its EXIF orientation applied) with the gain map
    /// applied; nil unless `hasGainMap`.
    static func decodeHDR(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard hasGainMap(at: url),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR,
        ]
        if maxPixelSize > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A 16-bit-float premultiplied RGBA bitmap context in extended-linear
    /// BT.2020, where 1.0 is SDR white and a highlight runs above it; its bytes
    /// are `rgba16Float`'s. `LayerRenderers.bitmap`'s size guard.
    static func linearBitmap(_ size: CGSize) -> CGContext? {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let side = LayerRenderers.maxTextureSide
        guard width > 0, height > 0, width <= side, height <= side,
            let linear = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
        else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
            space: linear,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue)
    }

    /// Encodes a `linearBitmap` to PQ in place (HD-22 (b)): each pixel
    /// un-premultiplied (alpha 0 stays 0), each channel floored at 0, taken
    /// to cd/m² with 1.0 at `pqReferenceWhite` (at most 10,000) and encoded by
    /// SMPTE ST 2084, then premultiplied again; alpha is kept. Rows are split
    /// over `concurrentPerform` as `ExportStraightAlpha` splits them. Answers
    /// the rendition's peak: its brightest channel × 203, rounded up, clamped
    /// to 1…10,000 cd/m².
    static func encodePQ(_ context: CGContext) -> UInt32 {
        guard let data = context.data, context.bitsPerComponent == 16,
            context.bitsPerPixel == 64
        else { return 1 }
        let width = context.width, height = context.height
        let bytesPerRow = context.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let chunk = ExportStraightAlpha.chunk(height)
        let chunks = (height + chunk - 1) / chunk
        // Each chunk's brightest channel, written by that chunk alone.
        let tops = UnsafeMutablePointer<Float>.allocate(capacity: chunks)
        tops.initialize(repeating: 0, count: chunks)
        defer { tops.deallocate() }
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            var top: Float = 0
            for y in index * chunk..<min(height, (index + 1) * chunk) {
                let row = UnsafeMutableRawPointer(pixels + y * bytesPerRow)
                    .assumingMemoryBound(to: Float16.self)
                for x in 0..<width {
                    let texel = row + x * 4
                    let alpha = Float(texel[3])
                    guard alpha > 0 else { continue }
                    for c in 0..<3 {
                        let v = max(Float(texel[c]) / alpha, 0)
                        top = max(top, v)
                        let nits = min(v * InputConversions.pqReferenceWhite, 10_000)
                        texel[c] = Float16(InputConversions.pqSignal(nits: nits) * alpha)
                    }
                }
            }
            tops[index] = top
        }
        let brightest = (0..<chunks).reduce(Float(0)) { max($0, tops[$1]) }
        return UInt32(min(max((brightest * 203).rounded(.up), 1), 10_000))
    }
}
