// kpgalligan/reelcut#171 — the inspector's name field is the inspector's value
// field (spec §11 SH-3); the probe (`name_field_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS`
// included (N8 and N9 ask `UISnapshotLayout`). Everything it calls exists in the
// baseline tree too, so the proof's `--baseline` builds the same source.
//
//   name_field_probe <light|dark> <fonts dir> <out dir>
//
// `NSApp.appearance` is set before any view is built. In a flipped host in
// an offscreen window: an `InspectorNameField` reading "HHHH" at 170 ×
// `DS.controlHeight` (its own height constraint), a header-configured one
// (`DS.sans(12, weight: .semibold)`, its height constraint re-pinned to 20 pt
// as `ClipSelectionHeaderView.installNameField` does), and an
// `OptionFieldControl` beside them. The host is captured by `cacheDisplay` at
// the window's backing scale into PNGs in `<out dir>` (rest, taller, header
// taller, editing, editing taller). INK is a pixel inside a field (1 pt in
// from its edge) more than 60 away, on some channel, from the field's own
// fill sampled 3 pt in from its right edge; "HHHH" has no descender, so the
// ink rows' extent is the cap height.
//
// One JSON object on `<out dir>/answer-<look>.json`: `rows` (name, ok,
// detail), rewritten after every row.
import AppKit

let arguments = CommandLine.arguments
let look = arguments.count > 1 ? arguments[1] : "light"
let fonts = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "/nonexistent")
let outDir = URL(fileURLWithPath: arguments.count > 3 ? arguments[3] : ".")
let answer = outDir.appendingPathComponent("answer-\(look).json")

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)

for name in (try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
}

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": "\(name) [\(look)]", "ok": ok, "detail": String(detail.prefix(1200))])
    if let data = try? JSONSerialization.data(
        withJSONObject: ["rows": rows], options: [.prettyPrinted, .sortedKeys])
    {
        try? data.write(to: answer)
    }
}

func spin(_ seconds: Double = 0.1) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// Flipped, and painted in the window's background so every captured pixel
/// is opaque, as it is over the inspector.
final class FlippedHost: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

/// The view's own height constraints — not the one Auto Layout makes of its
/// intrinsic size (`NSContentSizeLayoutConstraint`), which appears in
/// `constraints` once the field has been laid out in a window.
func heightConstraints(_ view: NSView) -> [NSLayoutConstraint] {
    view.constraints.filter {
        $0.firstItem === view && $0.firstAttribute == .height
            && !String(describing: type(of: $0)).contains("ContentSize")
    }
}

// MARK: - The views

let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
let window = NSWindow(
    contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = host

let field = InspectorNameField(
    read: { "HHHH" }, write: { _ in }, enabled: { true }, onEdit: {})
let header = InspectorNameField(
    read: { "HHHH" }, write: { _ in }, enabled: { true }, onEdit: {})
header.font = DS.sans(12, weight: .semibold)
for constraint in heightConstraints(header) { constraint.constant = 20 }
let number = OptionFieldControl(
    width: 80, unit: " px", decimals: 0, min: 0, max: 100,
    read: { 24 }, write: { _ in }, enabled: { true }, onEdit: {})

for view in [field, header, number] as [NSView] {
    view.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(view)
}
NSLayoutConstraint.activate([
    field.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
    field.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
    field.widthAnchor.constraint(equalToConstant: 170),
    number.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 20),
    number.topAnchor.constraint(equalTo: host.topAnchor, constant: 20),
    header.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
    header.topAnchor.constraint(equalTo: host.topAnchor, constant: 100),
    header.widthAnchor.constraint(equalToConstant: 170),
])
field.refresh()
header.refresh()
number.refresh()

// MARK: - Capture and ink

struct Capture {
    let rep: NSBitmapImageRep
    let scale: CGFloat

    func pixel(_ x: Int, _ y: Int) -> [Int] {
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
              let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        else { return [-1, -1, -1] }
        return [color.redComponent, color.greenComponent, color.blueComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    /// The pixel at a point in the host's (flipped) coordinates.
    func at(_ point: NSPoint) -> [Int] {
        pixel(Int(point.x * scale), Int(point.y * scale))
    }
}

func capture(_ tag: String) -> Capture? {
    host.layoutSubtreeIfNeeded()
    host.display()
    spin(0.05)
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: outDir.appendingPathComponent("name-field-\(look)-\(tag).png"))
    }
    return Capture(rep: rep, scale: CGFloat(rep.pixelsWide) / host.bounds.width)
}

