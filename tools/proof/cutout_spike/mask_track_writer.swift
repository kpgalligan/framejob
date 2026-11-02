// Road map "creator-jobs" CO0, spike CO-S2 — the writer half of
// `mask_track_probe` (compiled with it and `app/Sources`).
//
// - The bar code: 22 blocks across a band, block 0 white and block 1 black
//   (the references; a block reads 1 above the level halfway between them),
//   blocks 2…21 the index's 20 bits, most significant first.
// - `writeBarcode`: 1920×1080 30 fps H.264 (timescale 600, 8 Mb/s, a key
//   frame every 30), frame k carrying k (or, reversed, N − 1 − k at k's time).
// - Mask frames 512×288: the top half a 0…255 horizontal ramp, the bottom half
//   the analysed frame's index as the same bar code.
// - `chunkSamples`: CO-3's nearest-hold placement inside one chunk window.
// - `MaskEncoder`: the two encodings, pinned here before the first run —
//   HEVC 8-bit 4:2:0 full range (`420YpCbCr8BiPlanarFullRange`, Y = mask,
//   CbCr 128, quality 0.8, a key frame every 30 samples, no reordering) and
//   ProRes 422 Proxy (`422YpCbCr8`, Y = mask, CbCr 128); both tagged BT.709
//   primaries, transfer and matrix.
// - `decodeY`: a chunk read natively (`AVAssetReaderTrackOutput` in the
//   encoding's own YCbCr format), each sample's Y plane and time.
// - `codecRow`: CO-S2 (3) and (4) over CO-S1's dumped masks.
import AVFoundation
import Accelerate
import Foundation

struct SpikeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - The bar code

enum BarCode {
    static let blocks = 22
    static let bits = 20

    /// Block i's level: white or black (true = white).
    static func pattern(_ value: Int) -> [Bool] {
        var out = [true, false]
        for bit in stride(from: bits - 1, through: 0, by: -1) { out.append((value >> bit) & 1 == 1) }
        return out
    }

    /// Writes the code into a plane of 8-bit levels, `band` the rows it fills.
    static func draw(
        _ value: Int, into plane: UnsafeMutablePointer<UInt8>, stride: Int, width: Int,
        band: Range<Int>, white: UInt8, black: UInt8
    ) {
        let levels = pattern(value)
        for y in band {
            let row = plane + y * stride
            for i in 0..<blocks {
                let x0 = i * width / blocks, x1 = (i + 1) * width / blocks
                memset(row + x0, Int32(levels[i] ? white : black), x1 - x0)
            }
        }
    }

    /// Reads a code back through `level(x, y)` (any scale), `bandY` the
    /// band's centre as a fraction of the height. Averages a patch per block.
    static func read(width: Int, height: Int, bandY: Double, level: (Int, Int) -> Float) -> Int {
        func patch(_ i: Int) -> Float {
            let cx = Int((Double(i) + 0.5) * Double(width) / Double(blocks))
            let cy = Int(bandY * Double(height))
            let r = max(1, min(width / blocks / 4, height / 40))
            var sum: Float = 0, n: Float = 0
            for y in max(0, cy - r)...min(height - 1, cy + r) {
                for x in max(0, cx - r)...min(width - 1, cx + r) {
                    sum += level(x, y)
                    n += 1
                }
            }
            return sum / n
        }
        let white = patch(0), black = patch(1)
        let threshold = (white + black) / 2
        var value = 0
        for i in 2..<blocks { value = (value << 1) | (patch(i) > threshold ? 1 : 0) }
        return value
    }
}

// MARK: - Pixel buffers

func pixelBuffer(_ width: Int, _ height: Int, _ format: OSType) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    let status = CVPixelBufferCreate(
        nil, width, height, format, attributes as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else {
        throw SpikeError("CVPixelBufferCreate \(width)×\(height) \(format): \(status)")
    }
    return buffer
}

