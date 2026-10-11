// Road map "grading", phase GR3 — the waveform's probe (`seeing_proof.py`
// builds it through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libreelcut_core.a`, so every row drives the app's own
// types: `WaveformAnalyzer`, `WaveformTrace`, `WaveformTaps` (attached with
// the waveform alone),
// `EditorViewController`'s two commands, `RecipeSource`. The kernel is the
// tree's own `Waveform.metal`, compiled from source here (a probe has no
// default library), so a mutant of the shader reaches the rows.
//
//   waveform_probe <request.json> <answer.json>
//
// `request.json` names `shader` (the tree's `Waveform.metal`) and `package`, a
// project the proof saved over MCP. One JSON object out: `rows`, each a name,
// ok and detail, the name starting with its row id; `records`, G1's figures.
import AppKit
import CoreVideo
import Metal

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
var records: [String: Any] = [:]
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}
func finish() -> Never {
    let answer: [String: Any] = ["rows": rows, "records": records]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

// MARK: - The analyser over the tree's own kernel

let shaderPath = request["shader"] as? String ?? ""
let device = MTLCreateSystemDefaultDevice()
let library = device.flatMap { device in
    (try? String(contentsOfFile: shaderPath, encoding: .utf8))
        .flatMap { try? device.makeLibrary(source: $0, options: nil) }
}
guard let device, let library, let analyzer = WaveformAnalyzer(device: device, library: library)
else {
    for name in ["P1", "P2", "P3", "P4", "P7"] {
        check("\(name) the kernel compiles from \(shaderPath)", false,
              "device \(device != nil), library \(library != nil)")
    }
    finish()
}

/// A `width` × `height` rgba16Float texture whose pixel (x, y) is `rgb(x, y)`.
func texture(_ width: Int, _ height: Int, _ rgb: (Int, Int) -> (Float, Float, Float))
    -> MTLTexture?
{
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .managed
    guard let made = device.makeTexture(descriptor: descriptor) else { return nil }
    var halves = [Float16](repeating: 1, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b) = rgb(x, y)
            let at = (y * width + x) * 4
            halves[at] = Float16(r)
            halves[at + 1] = Float16(g)
            halves[at + 2] = Float16(b)
        }
    }
    halves.withUnsafeBytes { bytes in
        if let base = bytes.baseAddress {
            made.replace(
                region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base,
                bytesPerRow: width * 8)
        }
    }
    return made
}

/// The non-zero cells of a trace as (column, level, count).
func cells(_ trace: WaveformTrace) -> [(Int, Int, UInt32)] {
    trace.counts.enumerated().compactMap { index, count in
        count > 0 ? (index / WaveformTrace.levels, index % WaveformTrace.levels, count) : nil
    }
}

/// The one level every pixel of a uniform `value` lands at, or nil.
func level(of rgb: (Float, Float, Float)) -> Int? {
    guard let made = texture(8, 8, { _, _ in rgb }), let trace = analyzer.analyze(texture: made)
    else { return nil }
    let levels = Set(cells(trace).map { $0.1 })
    return levels.count == 1 ? levels.first : nil
}

// MARK: - P1 a ramp, P2 grey

do {
    let height = 360
    let ramp = texture(256, height) { x, _ in
        let v = Float(x) / 255
        return (v, v, v)
    }
    let trace = ramp.flatMap { analyzer.analyze(texture: $0) }
    let found = trace.map(cells) ?? []
    let stray = found.filter { $0.0 != $0.1 || $0.2 != UInt32(height) }
    check(
        "P1 a 256-wide ramp of the 8-bit codes puts counts[c][c] = 360 (its height) for every c "
            + "and nothing else",
        trace != nil && found.count == 256 && stray.isEmpty,
        "cells \(found.count); stray \(stray.prefix(6))")
    let grey = level(of: (128.0 / 255, 128.0 / 255, 128.0 / 255))
    check("P2 grey 128 lands at level 128", grey == 128, "level \(String(describing: grey))")
}

// MARK: - P3 the weights, P4 the rounding and the saturation

