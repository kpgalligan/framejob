import AppKit

/// The Reelcut mark: two clips overlapping with the playhead standing in the
/// overlap. The shape is the edit — where two pieces of footage meet, and
/// where you are in them (design handoff, Part 1 "The mark").
///
/// Every coordinate below is in the design's 120 × 120 box with **y measured
/// downward from the top**, exactly as the handoff's geometry table and
/// `logo/reelcut-mark.svg` write them, so the three can be diffed by eye.
/// That is why the drawing entry points all require a flipped context.
///
/// Two rules the drawing keeps, both of which the mark it replaces broke:
///
/// - **No blend mode anywhere.** The old `FrameMotifView` multiplied its two
///   frames, which means anything that ignores blend modes — a PDF export, an
///   icon compiler, a template rendering — flattens it wrong. Here the two
///   clips share a y and a height, so their intersection is exactly a 24-wide
///   rounded rect and is DRAWN, in the pre-multiplied ink, in draw order.
/// - **No strokes or hairlines.** The mark has to hold at 16px, where the two
///   clip blocks fuse into one dark bar and only the coral playhead has to
///   stay legible; a 1pt rule would turn to mud at that size and it is the
///   reason this direction was picked over the other four.
enum BrandMark {
    /// The side of the design box every coordinate in `draw(in:)` is in.
    /// The ink itself occupies x 18–102, y 20–102 of it — the optical inset
    /// is part of the mark, so callers scale the whole box, not the ink.
    static let designBox: CGFloat = 120

    /// Forest × butter, pre-multiplied. The one fixed ink outside `DS`, and
    /// deliberately not a token: it is the *result* of two brand inks
    /// crossing inside the mark, not a colour the interface may reach for,
    /// and a token would invite exactly that.
    private static let overlapInk = NSColor(
        srgbRed: 0x1D / 255, green: 0x65 / 255, blue: 0x1F / 255, alpha: 1)

    /// Draws the mark scaled to fit `rect`, preserving its aspect and
    /// centring the 120 box inside it.
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

        fill(NSRect(x: 18, y: 36, width: 54, height: 52), radius: 8, DS.forest)
        fill(NSRect(x: 48, y: 36, width: 54, height: 52), radius: 8, DS.butter)
        fill(NSRect(x: 48, y: 36, width: 24, height: 52), radius: 8, overlapInk)

        // The playhead goes on top at full opacity, never multiplied: it is
        // above the media in the mark for the same reason it is above the
        // media in the app. Its apex meets the clips' top edge at y 36, and
        // that contact is what stops the head reading as a floating triangle.
        DS.coral.setFill()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 49.5, y: 20))
        head.line(to: NSPoint(x: 70.5, y: 20))
        head.line(to: NSPoint(x: 60, y: 36))
        head.close()
        head.fill()
        fill(NSRect(x: 56.5, y: 20, width: 7, height: 82), radius: 3.5, DS.coral)
    }

    private static func fill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// The mark as an image, `size` points square — the About panel takes an
    /// `NSImage`, not a view. Not a template image: the mark is three brand
    /// inks and a flat tint would lose the cut. Use `logo/reelcut-mark-mono`
    /// where tinting is applied instead.
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
    /// The side of the square the 120 box is scaled into.
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
        setAccessibilityLabel("Reelcut")
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

/// The stacked lockup (design handoff, Part 1 "The wordmark"): the mark 88
/// tall, a 14pt gap, then "Reelcut" in the house display face at 52, both
/// centred. This is the welcome screen's masthead.
///
/// A stack view rather than hand-written constraints because the two pieces
/// have very different widths and only one of them may set the lockup's:
/// centring them with inequalities lets a text field answer a narrow parent
/// by wrapping instead of resisting, and the lockup then collapses to the
/// mark's 88pt with "Reelcut" broken over two lines.
final class BrandLockupView: NSStackView {
    static let markSize: CGFloat = 88
    static let wordSize: CGFloat = 52

    /// The clear space the lockup asks for on every side: one clip height,
    /// 52 of the 120 box, so 43% of the mark's height. Callers place the
    /// lockup with at least this much around it.
    static var clearSpace: CGFloat { (52 / BrandMark.designBox * markSize).rounded() }

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
                string: "Reelcut",
                attributes: [
                    .font: font,
                    // -0.015em, the tracking the lockup is drawn with.
                    .kern: -0.015 * BrandLockupView.wordSize,
                    .foregroundColor: DS.textStrong,
                ]))
        super.init(frame: .zero)

        // The mark and the word say the same thing; letting both speak would
        // make VoiceOver read "Reelcut" twice. The label carries it.
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
