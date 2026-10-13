// Road map "grading-2", phase G2-1 — the scopes' probe (`scopes_proof.py`
// builds it through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, so every row drives the app's own
// types: `WaveformAnalyzer` and its four kernels, `ParadeTrace`,
// `VectorscopeTrace`, `HistogramTrace`, `WaveformTaps`, `ScopesPanelView`,
// `EditorViewController.toggleScopes`. The kernels are the tree's own
// `Waveform.metal`, compiled from source here (a probe has no default
// library), so a mutant of the shader reaches the rows.
//
//   scopes_probe <request.json> <answer.json>
//
// `request.json` names `shader` (the tree's `Waveform.metal`) and `package`, a
// project the proof saved over MCP. One JSON object out: `rows` (S2–S10, each
// a name, ok and detail, the name starting with its row id), `data` (S1's
// bins, which the proof scores against its own BT.709 arithmetic) and
// `records` (T1's GPU times, which the proof scores against GR-10's bound, and
// T2's banded and forced-global parade times, which it scores as a ratio).
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
var data: [String: Any] = [:]
var records: [String: Any] = [:]
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1500))])
}
func finish() -> Never {
    let answer: [String: Any] = ["rows": rows, "data": data, "records": records]
    if let body = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? body.write(to: out)
    }
    exit(0)
}

// MARK: - The analyser over the tree's own kernels

let shaderPath = request["shader"] as? String ?? ""
let device = MTLCreateSystemDefaultDevice()
var compileError = ""
let library = device.flatMap { device -> MTLLibrary? in
    guard let text = try? String(contentsOfFile: shaderPath, encoding: .utf8) else { return nil }
    do {
        return try device.makeLibrary(source: text, options: nil)
    } catch {
        compileError = "\(error)"
        return nil
    }
}
guard let device, let library, let analyzer = WaveformAnalyzer(device: device, library: library)
else {
    for name in ["S2", "S3", "S4", "S5", "S6", "S7", "S8"] {
        check("\(name) the four kernels compile from \(shaderPath)", false,
              "device \(device != nil), library \(library != nil) \(compileError)")
    }
    finish()
}

/// SplitMix64, so every noise fixture is the same on every run.
struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit(_ steps: UInt64) -> Float { Float(next() % (steps + 1)) / Float(steps) }
}

typealias Fill = (Int, Int) -> (Float, Float, Float)

