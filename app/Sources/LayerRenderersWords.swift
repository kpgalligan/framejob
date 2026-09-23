import AppKit
import CoreText

/// The FOURTH text routine of `LayerRenderers` (road map 8 §5d, W3): a word
/// caption's timed page — the base pass, the active word's pill, and the
/// active word popped — and the headroom that keeps the pop inside the box.
///
/// The recipe's `word` and `word_pop` are the whole of what the core says
/// (`RecipeReveal`, spec §11 W-4): the active token is `word − 1`, the
/// spoken ones are before it, the upcoming ones from `word` on. Everything
/// here indexes `tokens(of: props.laidContent)` and nothing else, because
/// the `TextLayout` was laid from `laidContent` — so every
/// `CTLineGetOffsetForStringIndex`, `CTLineGetStringRange` and `midpoint`
/// index is in that string's UTF-16 space, which `case: upper` can make
/// longer than `content`'s ("ß" → "SS"). `props.content` is never indexed.
///
/// Two rules carry over from the reveal routines unchanged: the layout is
/// ALWAYS the full text's, so the box never depends on `word`; and a token
/// is clipped at the whitespace midpoints, never at a glyph edge, so two
/// passes never double-composite an antialiased pixel.
extension LayerRenderers {

    // MARK: - Headroom

    /// The horizontal headroom a pop or a pill is given at the least, in em.
    /// Road map 8 §8's measured 0.45 em, carried as a FLOOR: the formula in
    /// `wordHeadroom` is what holds at a long word or a 1.5 pop.
    static let wordHeadroomFloorEm = 0.45

    /// The vertical floor, in em. W0 q5 measured 0.30 em as enough for one
    /// page at 1.15; W3 made it a floor under the same formula, because at
    /// `active_scale` 1.5 the scaled pill outgrows it.
    static let wordHeadroomVerticalFloorEm = 0.30

    /// The peak of `backOut` over 0…1 — the most the pop ever overshoots
    /// its settled scale, as a multiple of `active_scale − 1`.
    static let popOvershoot = 1.1

    /// Pixels the formula is given past its exact edge, HORIZONTALLY only —
    /// the vertical term has its own constant below. The scaled pill's edge
    /// is antialiased into one more pixel than the exact formula covers;
    /// with no edge at all the probe measured the pill 2 px past the box at
    /// `active_scale` 1.5 (road map 8 §10.7).
    static let wordHeadroomEdgePx: CGFloat = 2

    /// The vertical edge: one pixel more than `wordHeadroomEdgePx`, for the
    /// worst `valign`. At "bottom" the frame starts at the inset and is two
    /// points taller than the text, and CoreText fills it from its top — so
    /// the first line reaches two points into the top inset, and the slack
    /// is below the last line, not above the text.
    static let wordHeadroomVerticalEdgePx: CGFloat = 3

    /// The room around the laid text a word-styled page's active word needs
    /// at the peak of its pop, in pixels per side — `.zero` when there is no
    /// style, or when nothing can overflow (`active_scale` 1 and no pill).
    ///
    /// The pop scales the active word's pill about its own centre, so what
    /// leaves the text's rect is the scaled padding plus the growth of half
    /// the WIDEST word (horizontally) or of half the line (vertically), less
    /// the outline inset already paid for — except horizontally with no
    /// pill, where the popped stroke is added instead. Both em constants
    /// are floors.
    static func wordHeadroom(for props: TextProps) -> CGSize {
        guard let style = props.wordStyle, style.activeScale != 1 || style.activePill != nil
        else { return .zero }
        let size = max(1, CGFloat(props.size))
        let peak = 1 + CGFloat(style.activeScale - 1) * CGFloat(popOvershoot)
        let pad = CGFloat(style.activePill?.padding ?? 0) * size
        let outline = props.outline.map { CGFloat($0.width) } ?? 0
        let metrics = wordMetrics(props)
        // With no pill the popped word's own STROKE is its edge, `peak ×
        // outline / 2` past the scaled glyphs, and the outline inset the
        // text rect already has does not cover it: W4a's P2 measured 10–11 px
        // of ink past the box at 1.5 with "− outline" here (road map 8
        // §10.7). A pill's padding is wider than the stroke, so its term
        // keeps the inset it was measured with.
        let stroke = style.activePill == nil ? peak * outline / 2 : -outline
        let width = max(
            CGFloat(wordHeadroomFloorEm) * size,
            peak * pad + (peak - 1) * metrics.widest / 2 + stroke + wordHeadroomEdgePx)
        let height = max(
            CGFloat(wordHeadroomVerticalFloorEm) * size,
            peak * pad + (peak - 1) * (metrics.ascent + metrics.descent) / 2 - outline
                + wordHeadroomVerticalEdgePx)
        return CGSize(width: width, height: height)
    }

