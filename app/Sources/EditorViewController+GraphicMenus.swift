import AppKit
import UniformTypeIdentifiers

/// The graphics menu commands (road map 10's G5b): Insert ▸ Graphic ▸ a
/// bundled template or From File…, and File ▸ Add Font to Graphics… and Add
/// Image to Graphics…. Each is the same code its MCP tool runs.
///
/// **Insert ▸ Graphic is `write_graphic` then `add_graphic_clip`** (spec
/// §7.9): the module is written into the package's `graphics/` under a free
/// name (`GraphicStore.uniqueModuleName`, spec §11 G-16 (b)), the folder is
/// rescanned so the registry has compiled THAT text, and one clip is placed
/// by `addGeneratedClip`'s rule — the front track if it fits, else a new track
/// above everything, Add Text's rule (G-16 (a)) — at the module's `meta`
/// duration and size. A module that does not compile stays on disk and
/// places nothing (G-16 (c)); the file write is not undoable (G-3) and the
/// clip is one undo step, "Insert Graphic".
///
/// The template item runs INSIDE its menu event, so `applyEdit`; the two
/// panels' completions are OFF-EVENT, so `performGroupedEdit` (app/CLAUDE.md's
/// undo pitfall). `rescan()` is called here, from the command, never from a
/// `.graphicsDidChange` observer.
extension EditorViewController {

    /// Insert ▸ Graphic ▸ <template>: the item's `representedObject` is the
    /// template's URL (`AppDelegate+GraphicMenu.swift`).
    @objc func insertGraphicTemplate(_ sender: Any?) {
        guard let url = (sender as? NSMenuItem)?.representedObject as? URL else {
            NSSound.beep()
            return
        }
        reportingGraphicFailure { try insertGraphic(from: url, grouped: false) }
    }

    /// Insert ▸ Graphic ▸ From File…: a `.js` chosen in a panel.
    @objc func insertGraphicFromFile(_ sender: Any?) {
        guard document?.graphicStore != nil, let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.javaScript]
        panel.message = "Choose a graphic module (.js) to copy into this project's graphics."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.reportingGraphicFailure { try self?.insertGraphic(from: url, grouped: true) }
        }
    }

    /// File ▸ Add Font to Graphics… — `import_graphic_font`'s body.
    @objc func addGraphicFont(_ sender: Any?) {
        chooseGraphicFile(
            types: GraphicStore.fontExtensions,
            message: "Choose a font (.ttf or .otf) to add to this project's graphics."
        ) { store, url in
            _ = try store.importFont(from: url)
        }
    }

    /// File ▸ Add Image to Graphics… — `import_graphic_asset`'s body, filed
    /// under the picture's own name.
    @objc func addGraphicImage(_ sender: Any?) {
        chooseGraphicFile(
            types: GraphicStore.assetExtensions,
            message: "Choose a picture (\(GraphicStore.assetKinds)) to add to this project's "
                + "graphics."
        ) { store, url in
            _ = try store.importAsset(from: url, as: url.lastPathComponent)
        }
    }

    /// The body, no dialog: write `url`'s module under a free name, rescan,
    /// and place a clip drawn by it — or throw the sentence saying why not.
    func insertGraphic(from url: URL, grouped: Bool) throws {
        guard let document = document, let store = document.graphicStore else {
            throw ReelCoreError(
                message: "This project has no graphics folder open (its window has not been made)")
        }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: url)
        } catch {
            throw ReelCoreError(
                message: "\(url.path) could not be read: \(error.localizedDescription)")
        }
        let name = store.uniqueModuleName(
            GraphicTemplates.moduleName(from: url.deletingPathExtension().lastPathComponent))
        try store.write(name: name, source: String(decoding: bytes, as: UTF8.self))
        store.rescan()
        let entry = GraphicRegistry.shared.entry(named: name, for: document.recipeKey)
        guard case .compiled(_, _, let meta, let schema)? = entry else {
            var first: GraphicDiagnostic?
            if case .failed(let diagnostics, _)? = entry { first = diagnostics.first }
            let line = first?.line.map { " (line \($0))" } ?? ""
            throw ReelCoreError(
                message: "graphics/\(name).js was written but does not compile: "
                    + (first?.message ?? "no diagnostic") + line)
        }
        let frame = max(document.project.snapshot.canvas.fps.frameDuration, 1)
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
        addGeneratedClip(named: "Insert Graphic", grouped: grouped) { track, at in
            .addGraphicClipRaw(
                track: track, at: at, duration: duration, name: name, width: width,
                height: height, props: nil, schema: schema)
        }
    }

    /// The menu arms for the four, answered from `validateUserInterfaceItem`'s
    /// default case: each needs the document's graphics store, which
    /// `startGraphicStore()` makes with the window.
    func validateGraphicMenuAction(_ action: Selector) -> Bool? {
        switch action {
        case #selector(insertGraphicTemplate(_:)), #selector(insertGraphicFromFile(_:)),
            #selector(addGraphicFont(_:)), #selector(addGraphicImage(_:)):
            return document?.graphicStore != nil
        default:
            return nil
        }
    }

    // MARK: - Helpers

    /// A file panel over `types` (file extensions); its completion runs
    /// `body` with the store and the chosen URL, a failure in a sheet.
    private func chooseGraphicFile(
        types: Set<String>, message: String,
        _ body: @escaping (GraphicStore, URL) throws -> Void
    ) {
        guard let store = document?.graphicStore, let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = types.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.message = message
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.reportingGraphicFailure { try body(store, url) }
        }
    }

    /// Runs `body`; a throw is shown in a sheet on the editor's window
    /// (`addImageBackground`'s shape), or a beep with no window. Success
    /// shows nothing.
    private func reportingGraphicFailure(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            guard let window = view.window else {
                NSSound.beep()
                return
            }
            NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
        }
    }
}
