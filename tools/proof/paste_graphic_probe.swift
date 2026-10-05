// Issue batch B85 phase 2 (#103, spec §11 G-32) — Edit ▸ Paste Graphic
// Properties, the person's door to `paste_attributes`' `graphic` group,
// driven through the app's own `EditorViewController`, `ProjectDocument` and
// main menu.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, with `-D REELCUT_DEV_TOOLS` (`UIMenu` exists
// only there), against `libreelcut_core.a`. One process:
//
//   paste_graphic_probe
//
// The answer is one JSON object on stdout, `{"rows": [...]}`, each row
// `{"id", "pass", "detail", "instrument"}`; `paste_graphic_probe.py` prints
// and scores them. Every wait pumps `RunLoop.main` and is bounded.
//
// The fixture: an untitled `ProjectDocument` and its `EditorViewController`
// as the content of a 1440×900 window owned by an `NSWindowController` added
// to the document, so `windowForSheet` is that window
// (`sheet_queue_probe.swift`'s set-up). Its clips are placed by ops: graphic
// A and graphic B drawn by `lower-third` (different props, key order, size;
// B trimmed at its head and given a length), graphic C drawn by
// `title-card`, and a text clip. No module file exists and none is needed:
// nothing here claims a picture.
//
// **The pasteboard is a PRIVATE named one**, released at exit. Every Copy and
// every paste here names it, `NSPasteboard.general` is never written, and K6
// holds its `changeCount` to what it was at start. K3, K4 and K7 call the
// door's body, `pasteGraphicProps(from:)`; K1 holds the item to the action's
// selector; and K8 SENDS that selector, `pasteGraphicProperties:`, to the
// controller with the private pasteboard as its sender — the action reads a
// pasteboard sender in place of the general one (a menu sends its
// `NSMenuItem`) — so the line that joins the item to the body is measured.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1800)),
                 "instrument": instrument])
}

let general = NSPasteboard.general
let generalCount = general.changeCount
let board = NSPasteboard(
    name: NSPasteboard.Name("com.kgalligan.reelcut.proof.paste-graphic.\(getpid())"))
board.clearContents()

var document: ProjectDocument?
func finish() -> Never {
    board.releaseGlobally()
    document?.removeTemporaryCacheDirectory()
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}

func pause(_ limit: Double) { _ = waitUntil(limit) { false } }

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

