// Road map 10, G3a — the package's `graphics/` folder, its store and its
// watcher, driven through the app's own `GraphicStore` and `ProjectDocument`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line. It MEASURES and prints one
// JSON object; `graphics_store_probe.py` scores it with oracles of its own
// (hashlib for every revision, its own literals for every sentence).
//
//   TMPDIR=<work_dir>/tmp graphics_store_probe <fonts_dir> <asset_png> <work_dir>
//
// `TMPDIR` does NOT move `NSTemporaryDirectory()` on this host (measured
// 2026-09-25: it answers the per-user `DARWIN_USER_TEMP_DIR` whatever the
// variable says), so the untitled roots land there; the probe reports that
// directory as `tmp` and removes every root it made before it answers.
// Every wait pumps `RunLoop.main` — which is what runs the store's
// main-queue drain — in bounded polls of at most 2 s; nothing sleeps.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: graphics_store_probe fonts png work\n".utf8))
    exit(2)
}
let fontsDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let assetPNG = URL(fileURLWithPath: arguments[2])
let work = URL(fileURLWithPath: arguments[3], isDirectory: true)
let files = FileManager.default
_ = NSApplication.shared
var answer: [String: Any] = ["ok": false, "tmp": NSTemporaryDirectory()]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

// MARK: - Instruments

struct Post { let store: ObjectIdentifier; let names: [String]; let library: Bool; let t: Date }
var posts: [Post] = []
var locationPosts: [ObjectIdentifier] = []
NotificationCenter.default.addObserver(forName: .graphicsDidChange, object: nil, queue: nil) { n in
    guard let store = n.object as? GraphicStore else { return }
    posts.append(Post(
        store: ObjectIdentifier(store),
        names: n.userInfo?[GraphicStore.namesKey] as? [String] ?? ["<unreadable>"],
        library: n.userInfo?[GraphicStore.libraryKey] as? Bool ?? false, t: Date()))
}
NotificationCenter.default.addObserver(
    forName: .graphicsLocationDidChange, object: nil, queue: nil
) { n in
    if let store = n.object as? GraphicStore { locationPosts.append(ObjectIdentifier(store)) }
}

/// Pumps the main run loop for `seconds` (at most 2).
func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(min(seconds, 2))
    while Date() < end { RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.01))) }
}