/// A `width` × `height` rgba16Float texture whose pixel (x, y) is `rgb(x, y)`.
func texture(_ width: Int, _ height: Int, _ rgb: Fill) -> MTLTexture? {
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

/// A Metal-compatible IOSurface 64RGBAHalf buffer whose pixel (x, y) is
/// `rgb(x, y)` — what the compositor offers the tap.
func pixelBuffer(_ width: Int, _ height: Int, _ rgb: Fill) -> CVPixelBuffer? {
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
    for y in 0..<height {
        let pixels = (base + y * row).bindMemory(to: Float16.self, capacity: width * 4)
        for x in 0..<width {
            let (r, g, b) = rgb(x, y)
            pixels[x * 4] = Float16(r)
            pixels[x * 4 + 1] = Float16(g)
            pixels[x * 4 + 2] = Float16(b)
            pixels[x * 4 + 3] = 1
        }
    }
    return buffer
}

/// GR-10's five fixtures at `width` × `height`, each a fill.
func fixtures(_ width: Int, _ height: Int) -> [(String, Fill)] {
    var nearGrey = SplitMix(state: 7)
    var noise = SplitMix(state: 11)
    return [
        ("flat", { _, _ in (0.5, 0.5, 0.5) }),
        ("ramp", { x, _ in
            let v = Float(x % 256) / 255
            return (v, v, v)
        }),
        ("near-grey", { _, _ in
            func one() -> Float { 0.5 + Float(Int(nearGrey.next() % 11) - 5) / 255 }
            return (one(), one(), one())
        }),
        ("gradient", { x, y in (Float(x) / Float(width), Float(y) / Float(height), 0.4) }),
        ("noise", { _, _ in (noise.unit(999), noise.unit(999), noise.unit(999)) }),
    ]
}

func analyze(_ made: MTLTexture?, _ kinds: Set<ScopeKind>) -> [ScopeKind: ScopeTrace]? {
    made.flatMap { analyzer.analyze(texture: $0, kinds: kinds) }
}

func vectorscope(_ traces: [ScopeKind: ScopeTrace]?) -> VectorscopeTrace? {
    if case .vectorscope(let trace)? = traces?[.vectorscope] { return trace }
    return nil
}
func parade(_ traces: [ScopeKind: ScopeTrace]?) -> ParadeTrace? {
    if case .parade(let trace)? = traces?[.parade] { return trace }
    return nil
}
func histogram(_ traces: [ScopeKind: ScopeTrace]?) -> HistogramTrace? {
    if case .histogram(let trace)? = traces?[.histogram] { return trace }
    return nil
}
func waveform(_ traces: [ScopeKind: ScopeTrace]?) -> WaveformTrace? {
    if case .waveform(let trace)? = traces?[.waveform] { return trace }
    return nil
}

/// A vectorscope's occupied bins as [cb, cr, count].
func occupied(_ trace: VectorscopeTrace?) -> [[Int]] {
    guard let trace else { return [] }
    return trace.counts.enumerated().compactMap { index, count in
        count > 0
            ? [index % VectorscopeTrace.bins, index / VectorscopeTrace.bins, Int(count)] : nil
    }
}

// MARK: - S1 the 75 % cards (scored by the proof)

do {
    let cards: [(String, (Float, Float, Float))] = [
        ("R", (0.75, 0, 0)), ("G", (0, 0.75, 0)), ("B", (0, 0, 0.75)),
        ("Cy", (0, 0.75, 0.75)), ("Mg", (0.75, 0, 0.75)), ("Yl", (0.75, 0.75, 0)),
    ]
    var bins: [String: Any] = [:]
    for (name, rgb) in cards {
        bins[name] = occupied(vectorscope(analyze(texture(16, 16) { _, _ in rgb }, [.vectorscope])))
    }
    let json = VectorscopeTrace(
        counts: [UInt32](repeating: 0, count: 65536), width: 1, height: 1
    ).json()
    data["S1"] = [
        "cards": bins, "targets": json["targets"] ?? [:],
        "skin_line_degrees": VectorscopeTrace.skinLineDegrees,
    ]
}

// MARK: - S2 greys land in the neutral bin

do {
    let centre = [VectorscopeTrace.centre, VectorscopeTrace.centre]
    let grey = occupied(vectorscope(analyze(texture(16, 16) { _, _ in
        (128.0 / 255, 128.0 / 255, 128.0 / 255)
    }, [.vectorscope])))
    let ramp = occupied(vectorscope(analyze(texture(256, 40) { x, _ in
        let v = Float(x) / 255
        return (v, v, v)
    }, [.vectorscope])))
    let tinted = occupied(vectorscope(analyze(texture(16, 16) { _, _ in
        (128.0 / 255, 129.0 / 255, 128.0 / 255)
    }, [.vectorscope])))
    func whole(_ bins: [[Int]], _ pixels: Int) -> Bool {
        bins.count == 1 && Array(bins[0].prefix(2)) == centre && bins[0][2] == pixels
    }
    check(
        "S2 a grey 128 card, a 256-level grey ramp and a (128, 129, 128)/255 card each land "
            + "wholly in the neutral bin (128, 128)",
        whole(grey, 256) && whole(ramp, 256 * 40) && whole(tinted, 256),
        "grey \(grey.prefix(4)); ramp \(ramp.prefix(4)); (128,129,128) \(tinted.prefix(4))")
}

// MARK: - S3 a red ramp's parade

do {
    // 256 wide counts globally (each 8-px threadgroup spans eight column
    // bins); 1920, 1999 and 3840 wide count per band in threadgroup memory,
    // so a band merged into the wrong column shows here (1999's last group is
    // 7 px, short of the 8 a group is across).
    var stray: [String] = []
    var traced = true
    for (width, height) in [(256, 360), (1920, 64), (1999, 64), (3840, 64)] {
        let trace = parade(analyze(texture(width, height) { x, _ in
            (Float(x * 256 / width) / 255, 0, 0)
        }, [.parade]))
        guard let trace else {
            traced = false
            continue
        }
        var perColumn = [Int](repeating: 0, count: 256)
        for x in 0..<width { perColumn[x * 256 / width] += height }
        for (index, name) in ["R", "G", "B"].enumerated() {
            let channel = trace.channel(index)
            for column in 0..<256 {
                for level in 0..<256 {
                    let count = Int(channel.counts[column * 256 + level])
                    let onIt = index == 0 ? level == column : level == 0
                    let want = onIt ? perColumn[column] : 0
                    if count != want {
                        stray.append("\(width) \(name)[\(column)][\(level)]=\(count)")
                    }
                }
            }
        }
    }
    check(
        "S3 an R-only ramp's parade at 256 × 360, 1920 × 64, 1999 × 64 and 3840 × 64: R′ has "
            + "counts[c][c] = the column's pixels and nothing else; G′ and B′ sit flat at level 0",
        traced && stray.isEmpty, "stray \(stray.prefix(8))")
}

// MARK: - S4 a grey ramp's histogram is flat

do {
    let trace = histogram(analyze(texture(256, 360) { x, _ in
        let v = Float(x) / 255
        return (v, v, v)
    }, [.histogram]))
    let planes = (0..<4).map { trace?.plane($0) ?? [] }
    let flat = planes.allSatisfy { $0.count == 256 && $0.allSatisfy { $0 == 360 } }
    check(
        "S4 a 256-wide grey ramp's histogram is flat: 360 at every level in R′, G′, B′ and Y′",
        trace != nil && flat,
        planes.enumerated().map { index, plane in
            "plane \(index): \(Set(plane).sorted().prefix(6))"
        }.joined(separator: "; "))
}

// MARK: - S5 the histogram's Y′ is the waveform's; the parade's marks

do {
    var rng = SplitMix(state: 5)
    let traces = analyze(texture(640, 360) { _, _ in
        let roll = rng.next() % 100
        if roll < 3 { return (1, 1, 1) }
        if roll < 5 { return (0, 0, 0) }
        return (rng.unit(255), rng.unit(255), rng.unit(255))
    }, [.waveform, .histogram])
    let wave = waveform(traces)
    let hist = histogram(traces)
    var sums = [UInt32](repeating: 0, count: 256)
    if let wave {
        for column in 0..<256 {
            for level in 0..<256 { sums[level] += wave.counts[column * 256 + level] }
        }
    }
    let luma = hist?.plane(3) ?? []
    let readouts = hist.map { [$0.highlightsReadout, $0.shadowsReadout] } ?? []
    let waveReadouts = wave.map { [$0.highlightsReadout, $0.shadowsReadout] } ?? []
    // Parade marks, per channel: R column 10 with 5 of 1000 at 255 (marked),
    // G column 11 with 1 of 200 at 0 (marked low), B column 12 with 4 of
    // 1000 at 255 (not).
    let plane = 256 * 256
    var counts = [UInt32](repeating: 0, count: 3 * plane)
    counts[10 * 256 + 128] = 995
    counts[10 * 256 + 255] = 5
    counts[plane + 11 * 256 + 128] = 199
    counts[plane + 11 * 256] = 1
    counts[2 * plane + 12 * 256 + 128] = 996
    counts[2 * plane + 12 * 256 + 255] = 4
    let marks = ParadeTrace(counts: counts, width: 80, height: 30)
    let r = marks.channel(0)
    let g = marks.channel(1)
    let b = marks.channel(2)
    let marked = r.marks(high: true) == [10] && r.marks(high: false).isEmpty
        && g.marks(high: false) == [11] && g.marks(high: true).isEmpty
        && b.marks(high: true).isEmpty && b.marks(high: false).isEmpty
    check(
        "S5 on noise the histogram's Y′ plane equals the waveform's column sums and its "
            + "readouts the waveform's; the parade marks a channel's column at 0.5 % (5 of 1000 "
            + "high, 1 of 200 low) and not below",
        wave != nil && hist != nil && luma == sums && readouts == waveReadouts && marked,
        "Y′ equal \(luma == sums) (first differences "
            + "\(zip(luma, sums).enumerated().filter { $0.1.0 != $0.1.1 }.prefix(4)));"
            + " readouts \(readouts) vs \(waveReadouts); marks R \(r.marks(high: true)) "
            + "G low \(g.marks(high: false)) B \(b.marks(high: true))")
}

// MARK: - S6 every pass counts every pixel

do {
    var misses: [String] = []
    for (width, height) in [(1001, 537), (333, 77)] {
        for (name, fill) in fixtures(width, height) {
            let traces = analyze(texture(width, height, fill), Set(ScopeKind.allCases))
            let pixels = UInt64(width * height)
            for kind in ScopeKind.allCases {
                let counts: [UInt32]
                switch traces?[kind] {
                case .waveform(let t)?: counts = t.counts
                case .parade(let t)?: counts = t.counts
                case .vectorscope(let t)?: counts = t.counts
                case .histogram(let t)?: counts = t.counts
                case nil: counts = []
                }
                let want = pixels * (kind == .parade ? 3 : kind == .histogram ? 4 : 1)
                let total = counts.reduce(UInt64(0)) { $0 + UInt64($1) }
                if total != want {
                    misses.append("\(width)×\(height) \(name) \(kind.rawValue): \(total) ≠ \(want)")
                }
            }
        }
    }
    check(
        "S6 every kind's counts total the pixels (×3 the parade, ×4 the histogram) on GR-10's "
            + "five fixtures at 1001 × 537 and 333 × 77",
        misses.isEmpty, "misses \(misses.prefix(8))")
}

// MARK: - S7 latest wins with two kinds shown

do {
    let frames = [0, 128, 255].map { value in
        pixelBuffer(3840, 2160) { _, _ in
            let v = Float(value) / 255
            return (v, v, v)
        }
    }
    let taps = WaveformTaps(analyzer: analyzer)
    var seen: [String] = []
    let key = 990_101
    taps.attach(key: key, kinds: [.vectorscope, .histogram]) { traces in
        let level = histogram(traces).flatMap { trace in
            trace.plane(3).firstIndex(where: { $0 > 0 })
        }
        seen.append("\(level ?? -1)\(vectorscope(traces) != nil ? "+V" : "")")
    }
    if frames.allSatisfy({ $0 != nil }) {
        for frame in frames.compactMap({ $0 }) { taps.offer(frame, key: key) }
    }
    let deadline = Date().addingTimeInterval(10)
    var settledAt: Date?
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if seen.last == "255+V", settledAt == nil { settledAt = Date() }
        if let settledAt, Date().timeIntervalSince(settledAt) > 0.5 { break }
    }
    taps.detach(key: key)
    check(
        "S7 latest wins with the vectorscope and the histogram shown: frames 0, 128, 255 offered "
            + "back to back — every reading holds both kinds, the last is 255's, delivered once",
        frames.allSatisfy { $0 != nil } && !seen.isEmpty && seen.allSatisfy { $0.hasSuffix("+V") }
            && seen.last == "255+V" && seen.filter { $0 == "255+V" }.count == 1,
        "readings (Y′ level, +V when the vectorscope came too): \(seen)")
}

