// #339 (spec §11 SR-26): the rate graph's rows R1–R7 for
// `rate_graph_proof.py`, compiled as `main.swift` over `app/Sources` through
// `swift_build.build()`. Prints one JSON object on stdout:
// `{"rows": [{"name", "ok", "detail"}, …]}`, every row's verdict and what it
// read. No network, no app, no document, no defaults written.
//
// The project is made in-process (`ReelProject.new`), one 60 s A/V media with
// no file, five media clips and a text clip on one track (clip time, 5 s
// clips unless said):
//   U  at 0: action [1 s, 3 s) linear {speed: 2}, and an opacity action
//      [3.5 s, 4.5 s) ease_out {video: {opacity: 0.5}}
//   D  at 6 s: action [1 s, 3 s) ease_in {speed: 0.5}
//   C  at 12 s: `set_speed` 2 — a constant clip
//   F  at 18 s: action [1 s, 3 s) linear {speed: 1}, the rate never moving
//   T  at 24 s, 2 s long: action [0, 2 s) linear {speed: 3}, then
//      `trim_end` to 1 s — the action runs past the end
//   X  a text clip at 30 s

import AppKit

let second: Ticks = 600_000
let clipLength: Ticks = 5 * second
var rows: [[String: Any]] = []
var problems: [String] = []

func row(_ name: String, _ ok: Bool, _ detail: String) {
    rows.append(["name": name, "ok": ok, "detail": detail])
}

func emit() -> Never {
    var out: [String: Any] = ["rows": rows]
    if !problems.isEmpty { out["problems"] = problems }
    let answer = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
    print(String(data: answer, encoding: .utf8) ?? "{}")
    exit(0)
}

func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-12) -> Bool {
    abs(a - b) <= tolerance
}

// MARK: - The project

guard var project = ReelProject.new(width: 320, height: 180, fps: .thirty) else {
    problems.append("ReelProject.new answered nil")
    emit()
}
/// Applied or an identity; a refusal or an error is a problem.
func step(_ op: ReelOp) {
    switch try? project.applying(op) {
    case .applied(let next)?: project = next
    case .identity?: break
    case .refused(let why)?: problems.append("\(op.name) refused: \(why.reason)")
    case nil: problems.append("\(op.name) was invalid: \(op.args)")
    }
}
func lastClip() -> UInt32 { project.snapshot.clips.max { $0.id < $1.id }?.id ?? 0 }
func actionIDs(_ clip: UInt32) -> Set<UInt32> {
    Set(project.snapshot.clip(clip)?.actions.map(\.id) ?? [])
}
/// An action at clip time `at` for `duration` along `curve` whose end is `patch`.
@discardableResult
func action(_ clip: UInt32, at: Ticks, duration: Ticks, _ curve: Curve,
            _ patch: [String: Any]) -> UInt32 {
    let before = actionIDs(clip)
    step(.addAction(clip: clip, at: at, duration: duration))
    guard let id = actionIDs(clip).subtracting(before).first else {
        problems.append("no action added on clip \(clip) at \(at)")
        return 0
    }
    step(.setAction(clip: clip, action: id, curve: curve))
    step(.setActionEndRaw(clip: clip, action: id, patch: patch))
    return id
}
step(.addMedia(descriptor: MediaDescriptor(
    path: "/fixtures/rate-graph.mov", kind: .video, duration: 60 * second, width: 320,
    height: 180, fps: .thirty, hasVideo: true, hasAudio: true)))
let media = project.snapshot.media.last?.id ?? 0
let track = project.snapshot.tracks.first?.id ?? 0
if media == 0 || track == 0 {
    problems.append("no media or no track")
    emit()
}
/// A media clip at `at`, `length` long.
func mediaClip(at: Ticks, length: Ticks = clipLength) -> UInt32 {
    step(.addClip(track: track, media: media, at: at))
    let id = lastClip()
    step(.trimEnd(clip: id, to: at + length))
    return id
}


let clipU = mediaClip(at: 0)
let speedU = action(clipU, at: second, duration: 2 * second, .linear, ["speed": 2])
let opacityU = action(
    clipU, at: 7 * second / 2, duration: second, .easeOut, ["video": ["opacity": 0.5]])
