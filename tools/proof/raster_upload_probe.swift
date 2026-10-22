// tools/proof/raster_upload_probe.swift — the Swift side of a graphic
// frame's raster cost behind `raster_bench.py` (issue #127, G6 phase 6).
// Compiled through `swift_build.build(optimize=True)` with every file in
// `app/Sources` but `main.swift`, copied in as `main.swift`.
//
//     raster_upload_probe <width> <height> <iterations>
//
// Each iteration, inside `autoreleasepool`, times three things on the
// system default Metal device: the zeroed buffer `GraphicLibrary.rasterize`
// allocates (`[UInt8](repeating: 0, count: max(h × w × 4, 1))`), the app's
// own `LayerRenderers.upload` of a `GraphicRaster` holding it, and
// `makeTexture(descriptor:)` alone with upload's descriptor (bgra8Unorm,
// `.shaderRead`, `.managed`). It prints one JSON object on stdout:
// `{width, height, iterations, zero_ms, upload_ms, texture_ms}`, each a
// median; or `{error}`.
import Foundation
import Metal

func emit(_ answer: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

func milliseconds(_ from: UInt64, _ to: UInt64) -> Double {
    Double(to - from) / 1_000_000
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let n = sorted.count
    return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let width = Int(arguments[1]), let height = Int(arguments[2]),
    let iterations = Int(arguments[3]), width > 0, height > 0, iterations > 0
else {
    emit(["error": "usage: raster_upload_probe <width> <height> <iterations>"])
}
guard let device = MTLCreateSystemDefaultDevice() else {
    emit(["error": "no Metal device"])
}
let renderers = LayerRenderers(device: device)
var zero: [Double] = []
var upload: [Double] = []
var texture: [Double] = []
var uploaded = 0
for _ in 0..<iterations {
    autoreleasepool {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let bgra = [UInt8](repeating: 0, count: max(height * width * 4, 1))
        let t1 = DispatchTime.now().uptimeNanoseconds
        let raster = GraphicRaster(
            width: width, height: height, stride: width * 4, bgra: bgra, warnings: [])
        let t2 = DispatchTime.now().uptimeNanoseconds
        let rendered = renderers.upload(raster)
        let t3 = DispatchTime.now().uptimeNanoseconds
        if rendered != nil { uploaded += 1 }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        let t4 = DispatchTime.now().uptimeNanoseconds
        let made = device.makeTexture(descriptor: descriptor)
        let t5 = DispatchTime.now().uptimeNanoseconds
        if made == nil { uploaded = -iterations }
        zero.append(milliseconds(t0, t1))
        upload.append(milliseconds(t2, t3))
        texture.append(milliseconds(t4, t5))
    }
}
guard uploaded == iterations else {
    emit(["error": "upload or makeTexture answered nil"])
}
emit([
    "width": width, "height": height, "iterations": iterations,
    "zero_ms": median(zero), "upload_ms": median(upload), "texture_ms": median(texture),
])