// MARK: - S8 the tap reads what render_frame reads

do {
    let width = 320
    let height = 180
    var rng = SplitMix(state: 9)
    var codes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let at = (y * width + x) * 4
            codes[at] = UInt8(x * 255 / (width - 1))
            codes[at + 1] = UInt8(y * 255 / (height - 1))
            codes[at + 2] = UInt8(rng.next() % 256)
        }
    }
    let image = CGDataProvider(data: Data(codes) as CFData).flatMap { provider in
        CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    // The buffer holds exactly the half floats `analyze(image:)` uploads: the
    // image drawn into the same 16-bit float bitmap, row for row.
    var halves: [Float16] = []
    if let image, let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 16,
            bytesPerRow: width * 8, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder16Little.rawValue)
    {
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        if let base = context.data {
            let bound = base.bindMemory(to: Float16.self, capacity: width * height * 4)
            halves = Array(UnsafeBufferPointer(start: bound, count: width * height * 4))
        }
    }
    let buffer = halves.isEmpty ? nil : pixelBuffer(width, height) { x, y in
        let at = (y * width + x) * 4
        return (Float(halves[at]), Float(halves[at + 1]), Float(halves[at + 2]))
    }
    let all = Set(ScopeKind.allCases)
    let reference = image.flatMap { analyzer.analyze(image: $0, kinds: all) }
    let taps = WaveformTaps(analyzer: analyzer)
    var tapped: [ScopeKind: ScopeTrace]?
    let key = 990_102
    taps.attach(key: key, kinds: all) { traces in tapped = traces }
    if let buffer { taps.offer(buffer, key: key) }
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, tapped == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    taps.detach(key: key)
    let differ = ScopeKind.allCases.filter { tapped?[$0] == nil || tapped?[$0] != reference?[$0] }
    check(
        "S8 the tap's reading of a 64RGBAHalf buffer equals analyze(image:kinds:) of the same "
            + "pixels, all four kinds",
        reference?.count == 4 && tapped?.count == 4 && differ.isEmpty,
        "reference kinds \(reference?.keys.map(\.rawValue).sorted() ?? []); tapped "
            + "\(tapped?.keys.map(\.rawValue).sorted() ?? []); differ \(differ.map(\.rawValue))")
}

