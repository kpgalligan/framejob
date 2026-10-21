import CoreGraphics
import Foundation
import ImageIO

/// An HDR still's step-0 arm (spec §11 HD-19 (a), #311): a still whose decoded
/// colour space is HLG- or PQ-based enters step 0 by that label, as an HLG or
/// PQ video does, instead of being drawn as SDR. `LayerRenderers` draws it in
/// its own space, its codes unconverted, and `source(for:…)` runs the arm on
/// the texture through `LayerLift` in either output. Every other still answers
/// nil here and takes today's path byte for byte.
///
/// M1 (HD-19 (a)) measured ImageIO's routes: today's still decode,
/// `MediaCacheFiles.decodeImage` (the thumbnail with its transform, bounded),
/// keeps an HLG or PQ PNG's, HEIC's and AVIF's space, depth and codes, and is
/// the only route that bounds and orients — so `read` is that decode, and
/// nothing here redoes either by hand.
enum StillColor {
    /// `.hlg(p)` for an HLG-based space, `.pq(p)` for a PQ-based one — p
    /// `.p3D65` for Display P3's, `.bt709` for ITU-R BT.709's, `.bt2020` for
    /// every other — and nil for every other space, or none.
    static func conversion(of space: CGColorSpace?) -> InputConversion? {
        guard let space else { return nil }
        let hlg = CGColorSpaceIsHLGBased(space)
        guard hlg || CGColorSpaceIsPQBased(space) else { return nil }
        let p = primaries(of: space.name)
        return hlg ? .hlg(p) : .pq(p)
    }

    /// The primaries a named HLG or PQ space carries.
    private static func primaries(of name: CFString?) -> InputPrimaries {
        guard let name else { return .bt2020 }
        if [CGColorSpace.displayP3_HLG, CGColorSpace.displayP3_PQ].contains(name) {
            return .p3D65
        }
        if [CGColorSpace.itur_709_HLG, CGColorSpace.itur_709_PQ].contains(name) {
            return .bt709
        }
        return .bt2020
    }

    /// The arm of the still at `url`, from its first image's colour space
    /// without decoding a pixel (`CGImageSourceCreateImageAtIndex` is lazy);
    /// nil for an SDR still or an unreadable file. The eyedropper's reading
    /// (`KeyReading.of(media:url:)`) and `read`'s first look.
    static func conversion(at url: URL) -> InputConversion? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return conversion(of: image.colorSpace)
    }

    /// An HDR still decoded as every still is (`MediaCacheFiles.decodeImage`:
    /// its longest side at most `maxPixelSize`, its EXIF orientation applied)
    /// with its arm; nil for an SDR still, which the lazy header read answers
    /// before any decode, so its one decode stays today's.
    static func read(_ url: URL, maxPixelSize: Int) -> (image: CGImage, conversion: InputConversion)? {
        guard conversion(at: url) != nil,
            let image = MediaImporter.decodeImage(url, maxPixelSize: maxPixelSize),
            let conversion = conversion(of: image.colorSpace)
        else { return nil }
        return (image, conversion)
    }
}
