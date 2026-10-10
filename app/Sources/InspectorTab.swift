import AppKit

// MARK: - Tabs

/// The four tabs, in strip order: the three of the chrome cleanup — the
/// selected CLIP, the project's media, the document itself — and the
/// Assistant (spec §11 AI-4). The raw value is the strip index, so the order
/// is API.
///
/// It was six — Video, Audio, Text, Shape, Media, Document — and four of those
/// were the same thing viewed four ways: the selected clip. Collapsing them
/// took the whole tab-visibility policy with it (a disabled tab, a preferred
/// tab, a pin to defeat the preference), because a Clip tab that lists the
/// sections the SELECTION actually has is always the right tab for a clip.
/// `ClipPane.makeSections()` is where that decision moved to.
///
/// The four kind tests below — three of them outlived the tabs they were
/// written for — are now what decides which sections the Clip tab shows.
enum InspectorTab: Int, CaseIterable {
    case clip, media, document, assistant

    var title: String {
        switch self {
        case .clip: return "Clip"
        case .media: return "Media"
        case .document: return "Document"
        case .assistant: return "Assistant"
        }
    }

    /// Whether the clip puts pixels on the canvas — and the test that keeps
    /// an audio-only clip out of the video sections.
    static func hasPixels(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        switch clip.source {
        case .text, .shape, .graphic, .nest, .adjustment:
            return true
        case .media, .still, .image:
            guard let media = snapshot.media(for: clip) else { return false }
            return media.hasVideo || media.kind == .image
        }
    }

    /// Whether the clip carries live audio: its media has a track AND this
    /// half of the clip is enabled (Detach Audio flips that, §6).
    ///
    /// A nest clip has no media of its own, so the media test cannot answer
    /// for it — and "no" would be the wrong answer, because a nest clip's own
    /// volume, mute and fades MULTIPLY every voice inside it
    /// (`core/src/audio.rs`: turning a nest down turns everything in it
    /// down). What it is asked instead is whether it has audio properties at
    /// all, which is the core's own answer to the same question: `nest` gives
    /// the clip an `AudioProps` exactly when something inside it can make a
    /// sound (`edit_nest.rs`) and `set_audio` errors with "clip N has no
    /// audio properties" when it did not. Walking the contents here would be
    /// a second copy of that rule, free to drift from the one the writes go
    /// through.
    static func hasAudio(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard clip.enabled.audio else { return false }
        if case .nest = clip.source { return clip.audio != nil }
        guard let media = snapshot.media(for: clip) else { return false }
        return media.hasAudio
    }

    /// Whether the clip's rectangle comes from a decoded source — the clips
    /// that get Crop, Colour and Corner Radius. Text and shape clips get
    /// Transform, Opacity and Shadow only (§4.3).
    static func hasSourcePixels(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        switch clip.source {
        case .media, .still, .image: return true
        case .text, .shape, .graphic, .nest, .adjustment: return false
        }
    }

    /// Whether the clip is an adjustment clip (spec §11 GR-6): it draws
    /// nothing of its own and grades what is behind it, so it gets Color and
    /// Clip and never Picture.
    static func isAdjustment(_ clip: ClipSnapshot) -> Bool {
        if case .adjustment = clip.source { return true }
        return false
    }
}
