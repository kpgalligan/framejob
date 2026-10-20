// Road map "grading-2", phase G2-1 — the scopes' probe (`scopes_proof.py`
// builds it through `swift_build.build` and runs it); grading-4 T4-1 added
// the vectorscope's zoom (spec §11 GR-31) and its same-bin add (GR-26).
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
// `request.json` names `shader` (the tree's `Waveform.metal`),
// `baseline_shader` (the T4-0 tree's, `31f3aa1`, which S12 compares ×1 counts
// against) and `package`, a project the proof saved over MCP. One JSON object
// out: `rows` (S2–S14, each a name, ok and detail, the name starting with its
// row id), `data` (S1's bins, which the proof scores against its own BT.709
// arithmetic, and hdr H-4's S15, an HLG signal's cards, levels and parade,
// against its BT.2020 arithmetic) and `records` (T1's GPU times, SDR and HLG
// variants, which the proof scores against
// GR-10's bound; T2's banded and forced-global parade times and T3's tree and
// forced-global vectorscope times, which it scores as ratios). With
// `central_ab` (`--central-ab`, #296) it runs only that A/B and answers
// `records["AB"]`.
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
    for name in ["S2", "S3", "S4", "S5", "S6", "S7", "S8", "S11", "S12"] {
        check("\(name) the four kernels compile from \(shaderPath)", false,
              "device \(device != nil), library \(library != nil) \(compileError)")
    }
    finish()
}

// MARK: - #296's A/B: the central threadgroup path against the kernel without it

/// `scopes_proof.py --central-ab` (spec §11 GR-26, #296): three shaders'
/// ×1 vectorscope passes on each of the six 4K fixtures, one buffer at a
/// time — `base` (the last tree with the central path), `twin` (`base` with
/// its `bool central = ` line forced to `false`) and `tree` (the tree's
/// shader) — over `rounds` rounds, round r timing them in `[base, tree,
/// twin]` rotated left by r % 3, one `gpuMedian` each, so load falls on all
/// three alike. The proof computes every statistic and the verdict.
func centralAB(_ ab: [String: Any]) -> [String: Any] {
    func read(_ key: String) -> String? {
        (ab[key] as? String).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
    }
    func loads() -> [Double] {
        var three = [Double](repeating: 0, count: 3)
        let got = getloadavg(&three, 3)
        return got == 3 ? three : []
    }
    let rounds = ab["rounds"] as? Int ?? 0
    guard let baseText = read("base_shader"), let twinText = read("forced_shader"),
        let treeText = try? String(contentsOfFile: shaderPath, encoding: .utf8), rounds > 0
    else { return ["error": "a shader could not be read, or rounds \(rounds) is not positive"] }
    var arms: [(String, WaveformAnalyzer)] = []
    for (name, text) in [("base", baseText), ("tree", treeText), ("twin", twinText)] {
        do {
            let library = try device.makeLibrary(source: text, options: nil)
            guard let made = WaveformAnalyzer(device: device, library: library) else {
                return ["error": "the \(name) WaveformAnalyzer is nil"]
            }
            arms.append((name, made))
        } catch {
            return ["error": "the \(name) shader does not compile: \(error)"]
        }
    }
    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    guard let cache, let queue = device.makeCommandQueue() else {
        return ["error": "no texture cache or command queue"]
    }
    let pass: Set<ScopePass> = [ScopePass(.vectorscope)]
    let (width, height) = (3840, 2160)
    var byFixture: [String: Any] = [:]
    for (name, fill) in fixtures(width, height) {
        guard let frame = pixelBuffer(width, height, fill) else {
            return ["error": "no 4K buffer for \(name)"]
        }
        var wrapper: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, frame, nil, .rgba16Float, width, height, 0, &wrapper)
        guard let wrapper, let made = CVMetalTextureGetTexture(wrapper) else {
            return ["error": "no texture over the \(name) buffer"]
        }
        let before = loads()
        var times: [String: [Double]] = ["base": [], "tree": [], "twin": []]
        for round in 0..<rounds {
            let shift = round % arms.count
            for (arm, through) in arms[shift...] + arms[..<shift] {
                guard let median = gpuMedian(through, pass, made, queue) else {
                    return ["error": "no GPU time for \(arm) on \(name), round \(round)"]
                }
                times[arm, default: []].append(median)
            }
        }
        var entry: [String: Any] = times
        entry["load_before"] = before
        entry["load_after"] = loads()
        byFixture[name] = entry
        withExtendedLifetime(wrapper) {}
    }
    return ["gpu": device.name, "rounds": rounds, "identical": baseText == treeText,
            "fixtures": byFixture]
}

