import Foundation

/// The three LOOKS a caption run may add to a word style's pages (spec §11
/// W-15, issue batch B86): a pill that slides between words, a word that
/// fills as it is spoken, and a dim in pauses — format version 12's
/// `active_pill.glide`, `active_fill` and `pause_dim` (W-12).
///
/// A value, like `CaptionStyle` a GENERATION choice: the sheet's three
/// checkboxes and `transcribe`'s `slide` / `fill` / `dim` each make one, and
/// `CaptionLayout.place` — still the one app-side writer of `word_style`
/// (W-10) — writes it through `CaptionStyle.wordStyle(_:)`. The six presets
/// are not edited: with `.none` every page is the preset's own.
///
/// **What is live when is derived, never a table.** `Look.isLive(for:)` reads
/// the style's own `wordStyle`, and `styles` / `styleList` are that rule run
/// over `CaptionStyle.allCases` — the one list the tool's descriptions and
/// its refusals print, so a seventh style needs no edit here.
///
/// **The looks ride outside the measurement.** `CaptionPages.Request` does not
/// carry them: none of the three moves a glyph or the box (W-14), so the
/// pager's measured page and the committed one differ only in these keys.
struct CaptionLooks: Equatable {
    var slide = false
    var fill = false
    var dim = false

    static let none = CaptionLooks()

    /// The `pause_dim` a ticked Dim writes: half. The sheet has no depth
    /// control (the owner's choice, W-15).
    static let dimDepth = 0.5

    /// The remembered boxes, each a Bool in the sheet's `defaults`; an absent
    /// key is off. Read when the row is built and written by a click
    /// (`TranscribeSheetController+Looks.swift`); the tool never reads them
    /// (R6-2 read across).
    static let slideKey = "FrameJobCaptionSlide"
    static let fillKey = "FrameJobCaptionFill"
    static let dimKey = "FrameJobCaptionDim"

    /// One look. The raw value is `transcribe`'s argument name.
    enum Look: String, CaseIterable {
        case slide
        case fill
        case dim

        /// The checkbox's title.
        var title: String {
            switch self {
            case .slide: return "Slide the pill"
            case .fill: return "Fill words as spoken"
            case .dim: return "Dim in pauses"
            }
        }

        var defaultsKey: String {
            switch self {
            case .slide: return CaptionLooks.slideKey
            case .fill: return CaptionLooks.fillKey
            case .dim: return CaptionLooks.dimKey
            }
        }

        /// Whether the look shows anything on this style's pages: a slide
        /// needs a pill; a fill needs something different either side of its
        /// edge — `build`'s undrawn word, or an upcoming colour that is not
        /// the active one; a dim needs only a word style.
        func isLive(for style: CaptionStyle) -> Bool {
            guard let word = style.wordStyle else { return false }
            switch self {
            case .slide:
                return word.activePill != nil
            case .fill:
                let active = word.activeColor ?? style.color
                let upcoming = word.upcomingColor ?? style.color
                return word.mode == .build || active != upcoming
            case .dim:
                return style.isWordStyle
            }
        }

        /// The styles the look is live with, in `CaptionStyle.allCases` order.
        var styles: [CaptionStyle] { CaptionStyle.allCases.filter(isLive) }

        /// `styles`' raw values as a phrase: "a", "a or b", "a, b or c".
        var styleList: String {
            let names = styles.map(\.rawValue)
            guard let last = names.last, names.count > 1 else { return names.first ?? "" }
            return names.dropLast().joined(separator: ", ") + " or " + last
        }
    }

    subscript(look: Look) -> Bool {
        get {
            switch look {
            case .slide: return slide
            case .fill: return fill
            case .dim: return dim
            }
        }
        set {
            switch look {
            case .slide: slide = newValue
            case .fill: fill = newValue
            case .dim: dim = newValue
            }
        }
    }

    /// These looks with every one that is not live for `style` cleared.
    func live(for style: CaptionStyle) -> CaptionLooks {
        var out = CaptionLooks.none
        for look in Look.allCases where self[look] && look.isLive(for: style) {
            out[look] = true
        }
        return out
    }

    /// The looks that are on, by argument name, in `Look.allCases` order.
    var names: [String] { Look.allCases.filter { self[$0] }.map(\.rawValue) }
}

extension CaptionStyle {

    /// The preset's `wordStyle` with the looks that are LIVE for this style
    /// turned on, and nothing else changed: every other field of the preset
    /// is carried across by name (`WordStyle` and `ActivePill` are all-`let`
    /// with defaulted inits, so a field left out here would compile and
    /// silently reset). `wordStyle(.none)` is `wordStyle`; nil for Subtitles.
    func wordStyle(_ looks: CaptionLooks) -> WordStyle? {
        guard let preset = wordStyle else { return nil }
        let live = looks.live(for: self)
        guard live != .none else { return preset }
        let pill = preset.activePill.map {
            ActivePill(
                color: $0.color, padding: $0.padding, radius: $0.radius,
                glide: live.slide || $0.glide)
        }
        return WordStyle(
            mode: preset.mode,
            activeColor: preset.activeColor,
            activeScale: preset.activeScale,
            activePill: pill,
            spokenColor: preset.spokenColor,
            upcomingColor: preset.upcomingColor,
            activeFill: live.fill || preset.activeFill,
            pauseDim: live.dim ? CaptionLooks.dimDepth : preset.pauseDim)
    }
}
