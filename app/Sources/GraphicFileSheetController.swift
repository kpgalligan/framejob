// app/Sources/GraphicFileSheetController.swift — File ▸ Rename Graphic…,
// Delete Graphic… and Restore Graphic Version… (spec §11 G-30; issue #103,
// issue batch B84): ONE small sheet for the three, a pop-up of the
// project's graphics over the three bodies in
// `ProjectDocument+GraphicFiles.swift` — the bodies `rename_graphic`,
// `delete_graphic` and `restore_graphic` call, so both doors refuse in the
// same sentences.
//
// **No second implementation.** Every act is one call of a body
// (`perform`); nothing here reaches a `GraphicStore` writer, an op or an
// undo registration, and no sentence a body throws is rewritten, prefixed
// or predicted: a refusal is shown word for word in `messageLabel` and the
// sheet stays up. The two guards written here name the CALL (spec §11
// D2-1): a new name that is empty or unchanged (`canConfirm`), and an item
// with nothing to list (`isOffered`).
//
// **`perform` runs from the button's action only**: each body ends in
// `rescan()`, which must never run from a `.graphicsDidChange` observer.
// Rename's `apply` is `performGroupedEdit`, never `applyEdit`: the clips'
// new name is one CLOSED undo step wherever the action was sent from, it
// does not throw, and the body's own re-read moves the file back when the
// edit was refused.

import AppKit

/// One of the three file acts a person can ask for.
enum GraphicFileAct: CaseIterable {
    case rename, delete, restore

    /// The File menu's title.
    var menuTitle: String {
        switch self {
        case .rename: return "Rename Graphic…"
        case .delete: return "Delete Graphic…"
        case .restore: return "Restore Graphic Version…"
        }
    }

    /// The sheet's title: the menu's without its "…".
    var sheetTitle: String { String(menuTitle.dropLast()) }

    var confirmTitle: String {
        switch self {
        case .rename: return "Rename"
        case .delete: return "Delete"
        case .restore: return "Restore"
        }
    }

    /// The sentence under the title (spec §11 G-30 (c), word for word).
    var hint: String {
        switch self {
        case .rename:
            return "Every clip that uses the graphic follows its new name, on the timeline and "
                + "inside nests. Undo renames it back when a clip uses it; a graphic no clip "
                + "uses is renamed back by renaming it again."
        case .delete:
            return "A graphic that clips still use cannot be deleted. Its code is kept with its "
                + "earlier versions, so Restore Graphic Version… brings it back. Deleting is "
                + "not an Undo step."
        case .restore:
            return "Puts back the newest kept version of the graphic's code. If the graphic has "
                + "code now, that code is kept in its place, so restoring again returns to "
                + "where you were. Restoring is not an Undo step."
        }
    }
}

/// One row of the sheet's pop-up.
struct GraphicFileChoice: Equatable {
    let name: String
    /// No `graphics/<name>.js`: a deleted module that still has kept texts.
    let deleted: Bool
    /// How many texts of it are kept.
    let kept: Int

    var title: String { deleted ? "\(name) (deleted)" : name }
}

final class GraphicFileSheetController: NSViewController, NSTextFieldDelegate {
    /// Weak, like every sheet's back-reference.
    private weak var document: ProjectDocument?
    private let act: GraphicFileAct
    private let choices: [GraphicFileChoice]
    private let opening: String?

    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let keptLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let confirmButton: NSButton

    private static let controlWidth: CGFloat = 240

    // MARK: - The model

    /// The rows an act lists, by name: the folder's modules for Rename and
    /// Delete; every name with a kept text for Restore, deleted modules
    /// included. Empty with no store.
    static func choices(for act: GraphicFileAct, in document: ProjectDocument)
        -> [GraphicFileChoice]
    {
        guard let store = document.graphicStore else { return [] }
        let names: [String]
        switch act {
        case .rename, .delete:
            return store.scan.modules.keys.sorted().map {
                GraphicFileChoice(name: $0, deleted: false, kept: store.kept(named: $0).count)
            }
        case .restore:
            names = store.keptNames()
        }
        return names.map {
            GraphicFileChoice(
                name: $0, deleted: !store.holdsModule(named: $0),
                kept: store.kept(named: $0).count)
        }
    }

    /// Whether the menu item is live: something to list, and for Rename no
    /// nest open (spec §11 G-28 (g)). A validator asks this on every menu
    /// open, so it answers whether `choices` would be empty without
    /// building them: Rename and Delete from the last scan, Restore from
    /// `keptNames()`, and no row's `kept` count is read.
    static func isOffered(_ act: GraphicFileAct, in document: ProjectDocument) -> Bool {
        if act == .rename, document.scope != nil { return false }
        guard let store = document.graphicStore else { return false }
        switch act {
        case .rename, .delete: return !store.scan.modules.isEmpty
        case .restore: return !store.keptNames().isEmpty
        }
    }

