// tools/proof/matte_spike/bench.swift — the GPU half of road map "mattes" MT0's
// spike (`matte_spike.py`). Compiled as `main.swift` over every other file in
// `app/Sources` through `swift_build.build(…, optimize=True)`, for ONE reason:
// it fills the app's own `LayerUniforms` (416 bytes, asserted below), so the
// block it hands the shader is the block the compositor hands it. It draws
// with pipelines of its own, built the way `MetalRenderer.init` builds them,
// from three metallibs `matte_spike.py` compiles:
//
//   V0  the tree's `Compositor.metal`
//   V1  + the placeholder route: every layer samples `texture(1)` (a 1×1
//         white texture for an unmatted layer)
//   V2  + the function-constant route: `kMatte [[function_constant(1)]]`,
//         false for an unmatted layer, true for a matted one
//
// Scenes (canvas = destination, full bleed, no effects):
//   S1  one picture layer
//   S2  the picture, then a white-text layer drawn normally
//   S3  S2 with the text as an alpha matte: the text drawn into a bgra8 matte
//       target, resolved into an r8 coverage cleared to 1, the picture drawn
//       cut by it (the text itself is not drawn on the canvas)
//   S4  S3 plus a static full-frame gradient as a luma matte, resolved into
//       the same coverage (two mattes, one coverage)
//
//     bench --lib V0=PATH --lib V1=PATH --lib V2=PATH --width W --height H
//           --frames N --runs R --warmup K --out JSON
//
// One command buffer per frame, committed and waited on; a frame's time is
// `gpuEndTime − gpuStartTime`. Within a run every (scene, variant) sample is
// taken in turn — V0, V1, V2, then V0 again for the C0 control at S1 — so the
// GPU's clock drift lands on every series alike. The JSON holds each sample's
// median, minimum and maximum (ms), and the K3/K4 readbacks.
import CoreGraphics
import CoreText
import Foundation
import Metal

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("bench: \(message)\n".utf8))
    exit(2)
}

// ---- arguments -------------------------------------------------------------

var libs: [String: String] = [:]
var width = 1920, height = 1080, frames = 200, runs = 3, warmup = 5
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
        case "--out": outPath = value
        default: fail("unknown flag \(flag)")
        }
    }
}
guard width > 0, height > 0, frames > 0, runs > 0, !outPath.isEmpty,
    libs["V0"] != nil, libs["V1"] != nil, libs["V2"] != nil
else { fail("usage: --lib V0=… --lib V1=… --lib V2=… --width --height --frames --runs --out") }
guard MemoryLayout<LayerUniforms>.stride == 416 else {
    fail("LayerUniforms is \(MemoryLayout<LayerUniforms>.stride) bytes, not 416")
}

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
else { fail("no Metal device") }

// ---- pipelines, as `MetalRenderer.init` builds them --------------------------

func layerDescriptor(_ vertex: MTLFunction, _ fragment: MTLFunction) -> MTLRenderPipelineDescriptor {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = vertex
    d.fragmentFunction = fragment
    d.colorAttachments[0].pixelFormat = .bgra8Unorm
    d.colorAttachments[0].isBlendingEnabled = true
    d.colorAttachments[0].rgbBlendOperation = .add
    d.colorAttachments[0].alphaBlendOperation = .add
    d.colorAttachments[0].sourceRGBBlendFactor = .one
    d.colorAttachments[0].sourceAlphaBlendFactor = .one
    d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return d
}

struct Pipes {
    let unmatted: MTLRenderPipelineState
    let matted: MTLRenderPipelineState?
    let resolve: MTLRenderPipelineState?
}

