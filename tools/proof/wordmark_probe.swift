// The Welcome lockup's product wordmark (spec §11 NM-16), measured through the app's own
// sources. Built by `wordmark_proof.py` over `app/Sources` without `main.swift`; prints one JSON
// object, {"rows": [{"id", "pass", "detail"}]}. Nothing is shown and nothing on this Mac is
// read or written. Every number a row compares is written here from the handoff's README, never
// read from the app's constants.
import AppKit

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}
func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool {
    abs(a - b) <= tolerance
}
func f(_ value: CGFloat) -> String { String(format: "%.3f", Double(value)) }

_ = NSApplication.shared

// W1: the compiled-in data parses; the playhead's bounds are the handoff's, in units.
let artwork = WordmarkArtwork.frameJob
if let artwork {
    let motif = artwork.motif.bounds
    let letters = artwork.letters.bounds
    row(
        "W1",
        artwork.width == 4844 && near(motif.minX, 2844.7) && near(motif.maxX, 3064.7)
            && near(motif.minY, -960) && near(motif.maxY, 0) && letters.minX >= 0
            && letters.maxX <= 4844 && letters.minY >= -1100 && letters.maxY <= 40
            && artwork.letters.elementCount > 100,
        "width \(artwork.width); motif \(motif) (want x 2844.7…3064.7, y −960…0); letters "
            + "\(letters) in \(artwork.letters.elementCount) elements")
} else {
    row("W1", false, "WordmarkArtwork.frameJob is nil: the compiled-in data does not parse")
}

// W2: the view at 44 pt: 213.136 × 50.16, baseline 48.4 below its top, caps from 17.16.
if let artwork {
    let view = ProductWordmarkView(
        artwork: artwork, name: "Frame Job", fontSize: 44, textColor: DS.textStrong)
    let size = view.intrinsicContentSize
    row(
        "W2",
        near(size.width, 213.136) && near(size.height, 50.16)
            && near(view.firstBaselineOffsetFromTop, 48.4)
            && near(view.lastBaselineOffsetFromBottom, 1.76)
            && near(view.capLineFromTop, 17.16) && view.isFlipped,
        "size \(f(size.width)) × \(f(size.height)) (want 213.136 × 50.160); first baseline "
            + "\(f(view.firstBaselineOffsetFromTop)) (48.400); last from bottom "
            + "\(f(view.lastBaselineOffsetFromBottom)) (1.760); cap line "
            + "\(f(view.capLineFromTop)) (17.160); flipped \(view.isFlipped)")
} else {
    row("W2", false, "not measured: no artwork")
}

// W3 and W4: the lockup, laid out at its fitting size.
let lockup: BrandLockupView? = artwork == nil ? nil : BrandLockupView()
if let lockup {
    lockup.frame = NSRect(origin: .zero, size: lockup.fittingSize)
    lockup.layoutSubtreeIfNeeded()
    let views = lockup.arrangedSubviews
    if views.count == 2, let mark = views[0] as? BrandMarkView,
        let wordmark = views[1] as? ProductWordmarkView
    {
        // The stack is not flipped: y grows upward. The mark's ink ends 90/824 of its 88 pt
        // above the view's foot; the wordmark's cap line is 17.16 below its top. The stack puts
        // frames on the backing's pixel grid, 1 pt in this windowless probe (0.5 pt on a Retina
        // window), so the gap is held to 0.5 pt.
        let markInset: CGFloat = 90 * 88 / 824
        let inkFoot = mark.frame.minY + markInset
        let capLine = wordmark.frame.maxY - 17.16
        let gap = inkFoot - capLine
        let height = lockup.frame.height
        row(
            "W3",
            mark.size == 88 && near(gap, 35, 0.5) && near(height, 158, 0.5) && near(mark.frame.midX, wordmark.frame.midX, 0.5)
                && near(wordmark.frame.width, 213.136, 1) && lockup.spacing > 7
                && lockup.spacing < 9,
            "mark \(mark.frame), wordmark \(wordmark.frame); the cap line \(f(gap)) below the "
                + "mark's ink (want 35.000); the lockup \(f(height)) tall (want 158, as before "
                + "NM-16); spacing \(f(lockup.spacing)) (about 8); centred "
                + "\(f(mark.frame.midX)) / \(f(wordmark.frame.midX))")
        let elements = ([mark, wordmark] as [NSView]).filter { $0.isAccessibilityElement() }
        row(
            "W4",
            elements.count == 1 && elements.first === wordmark
                && wordmark.accessibilityRole() == .staticText
                && wordmark.accessibilityLabel() == "Frame Job"
                && (wordmark.accessibilityValue() as? String) == "Frame Job",
            "accessibility elements \(elements.count) (want 1, the wordmark); role "
                + "\(String(describing: wordmark.accessibilityRole())); label "
                + "\(String(describing: wordmark.accessibilityLabel())); value "
                + "\(String(describing: wordmark.accessibilityValue())); mark is an element "
                + "\(mark.isAccessibilityElement())")
    } else {
        let kinds = views.map { String(describing: type(of: $0)) }
        row("W3", false, "arranged subviews \(kinds) (want BrandMarkView, ProductWordmarkView)")
        row("W4", false, "not measured: arranged subviews \(kinds)")
    }
} else {
    row("W3", false, "not measured: no artwork, so no lockup was built")
    row("W4", false, "not measured: no artwork, so no lockup was built")
}

