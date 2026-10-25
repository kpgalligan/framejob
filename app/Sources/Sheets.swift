import AppKit

// MARK: - Shared layout helpers
//
// Module-wide, not file-private: a dialog too big to live here is its own
// …SheetController file (LivePhotoFrameSheetController), and it must be
// built from these same pieces or the sheets stop matching each other.

let sheetWidth: CGFloat = 420
let sheetInset: CGFloat = 22

/// Assembles a design-system sheet: 420px card by default (`width:` for a
/// wider one — the Layer Style sheet's two panes, the export sheet's 480),
/// 15px/700 title, optional 12px muted hint, content, then the button row.
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
/// a destructive or a tertiary one, and on most sheets it would sit under a
/// footnote besides. It takes no key equivalent, which is the other half
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
///
/// **Every `leading` view resists compression at `.defaultLow`**, below the
/// buttons' default 750, so a long footnote gives way before a button and the
/// row has one answer instead of two tied ones (#141; a divergence from
/// Rasterize's copy).
func makeButtonRow(
    cancel: NSButton, apply: NSButton, secondary: NSButton? = nil, leading: [NSView] = []
) -> NSStackView {
    cancel.keyEquivalent = "\u{1b}"
    apply.keyEquivalent = "\r"
    for view in leading {
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
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

/// 10px mono footnote: in the button row's `leading` slot, or on a line of
/// its own under a sheet's content (the export sheet, #243). A label built by
/// `NSTextField(labelWithString:)` breaks by clipping, so a footnote too long
/// for its room ends with a tail ellipsis and carries the whole string as a
/// tooltip (Rasterize's two lines, #141).
func sheetFootnote(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = DS.mono(10)
    label.textColor = DS.textFaint
    label.lineBreakMode = .byTruncatingTail
    label.toolTip = text
    return label
}

func sheetCancelButton(target: AnyObject, action: Selector) -> NSButton {
    StickerButton(title: "Cancel", style: .secondary, target: target, action: action)
}

func sheetApplyButton(target: AnyObject, action: Selector) -> NSButton {
    StickerButton(title: "Apply", style: .primary, target: target, action: action)
}

// MARK: - Frame Job's own pieces (not in Rasterize's copy)
//
// The progress sheets' chrome and the settings sheets' grid, once each, so a
// sheet is built from them rather than re-typing the metrics (#359).

/// A progress sheet's bar: determinate 0…1 unless `indeterminate`, as wide as
/// the sheet's content.
func styleSheetProgressBar(_ bar: NSProgressIndicator, indeterminate: Bool = false) {
    bar.style = .bar
    bar.isIndeterminate = indeterminate
    bar.minValue = 0
    bar.maxValue = 1
    bar.doubleValue = 0
    bar.usesThreadedAnimation = true
    bar.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2).isActive = true
}

/// A progress sheet's 12px muted status line, wrapping at the content width.
func styleSheetStatusLabel(_ label: NSTextField) {
    label.font = DS.sans(12)
    label.textColor = DS.textMuted
    label.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
}

/// A progress sheet's 11px mono detail line (the file being worked on),
/// truncated in the middle at the content width.
func styleSheetDetailLabel(_ label: NSTextField) {
    label.font = DS.mono(11)
    label.textColor = DS.textFaint
    label.lineBreakMode = .byTruncatingMiddle
    label.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2).isActive = true
}

/// A progress sheet's content: bar, status and detail, 8px apart.
func makeProgressStack(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    return stack
}

/// The button a progress sheet shows only once it is over.
func hideReturnTarget(_ button: NSButton) {
    // Hidden AND disabled while the work runs: AppKit skips both when it
    // looks for the Return key's target, so the sheet's only live button is
    // Cancel until there is a result to act on.
    button.isHidden = true
    button.isEnabled = false
}

/// A settings sheet's label grid: rows 10px apart, a 106px right-aligned
/// label column (`fieldLabel`), 12px to the controls.
func makeSheetGrid(_ rows: [[NSView]]) -> NSGridView {
    let grid = NSGridView(views: rows)
    grid.rowSpacing = 10
    grid.columnSpacing = 12
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 0).width = 106
    return grid
}

/// A settings sheet's content column: its pieces stacked 10px apart.
func sheetColumn(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    return stack
}

/// The controls of one grid row, side by side, 6px apart.
func sheetRow(_ views: [NSView]) -> NSStackView {
    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    return row
}

/// The muted 13px unit after a field ("×", "s", "dB").
func sheetUnitLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = DS.sans(13)
    label.textColor = DS.textMuted
    return label
}

extension NSViewController {
    /// Ends a field's editing before a sheet acts on its values: true when
    /// there is no window or the window resigned its first responder;
    /// otherwise beeps and answers false.
    func endSheetFieldEditing() -> Bool {
        if let window = view.window, !window.makeFirstResponder(nil) {
            NSSound.beep()
            return false
        }
        return true
    }
}