    /// One `CTLine` per token of `laidContent` under `attributedString`'s
    /// attributes: the widest token's width, and the tallest typographic
    /// ascent and descent among them.
    static func wordMetrics(_ props: TextProps) -> (
        widest: CGFloat, ascent: CGFloat, descent: CGFloat
    ) {
        let attributed = attributedString(props)
        var widest: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        for token in tokens(of: props.laidContent) {
            let piece = attributed.attributedSubstring(
                from: NSRange(location: token.lowerBound, length: token.count))
            let line = CTLineCreateWithAttributedString(piece)
            var a: CGFloat = 0
            var d: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &a, &d, &leading))
            widest = max(widest, width)
            ascent = max(ascent, a)
            descent = max(descent, d)
        }
        return (widest: widest, ascent: ascent, descent: descent)
    }

    /// `core/src/motion.rs`'s `back_out`, the curve the pop rides: above 1
    /// from about 0.37, peaking at 1.100 near 0.58, exactly 1 at 1.
    static func backOut(_ u: Double) -> Double {
        let p = u - 1
        return 1 + 2.70158 * p * p * p + 1.70158 * p * p
    }

    // MARK: - Drawing a timed page

    /// A layout to draw tokens from, and the alpha it is composited at: a
    /// colour whose alpha is below 1 is laid out OPAQUE and faded as one
    /// composite (`drawFaded`'s reason — an outlined glyph's fill and stroke
    /// would otherwise composite twice).
    private struct WordInk {
        let layout: TextLayout
        let alpha: Double
    }

    private static func ink(_ props: TextProps, _ color: RGBA) -> WordInk {
        let alpha = color.count > 3 ? min(max(color[3], 0), 1) : 1
        var opaque = color
        if opaque.count > 3 { opaque[3] = 1 }
        return WordInk(layout: layout(for: props.recolored(opaque)), alpha: alpha)
    }

    /// Draws one line of `ink` at its alpha, clipped to `left…right`.
    private static func drawToken(
        _ ink: WordInk, line index: Int, left: CGFloat, right: CGFloat, height: CGFloat,
        in context: CGContext
    ) {
        guard ink.layout.lines.indices.contains(index), ink.alpha > 0 else { return }
        context.saveGState()
        // The clip BEFORE the alpha: a transparency layer is bounded by the
        // clip standing when it opens.
        context.clip(to: CGRect(x: left, y: 0, width: max(right - left, 0), height: height))
        drawFaded(ink.layout.lines[index], alpha: ink.alpha, in: context)
        context.restoreGState()
    }

    /// A timed page at `word` (how many words have started) and `pop` (0…1
    /// through the active word's pop, nil for none).
    ///
    /// The base pass first, token by token: build mode skips the upcoming
    /// tokens (`≥ word`), highlight draws them in `upcoming_color` when set;
    /// the spoken ones (`< word − 1`) take `spoken_color` when set; the base
    /// colour otherwise. Then the ACTIVE token, `word − 1`, in this order
    /// inside one saved state: the CTM scaled about its pill's centre by
    /// `1 + (active_scale − 1) × backOut(pop)`; the pill filled UNCLIPPED —
    /// it reaches past the midpoints by design; then the midpoint clip, set
    /// in text space so the CTM scales it with the token, and the token in
    /// `active_color`. Clipping before scaling would shave the popped
    /// word's end glyphs at the unscaled midpoints.
    static func drawWords(
        _ layout: TextLayout, of props: TextProps, style: WordStyle, word: Int, pop: Double?,
        in context: CGContext
    ) {
        let tokens = tokens(of: props.laidContent)
        guard !tokens.isEmpty, !layout.lines.isEmpty else { return }
        context.textMatrix = .identity
        // The base colour draws from the layout AS LAID, as the static page
        // does: fill at its own alpha, the stroke at the outline's.
        let base = WordInk(layout: layout, alpha: 1)
        let spoken = style.spokenColor.map { ink(props, $0) } ?? base
        let upcoming = style.upcomingColor.map { ink(props, $0) } ?? base
        let active = word - 1
        let height = layout.size.height

        for (index, laid) in layout.lines.enumerated() {
            let line = laid.range.location..<(laid.range.location + laid.range.length)
            // `wordFade`'s filter: the tokens with ink on THIS line.
            let here = tokens.indices.filter {
                tokens[$0].lowerBound < line.upperBound && tokens[$0].upperBound > line.lowerBound
            }
            for (position, token) in here.enumerated() where token != active {
                if token >= word, style.mode == .build { continue }
                let bounds = clipBounds(layout, laid, tokens, here, position, line)
                drawToken(
                    token >= word ? upcoming : spoken, line: index, left: bounds.left,
                    right: bounds.right, height: height, in: context)
            }
        }

        guard active >= 0, active < tokens.count else { return }
        let activeInk = style.activeColor.map { ink(props, $0) } ?? base
        let size = max(1, CGFloat(props.size))
        let scale = pop.map { 1 + CGFloat(style.activeScale - 1) * CGFloat(backOut($0)) } ?? 1
        for (index, laid) in layout.lines.enumerated() {
            let line = laid.range.location..<(laid.range.location + laid.range.length)
            let here = tokens.indices.filter {
                tokens[$0].lowerBound < line.upperBound && tokens[$0].upperBound > line.lowerBound
            }
            guard let position = here.firstIndex(of: active) else { continue }
            let range = tokens[active].clamped(to: line)
            let left = laid.origin.x
                + CTLineGetOffsetForStringIndex(laid.line, range.lowerBound, nil)
            let right = laid.origin.x
                + CTLineGetOffsetForStringIndex(laid.line, range.upperBound, nil)
            let pad = CGFloat(style.activePill?.padding ?? 0) * size
            let pill = CGRect(
                x: left - pad, y: laid.origin.y - laid.descent - pad,
                width: (right - left) + pad * 2, height: laid.ascent + laid.descent + pad * 2)
            let bounds = clipBounds(layout, laid, tokens, here, position, line)

            context.saveGState()
            // (a) the pop, about the pill's centre.
            context.translateBy(x: pill.midX, y: pill.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -pill.midX, y: -pill.midY)
            // (b) the pill, unclipped.
            if let plate = style.activePill, pill.width > 0, pill.height > 0 {
                let radius = min(
                    CGFloat(plate.radius) * size, min(pill.width, pill.height) / 2)
                context.addPath(
                    CGPath(
                        roundedRect: pill, cornerWidth: max(radius, 0),
                        cornerHeight: max(radius, 0), transform: nil))
                context.setFillColor(plate.color.nsColor.cgColor)
                context.fillPath()
            }
            // (c) the token, clipped at its midpoints in text space.
            drawToken(
                activeInk, line: index, left: bounds.left, right: bounds.right, height: height,
                in: context)
            context.restoreGState()
        }
    }

    /// The clip for token `here[position]` on one line: from the middle of
    /// the gap on its left to the middle of the gap on its right, or the
    /// box's own edge where it is the line's first or last — `wordFade`'s
    /// arithmetic exactly.
    private static func clipBounds(
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
}
