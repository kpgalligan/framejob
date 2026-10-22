// Clean-up round 3, batch A (#327) — the timeline height and the inspector
// width are saved only from a person's divider drag, never from a window
// resize, the editor's own restore or ⌥⌘I.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, through
// `swift_build.build`; `pane_size_probe.py` builds, runs and scores it. One
// process:
//
//   pane_size_probe
//
// Its `UserDefaults.standard` is this executable's own domain,
// `pane_size_probe` (never the owner's `com.kgalligan.FrameJob*`: spec §11
// V-5, #238); the probe removes `FrameJobTimelineHeight` and
// `FrameJobInspectorWidth` from it before the editor loads, and the driver
// removes the domain after the probe exits.
//
// The fixture is the harness's (`tools/proof/harness/main.swift`): an
// untitled `ProjectDocument` in `EditorViewController(document:)` in a
// titled, resizable 1280×800 `NSWindow` that is never ordered on screen,
// `viewWillAppear`/`viewDidAppear`, then runloop turns with a layout pass
// each. The two split views are found by walking `controller.view` (main is
// the one whose `isVertical` is false). An observer on
// `NSSplitView.didResizeSubviewsNotification` records each notification's
// user-info keys.
//
// The answer is one JSON object on stdout, `{"rows": [...]}`, each row
// `{"id", "pass", "detail"}`. Rows:
//   R0 after the restore and the layout turns, neither key is set.
//   W1 `setContentSize` 1440×900 then 1100×700, turns: neither key is set;
//      the detail RECORDs whether those notifications carried
//      `NSSplitViewDividerIndex` (NSSplitView.h: since macOS 12, "during
//      resize and layout events as well").
//   H1 `toggleInspector(nil)` twice: neither size key is set.
//   D1 a drag of main's divider 60 pt up — a leftMouseDown at the divider's
//      centre, a leftMouseDragged and a leftMouseUp posted to the queue, then
//      `main.mouseDown(with: down)`, which tracks them as AppKit's drag does:
//      the timeline pane changed height (so the drag happened), the height
//      key equals its new height ± 0.5 pt, the width key is absent, and
//      `isDraggingDivider` is false after.
//   D2 the same on upper's divider 40 pt left: the inspector changed width,
//      the width key equals it ± 0.5 pt and the height key still holds D1's
//      value. (After W1's 1100 × 700 the inspector is narrower than its
//      280 pt minimum, measured, and the drag's own clamp lands it at 279,
//      so the row asks for a change, not for exactly 40 pt.)
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

