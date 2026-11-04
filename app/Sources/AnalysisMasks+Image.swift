import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// A picture's masks (spec §11 CO-105; road map "creator-jobs" CO10b): one mask per image
/// media and subject kind — `masks` for `person` (the person request and stamp
/// `AnalysisMasks.swift` keeps for movies) and `foreground` for `foreground`
/// (`VNGenerateForegroundInstanceMaskRequest`) — made from the picture as
/// `LayerRenderers.image` decodes it, upright, so the mask is in display orientation.
///
/// **The job** decodes once, runs one fresh, pinned request on a `cgImage` handler (refused
/// when the device it reads back is not the stamp's), and publishes a pack of one frame
/// `(pts 0, index 0, slot 0)` covering `0...0`. Progress is 0, then 1 after Vision; a cancel
/// before Vision answers false.
extension AnalysisMasks {

    /// CO-105: the foreground request's device, as the person request's (CO-11).
    static let foregroundComputeDevice: AnalysisVision.Device = .gpu
    /// The device a pinned foreground request reads back, once (the stamp's `device`).
    static let foregroundDevice: String =
        AnalysisVision.pin(makeForegroundRequest(), to: foregroundComputeDevice)

    static let foregroundVision = AnalysisVisionStamp(
        request: "foreground_instance_mask", quality: "none", revision: 1, rate: "one",
        readSize: "image")

    /// What the stored foreground masks depend on: the stamp's digest.
    static let foregroundParameters: [String: Any] = [
        "request": foregroundVision.request, "revision": foregroundVision.revision,
        "output": "scaled_one_component_8", "rate": foregroundVision.rate,
        "read_size": "image_\(LayerRenderers.maxTextureSide)",
        "found": "above_127_at_least_1_in_200", "compression": "lzfse",
        "pack_version": Int(MaskPack.version),
    ]

    /// A fresh foreground request, revision 1.
    static func makeForegroundRequest() -> VNGenerateForegroundInstanceMaskRequest {
        let request = VNGenerateForegroundInstanceMaskRequest()
        request.revision = VNGenerateForegroundInstanceMaskRequestRevision1
        return request
    }

    enum ForegroundMaskError: LocalizedError {
        case device(String)

        var errorDescription: String? {
            switch self {
            case .device(let named):
                return "the foreground mask request ran on \(named), not "
                    + "\(AnalysisMasks.foregroundDevice)"
            }
        }
    }

    /// `request`'s one mask (a `masks` or `foreground` request of an image media), published.
    /// False when `cancelled()` stopped it before Vision ran.
    static func runImage(
        _ request: AnalysisRequest, cancelled: () -> Bool, progress: (Double) -> Void
    ) throws -> Bool {
        progress(0)
        guard let image = MediaImporter.decodeImage(
            request.url, maxPixelSize: LayerRenderers.maxTextureSide)
        else { throw AnalysisFrames.ReadError.reader("the picture could not be decoded") }
        guard !cancelled() else { return false }
        let (bytes, width, height) = try autoreleasepool {
            request.kind == .foreground ? try foregroundMask(image) : try personMask(image)
        }
        progress(1)
        let found = bytes.withUnsafeBytes { MaskPack.found($0, width: width, height: height) }
        guard let compressed = try? (Data(bytes) as NSData).compressed(using: .lzfse) as Data
        else { throw AnalysisStore.StoreError.write("a mask could not be compressed") }
        let mask = MaskPack.Analysed(pts: 0, compressed: compressed, found: found)
        try AnalysisStore.publishFile(
            kind: request.kind, cacheDir: request.cacheDir, mediaID: request.media.id,
            stamp: request.stamp, covered: [0...0], files: [MaskPack.fileName]
        ) { onDisk, partial in
            try MaskPack.write(
                onDisk: onDisk, partial: partial, width: width, height: height,
                frames: [(pts: 0, index: 0, maskPts: 0)], masks: [mask])
        }
        return true
    }

    /// The person request's mask at Vision's own size; with no observation, an all-zero mask
    /// at the picture's size.
    private static func personMask(_ image: CGImage) throws -> ([UInt8], Int, Int) {
        let request = makeRequest()
        let named = AnalysisVision.pin(request, to: computeDevice)
        guard named == device else { throw MaskError.device(named) }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else {
            return ([UInt8](repeating: 0, count: image.width * image.height), image.width,
                image.height)
        }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        var bytes = [UInt8](repeating: 0, count: w * h)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let row = CVPixelBufferGetBytesPerRow(buffer)
            bytes.withUnsafeMutableBytes { out in
                for y in 0..<h { memcpy(out.baseAddress! + y * w, base + y * row, w) }
            }
        }
        return (bytes, w, h)
    }

    /// The foreground request's every instance, scaled to the picture, each float stored as
    /// `clamp(round(v · 255), 0, 255)`; with no observation or no instance, all zero.
    private static func foregroundMask(_ image: CGImage) throws -> ([UInt8], Int, Int) {
        let request = makeForegroundRequest()
        let named = AnalysisVision.pin(request, to: foregroundComputeDevice)
        guard named == foregroundDevice else { throw ForegroundMaskError.device(named) }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        guard let observation = request.results?.first, !observation.allInstances.isEmpty
        else { return (bytes, w, h) }
        let buffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler)
        let bw = CVPixelBufferGetWidth(buffer), bh = CVPixelBufferGetHeight(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (bytes, w, h) }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
        else {
            throw AnalysisFrames.ReadError.reader("Vision answered a foreground mask that is not float")
        }
        for y in 0..<min(h, bh) {
            let line = (base + y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<min(w, bw) {
                bytes[y * w + x] = UInt8(min(max((line[x] * 255).rounded(), 0), 255))
            }
        }
        return (bytes, w, h)
    }
}
