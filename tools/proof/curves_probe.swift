// Road map "grading-2", phase G2-3 — the curves' probe (`curves_proof.py`
// builds it through `swift_build.build` and runs it); grading-4 T4-2 (spec §11
// GR-32) adds P12–P19 and amends P7 for the two-row strip; T4-3 (spec §11
// GR-34) adds P20–P21 and amends P10 (a count change inside an action lands on
// the END).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, so every row drives the app's own
// types: `ClipPane`, `VideoPane.curvesSection(_:)`, `CurvesView`,
// `CurveEditorView`, `InspectorBinding`'s ops and `curvesReset`, a
// `ProjectDocument`'s live trio and undo stack, `LayerUniforms.apply(curves:)`,
// `CurveTable`, `CurveTextures`, `ClipSubTab.keyedCount` and the editor's
// Delete validator. The plot's gestures are driven through its `press` /
// `drag` / `release` / `key`, the event handlers' own bodies. Nothing private
// is widened.
//
//   curves_probe <request.json> <answer.json>
//
// `request.json` names `package`, a project the proof saved over MCP with two
// CARD clips whose master curves are [[0,0],[0.5,0.6],[1,1]] and
// [[0,0],[0.5,0.4],[1,1]], `clips`, their ids, `oracle`, 200 seeded
// curves with the proof's own Fritsch–Carlson values at 64 inputs each, and
// `hue_oracle`, 200 seeded hue curves in each hue domain with the proof's own
// periodic values at 66 hues each. One JSON object out: `rows`, each a name,
// ok and detail, the name starting with its P-number.
import AppKit
import Metal

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func parsed(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}

func pts(_ list: [[Double]]) -> [CurvePoint] { list.map { CurvePoint(x: $0[0], y: $0[1]) } }
func pairs(_ list: [CurvePoint]) -> [[Double]] { list.map { [$0.x, $0.y] } }

/// A key-down as the keyboard delivers it.
func keyEvent(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: code)!
}
func function(_ scalar: Int) -> String { String(Character(UnicodeScalar(UInt32(scalar))!)) }
let up = keyEvent(function(NSUpArrowFunctionKey), code: 126, flags: [.numericPad, .function])
let right = keyEvent(function(NSRightArrowFunctionKey), code: 124, flags: [.numericPad, .function])
let shiftRight = keyEvent(
    function(NSRightArrowFunctionKey), code: 124, flags: [.shift, .numericPad, .function])
let backspace = keyEvent("\u{7f}", code: 51)
let escape = keyEvent("\u{1b}", code: 53)

// MARK: - P5 the flag, P6 the spline, P7 the strip, P8 the badge

do {
    var red = LayerUniforms()
    red.apply(curves: ColorCurves(red: pts([[0, 0], [0.5, 0.7], [1, 1]])))
    var identity = LayerUniforms()
    identity.apply(curves: .identity)
    var diagonal = LayerUniforms()
    diagonal.apply(curves: ColorCurves(master: pts([[0, 0], [0.5, 0.5], [1, 1]])))
    check(
        "P5 apply(curves:) sets curvesEnabled 1 for a red curve alone, 0 for the identity and "
            + "for a 3-point diagonal",
        red.curvesEnabled == 1 && identity.curvesEnabled == 0 && diagonal.curvesEnabled == 0
            && red.wheelsEnabled == 0,
        "red \(red.curvesEnabled), identity \(identity.curvesEnabled), diagonal "
            + "\(diagonal.curvesEnabled)")
}

do {
    let oracle = request["oracle"] as? [[String: Any]] ?? []
    var worst = 0.0
    var outside: [String] = []
    for (index, entry) in oracle.enumerated() {
        let points = pts((entry["points"] as? [[Double]]) ?? [])
        let inputs = entry["inputs"] as? [Double] ?? []
        let values = entry["values"] as? [Double] ?? []
        for (x, want) in zip(inputs, values) {
            worst = max(worst, abs(CurveTable.value(points, at: x) - want))
        }
        for k in 0..<max(points.count - 1, 0) {
            let low = min(max(min(points[k].y, points[k + 1].y), 0), 1)
            let high = min(max(max(points[k].y, points[k + 1].y), 0), 1)
            for step in 0...50 {
                let x = points[k].x + (points[k + 1].x - points[k].x) * Double(step) / 50
                let y = CurveTable.value(points, at: x)
                if y < low - 1e-12 || y > high + 1e-12 {
                    outside.append("curve \(index) segment \(k): \(y) outside [\(low), \(high)]")
                    break
                }
            }
        }
    }
    check(
        "P6 CurveTable.value equals the proof's Fritsch–Carlson within 1e-9 on \(oracle.count) "
            + "seeded curves (worst \(worst)) and never leaves a segment's y span",
        oracle.count == 200 && worst <= 1e-9 && outside.isEmpty,
        "worst \(worst); outside \(outside.count): \(outside.prefix(3))")
}

