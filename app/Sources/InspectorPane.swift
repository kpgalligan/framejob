import AppKit

/// The inspector's shared vocabulary (spec §4.3): which tabs exist and when
/// they are live, the disclosure section every pane is built from, the row and
/// control builders, and — the piece that carries the most rules —
/// `InspectorBinding`, which is the ONE place that knows how a pane reads a
/// property and how an edit made in a pane reaches the document.
///
/// Two rules live here and nowhere else, because getting either wrong is
/// invisible until a project is saved:
///
///  - **Reads are evaluated.** With the playhead inside an action, a field
///    must show the value the frame actually has, which is
///    `rc_project_clip_state` (§7.1), not the clip's base props.
///  - **Writes follow the read.** Inside an action, an edit sets THAT
///    action's end patch (`set_action_end`); outside one it merges into the
///    base props (`set_video` and friends) with every selected clip in a
///    single op, which is what §4.3 means by "edit their common properties
///    together".
///
/// Controls come from `OptionControls.swift` — they hold no value of their
/// own, so "model → inspector" is one walk calling `refresh()`
/// (`refreshOptionControls(in:)`). The one control added here is the slider:
/// the options bar never needed one, and forking the Rasterize-copied files
/// to add it would break the "keep them in sync" rule in app/CLAUDE.md.

// MARK: - Tabs

/// The six tabs of spec §4.3, in strip order. The raw value is the strip
/// index and the `UserDefaults` spelling of a pin, so the order is API.
enum InspectorTab: Int, CaseIterable {
    case video, audio, text, shape, media, document

    var title: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .text: return "Text"
        case .shape: return "Shape"
        case .media: return "Media"
        case .document: return "Document"
        }
    }

    /// What the strip draws when six full titles do not fit the pane's width
    /// (the inspector is 280–440 pt wide).
    var shortTitle: String {
        switch self {
        case .document: return "Doc"
        default: return title
        }
    }

    /// A tab is disabled when no selected clip has that aspect (§4.3). Media
    /// and Document are properties of the project, so they are always live.
    func isEnabled(for clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> Bool {
        switch self {
        case .media, .document:
            return true
        case .video:
            return clips.contains { InspectorTab.hasPixels($0, in: snapshot) }
        case .audio:
            return clips.contains { InspectorTab.hasAudio($0, in: snapshot) }
        case .text:
            return clips.contains { clip in
                if case .text = clip.source { return true }
                return false
            }
        case .shape:
            return clips.contains { clip in
                if case .shape = clip.source { return true }
                return false
            }
        }
    }

    /// Whether the clip puts pixels on the canvas — the Video tab's test, and
    /// the one that keeps an audio-only clip out of it.
    static func hasPixels(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        switch clip.source {
        case .text, .shape, .nest:
            return true
        case .media, .still, .image:
            guard let media = snapshot.media(for: clip) else { return false }
            return media.hasVideo || media.kind == .image
        }
    }

    /// Whether the clip carries live audio: its media has a track AND this
    /// half of the clip is enabled (Detach Audio flips that, §6).
    static func hasAudio(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard clip.enabled.audio, let media = snapshot.media(for: clip) else { return false }
        return media.hasAudio
    }

    /// Whether the clip's rectangle comes from a decoded source — the clips
    /// that get Crop, Colour and Corner Radius. Text and shape clips get
    /// Transform, Opacity and Shadow only (§4.3).
    static func hasSourcePixels(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        switch clip.source {
        case .media, .still, .image: return true
        case .text, .shape, .nest: return false
        }
    }

    /// The tab a fresh selection lands on unless the user pinned one. A text
    /// clip wants Text, a shape wants Shape, a clip with no pixels wants
    /// Audio; everything else wants Video.
    static func preferred(for clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> InspectorTab {
        guard let clip = clips.first else { return .media }
        switch clip.source {
        case .text: return .text
        case .shape: return .shape
        default:
            if !hasPixels(clip, in: snapshot), hasAudio(clip, in: snapshot) { return .audio }
            return .video
        }
    }
}

// MARK: - Metrics

/// The inspector's fixed dimensions. Separate from `DS` because they describe
/// this panel's grid, not the app's chrome.
enum InspectorMetrics {
    static let labelWidth: CGFloat = 76
    static let rowSpacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 2
    static let inset: CGFloat = 10
    static let headerHeight: CGFloat = 26
    static let fieldWidth: CGFloat = 58
    static let wideFieldWidth: CGFloat = 72
    static let popupWidth: CGFloat = 116
}

// MARK: - Refreshing

/// Re-reads every descriptor-driven control under `view`. The controls store
/// no value (OptionControls.swift), so this single walk IS the model →
/// inspector direction; nothing else pushes values into a field.
func refreshOptionControls(in view: NSView) {
    for subview in view.subviews {
        if let control = subview as? any OptionControl { control.refresh() }
        refreshOptionControls(in: subview)
    }
}

// MARK: - Small labels

/// A row's leading label. A plain `NSTextField` so it participates in the
/// stack's baseline alignment, styled once here so no pane re-invents it.
final class InspectorRowLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.sans(11)
        textColor = DS.textMuted
        lineBreakMode = .byTruncatingTail
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorRowLabel does not support NSCoder")
    }
}