func far(_ a: [Int], _ b: [Int], _ limit: Int = 60) -> Bool {
    zip(a, b).contains { abs($0 - $1) > limit }
}

/// The ink's extent inside `view`: top, bottom and left edges in points of
/// the host, the rows' centre, or nil when there is none. `columns` narrows
/// it to that many points from the first ink column (the first glyph, clear
/// of a caret at the end).
struct Ink {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    var centre: CGFloat { (top + bottom) / 2 }
}

func ink(in view: NSView, _ shot: Capture, columns: CGFloat? = nil) -> Ink? {
    let frame = view.frame
    let fill = shot.at(NSPoint(x: frame.maxX - 3, y: frame.midY))
    let scale = shot.scale
    let x0 = Int(((frame.minX + 1) * scale).rounded(.up))
    let x1 = Int(((frame.maxX - 1) * scale).rounded(.down))
    let y0 = Int(((frame.minY + 1) * scale).rounded(.up))
    let y1 = Int(((frame.maxY - 1) * scale).rounded(.down))
    var left: Int?
    for x in x0..<x1 {
        if (y0..<y1).contains(where: { far(shot.pixel(x, $0), fill) }) {
            left = x
            break
        }
    }
    guard let first = left else { return nil }
    let last = columns.map { min(x1, first + Int($0 * scale)) } ?? x1
    var top: Int?
    var bottom: Int?
    for y in y0..<y1 where (first..<last).contains(where: { far(shot.pixel($0, y), fill) }) {
        if top == nil { top = y }
        bottom = y + 1
    }
    guard let t = top, let b = bottom else { return nil }
    return Ink(top: CGFloat(t) / scale, bottom: CGFloat(b) / scale, left: CGFloat(first) / scale)
}

func describe(_ value: Ink?) -> String {
    guard let value else { return "no ink" }
    return String(format: "ink rows %.2f–%.2f (centre %.2f), from x %.2f",
                  value.top, value.bottom, value.centre, value.left)
}

// MARK: - The rows

spin(0.2)
guard let rest = capture("rest") else {
    check("N0 the host captures", false)
    exit(0)
}

// N1 — the box: border and interior pixels, the name field's against the
// number field's, at the same offsets from each box's edges.
do {
    let a = field.frame
    let b = number.frame
    let samples: [(String, NSPoint, NSPoint)] = [
        ("left border", NSPoint(x: a.minX + 0.25, y: a.midY), NSPoint(x: b.minX + 0.25, y: b.midY)),
        ("top border", NSPoint(x: a.maxX - 3, y: a.minY + 0.25),
         NSPoint(x: b.maxX - 3, y: b.minY + 0.25)),
        ("bottom border", NSPoint(x: a.maxX - 3, y: a.maxY - 0.25),
         NSPoint(x: b.maxX - 3, y: b.maxY - 0.25)),
        ("interior", NSPoint(x: a.maxX - 3, y: a.midY), NSPoint(x: b.maxX - 3, y: b.midY)),
        ("interior, top", NSPoint(x: a.maxX - 3, y: a.minY + 2),
         NSPoint(x: b.maxX - 3, y: b.minY + 2)),
    ]
    var worst = 0
    var notes: [String] = []
    for (label, p, q) in samples {
        let x = rest.at(p)
        let y = rest.at(q)
        let off = zip(x, y).map { abs($0 - $1) }.max() ?? 999
        worst = max(worst, off)
        notes.append("\(label) \(x) vs \(y)")
    }
    check("N1 the name field's border and interior pixels are the number field's, within 2",
          worst <= 2, "worst \(worst); " + notes.joined(separator: "; "))
}

// N2 — the cap ink's centre is the field's centre.
let restInk = ink(in: field, rest)
do {
    let off = restInk.map { abs($0.centre - field.frame.midY) } ?? .infinity
    check("N2 the cap ink's vertical centre is within 1 pt of the field's",
          off <= 1, describe(restInk) + String(format: "; field centre %.2f, off %.2f",
                                                field.frame.midY, off))
}

/// Grows `view`'s own height constraint by 20 pt, captures, and answers how
/// far the ink's centre moved; the constraint is put back.
func grown(_ view: NSView, tag: String, before: Ink?, columns: CGFloat? = nil)
    -> (moved: CGFloat, detail: String)
{
    let own = heightConstraints(view)
    guard let constraint = own.first else { return (.infinity, "no height constraint") }
    let height = constraint.constant
    constraint.constant = height + 20
    defer {
        constraint.constant = height
        host.layoutSubtreeIfNeeded()
    }
    guard let shot = capture(tag) else { return (.infinity, "no capture") }
    let after = ink(in: view, shot, columns: columns)
    guard let b = before, let a = after else {
        return (.infinity, describe(before) + " → " + describe(after))
    }
    return (a.centre - b.centre, String(format: "height %.0f → %.0f: ", height, height + 20)
                + describe(b) + " → " + describe(a))
}

