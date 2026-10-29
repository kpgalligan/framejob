// app/Sources/GraphicTemplates.swift — the graphic modules the app bundles
// as templates (road map 10's G5b): `graphic/tests/graphics/*.js`, copied
// into `Contents/Resources/GraphicTemplates/` by project.yml's "Copy Graphic
// Templates" script. Insert ▸ Graphic… lists them by category
// (`GraphicCatalog.swift`, spec §11 G-45); inserting one writes it into the
// package's `graphics/` under a free name and places a clip drawn by it.
//
// **`list(in:)` compiles nothing**: it reads the folder, and a template's
// `title` here is its FILE STEM's. The browser's titles come from each
// template's `meta.name` (`GraphicTemplateLibrary` compiles them once, when
// the browser first opens); `title(for:)` is the fallback for a module with
// no `meta.name`. A missing folder lists nothing.

import Foundation

/// One bundled template: its module name (the file stem), its menu title
/// and where the file is.
struct GraphicTemplate: Equatable {
    let name: String
    let title: String
    let url: URL
}

enum GraphicTemplates {
    static let folderName = "GraphicTemplates"

    /// The folder beside `Fonts/` — `GraphicStore.manualDirectory`'s rule,
    /// so a probe that copies `Fonts/` next to itself can copy this too.
    static func directory(besideFonts fonts: URL) -> URL {
        GraphicStore.manualDirectory(besideFonts: fonts)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// The app bundle's own.
    static var bundledDirectory: URL {
        directory(besideFonts: ProjectDocument.bundledFontsDirectory)
    }

    /// Every `*.js` in `directory` whose stem is a module name, sorted by
    /// name; `[]` when the folder is absent.
    static func list(in directory: URL) -> [GraphicTemplate] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { url -> GraphicTemplate? in
            guard url.pathExtension == "js" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            guard GraphicStore.isModuleName(name) else { return nil }
            return GraphicTemplate(name: name, title: title(for: name), url: url)
        }.sorted { $0.name < $1.name }
    }

    /// "lower-third" → "Lower Third": split on "-", each part capitalised.
    static func title(for name: String) -> String {
        name.split(separator: "-").map { part in
            part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    /// A file stem made a module name: lowercased; every run of anything
    /// but `a-z0-9` one "-"; "-" trimmed from both ends; at most 63
    /// characters; "graphic" when nothing is left.
    static func moduleName(from stem: String) -> String {
        var scalars: [Unicode.Scalar] = []
        var pendingDash = false
        for scalar in stem.lowercased().unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingDash, !scalars.isEmpty { scalars.append("-") }
                pendingDash = false
                scalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        var name = String(String.UnicodeScalarView(scalars.prefix(63)))
        while name.hasSuffix("-") { name.removeLast() }
        return name.isEmpty ? "graphic" : name
    }
}
