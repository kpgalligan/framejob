// Built by tools/proof/hdr_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header, rows P1–P9
// (grading-3 T3-1, spec §11 GR-15 as amended; P5 hdr H-1, spec §11 HD-12; P6
// hdr H-2, spec §11 HD-3, HD-13; P7 hdr H-3, spec §11 HD-14; P8 hdr H-4, spec
// §11 HD-15: `ScopeSignal`, the traces' JSON, and the waveform's, parade's
// and vectorscope's drawing cached to bitmaps; P9 hdr H-6, spec §11 HD-16:
// `RecipeCanvas.blended`, `uniforms(for:)` and the four blocks' sizes).
//
// Step 0's maths through the app's own types: `InputConversion`'s selector
// through BOTH readers (the labels as strings, and a `CMVideoFormatDescription`
// made with those extensions), `InputConversions.toBT709`, and the pass itself
// — an `InputStage` built from the tree's `Compositor.metal`, read from the
// request's `shader` and compiled by `makeLibrary(source:)` (look_probe.swift's
// way), drawing `rgba16Float` textures the oracle's inputs fill. Nothing
// private is widened.
//
//   hdr_probe <request.json> <answer.json>
//
// One JSON object out: `rows`, each a name, ok and detail, the name starting
// with its P-number.
import AVFoundation
import AppKit
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

func describe(_ conversion: InputConversion?) -> String {
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

// MARK: - P1 the selector, through both readers

do {
    let transfers: [String: String] = [
        "HLG": kCVImageBufferTransferFunction_ITU_R_2100_HLG as String,
        "PQ": kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String,
        "709": kCVImageBufferTransferFunction_ITU_R_709_2 as String,
        "2020": kCVImageBufferTransferFunction_ITU_R_2020 as String,
        "sRGB": kCVImageBufferTransferFunction_sRGB as String,
        "240M": kCVImageBufferTransferFunction_SMPTE_240M_1995 as String,
    ]
    let primaries: [String: String] = [
        "709": kCVImageBufferColorPrimaries_ITU_R_709_2 as String,
        "2020": kCVImageBufferColorPrimaries_ITU_R_2020 as String,
        "P3D65": kCVImageBufferColorPrimaries_P3_D65 as String,
        "DCIP3": kCVImageBufferColorPrimaries_DCI_P3 as String,
    ]
    let logs: [String: String] = [
        "AppleLog": kCVImageBufferLogTransferFunction_AppleLog as String
    ]
    var misses: [String] = []
    let cases = request["cases"] as? [[Any]] ?? []
    for item in cases where item.count == 5 {
        let transfer = (item[0] as? String).flatMap { transfers[$0] }
        let primary = (item[1] as? String).flatMap { primaries[$0] }
        let log = (item[2] as? String).flatMap { logs[$0] }
        let want = item[3] as? String ?? "?"
        let byLabel = InputConversion.choose(
            transfer: transfer, primaries: primary, logTransfer: log)
        var extensions: [String: Any] = [:]
        if let transfer { extensions[kCMFormatDescriptionExtension_TransferFunction as String] = transfer }
        if let primary { extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] = primary }
        if let log { extensions[kCMFormatDescriptionExtension_LogTransferFunction as String] = log }
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCMVideoCodecType_AppleProRes422, width: 16, height: 16,
            extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        let byDescription = description.flatMap { InputConversion.choose(for: $0) }
        let starts = item[4] as? Bool
        if describe(byLabel) != want || describe(byDescription) != want
            || (starts != nil && byLabel?.startsConversion != starts)
        {
            misses.append(
                "\(item[0]) \(item[1]) \(item[2]): labels \(describe(byLabel)), description "
                    + "\(describe(byDescription)), want \(want); starts "
                    + "\(String(describing: byLabel?.startsConversion)) want \(String(describing: starts))")
        }
    }
    check(
        "P1 the selector answers \(cases.count) label cases the same through both readers "
            + "(Apple Log + HLG → nil, DCI-P3 → nil, sRGB → the sRGB arm with its primaries), "
            + "and startsConversion is false for .srgb(.bt709) alone",
        cases.count >= 14 && misses.isEmpty, misses.joined(separator: "; "))
}

// MARK: - P2 the matrices

do {
    let python = request["matrices"] as? [String: [[Double]]] ?? [:]
    let primaries: [(String, InputPrimaries)] = [
        ("bt709", .bt709), ("bt2020", .bt2020), ("p3d65", .p3D65),
    ]
    var worst = 0.0
    var detail: [String] = []
    for (name, p) in primaries {
        let m = InputConversions.toBT709(from: p)
        guard let want = python[name], want.count == 3 else {
            worst = .infinity
            continue
        }
        for r in 0..<3 {
            for c in 0..<3 {
                worst = max(worst, abs(Double(m[c][r]) - want[r][c]))
            }
        }
        detail.append("\(name) row0 \(m[0][0]) \(m[1][0]) \(m[2][0])")
    }
    check(
        "P2 toBT709(from:) equals the oracle's derivation ±1e-4 for BT.709, BT.2020 and P3 D65",
        worst <= 1e-4, "worst |Δ| \(worst); \(detail.joined(separator: "; "))")
}

// MARK: - P3 the pass

func runPass(
    _ stage: InputStage, device: MTLDevice, queue: MTLCommandQueue,
    conversion: InputConversion, premultiplied: Bool, texels: [SIMD4<Float>]
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
            conversion, premultiplied: premultiplied, from: source, into: target, buffer: buffer),
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

