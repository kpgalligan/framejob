import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `render_frame`'s image block: what the model sees, which is a COPY of the file the tool
/// writes (spec §11 PR-22, #604).
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
/// `fullDepth` (`full_depth_image: true`) puts the file's own bytes in the block whatever it is.
/// It chooses the block only: the file's depth is never an argument (PR-4, PR-9).
///
/// Pure: no AppKit, no document and no file read here. The caller hands in the frame and the
/// file's bytes, so the block and the file cannot be two different frames.
enum FrameBlock {

    /// The block's bytes and `mimeType`, and the sentence the text gains before its last: nil
    /// when the block is the file's bytes, so a call that answered the file answers the text it
    /// always did.
    struct Block {
        let data: Data
        let mimeType: String
        let note: String?
    }

    /// The block for `image`, written as `format` to a file whose bytes are `file`. A copy that
    /// cannot be made leaves the file's bytes in the block: a copy never fails the tool.
    static func block(
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

    /// `labelled` drawn at its own size into an 8-bit premultiplied RGBA bitmap in its own
    /// colour space (BT.709, or an HLG project's BT.2100 HLG: the space the file is labelled
    /// in, so the draw rounds and converts nothing else), with no interpolation, and encoded PNG
    /// with no properties (`FrameWriter`'s PNG rule); nil when the bitmap or the encode cannot
    /// be made. The same size as the file, so `max_width` bounds both.
    static func eightBitPNG(_ labelled: CGImage) -> Data? {
        let space: CGColorSpace = {
            if let own = labelled.colorSpace, own.model == .rgb { return own }
            return CGColorSpaceCreateDeviceRGB()
        }()
        guard labelled.width > 0, labelled.height > 0,
            let context = CGContext(
                data: nil, width: labelled.width, height: labelled.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(
            labelled, in: CGRect(x: 0, y: 0, width: labelled.width, height: labelled.height))
        let data = NSMutableData()
        guard let eight = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, eight, nil)
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
