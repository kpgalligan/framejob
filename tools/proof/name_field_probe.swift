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
// After N9 (B32, #186 item 4), an `OptionFieldControl` with the number
// field's arguments joins the host at leading 20, top 60 (`below`, N13),
// captured as b32-rest.
//
// After N13 (B50, #199), two more `InspectorNameField`s join the host at
// leading 220, width 170, placeholder "Marker": `empty` reading "" at top 100
// and `named` reading "Director of Photography" at top 140, captured as
// b50-rest, b50-editing, b50-typed, b50-deleted and b50-cleared. PLACEHOLDER
// INK is a pixel more than 20 away, on some channel, from the field's sampled
// fill (`placeholderTextColor` is 25 % ink, which the 60 cannot see in dark).
// N19 and N20 run last, with the window ordered in, and order it out again;
// they read the field's layer's `needsDisplay()`.
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

// B32 (#186 item 4): a number field under the name field, for N13.
let below = OptionFieldControl(
    width: 80, unit: " px", decimals: 0, min: 0, max: 100,
    read: { 24 }, write: { _ in }, enabled: { true }, onEdit: {})
below.translatesAutoresizingMaskIntoConstraints = false
host.addSubview(below)
NSLayoutConstraint.activate([
    below.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 20),
    below.topAnchor.constraint(equalTo: host.topAnchor, constant: 60),
])
below.refresh()
spin(0.1)
let b32Rest = capture("b32-rest")

// N13 — the name field's box starts where a number field's does under the
// same leading constraint.
do {
    func column(_ view: NSView) -> CGFloat? {
        guard let shot = b32Rest else { return nil }
        let y = Int(view.frame.midY * shot.scale)
        let background = shot.pixel(Int(5 * shot.scale), y)
        let start = Int(12 * shot.scale)
        let end = Int(view.frame.maxX * shot.scale)
        guard start < end else { return nil }
        for x in start..<end where far(shot.pixel(x, y), background, 6) {
            return CGFloat(x) / shot.scale
        }
        return nil
    }
    let a = column(field)
    let b = column(below)
    var ok = false
    if let a, let b { ok = abs(a - b) <= 0.5 }
    check("N13 the name field's box starts where a number field's box under the same leading "
            + "constraint starts, within 0.5 pt", ok,
          String(format: "name field's box from x %.2f, number field's from x %.2f; ",
                 a ?? -1, b ?? -1)
            + "field.frame \(field.frame), alignmentRect \(field.alignmentRect(forFrame: field.frame))")
}

// MARK: - B50 (#199): the placeholder on its resting rows while editing

/// The placeholder ink's extent inside `view`: top, bottom, left and right
/// edges in points of the host, inside the x window `from`–`to` (default
/// 1 pt in from the view's edges) and 1 pt in from its top and bottom, and
/// the peak channel distance from the fill; nil when there is none.
struct Edges {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat
    let peak: Int
}

func placeholderInk(in view: NSView, _ shot: Capture, from: CGFloat? = nil, to: CGFloat? = nil)
    -> Edges?
{
    let frame = view.frame
    let fill = shot.at(NSPoint(x: frame.maxX - 3, y: frame.midY))
    let scale = shot.scale
    let x0 = Int(((from ?? frame.minX + 1) * scale).rounded(.up))
    let x1 = Int(((to ?? frame.maxX - 1) * scale).rounded(.down))
    let y0 = Int(((frame.minY + 1) * scale).rounded(.up))
    let y1 = Int(((frame.maxY - 1) * scale).rounded(.down))
    guard x0 < x1, y0 < y1 else { return nil }
    var top: Int?
    var bottom = 0
    var left = Int.max
    var right = Int.min
    var peak = 0
    for y in y0..<y1 {
        for x in x0..<x1 {
            let pixel = shot.pixel(x, y)
            guard far(pixel, fill, 20) else { continue }
            if top == nil { top = y }
            bottom = y + 1
            left = min(left, x)
            right = max(right, x + 1)
            peak = max(peak, zip(pixel, fill).map { abs($0 - $1) }.max() ?? 0)
        }
    }
    guard let t = top else { return nil }
    return Edges(top: CGFloat(t) / scale, bottom: CGFloat(bottom) / scale,
                 left: CGFloat(left) / scale, right: CGFloat(right) / scale, peak: peak)
}