/// The "the selected clips disagree about this value" marker. Shown beside a
/// field rather than blanking it: the field still edits (writing the value to
/// every clip), which is what §4.3's "edit their common properties together"
/// asks for.
final class InspectorMixedBadge: NSTextField, OptionControl {
    private let mixed: () -> Bool

    init(mixed: @escaping () -> Bool) {
        self.mixed = mixed
        super.init(frame: .zero)
        stringValue = "mixed"
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.mono(9)
        textColor = DS.textFaint
        toolTip = "The selected clips have different values"
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorMixedBadge does not support NSCoder")
    }

    func refresh() {
        isHidden = !mixed()
    }
}

/// An editable one-line string — a marker's name. `OptionFieldControl` is
/// numeric only, and a name is the one text value the inspector edits outside
/// the Text tab's content area.
final class InspectorNameField: NSTextField, OptionControl, NSTextFieldDelegate {
    private let read: () -> String
    private let write: (String) -> Void
    /// Not `enabled`: `NSControl` already owns that name, and a stored
    /// property would be read as an override of it.
    private let isLive: () -> Bool
    private let onEdit: () -> Void

    init(
        read: @escaping () -> String, write: @escaping (String) -> Void,
        enabled: @escaping () -> Bool, onEdit: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.isLive = enabled
        self.onEdit = onEdit
        super.init(frame: .zero)
        DSField.style(self)
        font = DS.sans(11)
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
        guard value != read() else { return }
        write(value)
        onEdit()
    }
}

/// A section's one-line note — "Editing action 2's end state" (§4.3). Hides
/// itself when the closure returns nil, so a section pays nothing for a note
/// it does not currently have.
final class InspectorNoteLabel: NSTextField, OptionControl {
    private let note: () -> String?

    init(note: @escaping () -> String?) {
        self.note = note
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.sans(11)
        textColor = DS.accent
        lineBreakMode = .byTruncatingTail
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorNoteLabel does not support NSCoder")
    }

    func refresh() {
        let text = note()
        stringValue = text ?? ""
        isHidden = text == nil
    }
}

// MARK: - Slider

/// A continuous value slider whose drag is a LIVE edit: `begin` on mouse
/// down, `write` on every move, `end` on mouse up (§4.3, the document's
/// `beginLiveEdit`/`updateLiveEdit`/`endLiveEdit` trio). Paired with an
/// `OptionFieldControl` in the same row, which commits typed values as a
/// single `applyEdit` instead.
///
/// It lives here rather than in `OptionControls.swift` because that file is
/// carried verbatim from Rasterize (app/CLAUDE.md: keep it in sync, do not
/// fork); it still conforms to `OptionControl` so `refreshOptionControls`
/// finds it like every other control.
final class InspectorSliderControl: NSView, OptionControl {
    private let lower: Double
    private let upper: Double
    private let read: () -> Double
    private let write: (Double) -> Void
    private let begin: () -> Void
    private let end: () -> Void
    private let enabled: () -> Bool
    private var isActive = true
    private var dragging = false

    private static let knob: CGFloat = 11
    private static let track: CGFloat = 3

    init(
        min lower: Double, max upper: Double, read: @escaping () -> Double,
        write: @escaping (Double) -> Void, begin: @escaping () -> Void,
        end: @escaping () -> Void, enabled: @escaping () -> Bool
    ) {
        self.lower = lower
        self.upper = Swift.max(upper, lower + 0.000_001)
        self.read = read
        self.write = write
        self.begin = begin
        self.end = end
        self.enabled = enabled
        super.init(frame: .zero)
        wantsLayer = true
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSliderControl does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DS.controlHeight)
    }

    func refresh() {
        isActive = enabled()
        alphaValue = isActive ? 1 : 0.42
        needsDisplay = true
    }

    private var fraction: CGFloat {
        let value = Swift.min(Swift.max(read(), lower), upper)
        return CGFloat((value - lower) / (upper - lower))
    }

    private func value(atX x: CGFloat) -> Double {
        let inset = Self.knob / 2
        let span = Swift.max(bounds.width - Self.knob, 1)
        let t = Swift.min(Swift.max((x - inset) / span, 0), 1)
        return lower + Double(t) * (upper - lower)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        dragging = true
        begin()
        write(value(atX: convert(event.locationInWindow, from: nil).x))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        write(value(atX: convert(event.locationInWindow, from: nil).x))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        // Ends the gesture even when the value never moved: the document
        // registers no undo step for an unchanged handle, so this is free.
        end()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let inset = Self.knob / 2
        let mid = bounds.midY
        let rail = NSRect(
            x: inset, y: mid - Self.track / 2, width: max(bounds.width - Self.knob, 1),
            height: Self.track)
        let railPath = NSBezierPath(roundedRect: rail, xRadius: 1.5, yRadius: 1.5)
        DS.border.setFill()
        railPath.fill()

        let filled = NSRect(
            x: rail.minX, y: rail.minY, width: rail.width * fraction, height: rail.height)
        DS.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 1.5, yRadius: 1.5).fill()

        let center = rail.minX + rail.width * fraction
        let knob = NSRect(
            x: center - Self.knob / 2, y: mid - Self.knob / 2,
            width: Self.knob, height: Self.knob)
        let knobPath = NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5))
        NSColor.controlBackgroundColor.setFill()
        knobPath.fill()
        (dragging ? DS.accent : DS.borderStrong).setStroke()
        knobPath.stroke()
    }
}

