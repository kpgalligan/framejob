// app/Sources/GraphicStore.swift — one document's `graphics/` folder: where
// it is, what is in it, and when that changes (road map 10 §5f, G3a). It
// scans, hashes (G-13) and says what changed; a file edit is not undo (G-3).
//
// **Created on the app's first write, never at open** (spec §11 G-14):
// `ensureFolder()` is the one creator inside a package; while it is absent
// the PACKAGE directory is watched, so an outside `mkdir` is seen.
//
// **The watch** is G0's q7(c): a folder source raises `.write` only and an
// in-place (`O_TRUNC`) save raises nothing on the folder, so every `*.js`
// has its own source; events are coalesced over 100 ms. Every pass re-opens
// every source BY PATH (a save swaps inodes) and arms BEFORE it scans.
//
// **Threading.** One serial queue alone touches the queue-confined state; it
// diffs, and main publishes in order through `drain()`. Main waits on the
// queue only through `queue.sync`; the queue never waits on main.

import CryptoKit
import Foundation

extension Notification.Name {
    /// Posted on main (object: the store) when modules were added, changed
    /// or removed, or the font and asset set moved. `userInfo[namesKey]`:
    /// the names, sorted (all of them when the library moved);
    /// `[libraryKey]`: whether it moved.
    static let graphicsDidChange = Notification.Name("ReelcutGraphicsDidChange")

    /// Posted on main by a `GraphicStore` (object: the store) when the first
    /// save, or a Save As, moved its folder (`packageDidMove(to:)`).
    static let graphicsLocationDidChange = Notification.Name(
        "ReelcutGraphicsLocationDidChange")
}

