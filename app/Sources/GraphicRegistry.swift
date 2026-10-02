// app/Sources/GraphicRegistry.swift — the compiled graphics each document
// draws with (road map 10 §5f's registry paragraph, G3b): a `RecipeSource`
// key → one immutable `GraphicSet`, the library and every module of that
// document's `graphics/` compiled against it.
//
// **Preview follows the newest revision** (G-13): the document installs its
// set when its store starts and swaps a NEW set in on every
// `.graphicsDidChange` (`ProjectDocument+Graphics.swift`). A font or asset
// change builds a new library and recompiles every module against it — a
// library is frozen by its first compile — and anything else recompiles only
// the named modules against the existing library. Nothing here calls
// `store.rescan()`: `drain()` is not re-entrant (road map 10 §10.6 G3a).
//
// **Threading.** `install`, `update`, `remove` and `entry` are main-only,
// because the store's scan is. `resolve`, `snapshot` and the pin's five
// calls are any-thread — the compositor's render queue and a `render_frame`
// generator thread — and the lock covers only the two maps; a module draws
// on a thread that did not compile it (the engine keeps per-thread
// runtimes, G1c).
//
// **An offline key** — the one `Exporter.renderFrame` or an export mints —
// draws with the set its caller PINNED on it (G-13, G3c): the document's
// set as it stood when the export or the frame was asked for, retained for
// the key's life however the document's own set changes. A key with no
// set and no pin resolves nil and the layer draws the slate. A pin also
// holds what the key's graphics REPORTED — the first failure in a slot of
// its own, then up to 64 warnings distinct by graphic and messages, the
// frame aside, so one graphic warning every frame keeps one (G-24 (c)) — for
// `render_frame`'s reply, the export's abort and its `graphicWarnings`.

import Foundation

/// One document's compiled graphics at one instant. Immutable: a change
/// makes a new one, so a frame in flight keeps a coherent set.
final class GraphicSet {
    let library: GraphicLibrary
    /// The store's `GraphicScan.libraryVersion` the library was built from —
    /// part of the texture key, so a font change never serves an old raster.
    let libraryVersion: String
    let modules: [String: GraphicRegistry.Entry]
    /// The library could not be built, so `library` is an empty stand-in:
    /// no module may be compiled against it, and `update` rebuilds instead.
    let libraryFailed: Bool

    init(
        library: GraphicLibrary, libraryVersion: String, modules: [String: GraphicRegistry.Entry],
        libraryFailed: Bool = false
    ) {
        self.library = library
        self.libraryVersion = libraryVersion
        self.modules = modules
        self.libraryFailed = libraryFailed
    }
}

/// What one graphic reported while an offline key drew it: a failure (the
/// error card was drawn) or a warning, with the graphic's own frame — nil
/// when the module did not compile.
struct GraphicReport: Equatable {
    let name: String
    let frame: Int?
    let failed: Bool
    let diagnostics: [GraphicDiagnostic]
}

final class GraphicRegistry {
    static let shared = GraphicRegistry()

    /// The engine's budgets, in milliseconds: a compile, one preview frame,
    /// and one frame of an export or a `render_frame`.
    static let compileBudgetMs = 250, previewBudgetMs = 250, offlineBudgetMs = 2000

    /// One module as compiled against a set's library: the module with its
    /// file's revision and its `describe` parsed, or why it did not compile.
    enum Entry {
        case compiled(GraphicModule, revision: String, meta: [String: Any], schema: [String: Any])
        case failed([GraphicDiagnostic], revision: String)
    }

    /// An offline key's pinned set and what its graphics reported. The
    /// FIRST failure owns `failure` for the pin's life, so a graphic that
    /// warns on every frame can fill `warnings` and never hide it.
    private struct Pin {
        let set: GraphicSet
        var failure: GraphicReport?
        var warnings: [GraphicReport]
    }

    /// Warnings a pin keeps; a later distinct one is dropped.
    static let warningLimit = 64

    private let lock = NSLock()
    private var sets: [Int: GraphicSet] = [:]
    private var pins: [Int: Pin] = [:]

    private init() {}

    /// Compiles every module the store's scan holds against a NEW library
    /// and publishes the set under `key`. Main.
    func install(_ store: GraphicStore, for key: Int) {
        let scan = store.scan
        let set: GraphicSet
        do {
            let library = try store.makeLibrary()
            set = GraphicSet(
                library: library, libraryVersion: scan.libraryVersion,
                modules: scan.modules.mapValues { Self.compile($0, library: library) })
        } catch {
            // The library could not be built (a font the engine refused):
            // every module fails with that sentence and draws the slate.
            let reason = [GraphicDiagnostic(
                level: "error", message: error.localizedDescription, line: nil, column: nil, frame: nil)]
            set = GraphicSet(
                library: GraphicLibrary(), libraryVersion: scan.libraryVersion,
                modules: scan.modules.mapValues { .failed(reason, revision: $0.revision) },
                libraryFailed: true)
        }
        publish(set, for: key)
    }

