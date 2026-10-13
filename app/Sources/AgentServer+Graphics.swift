// app/Sources/AgentServer+Graphics.swift — the two graphic OP tools (road map
// 10 §5h, G3b): `add_graphic_clip` and `set_graphic`; and G4a's three
// app-state tools, the agent's write/read loop over the package's
// `graphics/`: `write_graphic`, `get_graphic` and `graphic_reference`, with
// `graphicsSummary`, which `get_project` reports as `graphics`. G4b's three
// are next door: `render_graphic` in `AgentServer+GraphicRender.swift`, the
// two imports in `AgentServer+GraphicImports.swift`; and issue batch B84's
// three — `delete_graphic`, `rename_graphic`, `restore_graphic` — in
// `AgentServer+GraphicFiles.swift`.
//
// **The app fills `schema`, and only the app can** (G-4): the core has no
// filesystem, so the schema a `props` patch is checked against is read here
// from the module's CURRENT revision — `GraphicRegistry`'s compiled entry for
// the document — and sent with the op. The tool does not publish `schema`
// (`AgentCatalog+Declarations.swift`'s `.filledByTheApp` rows), so the gate
// refuses a caller's own as a stranger before a handler runs.
//
// What this side refuses is what the core cannot know: a module the folder
// does not hold, a module that did not compile, and a `meta` value that
// cannot be a duration or a side. Every rule about the props themselves is
// the core's sentence.

import Foundation

extension AgentServer {

    /// `add_graphic_clip` — UI path: Insert ▸ Graphic, which is
    /// `write_graphic` of a template (or a chosen `.js`) then this op
    /// (`EditorViewController+GraphicMenus.swift`).
    ///
    /// `duration`, `width` and `height` default from the module's `meta`
    /// (`durationInFrames` at the canvas rate; `width` / `height`), and
    /// past that to the core's own defaults (5 s; the canvas).
    func addGraphicClip(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let at = try timeArg(a, "at", document)
        let duration = try optionalTimeArg(a, "duration", document)
        let name = try requiredString(a, "name")
        let width = try graphicSide(a, "width")
        let height = try graphicSide(a, "height")
        let props = a["props"]
        let (_, meta, schema) = try compiledModule(named: name, document)
        let frame = max(document.project.snapshot.canvas.fps.frameDuration, 1)
        // `meta` is only the fallback: a caller's own `duration` is never
        // refused for a `durationInFrames` it does not use.
        let metaDuration: Ticks? = try duration != nil ? nil
            : Self.metaWhole(meta, "durationInFrames", name, in: 1...Int.max / Int(frame))
                .map { Ticks($0) * frame }
        return try editResult(
            document, "Add Graphic",
            [.addGraphicClipRaw(
                track: track.id, at: at, duration: duration ?? metaDuration, name: name,
                width: try width
                    ?? Self.metaWhole(meta, "width", name, in: Self.sides).map(UInt32.init),
                height: try height
                    ?? Self.metaWhole(meta, "height", name, in: Self.sides).map(UInt32.init),
                props: props, schema: schema)])
    }

    /// `set_graphic` — UI path: the Graphic sub-tab, Properties/Size/Timeline
    /// (GraphicPane.swift).
    ///
    /// A patch that carries `props` or `name` is checked against a schema:
    /// the patch's own `name`'s, else the one module every clip shares.
    func setGraphic(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try clipsArg(a, "clips", document)
        let patch = try rawPatchArg(a, "patch")
        var schema: [String: Any]?
        if let fields = patch as? [String: Any], fields["props"] != nil || fields["name"] != nil {
            let name: String
            if let named = fields["name"] as? String {
                name = named
            } else {
                let scope = try idScope(document)
                let names = Set(clips.compactMap { scope.clip($0)?.graphic?.name })
                guard names.count <= 1 else {
                    let listed = names.sorted().map { "\"\($0)\"" }.joined(separator: " and ")
                    throw ToolError(
                        message: "The clips are drawn by different modules (\(listed)); "
                            + "set props on one module's clips at a time.")
                }
                name = names.first ?? ""
            }
            if !name.isEmpty { schema = try compiledModule(named: name, document).schema }
        }
        return try editResult(
            document, "Graphic Properties",
            [.setGraphicRaw(clips: clips, patch: patch, schema: schema)])
    }

    // MARK: - The write/read loop (G4a)

    static let notUndoableNote = "not undoable; keep your own copy if you want the old one back"