/// `edges` less `origin`, as text.
func describe(_ edges: Edges?, from origin: NSPoint) -> String {
    guard let edges else { return "no placeholder ink" }
    return String(format: "rows %.2f–%.2f, columns %.2f–%.2f, peak %d",
                  edges.top - origin.y, edges.bottom - origin.y,
                  edges.left - origin.x, edges.right - origin.x, edges.peak)
}

/// Whether `a` and `b`, each taken from its own origin, share top, bottom
/// and right edges within 0.5 pt, and peak channel distance within 10 (one
/// copy of the placeholder, not two).
func sameEdges(_ a: Edges?, _ aOrigin: NSPoint, _ b: Edges?, _ bOrigin: NSPoint) -> Bool {
    guard let a, let b else { return false }
    return abs((a.top - aOrigin.y) - (b.top - bOrigin.y)) <= 0.5
        && abs((a.bottom - aOrigin.y) - (b.bottom - bOrigin.y)) <= 0.5
        && abs((a.right - aOrigin.x) - (b.right - bOrigin.x)) <= 0.5
        && abs(a.peak - b.peak) <= 10
}

let empty = InspectorNameField(read: { "" }, write: { _ in }, enabled: { true }, onEdit: {})
empty.placeholderString = "Marker"
let named = InspectorNameField(
    read: { "Director of Photography" }, write: { _ in }, enabled: { true }, onEdit: {})
named.placeholderString = "Marker"
for view in [empty, named] as [NSView] {
    view.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(view)
}
NSLayoutConstraint.activate([
    empty.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 220),
    empty.topAnchor.constraint(equalTo: host.topAnchor, constant: 100),
    empty.widthAnchor.constraint(equalToConstant: 170),
    named.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 220),
    named.topAnchor.constraint(equalTo: host.topAnchor, constant: 140),
    named.widthAnchor.constraint(equalToConstant: 170),
])
empty.refresh()
named.refresh()
spin(0.1)

let b50Rest = capture("b50-rest")
let emptyOrigin = empty.frame.origin

// N15 (control) — the empty field at rest draws its placeholder.
let restEdges = b50Rest.flatMap { placeholderInk(in: empty, $0) }
check("N15 an empty field draws its placeholder \"Marker\" at rest (a CONTROL)",
      restEdges != nil, describe(restEdges, from: emptyOrigin))

/// The placeholder's measurement while the field editor is attached: from
/// N15's left edge + 4 pt (clear of a caret at the origin) to the field's
/// right edge − 1 pt, at the same offsets from `view`'s origin.
func editingEdges(_ view: NSView, _ shot: Capture?) -> Edges? {
    guard let shot, let rest = restEdges else { return nil }
    let from = rest.left - emptyOrigin.x + view.frame.minX + 4
    return placeholderInk(in: view, shot, from: from, to: view.frame.maxX - 1)
}

func editorString(_ view: NSTextField) -> String {
    "editor \"\((view.currentEditor() as? NSTextView)?.string ?? "nil")\""
}

// N16 — the field editor attached, nothing typed: the placeholder sits on
// its resting rows, once.
let tookEmpty = window.makeFirstResponder(empty)
spin(0.1)
let emptyEditing = empty.currentEditor() != nil
let editingInk = editingEdges(empty, capture("b50-editing"))
check("N16 with the field editor attached and nothing typed, the placeholder is drawn once on "
        + "its rest rows and right edge, within 0.5 pt",
      tookEmpty && emptyEditing && sameEdges(editingInk, emptyOrigin, restEdges, emptyOrigin),
      "first responder \(tookEmpty), editor \(emptyEditing); rest "
        + describe(restEdges, from: emptyOrigin) + "; editing "
        + describe(editingInk, from: emptyOrigin))

