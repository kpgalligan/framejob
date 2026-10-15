// tools/proof/grading_spike/tree_bench.swift — the GPU half of `grading_spike.py
// --tree` (road map "grading" GR7a): GR0's method on two libraries only, V0
// (main's shader at the branch point) and VT (the tree's own, unpatched), to
// price what the grading branch costs an UNGRADED layer. Compiled as
// `main.swift` over every other file in `app/Sources` through
// `swift_build.build(…, optimize=True)`, for the app's own `LayerUniforms`:
// both libraries are handed the WHOLE block (128 floats, 512 bytes since
// grading-2 G2-2's wheels group, asserted; an older base's shader reads a
// prefix of it). Pipelines as `bench.swift`'s
// `layerState`: `kGatherFilters` false, blending as `pipelineState`,
// `MetalRenderer.workingFormat`. `texture(0)` the picture, `texture(1)` a 1×1
// white placeholder, `texture(2)` an identity 2³ `rgba16Float` lattice,
// `texture(3)` an identity 2×1 `rgba32Float` curve strip (grading-2 G2-3's;
// an older base's shader names no `texture(3)` and ignores it).
// The adjustment pass's pipelines are `adjustPipeline`'s (the shadow vertex
// stage, `framejob_adjust_fragment`, blending OFF) with a NEUTRAL
// `QualifierUniforms` bound at fragment `buffer(1)` (grading-2 G2-4's; an
// older base's fragment names no `buffer(1)` and ignores it).
//
//   tree_bench --lib V0=PATH --lib VT=PATH --width W --height H --frames N
//              --runs R --warmup K --seed S --vt-exposure EV [--adjust 0|1]
//              --out JSON
//
// Two scenes: S1, one full-bleed picture layer, ungraded; and SA (grading-2
// G2-4), S1 then one full-frame adjustment pass at +1 EV, unqualified. Series
// V0:S1, VT:S1, V0b:S1, V0:SA, VT:SA and V0b:SA (V0b is V0 again, the noise
// control), each run in an order drawn from SplitMix64 seeded with seed +
// run; a series is K warm-up frames then N timed ones, one command buffer per
// frame, committed and waited on, timed as `gpuEndTime − gpuStartTime`. KT,
// VT:S1 against V0:S1, and KA, VT:SA against V0:SA, each within 1/1023 over
// the whole frame, are read back before any timing. `--vt-exposure` is 0 except
// under `grading_spike.py`'s mutant `tree-graded`, where VT's draws carry that
// exposure with `toneEnabled` 1. `--adjust` is 1 by default; `--adjust 0`
// (a base whose shader predates grading GR4a's adjustment pass and so names
// no `framejob_adjust_fragment`, issue #284) builds no adjustment pipeline,
// reads no KA and times only V0:S1, VT:S1 and V0b:S1. The JSON has
// `bench-<h>.json`'s shape; under `--adjust 0` its `k` holds only KT.
//
// Grading-4 T4-4 (spec §11 GR-35) adds four VT-only series to every plan, for
// the qualifier's cleanup blur: VT:SQ, S1 then the adjustment pass at +1 EV
// with hue {120, 40, 20} computed inline; and VT:SQ2, VT:SQ8 and VT:SQ24, S1,
// the encoder ended, `MetalRenderer.encodeSelectionMap` (the app's own map
// pass, with `MetalRenderer.qualifierMapPipeline` over VT's library) into an
// `r16Float` pair with an `MPSImageGaussianBlur` at σ 2, 8 or 24 destination
// pixels (`.clamp`), then the pass resumed with `.load` and the same
// adjustment pass reading the blurred map (`blurred` 1). `grading_spike.py`'s
// TB is each VT:SQσ − VT:SQ.
import Foundation
import Metal
import MetalPerformanceShaders

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tree_bench: \(message)\n".utf8))
    exit(2)
}

// ---- arguments -------------------------------------------------------------

var libs: [String: String] = [:]
var width = 1920, height = 1080, frames = 200, runs = 3, warmup = 5
var seed: UInt64 = 1
var vtExposure: Float = 0
var adjust = true
var outPath = ""
do {
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let flag = it.next() {
        guard let value = it.next() else { fail("\(flag) takes a value") }
        switch flag {
        case "--lib":
            let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { fail("--lib NAME=PATH") }
            libs[parts[0]] = parts[1]
        case "--width": width = Int(value) ?? 0
        case "--height": height = Int(value) ?? 0
        case "--frames": frames = Int(value) ?? 0
        case "--runs": runs = Int(value) ?? 0
        case "--warmup": warmup = Int(value) ?? 0
        case "--seed": seed = UInt64(value) ?? 0
        case "--vt-exposure": vtExposure = Float(value) ?? 0
        case "--adjust":
            guard value == "0" || value == "1" else { fail("--adjust 0|1") }
            adjust = value == "1"
        case "--out": outPath = value
        default: fail("unknown flag \(flag)")
        }
    }
}
guard frames > 0, runs > 0, !outPath.isEmpty, width > 0, height > 0,
    libs["V0"] != nil, libs["VT"] != nil