// MARK: - S10 the layout rule

do {
    var misses: [String] = []
    for top in ScopeKind.allCases {
        for bottom in ScopeKind.allCases {
            for pane in [300, 359, 360, 460, 570, 1000] as [CGFloat] {
                let rule = ScopesPanelView.layout(picks: [top, bottom], paneHeight: pane)
                let shown = rule.showsBottom ? [top, bottom] : [top]
                let preferred = shown.map(ScopeSlotView.preferredBodyHeight)
                let chrome = shown.map(ScopeSlotView.chromeHeight).reduce(0, +)
                let where_ = "\(top.rawValue)/\(bottom.rawValue) at \(Int(pane))"
                if rule.showsBottom != (pane >= 360) || rule.bodyHeights.count != shown.count {
                    misses.append("\(where_): bottom \(rule.showsBottom)")
                    continue
                }
                if rule.bodyHeights.reduce(0, +) + chrome > pane + 0.001 {
                    misses.append("\(where_): \(rule.bodyHeights) + \(chrome) > pane")
                }
                let total = preferred.reduce(0, +)
                if chrome + total <= pane {
                    if rule.bodyHeights != preferred {
                        misses.append("\(where_): \(rule.bodyHeights) ≠ preferred \(preferred)")
                    }
                } else {
                    let factor = (pane - chrome) / total
                    for (body, want) in zip(rule.bodyHeights, preferred)
                    where abs(body - want * factor) >= 1 {
                        misses.append("\(where_): \(body) ≠ \(want) × \(factor)")
                    }
                }
                for (kind, body) in zip(shown, rule.bodyHeights) where kind == .vectorscope {
                    if min(ScopeSlotView.bodyWidth, body) > 224 {
                        misses.append("\(where_): vectorscope side > 224")
                    }
                }
            }
        }
    }
    check(
        "S10 layout(picks:paneHeight:) for every pick pair at 300, 359, 360, 460, 570 and 1000: "
            + "the bottom slot iff ≥ 360, bodies and chrome within the pane, preferred bodies "
            + "when they fit, else both scaled by one factor, a vectorscope side ≤ 224",
        misses.isEmpty, "misses \(misses.count): \(misses.prefix(6))")
}