func pipes(_ name: String) -> Pipes {
    let library: MTLLibrary
    do { library = try device.makeLibrary(URL: URL(fileURLWithPath: libs[name]!)) } catch {
        fail("\(name): the metallib would not load: \(error)")
    }
    func fragment(matte: Bool?) -> MTLFunction {
        let values = MTLFunctionConstantValues()
        var gather = false
        values.setConstantValue(&gather, type: .bool, index: 0)
        if var flag = matte { values.setConstantValue(&flag, type: .bool, index: 1) }
        do {
            return try library.makeFunction(name: "reelcut_layer_fragment", constantValues: values)
        } catch { fail("\(name): reelcut_layer_fragment: \(error)") }
    }
    guard let vertex = library.makeFunction(name: "reelcut_layer_vertex") else {
        fail("\(name): no reelcut_layer_vertex")
    }
    func state(_ d: MTLRenderPipelineDescriptor) -> MTLRenderPipelineState {
        do { return try device.makeRenderPipelineState(descriptor: d) } catch {
            fail("\(name): pipeline: \(error)")
        }
    }
    let constantRoute = name == "V2"
    let unmatted = state(layerDescriptor(vertex, fragment(matte: constantRoute ? false : nil)))
    guard name != "V0" else { return Pipes(unmatted: unmatted, matted: nil, resolve: nil) }
    let matted = constantRoute ? state(layerDescriptor(vertex, fragment(matte: true))) : unmatted
    guard let shadowVertex = library.makeFunction(name: "reelcut_shadow_vertex"),
        let resolveFragment = library.makeFunction(name: "reelcut_matte_resolve_fragment")
    else { fail("\(name): no reelcut_matte_resolve_fragment") }
    // The coverage pass: r8, dst = dst × src (source factor zero, destination
    // factor sourceColor), so each matte's value multiplies in.
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = shadowVertex
    d.fragmentFunction = resolveFragment
    d.colorAttachments[0].pixelFormat = .r8Unorm
    d.colorAttachments[0].isBlendingEnabled = true
    d.colorAttachments[0].rgbBlendOperation = .add
    d.colorAttachments[0].alphaBlendOperation = .add
    d.colorAttachments[0].sourceRGBBlendFactor = .zero
    d.colorAttachments[0].sourceAlphaBlendFactor = .zero
    d.colorAttachments[0].destinationRGBBlendFactor = .sourceColor
    d.colorAttachments[0].destinationAlphaBlendFactor = .sourceColor
    return Pipes(unmatted: unmatted, matted: matted, resolve: state(d))
}

let variants = ["V0", "V1", "V2"]
var pipesByName: [String: Pipes] = [:]
for name in variants { pipesByName[name] = pipes(name) }

let samplerDescriptor = MTLSamplerDescriptor()
samplerDescriptor.minFilter = .linear
samplerDescriptor.magFilter = .linear
samplerDescriptor.sAddressMode = .clampToEdge
samplerDescriptor.tAddressMode = .clampToEdge
guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
    fail("no sampler")
}

// ---- textures --------------------------------------------------------------

func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, target: Bool) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: format, width: w, height: h, mipmapped: false)
    d.usage = target ? [.shaderRead, .renderTarget] : [.shaderRead]
    d.storageMode = target ? .private : .shared
    guard let t = device.makeTexture(descriptor: d) else { fail("texture \(w)×\(h)") }
    return t
}

func upload(_ bytes: [UInt8], _ w: Int, _ h: Int) -> MTLTexture {
    let t = texture(.bgra8Unorm, w, h, target: false)
    bytes.withUnsafeBytes {
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                  withBytes: $0.baseAddress!, bytesPerRow: w * 4)
    }
    return t
}

let W = width, H = height
// The picture: straight, opaque BGRA; red runs with x, green with y, blue 0.
var pictureBytes = [UInt8](repeating: 255, count: W * H * 4)
for y in 0..<H {
    for x in 0..<W {
        let i = (y * W + x) * 4
        pictureBytes[i] = 0
        pictureBytes[i + 1] = UInt8(40 + (y * 200) / max(H - 1, 1))
        pictureBytes[i + 2] = UInt8(40 + (x * 200) / max(W - 1, 1))
    }
}
// The text: premultiplied BGRA (CoreGraphics' premultipliedFirst, little
// endian), white glyphs on transparent, rows of words across the whole frame.
var textBytes = [UInt8](repeating: 0, count: W * H * 4)
textBytes.withUnsafeMutableBytes { raw in
    guard let context = CGContext(
        data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
    else { fail("no text context") }
    let size = CGFloat(H) / 7
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):
            CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "REELCUT MATTE REELCUT MATTE", attributes: attributes))
    var baseline = CGFloat(H) - size
    while baseline > -size {
        context.textPosition = CGPoint(x: -size * 0.3, y: baseline)
        CTLineDraw(line, context)
        baseline -= size * 1.15
    }
}
// The gradient: opaque grey, black left of a quarter, white right of a half.
var gradientBytes = [UInt8](repeating: 255, count: W * H * 4)
func gradientLevel(_ x: Int) -> UInt8 {
    let a = W / 4, b = W / 2
    if x < a { return 0 }
    if x >= b { return 255 }
    return UInt8((255 * (x - a)) / (b - a))
}
for y in 0..<H {
    for x in 0..<W {
        let i = (y * W + x) * 4
        let g = gradientLevel(x)
        gradientBytes[i] = g
        gradientBytes[i + 1] = g
        gradientBytes[i + 2] = g
    }
}

let picture = upload(pictureBytes, W, H)
let text = upload(textBytes, W, H)
let gradient = upload(gradientBytes, W, H)
let placeholder = upload([255, 255, 255, 255], 1, 1)
let destination = texture(.bgra8Unorm, W, H, target: true)
let matteA = texture(.bgra8Unorm, W, H, target: true)
let matteB = texture(.bgra8Unorm, W, H, target: true)
let coverage = texture(.r8Unorm, W, H, target: true)
guard let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared) else {
    fail("no readback buffer")
}