var document: ProjectDocument?
func finish() -> Never {
    document?.removeTemporaryCacheDirectory()
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

let defaults = UserDefaults.standard
let heightKey = EditorViewController.timelineHeightKey
let widthKey = EditorViewController.inspectorWidthKey
defaults.removeObject(forKey: heightKey)
defaults.removeObject(forKey: widthKey)

func stored(_ key: String) -> Double? {
    (defaults.object(forKey: key) as? NSNumber)?.doubleValue
}
func keys() -> String {
    "height \(stored(heightKey).map { String(format: "%.2f", $0) } ?? "absent"), "
        + "width \(stored(widthKey).map { String(format: "%.2f", $0) } ?? "absent")"
}

// MARK: - The fixture

let doc = ProjectDocument()
document = doc
let controller = EditorViewController(document: doc)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
window.setContentSize(NSSize(width: 1280, height: 800))

var notes: [(split: String, keys: [String])] = []
var mainSplit: PaneSplitView?
var upperSplit: PaneSplitView?
let observer = NotificationCenter.default.addObserver(
    forName: NSSplitView.didResizeSubviewsNotification, object: nil, queue: nil
) { note in
    let name = (note.object as AnyObject?) === mainSplit
        ? "main" : (note.object as AnyObject?) === upperSplit ? "upper" : "other"
    notes.append((name, (note.userInfo ?? [:]).keys.map { "\($0)" }.sorted()))
}

func turns(_ count: Int = 12) {
    for _ in 0..<count {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        controller.view.layoutSubtreeIfNeeded()
    }
}

controller.viewWillAppear()
// A window on screen is laid out before it appears; this one never is, and a
// restore into split views still 0 × 0 (measured) collapses both panes.
controller.view.layoutSubtreeIfNeeded()
controller.viewDidAppear()
turns()

func splits(in view: NSView) -> [PaneSplitView] {
    var found: [PaneSplitView] = []
    if let split = view as? PaneSplitView { found.append(split) }
    for child in view.subviews { found += splits(in: child) }
    return found
}
let all = splits(in: controller.view)
mainSplit = all.first { !$0.isVertical }
upperSplit = all.first { $0.isVertical }
guard let main = mainSplit, let upper = upperSplit, main.arrangedSubviews.count == 2,
    upper.arrangedSubviews.count == 2
else {
    row("R0", false, "the editor's two PaneSplitViews were not found (\(all.count) found)")
    finish()
}
let timelinePane = main.arrangedSubviews[1]
let inspectorPane = upper.arrangedSubviews[1]

func layout() -> String {
    func frames(_ split: NSSplitView) -> String {
        split.arrangedSubviews.map {
            "\(Int($0.frame.width))×\(Int($0.frame.height))\($0.isHidden ? " hidden" : "")"
        }.joined(separator: " | ")
    }
    return "view \(Int(controller.view.bounds.width))×\(Int(controller.view.bounds.height)), "
        + "main [\(frames(main))], upper [\(frames(upper))]"
}

// MARK: - R0 — the restore

row("R0", stored(heightKey) == nil && stored(widthKey) == nil,
    "after the restore and \(notes.count) resize notifications: \(keys()); timeline "
        + String(format: "%.1f", timelinePane.bounds.height) + " pt, inspector "
        + String(format: "%.1f", inspectorPane.bounds.width) + " pt; " + layout())

// MARK: - W1 — a window resize

notes.removeAll()
window.setContentSize(NSSize(width: 1440, height: 900))
turns()
window.setContentSize(NSSize(width: 1100, height: 700))
turns()
let carried = notes.filter { $0.keys.contains("NSSplitViewDividerIndex") }.count
row("W1", stored(heightKey) == nil && stored(widthKey) == nil,
    "\(keys()); RECORD: \(notes.count) resize notifications "
        + "(\(notes.filter { $0.split == "main" }.count) main, "
        + "\(notes.filter { $0.split == "upper" }.count) upper), \(carried) carried "
        + "NSSplitViewDividerIndex; keys seen: "
        + Set(notes.flatMap { $0.keys }).sorted().joined(separator: ", "))

// MARK: - H1 — ⌥⌘I twice

notes.removeAll()
controller.toggleInspector(nil)
turns()
let hidden = inspectorPane.isHidden
controller.toggleInspector(nil)
turns()
row("H1", stored(heightKey) == nil && stored(widthKey) == nil,
    "\(keys()); hidden after the first \(hidden), after the second \(inspectorPane.isHidden); "
        + "\(notes.count) resize notifications")

// MARK: - D1, D2 — a divider drag

/// A drag of `split`'s divider by `delta` in the split's own (flipped)
/// coordinates: the down at the divider's centre, the dragged and the up
/// posted behind it, then the down handed to `mouseDown(with:)`, whose
/// tracking loop takes the posted two from the queue.
func drag(_ split: PaneSplitView, by delta: CGFloat) -> String {
    let first = split.arrangedSubviews[0].frame
    let thickness = split.dividerThickness
    let centre = split.isVertical
        ? NSPoint(x: first.maxX + thickness / 2, y: split.bounds.midY)
        : NSPoint(x: split.bounds.midX, y: first.maxY + thickness / 2)
    let target = split.isVertical
        ? NSPoint(x: centre.x + delta, y: centre.y)
        : NSPoint(x: centre.x, y: centre.y + delta)
    let from = split.convert(centre, to: nil)
    let to = split.convert(target, to: nil)
    func event(_ type: NSEvent.EventType, _ at: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type, location: at, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
    }
    guard let down = event(.leftMouseDown, from), let dragged = event(.leftMouseDragged, to),
        let up = event(.leftMouseUp, to)
    else { return "the events could not be made" }
    NSApp.postEvent(dragged, atStart: false)
    NSApp.postEvent(up, atStart: false)
    split.mouseDown(with: down)
    turns()
    return "window \(window.windowNumber), from \(from) to \(to)"
}

notes.removeAll()
let timelineBefore = timelinePane.bounds.height
let mainDrag = drag(main, by: -60)
let timelineAfter = timelinePane.bounds.height
let heightSaved = stored(heightKey)
row("D1",
    heightSaved.map { abs($0 - Double(timelineAfter)) <= 0.5 } == true
        && stored(widthKey) == nil && !main.isDraggingDivider
        && abs(timelineAfter - timelineBefore) >= 1,
    "\(keys()); timeline " + String(format: "%.1f → %.1f", timelineBefore, timelineAfter)
        + " pt; isDraggingDivider after \(main.isDraggingDivider); \(notes.count) notifications; "
        + mainDrag)

notes.removeAll()
let inspectorBefore = inspectorPane.bounds.width
let upperDrag = drag(upper, by: -40)
let inspectorAfter = inspectorPane.bounds.width
let widthSaved = stored(widthKey)
row("D2",
    widthSaved.map { abs($0 - Double(inspectorAfter)) <= 0.5 } == true
        && heightSaved != nil && stored(heightKey) == heightSaved && !upper.isDraggingDivider
        && abs(inspectorAfter - inspectorBefore) >= 1,
    "\(keys()); inspector " + String(format: "%.1f → %.1f", inspectorBefore, inspectorAfter)
        + " pt; isDraggingDivider after \(upper.isDraggingDivider); \(notes.count) notifications; "
        + upperDrag)

NotificationCenter.default.removeObserver(observer)
finish()