/// Every text field's string in a sheet's view tree.
func texts(_ sheet: NSWindow) -> [String] {
    (sheet.contentView.map(walk) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        .filter { !$0.isEmpty }
}

func canonical(_ value: Any?) -> String {
    guard let value, JSONSerialization.isValidJSONObject(value),
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    else { return "nil" }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - K1 — the menu item (no document needed)

let SEC: Ticks = 600_000
let doorSelector = "pasteGraphicProperties:"

let menu = AppDelegate().buildMainMenu()
let edit = menu.items.first { $0.title == "Edit" }?.submenu
let editTitles = edit?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? []
if let edit, let at = edit.items.firstIndex(where: { $0.title == "Paste Attributes" }),
    at + 1 < edit.items.count
{
    let next = edit.items[at + 1]
    let selector = UIMenu.selector(of: next) ?? "nil"
    let verdict = UIMenu.verdicts[doorSelector]?.rawValue ?? "missing"
    let once = edit.items.filter { $0.title == "Paste Graphic Properties" }.count
    row("K1",
        next.title == "Paste Graphic Properties" && selector == doorSelector
            && next.keyEquivalent.isEmpty && verdict == UIMenu.Verdict.plain.rawValue && once == 1,
        "after \"Paste Attributes\": \"\(next.title)\", action \(selector), key equivalent "
        + "\"\(next.keyEquivalent)\"; UIMenu.verdicts[\(doorSelector)] = \(verdict); "
        + "items so titled: \(once)")
} else {
    row("K1", false, "Edit has no item after \"Paste Attributes\": \(editTitles)")
}

// MARK: - The fixture

let doc = ProjectDocument()
document = doc
let controller = EditorViewController(document: doc)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
let windowController = NSWindowController(window: window)
doc.addWindowController(windowController)
windowController.showWindow(nil)
pause(0.3)

let scored = ["K2", "K3", "K4", "K5", "K6", "K7", "K8"]
func abandon(_ why: String) -> Never {
    for id in scored where !rows.contains(where: { $0["id"] as? String == id }) {
        row(id, false, "not run: \(why)", instrument: true)
    }
    finish()
}

guard let manager = doc.undoManager else { abandon("the document has no undo manager") }
guard let back = doc.project.snapshot.tracks.first?.id else { abandon("no track") }
doc.performGroupedEdit("Tracks", [.addTrack(index: 1), .addTrack(index: 2)])
let trackIDs = doc.project.snapshot.tracks.map { $0.id }
guard trackIDs.count == 3 else { abandon("the fixture has \(trackIDs.count) tracks") }

/// The id of the one clip an op adds.
func added(_ name: String, _ op: ReelOp) -> UInt32 {
    let before = Set(doc.project.snapshot.clips.map { $0.id })
    doc.performGroupedEdit(name, [op])
    guard let id = doc.project.snapshot.clips.map({ $0.id }).first(where: { !before.contains($0) })
    else { abandon("\(name) placed no clip") }
    return id
}
let clipA = added("A", .addGraphicClipRaw(
    track: trackIDs[1], at: 0, duration: 5 * SEC, name: "lower-third", width: 1920, height: 1080,
    props: ["title": "Ada", "accent": "#ff0000", "subtitle": "Host"]))
let clipB = added("B", .addGraphicClipRaw(
    track: trackIDs[1], at: 6 * SEC, duration: 4 * SEC, name: "lower-third", width: 1280,
    height: 720, props: ["subtitle": "Guest", "legacy": 3, "title": "Bob"]))
let clipC = added("C", .addGraphicClipRaw(
    track: trackIDs[2], at: 0, duration: 2 * SEC, name: "title-card", width: 1920, height: 1080,
    props: ["title": "Chapter"]))
let clipT = added("T", .addTextClip(track: trackIDs[0], at: 0, duration: 2 * SEC))
doc.performGroupedEdit("Trim", [.trimStart(clip: clipB, to: 7 * SEC)])
doc.performGroupedEdit("Length", [.setGraphicRaw(clips: [clipB], patch: ["length": 6 * SEC])])
manager.removeAllActions()
controller.refreshFromDocument(isLive: false)
pause(0.2)

func projectJSON() -> String { doc.project.json }

/// One timeline clip out of the project JSON, as the core wrote it.
func clip(_ id: UInt32) -> [String: Any] {
    guard let data = projectJSON().data(using: .utf8),
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let clips = root["clips"] as? [[String: Any]]
    else { return [:] }
    return clips.first { ($0["id"] as? NSNumber)?.uint32Value == id } ?? [:]
}

func graphic(_ id: UInt32) -> [String: Any] { clip(id)["graphic"] as? [String: Any] ?? [:] }

/// A graphic's name, size, in and length — what a target keeps.
func kept(_ id: UInt32) -> String {
    let g = graphic(id)
    return canonical(["name": g["name"] ?? NSNull(), "width": g["width"] ?? NSNull(),
                      "height": g["height"] ?? NSNull(), "in": g["in"] ?? NSNull(),
                      "length": g["length"] ?? NSNull()])
}

func undoState() -> String {
    "canUndo \(manager.canUndo) \"\(manager.undoActionName)\", canRedo \(manager.canRedo) "
        + "\"\(manager.redoActionName)\", groupingLevel \(manager.groupingLevel)"
}

func select(_ ids: [UInt32]) {
    doc.selection = Set(ids)
    controller.refreshFromDocument(isLive: false)
}

func copy(_ ids: [UInt32]) -> Bool {
    select(ids)
    return controller.copySelection(to: board)
}

/// The door as a menu event runs it: its undo, if any, one group.
func door() {
    doc.inUndoGroupIfRegistered { controller.pasteGraphicProps(from: board) }
    pause(0.2)
}

/// Ends a sheet a row did not expect, so the next row starts clear.
func settle() -> [String]? {
    guard waitUntil(0.6, { window.attachedSheet != nil }), let sheet = window.attachedSheet
    else { return nil }
    let shown = texts(sheet)
    window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
    _ = waitUntil(3) { window.attachedSheet == nil }
    return shown
}

func validates(_ name: String) -> Bool {
    controller.validateClipboardAction(NSSelectorFromString(name), pasteboard: board) ?? false
}

// Every door call below can end in the document's alert, which is a sheet on
// this window or, with no sheet window, an app-modal alert that never
// returns. So nothing is called unless the window is the document's.
let sheetWindow = doc.windowForSheet === window
guard sheetWindow, window.attachedSheet == nil else {
    abandon("windowForSheet is the window: \(sheetWindow); a sheet is already attached: "
        + "\(window.attachedSheet != nil)")
}
let fixture = "A \(clipA) \(canonical(graphic(clipA))); B \(clipB) \(canonical(graphic(clipB)))"
guard graphic(clipA)["name"] as? String == "lower-third",
    graphic(clipB)["name"] as? String == "lower-third",
    graphic(clipC)["name"] as? String == "title-card",
    (graphic(clipB)["in"] as? NSNumber)?.int64Value == Int64(SEC),
    canonical(graphic(clipA)["props"]) != canonical(graphic(clipB)["props"])
else { abandon("the fixture is not what the rows assume: \(fixture)") }

// MARK: - K2 — the validator arm

board.clearContents()
select([clipB])
let emptyDoor = validates(doorSelector)
let emptyAttributes = validates("pasteAttributes:")
let copiedForK2 = copy([clipA])
select([clipT])
let textDoor = validates(doorSelector)
let textAttributes = validates("pasteAttributes:")
select([clipB, clipT])
let graphicDoor = validates(doorSelector)
select([])
let noneDoor = validates(doorSelector)
let noneAttributes = validates("pasteAttributes:")
row("K2",
    copiedForK2 && !emptyDoor && !textDoor && graphicDoor && !noneDoor
        && !emptyAttributes && textAttributes && !noneAttributes,
    "Paste Graphic Properties validates — empty pasteboard, a graphic selected: \(emptyDoor); "
    + "a payload, only the text clip selected: \(textDoor); a payload, a graphic and the text "
    + "clip selected: \(graphicDoor); a payload, nothing selected: \(noneDoor). Paste "
    + "Attributes — empty pasteboard: \(emptyAttributes); a payload, the text clip selected: "
    + "\(textAttributes); a payload, nothing selected: \(noneAttributes)")

// MARK: - K3 — the door copies the props onto the same graphic's clip only

do {
    let before = projectJSON()
    let propsA = canonical(graphic(clipA)["props"])
    let keptB = kept(clipB)
    let restB = canonical(clip(clipB).filter { $0.key != "graphic" })
    let wasC = canonical(clip(clipC))
    let wasT = canonical(clip(clipT))
    let wasA = canonical(clip(clipA))
    let copied = copy([clipA])
    select([clipB, clipC, clipT])
    door()
    let stray = settle()
    let propsB = canonical(graphic(clipB)["props"])
    let name = manager.undoActionName
    let others = canonical(clip(clipC)) == wasC && canonical(clip(clipT)) == wasT
        && canonical(clip(clipA)) == wasA
    let keeps = kept(clipB) == keptB
        && canonical(clip(clipB).filter { $0.key != "graphic" }) == restB
    let landed = propsB == propsA
    if manager.canUndo { manager.undo() }
    pause(0.1)
    let restored = projectJSON() == before
    row("K3",
        copied && stray == nil && landed && keeps && others && name == "Paste Graphic Properties"
            && restored && !manager.canUndo,
        "copied A: \(copied); B's props equal A's: \(landed) (\(propsB)); B keeps its name, "
        + "size, in and length and everything outside graphic: \(keeps) (\(keptB)); A, C and "
        + "the text clip as they were: \(others); undo \"\(name)\"; one undo restores the "
        + "project text: \(restored), canUndo \(manager.canUndo)"
        + (stray.map { "; an unexpected sheet: \($0.joined(separator: " | "))" } ?? ""))
}

// MARK: - K4 — nothing to do is the beep: no change, no step, no sheet

do {
    let before = projectJSON()
    let state = undoState()
    let copiedA = copy([clipA])
    select([clipC, clipT])
    door()
    let strayOne = settle()
    let first = projectJSON() == before && undoState() == state && strayOne == nil
    let afterFirst = undoState()
    let copiedT = copy([clipT])
    select([clipB])
    door()
    let straySecond = settle()
    let second = projectJSON() == before && undoState() == state && straySecond == nil
    row("K4", copiedA && copiedT && first && second,
        "a copied graphic onto {C, text}: project, undo state and no sheet as before: \(first) "
        + "(\(afterFirst)); a copied text clip onto B: \(second) (\(undoState())); before: \(state)")
}

// MARK: - K5 — ⌥⌘V still copies the look and no props

do {
    doc.performGroupedEdit("Opacity", [.setVideoRaw(clips: [clipA], patch: ["opacity": 0.5])])
    let before = projectJSON()
    let wasGraphic = canonical(graphic(clipB))
    let videoA = canonical(clip(clipA)["video"])
    let differs = canonical(clip(clipB)["video"]) != videoA
    let copied = copy([clipA])
    select([clipB])
    doc.inUndoGroupIfRegistered { controller.pasteAttributes(from: board) }
    pause(0.2)
    let stray = settle()
    let videoB = canonical(clip(clipB)["video"])
    let nowGraphic = canonical(graphic(clipB))
    let name = manager.undoActionName
    if projectJSON() != before, manager.canUndo { manager.undo() }
    pause(0.1)
    row("K5",
        copied && differs && stray == nil && videoB == videoA && nowGraphic == wasGraphic
            && name == "Paste Attributes" && projectJSON() == before,
        "A's opacity set to 0.5 and A copied: \(copied); the videos differed first: \(differs); "
        + "after Paste Attributes B's video equals A's: \(videoB == videoA); B's graphic is "
        + "what it was: \(nowGraphic == wasGraphic) (\(nowGraphic)); undo \"\(name)\""
        + (stray.map { "; an unexpected sheet: \($0.joined(separator: " | "))" } ?? ""))
}

// MARK: - K7 — a malformed copied map: the beep with no taker, an alert with one

do {
    let sentence = "props.list must be a string, a number or a boolean, not [1]"
    let copied = copy([clipA])
    var written = false
    if let data = board.data(forType: EditorViewController.clipsPasteboardType),
        var payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        var clips = payload["clips"] as? [[String: Any]], !clips.isEmpty,
        var copiedGraphic = clips[0]["graphic"] as? [String: Any],
        var props = copiedGraphic["props"] as? [String: Any]
    {
        props["list"] = [1]
        copiedGraphic["props"] = props
        clips[0]["graphic"] = copiedGraphic
        payload["clips"] = clips
        if let malformed = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys])
        {
            board.declareTypes([EditorViewController.clipsPasteboardType], owner: nil)
            written = board.setData(malformed, forType: EditorViewController.clipsPasteboardType)
        }
    }
    let before = projectJSON()
    let state = undoState()
    if !(copied && written) {
        row("K7", false, "the malformed payload could not be written to the private "
            + "pasteboard (copied \(copied), written \(written))", instrument: true)
    } else {
        select([clipC, clipT])
        door()
        let stray = settle()
        let unread = projectJSON() == before && undoState() == state && stray == nil
        if !(doc.windowForSheet === window) || window.attachedSheet != nil {
            row("K7", false, "the alert half was not run: windowForSheet is no longer the "
                + "window, or a sheet is attached", instrument: true)
        } else {
            select([clipB])
            door()
            let attached = waitUntil(5) { window.attachedSheet != nil }
            let shown = window.attachedSheet.map(texts) ?? []
            let says = shown.contains { $0.contains(sentence) }
            if let sheet = window.attachedSheet {
                window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
            }
            let ended = waitUntil(3) { window.attachedSheet == nil }
            let unchanged = projectJSON() == before && undoState() == state
            row("K7", unread && attached && says && ended && unchanged,
                "onto {C, text}: project, undo state and no sheet as before: \(unread)"
                + (stray.map { " (a sheet: \($0.joined(separator: " | ")))" } ?? "")
                + "; onto B: a sheet attached within 5 s: \(attached), its text holds the "
                + "core's sentence: \(says) (\(shown.joined(separator: " | "))); ended: "
                + "\(ended); project and undo state as before: \(unchanged) (\(undoState()))")
        }
    }
}

