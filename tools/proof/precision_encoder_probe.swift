// Built by tools/proof/precision_proof.py as `main.swift` over every other file
// in `app/Sources` (`swift_build.py`). See that script's header, row E1.
//
// The precision road map's E1 and E2 (spec §11 PR-3; the orchestrator's ruling
// after PR0): what `ExportWriter` hands the `h264` (E1) and `hevc` (E2)
// encoders. VideoToolbox's H.264 encode is not repeatable run to run, so an
// encoded file cannot carry the claim; the encoder's INPUT can. For each
// package: the export's settings resolved by the core (`ReelExport.settings`,
// the frame's `preset`, `h264` when it names none), the composition
// built as an export builds it (`CompositionBuilder.build`,
// `ExportWriter.videoComposition`), one frame read through an
// `AVAssetReaderVideoCompositionOutput` in `Compositor.outputPixelFormat` with
// the reader's own copy — `ExportWriter`'s output, setting for setting — then
// `ExportWriter.frameForm(settings)`: when it names a form, the frame
// `ExportFrames(form:).convert` hands the writer; when it is nil, the reader's
// frame as it is, which is what the writer would get.
//
// argv[1] is the request (JSON), argv[2] the answer (JSON). The request is
// `{"fonts", "frames": [{"tag", "package", "tick", "raw", "preset"}]}`; each answer row is
// `{"tag", "form", "format", "width", "height"}` (the handed buffer's
// fourcc, and `raw` written with its pixel rows packed, 32BGRA only), or
// `{"tag", "error"}`.
import AVFoundation
import AppKit

let arguments = CommandLine.arguments
let requestURL = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "")
let outURL = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "")
let request =
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: requestURL)) as? [String: Any])
    ?? [:]

func fourcc(_ format: OSType) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((format >> UInt32($0)) & 0xFF) }
    return String(bytes: bytes, encoding: .ascii) ?? "\(format)"
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

func handed(_ spec: [String: Any]) -> [String: Any] {
    let tag = spec["tag"] as? String ?? "?"
    guard let document = openDocument(spec["package"] as? String ?? "") else {
        return ["tag": tag, "error": "the package would not open"]
    }
    let project = document.project
    guard let plan = project.plan, plan.duration > 0 else {
        return ["tag": tag, "error": "the project has no plan"]
    }
    let preset = spec["preset"] as? String ?? "h264"
    let settings: ExportSettings
    do {
        settings = try ReelExport.settings(project, preset: preset)
    } catch {
        return ["tag": tag, "error": "no \(preset) settings: \(error)"]
    }
    let key = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(key) }
    RecipeSource.shared.set(project, for: key)
    RecipeSource.shared.setOptions(.none, for: key)
    let built: BuiltComposition
    do {
        built = try CompositionBuilder.build(
            plan: plan, planJSON: project.planJSON, urls: document.mediaURLs(), recipeKey: key)
    } catch {
        return ["tag": tag, "error": "the composition would not build: \(error)"]
    }
    let reader: AVAssetReader
    do {
        reader = try AVAssetReader(asset: built.composition)
    } catch {
        return ["tag": tag, "error": "no reader: \(error)"]
    }
    let tick = Ticks(spec["tick"] as? Int ?? 0)
    reader.timeRange = CMTimeRange(
        start: CompositionBuilder.time(tick),
        duration: CompositionBuilder.frameDuration(project.snapshot.canvas.fps))
    let output = AVAssetReaderVideoCompositionOutput(
        videoTracks: built.composition.tracks(withMediaType: .video),
        videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
    output.videoComposition = ExportWriter.videoComposition(built, settings: settings)
    output.alwaysCopiesSampleData = true
    guard reader.canAdd(output) else { return ["tag": tag, "error": "the output was refused"] }
    reader.add(output)
    guard reader.startReading(), let sample = output.copyNextSampleBuffer() else {
        return ["tag": tag, "error": "no frame: \(String(describing: reader.error))"]
    }
    defer { reader.cancelReading() }
    let form = ExportWriter.frameForm(settings)
    let ready: CMSampleBuffer?
    if let form = form {
        ready = ExportFrames(form: form).convert(sample)
    } else {
        ready = sample
    }
    guard let given = ready, let buffer = CMSampleBufferGetImageBuffer(given) else {
        return ["tag": tag, "form": "\(String(describing: form))",
                "error": "the conversion answered nil"]
    }
    let format = CVPixelBufferGetPixelFormatType(buffer)
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    var row: [String: Any] = [
        "tag": tag, "form": form.map { "\($0)" } ?? "nil (the frame as drawn)",
        "format": fourcc(format), "width": width, "height": height,
        "time": CMSampleBufferGetPresentationTimeStamp(sample).seconds,
    ]
    guard format == kCVPixelFormatType_32BGRA, let raw = spec["raw"] as? String,
        CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return row }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return row }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    var packed = Data(capacity: width * height * 4)
    for y in 0..<height {
        packed.append(Data(bytes: base + y * bytesPerRow, count: width * 4))
    }
    do {
        try packed.write(to: URL(fileURLWithPath: raw))
        row["raw"] = raw
    } catch {
        row["error"] = "the raw frame was not written: \(error)"
    }
    return row
}

NSApplication.shared.setActivationPolicy(.prohibited)
// The app's bundled faces, as `ATSApplicationFontsPath` registers them for the
// bundle: a bare binary has none, and a title would draw in a fallback face.
let fonts = URL(fileURLWithPath: request["fonts"] as? String ?? "/nonexistent")
for name in (try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}
var rows: [[String: Any]] = []
for spec in request["frames"] as? [[String: Any]] ?? [] {
    rows.append(handed(spec))
}
let data = (try? JSONSerialization.data(
    withJSONObject: ["frames": rows], options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
try? data.write(to: outURL)
exit(0)
