import AppKit

/// An editable one-line string — a marker's name, a graphic's string
/// property, a clip's own name. `OptionFieldControl` is numeric only, and a
/// name is the one text value the inspector edits outside the Text tab's
/// content area.
///
/// It LOOKS like the inspector's value field (spec §11 SH-3): filled, a 1 pt
/// `DS.border` stroke, 7 pt padding, the line centred vertically — drawn by
/// `InspectorNameFieldCell`, not a layer border, so it follows the appearance
/// and a `cacheDisplay` capture holds it. It pins its own height at
/// `DS.controlHeight`, one constraint, which the clip header re-pins. Its
/// alignment rect is its frame (no insets), so a constraint places the box
/// where it places a value field's, and the text and the field editor move
/// with it (kpgalligan/reelcut#186).
final class InspectorNameField: NSTextField, OptionControl, NSTextFieldDelegate {
    private let read: () -> String
    private let write: (String) -> Void
    /// Not `enabled`: `NSControl` already owns that name, and a stored
    /// property would be read as an override of it.
    private let isLive: () -> Bool
    private let onEdit: () -> Void

    override class var cellClass: AnyClass? {
        get { InspectorNameFieldCell.self }
        set {}
    }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    init(
        read: @escaping () -> String, write: @escaping (String) -> Void,
        enabled: @escaping () -> Bool, onEdit: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.isLive = enabled
        self.onEdit = onEdit
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        textColor = DS.textStrong
        font = DS.sans(11)
        usesSingleLineMode = true
        cell?.isScrollable = true
        lineBreakMode = .byTruncatingTail
        heightAnchor.constraint(equalToConstant: DS.controlHeight).isActive = true
        delegate = self
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorNameField does not support NSCoder")
    }

    func refresh() {
        let active = isLive()
        alphaValue = active ? 1 : 0.42
        isEditable = active
        isSelectable = active
        // Skipped while the field is being typed into, or the value it is
        // about to commit would be overwritten by the one it replaces.
        guard currentEditor() == nil else { return }
        let value = read()
        if stringValue != value { stringValue = value }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let value = stringValue
        if value != read() {
            write(value)
            onEdit()
        }
        // Re-read directly rather than through `refresh()`: every refresh the
        // commit just ran was skipped, because the field editor is still
        // attached here — and after Return or Tab AppKit re-attaches it — so
        // the field would go on showing what was typed (blank after a clear,
        // padded text after a padded rename, blank on a clip whose empty
        // commit sent nothing) while the model holds the trimmed name or the
        // fallback. The timecode field's beep path sets itself the same way.
        let now = read()
        if stringValue != now { stringValue = now }
    }
}

/// `InspectorNameField`'s cell: `OptionFieldControl`'s box — the
/// `controlBackgroundColor` fill and the 1 pt `DS.border` stroke on the
/// bounds inset by half a point — with the text inset by `padding` on each
/// side and its line box centred vertically, at rest and while the field
/// editor is attached (spec §11 SH-3).
final class InspectorNameFieldCell: NSTextFieldCell {
    static let padding: CGFloat = 7
    /// The field editor's own `lineFragmentPadding`, which the rest drawing
    /// matches.
    private static let lineFragmentPadding: CGFloat = 2

    override init(textCell string: String) {
        super.init(textCell: string)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("InspectorNameFieldCell does not support NSCoder")
    }

    /// `rect` less the padding, cut to one line box and centred in it.
    private func lineRect(in rect: NSRect) -> NSRect {
        let inset = rect.insetBy(dx: Self.padding, dy: 0)
        let face = font ?? DS.sans(11)
        let line = min(inset.height, ceil(face.ascender - face.descender + face.leading))
        return NSRect(
            x: inset.minX, y: inset.minY + floor((inset.height - line) / 2),
            width: max(0, inset.width), height: line)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        lineRect(in: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        lineRect(in: rect)
    }

    /// Super's, widened by the padding on both sides, so the field's
    /// intrinsic width — and the layout dump's truncation rule — counts it.
    override func cellSize(forBounds rect: NSRect) -> NSSize {
        let size = super.cellSize(forBounds: rect)
        return NSSize(width: size.width + 2 * Self.padding, height: size.height)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let path = NSBezierPath(
            roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: DS.controlRadius, yRadius: DS.controlRadius)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        DS.border.setStroke()
        path.stroke()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    /// The text at rest, drawn by the text system the field editor lays
    /// out with — its line fragment padding and baseline, in the same line
    /// rect — so clicking in moves no glyph. Super's own rest drawing sits
    /// 1–2 pt below the field editor's line in this rect (measured: 2 pt at
    /// 11 pt, 1 pt at 12 pt). Nothing is drawn while the field editor is
    /// attached: it draws the text itself.
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if (controlView as? NSTextField)?.currentEditor() != nil { return }
        let face = font ?? DS.sans(11)
        let text: NSMutableAttributedString
        if !stringValue.isEmpty {
            text = NSMutableAttributedString(attributedString: attributedStringValue)
        } else if let placeholder = placeholderAttributedString {
            text = NSMutableAttributedString(attributedString: placeholder)
        } else if let placeholder = placeholderString, !placeholder.isEmpty {
            text = NSMutableAttributedString(
                string: placeholder,
                attributes: [.font: face, .foregroundColor: NSColor.placeholderTextColor])
        } else {
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(
            .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        text.draw(
            with: lineRect(in: cellFrame).insetBy(dx: Self.lineFragmentPadding, dy: 0),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func edit(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: lineRect(in: rect), in: controlView, editor: textObj, delegate: delegate,
            event: event)
    }

    override func select(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
        start selStart: Int, length selLength: Int
    ) {
        super.select(
            withFrame: lineRect(in: rect), in: controlView, editor: textObj, delegate: delegate,
            start: selStart, length: selLength)
    }
}