do {
    let master = pts([[0, 0.05], [0.3, 0.2], [0.7, 0.85], [1, 0.95]])
    let red = pts([[0, 0], [0.5, 0.7], [1, 1]])
    let blue = pts([[0, 0.1], [1, 1]])
    let shift = pts([[10, 40], [180, 0], [350, -20]])
    let curves = ColorCurves(master: master, red: red, blue: blue, hueHue: shift)
    if let device = MTLCreateSystemDefaultDevice(), let textures = CurveTextures(device: device) {
        let strip = textures.texture(for: curves)
        let want = CurveTable.strip(curves)
        let n = CurveTable.stripSize
        var got = [Float](repeating: -1, count: want.count)
        if strip.pixelFormat == .rgba32Float, got.count == n * 8 {
            got.withUnsafeMutableBytes { bytes in
                strip.getBytes(bytes.baseAddress!, bytesPerRow: strip.width * 16,
                               from: MTLRegionMake2D(0, 0, strip.width, 2), mipmapLevel: 0)
            }
        }
        // Row 0 is G2-3's composites, computed here from the splines alone;
        // row 1 the hue curves at 360·i/1023 (GR-32).
        var row0 = true
        var row1 = true
        for i in 0..<n where got.count == n * 8 {
            let x = Double(i) / Double(n - 1)
            let m = CurveTable.value(master, at: x)
            let composite: [Float] = [
                Float(CurveTable.value(red, at: m)), Float(m), Float(CurveTable.value(blue, at: m)), 1,
            ]
            if Array(got[(4 * i)..<(4 * i + 4)]) != composite { row0 = false }
            let hue = 360 * Double(i) / Double(n - 1)
            let hues: [Float] = [
                Float(CurveTable.value(shift, at: hue, domain: .hueShift) / 360), 1, 0, 1,
            ]
            if Array(got[(4 * (n + i))..<(4 * (n + i) + 4)]) != hues { row1 = false }
        }
        var holder = [Float](repeating: -1, count: 16)
        let placeholder = textures.placeholder
        if placeholder.pixelFormat == .rgba32Float, placeholder.height == 2 {
            holder.withUnsafeMutableBytes { bytes in
                placeholder.getBytes(bytes.baseAddress!, bytesPerRow: 32,
                                     from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
            }
        }
        let same = textures.texture(for: curves) === strip
        let identity = textures.texture(for: .identity) === placeholder
        check(
            "P7 the strip is rgba32Float \(CurveTable.stripSize)×2 on a 32-bit-filtering device "
                + "and reads back CurveTable.strip exactly, row 0 the composites and row 1 the "
                + "hue curves; the placeholder is the 2×2 identity",
            device.supports32BitFloatFiltering && strip.pixelFormat == .rgba32Float
                && strip.width == CurveTable.stripSize && strip.height == 2 && got == want
                && row0 && row1 && placeholder.width == 2 && placeholder.height == 2
                && holder == [0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1] && same && identity,
            "filtering \(device.supports32BitFloatFiltering), format \(strip.pixelFormat.rawValue), "
                + "\(strip.width)×\(strip.height), equal \(got == want), row 0 \(row0), row 1 "
                + "\(row1), placeholder \(placeholder.width)×\(placeholder.height) \(holder), "
                + "cached \(same), identity → placeholder \(identity)")
    } else {
        check("P7 a Metal device and the strip cache exist", false)
    }
}

// MARK: - P20 the blend form, P21 the blended strip (spec §11 GR-34)

do {
    // The app's own key strategy (`ProjectSnapshot.swift`'s decoder).
    func decoded(_ json: String) -> ColorCurves? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ColorCurves.self, from: Data(json.utf8))
    }
    let tone = decoded(#"""
        {"master": {"from": [[0, 0], [0.5, 0.3], [1, 1]],
                    "to": [[0, 0], [0.2, 0.35], [0.5, 0.6], [0.8, 0.9], [1, 1]], "t": 0.25},
         "red": [[0, 0], [1, 1]], "green": [[0, 0], [1, 1]], "blue": [[0, 0], [1, 1]],
         "hue_hue": [[0, 0], [180, 0]], "hue_sat": [[0, 1], [180, 1]]}
        """#)
    let hue = decoded(#"""
        {"hue_hue": {"from": [[0, 0], [120, 40], [240, 0]],
                     "to": [[0, 0], [60, -30], [120, 0], [200, 30], [300, 0]], "t": 0.5}}
        """#)
    // A blend whose from is the identity is still a blend: both flags read it.
    let neutralFrom = decoded(#"""
        {"red": {"from": [[0, 0], [1, 1]], "to": [[0, 0], [0.5, 0.7], [0.8, 0.9], [1, 1]],
                 "t": 0.5},
         "hue_sat": {"from": [[0, 1], [180, 1]], "to": [[0, 0.5], [120, 1], [240, 0.5]], "t": 2}}
        """#)
    let malformed = decoded(#"""
        {"master": {"from": [[0, 0.2]], "to": [[0, 0], [0.5, 0.6], [1, 1]], "t": 0.5},
         "red": {"from": [[0, 0], [0.5, 0.6], [1, 1]], "t": 0.5},
         "hue_hue": {"from": [[0, 10], [120, 40]], "to": [[0, 0], [90, 20], [180, 0]],
                     "t": "half"}}
        """#)
    func flags(_ curves: ColorCurves?) -> (Float, Float) {
        var u = LayerUniforms()
        if let curves { u.apply(curves: curves) }
        return (u.curvesEnabled, u.hueCurvesEnabled)
    }
    let master = tone?.blends[.master]
    let hueBlend = hue?.blends[.hueHue]
    let clamped = neutralFrom?.blends[.hueSat]?.t
    check(
        "P20 a blended channel decodes as its from points with the blend kept (t 0.25), not "
            + "the identity, curvesEnabled / hueCurvesEnabled 1 (a hue blend, and blends whose "
            + "from is the identity, t clamped to 1); a malformed blend is the identity",
        tone.map { pairs($0.master) } == [[0, 0], [0.5, 0.3], [1, 1]]
            && master.map { pairs($0.from) } == [[0, 0], [0.5, 0.3], [1, 1]]
            && master.map { $0.to.count } == 5 && master?.t == 0.25
            && tone?.blends.count == 1 && tone?.isIdentity == false && flags(tone) == (1, 0)
            && hue.map { pairs($0.hueHue) } == [[0, 0], [120, 40], [240, 0]]
            && hueBlend?.t == 0.5 && hueBlend?.to.count == 5 && flags(hue) == (0, 1)
            && neutralFrom?.blends.count == 2 && clamped == 1 && flags(neutralFrom) == (1, 1)
            && malformed?.isIdentity == true && malformed?.blends.isEmpty == true
            && flags(malformed) == (0, 0),
        "tone \(String(describing: tone)), hue \(String(describing: hue)), neutral from "
            + "\(String(describing: neutralFrom)), malformed \(String(describing: malformed))")
}

do {
    let fromM = pts([[0, 0], [0.5, 0.3], [1, 1]])
    let toM = pts([[0, 0], [0.2, 0.35], [0.5, 0.6], [0.8, 0.9], [1, 1]])
    let fromR = pts([[0, 0.1], [0.6, 0.5], [1, 0.9]])
    let toR = pts([[0, 0], [0.3, 0.5], [0.7, 0.6], [1, 1]])
    let fromH = pts([[0, 0], [120, 40], [240, 0]])
    let toH = pts([[0, 0], [60, -30], [120, 0], [200, 30], [300, 0]])
    let blue = pts([[0, 0.05], [1, 0.95]])
    func blended(_ t: Double) -> ColorCurves {
        ColorCurves(
            master: fromM, red: fromR, blue: blue, hueHue: fromH,
            blends: [
                .master: CurveBlend(from: fromM, to: toM, t: t),
                .red: CurveBlend(from: fromR, to: toR, t: t),
                .hueHue: CurveBlend(from: fromH, to: toH, t: t),
            ])
    }
    let t = 0.25
    let n = CurveTable.stripSize
    let got = CurveTable.strip(blended(t))
    var oracle = [Float](repeating: 1, count: n * 8)
    func mix(_ a: Double, _ b: Double) -> Double { (1 - t) * a + t * b }
    for i in 0..<n {
        let x = Double(i) / Double(n - 1)
        let m = mix(CurveTable.value(fromM, at: x), CurveTable.value(toM, at: x))
        oracle[4 * i] = Float(mix(CurveTable.value(fromR, at: m), CurveTable.value(toR, at: m)))
        oracle[4 * i + 1] = Float(m)
        oracle[4 * i + 2] = Float(CurveTable.value(blue, at: m))
        let h = 360 * Double(i) / Double(n - 1)
        let shift = mix(
            CurveTable.value(fromH, at: h, domain: .hueShift),
            CurveTable.value(toH, at: h, domain: .hueShift))
        oracle[4 * (n + i)] = Float(shift / 360)
        oracle[4 * (n + i) + 1] = 1
        oracle[4 * (n + i) + 2] = 0
    }
    let zero = CurveTable.strip(blended(0))
        == CurveTable.strip(ColorCurves(master: fromM, red: fromR, blue: blue, hueHue: fromH))
    let one = CurveTable.strip(blended(1))
        == CurveTable.strip(ColorCurves(master: toM, red: toR, blue: blue, hueHue: toH))
    let plain = CurveTable.strip(ColorCurves(master: fromM, red: fromR, blue: blue, hueHue: fromH))
    let differ = zip(got, oracle).filter { $0 != $1 }.count
    check(
        "P21 CurveTable.strip of Master, Red and Hue blends at t 0.25 equals the per-texel "
            + "oracle (1 − t)·A + t·B from CurveTable.value of the two lists exactly; t 0 and t 1 "
            + "are the plain strips of from and to exactly",
        got.count == n * 8 && differ == 0 && zero && one && got != plain,
        "\(differ) texels differ; t 0 \(zero), t 1 \(one), differs from from's \(got != plain)")
}

// MARK: - P12 the periodic spline, P13 the flags (spec §11 GR-32)

do {
    let oracle = request["hue_oracle"] as? [[String: Any]] ?? []
    var worst = 0.0
    var through = 0.0
    for entry in oracle {
        let domain: CurveDomain = entry["domain"] as? String == "hue_shift" ? .hueShift : .hueGain
        let points = pts((entry["points"] as? [[Double]]) ?? [])
        let spline = CurveTable.Spline(points, domain: domain)
        let inputs = entry["inputs"] as? [Double] ?? []
        let values = entry["values"] as? [Double] ?? []
        for (x, want) in zip(inputs, values) {
            worst = max(worst, abs(spline.value(at: x) - want))
        }
        for point in points { through = max(through, abs(spline.value(at: point.x) - point.y)) }
    }
    check(
        "P12 CurveTable's periodic spline equals the proof's oracle within 1e-9 on "
            + "\(oracle.count) seeded hue curves (worst \(worst)) and passes through every "
            + "point (worst \(through))",
        oracle.count == 400 && worst <= 1e-9 && through <= 1e-9,
        "worst \(worst), through \(through)")
}

do {
    func flags(_ curves: ColorCurves) -> (Float, Float) {
        var u = LayerUniforms()
        u.apply(curves: curves)
        return (u.curvesEnabled, u.hueCurvesEnabled)
    }
    let hue = flags(ColorCurves(hueHue: pts([[0, 0], [120, 30]])))
    let sat = flags(ColorCurves(hueSat: pts([[0, 1], [120, 0.5]])))
    let tone = flags(ColorCurves(red: pts([[0, 0], [0.5, 0.7], [1, 1]])))
    let both = flags(ColorCurves(red: pts([[0, 0.1], [1, 1]]), hueSat: pts([[0, 0], [9, 1]])))
    let neutral = ColorCurves(
        hueHue: pts([[10, 0], [200, 0], [300, 0]]), hueSat: pts([[0, 1], [90, 1]]))
    let none = flags(neutral)
    let offset = MemoryLayout<LayerUniforms>.offset(of: \LayerUniforms.hueCurvesEnabled) ?? -1
    check(
        "P13 apply(curves:) sets hueCurvesEnabled 1 for a hue curve alone and curvesEnabled for "
            + "a tone curve alone, both for both, neither for hue identities of any x's "
            + "(hueCurvesEnabled at byte 508 of 528)",
        hue == (0, 1) && sat == (0, 1) && tone == (1, 0) && both == (1, 1) && none == (0, 0)
            && neutral.isIdentity && offset == 508
            && MemoryLayout<LayerUniforms>.stride == 528,
        "hue \(hue), sat \(sat), tone \(tone), both \(both), identities \(none), offset "
            + "\(offset)")
}

// MARK: - P14 the ⇧ lock, P15 the readout, P18 the wrap's edges, P19 the labels

/// A plot of its own over `list` on `channel`, 254 pt square; its current
/// list (what a write or commit last sent).
final class Plot {
    let state = CurveEditorState()
    var list: [CurvePoint]
    var writes = 0
    // Strong captures: the probe keeps every plot for its whole run, so a
    // view outliving its `Plot` (P15's) still reads its list.
    lazy var view = CurveEditorView(
        state: state, read: { _ in self.list }, start: { _ in nil },
        write: { self.list = $0; self.writes += 1 }, begin: {}, end: {},
        commit: { self.list = $0; self.writes += 1 })

    init(_ channel: CurveChannel, _ list: [CurvePoint]) {
        self.list = list
        state.channel = channel
        view.frame = NSRect(x: 0, y: 0, width: 254, height: 254)
    }

    /// Press on `point`, drag by each offset in turn, release; the moved
    /// point (index `index`).
    func gesture(_ point: CurvePoint, _ index: Int, by offsets: [(CGFloat, CGFloat)],
                 lock: Bool) -> CurvePoint {
        let at = view.screen(point)
        view.press(at: at)
        for (dx, dy) in offsets {
            view.drag(to: NSPoint(x: at.x + dx, y: at.y + dy), fine: false, lock: lock)
        }
        view.release()
        return list[index]
    }
}

do {
    let start = pts([[0, 0], [0.5, 0.6], [1, 1]])
    let middle = start[1]
    let diagonal = Plot(.master, start).gesture(middle, 1, by: [(30, 20)], lock: true)
    let held = Plot(.master, start).gesture(middle, 1, by: [(30, 5), (30, 60)], lock: true)
    let upright = Plot(.master, start).gesture(middle, 1, by: [(5, 30)], lock: true)
    let short = Plot(.master, start)
    let still = short.gesture(middle, 1, by: [(2, 2)], lock: true)
    let free = Plot(.master, start).gesture(middle, 1, by: [(30, 20)], lock: false)
    check(
        "P14 the ⇧ lock: a diagonal drag keeps y exactly, an axis once picked holds, a mostly "
            + "vertical one keeps x exactly, under 4 pt nothing moves, and without ⇧ both move",
        diagonal.y == middle.y && diagonal.x > middle.x && held.y == middle.y
            && upright.x == middle.x && upright.y > middle.y && still == middle
            && short.writes == 0 && free.x > middle.x && free.y > middle.y,
        "diagonal \(diagonal), held \(held), upright \(upright), short \(still) "
            + "(\(short.writes) writes), free \(free)")
}

do {
    let tone = Plot(.master, pts([[0, 0], [0.5, 0.6], [1, 1]])).view
    let shift = Plot(.hueHue, pts([[0, 0], [90, -12], [180, 0]])).view
    let gain = Plot(.hueSat, pts([[0, 1], [120, 0.8], [240, 1]])).view
    let a = tone.readout(at: tone.screen(CurvePoint(x: 0.5, y: 0.6)))
    let b = shift.readout(at: shift.screen(CurvePoint(x: 90, y: -12)))
    let c = gain.readout(at: gain.screen(CurvePoint(x: 120, y: 0.8)))
    let strip = shift.readout(at: NSPoint(x: 100, y: 8))
    let outside = tone.readout(at: NSPoint(x: 300, y: 100))
    check(
        "P15 the readout reads \"In 0.50 → Out 0.60\", \"Hue 90° → −12°\" and "
            + "\"Hue 120° → ×0.80\" at three points, and nothing over the strip or off the plot",
        a == "In 0.50 → Out 0.60" && b == "Hue 90° → \u{2212}12°" && c == "Hue 120° → ×0.80"
            && strip == nil && outside == nil,
        "\(String(describing: a)), \(String(describing: b)), \(String(describing: c)), strip "
            + "\(String(describing: strip)), outside \(String(describing: outside))")
}

do {
    let plot = Plot(.hueHue, pts([[0, 0], [120, 30], [240, 0]]))
    let last = plot.gesture(CurvePoint(x: 240, y: 0), 2, by: [(400, 0)], lock: false)
    let first = plot.gesture(CurvePoint(x: 0, y: 0), 0, by: [(-400, 0)], lock: false)
    let top = plot.gesture(CurvePoint(x: 120, y: 30), 1, by: [(0, 900)], lock: false)
    let sat = Plot(.hueSat, pts([[0, 1], [180, 1.5]]))
    let ceiling = sat.gesture(CurvePoint(x: 180, y: 1.5), 1, by: [(0, 900)], lock: false)
    check(
        "P18 a hue curve's last point stops at 359.9 and its first at 0 (no crossing the wrap), "
            + "a shift at 180 and a gain at 2",
        last.x == 359.9 && first.x == 0 && top.y == 180 && ceiling.y == 2,
        "last \(last), first \(first), top \(top), gain \(ceiling)")
}

do {
    let state = CurveEditorState()
    let picker = CurveChannelPicker(state: state, curves: { .identity })
    // The picker spans the plot less 3 pt each side: 224 pt at the 230 pt plot.
    picker.frame = NSRect(x: 0, y: 0, width: 230 - 6, height: CurveChannelPicker.height)
    var tight: [String] = []
    var widths: [String] = []
    for (index, channel) in CurveChannel.allCases.enumerated() {
        let width = NSAttributedString(
            string: channel.title,
            attributes: [.font: DS.sans(CurveChannelPicker.labelSize, weight: .semibold)]
        ).size().width
        let cell = picker.cellRect(index).width
        widths.append("\(channel.title) \(String(format: "%.1f", width))/\(cell)")
        if width > cell - 2 { tight.append(channel.title) }
    }
    check(
        "P19 at the 230 pt plot each of the six labels fits its cell less 2 pt at "
            + "\(CurveChannelPicker.labelSize) pt",
        CurveChannel.allCases.count == 6 && tight.isEmpty,
        "\(widths.joined(separator: ", ")); too wide \(tight)")
}

do {
    let json = #"{"video": {"curves": {"master": [[0, 0], [0.5, 0.7], [1, 1]], "red": null}}}"#
    if let end = try? JSONDecoder().decode(ActionPatch.self, from: Data(json.utf8)) {
        let color = ClipSubTab.color.keyedCount(in: end)
        let picture = ClipSubTab.picture.keyedCount(in: end)
        check("P8 keyedCount for {video: {curves: {master, red}}}: Color 1, Picture 0",
              color == 1 && picture == 0, "color \(color), picture \(picture)")
    } else {
        check("P8 the end decodes as an ActionPatch", false, json)
    }
}

// MARK: - The inspector over project P

func master(_ document: ProjectDocument, _ id: UInt32, _ channel: CurveChannel = .master)
    -> [CurvePoint]
{
    document.project.snapshot.clips.first { $0.id == id }?.videoProps.curves.points(channel) ?? []
}

guard let path = request["package"] as? String,
      let clips = (request["clips"] as? [NSNumber])?.map(\.uint32Value), clips.count == 2
else {
    for name in ["P1", "P2", "P3", "P4", "P9", "P10", "P11", "P16", "P17"] {
        check("\(name) the request names the package and two clips", false, "\(request)")
    }
    finish()
}

func finish() -> Never {
    let answer: [String: Any] = ["rows": rows]
    if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
        try? data.write(to: out)
    }
    exit(0)
}

func open() -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        return nil
    }
    return document
}

guard let document = open() else {
    for name in ["P1", "P2", "P3", "P4", "P9", "P10", "P11", "P16", "P17"] {
        check("\(name) project P opens", false)
    }
    finish()
}
let inspector = InspectorViewController()
inspector.document = document
var begins = 0
var updates: [[ReelOp]] = []
var ended: [String] = []
var edits: [(String, [ReelOp])] = []
inspector.onLiveBegin = { begins += 1; document.beginLiveEdit() }
inspector.onLiveUpdate = { ops in updates.append(ops); document.updateLiveEdit(ops) }
inspector.onLiveEnd = { name in ended.append(name); document.endLiveEdit(name) }
inspector.onEdit = { name, ops in edits.append((name, ops)); document.applyEdit(name, ops) }
document.selection = Set(clips)
inspector.binding.invalidate()
let pane = ClipPane(inspector: inspector)
pane.binding.invalidate()
pane.choose(.color)
pane.rebuild()
pane.refresh()
let ids = pane.sections.map(\.id)
let order = Array(ids.drop { $0 != "video.color" }.prefix(4))
let view = pane.sections.first { $0.id == "video.curves" }
    .flatMap { walk($0).compactMap { $0 as? CurvesView }.first }
guard let view else {
    for name in ["P1", "P2", "P3", "P4", "P9", "P10", "P11", "P16", "P17"] {
        check("\(name) the Color tab has a Curves section", false, "sections \(ids)")
    }
    finish()
}
let editor = view.editor
editor.frame = NSRect(x: 0, y: 0, width: 254, height: 254)
spin(0.1)

/// The inspector caught up with the document, as its refresh would.
func settle() {
    spin(0.2)
    inspector.binding.invalidate()
    pane.refresh()
}

func reset() {
    begins = 0
    updates.removeAll()
    ended.removeAll()
    edits.removeAll()
}

let start = clips.map { master(document, $0) }

/// Every op in `ops` is one set_video naming both clips whose patch is exactly
/// `{curves: {channel: list}}`; the list.
func shape(_ ops: [ReelOp], _ channel: CurveChannel) -> [[Double]]? {
    guard ops.count == 1 else { return nil }
    let op = parsed(ops[0])
    let named = ((op["clips"] as? [NSNumber]) ?? []).map(\.uint32Value).sorted()
    let patch = op["patch"] as? [String: Any] ?? [:]
    let curves = patch["curves"] as? [String: Any] ?? [:]
    guard op["op"] as? String == "set_video", named == clips.sorted(),
          Set(patch.keys) == ["curves"], Set(curves.keys) == [channel.rawValue]
    else { return nil }
    return curves[channel.rawValue] as? [[Double]]
}

// MARK: - P1 a press adds a point on the curve, one live gesture

do {
    reset()
    let before = master(document, clips[0])
    let at = editor.screen(CurvePoint(x: 0.25, y: 0.9))
    editor.press(at: at)
    editor.release()
    settle()
    let sent = updates.compactMap { shape($0, .master) }
    let name = document.undoManager?.undoActionName ?? "-"
    let after = clips.map { master(document, $0) }
    let x = sent.first?[1][0] ?? -1
    let onCurve = abs((sent.first?[1][1] ?? -1) - CurveTable.value(before, at: x)) < 1e-12
    document.undoManager?.undo()
    settle()
    let undone = clips.map { master(document, $0) }
    check(
        "P1 a press off the points adds ONE point on the curve at the press's x: one live "
            + "gesture \"Curves\" sending {curves: {master: [4 points]}} to both clips (the "
            + "sections run \(order))",
        begins == 1 && ended == ["Curves"] && updates.count == 1 && sent.count == 1
            && sent[0].count == 4 && abs(x - 0.25) < 0.01 && onCurve && name == "Curves"
            && after.allSatisfy { pairs($0) == sent[0] } && undone == start
            && order == ["video.color", "video.wheels", "video.curves", "video.look"],
        "begins \(begins), ended \(ended), updates \(updates.map { $0.map(\.json) }), undo name "
            + "\(name), after \(after.map(pairs)), undone \(undone.map(pairs)), sections \(ids)")
}

// MARK: - P2 a drag is one step, held between its neighbours and in 0…1

do {
    reset()
    editor.state.clear()
    let middle = editor.screen(master(document, clips[0])[1])
    editor.press(at: middle)
    editor.drag(to: NSPoint(x: middle.x + 60, y: middle.y + 30), fine: false)
    editor.drag(to: NSPoint(x: middle.x + 400, y: middle.y + 400), fine: false)
    editor.release()
    settle()
    let held = master(document, clips[0])
    let name = document.undoManager?.undoActionName ?? "-"
    let steps = updates.count
    let gestures = begins
    document.undoManager?.undo()
    settle()
    let undone = clips.map { master(document, $0) }
    // An end point dragged out of the square stays at its corner.
    reset()
    editor.state.clear()
    editor.press(at: editor.screen(CurvePoint(x: 0, y: 0)))
    editor.drag(to: NSPoint(x: -200, y: -200), fine: false)
    editor.release()
    settle()
    let corner = master(document, clips[0])
    let cornerSteps = updates.count
    check(
        "P2 a drag is ONE step \"Curves\" (\(steps) updates), the point held 0.001 inside its "
            + "right neighbour's x and at y 1, and an end point dragged off the square stays "
            + "at (0, 0)",
        gestures == 1 && held.count == 3
            && abs(held[1].x - (1 - CurveEditorView.minGap)) < 1e-12 && held[1].y == 1
            && name == "Curves" && steps >= 1 && undone == start && corner == start[0]
            && cornerSteps == 0,
        "held \(pairs(held)), undo name \(name), steps \(steps), undone \(undone.map(pairs)), "
            + "corner \(pairs(corner)), corner writes \(cornerSteps)")
}

// MARK: - P3 ⌫ and a double-click delete, one step each; never below two

do {
    reset()
    editor.state.clear()
    let middle = editor.screen(master(document, clips[0])[1])
    editor.press(at: middle)
    editor.release()
    let typed = editor.key(backspace)
    settle()
    let afterKey = clips.map { master(document, $0) }
    let keyEdits = edits.map(\.0)
    document.undoManager?.undo()
    settle()
    edits.removeAll()
    editor.press(at: middle, clickCount: 1)
    editor.release()
    editor.press(at: middle, clickCount: 2)
    settle()
    let afterDouble = clips.map { master(document, $0) }
    let doubleEdits = edits.map(\.0)
    document.undoManager?.undo()
    settle()
    // Two points left: nothing.
    edits.removeAll()
    editor.state.clear()
    editor.state.channel = .red
    pane.refresh()
    editor.press(at: editor.screen(CurvePoint(x: 1, y: 1)))
    editor.release()
    _ = editor.key(backspace)
    editor.press(at: editor.screen(CurvePoint(x: 0, y: 0)), clickCount: 2)
    settle()
    let twoEdits = edits.count
    editor.state.clear()
    editor.state.channel = .master
    pane.refresh()
    check(
        "P3 ⌫ on a selected point and a double-click on one each delete it in ONE step "
            + "\"Curves\"; a 2-point curve deletes nothing",
        typed && keyEdits == ["Curves"] && afterKey.allSatisfy(ColorCurves.isIdentity)
            && doubleEdits == ["Curves"] && afterDouble.allSatisfy(ColorCurves.isIdentity)
            && twoEdits == 0 && clips.map { master(document, $0) } == start,
        "key \(typed) \(keyEdits) → \(afterKey.map(pairs)); double \(doubleEdits) → "
            + "\(afterDouble.map(pairs)); at two points \(twoEdits) edits")
}

// MARK: - P4 the arrows nudge, one step each

do {
    reset()
    editor.state.clear()
    let middle = editor.screen(master(document, clips[0])[1])
    editor.press(at: middle)
    editor.release()
    let upped = editor.key(up)
    settle()
    let first = master(document, clips[0])[1]
    let shifted = editor.key(shiftRight)
    settle()
    let second = master(document, clips[0])[1]
    let names = edits.map(\.0)
    document.undoManager?.undo()
    document.undoManager?.undo()
    settle()
    check(
        "P4 ↑ moves the selected point +0.01 and ⇧→ +0.1, one step \"Curves\" each "
            + "(\(first.x), \(first.y)) → (\(second.x), \(second.y))",
        upped && shifted && names == ["Curves", "Curves"] && first.x == 0.5
            && first.y == start[0][1].y + 0.01 && second.x == 0.5 + 0.1 && second.y == first.y
            && clips.map { master(document, $0) } == start,
        "names \(names), first \(first), second \(second), undone "
            + "\(clips.map { pairs(master(document, $0)) })")
}

// MARK: - P11 an identity channel: a click writes nothing, the point waits on y = x

do {
    reset()
    editor.state.clear()
    editor.state.channel = .green
    pane.refresh()
    let canUndo = document.undoManager?.canUndo ?? false
    let undoName = document.undoManager?.undoActionName ?? "-"
    editor.press(at: editor.screen(CurvePoint(x: 0.3, y: 0.7)))
    editor.release()
    settle()
    let quiet = updates.isEmpty && edits.isEmpty
        && (document.undoManager?.canUndo ?? false) == canUndo
        && (document.undoManager?.undoActionName ?? "-") == undoName
    let waiting = editor.points
    let selected = editor.state.selected
    let x = waiting.count == 3 ? waiting[1].x : -1
    let exact = waiting.count == 3 && waiting[1].y == waiting[1].x
    let upped = editor.key(up)
    settle()
    let sent = edits.count == 1 ? shape(edits[0].1, .green) : nil
    let stored = master(document, clips[0], .green)
    let still = editor.state.selected
    document.undoManager?.undo()
    settle()
    editor.state.clear()
    editor.state.channel = .master
    pane.refresh()
    check(
        "P11 on an identity channel a press and release writes nothing, the added point's y "
            + "is its x bit for bit (x \(x)) and stays selected, and ↑ then writes "
            + "[[0,0],[x, x + 0.01],[1,1]] in one step",
        quiet && exact && selected == 1 && upped && edits.count == 1
            && edits.first?.0 == "Curves"
            && sent == [[0, 0], [x, x + 0.01], [1, 1]] && pairs(stored) == sent! && still == 1,
        "quiet \(quiet), points \(pairs(waiting)), selected \(String(describing: selected)), "
            + "sent \(String(describing: sent)), stored \(pairs(stored)), after "
            + "\(String(describing: still))")
}

// MARK: - P16 the six cells, and a hue channel in the inspector

do {
    reset()
    let titles = CurveChannel.allCases.map(\.title)
    let cells = (0..<CurveChannel.allCases.count).map { view.picker.cellRect($0).width }
    editor.deselect()
    editor.state.channel = .hueHue
    pane.refresh()
    let canUndo = document.undoManager?.canUndo ?? false
    editor.press(at: editor.screen(CurvePoint(x: 100, y: 0)))
    editor.release()
    settle()
    let quiet = updates.isEmpty && edits.isEmpty
        && (document.undoManager?.canUndo ?? false) == canUndo
    reset()
    let point = editor.screen(CurvePoint(x: 100, y: 0))
    editor.press(at: point)
    editor.drag(to: NSPoint(x: point.x, y: point.y + 30), fine: false)
    editor.release()
    settle()
    let sent = updates.last.flatMap { shape($0, .hueHue) }
    let stored = master(document, clips[0], .hueHue)
    let name = document.undoManager?.undoActionName ?? "-"
    let gestures = begins
    let names = ended
    document.undoManager?.undo()
    settle()
    let undone = clips.map { master(document, $0, .hueHue) }
    editor.deselect()
    editor.state.channel = .master
    pane.refresh()
    let middle = sent.flatMap { $0.count == 3 ? $0[1] : nil } ?? []
    check(
        "P16 six equal cells Master · Red · Green · Blue · Hue · Sat; on Hue a press and "
            + "release writes nothing, and a press and drag writes hue_hue in degrees in ONE "
            + "step \"Curves\" (sent \(sent ?? []))",
        titles == ["Master", "Red", "Green", "Blue", "Hue", "Sat"]
            && Set(cells.map { Int($0.rounded()) }).count <= 2 && quiet && gestures == 1
            && names == ["Curves"] && name == "Curves" && middle.count == 2
            && abs(middle[0] - 100) < 1 && middle[1] > 30 && middle[1] < 60
            && pairs(stored) == sent! && undone.allSatisfy(CurveDomain.hueShift.isIdentity),
        "titles \(titles), cells \(cells), quiet \(quiet), begins \(gestures), ended \(names), "
            + "undo \(name), stored \(pairs(stored)), undone \(undone.map(pairs))")
}

// MARK: - P17 the In and Out fields follow the domain

do {
    let fields = walk(view).compactMap { $0 as? CurvePointField }
    func shown(_ field: CurvePointField) -> [OptionFieldControl] {
        field.subviews.compactMap { $0 as? OptionFieldControl }.filter { !$0.isHidden }
    }
    func text(_ field: CurvePointField) -> String {
        shown(field).first.flatMap { walk($0).compactMap { $0 as? NSTextField }.first }?
            .stringValue ?? "-"
    }
    func enter(_ field: CurvePointField, _ value: String) {
        guard let control = shown(field).first,
              let box = walk(control).compactMap({ $0 as? NSTextField }).first
        else { return }
        box.stringValue = value
        _ = control.control(box, textView: NSTextView(),
                            doCommandBy: #selector(NSResponder.insertNewline(_:)))
        settle()
        refreshOptionControls(in: view)
    }
    func pick(_ channel: CurveChannel, _ point: CurvePoint) {
        editor.deselect()
        editor.state.channel = channel
        pane.refresh()
        editor.press(at: editor.screen(point))
        editor.release()
        settle()
        refreshOptionControls(in: view)
    }
    func one() -> Bool { fields.count == 2 && fields.allSatisfy { shown($0).count == 1 } }
    func setup(_ patch: ColorCurvesPatch) {
        document.applyEdit("Setup", [.setVideo(clips: clips, patch: VideoPatch(curves: patch))])
        settle()
    }
    let tone3 = #"^\d\.\d{3}$"#
    pick(.red, CurvePoint(x: 1, y: 1))
    let red = (text(fields.first!), text(fields.last!), one())
    setup(.channel(.hueHue, pts([[0, 0], [120, 30], [240, 0]])))
    pick(.hueHue, CurvePoint(x: 240, y: 0))
    let hueBefore = (text(fields.first!), one())
    enter(fields.first!, "400")
    let hueAfter = (text(fields.first!), master(document, clips[0], .hueHue).last?.x ?? -1)
    setup(.channel(.hueSat, pts([[0, 1], [180, 0.5]])))
    pick(.hueSat, CurvePoint(x: 180, y: 0.5))
    let satBefore = (text(fields.last!), one())
    enter(fields.last!, "3")
    let satAfter = (text(fields.last!), master(document, clips[0], .hueSat).last?.y ?? -1)
    pick(.red, CurvePoint(x: 1, y: 1))
    let back = (text(fields.first!), one())
    editor.deselect()
    editor.state.channel = .master
    pane.refresh()
    setup(ColorCurvesPatch(hueHue: .some(nil), hueSat: .some(nil)))
    check(
        "P17 the fields follow the domain: Red shows 3 decimals; on Hue In shows \"°\" and 400 "
            + "clamps to 359.9; on Sat Out shows \"×\" and 3 clamps to 2; back on Red 3 decimals "
            + "again; exactly one field control visible in each",
        fields.count == 2 && red.0.range(of: tone3, options: .regularExpression) != nil
            && red.1.range(of: tone3, options: .regularExpression) != nil && red.2
            && hueBefore == ("240.0°", true) && hueAfter == ("359.9°", 359.9)
            && satBefore == ("0.50×", true) && satAfter == ("2.00×", 2)
            && back.0.range(of: tone3, options: .regularExpression) != nil && back.1,
        "red \(red), hue \(hueBefore) → \(hueAfter), sat \(satBefore) → \(satAfter), back \(back)")
}

// MARK: - P10 where a write lands inside an action, and Reset there

func opsJSON(_ ops: [ReelOp]) -> [[String: Any]] { ops.map(parsed) }

do {
    let a = clips[0]
    let binding = inspector.binding
    func setup(_ ops: [ReelOp]) { document.applyEdit("Setup", ops); settle() }
    setup([.setVideo(clips: [a], patch: VideoPatch(curves: .reset))])
    setup([.addAction(clip: a, at: 0, duration: ReelTime.perSecond)])
    let action = document.project.snapshot.clips.first { $0.id == a }?.actions.first?.id ?? 0
    let three = pts([[0, 0], [0.5, 0.7], [1, 1]])
    setup([.setActionEnd(clip: a, action: action,
                         patch: ActionPatch(video: VideoPatch(curves: .channel(.master, three))))])
    document.selection = [a]
    document.selectedAction = action
    settle()
    func where_(_ channel: CurveChannel, _ list: [CurvePoint]) -> String {
        let made = opsJSON(binding.ops(video: VideoPatch(curves: .channel(channel, list))))
        return made.map { $0["op"] as? String ?? "?" }.joined(separator: "+")
    }
    let four = pts([[0, 0], [0.3, 0.4], [0.5, 0.7], [1, 1]])
    let a1 = where_(.master, four)
    let a2 = where_(.master, pts([[0, 0], [0.5, 0.9], [1, 1]]))
    let a3 = where_(.master, ColorCurves.identityCurve)
    let a4 = where_(.red, pts([[0, 0], [0.5, 0.6], [1, 1]]))
    let resetA = opsJSON(binding.curvesReset(CurveChannel.allCases))
    let wantA: [String: Any] = ["video": ["curves": ["master": [[0, 0], [1, 1]]]]]
    let gotA = resetA.count == 1 && resetA[0]["op"] as? String == "set_action_end"
        && (resetA[0]["patch"] as? NSDictionary) == (wantA as NSDictionary)
    // Scenario B: the curve on the base only.
    setup([.setActionEndRaw(clip: a, action: action, patch: ["video": ["curves": NSNull()]])])
    setup([.setVideo(clips: [a], patch: VideoPatch(curves: .channel(.red, three)))])
    document.selectedAction = action
    settle()
    let resetB = opsJSON(binding.curvesReset(CurveChannel.allCases))
    let wantB: [String: Any] = ["video": ["curves": ["red": [[0, 0], [1, 1]]]]]
    let gotB = resetB.count == 1 && resetB[0]["op"] as? String == "set_action_end"
        && (resetB[0]["patch"] as? NSDictionary) == (wantB as NSDictionary)
    // All four the identity: nothing.
    setup([.setVideo(clips: [a], patch: VideoPatch(curves: .reset))])
    document.selectedAction = action
    settle()
    let resetNone = binding.curvesReset(CurveChannel.allCases)
    check(
        "P10 inside an action a count change between two curves, the same count, an identity "
            + "new list and an identity edited one all land on the end (GR-34); Reset writes "
            + "the identity curve (not null) to the end for exactly the non-identity channels "
            + "(A: end-only master, B: base-only red) and nothing when all four are identity",
        a1 == "set_action_end" && a2 == "set_action_end" && a3 == "set_action_end"
            && a4 == "set_action_end" && gotA && gotB && resetNone.isEmpty,
        "4 points \(a1), same count \(a2), identity new \(a3), identity edited \(a4); reset A "
            + "\(resetA), B \(resetB), none \(resetNone.map(\.json))")
    document.selectedAction = nil
}

// MARK: - P9 the Delete item is dead while the plot holds a point

do {
    guard let other = open() else {
        check("P9 a second copy of project P opens", false)
        finish()
    }
    other.selection = [clips[0]]
    NSDocumentController.shared.addDocument(other)
    other.makeWindowControllers()
    other.showWindows()
    spin(1.5)
    if let window = other.windowControllers.first?.window,
       let controller = window.contentViewController as? EditorViewController,
       let content = window.contentView
    {
        let state = CurveEditorState()
        let plot = CurveEditorView(
            state: state, read: { _ in pts([[0, 0], [0.5, 0.6], [1, 1]]) }, start: { _ in nil },
            write: { _ in }, begin: {}, end: {}, commit: { _ in })
        plot.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        content.addSubview(plot)
        let action = #selector(EditorViewController.deleteClips(_:))
        let before = controller.validateTimelineAction(action)
        plot.press(at: plot.screen(CurvePoint(x: 0.5, y: 0.6)))
        plot.release()
        let holding = window.firstResponder === plot && plot.holdsDeleteKey
        let during = controller.validateTimelineAction(action)
        _ = plot.key(escape)
        let after = controller.validateTimelineAction(action)
        check(
            "P9 Delete is enabled with a clip selected, disabled while the plot holds a "
                + "selected point, and enabled again after Esc",
            before == true && holding && during == false && after == true
                && state.selected == nil && window.firstResponder !== plot,
            "before \(String(describing: before)), holding \(holding), during "
                + "\(String(describing: during)), after \(String(describing: after))")
        plot.removeFromSuperview()
        other.close()
    } else {
        check("P9 the editor window opens", false)
    }
}

finish()
