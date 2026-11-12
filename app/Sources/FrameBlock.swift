import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `render_frame`'s image block: what the model sees, which is a COPY of the file the tool
/// writes (spec §11 PR-22, #604), drawn smaller when it would pass the API's limit (PR-23, #610).
///
/// The file and the path it answers stay as deep as the frame (PR-9, PR-20, PR-21). The block
/// goes to a model API, which takes at most 5 MB an image (Anthropic's: 5,242,880 bytes of
/// base64) and no HEIC, and a 16-bit PNG of a 1080p frame of camera footage is past that. So,
/// by the file written:
///
/// - a PNG of a frame of 8 bits a component: the file's bytes, as it always was;
/// - a PNG of a deeper frame, and a HEIC of any depth: an 8-bit PNG copy;
/// - a JPEG: the file's bytes (it holds 8 bits whatever it is handed).
///
/// Any of those whose base64 would still pass the limit (a 4K frame's can) is drawn smaller
/// until it fits, a PNG's as an 8-bit PNG and a JPEG's as a JPEG, and a sentence says to what
/// size (PR-23). The file is never scaled, and a block that fits is the one it always was.
///
/// `fullDepth` (`full_depth_image: true`) puts the file's own bytes in the block whatever it is
/// and whatever its size: it is never scaled. It chooses the block only: the file's depth is
/// never an argument (PR-4, PR-9).
///
/// Pure: no AppKit, no document and no file read here. The caller hands in the frame and the
/// file's bytes, so the block and the file cannot be two different frames.
enum FrameBlock {

    /// The block's bytes and `mimeType`, and the sentences the text gains before its last: nil
    /// when the block is the file's bytes at its own size, so a call that answered the file
    /// answers the text it always did.
    struct Block {
        let data: Data
        let mimeType: String
        let note: String?
    }

    /// The Anthropic API's limit on one image, in bytes of base64 (PR-22).
    static let limit = 5_242_880

    /// The most draws a scale makes before it answers the unscaled block (PR-23).
    static let attempts = 16

    /// The block for `image`, written as `format` to a file whose bytes are `file`: the unscaled
    /// block, or, when it would pass `limit` and `fullDepth` is false, the frame drawn smaller
    /// with the scale's sentence after the copy's. A scale that cannot be made leaves the
    /// unscaled block: a scale never fails the tool.
    static func block(
        of image: CGImage, format: FrameWriter.Format, file: Data, fullDepth: Bool
    ) -> Block {
        let whole = unscaled(of: image, format: format, file: file, fullDepth: fullDepth)
        guard !fullDepth, !fits(whole.data),
            let scaled = scaledDown(
                FrameWriter.labelled(image), as: scaledFormat(format), from: whole.data.count)
        else { return whole }
        return Block(
            data: scaled.data, mimeType: mimeType(scaledFormat(format)),
            note: [whole.note, scaleNote(width: scaled.width, height: scaled.height)]
                .compactMap { $0 }.joined(separator: " "))
    }

    /// The block at the frame's own size (PR-22): the file's bytes, or the 8-bit PNG copy. A
    /// copy that cannot be made leaves the file's bytes in the block: a copy never fails the
    /// tool.
    static func unscaled(
        of image: CGImage, format: FrameWriter.Format, file: Data, fullDepth: Bool
    ) -> Block {
        guard !fullDepth, copies(image, as: format),
            let copy = eightBitPNG(FrameWriter.labelled(image))
        else {
            return Block(data: file, mimeType: mimeType(format), note: nil)
        }
        return Block(data: copy, mimeType: mimeType(.png), note: note(for: format))
    }

    /// Whether the default block is a copy rather than the file: a PNG only of a frame deeper
    /// than 8 bits a component, a HEIC always (the API takes JPEG, PNG, GIF and WebP), a JPEG
    /// never.
    static func copies(_ image: CGImage, as format: FrameWriter.Format) -> Bool {
        switch format {
        case .png: return image.bitsPerComponent > 8
        case .heic: return true
        case .jpeg: return false
        }
    }

    /// The sentence a copy adds, naming what the file is.
    static func note(for format: FrameWriter.Format) -> String {
        format == .heic
            ? "The image here is an 8-bit PNG copy of the HEIC file."
            : "The image here is an 8-bit PNG copy of the 16-bit PNG file."
    }

    /// Whether `data`, sent as base64 (`base64EncodedString()` with no options: 4·⌈n/3⌉ bytes
    /// for n), is within `limit`. Exactly at it fits.
    static func fits(_ data: Data) -> Bool {
        4 * ((data.count + 2) / 3) <= limit
    }

    /// The format a scaled block is encoded as: a JPEG's a JPEG, as its file is; any other an
    /// 8-bit PNG, as the copy is (a HEIC's too: the API takes no HEIC).
    static func scaledFormat(_ format: FrameWriter.Format) -> FrameWriter.Format {
        format == .jpeg ? .jpeg : .png
    }

