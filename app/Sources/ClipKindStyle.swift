import AppKit

/// How a clip's KIND is spelled in the chrome: its tint, its symbol and the
/// one word that names it.
///
/// Four places show the same chip — the timeline clip's name strip, the
/// timeline bar's selection block, the inspector's selection header and the
/// Media tab — and they must agree, so the mapping lives here rather than four
/// times over. It is spec §4.4's table ("video slate, audio green, still
/// violet, text amber, shape teal, nest grey"), moved out of `TimelineView`
/// now that three views other than the timeline read it.
///
/// **Every entry point takes the snapshot**, and that is the one substantive
/// change to the old mapping. It used to answer for a `media` clip from
/// `clip.enabled.video` alone, which is the DETACH switch, not a fact about
/// the file: an imported mp3 has `enabled.video == true` (nothing ever turned
/// it off) and so drew slate blue with a filmstrip icon and called itself
/// "video" in two selection blocks. Only the media entry knows whether there
/// are pixels, so the tests are `media.hasVideo` and `media.hasAudio`, exactly
/// as `TimelineView.hasVideo` / `hasAudio` ask them — a clip reads as audio
/// when it has no picture to show, whether that is because the file has none
/// or because Detach Audio took it away.
enum ClipKindStyle {
    /// The kinds the chrome distinguishes. Not `ClipSource`'s cases: `media`
    /// splits by what the file actually holds, and `still` and `image` share
    /// one ink because both are a picture that does not move.
    enum Kind {
        case video
        case audio
        case still
        case text
        case shape
        case graphic
        case nest
        case adjustment
    }

    static func kind(of clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Kind {
        switch clip.source {
        case .media:
            let hasPicture = clip.enabled.video && (snapshot.media(for: clip)?.hasVideo ?? false)
            return hasPicture ? .video : .audio
        case .still, .image:
            return .still
        case .text:
            return .text
        case .shape:
            return .shape
        case .graphic:
            return .graphic
        case .nest:
            return .nest
        case .adjustment:
            return .adjustment
        }
    }

    /// The clip tint of spec §4.4, from `Theme.swift`'s tokens.
    static func tint(for clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> NSColor {
        switch kind(of: clip, in: snapshot) {
        case .video: return DS.clipVideo
        case .audio: return DS.clipAudio
        case .still: return DS.clipStill
        case .text: return DS.clipText
        case .shape: return DS.clipShape
        // Shape's ink until road map 10's G5 gives a graphic a token.
        case .graphic: return DS.clipShape
        case .nest: return DS.clipNest
        case .adjustment: return DS.clipAdjustment
        }
    }

    /// The SF Symbol for a clip's kind, with the glyph to fall back to when
    /// the symbol is missing (the `GhostButton` rule).
    static func symbol(
        for clip: ClipSnapshot, in snapshot: ProjectSnapshot
    ) -> (name: String, fallback: String) {
        switch kind(of: clip, in: snapshot) {
        case .video: return ("film", "▦")
        case .audio: return ("waveform", "∿")
        case .still:
            if case .still = clip.source { return ("snowflake", "❄") }
            return ("photo", "▣")
        case .text: return ("textformat", "T")
        case .shape: return ("square.on.circle", "▭")
        case .graphic: return ("curlybraces", "{}")
        case .nest: return ("square.stack.3d.down.right", "▤")
        case .adjustment: return ("camera.filters", "◐")
        }
    }

    /// The lowercase word under a clip's name in a selection block.
    static func name(for clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> String {
        switch kind(of: clip, in: snapshot) {
        case .video: return "video"
        case .audio: return "audio"
        case .still:
            if case .still = clip.source { return "still" }
            return "image"
        case .text: return "text"
        case .shape: return "shape"
        case .graphic: return "graphic"
        case .nest: return "nest"
        case .adjustment: return "adjustment"
        }
    }
}
