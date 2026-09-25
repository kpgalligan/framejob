// app/Sources/GraphicStore+Import.swift — a font or a picture copied into
// `graphics/fonts/` or `graphics/assets/` (road map 10 §5h, G4b; G5b): the
// ONE body behind the agent's `import_graphic_font` and
// `import_graphic_asset` and a person's File ▸ Add Font to Graphics… and
// Add Image to Graphics…, so the two doors refuse in the same sentences.
//
// It goes through `ensureFolder()`, the ONE creator of `graphics/` inside a
// package (G-14), and lands the file the way `write(name:source:)` lands a
// module: a `<name>.partial` beside it, then moved into place, so the scan
// never reads half a file (a `.partial`'s extension is in neither the font
// nor the asset set, so it is never listed). `importFile` does not rescan;
// `importFont` and `importAsset` end in ONE `rescan()`, so the registry has
// its new library when they return — both are called from a handler or a
// command, never from a `.graphicsDidChange` observer (`drain()` is not
// re-entrant).
//
// **A font's family names are the ENGINE's own** (`rc_graphic_library_families`):
// the file is loaded into a throwaway library of its own and that library is
// asked, so `families` is exactly what a `font-family` must say — CoreText
// names some files differently (road map 10 §10.7 G4b measured 13 of 2500).
// Not undoable and never dirty (G-3).

import Foundation

extension GraphicStore {
    /// Copies `source` to `graphics/<subfolder>/<name>`, replacing a file of
    /// that name. Whether one was replaced. Main.
    func importFile(from source: URL, into subfolder: String, as name: String) throws
        -> (url: URL, replaced: Bool)
    {
        try ensureFolder()
        let files = FileManager.default
        let folder = folderURL.appendingPathComponent(subfolder, isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(name)
        let partial = folder.appendingPathComponent(name + ".partial")
        try? files.removeItem(at: partial)
        try files.copyItem(at: source, to: partial)
        let replaced = files.fileExists(atPath: target.path)
        if replaced {
            _ = try files.replaceItemAt(target, withItemAt: partial)
        } else {
            try files.moveItem(at: partial, to: target)
        }
        return (target, replaced)
    }

    /// What `graphics/assets/` takes, in the refusals' words.
    static let assetKinds = "PNG, JPEG, GIF, WebP, SVG or SVGZ"

    /// A `.ttf` or `.otf` copied into `graphics/fonts/` under its own name,
    /// then `rescan()`. The families are the engine's reading of that file
    /// alone. Main.
    func importFont(from source: URL) throws -> (url: URL, replaced: Bool, families: [String]) {
        let path = source.path
        guard Self.fontExtensions.contains(source.pathExtension.lowercased()) else {
            throw ReelCoreError(message: "\(path) is not a .ttf or .otf file")
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: source)
        } catch {
            throw ReelCoreError(
                message: "\(path) could not be read: \(error.localizedDescription)")
        }
        let probe = GraphicLibrary()
        do {
            try probe.addFont(bytes)
        } catch let error as ReelCoreError {
            throw ReelCoreError(message: "\(path): " + error.message)
        }
        let families = probe.families()
        let landed = try importNamed(source, Self.fontsFolderName, source.lastPathComponent)
        rescan()
        return (landed.url, landed.replaced, families)
    }

    /// A picture copied into `graphics/assets/<name>`, then `rescan()`.
    /// `name` is what `asset(name)` says; its extension must be one of the
    /// six. Main.
    func importAsset(from source: URL, as name: String) throws
        -> (url: URL, replaced: Bool, bytes: Int)
    {
        let path = source.path
        let kinds = Self.assetKinds
        guard !name.isEmpty, !name.contains("/") else {
            throw ReelCoreError(
                message: "name must be a file name with no / (got \"\(name)\") — it is what "
                    + "asset(name) says")
        }
        guard Self.assetExtensions.contains((name as NSString).pathExtension.lowercased())
        else {
            throw ReelCoreError(
                message: "\(name) is not a \(kinds) file (.png .jpg .jpeg .gif .webp .svg .svgz)")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size]
            as? NSNumber)?.intValue ?? 0
        // An empty file crosses the FFI as NULL and the scan skips it.
        guard size > 0 else {
            throw ReelCoreError(
                message: "\(path) is empty (0 bytes) — an asset must hold a \(kinds) image")
        }
        let landed = try importNamed(source, Self.assetsFolderName, name)
        rescan()
        return (landed.url, landed.replaced, size)
    }

    /// `importFile`, its failure said in a sentence naming the folder.
    private func importNamed(_ source: URL, _ subfolder: String, _ name: String) throws
        -> (url: URL, replaced: Bool)
    {
        do {
            return try importFile(from: source, into: subfolder, as: name)
        } catch {
            throw ReelCoreError(
                message: "graphics/\(subfolder)/\(name) could not be written: "
                    + error.localizedDescription)
        }
    }
}
