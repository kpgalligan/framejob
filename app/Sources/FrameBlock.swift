import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `render_frame`'s image block: what the model sees, which is a COPY of the file the tool
/// writes (spec §11 PR-22, #604), at the file's size and never scaled (PR-25, #618).
///
/// The file and the path it answers stay as deep as the frame (PR-9, PR-20, PR-21). The block
/// goes to a model API, which takes no HEIC and at most 5 MB of base64 an image on Amazon Bedrock
/// (10 MB on the Anthropic API, PR-24), and a 16-bit PNG of a 1080p frame of camera footage is
/// past the smaller. So, by the file written:
///
/// - a PNG of a frame of 8 bits a component: the file's bytes, as it always was;
/// - a PNG of a deeper frame, and a HEIC of any depth: an 8-bit PNG copy;
/// - a JPEG: the file's bytes (it holds 8 bits whatever it is handed).
///
/// No block is scaled or capped, on its bytes or its sides: it is the file's size, `max_width`'s
/// or the canvas's, so a 4K frame's can pass 5 MB and is sent as it is. `render_frame`'s
/// description names the API's limits and `max_width` is the caller's control (PR-24, PR-25,
/// the owner's choice).
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

    /// The block for `image`, written as `format` to a file whose bytes are `file` (PR-22): the
    /// file's bytes, or the 8-bit PNG copy, at the file's size whatever its size in bytes (PR-25).
    /// A copy that cannot be made leaves the file's bytes in the block: a copy never fails the
    /// tool.
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
    /// colour space (`drawSpace`: BT.709, or an HLG project's BT.2100 HLG, the space the file is
    /// labelled in, so the draw rounds and converts nothing else), with no interpolation, and
    /// encoded PNG with no properties (`FrameWriter`'s PNG rule); nil when the bitmap or the
    /// encode cannot be made. The same size as the file, so `max_width` bounds both.
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
