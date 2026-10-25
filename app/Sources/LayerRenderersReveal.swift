import AppKit
import CoreText

/// The three REVEAL routines of `LayerRenderers`' text half — a typewriter's
/// prefix of the glyphs, a `word_fade`'s per-word alpha, a `line_rise`'s
/// per-line offset and alpha — and the stagger arithmetic they share.
///
/// A pure move out of `LayerRenderersText.swift` (road map 8's W3 toll: that
/// file stood at 577 against the ~600 cap before the fourth text routine,
/// the word caption, could land beside it). `drawText` stays there and
/// dispatches here; the layout, the laid-line drawing, the one-composite
/// fade, the tokenizer and the whitespace midpoint stay there too and widen
/// from `private` to internal, because `private` on an extension member
/// reaches only its own file. The three routines widen for the same reason;
/// beside them only the word-clip geometry `wordFade` shares with the word
/// caption crosses (`tokensOnLine`, `clipBounds`, `drawClipped`, #363).
extension LayerRenderers {

    /// Each word's fade is half covered by the next one's, so a `word_fade`
    /// reads as a wave over the line rather than as one word at a time. It is
    /// a constant and not a schema field: the animation has three keys, and
    /// whatever number is chosen here ships as the animation's identity.
    private static let wordOverlap = 0.5

    /// How far a `line_rise` line travels, as a fraction of its own height —
    /// far enough to read as movement, near enough that the line is legible
    /// for most of its arrival.
    private static let lineRiseFraction = 0.35

    /// Item `index` of `count`'s own 0…1 progress at an overall `amount`,
    /// each item's span overlapping its neighbour's by `wordOverlap`.
    ///
    /// Exact at both ends — every item is 0 at amount 0 and 1 at amount 1,
    /// which is what lets the two ends of an animation match the static frame
    /// — and correct for a single item, whose span is the whole ramp.
    private static func staggered(_ amount: Double, index: Int, count: Int) -> Double {
        guard count > 1 else { return min(max(amount, 0), 1) }
        let span = 1 / (1 + Double(count - 1) * (1 - wordOverlap))
        let start = Double(index) * span * (1 - wordOverlap)
        return min(max((amount - start) / span, 0), 1)
    }

    /// An item's place in the stagger, REVERSED while the text is leaving, so
    /// it goes the way it came: the first word in is the first word out.
    /// Reversing the amount alone would run the whole animation backwards and
    /// read as a rewind, which is what `reveal_phase` is carried for.
    ///
    /// The typewriter needs none of this — its un-reveal is a shrinking
    /// prefix, which is already the reverse of a growing one (it backspaces),
    /// so it reads the amount and ignores the phase.
    private static func staggerIndex(_ index: Int, count: Int, leaving: Bool) -> Int {
        leaving ? count - 1 - index : index
    }

    /// The UTF-16 offset a typewriter has reached, counted in GRAPHEME
    /// CLUSTERS of the content and floored.
    ///
    /// CoreText indexes UTF-16 and a Swift `Character` is a cluster, so
    /// counting code units would split an emoji or a combining mark and
    /// reveal half a character. Whitespace and newlines COUNT, so the type
    /// pauses at a space and at a line break — the conventional look, and no
    /// special case in the drawing.
    private static func typedPrefix(of content: String, amount: Double) -> Int {
        var boundaries = content.indices.map { $0.utf16Offset(in: content) }
        boundaries.append(content.utf16.count)
        let clusters = boundaries.count - 1
        guard clusters > 0 else { return 0 }
        let shown = Int((Double(clusters) * amount).rounded(.down))
        return boundaries[min(max(shown, 0), clusters)]
    }

    /// A prefix of the glyphs, revealed by CLIPPING the laid-out line — never
    /// by laying out a prefix of the string.
    ///
    /// A framesetter over a substring re-runs shaping: it would kern against
    /// a different next character, resolve a ligature spanning the cut
    /// differently, and shift glyphs sub-pixel as the reveal advanced.
    /// Clipping guarantees every revealed glyph sits at exactly the pixel the
    /// full draw puts it at, which is the whole meaning of "the layout is
    /// always the full text's".
    ///
    /// The cut lands on a character's advance, so a glyph whose neighbour
    /// overhangs it can be shaved by a fraction of a pixel. That is what a
    /// typewriter looks like. For BIDIRECTIONAL text a prefix of the string
    /// is not one run of x, and the single clip rect will reveal the wrong
    /// part of the line — a known limit, not a silent one.
    static func typewriter(
        _ layout: TextLayout, content: String, amount: Double, in context: CGContext
    ) {
        let shown = typedPrefix(of: content, amount: amount)
        for laid in layout.lines {
            if laid.range.location >= shown { continue }
            if laid.range.location + laid.range.length <= shown {
                drawLaidLine(laid, in: context)
                continue
            }
            let cut = laid.origin.x + CTLineGetOffsetForStringIndex(laid.line, shown, nil)
            context.saveGState()
            context.clip(
                to: CGRect(x: 0, y: 0, width: max(cut, 0), height: layout.size.height))
            drawLaidLine(laid, in: context)
            context.restoreGState()
        }
    }

    /// Per-word alpha with a stagger: each token is drawn as its own clipped
    /// pass over the line it sits on.
    ///
    /// The clip is cut in the WHITESPACE — from the middle of the gap on the
    /// left to the middle of the gap on the right — never at a glyph edge.
    /// Two clip rects meeting at a glyph double-composite the antialiased
    /// boundary pixel (0.5 over 0.5 is 0.75 coverage, not 1) and would leave
    /// a hairline seam down the word; cutting in the gap puts every seam
    /// where there is no ink to composite twice.
    static func wordFade(
        _ layout: TextLayout, content: String, amount: Double, leaving: Bool,
        in context: CGContext
    ) {
        let tokens = tokens(of: content)
        guard !tokens.isEmpty else { return }
        for laid in layout.lines {
            let line = laid.range.location..<(laid.range.location + laid.range.length)
            let here = tokensOnLine(tokens, line)
            for (position, token) in here.enumerated() {
                let alpha = staggered(
                    amount, index: staggerIndex(token, count: tokens.count, leaving: leaving),
                    count: tokens.count)
                guard alpha > 0 else { continue }
                let bounds = clipBounds(layout, laid, tokens, here, position, line)
                drawClipped(
                    laid, alpha: alpha, left: bounds.left, right: bounds.right,
                    height: layout.size.height, in: context)
            }
        }
    }

    /// Per-line alpha and offset, staggered top line first.
    ///
    /// The rise is MASKED BY THE BOX: the bitmap is exactly the measured box
    /// and the box may not grow (the overlay reads it), so a line still on
    /// its way up is cut off at the box's edge. Under a backdrop that reads
    /// as a deliberate mask reveal; without one the line slides out of
    /// nothing, which is the price of a texture that cannot move.
    static func lineRise(
        _ layout: TextLayout, amount: Double, leaving: Bool, in context: CGContext
    ) {
        let count = layout.lines.count
        for (index, laid) in layout.lines.enumerated() {
            let progress = staggered(
                amount, index: staggerIndex(index, count: count, leaving: leaving), count: count)
            guard progress > 0 else { continue }
            context.saveGState()
            // CoreGraphics is y-UP here, so a NEGATIVE offset starts the line
            // low and it rises into place as its progress reaches 1 — and on
            // the way out it sinks back down, which is the fall a departure
            // should be. The phase changes the ORDER, not the direction.
            context.translateBy(x: 0, y: -laid.height * lineRiseFraction * (1 - progress))
            drawFaded(laid, alpha: progress, in: context)
            context.restoreGState()
        }
    }
}
