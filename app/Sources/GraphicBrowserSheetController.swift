// app/Sources/GraphicBrowserSheetController.swift — Insert ▸ Graphic… (spec
// §11 G-45): a sheet of three panes — the categories, the graphics of the
// chosen one, and a looping preview of the chosen graphic with its title and
// one-line description — over a message line and a bottom bar of Export… and
// From File… at the left and Cancel and Insert at the right.
//
// **What it lists is `GraphicCatalog.categories(for:)`**, read once when the
// sheet is made, in the order `list_graphics` answers. It opens on the first
// category's first graphic; Insert is disabled with no graphic chosen, and a
// double-click on a graphic is Insert.
//
// **No second implementation.** Insert is one call of the editor's body —
// `insertGraphic(from:grouped:)` with the template's URL, or
// `insertProjectGraphic(named:grouped:)` for This Project — the bodies the
// old menu items called, which call `ProjectDocument+GraphicInsert.swift`
// as `insert_graphic` does. It runs inside the button's event, so `grouped:
// false` (`applyEdit`). A success dismisses the sheet; a throw beeps and
// shows the sentence word for word in `messageLabel`, and the sheet stays.
//
// **What follows the sheet starts in `viewDidDisappear`**, for
// `ReverseProgressSheetController`'s reason: a sheet dismissed a moment ago
// is still the window's `attachedSheet`. From File… only sets a flag and
// dismisses; the open panel is begun there, once the browser is down. And
// the preview's render thread is stopped there, so every way out — Cancel,
// Esc, Insert, From File… — stops it.
//
// **Opened after an import** (spec §11 G-47 (f)) with `select`: This Project
// and the graphic of that name are chosen, and `message` is put in the
// message line after the choice has cleared it.
//
// **Export…** (spec §11 G-46 (a)) is enabled when the chosen graphic
// compiles and no export is running. It opens a save panel as a sheet on the
// browser, which stays up; `exportChosen(to:)` builds a `GraphicPackageJob` on
// main and writes it on a `Thread` of `GraphicPrefetch.workerStackBytes`
// (QuickJS needs the stack), and the result or the refusal goes in the
// message line. No edit and no undo step.

import AppKit

