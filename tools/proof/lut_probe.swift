// Road map "grading", phase GR6a — the LUT probe (`lut_proof.py` builds it
// through `swift_build.build` and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libreelcut_core.a`, so every row drives the app's own
// types: `EditorViewController.payloadMediaIDs`, `LutTextures` (and through it
// `MediaImporter.readLUT` and the core's parser) and `RecipeSource`. Nothing
// private is widened.
//
//   lut_probe <request.json> <answer.json>
//
// `request.json` names `folder`, a scratch folder the probe writes its `.cube`
// files into. One JSON object out: `rows`, each a name, ok and detail.
import Accelerate
import AppKit
import AVFoundation
import Metal

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let folder = URL(fileURLWithPath: request["folder"] as? String ?? NSTemporaryDirectory())

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

// MARK: - P2 the payload's media ids

do {
    let clip: [String: Any] = [
        "id": 10, "source": ["kind": "media", "media": 1, "in": 0],
        "video": ["look": ["kind": "lut", "media": 5, "amount": 1]],
        "actions": [
            ["id": 20, "end": ["video": ["look": ["media": 6]]]],
            ["id": 21, "end": ["video": ["opacity": 0.5]]],
            ["id": 22, "end": ["video": ["look": ["media": 5, "amount": 0.5]]]],
        ],
    ]
    let text: [String: Any] = [
        "id": 11, "source": ["kind": "text"], "video": ["look": ["kind": "lut", "media": 7]],
    ]
    let plain: [String: Any] = ["id": 12, "source": ["kind": "media", "media": 2, "in": 0]]
    let ids = EditorViewController.payloadMediaIDs(clip)
    let textIDs = EditorViewController.payloadMediaIDs(text)
    let plainIDs = EditorViewController.payloadMediaIDs(plain)
    check(
        "P2 payloadMediaIDs: the source, the base look, then each end's look, without repeats",
        ids == [1, 5, 6] && textIDs == [7] && plainIDs == [2],
        "clip \(ids); text \(textIDs); plain \(plainIDs)")
}

// MARK: - T1, T2 the LUT textures

/// A size-2 table whose row k is (k/8, k mod 3 / 4, 1 − k/8), with row 0's
/// green −0.5 and row 7's red 1.5 (clamped to 0 and 1 when uploaded).
func asymmetric() -> (text: String, want: [[Float]]) {
    var lines = ["TITLE \"probe\"", "LUT_3D_SIZE 2"]
    var want: [[Float]] = []
    for k in 0..<8 {
        var red = Float(k) / 8
        var green = Float(k % 3) / 4
        let blue = 1 - Float(k) / 8
        var written = (red, green, blue)
        if k == 0 { written.1 = -0.5; green = 0 }
        if k == 7 { written.0 = 1.5; red = 1 }
        lines.append("\(written.0) \(written.1) \(written.2)")
        want.append([red, green, blue, 1])
    }
    return (lines.joined(separator: "\n") + "\n", want)
}