// MARK: - Multi-line text

/// The Text tab's content editor: an `NSTextView` that commits on blur (and
/// on ⌘Return), because a text clip's content is typed, not dialled. The
/// `refresh()` is skipped while it holds first responder, or every keystroke
/// would be overwritten by the value it just wrote.
final class InspectorTextArea: NSView, OptionControl, NSTextViewDelegate {
    private let read: () -> String
    private let write: (String) -> Void
    private let enabled: () -> Bool
    private let onEdit: () -> Void
    private let textView = NSTextView()
    private let scroll = NSScrollView()

    init(
        read: @escaping () -> String, write: @escaping (String) -> Void,
        enabled: @escaping () -> Bool, onEdit: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.enabled = enabled
        self.onEdit = onEdit
        super.init(frame: .zero)
        wantsLayer = true
        textView.isRichText = false
        textView.font = DS.sans(12)
        textView.textColor = DS.textStrong
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = DS.controlRadius
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = DS.border.cgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 72),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTextArea does not support NSCoder")
    }

    func refresh() {
        let active = enabled()
        alphaValue = active ? 1 : 0.42
        textView.isEditable = active
        textView.isSelectable = active
        guard window?.firstResponder !== textView else { return }
        let value = read()
        if textView.string != value { textView.string = value }
    }

    private func commit() {
        let value = textView.string
        guard value != read() else { return }
        write(value)
        onEdit()
    }

    func textDidEndEditing(_ notification: Notification) {
        commit()
    }

    /// ⌘Return commits without leaving the field — the same bargain the
    /// canvas's inline text session makes (PreviewCanvasView).
    func textView(
        _ view: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              NSApp.currentEvent?.modifierFlags.contains(.command) == true
        else { return false }
        commit()
        return true
    }
}

// MARK: - Sections

/// One disclosure group: a header with the title, an optional reset-to-default
/// button, and the rows. Collapsed state is per section id in `UserDefaults`,
/// so a pane rebuilt after every edit does not keep re-opening a group the
/// user closed.
final class InspectorSection: NSView {
    /// `UserDefaults` key prefix; the suffix is the section's stable id.
    static let collapsedKeyPrefix = "ReelcutInspectorSection."

    private let id: String
    private let header = InspectorSectionHeader()
    private let content = NSStackView()
    private(set) var isExpanded = true

    init(
        id: String, title: String, note: (() -> String?)? = nil,
        reset: (() -> Void)? = nil, rows: [NSView]
    ) {
        self.id = id
        super.init(frame: .zero)
        let key = Self.collapsedKeyPrefix + id
        isExpanded = !UserDefaults.standard.bool(forKey: key)

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = InspectorMetrics.rowSpacing
        content.edgeInsets = NSEdgeInsets(
            top: 2, left: InspectorMetrics.inset, bottom: 8, right: InspectorMetrics.inset)
        if let note = note {
            addRow(InspectorNoteLabel(note: note))
        }
        for row in rows { addRow(row) }

        header.configure(title: title, reset: reset)
        header.onToggle = { [weak self] in self?.toggle() }

        let stack = NSStackView(views: [header, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        content.isHidden = !isExpanded
        header.isExpanded = isExpanded
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSection does not support NSCoder")
    }

    private func addRow(_ row: NSView) {
        content.addArrangedSubview(row)
        row.widthAnchor.constraint(
            equalTo: content.widthAnchor, constant: -2 * InspectorMetrics.inset).isActive = true
    }

    private func toggle() {
        isExpanded.toggle()
        content.isHidden = !isExpanded
        header.isExpanded = isExpanded
        UserDefaults.standard.set(!isExpanded, forKey: Self.collapsedKeyPrefix + id)
    }

    func refresh() {
        refreshOptionControls(in: content)
    }
}

/// The section header: disclosure triangle, title in the micro-label face,
/// and the reset button pinned to the trailing edge. The button is a subview
/// so it eats its own clicks — everything else toggles the group.
final class InspectorSectionHeader: NSView {
    var onToggle: (() -> Void)?
    var isExpanded = true {
        didSet { needsDisplay = true }
    }
    private var title = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorSectionHeader does not support NSCoder")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: InspectorMetrics.headerHeight)
    }

    func configure(title: String, reset: (() -> Void)?) {
        self.title = title
        guard let reset = reset else { return }
        let button = OptionButtonControl(
            title: "Reset", action: reset, enabled: { true }, onEdit: {})
        button.toolTip = "Reset this section to its defaults"
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -InspectorMetrics.inset),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.hoverFill.withAlphaComponent(0.35).setFill()
        bounds.fill()
        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let glyph = isExpanded ? "chevron.down" : "chevron.right"
        let box = NSRect(x: InspectorMetrics.inset, y: bounds.midY - 5, width: 10, height: 10)
        if let icon = NSImage(systemSymbolName: glyph, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        {
            let tinted = icon.tinted(with: DS.textMuted)
            let size = tinted.size
            tinted.draw(
                in: NSRect(
                    x: box.minX, y: box.midY - size.height / 2, width: size.width,
                    height: size.height))
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: DS.sans(9), .foregroundColor: DS.textMuted,
            ]
            (isExpanded ? "▾" : "▸").draw(
                at: NSPoint(x: box.minX, y: box.minY), withAttributes: attributes)
        }

        let label = DS.microLabel(title, size: 10)
        label.draw(at: NSPoint(x: box.maxX + 6, y: bounds.midY - label.size().height / 2))
    }
}

