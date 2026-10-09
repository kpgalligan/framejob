// tools/proof/alpha_mode_probe.swift — the alpha-mode probe's entry (issue
// batch B92, spec §11 G-35).
//
// Copied to tools/proof/work/alpha-mode-probe/main.swift and compiled LAST
// with every app/Sources/*.swift except the app's main.swift, through
// swift_build.py (hevc_alpha_proof.py's `build_probe`), so `roundtrip` runs
// the product's own `ExportStraightAlpha.straighten(bgra:…)`. `write` and
// `read` use AVFoundation directly: the probe is a third-party writer and a
// reader that says what a file declares.
//
//   alpha-mode-probe write <path> <prores_4444|hevc_alpha> <premultiplied|straight|none> <r,g,b,a>
//   alpha-mode-probe read <path>
//   alpha-mode-probe roundtrip
//   alpha-mode-probe timing
//   alpha-mode-probe equivalence
//   alpha-mode-probe precision
//   alpha-mode-probe write-deep <path> <r,g,b,a>
//
// Each prints one JSON line on stdout and exits 0, or an {"error": …} line
// and exits 1.
//
// `write`: one second, 640 × 360 at 30 fps, alpha 0 (colour 0) except a
// centred 200 × 120 card of exactly that RGBA. The label goes on every
// buffer as `kCVImageBufferAlphaChannelModeKey` and, for `hevc_alpha`, as
// `kVTCompressionPropertyKey_AlphaChannelMode`; `none` sets neither. The
// colour is tagged 709, as `ExportWriter` tags it.
// `read`: {format_mode, decoded_mode, centre} — the video track's
// `kCMFormatDescriptionExtension_AlphaChannelMode` (through async
// `load(.formatDescriptions)`), the first decoded 32BGRA frame's attachment,
// and its centre pixel as RGBA. A missing value is null.
// `roundtrip`: R0's checks on the product's pixel half: every pair
// 0 ≤ c ≤ a, a in 1…255, straightened and re-premultiplied with
// (s·a + 127) / 255; a 16 × 16 plane with one opaque pixel at (8,8); the
// tie with visible pixels at (4,8) and (12,8); and the milliseconds for one
// 1920 × 1080 plane holding an opaque 600 × 360 card.
// `timing` (the review of B92 phase 2): the milliseconds `straighten(bgra:…)`
// takes, best of five after one warm-up, at 1920 × 1080 and 3840 × 2160 on
// three frames — `card` (an opaque card of 600 × 360 at 1080p, scaled with
// the frame, on a clear canvas), `soft` (every pixel's alpha in 1…254, so
// pass 1 divides every pixel and pass 2 finds no transparent one) and
// `sparse` (one visible pixel in each 9 × 9 block, so nearly every pixel is
// transparent and within reach of one: pass 2's worst case). The proof
// builds it optimised for this mode (`--measure straighten-speed`). Since
// B93 phase 2 each row also times `referenceStraighten` (below) on the same
// frames in the same run, so a loaded host slows both alike.
// `equivalence` (K1, issue batch B93 phase 2, #254): the product's
// `straighten(bgra:…)` against `referenceStraighten` — the fill as it was
// before B93 (commit 7308ace's `ExportStraightAlpha`, its square of offsets
// sorted by distance), copied verbatim as the oracle — byte for byte over
// whole planes, padding included: seeded frames of 1 × 1, 3 × 17, 17 × 3,
// 64 × 64 and 257 × 129 with 16 bytes of padding a row at four visible
// densities, 64 × 64 frames whose every fourth row is wholly visible,
// `timing`'s 9 × 9 lattice at 1920 × 1080, an 8 × 8 lattice of
// distinct colours at 1920 × 1080, and every pair of distinct visible pixels
// in a 9 × 9 plane around a transparent centre (3,160 pairs; `pair_ties`
// counts those the same distance from the centre).
// `precision` (the precision road map's PR1, spec §11 PR-3): R8, the product's
// `ExportStraightAlpha.eightBit(half:…)` — every k in 0…255 as half(k/255),
// half((k+0.4)/255) and half((k+0.6)/255) to bytes k, k and k+1 (k < 255) in
// each channel, and the RGBA → BGRA order; RH, `straighten(half:…)` over a
// grid of premultiplied pairs (c, a), c ≤ a: |s·a − c| ≤ 2⁻¹⁰ and s ≤ 1; KH,
// the half fill against the 8-bit fill over K1's seeded frames and both
// lattices — every visible pixel opaque and carrying a distinct id as its
// colour (an exact k/2048 per half channel), so after each fill a
// transparent pixel's colour names the source pixel it was given.
// `write-deep` (`--measure hevc-alpha-deep`, HA): `write`'s hevc_alpha file,
// labelled straight, from 64RGBAHalf buffers — whether the writer takes them.

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

