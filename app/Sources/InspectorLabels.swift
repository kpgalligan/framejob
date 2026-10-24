import AppKit

// Moved verbatim from InspectorPane.swift by speed ramps SR5-0, a pure move
// (designs/adr/app-file-history.md, InspectorPane's named next cut).

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

/// An editable TIMECODE — the Clip tab's In and Out. `OptionFieldControl` is
/// a number with a unit and would spell 4.5 seconds "4.50 s"; a clip's edges
/// are read against the ruler, so they are spelled the way the ruler and the
/// toolbar spell them.
///
/// Parsing is the core's (`ReelTime.parse`), so `1:23`, `83.5` and `1:23:04`
/// mean here what they mean in the toolbar's field — and, exactly as there,
/// text it refuses beeps and the field snaps back rather than committing a
/// guess. A trim the CORE refuses beeps too, from `applyEdit`; nothing here
/// clamps a value into range on the user's behalf.
final class InspectorTimecodeField: NSTextField, OptionControl, NSTextFieldDelegate {
    private let read: () -> Ticks
    private let write: (Ticks) -> Void
    private let fps: () -> Fps
    private let frames: () -> Bool
    private let onEdit: () -> Void

    init(
        read: @escaping () -> Ticks, write: @escaping (Ticks) -> Void,
        fps: @escaping () -> Fps, frames: @escaping () -> Bool,
        onEdit: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.fps = fps
        self.frames = frames
        self.onEdit = onEdit
        super.init(frame: .zero)
        DSField.style(self, height: DS.controlHeight, radius: DS.controlRadius, font: DS.mono(11))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 104).isActive = true
        delegate = self
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTimecodeField does not support NSCoder")
    }

    private var formatted: String {
        ReelTime.format(read(), fps: fps(), frames: frames())
    }

    func refresh() {
        // Skipped while the field is being typed into, or the value it is
        // about to commit would be overwritten by the one it replaces.
        guard currentEditor() == nil else { return }
        let value = formatted
        if stringValue != value { stringValue = value }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard stringValue != formatted else { return }
        guard let ticks = ReelTime.parse(stringValue, fps: fps()) else {
            NSSound.beep()
            // Set directly rather than through `refresh()`: the field editor
            // may still be attached here, and `refresh()` would defer to it.
            stringValue = formatted
            return
        }
        write(ReelTime.snapToFrame(ticks, fps: fps()))
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
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
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
