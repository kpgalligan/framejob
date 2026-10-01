// Issue batch B50 (#102) — the section header's hover and Normalize's boxed
// "clip" tag; the probe (`clip_inspector7_proof.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `InspectorSectionHeader`, `InspectorHeaderHoverBand`,
// `InspectorClipTag`, `ClipPane` and `DS.animate`.
//
//   clip_inspector7_probe <request.json> <answer.json>
//
// `request.json` names the package the proof wrote:
//   audio  one audio-only media clip of 6 s, clip 2 over media 90, action 10
//          at 1–2 s {audio: {volume: 0.5}}
// One JSON object out: `rows`, each a name, ok and detail. Row names start
// with their H- or T-number, which is what the proof counts.
//
// H1 replaces `-[NSWorkspace accessibilityDisplayShouldReduceMotion]` with a
// block answering `forcedReduceMotion`, so the rows after it set Reduce
// Motion. H2–H6 host a bare `InspectorSection` in a 304 × 120 window ordered
// in with `orderFrontRegardless()`, and order it out after H6. A fade still
// in flight carries its `opacity` key into the next call, so before each
// `mouseEntered` / `mouseExited` in H3 and H4, and before each H6 capture,
// the band's layer is cleaned (`removeAllAnimations()`) and its keys must
// read empty; a failed precondition fails that row.
import AppKit
import ObjectiveC

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

let second: Ticks = 600_000
func at(_ seconds: Double) -> Ticks { Ticks((seconds * Double(second)).rounded()) }

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// Every section key this probe pins, dropped at the start and at the end so
/// a run leaves the probe's defaults domain as it found it.
let pinnedIDs = ["audio.volume", "probe.hover"]
func key(_ id: String) -> String { InspectorSection.collapsedKeyPrefix + id }
func unpin() { for id in pinnedIDs { UserDefaults.standard.removeObject(forKey: key(id)) } }
unpin()
for id in pinnedIDs { UserDefaults.standard.set(false, forKey: key(id)) }