/// Pumps until `condition` holds or 2 s pass; the seconds it took, or nil.
@discardableResult
func waitUntil(_ condition: () -> Bool) -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < 2 {
        if condition() { return Date().timeIntervalSince(start) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition() ? Date().timeIntervalSince(start) : nil
}

/// The posts `store` made since `mark`, as JSON.
func since(_ mark: Int, _ store: GraphicStore) -> [[String: Any]] {
    posts[mark...].filter { $0.store == ObjectIdentifier(store) }
        .map { ["names": $0.names, "library": $0.library] }
}

/// Waits for `store`'s first post after `mark`, then 0.4 s more of quiet so
/// a second post would be counted too. Answers the posts and the latency.
func settle(_ mark: Int, _ store: GraphicStore) -> [String: Any] {
    let started = Date()
    let first = waitUntil { !since(mark, store).isEmpty }
    let latency = first.map { _ in
        (posts[mark...].first { $0.store == ObjectIdentifier(store) }?.t ?? Date())
            .timeIntervalSince(started)
    }
    pump(0.4)
    return ["posts": since(mark, store), "latency": latency ?? NSNull()]
}

func write(_ text: String, _ url: URL) { try? Data(text.utf8).write(to: url) }

/// An in-place save: the file truncated and rewritten through its own inode.
func writeInPlace(_ text: String, _ url: URL) { writeInPlace(Data(text.utf8), url) }

func writeInPlace(_ data: Data, _ url: URL) {
    let fd = open(url.path, O_WRONLY | O_TRUNC)
    guard fd >= 0 else { return }
    _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    close(fd)
}

func inode(_ url: URL) -> Int {
    ((try? files.attributesOfItem(atPath: url.path))?[.systemFileNumber] as? Int) ?? -1
}

let projectType = "com.kgalligan.reelcut-project"

/// A saved package with `project.json` and nothing else.
func scratchPackage(_ name: String) -> URL {
    let url = work.appendingPathComponent(name, isDirectory: true)
    try? files.removeItem(at: url)
    let blank = ProjectDocument()
    if let wrapper = try? blank.fileWrapper(ofType: projectType) {
        try? wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
    }
    return url
}

func present(_ url: URL) -> Bool { files.fileExists(atPath: url.path) }

// MARK: - W1 — the untitled store

var callbacks = 0
let s = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
s.folderDidAppear = { callbacks += 1 }
s.start()
pump(0.3)
answer["w1"] = [
    "folder": s.folderURL.path, "exists": present(s.folderURL),
    "empty": s.scan == .empty, "callbacks": callbacks, "posts": since(0, s).count,
]
let folder = s.folderURL

// MARK: - W3 / W4 / W5 — atomic save, in-place save, removal

var mark = posts.count
write("export function render() { return '<svg/>' } // v1\n",
      folder.appendingPathComponent("a.js"))
let w3setup = settle(mark, s)
let v2 = "export function render() { return '<svg/>' } // v2, renamed over\n"
write(v2, folder.appendingPathComponent("a.js.tmp"))
mark = posts.count
let renamed = rename(folder.appendingPathComponent("a.js.tmp").path,
                     folder.appendingPathComponent("a.js").path) == 0
var row = settle(mark, s)
row["setup"] = w3setup
row["renamed"] = renamed
row["content"] = v2
row["revision"] = s.module(named: "a")?.revision ?? NSNull()
answer["w3"] = row

let v3 = "export function render() { return '<svg/>' } // v3, in place\n"
let inodeBefore = inode(folder.appendingPathComponent("a.js"))
mark = posts.count
writeInPlace(v3, folder.appendingPathComponent("a.js"))
row = settle(mark, s)
row["content"] = v3
row["revision"] = s.module(named: "a")?.revision ?? NSNull()
row["same_inode"] = inodeBefore == inode(folder.appendingPathComponent("a.js"))
answer["w4"] = row

mark = posts.count
try? files.removeItem(at: folder.appendingPathComponent("a.js"))
row = settle(mark, s)
row["gone"] = s.module(named: "a") == nil
answer["w5"] = row

// MARK: - W6 — two files back to back are one post

mark = posts.count
write("// b\n", folder.appendingPathComponent("b.js"))
write("// c\n", folder.appendingPathComponent("c.js"))
answer["w6"] = settle(mark, s)

// MARK: - W7 — a bad name and a partial are not modules

mark = posts.count
write("// Bad\n", folder.appendingPathComponent("Bad.js"))
write("// d partial\n", folder.appendingPathComponent("d.js.partial"))
pump(0.5)
answer["w7"] = [
    "posts": since(mark, s), "warnings": s.scan.warnings,
    "modules": s.scan.modules.keys.sorted(),
]
try? files.removeItem(at: folder.appendingPathComponent("Bad.js"))
try? files.removeItem(at: folder.appendingPathComponent("d.js.partial"))
pump(0.3)

// MARK: - W8 — fonts and assets move the library

let versionBefore = s.scan.libraryVersion
let face = ((try? files.contentsOfDirectory(atPath: fontsDir.path)) ?? [])
    .filter { $0.hasSuffix(".ttf") }.sorted().first ?? "none.ttf"
mark = posts.count
try? files.createDirectory(
    at: folder.appendingPathComponent("fonts"), withIntermediateDirectories: false)
try? files.copyItem(
    at: fontsDir.appendingPathComponent(face),
    to: folder.appendingPathComponent("fonts").appendingPathComponent(face))
row = settle(mark, s)
row["modules"] = s.scan.modules.keys.sorted()
row["version_before"] = versionBefore
row["version_after"] = s.scan.libraryVersion
row["fonts"] = s.scan.fonts.map { $0.name }
do {
    _ = try s.makeLibrary()
    row["library"] = "ok"
} catch {
    row["library"] = error.localizedDescription
}
let versionFonts = s.scan.libraryVersion
mark = posts.count
try? files.createDirectory(
    at: folder.appendingPathComponent("assets"), withIntermediateDirectories: false)
try? files.copyItem(
    at: assetPNG, to: folder.appendingPathComponent("assets").appendingPathComponent("logo.png"))
files.createFile(
    atPath: folder.appendingPathComponent("assets").appendingPathComponent("empty.png").path,
    contents: Data())
var assets = settle(mark, s)
assets["version_before"] = versionFonts
assets["version_after"] = s.scan.libraryVersion
assets["warnings"] = s.scan.warnings
assets["assets"] = s.scan.assets.map { $0.name }
row["assets"] = assets
answer["w8"] = row

// MARK: - W2 — a package without graphics/, and a graphics/ made from outside

let p = scratchPackage("W2.reelcut")
var packageCallbacks = 0
let ps = GraphicStore(package: p, seed: nil, bundledFonts: fontsDir)
ps.folderDidAppear = { packageCallbacks += 1 }
ps.start()
pump(0.3)
row = ["absent_after_start": !present(p.appendingPathComponent("graphics")),
       "callbacks_after_start": packageCallbacks]
let outside = work.appendingPathComponent("x.js")
write("// x from outside\n", outside)
mark = posts.count
try? files.createDirectory(
    at: p.appendingPathComponent("graphics"), withIntermediateDirectories: false)
try? files.moveItem(at: outside, to: p.appendingPathComponent("graphics/x.js"))
row["appear"] = settle(mark, ps)
row["callbacks"] = packageCallbacks
mark = posts.count
writeInPlace("// x edited in place\n", p.appendingPathComponent("graphics/x.js"))
row["edit"] = settle(mark, ps)
answer["w2"] = row

// MARK: - W10 — the folder swapped as a save swaps it

let aside = work.appendingPathComponent("W2-aside-graphics", isDirectory: true)
try? files.removeItem(at: aside)
mark = posts.count
try? files.moveItem(at: p.appendingPathComponent("graphics"), to: aside)
try? files.copyItem(at: aside, to: p.appendingPathComponent("graphics"))
try? files.removeItem(at: aside)
pump(0.5)
row = ["swap_posts": since(mark, ps), "callbacks": packageCallbacks]
mark = posts.count
writeInPlace("// x edited after the swap\n", p.appendingPathComponent("graphics/x.js"))
row["edit"] = settle(mark, ps)
answer["w10"] = row

// MARK: - W11 — the package moves

let p2 = work.appendingPathComponent("W11.reelcut", isDirectory: true)
try? files.removeItem(at: p2)
try? files.copyItem(at: p, to: p2)
let locationMark = locationPosts.count
ps.packageDidMove(to: p2)
pump(0.3)
row = [
    "locations": locationPosts[locationMark...].filter { $0 == ObjectIdentifier(ps) }.count,
    "folder": ps.folderURL.path, "expected": p2.appendingPathComponent("graphics").path,
]
mark = posts.count
writeInPlace("// x edited in the new folder\n", p2.appendingPathComponent("graphics/x.js"))
row["new_edit"] = settle(mark, ps)
mark = posts.count
writeInPlace("// x edited in the OLD folder\n", p.appendingPathComponent("graphics/x.js"))
pump(0.5)
row["old_edit_posts"] = since(mark, ps)
answer["w11"] = row
ps.stop()

// MARK: - W9 — the app's own first write creates the folder

let p9 = scratchPackage("W9.reelcut")
var w9Callbacks = 0
let ws = GraphicStore(package: p9, seed: nil, bundledFonts: fontsDir)
ws.folderDidAppear = { w9Callbacks += 1 }
ws.start()
let dSource = "export function render() { return '<svg/>' } // d\n"
mark = posts.count
var thrown: Any = NSNull()
do { try ws.write(name: "d", source: dSource) } catch { thrown = error.localizedDescription }
row = settle(mark, ws)
row["thrown"] = thrown
row["callbacks"] = w9Callbacks
row["bytes_equal"] = (try? Data(contentsOf: p9.appendingPathComponent("graphics/d.js")))
    == Data(dSource.utf8)
row["partials"] = ((try? files.contentsOfDirectory(
    atPath: p9.appendingPathComponent("graphics").path)) ?? []).filter { $0.hasSuffix(".partial") }
var badMessage: Any = NSNull()
do { try ws.write(name: "Bad", source: "// no\n") } catch { badMessage = error.localizedDescription }
row["bad_message"] = badMessage
row["bad_files"] = ((try? files.contentsOfDirectory(
    atPath: p9.appendingPathComponent("graphics").path)) ?? []).filter { $0.hasPrefix("Bad") }
answer["w9"] = row
ws.stop()

// MARK: - W13 — the app's write and a rescan at once are ONE post

let es = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
es.start()
mark = posts.count
try? es.write(name: "e", source: "// e\n")
es.rescan()
pump(1.0)
answer["w13"] = ["posts": since(mark, es)]
es.stop()

// MARK: - W14 — a font or an asset rewritten IN PLACE is seen (issue #75)

let faces = ((try? files.contentsOfDirectory(atPath: fontsDir.path)) ?? [])
    .filter { $0.hasSuffix(".ttf") }.sorted()
let ls = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
ls.start()
let libraryFolder = ls.folderURL
let lsFont = libraryFolder.appendingPathComponent("fonts/\(faces.first ?? "none.ttf")")
let lsLogo = libraryFolder.appendingPathComponent("assets/logo.png")
mark = posts.count
try? files.createDirectory(
    at: libraryFolder.appendingPathComponent("fonts"), withIntermediateDirectories: false)
try? files.copyItem(at: fontsDir.appendingPathComponent(faces.first ?? "none.ttf"), to: lsFont)
try? files.createDirectory(
    at: libraryFolder.appendingPathComponent("assets"), withIntermediateDirectories: false)
try? files.copyItem(at: assetPNG, to: lsLogo)
row = ["setup": settle(mark, ls)]
pump(0.3)
/// Other PNG bytes: a 2 × 2 opaque blue bitmap, encoded here.
let otherPNG: Data = {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)
    else { return Data([0x89, 0x50, 0x4e, 0x47]) }
    rep.setColor(NSColor.blue, atX: 0, y: 0)
    return rep.representation(using: .png, properties: [:]) ?? Data([0x89, 0x50, 0x4e, 0x47])
}()
let logoInode = inode(lsLogo)
let libraryBefore = ls.scan.libraryVersion
row["png_differs"] = (try? Data(contentsOf: lsLogo)) != otherPNG
mark = posts.count
writeInPlace(otherPNG, lsLogo)
var logoRow = settle(mark, ls)
logoRow["same_inode"] = logoInode == inode(lsLogo)
logoRow["version_moved"] = ls.scan.libraryVersion != libraryBefore
row["logo"] = logoRow
let fontInode = inode(lsFont)
let fontBefore = ls.scan.libraryVersion
let secondFace = (try? Data(contentsOf: fontsDir.appendingPathComponent(
    faces.count > 1 ? faces[1] : "none.ttf"))) ?? Data()