/// The texture's texels as floats, in texel order (x fastest, then y, then z).
func texels(_ texture: MTLTexture, device: MTLDevice) -> [Float]? {
    let n = texture.width
    let count = n * n * n * 4
    guard let queue = device.makeCommandQueue(), let buffer = queue.makeCommandBuffer() else {
        return nil
    }
    if texture.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
        blit.synchronize(resource: texture)
        blit.endEncoding()
    }
    buffer.commit()
    buffer.waitUntilCompleted()
    var halves = [UInt16](repeating: 0, count: count)
    halves.withUnsafeMutableBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        texture.getBytes(
            base, bytesPerRow: n * 8, bytesPerImage: n * n * 8,
            from: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0)
    }
    var floats = [Float](repeating: 0, count: count)
    let ok: Bool = halves.withUnsafeMutableBytes { source in
        floats.withUnsafeMutableBytes { target in
            guard let from = source.baseAddress, let to = target.baseAddress else { return false }
            var src = vImage_Buffer(
                data: from, height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
            var dst = vImage_Buffer(
                data: to, height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
            return vImageConvert_Planar16FtoPlanarF(&src, &dst, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        }
    }
    return ok ? floats : nil
}

func cubeText(size: Int) -> String {
    var lines = ["LUT_3D_SIZE \(size)"]
    for b in 0..<size {
        for g in 0..<size {
            for r in 0..<size {
                let step = Float(size - 1)
                lines.append("\(Float(r) / step) \(Float(g) / step) \(Float(b) / step)")
            }
        }
    }
    return lines.joined(separator: "\n") + "\n"
}

if let device = MTLCreateSystemDefaultDevice() {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let luts = LutTextures(device: device)
    let (text, want) = asymmetric()
    let file = folder.appendingPathComponent("asymmetric.cube")
    try? text.write(to: file, atomically: true, encoding: .utf8)
    let texture = luts.texture(at: file)
    let read = texture.flatMap { texels($0, device: device) }
    var misses: [String] = []
    if let read = read {
        for b in 0..<2 {
            for g in 0..<2 {
                for r in 0..<2 {
                    let k = r + 2 * g + 4 * b
                    let got = Array(read[(k * 4)..<(k * 4 + 4)])
                    if got != want[k] { misses.append("(\(r),\(g),\(b)) \(got) want \(want[k])") }
                }
            }
        }
    }
    check(
        "T1 a size-2 asymmetric file uploads as a 2³ rgba16Float texture, texel (r, g, b) the "
            + "file's row r + 2g + 4b (red fastest), clamped to 0–1, alpha 1",
        texture?.width == 2 && texture?.depth == 2 && texture?.pixelFormat == .rgba16Float
            && read != nil && misses.isEmpty,
        "texture \(texture.map { "\($0.width)³ \($0.pixelFormat.rawValue)" } ?? "nil"); "
            + "misses \(misses.prefix(3))")

    let missing = folder.appendingPathComponent("absent.cube")
    let refused = folder.appendingPathComponent("refused.cube")
    try? "LUT_3D_SIZE 1\n0 0 0\n".write(to: refused, atomically: true, encoding: .utf8)
    let first = luts.texture(at: refused)
    let again = luts.texture(at: refused)
    let absent = luts.texture(at: missing)
    // The same name rewritten readable is a new key (its size and date moved).
    try? cubeText(size: 2).write(to: refused, atomically: true, encoding: .utf8)
    let fixed = luts.texture(at: refused)
    check(
        "T2 a missing file and a refused one answer nil (the refusal twice, cached), and the "
            + "refused file rewritten readable answers a texture",
        first == nil && again == nil && absent == nil && fixed != nil,
        "refused \(first == nil)/\(again == nil); missing \(absent == nil); rewritten "
            + "\(fixed != nil)")
} else {
    check("T1 a Metal device", false, "MTLCreateSystemDefaultDevice() is nil")
    check("T2 a Metal device", false, "MTLCreateSystemDefaultDevice() is nil")
}

// MARK: - P3 the look URLs

do {
    let source = RecipeSource.shared
    let published = source.register()
    let unpublished = source.register()
    let a = URL(fileURLWithPath: "/probe/a.cube")
    let b = URL(fileURLWithPath: "/probe/b.cube")
    func instruction(_ key: Int, _ urls: [UInt32: URL]) -> RecipeInstruction {
        RecipeInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)),
            requiredTrackIDs: [], recipeKey: key, mediaURLs: urls, sourceOrientations: [:],
            missingClips: [])
    }
    let built = instruction(published, [:])
    let before = source.lookURLs(for: built)
    source.setMediaURLs([3: a], for: published)
    let after = source.lookURLs(for: built)
    let fallback = source.lookURLs(for: instruction(unpublished, [4: b]))
    let none = source.lookURLs(for: nil)
    source.unregister(published)
    let dropped = source.lookURLs(for: built)
    source.unregister(unpublished)
    check(
        "P3 lookURLs(for:) answers the map published under the instruction's key after the "
            + "instruction was built with none, the instruction's own map for a key that never "
            + "published, [:] for nil, and the instruction's again once the key is unregistered",
        before.isEmpty && after == [3: a] && fallback == [4: b] && none.isEmpty
            && dropped.isEmpty,
        "before \(before); after \(after); fallback \(fallback); nil \(none); dropped \(dropped)")
}

finish()
