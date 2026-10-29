// app/Sources/ProjectDocument+GraphicInsert.swift — the two halves of
// Insert ▸ Graphic… that both doors share (spec §11 G-16, G-45 (f)): the
// sheet's Insert and From File… (`EditorViewController+GraphicMenus.swift`)
// and `insert_graphic` (`AgentServer+GraphicBrowser.swift`).
//
// `writeGraphicModule` is G-16 (b): a module's text copied into the
// package's `graphics/` under a free name, then the folder rescanned so the
// registry has compiled THAT text. `rescan()` runs here, from a command,
// never from a `.graphicsDidChange` observer (`drain()` is not re-entrant).
// The file write is not undoable (G-3).
//
// `graphicClipMaker` is the clip: `add_graphic_clip` at the module's `meta`
// duration and size, with the schema of its current revision (G-4). Where
// the clip goes is each caller's: `EditorViewController.generatedClipOps`,
// Add Text's rule (G-16 (a)). A module that does not compile places nothing
// and throws its first diagnostic (G-45 (f)).

import Foundation

extension ProjectDocument {
    /// The sentence for a document whose graphics store has not started —
    /// one with no window.
    static let noGraphicsFolderSentence =
        "This project has no graphics folder open (its window has not been made)"

    /// Writes `url`'s module into `graphics/` under a free name made from
    /// its stem (G-16 (b)) and rescans; the name it was written under.
    /// Throws, writing nothing, when the file cannot be read or is not
    /// UTF-8.
    func writeGraphicModule(from url: URL) throws -> String {
        guard let store = graphicStore else {
            throw ReelCoreError(message: Self.noGraphicsFolderSentence)
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: url)
        } catch {
            throw ReelCoreError(
                message: "\(url.path) could not be read: \(error.localizedDescription)")
        }
        guard let source = String(data: bytes, encoding: .utf8) else {
            throw ReelCoreError(
                message: "\(url.path) is not UTF-8 text — a graphic module must be UTF-8 "
                    + "JavaScript")
        }
        let name = store.uniqueModuleName(
            GraphicTemplates.moduleName(from: url.deletingPathExtension().lastPathComponent))
        try store.write(name: name, source: source)
        store.rescan()
        return name
    }

    /// The op that places one clip drawn by `graphics/<name>.js` at a track
    /// and a time: its `meta` duration and size, its schema. Throws the
    /// module's first diagnostic when it does not compile, the store's
    /// sentence when the folder does not hold it, and the `meta` sentence
    /// when a duration or side is not a whole number in range.
    func graphicClipMaker(named name: String) throws -> (UInt32, Ticks) -> ReelOp {
        guard let store = graphicStore else {
            throw ReelCoreError(message: Self.noGraphicsFolderSentence)
        }
        guard let entry = GraphicRegistry.shared.entry(named: name, for: recipeKey) else {
            throw ReelCoreError(message: store.noModuleSentence(name))
        }
        guard case .compiled(_, _, let meta, let schema) = entry else {
            var first: GraphicDiagnostic?
            if case .failed(let diagnostics, _) = entry { first = diagnostics.first }
            let line = first?.line.map { " (line \($0))" } ?? ""
            throw ReelCoreError(
                message: "graphics/\(name).js does not compile: "
                    + (first?.message ?? "no diagnostic") + line)
        }
        let frame = max(project.snapshot.canvas.fps.frameDuration, 1)
        let duration: Ticks?
        let width: UInt32?
        let height: UInt32?
        do {
            duration = try AgentServer.metaWhole(
                meta, "durationInFrames", name, in: 1...Int.max / Int(frame)
            ).map { Ticks($0) * frame }
            width = try AgentServer.metaWhole(meta, "width", name, in: AgentServer.sides)
                .map(UInt32.init)
            height = try AgentServer.metaWhole(meta, "height", name, in: AgentServer.sides)
                .map(UInt32.init)
        } catch let error as AgentServer.ToolError {
            throw ReelCoreError(message: error.message)
        }
        return { track, at in
            .addGraphicClipRaw(
                track: track, at: at, duration: duration, name: name, width: width,
                height: height, props: nil, schema: schema)
        }
    }
}