else { fail("usage: --lib V0=… --lib VT=… --width --height --frames --runs --out …") }

// ---- the block -------------------------------------------------------------

let blockBytes = 512
guard MemoryLayout<LayerUniforms>.stride == blockBytes,
    MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.hueCurvesEnabled) == blockBytes - 4
else {
    fail("LayerUniforms is \(MemoryLayout<LayerUniforms>.stride) bytes, not \(blockBytes) "
        + "(128 floats ending at hueCurvesEnabled)")
}

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
else { fail("no Metal device") }
let workingFormat = MetalRenderer.workingFormat
guard workingFormat == .rgba16Float else { fail("the working format is not rgba16Float") }

// ---- pipelines, as bench.swift's `layerState` --------------------------------

var libraries: [String: MTLLibrary] = [:]
for (name, path) in libs {
    do { libraries[name] = try device.makeLibrary(URL: URL(fileURLWithPath: path)) } catch {
        fail("\(name): the metallib would not load: \(error)")
    }
}

func function(_ lib: String, _ name: String) -> MTLFunction {
    let values = MTLFunctionConstantValues()
    var gather = false  // kGatherFilters: no layer here gathers
    values.setConstantValue(&gather, type: .bool, index: 0)
    do {
        return try libraries[lib]!.makeFunction(name: name, constantValues: values)
    } catch { fail("\(lib): \(name): \(error)") }
}

func layerState(_ lib: String) -> MTLRenderPipelineState {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = function(lib, "framejob_layer_vertex")
    d.fragmentFunction = function(lib, "framejob_layer_fragment")
    d.colorAttachments[0].pixelFormat = workingFormat
    d.colorAttachments[0].isBlendingEnabled = true
    d.colorAttachments[0].rgbBlendOperation = .add
    d.colorAttachments[0].alphaBlendOperation = .add
    d.colorAttachments[0].sourceRGBBlendFactor = .one
    d.colorAttachments[0].sourceAlphaBlendFactor = .one
    d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    do { return try device.makeRenderPipelineState(descriptor: d) } catch {
        fail("\(lib): pipeline: \(error)")
    }
}

let states = ["V0": layerState("V0"), "VT": layerState("VT")]

/// `MetalRenderer.adjustPipeline`'s: the shadow vertex stage and the adjust
/// fragment, blending OFF.
func adjustState(_ lib: String) -> MTLRenderPipelineState {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = function(lib, "framejob_shadow_vertex")
    d.fragmentFunction = function(lib, "framejob_adjust_fragment")
    d.colorAttachments[0].pixelFormat = workingFormat
    d.colorAttachments[0].isBlendingEnabled = false
    do { return try device.makeRenderPipelineState(descriptor: d) } catch {
        fail("\(lib): adjustment pipeline: \(error)")
    }
}

let adjustStates: [String: MTLRenderPipelineState] =
    adjust ? ["V0": adjustState("V0"), "VT": adjustState("VT")] : [:]
/// VT's adjustment state for the SQ series, which run in every plan: VT is the
/// tree's own shader, so it always has the pass.
let qualifiedState = adjustStates["VT"] ?? adjustState("VT")
/// The app's own map pipeline over VT's library (T4-4).
guard let mapState = MetalRenderer.qualifierMapPipeline(device: device, library: libraries["VT"]!)
else { fail("VT: the selection map pipeline would not build") }

let samplerDescriptor = MTLSamplerDescriptor()
samplerDescriptor.minFilter = .linear
samplerDescriptor.magFilter = .linear
samplerDescriptor.sAddressMode = .clampToEdge
samplerDescriptor.tAddressMode = .clampToEdge
guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
    fail("no sampler")
}

// ---- textures (a copy of bench.swift's `halfPicture`) -----------------------

typealias RGB = (Float, Float, Float)

func texture2D(_ format: MTLPixelFormat, _ w: Int, _ h: Int, target: Bool) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: w, height: h, mipmapped: false)
    d.usage = target ? [.shaderRead, .renderTarget] : [.shaderRead]
    d.storageMode = target ? .private : .shared
    guard let t = device.makeTexture(descriptor: d) else { fail("texture \(w)×\(h)") }
    return t
}

