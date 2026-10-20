// Built by tools/proof/log_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header, rows LP1–LP4
// (grading-3 T3-2, spec §11 GR-16).
//
// Step 0's camera-log maths through the app's own types: the selector over
// a media's `color` (`InputConversion.choose(input:)`), the decoding of a
// `color` the core writes without `detected` (alone, and as a recipe layer's
// and a plan segment's `input`), `InputConversions.toBT709` for the camera
// gamuts, and the pass itself — an `InputStage` built from the tree's
// `Compositor.metal`, read from the request's `shader` and compiled by
// `makeLibrary(source:)` (hdr_probe.swift's way), drawing `rgba16Float`
// textures the oracle's inputs fill; kind 8 samples a `.cube` the script
// wrote, uploaded by the app's own `LutTextures`. Nothing private is widened.
//
//   log_probe <request.json> <answer.json>
//
// One JSON object out: `rows`, each a name, ok and detail, the name starting
// with its LP-number.
import AVFoundation
import CoreMedia
import Metal
import simd

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1500))])
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

func name(_ p: InputPrimaries) -> String {
    switch p {
    case .bt709: return "bt709"
    case .bt2020: return "bt2020"
    case .p3D65: return "p3D65"
    case .sGamut3Cine: return "sGamut3Cine"
    case .sGamut3: return "sGamut3"
    case .vGamut: return "vGamut"
    case .appleWideGamut: return "appleWideGamut"
    }
}

func describe(_ conversion: InputConversion?) -> String {
    switch conversion {
    case nil: return "nil"
    case .hlg(let p): return "hlg(\(name(p)))"
    case .pq(let p): return "pq(\(name(p)))"
    case .sdrWide(let p): return "sdrWide(\(name(p)))"
    case .srgb(let p): return "srgb(\(name(p)))"
    case .log(let curve, let p): return "log(\(curve.rawValue),\(name(p)))"
    case .lut(let id): return "lut(\(id))"
    case .sdr: return "sdr"
    }
}

