import CoreML
import Foundation
import Vision

/// The `subjects` kind (spec §11 VR-10, VR-11; road map "creator-jobs" VR1):
/// the people and the salient regions Vision finds in a media's picture, per
/// sample of source time, kept as one `samples.bin` per media
/// (`AnalysisSubjects+Samples.swift`). View ▸ Show Subjects draws them, and
/// `get_media_analysis {kind: "subjects"}` answers them.
///
/// **The grid** is a sample grid, `rate` a second (`AnalysisKind.grid(of:)`),
/// sampled by `faces`' rule (CJ-33, `AnalysisSampleJob`): sample k takes the
/// first kept frame in `[ticks(k), ticks(k) + one sample interval)`, else none.
///
/// **The requests**, each FRESH per frame and performed together on ONE fresh
/// `VNImageRequestHandler`: `VNDetectHumanRectanglesRequest` revision 2 with
/// `upperBodyOnly` true (spec §11 VR-4 as VR-10 amends it) and
/// `VNGenerateAttentionBasedSaliencyImageRequest` revision 2, whose
/// `salientObjects` are the salient boxes. Each is pinned to its device (VR-11,
/// CJ-32) and a job refuses to run when a request reads back another
/// (`SubjectError.device`). No stateful request, no tracking (VR-4); boxes
/// carry no identity (CJ-31).
///
/// **The frames** are read through `AnalysisFrames.read`'s standard arms at
/// `min(longSide, the media's long side)`, as `faces`' are.
enum AnalysisSubjects {
    static let payloadName = "samples.bin"

    /// VR-11, VR-S1 rule 1: samples a second.
    static let rate: Double = AnalysisFaces.rate
    /// VR-11, CJ-S2 rule 3 re-run: the read's long side (at most the media's own).
    static let longSide = AnalysisFaces.longSide
    /// VR-11, CJ-S2 rule 1 per request.
    static let peopleDevice: AnalysisVision.Device = .neuralEngine
    static let salientDevice: AnalysisVision.Device = .neuralEngine
    static let publishInterval: TimeInterval = 30

    /// Each request's pinned readback, once.
    static let peopleReadback = AnalysisVision.pin(makePeople(), to: peopleDevice)
    static let salientReadback = AnalysisVision.pin(makeSalient(), to: salientDevice)
    /// The stamp's `device`: `people:<readback>;salient:<readback>`.
    static let device = "people:\(peopleReadback);salient:\(salientReadback)"

    /// The rate as the stamp spells it: "10", "5".
    static var rateName: String {
        rate == rate.rounded() ? String(Int(rate)) : String(rate)
    }

    static let vision = AnalysisVisionStamp(
        request: "human_rectangles+attention_saliency", quality: "upper_body", revision: 2,
        rate: rateName, readSize: String(longSide))

    /// What the stored samples depend on: the stamp's digest.
    static let parameters: [String: Any] = [
        "request": vision.request, "quality": vision.quality, "revision": vision.revision,
        "rate": vision.rate, "read_size": vision.readSize, "upper_body_only": true,
        "people_device": peopleDevice.rawValue, "salient_device": salientDevice.rawValue,
        "file_version": Int(fileVersion), "record_bytes": Int(recordBytes),
        "sample": "first_frame_at_or_after_within_one_interval",
        "order": "box_centre_x_then_y", "salient": "salient_objects",
    ]

    /// A fresh person request, revision 2, upper body only (VR-4 as amended).
    static func makePeople() -> VNDetectHumanRectanglesRequest {
        let request = VNDetectHumanRectanglesRequest()
        request.revision = VNDetectHumanRectanglesRequestRevision2
        request.upperBodyOnly = true
        return request
    }

    /// A fresh attention-based saliency request, revision 2.
    static func makeSalient() -> VNGenerateAttentionBasedSaliencyImageRequest {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        request.revision = VNGenerateAttentionBasedSaliencyImageRequestRevision2
        return request
    }

    enum SubjectError: LocalizedError {
        case device(String)

        var errorDescription: String? {
            switch self {
            case .device(let named):
                return "a subjects request ran on \(named), not \(AnalysisSubjects.device)"
            }
        }
    }

    /// The people and salient boxes in `picture`: both requests (above), each
    /// group ordered (CJ-31).
    static func subjects(in picture: AnalysisPicture) throws -> Subjects {
        var wrapped: CVPixelBuffer?
        guard CVPixelBufferCreateWithBytes(
            kCFAllocatorDefault, picture.width, picture.height, kCVPixelFormatType_32BGRA,
            UnsafeMutableRawPointer(mutating: picture.bytes), picture.bytesPerRow, nil, nil, nil,
            &wrapped) == kCVReturnSuccess, let wrapped
        else { throw AnalysisFrames.ReadError.reader("the frame could not be wrapped") }
        let people = makePeople()
        let named = AnalysisVision.pin(people, to: peopleDevice)
        guard named == peopleReadback else { throw SubjectError.device("people:\(named)") }
        let salient = makeSalient()
        let salientNamed = AnalysisVision.pin(salient, to: salientDevice)
        guard salientNamed == salientReadback else {
            throw SubjectError.device("salient:\(salientNamed)")
        }
        try VNImageRequestHandler(cvPixelBuffer: wrapped, options: [:]).perform([people, salient])
        let found = (people.results ?? []).map { box($0.boundingBox, $0.confidence) }
        let regions = (salient.results?.first?.salientObjects ?? []).map {
            box($0.boundingBox, $0.confidence)
        }
        return Subjects(people: ordered(found), salient: ordered(regions))
    }

    /// Vision's lower-left box in CJ-22's frame (`AnalysisFaces.topLeft`).
    static func box(_ rect: CGRect, _ confidence: Float) -> Box {
        let b = AnalysisFaces.topLeft(rect)
        return Box(
            x: Float(b.minX), y: Float(b.minY), width: Float(b.width), height: Float(b.height),
            confidence: confidence)
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
            cancelled: cancelled, progress: progress, analyse: { try subjects(in: $0) }
        ) { covering, found in
            try AnalysisStore.publishFile(
                kind: .subjects, cacheDir: request.cacheDir, mediaID: request.media.id,
                stamp: request.stamp, covered: [covering], files: [payloadName]
            ) { onDisk, partial in
                try write(
                    onDisk: onDisk, partial: partial, count: grid.count, covering: covering,
                    samples: found.mapValues { Sample(pts: $0.pts, subjects: $0.value) })
            }
        }
    }
}
