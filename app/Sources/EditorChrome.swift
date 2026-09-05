import AppKit

// MARK: - BarView

/// A chrome bar: the window background with a 1px hairline on one edge.
/// Reelcut's toolbar row (spec §3, 44 pt) and, later, the timeline's own
/// toolbar row are both this. Copied from Rasterize's `EditorChrome.swift` —
/// keep them in sync rather than forking.
final class BarView: NSView {
    enum Border {
        case top
        case bottom
        case none
    }

    private let border: Border

    init(border: Border) {
        self.border = border
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BarView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DS.chromeBackground.setFill()
        bounds.fill()
        DS.border.setFill()
        switch border {
        case .top:
            NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        case .bottom:
            NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        case .none:
            break
        }
    }
}

// MARK: - SafeGuidesView

/// The toolbar's Safe toggle (spec §4.1): the 90 % title-safe and 80 %
/// action-safe rectangles, drawn over the preview.
///
/// It is sized to the VIDEO rectangle by `EditorViewController.layoutCanvas`,
/// not to the pane, so the percentages are of the canvas and not of whatever
/// letterboxing is around it. Hit-transparent: the canvas overlay a later
/// stage puts here has to receive every click.
final class SafeGuidesView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SafeGuidesView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 2, bounds.height > 2 else { return }
        let rings: [(fraction: CGFloat, alpha: CGFloat)] = [(0.9, 0.85), (0.8, 0.55)]
        for (fraction, alpha) in rings {
            let inset = NSRect(
                x: bounds.width * (1 - fraction) / 2,
                y: bounds.height * (1 - fraction) / 2,
                width: bounds.width * fraction,
                height: bounds.height * fraction)
            let path = NSBezierPath(rect: inset.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            DS.marquee.withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
    }
}

// MARK: - PanePlaceholderView

/// A labelled stand-in for a pane whose real content lands in a later stage
/// (the inspector's tabs, the timeline). It draws the pane's name and a one
/// line note so an unfinished build reads as unfinished rather than broken,
/// and it is replaced wholesale — the containers around it
/// (`EditorViewController.inspectorContainer` / `.timelineContainer`) are
/// what later stages fill.
final class PanePlaceholderView: NSView {
    private let name: String
    private let note: String

    init(name: String, note: String) {
        self.name = name
        self.note = note
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanePlaceholderView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DS.chromeBackground.setFill()
        bounds.fill()

        let title = DS.microLabel(name, size: 11)
        title.draw(at: NSPoint(x: 14, y: 12))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.sans(12),
            .foregroundColor: DS.textFaint,
        ]
        note.draw(
            with: NSRect(x: 14, y: 34, width: max(bounds.width - 28, 10), height: 60),
            options: [.usesLineFragmentOrigin],
            attributes: attributes)
    }
}