    /// The sentence a scaled block adds, after a copy's (PR-23).
    static func scaleNote(width: Int, height: Int) -> String {
        "The image here is scaled down to \(width)×\(height) px to fit the API's 5 MB image limit; "
            + "the file is not scaled."
    }

    /// `labelled` drawn smaller until its encode as `format` fits (PR-23). Each attempt's width
    /// is `w · min(0.9, 0.9·√(raw / b))`, `w` and `b` the last encode's width and bytes (first
    /// the frame's width and `bytes`, the unscaled block's) and `raw` the bytes whose base64 is
    /// `limit`; its height is `max_width`'s (`Exporter.scaledSize`: aspect kept, rounded, at
    /// least 1). Every attempt is measured, since a PNG's size is not monotonic in its scale.
    /// Nil when an encode cannot be made or `attempts` do not fit.
    static func scaledDown(
        _ labelled: CGImage, as format: FrameWriter.Format, from bytes: Int
    ) -> (data: Data, width: Int, height: Int)? {
        let full = CGSize(width: labelled.width, height: labelled.height)
        let raw = Double(limit / 4 * 3)
        var last = (bytes: bytes, width: labelled.width)
        for _ in 0..<attempts {
            let shrink = min(0.9, 0.9 * (raw / Double(max(last.bytes, 1))).squareRoot())
            let next = Int((Double(last.width) * shrink).rounded(.down))
            guard next >= 1 else { return nil }
            let size = Exporter.scaledSize(full, to: next)
            let width = Int(size.width)
            let height = Int(size.height)
            guard let data = eightBit(labelled, as: format, width: width, height: height)
            else { return nil }
            if fits(data) { return (data, width, height) }
            last = (data.count, width)
        }
        return nil
    }

    /// `labelled` drawn at `width` × `height` into an 8-bit bitmap in its own colour space
    /// (`drawSpace`) with high-quality interpolation (a downscale), and encoded as `format`
    /// (`encoded`): premultiplied RGBA for a PNG; for a JPEG an opaque bitmap filled black
    /// first, the file's flatten (`FrameWriter.write`). Nil when the bitmap or the encode cannot
    /// be made.
    static func eightBit(
        _ labelled: CGImage, as format: FrameWriter.Format, width: Int, height: Int
    ) -> Data? {
        let opaque = !format.carriesAlpha
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: drawSpace(of: labelled), bitmapInfo: alpha.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if opaque {
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(rect)
        } else {
            context.setBlendMode(.copy)
        }
        context.interpolationQuality = .high
        context.draw(labelled, in: rect)
        return encoded(context.makeImage(), as: format)
    }

    /// `labelled` drawn at its own size into an 8-bit premultiplied RGBA bitmap in its own
    /// colour space (`drawSpace`: BT.709, or an HLG project's BT.2100 HLG, the space the file is
    /// labelled in, so the draw rounds and converts nothing else), with no interpolation, and
    /// encoded PNG with no properties (`FrameWriter`'s PNG rule); nil when the bitmap or the
    /// encode cannot be made. The same size as the file, so `max_width` bounds both, until
    /// `block` scales it (PR-23).
    static func eightBitPNG(_ labelled: CGImage) -> Data? {
        guard labelled.width > 0, labelled.height > 0,
            let context = CGContext(
                data: nil, width: labelled.width, height: labelled.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: drawSpace(of: labelled),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(
            labelled, in: CGRect(x: 0, y: 0, width: labelled.width, height: labelled.height))
        return encoded(context.makeImage(), as: .png)
    }

    /// The space a block is drawn in: the labelled frame's own where it is an RGB one, so the
    /// draw converts nothing; device RGB for any other.
    static func drawSpace(of labelled: CGImage) -> CGColorSpace {
        if let own = labelled.colorSpace, own.model == .rgb { return own }
        return CGColorSpaceCreateDeviceRGB()
    }

    /// `image` encoded as `format` with `FrameWriter`'s properties for it (none for PNG, the
    /// quality for JPEG), or nil.
    static func encoded(_ image: CGImage?, as format: FrameWriter.Format) -> Data? {
        let data = NSMutableData()
        guard let image,
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, format.contentType.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, format.destinationProperties)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The `mimeType` of a file's bytes, read off the format's own `UTType` rather than switched
    /// over a second time: the block and the file are one decision, and a fourth container
    /// would arrive described correctly. All three carry one (measured: `image/png`,
    /// `image/jpeg`, `image/heic`); the fallback exists only because the API is optional, and it
    /// is generic rather than a guess, since telling a client a HEIC is a PNG is worse than
    /// telling it nothing.
    static func mimeType(_ format: FrameWriter.Format) -> String {
        format.contentType.preferredMIMEType ?? "application/octet-stream"
    }
}