// MARK: - Row builders

/// One labelled row: the leading label column, then the controls, then the
/// mixed badge when the selection disagrees. Every pane builds rows through
/// here so the label column lines up down the whole inspector.
func inspectorRow(
    _ label: String?, _ controls: [NSView], mixed: (() -> Bool)? = nil
) -> NSView {
    var views: [NSView] = []
    if let label = label {
        let field = InspectorRowLabel(label)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: InspectorMetrics.labelWidth).isActive = true
        views.append(field)
    }
    views.append(contentsOf: controls)
    if let mixed = mixed { views.append(InspectorMixedBadge(mixed: mixed)) }
    // A slider is the row's stretchy element, so a row that has one gets NO
    // trailing spacer — two views hugging at the same priority would split
    // the free space and leave the slider half as wide as it should be.
    if !controls.contains(where: { $0 is InspectorSliderControl }) {
        let trailing = NSView()
        trailing.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        trailing.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        views.append(trailing)
    }

    let row = NSStackView(views: views)
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    return row
}

/// A row of buttons with no label column — "Fit to Canvas / Fill Canvas",
/// the text presets, the Add Action footer.
func inspectorButtonRow(_ buttons: [NSView]) -> NSView {
    let trailing = NSView()
    trailing.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    let row = NSStackView(views: buttons + [trailing])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    return row
}

/// A read-only value at the end of a row ("−6.0 dB", "00:00:04:12").
func inspectorReadout(width: CGFloat = 96, _ read: @escaping () -> String) -> OptionDisplayControl {
    OptionDisplayControl(width: width, read: read, enabled: { true })
}

/// A number bound to one property: a slider that drags LIVE beside a field
/// that commits once (spec §4.3). `ops` turns a value into the edit — the
/// binding decides whether that is a `set_video` or an action's end patch, so
/// no pane repeats that rule.
func inspectorValueRow(
    _ label: String, _ binding: InspectorBinding, name: String, unit: String = "",
    decimals: Int = 0, min lower: Double, max upper: Double, quick: [Double] = [],
    slider: Bool = true, width: CGFloat = InspectorMetrics.fieldWidth,
    read: @escaping () -> Double, ops: @escaping (Double) -> [ReelOp],
    mixed: (() -> Bool)? = nil, enabled: @escaping () -> Bool = { true }
) -> NSView {
    var controls: [NSView] = []
    if slider {
        controls.append(
            InspectorSliderControl(
                min: lower, max: upper, read: read,
                write: { [weak binding] value in binding?.liveUpdate(ops(value)) },
                begin: { [weak binding] in binding?.liveBegin() },
                end: { [weak binding] in binding?.liveEnd(name) },
                enabled: enabled))
    }
    controls.append(
        OptionFieldControl(
            width: width, unit: unit, decimals: decimals, min: lower, max: upper, quick: quick,
            read: read,
            write: { [weak binding] value in binding?.apply(name, ops(value)) },
            enabled: enabled,
            onEdit: { [weak binding] in binding?.edited() }))
    return inspectorRow(label, controls, mixed: mixed)
}

/// A boolean bound to one property. The checkbox carries its own label, so
/// the row's label column stays empty and the controls line up under the
/// numbers above them.
func inspectorCheckRow(
    _ label: String, _ binding: InspectorBinding, name: String, read: @escaping () -> Bool,
    ops: @escaping (Bool) -> [ReelOp], mixed: (() -> Bool)? = nil,
    enabled: @escaping () -> Bool = { true }
) -> NSView {
    let check = OptionCheckboxControl(
        label: label, read: read,
        write: { [weak binding] value in binding?.apply(name, ops(value)) },
        enabled: enabled,
        onEdit: { [weak binding] in binding?.edited() })
    return inspectorRow(nil, [check], mixed: mixed)
}

