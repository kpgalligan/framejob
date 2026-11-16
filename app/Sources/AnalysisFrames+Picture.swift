import AVFoundation

/// One kept frame's picture inside `AnalysisFrames.read`'s callback (#437):
/// made only when `picture` is called (again on each call) — turned upright,
/// rounded or converted then, so a frame the kind skips is never copied;
/// valid only inside the callback.
struct LazyAnalysisPicture {
    private let make: (_ body: (AnalysisPicture) throws -> Void) throws -> Void

    init(_ make: @escaping (_ body: (AnalysisPicture) throws -> Void) throws -> Void) {
        self.make = make
    }

    /// `body` over the picture. Throws `ReadError.reader` when the decoded
    /// buffer had no pixels to hand.
    func picture<R>(_ body: (AnalysisPicture) throws -> R) throws -> R {
        var result: R?
        var made = false
        try make { picture in
            result = try body(picture)
            made = true
        }
        guard made, let result else {
            throw AnalysisFrames.ReadError.reader("a decoded frame had no pixels")
        }
        return result
    }
}

extension AnalysisFrames {

    #if FRAMEJOB_DEV_TOOLS
    private static let uprightLock = NSLock()
    private static var uprightCount = 0

    /// How many times `Upright.picture(of:)` has run since launch. Any thread.
    static func uprightsMade() -> Int {
        uprightLock.lock()
        defer { uprightLock.unlock() }
        return uprightCount
    }

    fileprivate static func countUpright() {
        uprightLock.lock()
        uprightCount += 1
        uprightLock.unlock()
    }
    #endif

    /// A half-float RGBA buffer rounded to 8-bit BGRA in `scratch`.
    static func halfToBGRA(
        _ buffer: CVPixelBuffer, into scratch: inout [UInt8], _ body: (AnalysisPicture) throws -> Bool
    ) throws -> Bool {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return true }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        if scratch.count != width * height * 4 { scratch = [UInt8](repeating: 0, count: width * height * 4) }
        func byte(_ v: Float16) -> UInt8 { UInt8((min(max(Float(v), 0), 1) * 255).rounded()) }
        scratch.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let src = (base + y * row).assumingMemoryBound(to: Float16.self)
                for x in 0..<width {
                    let o = (y * width + x) * 4
                    out[o] = byte(src[x * 4 + 2])
                    out[o + 1] = byte(src[x * 4 + 1])
                    out[o + 2] = byte(src[x * 4])
                    out[o + 3] = 255
                }
            }
        }
        return try scratch.withUnsafeBufferPointer { pointer in
            try body(
                AnalysisPicture(
                    width: width, height: height, bytesPerRow: width * 4,
                    bytes: pointer.baseAddress!))
        }
    }

    /// The direct reader's turn upright: the transform's quarter turns and
    /// mirror (`orientationCode` classifies nothing else), each display pixel
    /// read from the natural pixel under its centre. Identity is no copy.
    struct Upright {
        let a: Int, b: Int, c: Int, d: Int
        var scratch: [UInt8] = []

        init(transform t: CGAffineTransform) {
            func unit(_ v: CGFloat) -> Int { v > 0.5 ? 1 : (v < -0.5 ? -1 : 0) }
            a = unit(t.a)
            b = unit(t.b)
            c = unit(t.c)
            d = unit(t.d)
        }

        var isIdentity: Bool { a == 1 && b == 0 && c == 0 && d == 1 }

        mutating func picture(
            of buffer: CVPixelBuffer, _ body: (AnalysisPicture) throws -> Bool
        ) throws -> Bool {
            #if FRAMEJOB_DEV_TOOLS
            AnalysisFrames.countUpright()
            #endif
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return true }
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            let source = base.assumingMemoryBound(to: UInt8.self)
            guard !isIdentity, a * d - b * c != 0 else {
                return try body(
                    AnalysisPicture(width: w, height: h, bytesPerRow: row, bytes: source))
            }
            // The natural rect's corners through the rotation; the display
            // origin is their minimum.
            let xs = [0, a * w, c * h, a * w + c * h]
            let ys = [0, b * w, d * h, b * w + d * h]
            let minX = xs.min()!, minY = ys.min()!
            let dw = xs.max()! - minX
            let dh = ys.max()! - minY
            if scratch.count != dw * dh * 4 { scratch = [UInt8](repeating: 0, count: dw * dh * 4) }
            let (a, b, c, d) = (a, b, c, d)
            scratch.withUnsafeMutableBufferPointer { out in
                for y in 0..<dh {
                    for x in 0..<dw {
                        // Twice the centre, so the inverse (the transpose) stays integral.
                        let u = 2 * (x + minX) + 1
                        let v = 2 * (y + minY) + 1
                        let nx = min(w - 1, max(0, (a * u + b * v - 1) / 2))
                        let ny = min(h - 1, max(0, (c * u + d * v - 1) / 2))
                        let s = source + ny * row + nx * 4
                        let o = (y * dw + x) * 4
                        out[o] = s[0]
                        out[o + 1] = s[1]
                        out[o + 2] = s[2]
                        out[o + 3] = s[3]
                    }
                }
            }
            return try scratch.withUnsafeBufferPointer { pointer in
                try body(
                    AnalysisPicture(
                        width: dw, height: dh, bytesPerRow: dw * 4, bytes: pointer.baseAddress!))
            }
        }
    }
}
