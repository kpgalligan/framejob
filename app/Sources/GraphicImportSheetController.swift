// app/Sources/GraphicImportSheetController.swift — Import Graphic, the sheet
// that asks before a `.fjgraphic` is copied into a project (spec §11 G-47
// (f)), and the two doors that put it up: the Finder's (`open(packageAt:)`,
// from `ProjectDocumentController`) and the Graphic dialog's From File…
// (`ask(packageAt:editor:)`).
//
// **No second implementation.** The sheet shows a plan
// (`GraphicImportPlan`, `GraphicPackageImport.swift`) and Import runs
// `ProjectDocument.importGraphicPackage`, the body `import_graphic` calls,
// which plans again against the folder as it is now. A throw beeps and shows
// its sentence word for word in `graphicimport.message`, and the sheet stays.
//
// **What follows the sheet starts in `viewDidDisappear`**, for
// `GraphicBrowserSheetController`'s reason: after Import, the Graphic dialog
// opens on This Project with the module chosen and the import's sentence in
// its message line. A sheet already attached to the window is queued by
// AppKit's `beginSheet`.
//
// **The Finder door chooses its project once launch and restoration are
// done** (G-47 (b)): `ProjectDocumentController.whenSettled`, then the front
// project, else File ▸ New Project's untitled one. A package refused before
// the sheet is an alert sheet on that project's window, or, with none,
// `NSApp.presentError`, and opens no project.
//
// **The dev accept** (`-RCDevGraphicImportAccept YES`, dev tools only): the
// sheet presses its own Import once it is up, so a proof can see a package
// opened at launch land.

import AppKit

final class GraphicImportSheetController: NSViewController {
    /// The dev-only launch default that presses Import (G-47's launch proof).
    static let devAcceptKey = "RCDevGraphicImportAccept"

    private let contents: GraphicPackageContents
    private let plan: GraphicImportPlan
    /// Weak, like every sheet's back-reference.
    private weak var editor: EditorViewController?
    private var imported: GraphicImportPlan?

    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let importButton: NSButton
    private static let width: CGFloat = 480

