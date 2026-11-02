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
// - `cursor_dir`: the drawing rows' fixture written there — `sprite.png`,
//   `cursor.fjcursor` (format v1 through `CursorFileBody`, read back through
//   `ReelCursor`) and CU3b's `cursor_wide.fjcursor` (the same but `movie_size`
//   [1280, 720]) — and answered beside the rows as `fixture` (the paths, the
//   sprite's centroid offset from its hot spot, its colour and that colour's
//   `InputConversions.liftSDR`, the moves).
// - `l7` (`movie`, `cursor`, `runs`): L7, the compositor's own per-frame
//   seconds (`PlaybackTrials`, so `FRAMEJOB_DEV_TOOLS`) over 120 frames read
//   through a composition output, the cursor with ripples against none, at
//   1920×1080, 3840×2160 and 5120×2880; and `CursorSprites.uploads` over 120
//   `cursorSprite` calls on a `MetalRenderer` of its own (the proof puts a
//   `default.metallib` of the tree's shader beside the binary).
//
// CU3b (spec §11 CU-38 (b), (c)):
// - I4, when the request says `i4: true`: the app's own `ClipPane` over a `ProjectDocument` (as
//   `co3_probe.swift` builds them, with no window): `video.cursor` right after `video.cutout`
//   for a clip whose media has `cursor {in_picture: false}`, titled "Cursor", and its checkbox,
//   pressed, commits one "Show Cursor" `set_video` whose patch is exactly `{cursor: {show:
//   false}}`; absent without a cursor and with `in_picture: true`; under a fixed selection, the
//   media's `cursor` set then cleared by `relink_media` with a probe makes the section appear
//   then go, the pane refreshed by the inspector's own rule (rebuilt only when its
//   `structureSignature` changed).
// - I6: `Exporter.cursorWarningSuffix` ("", " 1 cursor warning.", " 2 cursor warnings (hover
//   for details)."), `cursorWarningDetails` (the sentences, one a line; nil for none) and
//   `ExportQueueRowView.toolTip(for:)` of a completed job holding one cursor warning, which
//   ends with its sentence.
//
// CU4 (spec §11 CU-40, CU-41): `cursor_dir` also writes `cursor_idle.fjcursor` (`idleBody`) and
// `cursor_none.fjcursor` (no image), answered as `fixture.idle` and `fixture.none` with the idle
// file's vertices and down clicks. When the request says `cu4: true`:
// - S1 outside an action each Cursor row's control commits one named `set_video {cursor:
//   {<key>: v}}`, and Polish `{smoothing: 0.5, hide_idle: 3}`.
// - S5 with an action selected: Smoothing and Hide when idle a base `set_video` alone with a ⊘
//   gutter, Size 200 an end alone; on a clip with no base cursor the defaults on the base and
//   the end in one step, the recipe's `props.scale` strictly between 1 and 2 mid-action.
// - S7 `CursorSprites.arrow`: one upload per pixel size, the sizes, a fill texel opaque and dark
//   and texel (12, 2) transparent.

import AVFoundation
import AppKit
import Foundation
import ImageIO
import Metal

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
/// one image from t 0. `movieSize` is the header's `movie_size` (CU3b's `cursor_wide.fjcursor`
/// names 1280 × 720, a size the clean movie does not have); `image: .none` is CU4's
/// `cursor_none.fjcursor`, the same moves and clicks with no image at all.
func cursorBody(
    png: Data, movieSize: [Int] = [640, 360], image: CursorImageMode = .currentSystem
) -> CursorFileBody {
    var b = CursorFileBody(
        version: ReelCursor.fileVersion, inPicture: false, source: .display, displayID: 1,
        sourceFrame: [0, 0, 64000, 36000], pointSize: [64000, 36000], pixelsPerPoint: 1,
        contentSize: [640, 360], movieSize: movieSize, anchor: .e2, anchorHostUs: 0,
        cursorImage: image)
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
    guard image == .currentSystem else { return b }
    b.images = [.init(png: png.base64EncodedString(), hotX: Int64(spriteHot.0 * 100),
                      hotY: Int64(spriteHot.1 * 100), w: Int64(spriteWidth * 100),
                      h: Int64(spriteHeight * 100), kind: nil)]
    b.imageChanges.t = [0]
    b.imageChanges.id = [0]
    return b
}