row["faces"] = faces.count
mark = posts.count
writeInPlace(secondFace, lsFont)
var fontRow = settle(mark, ls)
fontRow["same_inode"] = fontInode == inode(lsFont)
fontRow["version_moved"] = ls.scan.libraryVersion != fontBefore
row["font"] = fontRow
answer["w14"] = row

// MARK: - W15 — a failed write leaves no .partial and the file as it was

let qSource = "// q, immutable\n"
let qURL = libraryFolder.appendingPathComponent("q.js")
write(qSource, qURL)
try? files.setAttributes([.immutable: true], ofItemAtPath: qURL.path)
var qThrown: Any = NSNull()
do { try ls.write(name: "q", source: "// q, replaced\n") } catch {
    qThrown = error.localizedDescription
}
answer["w15"] = [
    "thrown": qThrown,
    "partial": present(libraryFolder.appendingPathComponent("q.js.partial")),
    "bytes_unchanged": (try? Data(contentsOf: qURL)) == Data(qSource.utf8),
]
try? files.setAttributes([.immutable: false], ofItemAtPath: qURL.path)
try? files.removeItem(at: libraryFolder.appendingPathComponent("q.js.partial"))
ls.stop()

// MARK: - W16 — a .partial is not content (G-14)

let w16 = work.appendingPathComponent("W16-graphics", isDirectory: true)
try? files.removeItem(at: w16)
try? files.createDirectory(at: w16, withIntermediateDirectories: true)
write("# manual\n", w16.appendingPathComponent("API.md"))
write("// half\n", w16.appendingPathComponent("x.js.partial"))
let w16Before = GraphicStore.holdsContent(w16)
write("// x\n", w16.appendingPathComponent("x.js"))
answer["w16"] = ["partial_only": w16Before, "with_module": GraphicStore.holdsContent(w16)]

