import AppKit

/// How a clip's KIND is spelled in the chrome: its tint, its symbol and the
/// one word that names it.
///
/// Three places show the same chip — the timeline clip's name strip, the
/// timeline bar's selection block and the inspector's selection header — and
/// they must agree, so the mapping lives here rather than three times over.
/// The tint itself is still `TimelineView.tint(for:)`: it is spec §4.4's
/// table and there is no reason to have two of it.
enum ClipKindStyle {
    /// The SF Symbol for a clip's kind, with the glyph to fall back to when
    /// the symbol is missing (the `GhostButton` rule).
    static func symbol(for clip: ClipSnapshot) -> (name: String, fallback: String) {
        switch clip.source {
        case .media:
            return clip.enabled.video ? ("film", "▦") : ("waveform", "∿")
        case .still:
            return ("snowflake", "❄")
        case .image:
            return ("photo", "▣")
        case .text:
            return ("textformat", "T")
        case .shape:
            return ("square.on.circle", "▭")
        case .nest:
            return ("square.stack.3d.down.right", "▤")
        }
    }

    /// The lowercase word under a clip's name in a selection block — "video",
    /// "audio", "still", "image", "text", "shape", "nest". `media` is the one
    /// kind whose word depends on the clip: a detached audio twin is a media
    /// clip with its video half off, and calling that "video" would be a lie.
    static func name(for clip: ClipSnapshot) -> String {
        switch clip.source {
        case .media: return clip.enabled.video ? "video" : "audio"
        default: return clip.source.kindName
        }
    }

    /// The tint of the kind chip. One hop, so a call site never has to know
    /// that the table is the timeline's.
    static func tint(for clip: ClipSnapshot) -> NSColor { TimelineView.tint(for: clip) }
}