/// A colour well bound to one property, with the unchanged-colour guard the
/// continuous colour panel needs (`changedRGBA`).
func inspectorColorRow(
    _ label: String, _ binding: InspectorBinding, name: String, read: @escaping () -> RGBA,
    ops: @escaping (RGBA) -> [ReelOp], mixed: (() -> Bool)? = nil,
    enabled: @escaping () -> Bool = { true }
) -> NSView {
    let swatch = OptionSwatchControl(
        read: { read().nsColor },
        write: { [weak binding] color in
            guard let next = changedRGBA(color, from: read()) else { return }
            binding?.apply(name, ops(next))
        },
        enabled: enabled,
        onEdit: {})
    return inspectorRow(label, [swatch], mixed: mixed)
}

/// A popup bound to one property.
func inspectorPopupRow(
    _ label: String, _ binding: InspectorBinding, name: String, items: [String],
    width: CGFloat = InspectorMetrics.popupWidth, read: @escaping () -> Int,
    ops: @escaping (Int) -> [ReelOp], mixed: (() -> Bool)? = nil,
    enabled: @escaping () -> Bool = { true }
) -> NSView {
    let popup = OptionPopupControl(
        width: width, items: items, read: read,
        write: { [weak binding] index in binding?.apply(name, ops(index)) },
        enabled: enabled,
        onEdit: { [weak binding] in binding?.edited() })
    return inspectorRow(label, [popup], mixed: mixed)
}

/// A button that runs one edit.
func inspectorButton(
    _ title: String, _ binding: InspectorBinding, name: String,
    ops: @escaping () -> [ReelOp], enabled: @escaping () -> Bool = { true }
) -> OptionButtonControl {
    OptionButtonControl(
        title: title, action: { [weak binding] in binding?.apply(name, ops()) },
        enabled: enabled, onEdit: {})
}

/// The Shadow group, shared by the Video, Text and Shape panes because all
/// three write the SAME field — `video.shadow` (§4.3 lists it once under
/// Video and refers to it from the other two).
///
/// Every control writes a WHOLE `ShadowProps`: the patch replaces the object,
/// so each edit re-sends the other four values as they stand.
func inspectorShadowSection(_ binding: InspectorBinding) -> InspectorSection {
    func current() -> ShadowProps { binding.videoProps.shadow ?? ShadowProps() }
    func ops(_ next: ShadowProps) -> [ReelOp] { binding.ops(video: VideoPatch(shadow: .some(next))) }
    func on() -> Bool { binding.videoProps.shadow != nil }

    let toggle = inspectorCheckRow(
        "Drop shadow", binding, name: "Shadow",
        read: on,
        ops: { value in
            binding.ops(video: VideoPatch(shadow: value ? .some(ShadowProps()) : .some(nil)))
        },
        mixed: { binding.mixedVideo { $0.shadow != nil } })

    return InspectorSection(
        id: "video.shadow", title: "Shadow",
        reset: { binding.apply("Shadow", video: VideoPatch(shadow: .some(nil))) },
        rows: [
            toggle,
            inspectorColorRow(
                "Color", binding, name: "Shadow Color", read: { current().color },
                ops: { color in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: color, opacity: s.opacity, blur: s.blur, angle: s.angle,
                            distance: s.distance))
                },
                enabled: on),
            inspectorValueRow(
                "Opacity", binding, name: "Shadow Opacity", unit: "%", decimals: 0, min: 0,
                max: 100, quick: [0, 25, 50, 75, 100],
                read: { current().opacity * 100 },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: value / 100, blur: s.blur, angle: s.angle,
                            distance: s.distance))
                },
                enabled: on),
            inspectorValueRow(
                "Blur", binding, name: "Shadow Blur", unit: " px", decimals: 0, min: 0, max: 200,
                quick: [0, 4, 8, 12, 24, 48],
                read: { current().blur },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: s.opacity, blur: value, angle: s.angle,
                            distance: s.distance))
                },
                enabled: on),
            inspectorValueRow(
                "Angle", binding, name: "Shadow Angle", unit: "°", decimals: 0, min: 0, max: 360,
                quick: [0, 45, 90, 135, 180, 225, 270, 315],
                read: { current().angle },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: s.opacity, blur: s.blur, angle: value,
                            distance: s.distance))
                },
                enabled: on),
            inspectorValueRow(
                "Distance", binding, name: "Shadow Distance", unit: " px", decimals: 0, min: 0,
                max: 200, quick: [0, 4, 8, 16, 32],
                read: { current().distance },
                ops: { value in
                    let s = current()
                    return ops(
                        ShadowProps(
                            color: s.color, opacity: s.opacity, blur: s.blur, angle: s.angle,
                            distance: value))
                },
                enabled: on),
        ])
}

