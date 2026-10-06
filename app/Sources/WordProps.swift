import Foundation

/// The word-caption vocabulary (format version 9, road map 8's W3) — the
/// mirror of `core/src/model_words.rs`: `TextCase`, the `TextWord` timings a
/// caption page carries, and the `WordStyle` (with its `WordMode` and
/// `ActivePill`) that says how the word being spoken is drawn.
///
/// **A word caption is an ordinary text clip holding one PAGE** (spec §11,
/// W-1): `content` is the page, `words` is one `{start, end}` per
/// whitespace token of it in CLIP ticks, and `word_style` is how the
/// renderer shows which of them has been said. Nothing on this side times
/// anything: the core computes the five word keys per frame
/// (`RecipeReveal`) and `LayerRenderersWords.swift` draws them. Format
/// version 12 (spec §11 W-12) added `ActivePill.glide`,
/// `WordStyle.activeFill` and `WordStyle.pauseDim`, each off by default.
///
/// Decoding is LENIENT for `ProjectSnapshot.swift`'s reason — these are
/// values the CORE wrote — and every default mirrors the core's `Default`.
/// A caller's object is never decoded through them (app/CLAUDE.md).
///
/// Beside the types: the four `TextProps` facts the renderer and the
/// inspector share, `TextPatch.contentEdit` and the `InspectorBinding`
/// write that sends the Content field (W-2, W-6), which lives here rather
/// than in `InspectorPane.swift` (on the ledger) for the size rule alone.

// MARK: - Kinds

/// A transform applied to `content` before layout. Part of the layout key —
/// it changes the measured width — and it never changes the token count.
/// Decoded by RAW VALUE, which `.convertFromSnakeCase` never touches, so the
/// snake-case spelling is written by hand.
enum TextCase: String, Codable, CaseIterable {
    case asWritten = "as_written"
    case upper
}

/// How the words not yet active are shown: `highlight` draws the whole page
/// and picks the active word out; `build` hides the upcoming ones.
enum WordMode: String, Codable, CaseIterable {
    case highlight
    case build
}

// MARK: - Values

/// When one whitespace token of `content` is said, in CLIP ticks. A negative
/// `start` is legal ("already said", after a split).
struct TextWord: Codable, Equatable {
    let start: Ticks
    let end: Ticks

    init(start: Ticks = 0, end: Ticks = 0) {
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.lenient(.start, 0)
        end = c.lenient(.end, 0)
    }

    var dictionary: [String: Any] { ["start": start, "end": end] }
}

/// The rounded plate behind the active word. `padding` and `radius` are
/// FRACTIONS of the text's `size`; `glide` slides the plate from the word
/// before to the active one instead of jumping (format version 12).
struct ActivePill: Codable, Equatable {
    let color: RGBA
    let padding: Double
    let radius: Double
    let glide: Bool

    init(
        color: RGBA = [0.55, 0.27, 0.93, 1], padding: Double = 0.2, radius: Double = 0.25,
        glide: Bool = false
    ) {
        self.color = color
        self.padding = padding
        self.radius = radius
        self.glide = glide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.lenient(.color, [0.55, 0.27, 0.93, 1])
        padding = c.lenient(.padding, 0.2)
        radius = c.lenient(.radius, 0.25)
        glide = c.lenient(.glide, false)
    }

    var dictionary: [String: Any] {
        ["color": color, "padding": padding, "radius": radius, "glide": glide]
    }
}

/// How a timed page shows which word is being said (W-4). A nil colour means
/// "the text's own colour"; `activeScale` is where the pop settles, 1…1.5.
/// `activeFill` fills the active word left to right as it is said, and
/// `pauseDim` (0 off … 1 invisible) is how far the page dims in a pause
/// (format version 12, W-12).
struct WordStyle: Codable, Equatable {
    let mode: WordMode
    let activeColor: RGBA?
    let activeScale: Double
    let activePill: ActivePill?
    let spokenColor: RGBA?
    let upcomingColor: RGBA?
    let activeFill: Bool
    let pauseDim: Double

    init(
        mode: WordMode = .highlight, activeColor: RGBA? = nil, activeScale: Double = 1,
        activePill: ActivePill? = nil, spokenColor: RGBA? = nil, upcomingColor: RGBA? = nil,
        activeFill: Bool = false, pauseDim: Double = 0
    ) {
        self.mode = mode
        self.activeColor = activeColor
        self.activeScale = activeScale
        self.activePill = activePill
        self.spokenColor = spokenColor
        self.upcomingColor = upcomingColor
        self.activeFill = activeFill
        self.pauseDim = pauseDim
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.lenient(.mode, WordMode.highlight)
        activeColor = c.lenient(.activeColor)
        activeScale = c.lenient(.activeScale, 1)
        activePill = c.lenient(.activePill)
        spokenColor = c.lenient(.spokenColor)
        upcomingColor = c.lenient(.upcomingColor)
        activeFill = c.lenient(.activeFill, false)
        pauseDim = c.lenient(.pauseDim, 0)
    }

