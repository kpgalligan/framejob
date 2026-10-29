// app/Sources/AgentServer+GraphicBrowser.swift — `list_graphics` and
// `insert_graphic` (spec §11 G-45): the Insert ▸ Graphic… sheet's two acts
// for an agent — what its two lists show, and its Insert.
//
// **The list is the sheet's** (`GraphicCatalog.categories(for:)`): the same
// categories in the same order, the same titles — a This Project duplicate
// told apart by its module name — and the same `ok`.
//
// **Insert is the sheet's bodies** (`ProjectDocument+GraphicInsert.swift`):
// a template is written into `graphics/` under a free name, a This Project
// module is placed as it is, and the clip goes where Add Text's does
// (`EditorViewController.generatedClipOps`). The edit is `editResult`'s, so
// it is one closed undo step "Insert Graphic" and, with a nest open, lands
// inside it as the sheet's does. What this side refuses names the CALL
// (spec §11 D2-1): a `from` that is neither origin, a name that origin does
// not hold, and a document with no window.

import Foundation

extension AgentServer {

    /// `list_graphics` — UI path: Insert ▸ Graphic…'s two lists.
    func listGraphics(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let categories = GraphicCatalog.categories(for: document).map { category in
            [
                "name": category.name,
                "graphics": category.items.map { item in
                    [
                        "name": item.name, "title": item.title,
                        "description": item.description ?? NSNull(),
                        "category": item.category, "from": item.origin.rawValue, "ok": item.ok,
                    ] as [String: Any]
                },
            ] as [String: Any]
        }
        return try jsonResult(["categories": categories])
    }

    /// `insert_graphic` — UI path: Insert ▸ Graphic…'s Insert.
    func insertGraphic(_ a: [String: Any]) throws -> String {
        let name = try requiredString(a, "name")
        let from = try requiredString(a, "from")
        guard let origin = GraphicBrowserItem.Origin(rawValue: from) else {
            throw ToolError(message: "from must be template or project (got \"\(from)\").")
        }
        let document = try target(a)
        guard editor(document) != nil, let store = document.graphicStore else {
            throw ToolError(message: ProjectDocument.noGraphicsFolderSentence)
        }
        let placed: String
        do {
            switch origin {
            case .template:
                let templates = GraphicTemplateLibrary.shared.entries
                guard let template = templates.first(where: { $0.template.name == name }) else {
                    throw ToolError(
                        message: "No template named \"\(name)\" — the templates are: "
                            + templates.map(\.template.name).joined(separator: ", "))
                }
                placed = try document.writeGraphicModule(from: template.template.url)
            case .project:
                guard store.module(named: name) != nil else {
                    let held = store.scan.modules.keys.sorted()
                    throw ToolError(
                        message: "No module named \"\(name)\" in this project's graphics/ — it "
                            + "holds: " + (held.isEmpty ? "nothing" : held.joined(separator: ", ")))
                }
                placed = name
            }
            let make = try document.graphicClipMaker(named: placed)
            let ops = EditorViewController.generatedClipOps(in: document, make)
            return try editResult(document, "Insert Graphic", ops, ["name": placed])
        } catch let error as ReelCoreError {
            throw ToolError(message: error.message)
        }
    }
}