func json(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    else { return "{}" }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - LP1 the selector over a media's colour, and its decoding

do {
    var misses: [String] = []
    let cases = request["pairings"] as? [[Any]] ?? []
    for item in cases where item.count == 2 {
        let color = item[0] as? [String: Any] ?? [:]
        let want = item[1] as? String ?? "?"
        let decoded = ReelJSON.decode(MediaColor.self, from: json(color))
        let got = decoded.flatMap { InputConversion.choose(input: $0) }
        if describe(got) != want {
            misses.append("\(json(color)): \(describe(got)), want \(want)")
        }
        if let decoded, decoded.detected {
            misses.append("\(json(color)) decoded with detected true")
        }
    }
    // The core writes `detected` only when true, and never in an `input`.
    let inputs: [[String: Any]] = [["log": "slog3", "gamut": "s_gamut3_cine"], ["lut": 12]]
    for input in inputs {
        let alone = ReelJSON.decode(MediaColor.self, from: json(input))
        let layer = ReelJSON.decode(
            RecipeLayer.self,
            from: json(["clip": 3, "source": ["kind": "track", "track": 1], "input": input]))
        let segment = ReelJSON.decode(
            PlanSegment.self,
            from: json([
                "clip": 3, "media": 2, "source_in": 0, "source_duration": 600_000, "start": 0,
                "duration": 600_000, "input": input,
            ]))
        if alone == nil || alone?.detected != false {
            misses.append("\(json(input)) alone decoded to \(String(describing: alone))")
        }
        if layer?.input == nil || layer?.input != alone {
            misses.append("\(json(input)) as a layer's input: \(String(describing: layer?.input))")
        }
        if segment?.input == nil || segment?.input != alone {
            misses.append(
                "\(json(input)) as a segment's input: \(String(describing: segment?.input))")
        }
    }
    let detected = ReelJSON.decode(
        MediaColor.self, from: #"{"log":"apple_log","gamut":"bt2020","detected":true}"#)
    if detected?.detected != true {
        misses.append("a detected colour decoded to \(String(describing: detected))")
    }
    check(
        "LP1 choose(input:) answers \(cases.count) colours (every pairing, each curve's default "
            + "gamut, a LUT, and an empty colour → nil), and {log, gamut} and {lut} with no "
            + "detected decode non-nil alone, as a recipe layer's input and as a plan segment's",
        cases.count >= 10 && misses.isEmpty, misses.joined(separator: "; "))
}

// MARK: - LP2 the camera gamuts' matrices

do {
    let python = request["matrices"] as? [String: [[Double]]] ?? [:]
    let gamuts: [(String, CameraGamut)] = [
        ("bt2020", .bt2020), ("s_gamut3_cine", .sGamut3Cine), ("s_gamut3", .sGamut3),
        ("v_gamut", .vGamut), ("apple_wide_gamut", .appleWideGamut),
    ]
    var worst = 0.0
    var detail: [String] = []
    for (key, gamut) in gamuts {
        let m = InputConversions.toBT709(from: InputPrimaries(gamut))
        guard let want = python[key], want.count == 3 else {
            worst = .infinity
            detail.append("\(key): no oracle")
            continue
        }
        for r in 0..<3 {
            for c in 0..<3 {
                worst = max(worst, abs(Double(m[c][r]) - want[r][c]))
            }
        }
        detail.append("\(key) row0 \(m[0][0]) \(m[1][0]) \(m[2][0])")
    }
    check(
        "LP2 toBT709(from: InputPrimaries(gamut)) equals the oracle's derivation ±1e-4 for "
            + "BT.2020, S-Gamut3.Cine, S-Gamut3, V-Gamut and Apple Wide Gamut",
        worst <= 1e-4, "worst |Δ| \(worst); \(detail.joined(separator: "; "))")
}

// MARK: - LP3 the pass

func runPass(
    _ stage: InputStage, device: MTLDevice, queue: MTLCommandQueue,
    conversion: InputConversion, premultiplied: Bool, texels: [SIMD4<Float>], lut: MTLTexture?
) -> [SIMD4<Float>]? {
    let width = texels.count
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: 1, mipmapped: false)
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    guard let source = device.makeTexture(descriptor: descriptor) else { return nil }
    var halves = texels.flatMap { [Float16($0.x), Float16($0.y), Float16($0.z), Float16($0.w)] }
    source.replace(
        region: MTLRegionMake2D(0, 0, width, 1), mipmapLevel: 0, withBytes: &halves,
        bytesPerRow: width * 8)
    let readDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: 1, mipmapped: false)
    readDescriptor.storageMode = .shared
    guard let readback = device.makeTexture(descriptor: readDescriptor),
        let buffer = queue.makeCommandBuffer()
    else { return nil }
    stage.beginFrame()
    defer { stage.endFrame() }
    guard let target = stage.target(width: width, height: 1),
        stage.encode(
            conversion, premultiplied: premultiplied, from: source, into: target, buffer: buffer,
            lut: lut),
        let blit = buffer.makeBlitCommandEncoder()
    else { return nil }
    blit.copy(from: target, to: readback)
    blit.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    var back = [Float16](repeating: 0, count: width * 4)
    readback.getBytes(
        &back, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, 1), mipmapLevel: 0)
    return (0..<width).map {
        SIMD4<Float>(Float(back[4 * $0]), Float(back[4 * $0 + 1]), Float(back[4 * $0 + 2]),
                     Float(back[4 * $0 + 3]))
    }
}

func conversion(_ item: [String: Any]) -> InputConversion? {
    if let lut = item["lut"] as? Int { return .lut(UInt32(lut)) }
    guard let curve = (item["log"] as? String).flatMap(LogCurve.init(rawValue:)),
        let gamut = (item["gamut"] as? String).flatMap(CameraGamut.init(rawValue:))
    else { return nil }
    return .log(curve, InputPrimaries(gamut))
}