/// CU4's idle zig-zag (`cursor_idle.fjcursor`, S3 and S4): the frame vertices k 0–29 at
/// (60 + 6k, 100 + 8·(k mod 2)), still from k 30 to 104, then k 105–119 at
/// (60 + 6(k − 75), 100 + 8·(k mod 2)); between two vertices of a run, moves every 120th of a
/// second on the line joining them, so no gap inside a run is a hold (CU-21's 25 ms) and the
/// raw path at a frame's time is its vertex. Down clicks at k 9 and 20, ups at k 10 and 21, at
/// their vertices. One image from t 0, as `cursorBody`'s.
let idleRuns = [0...29, 105...119]
let idleDowns = [9, 20]
let idleUps = [10, 21]
func idleVertex(_ k: Int) -> (Double, Double) {
    (Double(60 + 6 * (k >= 105 ? k - 75 : k)), Double(100 + 8 * (k % 2)))
}
func idleBody(png: Data) -> CursorFileBody {
    var b = cursorBody(png: png)
    b.moves = .init()
    b.clicks = .init()
    for run in idleRuns {
        for k in run {
            let steps = k == run.upperBound ? 1 : 4
            for j in 0..<steps {
                let (x0, y0) = idleVertex(k)
                let (x1, y1) = k == run.upperBound ? (x0, y0) : idleVertex(k + 1)
                let f = Double(j) / 4
                b.moves.t.append(Int64(4 * k + j) * 1_000_000 / 120)
                b.moves.x.append(Int64(((x0 + f * (x1 - x0)) * 100).rounded()))
                b.moves.y.append(Int64(((y0 + f * (y1 - y0)) * 100).rounded()))
            }
        }
    }
    for (k, down) in (idleDowns.map { ($0, Int64(1)) } + idleUps.map { ($0, Int64(0)) })
        .sorted(by: { $0.0 < $1.0 })
    {
        let (x, y) = idleVertex(k)
        b.clicks.t.append(Int64(4 * k) * 1_000_000 / 120)
        b.clicks.button.append(0)
        b.clicks.down.append(down)
        b.clicks.x.append(Int64(x * 100))
        b.clicks.y.append(Int64(y * 100))
        b.clicks.count.append(1)
    }
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
        let wide = cursorBody(png: png, movieSize: [1280, 720]).encoded()
        do {
            try png.write(to: spriteURL)
            try bytes.write(to: cursorURL)
            _ = try ReelCursor(data: bytes)
            try wide.write(to: folder.appendingPathComponent("cursor_wide.fjcursor"))
            _ = try ReelCursor(data: wide)
            // CU4: the idle zig-zag and the file with no cursor image.
            let idle = idleBody(png: png).encoded()
            try idle.write(to: folder.appendingPathComponent("cursor_idle.fjcursor"))
            _ = try ReelCursor(data: idle)
            let none = cursorBody(png: png, image: .none).encoded()
            try none.write(to: folder.appendingPathComponent("cursor_none.fjcursor"))
            _ = try ReelCursor(data: none)
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
            "idle": folder.appendingPathComponent("cursor_idle.fjcursor").path,
            "none": folder.appendingPathComponent("cursor_none.fjcursor").path,
            "idle_vertices": (0..<120).map { k -> [Double] in
                let (x, y) = idleVertex(k)
                return [Double(k), x, y]
            },
            "idle_downs": idleDowns,
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

// ---- CU3b: I4 the Cursor section, I6 the cursor warnings ---------------------------------

/// The probe's own document controller, as `co3_probe.swift` makes one, so a `ProjectDocument`
/// opens without the app's.
final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}

/// The app's pieces a `ProjectDocument` and a `ClipPane` need, made once for I4 and CU4's rows.
var appDelegate: AppDelegate?
func prepareApp() {
    guard appDelegate == nil else { return }
    _ = ProbeDocumentController()
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let delegate = AppDelegate()
    delegate.applicationWillFinishLaunching(
        Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
    appDelegate = delegate
}

if request["i4"] as? Bool == true {
    prepareApp()
    var documents: [ProjectDocument] = []
    var kept: [AnyObject] = []
    var sent: [(name: String, ops: [ReelOp])] = []
    let moviePath = "/proof/cu3b/movie.mov"
    func descriptor(_ cursor: MediaCursor?, path: String = moviePath) -> MediaDescriptor {
        MediaDescriptor(
            path: path, kind: .video, duration: 4 * second, width: 640, height: 360,
            fps: .thirty, hasVideo: true, hasAudio: false, cursor: cursor)
    }
    /// A document holding one 640 × 360 video media with `cursor` and one clip of it.
    func makeDocument(_ cursor: MediaCursor?) -> (ProjectDocument, UInt32, UInt32)? {
        let document = ProjectDocument()
        documents.append(document)
        document.performGroupedEdit("Media", [.addMedia(descriptor: descriptor(cursor))])
        guard let media = document.project.snapshot.media.first?.id else { return nil }
        if document.project.snapshot.tracks.isEmpty {
            document.performGroupedEdit("Track", [.addTrack(index: 0)])
        }
        guard let track = document.project.snapshot.tracks.first?.id else { return nil }
        document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
        guard let clip = document.project.snapshot.clips.first?.id else { return nil }
        return (document, media, clip)
    }
    /// A Clip pane on the Picture sub-tab over `document` with `clip` selected and no window;
    /// every commit recorded in `sent` and applied.
    func clipPane(_ document: ProjectDocument, _ clip: UInt32) -> ClipPane {
        let inspector = InspectorViewController()
        inspector.document = document
        inspector.onEdit = { [weak document] name, ops in
            sent.append((name, ops))
            document?.applyEdit(name, ops)
        }
        document.selection = [clip]
        inspector.binding.invalidate()
        let pane = ClipPane(inspector: inspector)
        kept += [inspector, pane]
        pane.binding.invalidate()
        pane.choose(.picture)
        pane.rebuild()
        pane.refresh()
        return pane
    }
    /// The inspector's own rule (`InspectorViewController.refresh`): rebuilt only when the
    /// pane's `structureSignature` changed, refreshed always.
    func inspectorRefresh(_ pane: ClipPane, _ last: inout String) {
        pane.binding.invalidate()
        let signature = pane.structureSignature
        if signature != last {
            last = signature
            pane.rebuild()
        }
        pane.refresh()
    }
    func walkViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walkViews) }

    var problems: [String] = []
    var notes: [String] = []
    let separate = MediaCursor(path: "/proof/cu3b/movie.fjcursor", inPicture: false)
    // The section's place, after Background's slot, for a media with a separate cursor.
    if let (document, _, clip) = makeDocument(separate) {
        let pane = clipPane(document, clip)
        let order = pane.sections.map(\.id)
        let cutout = order.firstIndex(of: "video.cutout")
        let cursor = order.firstIndex(of: "video.cursor")
        notes.append("with a cursor: \(order)")
        if cutout == nil || cursor != cutout.map({ $0 + 1 }) {
            problems.append("video.cursor not right after video.cutout: \(order)")
        }
        let section = pane.sections.first { $0.id == "video.cursor" }
        if section?.title != "Cursor" { problems.append("title \(section?.title ?? "none")") }
        // Its checkbox, pressed: one "Show Cursor" whose patch is exactly {cursor: {show: false}}.
        let check = section.flatMap {
            walkViews($0).lazy.compactMap { $0 as? OptionCheckboxControl }.first
        }
        sent = []
        if let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
            let check
        {
            check.mouseDown(with: event)
        } else {
            problems.append("no checkbox")
        }
        let op = sent.count == 1 && sent[0].ops.count == 1
            ? (try? JSONSerialization.jsonObject(with: Data(sent[0].ops[0].json.utf8)))
                as? [String: Any] ?? [:]
            : [:]
        let patch = op["patch"] as? [String: Any] ?? [:]
        let written = patch["cursor"] as? [String: Any] ?? [:]
        let stored = document.project.snapshot.clip(clip)?.video?.cursor?.show
        notes.append("commits \(sent.map { ($0.name, $0.ops.map(\.json)) }); stored show "
            + "\(String(describing: stored))")
        if !(sent.count == 1 && sent[0].name == "Show Cursor"
            && op["op"] as? String == "set_video" && patch.count == 1 && written.count == 1
            && written["show"] as? Bool == false && stored == false)
        {
            problems.append("the press did not commit one Show Cursor {cursor: {show: false}}")
        }
    } else {
        problems.append("the separate-cursor fixture could not be made")
    }
    // Absent without a cursor, and with one in the picture.
    for (label, cursor) in [
        ("no cursor", nil), ("in_picture: true", MediaCursor(path: "/proof/x.fjcursor", inPicture: true)),
    ] as [(String, MediaCursor?)] {
        guard let (document, _, clip) = makeDocument(cursor) else {
            problems.append("the \(label) fixture could not be made")
            continue
        }
        let order = clipPane(document, clip).sections.map(\.id)
        if order.contains("video.cursor") { problems.append("video.cursor with \(label)") }
        notes.append("\(label): \(order.contains("video.cutout") ? "cutout, " : "")"
            + (order.contains("video.cursor") ? "Cursor" : "no Cursor"))
    }
    // A fixed selection: the media's cursor set, then cleared, through the document by a
    // relink-shaped edit (`relink_media` with a probe), the pane refreshed as the inspector does.
    if let (document, media, clip) = makeDocument(nil) {
        let pane = clipPane(document, clip)
        var last = pane.structureSignature
        var seen: [Bool] = [pane.sections.contains { $0.id == "video.cursor" }]
        for cursor in [separate, nil] as [MediaCursor?] {
            document.performGroupedEdit("Relink Media", [
                .relinkMedia(
                    media: media, path: moviePath, probe: descriptor(cursor))
            ])
            let has = document.project.snapshot.media(media)?.cursor == cursor
            if !has { problems.append("the relink left cursor \(String(describing: document.project.snapshot.media(media)?.cursor))") }
            inspectorRefresh(pane, &last)
            seen.append(pane.sections.contains { $0.id == "video.cursor" })
        }
        notes.append("under a fixed selection, the section shown \(seen)")
        if seen != [false, true, false] {
            problems.append("the section under a fixed selection \(seen), not [false, true, false]")
        }
    } else {
        problems.append("the relink fixture could not be made")
    }
    row("I4", problems.isEmpty, (problems + notes).joined(separator: "; "))
    for document in documents { document.removeTemporaryCacheDirectory() }
}

