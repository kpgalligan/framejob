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

/// The stacked lockup: the mark 88 tall, a 14pt gap, then "Frame Job" in
/// the house display face at 52, both centred.
/// This is the welcome screen's masthead.
///
/// A stack view rather than hand-written constraints because the two pieces
/// have very different widths and only one of them may set the lockup's:
/// centring them with inequalities lets a text field answer a narrow parent
/// by wrapping instead of resisting, and the lockup then collapses to the
/// mark's 88pt with "Frame Job" broken over two lines.
final class BrandLockupView: NSStackView {
    static let markSize: CGFloat = 88
    static let wordSize: CGFloat = 52

    /// The clear space the lockup asks for on every side, a fixed 38 pt.
    /// Callers place the lockup with at least this much around it. The value
    /// is the one the old mark derived (38.13, rounded), kept so the welcome
    /// column's height does not change when the mark does.
    static var clearSpace: CGFloat { 38 }

    /// The gap the handoff specifies, and the `line-height` the mock's
    /// wordmark sits in — needed together, see `wordmarkTopOffset`.
    private static let gap: CGFloat = 14
    private static let mockLineHeight: CGFloat = 0.82

    private let markView = BrandMarkView(size: BrandLockupView.markSize)
    private let wordmark: NSTextField

    init() {
        let font = DS.display(BrandLockupView.wordSize)
        wordmark = NSTextField(
            labelWithAttributedString: NSAttributedString(
                string: "Frame Job",
                attributes: [
                    .font: font,
                    // -0.015em, the tracking the lockup is drawn with.
                    .kern: -0.015 * BrandLockupView.wordSize,
                    .foregroundColor: DS.textStrong,
                ]))
        super.init(frame: .zero)

        // The mark and the word say the same thing; letting both speak would
        // make VoiceOver read "Frame Job" twice. The label carries it.
        markView.setAccessibilityElement(false)
        // One line, always — see the class note above.
        wordmark.maximumNumberOfLines = 1

        orientation = .vertical
        alignment = .centerX
        spacing = BrandLockupView.wordmarkTopOffset(font)
        addArrangedSubview(markView)
        addArrangedSubview(wordmark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BrandLockupView does not support NSCoder")
    }

    /// The spacing that puts the wordmark where the mock puts it.
    ///
    /// The mock measures its 14pt gap to the wordmark's LINE BOX, which its
    /// `line-height: 0.82` crops to little more than the cap line. An AppKit
    /// label keeps the face's whole ascent and descent instead, so stacking
    /// the two boxes 14pt apart would open an optical gap half again as
    /// large. Give back the half-leading the mock hides — with Darker
    /// Grotesque at 52 that is 13.9 of the 14, so the two boxes end up all
    /// but touching and the INK lands 26pt apart, as drawn. Written as the
    /// subtraction rather than as its answer so it stays right if the size or
    /// the fallback face changes; clamped at 0 because a face with even more
    /// leading than this one would ask for a negative stack spacing.
    private static func wordmarkTopOffset(_ font: NSFont) -> CGFloat {
        let lineBox = wordSize * mockLineHeight
        let halfLeading = ((font.ascender - font.descender) - lineBox) / 2
        return max(0, gap - halfLeading)
    }
}
