// Built by tools/proof/matte_probe.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header.
//
// Road map "mattes", phase MT3 (spec §11 MT-3, MT-6): a matte under View ▸
// Preview Quality — and since issue batch B90 phase 4 (spec §11 MT-8) a routed
// dissolve and zoom between nest clips, the same way. Each fixture is rendered at Full, Half and Quarter through
// the app's own path — the document, `CompositionBuilder.build`,
// `Playback.previewComposition` (called), `Compositor`, `MetalRenderer`, the
// project's own shader beside the binary — and read back by
// `AVAssetImageGenerator`, as `phase8_chrome.py`'s section 9 does. Nothing
// here fills a uniform or a coverage by hand. Every measurement is a colour
// CLASS's coverage and bounding box as FRACTIONS of the frame, because the
// question is whether one picture survives three destination sizes.
//
// argv[1] is the request (JSON), argv[2] the answer (JSON). The request is
// `{"renders": [{"tag", "package", "tick", "classes": [{"name", "low",
// "high"}]}]}`; the answer `{"renders": [{"tag", "quality", "canvas",
// "destination", "width", "height", "classes": {name: {"count", "coverage",
// "x0", "x1", "y0", "y1"}}} | {"tag", "quality", "error"}]}`.
import AVFoundation
import AppKit

let arguments = CommandLine.arguments
let requestURL = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "")
let outURL = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "")
let request =
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: requestURL)) as? [String: Any])
    ?? [:]
var answer: [String: Any] = [:]

func finish() {
    let data = (try? JSONSerialization.data(
        withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    try? data.write(to: outURL)
}

func openDocument(_ path: String) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
        document.fileURL = URL(fileURLWithPath: path)
    } catch {
        return nil
    }
    return document
}

/// One frame as straight 8-bit RGBA in sRGB, redrawn into a known space
/// because the generator hands back whatever space the composition used.
func framePixels(_ image: CGImage) -> ([UInt8], Int, Int)? {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let drawn: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (bytes, width, height) : nil
}

struct ColorClass {
    let name: String
    let low: [Int]
    let high: [Int]
}

func measureFrame(_ image: CGImage, _ classes: [ColorClass]) -> [String: Any] {
    guard let (pixels, width, height) = framePixels(image) else {
        return ["error": "the frame could not be read back"]
    }
    var count = [Int](repeating: 0, count: classes.count)
    var minX = [Int](repeating: width, count: classes.count)
    var maxX = [Int](repeating: -1, count: classes.count)
    var minY = [Int](repeating: height, count: classes.count)
    var maxY = [Int](repeating: -1, count: classes.count)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            for (n, klass) in classes.enumerated() {
                guard r >= klass.low[0], r <= klass.high[0], g >= klass.low[1],
                    g <= klass.high[1], b >= klass.low[2], b <= klass.high[2]
                else { continue }
                count[n] += 1
                minX[n] = min(minX[n], x); maxX[n] = max(maxX[n], x)
                minY[n] = min(minY[n], y); maxY[n] = max(maxY[n], y)
            }
        }
    }
    var measured: [String: Any] = [:]
    for (n, klass) in classes.enumerated() {
        var entry: [String: Any] = [
            "count": count[n], "coverage": Double(count[n]) / Double(width * height),
        ]
        if count[n] > 0 {
            entry["x0"] = Double(minX[n]) / Double(width)
            entry["x1"] = Double(maxX[n] + 1) / Double(width)
            entry["y0"] = Double(minY[n]) / Double(height)
            entry["y1"] = Double(maxY[n] + 1) / Double(height)
        }
        measured[klass.name] = entry
    }
    return ["width": width, "height": height, "classes": measured]
}

/// One frame of one document at one quality, through the app's own path:
/// the scaling is `Playback.previewComposition` itself, called.
func renderPreviewFrame(
    _ document: ProjectDocument, quality: PreviewQuality, at tick: Ticks
) -> (CGImage?, CGSize, CGSize, String?) {
    let project = document.project
    guard let plan = project.plan, plan.duration > 0 else {
        return (nil, .zero, .zero, "the project has no plan")
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
        return (nil, .zero, .zero, "the composition would not build: \(error)")
    }
    let base: AVVideoComposition = built.videoComposition
    let composition = Playback.previewComposition(built, quality: quality)
    let generator = AVAssetImageGenerator(asset: built.composition)
    generator.videoComposition = composition
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = false
    do {
        let image = try generator.copyCGImage(
            at: CompositionBuilder.time(max(0, tick)), actualTime: nil)
        return (image, base.renderSize, composition.renderSize, nil)
    } catch {
        return (nil, base.renderSize, composition.renderSize, "no frame: \(error)")
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)
var rendered: [[String: Any]] = []
for spec in request["renders"] as? [[String: Any]] ?? [] {
    let tag = spec["tag"] as? String ?? "?"
    let classes = (spec["classes"] as? [[String: Any]] ?? []).map {
        ColorClass(
            name: $0["name"] as? String ?? "?",
            low: $0["low"] as? [Int] ?? [0, 0, 0],
            high: $0["high"] as? [Int] ?? [255, 255, 255])
    }
    guard let document = openDocument(spec["package"] as? String ?? "") else {
        rendered.append(["tag": tag, "error": "the package would not open"])
        continue
    }
    let tick = Ticks(spec["tick"] as? Int ?? 0)
    for quality in PreviewQuality.allCases {
        let (image, canvas, destination, error) = renderPreviewFrame(
            document, quality: quality, at: tick)
        var row: [String: Any] = [
            "tag": tag, "quality": quality.rawValue,
            "canvas": [Int(canvas.width), Int(canvas.height)],
            "destination": [Int(destination.width), Int(destination.height)],
        ]
        if let image = image {
            for (key, value) in measureFrame(image, classes) { row[key] = value }
        } else {
            row["error"] = error ?? "no frame and no reason"
        }
        rendered.append(row)
    }
}
answer["renders"] = rendered
finish()
exit(0)
