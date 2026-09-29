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
// `red`. One JSON object out: `rows`, each a name, ok and detail.
//
// **No row calls `endUndoGrouping`** (app/CLAUDE.md: never flush the manager
// to level zero). A command called here runs OUTSIDE any AppKit event, so
// `applyEdit`'s registration opens the implicit event group; a run-loop turn
// in `.default` mode closes it the way AppKit does (`text_apply_probe.swift`'s
// `spin`).
import AppKit

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
check("M2 the menu bar has Insert right after Edit; Insert ▸ Graphic is the six templates by "
      + "title, a separator and From File…; each template's representedObject is a URL whose "
      + "bytes equal graphic/tests/graphics/",
      editIndex != nil && barTitles.indices.contains((editIndex ?? 0) + 1)
          && barTitles[(editIndex ?? 0) + 1] == "Insert"
          && insert?.items.map(\.title) == ["Graphic"]
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
let offBefore = validates()
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

finish()
