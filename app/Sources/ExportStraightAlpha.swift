import AVFoundation
import CoreVideo

// The alpha movie rows' frames written straight (spec §11 G-35, issue #242;
// amended by PR-3): `ExportWriter`'s video pump hands each frame of
// `prores_4444` and `hevc_alpha` to `ExportFrames` (`ExportStraightAlphaHalf.
// swift`) between the reader and `retimed`. The compositor's premultiplied
// frame is un-premultiplied in place — `prores_4444`'s in float, over its
// 64RGBAHalf pixels; `hevc_alpha`'s here, after it is rounded into 8-bit BGRA
// — every transparent pixel within `bleedRadius` of a visible one takes that
// pixel's colour, by the one fill below over either layout, and the buffer
// is labelled `StraightAlpha` and wrapped in a new sample.

/// One pixel layout the fill runs over: its size, which pixels are visible
/// (a > 0), the colour a transparent pixel takes from a visible one, and
/// whether a whole row is visible — a loop over the alpha alone, written per
/// layout so the compiler vectorises it (asked through `visible` it did not,
/// and the fill ran 15–25 % slower on opaque and soft frames).
protocol StraightAlphaLayout {
    static var bytesPerPixel: Int { get }
    static func visible(_ pixel: UnsafePointer<UInt8>) -> Bool
    static func copyColour(_ from: UnsafePointer<UInt8>, _ to: UnsafeMutablePointer<UInt8>)
    static func allVisible(_ row: UnsafePointer<UInt8>, width: Int) -> Bool
}

/// Premultiplied 8-bit BGRA, alpha the fourth byte.
enum BGRA8: StraightAlphaLayout {
    static var bytesPerPixel: Int { 4 }

    static func visible(_ pixel: UnsafePointer<UInt8>) -> Bool { pixel[3] > 0 }

    static func allVisible(_ row: UnsafePointer<UInt8>, width: Int) -> Bool {
        var lowest = UInt8.max
        for x in 0..<width { lowest = min(lowest, row[x * 4 + 3]) }
        return lowest > 0
    }

    static func copyColour(_ from: UnsafePointer<UInt8>, _ to: UnsafeMutablePointer<UInt8>) {
        to[0] = from[0]
        to[1] = from[1]
        to[2] = from[2]
    }
}

/// The un-premultiply and the fill, over one frame (G-35 (c), (d)).
enum ExportStraightAlpha {

