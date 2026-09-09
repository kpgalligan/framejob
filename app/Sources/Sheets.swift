import AppKit

// MARK: - Shared layout helpers
//
// Module-wide, not file-private: a dialog too big to live here is its own
// …SheetController file (LivePhotoFrameSheetController), and it must be
// built from these same pieces or the sheets stop matching each other.

let sheetWidth: CGFloat = 420
let sheetInset: CGFloat = 22

/// Assembles a design-system sheet: 420px card by default (`width:` for a
/// wider one — the Layer Style sheet's two panes), 15px/700 title, optional
/// 12px muted hint, content, then the button row.
func makeSheetView(
    title: String? = nil, hint: String? = nil, content: NSView, buttonRow: NSStackView,
    width: CGFloat = sheetWidth
) -> NSView {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 240))
    container.wantsLayer = true
    container.layer?.backgroundColor = DS.chromeBackground.cgColor

    var stackedViews: [NSView] = []
    if let title = title {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = DS.sans(15, weight: .bold)
        titleLabel.textColor = DS.textStrong
        stackedViews.append(titleLabel)
    }
    if let hint = hint {
        let hintLabel = NSTextField(wrappingLabelWithString: hint)
        hintLabel.font = DS.sans(12)
        hintLabel.textColor = DS.textMuted
        hintLabel.isEditable = false
        hintLabel.preferredMaxLayoutWidth = width - sheetInset * 2
        stackedViews.append(hintLabel)
    }
    stackedViews.append(content)
    let stack = NSStackView(views: stackedViews)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.setCustomSpacing(16, after: stackedViews[stackedViews.count - 2])

    stack.translatesAutoresizingMaskIntoConstraints = false
    buttonRow.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    container.addSubview(buttonRow)
    NSLayoutConstraint.activate([
        container.widthAnchor.constraint(equalToConstant: width),
        stack.topAnchor.constraint(equalTo: container.topAnchor, constant: sheetInset),
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: sheetInset),
        stack.trailingAnchor.constraint(
            lessThanOrEqualTo: container.trailingAnchor, constant: -sheetInset),
        buttonRow.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: sheetInset),
        buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: sheetInset),
        buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -sheetInset),
        buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -sheetInset),
    ])
    return container
}

/// The sheet's button row: `leading` at the far left (a footnote), then a
/// spacer, then the trailing cluster.
///
/// **`secondary` is a second affirmative button**, left of Cancel and inside
/// the trailing cluster — a "do something else with this card" beside the
/// button that does the main thing. It is NOT `leading`, which is where the
/// footnote lives: an affirmative button at the far left of a dialog reads as
/// a destructive or a tertiary one, and it would sit under the export sheet's
/// codec footnote besides. It takes no key equivalent, which is the other half
/// of the same point — Return belongs to `apply` and Escape to `cancel`, and a
/// row with two Returns has none.
///
/// Its one caller is the export sheet's "Add to Queue" (road map 2's phase 7e,
/// built and passed in `ExportSheetController.loadView`) — the shipped example
/// to read before a second dialog takes the slot. The parameter landed a wave
/// AHEAD of that button, alone, because this file is shared by every dialog in
/// the app and a change to it is worth making where the type checker can see
/// every existing call is unchanged; it defaults to nil, so every dialog but
/// the export card still asks for the two-button row it always had.
func makeButtonRow(
    cancel: NSButton, apply: NSButton, secondary: NSButton? = nil, leading: [NSView] = []
) -> NSStackView {
    cancel.keyEquivalent = "\u{1b}"
    apply.keyEquivalent = "\r"
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
    let trailing: [NSView] = secondary.map { [$0, cancel, apply] } ?? [cancel, apply]
    let row = NSStackView(views: leading + [spacer] + trailing)
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    return row
}

/// 13px row label for the sheet grids' 106px right-aligned label column.
func fieldLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = DS.sans(13)
    label.textColor = DS.textStrong
    return label
}

/// Bottom-left 10px mono footnote carried in the button row's leading slot.
func sheetFootnote(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = DS.mono(10)
    label.textColor = DS.textFaint
    return label
}

func sheetCancelButton(target: AnyObject, action: Selector) -> NSButton {
    StickerButton(title: "Cancel", style: .secondary, target: target, action: action)
}

func sheetApplyButton(target: AnyObject, action: Selector) -> NSButton {
    StickerButton(title: "Apply", style: .primary, target: target, action: action)
}