if let ab = request["central_ab"] as? [String: Any] {
    records["AB"] = centralAB(ab)
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

/// The RGBA half floats of a `width` × `height` fill, row by row.
func halves(_ width: Int, _ height: Int, _ rgb: Fill) -> [Float16] {
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
    return halves
}

/// A `width` × `height` rgba16Float texture whose pixel (x, y) is `rgb(x, y)`.
func texture(_ width: Int, _ height: Int, _ rgb: Fill) -> MTLTexture? {
    texture(width, height, halves: halves(width, height, rgb))
}

/// A `width` × `height` rgba16Float texture holding `halves`.
func texture(_ width: Int, _ height: Int, halves: [Float16]) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .managed
    guard let made = device.makeTexture(descriptor: descriptor) else { return nil }
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

/// GR-10's six fixtures (GR-26 added the flat saturated red) at `width` ×
/// `height`, each a fill.
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
        ("flat-red", { _, _ in (0.8, 0.1, 0.1) }),
    ]
}

func analyze(_ made: MTLTexture?, _ kinds: Set<ScopeKind>) -> [ScopeKind: ScopeTrace]? {
    made.flatMap { analyzer.analyze(texture: $0, kinds: kinds) }
}

func vectorscope(_ traces: [ScopeKind: ScopeTrace]?) -> VectorscopeTrace? {
    if case .vectorscope(let trace)? = traces?[.vectorscope] { return trace }
    return nil
}
/// The vectorscope of `made` at `zoom`, through `analyzer` (the tree's by
/// default).
func vectorscope(
    _ made: MTLTexture?, zoom: Int, through other: WaveformAnalyzer? = nil
) -> VectorscopeTrace? {
    let pass = ScopePass(.vectorscope, zoom: zoom)
    let through = other ?? analyzer
    if case .vectorscope(let trace)? = made.flatMap({
        through.analyze(texture: $0, passes: [pass])
    })?[pass] {
        return trace
    }
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

/// Whether every bin of `a` lies within ±1 bin on each axis of one of `b`'s.
func near(_ a: Set<[Int]>, _ b: Set<[Int]>) -> Bool {
    a.allSatisfy { one in
        (-1...1).contains { dx in
            (-1...1).contains { dy in b.contains([one[0] + dx, one[1] + dy]) }
        }
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

// MARK: - S15 an HLG signal's cards (scored by the proof; hdr H-4, spec §11 HD-15)

do {
    let cards: [(String, (Float, Float, Float))] = [
        ("R", (0.75, 0, 0)), ("G", (0, 0.75, 0)), ("B", (0, 0, 0.75)),
        ("Cy", (0, 0.75, 0.75)), ("Mg", (0.75, 0, 0.75)), ("Yl", (0.75, 0.75, 0)),
        ("warm", (0.875, 0.25, 0.125)), ("leaf", (0.125, 0.625, 0.375)),
        ("sky", (0.375, 0.5, 0.875)),
    ]
    var bins: [String: Any] = [:]
    var levels: [String: Any] = [:]
    var paradeSame = true
    let all: Set<ScopePass> = Set(ScopeKind.allCases.map { ScopePass($0) })
    for (name, rgb) in cards {
        let made = texture(16, 16) { _, _ in rgb }
        let hlg = made.flatMap { analyzer.analyze(texture: $0, passes: all, signal: .hlg) }
        let sdr = made.flatMap { analyzer.analyze(texture: $0, passes: all) }
        let byKind = hlg.map(WaveformAnalyzer.byKind)
        bins[name] = occupied(vectorscope(byKind))
        let wave = waveform(byKind).map { trace in
            (0..<WaveformTrace.levels).filter { level in
                (0..<WaveformTrace.columns).contains {
                    trace.counts[$0 * WaveformTrace.levels + level] > 0
                }
            }
        } ?? []
        let luma = histogram(byKind).map { trace in
            trace.plane(3).enumerated().filter { $0.element > 0 }.map(\.offset)
        } ?? []
        levels[name] = ["waveform": wave, "histogram": luma]
        let tree = parade(byKind)?.counts
        let plain = parade(sdr.map(WaveformAnalyzer.byKind))?.counts
        paradeSame = paradeSame && tree != nil && tree == plain
    }
    let json = VectorscopeTrace(
        counts: [UInt32](repeating: 0, count: 65536), width: 1, height: 1, signal: .hlg
    ).json()
    data["S15"] = [
        "cards": bins, "levels": levels, "parade_same": paradeSame,
        "targets": json["targets"] ?? [:],
        "skin_line_degrees": VectorscopeTrace.skinLineDegrees(for: .hlg),
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

// MARK: - S6 every pass counts every pixel; ×2 and ×4 against a CPU count

/// A CPU count of `pixels` (RGBA half floats) at `zoom`, binned as the kernel
/// bins: the saturated values, Y′, Cb and Cr in `Float` as the shader
/// computes them, then `128 + round(255·zoom·c)`. The plot's edges sit at
/// `255·zoom·c` = 127.5 and −128.5 (the raw bin leaves 0…255 past them); a
/// pixel within `tieBand` of one on either axis is a TIE, which either side
/// may count. `bins` holds the counted pixels' bins, `edge` the ties' bins
/// clamped to the plot, `off` the pixels definitely off it.
struct CPUCount {
    static let tieBand = 1e-3
    var bins = Set<[Int]>()
    var edge = Set<[Int]>()
    var off = 0
    var ties = 0

    init(_ pixels: [Float16], zoom: Int) {
        let scale = 255 * Double(zoom)
        func past(_ v: Double, by margin: Double) -> Bool {
            v > 127.5 + margin || v < -128.5 - margin
        }
        for at in stride(from: 0, to: pixels.count, by: 4) {
            let r = min(max(Float(pixels[at]), 0), 1)
            let g = min(max(Float(pixels[at + 1]), 0), 1)
            let b = min(max(Float(pixels[at + 2]), 0), 1)
            let luma: Float = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let cb: Float = (b - luma) / 1.8556
            let cr: Float = (r - luma) / 1.5748
            let v = [scale * Double(cb), scale * Double(cr)]
            let bin = v.map { min(255, max(0, 128 + Int($0.rounded()))) }
            if v.contains(where: { past($0, by: Self.tieBand) }) {
                off += 1
            } else if v.contains(where: { past($0, by: -Self.tieBand) }) {
                ties += 1
                edge.insert(bin)
            } else {
                bins.insert(bin)
            }
        }
    }
}

do {
    var misses: [String] = []
    var zoomed: [String] = []
    var crossed = true
    for (width, height) in [(1001, 537), (333, 77)] {
        for (name, fill) in fixtures(width, height) {
            let fixture = halves(width, height, fill)
            let made = texture(width, height, halves: fixture)
            let traces = analyze(made, Set(ScopeKind.allCases))
            let pixels = UInt64(width * height)
            for kind in ScopeKind.allCases {
                let counts: [UInt32]
                switch traces?[kind] {
                case .waveform(let t)?: counts = t.counts
                case .parade(let t)?: counts = t.counts
                case .vectorscope(let t)?:
                    counts = t.counts
                    if t.offPlot != 0 || t.zoom != 1 {
                        misses.append("\(width)×\(height) \(name) ×1: zoom \(t.zoom), off \(t.offPlot)")
                    }
                case .histogram(let t)?: counts = t.counts
                case nil: counts = []
                }
                let want = pixels * (kind == .parade ? 3 : kind == .histogram ? 4 : 1)
                let total = counts.reduce(UInt64(0)) { $0 + UInt64($1) }
                if total != want {
                    misses.append("\(width)×\(height) \(name) \(kind.rawValue): \(total) ≠ \(want)")
                }
            }
            for zoom in [2, 4] {
                let where_ = "\(width)×\(height) \(name) ×\(zoom)"
                let cpu = CPUCount(fixture, zoom: zoom)
                if name == "gradient", width == 1001, cpu.off == 0 || cpu.bins.isEmpty {
                    crossed = false
                }
                guard let gpu = vectorscope(made, zoom: zoom) else {
                    misses.append("\(where_): no trace")
                    continue
                }
                let total = gpu.counts.reduce(0) { $0 + Int($1) }
                let have = Set(occupied(gpu).map { Array($0.prefix(2)) })
                zoomed.append("\(where_) off \(gpu.offPlot) (cpu \(cpu.off)+\(cpu.ties) ties)")
                if gpu.zoom != zoom || gpu.offPlot != Int(pixels) - total
                    || gpu.offPlot < cpu.off || gpu.offPlot > cpu.off + cpu.ties
                {
                    misses.append(
                        "\(where_): zoom \(gpu.zoom), off \(gpu.offPlot), counted \(total), cpu off "
                            + "\(cpu.off) ties \(cpu.ties)")
                }
                if !near(have, cpu.bins.union(cpu.edge)) || !near(cpu.bins, have) {
                    misses.append(
                        "\(where_): bins apart (gpu \(have.count), cpu \(cpu.bins.count), first gpu "
                            + "strays \(have.filter { !near([$0], cpu.bins.union(cpu.edge)) }.prefix(3)), "
                            + "cpu strays \(cpu.bins.filter { !near([$0], have) }.prefix(3)))")
                }
            }
        }
    }
    check(
        "S6 every kind's counts total the pixels (×3 the parade, ×4 the histogram) at ×1 on "
            + "GR-26's six fixtures at 1001 × 537 and 333 × 77; at ×2 and ×4 the vectorscope's "
            + "off_plot lies between a CPU count's definite off-plot pixels and those plus its "
            + "edge ties, its occupied bins within ±1 of the CPU's both ways, and the gradient "
            + "crosses the plot's edge at both zooms",
        misses.isEmpty && crossed,
        "crossed \(crossed); misses \(misses.prefix(8)); "
            + zoomed.filter { $0.contains("gradient") || $0.contains("flat-red") }.joined(separator: "; "))
}

// MARK: - S11 a near-grey card spreads at the zoom

do {
    // Every (128 ± 5)/255 channel combination, 11³ pixels.
    let steps = 11
    let card: Fill = { x, _ in
        func level(_ i: Int) -> Float { Float(123 + i) / 255 }
        return (level(x / (steps * steps)), level((x / steps) % steps), level(x % steps))
    }
    let made = texture(steps * steps * steps, 1, card)
    var extents: [Int: (cb: Int, cr: Int)] = [:]
    for zoom in VectorscopeTrace.zooms {
        let bins = occupied(vectorscope(made, zoom: zoom))
        guard !bins.isEmpty else { continue }
        let cbs = bins.map { $0[0] }
        let crs = bins.map { $0[1] }
        extents[zoom] = ((cbs.max() ?? 0) - (cbs.min() ?? 0), (crs.max() ?? 0) - (crs.min() ?? 0))
    }
    let one = extents[1]
    let spread = one.map { one in
        [2, 4].allSatisfy { zoom in
            guard let at = extents[zoom] else { return false }
            return abs(at.cb - zoom * one.cb) <= 1 && abs(at.cr - zoom * one.cr) <= 1
        }
    } ?? false
    check(
        "S11 a near-grey card (every (128 ± 5)/255 channel combination): its Cb and Cr extents "
            + "at ×2 and ×4 are 2× and 4× ×1's, ±1 bin",
        extents.count == 3 && (one?.cb ?? 0) > 0 && spread,
        "extents (cb, cr) by zoom: "
            + extents.sorted { $0.key < $1.key }.map { "×\($0.key) \($0.value)" }.joined(separator: ", "))
}

// MARK: - S12 off the plot at ×2; ×1 identical to the T4-0 tree's

do {
    // (a) 75 % red: Cr bin 224 at ×1, raw 319 at ×2.
    let red = texture(16, 16) { _, _ in (0.75, 0, 0) }
    let one = vectorscope(red, zoom: 1)
    let two = vectorscope(red, zoom: 2)
    let sum = { (trace: VectorscopeTrace?) in trace?.counts.reduce(0) { $0 + Int($1) } ?? -1 }
    let offAtTwo = sum(one) == 256 && one?.offPlot == 0 && sum(two) == 0 && two?.offPlot == 256
    // (b) every kind at ×1 byte-equal to an analyser over the T4-0 shader.
    var baselineError = ""
    let baseline: WaveformAnalyzer? = {
        guard let path = request["baseline_shader"] as? String,
            let text = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            baselineError = "no baseline_shader in the request"
            return nil
        }
        do {
            let made = try device.makeLibrary(source: text, options: nil)
            return WaveformAnalyzer(device: device, library: made)
        } catch {
            baselineError = "the baseline shader does not compile: \(error)"
            return nil
        }
    }()
    var differ: [String] = []
    var compared = 0
    if let baseline {
        let (width, height) = (1001, 537)
        var cards: [(String, Fill)] = fixtures(width, height)
        let bars: [(String, (Float, Float, Float))] = [
            ("75-R", (0.75, 0, 0)), ("75-G", (0, 0.75, 0)), ("75-B", (0, 0, 0.75)),
            ("75-Cy", (0, 0.75, 0.75)), ("75-Mg", (0.75, 0, 0.75)), ("75-Yl", (0.75, 0.75, 0)),
            ("red", (1, 0, 0)),
        ]
        for (name, rgb) in bars { cards.append((name, { _, _ in rgb })) }
        let all = Set(ScopeKind.allCases)
        for (name, fill) in cards {
            let made = texture(width, height, fill)
            let tree = made.flatMap { analyzer.analyze(texture: $0, kinds: all) }
            let then = made.flatMap { baseline.analyze(texture: $0, kinds: all) }
            compared += 1
            for kind in ScopeKind.allCases {
                let a = tree?[kind]
                let b = then?[kind]
                if a == nil || a != b { differ.append("\(name) \(kind.rawValue)") }
            }
        }
    }
    check(
        "S12 75 % red counts every pixel at ×1 and none at ×2 (off_plot the pixels); at ×1 all "
            + "four kinds' counts equal an analyser over the T4-0 tree's Waveform.metal on the six "
            + "fixtures, the six 75 % cards and pure red",
        offAtTwo && baseline != nil && compared == 13 && differ.isEmpty,
        "75 % red ×1 sum \(sum(one)) off \(one?.offPlot ?? -1), ×2 sum \(sum(two)) off "
            + "\(two?.offPlot ?? -1); baseline \(baseline != nil) \(baselineError); compared "
            + "\(compared); differ \(differ.prefix(8))")
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

/// The median GPU time of `passes` over `frame`, in ms. A burst of sixteen
/// passes committed back to back first, unread, so the GPU's clock is up as it
/// is under playback: measured cold, one at a time, the figures swung two- to
/// threefold between runs. Then the twelve passes one at a time, each waited
/// on, since buffers committed together run two at once and each one's own
/// time doubles.
func gpuMedian(
    _ analyzer: WaveformAnalyzer, _ passes: Set<ScopePass>, _ frame: MTLTexture,
    _ queue: MTLCommandQueue, signal: ScopeSignal = .sdr
) -> Double? {
    var burst: [MTLCommandBuffer] = []
    for _ in 0..<16 {
        guard let buffer = queue.makeCommandBuffer(),
            analyzer.encode(passes, frame: frame, into: buffer, signal: signal) != nil
        else { continue }
        buffer.commit()
        burst.append(buffer)
    }
    for buffer in burst { buffer.waitUntilCompleted() }
    var times: [Double] = []
    for _ in 0..<12 {
        guard let buffer = queue.makeCommandBuffer(),
            analyzer.encode(passes, frame: frame, into: buffer, signal: signal) != nil
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
    // hdr H-4 (spec §11 HD-15): the HLG signal's variants beside the SDR ones.
    let variants: [(String, Set<ScopePass>, ScopeSignal)] = [
        ("parade", [ScopePass(.parade)], .sdr), ("vectorscope", [ScopePass(.vectorscope)], .sdr),
        ("vectorscope-x2", [ScopePass(.vectorscope, zoom: 2)], .sdr),
        ("vectorscope-x4", [ScopePass(.vectorscope, zoom: 4)], .sdr),
        ("histogram", [ScopePass(.histogram)], .sdr), ("waveform", [ScopePass(.waveform)], .sdr),
        ("waveform+vectorscope", [ScopePass(.waveform), ScopePass(.vectorscope)], .sdr),
        ("waveform-hlg", [ScopePass(.waveform)], .hlg),
        ("vectorscope-hlg", [ScopePass(.vectorscope)], .hlg),
        ("vectorscope-hlg-x2", [ScopePass(.vectorscope, zoom: 2)], .hlg),
        ("vectorscope-hlg-x4", [ScopePass(.vectorscope, zoom: 4)], .hlg),
        ("histogram-hlg", [ScopePass(.histogram)], .hlg),
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
                for (variant, passes, signal) in variants {
                    if let median = gpuMedian(analyzer, passes, made, queue, signal: signal) {
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

// MARK: - T2 and T3: a threadgroup path against its forced-global twin (scored by the proof)

/// The tree's shader again, with its one line starting `prefix` forced to
/// `forced`, timed against the tree's own pass back to back on each 4K
/// fixture: the record's `4K` holds `{fixture: {mine: ms, "global": ms}}`,
/// or it holds `anchor` (not exactly one such line) or `error`.
func forcedGlobal(
    prefix: String, forced: String, pass: ScopePass, mine: String
) -> [String: Any] {
    let text = (try? String(contentsOfFile: shaderPath, encoding: .utf8)) ?? ""
    var lines = text.components(separatedBy: "\n")
    let matches = lines.indices.filter {
        lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
    }
    guard matches.count == 1 else { return ["anchor": "\(matches.count) lines start `\(prefix)`"] }
    lines[matches[0]] = forced
    var error = ""
    var global: WaveformAnalyzer?
    do {
        let library = try device.makeLibrary(source: lines.joined(separator: "\n"), options: nil)
        global = WaveformAnalyzer(device: device, library: library)
        if global == nil { error = "the forced-global WaveformAnalyzer is nil" }
    } catch let failure {
        error = "the forced-global shader does not compile: \(failure)"
    }
    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    let queue = device.makeCommandQueue()
    guard let global, let cache, let queue else {
        return ["error": error.isEmpty ? "cache \(cache != nil), queue \(queue != nil)" : error]
    }
    var byFixture: [String: [String: Double]] = [:]
    let (width, height) = (3840, 2160)
    for (name, fill) in fixtures(width, height) {
        guard let frame = pixelBuffer(width, height, fill) else { continue }
        var wrapper: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, frame, nil, .rgba16Float, width, height, 0, &wrapper)
        guard let wrapper, let made = CVMetalTextureGetTexture(wrapper) else { continue }
        var pair: [String: Double] = [:]
        pair[mine] = gpuMedian(analyzer, [pass], made, queue)
        pair["global"] = gpuMedian(global, [pass], made, queue)
        byFixture[name] = pair
        withExtendedLifetime(wrapper) {}
    }
    return ["gpu": device.name, "4K": byFixture]
}

// T2: the parade's one `bool banded = ` line forced to `false`, so every
// parade group adds globally. The proof holds the banded time, on the
// fixture where the forced-global parade is slowest, to a fraction of the
// global one, which is what says the banded path is the one running (T1
// alone cannot: the global parade sits about GR-10's 1.1 ms).
records["T2"] = forcedGlobal(
    prefix: "bool banded = ", forced: "    bool banded = false;", pass: ScopePass(.parade),
    mine: "banded")

// T3 (grading-4 T4-1): the vectorscope's one `bool central = ` line forced
// to `false`, so every pixel goes to the global bins. GR-26's same-bin add
// rescues the flat fixtures T1 used to catch that on, so the proof holds the
// tree's ×1 time on near-grey, the fixture the central path is for (by name
// since #296), to a fraction of the global one: the central threadgroup path
// is the one running. Every fixture is timed and recorded.
records["T3"] = forcedGlobal(
    prefix: "bool central = ", forced: "            bool central = false;",
    pass: ScopePass(.vectorscope), mine: "tree")

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

// MARK: - S14 the panel's zoom: per slot, re-attached, kept, never saved

func s14() {
    guard let path = request["package"] as? String else {
        check("S14 the request names a package", false, "\(request)")
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
        check("S14 the package opens with a scopes panel", false, path)
        return
    }
    settle(controller)
    let before = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let key = document.recipeKey
    let slots = panel.slotViews
    var steps: [String] = []
    var ok = slots.map(\.zoom) == [1, 1]
    steps.append("opening zooms \(slots.map(\.zoom))")
    controller.toggleScopes(nil)
    settle(controller)
    var asks = 0
    let wired = panel.onNeedsFrame
    panel.onNeedsFrame = {
        asks += 1
        wired?()
    }
    func attached() -> Set<ScopePass> { WaveformTaps.shared.attachedPasses(key: key) ?? [] }
    func describe(_ passes: Set<ScopePass>) -> String {
        ScopePass.ordered(passes).map { "\($0.kind.rawValue)×\($0.zoom)" }.joined(separator: "+")
    }
    // A zoom on the bottom (vectorscope) slot: re-attached, one ask, the top
    // slot unchanged.
    var asked = asks
    panel.zoom(4, slot: 1)
    settle(controller)
    let zoomed = attached()
    let wantZoomed: Set<ScopePass> = [ScopePass(.waveform), ScopePass(.vectorscope, zoom: 4)]
    let cells = (slots[1].body as? VectorscopeView)?.cells.zoom
    ok = ok && zoomed == wantZoomed && asks - asked == 1 && slots[0].zoom == 1
        && slots[1].zoom == 4 && cells == 4 && panel.shownPasses == wantZoomed
    steps.append("bottom ×4: attached \(describe(zoomed)), asks +\(asks - asked), cells \(cells ?? -1)")
    // A zoom outside 1, 2, 4 is ignored.
    asked = asks
    panel.zoom(3, slot: 1)
    ok = ok && slots[1].zoom == 4 && asks == asked
    // Both slots vectorscope, ×1 over ×4: two passes, each slot its own trace.
    panel.pick(.vectorscope, slot: 0)
    settle(controller)
    let both = attached()
    let wantBoth: Set<ScopePass> = [
        ScopePass(.vectorscope), ScopePass(.vectorscope, zoom: 4),
    ]
    // The app's shared tap has no analyser in a probe (no default library),
    // so the panel's passes go through a tap over the probe's own: one frame
    // of a gradient, both passes' traces delivered together, then shown.
    var delivered: [ScopePass: ScopeTrace]?
    let local = WaveformTaps(analyzer: analyzer)
    let localKey = 990_114
    local.attach(key: localKey, passes: panel.shownPasses) { traces in delivered = traces }
    if let frame = pixelBuffer(320, 180, { x, y in (Float(x) / 320, Float(y) / 180, 0.4) }) {
        local.offer(frame, key: localKey)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, delivered == nil {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
    local.detach(key: localKey)
    panel.show(delivered)
    let shown = slots.map { ($0.body as? VectorscopeView)?.trace?.zoom }
    let offTop = (slots[0].body as? VectorscopeView)?.trace?.offPlot
    let offBottom = (slots[1].body as? VectorscopeView)?.trace?.offPlot
    ok = ok && both == wantBoth && delivered?.count == 2 && shown == [1, 4] && offTop == 0
    steps.append(
        "vectorscope ×1 over ×4: attached \(describe(both)), delivered "
            + "\(describe(Set(delivered?.keys.map { $0 } ?? []))), shown zooms \(shown), off "
            + "\(offTop ?? -1) / \(offBottom ?? -1)")
    // Kept across hide and show, and a pick away and back.
    controller.toggleScopes(nil)
    settle(controller)
    controller.toggleScopes(nil)
    settle(controller)
    let afterShow = slots.map(\.zoom)
    panel.pick(.parade, slot: 1)
    settle(controller)
    let away = attached()
    panel.pick(.vectorscope, slot: 1)
    settle(controller)
    let back = slots[1].zoom
    let backBody = (slots[1].body as? VectorscopeView)?.zoom
    ok = ok && afterShow == [1, 4] && away == [ScopePass(.vectorscope), ScopePass(.parade)]
        && back == 4 && backBody == 4 && attached() == wantBoth
    steps.append(
        "after hide/show \(afterShow); picked away \(describe(away)); back ×\(back), body "
            + "×\(backBody ?? -1)")
    controller.toggleScopes(nil)
    settle(controller)
    let after = UserDefaults.standard.dictionaryRepresentation() as NSDictionary
    let moved = Set((before.allKeys + after.allKeys).compactMap { $0 as? String }).filter {
        (before[$0] as? NSObject) != (after[$0] as? NSObject)
    }
    window.close()
    let fresh = open()
    let restarted = fresh?.1.scopesPanel?.slotViews.map(\.zoom)
    fresh?.2.close()
    check(
        "S14 both slots ×1 on open; a zoom re-attaches that slot's pass and asks for one frame, "
            + "the other slot unchanged; vectorscope ×1 over ×4 attaches two passes and each slot "
            + "shows its own zoom's trace; the zoom lasts across hide and show and a pick away and "
            + "back; no UserDefaults key moves; a new controller is ×1",
        ok && moved.isEmpty && restarted == [1, 1],
        steps.joined(separator: " | ") + "; moved \(moved.sorted()); restarted \(restarted ?? [])")
}
s14()

finish()