do {
    let red = level(of: (1, 0, 0))
    let green = level(of: (0, 1, 0))
    let blue = level(of: (0, 0, 1))
    check(
        "P3 Rec. 709 luma: (1,0,0) → 54, (0,1,0) → 182, (0,0,1) → 18",
        red == 54 && green == 182 && blue == 18,
        "red \(String(describing: red)), green \(String(describing: green)), blue "
            + "\(String(describing: blue))")
    let cases: [(String, Float, Int)] = [
        ("254.6/255", 254.6 / 255, 255), ("254.4/255", 254.4 / 255, 254),
        ("0.4/255", 0.4 / 255, 0), ("0.6/255", 0.6 / 255, 1),
        ("1.5", 1.5, 255), ("-0.5", -0.5, 0),
    ]
    let got = cases.map { name, value, _ in (name, level(of: (value, value, value))) }
    let ok = zip(cases, got).allSatisfy { $0.0.2 == $0.1.1 }
    check(
        "P4 levels round: 254.6/255 → 255, 254.4/255 → 254, 0.4/255 → 0, 0.6/255 → 1; "
            + "1.5 → 255 and -0.5 → 0 (saturated)",
        ok, got.map { "\($0.0) → \(String(describing: $0.1))" }.joined(separator: ", "))
}

// MARK: - P5 the marks and the readouts

do {
    let levels = WaveformTrace.levels
    var counts = [UInt32](repeating: 0, count: WaveformTrace.columns * levels)
    // Column 10: 1000 pixels, 5 at 255 (0.5 %) → marked; column 11: 4 of
    // 1000 → not; column 12: 1 of 200 at 0 (0.5 %) → marked low; column 13:
    // 1 of 201 at 0 → not.
    counts[10 * levels + 128] = 995
    counts[10 * levels + 255] = 5
    counts[11 * levels + 128] = 996
    counts[11 * levels + 255] = 4
    counts[12 * levels + 128] = 199
    counts[12 * levels + 0] = 1
    counts[13 * levels + 128] = 200
    counts[13 * levels + 0] = 1
    let trace = WaveformTrace(counts: counts, width: 80, height: 30)
    let high = trace.marks(high: true)
    let low = trace.marks(high: false)
    // 2401 pixels counted over a 2400-pixel frame is fine for the readouts:
    // 9 high of 2400 is 0.375 % → "0.4 %"; 2 low → 0.0833 % → "0.1 %".
    check(
        "P5 a column is marked at 0.5 % of its pixels clipping (5 of 1000 high, 1 of 200 low) "
            + "and not below; readouts \"Highlights clipped 0.4 %\", \"Shadows clipped 0.1 %\", "
            + "and \"—\" before a frame",
        high == [10] && low == [12] && trace.highlightsReadout == "Highlights clipped 0.4 %"
            && trace.shadowsReadout == "Shadows clipped 0.1 %"
            && WaveformTrace.noHighlights == "Highlights clipped —"
            && WaveformTrace.noShadows == "Shadows clipped —",
        "high \(high), low \(low); \(trace.highlightsReadout) / \(trace.shadowsReadout)")
}

// MARK: - P7 latest wins

/// A Metal-compatible 64RGBAHalf buffer of one grey `value`.
func pixelBuffer(_ width: Int, _ height: Int, _ value: Float) -> CVPixelBuffer? {
    let attributes: [String: Any] = [
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]
    var made: CVPixelBuffer?
    CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_64RGBAHalf,
        attributes as CFDictionary, &made)
    guard let buffer = made else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let half = Float16(value)
    for y in 0..<height {
        let pixels = (base + y * row).bindMemory(to: Float16.self, capacity: width * 4)
        for x in 0..<width {
            pixels[x * 4] = half
            pixels[x * 4 + 1] = half
            pixels[x * 4 + 2] = half
            pixels[x * 4 + 3] = 1
        }
    }
    return buffer
}