    /// Answers one `.graphicsDidChange`. `library` true is a font or asset
    /// change: a new library and every module recompiled. Otherwise only
    /// `names` are recompiled, against the EXISTING library — a frozen
    /// library refuses adds, not compiles — and a name the scan no longer
    /// holds is dropped. A set whose library failed is rebuilt whole, so no
    /// module compiles against its empty stand-in. Always a new set. Main.
    func update(_ store: GraphicStore, for key: Int, names: [String], library: Bool) {
        lock.lock()
        let current = sets[key]
        lock.unlock()
        guard let current = current, !library, !current.libraryFailed else {
            install(store, for: key)
            return
        }
        let scan = store.scan
        var modules = current.modules
        for name in names {
            if let file = scan.modules[name] {
                modules[name] = Self.compile(file, library: current.library)
            } else {
                modules.removeValue(forKey: name)
            }
        }
        publish(
            GraphicSet(
                library: current.library, libraryVersion: current.libraryVersion,
                modules: modules),
            for: key)
    }

    /// Drops a document's set, when its store stops. Main.
    func remove(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        sets.removeValue(forKey: key)
    }

    /// The module `name` as the document keyed `key` has it compiled — the
    /// op tools' read of `meta` and `schema`. Main.
    func entry(named name: String, for key: Int) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return sets[key]?.modules[name]
    }

    /// The set a document keyed `key` draws with right now — what an export
    /// or a `render_frame` pins. Any thread.
    func snapshot(for key: Int) -> GraphicSet? {
        lock.lock()
        defer { lock.unlock() }
        return sets[key]
    }

    /// Opens `key`'s pin on `set`: an offline key draws with it until
    /// `unpin`, and records its reports. Any thread.
    func pin(_ set: GraphicSet, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        pins[key] = Pin(set: set, failure: nil, warnings: [])
    }

    /// Drops `key`'s pin and its reports; a no-op for a key never pinned.
    /// Any thread.
    func unpin(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        pins.removeValue(forKey: key)
    }

    /// Keeps `report` against a pinned key; a no-op for any other key. A
    /// failure fills the failure slot if it is empty and is dropped
    /// otherwise; a warning is appended unless the same one (`sameWarning`)
    /// is held or `warningLimit` are. Any thread.
    func record(_ report: GraphicReport, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard var pin = pins[key] else { return }
        if report.failed {
            guard pin.failure == nil else { return }
            pin.failure = report
        } else {
            guard pin.warnings.count < Self.warningLimit,
                !pin.warnings.contains(where: { Self.sameWarning($0, report) })
            else { return }
            pin.warnings.append(report)
        }
        pins[key] = pin
    }

    /// Everything `key`'s pin holds: the failure first, then the warnings in
    /// the order they arrived. Any thread.
    func reports(for key: Int) -> [GraphicReport] {
        lock.lock()
        defer { lock.unlock() }
        guard let pin = pins[key] else { return [] }
        return (pin.failure.map { [$0] } ?? []) + pin.warnings
    }

    /// One graphic's same warning at another frame: the name and every
    /// diagnostic's located message equal, the frame aside (G-24 (c)).
    static func sameWarning(_ a: GraphicReport, _ b: GraphicReport) -> Bool {
        a.name == b.name && a.diagnostics.map(\.located) == b.diagnostics.map(\.located)
    }

    /// The pin's failure slot — the first failure it recorded. Any thread.
    func failure(for key: Int) -> GraphicReport? {
        lock.lock()
        defer { lock.unlock() }
        return pins[key]?.failure
    }

    /// The set a recipe under `key` draws with, and the per-frame budget:
    /// a document's own key answers its set at the preview budget; a
    /// pinned offline key answers its pinned set at the offline budget;
    /// anything else is nil. Any thread.
    func resolve(_ key: Int) -> (set: GraphicSet, budgetMs: Int)? {
        lock.lock()
        defer { lock.unlock() }
        if let own = sets[key] { return (own, Self.previewBudgetMs) }
        if let pinned = pins[key] { return (pinned.set, Self.offlineBudgetMs) }
        return nil
    }

    private func publish(_ set: GraphicSet, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        sets[key] = set
    }

    /// One module file compiled against `library`, its `describe` parsed.
    private static func compile(_ file: GraphicModuleFile, library: GraphicLibrary) -> Entry {
        let source = String(decoding: file.bytes, as: UTF8.self)
        do {
            let module = try GraphicModule.compile(
                library: library, name: file.name, source: source, budgetMs: compileBudgetMs)
            let described = (try? JSONSerialization.jsonObject(
                with: Data(module.describeJSON().utf8))) as? [String: Any]
            return .compiled(
                module, revision: file.revision,
                meta: described?["meta"] as? [String: Any] ?? [:],
                schema: described?["schema"] as? [String: Any] ?? [:])
        } catch let failure as GraphicFailure {
            return .failed(failure.diagnostics, revision: file.revision)
        } catch {
            return .failed(
                [GraphicDiagnostic(
                    level: "error", message: error.localizedDescription, line: nil, column: nil, frame: nil)],
                revision: file.revision)
        }
    }
}

extension GraphicModule {
    /// `describeJSON()`'s `warnings` — what the module's top level warned as
    /// it loaded (G-21 (b), G-24 (a)) — decoded; `[]` when absent or
    /// unreadable. Main or any thread.
    var compileWarnings: [GraphicDiagnostic] {
        struct Described: Decodable { let warnings: [GraphicDiagnostic]? }
        let described = try? JSONDecoder().decode(Described.self, from: Data(describeJSON().utf8))
        return described?.warnings ?? []
    }
}