func halfBits(_ v: Float) -> UInt16 { Float16(v).bitPattern }

/// An `rgba16Float` picture, straight and opaque (PR-2's stand-in source).
func halfPicture(_ w: Int, _ h: Int, _ colour: (Int, Int) -> RGB) -> MTLTexture {
    var data = [UInt16](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            let c = colour(x, y)
            let i = (y * w + x) * 4
            data[i] = halfBits(c.0)
            data[i + 1] = halfBits(c.1)
            data[i + 2] = halfBits(c.2)
            data[i + 3] = halfBits(1)
        }
    }
    let t = texture2D(.rgba16Float, w, h, target: false)
    data.withUnsafeBytes {
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                  withBytes: $0.baseAddress!, bytesPerRow: w * 8)
    }
    return t
}

let W = width, H = height
// The S1 picture: red runs with x, green with y, blue a fine checker (bench.swift's).
let picture = halfPicture(W, H) { x, y in
    (0.1 + 0.8 * Float(x) / Float(max(W - 1, 1)), 0.1 + 0.8 * Float(y) / Float(max(H - 1, 1)),
     ((x / 8 + y / 8) % 2 == 0) ? 0.3 : 0.7)
}
let placeholder: MTLTexture = {
    let t = texture2D(.bgra8Unorm, 1, 1, target: false)
    var white: UInt32 = 0xFFFF_FFFF
    t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white,
              bytesPerRow: 4)
    return t
}()
/// The identity 2³ `rgba16Float` lattice, red fastest.
let identity2: MTLTexture = {
    let d = MTLTextureDescriptor()
    d.textureType = .type3D
    d.pixelFormat = .rgba16Float
    d.width = 2
    d.height = 2
    d.depth = 2
    d.usage = [.shaderRead]
    d.storageMode = .shared
    guard let t = device.makeTexture(descriptor: d) else { fail("3D texture") }
    var data = [UInt16](repeating: 0, count: 8 * 4)
    for b in 0..<2 {
        for g in 0..<2 {
            for r in 0..<2 {
                let i = ((b * 2 + g) * 2 + r) * 4
                data[i] = halfBits(Float(r))
                data[i + 1] = halfBits(Float(g))
                data[i + 2] = halfBits(Float(b))
                data[i + 3] = halfBits(1)
            }
        }
    }
    data.withUnsafeBytes {
        t.replace(region: MTLRegionMake3D(0, 0, 0, 2, 2, 2), mipmapLevel: 0, slice: 0,
                  withBytes: $0.baseAddress!, bytesPerRow: 16, bytesPerImage: 32)
    }
    return t
}()
/// The identity 2×1 `rgba32Float` curve strip, `CurveTextures`' placeholder.
let identityStrip: MTLTexture = {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba32Float, width: 2, height: 1, mipmapped: false)
    d.usage = [.shaderRead]
    d.storageMode = .shared
    guard let t = device.makeTexture(descriptor: d) else { fail("strip texture") }
    var data: [Float] = [0, 0, 0, 1, 1, 1, 1, 1]
    t.replace(region: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0, withBytes: &data,
              bytesPerRow: 32)
    return t
}()
let destination = texture2D(workingFormat, W, H, target: true)
let background = MTLClearColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
/// The SQσ series' pair, as `Compositor+Selection.swift` allocates it.
let selectionSurfaces: MetalRenderer.QualifierSurfaces = {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r16Float, width: W, height: H, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead, .shaderWrite]
    d.storageMode = .private
    guard let map = device.makeTexture(descriptor: d), let blurred = device.makeTexture(descriptor: d)
    else { fail("the selection pair") }
    return MetalRenderer.QualifierSurfaces(map: map, blurred: blurred)
}()
/// One kernel per SQσ series, `.clamp` as `blurKernel(sigma:)` makes it.
let selectionBlurs: [Int: MPSImageGaussianBlur] = Dictionary(
    uniqueKeysWithValues: [2, 8, 24].map { sigma in
        let kernel = MPSImageGaussianBlur(device: device, sigma: Float(sigma))
        kernel.edgeMode = .clamp
        return (sigma, kernel)
    })

// ---- encoding --------------------------------------------------------------