// ---- encoding --------------------------------------------------------------

func uniforms(premultiplied: Bool) -> LayerUniforms {
    var u = LayerUniforms()
    u.canvasWidth = Float(W)
    u.canvasHeight = Float(H)
    u.anchorX = Float(W) / 2
    u.anchorY = Float(H) / 2
    u.sourceWidth = Float(W)
    u.sourceHeight = Float(H)
    u.scale = 1
    u.opacity = 1
    u.premultiplied = premultiplied ? 1 : 0
    u.canvasPerDestX = 1
    u.canvasPerDestY = 1
    return u
}
let pictureUniforms = uniforms(premultiplied: false)
let overlayUniforms = uniforms(premultiplied: true)
// Background 0.2/0.4/0.6, which store exactly as 51/102/153.
let background = MTLClearColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)

func pass(_ buffer: MTLCommandBuffer, _ target: MTLTexture, clear: MTLClearColor,
          _ body: (MTLRenderCommandEncoder) -> Void) {
    let d = MTLRenderPassDescriptor()
    d.colorAttachments[0].texture = target
    d.colorAttachments[0].loadAction = .clear
    d.colorAttachments[0].clearColor = clear
    d.colorAttachments[0].storeAction = .store
    guard let encoder = buffer.makeRenderCommandEncoder(descriptor: d) else { fail("encoder") }
    body(encoder)
    encoder.endEncoding()
}

func draw(_ e: MTLRenderCommandEncoder, _ state: MTLRenderPipelineState, _ source: MTLTexture,
          _ u: LayerUniforms, matte: MTLTexture?) {
    var block = u
    e.setRenderPipelineState(state)
    e.setVertexBytes(&block, length: MemoryLayout<LayerUniforms>.stride, index: 0)
    e.setFragmentBytes(&block, length: MemoryLayout<LayerUniforms>.stride, index: 0)
    e.setFragmentTexture(source, index: 0)
    if let matte { e.setFragmentTexture(matte, index: 1) }
    e.setFragmentSamplerState(sampler, index: 0)
    e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
}

func resolve(_ e: MTLRenderCommandEncoder, _ state: MTLRenderPipelineState, _ mask: MTLTexture,
             mode: Float) {
    var block: [Float] = [mode, 0, 0, 0]  // MatteUniforms: mode, three reserved
    e.setRenderPipelineState(state)
    e.setFragmentBytes(&block, length: 16, index: 0)
    e.setFragmentTexture(mask, index: 0)
    e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
}

let clearTransparent = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
let clearOne = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
let kMatteAlpha: Float = 1
let kMatteLuma: Float = 3

/// One frame of `scene` with `variant`'s pipelines, in its own command buffer.
func encode(_ variant: String, _ scene: String) -> MTLCommandBuffer {
    let p = pipesByName[variant]!
    guard let buffer = queue.makeCommandBuffer() else { fail("command buffer") }
    // V0's shader has no texture(1); the routes bind the placeholder there for
    // every unmatted draw (V2's kMatte = false specialization never reads it).
    let slot: MTLTexture? = variant == "V0" ? nil : placeholder
    switch scene {
    case "S1":
        pass(buffer, destination, clear: background) { e in
            draw(e, p.unmatted, picture, pictureUniforms, matte: slot)
        }
    case "S2":
        pass(buffer, destination, clear: background) { e in
            draw(e, p.unmatted, picture, pictureUniforms, matte: slot)
            draw(e, p.unmatted, text, overlayUniforms, matte: slot)
        }
    case "S3", "S4":
        guard let matted = p.matted, let resolveState = p.resolve else {
            fail("\(variant) has no matte pipelines")
        }
        pass(buffer, matteA, clear: clearTransparent) { e in
            draw(e, p.unmatted, text, overlayUniforms, matte: slot)
        }
        if scene == "S4" {
            pass(buffer, matteB, clear: clearTransparent) { e in
                draw(e, p.unmatted, gradient, overlayUniforms, matte: slot)
            }
        }
        pass(buffer, coverage, clear: clearOne) { e in
            resolve(e, resolveState, matteA, mode: kMatteAlpha)
            if scene == "S4" { resolve(e, resolveState, matteB, mode: kMatteLuma) }
        }
        pass(buffer, destination, clear: background) { e in
            draw(e, matted, picture, pictureUniforms, matte: coverage)
        }
    default:
        fail("unknown scene \(scene)")
    }
    return buffer
}

