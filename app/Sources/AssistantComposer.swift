import AppKit

/// The Assistant tab's composer (spec §11 AI-17): a plain-text view that
/// grows from one line to five inside `AssistantComposerField`.
///
/// **Keys.** A bare Return or keypad Enter is `onReturn` (the view sends
/// while idle and beeps otherwise — never an answer); Return with ⇧, ⌘, ⌥ or
/// ⌃ inserts "\n", K-2's rule through the same `TextEditKey.route`, and
/// nothing is routed while an input method has marked text. Tab and ⇧Tab
/// never type a tab: in the editor window `TextFocus` takes them first and
/// hands the keys back to the editor (spec §11 K-4), as a Return that sends
/// does (`AssistantView.send`); with Full Keyboard Access on they reach
/// here and move focus along the key-view loop.
///
/// **Undo is its own.** An editable text view takes its undo manager from
/// the window, and an editor window's IS the document's, so typing would
/// land on the project's stack. The override hands AppKit `ownUndoManager`
/// instead: ⌘Z here undoes typing, and typing never touches the document's
/// stack, its dirty state or `registerUndo`'s grouping (AI-10, app/CLAUDE.md's
/// Undo). A programmatic `string` (a send, the dev tools' pane path) drops
/// that history. The window's own `undo:` reads the WINDOW's manager, not the
/// first responder's (measured: `assistant_tab_probe` P11), so the composer
/// answers `undo:` and `redo:` itself, over the same manager.
final class AssistantComposerTextView: NSTextView {
    var placeholder: String = "" {
        didSet {
            setAccessibilityPlaceholderValue(placeholder)
            needsDisplay = true
        }
    }
    /// A bare Return or keypad Enter.
    var onReturn: (() -> Void)?
    /// Every change to the string, typed or set; the field refits.
    var onChange: (() -> Void)?
    private let ownUndoManager = UndoManager()

    override var undoManager: UndoManager? { ownUndoManager }

    override var string: String {
        didSet {
            ownUndoManager.removeAllActions()
            onChange?()
            needsDisplay = true
        }
    }

    @objc func undo(_ sender: Any?) {
        ownUndoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        ownUndoManager.redo()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            (item as? NSMenuItem)?.title = ownUndoManager.undoMenuItemTitle
            return ownUndoManager.canUndo
        case #selector(redo(_:)):
            (item as? NSMenuItem)?.title = ownUndoManager.redoMenuItemTitle
            return ownUndoManager.canRedo
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch TextEditKey.route(event, hasMarkedText: hasMarkedText()) {
        case .apply: onReturn?()
        case .newline: insertNewline(nil)
        case .escape, nil: super.keyDown(with: event)
        }
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?()
        needsDisplay = true
    }

    /// Where the placeholder is drawn: one line high, at the text's origin.
    var placeholderRect: NSRect {
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = textContainerOrigin
        let width = max(bounds.width - origin.x * 2 - padding * 2, 0)
        let height = AssistantComposerField.lineHeight(font ?? DS.sans(12))
        return NSRect(x: origin.x + padding, y: origin.y, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? DS.sans(12), .foregroundColor: NSColor.placeholderTextColor,
        ]
        (placeholder as NSString).draw(
            with: placeholderRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes)
    }
}

/// The composer's frame: DSField's square 1 pt border round a scroll view
/// whose text view is `AssistantComposerTextView`. 26 pt for one line, one
/// line height more per further line up to `maxLines`; past that the height
/// holds and the text scrolls. It refits on every change to the string and
/// on any width change.
final class AssistantComposerField: NSScrollView {
    static let maxLines = 5
    static let oneLineHeight: CGFloat = 26
    let textView: AssistantComposerTextView
    private var height: NSLayoutConstraint?
    private var fittedWidth: CGFloat = -1

    init() {
        textView = AssistantComposerTextView(usingTextLayoutManager: false)
        super.init(frame: .zero)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = DS.fieldRadius
        refreshBorder()

        let font = DS.sans(12)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textColor = DS.textStrong
        textView.insertionPointColor = DS.textStrong
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.typingAttributes = [.font: font, .foregroundColor: DS.textStrong]
        let lineHeight = Self.lineHeight(font)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainerInset = NSSize(
            width: 2, height: max((Self.oneLineHeight - lineHeight) / 2, 0))
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(origin: .zero, size: contentSize)
        textView.onChange = { [weak self] in self?.fit() }
        documentView = textView

        let constraint = heightAnchor.constraint(equalToConstant: Self.oneLineHeight)
        constraint.isActive = true
        height = constraint
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantComposerField does not support NSCoder")
    }

    override func layout() {
        super.layout()
        guard bounds.width != fittedWidth else { return }
        fittedWidth = bounds.width
        fit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBorder()
    }

    /// The height for the string's line count, capped at `maxLines`.
    func fit() {
        guard let layout = textView.layoutManager, let container = textView.textContainer
        else { return }
        let lineHeight = Self.lineHeight(textView.font ?? DS.sans(12))
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let lines = max(1, Int((used / lineHeight).rounded()))
        let shown = CGFloat(min(lines, Self.maxLines))
        let wanted = Self.oneLineHeight + (shown - 1) * lineHeight
        textView.sizeToFit()
        if height?.constant != wanted { height?.constant = wanted }
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    private func refreshBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = DS.borderStrong.cgColor
        }
    }
}
