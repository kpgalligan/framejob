// app/Sources/AgentServer+Graphics.swift — the two graphic OP tools (road map
// 10 §5h, G3b): `add_graphic_clip` and `set_graphic`. The six app-state
// graphics tools are G4's.
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

    /// `add_graphic_clip` — no UI path yet: G5's Graphic sub-tab (road map
    /// 10 §5j) is the menu this mirrors.
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
        let (meta, schema) = try compiledModule(named: name, document)
        let frame = max(document.project.snapshot.canvas.fps.frameDuration, 1)
        // `meta` is only the fallback: a caller's own `duration` is never
        // refused for a `durationInFrames` it does not use.
        let metaDuration: Ticks? = try duration != nil ? nil
            : metaWhole(meta, "durationInFrames", name, in: 1...Int.max / Int(frame))
                .map { Ticks($0) * frame }
        return try editResult(
            document, "Add Graphic",
            [.addGraphicClipRaw(
                track: track.id, at: at, duration: duration ?? metaDuration, name: name,
                width: try width ?? metaWhole(meta, "width", name, in: sides).map(UInt32.init),
                height: try height ?? metaWhole(meta, "height", name, in: sides).map(UInt32.init),
                props: props, schema: schema)])
    }

    /// `set_graphic` — no UI path yet: G5's Graphic sub-tab (road map 10
    /// §5j) is the inspector this mirrors.
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

    // MARK: - What only the app can know

    private var sides: ClosedRange<Int> { 1...GraphicLibrary.maxSide }

    /// A module's `meta` and `schema` from its current revision, or the
    /// sentence saying the folder does not hold it or it did not compile.
    private func compiledModule(
        named name: String, _ document: ProjectDocument
    ) throws -> (meta: [String: Any], schema: [String: Any]) {
        guard document.graphicStore?.module(named: name) != nil,
            let entry = GraphicRegistry.shared.entry(named: name, for: document.recipeKey)
        else {
            let held = (document.graphicStore?.scan.modules.keys).map { Array($0).sorted() } ?? []
            let listed = held.isEmpty ? "nothing" : held.joined(separator: ", ")
            throw ToolError(
                message: "No module named \"\(name)\" in graphics/ — the folder holds: \(listed)")
        }
        switch entry {
        case .compiled(_, _, let meta, let schema):
            return (meta, schema)
        case .failed(let diagnostics, _):
            let first = diagnostics.first
            let line = first?.line.map { " (line \($0))" } ?? ""
            throw ToolError(
                message: "The module \"\(name)\" does not compile: "
                    + (first?.message ?? "no diagnostic") + line)
        }
    }

    /// `width` or `height` as a side, refused by name outside 1…8192.
    private func graphicSide(_ a: [String: Any], _ key: String) throws -> UInt32? {
        guard let value = try intArg(a, key) else { return nil }
        guard sides.contains(value) else {
            throw ToolError(message: "\(key) is not a side of 1–\(GraphicLibrary.maxSide): \(value)")
        }
        return UInt32(value)
    }

    /// `meta[key]` as a whole number in `range`, nil when the module does
    /// not declare it, refused by name when it declares something else.
    private func metaWhole(
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