setvbuf(stdout, nil, _IOLBF, 0)

func emit(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{\"error\":\"unprintable\"}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

func fail(_ why: String) -> Never {
    emit(["error": why])
    exit(1)
}

/// Runs an async body to its end from top-level code.
func blocking<T>(_ body: @escaping () async throws -> T) throws -> T {
    let done = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    Task.detached {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        done.signal()
    }
    done.wait()
    guard let result = result else { fail("no result") }
    return try result.get()
}

// MARK: - write

func write(path: String, codec: String, mode: String, rgba: [Int], deep: Bool = false) {
    let width = 640, height = 360
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
        fail("no writer for \(path)")
    }
    let label: CFString? = mode == "premultiplied"
        ? kCVImageBufferAlphaChannelMode_PremultipliedAlpha
        : mode == "straight" ? kCVImageBufferAlphaChannelMode_StraightAlpha : nil
    var settings: [String: Any] = [
        AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ]
    switch codec {
    case "prores_4444":
        settings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
    case "hevc_alpha":
        settings[AVVideoCodecKey] = AVVideoCodecType.hevcWithAlpha
        if mode != "none" {
            settings[AVVideoCompressionPropertiesKey] = [
                kVTCompressionPropertyKey_AlphaChannelMode as String:
                    mode == "premultiplied"
                    ? kVTAlphaChannelMode_PremultipliedAlpha : kVTAlphaChannelMode_StraightAlpha
            ]
        }
    default:
        fail("unknown codec \(codec)")
    }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(deep ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
    guard writer.canAdd(input) else { fail("the writer refuses the input") }
    writer.add(input)
    guard writer.startWriting() else {
        fail("startWriting: \(writer.error?.localizedDescription ?? "?")")
    }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<30 {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        var made: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess,
            let buffer = made
        else { fail("no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { fail("no base address") }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height where deep {
            for x in 0..<width {
                let pixel = (base + y * row).assumingMemoryBound(to: Float16.self) + x * 4
                let card = x >= 220 && x < 420 && y >= 120 && y < 240
                for c in 0..<4 { pixel[c] = card ? Float16(Float(rgba[c]) / 255) : 0 }
            }
        }
        for y in 0..<height where !deep {
            for x in 0..<width {
                let pixel = bytes + y * row + x * 4
                let card = x >= 220 && x < 420 && y >= 120 && y < 240
                pixel[0] = card ? UInt8(rgba[2]) : 0
                pixel[1] = card ? UInt8(rgba[1]) : 0
                pixel[2] = card ? UInt8(rgba[0]) : 0
                pixel[3] = card ? UInt8(rgba[3]) : 0
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        if let label = label {
            CVBufferSetAttachment(buffer, kCVImageBufferAlphaChannelModeKey, label, .shouldPropagate)
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
        else { fail("append: \(writer.error?.localizedDescription ?? "?")") }
    }
    input.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else {
        fail("finishWriting: \(writer.error?.localizedDescription ?? "?")")
    }
    emit(["wrote": path, "codec": codec, "mode": mode, "rgba": rgba, "deep": deep])
}

// MARK: - read

func read(path: String) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let found: (AVAssetTrack, [CMFormatDescription])
    do {
        found = try blocking {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw NSError(domain: "probe", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "no video track"])
            }
            return (track, try await track.load(.formatDescriptions))
        }
    } catch {
        fail("load: \(error.localizedDescription)")
    }
    let formatMode = found.1.first.flatMap {
        CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_AlphaChannelMode)
    } as? String
    guard let reader = try? AVAssetReader(asset: asset) else { fail("no reader") }
    let output = AVAssetReaderTrackOutput(
        track: found.0,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
    reader.add(output)
    guard reader.startReading() else { fail("startReading: \(reader.error?.localizedDescription ?? "?")") }
    guard let sample = output.copyNextSampleBuffer(),
        let buffer = CMSampleBufferGetImageBuffer(sample)
    else { fail("no decoded frame") }
    let decodedMode = CVBufferCopyAttachment(buffer, kCVImageBufferAlphaChannelModeKey, nil)
        as? String
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { fail("no base address") }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let pixel = base.assumingMemoryBound(to: UInt8.self)
        + (height / 2) * CVPixelBufferGetBytesPerRow(buffer) + (width / 2) * 4
    reader.cancelReading()
    emit([
        "format_mode": formatMode as Any? ?? NSNull(),
        "decoded_mode": decodedMode as Any? ?? NSNull(),
        "centre": [Int(pixel[2]), Int(pixel[1]), Int(pixel[0]), Int(pixel[3])],
    ])
}

// MARK: - roundtrip

/// A BGRA plane of `width` × `height`, tightly packed, all (0,0,0,0).
func plane(_ width: Int, _ height: Int) -> UnsafeMutablePointer<UInt8> {
    let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
    bytes.initialize(repeating: 0, count: width * height * 4)
    return bytes
}

func set(_ p: UnsafeMutablePointer<UInt8>, _ width: Int, _ x: Int, _ y: Int, _ bgra: [UInt8]) {
    for i in 0..<4 { p[(y * width + x) * 4 + i] = bgra[i] }
}

func get(_ p: UnsafeMutablePointer<UInt8>, _ width: Int, _ x: Int, _ y: Int) -> [UInt8] {
    (0..<4).map { p[(y * width + x) * 4 + $0] }
}

func roundtrip() {
    // Every pair 0 ≤ c ≤ a, a in 1…255: row a − 1, column c; B, G and R
    // each c, so a swapped channel would still be caught by the count.
    let pw = 256, ph = 255
    let pairs = plane(pw, ph)
    for a in 1...255 {
        for c in 0...a { set(pairs, pw, c, a - 1, [UInt8(c), UInt8(c), UInt8(c), UInt8(a)]) }
    }
    ExportStraightAlpha.straighten(bgra: pairs, width: pw, height: ph, bytesPerRow: pw * 4)
    var count = 0, mismatches = 0
    var first: [String: Int]?
    for a in 1...255 {
        for c in 0...a {
            count += 1
            let s = get(pairs, pw, c, a - 1)
            let alphaKept = Int(s[3]) == a
            let back = (0..<3).map { (Int(s[$0]) * a + 127) / 255 }
            if !alphaKept || back != [c, c, c] {
                mismatches += 1
                if first == nil { first = ["a": a, "c": c, "s": Int(s[2])] }
            }
        }
    }
    pairs.deallocate()

    // One opaque pixel at (8,8) on 16 × 16: the Chebyshev ≤ 4 square holds
    // its colour at alpha 0, (8,8) is unchanged, everything else (0,0,0,0).
    let colour: [UInt8] = [30, 60, 200, 255]
    let square = plane(16, 16)
    set(square, 16, 8, 8, colour)
    ExportStraightAlpha.straighten(bgra: square, width: 16, height: 16, bytesPerRow: 64)
    var squareMismatches = 0
    for y in 0..<16 {
        for x in 0..<16 {
            let want: [UInt8] = (x, y) == (8, 8) ? colour
                : max(abs(x - 8), abs(y - 8)) <= 4 ? [30, 60, 200, 0] : [0, 0, 0, 0]
            if get(square, 16, x, y) != want { squareMismatches += 1 }
        }
    }
    square.deallocate()

    // A tie: (8,8) is 4 px from (4,8) and from (12,8); the first in
    // row-major order, (4,8), gives its colour.
    let tie = plane(16, 16)
    set(tie, 16, 4, 8, [10, 20, 30, 255])
    set(tie, 16, 12, 8, [90, 80, 70, 255])
    ExportStraightAlpha.straighten(bgra: tie, width: 16, height: 16, bytesPerRow: 64)
    let tied = get(tie, 16, 8, 8)
    tie.deallocate()

    // The time for one 1920 × 1080 frame with an opaque 600 × 360 card, best
    // of five after one warm-up.
    let fw = 1920, fh = 1080
    var times: [Double] = []
    for run in 0..<6 {
        let frame = plane(fw, fh)
        for y in 360..<720 { for x in 660..<1260 { set(frame, fw, x, y, [0, 0, 255, 255]) } }
        let start = DispatchTime.now().uptimeNanoseconds
        ExportStraightAlpha.straighten(bgra: frame, width: fw, height: fh, bytesPerRow: fw * 4)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        if run > 0 { times.append(ms) }
        frame.deallocate()
    }
    emit([
        "pairs": count, "pair_mismatches": mismatches,
        "first_mismatch": first as Any? ?? NSNull(),
        "square_mismatches": squareMismatches,
        "tie": tied.map { Int($0) }, "tie_ok": tied == [10, 20, 30, 0],
        "bleed_radius": ExportStraightAlpha.bleedRadius,
        "ms_best": times.min() ?? -1, "ms_runs": times,
    ])
}

// MARK: - timing

func timing() {
    var rows: [[String: Any]] = []
    for (fw, fh) in [(1920, 1080), (3840, 2160)] {
        let scale = fw / 1920
        for kind in ["card", "soft", "sparse"] {
            var times: [Double] = []
            var referenceTimes: [Double] = []
            for run in 0..<12 {
                let frame = plane(fw, fh)
                switch kind {
                case "card":
                    for y in (360 * scale)..<(720 * scale) {
                        for x in (660 * scale)..<(1260 * scale) {
                            set(frame, fw, x, y, [0, 0, 255, 255])
                        }
                    }
                case "soft":
                    for y in 0..<fh {
                        for x in 0..<fw {
                            let a = UInt8(1 + (x + y) % 254)
                            set(frame, fw, x, y, [a / 3, a / 2, a, a])
                        }
                    }
                default:
                    for y in stride(from: 4, to: fh, by: 9) {
                        for x in stride(from: 4, to: fw, by: 9) {
                            set(frame, fw, x, y, [0, 0, 128, 128])
                        }
                    }
                }
                // Runs alternate: even the product, odd the reference; the
                // first of each is the warm-up.
                let start = DispatchTime.now().uptimeNanoseconds
                if run % 2 == 0 {
                    ExportStraightAlpha.straighten(
                        bgra: frame, width: fw, height: fh, bytesPerRow: fw * 4)
                } else {
                    referenceStraighten(bgra: frame, width: fw, height: fh, bytesPerRow: fw * 4)
                }
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if run >= 2 {
                    if run % 2 == 0 { times.append(ms) } else { referenceTimes.append(ms) }
                }
                frame.deallocate()
            }
            rows.append([
                "size": "\(fw)x\(fh)", "frame": kind, "ms_best": times.min() ?? -1,
                "ms_runs": times, "reference_ms_best": referenceTimes.min() ?? -1,
                "reference_ms_runs": referenceTimes,
            ])
        }
    }
    emit(["timing": rows, "cores": ProcessInfo.processInfo.activeProcessorCount])
}

// MARK: - equivalence

/// The fill before B93 phase 2 (commit 7308ace's `ExportStraightAlpha`),
/// copied verbatim but for its names and `bleedRadius`, which is that
/// commit's 4: K1's oracle.
enum ReferenceStraightAlpha {

    static let bleedRadius = 4

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

    private static func chunk(_ height: Int) -> Int {
        let pieces = max(1, ProcessInfo.processInfo.activeProcessorCount * 4)
        return max(1, (height + pieces - 1) / pieces)
    }

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

func referenceStraighten(bgra: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) {
    ReferenceStraightAlpha.straighten(
        bgra: bgra, width: width, height: height, bytesPerRow: bytesPerRow)
}

/// A seeded linear congruential generator (Knuth's MMIX constants), so a
/// case is the same bytes on every run.
struct Seeded {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
    mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next()) }
}

/// The product and the reference over two copies of `bytes`; nil when every
/// byte agrees, else the first differing byte's place and both values.
func compare(
    _ bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
) -> [String: Int]? {
    var product = bytes
    var reference = bytes
    product.withUnsafeMutableBytes {
        ExportStraightAlpha.straighten(
            bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)
    }
    reference.withUnsafeMutableBytes {
        referenceStraighten(
            bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)
    }
    guard let at = (0..<bytes.count).first(where: { product[$0] != reference[$0] }) else {
        return nil
    }
    return ["byte": at, "x": (at % bytesPerRow) / 4, "y": at / bytesPerRow,
            "channel": at % 4, "product": Int(product[at]), "reference": Int(reference[at])]
}

func equivalence() {
    var cases = 0, mismatched = 0
    var first: [String: Any]?
    func run(_ name: String, _ bytes: [UInt8], _ width: Int, _ height: Int, _ bytesPerRow: Int) {
        cases += 1
        guard let where_ = compare(bytes, width: width, height: height, bytesPerRow: bytesPerRow)
        else { return }
        mismatched += 1
        if first == nil { first = ["case": name, "at": where_] }
    }
    // Seeded frames, every byte random (padding and transparent pixels'
    // colour included); a pixel is visible with the density's chance, its
    // alpha then 1…255.
    var random = Seeded(state: 0x5EED_B93)
    for (width, height) in [(1, 1), (3, 17), (17, 3), (64, 64), (257, 129)] {
        let bytesPerRow = width * 4 + 16
        for (density, label) in [(2, "0.2%"), (10, "1%"), (50, "5%"), (300, "30%")] {
            for seed in 0..<3 {
                var bytes = (0..<(bytesPerRow * height)).map { _ in random.byte() }
                for y in 0..<height {
                    for x in 0..<width {
                        let visible = Int(random.next() % 1000) < density
                        bytes[y * bytesPerRow + x * 4 + 3] =
                            visible ? UInt8(1 + Int(random.next() % 255)) : 0
                    }
                }
                run("\(width)x\(height) \(label) #\(seed)", bytes, width, height, bytesPerRow)
            }
        }
    }
    // Every fourth row wholly visible (the row table's fast path) between
    // rows of 2 % density, so transparent pixels read a whole row's entries.
    for seed in 0..<3 {
        let width = 64, height = 64, bytesPerRow = width * 4 + 16
        var bytes = (0..<(bytesPerRow * height)).map { _ in random.byte() }
        for y in 0..<height {
            for x in 0..<width {
                let visible = y % 4 == 0 || Int(random.next() % 1000) < 20
                bytes[y * bytesPerRow + x * 4 + 3] =
                    visible ? UInt8(1 + Int(random.next() % 255)) : 0
            }
        }
        run("64x64 whole rows #\(seed)", bytes, width, height, bytesPerRow)
    }
    // `timing`'s sparse frame: one visible pixel per 9 × 9 block.
    let fw = 1920, fh = 1080
    var lattice9 = [UInt8](repeating: 0, count: fw * fh * 4)
    for y in stride(from: 4, to: fh, by: 9) {
        for x in stride(from: 4, to: fw, by: 9) {
            let at = (y * fw + x) * 4
            lattice9[at] = 0; lattice9[at + 1] = 0; lattice9[at + 2] = 128; lattice9[at + 3] = 128
        }
    }
    run("1920x1080 9x9 lattice", lattice9, fw, fh, fw * 4)
    // An 8 × 8 lattice of distinct colours: a pixel 4 px from two or four of
    // them is a tie the colour shows.
    var lattice8 = [UInt8](repeating: 0, count: fw * fh * 4)
    var colours = Seeded(state: 8)
    for y in stride(from: 0, to: fh, by: 8) {
        for x in stride(from: 0, to: fw, by: 8) {
            let at = (y * fw + x) * 4
            for c in 0..<3 { lattice8[at + c] = colours.byte() }
            lattice8[at + 3] = 255
        }
    }
    run("1920x1080 8x8 lattice", lattice8, fw, fh, fw * 4)

    // Every pair of distinct visible pixels on a 9 × 9 plane around a
    // transparent centre (4,4).
    var pairs = 0, ties = 0, pairMismatches = 0
    var firstPair: [String: Any]?
    let places = (0..<81).filter { $0 != 40 }
    for i in 0..<places.count {
        for j in (i + 1)..<places.count {
            let (a, b) = (places[i], places[j])
            var bytes = [UInt8](repeating: 0, count: 81 * 4)
            for c in 0..<4 { bytes[a * 4 + c] = [10, 20, 30, 255][c] }
            for c in 0..<4 { bytes[b * 4 + c] = [90, 80, 70, 255][c] }
            pairs += 1
            let da = (a % 9 - 4) * (a % 9 - 4) + (a / 9 - 4) * (a / 9 - 4)
            let db = (b % 9 - 4) * (b % 9 - 4) + (b / 9 - 4) * (b / 9 - 4)
            if da == db { ties += 1 }
            if let where_ = compare(bytes, width: 9, height: 9, bytesPerRow: 36) {
                pairMismatches += 1
                if firstPair == nil {
                    firstPair = ["a": [a % 9, a / 9], "b": [b % 9, b / 9], "at": where_]
                }
            }
        }
    }
    emit([
        "cases": cases, "mismatched_cases": mismatched,
        "first_mismatch": first.map { $0 as Any } ?? firstPair.map { $0 as Any } ?? NSNull(),
        "pairs": pairs, "pair_ties": ties, "pair_mismatches": pairMismatches,
    ])
}

// MARK: - precision (PR1)

/// R8: `eightBit(half:…)` over one row of 256 × 3 pixels — k/255,
/// (k+0.4)/255 and (k+0.6)/255 in all four channels — and one pixel whose
/// channels differ, for the order.
func r8() -> [String: Any] {
    let width = 256 * 3 + 1
    var half = [Float16](repeating: 0, count: width * 4)
    for k in 0..<256 {
        for (n, offset) in [0.0, 0.4, 0.6].enumerated() {
            let v = Float16(min(1, (Double(k) + offset) / 255))
            for c in 0..<4 { half[(k * 3 + n) * 4 + c] = v }
        }
    }
    let order: [Float16] = [10, 20, 30, 40].map { Float16(Float($0) / 255) }
    for c in 0..<4 { half[(width - 1) * 4 + c] = order[c] }
    var bgra = [UInt8](repeating: 0, count: width * 4)
    half.withUnsafeBytes { from in
        bgra.withUnsafeMutableBytes { to in
            ExportStraightAlpha.eightBit(
                half: from.baseAddress!, halfBytesPerRow: width * 8, bgra: to.baseAddress!,
                bgraBytesPerRow: width * 4, width: width, height: 1)
        }
    }
    var mismatches = 0
    var first: [String: Any]?
    for k in 0..<256 {
        for (n, want) in [k, k, min(255, k + 1)].enumerated() where !(n == 2 && k == 255) {
            for c in 0..<4 where Int(bgra[(k * 3 + n) * 4 + c]) != want {
                mismatches += 1
                if first == nil {
                    first = ["k": k, "offset": [0, 0.4, 0.6][n], "channel": c,
                             "got": Int(bgra[(k * 3 + n) * 4 + c]), "want": want]
                }
            }
        }
    }
    let orderGot = (0..<4).map { Int(bgra[(width - 1) * 4 + $0]) }
    return ["mismatches": mismatches, "first": first.map { $0 as Any } ?? NSNull(),
            "order": orderGot, "order_ok": orderGot == [30, 20, 10, 40]]
}

/// RH: `straighten(half:…)` over premultiplied pairs (c, a): a in k/255 and
/// i/64, c = a·j/32; the pairs as their half values.
func rh() -> [String: Any] {
    var alphas = (1...255).map { Float($0) / 255 } + (1...64).map { Float($0) / 64 }
    alphas.sort()
    let fractions = (0...32).map { Float($0) / 32 }
    let width = fractions.count, height = alphas.count
    var half = [Float16](repeating: 0, count: width * height * 4)
    for (y, a) in alphas.enumerated() {
        for (x, f) in fractions.enumerated() {
            let at = (y * width + x) * 4
            for c in 0..<3 { half[at + c] = Float16(a * f) }
            half[at + 3] = Float16(a)
        }
    }
    let before = half
    half.withUnsafeMutableBytes {
        ExportStraightAlpha.straighten(
            half: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 8)
    }
    var worst: Float = 0, overOne = 0, pairs = 0
    var first: [String: Any]?
    for at in stride(from: 0, to: half.count, by: 4) {
        let a = Float(before[at + 3])
        for c in 0..<3 {
            pairs += 1
            let s = Float(half[at + c]), given = Float(before[at + c])
            let error = abs(s * a - given)
            if s > 1 { overOne += 1 }
            if error > worst { worst = error }
            if error > 1.0 / 1024, first == nil {
                first = ["c": given, "a": a, "s": s, "error": error]
            }
        }
    }
    return ["pairs": pairs, "worst": worst, "over_one": overOne, "bound": 1.0 / 1024,
            "first_over": first.map { $0 as Any } ?? NSNull()]
}

/// K1's alpha patterns (visible or not), each a width, height and a row-major
/// list of visibilities: `equivalence`'s frames, drawn from the same seeded
/// sequence in the same order, so each pattern is that frame's.
func kPatterns() -> [(String, Int, Int, [Bool])] {
    var patterns: [(String, Int, Int, [Bool])] = []
    var random = Seeded(state: 0x5EED_B93)
    for (width, height) in [(1, 1), (3, 17), (17, 3), (64, 64), (257, 129)] {
        let bytesPerRow = width * 4 + 16
        for (density, label) in [(2, "0.2%"), (10, "1%"), (50, "5%"), (300, "30%")] {
            for seed in 0..<3 {
                for _ in 0..<(bytesPerRow * height) { _ = random.byte() }
                var seen = [Bool](repeating: false, count: width * height)
                for i in 0..<(width * height) {
                    seen[i] = Int(random.next() % 1000) < density
                    if seen[i] { _ = random.next() }
                }
                patterns.append(("\(width)x\(height) \(label) #\(seed)", width, height, seen))
            }
        }
    }
    for seed in 0..<3 {
        for _ in 0..<((64 * 4 + 16) * 64) { _ = random.byte() }
        var seen = [Bool](repeating: false, count: 64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                seen[y * 64 + x] = y % 4 == 0 || Int(random.next() % 1000) < 20
                if seen[y * 64 + x] { _ = random.next() }
            }
        }
        patterns.append(("64x64 whole rows #\(seed)", 64, 64, seen))
    }
    let fw = 1920, fh = 1080
    var lattice9 = [Bool](repeating: false, count: fw * fh)
    for y in stride(from: 4, to: fh, by: 9) {
        for x in stride(from: 4, to: fw, by: 9) { lattice9[y * fw + x] = true }
    }
    patterns.append(("1920x1080 9x9 lattice", fw, fh, lattice9))
    var lattice8 = [Bool](repeating: false, count: fw * fh)
    for y in stride(from: 0, to: fh, by: 8) {
        for x in stride(from: 0, to: fw, by: 8) { lattice8[y * fw + x] = true }
    }
    patterns.append(("1920x1080 8x8 lattice", fw, fh, lattice8))
    return patterns
}

/// KH: per pattern, an 8-bit plane and a half plane (both with row padding)
/// whose visible pixels are opaque and carry id i + 1 as their colour, every
/// transparent pixel id 0; after each format's own straighten, every pixel's
/// id must agree.
func kh() -> [String: Any] {
    var cases = 0, mismatched = 0, filled = 0
    var first: [String: Any]?
    for (name, width, height, seen) in kPatterns() {
        cases += 1
        let row8 = width * 4 + 16, row16 = width * 8 + 32
        var bgra = [UInt8](repeating: 0, count: row8 * height)
        var half = [UInt8](repeating: 0, count: row16 * height)
        for i in 0..<(width * height) where seen[i] {
            let (x, y) = (i % width, i / width)
            let id = i + 1
            let at8 = y * row8 + x * 4
            bgra[at8] = UInt8(id & 0xFF)
            bgra[at8 + 1] = UInt8((id >> 8) & 0xFF)
            bgra[at8 + 2] = UInt8((id >> 16) & 0xFF)
            bgra[at8 + 3] = 255
            half.withUnsafeMutableBytes { raw in
                let pixel = (raw.baseAddress! + y * row16).assumingMemoryBound(to: Float16.self)
                    + x * 4
                for c in 0..<3 { pixel[c] = Float16(Float((id >> (11 * c)) & 0x7FF) / 2048) }
                pixel[3] = 1
            }
        }
        bgra.withUnsafeMutableBytes {
            ExportStraightAlpha.straighten(
                bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: row8)
        }
        half.withUnsafeMutableBytes {
            ExportStraightAlpha.straighten(
                half: $0.baseAddress!, width: width, height: height, bytesPerRow: row16)
        }
        var wrong = 0
        for y in 0..<height {
            for x in 0..<width {
                let at8 = y * row8 + x * 4
                let id8 = Int(bgra[at8]) | Int(bgra[at8 + 1]) << 8 | Int(bgra[at8 + 2]) << 16
                let id16: Int = half.withUnsafeBytes { raw in
                    let pixel = (raw.baseAddress! + y * row16)
                        .assumingMemoryBound(to: Float16.self) + x * 4
                    return (0..<3).reduce(0) { $0 | Int(Float(pixel[$1]) * 2048) << (11 * $1) }
                }
                if !seen[y * width + x] && id8 != 0 { filled += 1 }
                if id8 != id16 {
                    wrong += 1
                    if first == nil {
                        first = ["case": name, "x": x, "y": y, "eight": id8, "half": id16]
                    }
                }
            }
        }
        if wrong > 0 { mismatched += 1 }
    }
    return ["cases": cases, "mismatched_cases": mismatched, "filled": filled,
            "first": first.map { $0 as Any } ?? NSNull()]
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: alpha-mode-probe write|read|roundtrip|timing|equivalence|precision|write-deep …")
}
switch arguments[1] {
case "write":
    guard arguments.count == 6 else { fail("write <path> <codec> <mode> <r,g,b,a>") }
    let rgba = arguments[5].split(separator: ",").compactMap { Int($0) }
    guard rgba.count == 4, rgba.allSatisfy({ (0...255).contains($0) }),
        ["premultiplied", "straight", "none"].contains(arguments[4])
    else { fail("bad mode or colour") }
    write(path: arguments[2], codec: arguments[3], mode: arguments[4], rgba: rgba)
case "read":
    guard arguments.count == 3 else { fail("read <path>") }
    read(path: arguments[2])
case "roundtrip":
    roundtrip()
case "timing":
    timing()
case "equivalence":
    equivalence()
case "precision":
    emit(["r8": r8(), "rh": rh(), "kh": kh()])
case "write-deep":
    guard arguments.count == 4 else { fail("write-deep <path> <r,g,b,a>") }
    let rgba = arguments[3].split(separator: ",").compactMap { Int($0) }
    guard rgba.count == 4, rgba.allSatisfy({ (0...255).contains($0) }) else { fail("bad colour") }
    write(path: arguments[2], codec: "hevc_alpha", mode: "straight", rgba: rgba, deep: true)
default:
    fail("unknown mode \(arguments[1])")
}
