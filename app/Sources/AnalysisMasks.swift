import CoreML
import Foundation
import Vision

/// The `masks` kind (spec §11 CO-1, CO-4, CO-10, CO-11; road map
/// "creator-jobs" CO1): a person's mask for every analysed source frame of a
/// media, made by Vision on this Mac and kept as one pack per media
/// (`MaskPack`). Nothing visible; `get_media_analysis` answers its runs.
///
/// **The request** is a FRESH `VNGeneratePersonSegmentationRequest` per frame
/// (never `.fast`, which is stateful; never the instance mask on video),
/// `.balanced`, revision 1, 8-bit output, pinned to `computeDevice` on every
/// stage; a job refuses to run when the device a request reads back is not
/// the stamp's (`device`).
///
/// **The frames** are read through `AnalysisFrames.read` at the source size
/// (the long side `max(width, height)`), the third arm for a converting
/// media (CO-7). At `rate` "every" each kept frame of a range is analysed; at
/// a capped rate r the analysed frames are the first frame at or after each
/// k / r s (CJ-23), the read widened by ⌈fps / r⌉ indices each side so every
/// covered frame's nearest analysed frame (ties to the earlier) is in the job.
/// Only frames of the range enter the frame table.
///
/// **A mask** is the size Vision answers, the job's first setting it; no
/// observation is an all-zero mask; `found` is `MaskPack.found`. A job
/// publishes at each range's end and every `publishInterval`, mid-range
/// covering only through the last analysed frame done (`covered`).
enum AnalysisMasks {
    static let publishInterval: TimeInterval = 30

    /// CO-11: CJ-S2's rule 1 read for the mask request.
    static let computeDevice: AnalysisVision.Device = .gpu
    /// CO-11: CO-S1's Standard rate on that device.
    static let rate = "every"
    /// The device a pinned request reads back, once (the stamp's `device`).
    static let device: String = AnalysisVision.pin(makeRequest(), to: computeDevice)

    static let vision = AnalysisVisionStamp(
        request: "person_segmentation", quality: "balanced", revision: 1, rate: rate,
        readSize: "source")

    /// What the stored masks depend on: the stamp's digest.
    static let parameters: [String: Any] = [
        "request": vision.request, "quality": vision.quality, "revision": vision.revision,
        "output": "one_component_8", "rate": rate, "read_size": vision.readSize,
        "found": "above_127_at_least_1_in_200", "compression": "lzfse",
        "pack_version": Int(MaskPack.version),
    ]

    /// A fresh request: person `.balanced`, revision 1, 8-bit.
    static func makeRequest() -> VNGeneratePersonSegmentationRequest {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.revision = VNGeneratePersonSegmentationRequestRevision1
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }

    /// What a publish covers: all of `range` when `finished`; else through
    /// the last analysed frame done, at most `range`'s end; nil when none is.
    static func covered(
        _ range: ClosedRange<Int>, analysedDone: [Int], finished: Bool
    ) -> ClosedRange<Int>? {
        if finished { return range }
        guard let last = analysedDone.max(), last >= range.lowerBound else { return nil }
        return range.lowerBound...min(last, range.upperBound)
    }

    // MARK: - Runs

    struct Run: Equatable {
        let from: Int64
        let to: Int64
        let subjectFound: Bool
        let frames: Int
    }

