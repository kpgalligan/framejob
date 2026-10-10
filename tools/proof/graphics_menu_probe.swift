// Road map 10, G5b — Insert ▸ Graphic, File ▸ Add Font/Image to Graphics…,
// Help ▸ Graphics Reference; the probe (`graphics_menu_proof.py` builds and
// runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
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
let graphicItem = insert?.items.first { $0.title == "Graphic" }
let graphic = graphicItem?.submenu
let graphicTitles = graphic?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
let wantTitles = ["Bar Chart", "Callout", "Counter", "Kinetic Type", "Lower Third",
                  "Title Card", "—", "From File…"]
let templateItems = graphic?.items.filter {
    $0.action == #selector(EditorViewController.insertGraphicTemplate(_:))
} ?? []
let bytesMatch = templateItems.map { item -> String in
    guard let url = item.representedObject as? URL else { return "\(item.title): no URL" }
    let source = templatesURL.appendingPathComponent(url.lastPathComponent)
    let same = (try? Data(contentsOf: url)) == (try? Data(contentsOf: source))
        && (try? Data(contentsOf: url)) != nil
    return same ? "ok" : "\(item.title): \(url.path) differs from \(source.path)"
}
let editIndex = barTitles.firstIndex(of: "Edit")
check("M2 the menu bar has Insert right after Edit, holding Adjustment Clip then Graphic; "
      + "Insert ▸ Graphic is the six templates by "
      + "title, a separator and From File…; each template's representedObject is a URL whose "
      + "bytes equal graphic/tests/graphics/",
      editIndex != nil && barTitles.indices.contains((editIndex ?? 0) + 1)
          && barTitles[(editIndex ?? 0) + 1] == "Insert"
          && insert?.items.map(\.title) == ["Adjustment Clip", "Graphic"]
          && graphicTitles == wantTitles
          && graphic?.items.last?.action
              == #selector(EditorViewController.insertGraphicFromFile(_:))
          && templateItems.count == 6 && bytesMatch.allSatisfy { $0 == "ok" },
      "bar \(barTitles); Insert \(insert?.items.map(\.title) ?? []); Graphic \(graphicTitles); "
          + "bytes \(bytesMatch)")

let file = mainMenu.items.first { $0.title == "File" }?.submenu
let fileTitles = file?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
let help = mainMenu.items.first { $0.title == "Help" }?.submenu
let helpTitles = help?.items.map(\.title) ?? []
let consolidate = fileTitles.firstIndex(of: "Consolidate Media…") ?? -10
let fontItem = file?.items.first { $0.title == "Add Font to Graphics…" }
let imageItem = file?.items.first { $0.title == "Add Image to Graphics…" }
let referenceItem = help?.items.first { $0.title == "Graphics Reference" }
let fromFileItem = graphic?.items.first {
    $0.title == "From File…" && $0.action == #selector(EditorViewController.insertGraphicFromFile(_:))
}
let newItems = templateItems + [fromFileItem, fontItem, imageItem, referenceItem]
    .compactMap { $0 }
let keyed = newItems.filter { !$0.keyEquivalent.isEmpty }.map(\.title)
check("M3 File holds Add Font to Graphics… then Add Image to Graphics… right after "
      + "Consolidate Media…; Help holds Graphics Reference after Reelcut Help; none of the ten "
      + "new items has a key equivalent",
      fileTitles.indices.contains(consolidate + 2)
          && fileTitles[consolidate + 1] == "Add Font to Graphics…"
          && fileTitles[consolidate + 2] == "Add Image to Graphics…"
          && fontItem?.action == #selector(EditorViewController.addGraphicFont(_:))
          && imageItem?.action == #selector(EditorViewController.addGraphicImage(_:))
          && helpTitles == ["Reelcut Help", "Graphics Reference"]
          && referenceItem?.action == #selector(AppDelegate.showGraphicsReference(_:))
          && newItems.count == 10 && keyed.isEmpty,
      "File \(fileTitles); Help \(helpTitles); \(newItems.count) new items; keyed \(keyed)")

// MARK: - M4: no window

let editorSelectors = [
    #selector(EditorViewController.insertGraphicTemplate(_:)),
    #selector(EditorViewController.insertGraphicFromFile(_:)),
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
check("M4 with no window the four editor selectors have no target; Graphics Reference "
      + "validates true, and false once GraphicsAPI.md is moved away (CONTROL)",
      targets.allSatisfy { $0 == nil } && liveBefore && moved && !liveAfter && restored,
      "targets \(targets.map { $0.map { "\($0)" } ?? "nil" }), before \(liveBefore), moved "
          + "\(moved), after \(liveAfter), restored \(restored), \(reference.path)")

// MARK: - M5: the editor's validator

func openDocument(_ url: URL) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(from: url, ofType: "com.kgalligan.reelcut-project")
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
check("M5 the four editor items validate false before startGraphicStore() and true after",
      offBefore == [false, false, false, false] && onAfter == [true, true, true, true],
      "before \(offBefore), after \(onAfter)")

guard let store = document.graphicStore, let undo = document.undoManager else {
    check("M0 the document has a store and an undo manager", false)
    finish()
}

// MARK: - M6, M7: the template item, twice

let second: Ticks = 600_000
func graphicClips() -> [ClipSnapshot] {
    document.project.snapshot.clips.filter { $0.graphic != nil }
}
func names() -> [String] { graphicClips().compactMap { $0.graphic?.name }.sorted() }
let lowerThird = templateItems.first { $0.title == "Lower Third" }
let lowerSource = try? Data(contentsOf: templatesURL.appendingPathComponent("lower-third.js"))
let folder = store.folderURL

document.playhead = 2 * second
let countBefore = document.project.snapshot.clips.count
controller.insertGraphicTemplate(lowerThird)
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
check("M6 Insert ▸ Graphic ▸ Lower Third at 2 s: graphics/lower-third.js byte-equal to the "
      + "template, one clip named lower-third at 1 200 000 lasting 3 000 000, undo name "
      + "\"Insert Graphic\"; a run-loop turn closes the event group (level 0); one undo removes "
      + "the clip, the file stays, canUndo is then false",
      lowerThird != nil && lowerSource != nil && written == lowerSource
          && countAfter == countBefore + 1 && landed.count == 1 && clip?.graphic?.name == "lower-third"
          && clip?.start == 1_200_000 && clip?.duration == 3_000_000
          && actionName == "Insert Graphic" && level6 == 0 && canUndo6
          && afterUndo == 0 && fileStays && !undo.canUndo,
      "item \(lowerThird != nil), bytes equal \(written == lowerSource), clips \(landed.map { "\($0.graphic?.name ?? "?") \($0.start)+\($0.duration)" }), "
          + "undo name \(actionName), level \(level6), canUndo \(canUndo6), after undo "
          + "\(afterUndo), file \(fileStays), canUndo after \(undo.canUndo)")

controller.insertGraphicTemplate(lowerThird)
let second7 = names()
let written7 = try? Data(contentsOf: folder.appendingPathComponent("lower-third-2.js"))
spin(0.3)
let level7 = undo.groupingLevel
check("M7 the same item again writes lower-third-2.js and places a clip named lower-third-2; "
      + "a run-loop turn leaves level 0, so it is a CLOSED step",
      second7 == ["lower-third-2"] && written7 == lowerSource && level7 == 0,
      "clips \(second7), bytes equal \(written7 == lowerSource), level \(level7)")

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
