import AppKit

/// The inspector's foot (spec §11 CI-10): "Refused: " and the rule's own
/// sentence, VERBATIM, when the core refused a person's edit.
/// `ProjectDocument.applyEdit` has already beeped; this is the one thing a
/// person sees that an identity does not show them.
///
/// It lasts until the PROJECT changes — `clearIfStale` runs at the top of
/// every inspector refresh and clears it once `editedProject` is another
/// handle, which is an applied edit, an undo, a redo or a scope change — or
/// until it is clicked. A playhead or selection move keeps the same handle,
/// so it keeps the strip. Hidden, it is detached from the foot's stack, so
/// it takes no room.
final class InspectorRefusalStrip: NSView {
    private(set) var text: String?
    /// The handle the refusal was shown under. Weak: a handle nothing else
    /// holds is one the project has moved away from, and nil is not it.
    private weak var project: ReelProject?
    private let label = NSTextField(wrappingLabelWithString: "")
    /// Its width pinned to the foot's, made on a show: hidden, the strip is
    /// detached from the foot's stack, and a constraint made once in
    /// `loadView` need not survive that.
    private var spanning: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        label.font = DS.sans(11)
        label.textColor = DS.textStrong
        label.isSelectable = false
        label.maximumNumberOfLines = 3
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: InspectorMetrics.inset),
            label.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -InspectorMetrics.inset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorRefusalStrip does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    /// A wrapping label needs its width to know its height.
    override func layout() {
        super.layout()
        let width = max(bounds.width - 2 * InspectorMetrics.inset, 0)
        guard label.preferredMaxLayoutWidth != width else { return }
        label.preferredMaxLayoutWidth = width
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.hoverFill.setFill()
        bounds.fill()
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    func show(_ refusal: ReelRefusal, under project: ReelProject?) {
        let sentence = "Refused: " + refusal.reason
        text = sentence
        self.project = project
        label.stringValue = sentence
        toolTip = sentence
        isHidden = false
        needsDisplay = true
    }

    /// Clears once the project is not the handle the refusal was shown under.
    func clearIfStale(_ project: ReelProject?) {
        guard text != nil, project !== self.project else { return }
        clear()
    }

    func clear() {
        guard text != nil else { return }
        text = nil
        project = nil
        label.stringValue = ""
        toolTip = nil
        isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        clear()
    }

    /// Pins the strip to `container`'s width unless that pin is still active.
    func span(_ container: NSView) {
        guard spanning?.isActive != true, isDescendant(of: container) else { return }
        spanning = widthAnchor.constraint(equalTo: container.widthAnchor)
        spanning?.isActive = true
    }
}

extension InspectorViewController {
    /// The editor's forward of `projectDocumentDidRefuse`.
    func showRefusal(_ refusal: ReelRefusal) {
        guard isViewLoaded else { return }
        refusalStrip.show(refusal, under: document?.editedProject)
        refusalStrip.span(footContainer)
    }
}