do {
    // 4K frames, so the first pass is still in flight when the next two are
    // offered back to back.
    let frames = [0, 128, 255].map { pixelBuffer(3840, 2160, Float($0) / 255) }
    let taps = WaveformTaps(analyzer: analyzer)
    var seen: [Int] = []
    let key = 990_001
    taps.attach(key: key, kinds: [.waveform]) { traces in
        guard case .waveform(let trace)? = traces[.waveform] else {
            seen.append(-2)
            return
        }
        let levels = Set(cells(trace).map { $0.1 })
        seen.append(levels.count == 1 ? (levels.first ?? -1) : -1)
    }
    if frames.allSatisfy({ $0 != nil }) {
        for frame in frames.compactMap({ $0 }) { taps.offer(frame, key: key) }
    }
    let deadline = Date().addingTimeInterval(10)
    var settledAt: Date?
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if seen.last == 255, settledAt == nil { settledAt = Date() }
        if let settledAt, Date().timeIntervalSince(settledAt) > 0.5 { break }
    }
    taps.detach(key: key)
    check(
        "P7 latest wins: frames A (0), B (128), C (255) offered back to back while A is in flight "
            + "— the last trace delivered is C's, and C's is delivered once",
        frames.allSatisfy { $0 != nil } && seen.last == 255 && seen.filter { $0 == 255 }.count == 1,
        "traces delivered, by level: \(seen)")
}

// MARK: - G1 the pass's GPU time (RECORD)

do {
    var figures: [String: Double] = [:]
    for (name, width, height) in [("1080p", 1920, 1080), ("4K", 3840, 2160)] {
        guard let frame = texture(width, height, { x, _ in
            let v = Float(x % 256) / 255
            return (v, v, v)
        }), let queue = device.makeCommandQueue() else { continue }
        var times: [Double] = []
        for _ in 0..<12 {
            guard let buffer = queue.makeCommandBuffer(),
                analyzer.encode(frame, into: buffer) != nil
            else { continue }
            buffer.commit()
            buffer.waitUntilCompleted()
            times.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
        }
        let sorted = times.dropFirst(2).sorted()
        if !sorted.isEmpty { figures[name] = sorted[sorted.count / 2] }
    }
    records["G1"] = figures
}

// MARK: - P6 the two commands: no defaults, the option on the document key only

func p6() {
    guard let path = request["package"] as? String else {
        check("P6 the request names a package", false, "\(request)")
        return
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
        document.fileURL = URL(fileURLWithPath: path)
    } catch {
        check("P6 the package opens", false, "\(error)")
        return
    }
    let controller = EditorViewController(document: document)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 862),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.viewWillAppear()
    controller.viewDidAppear()
    controller.refreshFromDocument(isLive: false)
    func settle() {
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            controller.view.layoutSubtreeIfNeeded()
        }
    }
    settle()
    let before = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let key = document.recipeKey
    let other = RecipeSource.shared.register()
    defer { RecipeSource.shared.unregister(other) }
    controller.toggleShowUngraded(nil)
    controller.toggleScopes(nil)
    settle()
    let onKey = RecipeSource.shared.options(for: key)
    let onOther = RecipeSource.shared.options(for: other)
    let shown = controller.scopesPanel?.isShown == true
    let tagShown = controller.ungradedTag?.isHidden == false
    let tagClicks = controller.ungradedTag?.hitTest(NSPoint(x: 2, y: 2)) != nil
    controller.toggleShowUngraded(nil)
    controller.toggleScopes(nil)
    settle()
    let offKey = RecipeSource.shared.options(for: key)
    let after = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let moved = Set((before.allKeys + after.allKeys).compactMap { $0 as? String }).filter {
        (before[$0] as? NSObject) != (after[$0] as? NSObject)
    }
    check(
        "P6 Show Ungraded and Scopes on and off write no UserDefaults key; on, the document's "
            + "key holds ungraded (only), another key none, the panel and the tag show and the "
            + "tag takes no click; off, the key holds none",
        moved.isEmpty && onKey == RecipeOptions(ungraded: true) && onOther == .none && shown
            && tagShown && !tagClicks && offKey == .none
            && controller.scopesPanel?.isShown == false && controller.ungradedTag?.isHidden == true,
        "moved \(moved.sorted()); on \(onKey), other \(onOther), shown \(shown), tag \(tagShown), "
            + "tag clicks \(tagClicks); off \(offKey)")
    window.close()
}
p6()

finish()