/// Fills a bi-planar or 2vuy buffer whose luma is `luma(y, row)` (a row of
/// `width` levels written by the closure) and whose chroma is 128.
func fillLuma(_ buffer: CVPixelBuffer, _ luma: (Int, UnsafeMutablePointer<UInt8>) -> Void) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let format = CVPixelBufferGetPixelFormatType(buffer)
    if format == kCVPixelFormatType_422YpCbCr8 {
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var row = [UInt8](repeating: 0, count: width)
        for y in 0..<height {
            row.withUnsafeMutableBufferPointer { luma(y, $0.baseAddress!) }
            let out = base + y * stride
            for x in 0..<width {
                out[2 * x] = 128          // Cb or Cr
                out[2 * x + 1] = row[x]   // Y
            }
        }
        return
    }
    let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    for y in 0..<height { luma(y, yBase + y * yStride) }
    let cBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!
    let cStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
    memset(cBase, 128, cStride * CVPixelBufferGetHeightOfPlane(buffer, 1))
}

// MARK: - The bar-code movie

/// `frames` frames at 30 fps (timescale 600), 1920×1080 H.264; frame k shows
/// `value(k)`. Video range: white 235, black 16, the rest 126.
func writeBarcode(_ url: URL, frames: Int, value: (Int) -> Int) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let width = 1920, height = 1080
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 8_000_000, AVVideoMaxKeyFrameIntervalKey: 30,
            AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: 30,
        ],
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.mediaTimeScale = 600
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
    writer.add(input)
    guard writer.startWriting() else { throw SpikeError("writer: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    let band = Int(Double(height) * 0.35)..<Int(Double(height) * 0.65)
    for k in 0..<frames {
        while !input.isReadyForMoreMediaData { usleep(500) }
        guard let pool = adaptor.pixelBufferPool else { throw SpikeError("no pool") }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw SpikeError("the pool gave no buffer") }
        let code = value(k)
        CVPixelBufferLockBaseAddress(buffer, [])
        let plane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        memset(plane, 126, stride * height)
        BarCode.draw(code, into: plane, stride: stride, width: width, band: band, white: 235,
                     black: 16)
        let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!
        memset(chroma, 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * height / 2)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(k) * 20,
                                                                    timescale: 600))
        else { throw SpikeError("append \(k): \(String(describing: writer.error))") }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(frames) * 20, timescale: 600))
    try finish(writer)
}

func finish(_ writer: AVAssetWriter) throws {
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else {
        throw SpikeError("finish: \(String(describing: writer.error))")
    }
}

// MARK: - Mask frames and chunks

let maskWidth = 512, maskHeight = 288

/// A bar-code mask frame: the ramp over the top half, `index` over the bottom.
func barcodeMask(_ index: Int) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: maskWidth * maskHeight)
    out.withUnsafeMutableBufferPointer { pointer in
        let base = pointer.baseAddress!
        for y in 0..<(maskHeight / 2) {
            for x in 0..<maskWidth {
                base[y * maskWidth + x] = UInt8((Double(x) * 255 / Double(maskWidth - 1)).rounded())
            }
        }
        BarCode.draw(index, into: base, stride: maskWidth, width: maskWidth,
                     band: (maskHeight / 2 + 16)..<(maskHeight - 16), white: 255, black: 0)
    }
    return out
}

/// The bottom half's band centre, as a fraction of the mask's height.
let maskBandY = Double(maskHeight / 2 + 16 + (maskHeight - 16)) / 2 / Double(maskHeight)