let clipD = mediaClip(at: 6 * second)
action(clipD, at: second, duration: 2 * second, .easeIn, ["speed": 0.5])
let clipC = mediaClip(at: 12 * second)
step(.setSpeed(clip: clipC, rate: 2))
let clipF = mediaClip(at: 18 * second)
action(clipF, at: second, duration: 2 * second, .linear, ["speed": 1])
let clipT = mediaClip(at: 24 * second, length: 2 * second)
action(clipT, at: 0, duration: 2 * second, .linear, ["speed": 3])
step(.trimEnd(clip: clipT, to: 25 * second))
step(.addTextClip(track: track, at: 30 * second, duration: second))
let clipX = lastClip()
if !problems.isEmpty { emit() }

func describe(_ rate: [RatePoint]) -> String {
    rate.map { "(\($0.tick), \($0.rate))" }.joined(separator: " ")
}

// MARK: - R1: the decoded rate list

let mapU = project.sourceMap(clipU)
let mapD = project.sourceMap(clipD)
let mapC = project.sourceMap(clipC)
let mapF = project.sourceMap(clipF)
let mapT = project.sourceMap(clipT)

var oracleU: [RatePoint] = [RatePoint(tick: 0, rate: 1)]
for k in Ticks(0)...32 {
    let t = second + 2 * second * k / 32
    oracleU.append(RatePoint(tick: t, rate: 1 + Double(t - second) / Double(2 * second)))
}
oracleU.append(RatePoint(tick: clipLength, rate: 2))
let rateU = mapU?.rate ?? []
row("R1 U's rate is the oracle: (0, 1), 33 samples across [1 s, 3 s] at 1 + (t − 1 s)/2 s, "
    + "(5 s, 2)",
    rateU.count == oracleU.count
        && zip(rateU, oracleU).allSatisfy { $0.tick == $1.tick && close($0.rate, $1.rate) },
    "\(rateU.count) points: \(describe(rateU))")
let middleD = mapD?.rate.first { $0.tick == 2 * second }
row("R1 D's 2 s sample is 0.875", middleD.map { close($0.rate, 0.875) } ?? false,
    "\(String(describing: middleD))")
let lastT = mapT?.rate.last
row("R1 T's last point is (1 s, 2)",
    lastT.map { $0.tick == second && close($0.rate, 2) } ?? false,
    "\(mapT.map { describe($0.rate) } ?? "no map")")

// MARK: - R2: no line where the rate does not move

func xOf(_ rect: CGRect, _ length: Ticks) -> (Ticks) -> CGFloat {
    { rect.minX + rect.width * CGFloat($0) / CGFloat(length) }
}
let rect = CGRect(x: 10, y: 20, width: 200, height: 14)
for (name, map) in [("C (constant ×2)", mapC), ("F (ends at ×1)", mapF),
                    ("a nil map", nil), ("X (text)", project.sourceMap(clipX))] {
    let points = RateGraph.points(map, in: rect, x: xOf(rect, clipLength))
    row("R2 no line for \(name)", points == nil, "\(String(describing: points))")
}

// MARK: - R3, R4: the line's geometry

func near(_ a: CGPoint?, _ b: CGPoint) -> Bool {
    guard let a else { return false }
    return abs(a.x - b.x) <= 1e-9 && abs(a.y - b.y) <= 1e-9
}
let pointsU = RateGraph.points(mapU, in: rect, x: xOf(rect, clipLength))
let atThreeU = pointsU.flatMap { points in
    zip(rateU, points).first { $0.0.tick == 3 * second }?.1
}
let fallingU = pointsU.map { points in
    zip(points, points.dropFirst()).allSatisfy { $1.y <= $0.y }
} ?? false
row("R3 U: first (minX, maxY), 3 s at (minX + 120, minY), last (maxX, minY), y never rising",
    near(pointsU?.first, CGPoint(x: rect.minX, y: rect.maxY))
        && near(atThreeU, CGPoint(x: rect.minX + 120, y: rect.minY))
        && near(pointsU?.last, CGPoint(x: rect.maxX, y: rect.minY)) && fallingU,
    "\(pointsU?.count ?? 0) points; first \(String(describing: pointsU?.first)), 3 s "
        + "\(String(describing: atThreeU)), last \(String(describing: pointsU?.last))")

