// Built by tools/proof/log_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`), for its `composition-gap` mode (issue
// batch B102, #294). See that script's header.
//
// One frame of a saved package, read at three stages of the composition
// path, so the stage where a VP9 file and an HEVC file holding the same codes
// part can be named:
//   - `tap`: the first source frame AVFoundation hands a probe-local
//     `AVVideoCompositing` class. The composition is the built one's
//     configuration with only `customVideoCompositorClass` swapped, and the
//     tap answers the built class's `sourcePixelBufferAttributes`,
//     `canConformColorOfSourceFrames` and `supportsHDRSourceFrames`, read off
//     an instance of it.
//   - `reader`: `AVAssetReaderVideoCompositionOutput` over the built
//     `videoComposition` at `Compositor.outputPixelFormat`
//     (precision_encoder_probe.swift's way): what the app's compositor drew.
//   - `generator`: `Exporter.renderFrame(project:urls:at:maxWidth: nil)`
//     drawn into a 16-bit-float context in the image's OWN space, so no
//     conversion happens: what `render_frame` writes.
// `DecoderSupport.enable()` runs first: without the opt-in no VP9 file reads.
//
//   composition_gap_probe <request.json> <answer.json>
//
// The request: {"frames": [{"tag", "package", "tick"}], "points": [[x, y]]}.
// The answer: {"rows": [{"tag", "compositor", "track": {primaries, transfer,
// matrix, full_range}, "tap": {"format", "width", "height", "attachments",
// "values"}, "reader": {"values"}, "generator": {"space", "bits", "values"}}
// or {"tag", "error"}]}, each `values` [[x, y, [r, g, b]]] in floats 0…1 (a
// biplanar tap frame as its 10-bit Y, Cb, Cr codes over 1023).
import AVFoundation
import AppKit

DecoderSupport.enable()

let arguments = CommandLine.arguments
let request =
    (try? JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "")))
        as? [String: Any]) ?? [:]
let outURL = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "")
let points = ((request["points"] as? [[Int]]) ?? []).filter { $0.count == 2 }

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

func fourcc(_ format: OSType) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((format >> UInt32($0)) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii) ?? "\(format)"
}

/// The values at `points` in `buffer`, by its own pixel format; nil for a
/// format this probe does not read.
func pixelValues(_ buffer: CVPixelBuffer) -> [[Any]]? {
    let format = CVPixelBufferGetPixelFormatType(buffer)
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    var answered: [[Any]] = []
    for point in points {
        let x = point[0], y = point[1]
        guard x < width, y < height else { return nil }
        var triple: [Double]
        switch format {
        case kCVPixelFormatType_64RGBAHalf:
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
                .assumingMemoryBound(to: Float16.self)
            triple = (0..<3).map { Double(row[x * 4 + $0]) }
        case kCVPixelFormatType_128RGBAFloat:
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer))
                .assumingMemoryBound(to: Float32.self)
            triple = (0..<3).map { Double(row[x * 4 + $0]) }
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            guard let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
            else { return nil }
            let yy = luma.advanced(by: y * CVPixelBufferGetBytesPerRowOfPlane(buffer, 0))
                .assumingMemoryBound(to: UInt16.self)[x]
            let pair = chroma.advanced(by: (y / 2) * CVPixelBufferGetBytesPerRowOfPlane(buffer, 1))
                .assumingMemoryBound(to: UInt16.self)
            triple = [Double(yy >> 6) / 1023, Double(pair[(x / 2) * 2] >> 6) / 1023,
                      Double(pair[(x / 2) * 2 + 1] >> 6) / 1023]
        default:
            return nil
        }
        answered.append([x, y, triple])
    }
    return answered
}

func attachments(_ buffer: CVPixelBuffer) -> [String: String] {
    guard let found = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any]
    else { return [:] }
    return found.mapValues { "\($0)" }
}

/// The tap: the first source frame of the first request it serves, and a
/// blank composed frame for every request.
final class TapCompositor: NSObject, AVVideoCompositing {
    static var attributes: [String: any Sendable]?
    static var conforms = false
    static var hdr = false
    static let lock = NSLock()
    static var captured: [String: Any]?

    var sourcePixelBufferAttributes: [String: any Sendable]? { TapCompositor.attributes }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }
    var canConformColorOfSourceFrames: Bool { TapCompositor.conforms }
    var supportsHDRSourceFrames: Bool { TapCompositor.hdr }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        TapCompositor.lock.lock()
        if TapCompositor.captured == nil, let id = request.sourceTrackIDs.first,
            let frame = request.sourceFrame(byTrackID: id.int32Value)
        {
            var row: [String: Any] = [
                "format": fourcc(CVPixelBufferGetPixelFormatType(frame)),
                "width": CVPixelBufferGetWidth(frame), "height": CVPixelBufferGetHeight(frame),
                "attachments": attachments(frame),
            ]
            row["values"] = pixelValues(frame).map { $0 as Any } ?? NSNull()
            TapCompositor.captured = row
        }
        TapCompositor.lock.unlock()
        guard let out = request.renderContext.newPixelBuffer() else {
            request.finish(with: ProbeFailure(description: "no pixel buffer"))
            return
        }
        request.finish(withComposedVideoFrame: out)
    }
}

func openDocument(_ path: String) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = URL(fileURLWithPath: path)
    } catch {
        return nil
    }
    return document
}