do {
    let shaderPath = request["shader"] as? String ?? ""
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
        let text = try? String(contentsOfFile: shaderPath, encoding: .utf8)
    else {
        check("LP3 the pass runs", false, "no Metal device or no shader at \(shaderPath)")
        finish()
    }
    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: text, options: nil)
    } catch {
        check("LP3 the pass runs", false, "the shader did not compile: \(error)")
        finish()
    }
    guard let stage = InputStage(device: device, library: library) else {
        check("LP3 the pass runs", false, "InputStage(device:library:) answered nil")
        finish()
    }
    let lutTexture = (request["cube"] as? String).flatMap {
        LutTextures(device: device).texture(at: URL(fileURLWithPath: $0))
    }
    var misses: [String] = []
    var worst: Float = 0
    for item in request["p3"] as? [[String: Any]] ?? [] {
        let label = item["label"] as? String ?? "?"
        guard let conversion = conversion(item) else {
            misses.append("\(label): no conversion")
            continue
        }
        let isLUT: Bool
        if case .lut = conversion { isLUT = true } else { isLUT = false }
        if isLUT && lutTexture == nil {
            misses.append("\(label): the cube did not upload")
            continue
        }
        let inputs = (item["inputs"] as? [[Double]] ?? []).map {
            SIMD4<Float>(Float($0[0]), Float($0[1]), Float($0[2]), 1)
        }
        let outputs = item["outputs"] as? [[Double]] ?? []
        let bounds = item["bounds"] as? [Double]
        guard let straight = runPass(
            stage, device: device, queue: queue, conversion: conversion, premultiplied: false,
            texels: inputs, lut: isLUT ? lutTexture : nil), straight.count == outputs.count
        else {
            misses.append("\(label): the pass did not run")
            continue
        }
        var bad = 0
        for (i, (got, want)) in zip(straight, outputs).enumerated() {
            let gap = (0..<3).map { abs(got[$0] - Float(want[$0])) }.max() ?? 0
            let bound = Float(bounds?[i] ?? 2e-3)
            worst = max(worst, bounds == nil ? gap : 0)
            if gap > bound || !got.x.isFinite || !got.y.isFinite || !got.z.isFinite {
                bad += 1
                if bad <= 3 {
                    misses.append("\(label) #\(i) in \(inputs[i]) got \(got) want \(want) ±\(bound)")
                }
            }
        }
        if bad > 3 { misses.append("\(label): \(bad) texels outside their bound") }
        guard item["premultiplied"] as? Bool ?? false else { continue }
        // Premultiplied: α 0 (rgb 0) and α 0.5 (rgb × 0.5) against the straight result.
        let sample = Array(inputs.prefix(40))
        let zero = sample.map { _ in SIMD4<Float>(0, 0, 0, 0) }
        let halfAlpha = sample.map { SIMD4<Float>($0.x * 0.5, $0.y * 0.5, $0.z * 0.5, 0.5) }
        if let z = runPass(stage, device: device, queue: queue, conversion: conversion,
                           premultiplied: true, texels: zero, lut: isLUT ? lutTexture : nil),
            let h = runPass(stage, device: device, queue: queue, conversion: conversion,
                            premultiplied: true, texels: halfAlpha, lut: isLUT ? lutTexture : nil)
        {
            let zeroOK = z.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w == 0
                    && abs($0.x) + abs($0.y) + abs($0.z) <= 1e-6
            }
            let halfOK = zip(h, straight.prefix(40)).allSatisfy { got, full in
                (0..<3).allSatisfy { abs(got[$0] - full[$0] * 0.5) <= 2e-3 } && got.w == 0.5
            }
            if !zeroOK { misses.append("\(label): α 0 gave \(z.prefix(2))") }
            if !halfOK {
                misses.append("\(label): α 0.5 gave \(h.prefix(2)) vs \(straight.prefix(2))")
            }
        } else {
            misses.append("\(label): the premultiplied passes did not run")
        }
    }
    check(
        "LP3 the pass on rgba16Float: each curve at its maker's 0/18/90 % codes decodes to 0, "
            + "0.18 and 0.90 (±0.005 of reflectance), a 1,024-step ramp across its break and 512 "
            + "seeded triples equal the oracle ±2e-3, premultiplied α 0 stays 0 and α 0.5 is the "
            + "straight result × 0.5; kind 8 with a channel-distinct 17³ cube over a 9×9×9 grid "
            + "equals Python's trilinear ±2e-3",
        misses.isEmpty && !(request["p3"] as? [Any] ?? []).isEmpty,
        "worst |Δ| \(worst); \(misses.prefix(12).joined(separator: "; "))")
}

// MARK: - LP4 the constants

do {
    let want = request["constants"] as? [String: Double] ?? [:]
    let mine: [String: Float] = [
        "logMidGrey": InputConversions.logMidGrey,
        "logExposure": InputConversions.logExposure,
        "logWhite": InputConversions.logWhite,
        "shoulderKnee": InputConversions.shoulderKnee,
        "displayGamma": InputConversions.displayGamma,
        "videoCodeScale": InputConversions.videoCodeScale,
        "videoCodeOffset": InputConversions.videoCodeOffset,
        "kindAppleLog": InputUniforms.appleLog,
        "kindSlog3": InputUniforms.slog3,
        "kindVlog": InputUniforms.vlog,
        "kindLUT": InputUniforms.lut,
    ]
    let wrong = mine.filter { key, value in
        guard let w = want[key] else { return true }
        return abs(Double(value) - w) > 1e-6 * max(1, abs(w))
    }
    let stride = MemoryLayout<InputUniforms>.stride
    check(
        "LP4 InputConversions' log constants are GR-16's (mid-grey 0.42, exposure 0.42^2.4/0.18, "
            + "white 64·0.42^2.4, knee 0.39, the video code scale and offset), the kinds are 5–8, "
            + "and InputUniforms is 112 bytes (hdr H-2's HLG group)",
        wrong.isEmpty && want.count == mine.count && stride == 112,
        "wrong \(wrong); stride \(stride)")
}

finish()
