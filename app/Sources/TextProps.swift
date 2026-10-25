import Foundation

/// The text group of the read-only mirror (spec §5.2's `text`), and the
/// recipe's account of one text layer's reveal: `TextAnimationKind`,
/// `OutlineProps`, `BackdropProps`, `TextAnimation`, `TextProps` and
/// `RecipeReveal`.
///
/// A pure move out of `ProjectSnapshot.swift` (2516 lines, on the ledger),
/// made before format version 9's three text fields and the recipe's two
/// word keys could land: Swift cannot add a stored property in an
/// extension, so the types had to leave the over-cap file before they could
/// grow. `MotionProps.swift` is the precedent. The decoding rules are
/// `ProjectSnapshot.swift`'s, stated once at its head — `lenient` and the
/// snake-case key strategy included.

/// The three text reveals of spec §4.3 (format version 5), closed at three.
///
/// `model_props.rs` argues the closure: each kind is a distinct drawing
/// routine in `LayerRenderers.renderText` — a prefix of the glyphs, a
/// per-word alpha ramp, a per-line offset and alpha — not a parameter of a
/// shared one, so there is no neutral kind to fall back to the way a
/// filter's `amount` falls back to 0. The core refuses an unknown one at the
/// serde boundary; HERE the lenient decode answers nil instead, which reads
/// as "no animation" and draws the whole text — the failure direction that
/// shows the words rather than hiding them.
///
/// The key decoding strategy converts KEYS and never VALUES, so the two
/// multi-word cases carry their snake_case spelling by hand, as `Curve` and
/// `TransitionKind` do.
enum TextAnimationKind: String, Codable, CaseIterable {
    case typewriter
    case wordFade = "word_fade"
    case lineRise = "line_rise"

    var displayName: String {
        switch self {
        case .typewriter: return "Typewriter"
        case .wordFade: return "Word Fade"
        case .lineRise: return "Line Rise"
        }
    }
}

/// A text outline (stroke), in canvas pixels.
struct OutlineProps: Codable, Equatable {
    var width: Double
    var color: RGBA

    init(width: Double = 2, color: RGBA = [0, 0, 0, 1]) {
        self.width = width
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 2)
        color = c.lenient(.color, [0, 0, 0, 1])
    }
}

/// The plate drawn behind text.
struct BackdropProps: Codable, Equatable {
    var color: RGBA
    var padding: Double
    var radius: Double

    init(color: RGBA = [0, 0, 0, 0.6], padding: Double = 12, radius: Double = 8) {
        self.color = color
        self.padding = padding
        self.radius = radius
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.lenient(.color, [0, 0, 0, 0.6])
        padding = c.lenient(.padding, 12)
        radius = c.lenient(.radius, 8)
    }
}

/// How a text layer arrives and how it leaves (format version 5).
///
/// Three keys and no fourth: `in` and `out` are DURATIONS, not times — the
/// reveal runs for `in` from the clip's own first frame and the un-reveal for
/// `out` back from its own last one, either of them 0 for "that end does not
/// happen". `model_props.rs` argues the missing curve field: the shape of the
/// motion is already in the kind, and easing between two arbitrary values is
/// what the action system is for.
///
/// Nothing in the app derives the reveal from THIS. The core turns it into
/// one number per frame and the recipe carries that number
/// (`RecipeReveal`); this type is what the inspector reads and writes, and
/// the recipe deliberately strips it out of the description it hands the
/// renderer so there can only ever be one answer to "how far along is it".
///
/// `in` is a Swift keyword, so the two durations are spelled out here and the
/// model's own key names live in `CodingKeys` — `ClipSource`'s arrangement,
/// for its reason. The key spelling is the contract with
/// `core/src/model_props.rs`'s `#[serde(rename = "in")]`; the property name
/// is this side's business alone.
struct TextAnimation: Codable, Equatable {
    var kind: TextAnimationKind
    /// How long the reveal takes, from the clip's first frame (the model's
    /// `in`).
    var inDuration: Ticks
    /// How long the un-reveal takes, back from the clip's last frame (the
    /// model's `out`).
    var outDuration: Ticks