// MARK: - T1 the passes' GPU time (scored by the proof)

/// The median GPU time of `kinds` over `frame`, in ms. A burst of sixteen
/// passes committed back to back first, unread, so the GPU's clock is up as it
/// is under playback: measured cold, one at a time, the figures swung two- to
/// threefold between runs. Then the twelve passes one at a time, each waited
/// on, since buffers committed together run two at once and each one's own
/// time doubles.
func gpuMedian(
    _ analyzer: WaveformAnalyzer, _ kinds: Set<ScopeKind>, _ frame: MTLTexture,
    _ queue: MTLCommandQueue
) -> Double? {
    var burst: [MTLCommandBuffer] = []
    for _ in 0..<16 {
        guard let buffer = queue.makeCommandBuffer(),
            analyzer.encode(kinds, frame: frame, into: buffer) != nil
        else { continue }
        buffer.commit()
        burst.append(buffer)
    }
    for buffer in burst { buffer.waitUntilCompleted() }
    var times: [Double] = []
    for _ in 0..<12 {
        guard let buffer = queue.makeCommandBuffer(),
            analyzer.encode(kinds, frame: frame, into: buffer) != nil
        else { continue }
        buffer.commit()
        buffer.waitUntilCompleted()
        times.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
    }
    let sorted = times.dropFirst(2).sorted()
    return sorted.isEmpty ? nil : sorted[sorted.count / 2]
}