func frameMilliseconds(_ variant: String, _ scene: String) -> Double {
    let buffer = encode(variant, scene)
    buffer.commit()
    buffer.waitUntilCompleted()
    if let error = buffer.error { fail("\(variant) \(scene): \(error)") }
    return (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
}

/// The destination's bytes after one frame, BGRA.
func render(_ variant: String, _ scene: String) -> [UInt8] {
    let buffer = encode(variant, scene)
    guard let blit = buffer.makeBlitCommandEncoder() else { fail("blit") }
    blit.copy(from: destination, sourceSlice: 0, sourceLevel: 0,
              sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: W, height: H, depth: 1),
              to: readback, destinationOffset: 0, destinationBytesPerRow: W * 4,
              destinationBytesPerImage: W * H * 4)
    blit.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()
    if let error = buffer.error { fail("\(variant) \(scene) readback: \(error)") }
    let raw = readback.contents().bindMemory(to: UInt8.self, capacity: W * H * 4)
    return Array(UnsafeBufferPointer(start: raw, count: W * H * 4))
}

// ---- K3, K4: one pixel inside and one outside, so a broken pass is never timed

/// The first pixel (scanning from the frame's centre row outward) whose 5×5
/// neighbourhood all satisfies `test`, so a sample landing between texels
/// could not change the answer.
func pick(_ test: (Int, Int) -> Bool) -> (Int, Int)? {
    let rows = (0..<H).sorted { abs($0 - H / 2) < abs($1 - H / 2) }
    for y in rows where y >= 2 && y < H - 2 {
        for x in 2..<(W - 2) {
            var ok = true
            check: for dy in -2...2 {
                for dx in -2...2 where !test(x + dx, y + dy) { ok = false; break check }
            }
            if ok { return (x, y) }
        }
    }
    return nil
}
func textAlpha(_ x: Int, _ y: Int) -> UInt8 { textBytes[(y * W + x) * 4 + 3] }

let inText = { (x: Int, y: Int) in textAlpha(x, y) == 255 }
let picks: [(row: String, side: String, at: (Int, Int)?)] = [
    ("K3", "inside", pick(inText)),
    ("K3", "outside", pick { textAlpha($0, $1) == 0 }),
    ("K4", "inside", pick { inText($0, $1) && gradientLevel($0) == 255 }),
    ("K4", "outside", pick { inText($0, $1) && gradientLevel($0) == 0 }),
]

var kRows: [[String: Any]] = []
for variant in ["V1", "V2"] {
    let alone = render(variant, "S1")  // the picture's own bytes over the background
    let renders = ["K3": render(variant, "S3"), "K4": render(variant, "S4")]
    for (row, side, at) in picks {
        guard let point = at else {
            kRows.append(["row": row, "variant": variant, "side": side, "ok": false,
                          "detail": "no pixel in the fixture meets the \(side) test"])
            continue
        }
        let (x, y) = point
        let i = (y * W + x) * 4
        let got = Array(renders[row]![i..<i + 4]).map(Int.init)
        let want = side == "inside" ? Array(alone[i..<i + 4]).map(Int.init) : [153, 102, 51, 255]
        let ok = zip(got, want).allSatisfy { abs($0 - $1) <= 1 }
        kRows.append(["row": row, "variant": variant, "side": side, "x": x, "y": y,
                      "got_bgra": got, "want_bgra": want, "ok": ok])
    }
}

// ---- timing ----------------------------------------------------------------

// The order inside a run: per scene, every variant that draws it, interleaved;
// S1 ends with a second V0 series (the C0 control).
let plan: [(series: String, variant: String, scene: String)] = [
    ("V0:S1", "V0", "S1"), ("V1:S1", "V1", "S1"), ("V2:S1", "V2", "S1"), ("V0b:S1", "V0", "S1"),
    ("V1:S2", "V1", "S2"), ("V2:S2", "V2", "S2"),
    ("V1:S3", "V1", "S3"), ("V2:S3", "V2", "S3"),
    ("V1:S4", "V1", "S4"), ("V2:S4", "V2", "S4"),
]
func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
var samples: [String: [[String: Double]]] = [:]
for _ in 0..<runs {
    for (series, variant, scene) in plan {
        for _ in 0..<warmup { _ = frameMilliseconds(variant, scene) }
        let times = (0..<frames).map { _ in frameMilliseconds(variant, scene) }
        samples[series, default: []].append(
            ["median": median(times), "min": times.min()!, "max": times.max()!])
    }
}

let answer: [String: Any] = [
    "width": W, "height": H, "frames": frames, "runs": runs, "warmup": warmup,
    "gpu": device.name, "uniform_bytes": MemoryLayout<LayerUniforms>.stride,
    "k": kRows, "samples": samples,
]
do {
    let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys, .prettyPrinted])
    try data.write(to: URL(fileURLWithPath: outPath))
} catch { fail("could not write \(outPath): \(error)") }
print("bench: wrote \(outPath)")
