import AppKit

/// The Frame Job mark: a viewfinder — four corner brackets framing a shot,
/// with the playhead standing through it. The owner's
/// `designs/frame-job/frame-job-icon.svg` without its cream tile (spec §11
/// NM-11): the Dock shows the tiled icon, and this is what goes on a surface
/// that is already a card.
///
/// Every coordinate below is written exactly as the SVG writes it, in its
/// 1024 viewBox with **y measured downward from the top**, so the two can be
/// diffed by eye. That is why the drawing entry points all require a flipped
/// context.
///
/// Two rules the drawing keeps:
///
/// - **No blend mode anywhere.** Anything that ignores blend modes — a PDF
///   export, an icon compiler, a template rendering — would flatten it wrong.
///   The shapes are drawn opaque, in the SVG's order.
/// - **No strokes, hairlines or radii.** The SVG has none; a 1pt rule would
///   turn to mud at small sizes.
enum BrandMark {
    /// The side of the design box `draw(in:)` scales: the SVG's tile, 824 of
    /// its 1024 viewBox. The tile's own inset is part of the mark, so callers
    /// scale the whole box, not the ink.
    static let designBox: CGFloat = 824

    /// The tile's x and y in the SVG: the box starts here, so the drawing is
    /// moved back by it and the coordinates stay the SVG's own.
    private static let tileOrigin: CGFloat = 100

    /// Draws the mark scaled to fit `rect`, preserving its aspect and
    /// centring the tile box inside it.
    ///
    /// **The current context must be flipped** (y down), or the mark lands
    /// upside down: `BrandMarkView` is `isFlipped` and `image(size:)` asks
    /// `NSImage` for a flipped drawing handler for this reason.
    static func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(rect.width, rect.height) / designBox
        guard scale > 0 else { return }
        let side = designBox * scale

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(
            x: rect.minX + (rect.width - side) / 2,
            y: rect.minY + (rect.height - side) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -tileOrigin, y: -tileOrigin)

        // The four corner brackets, each an L of 64 thickness.
        polygon([(190, 380), (190, 190), (380, 190), (380, 254), (254, 254), (254, 380)], DS.forest)
        polygon([(834, 380), (834, 190), (644, 190), (644, 254), (770, 254), (770, 380)], DS.forest)
        polygon([(190, 644), (190, 834), (380, 834), (380, 770), (254, 770), (254, 644)], DS.forest)
        polygon([(834, 644), (834, 834), (644, 834), (644, 770), (770, 770), (770, 644)], DS.forest)
        // The frame, then the playhead on top of it at full opacity: it is
        // above the media in the mark for the same reason it is above the
        // media in the app.
        fill(NSRect(x: 330, y: 400, width: 364, height: 224), DS.butter)
        fill(NSRect(x: 488, y: 310, width: 48, height: 424), DS.coral)
        polygon([(461, 290), (563, 290), (512, 366)], DS.coral)
    }

    private static func fill(_ rect: NSRect, _ color: NSColor) {
        color.setFill()
        NSBezierPath(rect: rect).fill()
    }

    private static func polygon(_ points: [(CGFloat, CGFloat)], _ color: NSColor) {
        guard let first = points.first else { return }
        color.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: first.0, y: first.1))
        for point in points.dropFirst() {
            path.line(to: NSPoint(x: point.0, y: point.1))
        }
        path.close()
        path.fill()
    }

    /// The mark as an image, `size` points square — the About panel takes an
    /// `NSImage`, not a view. Not a template image: the mark is three brand
    /// inks and a flat tint would lose the playhead against the frame.
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            draw(in: rect)
            return true
        }
    }
}

// MARK: - BrandMarkView

/// The mark as a view, square and scaled to `size`. Nothing else about it is
/// configurable — it is one shape in fixed inks.
final class BrandMarkView: NSView {
    /// The side of the square the design box is scaled into.
    var size: CGFloat {
        didSet {
            guard size != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    init(size: CGFloat) {
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        setAccessibilityRole(.image)
        setAccessibilityLabel("Frame Job")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BrandMarkView does not support NSCoder")
    }

    /// `BrandMark`'s coordinates are y-down; this is what lets them be used
    /// verbatim.
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: size, height: size) }

