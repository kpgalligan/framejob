// Road map 10, G1d — the graphics engine through `ReelCore.swift`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so it drives the app's own
// wrappers: `GraphicLibrary`, `GraphicModule`, `GraphicRaster`. It MEASURES
// and prints one JSON object; `graphics_ffi_probe.py` scores it against
// oracles of its own (hashlib, the crate's `pins.json`).
//
//   graphics_ffi_probe <app_fonts_dir> <lower-third.js> <out_dir>
//
// Writes `<out_dir>/lower-third-30.bgra` (the raw frame, for Python to hash)
// and `<out_dir>/lower-third-30.png`.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: graphics_ffi_probe fonts fixture out\n".utf8))
    exit(2)
}
let fontsDir = URL(fileURLWithPath: arguments[1])
let fixtureURL = URL(fileURLWithPath: arguments[2])
let outDir = URL(fileURLWithPath: arguments[3])
var answer: [String: Any] = ["ok": false]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func diagnostics(_ list: [GraphicDiagnostic]) -> [[String: Any]] {
    list.map { d in
        ["level": d.level, "message": d.message, "line": d.line ?? NSNull(),
         "column": d.column ?? NSNull(), "frame": d.frame ?? NSNull()]
    }
}

func failure(_ error: Error) -> [[String: Any]] {
    if let f = error as? GraphicFailure { return diagnostics(f.diagnostics) }
    return [["level": "error", "message": String(describing: error)]]
}

/// `graphic/tests/common/mod.rs`'s `ctx(frame, 30.0, 150, 1920, 1080)`.
func ctx(_ frame: Int) -> String {
    let progress = min(max(Double(frame) / 149.0, 0), 1)
    return "{\"fps\":30.0,\"time\":\(Double(frame) / 30.0),\"durationInFrames\":150,"
        + "\"progress\":\(progress),\"width\":1920,\"height\":1080,"
        + "\"canvas\":{\"width\":1920,\"height\":1080}}"
}

// P2 — every bundled face, and 16 zero bytes.
let library = GraphicLibrary()
let names = ((try? FileManager.default.contentsOfDirectory(atPath: fontsDir.path)) ?? [])
    .filter { $0.hasSuffix(".ttf") }.sorted()
var taken = 0
var fontErrors: [String] = []
for name in names {
    do {
        try library.addFont(try Data(contentsOf: fontsDir.appendingPathComponent(name)))
        taken += 1
    } catch {
        fontErrors.append("\(name): \(error.localizedDescription)")
    }
}
var zero: Any = NSNull()
do { try library.addFont(Data(count: 16)) } catch { zero = error.localizedDescription }
answer["p2"] = ["folder": names.count, "taken": taken, "errors": fontErrors, "zero": zero]

// P3 — compile and describe.
guard let source = try? String(contentsOf: fixtureURL, encoding: .utf8) else { finish() }
let module: GraphicModule
do {
    module = try GraphicModule.compile(
        library: library, name: "lower-third", source: source, budgetMs: 250)
} catch {
    answer["compile"] = failure(error)
    finish()
}
answer["p3"] = ["describe": module.describeJSON()]

// P4, P5, P6 — frames 30, 30 again, and 0, each drawn.
func frame(_ n: Int) -> (svg: String, warnings: [GraphicDiagnostic], raster: GraphicRaster)? {
    guard let drawn = try? module.svg(frame: n, propsJSON: "{}", ctxJSON: ctx(n), budgetMs: 250),
          let raster = try? library.rasterize(drawn.svg, width: 1920, height: 1080)
    else { return nil }
    return (drawn.svg, drawn.warnings, raster)
}
guard let thirty = frame(30), let again = frame(30), let first = frame(0) else {
    answer["frames"] = "a frame did not draw"
    finish()
}
answer["p4"] = ["prefix": String(thirty.svg.prefix(4)), "warnings": diagnostics(thirty.warnings),
                "raster_warnings": diagnostics(thirty.raster.warnings)]

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let bgraURL = outDir.appendingPathComponent("lower-third-30.bgra")
let pngURL = outDir.appendingPathComponent("lower-third-30.png")
try? FileManager.default.removeItem(at: bgraURL)
try? FileManager.default.removeItem(at: pngURL)
try? Data(thirty.raster.bgra).write(to: bgraURL)
var pngWritten = false
let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
    | CGBitmapInfo.byteOrder32Little.rawValue)
if let provider = CGDataProvider(data: Data(thirty.raster.bgra) as CFData),
   let image = CGImage(
       width: 1920, height: 1080, bitsPerComponent: 8, bitsPerPixel: 32,
       bytesPerRow: thirty.raster.stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
   let sink = CGImageDestinationCreateWithURL(pngURL as CFURL, UTType.png.identifier as CFString,
                                              1, nil) {
    CGImageDestinationAddImage(sink, image, nil)
    pngWritten = CGImageDestinationFinalize(sink)
}
answer["p5"] = ["bgra": bgraURL.path, "png": pngURL.path, "png_written": pngWritten,
                "stride": thirty.raster.stride, "bytes": thirty.raster.bgra.count]
answer["p6"] = ["svg_again_equal": thirty.svg == again.svg,
                "bgra_again_equal": thirty.raster.bgra == again.raster.bgra,
                "bgra_0_differs": thirty.raster.bgra != first.raster.bgra]

// P7 — a syntax error; P8 — a top-level loop at 50 ms.
do {
    _ = try GraphicModule.compile(library: library, name: "broken",
                                  source: "export const meta = {};\n\nconst x = ;\n", budgetMs: 250)
    answer["p7"] = ["compiled": true]
} catch {
    answer["p7"] = ["compiled": false, "diagnostics": failure(error)]
}
let began = Date()
do {
    _ = try GraphicModule.compile(library: library, name: "loop", source: "while (true) {}\n",
                                  budgetMs: 50)
    answer["p8"] = ["compiled": true]
} catch {
    answer["p8"] = ["compiled": false, "diagnostics": failure(error),
                    "seconds": Date().timeIntervalSince(began)]
}

// P9 — a prop the schema does not take, at frame 30.
do {
    let drawn = try module.svg(frame: 30, propsJSON: "{\"size\":\"big\"}", ctxJSON: ctx(30),
                               budgetMs: 250)
    answer["p9"] = ["drew": true, "warnings": diagnostics(drawn.warnings)]
} catch {
    answer["p9"] = ["drew": false, "diagnostics": failure(error)]
}

answer["ok"] = true
finish()