    /// `write_graphic` — UI path: the file on disk (an external editor);
    /// Insert ▸ Graphic, which writes a template or a chosen `.js` through
    /// the same `store.write` then places it (`add_graphic_clip`); and
    /// Duplicate as New Graphic…, which writes the copy through the same
    /// `store.write` then repoints with `set_graphic {name}`.
    ///
    /// Writes `graphics/<name>.js` through the store's one writer, then
    /// rescans at once, so the registry has compiled THAT text before the
    /// reply is built: a failed compile is an answer (`ok` false with its
    /// diagnostics), not an error. Not undoable and never dirty (G-3); the
    /// text it replaced is kept by that rescan's pass, and `kept` lists the
    /// module's kept revisions, newest first (G-29).
    func writeGraphic(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let name = try requiredString(a, "name")
        let source = try requiredString(a, "source")
        let store = try graphicStore(document)
        do {
            try store.write(name: name, source: source)
        } catch let error as ReelCoreError {
            throw ToolError(message: error.message)
        } catch {
            throw ToolError(
                message: "graphics/\(name).js could not be written: \(error.localizedDescription)")
        }
        store.rescan()
        guard store.module(named: name) != nil else {
            throw ToolError(
                message: "graphics/\(name).js was written but the folder's scan does not list it "
                    + "— graphics/ may not be readable by Frame Job, or was replaced mid-write; "
                    + "get_graphic {} shows what the scan sees")
        }
        var result = moduleReport(named: name, document)
        result["name"] = name
        result["kept"] = store.kept(named: name).map(\.revision)
        result["note"] = Self.keptNote
        return try jsonResult(result)
    }

    /// `get_graphic` — UI path: the Graphic sub-tab, Source section
    /// (GraphicPane+Source.swift).
    ///
    /// With `name`, one module as the folder holds it now: its source, its
    /// revision, its compile and `kept`, its kept revisions newest first.
    /// Without, where the folder is, what it holds, `warnings`: what its
    /// scan skipped or could not watch (G-24 (b)), and `history`: every
    /// name with a kept revision, deleted modules included (G-29 (e)).
    func getGraphic(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let store = try graphicStore(document)
        guard let name = try stringArg(a, "name") else {
            return try jsonResult([
                "folder": store.folderURL.path,
                "folder_exists": FileManager.default.fileExists(atPath: store.folderURL.path),
                "modules": graphicsSummary(document),
                "families": libraryFamilies(document),
                "assets": store.scan.assets.map(\.name),
                "warnings": store.scan.warnings,
                "history": store.keptNames().map { kept -> [String: Any] in
                    ["name": kept, "kept": store.kept(named: kept).map(\.revision)]
                },
            ])
        }
        guard let file = store.module(named: name) else {
            throw ToolError(message: noModuleSentence(name, document))
        }
        var result = moduleReport(named: name, document)
        result["name"] = name
        result["source"] = String(decoding: file.bytes, as: UTF8.self)
        result["kept"] = store.kept(named: name).map(\.revision)
        return try jsonResult(result)
    }

    /// `graphic_reference` — UI path: Help ▸ Graphics Reference, which
    /// opens the same file (`AppDelegate+GraphicMenu.swift`).
    ///
    /// The bundled `GraphicsAPI.md`, verbatim. Needs no open document, so
    /// it calls `target(a)` only when given `project`, to refuse a path no
    /// open project is at (spec §11 G-20 (e)).
    func graphicReference(_ a: [String: Any]) throws -> String {
        if let project = a["project"], !(project is NSNull) { _ = try target(a) }
        guard let data = try? Data(contentsOf: GraphicStore.bundledReferenceURL) else {
            throw ToolError(
                message: "The bundled reference GraphicsAPI.md is missing from the app's Resources")
        }
        return try callResult(
            content: [["type": "text", "text": String(decoding: data, as: UTF8.self)]],
            isError: false)
    }

    /// `[{name, revision, ok, clips}]` by name over the store's scan; `[]`
    /// with no store. `get_project`'s `graphics`.
    func graphicsSummary(_ document: ProjectDocument) -> [[String: Any]] {
        guard let store = document.graphicStore else { return [] }
        return store.scan.modules.values.sorted { $0.name < $1.name }.map { file in
            let ok: Bool
            if case .compiled = GraphicRegistry.shared.entry(
                named: file.name, for: document.recipeKey)
            {
                ok = true
            } else {
                ok = false
            }
            return [
                "name": file.name, "revision": file.revision, "ok": ok,
                "clips": clipsUsing(file.name, document),
            ]
        }
    }

    /// The families of the library the document's graphics draw with — the
    /// engine's own names, the exact strings a `font-family` must match; `[]`
    /// with no set. May freeze the set's library, which nothing adds to after
    /// `install`. Main.
    func libraryFamilies(_ document: ProjectDocument) -> [String] {
        GraphicRegistry.shared.snapshot(for: document.recipeKey)?.library.families() ?? []
    }

    func graphicStore(_ document: ProjectDocument) throws -> GraphicStore {
        guard let store = document.graphicStore else {
            throw ToolError(
                message: "This project has no graphics folder open (its window has not been made)")
        }
        return store
    }