/// One chunk's samples by CO-3's nearest-hold rule, in the stream's own
/// timescale: the frame shown at the window's start (the last frame at or
/// before it) gives the sample at relative 0, then every frame inside the
/// window whose nearest analysed frame differs from the last sample's. Each
/// is (relative time, analysed time). `analysed` is sorted.
func chunkSamples(frames: [Int64], analysed: [Int64], window: Range<Int64>)
    -> [(time: Int64, analysed: Int64)]
{
    func nearest(_ t: Int64) -> Int64 {
        var lo = 0, hi = analysed.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if analysed[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        if lo < analysed.count, analysed[lo] == t { return t }
        let after = lo < analysed.count ? analysed[lo] : nil
        let before = lo > 0 ? analysed[lo - 1] : nil
        guard let before else { return after! }
        guard let after else { return before }
        return t - before <= after - t ? before : after
    }
    var out: [(Int64, Int64)] = []
    let shownAtStart = frames.last(where: { $0 <= window.lowerBound }) ?? frames.first
    if let shown = shownAtStart { out.append((0, nearest(shown))) }
    for frame in frames where frame > window.lowerBound && frame < window.upperBound {
        let a = nearest(frame)
        if a != out.last?.1 { out.append((frame - window.lowerBound, a)) }
    }
    return out
}

enum MaskEncoding: String, CaseIterable {
    case hevc
    case proresProxy = "prores-proxy"

    var pixelFormat: OSType {
        self == .hevc ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            : kCVPixelFormatType_422YpCbCr8
    }

    /// The settings, pinned before the first run and recorded in each result.
    func settings(width: Int, height: Int) -> [String: Any] {
        let colour: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        switch self {
        case .hevc:
            return [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width,
                    AVVideoHeightKey: height, AVVideoColorPropertiesKey: colour,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoQualityKey: 0.8, AVVideoMaxKeyFrameIntervalKey: 30,
                        AVVideoAllowFrameReorderingKey: false,
                    ]]
        case .proresProxy:
            return [AVVideoCodecKey: AVVideoCodecType.proRes422Proxy, AVVideoWidthKey: width,
                    AVVideoHeightKey: height, AVVideoColorPropertiesKey: colour]
        }
    }

    static var pinned: [String: String] {
        var out: [String: String] = [:]
        for encoding in allCases {
            out[encoding.rawValue] = "\(encoding.settings(width: maskWidth, height: maskHeight))"
                + " input \(encoding.pixelFormat)"
        }
        return out
    }
}

/// Writes one chunk movie: `samples` (relative time, mask bytes) in the
/// stream's `timescale`, the session ended at `length`.
func writeChunk(
    _ url: URL, encoding: MaskEncoding, width: Int, height: Int, timescale: Int32,
    length: Int64, samples: [(time: Int64, mask: () -> [UInt8])]
) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
        mediaType: .video, outputSettings: encoding.settings(width: width, height: height))
    input.mediaTimeScale = timescale
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: encoding.pixelFormat,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
    writer.add(input)
    guard writer.startWriting() else { throw SpikeError("chunk: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    for sample in samples {
        while !input.isReadyForMoreMediaData { usleep(200) }
        let buffer = try pixelBuffer(width, height, encoding.pixelFormat)
        let bytes = sample.mask()
        fillLuma(buffer) { y, row in
            bytes.withUnsafeBufferPointer { _ = memcpy(row, $0.baseAddress! + y * width, width) }
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: sample.time,
                                                                    timescale: timescale))
        else { throw SpikeError("chunk append: \(String(describing: writer.error))") }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: length, timescale: timescale))
    try finish(writer)
}

/// Every sample of a chunk decoded in the encoding's own YCbCr format: its
/// time (the track's timescale) and its Y plane, row-packed.
func decodeY(_ url: URL, encoding: MaskEncoding) throws -> [(time: Int64, y: [UInt8], w: Int, h: Int)] {
    let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video) else {
        throw SpikeError("\(url.lastPathComponent): no track")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: encoding.pixelFormat,
    ])
    reader.add(output)
    guard reader.startReading() else { throw SpikeError("decode: \(String(describing: reader.error))") }
    let scale = track.naturalTimeScale
    var out: [(Int64, [UInt8], Int, Int)] = []
    while let sample = output.copyNextSampleBuffer() {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        let time = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample),
                                      timescale: scale, method: .roundHalfAwayFromZero).value
        out.append((time, lumaPlane(buffer), CVPixelBufferGetWidth(buffer),
                    CVPixelBufferGetHeight(buffer)))
    }
    guard reader.status == .completed else {
        throw SpikeError("decode ended \(reader.status.rawValue): \(String(describing: reader.error))")
    }
    return out
}