do {
    let shaderPath = request["shader"] as? String ?? ""
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
        let text = try? String(contentsOfFile: shaderPath, encoding: .utf8)
    else {
        check("P3 the pass runs", false, "no Metal device or no shader at \(shaderPath)")
        finish()
    }
    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: text, options: nil)
    } catch {
        check("P3 the pass runs", false, "the shader did not compile: \(error)")
        finish()
    }
    guard let stage = InputStage(device: device, library: library) else {
        check("P3 the pass runs", false, "InputStage(device:library:) answered nil")
        finish()
    }
    let gamuts: [String: InputPrimaries] = ["bt709": .bt709, "bt2020": .bt2020, "p3d65": .p3D65]
    var misses: [String] = []
    var worst: Float = 0
    for item in request["p3"] as? [[String: Any]] ?? [] {
        let code = item["code"] as? Int ?? 0
        let p = gamuts[item["primaries"] as? String ?? ""] ?? .bt709
        let conversion: InputConversion
        switch code {
        case 1: conversion = .hlg(p)
        case 2: conversion = .pq(p)
        case 3: conversion = .sdrWide(p)
        default: conversion = .srgb(p)
        }
        let label = "\(describe(conversion))"
        let inputs = (item["inputs"] as? [[Double]] ?? []).map {
            SIMD4<Float>(Float($0[0]), Float($0[1]), Float($0[2]), 1)
        }
        let outputs = item["outputs"] as? [[Double]] ?? []
        guard let straight = runPass(
            stage, device: device, queue: queue, conversion: conversion, premultiplied: false,
            texels: inputs), straight.count == outputs.count
        else {
            misses.append("\(label): the pass did not run")
            continue
        }
        var bad = 0
        for (i, (got, want)) in zip(straight, outputs).enumerated() {
            let gap = (0..<3).map { abs(got[$0] - Float(want[$0])) }.max() ?? 0
            worst = max(worst, gap)
            if gap > 2e-3 || !got.x.isFinite || !got.y.isFinite || !got.z.isFinite {
                bad += 1
                if bad <= 3 {
                    misses.append("\(label) #\(i) in \(inputs[i]) got \(got) want \(want)")
                }
            }
        }
        if bad > 3 { misses.append("\(label): \(bad) texels outside ±2e-3") }
        // Premultiplied: α 0 (rgb 0) and α 0.5 (rgb × 0.5) against the straight result.
        let sample = Array(inputs.prefix(40))
        let zero = sample.map { _ in SIMD4<Float>(0, 0, 0, 0) }
        let halfAlpha = sample.map { SIMD4<Float>($0.x * 0.5, $0.y * 0.5, $0.z * 0.5, 0.5) }
        if let z = runPass(stage, device: device, queue: queue, conversion: conversion,
                           premultiplied: true, texels: zero),
            let h = runPass(stage, device: device, queue: queue, conversion: conversion,
                            premultiplied: true, texels: halfAlpha)
        {
            let zeroOK = z.allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.x == 0 && $0.y == 0
                    && $0.z == 0 && $0.w == 0
            }
            let halfOK = zip(h, straight.prefix(40)).allSatisfy { got, full in
                (0..<3).allSatisfy { abs(got[$0] - full[$0] * 0.5) <= 2e-3 } && got.w == 0.5
            }
            if !zeroOK { misses.append("\(label): α 0 gave \(z.prefix(2))") }
            if !halfOK { misses.append("\(label): α 0.5 gave \(h.prefix(2)) vs \(straight.prefix(2))") }
        } else {
            misses.append("\(label): the premultiplied passes did not run")
        }
    }
    check(
        "P3 the pass on rgba16Float grey steps (0.453 among them; 0.02 and 0.04 for the sRGB "
            + "arm) and 512 seeded triples per case equals the oracle ±2e-3, and premultiplied "
            + "texels at α 0 stay 0 and at α 0.5 are the straight result × 0.5",
        misses.isEmpty, "worst |Δ| \(worst); \(misses.prefix(12).joined(separator: "; "))")
}

// MARK: - P4 the constants

do {
    let want = request["constants"] as? [String: Double] ?? [:]
    let mine: [String: Float] = [
        "hlgSystemGamma": InputConversions.hlgSystemGamma,
        "hlgGain": InputConversions.hlgGain,
        "shoulderKnee": InputConversions.shoulderKnee,
        "hlgWhite": InputConversions.hlgWhite,
        "pqReferenceWhite": InputConversions.pqReferenceWhite,
        "pqWhite": InputConversions.pqWhite,
        "displayGamma": InputConversions.displayGamma,
        "coreMedia709Gamma": InputConversions.coreMedia709Gamma,
    ]
    let wrong = mine.filter { key, value in
        guard let w = want[key] else { return true }
        return abs(Double(value) - w) > 1e-6
    }
    let stride = MemoryLayout<InputUniforms>.stride
    check(
        "P4 InputConversions' constants are GR-15's (502/256 included) and InputUniforms is 112 "
            + "bytes (hdr H-2's HLG group)",
        wrong.isEmpty && want.count == mine.count && stride == 112,
        "wrong \(wrong); stride \(stride)")
}

// MARK: - P5 the PQ peak (hdr H-1, spec §11 HD-12)