// N3 — 20 pt taller, the ink moves down 10.
do {
    let (moved, detail) = grown(field, tag: "taller", before: restInk)
    check("N3 the name field 20 pt taller: the ink moves by 10 ± 0.5 pt",
          abs(moved - 10) <= 0.5, String(format: "moved %.2f; ", moved) + detail)
}

// N4 — the same for the header's field.
do {
    let before = ink(in: header, rest)
    let (moved, detail) = grown(header, tag: "header-taller", before: before)
    check("N4 the header's field (12 semibold, 20 pt) 20 pt taller: the ink moves by 10 ± 0.5 pt",
          abs(moved - 10) <= 0.5, String(format: "moved %.2f; ", moved) + detail)
}

// N5 — N2 and N3 with the field editor attached, the caret at the end.
do {
    let took = window.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(location: 4, length: 0)
    spin(0.1)
    let editing = field.currentEditor() != nil
    let shot = capture("editing")
    let glyph: CGFloat = 5
    let before = shot.flatMap { ink(in: field, $0, columns: glyph) }
    let off = before.map { abs($0.centre - field.frame.midY) } ?? .infinity
    let (moved, detail) = grown(field, tag: "editing-taller", before: before, columns: glyph)
    check("N5 with the field editor attached: the first glyph's centre is within 1 pt of the "
            + "field's, and 20 pt taller moves it by 10 ± 0.5 pt",
          took && editing && off <= 1 && abs(moved - 10) <= 0.5,
          "first responder \(took), editor \(editing); "
            + String(format: "off %.2f, moved %.2f; ", off, moved) + detail)
    window.makeFirstResponder(nil)
    spin(0.1)
}

// N6 — the text starts inside the padding.
do {
    let left = restInk.map { $0.left - field.frame.minX } ?? -1
    check("N6 the ink starts 7–11 pt from the field's left edge",
          left >= 7 && left <= 11, String(format: "%.2f pt", left))
}

// N7 — one height constraint of its own.
do {
    let own = heightConstraints(field).map(\.constant)
    check("N7 the name field has exactly one height constraint of its own, DS.controlHeight",
          own == [DS.controlHeight], "\(own)")
}

// N8 (control) and N9 — the layout dump's truncation rule over the host. The
// field is read NOT editable, as a dimmed row's is (`refresh`): an editable
// `NSTextField` reports no intrinsic width, so the rule never reaches it. N9
// is not a control: the rule skips a field whose cell WRAPS, and a field that
// is not single-line wraps.
func kinds(_ problems: [[String: Any]]) -> String {
    let names: [String] = problems.map { ($0["kind"] as? String) ?? "?" }
    return "[" + names.joined(separator: ", ") + "]"
}

do {
    field.isEditable = false
    field.stringValue = "Director of Photography"
    host.layoutSubtreeIfNeeded()
    let cleanReport = UISnapshotLayout.report(root: host, skipping: nil)
    let clean: [[String: Any]] = cleanReport["problems"] as? [[String: Any]] ?? [["kind": "none"]]
    let cleanWidth = String(format: "intrinsic %.1f in %.1f",
                            field.intrinsicContentSize.width, field.frame.width)
    check("N8 the layout dump finds no problem with \"Director of Photography\" (a CONTROL)",
          clean.isEmpty, "problems " + kinds(clean) + "; " + cleanWidth)
    field.stringValue = "Director of Photography and Second Unit Camera Operator, Nights"
    host.layoutSubtreeIfNeeded()
    let longReport = UISnapshotLayout.report(root: host, skipping: nil)
    let long: [[String: Any]] = longReport["problems"] as? [[String: Any]] ?? []
    let truncated = long.filter { ($0["kind"] as? String) == "truncated" }
    let longWidth = String(format: "intrinsic %.1f in %.1f",
                           field.intrinsicContentSize.width, field.frame.width)
    let wraps = field.cell?.wraps == true ? "wraps" : "does not wrap"
    let single = field.usesSingleLineMode ? "single-line" : "not single-line"
    check("N9 the layout dump finds a name wider than the field truncated",
          truncated.count == 1,
          "problems " + kinds(long) + "; " + longWidth + "; the cell " + wraps + ", " + single)
    field.stringValue = "HHHH"
    field.isEditable = true
}

exit(0)