/// The Y plane of a bi-planar or 2vuy buffer, row-packed.
func lumaPlane(_ buffer: CVPixelBuffer) -> [UInt8] {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    var out = [UInt8](repeating: 0, count: width * height)
    if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_422YpCbCr8 {
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height { for x in 0..<width { out[y * width + x] = base[y * stride + 2 * x + 1] } }
    } else {
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for y in 0..<height { memcpy(&out[y * width], base + y * stride, width) }
    }
    return out
}

/// The fixed cost of one chunk: open a writer, write one sample, finish.
func fixedCost(_ encoding: MaskEncoding, folder: URL) throws -> Double {
    let url = folder.appendingPathComponent("fixed-\(encoding.rawValue).mov")
    let mask = barcodeMask(1)
    let started = CFAbsoluteTimeGetCurrent()
    try writeChunk(url, encoding: encoding, width: maskWidth, height: maskHeight, timescale: 600,
                   length: 20, samples: [(0, { mask })])
    let seconds = CFAbsoluteTimeGetCurrent() - started
    try? FileManager.default.removeItem(at: url)
    return seconds
}

// MARK: - (3) and (4): codec loss and size over CO-S1's dumped masks

struct Dump {
    let width: Int, height: Int, timescale: Int32, duration: Double
    let pts: [Int64]
    /// Every decoded frame's time, analysed or not.
    let allPts: [Int64]
    let masks: Data

    init(_ folder: URL) throws {
        let index = try JSONSerialization.jsonObject(
            with: Data(contentsOf: folder.appendingPathComponent("index.json"))) as! [String: Any]
        width = index["width"] as! Int
        height = index["height"] as! Int
        timescale = Int32(index["timescale"] as! Int)
        duration = index["duration_s"] as! Double
        pts = (index["pts"] as! [NSNumber]).map(\.int64Value)
        allPts = (index["all_pts"] as! [NSNumber]).map(\.int64Value).sorted()
        masks = try Data(contentsOf: folder.appendingPathComponent("masks.bin"))
    }

    func mask(_ i: Int) -> [UInt8] {
        let size = width * height
        return [UInt8](masks[(i * size)..<((i + 1) * size)])
    }
}

/// The 8 px band (Chebyshev) around the thresholded mask's edge: pixels
/// within 8 of a pixel whose 4-neighbour differs across 127.
func edgeBand(_ mask: [UInt8], _ w: Int, _ h: Int, radius: Int = 8) -> [Bool] {
    var edge = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w {
            let inside = mask[y * w + x] > 127
            if (x + 1 < w && (mask[y * w + x + 1] > 127) != inside)
                || (y + 1 < h && (mask[(y + 1) * w + x] > 127) != inside) {
                edge[y * w + x] = true
                if x + 1 < w { edge[y * w + x + 1] = true }
                if y + 1 < h { edge[(y + 1) * w + x] = true }
            }
        }
    }
    // A box dilation, rows then columns (Chebyshev distance ≤ radius).
    var rows = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        var nearestLeft = Int.min / 2
        var marks = [Int](repeating: Int.max / 2, count: w)
        for x in 0..<w {
            if edge[y * w + x] { nearestLeft = x }
            marks[x] = x - nearestLeft
        }
        var nearestRight = Int.max / 2
        for x in stride(from: w - 1, through: 0, by: -1) {
            if edge[y * w + x] { nearestRight = x }
            rows[y * w + x] = min(marks[x], nearestRight - x) <= radius
        }
    }
    var band = [Bool](repeating: false, count: w * h)
    for x in 0..<w {
        var nearestUp = Int.min / 2
        var marks = [Int](repeating: Int.max / 2, count: h)
        for y in 0..<h {
            if rows[y * w + x] { nearestUp = y }
            marks[y] = y - nearestUp
        }
        var nearestDown = Int.max / 2
        for y in stride(from: h - 1, through: 0, by: -1) {
            if rows[y * w + x] { nearestDown = y }
            band[y * w + x] = min(marks[y], nearestDown - y) <= radius
        }
    }
    return band
}

