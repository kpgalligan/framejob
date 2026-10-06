import Foundation

/// The typed text patch the op builders send (`set_text`, `add_text_clip`,
/// an action's end patch).
///
/// A pure move out of `ReelCore.swift` (1542 lines, on the ledger), made
/// before format version 9's `case` and `words` could land in it: Swift
/// cannot add a stored property in an extension, so the type had to leave
/// the over-cap file before it could grow. The `dictionary` extensions on
/// `OutlineProps`, `BackdropProps` and `TextAnimation` that it calls stay in
/// `ReelCore.swift` with every other property type's.

/// A sparse patch of text properties. `width` is three-state as well: nil
/// leaves the box alone, `.some(nil)` restores auto-sizing, `.some(w)` fixes
/// the width and wraps.
///
/// `animation` (format version 5) is three-state for the same reason and
/// with one extra trap of its own: it is an OBJECT, so `.some(a)` REPLACES
/// the whole animation rather than merging into it — a key the caller left
/// out of the object arrives as `TextAnimation`'s own default, not as the
/// clip's current value. `AgentCatalog`'s text-patch sentence says so, and
/// app/CLAUDE.md records the general rule for every nested object in a patch.
struct TextPatch: Codable, Equatable {
    var content: String?
    var font: String?
    var size: Double?
    var color: RGBA?
    var align: String?
    var valign: String?
    var lineSpacing: Double?
    var tracking: Double?
    var outline: OutlineProps??
    var backdrop: BackdropProps??
    var width: Double??
    /// LAST, as `animation` is the last key of the model's `TextProps` — the
    /// two orders are read side by side often enough to be worth keeping.
    var animation: TextAnimation??
    /// Format version 9: `case`, a Swift keyword and so `textCase` here, and
    /// `words`, where an EMPTY list is the sentence "this page is no longer
    /// timed" — what a content edit that changes the word count must send in
    /// the same patch, or the core errors (spec §11 W-2). `word_style` has
    /// ONE writer on this side, `CaptionLayout.place` for a word caption
    /// style (road map 8's W4a); the inspector never sets it (W-10). It is
    /// sent whole — `WordStyle.dictionary` writes all eight keys — because the
    /// core deep-merges it over its template.
    var textCase: TextCase?
    var words: [TextWord]?
    var wordStyle: WordStyle?

    private enum CodingKeys: String, CodingKey {
        case content, font, size, color, align, valign, lineSpacing, tracking, outline, backdrop,
            width, animation, words, wordStyle
        case textCase = "case"
    }

    init(
        content: String? = nil, font: String? = nil, size: Double? = nil, color: RGBA? = nil,
        align: String? = nil, valign: String? = nil, lineSpacing: Double? = nil,
        tracking: Double? = nil, outline: OutlineProps?? = nil, backdrop: BackdropProps?? = nil,
        width: Double?? = nil, animation: TextAnimation?? = nil, textCase: TextCase? = nil,
        words: [TextWord]? = nil, wordStyle: WordStyle? = nil
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
        content = c.lenient(.content)
        font = c.lenient(.font)
        size = c.lenient(.size)
        color = c.lenient(.color)
        align = c.lenient(.align)
        valign = c.lenient(.valign)
        lineSpacing = c.lenient(.lineSpacing)
        tracking = c.lenient(.tracking)
        outline = c.nullable(.outline)
        backdrop = c.nullable(.backdrop)
        width = c.nullable(.width)
        animation = c.nullable(.animation)
        textCase = c.lenient(.textCase)
        words = c.lenient(.words)
        wordStyle = c.lenient(.wordStyle)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let content = content { d["content"] = content }
        if let font = font { d["font"] = font }
        if let size = size { d["size"] = size }
        if let color = color { d["color"] = color }
        if let align = align { d["align"] = align }
        if let valign = valign { d["valign"] = valign }
        if let lineSpacing = lineSpacing { d["line_spacing"] = lineSpacing }
        if let tracking = tracking { d["tracking"] = tracking }
        if let outline = outline {
            if let outline = outline {
                d["outline"] = outline.dictionary
            } else {
                d["outline"] = NSNull()
            }
        }
        if let backdrop = backdrop {
            if let backdrop = backdrop {
                d["backdrop"] = backdrop.dictionary
            } else {
                d["backdrop"] = NSNull()
            }
        }
        if let width = width {
            if let width = width { d["width"] = width } else { d["width"] = NSNull() }
        }
        if let animation = animation {
            if let animation = animation {
                d["animation"] = animation.dictionary
            } else {
                d["animation"] = NSNull()
            }
        }
        if let textCase = textCase { d["case"] = textCase.rawValue }
        if let words = words { d["words"] = words.map { $0.dictionary } }
        if let wordStyle = wordStyle { d["word_style"] = wordStyle.dictionary }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}