do {
    var problems: [String] = []
    let one = [ExportCursorWarning(media: 3, path: "/p/a.fjcursor", message: "it is not JSON")]
    let two = one + [ExportCursorWarning(media: 4, path: "/p/b.fjcursor", message: "gone")]
    let suffixes = [
        Exporter.cursorWarningSuffix([]), Exporter.cursorWarningSuffix(one, hover: false),
        Exporter.cursorWarningSuffix(two),
    ]
    let wanted = ["", " 1 cursor warning.", " 2 cursor warnings (hover for details)."]
    if suffixes != wanted { problems.append("suffixes \(suffixes)") }
    let sentence = "The cursor of media 3 is not drawn: it is not JSON."
    let details = Exporter.cursorWarningDetails(two)
    if Exporter.cursorWarningDetails([]) != nil
        || details != sentence + "\nThe cursor of media 4 is not drawn: gone."
    {
        problems.append("details \(String(describing: details))")
    }
    var tip = ""
    if let project = try? ReelProject.from(json: fixtureText),
        let settings = try? ReelExport.settings(project, preset: "h264")
    {
        var job = ExportQueueController.Job(
            id: 1, project: project, urls: [:], reverse: .none, settings: settings,
            destination: URL(fileURLWithPath: "/proof/cu3b/out.mp4"), options: .none,
            graphics: nil)
        job.state = .completed
        job.cursorWarnings = one
        tip = ExportQueueRowView.toolTip(for: job)
        if !tip.hasSuffix("\n" + sentence) { problems.append("the queue row's tooltip \(tip)") }
    } else {
        problems.append("no job could be made")
    }
    row("I6", problems.isEmpty, problems.isEmpty
        ? "suffixes \(suffixes); the details two lines; the queue row's tooltip ends with "
            + "\"\(sentence)\""
        : problems.joined(separator: "; "))
}