    /// `{path, revision, ok, meta, schema, diagnostics, clips}` for a module
    /// the scan holds; a compiled module's diagnostics are what its top level
    /// warned (G-24 (a)).
    func moduleReport(named name: String, _ document: ProjectDocument) -> [String: Any] {
        let file = document.graphicStore?.module(named: name)
        var result: [String: Any] = [
            "path": file?.url.path ?? NSNull(),
            "revision": file?.revision ?? NSNull(),
            "clips": clipsUsing(name, document),
        ]
        switch GraphicRegistry.shared.entry(named: name, for: document.recipeKey) {
        case .compiled(let module, _, let meta, let schema):
            result["ok"] = true
            result["meta"] = meta
            result["schema"] = schema
            result["diagnostics"] = module.compileWarnings.map(Self.diagnosticJSON)
        case .failed(let diagnostics, _):
            result["ok"] = false
            result["meta"] = [String: Any]()
            result["schema"] = [String: Any]()
            result["diagnostics"] = diagnostics.map(Self.diagnosticJSON)
        case nil:
            result["ok"] = false
            result["meta"] = [String: Any]()
            result["schema"] = [String: Any]()
            result["diagnostics"] = [Self.diagnosticJSON(GraphicDiagnostic(
                level: "error",
                message: "The module \"\(name)\" is in graphics/ but the app has not compiled "
                    + "it yet — call again",
                line: nil, column: nil, frame: nil))]
        }
        return result
    }

    /// Ascending ids of every clip, the timeline's and every nest's, drawn
    /// by the module `name`.
    private func clipsUsing(_ name: String, _ document: ProjectDocument) -> [Int] {
        let snapshot = document.project.snapshot
        let clips = snapshot.clips + snapshot.nests.flatMap { $0.clips }
        return clips.filter { $0.graphic?.name == name }.map { Int($0.id) }.sorted()
    }

    static func diagnosticJSON(_ d: GraphicDiagnostic) -> [String: Any] {
        [
            "level": d.level, "message": d.message,
            "line": d.line ?? NSNull(), "column": d.column ?? NSNull(),
            "frame": d.frame ?? NSNull(),
        ] as [String: Any]
    }

    // MARK: - What only the app can know

    static var sides: ClosedRange<Int> { 1...GraphicLibrary.maxSide }

    /// A module, its `meta` and its `schema` from its current revision, or
    /// the sentence saying the folder does not hold it or it did not compile.
    func compiledModule(
        named name: String, _ document: ProjectDocument
    ) throws -> (module: GraphicModule, meta: [String: Any], schema: [String: Any]) {
        guard document.graphicStore?.module(named: name) != nil,
            let entry = GraphicRegistry.shared.entry(named: name, for: document.recipeKey)
        else { throw ToolError(message: noModuleSentence(name, document)) }
        switch entry {
        case .compiled(let module, _, let meta, let schema):
            return (module, meta, schema)
        case .failed(let diagnostics, _):
            let first = diagnostics.first
            let line = first?.line.map { " (line \($0))" } ?? ""
            throw ToolError(
                message: "The module \"\(name)\" does not compile: "
                    + (first?.message ?? "no diagnostic") + line)
        }
    }

    /// The sentence for a module the folder does not hold, naming what it does.
    /// The store's own sentence (`GraphicStore+Files.swift`), which the
    /// delete and rename bodies answer too.
    func noModuleSentence(_ name: String, _ document: ProjectDocument) -> String {
        document.graphicStore?.noModuleSentence(name)
            ?? "No module named \"\(name)\" in graphics/ — the folder holds: nothing"
    }

    /// `width` or `height` as a side, refused by name outside 1…8192.
    func graphicSide(_ a: [String: Any], _ key: String) throws -> UInt32? {
        guard let value = try intArg(a, key) else { return nil }
        guard Self.sides.contains(value) else {
            throw ToolError(message: "\(key) is not a side of 1–\(GraphicLibrary.maxSide): \(value)")
        }
        return UInt32(value)
    }

    /// `meta[key]` as a whole number in `range`, nil when the module does
    /// not declare it, refused by name when it declares something else.
    static func metaWhole(
        _ meta: [String: Any], _ key: String, _ name: String, in range: ClosedRange<Int>
    ) throws -> Int? {
        guard let raw = meta[key], !(raw is NSNull) else { return nil }
        let number = (raw as? NSNumber).flatMap {
            CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : AgentServer.whole($0)
        }
        guard let value = number, range.contains(value) else {
            throw ToolError(
                message: "meta.\(key) of module \"\(name)\" is not a whole number of "
                    + "\(range.lowerBound)–\(range.upperBound): \(raw)")
        }
        return value
    }
}
