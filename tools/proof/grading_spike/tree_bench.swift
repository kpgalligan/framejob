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
//
//   tree_bench --lib V0=PATH --lib VT=PATH --width W --height H --frames N
//              --runs R --warmup K --seed S --vt-exposure EV --out JSON
//
// One scene, S1: one full-bleed picture layer, ungraded. Series V0:S1, VT:S1
// and V0b:S1 (V0 again, the noise control), each run in an order drawn from
// SplitMix64 seeded with seed + run; a series is K warm-up frames then N timed
// ones, one command buffer per frame, committed and waited on, timed as
// `gpuEndTime − gpuStartTime`. KT, VT:S1 against V0:S1 within 1/1023 over the
// whole frame, is read back before any timing. `--vt-exposure` is 0 except
// under `grading_spike.py`'s mutant `tree-graded`, where VT's draws carry that
// exposure with `toneEnabled` 1. The JSON has `bench-<h>.json`'s shape.
import Foundation
import Metal

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tree_bench: \(message)\n".utf8))
    exit(2)
}

// ---- arguments -------------------------------------------------------------

var libs: [String: String] = [:]
var width = 1920, height = 1080, frames = 200, runs = 3, warmup = 5
var seed: UInt64 = 1
var vtExposure: Float = 0
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
    MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.gradeReserved0) == blockBytes - 4
else {
    fail("LayerUniforms is \(MemoryLayout<LayerUniforms>.stride) bytes, not \(blockBytes) "
        + "(128 floats ending at gradeReserved0)")
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
    d.vertexFunction = function(lib, "reelcut_layer_vertex")
    d.fragmentFunction = function(lib, "reelcut_layer_fragment")
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

func encode(_ series: String, _ buffer: MTLCommandBuffer) {
    let lib = series == "VT" ? "VT" : "V0"
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
    e.endEncoding()
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
do {
    let reference = readHalves("V0")
    let got = readHalves("VT")
    var worst: Float = 0
    var at = 0
    for i in 0..<got.count {
        let d = abs(Float(Float16(bitPattern: got[i])) - Float(Float16(bitPattern: reference[i])))
        if d > worst { worst = d; at = i }
    }
    let ok = worst <= 1.0 / 1023
    kRows.append([
        "row": "KT", "variant": "VT", "ok": ok,
        "detail": "VT:S1 against V0:S1 max |Δ| \(r4(Double(worst))) "
            + "(\(r4(Double(worst) * 1023)) / 1023) at pixel \(at / 4) channel \(at % 4); "
            + "bound 1/1023; VT exposure \(vtExposure)",
    ])
}

// ---- timing ----------------------------------------------------------------

let plan = ["V0:S1", "VT:S1", "V0b:S1"]

func frameMilliseconds(_ name: String) -> Double {
    guard let buffer = queue.makeCommandBuffer() else { fail("command buffer") }
    encode(String(name.split(separator: ":")[0]), buffer)
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
