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
//
// **`export_graphic` is the sheet's Export…** (spec §11 G-46): the graphic
// resolved as `insert_graphic` resolves it (`browserGraphic`, its refusals),
// its `GraphicPackageJob` built inside `onMain`, and the package written on
// the SERVER thread (`AgentServer.offMainTools`), `render_graphic`'s posture,
// since drawing every frame is seconds of QuickJS. It is no edit.

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

    /// What `name` and `from` name in Insert ▸ Graphic…'s lists.
    enum BrowserGraphic {
        case template(GraphicTemplateLibrary.Entry)
        case project(String)
    }

    /// `name` resolved in the origin `from` names, refused in `insert_graphic`'s sentences:
    /// a `from` that is neither origin, a document with no window, a name that origin does
    /// not hold. Main.
    func browserGraphic(
        name: String, from: String, document: ProjectDocument
    ) throws -> BrowserGraphic {
        guard let origin = GraphicBrowserItem.Origin(rawValue: from) else {
            throw ToolError(message: "from must be template or project (got \"\(from)\").")
        }
        guard editor(document) != nil, let store = document.graphicStore else {
            throw ToolError(message: ProjectDocument.noGraphicsFolderSentence)
        }
        switch origin {
        case .template:
            let templates = GraphicTemplateLibrary.shared.entries
            guard let template = templates.first(where: { $0.template.name == name }) else {
                throw ToolError(
                    message: "No template named \"\(name)\" — the templates are: "
                        + templates.map(\.template.name).joined(separator: ", "))
            }
            return .template(template)
        case .project:
            guard store.module(named: name) != nil else {
                let held = store.scan.modules.keys.sorted()
                throw ToolError(
                    message: "No module named \"\(name)\" in this project's graphics/ — it "
                        + "holds: " + (held.isEmpty ? "nothing" : held.joined(separator: ", ")))
            }
            return .project(name)
        }
    }

    /// `insert_graphic` — UI path: Insert ▸ Graphic…'s Insert.
    func insertGraphic(_ a: [String: Any]) throws -> String {
        let name = try requiredString(a, "name")
        let from = try requiredString(a, "from")
        let document = try target(a)
        let graphic = try browserGraphic(name: name, from: from, document: document)
        let placed: String
        do {
            switch graphic {
            case .template(let template):
                placed = try document.writeGraphicModule(from: template.template.url)
            case .project(let module):
                placed = module
            }
            let make = try document.graphicClipMaker(named: placed)
            let ops = EditorViewController.generatedClipOps(in: document, make)
            return try editResult(document, "Insert Graphic", ops, ["name": placed])
        } catch let error as ReelCoreError {
            throw ToolError(message: error.message)
        }
    }

    /// `export_graphic` — UI path: Insert ▸ Graphic…'s Export…. Runs off main.
    func exportGraphic(_ a: [String: Any]) throws -> String {
        let name = try requiredString(a, "name")
        let from = try requiredString(a, "from")
        let path = try requiredString(a, "path")
        let url = try Self.requireFolder(
            of: Self.destinationURL(
                try Self.nonEmptyOutputPath(path), extension: GraphicPackage.fileExtension))
        let job = try onMain { () throws -> GraphicPackageJob in
            let document = try self.target(a)
            let graphic = try self.browserGraphic(name: name, from: from, document: document)
            do {
                switch graphic {
                case .template(let template):
                    return try GraphicPackageJob.template(template, document: document)
                case .project(let module):
                    return try GraphicPackageJob.project(named: module, document: document)
                }
            } catch let error as ReelCoreError {
                throw ToolError(message: error.message)
            }
        }
        let result: GraphicPackageResult
        do {
            result = try job.write(to: url)
        } catch let error as ReelCoreError {
            throw ToolError(message: error.message)
        }
        return try jsonResult([
            "path": result.url.path, "files": ["manifest.json"] + result.files,
            "frames": result.frames, "failed_frames": result.failedFrames,
        ])
    }
}