func fullBleed(graded: Bool) -> LayerUniforms {
    var u = LayerUniforms()
    u.canvasWidth = Float(W)
    u.canvasHeight = Float(H)
    u.anchorX = Float(W) / 2
    u.anchorY = Float(H) / 2
    u.sourceWidth = Float(W)
    u.sourceHeight = Float(H)
    u.scale = 1
    u.opacity = 1
    u.premultiplied = 0
    u.canvasPerDestX = 1
    u.canvasPerDestY = 1
    if graded && vtExposure != 0 {
        u.exposure = vtExposure
        u.toneEnabled = 1
    }
    return u
}

/// SA's adjustment block: the canvas, full strength, +1 EV (`toneEnabled` 1).
func adjustBlock() -> LayerUniforms {
    var u = LayerUniforms()
    u.canvasWidth = Float(W)
    u.canvasHeight = Float(H)
    u.canvasPerDestX = 1
    u.canvasPerDestY = 1
    u.opacity = 1
    u.exposure = 1
    u.toneEnabled = 1
    return u
}

/// One frame of `series` ("V0:S1", "VT:SA", "VT:SQ8", …).
func encode(_ series: String, _ buffer: MTLCommandBuffer) {
    let parts = series.split(separator: ":").map(String.init)
    let lib = parts[0] == "VT" ? "VT" : "V0"
    let scene = parts.count > 1 ? parts[1] : "S1"
    let adjusted = scene == "SA"
    var block = fullBleed(graded: lib == "VT")
    let d = MTLRenderPassDescriptor()
    d.colorAttachments[0].texture = destination
    d.colorAttachments[0].loadAction = .clear
    d.colorAttachments[0].clearColor = background
    d.colorAttachments[0].storeAction = .store
    guard let e = buffer.makeRenderCommandEncoder(descriptor: d) else { fail("encoder") }
    e.setRenderPipelineState(states[lib]!)
    withUnsafeBytes(of: &block) { bytes in
        e.setVertexBytes(bytes.baseAddress!, length: blockBytes, index: 0)
        e.setFragmentBytes(bytes.baseAddress!, length: blockBytes, index: 0)
    }
    e.setFragmentTexture(picture, index: 0)
    e.setFragmentTexture(placeholder, index: 1)
    e.setFragmentTexture(identity2, index: 2)
    e.setFragmentTexture(identityStrip, index: 3)
    e.setFragmentSamplerState(sampler, index: 0)
    e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    if adjusted {
        var adjust = adjustBlock()
        var qualifier = QualifierUniforms(.none, selection: false)
        e.setRenderPipelineState(adjustStates[lib]!)
        withUnsafeBytes(of: &adjust) { bytes in
            e.setFragmentBytes(bytes.baseAddress!, length: blockBytes, index: 0)
        }
        e.setFragmentBytes(&qualifier, length: MemoryLayout<QualifierUniforms>.stride, index: 1)
        e.setFragmentTexture(placeholder, index: 1)
        e.setFragmentTexture(identity2, index: 2)
        e.setFragmentTexture(identityStrip, index: 3)
        e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    guard scene.hasPrefix("SQ") else {
        e.endEncoding()
        return
    }
    // T4-4: the qualified adjustment pass, inline (SQ) or through the blurred
    // map (SQσ), the pass broken and resumed as `drawAdjustment` does.
    var q = QualifierUniforms(
        ColorQualifier(hue: QualifierHue(center: 120, width: 40, softness: 20)), selection: false)
    var adjust = adjustBlock()
    var pass = e
    var map: MTLTexture = placeholder
    if let sigma = Int(scene.dropFirst(2)) {
        guard let blur = selectionBlurs[sigma] else { fail("no kernel for σ \(sigma)") }
        e.endEncoding()
        map = MetalRenderer.encodeSelectionMap(
            q, from: destination, into: selectionSurfaces, pipeline: mapState, blur: blur,
            buffer: buffer)
        q.blurred = 1
        let resume = MTLRenderPassDescriptor()
        resume.colorAttachments[0].texture = destination
        resume.colorAttachments[0].loadAction = .load
        resume.colorAttachments[0].storeAction = .store
        guard let reopened = buffer.makeRenderCommandEncoder(descriptor: resume) else {
            fail("encoder")
        }
        reopened.setFragmentSamplerState(sampler, index: 0)
        pass = reopened
    }
    pass.setRenderPipelineState(qualifiedState)
    withUnsafeBytes(of: &adjust) { bytes in
        pass.setFragmentBytes(bytes.baseAddress!, length: blockBytes, index: 0)
    }
    pass.setFragmentBytes(&q, length: MemoryLayout<QualifierUniforms>.stride, index: 1)
    pass.setFragmentTexture(map, index: 0)
    pass.setFragmentTexture(placeholder, index: 1)
    pass.setFragmentTexture(identity2, index: 2)
    pass.setFragmentTexture(identityStrip, index: 3)
    pass.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    pass.endEncoding()
}

// ---- KT: the readback, before any timing -------------------------------------

func readHalves(_ series: String) -> [UInt16] {
    guard let out = device.makeBuffer(length: W * H * 8, options: .storageModeShared),
        let buffer = queue.makeCommandBuffer()
    else { fail("readback buffer") }
    encode(series, buffer)
    guard let blit = buffer.makeBlitCommandEncoder() else { fail("blit") }
    blit.copy(from: destination, sourceSlice: 0, sourceLevel: 0,
              sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
              sourceSize: MTLSize(width: W, height: H, depth: 1), to: out,
              destinationOffset: 0, destinationBytesPerRow: W * 8,
              destinationBytesPerImage: W * H * 8)
    blit.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    if let error = buffer.error { fail("readback: \(error)") }
    let p = out.contents().bindMemory(to: UInt16.self, capacity: W * H * 4)
    return Array(UnsafeBufferPointer(start: p, count: W * H * 4))
}

func r4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }

