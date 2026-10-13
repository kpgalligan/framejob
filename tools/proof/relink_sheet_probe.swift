// Issue batch B29 (#180.2) — the missing-media sheet alerts each refused
// relink's sentence after its one grouped commit, driven through the app's
// own `RelinkSheetController` and `ProjectDocument`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` — the swiftc
// line `cache_pass_probe.py` uses. One process:
//
//   relink_sheet_probe <request.json>
//
// The request names `media` (a copy of tools/proof/media) and `work` (this
// run's directory). The answer is one JSON object on stdout, `{"rows": [...]}`,
// each row `{"id", "pass", "detail"}`; `relink_sheet_probe.py` prints and
// scores them. Every wait pumps `RunLoop.main` (the probe's completion hops to
// main) and is bounded; a timeout is the row's FAIL.
//
// The fixture: an untitled `ProjectDocument` with three video media added by
// one grouped `add_media`, each `probeBlocking`'s descriptor of an A.mov copy
// with its `path` pointed at a file that does not exist and its `bookmark`
// nil (`mediaURL(for:)` resolves a bookmark first), so all three are missing.
// Its window is a bare host view controller's, so `windowForSheet` is it.
// The sheet never becomes key under `.prohibited`, so its Relink button is
// pressed with `performClick` and an alert is ended with `endSheet`. S4 runs
// a second sheet after S1's undo: an unreadable file, a refusal, A.mov.
//
// A1–A5 (issue batch B51, #195) run after S4, each counting the alerts that
// attach — an alert is an attached sheet that is not a relink sheet, A4's
// bare sheet or A5's blocker, and not one already seen: A1 Add Media… of two
// unreadable files, A2 the Media tab's relink of one, A3 the sheet's relink
// whose commit throws after a refusal, A4 `present(_:)` while a bare view
// controller's sheet is up, A5 while an `NSAlert` sheet is up.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2,
    let requestData = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let mediaPath = request["media"] as? String, let workPath = request["work"] as? String
else {
    FileHandle.standardError.write(Data("usage: relink_sheet_probe <request.json>\n".utf8))
    exit(2)
}
let mediaDir = URL(fileURLWithPath: mediaPath, isDirectory: true)
let work = URL(fileURLWithPath: workPath, isDirectory: true)
let files = FileManager.default
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

/// Pumps until `condition` holds or `limit` seconds pass; the seconds it
/// took, or nil.
func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return Date().timeIntervalSince(start) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

func seconds(_ value: Double?) -> String { value.map { String(format: "%.2f s", $0) } ?? "never" }

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

