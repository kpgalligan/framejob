// app/Sources/AgentServer+GraphicImports.swift — `import_graphic_font` and
// `import_graphic_asset` (road map 10 §5h, G4b): a file copied into the
// package's `graphics/fonts/` or `graphics/assets/` through the store's
// `importFont(from:)` / `importAsset(from:as:)` (`GraphicStore+Import.swift`),
// the SAME body File ▸ Add Font to Graphics… and Add Image to Graphics… run
// (G5b). The store ends in ONE synchronous `rescan()`, whose post reaches the
// registry even in a folder holding no module, so the library is rebuilt
// before the reply is built.
//
// Both run on MAIN: the copy is one small file, and `rescan()` must be
// called from main, from the handler — never from a `.graphicsDidChange`
// observer, because `drain()` is not re-entrant. Not undoable and never
// dirty (G-3), `write_graphic`'s posture.

import Foundation

extension AgentServer {

    /// `import_graphic_font` — UI path: File ▸ Add Font to Graphics…
    /// (`EditorViewController+GraphicMenus.swift`).
    func importGraphicFont(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let store = try graphicStore(document)
        let (source, _) = try graphicImportSource(a)
        let landed = try store.importFont(from: source)
        return try jsonResult([
            "path": landed.url.path, "name": source.lastPathComponent, "replaced": landed.replaced,
            "families": landed.families, "library_families": libraryFamilies(document),
            "note": Self.notUndoableNote,
        ])
    }

    /// `import_graphic_asset` — UI path: File ▸ Add Image to Graphics…
    /// (`EditorViewController+GraphicMenus.swift`).
    func importGraphicAsset(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let store = try graphicStore(document)
        let (source, _) = try graphicImportSource(a)
        let name = try stringArg(a, "name") ?? source.lastPathComponent
        let landed = try store.importAsset(from: source, as: name)
        return try jsonResult([
            "path": landed.url.path, "name": name, "replaced": landed.replaced,
            "bytes": landed.bytes, "assets": store.scan.assets.map(\.name),
            "note": Self.notUndoableNote,
        ])
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
}