// W5: drawn in each appearance: the F's stem in the text colour, the playhead coral, a gap
// clear. Points in units → points at 44 pt: x·0.044, (y + 1100)·0.044 from the top.
func render(_ view: NSView, _ name: NSAppearance.Name) -> NSBitmapImageRep? {
    view.appearance = NSAppearance(named: name)
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
func sample(_ rep: NSBitmapImageRep, _ view: NSView, _ ux: CGFloat, _ uy: CGFloat) -> NSColor? {
    let s = CGFloat(rep.pixelsWide) / view.bounds.width
    let x = Int((ux * 0.044 * s).rounded(.down))
    let y = Int(((uy + 1100) * 0.044 * s).rounded(.down))
    return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
}
if let artwork {
    let view = ProductWordmarkView(
        artwork: artwork, name: "Frame Job", fontSize: 44, textColor: DS.textStrong)
    view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
    var good = true
    var notes: [String] = []
    for (name, dark) in [(NSAppearance.Name.aqua, false), (.darkAqua, true)] {
        guard let rep = render(view, name), let stem = sample(rep, view, 70, -200),
            let head = sample(rep, view, 2954.7, -400), let gap = sample(rep, view, 300, -100)
        else {
            good = false
            notes.append("\(name.rawValue): no bitmap")
            continue
        }
        let stemOK =
            stem.alphaComponent > 0.5
            && (dark ? stem.brightnessComponent > 0.8 : stem.brightnessComponent < 0.2)
        let coralOK =
            head.alphaComponent > 0.95 && near(head.redComponent, 0xF4 / 255, 0.06)
            && near(head.greenComponent, 0x65 / 255, 0.06)
            && near(head.blueComponent, 0x3F / 255, 0.06)
        let gapOK = gap.alphaComponent < 0.1
        good = good && stemOK && coralOK && gapOK
        notes.append(
            "\(dark ? "dark" : "light"): F stem \(stem) \(stemOK); playhead \(head) "
                + "\(coralOK); gap alpha \(f(gap.alphaComponent)) \(gapOK)")
    }
    row("W5", good, notes.joined(separator: "; "))
} else {
    row("W5", false, "not drawn: no artwork")
}

// W6: the letters fill by the nonzero rule, and wherever the overlapping glyphs make the two
// rules disagree, the drawn pixel is filled.
if let artwork {
    let letters = artwork.letters
    let evenOdd = letters.copy() as! NSBezierPath
    evenOdd.windingRule = .evenOdd
    let nonZero = letters.copy() as! NSBezierPath
    nonZero.windingRule = .nonZero
    var overlaps: [NSPoint] = []
    var x: CGFloat = 0
    while x < 4844 {
        var y: CGFloat = -1100
        while y < 40 {
            let p = NSPoint(x: x, y: y)
            if nonZero.contains(p) != evenOdd.contains(p) { overlaps.append(p) }
            y += 8
        }
        x += 8
    }
    let view = ProductWordmarkView(
        artwork: artwork, name: "Frame Job", fontSize: 44, textColor: DS.textStrong)
    view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
    var filled = 0
    if let rep = render(view, .aqua) {
        for p in overlaps where (sample(rep, view, p.x, p.y)?.alphaComponent ?? 0) > 0.5 {
            filled += 1
        }
    }
    let ruleOK = letters.windingRule == .nonZero
    row(
        "W6", ruleOK && !overlaps.isEmpty && filled * 10 >= overlaps.count * 9,
        "winding rule nonZero \(ruleOK); \(overlaps.count) sampled points where the rules "
            + "disagree (glyph overlaps), \(filled) of them drawn filled (want at least 90%)")
} else {
    row("W6", false, "not measured: no artwork")
}

let data = try! JSONSerialization.data(withJSONObject: ["rows": rows])
print(String(data: data, encoding: .utf8)!)
