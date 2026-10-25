import AppKit
import CoreText

/// The FOURTH text routine of `LayerRenderers` (road map 8 §5d, W3): a word
/// caption's timed page — the base pass, the active word's pill, and the
/// active word popped — and the headroom that keeps the pop inside the box.
/// Since issue batch B86 (spec §11 W-14) also the three looks: a pill that
/// glides, a word that fills, a page that dims in a pause — and, since its
/// phase 3 (spec §11 W-16), the one rule for WHERE that dim is drawn,
/// `wordDim(of:reveal:)`: the compositor's layer opacity on a page with no
/// backdrop, and on a page with one `drawWords`' own multiply of the
/// bitmap, drawn before the backdrop is put under it (spec §11 W-17).
///
/// The recipe's five word keys are the whole of what the core says
/// (`RecipeReveal`, spec §11 W-4, W-13): the active token is `word − 1`, the
/// spoken ones are before it, the upcoming ones from `word` on, and a
/// gliding pill comes from token `word − 2`. Everything
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

    // MARK: - Where a dim is drawn

    /// Where a timed page's dim is drawn (spec §11 W-16).
    struct WordDim: Equatable {
        /// `word_dim × pause_dim`, each clamped to 0…1; 0 on a page that is
        /// not timed and styled.
        let amount: Double
        /// True: the compositor's layer opacity carries the dim and the
        /// bitmap holds none of it. False: the bitmap does.
        let onLayer: Bool
    }

    /// The ONE clamp of a dim, which `drawWords` and `wordDim` both call:
    /// the recipe's `word_dim` (nil is 0) times the style's `pause_dim`.
    static func dimAmount(_ dim: Double?, pauseDim: Double) -> Double {
        min(max(dim ?? 0, 0), 1) * min(max(pauseDim, 0), 1)
    }

    /// The one rule (spec §11 W-16). The amount is 0 unless the page is
    /// timed and styled — `drawText`'s own condition for drawing words at
    /// all. The dim is the LAYER's when the page has no backdrop: the bitmap
    /// then holds the words and the pill and nothing else, so one multiply
    /// of it in the compositor is one opacity over both. With a backdrop in
    /// the same bitmap that multiply would dim the backdrop too, so the dim
    /// is the BITMAP's.
    static func wordDim(of props: TextProps, reveal: RecipeReveal) -> WordDim {
        let onLayer = props.backdrop == nil
        guard reveal.word != nil, let style = props.wordStyle else {
            return WordDim(amount: 0, onLayer: onLayer)
        }
        return WordDim(
            amount: dimAmount(reveal.wordDim, pauseDim: style.pauseDim), onLayer: onLayer)
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
        drawClipped(
            ink.layout.lines[index], alpha: ink.alpha, left: left, right: right, height: height,
            in: context)
    }

    /// `1 − (1 − u)³`, the curve a gliding pill rides: fast off the word it
    /// leaves, settling onto the active one (spec §11 W-14).
    static func easeOut(_ u: Double) -> Double {
        let p = 1 - u
        return 1 - p * p * p
    }

    /// The part of one token that lies on one line: where its glyph range
    /// starts and ends, the pill around it, and its midpoint clip.
    private struct TokenPiece {
        let line: Int
        let left: CGFloat
        let right: CGFloat
        let pill: CGRect
        let bounds: (left: CGFloat, right: CGFloat)
    }

    /// `token`'s pieces in line order — one, unless the token wraps; none
    /// for an index that is no token.
    private static func pieces(
        of token: Int, _ layout: TextLayout, _ tokens: [Range<Int>], pad: CGFloat
    ) -> [TokenPiece] {
        guard tokens.indices.contains(token) else { return [] }
        var found: [TokenPiece] = []
        for (index, laid) in layout.lines.enumerated() {
            let line = laid.range.location..<(laid.range.location + laid.range.length)
            let here = tokensOnLine(tokens, line)
            guard let position = here.firstIndex(of: token) else { continue }
            let range = tokens[token].clamped(to: line)
            let left = laid.origin.x
                + CTLineGetOffsetForStringIndex(laid.line, range.lowerBound, nil)
            let right = laid.origin.x
                + CTLineGetOffsetForStringIndex(laid.line, range.upperBound, nil)
            let pill = CGRect(
                x: left - pad, y: laid.origin.y - laid.descent - pad,
                width: (right - left) + pad * 2, height: laid.ascent + laid.descent + pad * 2)
            found.append(
                TokenPiece(
                    line: index, left: left, right: right, pill: pill,
                    bounds: clipBounds(layout, laid, tokens, here, position, line)))
        }
        return found
    }

    /// Fills `plate` in `rect`, scaled about the rect's own centre.
    private static func fillPlate(
        _ plate: ActivePill, in rect: CGRect, size: CGFloat, scale: CGFloat, in context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.midX, y: -rect.midY)
        fillPlate(plate, in: rect, size: size, in: context)
        context.restoreGState()
    }

    private static func fillPlate(
        _ plate: ActivePill, in rect: CGRect, size: CGFloat, in context: CGContext
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = min(CGFloat(plate.radius) * size, min(rect.width, rect.height) / 2)
        context.addPath(
            CGPath(
                roundedRect: rect, cornerWidth: max(radius, 0), cornerHeight: max(radius, 0),
                transform: nil))
        context.setFillColor(plate.color.nsColor.cgColor)
        context.fillPath()
    }

    /// `x` moved onto the nearest whole DEVICE pixel column under the
    /// context's current transform, so a fill's edge never antialiases.
    private static func snappedToDevice(
        _ x: CGFloat, y: CGFloat, in context: CGContext
    ) -> CGFloat {
        var device = context.convertToDeviceSpace(CGPoint(x: x, y: y))
        device.x = device.x.rounded()
        return context.convertToUserSpace(device).x
    }

    /// A timed page at `word` (how many words have started) and `pop` (0…1
    /// through the active word's pop, nil for none), with the three looks of
    /// spec §11 W-14: `glide` (0…1 through the pill's slide from token
    /// `word − 2`), `fill` (0…1 of the active word filled) and `dim` (0…1
    /// into a pause's dim, nil for a page whose dim is not this bitmap's).
    /// All three are clamped — `glide` and `fill` here, `dim` and `pauseDim`
    /// in `dimAmount`: an action's end patch is not range-checked.
    ///
    /// **With `activePill.glide` not set and `fill` and `dim` nil, the calls
    /// are the ones this routine has always made, in their order.** The base
    /// pass first, token by token: build mode skips the upcoming tokens
    /// (`≥ word`), highlight draws them in `upcoming_color` when set; the
    /// spoken ones (`< word − 1`) take `spoken_color` when set; the base
    /// colour otherwise. Then the ACTIVE token, `word − 1`, in this order
    /// inside one saved state: the CTM scaled about its pill's centre by
    /// `1 + (active_scale − 1) × backOut(pop)`; the pill filled UNCLIPPED —
    /// it reaches past the midpoints by design; then the midpoint clip, set
    /// in text space so the CTM scales it with the token, and the token in
    /// `active_color`. Clipping before scaling would shave the popped
    /// word's end glyphs at the unscaled midpoints.
    ///
    /// **A gliding pill is filled BEFORE the base pass, in every frame of
    /// the page**, sliding or settled, so every word's ink lies over it —
    /// the word it is leaving included — and the order never flips when a
    /// slide ends. Its rect is the interpolation of token `word − 2`'s pill
    /// and the active token's at `easeOut(glide)` when each lies on one
    /// line, else the active token's settled pill; it pops about its OWN
    /// centre, and the active token still pops about its settled pill's.
    ///
    /// **A fill's edge is hard**: `left + fill × (right − left)` over the
    /// token's glyph range, on a whole device pixel; the active ink left of
    /// it, and right of it the upcoming ink (highlight) or nothing (build).
    /// At 1 the edge is the token's own clip bound, so a full word is drawn
    /// whole — an outline's stroke reaches past the glyph range.
    ///
    /// **A dim is one opacity over the words and the pill together**,
    /// `1 − dimAmount(dim, pauseDim:)`, drawn HERE — which only a page with a
    /// backdrop asks for, and its caller puts the backdrop under the words
    /// AFTER this returns, so it never dims (spec §11 W-17). The page is
    /// drawn undimmed and the whole bitmap multiplied once
    /// (`scaleBitmap`), on every exit after drawing starts, so the context
    /// must hold nothing but this page when a dim is passed; a context with
    /// no memory, decided before anything is drawn, takes one transparency
    /// layer instead. For a page with no backdrop the caller hands a nil
    /// `dim`, this routine draws the undimmed page, and the compositor
    /// multiplies the layer's opacity (`wordDim(of:reveal:)`, spec §11 W-16).
    static func drawWords(
        _ layout: TextLayout, of props: TextProps, style: WordStyle, word: Int, pop: Double?,
        glide: Double? = nil, fill: Double? = nil, dim: Double? = nil, in context: CGContext
    ) {
        let tokens = tokens(of: props.laidContent)
        guard !tokens.isEmpty, !layout.lines.isEmpty else { return }
        let dimmed = dimAmount(dim, pauseDim: style.pauseDim)
        guard dimmed < 1 else { return }
        let multiplies = dimmed > 0 && context.data != nil
        if dimmed > 0, !multiplies {
            context.saveGState()
            context.setAlpha(CGFloat(1 - dimmed))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer {
            if multiplies {
                scaleBitmap(context, by: 1 - dimmed)
            } else if dimmed > 0 {
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        context.textMatrix = .identity
        // The base colour draws from the layout AS LAID, as the static page
        // does: fill at its own alpha, the stroke at the outline's.
        let base = WordInk(layout: layout, alpha: 1)
        let spoken = style.spokenColor.map { ink(props, $0) } ?? base
        let upcoming = style.upcomingColor.map { ink(props, $0) } ?? base
        let active = word - 1
        let height = layout.size.height
        let size = max(1, CGFloat(props.size))
        let scale = pop.map { 1 + CGFloat(style.activeScale - 1) * CGFloat(backOut($0)) } ?? 1
        let pad = CGFloat(style.activePill?.padding ?? 0) * size
        let activePieces = pieces(of: active, layout, tokens, pad: pad)
        let glidingPlate = style.activePill.flatMap { $0.glide ? $0 : nil }

        if let plate = glidingPlate {
            drawGlidingPlate(
                plate, to: activePieces, from: pieces(of: active - 1, layout, tokens, pad: pad),
                glide: glide, size: size, scale: scale, in: context)
        }
        drawBase(
            layout, tokens, word: word, mode: style.mode, spoken: spoken, upcoming: upcoming,
            in: context)

        guard active >= 0, active < tokens.count else { return }
        let activeInk = style.activeColor.map { ink(props, $0) } ?? base
        let filled: Double? = fill.map { min(max($0, 0), 1) }
        for piece in activePieces {
            let pill = piece.pill
            let bounds = piece.bounds
            context.saveGState()
            // (a) the pop, about the pill's centre.
            context.translateBy(x: pill.midX, y: pill.midY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -pill.midX, y: -pill.midY)
            // (b) the pill, unclipped — unless it glides, and is already
            // down under the base pass.
            if glidingPlate == nil, let plate = style.activePill {
                fillPlate(plate, in: pill, size: size, in: context)
            }
            // (c) the token, clipped at its midpoints in text space, and at
            // the fill's edge when it is filling.
            if let filled {
                let edge = filled >= 1
                    ? bounds.right
                    : snappedToDevice(
                        piece.left + CGFloat(filled) * (piece.right - piece.left), y: pill.midY,
                        in: context)
                drawToken(
                    activeInk, line: piece.line, left: bounds.left, right: edge, height: height,
                    in: context)
                if style.mode == .highlight, edge < bounds.right {
                    drawToken(
                        upcoming, line: piece.line, left: edge, right: bounds.right,
                        height: height, in: context)
                }
            } else {
                drawToken(
                    activeInk, line: piece.line, left: bounds.left, right: bounds.right,
                    height: height, in: context)
            }
            context.restoreGState()
        }
    }

    /// A gliding pill's plate: between `from`'s pill and `to`'s at
    /// `easeOut(glide)` while it slides and each is one piece, else on
    /// `to`'s pieces, settled. A nil `glide` is a page's first word, or a
    /// caller with no recipe (the sheet's preview): settled.
    private static func drawGlidingPlate(
        _ plate: ActivePill, to: [TokenPiece], from: [TokenPiece], glide: Double?, size: CGFloat,
        scale: CGFloat, in context: CGContext
    ) {
        var rects = to.map { $0.pill }
        let travel = CGFloat(easeOut(min(max(glide ?? 1, 0), 1)))
        if travel < 1, to.count == 1, from.count == 1 {
            let a = from[0].pill
            let b = to[0].pill
            rects = [
                CGRect(
                    x: a.minX + (b.minX - a.minX) * travel,
                    y: a.minY + (b.minY - a.minY) * travel,
                    width: a.width + (b.width - a.width) * travel,
                    height: a.height + (b.height - a.height) * travel)
            ]
        }
        for rect in rects {
            fillPlate(plate, in: rect, size: size, scale: scale, in: context)
        }
    }

    /// The base pass: every token but the active one, `word − 1`.
    private static func drawBase(
        _ layout: TextLayout, _ tokens: [Range<Int>], word: Int, mode: WordMode, spoken: WordInk,
        upcoming: WordInk, in context: CGContext
    ) {
        let active = word - 1
        let height = layout.size.height
        for (index, laid) in layout.lines.enumerated() {
            let line = laid.range.location..<(laid.range.location + laid.range.length)
            // `tokensOnLine`: the tokens with ink on THIS line.
            let here = tokensOnLine(tokens, line)
            for (position, token) in here.enumerated() where token != active {
                if token >= word, mode == .build { continue }
                let bounds = clipBounds(layout, laid, tokens, here, position, line)
                drawToken(
                    token >= word ? upcoming : spoken, line: index, left: bounds.left,
                    right: bounds.right, height: height, in: context)
            }
        }
    }
}