// N17 — one letter typed hides it; deleted, N16 holds again.
do {
    let editor = empty.currentEditor() as? NSTextView
    editor?.insertText("i", replacementRange: NSRange(location: NSNotFound, length: 0))
    let typedEditor = editorString(empty)
    let typed = capture("b50-typed").flatMap { placeholderInk(in: empty, $0) }
    let typedGone = typed.map { t in restEdges.map { t.right <= $0.right - 10 } ?? false }
        ?? false
    editor?.deleteBackward(nil)
    let deleted = editingEdges(empty, capture("b50-deleted"))
    let back = sameEdges(deleted, emptyOrigin, restEdges, emptyOrigin)
    check("N17 one letter typed: the placeholder is gone; deleted: N16 holds again",
          editor != nil && typedGone && back,
          "after the insert " + typedEditor + "; typed (whole interior) "
            + describe(typed, from: emptyOrigin) + "; deleted "
            + describe(deleted, from: emptyOrigin) + "; rest "
            + describe(restEdges, from: emptyOrigin))
    window.makeFirstResponder(nil)
    spin(0.1)
}

// N18 — a named field cleared with the field editor attached draws the
// placeholder as N16 does, not the old name.
do {
    let took = window.makeFirstResponder(named)
    spin(0.1)
    let editor = named.currentEditor() as? NSTextView
    editor?.selectAll(nil)
    editor?.deleteBackward(nil)
    let cleared = editingEdges(named, capture("b50-cleared"))
    let origin = named.frame.origin
    check("N18 a named field cleared with the field editor attached draws the placeholder once on "
            + "N15's rows and right edge, within 0.5 pt, and not the old name",
          took && editor != nil && sameEdges(cleared, origin, restEdges, emptyOrigin),
          "first responder \(took); " + editorString(named) + "; cleared "
            + describe(cleared, from: origin) + "; N15 " + describe(restEdges, from: emptyOrigin))
    window.makeFirstResponder(nil)
    spin(0.1)
}

// N19 (control) and N20 — with the window ordered in, a display clears the
// field's needsDisplay, and a letter typed into its field editor sets it.
// Read on the field's LAYER (`layer.needsDisplay()`): the view's own getter
// reads false here even straight after `needsDisplay = true` (measured, B50),
// which is why B32's N12 read false after the insert.
window.orderFrontRegardless()
spin(0.2)
func layerDirty(_ view: NSView) -> Bool? { view.layer?.needsDisplay() }
do {
    let took = window.makeFirstResponder(empty)
    spin(0.1)
    empty.display()
    let clean = layerDirty(empty) == false
    check("N19 with the window ordered in, display() leaves the empty field's needsDisplay false "
            + "(a CONTROL)",
          took && empty.currentEditor() != nil && clean,
          "first responder \(took), editor \(empty.currentEditor() != nil); after display() "
            + "layer.needsDisplay() \(String(describing: layerDirty(empty))), the view's getter "
            + "\(empty.needsDisplay)")
    let editor = empty.currentEditor() as? NSTextView
    editor?.insertText("i", replacementRange: NSRange(location: NSNotFound, length: 0))
    let marked = layerDirty(empty) == true
    check("N20 a letter inserted into the field editor marks the field for display",
          editor != nil && clean && marked,
          "after the insert layer.needsDisplay() \(String(describing: layerDirty(empty))), the "
            + "view's getter \(empty.needsDisplay); " + editorString(empty))
    editor?.deleteBackward(nil)
    window.makeFirstResponder(nil)
    spin(0.1)
}
window.orderOut(nil)

exit(0)
