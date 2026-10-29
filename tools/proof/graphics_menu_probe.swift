// Road map 10, G5b — Insert ▸ Graphic…, File ▸ Add Font/Image to Graphics…,
// Help ▸ Graphics Reference; the probe (`graphics_menu_proof.py` builds and
// runs it). Since spec §11 G-45 Insert ▸ Graphic… is the graphic browser:
// M21–M23 hold `GraphicCatalog` over fixture items, and M24–M32 drive the
// browser through its own controls (found by accessibility identifier), as
// M16–M20 drive the file sheet; M33–M37 its Export… (spec §11 G-46 (a)).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — with `Fonts/`,
// `GraphicTemplates/` and `GraphicsAPI.md` copied beside the binary (its
// `resourceURL`, where the app finds all three). Every row drives the app's
// own `AppDelegate`, `ProjectDocument`, `GraphicStore`, `GraphicRegistry` and
// `EditorViewController`.
//
//   graphics_menu_probe <request.json> <answer.json>
//
// `request.json` names `package` and `bare` (two COPIES of the module-less
// fixture the proof made over MCP), `templates` (`graphic/tests/graphics/`),
// `scratch` (a directory the probe writes its own files into), `oswald` and
// `red`; and, for M14–M20 (issue batch B84's phase 2, spec §11 G-30),
// `files` (a COPY of GF) with `title_a` and `title_b`, the two texts GF's
// `title` was written with. One JSON object out: `rows`, each a name, ok
// and detail.
//
// **How M16–M20 reach a confirm** (no dev tool presses a sheet's default
// button): on the probe's own `EditorViewController` over `files`, in an
// unshown window, a row sets `selection`, calls the editor's own action
// (`deleteGraphic(nil)`), waits for `attachedSheet`, selects the pop-up's
// row by `representedObject` and sends the pop-up's action, writes the field
// and hands its delegate the text-change, and sends the `graphicfile.confirm`
// button's own action to its own target. A disabled button is never sent.
//
// **No row calls `endUndoGrouping`** (app/CLAUDE.md: never flush the manager
// to level zero). A command called here runs OUTSIDE any AppKit event, so
// `applyEdit`'s registration opens the implicit event group; a run-loop turn
// in `.default` mode closes it the way AppKit does (`text_apply_probe.swift`'s
// `spin`).
import AppKit
import CryptoKit

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

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}
func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    try? data.write(to: out)
    exit(0)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func path(_ key: String) -> URL? {
    (request[key] as? String).map { URL(fileURLWithPath: $0) }
}
guard let packageURL = path("package"), let bareURL = path("bare"),
      let templatesURL = path("templates"), let scratch = path("scratch"),
      let oswald = path("oswald"), let red = path("red")
else {
    check("M0 the request names package, bare, templates, scratch, oswald and red", false)
    finish()
}

// MARK: - M2, M3: the menu bar

let delegate = AppDelegate()
let mainMenu = delegate.buildMainMenu()
let barTitles = mainMenu.items.map(\.title)
let insert = mainMenu.items.first { $0.title == "Insert" }?.submenu
let graphicItem = insert?.items.first { $0.title == "Graphic…" }
let editIndex = barTitles.firstIndex(of: "Edit")
check("M2 the menu bar has Insert right after Edit, holding Adjustment Clip then Graphic… — "
      + "one item with no submenu, its action showGraphicBrowser: (spec §11 G-45 (f))",
      editIndex != nil && barTitles.indices.contains((editIndex ?? 0) + 1)
          && barTitles[(editIndex ?? 0) + 1] == "Insert"
          && insert?.items.map(\.title) == ["Adjustment Clip", "Graphic…"]
          && graphicItem?.submenu == nil
          && graphicItem?.action == #selector(EditorViewController.showGraphicBrowser(_:)),
      "bar \(barTitles); Insert \(insert?.items.map(\.title) ?? []); Graphic… submenu "
          + "\(graphicItem?.submenu != nil), action "
          + "\(graphicItem?.action.map(NSStringFromSelector) ?? "nil")")

let file = mainMenu.items.first { $0.title == "File" }?.submenu
let fileTitles = file?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
let help = mainMenu.items.first { $0.title == "Help" }?.submenu
let helpTitles = help?.items.map(\.title) ?? []
let consolidate = fileTitles.firstIndex(of: "Consolidate Media…") ?? -10
let fontItem = file?.items.first { $0.title == "Add Font to Graphics…" }
let imageItem = file?.items.first { $0.title == "Add Image to Graphics…" }
let referenceItem = help?.items.first { $0.title == "Graphics Reference" }
let newItems = [graphicItem, fontItem, imageItem, referenceItem].compactMap { $0 }
let keyed = newItems.filter { !$0.keyEquivalent.isEmpty }.map(\.title)
check("M3 File holds Add Font to Graphics… then Add Image to Graphics… right after "
      + "Consolidate Media…; Help holds Graphics Reference after Frame Job Help; none of the four "
      + "items (Graphic…, the two Adds, Graphics Reference) has a key equivalent",
      fileTitles.indices.contains(consolidate + 2)
          && fileTitles[consolidate + 1] == "Add Font to Graphics…"
          && fileTitles[consolidate + 2] == "Add Image to Graphics…"
          && fontItem?.action == #selector(EditorViewController.addGraphicFont(_:))
          && imageItem?.action == #selector(EditorViewController.addGraphicImage(_:))
          && helpTitles == ["Frame Job Help", "Graphics Reference"]
          && referenceItem?.action == #selector(AppDelegate.showGraphicsReference(_:))
          && newItems.count == 4 && keyed.isEmpty,
      "File \(fileTitles); Help \(helpTitles); \(newItems.count) items; keyed \(keyed)")

// MARK: - M4: no window

