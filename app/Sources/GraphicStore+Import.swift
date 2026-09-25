// app/Sources/GraphicStore+Import.swift — a font or a picture copied into
// `graphics/fonts/` or `graphics/assets/` (road map 10 §5h, G4b): the
// agent's `import_graphic_font` and `import_graphic_asset`, and G5's File ▸
// Add Font/Image to Graphics… when they are built.
//
// It goes through `ensureFolder()`, the ONE creator of `graphics/` inside a
// package (G-14), and lands the file the way `write(name:source:)` lands a
// module: a `<name>.partial` beside it, then moved into place, so the scan
// never reads half a file (a `.partial`'s extension is in neither the font
// nor the asset set, so it is never listed). It does not rescan; the caller
// does, outside any `.graphicsDidChange` observer.

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
}