do {
    var misses: [String] = []
    let reference = InputConversions.pqReferenceWhite
    let whites: [(UInt32?, Float)] = [
        (nil, InputConversions.pqWhite / reference), (100, 1), (203, 1), (1000, 1000 / reference),
        (4000, Float(4000) / reference),
    ]
    for (peak, want) in whites {
        let got = InputConversions.pqShoulderWhite(peak: peak)
        if got.bitPattern != want.bitPattern {
            misses.append("pqShoulderWhite(\(peak.map(String.init) ?? "nil")) = \(got), want \(want)")
        }
    }
    let unknown = InputConversion.pq(.bt2020).uniforms(premultiplied: false).white
    if unknown.bitPattern != (InputConversions.pqWhite / reference).bitPattern {
        misses.append("the PQ arm's white with no peak is \(unknown), not 1000/203")
    }
    let at4000 = InputConversion.pq(.bt2020).uniforms(premultiplied: false, peak: 4000).white
    if at4000.bitPattern != (Float(4000) / reference).bitPattern {
        misses.append("the PQ arm's white at 4,000 is \(at4000)")
    }
    func decoded(_ text: String) -> MediaColor? {
        try? JSONDecoder().decode(MediaColor.self, from: Data(text.utf8))
    }
    let stored = decoded(
        #"{"log":"slog3","gamut":"s_gamut3","pq":{"file":4000,"from":"max_cll","peak":1000}}"#)
    if stored?.pq != PQColor(file: 4000, from: .maxCLL, peak: 1000) || stored?.peak != nil
        || stored?.pq?.effectivePeak != 1000 || stored?.log != .slog3
    {
        misses.append("the stored shape decoded as \(String(describing: stored))")
    }
    let reading = decoded(#"{"pq":{"file":2000,"from":"mastering_display"}}"#)
    if reading?.pq != PQColor(file: 2000, from: .masteringDisplay) || reading?.pq?.effectivePeak != 2000 {
        misses.append("a reading decoded as \(String(describing: reading))")
    }
    let empty = decoded(#"{"pq":{}}"#)
    if empty?.pq != PQColor() || empty?.pq?.effectivePeak != nil {
        misses.append("{pq: {}} decoded as \(String(describing: empty))")
    }
    let input = decoded(#"{"peak":4000}"#)
    if input?.peak != 4000 || input?.pq != nil || input?.log != nil || input?.lut != nil {
        misses.append("the input shape decoded as \(String(describing: input))")
    }
    let color = MediaColor(
        log: .slog3, gamut: .sGamut3, pq: PQColor(file: 4000, from: .maxCLL, peak: 1000))
    let op = color.opDictionary
    if op.count != 3 || op["log"] as? String != "slog3" || op["gamut"] as? String != "s_gamut3"
        || op["peak"] as? UInt32 != 1000
    {
        misses.append("opDictionary \(op)")
    }
    let descriptor = color.descriptorDictionary
    let pq = descriptor["pq"] as? [String: Any] ?? [:]
    if descriptor["peak"] != nil || pq.count != 3 || pq["file"] as? UInt32 != 4000
        || pq["from"] as? String != "max_cll" || pq["peak"] as? UInt32 != 1000
    {
        misses.append("descriptorDictionary \(descriptor)")
    }
    let readingOnly = MediaColor(pq: PQColor(file: 4000, from: .maxCLL))
    for (tag, asked) in [("a reading alone", readingOnly), ("an empty color", MediaColor())] {
        let sent = ReelOp.setMediaColor(media: 3, color: asked).args["color"]
        if !(sent is NSNull) {
            misses.append("setMediaColor with \(tag) sent \(String(describing: sent)), not null")
        }
    }
    let overridden = ReelOp.setMediaColor(
        media: 3, color: MediaColor(pq: PQColor(file: 4000, from: .maxCLL, peak: 600)))
        .args["color"] as? [String: Any] ?? [:]
    if overridden.count != 1 || overridden["peak"] as? UInt32 != 600 {
        misses.append("setMediaColor with an override sent \(overridden)")
    }
    let source = MediaImporter.CacheStamp(
        size: 1, modified: 2, duration: 3, width: 4, height: 5, hasVideo: true, hasAudio: false,
        thumbnailHeight: 6, maxThumbnails: 7, peakBucketsPerSecond: 8)
    /// The marker's top-level keys and values, as written to disk.
    func marker(_ color: MediaColor) -> [String: Any] {
        let media = MediaSnapshot(id: 1, path: "/p.mov", color: color)
        guard let thumbs = ThumbnailInput(media: media, urls: [:]),
            let data = try? JSONEncoder().encode(
                ConvertedThumbsStamp(source, input: thumbs, fullRange: false)),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return object
    }
    let logMarker = marker(MediaColor(log: .slog3, gamut: .sGamut3))
    let peakMarker = marker(MediaColor(pq: PQColor(file: 4000, from: .maxCLL)))
    if logMarker["peak"] != nil || logMarker["log"] as? String != "slog3" {
        misses.append("a Camera Log marker with no peak: \(logMarker)")
    }
    if peakMarker["peak"] as? Int != 4000 || peakMarker["log"] != nil {
        misses.append("a PQ reading's marker: \(peakMarker)")
    }
    check(
        "P5 pqShoulderWhite is 1000/203 bit-exact with no peak, 1 at 100 and 203, peak/203 at "
            + "1,000 and 4,000; MediaColor decodes the stored pq and the input's peak; "
            + "opDictionary sends peak and descriptorDictionary pq; setMediaColor sends null "
            + "for an empty dictionary; a marker omits a nil peak",
        misses.isEmpty, misses.joined(separator: "; "))
}

// MARK: - P6 the lift, its inverse, the HLG selector and the pick (hdr H-2, spec §11 HD-13)

do {
    var misses: [String] = []
    // (a) liftSDR against Core Graphics drawing each Core Media 709 grey into a 16-bit-float
    // `itur_2100_HLG` bitmap (HD-3's measurement, at every 10-bit grey).
    let cm709 = CVImageBufferCreateColorSpaceFromAttachments([
        kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
        kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
        kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
    ] as CFDictionary)?.takeRetainedValue()
    let hlg = CGColorSpace(name: CGColorSpace.itur_2100_HLG)
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGBitmapInfo.byteOrder16Little.rawValue
    var worstCG: Float = .infinity, worstRound: Float = .infinity
    if let cm709, let hlg,
        let ctx = CGContext(
            data: nil, width: 1024, height: 1, bitsPerComponent: 16, bytesPerRow: 1024 * 8,
            space: hlg, bitmapInfo: info)
    {
        for i in 0..<1024 {
            let v = CGFloat(i) / 1023
            ctx.setFillColor(CGColor(colorSpace: cm709, components: [v, v, v, 1])!)
            ctx.fill(CGRect(x: i, y: 0, width: 1, height: 1))
        }
        let drawn = ctx.data!.assumingMemoryBound(to: Float16.self)
        worstCG = 0
        worstRound = 0
        var at: (Int, Float, Float) = (0, 0, 0)
        for i in 0..<1024 {
            let g = Float(i) / 1023
            let lifted = InputConversions.liftSDR(SIMD3<Float>(repeating: g))
            let cg = Float(drawn[i * 4])
            if abs(lifted.x - cg) > worstCG { worstCG = abs(lifted.x - cg); at = (i, lifted.x, cg) }
            let back = InputConversions.unliftSDR(lifted)
            worstRound = max(worstRound, abs(back.x - g), abs(back.y - g), abs(back.z - g))
        }
        if worstCG > 1.0 / 1023 {
            misses.append("liftSDR against CG worst \(worstCG * 1023) levels at grey \(at.0): "
                + "\(at.1) against \(at.2)")
        }
        if worstRound > 1.0 / 1023 {
            misses.append("unliftSDR(liftSDR(x)) worst \(worstRound * 1023) levels")
        }
    } else {
        misses.append("the Core Media 709 space or the HLG bitmap could not be made")
    }
    // (c) choose(input:buffer:output:)'s table.
    func buffer(_ transfer: CFString?, _ primaries: CFString?, log: CFString? = nil) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_64RGBAHalf, nil, &made)
        guard let made else { return nil }
        if let transfer {
            CVBufferSetAttachment(made, kCVImageBufferTransferFunctionKey, transfer, .shouldPropagate)
        }
        if let primaries {
            CVBufferSetAttachment(made, kCVImageBufferColorPrimariesKey, primaries, .shouldPropagate)
        }
        if let log {
            CVBufferSetAttachment(made, kCVImageBufferLogTransferFunctionKey, log, .shouldPropagate)
        }
        return made
    }
    let hlgT = kCVImageBufferTransferFunction_ITU_R_2100_HLG
    let pqT = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
    let t709 = kCVImageBufferTransferFunction_ITU_R_709_2
    let srgbT = kCVImageBufferTransferFunction_sRGB
    let p2020 = kCVImageBufferColorPrimaries_ITU_R_2020
    let p709 = kCVImageBufferColorPrimaries_ITU_R_709_2
    let p3 = kCVImageBufferColorPrimaries_P3_D65
    let slog3 = MediaColor(log: .slog3, gamut: .sGamut3)
    let lut = try? JSONDecoder().decode(MediaColor.self, from: Data(#"{"lut":7}"#.utf8))
    // (name, input, buffer, the SDR answer, the HLG answer)
    let table: [(String, MediaColor?, CVPixelBuffer?, String, String)] = [
        ("HLG 2020", nil, buffer(hlgT, p2020), "hlg(bt2020)", "nil"),
        ("HLG P3", nil, buffer(hlgT, p3), "hlg(p3D65)", "hlg(p3D65)"),
        ("HLG 709", nil, buffer(hlgT, p709), "hlg(bt709)", "hlg(bt709)"),
        ("PQ 2020", nil, buffer(pqT, p2020), "pq(bt2020)", "pq(bt2020)"),
        ("709 709", nil, buffer(t709, p709), "nil", "sdr"),
        ("untagged", nil, buffer(nil, nil), "nil", "sdr"),
        ("sRGB 709", nil, buffer(srgbT, p709), "srgb(bt709)", "srgb(bt709)"),
        ("709 2020", nil, buffer(t709, p2020), "sdrWide(bt2020)", "sdrWide(bt2020)"),
        ("Apple Log label", nil,
         buffer(nil, p2020, log: kCVImageBufferLogTransferFunction_AppleLog), "nil", "sdr"),
        ("S-Log3 on 709", slog3, buffer(t709, p709), "log(slog3,sGamut3)", "log(slog3,sGamut3)"),
        ("a LUT on HLG", lut, buffer(hlgT, p2020), "lut(7)", "lut(7)"),
    ]
    for (name, input, frame, sdr, hdr) in table {
        guard let frame else { misses.append("\(name): no buffer"); continue }
        let old = describe(input.flatMap(InputConversion.choose(input:))
            ?? InputConversion.choose(for: frame))
        let gotSDR = describe(InputConversion.choose(input: input, buffer: frame, output: .sdr))
        let gotHLG = describe(InputConversion.choose(input: input, buffer: frame, output: .hlg))
        if gotSDR != sdr || old != sdr || gotHLG != hdr {
            misses.append("\(name): sdr \(gotSDR) (today's \(old), want \(sdr)), hlg \(gotHLG) "
                + "(want \(hdr))")
        }
    }
    // (d) the pick: a 16-bit HLG frame of a known colour, read at its code values, and the
    // eyedropper's stored key un-lifted in an HLG project.
    let known: [CGFloat] = [0.62, 0.40, 0.21]
    var pickDetail = "no frame"
    if let hlg,
        let ctx = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 16, bytesPerRow: 4 * 8,
            space: hlg, bitmapInfo: info)
    {
        ctx.setFillColor(CGColor(colorSpace: hlg, components: known + [1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        if let frame = ctx.makeImage() {
            let point = CGPoint(x: 1.5, y: 1.5)
            let sdrCanvas = CanvasSnapshot(width: 4, height: 4)
            let hlgCanvas = CanvasSnapshot(width: 4, height: 4, output: .hlg)
            let picked = CanvasEyedropperSession.color(
                at: point, in: FrameWriter.pickable(frame), canvas: sdrCanvas)
            let keySDR = CanvasEyedropperSession.keyColor(at: point, in: frame, canvas: sdrCanvas)
            let keyHLG = CanvasEyedropperSession.keyColor(at: point, in: frame, canvas: hlgCanvas)
            let want = InputConversions.unliftedPick(known.map(Double.init) + [1])
            pickDetail = "picked \(String(describing: picked)), key sdr \(String(describing: keySDR)), "
                + "key hlg \(String(describing: keyHLG)), unliftedPick \(want)"
            let pickOK = picked.map { p in (0..<3).allSatisfy { abs(p[$0] - Double(known[$0])) <= 1.0 / 255 } } ?? false
            let keyOK = keyHLG.map { k in (0..<3).allSatisfy { abs(k[$0] - want[$0]) <= 2.0 / 255 } } ?? false
            if !pickOK || keySDR != picked || !keyOK || FrameWriter.isHLG(frame) == false {
                misses.append("the pick: \(pickDetail)")
            }
        } else {
            misses.append("the HLG frame could not be made")
        }
    } else {
        misses.append("the HLG bitmap could not be made")
    }
    check(
        "P6 liftSDR = Core Graphics drawing Core Media 709 into itur_2100_HLG at 1,024 greys ±1/1023, "
            + "unliftSDR(liftSDR(x)) = x ±1/1023, choose(…, output:)'s table (SDR today's, HLG: "
            + "HLG BT.2020 nil, no arm → sdr), and an HLG frame's pick at its code values ±1/255, "
            + "the HLG eyedropper's key = unliftedPick ±2/255",
        misses.isEmpty,
        (misses.isEmpty ? [] : misses).joined(separator: "; ")
            + "; worst against CG \(worstCG * 1023) levels, round trip \(worstRound * 1023) levels; "
            + pickDetail)
}


// MARK: - P7 the output pass's values (hdr H-3, spec §11 HD-14)

do {
    var misses: [String] = []
    func name(_ c: VideoColour) -> String {
        "\(c.primaries ?? "nil")/\(c.transfer ?? "nil")/\(c.matrix ?? "nil")"
    }
    // (a) compositionColour's table: an SDR project's as it was, an HLG one's by the range.
    let bt709 = VideoColour(
        primaries: AVVideoColorPrimaries_ITU_R_709_2, transfer: AVVideoTransferFunction_ITU_R_709_2,
        matrix: AVVideoYCbCrMatrix_ITU_R_709_2)
    let hlgColour = VideoColour(
        primaries: AVVideoColorPrimaries_ITU_R_2020, transfer: AVVideoTransferFunction_ITU_R_2100_HLG,
        matrix: AVVideoYCbCrMatrix_ITU_R_2020)
    let pqColour = VideoColour(
        primaries: AVVideoColorPrimaries_ITU_R_2020,
        transfer: AVVideoTransferFunction_SMPTE_ST_2084_PQ, matrix: AVVideoYCbCrMatrix_ITU_R_2020)
    let none = VideoColour(primaries: nil, transfer: nil, matrix: nil)
    let table: [(Bool, Bool, DynamicRange?, VideoColour)] = [
        (false, false, nil, none), (false, true, nil, bt709), (false, false, .sdr, none),
        (false, true, .pq, bt709), (false, true, .sdr, bt709), (true, true, nil, hlgColour),
        (true, true, .hlg, hlgColour), (true, true, .pq, pqColour), (true, true, .sdr, bt709),
    ]
    for (hlg, converts, range, want) in table {
        let got = OutputTransform.compositionColour(hlg: hlg, converts: converts, range: range)
        if got != want {
            misses.append("compositionColour(hlg \(hlg), converts \(converts), "
                + "\(range?.rawValue ?? "nil")) = \(name(got)), not \(name(want))")
        }
    }
    // (b) previewComposition on hand-built compositions: an HLG one recoloured by the switch,
    // an SDR one never, and at Full with nothing to change the builder's own object.
    func built(_ colour: VideoColour, output: CanvasOutput) -> BuiltComposition {
        let configuration = AVVideoComposition.Configuration(
            colorPrimaries: colour.primaries, colorTransferFunction: colour.transfer,
            colorYCbCrMatrix: colour.matrix, customVideoCompositorClass: nil,
            frameDuration: CMTime(value: 1, timescale: 30), instructions: [], renderScale: 1,
            renderSize: CGSize(width: 64, height: 32))
        return BuiltComposition(
            composition: AVMutableComposition(),
            videoComposition: AVVideoComposition(configuration: configuration),
            videoConfiguration: configuration, audioMix: AVMutableAudioMix(), planJSON: "{}",
            meters: [], output: output)
    }
    func colourOf(_ c: AVVideoComposition) -> VideoColour {
        VideoColour(
            primaries: c.colorPrimaries, transfer: c.colorTransferFunction,
            matrix: c.colorYCbCrMatrix)
    }
    let hlgBuilt = built(hlgColour, output: .hlg)
    let sdrOn = Playback.previewComposition(hlgBuilt, quality: .full, sdrVersion: true)
    let sdrOff = Playback.previewComposition(hlgBuilt, quality: .full, sdrVersion: false)
    if colourOf(sdrOn) != bt709 { misses.append("HLG, sdrVersion true: \(name(colourOf(sdrOn)))") }
    if sdrOn === hlgBuilt.videoComposition { misses.append("HLG, sdrVersion true: the same object") }
    if sdrOff !== hlgBuilt.videoComposition {
        misses.append("HLG, sdrVersion false at Full: not the builder's own object")
    }
    let halfOn = Playback.previewComposition(hlgBuilt, quality: .half, sdrVersion: true)
    if colourOf(halfOn) != bt709 || halfOn.renderSize != CGSize(width: 32, height: 16) {
        misses.append("HLG, sdrVersion true at Half: \(name(colourOf(halfOn))) \(halfOn.renderSize)")
    }
    let sdrBuilt = built(bt709, output: .sdr)
    for on in [false, true] {
        let got = Playback.previewComposition(sdrBuilt, quality: .full, sdrVersion: on)
        if got !== sdrBuilt.videoComposition {
            misses.append("SDR, sdrVersion \(on) at Full: not the builder's own object")
        }
    }
    let sdrHalf = Playback.previewComposition(sdrBuilt, quality: .half, sdrVersion: true)
    if colourOf(sdrHalf) != bt709 { misses.append("SDR at Half: \(name(colourOf(sdrHalf)))") }
    // (c) the block, the knee, the uniforms' choice and the two blobs.
    if MemoryLayout<OutputUniforms>.stride != 16 {
        misses.append("OutputUniforms is \(MemoryLayout<OutputUniforms>.stride) bytes")
    }
    if OutputTransform.sdrKnee != 0.9 { misses.append("sdrKnee \(OutputTransform.sdrKnee)") }
    let canvases: [(RecipeCanvas, Float?)] = [
        (RecipeCanvas(), nil), (RecipeCanvas(dynamicRange: .sdr), nil),
        (RecipeCanvas(output: .hlg), nil), (RecipeCanvas(output: .hlg, dynamicRange: .hlg), nil),
        (RecipeCanvas(output: .hlg, dynamicRange: .sdr), 1),
        (RecipeCanvas(output: .hlg, dynamicRange: .pq), 2),
    ]
    for (canvas, mode) in canvases {
        let got = OutputTransform.uniforms(for: canvas)
        if got?.mode != mode || (got != nil && got?.knee != 0.9) {
            misses.append("uniforms(\(canvas.output), \(canvas.dynamicRange?.rawValue ?? "nil")) = "
                + "\(String(describing: got?.mode))")
        }
    }
    let hex = { (d: Data) in d.map { String(format: "%02x", $0) }.joined() }
    if hex(OutputTransform.masteringDisplay) != "33c286c41d4c0bb884d03e803d134042009896800000" + "0032" {
        misses.append("masteringDisplay \(hex(OutputTransform.masteringDisplay))")
    }
    if hex(OutputTransform.contentLightLevel) != "03e80000" {
        misses.append("contentLightLevel \(hex(OutputTransform.contentLightLevel))")
    }
    // (d) RecipeOptions: the json, delivering and forFrame.
    if RecipeOptions.none.json != nil { misses.append("none.json \(RecipeOptions.none.json ?? "")") }
    let sdrJSON = RecipeOptions(dynamicRange: .sdr).json
    if sdrJSON != "{\"burn_in_timecode\":false,\"ungraded\":false,\"dynamic_range\":\"sdr\"}" {
        misses.append("json \(sdrJSON ?? "nil")")
    }
    func settings(_ color: String?) -> ExportSettings? {
        let colorKey = color.map { ",\"color\":\"\($0)\"" } ?? ""
        let text = "{\"preset\":\"h264\",\"container\":\"mp4\",\"codec\":\"h264\",\"width\":64,"
            + "\"height\":32,\"fps\":[30,1],\"range\":{\"start\":0,\"duration\":600000}\(colorKey)}"
        return try? ReelJSON.decoder().decode(ExportSettings.self, from: Data(text.utf8))
    }
    let burnt = RecipeOptions(burnInTimecode: true)
    for (color, want) in [(nil, nil), ("hlg", nil), ("pq", DynamicRange.pq), ("sdr", .sdr)]
        as [(String?, DynamicRange?)]
    {
        guard let resolved = settings(color) else {
            misses.append("settings \(color ?? "nil") did not decode")
            continue
        }
        let got = burnt.delivering(resolved)
        if got.dynamicRange != want || !got.burnInTimecode {
            misses.append("delivering(\(color ?? "nil")) = \(got.dynamicRange?.rawValue ?? "nil")")
        }
    }
    for format in FrameWriter.Format.allCases {
        for output in CanvasOutput.allCases {
            let got = burnt.forFrame(format, output: output)
            let want: DynamicRange? = format == .jpeg && output == .hlg ? .sdr : nil
            if got.dynamicRange != want || !got.burnInTimecode {
                misses.append("forFrame(\(format), \(output)) = \(got.dynamicRange?.rawValue ?? "nil")")
            }
        }
    }
    check(
        "P7 compositionColour's table, previewComposition recolouring an HLG composition by "
            + "sdrVersion (an SDR one never; the same object at Full with nothing to change), "
            + "OutputUniforms 16 bytes, sdrKnee 0.9, uniforms(for:) only for HLG + sdr/pq, the two "
            + "HDR10 blobs, RecipeOptions.json / delivering / forFrame",
        misses.isEmpty, misses.isEmpty ? "as wanted" : misses.joined(separator: "; "))
}

// MARK: - P8 the scopes' signal (hdr H-4, spec §11 HD-15)

/// `view` drawn by `cacheDisplay` inside a borderless offscreen window (the
/// panel's own paint path), or nil.
func cached(_ view: NSView) -> NSBitmapImageRep? {
    let window = NSWindow(
        contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    let holder = NSView(frame: NSRect(origin: .zero, size: view.frame.size))
    window.contentView = holder
    view.frame.origin = .zero
    holder.addSubview(view)
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// A cached view's pixels addressed in the view's points (origin bottom-left):
/// points map to pixels by the rep's `pixelsWide / bounds.width`.
struct Pixels {
    let rep: NSBitmapImageRep
    let bounds: NSRect
    var scale: CGFloat { CGFloat(rep.pixelsWide) / bounds.width }
    /// The brightest channel of pixel (`px`, `py`), `py` from the top, 0…1.
    func at(_ px: Int, _ py: Int) -> Double {
        guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh,
            let color = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB)
        else { return 0 }
        return Double(max(color.redComponent, color.greenComponent, color.blueComponent))
    }
    /// The pixel holding point (`x`, `y`).
    func pixel(_ x: CGFloat, _ y: CGFloat) -> (Int, Int) {
        (Int((x * scale).rounded(.down)), Int(((bounds.height - y) * scale).rounded(.down)))
    }
    func value(_ x: CGFloat, _ y: CGFloat) -> Double {
        let (px, py) = pixel(x, y)
        return at(px, py)
    }
    /// Whether any pixel within ±`slack` px of point (`x`, `y`) is brighter
    /// than `fill` by more than 0.05.
    func lit(_ x: CGFloat, _ y: CGFloat, above fill: Double, slack: Int = 1) -> Bool {
        let (px, py) = pixel(x, y)
        for dx in -slack...slack {
            for dy in -slack...slack where at(px + dx, py + dy) > fill + 0.05 {
                return true
            }
        }
        return false
    }
    /// The pixel rows (from the top) of `well` whose run across the well is
    /// dashed: lit between 30 and 70 % of it, with at least 8 lit-to-unlit
    /// changes. A solid line is lit across, an empty row nowhere.
    func dashedRows(_ well: NSRect, above fill: Double) -> [Int] {
        let first = Int(((bounds.height - well.maxY) * scale).rounded(.down))
        let last = Int(((bounds.height - well.minY) * scale).rounded(.up)) - 1
        let left = Int((well.minX * scale).rounded(.up)) + 1
        let right = Int((well.maxX * scale).rounded(.down)) - 2
        guard right > left else { return [] }
        return (max(first, 0)...max(first, last)).filter { py in
            var lit = 0
            var changes = 0
            var was = false
            for px in left...right {
                let now = at(px, py) > fill + 0.05
                if now { lit += 1 }
                if was && !now { changes += 1 }
                was = now
            }
            let share = Double(lit) / Double(right - left + 1)
            return share >= 0.3 && share <= 0.7 && changes >= 8
        }
    }
    /// The pixel rows (from the top) of a 1 pt line at `row` points.
    func rows(ofLineAt row: CGFloat) -> [Int] {
        let top = Int(((bounds.height - row - 1) * scale).rounded(.down))
        let bottom = Int(((bounds.height - row) * scale).rounded(.down))
        return Array(top..<max(top + 1, bottom))
    }
}

do {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    var misses: [String] = []
    var notes: [String] = []
    // ScopeSignal's table.
    let table: [(CanvasOutput, DynamicRange?, ScopeSignal)] = [
        (.sdr, nil, .sdr), (.sdr, .sdr, .sdr), (.sdr, .pq, .sdr), (.sdr, .hlg, .sdr),
        (.hlg, nil, .hlg), (.hlg, .hlg, .hlg), (.hlg, .pq, .hlg), (.hlg, .sdr, .sdr),
    ]
    for (output, range, want) in table {
        let got = ScopeSignal(output: output, dynamicRange: range)
        let canvas = ScopeSignal(canvas: RecipeCanvas(output: output, dynamicRange: range))
        if got != want || canvas != want {
            misses.append("(\(output), \(range?.rawValue ?? "nil")) → \(got), canvas \(canvas)")
        }
    }
    if ScopeSignal(canvas: nil) != .sdr { misses.append("canvas nil is not sdr") }
    if ScopeSignal.sdr.uniform != 0 || ScopeSignal.hlg.uniform != 1 {
        misses.append("uniforms \(ScopeSignal.sdr.uniform), \(ScopeSignal.hlg.uniform)")
    }
    if ScopeSignal.sdr.matrixName != "Rec. 709" || ScopeSignal.hlg.matrixName != "Rec. 2020" {
        misses.append("matrix names")
    }
    // The ticks, labels and captions.
    let sdrLabels = ScopeSignal.sdr.graticule.map { "\($0.percent):\($0.label ?? "-")" }
    let hlgLabels = ScopeSignal.hlg.graticule.map { "\($0.percent):\($0.label ?? "-")" }
    if sdrLabels != ["0:0", "25:-", "50:50", "75:-", "100:100"] {
        misses.append("SDR labels \(sdrLabels)")
    }
    if hlgLabels != ["0:0", "25:10", "50:51", "75:203", "100:1000"] {
        misses.append("HLG labels \(hlgLabels)")
    }
    if ScopeSignal.sdr.referenceWhitePercent != nil || ScopeSignal.hlg.referenceWhitePercent != 75 {
        misses.append("reference white \(String(describing: ScopeSignal.hlg.referenceWhitePercent))")
    }
    let wantTicks: [[Double]] = [[0, 0, 0], [25, 64, 9.6], [50, 128, 50.7], [75, 191, 203.2],
                                 [100, 255, 1000]]
    let scale = ScopeSignal.hlg.scaleJSON ?? [:]
    let ticks = (scale["ticks"] as? [[String: Any]] ?? []).map { tick -> [Double] in
        ["percent", "level", "nits"].map { (tick[$0] as? NSNumber)?.doubleValue ?? -1 }
    }
    if ticks != wantTicks || scale["unit"] as? String != "cd/m²"
        || scale["reference_white_percent"] as? Int != 75 || scale["clip_percent"] as? Int != 100
        || ScopeSignal.sdr.scaleJSON != nil
    {
        misses.append("scale \(scale)")
    }
    for kind in ScopeKind.allCases {
        let hlg = kind == .waveform || kind == .parade ? "HLG · cd/m²" : "Rec. 2100 HLG"
        if ScopeSignal.sdr.caption(for: kind) != "Rec. 709 · encoded"
            || ScopeSignal.hlg.caption(for: kind) != hlg
        {
            misses.append("caption \(kind)")
        }
    }
    // The targets.
    let sdrTargets = VectorscopeTrace.targets(for: .sdr)
    if sdrTargets.count != 6 || zip(sdrTargets, VectorscopeTrace.targets).contains(where: {
        $0.name != $1.name || $0.cb.bitPattern != $1.cb.bitPattern
            || $0.cr.bitPattern != $1.cr.bitPattern
    }) {
        misses.append("targets(for: .sdr) ≠ targets")
    }
    if VectorscopeTrace.skinLineDegrees(for: .sdr).bitPattern
        != VectorscopeTrace.skinLineDegrees.bitPattern
    {
        misses.append("skinLineDegrees(for: .sdr) ≠ skinLineDegrees")
    }
    let bars: [String: (Double, Double, Double)] = [
        "R": (0.75, 0, 0), "Mg": (0.75, 0, 0.75), "B": (0, 0, 0.75), "Cy": (0, 0.75, 0.75),
        "G": (0, 0.75, 0), "Yl": (0.75, 0.75, 0),
    ]
    for target in VectorscopeTrace.targets(for: .hlg) {
        guard let (r, g, b) = bars[target.name] else {
            misses.append("target \(target.name)")
            continue
        }
        let y = 0.2627 * r + 0.6780 * g + 0.0593 * b
        if abs(target.cb - (b - y) / 1.8814) > 1e-12 || abs(target.cr - (r - y) / 1.4746) > 1e-12 {
            misses.append("HLG target \(target.name) \(target.cb), \(target.cr)")
        }
    }
    // The JSON: no `signal` or `scale` in SDR; both in HLG.
    let zeros = [UInt32](repeating: 0, count: 65536)
    func traces(_ signal: ScopeSignal) -> [ScopeTrace] {
        [
            .waveform(WaveformTrace(counts: zeros, width: 1, height: 1, signal: signal)),
            .parade(ParadeTrace(
                counts: [UInt32](repeating: 0, count: 3 * 65536), width: 1, height: 1,
                signal: signal)),
            .vectorscope(VectorscopeTrace(counts: zeros, width: 1, height: 1, signal: signal)),
            .histogram(HistogramTrace(
                counts: [UInt32](repeating: 0, count: 1024), width: 1, height: 1, signal: signal)),
        ]
    }
    for trace in traces(.sdr) {
        let json = trace.json()
        if json["signal"] != nil || json["scale"] != nil { misses.append("SDR \(trace.kind) keys") }
    }
    for trace in traces(.hlg) {
        let json = trace.json()
        let scaled = trace.kind != .vectorscope
        if json["signal"] as? String != "hlg" || (json["scale"] != nil) != scaled
            || (trace.kind == .vectorscope && json["matrix"] as? String != "Rec. 2020")
        {
            misses.append("HLG \(trace.kind) keys \(json.keys.sorted())")
        }
    }
    // The waveform's and the parade's dashed reference-white row.
    func wellFill(_ pixels: Pixels, _ well: NSRect) -> Double {
        pixels.value(well.midX, well.minY + well.height * 0.125)
    }
    func dashCheck(_ name: String, _ pixels: Pixels, _ wells: [NSRect], _ signal: ScopeSignal) {
        for (index, well) in wells.enumerated() {
            let fill = wellFill(pixels, well)
            let dashed = pixels.dashedRows(well, above: fill)
            let y = well.minY + well.height * 0.75
            let want = Set(pixels.rows(ofLineAt: min(y, well.maxY - 1)))
            notes.append("\(name) \(signal) well \(index): dashed rows \(dashed), 75 % at \(want.sorted())")
            if signal == .hlg ? (dashed.isEmpty || !Set(dashed).isSubset(of: want)
                || !want.isSubset(of: Set(dashed))) : !dashed.isEmpty
            {
                misses.append("\(name) \(signal) well \(index): dashed rows \(dashed), want \(signal == .hlg ? want.sorted() : [])")
            }
        }
    }
    for signal in [ScopeSignal.hlg, .sdr] {
        let waveform = WaveformTraceView(frame: NSRect(x: 0, y: 0, width: 248, height: 200))
        waveform.trace = WaveformTrace(counts: zeros, width: 1, height: 1, signal: signal)
        if let rep = cached(waveform) {
            let pixels = Pixels(rep: rep, bounds: waveform.bounds)
            let well = NSRect(
                x: WaveformTraceView.gutter, y: 0, width: 248 - WaveformTraceView.gutter,
                height: 200)
            dashCheck("waveform", pixels, [well], signal)
        } else {
            misses.append("the waveform view did not cache")
        }
        let parade = ParadeView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        parade.trace = ParadeTrace(
            counts: [UInt32](repeating: 0, count: 3 * 65536), width: 1, height: 1, signal: signal)
        if let rep = cached(parade) {
            dashCheck("parade", Pixels(rep: rep, bounds: parade.bounds), parade.wells(), signal)
        } else {
            misses.append("the parade view did not cache")
        }
    }
    // The vectorscope's boxes and skin line, at ×1 and ×2.
    var parted = 0
    for zoom in [1, 2] {
        var bitmaps: [ScopeSignal: Pixels] = [:]
        var views: [ScopeSignal: VectorscopeView] = [:]
        for signal in [ScopeSignal.hlg, .sdr] {
            let view = VectorscopeView()
            view.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
            view.zoom = zoom
            view.trace = VectorscopeTrace(
                counts: zeros, width: 1, height: 1, zoom: zoom, signal: signal)
            guard let rep = cached(view) else {
                misses.append("the vectorscope view did not cache at ×\(zoom)")
                continue
            }
            bitmaps[signal] = Pixels(rep: rep, bounds: view.bounds)
            views[signal] = view
        }
        guard let hlgPixels = bitmaps[.hlg], let sdrPixels = bitmaps[.sdr],
            let hlgView = views[.hlg], let sdrView = views[.sdr]
        else { continue }
        let fill = hlgPixels.value(3, 3)
        func corners(_ at: NSPoint) -> [NSPoint] {
            let half = VectorscopeView.targetBox / 2
            return [(-1, -1), (-1, 1), (1, -1), (1, 1)].map {
                NSPoint(x: at.x + CGFloat($0.0) * half, y: at.y + CGFloat($0.1) * half)
            }
        }
        for (signal, pixels, view) in [(ScopeSignal.hlg, hlgPixels, hlgView),
                                       (.sdr, sdrPixels, sdrView)] {
            var boxes = 0
            for target in VectorscopeTrace.targets(for: signal) {
                guard let bins = VectorscopeTrace.targetBins(
                    cb: target.cb, cr: target.cr, zoom: zoom)
                else { continue }
                boxes += 1
                let at = view.point(cb: bins.cb, cr: bins.cr)
                let dark = corners(at).filter { !pixels.lit($0.x, $0.y, above: fill) }
                if !dark.isEmpty {
                    misses.append("×\(zoom) \(signal) \(target.name): corners unlit \(dark)")
                }
            }
            let angle = VectorscopeTrace.skinLineDegrees(for: signal) * .pi / 180
            let centre = view.point(cb: VectorscopeTrace.centre, cr: VectorscopeTrace.centre)
            let reach = 0.9 * view.bounds.width / 2
            let ray = NSPoint(
                x: centre.x + reach * CGFloat(cos(angle)), y: centre.y + reach * CGFloat(sin(angle)))
            if !pixels.lit(ray.x, ray.y, above: fill) {
                misses.append("×\(zoom) \(signal): the skin line is unlit at 0.9 of the reach")
            }
            notes.append("×\(zoom) \(signal): \(boxes) boxes on the plot")
        }
        guard zoom == 1 else { continue }
        let hlgTargets = VectorscopeTrace.targets(for: .hlg)
        let sdrTargets = VectorscopeTrace.targets(for: .sdr)
        for (h, s) in zip(hlgTargets, sdrTargets) {
            guard let hb = VectorscopeTrace.targetBins(cb: h.cb, cr: h.cr, zoom: 1),
                let sb = VectorscopeTrace.targetBins(cb: s.cb, cr: s.cr, zoom: 1)
            else { continue }
            let hp = hlgView.point(cb: hb.cb, cr: hb.cr)
            let sp = sdrView.point(cb: sb.cb, cr: sb.cr)
            guard hypot(hp.x - sp.x, hp.y - sp.y) >= 4 else { continue }
            parted += 1
            let boxed = corners(hp).filter { sdrPixels.lit($0.x, $0.y, above: fill, slack: 0) }
            if !boxed.isEmpty {
                misses.append("CONTROL \(h.name): the SDR bitmap has a lit corner of the HLG box \(boxed)")
            }
        }
        // The two skin rays.
        func ray(_ signal: ScopeSignal) -> NSPoint {
            let angle = VectorscopeTrace.skinLineDegrees(for: signal) * .pi / 180
            let centre = hlgView.point(cb: VectorscopeTrace.centre, cr: VectorscopeTrace.centre)
            let reach = 0.9 * hlgView.bounds.width / 2
            return NSPoint(
                x: centre.x + reach * CGFloat(cos(angle)), y: centre.y + reach * CGFloat(sin(angle)))
        }
        let (a, b) = (ray(.hlg), ray(.sdr))
        let apart = hypot(a.x - b.x, a.y - b.y) * hlgPixels.scale
        notes.append("the skin rays part by \(String(format: "%.1f", apart)) px at 0.9 of the reach")
        if apart >= 3, sdrPixels.lit(a.x, a.y, above: fill, slack: 0) {
            misses.append("CONTROL: the SDR bitmap is lit on the HLG skin ray")
        }
    }
    if parted < 4 {
        misses.append("CONTROL: only \(parted) targets' HLG and SDR boxes part by ≥ 4 pt at ×1")
    }
    check(
        "P8 ScopeSignal's table, ticks, labels and captions; targets(for: .sdr) bit-equal to "
            + "targets, targets(for: .hlg) BT.2020's; SDR JSON with no signal/scale, HLG with "
            + "both; the waveform's and each parade well's dashed row at 75 % in HLG only; the "
            + "vectorscope's boxes and skin line at ×1 and ×2 for its trace's signal (CONTROL: "
            + "\(parted) targets part HLG from SDR by ≥ 4 pt)",
        misses.isEmpty,
        (misses.isEmpty ? "as wanted" : misses.joined(separator: "; ")) + " | "
            + notes.joined(separator: "; "))
}

// MARK: - P9 linear light's values (hdr H-6, spec §11 HD-16)

do {
    var misses: [String] = []
    // (a) `blended` against IEC 61966-2-1's EOTF and BT.2100's HLG inverse OETF,
    // written out here in Double, per channel, clamped to 0…1.
    func iec(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    func hlgInverse(_ c: Double) -> Double {
        let a = 0.17883277, b = 1 - 4 * 0.17883277
        let cc = 0.5 - a * log(4 * a)
        let v = min(max(c, 0), 1)
        return v <= 0.5 ? v * v / 3 : (exp((v - cc) / a) + b) / 12
    }
    let inputs: [Double] = [-0.1, 0, 0.02, 0.04045, 0.05, 0.25, 0.5, 0.5059, 0.75, 1, 1.2]
    var worst = 0.0
    for output in CanvasOutput.allCases {
        let encoded = RecipeCanvas(output: output)
        let linear = RecipeCanvas(output: output, blending: .linear)
        for x in inputs {
            let rgb = SIMD3<Float>(Float(x), Float(x) * 0.5, 1 - Float(x))
            if encoded.blended(rgb) != rgb {
                misses.append("encoded \(output) blended(\(x)) is not the identity")
            }
            let got = linear.blended(rgb)
            for (g, c) in [(got.x, rgb.x), (got.y, rgb.y), (got.z, rgb.z)] {
                let want = output == .hlg ? hlgInverse(Double(c)) : iec(Double(c))
                worst = max(worst, abs(Double(g) - want))
                if abs(Double(g) - want) > 2e-6 {
                    misses.append("\(output) blended(\(c)) = \(g), want \(want)")
                }
            }
        }
    }
    // (b) `uniforms(for:)` over output × blending × range: (mode, linearLight,
    // hlgOutput), nil where no pass is drawn; an encoded canvas's answer is H-3's.
    let ranges: [DynamicRange?] = [nil, .hlg, .sdr, .pq]
    for output in CanvasOutput.allCases {
        for blending in CanvasBlending.allCases {
            for range in ranges {
                let canvas = RecipeCanvas(output: output, dynamicRange: range, blending: blending)
                let got = OutputTransform.uniforms(for: canvas)
                let hdrMode: Float? = output == .hlg ? (range == .sdr ? 1 : range == .pq ? 2 : nil) : nil
                let want: (Float, Float, Float)? = blending == .encoded
                    ? hdrMode.map { ($0, 0, 0) }
                    : (hdrMode ?? 0, 1, output == .hlg ? 1 : 0)
                let said = got.map { "(\($0.mode), \($0.linearLight), \($0.hlgOutput), knee \($0.knee))" }
                    ?? "nil"
                let match: Bool
                if let w = want, let g = got {
                    match = g.mode == w.0 && g.linearLight == w.1 && g.hlgOutput == w.2
                        && g.knee == OutputTransform.sdrKnee
                } else {
                    match = want == nil && got == nil
                }
                if !match {
                    misses.append("uniforms(\(output), \(blending), \(range?.rawValue ?? "nil")) = \(said)")
                }
            }
        }
    }
    // (c) the Blending popup's items (HD-16 (g)).
    let names = CanvasBlending.allCases.map(\.menuName)
    if names != ["Encoded", "Linear light"] { misses.append("the popup's items \(names)") }
    // (d) the four blocks' sizes: the renamed floats added nothing.
    let sizes = [
        ("LayerUniforms", MemoryLayout<LayerUniforms>.stride, 528),
        ("QualifierUniforms", MemoryLayout<QualifierUniforms>.stride, 80),
        ("MatteUniforms", MemoryLayout<MatteUniforms>.stride, 16),
        ("OutputUniforms", MemoryLayout<OutputUniforms>.stride, 16),
    ]
    for (name, got, want) in sizes where got != want {
        misses.append("\(name) is \(got) bytes, not \(want)")
    }
    check(
        "P9 RecipeCanvas.blended: the identity when encoded, IEC 61966-2-1's EOTF (SDR) and "
            + "HLG's inverse OETF (HLG) when linear, ±2e-6; uniforms(for:) over output × "
            + "blending × range (encoded H-3's, linear mode 0/1/2 with linearLight 1 and "
            + "hlgOutput the canvas's); the popup's items Encoded and Linear light; "
            + "LayerUniforms 528, QualifierUniforms 80, MatteUniforms "
            + "16 and OutputUniforms 16 bytes",
        misses.isEmpty,
        (misses.isEmpty ? "as wanted" : misses.prefix(12).joined(separator: "; "))
            + " | worst blended |Δ| \(worst)")
}

finish()
