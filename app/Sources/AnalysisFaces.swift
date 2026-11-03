import CoreML
import Foundation
import Vision

/// The `faces` kind (spec §11 CJ-30…CJ-34; road map "creator-jobs" CJ3):
/// every face Vision finds in a media's picture, per sample of source time,
/// kept as one `samples.bin` per media (`AnalysisFaces+Samples.swift`).
/// Nothing visible; `get_media_analysis {kind: "faces"}` answers the samples.
///
/// **The grid** is the sample grid, `rate` a second (`AnalysisKind.grid(of:)`):
/// sample k at `ticks(k)` takes the first kept frame whose pts lies in
/// `[ticks(k), ticks(k) + one sample interval)`, else none (pts −1, no faces),
/// whatever the job's bounds; a frame serving two samples is analysed once
/// (CJ-33, `samples(at:after:grid:)`).
///
/// **The requests**, each FRESH on a fresh `VNImageRequestHandler` per frame:
/// `VNDetectFaceRectanglesRequest` revision 3 (box, confidence, roll, yaw),
/// then, with `landmarks`, `VNDetectFaceLandmarksRequest` revision 3 with
/// `.constellation76Points` over those faces (the mouth's inner-lip gap and
/// outer-lip width, each over the box's height in picture pixels). Each is
/// pinned to its device (CJ-32) and a job refuses to run when a request reads
/// back another (`FaceError.device`).
///
/// **The frames** are read through `AnalysisFrames.read`'s standard arms (the
/// direct reader, or the converted one for a converting media, CJ-S2 rule 5)
/// at `min(longSide, the media's long side)`. A job (`AnalysisSampleJob`)
/// publishes at each range's end and every `publishInterval`, mid-range only
/// through the samples decided.
enum AnalysisFaces {
    static let payloadName = "samples.bin"

    /// CJ-30, CJ-S2 rule 2: samples a second.
    static let rate: Double = 10
    /// CJ-30, CJ-S2 rule 3: the read's long side (at most the media's own).
    static let longSide = 720
    /// CJ-30, CJ-S2 rule 4: the mouth measures stay in this kind.
    static let landmarks = true
    /// CJ-32, CJ-S2 rule 1, per request.
    static let rectanglesDevice: AnalysisVision.Device = .neuralEngine
    static let landmarksDevice: AnalysisVision.Device = .neuralEngine
    static let publishInterval: TimeInterval = 30

    /// Each request's pinned readback, once.
    static let rectanglesReadback = AnalysisVision.pin(makeRectangles(), to: rectanglesDevice)
    static let landmarksReadback = AnalysisVision.pin(makeLandmarks([]), to: landmarksDevice)
    /// The stamp's `device`: `rectangles:<readback>;landmarks:<readback>`.
    static let device: String =
        "rectangles:\(rectanglesReadback)" + (landmarks ? ";landmarks:\(landmarksReadback)" : "")

    /// The rate as the stamp spells it: "10", "5", "2.5".
    static var rateName: String {
        rate == rate.rounded() ? String(Int(rate)) : String(rate)
    }

    static let vision = AnalysisVisionStamp(
        request: landmarks ? "face_rectangles+face_landmarks" : "face_rectangles",
        quality: landmarks ? "constellation_76" : "none", revision: 3, rate: rateName,
        readSize: String(longSide))

    /// What the stored samples depend on: the stamp's digest.
    static let parameters: [String: Any] = [
        "request": vision.request, "quality": vision.quality, "revision": vision.revision,
        "rate": vision.rate, "read_size": vision.readSize, "landmarks": landmarks,
        "rectangles_device": rectanglesDevice.rawValue,
        "landmarks_device": landmarksDevice.rawValue,
        "file_version": Int(fileVersion), "record_bytes": Int(recordBytes),
        "sample": "first_frame_at_or_after_within_one_interval",
        "order": "box_centre_x_then_y", "mouth": "inner_gap_outer_width_over_box_height",
    ]