// MARK: - W17 — a source whose open fails is a scan warning (issue #172)

let fs = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
fs.start()
mark = posts.count
write("export function render() { return '<svg/>' } // W17\n",
      fs.folderURL.appendingPathComponent("a.js"))
row = ["setup": settle(mark, fs)]
row["modules_before"] = fs.scan.modules.keys.sorted()
// The soft limit set to the lowest free descriptor, so every open fails
// with EMFILE until it is restored.
var saved = rlimit()
let gotLimit = getrlimit(RLIMIT_NOFILE, &saved) == 0
let lowest = open("/dev/null", O_RDONLY)
if lowest >= 0 { close(lowest) }
var lowered = saved
lowered.rlim_cur = rlim_t(max(lowest, 0))
let setLimit = gotLimit && lowest >= 0 && setrlimit(RLIMIT_NOFILE, &lowered) == 0
fs.rescan()
let restored = setLimit ? setrlimit(RLIMIT_NOFILE, &saved) == 0 : false
row["lowest"] = Int(lowest)
row["limited"] = setLimit
row["restored"] = restored
row["warnings"] = fs.scan.warnings
fs.rescan()
row["control_warnings"] = fs.scan.warnings
row["control_modules"] = fs.scan.modules.keys.sorted()
answer["w17"] = row
let failedOpenRoot = fs.folderURL
fs.stop()

