// Road map "creator-jobs" CU3a1 (spec §11 CU-30, CU-32, CU-35, CU-39): the
// probe rows of `cursor_layer_proof.py`, compiled as `main.swift` over
// `app/Sources` through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS`, and
// run as `cursor-layer-probe <request.json>`. The request names the v37
// fixture (`fixture`, a project as JSON text: A.mov, one clip, one zoom
// action). No app, no file read but the request. It prints one JSON object,
// `{"rows": [{"id", "pass", "detail"}]}`, on stdout.
//
// - L1d the Swift mirrors of a fixture carrying `media.cursor` and
//   `video.cursor`: `MediaSnapshot.cursor` and `VideoProps.cursor` equal the
//   JSON, `MediaDescriptor(media).dictionary["cursor"]` is the JSON object,
//   and `VideoPatch`'s `cursor` writes all eight keys, or `NSNull` for
//   `.some(nil)`.
// - L3r at five times every layer's `cursor` is null; with `media[0].cursor`
//   `{path, in_picture: true}` the recipe's TEXT is byte-identical at each
//   time; the control, `in_picture: false`, is not null.
// - L9 a base `cursor {smoothing: 0}` and an action over [1 s, 3 s) ending
//   `{smoothing: 1, hide_idle: 5, scale: 3}`: at 0.5, 1.5, 2.5 and 3.5 s the
//   key's and `props`' `smoothing` are 0 and `hide_idle` null; `props.scale`
//   1, strictly between 1 and 3 twice, then 3; `recipe(at:)` decodes the same.
//
// CU3a2 (spec §11 CU-33, CU-37), when the request names them:
// - `cursor_dir`: the drawing rows' fixture written there — `sprite.png` and
//   `cursor.fjcursor` (format v1 through `CursorFileBody`, read back through
//   `ReelCursor`) — and answered beside the rows as `fixture` (the paths, the
//   sprite's centroid offset from its hot spot, its colour and that colour's
//   `InputConversions.liftSDR`, the moves).
// - `l7` (`movie`, `cursor`, `runs`): L7, the compositor's own per-frame
//   seconds (`PlaybackTrials`, so `FRAMEJOB_DEV_TOOLS`) over 120 frames read
//   through a composition output, the cursor with ripples against none, at
//   1920×1080, 3840×2160 and 5120×2880; and `CursorSprites.uploads` over 120
//   `cursorSprite` calls on a `MetalRenderer` of its own (the proof puts a
//   `default.metallib` of the tree's shader beside the binary).

import AVFoundation
import Foundation
import ImageIO