final class GraphicBrowserSheetController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    /// Weak, like every sheet's back-reference.
    private weak var document: ProjectDocument?
    private weak var editor: EditorViewController?
    private let categories: [GraphicBrowserCategory]
    private let canvas: CanvasSnapshot
    private var fromFilePending = false
    /// The graphic to choose and the message to show at load (G-47 (f)).
    private let select: String?
    private let message: String?
    /// An export's thread is running; Export… stays disabled until it reports.
    private(set) var exporting = false
    /// The last export's thread, for the probe to see it finish.
    private(set) var exportThread: Thread?

    private let categoryTable = NSTableView()
    private let graphicTable = NSTableView()
    private let previewView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let insertButton: NSButton
    private let fromFileButton: NSButton
    private let exportButton: NSButton

    /// The preview's loop; its thread starts with the first graphic shown.
    private(set) lazy var player = GraphicPreviewPlayer(canvas: canvas) { [weak self] image in
        self?.showFrame(image)
    }

    private static let width: CGFloat = 920
    private static let paneHeight: CGFloat = 410
    private static let categoriesWidth: CGFloat = 180
    private static let graphicsWidth: CGFloat = 240
    private static let gap: CGFloat = 12
    private static let cellID = NSUserInterfaceItemIdentifier("graphicbrowser.cell")

    init(
        document: ProjectDocument, editor: EditorViewController, select: String? = nil,
        message: String? = nil
    ) {
        self.document = document
        self.editor = editor
        self.select = select
        self.message = message
        self.categories = GraphicCatalog.categories(for: document)
        self.canvas = document.project.snapshot.canvas
        self.insertButton = StickerButton(title: "Insert", style: .primary, target: nil, action: nil)
        self.fromFileButton = StickerButton(
            title: "From File…", style: .secondary, target: nil, action: nil)
        self.exportButton = StickerButton(
            title: "Export…", style: .secondary, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GraphicBrowserSheetController does not support NSCoder")
    }

    // MARK: - Layout

    override func loadView() {
        let contentWidth = Self.width - sheetInset * 2
        let previewWidth = contentWidth - Self.categoriesWidth - Self.graphicsWidth - Self.gap * 2
        configure(categoryTable, id: "graphicbrowser.categories")
        categoryTable.allowsEmptySelection = false
        configure(graphicTable, id: "graphicbrowser.graphics")
        graphicTable.target = self
        graphicTable.doubleAction = #selector(graphicDoubleClicked(_:))

        // The well at the canvas's aspect ratio, as large as the column allows
        // with the title and description under it.
        let room = NSSize(width: previewWidth, height: Self.paneHeight - 56)
        let aspect = CGFloat(max(canvas.width, 1)) / CGFloat(max(canvas.height, 1))
        let well = aspect >= room.width / room.height
            ? NSSize(width: room.width, height: (room.width / aspect).rounded())
            : NSSize(width: (room.height * aspect).rounded(), height: room.height)
        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = DS.canvasVoid.cgColor
        previewView.setAccessibilityIdentifier("graphicbrowser.preview")
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.widthAnchor.constraint(equalToConstant: well.width).isActive = true
        previewView.heightAnchor.constraint(equalToConstant: well.height).isActive = true

        titleLabel.font = DS.sans(13, weight: .bold)
        titleLabel.textColor = DS.textStrong
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setAccessibilityIdentifier("graphicbrowser.title")
        descriptionLabel.font = DS.sans(12)
        descriptionLabel.textColor = DS.textMuted
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.maximumNumberOfLines = 1
        descriptionLabel.setAccessibilityIdentifier("graphicbrowser.description")
        // A plain view with every edge pinned, so nothing in the column is
        // left to a stack's low-priority guesses.
        let previewColumn = NSView()
        previewColumn.translatesAutoresizingMaskIntoConstraints = false
        for label in [titleLabel, descriptionLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for piece in [previewView, titleLabel, descriptionLabel] { previewColumn.addSubview(piece) }
        NSLayoutConstraint.activate([
            previewColumn.widthAnchor.constraint(equalToConstant: previewWidth),
            previewColumn.heightAnchor.constraint(equalToConstant: Self.paneHeight),
            previewView.topAnchor.constraint(equalTo: previewColumn.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: previewColumn.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
        ] + [titleLabel, descriptionLabel].flatMap { label in
            [
                label.leadingAnchor.constraint(equalTo: previewColumn.leadingAnchor),
                label.widthAnchor.constraint(equalToConstant: previewWidth),
            ]
        })

        let panes = NSStackView(views: [
            scroll(categoryTable, width: Self.categoriesWidth),
            scroll(graphicTable, width: Self.graphicsWidth), previewColumn,
        ])
        panes.orientation = .horizontal
        panes.alignment = .top
        panes.spacing = Self.gap
        panes.heightAnchor.constraint(equalToConstant: Self.paneHeight).isActive = true

        messageLabel.font = DS.sans(12)
        messageLabel.textColor = DS.textStrong
        messageLabel.preferredMaxLayoutWidth = contentWidth
        messageLabel.setAccessibilityIdentifier("graphicbrowser.message")

        insertButton.target = self
        insertButton.action = #selector(insertClicked(_:))
        insertButton.setAccessibilityIdentifier("graphicbrowser.insert")
        fromFileButton.target = self
        fromFileButton.action = #selector(fromFileClicked(_:))
        fromFileButton.setAccessibilityIdentifier("graphicbrowser.fromFile")
        exportButton.target = self
        exportButton.action = #selector(exportClicked(_:))
        exportButton.setAccessibilityIdentifier("graphicbrowser.export")
        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        cancelButton.setAccessibilityIdentifier("graphicbrowser.cancel")
        view = makeSheetView(
            title: "Insert Graphic", content: sheetColumn([panes, messageLabel]),
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: insertButton, leading: [exportButton, fromFileButton]),
            width: Self.width)

        categoryTable.reloadData()
        if !categories.isEmpty {
            categoryTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        categoryChanged()
        chooseSelected()
    }

    /// `select` chosen under This Project, then `message` shown (G-47 (f)).
    private func chooseSelected() {
        if let select = select,
            let section = categories.firstIndex(where: { $0.name == GraphicCatalog.thisProject }),
            let row = categories[section].items.firstIndex(where: { $0.name == select })
        {
            categoryTable.selectRowIndexes(IndexSet(integer: section), byExtendingSelection: false)
            categoryChanged()
            graphicTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            graphicChanged()
        }
        if let message = message { messageLabel.stringValue = message }
    }

    private func configure(_ table: NSTableView, id: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 24
        table.style = .plain
        table.focusRingType = .none
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityIdentifier(id)
    }

    private func scroll(_ table: NSTableView, width: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: Self.paneHeight).isActive = true
        table.sizeLastColumnToFit()
        return scroll
    }

    // MARK: - The two lists

    private var chosenCategory: GraphicBrowserCategory? {
        let row = categoryTable.selectedRow
        return categories.indices.contains(row) ? categories[row] : nil
    }

    private var chosenItem: GraphicBrowserItem? {
        let items = chosenCategory?.items ?? []
        let row = graphicTable.selectedRow
        return items.indices.contains(row) ? items[row] : nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === categoryTable ? categories.count : (chosenCategory?.items.count ?? 0)
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: Self.cellID, owner: self)
            as? NSTableCellView) ?? Self.makeCell()
        if tableView === categoryTable {
            cell.textField?.stringValue = categories.indices.contains(row)
                ? categories[row].name : ""
            cell.textField?.textColor = DS.textStrong
        } else {
            let items = chosenCategory?.items ?? []
            let item = items.indices.contains(row) ? items[row] : nil
            cell.textField?.stringValue = item?.title ?? ""
            cell.textField?.textColor = item?.ok == false ? DS.textFaint : DS.textStrong
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if notification.object as? NSTableView === categoryTable {
            categoryChanged()
        } else {
            graphicChanged()
        }
    }

    private static func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = cellID
        let field = NSTextField(labelWithString: "")
        field.font = DS.sans(13)
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// A new category: its graphics listed, the first chosen.
    private func categoryChanged() {
        graphicTable.reloadData()
        if graphicTable.numberOfRows > 0 {
            graphicTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        graphicChanged()
    }

    /// A new graphic (or none): its title and description, Insert, and the
    /// preview playing it.
    private func graphicChanged() {
        let item = chosenItem
        titleLabel.stringValue = item?.title ?? ""
        descriptionLabel.stringValue = item?.description ?? ""
        descriptionLabel.toolTip = item?.description
        messageLabel.stringValue = ""
        insertButton.isEnabled = item != nil
        exportButton.isEnabled = item?.ok == true && !exporting
        if item == nil { previewView.image = nil }
        player.play(item.map(subject(for:)))
    }

    /// What the preview draws `item` with: the template library's compile,
    /// or the document's registry for This Project.
    private func subject(for item: GraphicBrowserItem) -> GraphicPreviewPlayer.Subject {
        let entry: GraphicRegistry.Entry?
        switch item.origin {
        case .template:
            entry = GraphicTemplateLibrary.shared.entry(named: item.name)?.entry
        case .project:
            entry = document.flatMap {
                GraphicRegistry.shared.entry(named: item.name, for: $0.recipeKey)
            }
        }
        switch entry {
        case .compiled(let module, _, let meta, _)?:
            return .module(module, name: item.name, meta: meta)
        case .failed(let diagnostics, _)?:
            return .failed(name: item.name, diagnostics)
        case nil:
            return .failed(
                name: item.name, [.error("graphics/\(item.name).js is not compiled")])
        }
    }

    private func showFrame(_ image: CGImage) {
        previewView.image = NSImage(
            cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    @objc private func fromFileClicked(_ sender: Any?) {
        fromFilePending = true
        dismiss(self)
    }

    @objc private func graphicDoubleClicked(_ sender: Any?) {
        guard graphicTable.clickedRow >= 0, insertButton.isEnabled else { return }
        insertClicked(sender)
    }

    /// The chosen graphic placed, once. A throw beeps and shows its sentence,
    /// and the sheet stays up; a success closes it.
    @objc private func insertClicked(_ sender: Any?) {
        guard let editor = editor, let item = chosenItem else {
            NSSound.beep()
            return
        }
        do {
            switch item.origin {
            case .template:
                guard let template = GraphicTemplateLibrary.shared.entry(named: item.name) else {
                    throw ReelCoreError(
                        message: "The template \"\(item.name)\" is not in this build's bundle")
                }
                try editor.insertGraphic(from: template.template.url, grouped: false)
            case .project:
                try editor.insertProjectGraphic(named: item.name, grouped: false)
            }
        } catch {
            NSSound.beep()
            messageLabel.stringValue = (error as? ReelCoreError)?.message
                ?? error.localizedDescription
            return
        }
        dismiss(self)
    }

    // MARK: - Export

    /// The save panel, as a sheet on the browser, named `<module>.fjgraphic`.
    @objc private func exportClicked(_ sender: Any?) {
        guard let item = chosenItem, item.ok, !exporting, let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [GraphicPackage.contentType]
        panel.nameFieldStringValue = "\(item.name).\(GraphicPackage.fileExtension)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.exportChosen(to: url)
        }
    }

    /// The panel's OK (and the probe's entry): the chosen graphic's job built here, on main,
    /// and written on its own thread. A throw beeps and shows the sentence.
    func exportChosen(to url: URL) {
        guard let item = chosenItem, let document = document, !exporting else {
            NSSound.beep()
            return
        }
        let job: GraphicPackageJob
        do {
            switch item.origin {
            case .template:
                guard let template = GraphicTemplateLibrary.shared.entry(named: item.name) else {
                    throw ReelCoreError(
                        message: "The template \"\(item.name)\" is not in this build's bundle")
                }
                job = try GraphicPackageJob.template(template, document: document)
            case .project:
                job = try GraphicPackageJob.project(named: item.name, document: document)
            }
        } catch {
            NSSound.beep()
            messageLabel.stringValue = Self.sentence(error)
            return
        }
        exporting = true
        exportButton.isEnabled = false
        messageLabel.stringValue = "Exporting \(job.title)…"
        let thread = Thread { [weak self] in
            let outcome = Result { try job.write(to: url) }
            DispatchQueue.main.async { [weak self] in self?.exportFinished(job, outcome) }
        }
        thread.stackSize = GraphicPrefetch.workerStackBytes
        thread.name = "com.kgalligan.framejob.graphic-export"
        exportThread = thread
        thread.start()
    }

    private func exportFinished(
        _ job: GraphicPackageJob, _ outcome: Result<GraphicPackageResult, Error>
    ) {
        exporting = false
        exportButton.isEnabled = chosenItem?.ok == true
        switch outcome {
        case .success(let result):
            messageLabel.stringValue = "Exported \(job.title) to \(result.url.lastPathComponent): "
                + result.files.joined(separator: ", ") + "."
        case .failure(let error):
            NSSound.beep()
            messageLabel.stringValue = Self.sentence(error)
        }
    }

    private static func sentence(_ error: Error) -> String {
        (error as? ReelCoreError)?.message ?? error.localizedDescription
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        player.stop()
        if fromFilePending {
            fromFilePending = false
            editor?.insertGraphicFromFile(nil)
        }
    }
}