/// One frame of `composition` at `tick` through a composition output at
/// `Compositor.outputPixelFormat`.
func readFrame(
    _ asset: AVAsset, _ composition: AVVideoComposition, tick: Ticks, duration: CMTime
) throws -> CVPixelBuffer {
    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = CMTimeRange(start: CompositionBuilder.time(tick), duration: duration)
    let output = AVAssetReaderVideoCompositionOutput(
        videoTracks: asset.tracks(withMediaType: .video),
        videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
    output.videoComposition = composition
    output.alwaysCopiesSampleData = true
    guard reader.canAdd(output) else { throw ProbeFailure(description: "the output was refused") }
    reader.add(output)
    guard reader.startReading() else {
        throw ProbeFailure(description: "the reader did not start: \(String(describing: reader.error))")
    }
    defer { reader.cancelReading() }
    guard let sample = output.copyNextSampleBuffer(),
        let buffer = CMSampleBufferGetImageBuffer(sample)
    else {
        throw ProbeFailure(description: "no frame: \(String(describing: reader.error))")
    }
    return buffer
}

/// `image` drawn into a 16-bit-float RGBA context in its own space, read at
/// `points`.
func generatorValues(_ image: CGImage) -> [[Any]]? {
    guard let space = image.colorSpace,
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 16,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return nil }
    let rowBytes = context.bytesPerRow
    var answered: [[Any]] = []
    for point in points {
        let x = point[0], y = point[1]
        guard x < image.width, y < image.height else { return nil }
        let row = data.advanced(by: y * rowBytes).assumingMemoryBound(to: Float16.self)
        answered.append([x, y, (0..<3).map { Double(row[x * 4 + $0]) }])
    }
    return answered
}

func trackLabels(_ url: URL?) -> [String: Any] {
    guard let url = url,
        let track = CompositionBuilder.firstTrack(of: AVURLAsset(url: url), mediaType: .video),
        let description = (CompositionBuilder.keyed(track, "formatDescriptions")
            as? [CMFormatDescription])?.first
    else { return ["error": "no video track"] }
    func ext(_ key: CFString) -> String {
        CMFormatDescriptionGetExtension(description, extensionKey: key).map { "\($0)" } ?? "none"
    }
    return [
        "primaries": ext(kCMFormatDescriptionExtension_ColorPrimaries),
        "transfer": ext(kCMFormatDescriptionExtension_TransferFunction),
        "matrix": ext(kCMFormatDescriptionExtension_YCbCrMatrix),
        "full_range": CompositionBuilder.isFullRange(track),
    ]
}

func probe(_ spec: [String: Any]) -> [String: Any] {
    let tag = spec["tag"] as? String ?? "?"
    guard let document = openDocument(spec["package"] as? String ?? "") else {
        return ["tag": tag, "error": "the package would not open"]
    }
    let project = document.project
    guard let plan = project.plan, plan.duration > 0 else {
        return ["tag": tag, "error": "the project has no plan"]
    }
    let tick = Ticks(spec["tick"] as? Int ?? 0)
    let urls = document.mediaURLs()
    let key = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(key) }
    RecipeSource.shared.set(project, for: key)
    RecipeSource.shared.setOptions(.none, for: key)
    let built: BuiltComposition
    do {
        built = try CompositionBuilder.build(
            plan: plan, planJSON: project.planJSON, urls: urls, recipeKey: key)
    } catch {
        return ["tag": tag, "error": "the composition would not build: \(error)"]
    }
    let compositorClass = built.videoConfiguration.customVideoCompositorClass
    var row: [String: Any] = [
        "tag": tag,
        "compositor": compositorClass.map { NSStringFromClass($0) } ?? "none",
        "track": trackLabels(urls.values.first),
    ]
    // The built class's three answers, read off an instance of it.
    if let made = (compositorClass as? NSObject.Type)?.init() as? AVVideoCompositing {
        TapCompositor.attributes = made.sourcePixelBufferAttributes ?? nil
        TapCompositor.conforms = made.canConformColorOfSourceFrames ?? false
        TapCompositor.hdr = made.supportsHDRSourceFrames ?? false
    } else {
        return ["tag": tag, "error": "the built compositor class could not be made"]
    }
    TapCompositor.captured = nil
    var configuration = built.videoConfiguration
    configuration.customVideoCompositorClass = TapCompositor.self
    let duration = built.videoConfiguration.frameDuration
    do {
        _ = try readFrame(
            built.composition, AVVideoComposition(configuration: configuration), tick: tick,
            duration: duration)
        row["tap"] = TapCompositor.captured ?? ["error": "the tap saw no source frame"]
    } catch {
        row["tap"] = ["error": "\(error)"]
    }
    do {
        let buffer = try readFrame(
            built.composition, built.videoComposition, tick: tick, duration: duration)
        row["reader"] = ["values": pixelValues(buffer).map { $0 as Any } ?? NSNull()]
    } catch {
        row["reader"] = ["error": "\(error)"]
    }
    if let image = Exporter.renderFrame(project: project, urls: urls, at: tick, maxWidth: nil) {
        row["generator"] = [
            "space": (image.colorSpace?.name as String?) ?? "unnamed",
            "bits": image.bitsPerComponent,
            "values": generatorValues(image).map { $0 as Any } ?? NSNull(),
        ]
    } else {
        row["generator"] = ["error": "renderFrame answered nil"]
    }
    return row
}

NSApplication.shared.setActivationPolicy(.prohibited)
var rows: [[String: Any]] = []
for spec in request["frames"] as? [[String: Any]] ?? [] {
    rows.append(probe(spec))
}
let data = (try? JSONSerialization.data(
    withJSONObject: ["rows": rows], options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
try? data.write(to: outURL)
exit(0)
