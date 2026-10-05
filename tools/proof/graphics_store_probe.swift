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

// MARK: - W18 — a font unchanged on disk is not read again (spec §11 G-23 (f))

func modified(_ url: URL) -> Date? {
    (try? files.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}
let ts = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
ts.start()
let fontRoot = ts.folderURL
let tsFont = fontRoot.appendingPathComponent("fonts/f.ttf")
let faceBytes = (try? Data(contentsOf: fontsDir.appendingPathComponent(
    faces.first ?? "none.ttf"))) ?? Data()
let pinned = Date(timeIntervalSince1970: 1_700_000_000)
try? files.createDirectory(
    at: fontRoot.appendingPathComponent("fonts"), withIntermediateDirectories: false)
try? faceBytes.write(to: tsFont)
try? files.setAttributes([.modificationDate: pinned], ofItemAtPath: tsFont.path)
ts.rescan()
pump(0.3)
row = ["setup_fonts": ts.scan.fonts.map { $0.name }, "face_bytes": faceBytes.count]
ts.stop()
let tsInode = inode(tsFont)
writeInPlace(Data(count: faceBytes.count), tsFont)
try? files.setAttributes([.modificationDate: pinned], ofItemAtPath: tsFont.path)
row["same_inode"] = tsInode == inode(tsFont)
row["same_mtime"] = modified(tsFont) == pinned
row["zeroed"] = (try? Data(contentsOf: tsFont)) == Data(count: faceBytes.count)
ts.start()
row["fonts"] = ts.scan.fonts.map { $0.name }
row["bytes_equal"] = ts.scan.fonts.first?.bytes == faceBytes
row["warnings"] = ts.scan.warnings
try? files.setAttributes(
    [.modificationDate: pinned.addingTimeInterval(2)], ofItemAtPath: tsFont.path)
ts.rescan()
row["control_fonts"] = ts.scan.fonts.map { $0.name }
row["control_warnings"] = ts.scan.warnings
answer["w18"] = row
ts.stop()

// MARK: - W19 — a name asset(name) cannot use is renamed at import (spec §11 G-23)

let nameTable = [
    "#logo&mark.png", ".hidden.png", "My Photo (1).png", "a\"b'c<d>e.png", "a&&b.png",
    "#&.png", "x\u{07}y.PNG", "10:30.jpg", String(repeating: "é", count: 200) + ".png",
    String(repeating: "a", count: 247) + ".png", "logo.svg",
]
row = ["table": nameTable.map { name -> [String: Any] in
    let legal = GraphicAssetName.legalized(name)
    return [
        "name": name, "legalized": legal, "bytes": legal.utf8.count,
        "invariant": GraphicAssetName.isLegal(name) == (legal == name)
            && GraphicAssetName.isLegal(legal),
    ]
}]
let ns = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
ns.start()
let otherPNGFile = work.appendingPathComponent("W19-other.png")
try? otherPNG.write(to: otherPNGFile)
func imported(_ source: URL, _ name: String) -> [String: Any] {
    do {
        let landed = try ns.importAsset(from: source, as: name)
        return [
            "name": landed.name, "renamed_from": landed.renamedFrom ?? NSNull(),
            "replaced": landed.replaced, "listed": ns.scan.assets.contains { $0.name == landed.name },
            "on_disk": present(landed.url), "bytes": landed.name.utf8.count,
        ]
    } catch {
        return ["thrown": error.localizedDescription]
    }
}
let longName = String(repeating: "a", count: 300) + ".png"
row["first"] = imported(assetPNG, "#logo&mark.png")
row["second"] = imported(otherPNGFile, "#logo&mark.png")
row["first_bytes_unchanged"] = (try? Data(contentsOf: ns.folderURL.appendingPathComponent(
    "assets/logo-mark.png"))) == (try? Data(contentsOf: assetPNG))
row["legal"] = imported(assetPNG, "logo-mark.png")
row["long"] = imported(assetPNG, longName)
row["long_again"] = imported(assetPNG, longName)
row["notice"] = GraphicAssetName.renameNotice(from: "#logo&mark.png", to: "logo-mark.png")
row["assets"] = ns.scan.assets.map { $0.name }
answer["w19"] = row
let namesRoot = ns.folderURL
ns.stop()

// MARK: - W20 — the scan skips an illegal asset file with a warning (spec §11 G-23 (e))

let bs = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
bs.start()
let badRoot = bs.folderURL
try? files.createDirectory(
    at: badRoot.appendingPathComponent("assets"), withIntermediateDirectories: false)
for bad in ["#bad.png", ".dot.png", "ok.png"] {
    try? files.copyItem(at: assetPNG, to: badRoot.appendingPathComponent("assets/\(bad)"))
}
bs.rescan()
answer["w20"] = [
    "assets": bs.scan.assets.map { $0.name }, "warnings": bs.scan.warnings,
    "on_disk": ((try? files.contentsOfDirectory(
        atPath: badRoot.appendingPathComponent("assets").path)) ?? []).sorted(),
]
bs.stop()

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

// MARK: - H1..H18, C7 — kept revisions, delete, rename, restore (issue batch B84, #103)

func moduleText(_ tag: String) -> String {
    "export function render() { return '<svg/>' } // \(tag)\n"
}
func textAt(_ url: URL) -> Any { (try? String(contentsOf: url, encoding: .utf8)) ?? NSNull() }
func keptTexts(_ store: GraphicStore?, _ name: String) -> [Any] {
    (store?.kept(named: name) ?? []).map { textAt($0.url) }
}
func keptRevisions(_ store: GraphicStore?, _ name: String) -> [String] {
    (store?.kept(named: name) ?? []).map(\.revision)
}
func sentence(_ body: () throws -> Void) -> Any {
    do { try body(); return NSNull() } catch { return error.localizedDescription }
}
func historyDirectory(_ store: GraphicStore?, _ name: String) -> Bool {
    store.map { present($0.folderURL.appendingPathComponent("history/\(name)")) } ?? false
}
/// A new untitled document with its store started and one track; the track.
func graphicDocument() -> (ProjectDocument, UInt32) {
    let document = ProjectDocument()
    document.startGraphicStore()
    document.performGroupedEdit("Add Track", [.addTrack(index: 0)])
    return (document, document.project.snapshot.tracks.first?.id ?? 0)
}
/// Writes `name` and rescans, as `write_graphic` does.
func writeModule(_ document: ProjectDocument, _ name: String, _ text: String) {
    try? document.graphicStore?.write(name: name, source: text)
    document.graphicStore?.rescan()
}
/// Places a graphic clip drawn by `name` at `at` seconds; its id.
func placeGraphic(_ document: ProjectDocument, _ track: UInt32, _ name: String, at: Int) -> UInt32 {
    let before = Set(document.project.snapshot.clips.map(\.id))
    document.performGroupedEdit("Add Graphic", [.addGraphicClipRaw(
        track: track, at: Ticks(at) * 600_000, duration: 600_000, name: name)])
    return document.project.snapshot.clips.first { !before.contains($0.id) }?.id ?? 0
}
/// Every graphic clip's module name, the timeline's and every nest's, by id.
func graphicNames(_ document: ProjectDocument) -> [String: String] {
    let snapshot = document.project.snapshot
    var names: [String: String] = [:]
    for clip in snapshot.clips + snapshot.nests.flatMap({ $0.clips }) {
        if let name = clip.graphic?.name { names[String(clip.id)] = name }
    }
    return names
}
func walk(_ document: ProjectDocument, redo: Bool) {
    guard let manager = document.undoManager else { return }
    let groupsByEvent = manager.groupsByEvent
    if groupsByEvent { manager.groupsByEvent = false }
    if redo { manager.redo() } else { manager.undo() }
    if groupsByEvent { manager.groupsByEvent = true }
}
var historyRoots: [URL] = []

// H1 — a replacing write and an in-place outside rewrite each keep the text
let hs = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
hs.start()
historyRoots.append(hs.folderURL)
let (h1a, h1b, h1c) = (moduleText("h1 a"), moduleText("h1 b"), moduleText("h1 c"))
try? hs.write(name: "h", source: h1a)
hs.rescan()
let h1Fresh = keptTexts(hs, "h")
try? hs.write(name: "h", source: h1b)
hs.rescan()
row = ["texts": [h1a, h1b, h1c], "kept_fresh": h1Fresh, "kept_after_write": keptTexts(hs, "h")]
pump(0.3)
mark = posts.count
writeInPlace(h1c, hs.folderURL.appendingPathComponent("h.js"))
row["outside"] = settle(mark, hs)
row["kept_after_outside"] = keptTexts(hs, "h")
row["revisions"] = keptRevisions(hs, "h")
answer["h1"] = row
hs.stop()

// H2 — restore writes the newest kept text and keeps what it replaced
let h2 = ProjectDocument()
h2.startGraphicStore()
if let root = h2.graphicStore?.folderURL { historyRoots.append(root) }
let (h2a, h2b) = (moduleText("h2 a"), moduleText("h2 b"))
writeModule(h2, "r", h2a)
writeModule(h2, "r", h2b)
let h2File = h2.graphicStore?.folderURL.appendingPathComponent("r.js") ?? work
row = ["texts": [h2a, h2b]]
row["first"] = (try? h2.restoreGraphic(named: "r", revision: nil)) ?? NSNull()
row["file_after_first"] = textAt(h2File)
row["bytes_equal"] = (try? Data(contentsOf: h2File)) == Data(h2a.utf8)
row["kept_after_first"] = keptTexts(h2.graphicStore, "r")
row["second"] = (try? h2.restoreGraphic(named: "r", revision: nil)) ?? NSNull()
row["file_after_second"] = textAt(h2File)
row["kept_after_second"] = keptTexts(h2.graphicStore, "r")
row["none"] = sentence { _ = try h2.restoreGraphic(named: "never", revision: nil) }
row["unknown"] = sentence { _ = try h2.restoreGraphic(named: "r", revision: "feed") }
row["kept_revisions"] = keptRevisions(h2.graphicStore, "r")
row["edited"] = h2.isDocumentEdited
// A kept file changed by hand is not a kept text: restore refuses it and writes nothing.
let h2c = moduleText("h2 c")
writeModule(h2, "r", h2c)
let h2Newest = h2.graphicStore?.kept(named: "r").first
if let url = h2Newest?.url { write(moduleText("h2 changed by hand"), url) }
row["third"] = h2c
row["tampered_file"] = h2Newest?.url.lastPathComponent ?? ""
row["tampered"] = sentence { _ = try h2.restoreGraphic(named: "r", revision: nil) }
row["file_after_tampered"] = textAt(h2File)
row["kept_revisions_after_tampered"] = keptRevisions(h2.graphicStore, "r")
answer["h2"] = row

// H3 — thirteen texts keep exactly ten; a text kept twice is listed once
let h3Texts = (0..<13).map { moduleText("h3 \($0)") }
for text in h3Texts { writeModule(h2, "t", text) }
row = ["texts": h3Texts, "kept": keptTexts(h2.graphicStore, "t")]
if let folder = h2.graphicStore?.folderURL {
    GraphicStore.keep(Data(h3Texts[7].utf8), named: "t", in: folder)
}
row["kept_again"] = keptTexts(h2.graphicStore, "t")
answer["h3"] = row
h2.close()

// H4 — delete is refused while a clip draws the module, then done
let (h4, h4Track) = graphicDocument()
let h4Store = h4.graphicStore
let h4Folder = h4Store?.folderURL ?? work
historyRoots.append(h4Folder)
let h4Text = moduleText("h4")
writeModule(h4, "used", h4Text)
try? files.createDirectory(
    at: h4Folder.appendingPathComponent("fonts"), withIntermediateDirectories: false)
try? files.copyItem(
    at: fontsDir.appendingPathComponent(face), to: h4Folder.appendingPathComponent("fonts/\(face)"))
try? files.createDirectory(
    at: h4Folder.appendingPathComponent("assets"), withIntermediateDirectories: false)
try? files.copyItem(at: assetPNG, to: h4Folder.appendingPathComponent("assets/logo.png"))
h4Store?.rescan()
let h4Clip = placeGraphic(h4, h4Track, "used", at: 0)
row = ["clip": Int(h4Clip), "text": h4Text]
row["refused"] = sentence { _ = try h4.deleteGraphic(named: "used") }
row["file_after_refusal"] = present(h4Folder.appendingPathComponent("used.js"))
row["absent"] = sentence { _ = try h4.deleteGraphic(named: "nope") }
h4.performGroupedEdit("Delete", [.delete(clips: [h4Clip])])
let h4Edited = h4.isDocumentEdited
h4.updateChangeCount(.changeCleared)
row["deleted"] = (try? h4.deleteGraphic(named: "used")) ?? NSNull()
row["file_after_delete"] = present(h4Folder.appendingPathComponent("used.js"))
row["listed_after_delete"] = h4Store?.module(named: "used") != nil
row["kept"] = keptTexts(h4Store, "used")
row["kept_names"] = h4Store?.keptNames() ?? []
row["font_kept"] = present(h4Folder.appendingPathComponent("fonts/\(face)"))
row["asset_kept"] = present(h4Folder.appendingPathComponent("assets/logo.png"))
row["edited_by_clip_delete"] = h4Edited
row["edited_by_delete"] = h4.isDocumentEdited
answer["h4"] = row
h4.close()

// H5 — rename moves a timeline clip, a nest clip and the kept texts; undo and redo
let (h5, h5Track) = graphicDocument()
let h5Store = h5.graphicStore
let h5Folder = h5Store?.folderURL ?? work
historyRoots.append(h5Folder)
let (h5a, h5b) = (moduleText("h5 a"), moduleText("h5 b"))
writeModule(h5, "old", h5a)
writeModule(h5, "old", h5b)
writeModule(h5, "other", moduleText("h5 other"))
let h5Timeline = placeGraphic(h5, h5Track, "old", at: 0)
let h5Nested = placeGraphic(h5, h5Track, "old", at: 2)
h5.performGroupedEdit("Nest", [.nest(clips: [h5Nested])])
let h5Nest = h5.project.snapshot.nests.first?.id ?? 0
let h5NestClip = h5.project.snapshot.clips.first { $0.source.nestID == h5Nest }?.id ?? 0
func h5State() -> [String: Any] {
    [
        "names": graphicNames(h5),
        "old_file": textAt(h5Folder.appendingPathComponent("old.js")),
        "new_file": textAt(h5Folder.appendingPathComponent("new.js")),
        "kept_old": keptTexts(h5Store, "old"), "kept_new": keptTexts(h5Store, "new"),
        "history_old": historyDirectory(h5Store, "old"),
        "history_new": historyDirectory(h5Store, "new"),
        "modules": h5Store?.scan.modules.keys.sorted() ?? [],
    ]
}
row = [
    "timeline": Int(h5Timeline), "nested": Int(h5Nested), "nest": Int(h5Nest),
    "texts": [h5a, h5b], "before": h5State(),
    "groups": h5.graphicClips(named: "old").map { group -> [String: Any] in
        ["nest": group.nest.map { Int($0) as Any } ?? NSNull(), "clips": group.clips.map { Int($0) }]
    },
]
row["taken"] = sentence {
    _ = try h5.renameGraphic(named: "old", to: "other") { h5.performGroupedEdit("Rename Graphic", $0) }
}
row["bad"] = sentence {
    _ = try h5.renameGraphic(named: "old", to: "Bad Name") { h5.performGroupedEdit("Rename Graphic", $0) }
}
h5.setNestPath([NestScopeStep(nest: h5Nest, clip: h5NestClip)], playhead: 0, selection: [])
row["scope_inside"] = h5.scope.map { Int($0) as Any } ?? NSNull()
row["nest_open"] = sentence {
    _ = try h5.renameGraphic(named: "old", to: "new") { h5.performGroupedEdit("Rename Graphic", $0) }
}
row["after_refusals"] = h5State()
h5.setNestPath([], playhead: 0, selection: [])
row["renamed"] = (try? h5.renameGraphic(named: "old", to: "new") {
    h5.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
row["undo_name"] = h5.undoManager?.undoActionName ?? ""
row["after_rename"] = h5State()
row["pairs"] = (h5Store?.renamePairs() ?? []).map { [$0.0, $0.1] }
walk(h5, redo: false)
row["after_undo"] = h5State()
walk(h5, redo: true)
row["after_redo"] = h5State()
answer["h5"] = row
h5.close()

// H6 — a document read naming the old name beside a renamed file is healed at start
let (h6, h6Track) = graphicDocument()
if let root = h6.graphicStore?.folderURL { historyRoots.append(root) }
let h6Text = moduleText("h6")
writeModule(h6, "old", h6Text)
_ = placeGraphic(h6, h6Track, "old", at: 0)
let h6Package = work.appendingPathComponent("H6.reelcut", isDirectory: true)
let h6Control = work.appendingPathComponent("H6-control.reelcut", isDirectory: true)
try? files.removeItem(at: h6Package)
try? files.removeItem(at: h6Control)
row = [:]
do {
    let wrapper = try h6.fileWrapper(ofType: projectType)
    try wrapper.write(to: h6Package, options: .atomic, originalContentsURL: nil)
} catch {
    row["save_error"] = error.localizedDescription
}
h6.close()
let h6Graphics = h6Package.appendingPathComponent("graphics")
try? files.moveItem(
    at: h6Graphics.appendingPathComponent("old.js"), to: h6Graphics.appendingPathComponent("new.js"))
try? files.copyItem(at: h6Package, to: h6Control)
try? files.createDirectory(
    at: h6Graphics.appendingPathComponent("history"), withIntermediateDirectories: true)
write("[[\"old\", \"new\"]]", h6Graphics.appendingPathComponent("history/renames.json"))
func opened(_ package: URL) -> [String: Any] {
    let document = ProjectDocument()
    do {
        try document.read(from: package, ofType: projectType)
        document.fileURL = package
        document.startGraphicStore()
    } catch {
        return ["error": error.localizedDescription]
    }
    let graphics = package.appendingPathComponent("graphics")
    let state: [String: Any] = [
        "names": Array(graphicNames(document).values),
        "old_file": textAt(graphics.appendingPathComponent("old.js")),
        "new_file": present(graphics.appendingPathComponent("new.js")),
        "new_text": textAt(graphics.appendingPathComponent("new.js")),
        "kept_old": keptTexts(document.graphicStore, "old"),
        "pairs": (document.graphicStore?.renamePairs() ?? []).map { [$0.0, $0.1] },
        "listed": document.graphicStore?.scan.modules.keys.sorted() ?? [],
        "edited": document.isDocumentEdited,
    ]
    document.close()
    return state
}
row["text"] = h6Text
row["healed"] = opened(h6Package)
row["control"] = opened(h6Control)
answer["h6"] = row

// H7 — Undo never moves a live module under a deleted one's name
let (h7, h7Track) = graphicDocument()
let h7Store = h7.graphicStore
let h7Folder = h7Store?.folderURL ?? work
historyRoots.append(h7Folder)
let (h7Old, h7New) = (moduleText("h7 the first title"), moduleText("h7 the new title"))
writeModule(h7, "title", h7Old)
let h7Clip = placeGraphic(h7, h7Track, "title", at: 0)
row = ["clip": Int(h7Clip), "texts": [h7Old, h7New]]
row["renamed"] = (try? h7.renameGraphic(named: "title", to: "title-v1") {
    h7.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
writeModule(h7, "title", h7New)
h7.performGroupedEdit(
    "Graphic Properties", [.setGraphicRaw(clips: [h7Clip], patch: ["name": "title"])])
row["repointed"] = graphicNames(h7)
row["deleted"] = sentence { _ = try h7.deleteGraphic(named: "title-v1") }
walk(h7, redo: false)
row["names_after_undo"] = graphicNames(h7)
row["title_file"] = textAt(h7Folder.appendingPathComponent("title.js"))
row["v1_file"] = present(h7Folder.appendingPathComponent("title-v1.js"))
row["kept_v1"] = keptTexts(h7Store, "title-v1")
row["modules"] = h7Store?.scan.modules.keys.sorted() ?? []
answer["h7"] = row
h7.close()

// H8 — a name a clip already draws with no file behind it is not a rename's target
let (h8, h8Track) = graphicDocument()
let h8Store = h8.graphicStore
let h8Folder = h8Store?.folderURL ?? work
historyRoots.append(h8Folder)
let h8Other = moduleText("h8 other")
writeModule(h8, "ghost", moduleText("h8 ghost"))
writeModule(h8, "other", h8Other)
let h8Clip = placeGraphic(h8, h8Track, "ghost", at: 0)
h8.performGroupedEdit("Delete", [.delete(clips: [h8Clip])])
row = ["clip": Int(h8Clip)]
row["deleted"] = sentence { _ = try h8.deleteGraphic(named: "ghost") }
walk(h8, redo: false)
row["names_after_undo"] = graphicNames(h8)
row["ghost_file_after_undo"] = present(h8Folder.appendingPathComponent("ghost.js"))
row["drawn"] = sentence {
    _ = try h8.renameGraphic(named: "other", to: "ghost") { h8.performGroupedEdit("Rename Graphic", $0) }
}
row["other_file"] = textAt(h8Folder.appendingPathComponent("other.js"))
row["other_text"] = h8Other
row["ghost_file"] = present(h8Folder.appendingPathComponent("ghost.js"))
row["kept_ghost"] = keptTexts(h8Store, "ghost").count
row["kept_other"] = keptTexts(h8Store, "other").count
answer["h8"] = row
h8.close()

// H9 — the rename journal holds at most 32 pairs, a repeated pair once, at the end
let js = GraphicStore(package: nil, seed: nil, bundledFonts: fontsDir)
js.start()
for i in 0..<40 { GraphicStore.recordRename("n\(i)", "m\(i)", in: js.folderURL) }
GraphicStore.recordRename("m20", "n20", in: js.folderURL)
answer["h9"] = ["pairs": js.renamePairs().map { [$0.0, $0.1] }, "limit": GraphicStore.renameJournalLimit]
js.stop()
try? files.removeItem(at: js.folderURL)

// H10 — a removal the app did not make is not a rename to repair
let (h10, h10Track) = graphicDocument()
let h10Store = h10.graphicStore
let h10Folder = h10Store?.folderURL ?? work
historyRoots.append(h10Folder)
let h10New = moduleText("h10 the new a")
writeModule(h10, "a", moduleText("h10 a"))
let h10Clip = placeGraphic(h10, h10Track, "a", at: 0)
row = ["clip": Int(h10Clip), "text": h10New]
row["renamed"] = (try? h10.renameGraphic(named: "a", to: "b") {
    h10.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
try? files.removeItem(at: h10Folder.appendingPathComponent("b.js"))
h10Store?.rescan()
row["kept_b"] = keptTexts(h10Store, "b").count
writeModule(h10, "a", h10New)
row["pairs"] = (h10Store?.renamePairs() ?? []).map { [$0.0, $0.1] }
let h10Tracks = h10.project.snapshot.tracks.count
h10.performGroupedEdit("Add Track", [.addTrack(index: 0)])
row["tracks_added"] = h10.project.snapshot.tracks.count - h10Tracks
row["names"] = graphicNames(h10)
row["a_file"] = textAt(h10Folder.appendingPathComponent("a.js"))
row["b_file"] = present(h10Folder.appendingPathComponent("b.js"))
row["modules"] = h10Store?.scan.modules.keys.sorted() ?? []
answer["h10"] = row
h10.close()

// H11 — Undo of a rename whose old name was since written anew and deleted
let (h11, h11Track) = graphicDocument()
let h11Store = h11.graphicStore
let h11Folder = h11Store?.folderURL ?? work
historyRoots.append(h11Folder)
let (h11Text, h11New) = (moduleText("h11 the module"), moduleText("h11 a new a"))
writeModule(h11, "a", h11Text)
let h11Clip = placeGraphic(h11, h11Track, "a", at: 0)
row = ["clip": Int(h11Clip), "texts": [h11Text, h11New]]
row["renamed"] = (try? h11.renameGraphic(named: "a", to: "b") {
    h11.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
writeModule(h11, "a", h11New)
row["deleted"] = sentence { _ = try h11.deleteGraphic(named: "a") }
row["undo_name"] = h11.undoManager?.undoActionName ?? ""
walk(h11, redo: false)
row["names_after_undo"] = graphicNames(h11)
row["a_file"] = present(h11Folder.appendingPathComponent("a.js"))
row["b_file"] = textAt(h11Folder.appendingPathComponent("b.js"))
row["kept_a"] = keptTexts(h11Store, "a")
row["modules"] = h11Store?.scan.modules.keys.sorted() ?? []
answer["h11"] = row
h11.close()

// H12 — start() drops a module's current text from its history
let h12Package = scratchPackage("H12.reelcut")
let h12Graphics = h12Package.appendingPathComponent("graphics", isDirectory: true)
try? files.createDirectory(at: h12Graphics, withIntermediateDirectories: true)
let (h12Old, h12Current) = (moduleText("h12 old"), moduleText("h12 current"))
GraphicStore.keep(Data(h12Old.utf8), named: "m", in: h12Graphics)
GraphicStore.keep(Data(h12Current.utf8), named: "m", in: h12Graphics)
write(h12Current, h12Graphics.appendingPathComponent("m.js"))
let h12History = h12Graphics.appendingPathComponent("history/m")
func h12Entries() -> [String] {
    ((try? files.contentsOfDirectory(atPath: h12History.path)) ?? []).sorted()
}
row = ["texts": [h12Old, h12Current], "built": h12Entries()]
let h12 = ProjectDocument()
do {
    try h12.read(from: h12Package, ofType: projectType)
    h12.fileURL = h12Package
    h12.startGraphicStore()
    row["kept_at_start"] = keptTexts(h12.graphicStore, "m")
    row["entries_at_start"] = h12Entries()
    row["restored"] = (try? h12.restoreGraphic(named: "m", revision: nil)) ?? NSNull()
    row["file"] = textAt(h12Graphics.appendingPathComponent("m.js"))
    row["kept_after"] = keptTexts(h12.graphicStore, "m")
    row["edited"] = h12.isDocumentEdited
} catch {
    row["error"] = error.localizedDescription
}
h12.close()
answer["h12"] = row

// H13 — a rename that cannot be journalled is refused, and nothing has moved
let (h13, h13Track) = graphicDocument()
let h13Store = h13.graphicStore
let h13Folder = h13Store?.folderURL ?? work
historyRoots.append(h13Folder)
let (h13a, h13b) = (moduleText("h13 a"), moduleText("h13 b"))
writeModule(h13, "old", h13a)
writeModule(h13, "old", h13b)
let h13Clip = placeGraphic(h13, h13Track, "old", at: 0)
let h13Journal = h13Folder.appendingPathComponent("history/renames.json", isDirectory: true)
try? files.createDirectory(at: h13Journal, withIntermediateDirectories: true)
write("in the way", h13Journal.appendingPathComponent("in-the-way"))
row = ["clip": Int(h13Clip), "texts": [h13a, h13b]]
row["journal_is_directory"] = present(h13Journal.appendingPathComponent("in-the-way"))
row["refused"] = sentence {
    _ = try h13.renameGraphic(named: "old", to: "new") { h13.performGroupedEdit("Rename Graphic", $0) }
}
row["names"] = graphicNames(h13)
row["old_file"] = textAt(h13Folder.appendingPathComponent("old.js"))
row["new_file"] = present(h13Folder.appendingPathComponent("new.js"))
row["kept_old"] = keptTexts(h13Store, "old")
row["history_new"] = historyDirectory(h13Store, "new")
row["modules"] = h13Store?.scan.modules.keys.sorted() ?? []
row["undo_name"] = h13.undoManager?.undoActionName ?? ""
answer["h13"] = row
h13.close()

// H14 — a rename whose history cannot be folded is put back, and journals nothing
let (h14, h14Track) = graphicDocument()
let h14Store = h14.graphicStore
let h14Folder = h14Store?.folderURL ?? work
historyRoots.append(h14Folder)
let (h14a, h14b) = (moduleText("h14 a"), moduleText("h14 b"))
writeModule(h14, "old", h14a)
writeModule(h14, "old", h14b)
let h14Clip = placeGraphic(h14, h14Track, "old", at: 0)
write("in the way", h14Folder.appendingPathComponent("history/new"))
row = ["clip": Int(h14Clip), "texts": [h14a, h14b]]
row["in_the_way"] = present(h14Folder.appendingPathComponent("history/new"))
row["refused"] = sentence {
    _ = try h14.renameGraphic(named: "old", to: "new") { h14.performGroupedEdit("Rename Graphic", $0) }
}
row["names"] = graphicNames(h14)
row["old_file"] = textAt(h14Folder.appendingPathComponent("old.js"))
row["new_file"] = present(h14Folder.appendingPathComponent("new.js"))
row["kept_old"] = keptTexts(h14Store, "old")
row["pairs"] = (h14Store?.renamePairs() ?? []).map { [$0.0, $0.1] }
row["journal_file"] = present(h14Folder.appendingPathComponent("history/renames.json"))
row["modules"] = h14Store?.scan.modules.keys.sorted() ?? []
row["undo_name"] = h14.undoManager?.undoActionName ?? ""
answer["h14"] = row
h14.close()

// H15 — the state a crash inside moveModule leaves when the old name had kept texts: the file
// at the new name, the pair journalled, history/old/ still there. Built by hand (G-28 (f)).
// Then, in the same package, the default restore G-28 (f) speaks of: it writes the OLDER text.
let h15Package = work.appendingPathComponent("H15.reelcut", isDirectory: true)
try? files.removeItem(at: h15Package)
try? files.copyItem(at: h6Control, to: h15Package)
let h15Graphics = h15Package.appendingPathComponent("graphics")
let h15Kept = moduleText("h15 an older text of old")
GraphicStore.keep(Data(h15Kept.utf8), named: "old", in: h15Graphics)
write("[[\"old\", \"new\"]]", h15Graphics.appendingPathComponent("history/renames.json"))
row = ["text": h6Text, "kept": h15Kept, "opened": opened(h15Package)]
let h15 = ProjectDocument()
do {
    try h15.read(from: h15Package, ofType: projectType)
    h15.fileURL = h15Package
    h15.startGraphicStore()
    var restored: [String: Any] = [:]
    do {
        restored["revision"] = try h15.restoreGraphic(named: "old", revision: nil)
    } catch {
        restored["error"] = error.localizedDescription
    }
    restored["names"] = Array(graphicNames(h15).values)
    restored["drawn_new"] = h15.graphicClips(named: "new").count
    restored["old_file"] = textAt(h15Graphics.appendingPathComponent("old.js"))
    restored["new_text"] = textAt(h15Graphics.appendingPathComponent("new.js"))
    restored["kept_old"] = keptTexts(h15.graphicStore, "old")
    restored["pairs"] = (h15.graphicStore?.renamePairs() ?? []).map { [$0.0, $0.1] }
    restored["listed"] = h15.graphicStore?.scan.modules.keys.sorted() ?? []
    restored["edited"] = h15.isDocumentEdited
    row["restored"] = restored
} catch {
    row["restore_error"] = error.localizedDescription
}
h15.close()
answer["h15"] = row

// H16 — a rename back that is refused at the fold leaves the EARLIER pair, so Undo still repairs
let (h16, h16Track) = graphicDocument()
let h16Store = h16.graphicStore
let h16Folder = h16Store?.folderURL ?? work
historyRoots.append(h16Folder)
let (h16a, h16b) = (moduleText("h16 a"), moduleText("h16 b"))
writeModule(h16, "a", h16a)
writeModule(h16, "a", h16b)
let h16Clip = placeGraphic(h16, h16Track, "a", at: 0)
let h16Journal = h16Folder.appendingPathComponent("history/renames.json")
row = ["clip": Int(h16Clip), "texts": [h16a, h16b]]
row["renamed"] = (try? h16.renameGraphic(named: "a", to: "b") {
    h16.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
row["journal_before"] = textAt(h16Journal)
row["pairs_before"] = (h16Store?.renamePairs() ?? []).map { [$0.0, $0.1] }
write("in the way", h16Folder.appendingPathComponent("history/a"))
row["in_the_way"] = present(h16Folder.appendingPathComponent("history/a"))
row["refused"] = sentence {
    _ = try h16.renameGraphic(named: "b", to: "a") { h16.performGroupedEdit("Rename Graphic", $0) }
}
row["journal_after"] = textAt(h16Journal)
row["pairs_after"] = (h16Store?.renamePairs() ?? []).map { [$0.0, $0.1] }
row["names_after_refusal"] = graphicNames(h16)
row["a_file_after_refusal"] = present(h16Folder.appendingPathComponent("a.js"))
row["b_file_after_refusal"] = textAt(h16Folder.appendingPathComponent("b.js"))
row["kept_b_after_refusal"] = keptTexts(h16Store, "b")
try? files.removeItem(at: h16Folder.appendingPathComponent("history/a"))
row["undo_name"] = h16.undoManager?.undoActionName ?? ""
walk(h16, redo: false)
row["names_after_undo"] = graphicNames(h16)
row["a_file"] = textAt(h16Folder.appendingPathComponent("a.js"))
row["b_file"] = present(h16Folder.appendingPathComponent("b.js"))
row["kept_a"] = keptTexts(h16Store, "a")
row["kept_b"] = keptTexts(h16Store, "b")
row["modules"] = h16Store?.scan.modules.keys.sorted() ?? []
answer["h16"] = row
h16.close()

// H17 — a chain of renames undoes and redoes step by step
let (h17, h17Track) = graphicDocument()
let h17Store = h17.graphicStore
let h17Folder = h17Store?.folderURL ?? work
historyRoots.append(h17Folder)
let (h17a, h17b) = (moduleText("h17 a"), moduleText("h17 b"))
writeModule(h17, "a", h17a)
writeModule(h17, "a", h17b)
let h17Clip = placeGraphic(h17, h17Track, "a", at: 0)
func h17State() -> [String: Any] {
    var state: [String: Any] = [
        "names": graphicNames(h17), "modules": h17Store?.scan.modules.keys.sorted() ?? [],
    ]
    for name in ["a", "b", "c"] {
        state["file_\(name)"] = textAt(h17Folder.appendingPathComponent("\(name).js"))
        state["kept_\(name)"] = keptTexts(h17Store, name)
        state["history_\(name)"] = historyDirectory(h17Store, name)
    }
    return state
}
row = ["clip": Int(h17Clip), "texts": [h17a, h17b], "before": h17State()]
row["renamed_b"] = (try? h17.renameGraphic(named: "a", to: "b") {
    h17.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
row["after_b"] = h17State()
row["renamed_c"] = (try? h17.renameGraphic(named: "b", to: "c") {
    h17.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
row["after_c"] = h17State()
row["pairs"] = (h17Store?.renamePairs() ?? []).map { [$0.0, $0.1] }
walk(h17, redo: false)
row["undo_1"] = h17State()
walk(h17, redo: false)
row["undo_2"] = h17State()
walk(h17, redo: true)
row["redo_1"] = h17State()
walk(h17, redo: true)
row["redo_2"] = h17State()
answer["h17"] = row
h17.close()

// H18 — a rename refused at the CLIPS is moved back and journals nothing (G-28 (d)): `apply`
// throws, or returns having applied nothing, with no journal and with an earlier pair.
let (h18, h18Track) = graphicDocument()
let h18Store = h18.graphicStore
let h18Folder = h18Store?.folderURL ?? work
historyRoots.append(h18Folder)
let (h18a, h18b) = (moduleText("h18 a"), moduleText("h18 b"))
writeModule(h18, "a", h18a)
writeModule(h18, "a", h18b)
let h18Clip = placeGraphic(h18, h18Track, "a", at: 0)
func h18State() -> [String: Any] {
    var state: [String: Any] = [
        "names": graphicNames(h18), "modules": h18Store?.scan.modules.keys.sorted() ?? [],
        "journal": textAt(h18Folder.appendingPathComponent("history/renames.json")),
        "pairs": (h18Store?.renamePairs() ?? []).map { [$0.0, $0.1] },
        "undo_name": h18.undoManager?.undoActionName ?? "",
    ]
    for name in ["a", "b", "c"] {
        state["file_\(name)"] = textAt(h18Folder.appendingPathComponent("\(name).js"))
        state["kept_\(name)"] = keptTexts(h18Store, name)
        state["history_\(name)"] = historyDirectory(h18Store, name)
    }
    return state
}
/// A rename whose `apply` throws (`throwing`) or returns having applied nothing; the state after
/// it, the sentence it threw and the ops `apply` was handed.
func h18Refused(_ from: String, _ to: String, throwing: Bool) -> [String: Any] {
    var asked = 0
    let said = sentence {
        _ = try h18.renameGraphic(named: from, to: to) { ops in
            asked += ops.count
            if throwing { throw ReelCoreError(message: "h18: the clips refused") }
        }
    }
    var state = h18State()
    state["refused"] = said
    state["asked"] = asked
    return state
}
row = ["clip": Int(h18Clip), "texts": [h18a, h18b], "before": h18State()]
row["thrown_no_journal"] = h18Refused("a", "b", throwing: true)
row["left_no_journal"] = h18Refused("a", "b", throwing: false)
row["renamed"] = (try? h18.renameGraphic(named: "a", to: "b") {
    h18.performGroupedEdit("Rename Graphic", $0)
})?.map { Int($0) } ?? NSNull()
row["after_rename"] = h18State()
row["thrown_with_pair"] = h18Refused("b", "c", throwing: true)
row["left_with_pair"] = h18Refused("b", "c", throwing: false)
walk(h18, redo: false)
row["after_undo"] = h18State()
h18.close()
// LIMIT (G-28 (d)): onto a DELETED module's name the two histories have folded before the clips
// refuse, so the move back carries the deleted module's kept text under the renamed module.
let (h18d, h18dTrack) = graphicDocument()
let h18dStore = h18d.graphicStore
let h18dFolder = h18dStore?.folderURL ?? work
historyRoots.append(h18dFolder)
let (h18Gone, h18Live1, h18Live2) = (
    moduleText("h18 gone"), moduleText("h18 live 1"), moduleText("h18 live 2"))
writeModule(h18d, "gone", h18Gone)
var h18Deleted: [String: Any] = ["texts": [h18Gone, h18Live1, h18Live2]]
h18Deleted["deleted"] = sentence { _ = try h18d.deleteGraphic(named: "gone") }
writeModule(h18d, "live", h18Live1)
writeModule(h18d, "live", h18Live2)
let h18dClip = placeGraphic(h18d, h18dTrack, "live", at: 0)
h18Deleted["clip"] = Int(h18dClip)
h18Deleted["kept_before"] = ["gone": keptTexts(h18dStore, "gone"), "live": keptTexts(h18dStore, "live")]
h18Deleted["refused"] = sentence {
    _ = try h18d.renameGraphic(named: "live", to: "gone") { _ in
        throw ReelCoreError(message: "h18: the clips refused")
    }
}
h18Deleted["names"] = graphicNames(h18d)
h18Deleted["live_file"] = textAt(h18dFolder.appendingPathComponent("live.js"))
h18Deleted["gone_file"] = present(h18dFolder.appendingPathComponent("gone.js"))
h18Deleted["kept_after"] = ["gone": keptTexts(h18dStore, "gone"), "live": keptTexts(h18dStore, "live")]
h18Deleted["history_gone"] = historyDirectory(h18dStore, "gone")
h18Deleted["kept_names"] = h18dStore?.keptNames() ?? []
h18Deleted["journal"] = textAt(h18dFolder.appendingPathComponent("history/renames.json"))
h18Deleted["modules"] = h18dStore?.scan.modules.keys.sorted() ?? []
row["deleted_name"] = h18Deleted
h18d.close()
// A move back that FAILS (a FILE put at history/a by `apply` itself, so the history cannot be
// folded back) leaves the pair journalled; with the file removed, a committed change repairs.
let (h18f, h18fTrack) = graphicDocument()
let h18fStore = h18f.graphicStore
let h18fFolder = h18fStore?.folderURL ?? work
historyRoots.append(h18fFolder)
let (h18f1, h18f2) = (moduleText("h18 f 1"), moduleText("h18 f 2"))
writeModule(h18f, "a", h18f1)
writeModule(h18f, "a", h18f2)
let h18fClip = placeGraphic(h18f, h18fTrack, "a", at: 0)
let h18fInTheWay = h18fFolder.appendingPathComponent("history/a")
func h18fState() -> [String: Any] {
    [
        "names": graphicNames(h18f), "modules": h18fStore?.scan.modules.keys.sorted() ?? [],
        "a_file": textAt(h18fFolder.appendingPathComponent("a.js")),
        "b_file": textAt(h18fFolder.appendingPathComponent("b.js")),
        "kept_a": keptTexts(h18fStore, "a"), "kept_b": keptTexts(h18fStore, "b"),
        "pairs": (h18fStore?.renamePairs() ?? []).map { [$0.0, $0.1] },
    ]
}
var h18Failed: [String: Any] = ["clip": Int(h18fClip), "texts": [h18f1, h18f2]]
h18Failed["refused"] = sentence {
    _ = try h18f.renameGraphic(named: "a", to: "b") { _ in
        write("in the way", h18fInTheWay)
        throw ReelCoreError(message: "h18: the clips refused")
    }
}
h18Failed["in_the_way"] = present(h18fInTheWay)
h18Failed["stranded"] = h18fState()
try? files.removeItem(at: h18fInTheWay)
let h18fTracks = h18f.project.snapshot.tracks.count
h18f.performGroupedEdit("Add Track", [.addTrack(index: 0)])
h18Failed["tracks_added"] = h18f.project.snapshot.tracks.count - h18fTracks
h18Failed["repaired"] = h18fState()
row["failed_move_back"] = h18Failed
answer["h18"] = row
h18f.close()

// C7 — an untitled document's save carries graphics/history/
let (c7, _) = graphicDocument()
if let root = c7.graphicStore?.folderURL { historyRoots.append(root) }
let (c7a, c7b) = (moduleText("c7 a"), moduleText("c7 b"))
writeModule(c7, "m", c7a)
writeModule(c7, "m", c7b)
let c7Package = work.appendingPathComponent("C7-saved.reelcut", isDirectory: true)
try? files.removeItem(at: c7Package)
row = ["texts": [c7a, c7b]]
do {
    let wrapper = try c7.fileWrapper(ofType: projectType)
    try wrapper.write(to: c7Package, options: .atomic, originalContentsURL: nil)
} catch {
    row["save_error"] = error.localizedDescription
}
let c7History = c7Package.appendingPathComponent("graphics/history/m")
let c7Entries = ((try? files.contentsOfDirectory(atPath: c7History.path)) ?? []).sorted()
row["entries"] = c7Entries
row["kept_text"] = c7Entries.first.map { textAt(c7History.appendingPathComponent($0)) } ?? NSNull()
row["module"] = textAt(c7Package.appendingPathComponent("graphics/m.js"))
answer["c7"] = row
c7.close()
answer["history_roots_removed"] = historyRoots.allSatisfy { !present($0) || $0 == hs.folderURL }
try? files.removeItem(at: hs.folderURL)

// The untitled roots this run made, removed so the temporary directory is
// left as found (a mutant leaves the C5 and C6 ones behind).
for leftover in [c5aRoot, c5bRoot, c6aRoot, c6bRoot].compactMap({ $0 }) {
    try? files.removeItem(at: leftover)
}
let roots = [s.folderURL, es.folderURL, libraryFolder, failedOpenRoot, fontRoot, namesRoot, badRoot]
    + [c2Root, c3Root].compactMap { $0 }
for root in roots { try? files.removeItem(at: root) }
answer["roots_removed"] = roots.allSatisfy { !present($0) }

answer["ok"] = true
finish()