/// The colour as the model's RGBA, or nil when it already matches `current`.
///
/// **Pitfall:** the shared colour panel is continuous, so a drag inside it
/// calls a swatch's writer on every mouse-moved event — including with the
/// colour it already has. Without this guard the document would answer an
/// unchanged edit with a refusal beep on every one of them.
func changedRGBA(_ color: NSColor, from current: RGBA) -> RGBA? {
    let next = color.rgbaComponents
    guard next.count == current.count else { return next }
    for (a, b) in zip(next, current) where abs(a - b) > 0.001 { return next }
    return nil
}

// MARK: - Binding

/// Reading and writing the selection's properties (spec §4.3). Created once
/// by `InspectorViewController` and handed to every pane; `invalidate()` at
/// the start of each refresh drops the evaluated-state cache so a moved
/// playhead is never read stale.
final class InspectorBinding {
    private weak var inspector: InspectorViewController?

    /// Evaluated props per clip, filled lazily. Only clips the playhead is
    /// inside an action of ever reach the FFI; everything else reads its base
    /// props straight off the snapshot.
    private struct Evaluated {
        var video: VideoProps?
        var audio: AudioProps?
        var text: TextProps?
    }
    private var cache: [UInt32: Evaluated] = [:]

    init(inspector: InspectorViewController) {
        self.inspector = inspector
    }

    // MARK: Model access

    var document: ProjectDocument? { inspector?.document }
    var project: ReelProject? { document?.project }
    var snapshot: ProjectSnapshot { project?.snapshot ?? .empty }
    var canvas: CanvasSnapshot { snapshot.canvas }
    var playhead: Ticks { document?.playhead ?? 0 }
    var clips: [ClipSnapshot] { inspector?.selectedClips ?? [] }
    var ids: [UInt32] { clips.map { $0.id } }
    var primary: ClipSnapshot? { clips.first }
    var isEmpty: Bool { clips.isEmpty }
    var isSingle: Bool { clips.count == 1 }

    /// The selected clips each property group actually applies to. A mixed
    /// selection is normal — a video clip and a text clip picked together —
    /// and sending `set_text` to the video one would be an error at the FFI,
    /// so every read, mixed test and op below works from these lists rather
    /// than from the raw selection.
    var videoClips: [ClipSnapshot] { clips.filter { InspectorTab.hasPixels($0, in: snapshot) } }
    var audioClips: [ClipSnapshot] { clips.filter { InspectorTab.hasAudio($0, in: snapshot) } }
    var textClips: [ClipSnapshot] {
        clips.filter { clip in
            if case .text = clip.source { return true }
            return false
        }
    }
    var shapeClips: [ClipSnapshot] {
        clips.filter { clip in
            if case .shape = clip.source { return true }
            return false
        }
    }

    func invalidate() {
        cache.removeAll(keepingCapacity: true)
    }

    // MARK: Actions

    /// The action of `clip` the playhead is inside, if any. `start` is CLIP
    /// time (§5.4), so the playhead is converted before the test.
    func action(_ clip: ClipSnapshot) -> ActionSnapshot? {
        guard clip.contains(playhead) else { return nil }
        let t = clip.clipTime(playhead)
        return clip.actions.first { t >= $0.start && t < $0.endTime }
    }

    /// True when at least one selected clip would have its edit land on an
    /// action's end patch instead of its base props.
    var editsAction: Bool {
        clips.contains { action($0) != nil }
    }

    /// The line a Video/Audio/Text section header carries while the playhead
    /// is inside an action (§4.3).
    var actionNote: String? {
        guard editsAction else { return nil }
        if let clip = primary, clips.count == 1, let action = action(clip) {
            let index = (clip.actions.firstIndex { $0.id == action.id }) ?? 0
            return "Editing action \(index + 1)'s end state"
        }
        return "Editing the end state of the actions under the playhead"
    }

    // MARK: Evaluated reads

    private func evaluated(_ clip: ClipSnapshot) -> Evaluated {
        if let cached = cache[clip.id] { return cached }
        var state = Evaluated()
        if action(clip) != nil, let raw = project?.clipState(clip.id, at: playhead) {
            state.video = InspectorBinding.decode(VideoProps.self, raw["video"])
            state.audio = InspectorBinding.decode(AudioProps.self, raw["audio"])
            state.text = InspectorBinding.decode(TextProps.self, raw["text"])
        }
        cache[clip.id] = state
        return state
    }