    /// The core's own default (`TextAnimation::default`): a one-second
    /// typewriter that does not un-reveal. Mirrored rather than derived, so
    /// switching the inspector's popup on writes exactly what the core would
    /// have defaulted to had the key simply appeared.
    init(
        kind: TextAnimationKind = .typewriter, inDuration: Ticks = Ticks(ReelTime.perSecond),
        outDuration: Ticks = 0
    ) {
        self.kind = kind
        self.inDuration = inDuration
        self.outDuration = outDuration
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case inDuration = "in"
        case outDuration = "out"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, TextAnimationKind.typewriter)
        inDuration = c.lenient(.inDuration, Ticks(ReelTime.perSecond))
        outDuration = c.lenient(.outDuration, 0)
    }
}

/// A text clip's description. The model NEVER stores the measured layout
/// size — only `LayerRenderers` knows it, and it reports it to the canvas
/// overlay through a hash-keyed cache (§5.3, §11).
struct TextProps: Codable, Equatable {
    var content: String
    var font: String
    var size: Double
    var color: RGBA
    /// "left" | "center" | "right".
    var align: String
    /// "top" | "middle" | "bottom", within the box.
    var valign: String
    var lineSpacing: Double
    /// Letter spacing, in points.
    var tracking: Double
    var outline: OutlineProps?
    var backdrop: BackdropProps?
    /// Fixed box width in canvas pixels; nil auto-sizes to the content.
    var width: Double?
    /// How the words arrive and leave, or nil for text that is simply there
    /// for the length of its clip (format version 5). LAST, as it is in the
    /// model, and absent from `LayerRenderers.layoutKey` on purpose: an
    /// animation cannot move a glyph, and a per-frame value in that key
    /// would churn the measured-size cache and walk the overlay's handles.
    var animation: TextAnimation?
    /// Format version 9's three word-caption fields, in the model's order
    /// after `animation` (`core/src/model_text.rs`); their types and what
    /// they mean are `WordProps.swift`'s. `case` is a Swift keyword, so the
    /// property is `textCase` and the model's key lives in `CodingKeys`.
    var textCase: TextCase
    var words: [TextWord]
    var wordStyle: WordStyle?

    private enum CodingKeys: String, CodingKey {
        case content, font, size, color, align, valign, lineSpacing, tracking, outline, backdrop,
            width, animation, words, wordStyle
        case textCase = "case"
    }

    init(
        content: String = "", font: String = "SourceSans3-SemiBold", size: Double = 72,
        color: RGBA = [1, 1, 1, 1], align: String = "center", valign: String = "middle",
        lineSpacing: Double = 1, tracking: Double = 0, outline: OutlineProps? = nil,
        backdrop: BackdropProps? = nil, width: Double? = nil, animation: TextAnimation? = nil,
        textCase: TextCase = .asWritten, words: [TextWord] = [], wordStyle: WordStyle? = nil
    ) {
        self.content = content
        self.font = font
        self.size = size
        self.color = color
        self.align = align
        self.valign = valign
        self.lineSpacing = lineSpacing
        self.tracking = tracking
        self.outline = outline
        self.backdrop = backdrop
        self.width = width
        self.animation = animation
        self.textCase = textCase
        self.words = words
        self.wordStyle = wordStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = c.lenient(.content, "")
        font = c.lenient(.font, "SourceSans3-SemiBold")
        size = c.lenient(.size, 72)
        color = c.lenient(.color, [1, 1, 1, 1])
        align = c.lenient(.align, "center")
        valign = c.lenient(.valign, "middle")
        lineSpacing = c.lenient(.lineSpacing, 1)
        tracking = c.lenient(.tracking, 0)
        outline = c.lenient(.outline)
        backdrop = c.lenient(.backdrop)
        width = c.lenient(.width)
        animation = c.lenient(.animation)
        textCase = c.lenient(.textCase, TextCase.asWritten)
        words = c.lenient(.words, [])
        wordStyle = c.lenient(.wordStyle)
    }
}

