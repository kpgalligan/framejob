import AppKit
import CoreText

/// The TEXT half of `LayerRenderers`: measuring a description, laying it out
/// once, and drawing as much of it as the recipe's REVEAL says is showing
/// (spec §5.2's `text.animation`, format version 5).
///
/// The seam is the one thing text has that no other source kind does: it is
/// the property group the MODEL cannot measure (§11), because only the
/// platform can lay a paragraph out. Everything downstream of that
/// measurement is here — the size cache, the layout cache, and `drawText`,
/// which dispatches to the three reveal routines (`LayerRenderersReveal`) and
/// the word caption (`LayerRenderersWords`) — and everything that merely
/// rasterizes a box the model already describes stays in
/// `LayerRenderers.swift`, which keeps the texture cache, the text and shape
/// entry points, shapes and the bitmap/texture pair (stills went out to
/// `LayerRenderersImage.swift`).
/// The file is an extension and not a second type for that reason: there is
/// one cache and one lock, and a text texture is looked up beside a shape's.
///
/// The REVEAL is the core's number and this file's picture. `recipe.rs`
/// decides how much of the text is showing, which way it is going and which
/// of the three animations is showing it, and nothing here reads
/// `props.animation` — the recipe strips it out of the description precisely
/// so there is one answer. Two rules hold the drawing together and both are
/// older than the file: the layout is ALWAYS the full text's, so a reveal can
/// never reflow the box the canvas overlay measures its handles against; and
/// `reveal = 1` takes the original single `CTFrameDraw` rather than the span
/// machinery, which is what makes a full reveal byte-identical to no
/// animation at all.
///
/// The cut is the size payment road map 2's phase 6 owed before adding
/// gradients (845 lines against a ~600 cap), the same payment
/// `model_props.rs` made on the core side of the same phase.
///
/// Three members widened from `private` to internal across that cut —
/// `renderText` here, `bitmap` and `upload` there — for
/// `ExporterLoudness.swift`'s reason: `private` on an extension member
/// reaches only its own file, and a stored property cannot move into an
/// extension at all. Road map 8's W3 widened more for the same reason: the
/// layout types, `layout(for:)`, `drawLaidLine`, `drawFaded`, `tokens(of:)`,
/// `midpoint` and `attributedString`, which the two sibling files draw with;
/// and #363 added the word-clip geometry both of them share, `tokensOnLine`,
/// `clipBounds` (moved here from `LayerRenderersWords.swift`) and
/// `drawClipped`.
extension LayerRenderers {

    // MARK: - Measured text

    /// The layout size of a text description, in source pixels, INCLUDING
    /// the backdrop's padding and the outline's overshoot — the box the
    /// texture is drawn into, so the compositor and the overlay agree on
    /// where a text layer is.
    ///
    /// Static and process-wide because the overlay asks for it on the main
    /// thread while the compositor asks for it on its render queue, and
    /// re-measuring a paragraph per frame is the one cost this cache exists
    /// to avoid.
    static func measuredSize(for props: TextProps) -> CGSize {
        let key = layoutKey(props)
        sizeLock.lock()
        if let hit = sizeCache[key] {
            sizeLock.unlock()
            return hit
        }
        sizeLock.unlock()

        let size = measure(props)
        sizeLock.lock()
        if sizeCache.count > cacheLimit * 4 { sizeCache.removeAll() }
        sizeCache[key] = size
        sizeLock.unlock()
        return size
    }

    private static let sizeLock = NSLock()
    private static var sizeCache: [String: CGSize] = [:]

    /// Every field that changes the LAYOUT (colour does not, and neither
    /// does the animation). Cheap to build and stable, which is all a cache
    /// key has to be.
    ///
    /// The list is an allowlist nothing checks, so it cuts both ways: a new
    /// field that DOES move a glyph and is left out here is mis-measured
    /// forever, with the overlay's handles and the drawn texture disagreeing
    /// and no diagnostic anywhere; a per-frame value added to it would churn
    /// this cache and walk the handles as the words arrive. `animation` and
    /// the reveal are of the second kind and stay out, and so do `words`,
    /// `word` and `word_pop`: `case` and the word style's headroom inputs
    /// are the first kind, appended only when set so an unstyled, as-written
    /// text keeps the key it always had.
    private static func layoutKey(_ props: TextProps) -> String {
        let outline = props.outline.map { "\($0.width)" } ?? "-"
        let backdrop = props.backdrop.map { "\($0.padding)" } ?? "-"
        let width = props.width.map { "\($0)" } ?? "-"
        var key = [
            props.content, props.font, "\(props.size)", props.align, props.valign,
            "\(props.lineSpacing)", "\(props.tracking)", outline, backdrop, width,
        ]
        if props.textCase != .asWritten || props.wordStyle != nil {
            let style = props.wordStyle
            key += [
                props.textCase.rawValue, style.map { "\($0.activeScale)" } ?? "-",
                style?.activePill.map { "\($0.padding)" } ?? "-", "\(style != nil)",
            ]
        }
        return key.joined(separator: "\u{1}")
    }