// MARK: - W12 — stop() drops a pending pass and every source

mark = posts.count
writeInPlace("// b edited just before stop\n", folder.appendingPathComponent("b.js"))
s.stop()
pump(0.3)
writeInPlace("// b edited after stop\n", folder.appendingPathComponent("b.js"))
pump(0.5)
answer["w12"] = ["posts": since(mark, s)]

// MARK: - C1..C4 — the document, its whitelist and its lifetime

let c = scratchPackage("C1.reelcut")
try? files.createDirectory(
    at: c.appendingPathComponent("graphics"), withIntermediateDirectories: false)
let xSource = "export function render() { return '<svg/>' } // C\n"
write(xSource, c.appendingPathComponent("graphics/x.js"))

func written(_ document: ProjectDocument, to url: URL, original: URL?) -> [String: Any] {
    do {
        let wrapper = try document.fileWrapper(ofType: projectType)
        let child = wrapper.fileWrappers?["graphics"] != nil
        try wrapper.write(to: url, options: .atomic, originalContentsURL: original)
        let bytes = try? Data(contentsOf: url.appendingPathComponent("graphics/x.js"))
        return ["child": child, "present": bytes != nil,
                "bytes_equal": bytes == Data(xSource.utf8),
                "graphics_dir": present(url.appendingPathComponent("graphics"))]
    } catch {
        return ["error": error.localizedDescription]
    }
}

let c1 = ProjectDocument()
do {
    try c1.read(from: c, ofType: projectType)
    c1.fileURL = c
    c1.startGraphicStore()
    answer["c1"] = written(c1, to: c, original: c)
} catch {
    answer["c1"] = ["error": error.localizedDescription]
}
c1.graphicStore?.stop()

let c2 = ProjectDocument()
do {
    try c2.read(from: c, ofType: projectType)
    c2.autosavedContentsFileURL = c
    c2.startGraphicStore()
    let root = c2.graphicStore?.folderURL
    var r = written(c2, to: work.appendingPathComponent("C2-saved.reelcut"), original: nil)
    r["file_url_nil"] = c2.fileURL == nil
    r["folder"] = root?.path ?? NSNull()
    r["copied"] = root.map { present($0.appendingPathComponent("x.js")) } ?? false
    answer["c2"] = r
} catch {
    answer["c2"] = ["error": error.localizedDescription]
}
let c2Root = c2.graphicStore?.folderURL
c2.graphicStore?.stop()

let c3 = ProjectDocument()
c3.startGraphicStore()
var r3 = written(c3, to: work.appendingPathComponent("C3-saved.reelcut"), original: nil)
r3["root_exists"] = c3.graphicStore.map { present($0.folderURL) } ?? false
answer["c3"] = r3
let c3Root = c3.graphicStore?.folderURL
c3.graphicStore?.stop()

weak var closedDocument: ProjectDocument?
weak var droppedDocument: ProjectDocument?
autoreleasepool {
    let closing = ProjectDocument()
    closedDocument = closing
    closing.startGraphicStore()
    closing.close()
    let dropping = ProjectDocument()
    droppedDocument = dropping
    dropping.startGraphicStore()
}
pump(0.1)
answer["c4"] = ["closed_freed": closedDocument == nil, "dropped_freed": droppedDocument == nil]

// MARK: - C5 — the untitled graphics root goes at close and at the first save