    /// One property group of `rc_project_clip_state`'s untyped reply, decoded
    /// through the same lenient path as the project itself.
    private static func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
        guard let object = value, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return ReelJSON.decode(type, from: text)
    }

    func video(_ clip: ClipSnapshot) -> VideoProps { evaluated(clip).video ?? clip.videoProps }
    func audio(_ clip: ClipSnapshot) -> AudioProps { evaluated(clip).audio ?? clip.audioProps }
    func text(_ clip: ClipSnapshot) -> TextProps { evaluated(clip).text ?? clip.text ?? TextProps() }
    /// Shapes are not animatable (§5.4's patch covers video, audio and text),
    /// so this is always the base description.
    func shape(_ clip: ClipSnapshot) -> ShapeProps { clip.shape ?? ShapeProps() }

    /// The values the fields show: the FIRST applicable clip's, evaluated.
    var videoProps: VideoProps { videoClips.first.map { video($0) } ?? .identity }
    var audioProps: AudioProps { audioClips.first.map { audio($0) } ?? AudioProps() }
    var textProps: TextProps { textClips.first.map { text($0) } ?? TextProps() }
    var shapeProps: ShapeProps { shapeClips.first.map { shape($0) } ?? ShapeProps() }

    // MARK: Mixed tests

    /// Whether a list of clips disagrees about one value.
    func mixed<T: Equatable>(_ clips: [ClipSnapshot], _ read: (ClipSnapshot) -> T) -> Bool {
        guard let first = clips.first.map(read) else { return false }
        return clips.dropFirst().contains { read($0) != first }
    }

    /// Whether the whole selection disagrees — for clip-level values (speed).
    func mixed<T: Equatable>(_ read: (ClipSnapshot) -> T) -> Bool {
        mixed(clips, read)
    }

    func mixedVideo<T: Equatable>(_ read: @escaping (VideoProps) -> T) -> Bool {
        mixed(videoClips) { read(video($0)) }
    }

    func mixedAudio<T: Equatable>(_ read: @escaping (AudioProps) -> T) -> Bool {
        mixed(audioClips) { read(audio($0)) }
    }

    func mixedText<T: Equatable>(_ read: @escaping (TextProps) -> T) -> Bool {
        mixed(textClips) { read(text($0)) }
    }

    func mixedShape<T: Equatable>(_ read: @escaping (ShapeProps) -> T) -> Bool {
        mixed(shapeClips) { read(shape($0)) }
    }

    // MARK: Writes

    /// One clip's ops for a video patch: the action's end state when the
    /// playhead is inside one, the base props otherwise.
    func ops(video patch: VideoPatch, for clip: ClipSnapshot) -> [ReelOp] {
        guard !patch.isEmpty else { return [] }
        if let action = action(clip) {
            return [
                .setActionEnd(clip: clip.id, action: action.id, patch: ActionPatch(video: patch))
            ]
        }
        return [.setVideo(clips: [clip.id], patch: patch)]
    }

    /// The selection's ops for a video patch. Clips outside an action share
    /// ONE `set_video` with several ids (§4.3); the ones inside get their own
    /// `set_action_end`.
    func ops(video patch: VideoPatch) -> [ReelOp] {
        split(
            videoClips, patch.isEmpty, base: { .setVideo(clips: $0, patch: patch) },
            action: { ActionPatch(video: patch) })
    }

    func ops(audio patch: AudioPatch) -> [ReelOp] {
        split(
            audioClips, patch.isEmpty, base: { .setAudio(clips: $0, patch: patch) },
            action: { ActionPatch(audio: patch) })
    }

    func ops(text patch: TextPatch) -> [ReelOp] {
        split(
            textClips, patch.isEmpty, base: { .setText(clips: $0, patch: patch) },
            action: { ActionPatch(text: patch) })
    }

    /// Shapes have no action form (§5.4's patch covers video, audio and text),
    /// so this is always one `set_shape` over every selected shape clip.
    func ops(shape patch: ShapePatch) -> [ReelOp] {
        let ids = shapeClips.map { $0.id }
        guard !patch.isEmpty, !ids.isEmpty else { return [] }
        return [.setShape(clips: ids, patch: patch)]
    }

    /// The shared rule: clips outside an action share ONE op with several ids
    /// (§4.3's "one op with several clip ids"); each clip the playhead is
    /// inside an action of gets its own `set_action_end` instead.
    private func split(
        _ clips: [ClipSnapshot], _ isEmpty: Bool, base: ([UInt32]) -> ReelOp,
        action patch: () -> ActionPatch
    ) -> [ReelOp] {
        guard !isEmpty, !clips.isEmpty else { return [] }
        var ops: [ReelOp] = []
        var ids: [UInt32] = []
        for clip in clips {
            if let inside = action(clip) {
                ops.append(.setActionEnd(clip: clip.id, action: inside.id, patch: patch()))
            } else {
                ids.append(clip.id)
            }
        }
        if !ids.isEmpty { ops.insert(base(ids), at: 0) }
        return ops
    }

    // MARK: Commits

    func apply(_ name: String, _ ops: [ReelOp]) {
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        inspector?.onEdit?(name, ops)
    }

    func apply(_ name: String, video patch: VideoPatch) { apply(name, ops(video: patch)) }
    func apply(_ name: String, audio patch: AudioPatch) { apply(name, ops(audio: patch)) }
    func apply(_ name: String, text patch: TextPatch) { apply(name, ops(text: patch)) }
    func apply(_ name: String, shape patch: ShapePatch) { apply(name, ops(shape: patch)) }

    /// Off-event commits (a sheet's completion, an alert's answer) — the
    /// grouped entry point is mandatory there (app/CLAUDE.md's undo pitfall).
    func applyGrouped(_ name: String, _ ops: [ReelOp]) {
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        inspector?.onGroupedEdit?(name, ops)
    }

    // MARK: Live gestures

    func liveBegin() { inspector?.onLiveBegin?() }
    func liveUpdate(_ ops: [ReelOp]) {
        guard !ops.isEmpty else { return }
        inspector?.onLiveUpdate?(ops)
    }
    func liveEnd(_ name: String) { inspector?.onLiveEnd?(name) }

    /// The refresh a control asks for after it writes, so the readouts and
    /// dependent fields in the same section catch up.
    func edited() { inspector?.refresh(isLive: false) }
}