    /// The row the sheet opens on: for Rename and Restore the selected
    /// clip's graphic when it is a row, else — and always for Delete, whose
    /// selected clip's graphic is in use — the first; nil with no rows.
    static func opening(
        for act: GraphicFileAct, selected: String?, in choices: [GraphicFileChoice]
    ) -> String? {
        var asked = selected
        if act == .delete { asked = nil }
        if let asked = asked, choices.contains(where: { $0.name == asked }) { return asked }
        return choices.first?.name
    }

    static func keptLine(_ kept: Int) -> String {
        kept == 1 ? "1 version kept" : "\(kept) versions kept"
    }

    /// Whether the button is live: Rename needs a new name that is not the
    /// chosen one.
    static func canConfirm(_ act: GraphicFileAct, name: String, to: String) -> Bool {
        act != .rename || (!to.isEmpty && to != name)
    }

    /// The act itself: one call of the body its tool calls. `to` is
    /// Rename's alone and goes to the body as typed.
    static func perform(
        _ act: GraphicFileAct, name: String, to: String, on document: ProjectDocument
    ) throws {
        switch act {
        case .rename:
            _ = try document.renameGraphic(named: name, to: to) {
                document.performGroupedEdit("Rename Graphic", $0)
            }
        case .delete:
            _ = try document.deleteGraphic(named: name)
        case .restore:
            _ = try document.restoreGraphic(named: name, revision: nil)
        }
    }

    // MARK: - Life cycle

    init(
        document: ProjectDocument, act: GraphicFileAct, choices: [GraphicFileChoice],
        opening: String?
    ) {
        self.document = document
        self.act = act
        self.choices = choices
        self.opening = opening
        self.confirmButton = StickerButton(
            title: act.confirmTitle, style: .primary, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GraphicFileSheetController does not support NSCoder")
    }

    override func loadView() {
        // Rows are `NSMenuItem`s carrying the name: `addItem(withTitle:)`
        // removes a row with the same title, and a row is never read by index.
        for choice in choices {
            let row = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            row.representedObject = choice.name
            popup.menu?.addItem(row)
        }
        if let row = popup.itemArray.first(where: { $0.representedObject as? String == opening }) {
            popup.select(row)
        }
        popup.font = DS.sans(13)
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        popup.setAccessibilityIdentifier("graphicfile.popup")

        nameField.delegate = self
        nameField.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        DSField.style(nameField)
        nameField.setAccessibilityIdentifier("graphicfile.name")

        keptLabel.font = DS.mono(11)
        keptLabel.textColor = DS.textMuted
        keptLabel.setAccessibilityIdentifier("graphicfile.kept")

        messageLabel.font = DS.sans(12)
        messageLabel.textColor = DS.textStrong
        messageLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        messageLabel.isHidden = true
        messageLabel.setAccessibilityIdentifier("graphicfile.message")

        var rows: [[NSView]] = [[fieldLabel("Graphic:"), popup]]
        if act == .rename { rows.append([fieldLabel("New name:"), nameField]) }
        if act == .restore { rows.append([NSGridCell.emptyContentView, keptLabel]) }
        let grid = makeSheetGrid(rows)

        let content = sheetColumn([grid, messageLabel])

        confirmButton.target = self
        confirmButton.action = #selector(confirmClicked(_:))
        confirmButton.setAccessibilityIdentifier("graphicfile.confirm")
        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        view = makeSheetView(
            title: act.sheetTitle, hint: act.hint, content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: confirmButton,
                leading: act == .rename ? [sheetFootnote("lowercase letters, digits and -")] : []))
        syncChoice()
    }

    // MARK: - Values

    private var chosenName: String? { popup.selectedItem?.representedObject as? String }

    /// The chosen row into the controls that follow it: Rename's field and
    /// Restore's kept line; then the button.
    private func syncChoice() {
        let name = chosenName
        nameField.stringValue = name ?? ""
        let kept = choices.first { $0.name == name }?.kept ?? 0
        keptLabel.stringValue = Self.keptLine(kept)
        syncConfirm()
    }

    private func syncConfirm() {
        confirmButton.isEnabled = chosenName.map {
            Self.canConfirm(act, name: $0, to: nameField.stringValue)
        } ?? false
    }

    // MARK: - Controls

    @objc private func popupChanged(_ sender: Any?) {
        syncChoice()
    }

    func controlTextDidChange(_ obj: Notification) {
        syncConfirm()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// The act, once. A refusal beeps and shows the body's sentence, and
    /// the sheet stays up; a success closes it and says nothing.
    @objc private func confirmClicked(_ sender: Any?) {
        guard let document = document, let name = chosenName,
            Self.canConfirm(act, name: name, to: nameField.stringValue)
        else {
            NSSound.beep()
            return
        }
        do {
            try Self.perform(act, name: name, to: nameField.stringValue, on: document)
        } catch {
            NSSound.beep()
            let message = (error as? ReelCoreError)?.message ?? error.localizedDescription
            messageLabel.stringValue = message
            messageLabel.isHidden = false
            return
        }
        dismiss(self)
    }
}