    override func draw(_ dirtyRect: NSRect) {
        BrandMark.draw(in: bounds)
    }
}

// MARK: - BrandLockupView

/// The stacked lockup, the welcome screen's masthead (spec §11 NM-16): the mark 88 tall, then
/// Frame Job's product wordmark at a 44 pt font size, both centred, the wordmark's cap line
/// 35 pt below the mark's ink, and the whole 158 pt tall, as the lockup was before.
///
/// A stack view rather than hand-written constraints because the two pieces have very
/// different widths and only one of them may set the lockup's. The wordmark is drawn, so it
/// never wraps; the label it falls back to is held to one line for the same reason.
final class BrandLockupView: NSStackView {
    static let markSize: CGFloat = 88
    /// The wordmark's font size: caps 31.2 pt tall and 213 pt wide, the old label's size.
    static let wordmarkFontSize: CGFloat = 44

    /// The clear space the lockup asks for on every side, a fixed 38 pt.
    /// Callers place the lockup with at least this much around it. The value
    /// is the one the old mark derived (38.13, rounded), kept so the welcome
    /// column's height does not change when the mark does.
    static var clearSpace: CGFloat { 38 }

    /// From the mark's ink (the brackets' foot) down to the wordmark's cap line: where the
    /// handoff's reference capture puts it (the old label's was 35.5).
    private static let capLineBelowMarkInk: CGFloat = 35
    /// The lockup's height before NM-16 (the 88 pt mark, a 0.06 pt gap and the old label's
    /// 70 pt line), kept so that the Welcome column, which is centred, does not move: the
    /// shorter wordmark leaves the difference as space below it.
    static let height: CGFloat = 158
    /// The mark view's inset below its ink: the design box ends 90 units under the brackets'
    /// foot (924 against 834 in the SVG's viewBox), scaled from the 824-unit box to the view.
    private static var markInsetBelowInk: CGFloat { 90 * markSize / BrandMark.designBox }

    private let markView = BrandMarkView(size: BrandLockupView.markSize)

    init() {
        super.init(frame: .zero)

        // The mark and the wordmark say the same thing; letting both speak would make
        // VoiceOver read "Frame Job" twice. The wordmark carries it.
        markView.setAccessibilityElement(false)

        let name = "Frame Job"
        let wordmark: NSView
        let capLineFromTop: CGFloat
        let wordmarkHeight: CGFloat
        if let artwork = WordmarkArtwork.frameJob {
            let view = ProductWordmarkView(
                artwork: artwork, name: name, fontSize: BrandLockupView.wordmarkFontSize,
                textColor: DS.textStrong)
            capLineFromTop = view.capLineFromTop
            wordmarkHeight = view.intrinsicContentSize.height
            wordmark = view
        } else {
            // Unreachable while the compiled-in data parses (wordmark_proof.py checks it): the
            // name as the label it was before NM-16.
            assertionFailure("Frame Job's wordmark data does not parse")
            let size: CGFloat = 52
            let font = DS.display(size)
            let label = NSTextField(
                labelWithAttributedString: NSAttributedString(
                    string: name,
                    attributes: [
                        .font: font,
                        .kern: -0.015 * size,
                        .foregroundColor: DS.textStrong,
                    ]))
            label.maximumNumberOfLines = 1
            capLineFromTop = font.ascender - font.capHeight
            wordmarkHeight = label.intrinsicContentSize.height
            wordmark = label
        }

        orientation = .vertical
        alignment = .centerX
        // Set from the named distances, never as their answer (about 9 pt for the wordmark):
        // the cap line's 36 pt, less what the mark view keeps below its ink and what the
        // wordmark keeps above its caps. Clamped, since a stack takes no negative spacing.
        spacing = max(
            0,
            BrandLockupView.capLineBelowMarkInk - BrandLockupView.markInsetBelowInk
                - capLineFromTop)
        edgeInsets.bottom = max(
            0, BrandLockupView.height - BrandLockupView.markSize - spacing - wordmarkHeight)
        addArrangedSubview(markView)
        addArrangedSubview(wordmark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BrandLockupView does not support NSCoder")
    }
}
