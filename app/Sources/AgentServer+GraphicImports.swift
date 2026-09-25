// app/Sources/AgentServer+GraphicImports.swift — `import_graphic_font` and
// `import_graphic_asset` (road map 10 §5h, G4b): a file copied into the
// package's `graphics/fonts/` or `graphics/assets/` through the store
// (`GraphicStore+Import.swift`), then ONE synchronous `rescan()`, so the
// registry has rebuilt the library before the reply is built.
//
// Both run on MAIN: the copy is one small file, and `rescan()` must be
// called from main, from the handler — never from a `.graphicsDidChange`
// observer, because `drain()` is not re-entrant.
//
// **A font's family names are the ENGINE's own** (`rc_graphic_library_families`):
// the file is loaded into a throwaway library of its own and that library is
// asked, so `families` is exactly what a `font-family` must say — CoreText
// names some files differently (road map 10 §10.7 G4b measured 13 of 2500).
// Not undoable and never dirty (G-3), `write_graphic`'s posture.

import Foundation

extension AgentServer {

    /// `import_graphic_font` — UI path: none yet — File ▸ Add Font to
    /// Graphics… (G5).
    func importGraphicFont(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let store = try graphicStore(document)
        let (source, path) = try graphicImportSource(a)
        guard GraphicStore.fontExtensions.contains(source.pathExtension.lowercased()) else {
            throw ToolError(message: "\(path) is not a .ttf or .otf file")
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: source)
        } catch {
            throw ToolError(message: "\(path) could not be read: \(error.localizedDescription)")
        }
        let probe = GraphicLibrary()
        do {
            try probe.addFont(bytes)
        } catch let error as ReelCoreError {
            throw ToolError(message: "\(path): " + error.message)
        }
        let families = probe.families()
        let landed = try graphicImport(store, source, GraphicStore.fontsFolderName,
                                       source.lastPathComponent)
        store.rescan()
        catchUpLibrary(store, document)
        return try jsonResult([
            "path": landed.url.path, "name": source.lastPathComponent, "replaced": landed.replaced,
            "families": families, "library_families": libraryFamilies(document),
            "note": Self.notUndoableNote,
        ])
    }

    /// `import_graphic_asset` — UI path: none yet — File ▸ Add Image to
    /// Graphics… (G5).
    func importGraphicAsset(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let store = try graphicStore(document)
        let (source, path) = try graphicImportSource(a)
        let name = try stringArg(a, "name") ?? source.lastPathComponent
        guard !name.isEmpty, !name.contains("/") else {
            throw ToolError(
                message: "name must be a file name with no / (got \"\(name)\") — it is what "
                    + "asset(name) says")
        }
        let kinds = "PNG, JPEG, GIF, WebP, SVG or SVGZ"
        guard GraphicStore.assetExtensions.contains((name as NSString).pathExtension.lowercased())
        else {
            throw ToolError(
                message: "\(name) is not a \(kinds) file (.png .jpg .jpeg .gif .webp .svg .svgz)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size]
            as? NSNumber)?.intValue ?? 0
        // An empty file crosses the FFI as NULL and the scan skips it.
        guard size > 0 else {
            throw ToolError(
                message: "\(path) is empty (0 bytes) — an asset must hold a \(kinds) image")
        }
        let landed = try graphicImport(store, source, GraphicStore.assetsFolderName, name)
        store.rescan()
        catchUpLibrary(store, document)
        return try jsonResult([
            "path": landed.url.path, "name": name, "replaced": landed.replaced, "bytes": size,
            "assets": store.scan.assets.map(\.name), "note": Self.notUndoableNote,
        ])
    }

    /// The registry's library rebuilt when the rescan left it behind: the
    /// store posts no `.graphicsDidChange` while `graphics/` holds no module,
    /// so a face or a picture imported into such a folder would stay out of
    /// the library — and out of every module written after it, which
    /// recompiles against the set's EXISTING library (road map 10 §10.7 G4b).
    /// Main, from the handler, never from an observer.
    private func catchUpLibrary(_ store: GraphicStore, _ document: ProjectDocument) {
        guard let current = GraphicRegistry.shared.snapshot(for: document.recipeKey),
            current.libraryVersion != store.scan.libraryVersion
        else { return }
        GraphicRegistry.shared.install(store, for: document.recipeKey)
    }

    /// `path`, `~` expanded: a regular file, or the sentence saying there is none.
    private func graphicImportSource(_ a: [String: Any]) throws -> (url: URL, path: String) {
        let path = (try requiredString(a, "path") as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { throw ToolError(message: "No file at \(path).") }
        return (URL(fileURLWithPath: path), path)
    }

    /// The store's copy, its failure said in a sentence naming the folder.
    private func graphicImport(
        _ store: GraphicStore, _ source: URL, _ subfolder: String, _ name: String
    ) throws -> (url: URL, replaced: Bool) {
        do {
            return try store.importFile(from: source, into: subfolder, as: name)
        } catch {
            throw ToolError(
                message: "graphics/\(subfolder)/\(name) could not be written: "
                    + error.localizedDescription)
        }
    }
}
