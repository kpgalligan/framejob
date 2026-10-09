import AVFoundation
import CoreVideo

// What the video pump makes of the compositor's 64RGBAHalf frame before the
// encoder (spec §11 PR-3, amending G-35 (c)). `ExportWriter.frameForm` picks
// the form per row: `prores_4444`'s frame is straightened in place in float;
// `hevc_alpha`'s is rounded to 8-bit premultiplied BGRA first and then
// straightened by `ExportStraightAlpha.straighten(bgra:…)` unchanged, so that
// row's encoder input is what it was; `h264`'s and `hevc`'s are rounded the
// same way and neither straightened nor labelled. Every other row takes the frame as
// drawn.

/// Which conversion `ExportFrames` applies (`ExportWriter.frameForm`).
enum ExportFrameForm {
    /// Un-premultiplied in place in float, filled, labelled straight.
    case straightHalf
    /// Rounded into a pooled 32BGRA buffer, then straightened and labelled.
    case straightEightBit
    /// Rounded into a pooled 32BGRA buffer, nothing else.
    case eightBit
}

/// One export's frame conversion: a 64RGBAHalf sample in, a new sample with
/// the original's timing out. Used on the video pump's queue alone.
final class ExportFrames {
    let form: ExportFrameForm
    /// The 32BGRA buffers the two 8-bit forms draw into, made at the first
    /// frame's size and remade when the size changes.
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)

    init(form: ExportFrameForm) {
        self.form = form
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportFrames does not support NSCoder")
    }

    /// The sentence an export stops with when `convert` answers nil: G-35's
    /// for the two straight forms.
    var failure: String {
        form == .eightBit
            ? "A frame could not be rounded to 8 bits for the encoder."
            : "A frame's transparency could not be written straight."
    }

    /// The converted frame in a new sample, or nil when the frame is not
    /// 64RGBAHalf, cannot be locked, or no buffer or sample can be made.
    /// `.straightHalf` writes into the reader's own copy
    /// (`alwaysCopiesSampleData`), so no other frame changes.
    func convert(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sample),
            CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_64RGBAHalf,
            !CVPixelBufferIsPlanar(source)
        else { return nil }
        let buffer: CVPixelBuffer
        if form == .straightHalf {
            guard Self.locked(source, [], { base, bytesPerRow in
                ExportStraightAlpha.straighten(
                    half: base, width: CVPixelBufferGetWidth(source),
                    height: CVPixelBufferGetHeight(source), bytesPerRow: bytesPerRow)
            }) else { return nil }
            buffer = source
        } else {
            guard let rounded = eightBit(source) else { return nil }
            buffer = rounded
        }
        guard form != .eightBit else { return Self.wrap(buffer, timedAs: sample) }
        CVBufferSetAttachment(
            buffer, kCVImageBufferAlphaChannelModeKey,
            kCVImageBufferAlphaChannelMode_StraightAlpha, .shouldPropagate)
        return Self.wrap(buffer, timedAs: sample)
    }

    /// `source` rounded into a pooled 32BGRA buffer carrying its
    /// attachments, straightened when the form says so.
    private func eightBit(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0, let pool = pool(width: width, height: height) else {
            return nil
        }
        var made: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &made)
            == kCVReturnSuccess, let bgra = made
        else { return nil }
        CVBufferPropagateAttachments(source, bgra)
        let straight = form == .straightEightBit
        var written = false
        let read = Self.locked(source, .readOnly) { half, halfBytesPerRow in
            written = Self.locked(bgra, []) { base, bytesPerRow in
                ExportStraightAlpha.eightBit(
                    half: half, halfBytesPerRow: halfBytesPerRow, bgra: base,
                    bgraBytesPerRow: bytesPerRow, width: width, height: height)
                guard straight else { return }
                ExportStraightAlpha.straighten(
                    bgra: base, width: width, height: height, bytesPerRow: bytesPerRow)
            }
        }
        return read && written ? bgra : nil
    }

    private func pool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool = pool, poolSize == (width, height) { return pool }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var made: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault, nil, attributes as CFDictionary, &made) == kCVReturnSuccess
        else { return nil }
        pool = made
        poolSize = (width, height)
        return made
    }

    /// Runs `body` over `buffer`'s locked base address; false when it
    /// cannot be locked or has none (and `body` did not run).
    private static func locked(
        _ buffer: CVPixelBuffer, _ flags: CVPixelBufferLockFlags,
        _ body: (UnsafeMutableRawPointer, Int) -> Void
    ) -> Bool {
        guard CVPixelBufferLockBaseAddress(buffer, flags) == kCVReturnSuccess else {
            return false
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, flags) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        body(base, CVPixelBufferGetBytesPerRow(buffer))
        return true
    }

    /// `buffer` in a new sample: its format description made from the
    /// buffer, the original's timing.
    private static func wrap(_ buffer: CVPixelBuffer, timedAs sample: CMSampleBuffer)
        -> CMSampleBuffer?
    {
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
        var made: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &made) == noErr
        else { return nil }
        return made
    }
}

