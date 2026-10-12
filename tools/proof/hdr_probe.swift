// Built by tools/proof/hdr_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header, rows P1–P4
// (grading-3 T3-1, spec §11 GR-15 as amended).
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
        }
    }
    switch conversion {
    case nil: return "nil"
    case .hlg(let p): return "hlg(\(name(p)))"
    case .pq(let p): return "pq(\(name(p)))"
    case .sdrWide(let p): return "sdrWide(\(name(p)))"
    case .srgb(let p): return "srgb(\(name(p)))"
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
        "P4 InputConversions' constants are GR-15's (502/256 included) and InputUniforms is 96 "
            + "bytes",
        wrong.isEmpty && want.count == mine.count && stride == 96,
        "wrong \(wrong); stride \(stride)")
}

finish()