/// A text layer's computed reveal (§7.3): how much of the text is showing at
/// this instant, which way it is going, and which of the three animations is
/// showing it.
///
/// The CORE computes all three, from `text.animation` and the clip's own
/// time, which is what makes a `render_frame` and an export of the same frame
/// agree by construction — they read one recipe. The layer's `hash` covers
/// them, so the texture cache key IS the picture, and the recipe strips
/// `animation` out of the description it carries: this is the renderer's only
/// account of the animation, and there is deliberately no second one.
///
/// Not `Codable`: the keys are SIBLINGS of `hash` and `text` inside the
/// tagged source object rather than a nested object, so `RecipeSourceRef`'s
/// `text` arm reads them through `init(siblingsOf:)` below. Grouping them here
/// is for the renderer's sake, not the wire's.
struct RecipeReveal: Equatable {
    /// 0 (nothing showing) through 1 (all of it), the un-reveal folded in.
    let amount: Double
    /// "in" while the arrival is holding the amount back, "out" once the
    /// departure is, nil with no animation. `RecipeTransition.role`'s shape,
    /// for its reason: one number cannot say which way it is going.
    let phase: String?
    /// Which drawing routine, or nil for a layer with no animation — which
    /// is also what an unreadable or unknown kind decodes to, so a newer
    /// core's fourth reveal draws the whole text rather than the wrong
    /// animation.
    let kind: TextAnimationKind?
    /// How many of a timed page's words have started, 0 to n — the active
    /// token is `word − 1` — or nil for a page that is not word-timed (no
    /// `word_style`, no `words`, or a count mismatch), which draws static.
    /// The core's `recipe_words.rs` computes it (format version 9).
    let word: Int?
    /// 0…1 through the active word's pop, holding 1 once it settles; nil
    /// before the first word or when `active_scale` is 1.
    let wordPop: Double?
    /// The three looks' answers (format version 12, spec §11 W-13), each
    /// 0…1 or nil: how far the pill has slid from token `word − 2` to the
    /// active one; how much of the active word is filled; how far into a
    /// pause's dim the page is. Nil when the style does not ask for it.
    let wordGlide: Double?
    let wordFill: Double?
    let wordDim: Double?

    init(
        amount: Double = 1, phase: String? = nil, kind: TextAnimationKind? = nil,
        word: Int? = nil, wordPop: Double? = nil, wordGlide: Double? = nil,
        wordFill: Double? = nil, wordDim: Double? = nil
    ) {
        self.amount = amount
        self.phase = phase
        self.kind = kind
        self.word = word
        self.wordPop = wordPop
        self.wordGlide = wordGlide
        self.wordFill = wordFill
        self.wordDim = wordDim
    }

    /// A layer with no animation: all of it, all of the time. The core's
    /// `Reveal::WHOLE`, and the fallback for a recipe this build cannot read
    /// — the failure direction that shows the words.
    static let whole = RecipeReveal()

    /// Whether the departure is what is holding the amount back.
    var isLeaving: Bool { phase == "out" }
}

/// The reveal's keys as `RecipeSourceRef`'s `text` arm carries them: SIBLINGS
/// of `hash` and `text` in the tagged source object, read and written here so
/// the over-cap `ProjectSnapshot.swift` holds none of them
/// (`RecipeSourceRef.graphic(from:)` is the pattern).
extension RecipeReveal {
    /// The core writes `reveal_phase`, `reveal_kind`, `word_pop` and the
    /// rest in snake case, which the converter hands over camel-cased: spell
    /// a key the way the converter does or it silently never matches.
    private enum SiblingKeys: String, CodingKey {
        case reveal, revealPhase, revealKind
        case word, wordPop, wordGlide, wordFill, wordDim
    }

    /// The amount falls back to 1 and the kind to nil, so a recipe this
    /// build cannot read draws the whole text rather than none of it.
    init(siblingsOf decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: SiblingKeys.self) else {
            self = .whole
            return
        }
        self.init(
            amount: c.lenient(.reveal, 1), phase: c.lenient(.revealPhase),
            kind: c.lenient(.revealKind), word: c.lenient(.word),
            wordPop: c.lenient(.wordPop), wordGlide: c.lenient(.wordGlide),
            wordFill: c.lenient(.wordFill), wordDim: c.lenient(.wordDim))
    }

    func encodeSiblings(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SiblingKeys.self)
        try c.encode(amount, forKey: .reveal)
        try c.encode(phase, forKey: .revealPhase)
        try c.encode(kind, forKey: .revealKind)
        try c.encode(word, forKey: .word)
        try c.encode(wordPop, forKey: .wordPop)
        try c.encode(wordGlide, forKey: .wordGlide)
        try c.encode(wordFill, forKey: .wordFill)
        try c.encode(wordDim, forKey: .wordDim)
    }
}
