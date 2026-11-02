import AppKit

// MARK: - The save panel's options

/// The one choice a frame grab has — which container — carried in the save
/// panel's accessory view rather than in a sheet of its own.
///
/// `CaptionExportOptions` is the pattern and its argument holds here too: a
/// sheet for one popup would be the heavier answer, and chaining a sheet out
/// of a sheet is what `ReverseProgressSheetController` records as not working
/// in this app. The line under the popup is not decoration either — it is what
/// each format does with alpha, said out loud at the moment the format is
/// chosen, which is the only place a person with a transparent canvas
/// (phase 7b) will read it before the JPEG has already flattened.
///
/// It owns nothing but its controls; the panel's completion holds it for as
/// long as the panel is up.
final class SaveFrameOptions: NSObject {
    private weak var panel: NSSavePanel?
    private let stem: String
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hint = NSTextField(labelWithString: FrameWriter.Format.png.alphaNote)

    let view: NSView

    init(panel: NSSavePanel, stem: String) {
        self.panel = panel
        self.stem = stem

        for format in FrameWriter.Format.allCases {
            formatPopup.addItem(withTitle: format.displayName)
            // The row carries the FORMAT, never its position in the list.
            // `NSPopUpButton.addItem(withTitle:)` removes an existing row with
            // the same title before adding the new one, so a popup read by
            // `indexOfSelectedItem` is one duplicated title away from writing
            // a different format than the row named and reporting success —
            // phase 4's measured defect, in `app/CLAUDE.md`'s pitfall list.
            // These three titles are distinct; reading the object makes that
            // stop mattering.
            formatPopup.lastItem?.representedObject = format
        }
        formatPopup.font = DS.sans(13)
        formatPopup.selectItem(at: 0)

        hint.font = DS.sans(11)
        hint.textColor = DS.textMuted
        hint.isEditable = false

        let grid = NSGridView(views: [[fieldLabel("Format:"), formatPopup]])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 60
        grid.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        container.addSubview(hint)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 6),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            hint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: grid.widthAnchor, constant: 32),
            container.widthAnchor.constraint(greaterThanOrEqualTo: hint.widthAnchor, constant: 32),
            // A floor wide enough for the longest of the three notes, so the
            // accessory view is one size for every format. Without it the
            // container shrinks to fit whichever line is showing and the
            // popup above it walks sideways each time the popup is used —
            // which reads as the panel twitching at the person's own click.
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])
        view = container

        super.init()
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        syncHint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SaveFrameOptions does not support NSCoder")
    }

    var format: FrameWriter.Format {
        formatPopup.selectedItem?.representedObject as? FrameWriter.Format ?? .png
    }

    /// The panel's filter and its name field both name the container, so both
    /// move together — otherwise AppKit appends `.png` to a name the person
    /// just asked to be a `.jpg`.
    ///
    /// Only the EXTENSION is this method's to change. The stem is read back
    /// off the PANEL rather than from `stem`, which was fixed when the panel
    /// opened: somebody who typed "cover art" over the suggested name and then
    /// chose JPEG would otherwise watch the field silently revert to the
    /// project's name and save to a path they had already replaced. `stem`
    /// survives as the fallback for a field emptied to nothing.
    ///
    /// **The rewrite itself is `FrameWriter.renamed`**, which the review is
    /// what moved there: it strips a trailing suffix only when it is one of
    /// the three formats' own spellings, so `Board v1.2` no longer becomes
    /// `Board v1.jpg` when somebody picks JPEG, and — the reason it is a free
    /// function rather than four lines here — a rule inside a save panel's
    /// private method is a rule no proof can reach.
    @objc private func formatChanged(_ sender: Any?) {
        syncHint()
        guard let panel = panel else { return }
        let format = self.format
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = FrameWriter.renamed(
            panel.nameFieldStringValue, as: format, fallback: stem)
    }

    /// The note follows the popup. Every row has one, so the line never
    /// appears or disappears — `Format.alphaNote` argues why that is better
    /// than a warning that shows up only over JPEG, and a label whose height
    /// never changes is also what keeps the accessory view one size.
    private func syncHint() {
        hint.stringValue = format.alphaNote
    }
}