var rows: [[String: Any]] = []
/// The CU3a2 fixture's facts, answered beside the rows when the request names `cursor_dir`.
var fixtureAnswer: [String: Any] = [:]

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func finish() -> Never {
    let data =
        (try? JSONSerialization.data(
            withJSONObject: ["rows": rows, "fixture": fixtureAnswer], options: [.sortedKeys]))
        ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

let second: Ticks = 600_000

guard CommandLine.arguments.count > 1,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let fixtureText = request["fixture"] as? String,
    let fixtureData = fixtureText.data(using: .utf8),
    let fixture = (try? JSONSerialization.jsonObject(with: fixtureData)) as? [String: Any]
else {
    for id in ["L1d", "L3r", "L9"] { row(id, false, "the request could not be read") }
    finish()
}

/// `fixture` changed by `edit`, as JSON text.
func variant(_ edit: (inout [String: Any]) -> Void) -> String {
    var copy = fixture
    edit(&copy)
    let data = (try? JSONSerialization.data(withJSONObject: copy, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

/// Sets `value` at `media[0][key]`.
func setMedia(_ project: inout [String: Any], _ key: String, _ value: Any) {
    var media = project["media"] as? [[String: Any]] ?? []
    if !media.isEmpty { media[0][key] = value }
    project["media"] = media
}

/// Sets `value` at `clips[0][key]`.
func setClip(_ project: inout [String: Any], _ key: String, _ value: Any) {
    var clips = project["clips"] as? [[String: Any]] ?? []
    if !clips.isEmpty { clips[0][key] = value }
    project["clips"] = clips
}

func layers(_ text: String?) -> [[String: Any]] {
    guard let data = text?.data(using: .utf8),
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [] }
    return object["layers"] as? [[String: Any]] ?? []
}

let mediaCursorJSON: [String: Any] = [
    "path": "/proof/A.fjcursor", "bookmark": "Qk0=", "in_picture": false,
]
let cursorJSON: [String: Any] = [
    "show": false, "scale": 2.5, "style": "arrow", "smoothing": 0.5, "hide_idle": 3.0,
    "clicks": "ripple", "click_color": "red", "click_size": 1.5,
]

// ---- L1d ------------------------------------------------------------------

do {
    let text = variant { project in
        setMedia(&project, "cursor", mediaCursorJSON)
        var clips = project["clips"] as? [[String: Any]] ?? []
        var video = clips.first?["video"] as? [String: Any] ?? [:]
        video["cursor"] = cursorJSON
        if !clips.isEmpty { clips[0]["video"] = video }
        project["clips"] = clips
    }
    var problems: [String] = []
    do {
        let project = try ReelProject.from(json: text)
        let snapshot = project.snapshot
        let expectedMedia = MediaCursor(path: "/proof/A.fjcursor", bookmark: "Qk0=", inPicture: false)
        let expectedProps = CursorProps(
            show: false, scale: 2.5, style: .arrow, smoothing: 0.5, hideIdle: 3, clicks: .ripple,
            clickColor: "red", clickSize: 1.5)
        if snapshot.media.first?.cursor != expectedMedia {
            problems.append("MediaSnapshot.cursor \(String(describing: snapshot.media.first?.cursor))")
        }
        if snapshot.clips.first?.video?.cursor != expectedProps {
            problems.append("VideoProps.cursor \(String(describing: snapshot.clips.first?.video?.cursor))")
        }
        if let media = snapshot.media.first {
            let written = MediaDescriptor(media).dictionary["cursor"] as? [String: Any] ?? [:]
            if !(written as NSDictionary).isEqual(to: mediaCursorJSON) {
                problems.append("MediaDescriptor's cursor \(written)")
            }
            let probe = MediaDescriptor(media).probeDictionary["cursor"] as? [String: Any] ?? [:]
            if !(probe as NSDictionary).isEqual(to: mediaCursorJSON) {
                problems.append("the probe's cursor \(probe)")
            }
        } else {
            problems.append("no media")
        }
        let patch = VideoPatch(cursor: .some(expectedProps)).dictionary["cursor"] as? [String: Any] ?? [:]
        if patch.count != 8 || !(patch as NSDictionary).isEqual(to: cursorJSON) {
            problems.append("VideoPatch's cursor \(patch)")
        }
        let defaults = VideoPatch(cursor: .some(CursorProps())).dictionary["cursor"] as? [String: Any] ?? [:]
        if defaults.count != 8 || !(defaults["hide_idle"] is NSNull)
            || defaults["clicks"] as? String != "none"
        {
            problems.append("VideoPatch's default cursor \(defaults)")
        }
        if !(VideoPatch(cursor: .some(nil)).dictionary["cursor"] is NSNull) {
            problems.append("VideoPatch(cursor: .some(nil)) did not write NSNull")
        }
        if VideoPatch().dictionary["cursor"] != nil {
            problems.append("VideoPatch() wrote a cursor")
        }
    } catch {
        problems.append("the fixture did not open: \(error)")
    }
    row("L1d", problems.isEmpty, problems.isEmpty
        ? "the snapshot, the descriptor and the patch mirror media.cursor and video.cursor"
        : problems.joined(separator: "; "))
}

// ---- L3r ------------------------------------------------------------------

do {
    let times: [Ticks] = [0, second / 2, 3 * second / 2, 2 * second + 20_000, 5 * second]
    var problems: [String] = []
    do {
        let plain = try ReelProject.from(json: variant { _ in })
        let inPicture = try ReelProject.from(json: variant { project in
            setMedia(&project, "cursor", ["path": "/proof/A.fjcursor", "in_picture": true])
        })
        let control = try ReelProject.from(json: variant { project in
            setMedia(&project, "cursor", ["path": "/proof/A.fjcursor", "in_picture": false])
        })
        for t in times {
            let text = plain.recipeJSON(at: t)
            let drawn = layers(text)
            if drawn.isEmpty { problems.append("no layer at \(t)") }
            if drawn.contains(where: { !($0["cursor"] is NSNull) }) {
                problems.append("a non-null cursor at \(t)")
            }
            if inPicture.recipeJSON(at: t) != text {
                problems.append("in_picture: true changed the recipe text at \(t)")
            }
            let controlled = layers(control.recipeJSON(at: t))
            if controlled.isEmpty || controlled.contains(where: { $0["cursor"] is NSNull }) {
                problems.append("the control's cursor is null at \(t)")
            }
        }
    } catch {
        problems.append("a fixture did not open: \(error)")
    }
    row("L3r", problems.isEmpty, problems.isEmpty
        ? "null at \(times.count) times, in_picture: true byte-identical, the control keyed"
        : problems.joined(separator: "; "))
}

// ---- L9 -------------------------------------------------------------------

do {
    var problems: [String] = []
    var scales: [Double] = []
    do {
        let project = try ReelProject.from(json: variant { project in
            setMedia(&project, "cursor", ["path": "/proof/A.fjcursor", "in_picture": false])
            var clips = project["clips"] as? [[String: Any]] ?? []
            var video = clips.first?["video"] as? [String: Any] ?? [:]
            video["cursor"] = ["smoothing": 0]
            if !clips.isEmpty { clips[0]["video"] = video }
            project["clips"] = clips
            setClip(&project, "actions", [[
                "id": 4, "start": second, "duration": 2 * second, "curve": "linear",
                "end": ["video": ["cursor": ["smoothing": 1, "hide_idle": 5, "scale": 3]]],
            ]])
        })
        let start = (fixture["clips"] as? [[String: Any]])?.first?["start"] as? Int ?? 0
        for clipT in [second / 2, 3 * second / 2, 5 * second / 2, 7 * second / 2] {
            let t = Ticks(start) + clipT
            guard let key = layers(project.recipeJSON(at: t)).first?["cursor"] as? [String: Any],
                let props = key["props"] as? [String: Any]
            else {
                problems.append("no cursor key at \(t)")
                continue
            }
            if (key["smoothing"] as? Double) != 0 || (props["smoothing"] as? Double) != 0 {
                problems.append("smoothing \(key["smoothing"] ?? "nil") / \(props["smoothing"] ?? "nil") at \(t)")
            }
            if !(key["hide_idle"] is NSNull) || !(props["hide_idle"] is NSNull) {
                problems.append("hide_idle \(key["hide_idle"] ?? "nil") at \(t)")
            }
            let scale = (props["scale"] as? Double) ?? .nan
            scales.append(scale)
            guard let decoded = project.recipe(at: t)?.layers.first?.cursor else {
                problems.append("recipe(at:) decoded no cursor at \(t)")
                continue
            }
            if decoded.smoothing != 0 || decoded.hideIdle != nil || decoded.props.smoothing != 0
                || decoded.props.hideIdle != nil || decoded.props.scale != scale
            {
                problems.append("recipe(at:) decoded \(decoded) at \(t)")
            }
        }
    } catch {
        problems.append("the fixture did not open: \(error)")
    }
    let shaped = scales.count == 4 && scales[0] == 1 && scales[1] > 1 && scales[1] < 3
        && scales[2] > scales[1] && scales[2] < 3 && scales[3] == 3
    if !shaped { problems.append("props.scale \(scales)") }
    row("L9", problems.isEmpty, problems.isEmpty
        ? "smoothing 0 and hide_idle null at 4 times; props.scale \(scales)"
        : problems.joined(separator: "; "))
}

// ---- CU3a2: the fixture (cursor file and sprite) ------------------------------

/// The sprite: a 12 × 16 arrow-like triangle, opaque where `col <= row * 3 / 4 + 1`,
/// transparent elsewhere, in one distinctive colour; hot spot (1, 1); 1 px a point.
let spriteWidth = 12
let spriteHeight = 16
let spriteColor: (UInt8, UInt8, UInt8) = (120, 30, 100)
let spriteHot = (1, 1)
func spriteOpaque(_ col: Int, _ row: Int) -> Bool { Double(col) <= Double(row) * 0.75 + 1 }

/// The file's moves: one a frame at 30 fps from µs `floor(k·10⁶/30)`, at px
/// (60 + 3k, 50 + k); two down clicks at k 30 and 75.
func moveMicros(_ k: Int) -> Int64 { Int64(k) * 100_000 / 3 }
func movePixel(_ k: Int) -> (Int64, Int64) { (Int64(60 + 3 * k), Int64(50 + k)) }
let moveCount = 120
let clickFrames = [30, 75]

/// The sprite as PNG bytes (straight RGBA, 8 bits).
func spritePNG() -> Data? {
    let bytesPerRow = spriteWidth * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * spriteHeight)
    for row in 0..<spriteHeight {
        for col in 0..<spriteWidth where spriteOpaque(col, row) {
            let at = row * bytesPerRow + col * 4
            pixels[at] = spriteColor.0
            pixels[at + 1] = spriteColor.1
            pixels[at + 2] = spriteColor.2
            pixels[at + 3] = 255
        }
    }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: spriteWidth, height: spriteHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        out as CFMutableData, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return out as Data
}

/// The v1 cursor file through the app's own encoder (`CursorFileBody`): identity geometry
/// (640 × 360 points at 1 px a point, the screen at the origin), the moves, the clicks, the
/// one image from t 0.
func cursorBody(png: Data) -> CursorFileBody {
    var b = CursorFileBody(
        version: ReelCursor.fileVersion, inPicture: false, source: .display, displayID: 1,
        sourceFrame: [0, 0, 64000, 36000], pointSize: [64000, 36000], pixelsPerPoint: 1,
        contentSize: [640, 360], movieSize: [640, 360], anchor: .e2, anchorHostUs: 0,
        cursorImage: .currentSystem)
    b.geometry = [.init(t: 0, screenRect: [0, 0, 64000, 36000],
                        contentRect: [0, 0, 64000, 36000], contentScale: 1, scaleFactor: 1)]
    for k in 0..<moveCount {
        let (x, y) = movePixel(k)
        b.moves.t.append(moveMicros(k))
        b.moves.x.append(x * 100)
        b.moves.y.append(y * 100)
    }
    for k in clickFrames {
        let (x, y) = movePixel(k)
        b.clicks.t.append(moveMicros(k))
        b.clicks.button.append(0)
        b.clicks.down.append(1)
        b.clicks.x.append(x * 100)
        b.clicks.y.append(y * 100)
        b.clicks.count.append(1)
    }
    b.images = [.init(png: png.base64EncodedString(), hotX: Int64(spriteHot.0 * 100),
                      hotY: Int64(spriteHot.1 * 100), w: Int64(spriteWidth * 100),
                      h: Int64(spriteHeight * 100), kind: nil)]
    b.imageChanges.t = [0]
    b.imageChanges.id = [0]
    return b
}

if let dir = request["cursor_dir"] as? String {
    let folder = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var problems: [String] = []
    if let png = spritePNG() {
        let spriteURL = folder.appendingPathComponent("sprite.png")
        let cursorURL = folder.appendingPathComponent("cursor.fjcursor")
        let bytes = cursorBody(png: png).encoded()
        do {
            try png.write(to: spriteURL)
            try bytes.write(to: cursorURL)
            _ = try ReelCursor(data: bytes)
        } catch {
            problems.append("the fixture did not write or read back: \(error)")
        }
        var sx = 0.0, sy = 0.0, n = 0.0
        for row in 0..<spriteHeight {
            for col in 0..<spriteWidth where spriteOpaque(col, row) {
                sx += Double(col) + 0.5
                sy += Double(row) + 0.5
                n += 1
            }
        }
        let lifted = InputConversions.liftSDR(SIMD3<Float>(
            Float(spriteColor.0) / 255, Float(spriteColor.1) / 255, Float(spriteColor.2) / 255))
        fixtureAnswer = [
            "sprite": spriteURL.path, "cursor": cursorURL.path,
            "centroid": [sx / n - Double(spriteHot.0), sy / n - Double(spriteHot.1)],
            "color": [Int(spriteColor.0), Int(spriteColor.1), Int(spriteColor.2)],
            "lifted": [Double(lifted.x), Double(lifted.y), Double(lifted.z)],
            "hot": [spriteHot.0, spriteHot.1], "size": [spriteWidth, spriteHeight],
            "moves": (0..<moveCount).map { k -> [Int64] in
                let (x, y) = movePixel(k)
                return [moveMicros(k), x, y]
            },
        ]
    } else {
        problems.append("the sprite PNG could not be made")
    }
    if !problems.isEmpty { fixtureAnswer["problems"] = problems }
}

// ---- L7: the cost, through the compositor and through MetalRenderer --------------

/// Reads `frames` frames of `built` through a composition output, recording each one's
/// compose seconds on `key` (`PlaybackTrials`, the compositor's own measure, a dev tool:
/// nil without `FRAMEJOB_DEV_TOOLS`, which the proof always builds with); the median.
func composeMedian(_ built: BuiltComposition, key: Int, frames: Int) -> Double? {
    #if !FRAMEJOB_DEV_TOOLS
    return nil
    #else
    guard let reader = try? AVAssetReader(asset: built.composition) else { return nil }
    let output = AVAssetReaderVideoCompositionOutput(
        videoTracks: built.composition.tracks(withMediaType: .video),
        videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
    output.videoComposition = built.videoComposition
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    PlaybackTrials.shared.begin(key, digests: false)
    guard reader.startReading() else {
        _ = PlaybackTrials.shared.end(key)
        return nil
    }
    var read = 0
    while read < frames, output.copyNextSampleBuffer() != nil { read += 1 }
    reader.cancelReading()
    let seconds = PlaybackTrials.shared.end(key).prefix(frames).map(\.seconds).sorted()
    guard seconds.count >= frames / 2 else { return nil }
    return seconds[seconds.count / 2]
    #endif
}

if let l7 = request["l7"] as? [String: Any], let movie = l7["movie"] as? String,
   let cursorPath = l7["cursor"] as? String
{
    var problems: [String] = []
    var lines: [String] = []
    let runs = (l7["runs"] as? Int) ?? 3
    let frames = 120
    let limits: [(Int, Int, Double)] = [(1920, 1080, 0.3), (3840, 2160, 1), (5120, 2880, 1)]
    func project(width: Int, height: Int, on: Bool) -> ReelProject? {
        let cursor: [String: Any] = on
            ? ["show": true, "clicks": "ripple"] : ["show": false, "clicks": "none"]
        let json: [String: Any] = [
            "version": 38,
            "canvas": ["width": width, "height": height, "fps": [30, 1]],
            "media": [["id": 1, "path": movie, "kind": "video", "duration": 4 * second,
                       "width": 640, "height": 360, "fps": [30, 1], "has_video": true,
                       "has_audio": false,
                       "cursor": ["path": cursorPath, "in_picture": false]]],
            "tracks": [["id": 2, "name": "Track 1"]],
            "clips": [["id": 3, "track": 2, "start": 0, "duration": 4 * second,
                       "source": ["kind": "media", "media": 1, "in": 0],
                       "video": ["scale": Double(width) / 640, "cursor": cursor]]],
            "next_id": 4,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? ReelProject.from(json: String(decoding: data, as: UTF8.self))
    }
    let urls: [UInt32: URL] = [1: URL(fileURLWithPath: movie)]
    var worst: [String] = []
    for (width, height, limit) in limits {
        var differences: [Double] = []
        var medians: [String] = []
        for _ in 0..<runs {
            var pair: [Double] = []
            for on in [true, false] {
                guard let made = project(width: width, height: height, on: on),
                      let plan = made.plan
                else {
                    problems.append("\(width)×\(height) did not open")
                    break
                }
                let key = RecipeSource.shared.register()
                RecipeSource.shared.set(made, for: key)
                let warned = (try? Exporter.waitForCursors(
                    project: made, key: key, at: nil, options: .none, cancelled: { false })) ?? []
                if !warned.isEmpty { problems.append("the wait warned \(warned)") }
                if let built = try? CompositionBuilder.build(
                    plan: plan, planJSON: made.planJSON, urls: urls, recipeKey: key),
                   let median = composeMedian(built, key: key, frames: frames)
                {
                    pair.append(median)
                } else {
                    problems.append("\(width)×\(height) did not compose")
                }
                RecipeSource.shared.unregister(key)
            }
            if pair.count == 2 {
                differences.append((pair[0] - pair[1]) * 1000)
                medians.append(String(format: "%.3f/%.3f", pair[0] * 1000, pair[1] * 1000))
            }
        }
        let sorted = differences.sorted()
        let middle = sorted.isEmpty ? Double.nan : sorted[sorted.count / 2]
        lines.append("\(width)×\(height): on/off medians ms \(medians.joined(separator: ", ")); "
            + "difference median \(String(format: "%.3f", middle)) ms (limit \(limit))")
        if !(middle <= limit) { worst.append("\(width)×\(height) \(middle) ms") }
    }
    // No texture per frame: a MetalRenderer of the probe's own asks for the 120 frames'
    // sprites through `cursorSprite`, its `uploads` read after the first and after the last.
    var uploads: [Int] = []
    if let made = project(width: 1920, height: 1080, on: true), let renderer = MetalRenderer() {
        let key = RecipeSource.shared.register()
        RecipeSource.shared.set(made, for: key)
        _ = try? Exporter.waitForCursors(
            project: made, key: key, at: nil, options: .none, cancelled: { false })
        let instruction = RecipeInstruction(
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 4, timescale: 1)),
            requiredTrackIDs: [], recipeKey: key, mediaURLs: [:], sourceOrientations: [:],
            missingClips: [])
        var drawn = 0
        for frame in 0..<frames {
            guard let layer = made.recipe(at: Ticks(frame) * 20_000)?.layers.first else { continue }
            var uniforms = LayerUniforms()
            let texture = renderer.cursorSprite(
                for: layer, instruction: instruction, output: .sdr, uniforms: &uniforms)
            if texture !== renderer.placeholder, uniforms.cursorEnabled > 0.5 { drawn += 1 }
            if frame == 0 || frame == frames - 1 { uploads.append(renderer.cursorSprites.uploads) }
        }
        RecipeSource.shared.unregister(key)
        lines.append("cursorSprite drew a sprite at \(drawn) of \(frames) frames; uploads "
            + "after the first and the last: \(uploads)")
        if drawn != frames { problems.append("a sprite at \(drawn) of \(frames) frames") }
    } else {
        problems.append("no MetalRenderer")
    }
    if uploads.count != 2 || uploads[0] != 1 || uploads[1] != 1 {
        problems.append("uploads \(uploads), not [1, 1]")
    }
    if !worst.isEmpty { problems.append("over the limit: " + worst.joined(separator: "; ")) }
    row("L7", problems.isEmpty, (problems + lines).joined(separator: "; "))
}

finish()
