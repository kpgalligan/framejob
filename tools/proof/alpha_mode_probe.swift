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
// builds it optimised for this mode (`--measure straighten-speed`).

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

func write(path: String, codec: String, mode: String, rgba: [Int]) {
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
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
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
        for y in 0..<height {
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
    emit(["wrote": path, "codec": codec, "mode": mode, "rgba": rgba])
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
            for run in 0..<6 {
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
                let start = DispatchTime.now().uptimeNanoseconds
                ExportStraightAlpha.straighten(
                    bgra: frame, width: fw, height: fh, bytesPerRow: fw * 4)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if run > 0 { times.append(ms) }
                frame.deallocate()
            }
            rows.append([
                "size": "\(fw)x\(fh)", "frame": kind, "ms_best": times.min() ?? -1,
                "ms_runs": times,
            ])
        }
    }
    emit(["timing": rows, "cores": ProcessInfo.processInfo.activeProcessorCount])
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: alpha-mode-probe write|read|roundtrip|timing …")
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
default:
    fail("unknown mode \(arguments[1])")
}
