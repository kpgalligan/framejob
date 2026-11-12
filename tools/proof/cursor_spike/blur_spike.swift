// Road map "creator-jobs" CU11, spike CU-S5 — motion blur's cost. Compiled as `main.swift`
// over `app/Sources` (all but the app's `main.swift`) through `swift_build.build()` with
// `FRAMEJOB_DEV_TOOLS`, by `blur_spike.py`, with a `default.metallib` of the tree's
// `Compositor.metal` beside the binary (where `MetalRenderer` looks). Run as
// `<binary> blur-spike <request.json>`; prints one JSON object on stdout:
// `{rows: [{width, height, n (0 = once), run_medians_ms, samples_ms}], problems}`.
//
// Per size: a project (the canvas that size, 30 fps) with one canvas-sized `image` media and
// one 2 s clip whose action over [0, 1 s) eases in and out to `{video: {scale: 2}}`; t is
// 0.5 s (300,000 ticks), the zoom's middle. The source is the probe's own `rgba16Float`
// texture of the canvas's size, a fixed checker. Uniforms come from `MetalRenderer.uniforms`
// of `ReelProject.recipe(at:)`'s layer.
// - once: a fresh destination cleared, one draw through `renderer.pipeline` at t.
// - blurred N: a `mattePool` composite cleared, N draws through a probe-built accumulate
//   pipeline (the plain layer fragment, both destination factors `.one`) at the placements of
//   `recipe(at: t + round(((2k+1−N)/(2N))·shutter·20,000))`, each at opacity / N; then one draw
//   of that composite onto the cleared destination through `renderer.pipeline` with the
//   uniforms of `recipe(at: 0)`'s layer (scale 1).
// Textures 1–5 are `renderer.placeholder`. One command buffer per frame on the probe's own
// queue; a frame's GPU ms is `gpuEndTime − gpuStartTime`; the warm-up frames are dropped.

import Foundation
import Metal

let second: Ticks = 600_000
let frameTicks: Double = 20_000

var problems: [String] = []
var rows: [[String: Any]] = []

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows, "problems": problems]
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{\"rows\": [], \"problems\": [\"the answer did not encode\"]}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3, arguments[1] == "blur-spike",
      let requestData = FileManager.default.contents(atPath: arguments[2]),
      let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any]
else {
    FileHandle.standardError.write(Data("usage: <binary> blur-spike <request.json>\n".utf8))
    exit(2)
}
let sizes = (request["sizes"] as? [[Int]]) ?? [[1920, 1080], [3840, 2160]]
let ns = (request["ns"] as? [Int]) ?? [4, 8, 16]
let runs = (request["runs"] as? Int) ?? 5
let frames = (request["frames"] as? Int) ?? 60
let warmup = (request["warmup"] as? Int) ?? 10
let shutter = (request["shutter"] as? Double) ?? 0.5

guard let renderer = MetalRenderer() else {
    problems.append("no MetalRenderer (is default.metallib beside the binary?)")
    finish()
}
let device = renderer.device
guard let queue = device.makeCommandQueue() else {
    problems.append("no command queue")
    finish()
}
guard let library = (try? device.makeDefaultLibrary(bundle: Bundle.main)) ?? device.makeDefaultLibrary(),
      let vertex = library.makeFunction(name: "framejob_layer_vertex"),
      let fragment = MetalRenderer.layerFragment(library, gather: false)
else {
    problems.append("the layer functions did not load")
    finish()
}
let accumulateDescriptor = MetalRenderer.pipelineDescriptor(
    label: "CU-S5 accumulate", vertex: vertex, fragment: fragment)
accumulateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
accumulateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
guard let accumulate = try? device.makeRenderPipelineState(descriptor: accumulateDescriptor) else {
    problems.append("the accumulate pipeline did not build")
    finish()
}

/// The size's project as the header says.
func project(width: Int, height: Int) -> ReelProject? {
    let json: [String: Any] = [
        "version": 41,
        "canvas": ["width": width, "height": height, "fps": [30, 1], "background": [0, 0, 0, 1]],
        "media": [["id": 1, "path": "/cu-s5/pattern.png", "kind": "image", "duration": 0,
                   "width": width, "height": height, "has_video": true, "has_audio": false]],
        "tracks": [["id": 2, "name": "Track 1"]],
        "clips": [["id": 3, "track": 2, "start": 0, "duration": 2 * second,
                   "source": ["kind": "image", "media": 1], "video": [:],
                   "actions": [["id": 4, "start": 0, "duration": second, "curve": "ease_in_out",
                                "end": ["video": ["scale": 2.0]]]]]],
        "next_id": 5,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
    do {
        return try ReelProject.from(json: String(decoding: data, as: UTF8.self))
    } catch {
        problems.append("\(width)×\(height): \(error)")
        return nil
    }
}

/// A fixed checker of 64 px squares, two greys, opaque, in `rgba16Float`.
func pattern(width: Int, height: Int) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    func row(_ phase: Int) -> [Float16] {
        var values = [Float16](repeating: 1, count: width * 4)
        for x in 0..<width {
            let light = ((x / 64) + phase) % 2 == 0
            let v: Float16 = light ? 0.8 : 0.2
            values[x * 4] = v
            values[x * 4 + 1] = light ? 0.6 : 0.3
            values[x * 4 + 2] = v
        }
        return values
    }
    let rowsByPhase = [row(0), row(1)]
    for y in 0..<height {
        rowsByPhase[(y / 64) % 2].withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, y, width, 1), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: width * 8)
        }
    }
    return texture
}