/// (3) and (4) for one encoding and L: the dump's masks written as chunks by
/// the nearest-hold rule over the dump's source frames, decoded, and compared
/// with Vision's own; the bytes scaled to one minute.
func codecRow(dump: Dump, sourceFrames: [Int64], encoding: MaskEncoding, chunkSeconds: Int,
              folder: URL) throws -> [String: Any] {
    try? FileManager.default.removeItem(at: folder)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let scale = Int64(dump.timescale)
    let length = Int64(chunkSeconds) * scale
    let total = Int64((dump.duration * Double(scale)).rounded())
    let byTime = Dictionary(uniqueKeysWithValues: dump.pts.enumerated().map { ($0.element, $0.offset) })
    // Even sides for 4:2:0; the padding is zero and never compared.
    let w = (dump.width + 1) / 2 * 2, h = (dump.height + 1) / 2 * 2
    func padded(_ m: [UInt8]) -> [UInt8] {
        if w == dump.width && h == dump.height { return m }
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<dump.height { for x in 0..<dump.width { out[y * w + x] = m[y * dump.width + x] } }
        return out
    }
    var bytes = 0, ious: [Double] = [], bandSum = 0.0, bandCount = 0, chunks = 0, compared = 0
    var pooledInter = 0, pooledUnion = 0
    var k: Int64 = 0
    while k * length < total {
        let window = (k * length)..<min((k + 1) * length, total)
        let samples = chunkSamples(frames: sourceFrames, analysed: dump.pts, window: window)
        let url = folder.appendingPathComponent("\(k).mov")
        try writeChunk(url, encoding: encoding, width: w, height: h, timescale: dump.timescale,
                       length: window.upperBound - window.lowerBound,
                       samples: samples.map { s in (s.time, { padded(dump.mask(byTime[s.analysed]!)) }) })
        bytes += (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let samplesByTime = Dictionary(uniqueKeysWithValues: samples.map { ($0.time, $0.analysed) })
        for decoded in try decodeY(url, encoding: encoding) {
            guard let analysed = samplesByTime[decoded.time] else {
                throw SpikeError("chunk \(k): a decoded sample at \(decoded.time) was never written")
            }
            let truth = dump.mask(byTime[analysed]!)
            var inter = 0, union = 0
            let band = edgeBand(truth, dump.width, dump.height)
            for y in 0..<dump.height {
                for x in 0..<dump.width {
                    let t = truth[y * dump.width + x], d = decoded.y[y * decoded.w + x]
                    let a = t > 127, b = d > 127
                    if a && b { inter += 1 }
                    if a || b { union += 1 }
                    if band[y * dump.width + x] {
                        bandSum += Double(abs(Int(t) - Int(d)))
                        bandCount += 1
                    }
                }
            }
            ious.append(union == 0 ? 1 : Double(inter) / Double(union))
            pooledInter += inter
            pooledUnion += union
            compared += 1
        }
        chunks += 1
        k += 1
    }
    let seconds = Double(total) / Double(scale)
    // `iou` is the mean over frames, as CO-S1's J is; `iou_pooled` (every
    // frame's intersections over every frame's unions) is recorded beside it.
    return ["iou": ious.reduce(0, +) / Double(max(1, ious.count)), "iou_min": ious.min() ?? 0,
            "iou_pooled": pooledUnion == 0 ? 1 : Double(pooledInter) / Double(pooledUnion),
            "edge_mad": bandCount == 0 ? 0 : bandSum / Double(bandCount),
            "band_pixels": bandCount, "bytes": bytes, "seconds": seconds,
            "mb_per_min": Double(bytes) / 1e6 * 60 / seconds, "chunks": chunks,
            "compared": compared, "mask": "\(dump.width)x\(dump.height)"]
}