let pointsD = RateGraph.points(mapD, in: rect, x: xOf(rect, clipLength))
let rateD = mapD?.rate ?? []
let atThreeD = pointsD.flatMap { points in
    zip(rateD, points).first { $0.0.tick == 3 * second }?.1
}
row("R4 D: first y minY (×1 the fastest), 3 s and last at maxY",
    pointsD?.first.map { abs($0.y - rect.minY) <= 1e-9 } ?? false
        && atThreeD.map { abs($0.y - rect.maxY) <= 1e-9 } ?? false
        && pointsD?.last.map { abs($0.y - rect.maxY) <= 1e-9 } ?? false,
    "first \(String(describing: pointsD?.first)), 3 s \(String(describing: atThreeD)), "
        + "last \(String(describing: pointsD?.last))")

// MARK: - R5: the band's curve under the line

let actionsU = project.snapshot.clip(clipU)?.actions ?? []
if let speed = actionsU.first(where: { $0.id == speedU }),
   let opacity = actionsU.first(where: { $0.id == opacityU }) {
    let graphed = RateGraph.bandCurve(speed, graphed: true)
    let plain = RateGraph.bandCurve(speed, graphed: false)
    let other = RateGraph.bandCurve(opacity, graphed: true)
    row("R5 a Speed band under the line strokes no curve", graphed == nil,
        "\(String(describing: graphed))")
    row("R5 a Speed band with no line strokes its curve", plain == .linear,
        "\(String(describing: plain))")
    row("R5 an opacity band under the line strokes its curve", other == .easeOut,
        "\(String(describing: other))")
} else {
    row("R5 U's two actions are read", false, "\(actionsU.map(\.id))")
}

// MARK: - R6: the decode's check

let good = #"{"ramped":true,"map":[[0,0],[100,200]],"rate":[[0,1.0],[100,2.0]]}"#
let firstFive = #"{"ramped":true,"map":[[0,0],[100,200]],"rate":[[5,1.0],[100,2.0]]}"#
let zeroRate = #"{"ramped":true,"map":[[0,0],[100,200]],"rate":[[0,0],[100,2.0]]}"#
let noKey = #"{"ramped":true,"map":[[0,0],[100,200]]}"#
let decoded = SourceMap(json: good)
row("R6 a good list is kept", decoded?.rate.count == 2,
    "\(decoded.map { describe($0.rate) } ?? "nil")")
let five = SourceMap(json: firstFive)
row("R6 a list starting at tick 5: the map kept, rate []",
    five?.points == [[0, 0], [100, 200]] && five?.rate == [],
    "\(String(describing: five))")
let zero = SourceMap(json: zeroRate)
row("R6 a rate of 0: the map kept, rate []",
    zero?.points == [[0, 0], [100, 200]] && zero?.rate == [], "\(String(describing: zero))")
let none = SourceMap(json: noKey)
row("R6 no rate key: the map kept, rate []",
    none?.points == [[0, 0], [100, 200]] && none?.rate == [], "\(String(describing: none))")

// MARK: - R7: the painter

let width = 200, height = 20
let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
if let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    RateGraph.draw(
        [CGPoint(x: 0, y: 10.5), CGPoint(x: 200, y: 10.5)],
        in: CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.current = previous
    if let data = context.data {
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Row 0 of the buffer is the image's top.
        func pixel(_ x: Int, _ y: Int) -> [Double] {
            (0..<4).map { Double(bytes[(y * width + x) * 4 + $0]) / 255 }
        }
        let inside = pixel(150, 10)
        let below = pixel(150, 16)
        row("R7 the white stroke covers row 10 at x 150 (white ≥ 0.8, α ≥ 0.9)",
            inside[0] >= 0.8 && inside[1] >= 0.8 && inside[2] >= 0.8 && inside[3] >= 0.9,
            "rgba \(inside)")
        row("R7 row 16 at x 150 is clear (α 0)", below[3] == 0, "rgba \(below)")
    } else {
        row("R7 the bitmap is readable", false, "no data")
    }
} else {
    row("R7 the bitmap is made", false, "CGContext answered nil")
}

emit()