var kRows: [[String: Any]] = []
for (row, scene) in [("KT", "S1"), ("KA", "SA")] where adjust || scene == "S1" {
    let reference = readHalves("V0:\(scene)")
    let got = readHalves("VT:\(scene)")
    var worst: Float = 0
    var at = 0
    for i in 0..<got.count {
        let d = abs(Float(Float16(bitPattern: got[i])) - Float(Float16(bitPattern: reference[i])))
        if d > worst { worst = d; at = i }
    }
    let ok = worst <= 1.0 / 1023
    kRows.append([
        "row": row, "variant": "VT", "ok": ok,
        "detail": "VT:\(scene) against V0:\(scene) max |Δ| \(r4(Double(worst))) "
            + "(\(r4(Double(worst) * 1023)) / 1023) at pixel \(at / 4) channel \(at % 4); "
            + "bound 1/1023; VT exposure \(vtExposure)",
    ])
}

// ---- timing ----------------------------------------------------------------

let selectionPlan = ["VT:SQ", "VT:SQ2", "VT:SQ8", "VT:SQ24"]
let plan = (adjust
    ? ["V0:S1", "VT:S1", "V0b:S1", "V0:SA", "VT:SA", "V0b:SA"]
    : ["V0:S1", "VT:S1", "V0b:S1"]) + selectionPlan

func frameMilliseconds(_ name: String) -> Double {
    guard let buffer = queue.makeCommandBuffer() else { fail("command buffer") }
    encode(name, buffer)
    buffer.commit()
    buffer.waitUntilCompleted()
    if let error = buffer.error { fail("\(name): \(error)") }
    return (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
}

/// SplitMix64: the order of a run is a permutation drawn from seed + run.
struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

var samples: [String: [[String: Double]]] = [:]
var orders: [[String]] = []
// A failed KT makes every figure meaningless (the driver scores it a FAIL and
// reads no time), so the GPU time is not spent.
if kRows.contains(where: { ($0["ok"] as? Bool) != true }) { runs = 0 }
for run in 0..<runs {
    var rng = SplitMix(state: seed &+ UInt64(run))
    var order = Array(plan.indices)
    for i in stride(from: order.count - 1, to: 0, by: -1) {
        let j = Int(rng.next() % UInt64(i + 1))
        order.swapAt(i, j)
    }
    orders.append(order.map { plan[$0] })
    for index in order {
        let name = plan[index]
        for _ in 0..<warmup { _ = frameMilliseconds(name) }
        let times = (0..<frames).map { _ in frameMilliseconds(name) }
        samples[name, default: []].append(
            ["median": median(times), "min": times.min()!, "max": times.max()!])
    }
}

do {
    let object: [String: Any] = [
        "width": W, "height": H, "frames": frames, "runs": runs, "warmup": warmup,
        "seed": seed, "gpu": device.name, "uniform_bytes": blockBytes,
        "layer_uniform_bytes": MemoryLayout<LayerUniforms>.stride, "vt_exposure": vtExposure,
        "k": kRows, "samples": samples, "orders": orders,
    ]
    let data = try JSONSerialization.data(withJSONObject: object,
                                          options: [.sortedKeys, .prettyPrinted])
    try data.write(to: URL(fileURLWithPath: outPath))
} catch { fail("could not write \(outPath): \(error)") }
print("tree_bench: wrote \(outPath)")