/// Every text field's string in a sheet's view tree.
func texts(_ sheet: NSWindow) -> [String] {
    (sheet.contentView.map(walk) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        .filter { !$0.isEmpty }
}

func copyMedium(_ name: String) -> URL {
    let url = work.appendingPathComponent(name)
    try? files.removeItem(at: url)
    try? files.copyItem(at: mediaDir.appendingPathComponent(name), to: url)
    return url
}

try? files.createDirectory(at: work, withIntermediateDirectories: true)
let toneA = copyMedium("toneA.m4a")
let toneB = copyMedium("toneB.m4a")
let movie = copyMedium("A.mov")

// MARK: - The fixture

guard let probed = try? MediaImporter.probeBlocking(url: movie) else {
    row("C1", false, "A.mov did not probe")
    finish()
}
let gone = work.appendingPathComponent("gone", isDirectory: true)
try? files.removeItem(at: gone)
let doc = ProjectDocument()
document = doc
let descriptors = (1...3).map { n -> MediaDescriptor in
    var d = probed
    d.path = gone.appendingPathComponent("missing-\(n).mov").path
    d.bookmark = nil
    return d
}
doc.performGroupedEdit("Add Media", descriptors.map { ReelOp.addMedia(descriptor: $0) })
let ids = doc.project.snapshot.media.map { $0.id }
doc.undoManager?.removeAllActions()
guard ids.count == 3 else {
    row("S0", false, "the fixture holds \(ids.count) media, not 3")
    finish()
}
let (m1, m2, m3) = (ids[0], ids[1], ids[2])

let host = NSViewController()
host.view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
let window = NSWindow(contentViewController: host)
let controller = NSWindowController(window: window)
doc.addWindowController(controller)
controller.showWindow(nil)

func path(_ media: UInt32) -> String {
    doc.project.snapshot.media.first { $0.id == media }?.path ?? "<no media \(media)>"
}
let before = (m1: path(m1), m2: path(m2), m3: path(m3))

/// `.refused(r).reason` of relinking `media` alone to `url`'s descriptor, on
/// the pre-commit handle.
func expected(_ media: UInt32, _ url: URL) -> String? {
    guard let d = try? MediaImporter.probeBlocking(url: url),
        case .refused(let refusal)? = try? doc.project.applying(
            .relinkMedia(media: media, path: d.path, bookmark: d.bookmark, probe: d))
    else { return nil }
    return refusal.reason
}
let sentence1 = expected(m1, toneA)
let sentence2 = expected(m2, toneB)

// MARK: - C1 — CONTROL: the Media tab's door keeps the fold's strip, no alert

var refused: [String] = []
let observer = NotificationCenter.default.addObserver(
    forName: .projectDocumentDidRefuse, object: doc, queue: nil
) { note in
    refused.append((note.userInfo?["refusal"] as? ReelRefusal)?.reason ?? "<no refusal>")
}
doc.relinkMedia([(media: m1, url: toneA)])
let heard = waitUntil(20) { !refused.isEmpty }
var sheetAttached = false
_ = waitUntil(3) {
    if window.attachedSheet != nil { sheetAttached = true }
    return false
}
row("C1", heard != nil && refused.count == 1 && sentence1 != nil && refused.first == sentence1
        && !sheetAttached,
    "refusals posted \(refused.count) (first \(seconds(heard))): \(refused); "
    + "expected \(sentence1 ?? "<none>"); a sheet attached within 3 s: \(sheetAttached)")
NotificationCenter.default.removeObserver(observer)

// MARK: - S0 — CONTROL: the fixture's three media are missing

let missing = doc.missingMedia
let resolved = [m1, m2, m3].map { id -> String in
    let media = doc.project.snapshot.media.first { $0.id == id }
    return "\(id): " + (media.flatMap(mediaURL(for:))?.path ?? "nil")
}
row("S0", missing.count == 3,
    "missingMedia \(missing.count); mediaURL(for:) " + resolved.joined(separator: ", "))

// MARK: - The sheet: three choices, then Relink

let sheet = RelinkSheetController(document: doc)
host.presentAsSheet(sheet)
_ = waitUntil(3) { window.attachedSheet != nil }
let relinkWindow = sheet.view.window
sheet.chose(toneA, for: m1)
sheet.chose(toneB, for: m2)
sheet.chose(movie, for: m3)
let relink = walk(sheet.view).compactMap { $0 as? NSButton }.first { $0.title == "Relink" }
guard let relink else {
    row("S1", false, "no Relink button in the sheet")
    row("S2", false, "not run")
    row("S3", false, "not run")
    finish()
}
relink.performClick(nil)

// S1's first half: the grouped commit lands media 3's new path.
let committed = waitUntil(20) { path(m3) == movie.path }
let otherKept = path(m1) == before.m1 && path(m2) == before.m2

// S2 and S3: the alerts, one per refusal, in order, after the commit.
func nextAlert(_ limit: Double, after seen: [NSWindow]) -> NSWindow? {
    var found: NSWindow?
    _ = waitUntil(limit) {
        if let attached = window.attachedSheet, attached !== relinkWindow,
            !seen.contains(where: { $0 === attached }) {
            found = attached
        }
        return found != nil
    }
    return found
}
var alertTexts: [[String]] = []
var s3Path = "<no alert>"
let first = nextAlert(20, after: [])
if let first {
    s3Path = path(m3)
    alertTexts.append(texts(first))
    window.endSheet(first, returnCode: .alertFirstButtonReturn)
}
let second = first.flatMap { nextAlert(10, after: [$0]) }
if let second {
    alertTexts.append(texts(second))
    window.endSheet(second, returnCode: .alertFirstButtonReturn)
}
let third = second.flatMap { nextAlert(2, after: [first, $0].compactMap { $0 }) }
let firstHolds = sentence1.map { s in alertTexts.first?.contains(s) == true } ?? false
let secondHolds = sentence2.map { s in alertTexts.count > 1 && alertTexts[1].contains(s) } ?? false
row("S2", first != nil && second != nil && firstHolds && secondHolds && third == nil,
    "alert 1 \(first != nil) holds media \(m1)'s sentence \(firstHolds); "
    + "alert 2 \(second != nil) holds media \(m2)'s \(secondHolds); "
    + "a third within 2 s: \(third != nil); texts \(alertTexts); "
    + "expected \(sentence1 ?? "<none>") / \(sentence2 ?? "<none>")")
row("S3", first != nil && s3Path == movie.path,
    "media \(m3)'s path when the first alert attached: \(s3Path)")

// S1's second half: one undo step, named, that undoes the relink.
let undo = doc.undoManager
let name = undo?.undoActionName ?? "<no undo manager>"
undo?.undo()
_ = waitUntil(0.5) { false }
let restored = path(m3) == before.m3
let canUndo = undo?.canUndo ?? true
row("S1", committed != nil && otherKept && name == "Relink Media" && restored && !canUndo,
    "media \(m3) relinked to the A.mov copy \(seconds(committed)); media \(m1) and \(m2) "
    + "unchanged: \(otherKept); undo action \"\(name)\"; one undo restored media \(m3)'s path: "
    + "\(restored); canUndo after: \(canUndo)")

// MARK: - S4 — an unreadable file, then a refusal: both alerts, in order

// A garbage `.png`: ImageIO refuses it and a still never reaches ffmpeg's
// consent alert, so the probe fails without asking anything.
let bad = work.appendingPathComponent("unreadable.png")
try? Data("not a picture".utf8).write(to: bad)
var unreadableText: String?
do { _ = try MediaImporter.probeBlocking(url: bad) } catch {
    unreadableText = error.localizedDescription
}
let sentence4 = expected(m2, toneA)
let sheet4 = RelinkSheetController(document: doc)
host.presentAsSheet(sheet4)
_ = waitUntil(3) { window.attachedSheet === sheet4.view.window }
let relinkWindow4 = sheet4.view.window
sheet4.chose(bad, for: m1)
sheet4.chose(toneA, for: m2)
sheet4.chose(movie, for: m3)
let relink4 = walk(sheet4.view).compactMap { $0 as? NSButton }.first { $0.title == "Relink" }
var s4Texts: [[String]] = []
var s4Seen: [NSWindow] = []
if let relink4 {
    relink4.performClick(nil)
    for limit in [20.0, 10.0] {
        var found: NSWindow?
        _ = waitUntil(limit) {
            if let attached = window.attachedSheet, attached !== relinkWindow4,
                !s4Seen.contains(where: { $0 === attached }) {
                found = attached
            }
            return found != nil
        }
        guard let found else { break }
        s4Seen.append(found)
        s4Texts.append(texts(found))
        // Held as a person holds it, until the commit has landed and a beat
        // after: the alerts behind it are asked for while it is still up.
        if s4Seen.count == 1 {
            _ = waitUntil(20) { path(m3) == movie.path }
            _ = waitUntil(0.5) { false }
        }
        window.endSheet(found, returnCode: .alertFirstButtonReturn)
    }
}
var s4Third = false
if s4Seen.count == 2 {
    _ = waitUntil(2) {
        if let attached = window.attachedSheet, attached !== relinkWindow4,
            !s4Seen.contains(where: { $0 === attached }) {
            s4Third = true
        }
        return s4Third
    }
}
let s4First = unreadableText.map { t in s4Texts.first?.contains(t) == true } ?? false
let s4Second = sentence4.map { t in s4Texts.count > 1 && s4Texts[1].contains(t) } ?? false
row("S4", relink4 != nil && s4Seen.count == 2 && s4First && s4Second && !s4Third
        && path(m3) == movie.path,
    "Relink button \(relink4 != nil); alerts \(s4Seen.count); alert 1 holds the unreadable "
    + "file's error \(s4First); alert 2 holds media \(m2)'s sentence \(s4Second); a third "
    + "within 2 s: \(s4Third); media \(m3) relinked: \(path(m3) == movie.path); texts "
    + "\(s4Texts); expected \(unreadableText ?? "<the file probed>") / \(sentence4 ?? "<none>")")

// MARK: - A1–A5 — every error the document presents is shown (#195)

/// An attached sheet that is none of `besides` (the relink sheets, a bare
/// sheet, a blocker alert's window) and not in `seen`, within `limit` s.
func newAlert(_ limit: Double, after seen: [NSWindow], besides: [NSWindow?] = [])
    -> NSWindow?
{
    let others = [relinkWindow, relinkWindow4] + besides
    var found: NSWindow?
    _ = waitUntil(limit) {
        if let attached = window.attachedSheet,
            !others.contains(where: { $0 === attached }),
            !seen.contains(where: { $0 === attached }) {
            found = attached
        }
        return found != nil
    }
    return found
}

/// Ends `alert` and returns its texts.
func end(_ alert: NSWindow) -> [String] {
    let shown = texts(alert)
    window.endSheet(alert, returnCode: .alertFirstButtonReturn)
    return shown
}

func unreadable(_ name: String) -> (URL, String?) {
    let url = work.appendingPathComponent(name)
    try? Data("not a picture".utf8).write(to: url)
    var text: String?
    do { _ = try MediaImporter.probeBlocking(url: url) } catch { text = error.localizedDescription }
    return (url, text)
}

func holds(_ shown: [String]?, _ text: String?) -> Bool {
    guard let shown, let text else { return false }
    return shown.contains(text)
}

let clear = waitUntil(3) { window.attachedSheet == nil }
let preamble = "no sheet attached before A1: \(seconds(clear)); "
let (bad1, bad1Text) = unreadable("unreadable-1.png")
let (bad2, bad2Text) = unreadable("unreadable-2.png")

// A1 (#195.1): File ▸ Add Media… of two unreadable files: both alerts.
var a1Done: Double?
let a1Start = Date()
doc.importMedia([bad1, bad2]) { _ in a1Done = Date().timeIntervalSince(a1Start) }
var a1Seen: [NSWindow] = []
var a1Texts: [[String]] = []
if let first = newAlert(20, after: []) {
    a1Seen.append(first)
    _ = waitUntil(20) { a1Done != nil }
    _ = waitUntil(0.5) { false }
    a1Texts.append(end(first))
    if let second = newAlert(10, after: a1Seen) {
        a1Seen.append(second)
        a1Texts.append(end(second))
    }
}
let a1Third = a1Seen.count == 2 ? newAlert(2, after: a1Seen) != nil : false
row("A1", a1Seen.count == 2 && holds(a1Texts.first, bad1Text)
        && holds(a1Texts.count > 1 ? a1Texts[1] : nil, bad2Text) && !a1Third,
    preamble + "alerts \(a1Seen.count); completion ran at \(seconds(a1Done)); a third within "
    + "2 s: \(a1Third); texts \(a1Texts); expected \(bad1Text ?? "<probed>") / "
    + "\(bad2Text ?? "<probed>")")

// A2 (#195.2): the Media tab's door, one unreadable file: one alert.
doc.relinkMedia([(media: m1, url: bad1)])
var a2Seen: [NSWindow] = []
var a2Texts: [[String]] = []
if let first = newAlert(20, after: []) {
    a2Seen.append(first)
    _ = waitUntil(0.5) { false }
    a2Texts.append(end(first))
}
let a2Second = a2Seen.count == 1 ? newAlert(2, after: a2Seen) != nil : false
row("A2", a2Seen.count == 1 && holds(a2Texts.first, bad1Text) && !a2Second,
    "alerts \(a2Seen.count); a second within 2 s: \(a2Second); texts \(a2Texts); "
    + "expected \(bad1Text ?? "<probed>")")

// A3 (#195.3): the sheet's door, a commit that throws: its error, then the refusal.
let a3Before = doc.project.snapshot.media.map { "\($0.id)=\($0.path)" }
let noMedia = (doc.project.snapshot.media.map { $0.id }.max() ?? 0) + 1000
var a3Thrown: String?
var a3Refusal: String?
if let tone = try? MediaImporter.probeBlocking(url: toneA),
    let mov = try? MediaImporter.probeBlocking(url: movie)
{
    let ops: [ReelOp] = [
        .relinkMedia(media: m1, path: tone.path, bookmark: tone.bookmark, probe: tone),
        .relinkMedia(media: noMedia, path: mov.path, bookmark: mov.bookmark, probe: mov),
    ]
    do { _ = try doc.project.applying(ops) } catch { a3Thrown = error.localizedDescription }
    a3Refusal = expected(m1, toneA)
}
doc.relinkMedia([(media: m1, url: toneA), (media: noMedia, url: movie)], alertingRefusals: true)
var a3Seen: [NSWindow] = []
var a3Texts: [[String]] = []
if let first = newAlert(20, after: []) {
    a3Seen.append(first)
    _ = waitUntil(0.5) { false }
    a3Texts.append(end(first))
    if let second = newAlert(10, after: a3Seen) {
        a3Seen.append(second)
        a3Texts.append(end(second))
    }
}
let a3Third = a3Seen.count == 2 ? newAlert(2, after: a3Seen) != nil : false
let a3After = doc.project.snapshot.media.map { "\($0.id)=\($0.path)" }
row("A3", a3Seen.count == 2 && holds(a3Texts.first, a3Thrown)
        && holds(a3Texts.count > 1 ? a3Texts[1] : nil, a3Refusal) && !a3Third
        && a3After == a3Before,
    "alerts \(a3Seen.count); a third within 2 s: \(a3Third); paths unchanged: "
    + "\(a3After == a3Before); texts \(a3Texts); expected \(a3Thrown ?? "<no throw>") / "
    + "\(a3Refusal ?? "<no refusal>")")

func probeError(_ text: String) -> NSError {
    NSError(domain: "RelinkSheetProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}

/// A4 and A5: `blocker` is up, E1 is presented, the blocker ends 1 s later;
/// E1's alert, then E2's after it, then none.
func blockedRow(_ id: String, _ blockerWindow: NSWindow?, _ endBlocker: () -> Void) {
    let up = waitUntil(3) { window.attachedSheet != nil && window.attachedSheet === blockerWindow }
    let presented = Date()
    doc.present(probeError("probe alert one"))
    _ = waitUntil(1) { false }
    endBlocker()
    var seen: [NSWindow] = []
    var shown: [[String]] = []
    var firstAt: Double?
    if let first = newAlert(4, after: [], besides: [blockerWindow]) {
        firstAt = Date().timeIntervalSince(presented)
        seen.append(first)
        shown.append(end(first))
        _ = waitUntil(0.2) { false }
        doc.present(probeError("probe alert two"))
        if let second = newAlert(2, after: seen, besides: [blockerWindow]) {
            seen.append(second)
            shown.append(end(second))
        }
    }
    let third = seen.count == 2 ? newAlert(2, after: seen, besides: [blockerWindow]) != nil : false
    row(id, up != nil && seen.count == 2 && holds(shown.first, "probe alert one")
            && holds(shown.count > 1 ? shown[1] : nil, "probe alert two") && !third,
        "blocker attached: \(seconds(up)); alerts \(seen.count); E1's attached "
        + "\(seconds(firstAt)) after its present; a third within 2 s: \(third); texts \(shown)")
}

// A4: a sheet that is not an alert (a bare view controller's).
let bare = NSViewController()
bare.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
_ = waitUntil(3) { window.attachedSheet == nil }
host.presentAsSheet(bare)
_ = waitUntil(3) { bare.view.window != nil }
blockedRow("A4", bare.view.window) { host.dismiss(bare) }

// A5: an alert sheet, the kind the `beginSheetModal(for:)` sites attach.
_ = waitUntil(3) { window.attachedSheet == nil }
let blocker = NSAlert()
blocker.messageText = "probe blocker"
blocker.beginSheetModal(for: window, completionHandler: nil)
blockedRow("A5", blocker.window) { window.endSheet(blocker.window) }

finish()
