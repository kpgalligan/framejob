// app/Sources/ProjectDocument+Graphics.swift — the document's side of the
// package's `graphics/` folder (road map 10 §5f, G3a): the store's start,
// and the lazy wrapper the save whitelist carries the folder in.
//
// An `extension ProjectDocument` in its own file, `+Recording`'s shape: the
// base file is over the ~600-line cap and takes only what cannot live here —
// the stored `graphicStore`, the whitelist line, and the three one-line
// calls in `fileURL`'s setter, `makeWindowControllers()` and `close()`.
// G3b adds the compiled set: `GraphicRegistry`'s install at start, its
// update on the store's `.graphicsDidChange`, its removal at stop.
//
// **`graphics/` is user content, and the save wrapper is a whitelist**: a
// folder `fileWrapper(ofType:)` does not name is DELETED by the next save,
// autosave included (G0's q7 CONTROL). And it is created on the app's first
// write, never at open (spec §11 G-14), so a package that never gets a
// graphic is not touched.

import AppKit

extension ProjectDocument {
    static let graphicsDirectoryName = GraphicStore.folderName

    /// The faces bundled with the app (`project.yml`'s
    /// `ATSApplicationFontsPath`); the offscreen harness copies `Fonts`
    /// beside its binary, which is its `resourceURL`.
    static var bundledFontsDirectory: URL {
        (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    /// `graphics/` as a LAZY wrapper — `cacheWrapper()`'s laziness, read
    /// while NSDocument writes the new package, before the swap. A saved
    /// document reads `<fileURL>/graphics` itself and never asks the store,
    /// so a document with no store (never windowed) cannot drop a saved
    /// folder. An untitled one carries the store's root, and only when it
    /// holds something: an EMPTY scratch root is not carried (G-14).
    func graphicsWrapper() -> FileWrapper? {
        let files = FileManager.default
        let directory: URL
        if let fileURL = fileURL {
            directory = fileURL.appendingPathComponent(
                Self.graphicsDirectoryName, isDirectory: true)
            guard files.fileExists(atPath: directory.path) else { return nil }
        } else {
            guard let root = graphicStore?.folderURL, GraphicStore.holdsContent(root)
            else { return nil }
            directory = root
        }
        guard let wrapper = try? FileWrapper(url: directory, options: []) else { return nil }
        wrapper.preferredFilename = Self.graphicsDirectoryName
        return wrapper
    }

    /// Starts this document's store, from `makeWindowControllers()` — after
    /// NSDocument has set `fileURL`, and for an untitled document restored
    /// from autosave `autosavedContentsFileURL`, whose `graphics/` seeds the
    /// fresh root. `folderDidAppear` is the ONE caller of
    /// `packageContentsDidChangeOnDisk()` for this folder, weakly, so the
    /// store does not keep a closed document alive. It also observes the
    /// document's own `.projectDocumentDidChange` for the rename repair and
    /// ends with one repair (`ProjectDocument+GraphicFiles.swift`, spec §11
    /// G-28 (e)).
    func startGraphicStore() {
        let seed = fileURL == nil
            ? autosavedContentsFileURL?.appendingPathComponent(
                Self.graphicsDirectoryName, isDirectory: true)
            : nil
        let store = GraphicStore(
            package: fileURL, seed: seed, bundledFonts: Self.bundledFontsDirectory)
        store.folderDidAppear = { [weak self] in self?.packageContentsDidChangeOnDisk() }
        graphicStore = store
        store.start()
        GraphicRegistry.shared.install(store, for: recipeKey)
        NotificationCenter.default.addObserver(
            self, selector: #selector(graphicsDidChange(_:)), name: .graphicsDidChange,
            object: store)
        NotificationCenter.default.addObserver(
            self, selector: #selector(graphicNamesMayHaveChanged(_:)),
            name: .projectDocumentDidChange, object: self)
        reconcileGraphicNames()
    }

    /// The store saw modules or the font and asset set change: the registry
    /// compiles what changed (road map 10 G3b; G-13, preview follows the
    /// newest revision), THEN the document says so, so an observer that
    /// redraws draws with the new set. Never `rescan()` here: `drain()`,
    /// which posted this, is not re-entrant.
    @objc func graphicsDidChange(_ note: Notification) {
        guard let store = graphicStore, note.object as? GraphicStore === store else { return }
        let names = note.userInfo?[GraphicStore.namesKey] as? [String] ?? []
        let library = note.userInfo?[GraphicStore.libraryKey] as? Bool ?? false
        GraphicRegistry.shared.update(store, for: recipeKey, names: names, library: library)
        NotificationCenter.default.post(
            name: .projectGraphicsDidChange, object: self,
            userInfo: [GraphicStore.namesKey: names, GraphicStore.libraryKey: library])
    }

    /// Stops the store and drops its compiled set, from `close()`, then
    /// removes the untitled graphics root and the untitled cache root (spec
    /// §11 G-19 (d)). `close()`, in the over-cap base file, reaches the
    /// cache removal through this call.
    func stopGraphicStore() {
        if let store = graphicStore {
            NotificationCenter.default.removeObserver(
                self, name: .graphicsDidChange, object: store)
        }
        NotificationCenter.default.removeObserver(
            self, name: .projectDocumentDidChange, object: self)
        GraphicRegistry.shared.remove(recipeKey)
        graphicStore?.stop()
        graphicStore?.removeScratchRoot()
        graphicStore = nil
        removeTemporaryCacheDirectory()
    }

    /// Main, from `stopGraphicStore()`, which `close()` in the over-cap base
    /// file calls: removes `temporaryCacheDirectory` when it is set, whatever
    /// `fileURL` is, and leaves the property as it is. At close ONLY, never
    /// at the first save: until then the timeline and any pass in flight
    /// still hold that path, and the save's copy is complete by close
    /// (G-19 (d)).
    func removeTemporaryCacheDirectory() {
        guard let directory = temporaryCacheDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

extension Notification.Name {
    /// Posted on main (object: the document) after the registry has taken a
    /// `.graphicsDidChange` from the document's store; `userInfo` carries
    /// the store's `namesKey` and `libraryKey` through. The editor refreshes
    /// the paused frame on it.
    static let projectGraphicsDidChange = Notification.Name("FrameJobProjectGraphicsDidChange")
}