let editorSelectors = [
    #selector(EditorViewController.showGraphicBrowser(_:)),
    #selector(EditorViewController.addGraphicFont(_:)),
    #selector(EditorViewController.addGraphicImage(_:)),
]
let targets = editorSelectors.map { NSApp.target(forAction: $0) }
/// File's three graphic-file items (M14–M20), in menu order.
let fileActs: [(title: String, action: Selector)] = [
    ("Rename Graphic…", #selector(EditorViewController.renameGraphic(_:))),
    ("Delete Graphic…", #selector(EditorViewController.deleteGraphic(_:))),
    ("Restore Graphic Version…", #selector(EditorViewController.restoreGraphicVersion(_:))),
]
let fileActTargets = fileActs.map { NSApp.target(forAction: $0.action) }
let reference = GraphicStore.bundledReferenceURL
let aside = scratch.appendingPathComponent("GraphicsAPI.md.aside")
let liveBefore = referenceItem.map { delegate.validateMenuItem($0) } ?? false
try? FileManager.default.removeItem(at: aside)
let moved = (try? FileManager.default.moveItem(at: reference, to: aside)) != nil
let liveAfter = referenceItem.map { delegate.validateMenuItem($0) } ?? true
let restored = (try? FileManager.default.moveItem(at: aside, to: reference)) != nil
check("M4 with no window the three editor selectors have no target; Graphics Reference "
      + "validates true, and false once GraphicsAPI.md is moved away (CONTROL)",
      targets.allSatisfy { $0 == nil } && liveBefore && moved && !liveAfter && restored,
      "targets \(targets.map { $0.map { "\($0)" } ?? "nil" }), before \(liveBefore), moved "
          + "\(moved), after \(liveAfter), restored \(restored), \(reference.path)")

// MARK: - M21..M23: the catalog over fixture items (spec §11 G-45 (a), (d), (e))

func fixtureItem(
    _ name: String, _ title: String, _ category: String, _ origin: GraphicBrowserItem.Origin
) -> GraphicBrowserItem {
    GraphicBrowserItem(
        name: name, title: title, description: nil, category: category, origin: origin, ok: true)
}
func outline(_ categories: [GraphicBrowserCategory]) -> [String] {
    categories.map { "\($0.name): " + $0.items.map { "\($0.title) [\($0.name)]" }.joined(separator: ", ") }
}

let blank = GraphicCatalog.category(meta: [:])
let spaces = GraphicCatalog.category(meta: ["category": "   "])
let number = GraphicCatalog.category(meta: ["category": 5])
let padded = GraphicCatalog.category(meta: ["category": " Screencast "])
let itemNoMeta = GraphicCatalog.item(name: "plain-module", entry: nil, origin: .template)
check("M21 a module with no category is filed under Other: meta {} , a blank string and a "
      + "number are Other, \" Screencast \" is Screencast; an item with no meta is Other, titled "
      + "from its stem, not ok",
      blank == "Other" && spaces == "Other" && number == "Other" && padded == "Screencast"
          && itemNoMeta.category == "Other" && itemNoMeta.title == "Plain Module"
          && itemNoMeta.description == nil && !itemNoMeta.ok,
      "{} \(blank), blank \(spaces), 5 \(number), padded \(padded); item \(itemNoMeta)")

let fixtureTemplates = [
    fixtureItem("zz", "Zed", "Zeta", .template),
    fixtureItem("misc", "Misc", "Other", .template),
    fixtureItem("b2", "banana", "Alpha", .template),
    fixtureItem("b1", "Banana", "Alpha", .template),
    fixtureItem("ap", "apple", "Alpha", .template),
    fixtureItem("be", "Bee", "beta", .template),
]
let noProject = GraphicCatalog.categories(templates: fixtureTemplates, project: [])
let wantNoProject = ["Alpha: apple [ap], Banana [b1], banana [b2]", "beta: Bee [be]",
                     "Zeta: Zed [zz]", "Other: Misc [misc]"]
check("M22 with no project module there is no This Project: the categories by case-insensitive "
      + "name, Other last, each graphic by title case-insensitively then name",
      outline(noProject) == wantNoProject,
      "\(outline(noProject))")

let fixtureProject = [
    fixtureItem("lower-third-2", "Lower third", "Titles & Text", .project),
    fixtureItem("arrow", "Arrow", "Screencast", .project),
    fixtureItem("lower-third", "lower third", "Titles & Text", .project),
]
let withProject = GraphicCatalog.categories(templates: fixtureTemplates, project: fixtureProject)
let wantWithProject = ["This Project: Arrow [arrow], lower third — lower-third [lower-third], "
                           + "Lower third — lower-third-2 [lower-third-2]"] + wantNoProject
check("M23 with project modules This Project comes first and lists every one whatever its own "
      + "category; two whose titles match case-insensitively read \"<title> — <name>\"; the "
      + "templates' categories follow in M22's order",
      outline(withProject) == wantWithProject,
      "\(outline(withProject))")

// MARK: - M5: the editor's validator

func openDocument(_ url: URL) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = url
        return document
    } catch {
        check("M0 \(url.lastPathComponent) opens", false, "\(error)")
        return nil
    }
}
guard let document = openDocument(packageURL) else { finish() }
let controller = EditorViewController(document: document)
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
spin(0.3)

func validates() -> [Bool] {
    editorSelectors.map { action in
        controller.validateUserInterfaceItem(NSMenuItem(title: "x", action: action,
                                                         keyEquivalent: ""))
    }
}
func fileValidates(_ editor: EditorViewController) -> [Bool] {
    fileActs.map { act in
        editor.validateUserInterfaceItem(NSMenuItem(title: "x", action: act.action,
                                                     keyEquivalent: ""))
    }
}
let offBefore = validates()
let fileOffBefore = fileValidates(controller)
document.startGraphicStore()
let onAfter = validates()
check("M5 the three editor items validate false before startGraphicStore() and true after",
      offBefore == [false, false, false] && onAfter == [true, true, true],
      "before \(offBefore), after \(onAfter)")

guard let store = document.graphicStore, let undo = document.undoManager else {
    check("M0 the document has a store and an undo manager", false)
    finish()
}

// MARK: - The browser, driven through its own controls

let second: Ticks = 600_000
func graphicClips() -> [ClipSnapshot] {
    document.project.snapshot.clips.filter { $0.graphic != nil }
}
func names() -> [String] { graphicClips().compactMap { $0.graphic?.name }.sorted() }
let lowerSource = try? Data(contentsOf: templatesURL.appendingPathComponent("lower-third.js"))
let folder = store.folderURL
/// The `.js` files `graphics/` holds, sorted.
func modulesOnDisk() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        .filter { $0.hasSuffix(".js") }.sorted()
}

/// Pumps until `condition` holds or `limit` seconds pass; whether it held.
func pumpUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}
func subviews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(subviews) }
struct Browser {
    let window: NSWindow
    let controller: GraphicBrowserSheetController
    let categories: NSTableView
    let graphics: NSTableView
    let preview: NSImageView
    let title: NSTextField
    let message: NSTextField
    let insert: NSButton
    let fromFile: NSButton
    let cancel: NSButton
    /// Export… (G-46); looked for but not required, so a missing one fails M33 alone.
    let export: NSButton?