    /// CoreText's "no constraint". `CGFloat.greatestFiniteMagnitude` makes
    /// the framesetter's arithmetic overflow into NaN on some fonts; a large
    /// finite number does not.
    private static let unconstrained: CGFloat = 100_000

    private static func measure(_ props: TextProps) -> CGSize {
        let attributed = attributedString(props)
        guard attributed.length > 0 else { return CGSize(width: 1, height: 1) }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let constraint = CGSize(
            width: props.width.map { max(1, CGFloat($0)) } ?? unconstrained,
            height: unconstrained)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraint, &fitRange)
        let insets = textInsets(props)
        let width = (props.width.map { CGFloat($0) } ?? suggested.width) + insets.x * 2
        let height = suggested.height + insets.y * 2
        return CGSize(
            width: min(CGFloat(maxTextureSide), max(1, width.rounded(.up))),
            height: min(CGFloat(maxTextureSide), max(1, height.rounded(.up))))
    }

    /// The margin around the laid-out text, per axis: the backdrop's
    /// padding, and enough room for the outline, whose stroke straddles the
    /// glyph edge — plus, on a word-styled page, the room its active word's
    /// pop and pill need (`wordHeadroom`, zero for everything else, so an
    /// unstyled text's two insets are the one it always had).
    static func textInsets(_ props: TextProps) -> (x: CGFloat, y: CGFloat) {
        let outline = props.outline.map { CGFloat($0.width) } ?? 0
        let padding = props.backdrop.map { CGFloat($0.padding) } ?? 0
        let base = max(outline, padding)
        let headroom = wordHeadroom(for: props)
        return (x: base + headroom.width, y: base + headroom.height)
    }

    static func attributedString(_ props: TextProps) -> NSAttributedString {
        NSAttributedString(string: props.laidContent, attributes: textAttributes(props))
    }

    /// The one attribute set a text is laid out in: the font, the fill, the
    /// paragraph style, the kern and the outline. `scale` multiplies every
    /// LENGTH — the font size and the kern — so the canvas's text editor
    /// takes the render's own set at view points (spec §11 K-3); the stroke
    /// is a percentage of the font size and so scale-free. At scale 1 every
    /// value is the one the render has always laid out.
    static func textAttributes(
        _ props: TextProps, scale: CGFloat = 1
    ) -> [NSAttributedString.Key: Any] {
        let size = max(1, CGFloat(props.size))
        let font = CTFontCreateWithName(props.font as CFString, size * scale, nil)
        let paragraph = NSMutableParagraphStyle()
        switch props.align {
        case "left": paragraph.alignment = .left
        case "right": paragraph.alignment = .right
        default: paragraph.alignment = .center
        }
        // `lineSpacing` is a MULTIPLE of the natural line height (§5.2), not
        // a point value, which is `lineHeightMultiple`, not `lineSpacing`.
        if props.lineSpacing > 0, props.lineSpacing != 1 {
            paragraph.lineHeightMultiple = CGFloat(props.lineSpacing)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: props.color.nsColor,
            .paragraphStyle: paragraph,
        ]
        if props.tracking != 0 { attributes[.kern] = CGFloat(props.tracking) * scale }
        if let outline = props.outline {
            // A NEGATIVE stroke width means "fill AND stroke", and the value
            // is a PERCENTAGE of the font size — positive would draw the
            // outline only and lose the fill.
            attributes[.strokeWidth] = -CGFloat(outline.width) / size * 100
            attributes[.strokeColor] = outline.color.nsColor
        }
        return attributes
    }

    // MARK: - Laid-out text

    /// One laid-out line, with the geometry a reveal needs and nothing else.
    struct TextLine {
        let line: CTLine
        /// The line's origin in the BITMAP's coordinates (y up), the frame
        /// path's own origin already added.
        let origin: CGPoint
        /// The line's range in the attributed string, in UTF-16 units —
        /// which is the unit every CoreText string index is in.
        let range: CFRange
        let ascent: CGFloat
        let descent: CGFloat
        let leading: CGFloat

        /// The line's full height, and the distance a `line_rise` measures
        /// its offset against.
        var height: CGFloat { ascent + descent + leading }
    }

    /// A text description laid out once: the box it occupies, the frame
    /// CoreText draws, and the lines inside it.
    struct TextLayout {
        let size: CGSize
        /// nil for an empty description — the box is still drawn (a backdrop
        /// may be under it), there is simply nothing to lay out.
        let frame: CTFrame?
        let lines: [TextLine]
    }

    private static let layoutLock = NSLock()
    private static var layoutCache: [String: TextLayout] = [:]

    /// The key a laid-out frame is cached under: everything `layoutKey`
    /// covers, plus the two COLOURS.
    ///
    /// `layoutKey` leaves colour out on purpose — a colour cannot move a
    /// glyph, and the measured size must not churn — but a `CTFrame` carries
    /// its glyphs' fill and stroke colours inside it, so a frame cached under
    /// a colour-free key would draw the previous clip's colour with this
    /// clip's words. The reveal is NOT in here either, and that is the point:
    /// a reveal draws a layout, it can never ask for a different one.
    private static func frameKey(_ props: TextProps) -> String {
        let outline = props.outline.map { "\($0.color)" } ?? "-"
        return [layoutKey(props), "\(props.color)", outline].joined(separator: "\u{1}")
    }

    /// The laid-out text for a description, built once and cached.
    ///
    /// `renderText` used to build a SECOND framesetter over the string that
    /// `measure` had already framed, with a different constraint width: two
    /// objects that had to agree and agreed only by construction, re-made on
    /// every frame of an animation. There is one now.
    ///
    /// Bounded like `sizeCache` and flushed wholesale rather than aged, but
    /// an order of magnitude tighter, because a `CTFrame` holds every glyph
    /// of a paragraph where a `CGSize` is two numbers. Built OUTSIDE the
    /// lock, so two threads racing on one miss lay out twice and the second
    /// store wins — the acceptance `cached` already documents. Everything
    /// stored is an immutable CoreText object, which is what makes it safe
    /// for the render queues of two compositors to draw one frame at once.
    static func layout(for props: TextProps) -> TextLayout {
        let key = frameKey(props)
        layoutLock.lock()
        if let hit = layoutCache[key] {
            layoutLock.unlock()
            return hit
        }
        layoutLock.unlock()

        let layout = makeLayout(props)
        layoutLock.lock()
        if layoutCache.count > cacheLimit { layoutCache.removeAll() }
        layoutCache[key] = layout
        layoutLock.unlock()
        return layout
    }

    private static func makeLayout(_ props: TextProps) -> TextLayout {
        let size = measuredSize(for: props)
        let attributed = attributedString(props)
        guard attributed.length > 0 else {
            return TextLayout(size: size, frame: nil, lines: [])
        }
        let insets = textInsets(props)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var fitRange = CFRange()
        let constraint = CGSize(width: size.width - insets.x * 2, height: unconstrained)
        let laid = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraint, &fitRange)
        // Two points of slack: CoreText CLIPS to the frame path, and a frame
        // exactly as tall as the suggested size drops the last line on some
        // fonts through rounding.
        let height = min(size.height - insets.y * 2, laid.height) + 2
        let y: CGFloat
        switch props.valign {
        // CoreGraphics is y-UP here, so "top" is the high y.
        case "top": y = size.height - insets.y - height
        case "bottom": y = insets.y
        default: y = (size.height - height) / 2
        }
        let rect = CGRect(
            x: insets.x, y: y, width: size.width - insets.x * 2, height: height)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)

        // `as!` is banned, and this bridge is the one place the ban is
        // awkward; an empty list simply draws nothing.
        let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        guard !lines.isEmpty else { return TextLayout(size: size, frame: frame, lines: []) }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var laidLines: [TextLine] = []
        laidLines.reserveCapacity(lines.count)
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            laidLines.append(
                TextLine(
                    line: line,
                    // Line origins are relative to the frame path's bounding
                    // box, which starts at the inset.
                    origin: CGPoint(x: rect.minX + origin.x, y: rect.minY + origin.y),
                    range: CTLineGetStringRange(line), ascent: ascent, descent: descent,
                    leading: leading))
        }
        return TextLayout(size: size, frame: frame, lines: laidLines)
    }

    // MARK: - Rasterizing text

    /// Internal rather than private because `text(_:hash:reveal:)` — the
    /// cache's entry point, which stays with the cache — is in the other
    /// file, and `private` on an extension member reaches only its own.
    func renderText(_ props: TextProps, reveal: RecipeReveal) -> Rendered? {
        guard let context = renderTextBitmap(props, reveal: reveal) else { return nil }
        return upload(context, size: CGSize(width: context.width, height: context.height))
    }

    /// The drawn bitmap `renderText` uploads, and nothing else — split out
    /// so a probe can read the pixels a word caption lands (road map 8's
    /// W3) without a texture in the way.
    func renderTextBitmap(_ props: TextProps, reveal: RecipeReveal) -> CGContext? {
        Self.textBitmap(props, reveal: reveal)
    }

    /// `renderTextBitmap`'s body, static so the Generate Captions sheet's
    /// preview (road map 8's W4b) draws with the renderer's own routine and
    /// no Metal device.
    ///
    /// A timed page's pause dim is in this bitmap only when the page has a
    /// backdrop. With none the bitmap is the undimmed page's, byte for byte,
    /// and the compositor's layer opacity carries the dim
    /// (`wordDim(of:reveal:)`, `RecipeLayer.drawnOpacity`, spec §11 W-16).
    /// With one, a TIMED page draws its words first — a dim is then one
    /// multiply of them (`drawWords`) — and its backdrop UNDER them; every
    /// other page draws its backdrop first (spec §11 W-17).
    static func textBitmap(_ props: TextProps, reveal: RecipeReveal) -> CGContext? {
        let layout = LayerRenderers.layout(for: props)
        guard let context = LayerRenderers.bitmap(layout.size) else { return nil }

        // The backdrop is drawn at FULL opacity whatever the reveal: it is
        // the readability plate, not the words, and a plate that faded or
        // wiped with them would flicker under every caption. The outline
        // needs no decision at all — it is a glyph attribute, so it arrives
        // and leaves with its own glyph. `drawText`'s own condition for
        // drawing words decides which goes down first.
        let wordsFirst = reveal.word != nil && props.wordStyle != nil
        if let backdrop = props.backdrop, !wordsFirst {
            drawBackdrop(backdrop, size: layout.size, under: false, in: context)
        }
        LayerRenderers.drawText(layout, of: props, reveal: reveal, in: context)
        if let backdrop = props.backdrop, wordsFirst {
            drawBackdrop(backdrop, size: layout.size, under: true, in: context)
        }
        return context
    }

    // MARK: - Drawing a reveal

    /// Draws the text of `layout` as much of it as `reveal` says is showing.
    ///
    /// No animation, or a reveal that has finished, takes the ORIGINAL path —
    /// one `CTFrameDraw` — which is what makes a full reveal BYTE-identical
    /// to a clip with no animation at all. The span machinery is not asked to
    /// reproduce `CTFrameDraw` exactly at 1.0; it is not called at all.
    private static func drawText(
        _ layout: TextLayout, of props: TextProps, reveal: RecipeReveal, in context: CGContext
    ) {
        // A timed page draws its words and nothing else (W-5: a styled page
        // gets a WHOLE reveal). A page whose `word` is null — untimed, or a
        // count mismatch — falls through and draws static. The dim is
        // handed on only when the rule says the bitmap draws it (W-16).
        if let word = reveal.word, let style = props.wordStyle {
            drawWords(
                layout, of: props, style: style, word: word, pop: reveal.wordPop,
                glide: reveal.wordGlide, fill: reveal.wordFill,
                dim: wordDim(of: props, reveal: reveal).onLayer ? nil : reveal.wordDim,
                in: context)
            return
        }
        guard let frame = layout.frame else { return }
        let amount = min(max(reveal.amount, 0), 1)
        guard let kind = reveal.kind, amount < 1 else {
            CTFrameDraw(frame, context)
            return
        }
        guard amount > 0, !layout.lines.isEmpty else { return }
        // `CTFrameDraw` sets the text matrix up for you; `CTLineDraw` does
        // not, and glyphs would come out under whatever the context last held.
        context.textMatrix = .identity
        switch kind {
        case .typewriter:
            typewriter(layout, content: props.laidContent, amount: amount, in: context)
        case .wordFade:
            wordFade(
                layout, content: props.laidContent, amount: amount, leaving: reveal.isLeaving,
                in: context)
        case .lineRise:
            lineRise(layout, amount: amount, leaving: reveal.isLeaving, in: context)
        }
    }

    static func drawLaidLine(_ laid: TextLine, in context: CGContext) {
        context.textPosition = laid.origin
        CTLineDraw(laid.line, context)
    }

    /// One laid-out line drawn at `alpha`, as a SINGLE composite.
    ///
    /// An outlined glyph is filled and THEN stroked — `attributedString`
    /// sets a negative `.strokeWidth`, which is Core Text's spelling of
    /// "fill and stroke" — and `CGContext.setAlpha` applies to each of those
    /// two draws separately. The inner half of the stroke lands on ink the
    /// fill has already laid down, so at a partial alpha it composites twice
    /// and comes out both denser and the wrong colour: a black outline on a
    /// white word reads as a heavy grey halo for the whole ramp and snaps to
    /// a crisp edge only at reveal 1. Nothing before this phase could see it,
    /// because a text texture was only ever faded whole, in the shader, where
    /// the per-clip opacity meets the FINISHED pixels once.
    ///
    /// A transparency layer is that same "once": both passes draw at alpha 1
    /// into a buffer and the alpha is applied to the result. An opaque line
    /// skips it — at alpha 1 the stroke covers the fill exactly as it would
    /// in the finished glyph, and an intermediate buffer would buy nothing
    /// but a rounding step and a full-canvas allocation.
    static func drawFaded(_ laid: TextLine, alpha: Double, in context: CGContext) {
        context.setAlpha(CGFloat(alpha))
        guard alpha < 1 else {
            drawLaidLine(laid, in: context)
            return
        }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawLaidLine(laid, in: context)
        context.endTransparencyLayer()
    }

    /// Maximal runs of non-whitespace characters, as UTF-16 ranges.
    ///
    /// Not `enumerateSubstrings(options: .byWords)`, which skips punctuation:
    /// a comma would then belong to no token and never be drawn at all. Every
    /// visible glyph belongs to exactly one token here.
    static func tokens(of content: String) -> [Range<Int>] {
        var tokens: [Range<Int>] = []
        var start: Int?
        for index in content.indices {
            let offset = index.utf16Offset(in: content)
            if content[index].isWhitespace {
                if let from = start { tokens.append(from..<offset) }
                start = nil
            } else if start == nil {
                start = offset
            }
        }
        if let from = start { tokens.append(from..<content.utf16.count) }
        return tokens
    }

    /// The x halfway between two string indices on one line: the middle of
    /// the whitespace between two words. `CTLineGetOffsetForStringIndex`
    /// reads the line as it was ALREADY laid out, so it never re-shapes and
    /// never moves a glyph.
    static func midpoint(_ laid: TextLine, _ a: Int, _ b: Int) -> CGFloat {
        let first = CTLineGetOffsetForStringIndex(laid.line, a, nil)
        let second = CTLineGetOffsetForStringIndex(laid.line, b, nil)
        return laid.origin.x + (first + second) / 2
    }

    /// The tokens with ink on the line spanning `line`, in string order. A
    /// token can straddle a line break when a single word is wider than the
    /// box, so it is on both lines and each half is clipped to its own.
    static func tokensOnLine(_ tokens: [Range<Int>], _ line: Range<Int>) -> [Int] {
        tokens.indices.filter {
            tokens[$0].lowerBound < line.upperBound && tokens[$0].upperBound > line.lowerBound
        }
    }

    /// The clip for token `here[position]` on one line: from the middle of
    /// the gap on its left to the middle of the gap on its right, or the
    /// box's own edge where it is the line's first or last — never a glyph
    /// edge, where two clips would double-composite an antialiased pixel.
    static func clipBounds(
        _ layout: TextLayout, _ laid: TextLine, _ tokens: [Range<Int>], _ here: [Int],
        _ position: Int, _ line: Range<Int>
    ) -> (left: CGFloat, right: CGFloat) {
        let range = tokens[here[position]].clamped(to: line)
        let left: CGFloat
        if position == 0 {
            left = 0
        } else {
            let previous = tokens[here[position - 1]].clamped(to: line)
            left = midpoint(laid, previous.upperBound, range.lowerBound)
        }
        let right: CGFloat
        if position == here.count - 1 {
            right = layout.size.width
        } else {
            let next = tokens[here[position + 1]].clamped(to: line)
            right = midpoint(laid, range.upperBound, next.lowerBound)
        }
        return (left: left, right: right)
    }

    /// Draws `laid` at `alpha` (`drawFaded`), clipped to `left…right` over
    /// the box's `height`.
    static func drawClipped(
        _ laid: TextLine, alpha: Double, left: CGFloat, right: CGFloat, height: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        // The clip is set BEFORE the alpha, because `drawFaded` may open a
        // transparency layer and a layer is bounded by the clip that was
        // standing when it opened.
        context.clip(to: CGRect(x: left, y: 0, width: max(right - left, 0), height: height))
        drawFaded(laid, alpha: alpha, in: context)
        context.restoreGState()
    }
}