// MARK: - Pane

/// What the inspector hosts in its scroll view. A pane is rebuilt only when
/// the SHAPE of the model changes (`structureSignature`) and refreshed on
/// every other document change — rebuilding on each edit would tear down the
/// control under the user's cursor.
protocol InspectorPane: NSView {
    var tab: InspectorTab { get }
    var structureSignature: String { get }
    func rebuild()
    func refresh()
}

/// The base every pane subclasses: a vertical stack of `InspectorSection`s
/// plus the empty-state label. Subclasses override `makeSections()` and, when
/// their row set depends on the model (the actions table, the media list, the
/// markers list), `structureSignature`.
class InspectorPaneView: NSView, InspectorPane {
    let binding: InspectorBinding
    weak var inspector: InspectorViewController?
    private let stack = NSStackView()
    private var sections: [InspectorSection] = []
    /// The previous build's views, held one generation past their removal —
    /// see the pitfall in `rebuild()`.
    private var retired: [NSView] = []

    init(inspector: InspectorViewController) {
        self.inspector = inspector
        self.binding = inspector.binding
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = InspectorMetrics.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // The pane is a scroll-view document view: the clip view fixes its
        // width, and nothing fixes its height — so the content has to. The
        // bottom pin is a `<=` at full strength plus an `==` at low priority,
        // which resolves to "as tall as the sections, but never shorter than
        // the visible area" once `InspectorViewController` adds its own
        // minimum (a pane that stopped at its content would leave the Media
        // tab's Finder-drop target the size of its rows).
        let hug = stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        hug.priority = .defaultLow
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            hug,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorPaneView does not support NSCoder")
    }

    // MARK: Subclass hooks

    var tab: InspectorTab { .video }

    /// The sections, in order. Called on every rebuild.
    func makeSections() -> [InspectorSection] { [] }

    /// What the pane says when it has nothing to show; nil means "never
    /// empty" (Media and Document).
    var emptyMessage: String? { "Select a clip to edit its properties." }

    /// The model facts that change the pane's LAYOUT rather than its values.
    /// The default covers the selection and the action under the playhead;
    /// panes with tables extend it.
    var structureSignature: String {
        let clips = binding.clips.map { clip -> String in
            let action = binding.action(clip).map { String($0.id) } ?? "-"
            return "\(clip.id):\(clip.source.kindName):\(action)"
        }
        return clips.joined(separator: ",")
    }

    // MARK: Building

    func rebuild() {
        sections = []
        // **Pitfall:** a rebuild often runs INSIDE a control's own event
        // handler — a button's `action()` applies the edit, the document
        // posts, and the pane rebuilds before that handler returns. Keeping
        // one generation of removed views alive means the control that
        // started it all is still there when its method returns.
        // `removeFromSuperview` also un-arranges it; `removeArrangedSubview`
        // alone would leave the view drawn on top of the new ones.
        retired = stack.arrangedSubviews
        for view in retired { view.removeFromSuperview() }
        if binding.isEmpty, let message = emptyMessage {
            let placeholder = InspectorPaneView.emptyRow(message)
            stack.addArrangedSubview(placeholder)
            placeholder.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return
        }
        for section in makeSections() {
            sections.append(section)
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    /// The centred "nothing selected" line, built fresh each time so its
    /// constraints go away with the build that made it.
    private static func emptyRow(_ message: String) -> NSView {
        let box = NSView()
        let label = InspectorRowLabel(message)
        label.alignment = .center
        label.textColor = DS.textFaint
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 28),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -28),
            label.leadingAnchor.constraint(
                equalTo: box.leadingAnchor, constant: InspectorMetrics.inset),
            label.trailingAnchor.constraint(
                equalTo: box.trailingAnchor, constant: -InspectorMetrics.inset),
        ])
        return box
    }

    func refresh() {
        for section in sections { section.refresh() }
    }
}