do {
    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    let variants: [(String, Set<ScopeKind>)] = [
        ("parade", [.parade]), ("vectorscope", [.vectorscope]), ("histogram", [.histogram]),
        ("waveform", [.waveform]), ("waveform+vectorscope", [.waveform, .vectorscope]),
    ]
    var figures: [String: Any] = ["gpu": device.name]
    if let cache, let queue = device.makeCommandQueue() {
        for (size, width, height) in [("1080p", 1920, 1080), ("4K", 3840, 2160)] {
            var bySize: [String: [String: Double]] = [:]
            for (name, fill) in fixtures(width, height) {
                guard let frame = pixelBuffer(width, height, fill) else { continue }
                var wrapper: CVMetalTexture?
                CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, cache, frame, nil, .rgba16Float, width, height, 0,
                    &wrapper)
                guard let wrapper, let made = CVMetalTextureGetTexture(wrapper) else { continue }
                for (variant, kinds) in variants {
                    if let median = gpuMedian(analyzer, kinds, made, queue) {
                        bySize[variant, default: [:]][name] = median
                    }
                }
                withExtendedLifetime(wrapper) {}
            }
            figures[size] = bySize
        }
    }
    records["T1"] = figures
}

// MARK: - T2 the banded parade against the forced-global one (scored by the proof)

// The tree's shader again, with its one `bool banded = ` line forced to
// `false`, so every parade group adds globally. The tree's parade and the
// forced-global one are timed back to back on each 4K fixture; the proof
// holds the banded time, on the fixture where the forced-global parade is
// slowest, to a fraction of the global one, which is what says the banded
// path is the one running (T1 alone cannot: the global parade sits about
// GR-10's 1.1 ms).
do {
    let text = (try? String(contentsOfFile: shaderPath, encoding: .utf8)) ?? ""
    var lines = text.components(separatedBy: "\n")
    let prefix = "bool banded = "
    let matches = lines.indices.filter {
        lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
    }
    if matches.count != 1 {
        records["T2"] = ["anchor": "\(matches.count) lines start `\(prefix)`"]
    } else {
        lines[matches[0]] = "    bool banded = false;"
        var error = ""
        var global: WaveformAnalyzer?
        do {
            let forced = try device.makeLibrary(source: lines.joined(separator: "\n"), options: nil)
            global = WaveformAnalyzer(device: device, library: forced)
            if global == nil { error = "the forced-global WaveformAnalyzer is nil" }
        } catch let failure {
            error = "the forced-global shader does not compile: \(failure)"
        }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        let queue = device.makeCommandQueue()
        if let global, let cache, let queue {
            var byFixture: [String: [String: Double]] = [:]
            let (width, height) = (3840, 2160)
            for (name, fill) in fixtures(width, height) {
                guard let frame = pixelBuffer(width, height, fill) else { continue }
                var wrapper: CVMetalTexture?
                CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault, cache, frame, nil, .rgba16Float, width, height, 0,
                    &wrapper)
                guard let wrapper, let made = CVMetalTextureGetTexture(wrapper) else { continue }
                var pair: [String: Double] = [:]
                pair["banded"] = gpuMedian(analyzer, [.parade], made, queue)
                pair["global"] = gpuMedian(global, [.parade], made, queue)
                byFixture[name] = pair
                withExtendedLifetime(wrapper) {}
            }
            records["T2"] = ["gpu": device.name, "4K": byFixture]
        } else {
            if error.isEmpty {
                error = "cache \(cache != nil), queue \(queue != nil)"
            }
            records["T2"] = ["error": error]
        }
    }
}

