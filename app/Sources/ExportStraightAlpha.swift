import AVFoundation
import CoreVideo

// The alpha movie rows' frames written straight (spec §11 G-35, issue #242):
// `ExportWriter`'s video pump hands each frame of `prores_4444` and
// `hevc_alpha` here between the reader and `retimed`. The compositor's
// premultiplied 32BGRA is un-premultiplied in place, every transparent pixel
// within `bleedRadius` of a visible one takes that pixel's colour, and the
// buffer is labelled `StraightAlpha` and wrapped in a new sample.

/// The un-premultiply and the fill, over one frame (G-35 (c), (d)).
enum ExportStraightAlpha {

    /// Chebyshev pixels within which a transparent pixel takes a visible
    /// neighbour's colour (G-35 (d)): a codec that subsamples colour would
    /// otherwise average the black of a transparent pixel into the edge
    /// beside it.
    static let bleedRadius = 4

    /// The sample's 32BGRA image buffer straightened in place (below),
    /// attached `kCVImageBufferAlphaChannelModeKey` = `StraightAlpha`
    /// (`.shouldPropagate`), and wrapped in a NEW sample: its format
    /// description made from the buffer, the original's timing. nil when the
    /// buffer is not 32BGRA, cannot be locked, or the sample cannot be made.
    ///
    /// The buffer is the reader's own copy (`alwaysCopiesSampleData`, the
    /// output's default), so writing into it changes no other frame.
    static func straighten(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let buffer = CMSampleBufferGetImageBuffer(sample),
            CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
            !CVPixelBufferIsPlanar(buffer),
            CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess
        else { return nil }
        let base = CVPixelBufferGetBaseAddress(buffer)
        if let base = base {
            straighten(
                bgra: base, width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer),
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard base != nil else { return nil }
        CVBufferSetAttachment(
            buffer, kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_StraightAlpha, .shouldPropagate)
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &format) == noErr,
            let format = format
        else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        guard CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing) == noErr
        else { return nil }
        var straight: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &straight) == noErr
        else { return nil }
        return straight
    }

    /// The pure pixel half, over one premultiplied BGRA plane, in place.
    ///
    /// Pass 1, every pixel with a > 0: c' = min(255, (c·255 + a/2) / a) in
    /// integers — exact, since re-premultiplying with (s·a + 127) / 255
    /// gives c back for every c ≤ a (G-35 (c)). Pass 2, every pixel with
    /// a == 0 within Chebyshev `bleedRadius` of a pixel with a > 0 takes that
    /// pixel's (pass-1) colour, the smallest dx² + dy² winning and a tie
    /// going to the first in row-major order; its alpha stays 0. Every other
    /// a == 0 pixel is left as it was.
    ///
    /// Both passes are split by rows over `concurrentPerform`. Pass 2 reads
    /// only pixels with a > 0, which it never writes, so in place is
    /// race-free. A row whose band of rows within `bleedRadius` holds no
    /// visible pixel is skipped, and so is a pixel outside the band's
    /// visible columns widened by the radius.
    static func straighten(
        bgra: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int
    ) {
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return }
        let pixels = bgra.assumingMemoryBound(to: UInt8.self)
        // Each row's first and last visible column; `first > last` is none.
        let spans = UnsafeMutablePointer<Int>.allocate(capacity: height * 2)
        defer { spans.deallocate() }
        let chunk = Self.chunk(height)
        let chunks = (height + chunk - 1) / chunk
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            for y in index * chunk..<min(height, (index + 1) * chunk) {
                unpremultiply(row: pixels + y * bytesPerRow, width: width, span: spans + y * 2)
            }
        }
        let radius = bleedRadius
        guard radius > 0 else { return }
        let offsets = Self.offsets(radius)
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            for y in index * chunk..<min(height, (index + 1) * chunk) {
                fill(
                    y: y, pixels: pixels, width: width, height: height,
                    bytesPerRow: bytesPerRow, spans: spans, radius: radius, offsets: offsets)
            }
        }
    }

    // MARK: - The passes

    /// Rows per `concurrentPerform` iteration: about four per core, so a
    /// slow band does not hold the frame.
    private static func chunk(_ height: Int) -> Int {
        let pieces = max(1, ProcessInfo.processInfo.activeProcessorCount * 4)
        return max(1, (height + pieces - 1) / pieces)
    }

    /// Pass 1 over one row, recording its visible columns in `span`.
    private static func unpremultiply(
        row: UnsafeMutablePointer<UInt8>, width: Int, span: UnsafeMutablePointer<Int>
    ) {
        var first = width
        var last = -1
        for x in 0..<width {
            let pixel = row + x * 4
            let alpha = Int(pixel[3])
            guard alpha > 0 else { continue }
            if first == width { first = x }
            last = x
            let unpremultiplies = alpha < 255
            guard unpremultiplies else { continue }
            let half = alpha / 2
            for channel in 0..<3 {
                let value = (Int(pixel[channel]) * 255 + half) / alpha
                pixel[channel] = UInt8(min(255, value))
            }
        }
        span[0] = first
        span[1] = last
    }

    /// Pass 2 over row `y`: each transparent pixel near a visible one takes
    /// the nearest one's colour.
    private static func fill(
        y: Int, pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
        bytesPerRow: Int, spans: UnsafeMutablePointer<Int>, radius: Int,
        offsets: [(dx: Int, dy: Int)]
    ) {
        var low = width
        var high = -1
        for band in max(0, y - radius)...min(height - 1, y + radius) {
            low = min(low, spans[band * 2])
            high = max(high, spans[band * 2 + 1])
        }
        guard low <= high else { return }
        let row = pixels + y * bytesPerRow
        for x in max(0, low - radius)...min(width - 1, high + radius) {
            let pixel = row + x * 4
            guard pixel[3] == 0 else { continue }
            for offset in offsets {
                let nx = x + offset.dx
                let ny = y + offset.dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let near = pixels + ny * bytesPerRow + nx * 4
                guard near[3] > 0 else { continue }
                pixel[0] = near[0]
                pixel[1] = near[1]
                pixel[2] = near[2]
                break
            }
        }
    }

    /// Every offset within Chebyshev `radius` but the pixel itself, nearest
    /// first by dx² + dy², and among equals the first in row-major order
    /// (dy, then dx) — so the first visible one met is the one G-35 (d) names.
    private static func offsets(_ radius: Int) -> [(dx: Int, dy: Int)] {
        var all: [(dx: Int, dy: Int)] = []
        for dy in -radius...radius {
            for dx in -radius...radius where dx != 0 || dy != 0 {
                all.append((dx, dy))
            }
        }
        return all.sorted { a, b in
            let da = a.dx * a.dx + a.dy * a.dy
            let db = b.dx * b.dx + b.dy * b.dy
            if da != db { return da < db }
            return a.dy != b.dy ? a.dy < b.dy : a.dx < b.dx
        }
    }
}