    /// A fresh rectangles request, revision 3.
    static func makeRectangles() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }

    /// A fresh landmarks request over `faces`, revision 3, 76 points.
    static func makeLandmarks(_ faces: [VNFaceObservation]) -> VNDetectFaceLandmarksRequest {
        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3
        request.constellation = .constellation76Points
        request.inputFaceObservations = faces
        return request
    }

    enum FaceError: LocalizedError {
        case device(String)

        var errorDescription: String? {
            switch self {
            case .device(let named):
                return "a face request ran on \(named), not \(AnalysisFaces.device)"
            }
        }
    }

    /// Vision's lower-left box in CJ-22's frame: top-left, y down, 0…1.
    static func topLeft(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// CJ-31: by box centre x, then y (top-left frame), exact float compare.
    static func ordered(_ faces: [Face]) -> [Face] {
        faces.sorted { a, b in
            let ax = a.x + a.width / 2, bx = b.x + b.width / 2
            if ax != bx { return ax < bx }
            return a.y + a.height / 2 < b.y + b.height / 2
        }
    }

    /// Every face in `picture`: the requests (above), ordered.
    static func faces(in picture: AnalysisPicture) throws -> [Face] {
        var wrapped: CVPixelBuffer?
        guard CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault, picture.width, picture.height, kCVPixelFormatType_32BGRA,
            UnsafeMutableRawPointer(mutating: picture.bytes), picture.bytesPerRow, nil, nil, nil,
            &wrapped) == kCVReturnSuccess, let wrapped
        else { throw AnalysisFrames.ReadError.reader("the frame could not be wrapped") }
        let rectangles = makeRectangles()
        let named = AnalysisVision.pin(rectangles, to: rectanglesDevice)
        guard named == rectanglesReadback else { throw FaceError.device("rectangles:\(named)") }
        try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform([rectangles])
        let observations = rectangles.results ?? []
        var faces = observations.map { o -> Face in
            let box = topLeft(o.boundingBox)
            return Face(
                x: Float(box.minX), y: Float(box.minY), width: Float(box.width),
                height: Float(box.height), confidence: o.confidence,
                roll: o.roll?.floatValue ?? .nan, yaw: o.yaw?.floatValue ?? .nan,
                mouthGap: .nan, mouthWidth: .nan)
        }
        guard landmarks, !observations.isEmpty else { return ordered(faces) }
        let marks = makeLandmarks(observations)
        let markNamed = AnalysisVision.pin(marks, to: landmarksDevice)
        guard markNamed == landmarksReadback else { throw FaceError.device("landmarks:\(markNamed)") }
        try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform([marks])
        let size = CGSize(width: picture.width, height: picture.height)
        for (i, o) in (marks.results ?? []).enumerated() where i < faces.count {
            let (gap, width) = mouth(o, size: size)
            faces[i].mouthGap = gap
            faces[i].mouthWidth = width
        }
        return ordered(faces)
    }

    /// The inner lips' vertical extent and the outer lips' horizontal extent,
    /// each over the box's height in picture pixels (image axes, raw); NaN
    /// when Vision gave no lips.
    static func mouth(_ face: VNFaceObservation, size: CGSize) -> (Float, Float) {
        let boxHeight = Double(face.boundingBox.height) * Double(size.height)
        guard boxHeight > 0,
            let inner = face.landmarks?.innerLips?.pointsInImage(imageSize: size),
            let outer = face.landmarks?.outerLips?.pointsInImage(imageSize: size),
            let top = inner.map(\.y).max(), let bottom = inner.map(\.y).min(),
            let right = outer.map(\.x).max(), let left = outer.map(\.x).min()
        else { return (.nan, .nan) }
        return (Float((top - bottom) / boxHeight), Float((right - left) / boxHeight))
    }

    /// The samples of the sample grid `grid` the frame at `pts` serves —
    /// those k with `previous < ticks(k) ≤ pts` and `pts < ticks(k) + one
    /// interval` (`previous` the kept frame before it, nil at the media's
    /// start); nil when none.
    static func samples(at pts: Int64, after previous: Int64?, grid: AnalysisGrid)
        -> ClosedRange<Int>?
    {
        let after = previous ?? Int64.min
        let upto = pts
        var high = min(grid.lastIndex, Int((Double(upto) * grid.rate).rounded(.down)) + 1)
        while high >= 0, grid.ticks(of: high) > upto { high -= 1 }
        var low = high + 1
        while low > 0 {
            let t = grid.ticks(of: low - 1)
            guard t > after, Double(pts) < Double(t) + grid.frameTicks else { break }
            low -= 1
        }
        return low <= high ? low...high : nil
    }

    // MARK: - The job

    /// Runs `request`'s ranges (sample indices) in order through
    /// `AnalysisSampleJob`. False when `cancelled()` stopped it; `progress`
    /// hears the share of samples decided.
    static func run(
        _ request: AnalysisRequest, cancelled: () -> Bool, progress: (Double) -> Void
    ) throws -> Bool {
        let grid = request.kind.grid(of: request.media)
        return try AnalysisSampleJob.run(
            request, grid: grid, longSide: longSide, publishInterval: publishInterval,
            cancelled: cancelled, progress: progress, analyse: { try faces(in: $0) }
        ) { covering, found in
            try AnalysisStore.publishFile(
                kind: .faces, cacheDir: request.cacheDir, mediaID: request.media.id,
                stamp: request.stamp, covered: [covering], files: [payloadName]
            ) { onDisk, partial in
                try write(
                    onDisk: onDisk, partial: partial, count: grid.count, covering: covering,
                    samples: found.mapValues { Sample(pts: $0.pts, faces: $0.value) })
            }
        }
    }
}