let moduleSource = "export function render() { return '<svg/>' } // m\n"
let c5a = ProjectDocument()
c5a.startGraphicStore()
try? c5a.graphicStore?.write(name: "m", source: moduleSource)
let c5aRoot = c5a.graphicStore?.folderURL
var r5: [String: Any] = [
    "closed_root_before": c5aRoot.map { present($0.appendingPathComponent("m.js")) } ?? false,
]
c5a.close()
r5["closed_root_after"] = c5aRoot.map(present) ?? true
let c5b = ProjectDocument()
c5b.startGraphicStore()
try? c5b.graphicStore?.write(name: "m", source: moduleSource)
let c5bRoot = c5b.graphicStore?.folderURL
let c5Package = work.appendingPathComponent("C5-saved.reelcut", isDirectory: true)
try? files.removeItem(at: c5Package)
do {
    let wrapper = try c5b.fileWrapper(ofType: projectType)
    try wrapper.write(to: c5Package, options: .atomic, originalContentsURL: nil)
    c5b.fileURL = c5Package
} catch {
    r5["save_error"] = error.localizedDescription
}
r5["saved_root_after"] = c5bRoot.map(present) ?? true
r5["folder"] = c5b.graphicStore?.folderURL.path ?? NSNull()
r5["expected"] = c5Package.appendingPathComponent("graphics").path
r5["module_in_package"] = (try? Data(contentsOf: c5Package.appendingPathComponent(
    "graphics/m.js"))) == Data(moduleSource.utf8)
c5b.close()
r5["control_package_graphics"] = present(c5Package.appendingPathComponent("graphics/m.js"))
answer["c5"] = r5

// MARK: - C6 — the untitled cache root goes at close ONLY

let transcript = Data("{\"words\": [], \"note\": \"C6\"}\n".utf8)
func seedTranscript(_ document: ProjectDocument) -> URL? {
    guard let cache = document.cacheDirectory else { return nil }
    let folder = cache.appendingPathComponent("transcripts", isDirectory: true)
    try? files.createDirectory(at: folder, withIntermediateDirectories: true)
    try? transcript.write(to: folder.appendingPathComponent("9.json"))
    return cache
}
let c6a = ProjectDocument()
let c6aRoot = seedTranscript(c6a)
var r6: [String: Any] = [
    "closed_root_before": c6aRoot.map {
        present($0.appendingPathComponent("transcripts/9.json"))
    } ?? false,
    "closed_root_is_temporary": c6aRoot != nil && c6aRoot == c6a.temporaryCacheDirectory,
]
c6a.close()
r6["closed_root_after"] = c6aRoot.map(present) ?? true
let c6b = ProjectDocument()
let c6bRoot = seedTranscript(c6b)
let c6Package = work.appendingPathComponent("C6-saved.reelcut", isDirectory: true)
try? files.removeItem(at: c6Package)
let packaged = c6Package.appendingPathComponent("cache/transcripts/9.json")
do {
    let wrapper = try c6b.fileWrapper(ofType: projectType)
    try wrapper.write(to: c6Package, options: .atomic, originalContentsURL: nil)
    c6b.fileURL = c6Package
} catch {
    r6["save_error"] = error.localizedDescription
}
r6["copy_equal"] = (try? Data(contentsOf: packaged)) == transcript
r6["saved_root_kept"] = c6bRoot.map(present) ?? false
c6b.close()
r6["saved_root_after"] = c6bRoot.map(present) ?? true
r6["copy_after_close"] = (try? Data(contentsOf: packaged)) == transcript
let c6c = ProjectDocument()
do {
    try c6c.read(from: c6Package, ofType: projectType)
    c6c.fileURL = c6Package
    r6["control_temporary_nil"] = c6c.temporaryCacheDirectory == nil
    c6c.close()
    r6["control_package_cache"] = present(c6Package.appendingPathComponent("cache"))
} catch {
    r6["control_error"] = error.localizedDescription
}
answer["c6"] = r6

// The untitled roots this run made, removed so the temporary directory is
// left as found (a mutant leaves the C5 and C6 ones behind).
for leftover in [c5aRoot, c5bRoot, c6aRoot, c6bRoot].compactMap({ $0 }) {
    try? files.removeItem(at: leftover)
}
let roots = [s.folderURL, es.folderURL, libraryFolder, failedOpenRoot]
    + [c2Root, c3Root].compactMap { $0 }
for root in roots { try? files.removeItem(at: root) }
answer["roots_removed"] = roots.allSatisfy { !present($0) }

answer["ok"] = true
finish()