    func rows(_ table: NSTableView) -> [String] {
        (0..<table.numberOfRows).map { row in
            (table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?
                .textField?.stringValue ?? "?"
        }
    }
    /// The row reading `text` selected; whether there was one.
    func choose(_ table: NSTableView, _ text: String) -> Bool {
        guard let row = rows(table).firstIndex(of: text) else { return false }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return true
    }
    /// A button's own action sent to its own target, never a disabled one's.
    func press(_ button: NSButton) -> Bool {
        guard button.isEnabled, let action = button.action,
              window === button.window?.sheetParent?.attachedSheet
        else { return false }
        return NSApp.sendAction(action, to: button.target, from: button)
    }
}
/// The editor's own action called and the browser waited for.
func openBrowser() -> Browser? {
    controller.showGraphicBrowser(nil)
    guard pumpUntil(3, { window.attachedSheet != nil }), let sheet = window.attachedSheet,
          let browser = sheet.contentViewController as? GraphicBrowserSheetController
    else { return nil }
    let views = sheet.contentView.map(subviews) ?? []
    func find<T>(_ id: String, _ type: T.Type) -> T? {
        views.first { $0.accessibilityIdentifier() == id } as? T
    }
    guard let categories = find("graphicbrowser.categories", NSTableView.self),
          let graphics = find("graphicbrowser.graphics", NSTableView.self),
          let preview = find("graphicbrowser.preview", NSImageView.self),
          let title = find("graphicbrowser.title", NSTextField.self),
          let message = find("graphicbrowser.message", NSTextField.self),
          let insertButton = find("graphicbrowser.insert", NSButton.self),
          let fromFile = find("graphicbrowser.fromFile", NSButton.self),
          let cancel = find("graphicbrowser.cancel", NSButton.self)
    else { return nil }
    return Browser(
        window: sheet, controller: browser, categories: categories, graphics: graphics,
        preview: preview, title: title, message: message, insert: insertButton,
        fromFile: fromFile, cancel: cancel, export: find("graphicbrowser.export", NSButton.self))
}
func browserGone() -> Bool {
    pumpUntil(3) { !(window.attachedSheet?.contentViewController is GraphicBrowserSheetController) }
}
/// Whatever sheet a failed row left attached, ended.
func clearBrowser() {
    if let stuck = window.attachedSheet { window.endSheet(stuck) }
    spin(0.3)
}
/// Every category's graphics as the sheet's tables show them, the first
/// category selected again afterwards.
func tableOutline(_ browser: Browser) -> [String] {
    let names = browser.rows(browser.categories)
    var lines: [String] = []
    for (row, name) in names.enumerated() {
        browser.categories.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        lines.append("\(name): " + browser.rows(browser.graphics).joined(separator: ", "))
    }
    if !names.isEmpty {
        browser.categories.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
    return lines
}
func catalogOutline() -> [String] {
    GraphicCatalog.categories(for: document).map {
        "\($0.name): " + $0.items.map(\.title).joined(separator: ", ")
    }
}

// M24..M27 — open, the lists, the preview, Insert with nothing chosen, Esc

var ok24 = false, ok25 = false, ok26 = false, ok27 = false, ok33 = false
var detail24 = "the sheet did not attach", detail25 = "", detail26 = "", detail27 = ""
var detail33 = "the sheet did not attach"
/// M34's first half: Export… with no graphic chosen.
var exportNoneEnabled: Bool?
let catalog24 = GraphicCatalog.categories(for: document)
if let browser = openBrowser() {
    let shown = tableOutline(browser)
    let wanted = catalogOutline()
    let firstCategory = browser.categories.selectedRow
    let firstGraphic = browser.graphics.selectedRow
    let titled = browser.title.stringValue
    let live = browser.insert.isEnabled
    let firstName = catalog24.first?.name
    let firstTitle = catalog24.first?.items.first?.title
    ok24 = shown == wanted && catalog24.count >= 4 && firstName == "Data & Time"
        && firstCategory == 0 && firstGraphic == 0 && titled == firstTitle && live
    detail24 = "tables \(shown) vs catalog \(wanted); opened on category \(firstCategory) "
        + "(\(firstName ?? "nil")), graphic \(firstGraphic), title \(titled.debugDescription) "
        + "(\(firstTitle ?? "nil")), Insert enabled \(live)"

    let pictured = pumpUntil(3) { browser.preview.image != nil }
    let drawn = browser.controller.player.drawn
    let thread = browser.controller.player.thread
    ok25 = pictured && drawn.frames > 0 && !drawn.onMain && thread != nil && thread !== Thread.main
    detail25 = "image within 3 s \(pictured), frames \(drawn.frames), any on main \(drawn.onMain), "
        + "thread \(thread?.name ?? "nil")"

    // M33 — Export… leftmost in the bottom bar, titled, enabled on the opening graphic.
    func minX(_ button: NSButton?) -> CGFloat {
        button.map { $0.convert($0.bounds, to: nil).minX } ?? .infinity
    }
    let exportX = minX(browser.export)
    let others = [browser.fromFile, browser.cancel, browser.insert].map(minX)
    ok33 = browser.export != nil && others.allSatisfy { exportX < $0 }
        && browser.export?.title == "Export…" && browser.export?.isEnabled == true
    detail33 = "export \(browser.export != nil) at minX \(exportX) vs From File…, Cancel, Insert "
        + "\(others); title \(browser.export?.title.debugDescription ?? "nil"), enabled "
        + "\(browser.export?.isEnabled == true) on \(titled.debugDescription)"

    browser.graphics.deselectAll(nil)
    exportNoneEnabled = browser.export?.isEnabled
    let dimmed = !browser.insert.isEnabled
    let cleared = browser.title.stringValue.isEmpty
    ok26 = dimmed && cleared && browser.graphics.selectedRow == -1
    detail26 = "graphic row \(browser.graphics.selectedRow), Insert disabled \(dimmed), title "
        + "cleared \(cleared)"

    let clips = document.project.snapshot.clips.count
    let escape = browser.cancel.keyEquivalent == "\u{1b}"
    let pressed = browser.press(browser.cancel)
    let gone = browserGone()
    ok27 = escape && pressed && gone && modulesOnDisk().isEmpty
        && document.project.snapshot.clips.count == clips && !undo.canUndo
    detail27 = "Cancel's key Esc \(escape), pressed \(pressed), gone \(gone), graphics/ "
        + "\(modulesOnDisk()), clips \(document.project.snapshot.clips.count) vs \(clips), canUndo "
        + "\(undo.canUndo)"
}
clearBrowser()
check("M24 Insert ▸ Graphic… opens the browser on the first category (Data & Time — no This "
      + "Project on a package with no module) and its first graphic, the title shown and Insert "
      + "enabled; the two tables' rows, category by category, equal "
      + "GraphicCatalog.categories(for:)",
      ok24, detail24)
check("M25 the preview shows a picture within 3 s, drawn on the player's own thread (no frame on "
      + "main)",
      ok25, detail25)
check("M26 with the graphic deselected Insert is disabled and the title cleared", ok26, detail26)
check("M27 Cancel (Esc) closes the browser and writes nothing: no module, no clip, no undo step",
      ok27, detail27)
check("M33 Export… is the bottom bar's leftmost button (its minX below From File…'s, Cancel's and "
      + "Insert's), titled \"Export…\", and enabled on the opening graphic",
      ok33, detail33)

// M6, M28 — Titles & Text ▸ Lower third through the Insert button

document.playhead = 2 * second
var ok6 = false, ok28 = false
var detail6 = "the sheet did not attach", detail28 = "the sheet did not attach"
if let browser = openBrowser() {
    let countBefore = document.project.snapshot.clips.count
    let chose = browser.choose(browser.categories, "Titles & Text")
        && browser.choose(browser.graphics, "Lower third")
    let thread = browser.controller.player.thread
    let pressed = browser.press(browser.insert)
    let gone = browserGone()
    let finished = pumpUntil(2) { thread?.isFinished == true }
    ok28 = thread != nil && finished
    detail28 = "thread \(thread?.name ?? "nil"), finished within 2 s \(finished)"
    let countAfter = document.project.snapshot.clips.count
    let actionName = undo.undoActionName
    let landed = graphicClips()
    let written = try? Data(contentsOf: folder.appendingPathComponent("lower-third.js"))
    let clip = landed.first
    spin(0.3)
    let level6 = undo.groupingLevel
    let canUndo6 = undo.canUndo
    undo.undo()
    let afterUndo = graphicClips().count
    let fileStays = FileManager.default.fileExists(
        atPath: folder.appendingPathComponent("lower-third.js").path)
    ok6 = chose && pressed && gone && lowerSource != nil && written == lowerSource
        && countAfter == countBefore + 1 && landed.count == 1
        && clip?.graphic?.name == "lower-third" && clip?.start == 1_200_000
        && clip?.duration == 3_000_000 && actionName == "Insert Graphic" && level6 == 0
        && canUndo6 && afterUndo == 0 && fileStays && !undo.canUndo
    detail6 = "chose \(chose), pressed \(pressed), browser gone \(gone), bytes equal "
        + "\(written == lowerSource), clips \(landed.map { "\($0.graphic?.name ?? "?") \($0.start)+\($0.duration)" }), "
        + "undo name \(actionName), level \(level6), canUndo \(canUndo6), after undo "
        + "\(afterUndo), file \(fileStays), canUndo after \(undo.canUndo)"
}
clearBrowser()
check("M6 the browser's Titles & Text ▸ Lower third, Insert pressed at 2 s: the browser closes, "
      + "graphics/lower-third.js byte-equal to the template, one clip named lower-third at "
      + "1 200 000 lasting 3 000 000, undo name \"Insert Graphic\"; a run-loop turn closes the "
      + "event group (level 0); one undo removes the clip, the file stays, canUndo is then false",
      ok6, detail6)
check("M28 after that Insert the preview's render thread has exited within 2 s", ok28, detail28)

// M7, M29, M30 — the same template again; This Project; a project graphic placed with no copy

var ok7 = false
var detail7 = "the sheet did not attach"
if let browser = openBrowser() {
    let chose = browser.choose(browser.categories, "Titles & Text")
        && browser.choose(browser.graphics, "Lower third")
    let pressed = browser.press(browser.insert)
    let gone = browserGone()
    let second7 = names()
    let written7 = try? Data(contentsOf: folder.appendingPathComponent("lower-third-2.js"))
    spin(0.3)
    let level7 = undo.groupingLevel
    ok7 = chose && pressed && gone && second7 == ["lower-third-2"] && written7 == lowerSource
        && level7 == 0
    detail7 = "chose \(chose), pressed \(pressed), gone \(gone), clips \(second7), bytes equal "
        + "\(written7 == lowerSource), level \(level7)"
}
clearBrowser()
check("M7 the same graphic again writes lower-third-2.js and places a clip named lower-third-2; "
      + "a run-loop turn leaves level 0, so it is a CLOSED step",
      ok7, detail7)

var ok29 = false, ok30 = false
var detail29 = "the sheet did not attach", detail30 = "the sheet did not attach"
let catalog29 = GraphicCatalog.categories(for: document)
if let browser = openBrowser() {
    let shown = tableOutline(browser)
    let wanted = catalogOutline()
    let ours = catalog29.first
    let wantedOurs = ["Lower third — lower-third", "Lower third — lower-third-2"]
    ok29 = shown == wanted && ours?.name == "This Project"
        && ours?.items.map(\.title) == wantedOurs
        && ours?.items.allSatisfy { $0.origin == .project && $0.category == "Titles & Text" } == true
    detail29 = "first \(ours?.name ?? "nil"): \(ours?.items.map(\.title) ?? []); tables \(shown) "
        + "vs catalog \(wanted)"

    let opened = browser.categories.selectedRow == 0
        && browser.rows(browser.categories).first == "This Project"
    let onDisk = modulesOnDisk()
    let clips = document.project.snapshot.clips.count
    let chose = browser.choose(browser.graphics, "Lower third — lower-third-2")
    let pressed = browser.press(browser.insert)
    let gone = browserGone()
    let after = names()
    let actionName = undo.undoActionName
    let unwritten = modulesOnDisk() == onDisk
    spin(0.3)
    let level = undo.groupingLevel
    undo.undo()
    ok30 = opened && chose && pressed && gone && unwritten
        && document.project.snapshot.clips.count == clips
        && after == ["lower-third-2", "lower-third-2"] && actionName == "Insert Graphic"
        && level == 0 && names() == ["lower-third-2"]
    detail30 = "opened on This Project \(opened), chose \(chose), pressed \(pressed), gone "
        + "\(gone), graphics/ \(onDisk) → \(modulesOnDisk()), clips \(after), undo name "
        + "\(actionName), level \(level), after undo \(names())"
}
clearBrowser()
check("M29 after two inserts of Lower third, This Project comes first listing \"Lower third — "
      + "lower-third\" and \"Lower third — lower-third-2\" (each its module's own category); the "
      + "tables equal GraphicCatalog.categories(for:)",
      ok29, detail29)
check("M30 the browser opens on This Project; lower-third-2 inserted from it writes no file and "
      + "places one more clip drawn by lower-third-2, \"Insert Graphic\", level 0; undo takes it "
      + "back",
      ok30, detail30)

// MARK: - M8: From File…'s body, grouped

let counterCopy = scratch.appendingPathComponent("My Counter (v2).js")
try? FileManager.default.removeItem(at: counterCopy)
try? FileManager.default.copyItem(
    at: templatesURL.appendingPathComponent("counter.js"), to: counterCopy)
var thrown8 = ""
do {
    try controller.insertGraphic(from: counterCopy, grouped: true)
} catch {
    thrown8 = error.localizedDescription
}
let names8 = names()
let level8 = undo.groupingLevel
undo.undo()
let names8b = names()
check("M8 insertGraphic(from: \"My Counter (v2).js\", grouped: true) → module my-counter-v2, "
      + "level 0 at once; one undo removes my-counter-v2 and lower-third-2 STAYS; canUndo "
      + "still true",
      thrown8.isEmpty && names8 == ["lower-third-2", "my-counter-v2"]
          && store.module(named: "my-counter-v2") != nil && level8 == 0
          && names8b == ["lower-third-2"] && undo.canUndo,
      "thrown \(thrown8), clips \(names8), level \(level8), after undo \(names8b), canUndo "
          + "\(undo.canUndo)")

// MARK: - M9: a module that does not compile

let broken = scratch.appendingPathComponent("broken.js")
try? Data("export function render() { return".utf8).write(to: broken)
let clips9 = document.project.snapshot.clips.count
let canUndo9 = undo.canUndo
var thrown9 = ""
do {
    try controller.insertGraphic(from: broken, grouped: true)
} catch {
    thrown9 = error.localizedDescription
}
check("M9 a .js that does not compile throws a sentence naming the module and \"does not "
      + "compile\"; the file stays, no clip, canUndo unchanged",
      thrown9.contains("broken") && thrown9.contains("does not compile")
          && FileManager.default.fileExists(atPath: folder.appendingPathComponent("broken.js").path)
          && document.project.snapshot.clips.count == clips9 && undo.canUndo == canUndo9,
      "thrown \(thrown9), clips \(document.project.snapshot.clips.count) vs \(clips9), "
          + "canUndo \(undo.canUndo) vs \(canUndo9)")

// MARK: - M31: a This Project module that does not compile, inserted from the browser

var want31 = ""
do { _ = try document.graphicClipMaker(named: "broken") } catch { want31 = error.localizedDescription }
let brokenTitle = GraphicCatalog.categories(for: document).first?.items
    .first { $0.name == "broken" }?.title
var ok31 = false
var detail31 = "the sheet did not attach"
/// M34's second half: Export… on a This Project module that does not compile.
var exportBrokenEnabled: Bool?
if let browser = openBrowser() {
    let clips = document.project.snapshot.clips.count
    let canUndo = undo.canUndo
    let chose = brokenTitle.map { browser.choose(browser.graphics, $0) } ?? false
    exportBrokenEnabled = browser.export?.isEnabled
    let pressed = browser.press(browser.insert)
    spin(0.5)
    let stays = window.attachedSheet === browser.window
    let shown = browser.message.stringValue
    let cancelled = browser.press(browser.cancel) && browserGone()
    ok31 = !want31.isEmpty && want31.hasPrefix("graphics/broken.js does not compile: ")
        && chose && pressed && stays && shown == want31
        && document.project.snapshot.clips.count == clips && undo.canUndo == canUndo && cancelled
    detail31 = "title \(brokenTitle ?? "nil"), chose \(chose), pressed \(pressed), stays \(stays), "
        + "message \(shown.debugDescription) (wanted \(want31.debugDescription)), clips "
        + "\(document.project.snapshot.clips.count) vs \(clips), canUndo \(undo.canUndo) vs "
        + "\(canUndo), Cancel detached \(cancelled)"
}
clearBrowser()
check("M31 This Project's broken (does not compile) chosen and Insert pressed: the browser stays "
      + "up with graphicClipMaker's sentence word for word in graphicbrowser.message (\"graphics/"
      + "broken.js does not compile: …\"), no clip, the undo stack unmoved; Cancel closes it",
      ok31, detail31)
check("M34 Export… is disabled with no graphic chosen and on This Project's broken (does not "
      + "compile)",
      exportNoneEnabled == false && exportBrokenEnabled == false,
      "no graphic chosen: enabled \(exportNoneEnabled.map(String.init) ?? "no button"); broken: "
          + "enabled \(exportBrokenEnabled.map(String.init) ?? "no button")")

// MARK: - M32: From File… — the browser goes down, then the open panel comes up

var ok32 = false
var detail32 = "the sheet did not attach"
if let browser = openBrowser() {
    let pressed = browser.press(browser.fromFile)
    let panelUp = pumpUntil(2) { window.attachedSheet is NSOpenPanel }
    let gone = !(window.attachedSheet?.contentViewController is GraphicBrowserSheetController)
    let attached = window.attachedSheet.map { String(describing: type(of: $0)) } ?? "nothing"
    if let panel = window.attachedSheet as? NSOpenPanel {
        window.endSheet(panel, returnCode: .cancel)
    }
    let cleared = pumpUntil(2) { window.attachedSheet == nil }
    ok32 = pressed && panelUp && gone && cleared
    detail32 = "pressed \(pressed), an NSOpenPanel attached within 2 s \(panelUp) (\(attached)), "
        + "the browser gone \(gone), cleared after cancelling \(cleared)"
}
clearBrowser()
check("M32 From File… pressed: within 2 s the browser is gone and an NSOpenPanel is the window's "
      + "attached sheet (then cancelled)",
      ok32, detail32)

// MARK: - M35..M37: Export… — the save panel on the browser, the package, nothing edited

var ok35 = false, ok36 = false, ok37 = false
var detail35 = "the sheet did not attach", detail36 = "not reached", detail37 = "not reached"
if let browser = openBrowser() {
    let handle = document.project
    let undoBefore = "\(undo.canUndo) \(undo.undoActionName) \(undo.canRedo)"
    let chose = browser.choose(browser.categories, "Titles & Text")
        && browser.choose(browser.graphics, "Lower third")
    let pressed = browser.export.map { browser.press($0) } ?? false
    let panelUp = pumpUntil(2) { browser.window.attachedSheet is NSSavePanel }
    let panel = browser.window.attachedSheet as? NSSavePanel
    let named = panel?.nameFieldStringValue ?? "nil"
    let upWithPanel = window.attachedSheet === browser.window
    if let panel = panel { browser.window.endSheet(panel, returnCode: .cancel) }
    let panelGone = pumpUntil(2) { browser.window.attachedSheet == nil }
    ok35 = chose && pressed && panelUp && named == "lower-third.fjgraphic" && upWithPanel
        && panelGone
    detail35 = "chose \(chose), pressed \(pressed), an NSSavePanel on the browser within 2 s "
        + "\(panelUp), named \(named.debugDescription), browser up \(upWithPanel), panel "
        + "cancelled \(panelGone)"

    let target = scratch.appendingPathComponent("lower-third.fjgraphic")
    try? FileManager.default.removeItem(at: target)
    browser.controller.exportChosen(to: target)
    let started = browser.controller.exporting
    let done = pumpUntil(30) { !browser.controller.exporting }
    let head = (try? FileHandle(forReadingFrom: target)).map { handle -> Data in
        defer { try? handle.close() }
        return handle.readData(ofLength: 4)
    }
    let message = browser.message.stringValue
    let wanted = "Exported Lower third to lower-third.fjgraphic: lower-third.js."
    ok36 = started && done && head == Data([0x50, 0x4B, 0x03, 0x04]) && message == wanted
    detail36 = "started \(started), finished within 30 s \(done), head "
        + "\(head.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "no file"), message "
        + "\(message.debugDescription) (wanted \(wanted.debugDescription))"

    let thread = browser.controller.exportThread
    let finished = pumpUntil(2) { thread?.isFinished == true }
    let stillUp = window.attachedSheet === browser.window
    let undoAfter = "\(undo.canUndo) \(undo.undoActionName) \(undo.canRedo)"
    ok37 = stillUp && document.project === handle && undoAfter == undoBefore && finished
        && thread?.name == "com.kgalligan.framejob.graphic-export"
    detail37 = "browser up \(stillUp), project handle the same \(document.project === handle), "
        + "undo \(undoBefore) → \(undoAfter), export thread \(thread?.name ?? "nil") finished "
        + "\(finished)"
    _ = browser.press(browser.cancel) && browserGone()
}
clearBrowser()
check("M35 Titles & Text ▸ Lower third, Export… pressed: within 2 s an NSSavePanel is the "
      + "browser's attached sheet, named lower-third.fjgraphic, the browser still up; then "
      + "cancelled",
      ok35, detail35)
check("M36 exportChosen(to:) writes a file beginning PK\\x03\\x04 within 30 s and the message reads "
      + "\"Exported Lower third to lower-third.fjgraphic: lower-third.js.\"",
      ok36, detail36)
check("M37 through M35–M36 the browser stays up, the project handle and the undo state are "
      + "unchanged, and the export thread (com.kgalligan.framejob.graphic-export) has finished",
      ok37, detail37)

// MARK: - M11: a module written from the shell a moment before is not overwritten (#75)

let outsideCounter = folder.appendingPathComponent("counter.js")
let outsideBytes = Data("// written outside the app\n".utf8)
try? outsideBytes.write(to: outsideCounter)
let counterSource = try? Data(contentsOf: templatesURL.appendingPathComponent("counter.js"))
var thrown11 = ""
do {
    try controller.insertGraphic(
        from: templatesURL.appendingPathComponent("counter.js"), grouped: true)
} catch {
    thrown11 = error.localizedDescription
}
let names11 = names()
let counterKept = (try? Data(contentsOf: outsideCounter)) == outsideBytes
let counter2 = try? Data(contentsOf: folder.appendingPathComponent("counter-2.js"))
if names11.contains("counter-2") { undo.undo() }
check("M11 graphics/counter.js written straight to disk, then at once (no run-loop turn) "
      + "insertGraphic(from: templates/counter.js): a clip counter-2, counter.js unchanged, "
      + "counter-2.js equal to the template",
      thrown11.isEmpty && names11 == ["counter-2", "lower-third-2"] && counterKept
          && counterSource != nil && counter2 == counterSource,
      "thrown \(thrown11), clips \(names11), counter.js kept \(counterKept), counter-2.js "
          + "equal \(counter2 == counterSource), after undo \(names())")

// MARK: - M12: a module that is not UTF-8 is refused before it is written

let latin1 = scratch.appendingPathComponent("latin1.js")
try? Data([0x2f, 0x2f, 0x20, 0x63, 0x61, 0x66, 0xe9, 0x0a]).write(to: latin1)
let clips12 = document.project.snapshot.clips.count
var thrown12 = ""
do {
    try controller.insertGraphic(from: latin1, grouped: true)
} catch {
    thrown12 = error.localizedDescription
}
let want12 = "\(latin1.path) is not UTF-8 text — a graphic module must be UTF-8 JavaScript"
let latinWritten = FileManager.default.fileExists(
    atPath: folder.appendingPathComponent("latin1.js").path)
check("M12 insertGraphic of a latin1.js holding \"// caf\\xE9\" throws the UTF-8 sentence; "
      + "graphics/latin1.js is absent and the clip count unchanged",
      thrown12 == want12 && !latinWritten && document.project.snapshot.clips.count == clips12,
      "thrown \(thrown12), written \(latinWritten), clips "
          + "\(document.project.snapshot.clips.count) vs \(clips12)")

// MARK: - M13: Add Image's body renames a name asset(name) cannot use, and says so (#105)

/// Pumps until `condition` holds or `limit` seconds pass; whether it held.
func waitUntil(_ limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < limit {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
}
func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }
/// Every non-empty text field's string in a sheet's view tree.
func texts(_ sheet: NSWindow) -> [String] {
    (sheet.contentView.map(walk) ?? []).compactMap { ($0 as? NSTextField)?.stringValue }
        .filter { !$0.isEmpty }
}
let oddCopy = scratch.appendingPathComponent("#logo&mark.png")
let plainCopy = scratch.appendingPathComponent("plain.png")
for copy in [oddCopy, plainCopy] {
    try? FileManager.default.removeItem(at: copy)
    try? FileManager.default.copyItem(at: red, to: copy)
}
var thrown13 = ""
do { try controller.addGraphicImage(from: oddCopy) } catch { thrown13 = "\(error)" }
let shown13 = waitUntil(3) { window.attachedSheet != nil }
let sheet13 = window.attachedSheet
let texts13 = sheet13.map(texts) ?? []
let want13 = GraphicAssetName.renameNotice(from: "#logo&mark.png", to: "logo-mark.png")
let listed13 = store.scan.assets.map(\.name)
if let sheet13 = sheet13 { window.endSheet(sheet13) }
spin(0.3)
var thrownPlain = ""
do { try controller.addGraphicImage(from: plainCopy) } catch { thrownPlain = "\(error)" }
spin(0.5)
let plainSheet = window.attachedSheet != nil
let listedPlain = store.scan.assets.map(\.name)
if let stray = window.attachedSheet { window.endSheet(stray) }
check("M13 addGraphicImage(from: \"#logo&mark.png\") files logo-mark.png and attaches a sheet "
      + "within 3 s whose text is exactly the rename notice; CONTROL: plain.png attaches no "
      + "sheet in 0.5 s and is listed",
      thrown13.isEmpty && shown13 && texts13 == [want13] && listed13.contains("logo-mark.png")
          && thrownPlain.isEmpty && !plainSheet && listedPlain.contains("plain.png"),
      "thrown \(thrown13), sheet \(shown13), texts \(texts13), assets \(listed13); plain: thrown "
          + "\(thrownPlain), sheet \(plainSheet), assets \(listedPlain)")

// MARK: - M10: the imports on a package with no module

guard let bare = openDocument(bareURL) else { finish() }
bare.startGraphicStore()
guard let bareStore = bare.graphicStore else {
    check("M10 the bare package has a store", false)
    finish()
}
let notes = scratch.appendingPathComponent("notes.txt")
try? Data("notes".utf8).write(to: notes)
var font: (url: URL, replaced: Bool, families: [String])?
var fontError = "", textFontError = "", textAssetError = "", assetError = ""
do { font = try bareStore.importFont(from: oswald) } catch { fontError = "\(error)" }
let library = GraphicRegistry.shared.snapshot(for: bare.recipeKey)?.library.families() ?? []
do { _ = try bareStore.importFont(from: notes) } catch {
    textFontError = error.localizedDescription
}
do { _ = try bareStore.importAsset(from: red, as: red.lastPathComponent) } catch {
    assetError = "\(error)"
}
let assets = bareStore.scan.assets.map(\.name)
do { _ = try bareStore.importAsset(from: notes, as: notes.lastPathComponent) } catch {
    textAssetError = error.localizedDescription
}
let fontsFolder = bareStore.folderURL.appendingPathComponent("fonts")
check("M10 on a package with NO module: importFont(Oswald-Medium.ttf) answers [\"Oswald\"], "
      + "lands in fonts/, and the registry's library holds Oswald at once; a .txt is refused "
      + "naming .ttf; importAsset(red.png) lists [\"red.png\"], a .txt is refused naming PNG",
      bareStore.scan.modules.isEmpty && fontError.isEmpty && font?.families == ["Oswald"]
          && font?.url.deletingLastPathComponent().standardizedFileURL.path
              == fontsFolder.standardizedFileURL.path
          && library.contains("Oswald") && textFontError.contains(".ttf")
          && assetError.isEmpty && assets == ["red.png"] && textAssetError.contains("PNG"),
      "font \(String(describing: font)) \(fontError), library \(library), txt font "
          + "\(textFontError), asset \(assetError) \(assets), txt asset \(textAssetError)")

// MARK: - M14: File's three graphic-file items (B84 phase 2, spec §11 G-30)

let addImage = fileTitles.firstIndex(of: "Add Image to Graphics…")
let fileTail = addImage.map { Array(fileTitles[$0...]) } ?? []
let wantTail = ["Add Image to Graphics…", "—", "Rename Graphic…", "Delete Graphic…",
                "Restore Graphic Version…", "—", "Export…", "Save Frame…"]
let actItems = fileActs.map { act in file?.items.first { $0.title == act.title } }
let actActions = zip(fileActs, actItems).map { $0.1?.action == $0.0.action }
let actKeyed = actItems.compactMap { $0 }.filter { !$0.keyEquivalent.isEmpty }.map(\.title)
check("M14 File from Add Image to Graphics… on reads Add Image to Graphics…, —, Rename "
      + "Graphic…, Delete Graphic…, Restore Graphic Version…, —, Export…, Save Frame…; "
      + "the "
      + "three carry their actions and no key equivalent, and with no window none has a target",
      fileTail == wantTail && actActions == [true, true, true] && actKeyed.isEmpty
          && fileActTargets.allSatisfy { $0 == nil },
      "tail \(fileTail); actions \(actActions); keyed \(actKeyed); targets "
          + "\(fileActTargets.map { $0.map { "\($0)" } ?? "nil" })")

// MARK: - M15: the three items' validator

func makeEditor(_ document: ProjectDocument) -> (EditorViewController, NSWindow) {
    let editor = EditorViewController(document: document)
    let host = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    host.contentViewController = editor
    editor.viewWillAppear()
    editor.viewDidAppear()
    editor.refreshFromDocument(isLive: false)
    spin(0.3)
    return (editor, host)
}
spin(0.3)
let packageClear = window.attachedSheet == nil
let onPackage = fileValidates(controller)
let packageKept = store.keptNames()
let (bareEditor, bareWindow) = makeEditor(bare)
let onBare = fileValidates(bareEditor)
guard let filesURL = path("files"), let titleA = request["title_a"] as? String,
      let titleB = request["title_b"] as? String, let files = openDocument(filesURL)
else {
    check("M15 the request names files, title_a and title_b, and files opens", false)
    finish()
}
files.startGraphicStore()
let (filesEditor, filesWindow) = makeEditor(files)
guard let filesStore = files.graphicStore, let filesUndo = files.undoManager else {
    check("M15 files has a store and an undo manager", false)
    finish()
}
let filesAtOpen = files.project.snapshot
let nestID = filesAtOpen.nests.first?.id ?? 0
let nestClip = filesAtOpen.clips.first { $0.source.nestID == nestID }?.id ?? 0
/// `t` is the timeline's `title` clip, `n` the nested one.
let t = filesAtOpen.clips.first { $0.graphic?.name == "title" }?.id ?? 0
let n = filesAtOpen.nests.first?.clips.first { $0.graphic?.name == "title" }?.id ?? 0
let onFiles = fileValidates(filesEditor)
files.setNestPath([NestScopeStep(nest: nestID, clip: nestClip)], playhead: 0, selection: [])
let scopeInside = files.scope
let inNest = fileValidates(filesEditor)
files.setNestPath([], playhead: 0, selection: [])
let backOut = fileValidates(filesEditor)
check("M15 Rename, Delete, Restore validate false,false,false before startGraphicStore() and "
      + "on bare with its store; true,true,false on package (modules, nothing kept); "
      + "true,true,true on files; false,true,true with its nest open; true,true,true back out",
      fileOffBefore == [false, false, false] && onBare == [false, false, false]
          && bare.graphicStore != nil && packageClear && packageKept.isEmpty
          && onPackage == [true, true, false] && onFiles == [true, true, true]
          && t != 0 && n != 0 && nestID != 0 && scopeInside == nestID
          && inNest == [false, true, true] && backOut == [true, true, true],
      "before \(fileOffBefore), bare \(onBare), package \(onPackage) (sheet clear "
          + "\(packageClear), kept \(packageKept)), files \(onFiles), nest \(nestID) open "
          + "\(String(describing: scopeInside)) \(inNest), back out \(backOut); t \(t), n \(n)")

// MARK: - M16..M20: the sheet, driven through its own controls

func identified(_ sheet: NSWindow, _ id: String) -> NSView? {
    (sheet.contentView.map(walk) ?? []).first { $0.accessibilityIdentifier() == id }
}
struct FileSheet {
    let window: NSWindow
    let popup: NSPopUpButton
    let field: NSTextField?
    let kept: NSTextField?
    let confirm: NSButton
    let cancel: NSButton?

    /// Looked up when asked: a hidden view is out of its stack's hierarchy
    /// (`detachesHiddenViews`), so the label is not there until a refusal.
    var message: NSTextField? { identified(window, "graphicfile.message") as? NSTextField }
    var rows: [String] { popup.itemArray.map(\.title) }
    var opened: String? { popup.selectedItem?.representedObject as? String }
    var openedTitle: String? { popup.selectedItem?.title }
}
/// `selection` set, the editor's own action called, the sheet waited for.
func openSheet(selecting clips: Set<UInt32>, _ action: () -> Void) -> FileSheet? {
    files.selection = clips
    action()
    guard waitUntil(3, { filesWindow.attachedSheet != nil }),
          let sheet = filesWindow.attachedSheet,
          sheet.contentViewController is GraphicFileSheetController,
          let popup = identified(sheet, "graphicfile.popup") as? NSPopUpButton,
          let confirm = identified(sheet, "graphicfile.confirm") as? NSButton
    else { return nil }
    let buttons = (sheet.contentView.map(walk) ?? []).compactMap { $0 as? NSButton }
    return FileSheet(
        window: sheet, popup: popup,
        field: identified(sheet, "graphicfile.name") as? NSTextField,
        kept: identified(sheet, "graphicfile.kept") as? NSTextField,
        confirm: confirm, cancel: buttons.first { $0.keyEquivalent == "\u{1b}" })
}
/// The pop-up's row carrying `name`, selected, and the pop-up's own action
/// sent to its own target.
func choose(_ sheet: FileSheet, _ name: String) -> Bool {
    let rows = sheet.popup.itemArray
    guard let row = rows.first(where: { $0.representedObject as? String == name }),
          let action = sheet.popup.action
    else { return false }
    sheet.popup.select(row)
    return NSApp.sendAction(action, to: sheet.popup.target, from: sheet.popup)
}
/// `text` written into New name and its delegate told the text changed.
func typeName(_ sheet: FileSheet, _ text: String) -> Bool {
    guard let field = sheet.field, let delegate = field.delegate else { return false }
    field.stringValue = text
    delegate.controlTextDidChange?(
        Notification(name: NSControl.textDidChangeNotification, object: field))
    return true
}
/// A button's own action sent to its own target; never a disabled one, and
/// never one whose sheet is no longer the attached one — a sheet an earlier
/// step closed is not driven again (dismissing it twice raises).
func press(_ button: NSButton?) -> Bool {
    guard let button = button, button.isEnabled, let action = button.action,
          let sheet = button.window, sheet === filesWindow.attachedSheet
    else { return false }
    return NSApp.sendAction(action, to: button.target, from: button)
}
func detached() -> Bool { waitUntil(3) { filesWindow.attachedSheet == nil } }
/// Whatever sheet a failed row left attached, ended.
func clearSheet() {
    if let stuck = filesWindow.attachedSheet { filesWindow.endSheet(stuck) }
    spin(0.3)
}
let filesFolder = filesStore.folderURL
func onDisk(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: filesFolder.appendingPathComponent(name + ".js").path)
}
func bytesOf(_ name: String) -> Data? {
    try? Data(contentsOf: filesFolder.appendingPathComponent(name + ".js"))
}
func sha(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
/// The module a clip names, on the timeline or inside a nest.
func nameOf(_ id: UInt32) -> String {
    let snapshot = files.project.snapshot
    return (snapshot.clips + snapshot.nests.flatMap { $0.clips }).first { $0.id == id }?
        .graphic?.name ?? "?"
}
func keptRevisions(_ name: String) -> [String] { filesStore.kept(named: name).map(\.revision) }
func undoState() -> String {
    "\(filesUndo.undoActionName)|\(filesUndo.canUndo)|\(files.isDocumentEdited)"
}

// M16 — Delete: opened on the first, a refusal shown in the sheet

var ok16 = false
var detail16 = "the sheet did not attach"
if let sheet = openSheet(selecting: [t], { filesEditor.deleteGraphic(nil) }) {
    let rows = sheet.rows
    let opened = sheet.opened
    let returnKey = sheet.confirm.keyEquivalent == "\r"
    sheet.window.layoutIfNeeded()
    let heightBefore = sheet.window.frame.height
    let hiddenBefore = sheet.message?.isHidden ?? true
    let chose = choose(sheet, "title")
    let pressed = press(sheet.confirm)
    spin(0.5)
    let stays = filesWindow.attachedSheet === sheet.window
    let shown = sheet.message?.stringValue ?? "(no label)"
    let want = "The graphic \"title\" is still drawn by clip \(t) on the timeline and clip \(n) "
        + "in nest \(nestID); delete those clips or point them at another module "
        + "(set_graphic {name}) first"
    let intact = bytesOf("title") == Data(titleB.utf8)
    sheet.window.layoutIfNeeded()
    var visible = false, inside = false
    var needed: CGFloat = 0, labelHeight: CGFloat = 0, labelWidth: CGFloat = 0
    if let label = sheet.message, let content = sheet.window.contentView {
        visible = !label.isHidden
        inside = content.bounds.insetBy(dx: -0.5, dy: -0.5)
            .contains(label.convert(label.bounds, to: content))
        let font = label.font ?? NSFont.systemFont(ofSize: 12)
        labelWidth = label.bounds.width
        labelHeight = label.bounds.height
        needed = NSAttributedString(string: label.stringValue, attributes: [.font: font])
            .boundingRect(
                with: NSSize(width: labelWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    }
    let heightAfter = sheet.window.frame.height
    let cancelled = press(sheet.cancel) && detached()
    ok16 = rows == ["other", "spare", "title"] && opened == "other" && returnKey && hiddenBefore
        && chose && pressed && stays && shown == want && intact && visible && inside
        && labelHeight >= needed - 1 && heightAfter > heightBefore && cancelled
    detail16 = "rows \(rows), opened \(opened ?? "nil"), Return \(returnKey), hidden before "
        + "\(hiddenBefore), chose \(chose), pressed \(pressed), stays \(stays), message "
        + "\(shown.debugDescription) (wanted: \(shown == want)), title.js intact \(intact); "
        + "label visible \(visible), inside the content view \(inside), \(labelWidth) × "
        + "\(labelHeight) needing \(needed); sheet height \(heightBefore) → \(heightAfter); "
        + "Cancel detached \(cancelled)"
}
clearSheet()
check("M16 Delete with the timeline's title clip selected: rows other, spare, title, opened on "
      + "other with no message shown, the button's key Return; title confirmed: the sheet "
      + "stays, the message is "
      + "exactly the body's sentence naming both clips, title.js unchanged; the label is "
      + "shown inside the content view, tall enough for its text at its width, and the sheet "
      + "is taller than before; Cancel detaches it",
      ok16, detail16)

// M17 — Delete: a success closes the sheet and is no undo step

var ok17 = false
var detail17 = "the sheet did not attach"
if let sheet = openSheet(selecting: [t], { filesEditor.deleteGraphic(nil) }) {
    let spare = bytesOf("spare")
    let before = undoState()
    let chose = choose(sheet, "spare")
    let pressed = press(sheet.confirm)
    let closed = detached()
    let kept = keptRevisions("spare")
    ok17 = chose && pressed && closed && !onDisk("spare") && spare != nil
        && kept.first == spare.map(sha) && undoState() == before
    detail17 = "chose \(chose), pressed \(pressed), detached \(closed), spare.js on disk "
        + "\(onDisk("spare")), kept leads with its hash \(kept.first == spare.map(sha)) "
        + "(\(kept.count) kept), undo \(before) → \(undoState())"
}
clearSheet()
check("M17 Delete, spare confirmed: the sheet detaches within 3 s, spare.js is gone, "
      + "kept(spare) leads with its SHA-256, and undoActionName, canUndo and isDocumentEdited "
      + "are unmoved",
      ok17, detail17)

// M18 — Rename: opened on the selected clip's graphic; an unused graphic's
// rename is no step; a used one's is one closed step that Undo takes back

var ok18 = false
var detail18 = "the first sheet did not attach"
if let sheet = openSheet(selecting: [t], { filesEditor.renameGraphic(nil) }) {
    let rows = sheet.rows
    let opened = sheet.opened
    let filled = sheet.field?.stringValue ?? "(no field)"
    let dimmed = !sheet.confirm.isEnabled
    let chose = choose(sheet, "other")
    let refilled = sheet.field?.stringValue ?? "(no field)"
    let typed = typeName(sheet, "extra")
    let pressed = press(sheet.confirm)
    let closed = detached()
    let unused = onDisk("extra") && !onDisk("other") && nameOf(t) == "title"
        && nameOf(n) == "title" && !filesUndo.canUndo && filesUndo.undoActionName.isEmpty
        && !files.isDocumentEdited
    let first = rows == ["other", "title"] && opened == "title" && filled == "title" && dimmed
        && chose && refilled == "other" && typed && pressed && closed && unused
    detail18 = "rows \(rows), opened \(opened ?? "nil"), field \(filled), dimmed \(dimmed); "
        + "other chosen \(chose) (field \(refilled)), extra typed \(typed), pressed "
        + "\(pressed), detached \(closed), extra.js \(onDisk("extra")), other.js "
        + "\(onDisk("other")), clips \(nameOf(t))/\(nameOf(n)), undo \(undoState())"
    clearSheet()
    if let again = openSheet(selecting: [t], { filesEditor.renameGraphic(nil) }) {
        let reopened = again.opened
        let typedAgain = typeName(again, "headline")
        let live = again.confirm.isEnabled
        let pressedAgain = press(again.confirm)
        let level = filesUndo.groupingLevel
        let actionName = filesUndo.undoActionName
        let closedAgain = detached()
        let renamed = nameOf(t) == "headline" && nameOf(n) == "headline" && onDisk("headline")
            && !onDisk("title")
        filesUndo.undo()
        let undone = nameOf(t) == "title" && nameOf(n) == "title" && onDisk("title")
            && !onDisk("headline")
        filesUndo.redo()
        let redone = nameOf(t) == "headline" && nameOf(n) == "headline" && onDisk("headline")
            && !onDisk("title")
        ok18 = first && reopened == "title" && typedAgain && live && pressedAgain && level == 0
            && actionName == "Rename Graphic" && closedAgain && renamed && undone && redone
        detail18 += "; reopened on \(reopened ?? "nil"), headline typed \(typedAgain), live "
            + "\(live), pressed \(pressedAgain), level \(level), undo name \(actionName), "
            + "detached \(closedAgain), renamed \(renamed), undone \(undone), redone \(redone)"
    } else {
        detail18 += "; the second sheet did not attach"
    }
}
clearSheet()
check("M18 Rename with the timeline's title clip selected: rows other, title, opened on title "
      + "with the field title and the button dimmed; other → extra: detached, extra.js and no "
      + "other.js, no clip renamed, canUndo false, no undo name, not edited; reopened on "
      + "title, headline typed enables the button; confirmed: both clips name headline, "
      + "headline.js and no title.js, undo name \"Rename Graphic\", level 0 with no run-loop "
      + "turn; undo puts title back on the clips and the file, redo headline",
      ok18, detail18)

// M19 — Rename: two refusals, each the body's sentence, the name as typed

var ok19 = false
var detail19 = "the sheet did not attach"
if let sheet = openSheet(selecting: [t], { filesEditor.renameGraphic(nil) }) {
    let opened = sheet.opened
    let typed = typeName(sheet, "extra")
    let pressed = press(sheet.confirm)
    spin(0.5)
    let stays = filesWindow.attachedSheet === sheet.window
    let taken = sheet.message?.stringValue ?? "(no label)"
    let unmoved = onDisk("headline") && onDisk("extra") && nameOf(t) == "headline"
        && nameOf(n) == "headline"
    let typedBad = typeName(sheet, "Bad Name")
    let pressedBad = press(sheet.confirm)
    spin(0.5)
    let staysBad = filesWindow.attachedSheet === sheet.window
    let bad = sheet.message?.stringValue ?? "(no label)"
    let wantBad = GraphicStore.nameSentence("Bad Name")
    let cancelled = press(sheet.cancel) && detached()
    let still = nameOf(t) == "headline" && nameOf(n) == "headline" && onDisk("headline")
    ok19 = opened == "headline" && typed && pressed && stays
        && taken == "graphics/extra.js already exists" && unmoved && typedBad && pressedBad
        && staysBad && bad == wantBad && cancelled && still
    detail19 = "opened \(opened ?? "nil"); extra: typed \(typed), pressed \(pressed), stays "
        + "\(stays), message \(taken.debugDescription), nothing moved \(unmoved); Bad Name: "
        + "typed \(typedBad), pressed \(pressedBad), stays \(staysBad), message "
        + "\(bad.debugDescription) (wanted \(wantBad.debugDescription)); Cancel detached "
        + "\(cancelled), clips still headline \(still)"
}
clearSheet()
check("M19 Rename, opened on headline: extra typed and confirmed shows \"graphics/extra.js "
      + "already exists\", the sheet up and nothing moved; Bad Name shows exactly "
      + "GraphicStore.nameSentence(\"Bad Name\"); Cancel detaches, the clips still headline",
      ok19, detail19)

// M20 — Restore: deleted graphics are rows; a clip drawing one opens on it

files.performGroupedEdit(
    "Set Graphic", [.setGraphicRaw(clips: [t], patch: ["name": "spare"])])
var ok20 = false
var detail20 = "the first sheet did not attach"
let pointed = nameOf(t)
if let sheet = openSheet(selecting: [t], { filesEditor.restoreGraphicVersion(nil) }) {
    let rows = sheet.rows
    let listed = GraphicFileSheetController.choices(for: .restore, in: files)
    let wantListed = [
        GraphicFileChoice(name: "gone", deleted: true, kept: 1),
        GraphicFileChoice(name: "headline", deleted: false, kept: 1),
        GraphicFileChoice(name: "spare", deleted: true, kept: 1),
    ]
    let openedTitle = sheet.openedTitle
    let keptLine = sheet.kept?.stringValue ?? "(no label)"
    let deletedBytes = filesStore.kept(named: "spare").first
        .flatMap { try? Data(contentsOf: $0.url) }
    let before = filesUndo.undoActionName
    let pressed = press(sheet.confirm)
    let closed = detached()
    let restored = deletedBytes != nil && bytesOf("spare") == deletedBytes
    let first = pointed == "spare" && rows == ["gone (deleted)", "headline", "spare (deleted)"]
        && listed == wantListed && openedTitle == "spare (deleted)"
        && keptLine == "1 version kept" && pressed && closed && restored
        && keptRevisions("spare").isEmpty && filesUndo.undoActionName == before
    detail20 = "t names \(pointed); rows \(rows), choices as wanted \(listed == wantListed), "
        + "opened \(openedTitle ?? "nil"), kept line \(keptLine), pressed \(pressed), detached "
        + "\(closed), spare.js holds its deleted bytes \(restored), kept(spare) "
        + "\(keptRevisions("spare").count), undo name \(before.debugDescription) → "
        + "\(filesUndo.undoActionName.debugDescription)"
    clearSheet()
    if let again = openSheet(selecting: [t], { filesEditor.restoreGraphicVersion(nil) }) {
        let rowsAgain = again.rows
        let reopened = again.openedTitle
        let chose = choose(again, "headline")
        let pressedAgain = press(again.confirm)
        let closedAgain = detached()
        let holdsA = bytesOf("headline") == Data(titleA.utf8)
        let keptB = keptRevisions("headline") == [sha(Data(titleB.utf8))]
        ok20 = first && rowsAgain == ["gone (deleted)", "headline"]
            && reopened == "gone (deleted)" && chose && pressedAgain && closedAgain && holdsA
            && keptB
        detail20 += "; reopened: rows \(rowsAgain), opened \(reopened ?? "nil"), headline "
            + "chosen \(chose), pressed \(pressedAgain), detached \(closedAgain), headline.js "
            + "holds text a \(holdsA), kept is [sha(b)] \(keptB)"
    } else {
        detail20 += "; the second sheet did not attach"
    }
}
clearSheet()
check("M20 Restore with a clip drawing the deleted spare selected: rows gone (deleted), "
      + "headline, spare (deleted), each with 1 kept, opened on spare (deleted) with "
      + "\"1 version kept\"; confirmed: detached, spare.js holds its deleted bytes, kept(spare) "
      + "is empty, the undo name unmoved; reopened: rows gone (deleted), headline, opened on "
      + "gone (deleted); headline confirmed: headline.js holds text a and kept is [sha(b)]",
      ok20, detail20)

finish()