    /// Chebyshev pixels within which a transparent pixel takes a visible
    /// neighbour's colour (G-35 (d)): a codec that subsamples colour would
    /// otherwise average the black of a transparent pixel into the edge
    /// beside it.
    static let bleedRadius = 4

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
    /// Both passes are split by rows over `concurrentPerform`. Pass 1 also
    /// records, for each row with a visible pixel, every column's nearest
    /// visible pixel in that row (`nearestInRow`); pass 2 then reads one
    /// entry per row of the band, so it finds the nearest without walking
    /// the square. Pass 2 reads only pixels with a > 0, which it never
    /// writes, so in place is race-free. A row whose band of rows within
    /// `bleedRadius` holds no visible pixel is skipped, and so is a pixel
    /// outside the band's visible columns widened by the radius.
    static func straighten(
        bgra: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int
    ) {
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return }
        straighten(
            BGRA8.self, pixels: bgra.assumingMemoryBound(to: UInt8.self), width: width,
            height: height, bytesPerRow: bytesPerRow, unpremultiply: unpremultiply)
    }

    /// The two passes over any layout: `unpremultiply` is pass 1 over one
    /// row (recording its first and last visible column in `span`), then the
    /// one fill. The caller has checked the size and the row length.
    static func straighten<L: StraightAlphaLayout>(
        _ layout: L.Type, pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
        bytesPerRow: Int,
        unpremultiply: (UnsafeMutablePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> Void
    ) {
        // Each row's first and last visible column; `first > last` is none.
        let spans = UnsafeMutablePointer<Int>.allocate(capacity: height * 2)
        defer { spans.deallocate() }
        // Per row with a visible pixel, each column's signed dx to the
        // nearest visible pixel in that row (`nearestInRow`).
        let nearest = UnsafeMutablePointer<Int8>.allocate(capacity: height * width)
        defer { nearest.deallocate() }
        let radius = bleedRadius
        let chunk = Self.chunk(height)
        let chunks = (height + chunk - 1) / chunk
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            for y in index * chunk..<min(height, (index + 1) * chunk) {
                let row = pixels + y * bytesPerRow
                unpremultiply(row, width, spans + y * 2)
                guard radius > 0, spans[y * 2] <= spans[y * 2 + 1] else { continue }
                nearestInRow(
                    L.self, row, width: width, radius: radius, into: nearest + y * width)
            }
        }
        guard radius > 0 else { return }
        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            for y in index * chunk..<min(height, (index + 1) * chunk) {
                fill(
                    L.self, y: y, pixels: pixels, width: width, height: height,
                    bytesPerRow: bytesPerRow, spans: spans, nearest: nearest, radius: radius)
            }
        }
    }

    // MARK: - The passes

    /// Rows per `concurrentPerform` iteration: about four per core, so a
    /// slow band does not hold the frame.
    static func chunk(_ height: Int) -> Int {
        let pieces = max(1, ProcessInfo.processInfo.activeProcessorCount * 4)
        return max(1, (height + pieces - 1) / pieces)
    }

    /// Pass 1 over one 8-bit row, recording its visible columns in `span`.
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

    /// A `nearestInRow` entry: no visible pixel in the row within the radius.
    /// An entry is an Int8, so `bleedRadius` must stay ≤ 126 (`Int8(d)`
    /// traps past 127, and at 127 it equals this sentinel).
    private static let noVisible: Int8 = .max

    /// Per x of one row, the signed dx of the a > 0 pixel in this row with
    /// the smallest |dx| ≤ `radius`, a tie going to the negative dx (the
    /// first in row-major order); `noVisible` when there is none. One sweep
    /// left to right: a transparent pixel takes the last visible one on its
    /// left, and a visible pixel is its own nearest (0) and takes over each
    /// transparent pixel within reach on its left that it is STRICTLY
    /// nearer to, so a tie stays with the left. A row with no transparent
    /// pixel (`allVisible`) is its own nearest everywhere.
    static func nearestInRow<L: StraightAlphaLayout>(
        _ layout: L.Type, _ row: UnsafePointer<UInt8>, width: Int, radius: Int,
        into table: UnsafeMutablePointer<Int8>
    ) {
        let step = L.bytesPerPixel
        guard !L.allVisible(row, width: width) else {
            table.initialize(repeating: 0, count: width)
            return
        }
        let reach = radius
        var last = Int.min / 2      // the last visible column so far; none yet
        for x in 0..<width {
            guard L.visible(row + x * step) else {
                let left = x - last
                table[x] = left <= reach ? Int8(-left) : noVisible
                continue
            }
            table[x] = 0
            var d = 1
            while d <= reach && d <= x && x - d > last {
                let left = x - d - last
                if d < left { table[x - d] = Int8(d) }
                d += 1
            }
            last = x
        }
    }

    /// Pass 2 over row `y`: each transparent pixel near a visible one takes
    /// the nearest one's colour. Each row of the band that holds a visible
    /// pixel (listed once per `y`) offers its own nearest (`nearest`, from
    /// pass 1); the rows are read top to bottom and only a strictly smaller
    /// dx² + dy² replaces the one held, so of equals the smallest dy wins,
    /// and within a row the smallest dx — the first in row-major order
    /// (G-35 (d)).
    static func fill<L: StraightAlphaLayout>(
        _ layout: L.Type, y: Int, pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
        bytesPerRow: Int, spans: UnsafeMutablePointer<Int>, nearest: UnsafePointer<Int8>,
        radius: Int
    ) {
        var low = width
        var high = -1
        let top = max(0, y - radius)
        let bottom = min(height - 1, y + radius)
        for band in top...bottom {
            low = min(low, spans[band * 2])
            high = max(high, spans[band * 2 + 1])
        }
        guard low <= high else { return }
        let row = pixels + y * bytesPerRow
        withUnsafeTemporaryAllocation(of: Int.self, capacity: bottom - top + 1) { visibleRows in
            var count = 0
            for ny in top...bottom where spans[ny * 2] <= spans[ny * 2 + 1] {
                visibleRows[count] = ny
                count += 1
            }
            for x in max(0, low - radius)...min(width - 1, high + radius) {
                let pixel = row + x * L.bytesPerPixel
                guard !L.visible(pixel) else { continue }
                var best = Int.max
                var bestX = 0
                var bestY = 0
                for index in 0..<count {
                    let ny = visibleRows[index]
                    let entry = nearest[ny * width + x]
                    guard entry != noVisible else { continue }
                    let dx = Int(entry)
                    let dy = ny - y
                    let distance = dx * dx + dy * dy
                    if distance < best {
                        best = distance
                        bestX = x + dx
                        bestY = ny
                    }
                }
                guard best != Int.max else { continue }
                L.copyColour(pixels + bestY * bytesPerRow + bestX * L.bytesPerPixel, pixel)
            }
        }
    }
}