    /// The pack's frames inside `window` and a coverage range, in maximal runs
    /// of consecutive frames in one coverage range whose masks' `found`
    /// agree; `to` the last frame's pts plus one frame.
    static func runs(
        _ pack: MaskPack, window: ClosedRange<Int>, coverage: [ClosedRange<Int>],
        grid: AnalysisGrid
    ) -> [Run] {
        let ranges = AnalysisStore.merged(coverage)
        var out: [Run] = []
        var open: (from: Int64, last: Int64, found: Bool, range: Int, frames: Int)?
        func close() {
            guard let run = open else { return }
            out.append(
                Run(from: run.from, to: Int64((Double(run.last) + grid.frameTicks).rounded()),
                    subjectFound: run.found, frames: run.frames))
            open = nil
        }
        for frame in pack.frames {
            let index = Int(frame.index)
            guard window.contains(index),
                let range = ranges.firstIndex(where: { $0.contains(index) })
            else {
                close()
                continue
            }
            let found = pack.masks[Int(frame.slot)].found
            if let run = open, run.found == found, run.range == range {
                open = (run.from, frame.pts, found, range, run.frames + 1)
            } else {
                close()
                open = (frame.pts, frame.pts, found, range, 1)
            }
        }
        close()
        return out
    }

    // MARK: - The job

    enum MaskError: LocalizedError {
        case device(String)
        case size(Int, Int, Int, Int)
        case noMask(Int64)

        var errorDescription: String? {
            switch self {
            case .device(let named):
                return "the mask request ran on \(named), not \(AnalysisMasks.device)"
            case .size(let w, let h, let width, let height):
                return "Vision answered a \(w) × \(h) mask, not \(width) × \(height)"
            case .noMask(let pts):
                return "Vision answered no mask for the frame at \(pts), before any other"
            }
        }
    }

    /// Runs `request`'s ranges in order (above). False when `cancelled()`
    /// stopped it; `progress` hears done / total of the ranges' indices.
    static func run(
        _ request: AnalysisRequest, cancelled: () -> Bool, progress: (Double) -> Void
    ) throws -> Bool {
        let grid = AnalysisGrid(media: request.media)
        let source = AnalysisFrames.Source(
            media: request.media, url: request.url, input: request.input,
            arm: request.input == nil ? .standard : .inputPass)
        let longSide = max(request.media.width, request.media.height)
        let total = max(1, request.ranges.reduce(0) { $0 + $1.count })
        let capped = Double(rate)
        let widen = capped.map { Int((grid.num / grid.den / $0).rounded(.up)) } ?? 0
        var size: (width: Int, height: Int)?
        var before = 0
        for range in request.ranges {
            var job = Job(range: range, grid: grid)
            let read = max(0, range.lowerBound - widen)...min(grid.lastIndex, range.upperBound + widen)
            var previous: Int64?
            var lastPublish = Date()
            let finished = try AnalysisFrames.read(
                range: read, grid: grid, source: source, longSide: longSide, cancelled: cancelled
            ) { k, pts, picture in
                defer { previous = pts }
                guard k >= read.lowerBound else { return }
                if range.contains(k) {
                    job.frames.append((pts, Int32(k)))
                    progress(Double(before + k - range.lowerBound + 1) / Double(total))
                }
                guard analysed(pts, after: previous, rate: capped) else { return }
                let mask = try autoreleasepool { try self.mask(picture, pts: pts, size: &size) }
                job.masks.append(mask)
                job.analysedDone.append(k)
                if Date().timeIntervalSince(lastPublish) >= publishInterval,
                    let through = covered(range, analysedDone: job.analysedDone, finished: false),
                    through.upperBound >= job.from
                {
                    try publish(request, &job, through: through, size: size)
                    lastPublish = Date()
                }
            }
            guard finished else { return false }
            try publish(request, &job, through: range, size: size)
            before += range.count
        }
        return true
    }

    /// One range's job state: its frames and masks not yet published.
    private struct Job {
        let range: ClosedRange<Int>
        let grid: AnalysisGrid
        var from: Int
        var frames: [(pts: Int64, index: Int32)] = []
        var masks: [MaskPack.Analysed] = []
        var analysedDone: [Int] = []

        init(range: ClosedRange<Int>, grid: AnalysisGrid) {
            self.range = range
            self.grid = grid
            from = range.lowerBound
        }
    }