func opened(_ name: String) -> ProjectDocument? {
    guard let path = request[name] as? String else {
        check("T0 the \(name) fixture is named", false)
        return nil
    }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("T0 the \(name) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

/// A Clip pane over a document with `selection` selected, the playhead at
/// `seconds` and `action` selected, no window, the inspector's two intents
/// wired as `installInspector()` wires them.
var kept: [AnyObject] = []
func clipPane(
    _ name: String, select selection: Set<UInt32> = [2], playhead seconds: Double,
    action: UInt32?
) -> (ProjectDocument, InspectorViewController, ClipPane)? {
    guard let document = opened(name) else { return nil }
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }
    inspector.onSelectAction = { [weak document] id in document?.selectAction(id) }
    document.selection = selection
    document.playhead = at(seconds)
    document.selectAction(action)
    inspector.binding.invalidate()
    kept += [document, inspector]
    return (document, inspector, ClipPane(inspector: inspector))
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func sections(_ pane: ClipPane, _ tab: ClipSubTab) -> [InspectorSection] {
    pane.binding.invalidate()
    pane.choose(tab)
    pane.rebuild()
    pane.refresh()
    return pane.sections
}

func section(_ list: [InspectorSection], _ id: String) -> InspectorSection? {
    list.first { $0.id == id }
}

// MARK: - H1 Reduce Motion, forced (a CONTROL)

var forcedReduceMotion = false
do {
    let selector = NSSelectorFromString("accessibilityDisplayShouldReduceMotion")
    let method = class_getInstanceMethod(NSWorkspace.self, selector)
    let block: @convention(block) (AnyObject) -> Bool = { _ in forcedReduceMotion }
    if let method {
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
    forcedReduceMotion = false
    let off = DS.reduceMotion
    forcedReduceMotion = true
    let on = DS.reduceMotion
    forcedReduceMotion = false
    check("H1 with the getter replaced, DS.reduceMotion reads false, then true, as forced "
            + "(a CONTROL)",
          method != nil && !off && on, "method \(method != nil), off \(off), on \(on)")
}

// MARK: - H2–H6 the header's hover

let hoverWindow = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 304, height: 120), styleMask: [.titled],
    backing: .buffered, defer: false)
hoverWindow.isReleasedWhenClosed = false
let hoverSection = InspectorSection(id: "probe.hover", title: "Probe", rows: [])
hoverSection.translatesAutoresizingMaskIntoConstraints = false
if let content = hoverWindow.contentView {
    content.addSubview(hoverSection)
    NSLayoutConstraint.activate([
        hoverSection.topAnchor.constraint(equalTo: content.topAnchor),
        hoverSection.leadingAnchor.constraint(equalTo: content.leadingAnchor),
        hoverSection.trailingAnchor.constraint(equalTo: content.trailingAnchor),
    ])
}
hoverWindow.orderFrontRegardless()
hoverWindow.contentView?.layoutSubtreeIfNeeded()
spin(0.2)
let header = hoverSection.header
let band = header.hoverBand

func enterExit(_ type: NSEvent.EventType) -> NSEvent? {
    NSEvent.enterExitEvent(
        with: type, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: hoverWindow.windowNumber, context: nil, eventNumber: 0,
        trackingNumber: 0, userData: nil)
}

/// Removes every animation on the band's layer; true when its keys then
/// read empty — the clean-layer precondition.
func cleanLayer() -> Bool {
    band.layer?.removeAllAnimations()
    return band.layer != nil && (band.layer?.animationKeys() ?? []).isEmpty
}

func keys() -> [String] { band.layer?.animationKeys() ?? [] }

func opacityDuration() -> Double? { band.layer?.animation(forKey: "opacity")?.duration }

// H2 — one tracking area of the header's own, at rest.
do {
    header.updateTrackingAreas()
    header.updateTrackingAreas()
    let own = header.trackingAreas.filter { $0.owner === header }
    let area = own.first
    let options = area?.options ?? []
    check("H2 after two updateTrackingAreas() the header owns exactly one area, its bounds, "
            + "mouseEnteredAndExited and activeInKeyWindow; at rest isHovered is false and the "
            + "band's alpha 0",
          own.count == 1 && area?.rect == header.bounds
            && options.contains(.mouseEnteredAndExited) && options.contains(.activeInKeyWindow)
            && !header.isHovered && band.alphaValue == 0,
          "own areas \(own.count), rect \(String(describing: area?.rect)), bounds "
            + "\(header.bounds), options \(options.rawValue), isHovered \(header.isHovered), "
            + "alpha \(band.alphaValue)")
}

// H3 — Reduce Motion off: the state at once, the alpha faded over 0.14 s.
do {
    forcedReduceMotion = false
    var notes: [String] = []
    var ok = true
    if let entered = enterExit(.mouseEntered), let exited = enterExit(.mouseExited) {
        let cleanIn = cleanLayer()
        header.mouseEntered(with: entered)
        let inState = (header.isHovered, band.alphaValue, keys(), opacityDuration())
        let cleanOut = cleanLayer()
        header.mouseExited(with: exited)
        let outState = (header.isHovered, band.alphaValue, keys(), opacityDuration())
        func animated(_ d: Double?) -> Bool { d.map { abs($0 - 0.14) <= 0.001 } ?? false }
        ok = cleanIn && cleanOut && inState.0 && inState.1 == 1 && animated(inState.3)
            && !outState.0 && outState.1 == 0 && animated(outState.3)
        notes.append("clean before enter \(cleanIn), before exit \(cleanOut)")
        notes.append("entered: isHovered \(inState.0), alpha \(inState.1), keys \(inState.2), "
                     + "opacity duration \(String(describing: inState.3))")
        notes.append("exited: isHovered \(outState.0), alpha \(outState.1), keys \(outState.2), "
                     + "opacity duration \(String(describing: outState.3))")
    } else {
        ok = false
        notes.append("no enter/exit event")
    }
    check("H3 Reduce Motion off: from a clean layer mouseEntered sets alpha 1 at once and the "
            + "band's layer carries an opacity animation of 0.14 s; mouseExited the same to 0",
          ok, notes.joined(separator: "; "))
}

// H4 — Reduce Motion on: the same calls, no animation.
do {
    forcedReduceMotion = true
    var notes: [String] = []
    var ok = true
    if let entered = enterExit(.mouseEntered), let exited = enterExit(.mouseExited) {
        let cleanIn = cleanLayer()
        header.mouseEntered(with: entered)
        let inState = (header.isHovered, band.alphaValue, keys())
        let cleanOut = cleanLayer()
        header.mouseExited(with: exited)
        let outState = (header.isHovered, band.alphaValue, keys())
        ok = cleanIn && cleanOut && inState.0 && inState.1 == 1 && inState.2.isEmpty
            && !outState.0 && outState.1 == 0 && outState.2.isEmpty
        notes.append("clean before enter \(cleanIn), before exit \(cleanOut)")
        notes.append("entered: isHovered \(inState.0), alpha \(inState.1), keys \(inState.2)")
        notes.append("exited: isHovered \(outState.0), alpha \(outState.1), keys \(outState.2)")
    } else {
        ok = false
        notes.append("no enter/exit event")
    }
    forcedReduceMotion = false
    check("H4 Reduce Motion on: from a clean layer mouseEntered sets alpha 1 and mouseExited 0, "
            + "and the band's layer carries no animation after either",
          ok, notes.joined(separator: "; "))
}

// H5 — the band: first, above the rule, and clicks pass through it.
do {
    let first = header.subviews.first === band
    let h = header.bounds.height
    let w = header.bounds.width
    let frameOK = band.frame == NSRect(x: 0, y: 0, width: w, height: h - 1)
    let centre = NSPoint(x: band.frame.midX, y: band.frame.midY)
    let point = header.superview.map { header.convert(centre, to: $0) } ?? centre
    let hit = header.hitTest(point)
    check("H5 the band is the header's first subview, framed (0, 0, w, h − 1), and a hit at its "
            + "centre answers the header",
          first && frameOK && hit === header,
          "first \(first), band frame \(band.frame), header bounds \(header.bounds), hit "
            + "\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
}

// H6 — hovered and at rest, captured: the band shows, the rule does not move.
do {
    forcedReduceMotion = true
    func shot() -> NSBitmapImageRep? {
        header.display()
        guard let rep = header.bitmapImageRepForCachingDisplay(in: header.bounds) else {
            return nil
        }
        header.cacheDisplay(in: header.bounds, to: rep)
        return rep
    }
    func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return [] }
        return [color.redComponent, color.greenComponent, color.blueComponent,
                color.alphaComponent].map { Int(($0 * 255).rounded()) }
    }
    var notes: [String] = []
    var ok = false
    if let entered = enterExit(.mouseEntered), let exited = enterExit(.mouseExited) {
        header.mouseEntered(with: entered)
        let cleanHovered = cleanLayer()
        let hovered = shot()
        header.mouseExited(with: exited)
        let cleanRest = cleanLayer()
        let rest = shot()
        if let hovered, let rest {
            let scale = CGFloat(hovered.pixelsWide) / header.bounds.width
            let corner = (Int(2 * scale), Int(2 * scale))
            let a = pixel(hovered, corner.0, corner.1)
            let b = pixel(rest, corner.0, corner.1)
            let ruleY = Int((header.bounds.height - 0.5) * scale)
            let ruleSame = (0..<hovered.pixelsWide).allSatisfy {
                pixel(hovered, $0, ruleY) == pixel(rest, $0, ruleY)
            }
            ok = cleanHovered && cleanRest && !a.isEmpty && a != b && ruleSame
            notes.append("clean before hovered \(cleanHovered), before rest \(cleanRest)")
            notes.append("(2, 2) hovered \(a), rest \(b); rule row \(ruleY) px equal \(ruleSame)")
        } else {
            notes.append("no capture")
        }
    } else {
        notes.append("no enter/exit event")
    }
    forcedReduceMotion = false
    check("H6 Reduce Motion on, from a clean layer: the header captured hovered and at rest "
            + "differs at (2, 2) and is equal on the rule's row, y = h − 0.5",
          ok, notes.joined(separator: "; "))
}
hoverWindow.orderOut(nil)

