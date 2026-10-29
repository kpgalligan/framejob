import AppKit
import UniformTypeIdentifiers

/// The graphics menu commands (road map 10's G5b; spec §11 G-45): Insert ▸
/// Graphic…, the sheet (`GraphicBrowserSheetController.swift`) and its From
/// File…, and File ▸ Add Font to Graphics… and Add Image to Graphics…. Each
/// is the same code its MCP tool runs.
///
/// **Insert is `write_graphic` then `add_graphic_clip`** (spec §7.9) for a
/// template or a chosen `.js`: the module is written into the package's
/// `graphics/` under a free name and the folder rescanned
/// (`ProjectDocument.writeGraphicModule`, G-16 (b)), and one clip is placed
/// by `addGeneratedClip`'s rule — the front track if it fits, else a new
/// track above everything, Add Text's rule (G-16 (a)) — at the module's
/// `meta` duration and size (`ProjectDocument.graphicClipMaker`). A This
/// Project graphic is the clip alone, no copy (G-45 (f)). A module that does
/// not compile places nothing (G-16 (c)); the file write is not undoable
/// (G-3) and the clip is one undo step, "Insert Graphic". `insert_graphic`
/// calls the same two document bodies.
///
/// The sheet's Insert runs INSIDE its button's event, so `applyEdit`; the
/// panels' completions are OFF-EVENT, so `performGroupedEdit` (app/CLAUDE.md's
/// undo pitfall). `rescan()` is called from the command, never from a
/// `.graphicsDidChange` observer.
extension EditorViewController {

    /// Insert ▸ Graphic…: the browser, as a sheet on the editor's window.
    @objc func showGraphicBrowser(_ sender: Any?) {
        guard let document = document, document.graphicStore != nil else {
            NSSound.beep()
            return
        }
        let sheet = GraphicBrowserSheetController(document: document, editor: self)
        presentAsSheet(sheet)
    }

    /// The sheet's From File…: a `.js` chosen in a panel. Called from the
    /// browser's `viewDidDisappear`, once the browser is down, so the panel
    /// is the sheet that follows it.
    func insertGraphicFromFile(_ sender: Any?) {
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
        ) { [weak self] _, url in try self?.addGraphicImage(from: url) }
    }

    /// Add Image's body, no panel: the picture filed under its own name, or
    /// under a legal one with a sheet saying so (spec §11 G-23 (d)).
    func addGraphicImage(from url: URL) throws {
        guard let document = document, let store = document.graphicStore else {
            throw ReelCoreError(
                message: "This project has no graphics folder open (its window has not been made)")
        }
        let landed = try store.importAsset(from: url, as: url.lastPathComponent)
        if let asked = landed.renamedFrom, view.window != nil {
            showGraphicNotice(GraphicAssetName.renameNotice(from: asked, to: landed.name))
        }
    }

    /// The body, no dialog: write `url`'s module under a free name, rescan,
    /// and place a clip drawn by it — or throw the sentence saying why not.
    func insertGraphic(from url: URL, grouped: Bool) throws {
        guard let document = document else {
            throw ReelCoreError(message: ProjectDocument.noGraphicsFolderSentence)
        }
        let written = try document.writeGraphicModule(from: url)
        let make = try document.graphicClipMaker(named: written)
        addGeneratedClip(named: "Insert Graphic", grouped: grouped, make)
    }

    /// A This Project graphic placed: a clip drawn by `graphics/<name>.js`
    /// as it is, no copy written (spec §11 G-45 (f)) — or the sentence
    /// saying why not.
    func insertProjectGraphic(named name: String, grouped: Bool) throws {
        guard let document = document else {
            throw ReelCoreError(message: ProjectDocument.noGraphicsFolderSentence)
        }
        let make = try document.graphicClipMaker(named: name)
        addGeneratedClip(named: "Insert Graphic", grouped: grouped, make)
    }

    /// The menu arms for the three, answered from `validateUserInterfaceItem`'s
    /// default case: each needs the document's graphics store, which
    /// `startGraphicStore()` makes with the window. Any other action is
    /// forwarded to `validateGraphicFileAction`, the arm for File ▸ Rename
    /// Graphic…, Delete Graphic… and Restore Graphic Version…
    /// (`EditorViewController+GraphicFiles.swift`), which answers nil for
    /// an action that is none of the three.
    func validateGraphicMenuAction(_ action: Selector) -> Bool? {
        switch action {
        case #selector(showGraphicBrowser(_:)), #selector(addGraphicFont(_:)),
            #selector(addGraphicImage(_:)):
            return document?.graphicStore != nil
        default:
            return validateGraphicFileAction(action)
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

    /// An informational sheet on the editor's window saying `text`.
    private func showGraphicNotice(_ text: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