// ---- CU4: S1 and S5 the Cursor section's writes, S7 the arrow's textures ----------------------

if request["cu4"] as? Bool == true {
    prepareApp()
    var documents: [ProjectDocument] = []
    var kept: [AnyObject] = []
    var sent: [(name: String, ops: [ReelOp])] = []
    let separate = MediaCursor(path: "/proof/cu4/movie.fjcursor", inPicture: false)
    /// A document with one 640 × 360 media whose cursor is not in the picture and one clip of
    /// it at 0 for 4 s; `cursor` stored on the clip's base when given; an action over [1 s,
    /// 3 s) when `action`.
    func makeDocument(cursor: CursorProps?, action: Bool) -> (ProjectDocument, UInt32, UInt32?)? {
        let document = ProjectDocument()
        documents.append(document)
        document.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
            path: "/proof/cu4/movie.mov", kind: .video, duration: 4 * second, width: 640,
            height: 360, fps: .thirty, hasVideo: true, hasAudio: false, cursor: separate))])
        guard let media = document.project.snapshot.media.first?.id else { return nil }
        if document.project.snapshot.tracks.isEmpty {
            document.performGroupedEdit("Track", [.addTrack(index: 0)])
        }
        guard let track = document.project.snapshot.tracks.first?.id else { return nil }
        document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: 0)])
        guard let clip = document.project.snapshot.clips.first?.id else { return nil }
        if let cursor {
            document.performGroupedEdit(
                "Cursor", [.setVideo(clips: [clip], patch: VideoPatch(cursor: .some(cursor)))])
        }
        var actionID: UInt32?
        if action {
            document.performGroupedEdit(
                "Action", [.addAction(clip: clip, at: second, duration: 2 * second)])
            actionID = document.project.snapshot.clip(clip)?.actions.first?.id
        }
        return (document, clip, actionID)
    }
    /// A Clip pane on the Picture sub-tab over `document`, `clip` selected and `action` with it;
    /// every commit recorded in `sent` and applied.
    func clipPane(_ document: ProjectDocument, _ clip: UInt32, action: UInt32?) -> ClipPane {
        let inspector = InspectorViewController()
        inspector.document = document
        inspector.onEdit = { [weak document] name, ops in
            sent.append((name, ops))
            document?.applyEdit(name, ops)
        }
        inspector.onSelectAction = { [weak document] id in document?.selectAction(id) }
        document.selection = [clip]
        document.selectAction(action)
        inspector.binding.invalidate()
        let pane = ClipPane(inspector: inspector)
        kept += [inspector, pane]
        pane.binding.invalidate()
        pane.choose(.picture)
        pane.rebuild()
        pane.refresh()
        return pane
    }
    func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
    func section(_ pane: ClipPane) -> InspectorSection? {
        pane.sections.first { $0.id == "video.cursor" }
    }
    func labelled(_ pane: ClipPane, _ label: String) -> InspectorRowView? {
        guard let section = section(pane) else { return nil }
        return walk(section).compactMap { $0 as? InspectorRowView }.first { row in
            row.arrangedSubviews.contains { ($0 as? InspectorRowLabel)?.stringValue == label }
        }
    }
    func parsed(_ op: ReelOp) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
    }
    func same(_ a: Any?, _ b: Any) -> Bool {
        guard let a else { return false }
        return (a as AnyObject).isEqual(b)
    }
    func popup(_ pane: ClipPane, _ label: String, _ index: Int) {
        let control = labelled(pane, label).flatMap {
            walk($0).lazy.compactMap { $0 as? OptionPopupControl }.first
        }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = index
        _ = control?.perform(NSSelectorFromString("itemPicked:"), with: item)
    }
    func quick(_ pane: ClipPane, _ label: String, _ index: Int) {
        let control = labelled(pane, label).flatMap {
            walk($0).lazy.compactMap { $0 as? OptionFieldControl }.first
        }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.tag = index
        _ = control?.perform(NSSelectorFromString("quickPicked:"), with: item)
    }
    func gutter(_ pane: ClipPane, _ label: String) -> RowMark? {
        let mark = labelled(pane, label)?.arrangedSubviews.first as? InspectorMarkGutter
        mark?.refresh()
        return mark?.mark
    }
    let click = NSEvent.mouseEvent(
        with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, eventNumber: 0, clickCount: 1, pressure: 1)

    // ---- S1: outside an action, one named step of one `set_video {cursor: {key: v}}` --------
    var s1: [String] = []
    var s1Notes: [String] = []
    if let (document, clip, _) = makeDocument(cursor: nil, action: false) {
        let pane = clipPane(document, clip, action: nil)
        func expect(_ label: String, _ name: String, _ key: String, _ value: Any,
                    _ drive: () -> Void) {
            sent = []
            drive()
            pane.binding.invalidate()
            pane.refresh()
            let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
            let written = (op["patch"] as? [String: Any])?["cursor"] as? [String: Any] ?? [:]
            let ok = sent.count == 1 && sent[0].name == name && op["op"] as? String == "set_video"
                && (op["patch"] as? [String: Any])?.count == 1 && written.count == 1
                && same(written[key], value)
            s1Notes.append("\(label) → \(sent.map { ($0.name, $0.ops.map(\.json)) })")
            if !ok { s1.append("\(label) committed \(sent.map { ($0.name, $0.ops.map(\.json)) })") }
        }
        expect("Size 200", "Cursor Size", "scale", 2.0) { quick(pane, "Size", 3) }
        expect("Arrow", "Cursor Style", "style", "arrow") { popup(pane, "Style", 1) }
        expect("Medium", "Cursor Smoothing", "smoothing", 0.5) { popup(pane, "Smoothing", 2) }
        expect("3 s", "Hide Cursor When Idle", "hide_idle", 3.0) {
            popup(pane, "Hide when idle", 3)
        }
        expect("Never", "Hide Cursor When Idle", "hide_idle", NSNull()) {
            popup(pane, "Hide when idle", 0)
        }
        expect("Ripple", "Cursor Clicks", "clicks", "ripple") { popup(pane, "Clicks", 1) }
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let css = GraphicSchemaRows.css(red.rgbaComponents)
        expect("a colour", "Ripple Color", "click_color", css) {
            let swatch = labelled(pane, "Ripple color").flatMap {
                walk($0).lazy.compactMap { $0 as? OptionSwatchControl }.first
            }
            guard let swatch, let click else { return }
            swatch.mouseDown(with: click)
            let panel = NSColorPanel.shared
            // The swatch bound the shared panel to its relay; a pick is the panel's action.
            panel.color = red
            if sent.isEmpty {
                NSApp.sendAction(NSSelectorFromString("colorChanged:"), to: panel.value(
                    forKey: "target"), from: panel)
            }
            panel.orderOut(nil)
        }
        expect("Ripple size 150", "Ripple Size", "click_size", 1.5) {
            quick(pane, "Ripple size", 2)
        }
        // Polish: one step, its two keys.
        sent = []
        // The row holding a button (the section header's own buttons are not in a row).
        let button = section(pane).flatMap { s in
            walk(s).compactMap { $0 as? InspectorRowView }.lazy.compactMap { row in
                row.arrangedSubviews.lazy.compactMap { $0 as? OptionButtonControl }.first
            }.first
        }
        if let click { button?.mouseDown(with: click) }
        let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
        let written = (op["patch"] as? [String: Any])?["cursor"] as? [String: Any] ?? [:]
        s1Notes.append("Polish → \(sent.map { ($0.name, $0.ops.map(\.json)) })")
        if !(sent.count == 1 && sent[0].name == "Polish Cursor"
            && op["op"] as? String == "set_video" && written.count == 2
            && same(written["smoothing"], 0.5) && same(written["hide_idle"], 3.0))
        {
            s1.append("Polish committed \(sent.map { ($0.name, $0.ops.map(\.json)) })")
        }
        let stored = document.project.snapshot.clip(clip)?.video?.cursor
        let want = CursorProps(
            scale: 2, style: .arrow, smoothing: 0.5, hideIdle: 3, clicks: .ripple,
            clickColor: css, clickSize: 1.5)
        if stored != want { s1.append("stored \(String(describing: stored)), not \(want)") }
    } else {
        s1.append("the fixture could not be made")
    }
    row("S1", s1.isEmpty, (s1 + s1Notes).joined(separator: "; "))

    // ---- S5: with an action selected ---------------------------------------------------------
    var s5: [String] = []
    var s5Notes: [String] = []
    if let (document, clip, action) = makeDocument(cursor: CursorProps(), action: true),
       let action
    {
        let pane = clipPane(document, clip, action: action)
        let picks: [(String, Int, String, Any)] = [
            ("Smoothing", 3, "smoothing", 1.0), ("Hide when idle", 2, "hide_idle", 2.0),
        ]
        for (label, index, key, value) in picks {
            sent = []
            popup(pane, label, index)
            let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
            let written = (op["patch"] as? [String: Any])?["cursor"] as? [String: Any] ?? [:]
            s5Notes.append("\(label) → \(sent.map { $0.ops.map(\.json) })")
            if !(op["op"] as? String == "set_video" && written.count == 1
                && same(written[key], value))
            {
                s5.append("\(label) committed \(sent.map { $0.ops.map(\.json) })")
            }
            pane.binding.invalidate()
            pane.refresh()
            let mark = gutter(pane, label)
            if mark != .notAnimatable { s5.append("\(label)'s gutter \(String(describing: mark))") }
        }
        sent = []
        quick(pane, "Size", 3)
        let op = sent.count == 1 && sent[0].ops.count == 1 ? parsed(sent[0].ops[0]) : [:]
        s5Notes.append("Size 200 → \(sent.map { $0.ops.map(\.json) })")
        if !(op["op"] as? String == "set_action_end"
            && same(op["patch"], ["video": ["cursor": ["scale": 2.0]]]))
        {
            s5.append("Size 200 committed \(sent.map { $0.ops.map(\.json) })")
        }
    } else {
        s5.append("the base-cursor fixture could not be made")
    }
    if let (document, clip, action) = makeDocument(cursor: nil, action: true), let action {
        let pane = clipPane(document, clip, action: action)
        sent = []
        quick(pane, "Size", 3)
        let ops = sent.count == 1 ? sent[0].ops.map(parsed) : []
        s5Notes.append("no base cursor, Size 200 → \(sent.map { $0.ops.map(\.json) })")
        let base = ops.first.flatMap { ($0["patch"] as? [String: Any])?["cursor"] as? [String: Any] }
        let defaults = CursorProps().dictionary
        if !(ops.count == 2 && ops[0]["op"] as? String == "set_video"
            && (base.map { ($0 as NSDictionary).isEqual(to: defaults) } ?? false)
            && ops[1]["op"] as? String == "set_action_end"
            && same(ops[1]["patch"], ["video": ["cursor": ["scale": 2.0]]]))
        {
            s5.append("no base cursor: Size 200 committed \(sent.map { $0.ops.map(\.json) })")
        }
        let mid = document.project.recipe(at: 2 * second)?.layers.first?.cursor?.props.scale
        s5Notes.append("props.scale mid-action \(String(describing: mid))")
        if !(mid.map { $0 > 1 && $0 < 2 } ?? false) {
            s5.append("props.scale mid-action \(String(describing: mid)), not strictly in (1, 2)")
        }
    } else {
        s5.append("the no-cursor fixture could not be made")
    }
    row("S5", s5.isEmpty, (s5 + s5Notes).joined(separator: "; "))
    for document in documents { document.removeTemporaryCacheDirectory() }

    // ---- S7: CursorSprites.arrow, one texture per pixel size -------------------------------
    var s7: [String] = []
    var s7Notes: [String] = []
    if let renderer = MetalRenderer() {
        let sprites = renderer.cursorSprites
        let before = sprites.uploads
        let first = sprites.arrow(width: 14, height: 21, output: .sdr, lift: { $0 })
        let again = sprites.arrow(width: 14, height: 21, output: .sdr, lift: { $0 })
        let afterSame = sprites.uploads
        let double = sprites.arrow(width: 28, height: 42, output: .sdr, lift: { $0 })
        let afterDouble = sprites.uploads
        s7Notes.append("uploads \(before) → \(afterSame) after 14×21 twice → \(afterDouble) after 28×42")
        if afterSame != before + 1 || afterDouble != before + 2 {
            s7.append("uploads \([before, afterSame, afterDouble])")
        }
        if first == nil || first !== again { s7.append("14×21 asked twice was not one texture") }
        let sizes = [first, double].map { t in t.map { [$0.width, $0.height] } ?? [] }
        s7Notes.append("sizes \(sizes)")
        if sizes != [[14, 21], [28, 42]] { s7.append("sizes \(sizes)") }
        func texel(_ texture: MTLTexture?, _ x: Int, _ y: Int) -> [UInt8] {
            guard let texture else { return [] }
            var bytes = [UInt8](repeating: 0, count: 4)
            texture.getBytes(
                &bytes, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
            return bytes
        }
        let fill = texel(first, 3, 10)
        let outside = texel(first, 12, 2)
        s7Notes.append("texel (3, 10) BGRA \(fill), (12, 2) \(outside)")
        if !(fill.count == 4 && fill[3] == 255 && fill[0] < 40 && fill[1] < 40 && fill[2] < 40) {
            s7.append("the fill texel (3, 10) is \(fill), not opaque and dark")
        }
        if !(outside.count == 4 && outside[3] == 0) {
            s7.append("texel (12, 2) is \(outside), not transparent")
        }
    } else {
        s7.append("no MetalRenderer")
    }
    row("S7", s7.isEmpty, (s7 + s7Notes).joined(separator: "; "))
}

finish()