    init(contents: GraphicPackageContents, plan: GraphicImportPlan, editor: EditorViewController) {
        self.contents = contents
        self.plan = plan
        self.editor = editor
        importButton = StickerButton(title: "Import", style: .primary, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GraphicImportSheetController does not support NSCoder")
    }

    // MARK: - The doors

    /// The Finder's door: once launch and restoration are done, the package read, then the
    /// front project (else a new untitled one) asked. Main.
    static func open(packageAt url: URL) {
        ProjectDocumentController.whenSettled {
            let contents: GraphicPackageContents
            do {
                contents = try GraphicPackageContents.read(at: url)
            } catch {
                if let window = frontEditor()?.view.window {
                    NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                } else {
                    NSApp.presentError(error)
                }
                return
            }
            guard let editor = frontEditor() ?? untitledEditor() else { return }
            present(contents, editor: editor)
        }
    }

    /// From File…'s door: the package read and asked about in `editor`'s project. Main.
    static func ask(packageAt url: URL, editor: EditorViewController) {
        do {
            present(try GraphicPackageContents.read(at: url), editor: editor)
        } catch {
            alert(error, on: editor)
        }
    }

    /// The first editor window front to back with a project, else the first of an open
    /// project's (one restored but not yet ordered in).
    static func frontEditor() -> EditorViewController? {
        let editors = { (windows: [NSWindow]) in
            windows.lazy.compactMap { $0.contentViewController as? EditorViewController }
                .first { $0.document != nil }
        }
        let projects = NSDocumentController.shared.documents.compactMap { $0 as? ProjectDocument }
        return editors(NSApp.orderedWindows)
            ?? editors(projects.flatMap { $0.windowControllers.compactMap(\.window) })
    }

    /// File ▸ New Project's untitled project, made for the import; nil (the error shown) when
    /// it could not be made.
    private static func untitledEditor() -> EditorViewController? {
        do {
            let made = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            return made.windowControllers
                .compactMap { $0.contentViewController as? EditorViewController }.first
        } catch {
            NSApp.presentError(error)
            return nil
        }
    }

    private static func present(_ contents: GraphicPackageContents, editor: EditorViewController) {
        guard let document = editor.document else {
            NSSound.beep()
            return
        }
        do {
            let plan = try GraphicImportPlan.make(contents, document: document)
            editor.presentAsSheet(
                GraphicImportSheetController(contents: contents, plan: plan, editor: editor))
        } catch {
            alert(error, on: editor)
        }
    }

    private static func alert(_ error: Error, on editor: EditorViewController) {
        guard let window = editor.view.window else {
            NSSound.beep()
            return
        }
        NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
    }

    // MARK: - Layout

    override func loadView() {
        let contentWidth = Self.width - sheetInset * 2
        let title = label(contents.title, id: "graphicimport.title", bold: true)
        let description = label(contents.description ?? "", id: "graphicimport.description")
        description.isHidden = contents.description == nil
        let module = label(Self.moduleLine(plan.module), id: "graphicimport.module")
        let fonts = label(
            Self.filesLine("Fonts", plan.fonts), id: "graphicimport.fonts")
        let assets = label(
            Self.filesLine("Pictures", plan.assets), id: "graphicimport.assets")
        let note = label(
            "Importing copies these files into this project's graphics. It is not an Undo step.",
            id: "graphicimport.footnote")
        note.textColor = DS.textMuted
        for field in [title, description, module, fonts, assets, note, messageLabel] {
            field.preferredMaxLayoutWidth = contentWidth
        }
        messageLabel.font = DS.sans(12)
        messageLabel.textColor = DS.textStrong
        messageLabel.setAccessibilityIdentifier("graphicimport.message")

        importButton.target = self
        importButton.action = #selector(importClicked(_:))
        importButton.setAccessibilityIdentifier("graphicimport.import")
        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        cancelButton.setAccessibilityIdentifier("graphicimport.cancel")
        view = makeSheetView(
            title: "Import Graphic",
            content: sheetColumn([title, description, module, fonts, assets, note, messageLabel]),
            buttonRow: makeButtonRow(cancel: cancelButton, apply: importButton),
            width: Self.width)
    }

    private func label(_ text: String, id: String, bold: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = bold ? DS.sans(13, weight: .bold) : DS.sans(12)
        field.textColor = DS.textStrong
        field.setAccessibilityIdentifier(id)
        return field
    }

    /// `Module: <m>`, `… (already in this project)`, or `Module: <target> (<m> is taken)`.
    static func moduleLine(_ place: GraphicImportPlacement) -> String {
        if place.action == .reused { return "Module: \(place.name) (already in this project)" }
        if place.target != place.name { return "Module: \(place.target) (\(place.name) is taken)" }
        return "Module: \(place.name)"
    }

    /// `<heading>: a, b (already here), c (as c-2)`, or `<heading>: none`.
    static func filesLine(_ heading: String, _ places: [GraphicImportPlacement]) -> String {
        let names = places.map { place -> String in
            if place.action == .reused { return "\(place.name) (already here)" }
            if place.target != place.name { return "\(place.name) (as \(place.target))" }
            return place.name
        }
        return "\(heading): " + (names.isEmpty ? "none" : names.joined(separator: ", "))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        #if FRAMEJOB_DEV_TOOLS
        if UserDefaults.standard.bool(forKey: Self.devAcceptKey) {
            DispatchQueue.main.async { [weak self] in self?.importClicked(nil) }
        }
        #endif
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// The import, once, against the folder as it is now. A throw beeps and shows its
    /// sentence, and the sheet stays; a success closes it.
    @objc private func importClicked(_ sender: Any?) {
        guard imported == nil, let document = editor?.document else {
            NSSound.beep()
            return
        }
        do {
            imported = try document.importGraphicPackage(contents)
        } catch {
            NSSound.beep()
            messageLabel.stringValue = (error as? ReelCoreError)?.message
                ?? error.localizedDescription
            return
        }
        dismiss(self)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        guard let done = imported else { return }
        editor?.showGraphicBrowser(selecting: done.module.target, message: done.sentence)
    }
}