final class GraphicStore {
    static let folderName = "graphics", fontsFolderName = "fonts", assetsFolderName = "assets"
    static let namesKey = "names", libraryKey = "library"
    /// G-6: the faces the engine loads from `graphics/fonts/`.
    static let fontExtensions: Set<String> = ["ttf", "otf"]
    /// §5a: the pictures resvg draws from `graphics/assets/`.
    static let assetExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "svgz"]
    static let coalesceInterval: TimeInterval = 0.1

    /// G-3's rule, `^[a-z0-9][a-z0-9-]{0,62}$`, mirrored from
    /// `model_graphic.rs`'s `check_name`; the core stays the validator.
    static func isModuleName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard let head = scalars.first, scalars.count <= 63 else { return false }
        let lowerOrDigit = { (s: Unicode.Scalar) in
            ("a"..."z").contains(s) || ("0"..."9").contains(s)
        }
        return lowerOrDigit(head) && scalars.allSatisfy { lowerOrDigit($0) || $0 == "-" }
    }

    private static let nameRule = "is not a module name (lowercase letters, digits and -, "
        + "starting with a letter or a digit, at most 63 characters)"

    /// The core's own sentence for a bad name (`model_graphic.rs`).
    static func nameSentence(_ name: String) -> String {
        "graphic name \"\(name)\" \(nameRule)"
    }

    static func hex<D: Digest>(_ digest: D) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The app's bundled faces (`app/Resources/Fonts/`, G-6).
    let bundledFonts: URL
    /// The package, or nil for an untitled document.
    private(set) var package: URL?
    /// `<package>/graphics`, which the store creates only in
    /// `ensureFolder()`; or the untitled root, created at `start()`.
    private(set) var folderURL: URL
    /// The last published scan, written on main; locked because
    /// `module(named:)` and `makeLibrary()` may be called from any thread.
    private(set) var scan: GraphicScan {
        get { scanLock.withLock { storedScan } }
        set { scanLock.withLock { storedScan = newValue } }
    }
    /// Main; once per OBSERVED absent → present of `<package>/graphics`, made
    /// here or found. Never for the untitled root, never at `start()`.
    var folderDidAppear: (() -> Void)?

    private var seed: URL?
    private let scanLock = NSLock()
    private var storedScan = GraphicScan.empty
    private let queue = DispatchQueue(label: "com.kgalligan.reelcut.graphics")

    private typealias Outcome = (
        scan: GraphicScan, names: [String], library: Bool, folderAppeared: Bool
    )
    // Queue-confined, all of it.
    private var generation = 0
    private var running = false
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private var lastScan = GraphicScan.empty
    private var folderPresent = false
    private var outbox: [Outcome] = []
    private var watchedPackage: URL?
    private var watchedFolder: URL

    /// `seed`: a folder whose entries are copied into the fresh untitled
    /// root at `start()` — an untitled document restored from autosave.
    init(package: URL?, seed: URL?, bundledFonts: URL) {
        let folder = package?.appendingPathComponent(Self.folderName, isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("Reelcut", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + "-graphics", isDirectory: true)
        self.package = package
        self.seed = package == nil ? seed : nil
        self.bundledFonts = bundledFonts
        folderURL = folder
        watchedFolder = folder
    }

    deinit {
        // No `queue.sync`: the last release can come from a handler on the queue.
        for source in sources { source.cancel() }
    }

    // MARK: - Life cycle (main)

    func start() {
        let files = FileManager.default
        if package == nil {
            try? files.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if let seed = seed, let entries = try? files.contentsOfDirectory(
                at: seed, includingPropertiesForKeys: nil)
            {
                for entry in entries {
                    try? files.copyItem(
                        at: entry, to: folderURL.appendingPathComponent(entry.lastPathComponent))
                }
            }
            seed = nil
        }
        let (package, folder) = (self.package, folderURL)
        let initial: GraphicScan = queue.sync {
            generation += 1
            running = true
            watchedPackage = package
            watchedFolder = folder
            let (found, exists) = armAndScan(generation)
            lastScan = found
            folderPresent = exists
            outbox = []
            return found
        }
        scan = initial
    }

    func stop() {
        queue.sync {
            generation += 1
            running = false
            pending?.cancel()
            pending = nil
            cancelSources()
            outbox = []
        }
    }

    func packageDidMove(to package: URL?) {
        guard let package = package else { return }
        let folder = package.appendingPathComponent(Self.folderName, isDirectory: true)
        guard folder.standardizedFileURL.path != folderURL.standardizedFileURL.path else { return }
        stop()
        self.package = package
        folderURL = folder
        start()
        NotificationCenter.default.post(name: .graphicsLocationDidChange, object: self)
    }

    func rescan() {
        queue.sync { pass(generation) }
        drain()
    }

    /// The ONE creator of `graphics/` inside a package (G-14).
    func ensureFolder() throws {
        guard !FileManager.default.fileExists(atPath: folderURL.path) else { return }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        rescan()
    }

    func module(named name: String) -> GraphicModuleFile? { scan.modules[name] }

    /// The app's own write: `<name>.js.partial`, then moved into place, so
    /// a reader never sees half a module.
    func write(name: String, source: String) throws {
        guard Self.isModuleName(name) else { throw ReelCoreError(message: Self.nameSentence(name)) }
        try ensureFolder()
        let files = FileManager.default
        let target = folderURL.appendingPathComponent(name + ".js")
        let partial = folderURL.appendingPathComponent(name + ".js.partial")
        try? files.removeItem(at: partial)
        try Data(source.utf8).write(to: partial)
        if files.fileExists(atPath: target.path) {
            _ = try files.replaceItemAt(target, withItemAt: partial)
        } else {
            try files.moveItem(at: partial, to: target)
        }
    }

    /// A NEW builder each call — a library is frozen by its first compile
    /// or rasterize — holding the bundled faces, then `scan.fonts`, then
    /// `scan.assets` by name.
    func makeLibrary() throws -> GraphicLibrary {
        let library = GraphicLibrary()
        let bundled = (try? FileManager.default.contentsOfDirectory(
            at: bundledFonts, includingPropertiesForKeys: nil)) ?? []
        for url in bundled.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where Self.fontExtensions.contains(url.pathExtension.lowercased()) {
            try library.addFont(Data(contentsOf: url))
        }
        let current = scan
        for font in current.fonts { try library.addFont(font.bytes) }
        for asset in current.assets { try library.addAsset(name: asset.name, bytes: asset.bytes) }
        return library
    }

    // MARK: - Publishing (main)

    /// Takes the queue's outcomes and publishes each in order.
    private func drain() {
        let outcomes: [Outcome] = queue.sync { defer { outbox = [] }; return outbox }
        for outcome in outcomes {
            scan = outcome.scan
            if outcome.folderAppeared { folderDidAppear?() }
            guard !outcome.names.isEmpty else { continue }
            NotificationCenter.default.post(
                name: .graphicsDidChange, object: self,
                userInfo: [Self.namesKey: outcome.names, Self.libraryKey: outcome.library])
        }
    }

    // MARK: - The queue

    /// A source fired: the FIRST event schedules a pass 100 ms out, and the
    /// ones after it are absorbed into that pass.
    private func sourceFired(_ g: Int) {
        guard running, generation == g, pending == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.running, self.generation == g else { return }
            self.pending = nil
            self.pass(g)
            DispatchQueue.main.async { [weak self] in self?.drain() }
        }
        pending = item
        queue.asyncAfter(deadline: .now() + Self.coalesceInterval, execute: item)
    }

    /// Re-arms, rescans and diffs against the last pass; the outcome goes to
    /// the outbox for `drain()`.
    private func pass(_ g: Int) {
        guard running, generation == g else { return }
        let (found, exists) = armAndScan(g)
        var names = Set<String>()
        for (name, module) in found.modules
        where lastScan.modules[name]?.revision != module.revision {
            names.insert(name)
        }
        for name in lastScan.modules.keys where found.modules[name] == nil { names.insert(name) }
        let library = found.libraryVersion != lastScan.libraryVersion
        if library { names.formUnion(found.modules.keys) }
        let appeared = watchedPackage != nil && !folderPresent && exists
        lastScan = found
        folderPresent = exists
        outbox.append((found, names.sorted(), library, appeared))
    }

    private func cancelSources() {
        for source in sources { source.cancel() }
        sources = []
    }

    /// FOLDER mode when the folder exists (a source on it, on each existing
    /// subfolder and on each module file); PACKAGE mode when a saved
    /// package has none (one source on the package directory). An untitled
    /// root found absent is recreated. Arms first, then scans.
    private func armAndScan(_ g: Int) -> (GraphicScan, Bool) {
        cancelSources()
        let files = FileManager.default
        var exists = files.fileExists(atPath: watchedFolder.path)
        if !exists, watchedPackage == nil {
            try? files.createDirectory(at: watchedFolder, withIntermediateDirectories: true)
            exists = files.fileExists(atPath: watchedFolder.path)
        }
        guard exists else {
            if let package = watchedPackage { arm(package, folder: true, g) }
            return (.empty, false)
        }
        let fonts = watchedFolder.appendingPathComponent(Self.fontsFolderName, isDirectory: true)
        let assets = watchedFolder.appendingPathComponent(Self.assetsFolderName, isDirectory: true)
        for folder in [watchedFolder, fonts, assets] where files.fileExists(atPath: folder.path) {
            arm(folder, folder: true, g)
        }
        var warnings: [String] = []
        var modules: [String: GraphicModuleFile] = [:]
        for url in listing(watchedFolder) where url.pathExtension == "js" {
            let name = url.deletingPathExtension().lastPathComponent
            guard Self.isModuleName(name) else {
                warnings.append("\(Self.folderName)/\(url.lastPathComponent) \(Self.nameRule)")
                continue
            }
            arm(url, folder: false, g)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            modules[name] = GraphicModuleFile(
                name: name, url: url, bytes: bytes, revision: Self.hex(SHA256.hash(data: bytes)))
        }
        var fontFiles: [GraphicFile] = []
        for url in listing(fonts)
        where Self.fontExtensions.contains(url.pathExtension.lowercased()) {
            guard let bytes = try? Data(contentsOf: url) else { continue }
            do {
                try GraphicLibrary().addFont(bytes)
                fontFiles.append(GraphicFile(name: url.lastPathComponent, url: url, bytes: bytes))
            } catch {
                warnings.append("\(Self.relative(url)): \(error.localizedDescription)")
            }
        }
        var assetFiles: [GraphicFile] = []
        for url in listing(assets)
        where Self.assetExtensions.contains(url.pathExtension.lowercased()) {
            guard let bytes = try? Data(contentsOf: url) else { continue }
            // An empty `Data` crosses the FFI as NULL, which `addAsset` refuses.
            guard !bytes.isEmpty else {
                warnings.append("\(Self.relative(url)) is empty and was skipped")
                continue
            }
            assetFiles.append(GraphicFile(name: url.lastPathComponent, url: url, bytes: bytes))
        }
        var hasher = SHA256()
        for file in fontFiles + assetFiles {
            hasher.update(data: Data(file.name.utf8))
            hasher.update(data: file.bytes)
        }
        let found = GraphicScan(
            modules: modules, fonts: fontFiles, assets: assetFiles,
            libraryVersion: Self.hex(hasher.finalize()), warnings: warnings)
        return (found, true)
    }

    /// `graphics/fonts/x.ttf` for a warning.
    private static func relative(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return "\(folderName)/\(parent)/\(url.lastPathComponent)"
    }

    /// A folder's regular files, sorted by name; empty when it is absent.
    private func listing(_ folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []
        let regular = entries.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
        return regular.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func arm(_ url: URL, folder: Bool, _ g: Int) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let mask: DispatchSource.FileSystemEvent = folder
            ? [.write, .delete, .rename, .revoke] : [.write, .extend, .delete, .rename]
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in self?.sourceFired(g) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }
}