// MARK: - S9 the panel: picks, no defaults, the 360 pt floor

func s9() {
    guard let path = request["package"] as? String else {
        check("S9 the request names a package", false, "\(request)")
        return
    }
    func open() -> (ProjectDocument, EditorViewController, NSWindow)? {
        let document = ProjectDocument()
        do {
            try document.read(
                from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
            document.fileURL = URL(fileURLWithPath: path)
        } catch {
            return nil
        }
        let controller = EditorViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1000),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.viewWillAppear()
        controller.viewDidAppear()
        controller.refreshFromDocument(isLive: false)
        return (document, controller, window)
    }
    func settle(_ controller: EditorViewController) {
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            controller.view.layoutSubtreeIfNeeded()
        }
    }
    guard let (document, controller, window) = open(), let panel = controller.scopesPanel else {
        check("S9 the package opens with a scopes panel", false, path)
        return
    }
    settle(controller)
    let before = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let opening = panel.picks
    controller.toggleScopes(nil)
    settle(controller)
    panel.pick(.parade, slot: 0)
    panel.pick(.histogram, slot: 1)
    settle(controller)
    controller.toggleScopes(nil)
    settle(controller)
    controller.toggleScopes(nil)
    settle(controller)
    let kept = panel.picks
    let key = document.recipeKey
    // Across 360 pt of pane and back, counting the asks for a frame.
    var asks = 0
    let wired = panel.onNeedsFrame
    panel.onNeedsFrame = {
        asks += 1
        wired?()
    }
    var steps: [String] = []
    var stepsOk = true
    // The probe's window has no timeline beneath the pane, so the pane is
    // the content height less the toolbar: 1000 pt holds both slots, 380 pt
    // only the top.
    for (height, wantsBottom) in [(1000, true), (380, false), (1000, true)] {
        let asked = asks
        window.setContentSize(NSSize(width: 1440, height: height))
        settle(controller)
        let pane = panel.bounds.height
        let attached = WaveformTaps.shared.attachedKinds(key: key) ?? []
        let want: Set<ScopeKind> = wantsBottom ? [.parade, .histogram] : [.parade]
        let flipped = steps.isEmpty ? 0 : 1
        steps.append(
            "window \(height): pane \(pane), shown \(panel.shownKinds.map(\.rawValue).sorted()), "
                + "attached \(attached.map(\.rawValue).sorted()), asks +\(asks - asked)")
        stepsOk = stepsOk && (pane >= 360) == wantsBottom && panel.showsBottomSlot == wantsBottom
            && panel.shownKinds == want && attached == want
            && (steps.count == 1 || asks - asked == flipped)
    }
    controller.toggleScopes(nil)
    settle(controller)
    let after = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let moved = Set((before.allKeys + after.allKeys).compactMap { $0 as? String }).filter {
        (before[$0] as? NSObject) != (after[$0] as? NSObject)
    }
    window.close()
    let fresh = open()
    let restarted = fresh?.1.scopesPanel?.picks
    fresh?.2.close()
    check(
        "S9 the panel opens Waveform over Vectorscope; picks in both slots last across hide and "
            + "show; Scopes on and off and the picks write no UserDefaults key; a new controller "
            + "starts over; across 360 pt of pane both ways the shown and attached kinds follow "
            + "(the top pick alone below), each flip asking for one frame",
        opening == ScopesPanelView.openingPicks && opening == [.waveform, .vectorscope]
            && kept == [.parade, .histogram] && moved.isEmpty && stepsOk
            && restarted == ScopesPanelView.openingPicks,
        "opening \(opening.map(\.rawValue)); kept \(kept.map(\.rawValue)); moved "
            + "\(moved.sorted()); restarted \(restarted?.map(\.rawValue) ?? []); "
            + steps.joined(separator: " | "))
}
s9()

finish()
