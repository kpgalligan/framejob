// app/Sources/ProjectDocument+Graphics.swift — the document's side of the
// package's `graphics/` folder (road map 10 §5f, G3a): the store's start,
// and the lazy wrapper the save whitelist carries the folder in.
//
// An `extension ProjectDocument` in its own file, `+Recording`'s shape: the
// base file is over the ~600-line cap and takes only what cannot live here —
// the stored `graphicStore`, the whitelist line, and the three one-line
// calls in `fileURL`'s setter, `makeWindowControllers()` and `close()`.
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
            guard let root = graphicStore?.folderURL,
                let entries = try? files.contentsOfDirectory(atPath: root.path),
                !entries.isEmpty
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
    /// store does not keep a closed document alive.
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
    }
}