    /// Whether the frame at `pts` is analysed: every frame at "every"; at r a
    /// second, the first frame at or after some k / r s (`previous` the
    /// frame before it, nil at the media's start).
    static func analysed(_ pts: Int64, after previous: Int64?, rate: Double?) -> Bool {
        guard let rate else { return true }
        let k = (Double(pts) * rate / 600_000).rounded(.down)
        guard let previous else { return true }
        return k * 600_000 > Double(previous) * rate
    }

    /// Publishes the job's frames through `through` (the range's indices
    /// covered so far) and the masks they need; keeps the last mask for the
    /// frames after it.
    private static func publish(
        _ request: AnalysisRequest, _ job: inout Job, through: ClosedRange<Int>,
        size: (width: Int, height: Int)?
    ) throws {
        let covering = job.from...through.upperBound
        let frames = job.frames.filter { covering.contains(Int($0.index)) }
        let times = job.masks.map(\.pts)
        let rows = frames.map { frame -> (pts: Int64, index: Int32, maskPts: Int64) in
            (frame.pts, frame.index, nearest(frame.pts, in: times) ?? frame.pts)
        }
        let masks = job.masks
        try AnalysisStore.publishFile(
            kind: .masks, cacheDir: request.cacheDir, mediaID: request.media.id,
            stamp: request.stamp, covered: [covering], files: [MaskPack.fileName]
        ) { onDisk, partial in
            try MaskPack.write(
                onDisk: onDisk, partial: partial, width: size?.width ?? 0,
                height: size?.height ?? 0, frames: rows, masks: masks)
        }
        job.frames.removeAll { covering.contains(Int($0.index)) }
        job.masks = job.masks.last.map { [$0] } ?? []
        job.from = through.upperBound + 1
    }

    /// The member of sorted `times` nearest `pts`, ties to the earlier.
    static func nearest(_ pts: Int64, in times: [Int64]) -> Int64? {
        var best: Int64?
        for t in times {
            guard let b = best else {
                best = t
                continue
            }
            let d = abs(t - pts), e = abs(b - pts)
            if d < e || (d == e && t < b) { best = t }
        }
        return best
    }

    /// One fresh request on `picture`, its mask compressed, `found` set.
    private static func mask(
        _ picture: AnalysisPicture, pts: Int64, size: inout (width: Int, height: Int)?
    ) throws -> MaskPack.Analysed {
        var wrapped: CVPixelBuffer?
        guard CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault, picture.width, picture.height, kCVPixelFormatType_32BGRA,
            UnsafeMutableRawPointer(mutating: picture.bytes), picture.bytesPerRow, nil, nil, nil,
            &wrapped) == kCVReturnSuccess, let wrapped
        else { throw AnalysisFrames.ReadError.reader("the frame could not be wrapped") }
        let request = makeRequest()
        let named = AnalysisVision.pin(request, to: computeDevice)
        guard named == device else { throw MaskError.device(named) }
        try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform([request])
        var bytes: [UInt8]
        if let buffer = request.results?.first?.pixelBuffer {
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
            if let size, size != (w, h) { throw MaskError.size(w, h, size.width, size.height) }
            size = (w, h)
            bytes = [UInt8](repeating: 0, count: w * h)
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                let row = CVPixelBufferGetBytesPerRow(buffer)
                bytes.withUnsafeMutableBytes { out in
                    for y in 0..<h { memcpy(out.baseAddress! + y * w, base + y * row, w) }
                }
            }
        } else {
            guard let size else { throw MaskError.noMask(pts) }
            bytes = [UInt8](repeating: 0, count: size.width * size.height)
        }
        let (w, h) = size ?? (0, 0)
        let found = bytes.withUnsafeBytes { MaskPack.found($0, width: w, height: h) }
        guard let compressed = try? (Data(bytes) as NSData).compressed(using: .lzfse) as Data
        else { throw AnalysisStore.StoreError.write("a mask could not be compressed") }
        return MaskPack.Analysed(pts: pts, compressed: compressed, found: found)
    }
}
