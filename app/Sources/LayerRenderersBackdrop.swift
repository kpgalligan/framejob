import Accelerate
import AppKit

/// A text page's BACKDROP, and the one multiply a timed page's dim is
/// (issue batch B93 phase 3, spec §11 W-17).
///
/// A backdrop is a rounded rect the size of the box, and most of its pixels
/// are covered completely: the CROSS of the rows clear of the corners by
/// every whole column, and every whole row by the columns clear of them.
/// Those are written by vImage with the bytes CoreGraphics itself writes for
/// the colour at full coverage (`fullCoverageBytes`), which is what makes a
/// static page's backdrop the whole-path fill to the byte; CoreGraphics
/// draws the rest — the corners and any partly covered row or column —
/// clipped to the bitmap less the cross. Over an empty pixel the flatten is
/// exactly those bytes; under the words of a timed page (`under`) it is
/// source-over with the backdrop below, as `destinationOver` is.
///
/// `scaleBitmap` is a dim: every premultiplied byte of the bitmap times
/// one factor, which is one opacity over everything drawn so far.
extension LayerRenderers {

    /// Draws `backdrop` into the box of `size` of an EMPTY context, or UNDER
    /// what the context already holds when `under` is set (`textBitmap` on a
    /// timed page). Without `under` the flattened interior would land under
    /// anything already there while CoreGraphics' edge lands over it.
    static func drawBackdrop(
        _ backdrop: BackdropProps, size: CGSize, under: Bool, in context: CGContext
    ) {
        let rect = CGRect(origin: .zero, size: size)
        let radius = min(CGFloat(backdrop.radius), min(size.width, size.height) / 2)
        let path = CGPath(
            roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let blend: CGBlendMode = under ? .destinationOver : .normal
        guard let data = context.data, let bytes = fullCoverageBytes(backdrop.color) else {
            context.saveGState()
            context.setBlendMode(blend)
            context.addPath(path)
            context.setFillColor(backdrop.color.nsColor.cgColor)
            context.fillPath()
            context.restoreGState()
            return
        }
        let width = context.width
        let height = context.height
        // The cross, in pixel indices of CoreGraphics' y-up space, each half
        // clamped to the bitmap: `rows` by every whole column, and every
        // whole row by `columns`.
        let whole = (x: clamp(Int(size.width.rounded(.down)), width),
                     y: clamp(Int(size.height.rounded(.down)), height))
        let bottom = clamp(Int(radius.rounded(.up)), height)
        let top = clamp(Int((size.height - radius).rounded(.down)), height)
        let left = clamp(Int(radius.rounded(.up)), width)
        let right = clamp(Int((size.width - radius).rounded(.down)), width)
        let rows = bottom..<max(top, bottom)
        let columns = left..<max(right, left)

        // The cross flattened in place: the full-width band once, then the
        // column band above and below it, so no pixel is flattened twice.
        let background = [bytes.0, bytes.1, bytes.2, bytes.3]
        let base = data.assumingMemoryBound(to: UInt8.self)
        let flatten = { (band: Range<Int>, span: Range<Int>) in
            guard !band.isEmpty, !span.isEmpty else { return }
            // Memory row 0 is the TOP row: y-up row `j` is memory row
            // `height − 1 − j`.
            let first = height - band.upperBound
            var buffer = vImage_Buffer(
                data: base + first * context.bytesPerRow + span.lowerBound * 4,
                height: vImagePixelCount(band.count), width: vImagePixelCount(span.count),
                rowBytes: context.bytesPerRow)
            _ = withUnsafeMutablePointer(to: &buffer) { pointer in
                vImageFlatten_RGBA8888(
                    pointer, pointer, background, true, vImage_Flags(kvImageNoFlags))
            }
        }
        flatten(rows, 0..<whole.x)
        flatten(0..<min(rows.lowerBound, whole.y), columns)
        flatten(max(rows.upperBound, 0)..<whole.y, columns)

        // The rest of the path, by CoreGraphics: an even-odd clip of the
        // bitmap, both halves of the cross and their overlap is the bitmap
        // less the cross.
        let horizontal = CGRect(
            x: 0, y: rows.lowerBound, width: whole.x, height: rows.count)
        let vertical = CGRect(
            x: columns.lowerBound, y: 0, width: columns.count, height: whole.y)
        context.saveGState()
        context.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.addRect(horizontal)
        context.addRect(vertical)
        context.addRect(horizontal.intersection(vertical))
        context.clip(using: .evenOdd)
        context.setBlendMode(blend)
        context.addPath(path)
        context.setFillColor(backdrop.color.nsColor.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private static func clamp(_ value: Int, _ limit: Int) -> Int {
        min(max(value, 0), limit)
    }

    /// The B, G, R and A bytes CoreGraphics writes when it fills one pixel of
    /// a `LayerRenderers.bitmap` with `color` — the colour space's conversion
    /// and the premultiply, read rather than redone. Nil when no such bitmap
    /// could be made.
    static func fullCoverageBytes(_ color: RGBA) -> (UInt8, UInt8, UInt8, UInt8)? {
        guard let pixel = bitmap(CGSize(width: 1, height: 1)), let data = pixel.data else {
            return nil
        }
        pixel.setFillColor(color.nsColor.cgColor)
        pixel.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// Every byte of the context's memory times `factor` (0…1), in place —
    /// one opacity over everything the bitmap holds, since its pixels are
    /// premultiplied. In 1/4096ths, rounded. False, and nothing done, for a
    /// context with no memory.
    @discardableResult
    static func scaleBitmap(_ context: CGContext, by factor: Double) -> Bool {
        guard let data = context.data else { return false }
        let scale = Int16((min(max(factor, 0), 1) * 4096).rounded())
        let matrix: [Int16] = [
            scale, 0, 0, 0,
            0, scale, 0, 0,
            0, 0, scale, 0,
            0, 0, 0, scale,
        ]
        let bias: [Int32] = [2048, 2048, 2048, 2048]
        var buffer = vImage_Buffer(
            data: data, height: vImagePixelCount(context.height),
            width: vImagePixelCount(context.bytesPerRow / 4), rowBytes: context.bytesPerRow)
        _ = withUnsafeMutablePointer(to: &buffer) { pointer in
            vImageMatrixMultiply_ARGB8888(
                pointer, pointer, matrix, 4096, nil, bias, vImage_Flags(kvImageNoFlags))
        }
        return true
    }
}
