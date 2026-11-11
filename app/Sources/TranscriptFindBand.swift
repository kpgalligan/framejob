import AppKit

/// The Transcript tab's find bar (spec §11 TX-37): the field, the count,
/// Previous, Next and Done in one row above the transcript's text. It stores
/// nothing but the field's text; the pane owns the matches.
///
/// **Frame Job's own bar, not `NSTextFinder`'s** (TX-37): that bar is a
/// system search field whose Return K-4 would spend, it shows the current
/// match by setting the client's selection — here the in/out range (TX-31) —
/// and its only programmatic search string is the shared find pasteboard.
///
/// It is the field's host for K-4's click rule (`TextFocusHosting`), so a
/// press on Previous, Next or the count leaves the keys in the field.
final class TranscriptFindBand: NSView, TextFocusHosting {
    static let height: CGFloat = 34

    let field = TranscriptFindField()
    private let count = NSTextField(labelWithString: "")
    private(set) var previous: OptionButtonControl!
    private(set) var next: OptionButtonControl!
    private(set) var done: OptionButtonControl!

    /// The field's text changed, by typing or by `type(_:)`.
    var onQuery: ((String) -> Void)?
    /// Return or Next (+1), ⇧Return or Previous (−1).
    var onStep: ((Int) -> Void)?
    /// ⌘Return (spec §11 TX-43): the current match selected, as a click does.
    var onSelect: (() -> Void)?
    /// Esc in the field, or Done.
    var onClose: (() -> Void)?

    var query: String { field.stringValue }
    var countText: String { count.stringValue }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        setAccessibilityIdentifier("transcript.find")
        field.onQuery = { [weak self] text in self?.onQuery?(text) }
        field.onStep = { [weak self] delta in self?.onStep?(delta) }
        field.onSelect = { [weak self] in self?.onSelect?() }
        field.onClose = { [weak self] in self?.onClose?() }
        count.font = DS.sans(11)
        count.textColor = DS.textMuted
        count.lineBreakMode = .byTruncatingTail
        count.setAccessibilityIdentifier("transcript.find.count")
        previous = button("‹", "Previous match (⇧Return)", "previous") { [weak self] in
            self?.onStep?(-1)
        }
        next = button("›", "Next match (Return)", "next") { [weak self] in self?.onStep?(1) }
        done = button("Done", "Close Find (Esc)", "done") { [weak self] in self?.onClose?() }

        let row = NSStackView(views: [field, count, previous, next, done])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        // The field takes the slack and gives way last; the count truncates
        // before the field falls under its floor.
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(240), for: .horizontal)
        for control in [previous!, next!, done!] {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let floor = field.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        floor.priority = NSLayoutConstraint.Priority(900)
        // The row keeps its place when the band is collapsed to no height.
        let centre = row.centerYAnchor.constraint(equalTo: centerYAnchor)
        centre.priority = .defaultHigh
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InspectorMetrics.inset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InspectorMetrics.inset),
            centre, floor,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TranscriptFindBand does not support NSCoder")
    }

    private func button(
        _ title: String, _ tip: String, _ id: String, _ action: @escaping () -> Void
    ) -> OptionButtonControl {
        let control = OptionButtonControl(title: title, action: action, enabled: { true }, onEdit: {})
        control.toolTip = tip
        control.setAccessibilityIdentifier("transcript.find.\(id)")
        control.setAccessibilityLabel(tip)
        return control
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    func setCount(_ text: String) {
        count.stringValue = text
    }

    /// Sets the field's text as typing does: the same change path.
    func type(_ text: String) {
        if let editor = field.currentEditor() {
            editor.string = text
        }
        field.stringValue = text
        onQuery?(text)
    }
}

/// The find bar's field: `DSField` chrome, its own delegate as
/// `MediaSearchField` is. Return never commits and leaves: in the editor
/// window `EditorWindow` hands it Return with the event in hand
/// (`TextFocusKeepsReturn`, K-4 (3)'s one exception), so ⇧ and ⌘ are read
/// from the key itself (TX-43) and the field keeps the keys unless ⌘Return
/// selects the match.
final class TranscriptFindField: NSTextField, NSTextFieldDelegate, TextFocusKeepsReturn {
    var onQuery: ((String) -> Void)?
    var onStep: ((Int) -> Void)?
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        DSField.style(self, height: 24, radius: DS.controlRadius, font: DS.sans(11))
        placeholderString = "Find in transcript"
        setAccessibilityIdentifier("transcript.find.field")
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TranscriptFindField does not support NSCoder")
    }

    func controlTextDidChange(_ obj: Notification) {
        onQuery?(stringValue)
    }

    func returnPressed(_ key: KeptReturn) {
        switch key {
        case .next: onStep?(1)
        case .previous: onStep?(-1)
        case .select: onSelect?()
        }
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Outside the editor window (a harness): Return still steps.
            onStep?(1)
            return true
        default:
            return false
        }
    }
}