// MARK: - T1–T3 Normalize's "clip" tag

func clipTags(_ pane: ClipPane) -> [InspectorClipTag] {
    guard let volume = section(sections(pane, .sound), "audio.volume") else { return [] }
    return walk(volume).compactMap { $0 as? InspectorClipTag }
}

if let (_, _, pane) = clipPane("audio", playhead: 1.5, action: 10) {
    let tags = clipTags(pane)
    let tag = tags.first
    let stack = tag?.superview as? NSStackView
    let index = stack.flatMap { s in tag.flatMap { t in s.arrangedSubviews.firstIndex(of: t) } }
    let before = index.flatMap { $0 > 0 ? stack?.arrangedSubviews[$0 - 1] : nil }
    check("T1 with action 10 selected, Sound ▸ Volume holds exactly one InspectorClipTag, "
            + "visible, the arranged subview right after an OptionButtonControl",
          tags.count == 1 && tag?.isHidden == false && before is OptionButtonControl,
          "tags \(tags.count), hidden \(String(describing: tag?.isHidden)), index "
            + "\(String(describing: index)), before "
            + "\(before.map { String(describing: type(of: $0)) } ?? "nil")")
}

if let (_, _, pane) = clipPane("audio", playhead: 3.0, action: nil) {
    let tags = clipTags(pane)
    check("T2 with no action selected (playhead 3 s), the tag is hidden",
          tags.count == 1 && tags.first?.isHidden == true,
          "tags \(tags.count), hidden \(String(describing: tags.first?.isHidden))")
}

