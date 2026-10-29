// app/Sources/GraphicCatalog.swift — what Insert ▸ Graphic… lists (spec §11
// G-45): the bundled templates and the project's own modules as categories
// of graphics, in the one order the sheet (`GraphicBrowserSheetController`)
// and `list_graphics` (`AgentServer+GraphicBrowser.swift`) both show.
//
// **A template is compiled to read its `meta`, once per process**
// (`GraphicTemplateLibrary`, G-45 (e)): its title is `meta.name`, its
// category `meta.category`, its description `meta.description`. The first
// read is on main, when the browser or the tool first asks; it compiles
// against a library of the bundled fonts alone and is memoised under a lock.
// The menu bar never reads it (chrome probes instantiate `AppDelegate()`).
//
// **A project module is read from the registry**: the document's compiled
// set, as the inspector and the op tools read it. A module that does not
// compile is still listed (`ok` false), titled from its stem, so a person
// can see it is there and read why it will not insert.

import Foundation

/// One graphic the browser lists.
struct GraphicBrowserItem: Equatable {
    enum Origin: String { case template, project }
    /// A template's file stem; a project module's name.
    let name: String
    /// `GraphicCatalog.title(meta:name:)`; a This Project duplicate carries
    /// " — <name>" (G-45 (e)).
    let title: String
    let description: String?
    /// The module's own category (`meta.category`, else "Other") — a This
    /// Project item keeps its own here though it is listed under This Project.
    let category: String
    let origin: Origin
    /// The module compiled.
    let ok: Bool
}

/// One category and its graphics, in order.
struct GraphicBrowserCategory: Equatable {
    let name: String
    let items: [GraphicBrowserItem]
}

enum GraphicCatalog {
    static let thisProject = "This Project", other = "Other"

    /// G-45 (a): `meta.category` trimmed when it is a non-empty string, else
    /// "Other".
    static func category(meta: [String: Any]) -> String {
        let named = (meta["category"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return named.isEmpty ? other : named
    }

    /// G-45 (e): `meta.name` when it is a non-empty string, else the stem's
    /// title (`GraphicTemplates.title(for:)`).
    static func title(meta: [String: Any], name: String) -> String {
        let named = (meta["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return named.isEmpty ? GraphicTemplates.title(for: name) : named
    }

    /// `meta.description` trimmed, nil when absent or blank.
    static func description(meta: [String: Any]) -> String? {
        let text = (meta["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// One item from a compiled (or failed, or absent) registry entry.
    static func item(
        name: String, entry: GraphicRegistry.Entry?, origin: GraphicBrowserItem.Origin
    ) -> GraphicBrowserItem {
        var meta: [String: Any] = [:]
        var ok = false
        if case .compiled(_, _, let described, _)? = entry {
            meta = described
            ok = true
        }
        return GraphicBrowserItem(
            name: name, title: title(meta: meta, name: name), description: description(meta: meta),
            category: category(meta: meta), origin: origin, ok: ok)
    }

    /// G-45 (d): This Project first, only when `project` holds an item, with
    /// (e)'s duplicate titles told apart; then the templates' categories by
    /// case-insensitive name, Other last. Items by title case-insensitively,
    /// then by name.
    static func categories(
        templates: [GraphicBrowserItem], project: [GraphicBrowserItem]
    ) -> [GraphicBrowserCategory] {
        let ours: [GraphicBrowserCategory] = project.isEmpty ? []
            : [GraphicBrowserCategory(name: thisProject, items: sorted(distinguished(project)))]
        let names = Set(templates.map(\.category)).sorted { a, b in
            if (a == other) != (b == other) { return b == other }
            return a.caseInsensitiveCompare(b) == .orderedAscending
        }
        let theirs = names.map { name in
            GraphicBrowserCategory(
                name: name, items: sorted(templates.filter { $0.category == name }))
        }
        return ours + theirs
    }

    /// The document's list: the bundled templates and the modules its
    /// `graphics/` holds as the registry compiled them. Main.
    static func categories(for document: ProjectDocument) -> [GraphicBrowserCategory] {
        let templates = GraphicTemplateLibrary.shared.entries.map {
            item(name: $0.template.name, entry: $0.entry, origin: .template)
        }
        let modules = document.graphicStore?.scan.modules.keys.sorted() ?? []
        let project = modules.map {
            item(
                name: $0, entry: GraphicRegistry.shared.entry(named: $0, for: document.recipeKey),
                origin: .project)
        }
        return categories(templates: templates, project: project)
    }

    /// By title, case-insensitively, then by name.
    private static func sorted(_ items: [GraphicBrowserItem]) -> [GraphicBrowserItem] {
        items.sorted { a, b in
            switch a.title.caseInsensitiveCompare(b.title) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.name < b.name
            }
        }
    }

    /// Every item whose title another item shares, case-insensitively,
    /// titled "<title> — <name>".
    private static func distinguished(_ items: [GraphicBrowserItem]) -> [GraphicBrowserItem] {
        var counts: [String: Int] = [:]
        let key = { (title: String) in title.folding(options: .caseInsensitive, locale: nil) }
        for item in items { counts[key(item.title), default: 0] += 1 }
        return items.map { item in
            guard counts[key(item.title), default: 0] > 1 else { return item }
            return GraphicBrowserItem(
                name: item.name, title: "\(item.title) — \(item.name)",
                description: item.description, category: item.category, origin: item.origin,
                ok: item.ok)
        }
    }
}

/// The bundled templates, compiled once against a library of the bundled
/// fonts (G-45 (e)): what the browser reads their `meta` from and what its
/// preview draws them with.
final class GraphicTemplateLibrary {
    struct Entry {
        let template: GraphicTemplate
        let entry: GraphicRegistry.Entry
    }

    static let shared = GraphicTemplateLibrary(
        directory: GraphicTemplates.bundledDirectory, fonts: ProjectDocument.bundledFontsDirectory)

    private let directory: URL
    private let fonts: URL
    private let lock = NSLock()
    private var compiled: [Entry]?

    init(directory: URL, fonts: URL) {
        self.directory = directory
        self.fonts = fonts
    }

    /// Every template in `GraphicTemplates.list(in:)`'s order, compiled on
    /// the first read and kept. The first read is on main.
    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if let compiled = compiled { return compiled }
        let made = compile()
        compiled = made
        return made
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.template.name == name }
    }

    /// The bundled faces into a new library, then every template compiled
    /// against it. A face the engine refuses fails every template with its
    /// sentence, as `GraphicRegistry.install` does for a document.
    private func compile() -> [Entry] {
        let templates = GraphicTemplates.list(in: directory)
        let library = GraphicLibrary()
        var refused: [GraphicDiagnostic]?
        let faces = ((try? FileManager.default.contentsOfDirectory(
            at: fonts, includingPropertiesForKeys: nil)) ?? [])
            .filter { GraphicStore.fontExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        do {
            for face in faces { try library.addFont(Data(contentsOf: face)) }
        } catch {
            refused = GraphicDiagnostic.of(error)
        }
        return templates.map { template in
            let bytes = (try? Data(contentsOf: template.url)) ?? Data()
            if let refused = refused {
                return Entry(template: template, entry: .failed(refused, revision: ""))
            }
            let file = GraphicModuleFile(
                name: template.name, url: template.url, bytes: bytes, revision: "")
            return Entry(template: template, entry: GraphicRegistry.compile(file, library: library))
        }
    }
}