    /// ALL eight keys, `NSNull` for a nil slot — `MotionProps.dictionary`'s
    /// rule (app/CLAUDE.md): the core deep-merges `word_style`, so a key
    /// left out would keep whatever the clip already had.
    var dictionary: [String: Any] {
        [
            "mode": mode.rawValue,
            "active_color": activeColor.map { $0 as Any } ?? NSNull(),
            "active_scale": activeScale,
            "active_pill": activePill.map { $0.dictionary as Any } ?? NSNull(),
            "spoken_color": spokenColor.map { $0 as Any } ?? NSNull(),
            "upcoming_color": upcomingColor.map { $0 as Any } ?? NSNull(),
            "active_fill": activeFill,
            "pause_dim": pauseDim,
        ]
    }
}

// MARK: - What the renderer and the inspector read

extension TextProps {
    /// The string that is LAID OUT: `content` with `case` applied. Every
    /// layout, measurement and string index in the renderer is in this
    /// string's UTF-16 space — `uppercased()` can change a token's LENGTH
    /// ("ß" → "SS") though never the token count. The Unicode default
    /// mapping, no locale, so a page lays out the same on every Mac.
    var laidContent: String { textCase == .upper ? content.uppercased() : content }

    /// Whitespace tokens of `content` — the count the core's
    /// `split_whitespace` gives (road map 8's W0 q4 measured the two equal).
    var tokenCount: Int { content.split(whereSeparator: \.isWhitespace).count }

    /// A styled page with no timings: what a content edit that changed the
    /// word count leaves behind. It draws static, and the Content section
    /// says so.
    var isUntimedPage: Bool { wordStyle != nil && words.isEmpty }

    /// The same description in another fill colour — the key a second
    /// cached layout is drawn from (`frameKey` carries the colour).
    func recolored(_ color: RGBA) -> TextProps {
        TextProps(
            content: content, font: font, size: size, color: color, align: align,
            valign: valign, lineSpacing: lineSpacing, tracking: tracking, outline: outline,
            backdrop: backdrop, width: width, animation: animation, textCase: textCase,
            words: words, wordStyle: wordStyle)
    }
}

extension TextPatch {
    /// Per clip: `TextPatch(content:)` when `props.words` is empty or the new
    /// content has as many tokens as there are timings — the timings are
    /// kept — else `TextPatch(content:, words: [])`, because the core ERRORS
    /// on a timed page whose count no longer matches (W-2).
    static func contentEdit(_ content: String, over props: TextProps) -> TextPatch {
        let count = content.split(whereSeparator: \.isWhitespace).count
        if props.words.isEmpty || count == props.words.count {
            return TextPatch(content: content)
        }
        return TextPatch(content: content, words: [])
    }
}

// MARK: - The Content field's write

extension InspectorBinding {
    /// One selected text clip as the Content write sees it: its id, its
    /// props as the inspector reads them, and the action under the playhead.
    struct ContentTarget {
        let id: UInt32
        let props: TextProps
        let action: UInt32?
    }

    /// The ops a Content edit sends. Pure, so a probe can call it.
    ///
    /// `split`'s order: first ONE `set_text` over the base clips whose own
    /// count no longer matches, carrying `words: []`; then one `set_text`
    /// over the other base clips with the content alone; then one
    /// `set_action_end` per clip inside an action, with the content alone —
    /// NEVER `words` there, which the core refuses as an action target
    /// (W-6), while a content-only end is accepted and draws static where
    /// the counts disagree. Decided PER CLIP, because the binding's
    /// `textProps` is only the first clip's. An empty group emits nothing.
    static func contentOps(_ content: String, over targets: [ContentTarget]) -> [ReelOp] {
        var untimed: [UInt32] = []
        var kept: [UInt32] = []
        var inside: [ReelOp] = []
        for target in targets {
            if let action = target.action {
                inside.append(
                    .setActionEnd(
                        clip: target.id, action: action,
                        patch: ActionPatch(text: TextPatch(content: content))))
            } else if TextPatch.contentEdit(content, over: target.props).words != nil {
                untimed.append(target.id)
            } else {
                kept.append(target.id)
            }
        }
        var ops: [ReelOp] = []
        if !untimed.isEmpty {
            ops.append(.setText(clips: untimed, patch: TextPatch(content: content, words: [])))
        }
        if !kept.isEmpty { ops.append(.setText(clips: kept, patch: TextPatch(content: content))) }
        return ops + inside
    }

    /// The selection's Content write.
    func ops(textContent content: String) -> [ReelOp] {
        Self.contentOps(
            content,
            over: textClips.map {
                ContentTarget(id: $0.id, props: text($0), action: action($0)?.id)
            })
    }
}