if let (_, _, pane) = clipPane("audio", playhead: 1.5, action: 10), let tag = clipTags(pane).first {
    let width = InspectorClipTag.text.size(withAttributes: [.font: DS.mono(9)]).width
    let want = NSSize(width: ceil(width) + 10, height: 17)
    let size = tag.intrinsicContentSize
    tag.isHidden = false
    tag.removeFromSuperview()
    tag.frame = NSRect(origin: .zero, size: size)
    var notes = ["intrinsic \(size), formula \(want)"]
    var ok = size == want
    if let rep = tag.bitmapImageRepForCachingDisplay(in: tag.bounds) {
        tag.cacheDisplay(in: tag.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / tag.bounds.width
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? -1
        }
        let edge = alpha(0.5, size.height / 2)
        let corner = alpha(2, 2)
        var interior = false
        var y: CGFloat = 2
        while y < size.height - 2 && !interior {
            var x: CGFloat = 2
            while x < size.width - 2 && !interior {
                if alpha(x, y) > 0 { interior = true }
                x += 0.5
            }
            y += 0.5
        }
        ok = ok && edge > 0 && corner == 0 && interior
        notes.append("(0.5, h/2) alpha \(edge), (2, 2) alpha \(corner), interior drawn \(interior)")
    } else {
        ok = false
        notes.append("no capture")
    }
    check("T3 the tag's intrinsic size is (ceil(text width in mono 9) + 10, 17); captured alone, "
            + "(0.5, h/2) is drawn, (2, 2) is clear and some interior pixel is drawn",
          ok, notes.joined(separator: "; "))
}

// T4 — one pane refreshed in place (#209 item 2): the tag is read from `walk(pane)`, never
// through `clipTags` / `sections`, which rebuild.
if let (document, _, pane) = clipPane("audio", playhead: 1.5, action: 10),
   let tag = clipTags(pane).first
{
    func read() -> (count: Int, same: Bool, hidden: Bool?) {
        let found = walk(pane).compactMap { $0 as? InspectorClipTag }
        return (found.count, found.first === tag, found.first?.isHidden)
    }
    let shown = read()
    document.selectAction(nil)
    pane.binding.invalidate()
    pane.refresh()
    let cleared = read()
    document.selectAction(10)
    pane.binding.invalidate()
    pane.refresh()
    let reselected = read()
    let reads = [shown, cleared, reselected]
    check("T4 one pane refreshed in place: the same InspectorClipTag shows with action 10 "
            + "selected, hides when the action is cleared, shows again when 10 is reselected",
          reads.allSatisfy { $0.count == 1 && $0.same }
            && reads.map { $0.hidden } == [false, true, false],
          reads.map { "tags \($0.count), same \($0.same), hidden "
              + "\(String(describing: $0.hidden))" }.joined(separator: "; "))
}

unpin()
let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