// MARK: - K8 — the menu's ACTION, sent its own selector with the private pasteboard

do {
    // A's opacity is still K5's 0.5 and B's is not, so an action that ran
    // ⌥⌘V's body here would change B's video and leave its props.
    let action = NSSelectorFromString(doorSelector)
    let before = projectJSON()
    let wasName = manager.undoActionName
    let propsA = canonical(graphic(clipA)["props"])
    let differed = canonical(graphic(clipB)["props"]) != propsA
        && canonical(clip(clipB)["video"]) != canonical(clip(clipA)["video"])
    let keptB = kept(clipB)
    let restB = canonical(clip(clipB).filter { $0.key != "graphic" })
    let wasC = canonical(clip(clipC))
    let wasT = canonical(clip(clipT))
    let wasA = canonical(clip(clipA))
    let copied = copy([clipA])
    select([clipB, clipC, clipT])
    if !(copied && differed) {
        row("K8", false, "not run: the fixture is not what the row assumes (copied A: "
            + "\(copied); B's props and video differ from A's: \(differed))", instrument: true)
    } else if !(doc.windowForSheet === window) || window.attachedSheet != nil {
        row("K8", false, "not run: windowForSheet is no longer the window, or a sheet is "
            + "attached", instrument: true)
    } else if !controller.responds(to: action) {
        row("K8", false, "the controller does not respond to \(doorSelector)")
    } else {
        // What a menu item does with its action, the sender apart.
        doc.inUndoGroupIfRegistered { _ = controller.perform(action, with: board) }
        pause(0.2)
        let stray = settle()
        let propsB = canonical(graphic(clipB)["props"])
        let name = manager.undoActionName
        let others = canonical(clip(clipC)) == wasC && canonical(clip(clipT)) == wasT
            && canonical(clip(clipA)) == wasA
        let keeps = kept(clipB) == keptB
            && canonical(clip(clipB).filter { $0.key != "graphic" }) == restB
        let landed = propsB == propsA
        let changed = projectJSON() != before
        if changed, manager.canUndo { manager.undo() }
        pause(0.1)
        let restored = projectJSON() == before && manager.undoActionName == wasName
        row("K8",
            stray == nil && landed && keeps && others && name == "Paste Graphic Properties"
                && restored,
            "\(doorSelector) sent to the controller with the private pasteboard as its sender "
            + "— copied A: \(copied); B's props and video differed from A's first: \(differed); "
            + "B's props equal A's: \(landed) (\(propsB)); B keeps its name, size, in and length "
            + "and everything outside graphic: \(keeps); A, C and the text clip as they were: "
            + "\(others); the project changed: \(changed); undo \"\(name)\" (\"\(wasName)\" "
            + "before); one undo restores the project text and that name: \(restored)"
            + (stray.map { "; an unexpected sheet: \($0.joined(separator: " | "))" } ?? ""))
    }
}

// MARK: - K6 — the owner's pasteboard was never written

row("K6", general.changeCount == generalCount,
    "NSPasteboard.general.changeCount at start \(generalCount), at end \(general.changeCount)")

finish()