func destination(width: Int, height: Int) -> MTLTexture? {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: MetalRenderer.workingFormat, width: width, height: height, mipmapped: false)
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = .private
    return device.makeTexture(descriptor: descriptor)
}

/// One draw of `source` with `uniforms` through `state`, on `encoder`.
func draw(
    _ encoder: MTLRenderCommandEncoder, state: MTLRenderPipelineState, source: MTLTexture,
    uniforms: LayerUniforms
) {
    var u = uniforms
    u.sourceWidth = Float(source.width)
    u.sourceHeight = Float(source.height)
    encoder.setRenderPipelineState(state)
    encoder.setFragmentSamplerState(renderer.sampler, index: 0)
    for index in 1...5 { encoder.setFragmentTexture(renderer.placeholder, index: index) }
    encoder.setVertexBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
    encoder.setFragmentBytes(&u, length: MemoryLayout<LayerUniforms>.stride, index: 0)
    encoder.setFragmentTexture(source, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
}

func pass(_ target: MTLTexture, clear: MTLClearColor, buffer: MTLCommandBuffer)
    -> MTLRenderCommandEncoder?
{
    let descriptor = MTLRenderPassDescriptor()
    descriptor.colorAttachments[0].texture = target
    descriptor.colorAttachments[0].loadAction = .clear
    descriptor.colorAttachments[0].storeAction = .store
    descriptor.colorAttachments[0].clearColor = clear
    return buffer.makeRenderCommandEncoder(descriptor: descriptor)
}

let black = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
let clearTransparent = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

/// One frame's GPU milliseconds, or nil when it did not complete.
func frame(
    n: Int, source: MTLTexture, target: MTLTexture, at: LayerUniforms,
    samples: [LayerUniforms], whole: LayerUniforms
) -> Double? {
    guard let buffer = queue.makeCommandBuffer() else { return nil }
    if n == 0 {
        guard let encoder = pass(target, clear: black, buffer: buffer) else { return nil }
        draw(encoder, state: renderer.pipeline, source: source, uniforms: at)
        encoder.endEncoding()
    } else {
        renderer.mattePool.beginFrame(width: target.width, height: target.height, deep: false)
        defer { renderer.mattePool.endFrame() }
        guard let composite = renderer.mattePool.takeComposite(),
              let first = pass(composite, clear: clearTransparent, buffer: buffer)
        else { return nil }
        for u in samples { draw(first, state: accumulate, source: source, uniforms: u) }
        first.endEncoding()
        guard let onto = pass(target, clear: black, buffer: buffer) else { return nil }
        draw(onto, state: renderer.pipeline, source: composite, uniforms: whole)
        onto.endEncoding()
    }
    buffer.commit()
    buffer.waitUntilCompleted()
    guard buffer.status == .completed else { return nil }
    return (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
}

let t: Ticks = second / 2
for size in sizes where size.count == 2 {
    let (width, height) = (size[0], size[1])
    guard let made = project(width: width, height: height),
          let source = pattern(width: width, height: height),
          let target = destination(width: width, height: height)
    else {
        problems.append("\(width)×\(height): the project or a texture was not made")
        continue
    }
    let destinationSize = CGSize(width: width, height: height)
    func uniforms(at time: Ticks) -> LayerUniforms? {
        guard let recipe = made.recipe(at: time), let layer = recipe.layers.first else {
            return nil
        }
        return renderer.uniforms(for: layer, canvas: recipe.canvas, destination: destinationSize)
    }
    guard let at = uniforms(at: t), let whole = uniforms(at: 0) else {
        problems.append("\(width)×\(height): no layer at t or at 0")
        continue
    }
    var sampled: [Int: [LayerUniforms]] = [:]
    for n in ns {
        var list: [LayerUniforms] = []
        for k in 0..<n {
            let offset = (Double(2 * k + 1 - n) / Double(2 * n) * shutter * frameTicks).rounded()
            guard var u = uniforms(at: t + Ticks(offset)) else { continue }
            u.opacity /= Float(n)
            list.append(u)
        }
        if list.count != n { problems.append("\(width)×\(height): \(list.count) of \(n) samples") }
        sampled[n] = list
    }
    var medians: [Int: [Any]] = [:]
    var samplesMs: [Int: [[Double]]] = [:]
    for _ in 0..<runs {
        for n in [0] + ns {
            var times: [Double] = []
            for index in 0..<(warmup + frames) {
                guard let ms = frame(
                    n: n, source: source, target: target, at: at, samples: sampled[n] ?? [],
                    whole: whole)
                else {
                    problems.append("\(width)×\(height) n \(n): a frame did not complete")
                    continue
                }
                if index >= warmup { times.append(ms) }
            }
            let sorted = times.sorted()
            var median: Any = NSNull()
            if !sorted.isEmpty {
                median = sorted.count % 2 == 1
                    ? sorted[sorted.count / 2]
                    : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            }
            medians[n, default: []].append(median)
            samplesMs[n, default: []].append(times)
        }
    }
    for n in [0] + ns {
        rows.append(["width": width, "height": height, "n": n,
                     "run_medians_ms": medians[n] ?? [], "samples_ms": samplesMs[n] ?? []])
    }
}
finish()