extension ExportStraightAlpha {

    /// Premultiplied RGBA in 16-bit float, alpha the fourth half. Visible
    /// when the alpha is not ±0 (its bits & 0x7FFF ≠ 0).
    enum RGBAHalf: StraightAlphaLayout {
        static var bytesPerPixel: Int { 8 }

        static func visible(_ pixel: UnsafePointer<UInt8>) -> Bool {
            UnsafeRawPointer(pixel).load(fromByteOffset: 6, as: UInt16.self) & 0x7FFF != 0
        }

        static func copyColour(_ from: UnsafePointer<UInt8>, _ to: UnsafeMutablePointer<UInt8>) {
            UnsafeMutableRawPointer(to).copyMemory(from: from, byteCount: 6)
        }

        static func allVisible(_ row: UnsafePointer<UInt8>, width: Int) -> Bool {
            let halves = UnsafeRawPointer(row).assumingMemoryBound(to: UInt16.self)
            var lowest = UInt16.max
            for x in 0..<width { lowest = min(lowest, halves[x * 4 + 3] & 0x7FFF) }
            return lowest > 0
        }
    }

    /// One premultiplied 64RGBAHalf plane straightened in place (PR-3):
    /// every visible pixel's colour becomes s = min(1, c / a) in float, then
    /// the one fill (G-35 (d)) runs over the half pixels. A pixel with a ≤ 0
    /// keeps its colour unless the fill gives it one; its alpha stays.
    static func straighten(
        half: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int
    ) {
        guard width > 0, height > 0, bytesPerRow >= width * 8 else { return }
        straighten(
            RGBAHalf.self, pixels: half.assumingMemoryBound(to: UInt8.self), width: width,
            height: height, bytesPerRow: bytesPerRow, unpremultiply: unpremultiplyHalf)
    }

    /// Pass 1 over one half-float row, recording its visible columns in
    /// `span`.
    private static func unpremultiplyHalf(
        row: UnsafeMutablePointer<UInt8>, width: Int, span: UnsafeMutablePointer<Int>
    ) {
        let halves = UnsafeMutableRawPointer(row).assumingMemoryBound(to: Float16.self)
        var first = width
        var last = -1
        for x in 0..<width where RGBAHalf.visible(row + x * 8) {
            if first == width { first = x }
            last = x
            let pixel = halves + x * 4
            let alpha = Float(pixel[3])
            for channel in 0..<3 {
                pixel[channel] = Float16(min(1, Float(pixel[channel]) / alpha))
            }
        }
        span[0] = first
        span[1] = last
    }

    /// One premultiplied 64RGBAHalf plane rounded into premultiplied 8-bit
    /// BGRA: each channel round(clamp(v, 0, 1) · 255), a tie rounding up —
    /// exact for every k/255. Split by rows over `concurrentPerform`.
    static func eightBit(
        half: UnsafeRawPointer, halfBytesPerRow: Int, bgra: UnsafeMutableRawPointer,
        bgraBytesPerRow: Int, width: Int, height: Int
    ) {
        guard width > 0, height > 0, halfBytesPerRow >= width * 8,
            bgraBytesPerRow >= width * 4
        else { return }
        let chunk = Self.chunk(height)
        let chunks = (height + chunk - 1) / chunk
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            for y in index * chunk..<min(height, (index + 1) * chunk) {
                let from = (half + y * halfBytesPerRow).assumingMemoryBound(to: Float16.self)
                let to = (bgra + y * bgraBytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    let pixel = from + x * 4
                    let out = to + x * 4
                    out[0] = level(pixel[2])
                    out[1] = level(pixel[1])
                    out[2] = level(pixel[0])
                    out[3] = level(pixel[3])
                }
            }
        }
    }

    /// round(clamp(v, 0, 1) · 255) as a byte; NaN is 0.
    @inline(__always)
    private static func level(_ value: Float16) -> UInt8 {
        let v = Float(value)
        guard v > 0 else { return 0 }
        return UInt8(min(255, (v * 255).rounded()))
    }
}
