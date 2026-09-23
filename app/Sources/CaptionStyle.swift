import Foundation

/// The caption STYLES of road map 8 §5h — Subtitles and the five word
/// styles a generated caption track can be made in. A style is a GENERATION
/// choice (spec §11 W-10): it decides how `CaptionPages` fills a page and
/// what `CaptionLayout.place` writes into each text clip, and it is not an
/// inspector preset — `TextPreset.all` stays the Text pane's four rows.
///
/// **`font` is the PostScript name, verbatim** — what `TextProps.font`
/// carries and what `CTFontCreateWithName` is asked for. W0 q6 measured
/// each of the four bundled faces round-tripping (road map 8 §5a).
///
/// Sizes are fractions of `min(W, H)`, so a vertical and a horizontal
/// canvas get the same line height and the width is the pager's job; `y`
/// is a fraction of H, measured to the box's centre, positive downwards.
///
/// `.subtitles` is here so a caller has one vocabulary for the choice. Its
/// rows are never read for placement: `place` takes today's Caption-preset
/// path for it, byte for byte, and `CaptionCues.build` makes its cues.
///
/// A word style's page is ONE page in three places: `textProps` is what the
/// pager measures and what the sheet previews, and `pagePatch`, built from
/// it, is what `place` writes — so a committed page is the measured one.
enum CaptionStyle: String, CaseIterable {
    case subtitles
    case highlight
    case pill
    case karaoke
    case build
    case oneWord = "one_word"

    /// The remembered choice (road map 8 §5e): read and written by the
    /// sheet's Style popup alone (W4b); an agent call never reads it (R6-2's
    /// rule for the engine, read across).
    static let defaultsKey = "ReelcutCaptionStyle"

    var displayName: String {
        switch self {
        case .subtitles: return "Subtitles"
        case .highlight: return "Highlight"
        case .pill: return "Pill"
        case .karaoke: return "Karaoke"
        case .build: return "Build"
        case .oneWord: return "One Word"
        }
    }

    /// Every style but Subtitles pages by width and writes `words`.
    var isWordStyle: Bool { self != .subtitles }

    var font: String {
        switch self {
        case .subtitles: return "SourceSans3-Regular"
        case .highlight: return "Montserrat-Black"
        case .pill, .karaoke: return "Montserrat-ExtraBold"
        case .build: return "Anton-Regular"
        case .oneWord: return "BebasNeue-Regular"
        }
    }

    var textCase: TextCase {
        switch self {
        case .subtitles, .karaoke: return .asWritten
        case .highlight, .pill, .build, .oneWord: return .upper
        }
    }

    /// Of `min(W, H)`: 0.075, and One Word's ×1.6.
    var sizeFraction: Double { self == .oneWord ? 0.12 : 0.075 }

    /// Of H, to the box's centre.
    var yFraction: Double {
        switch self {
        case .subtitles: return 0.38
        case .highlight, .pill, .build: return 0.25
        case .karaoke: return 0.28
        case .oneWord: return 0.18
        }
    }

    /// The base colour: white for every style.
    var color: RGBA { [1, 1, 1, 1] }

    /// A black outline's width in em, or nil for none.
    var outlineEm: Double? {
        switch self {
        case .highlight, .build, .oneWord: return 0.08
        case .subtitles, .pill, .karaoke: return nil
        }
    }

    /// How the spoken word is shown — nil for Subtitles.
    var wordStyle: WordStyle? {
        let yellow: RGBA = [1, 0.85, 0, 1]
        switch self {
        case .subtitles:
            return nil
        case .highlight:
            return WordStyle(activeColor: yellow, activeScale: 1.12)
        case .pill:
            return WordStyle(activePill: ActivePill())
        case .karaoke:
            return WordStyle(
                activeColor: yellow, spokenColor: yellow, upcomingColor: [1, 1, 1, 0.55])
        case .build:
            return WordStyle(mode: .build, activeColor: yellow, activeScale: 1.15)
        case .oneWord:
            return WordStyle(activeScale: 1.2)
        }
    }

    /// One Word's page is one word; every other style's is the width's.
    var maxWords: Int? { self == .oneWord ? 1 : nil }

    /// Karaoke pages to two lines by design (§5h's footnote); nothing else
    /// wraps a multi-word page.
    var maxLines: Int { self == .karaoke ? 2 : 1 }

    /// The style's font size on this canvas, in canvas pixels.
    func size(for canvas: CGSize) -> Double {
        (sizeFraction * Double(min(canvas.width, canvas.height))).rounded()
    }

    /// The page as it will be placed — THE construction, read three ways:
    /// the pager hands it `LayerRenderers.measuredSize(for:)`, the sheet
    /// previews it, and `pagePatch` writes its values. `width` nil lays it on
    /// one line (or on its own hard breaks); `words` stays empty, which the
    /// measurement does not read.
    func textProps(content: String, size: Double, width: Double?) -> TextProps {
        TextProps(
            content: content, font: font, size: size, color: color, align: "center",
            valign: "middle",
            outline: outlineEm.map { OutlineProps(width: $0 * size, color: [0, 0, 0, 1]) },
            width: width, textCase: textCase, wordStyle: wordStyle)
    }

    /// One page's `text` patch, what `place` writes: `textProps(content:size:width:)`'s
    /// own values — so the committed page IS the page the pager measured and
    /// the sheet shows; the outline is em × THIS size, shrunk or not (the
    /// pill's padding and radius are fractions of `size` at render time, and
    /// `width` is the budget in pixels by design) — plus the page's `words` in
    /// CLIP time.
    func pagePatch(content: String, size: Double, width: Double?, words: [TextWord]?) -> TextPatch {
        let props = textProps(content: content, size: size, width: width)
        return TextPatch(
            content: props.content, font: props.font, size: props.size, color: props.color,
            align: props.align, valign: props.valign,
            outline: props.outline.map { .some($0) },
            width: props.width.map { .some($0) }, textCase: props.textCase, words: words,
            wordStyle: props.wordStyle)
    }
}
