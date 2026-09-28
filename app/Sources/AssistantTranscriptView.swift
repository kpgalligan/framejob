import AppKit

/// The Assistant tab's transcript, as the document view of its own scroll
/// view: one wrapping, selectable label per `AssistantEntry`, top-down, and
/// scrolled to the newest entry whenever one is appended or extended. It
/// draws the transcript it is handed and keeps none of it (spec §11 AI-4:
/// the entries are `EditorViewController.assistantTranscript`'s). Road map
/// 12 A2.
final class AssistantTranscriptView: NSView {
    private static let inset: CGFloat = 10
    private let stack = NSStackView()
    private var labels: [NSTextField] = []

    init() {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: Self.inset, bottom: 10, right: Self.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantTranscriptView does not support NSCoder")
    }

    /// Top-down, so the first entry is at y = 0 whatever the height is.
    override var isFlipped: Bool { true }

    /// A wrapping label needs its width to know its height
    /// (`InspectorRefusalStrip`'s pattern).
    override func layout() {
        super.layout()
        let width = max(bounds.width - 2 * Self.inset, 0)
        var changed = false
        for label in labels where label.preferredMaxLayoutWidth != width {
            label.preferredMaxLayoutWidth = width
            changed = true
        }
        if changed { super.layout() }
    }

    // MARK: - Drawing the transcript

    func reload(_ entries: [AssistantEntry]) {
        for label in labels { label.removeFromSuperview() }
        labels = []
        for entry in entries { add(entry) }
        scrollToNewest()
    }

    func apply(_ change: AssistantTranscriptChange) {
        switch change {
        case .appended(let entry):
            add(entry)
            scrollToNewest()
        case .extended(let index, let text):
            guard labels.indices.contains(index) else { return }
            labels[index].stringValue = text
            scrollToNewest()
        case .cleared:
            reload([])
        case .usage:
            break
        }
    }

    private func add(_ entry: AssistantEntry) {
        let label = NSTextField(wrappingLabelWithString: entry.text)
        label.isSelectable = true
        label.setAccessibilityIdentifier("assistant.entry.\(entry.kind.rawValue)")
        switch entry.kind {
        case .person:
            label.font = DS.sans(12, weight: .semibold)
            label.textColor = DS.textStrong
        case .reply:
            label.font = DS.sans(12)
            label.textColor = DS.textStrong
        case .progress:
            label.font = DS.sans(11)
            label.textColor = DS.textFaint
        case .meta:
            label.font = DS.mono(10)
            label.textColor = DS.textMuted
        case .error:
            label.font = DS.sans(11)
            label.textColor = DS.meterClip
        }
        label.preferredMaxLayoutWidth = max(bounds.width - 2 * Self.inset, 0)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        // The person's line opens a new exchange: a wider gap above it.
        if entry.kind == .person, let previous = labels.last {
            stack.setCustomSpacing(14, after: previous)
        }
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(
            equalTo: stack.widthAnchor, constant: -2 * Self.inset
        ).isActive = true
        labels.append(label)
    }

    /// The newest entry into view. The document is flipped, so the end is its
    /// full height less what the clip view shows.
    private func scrollToNewest() {
        guard let scroll = enclosingScrollView else { return }
        scroll.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let y = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(clip)
    }
}
