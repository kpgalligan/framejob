// Issue #588, spec §11 PR-16 — what a gradient shape's texture costs at each depth.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift` (`tools/proof/swift_build.py`'s line), so it calls the app's own
// `LayerRenderers.shape(_:hash:deep:)`. `renderShape` is private, so what is
// timed is a cache MISS: the Core Graphics draw into the bitmap plus the upload
// (`texture.replace`), which is what a gradient animated by an action pays a
// frame. It MEASURES and prints one JSON object; `shape_draw_probe.py` scores
// the formats and sizes and prints the times.
//
//   shape_draw_probe
import AppKit
import Metal

var answer: [String: Any] = ["ok": false]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

/// `raster_dither_proof.py`'s `shape563` at `width` × `height`.
func gradientShape(_ width: Int, _ height: Int) -> ShapeProps? {
    let json = """
        {"kind": "rectangle", "width": \(width), "height": \(height), "fill": [1, 1, 1, 1],
         "gradient": {"kind": "linear", "angle": 0, "stops": [
            {"at": 0, "color": [\(13.0 / 255), \(21.0 / 255), \(18.0 / 255), 1]},
            {"at": 1, "color": [\(42.0 / 255), \(79.0 / 255), \(61.0 / 255), 1]}]}}
        """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(ShapeProps.self, from: Data(json.utf8))
}

func formatName(_ format: MTLPixelFormat) -> String {
    switch format {
    case .bgra8Unorm: return "bgra8Unorm"
    case .rgba16Float: return "rgba16Float"
    default: return "raw \(format.rawValue)"
    }
}

guard let device = MTLCreateSystemDefaultDevice() else {
    answer["error"] = "no Metal device"
    finish()
}
let renderers = LayerRenderers(device: device)

/// One cache miss: its wall time in ms and the texture it answered.
func timed(_ props: ShapeProps, hash: String, deep: Bool) -> [String: Any] {
    let began = DispatchTime.now().uptimeNanoseconds
    let rendered = renderers.shape(props, hash: hash, deep: deep)
    let ms = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
    guard let texture = rendered?.texture else { return ["ms": ms, "format": "none"] }
    return [
        "ms": ms, "format": formatName(texture.pixelFormat), "width": texture.width,
        "height": texture.height,
    ]
}

let warmUps = 2
let pairs = 15
var sizes: [[String: Any]] = []
for (width, height) in [(1920, 1080), (3840, 2160)] {
    guard let shape = gradientShape(width, height), shape.drawsGradient else {
        answer["error"] = "the fixture did not decode as a gradient shape"
        finish()
    }
    var eight: [[String: Any]] = []
    var deep: [[String: Any]] = []
    for pair in 0..<(warmUps + pairs) {
        autoreleasepool {
            // A fresh hash a call, so every call is a miss; the order alternates pair to pair.
            let first = pair % 2 == 0
            var e: [String: Any] = [:]
            var d: [String: Any] = [:]
            if first { e = timed(shape, hash: "e-\(width)-\(pair)", deep: false) }
            d = timed(shape, hash: "d-\(width)-\(pair)", deep: true)
            if !first { e = timed(shape, hash: "e-\(width)-\(pair)", deep: false) }
            if pair >= warmUps {
                eight.append(e)
                deep.append(d)
            }
            renderers.purge()
        }
    }
    sizes.append(["width": width, "height": height, "eight": eight, "deep": deep])
}
answer["sizes"] = sizes
answer["pairs"] = pairs
answer["warm_ups"] = warmUps
answer["ok"] = true
finish()
