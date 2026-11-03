import Foundation

// MARK: - Hide while silent

// The Swift half of `video.hide_silent` (format 43, road map creator-jobs CO9,
// spec §11 CO-90…CO-94): the props the model stores, the media a person can
// pick the speech from, and the plan's `gates` read back for the timeline's
// line. **Rust decides the gate**: where a media's speech plays, which
// container it is read in and how the opacity ramps are
// `core/src/video_gate.rs`'s. Nothing here maps a span to the timeline or
// computes an opacity.

/// A clip's `video.hide_silent` (CO-90, CO-91): the media whose speech the
/// clip follows and the envelope around it, in ticks, stored as typed (off
/// the frame grid). Every write names all four keys (`dictionary`).
struct HideSilentProps: Codable, Equatable {
    var media: UInt32
    var preRoll: Ticks
    var hold: Ticks
    var fade: Ticks

    /// 0.2 s, 1.5 s and 0.3 s, and each one's top, 5 s (the core's
    /// `HIDE_SILENT_*`).
    static let defaultPreRoll: Ticks = 120_000
    static let defaultHold: Ticks = 900_000
    static let defaultFade: Ticks = 180_000
    static let maxTicks: Ticks = 3_000_000

    init(
        media: UInt32, preRoll: Ticks = defaultPreRoll, hold: Ticks = defaultHold,
        fade: Ticks = defaultFade
    ) {
        self.media = media
        self.preRoll = preRoll
        self.hold = hold
        self.fade = fade
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        media = c.lenient(.media, 0)
        preRoll = c.lenient(.preRoll, Self.defaultPreRoll)
        hold = c.lenient(.hold, Self.defaultHold)
        fade = c.lenient(.fade, Self.defaultFade)
    }

    /// All four keys under the model's names, so a written gate says every
    /// key (`set_video` merges).
    var dictionary: [String: Any] {
        ["media": media, "pre_roll": preRoll, "hold": hold, "fade": fade]
    }
}

/// The media the Hide While Silent section offers for "Speech from" (CO-94).
enum HideSilentSources {
    /// The media with sound of any clip in `snapshot` (the selected clips
    /// included) whose span overlaps a selected clip's: picture-less media
    /// first — the microphone first — then by total overlap with the
    /// selected clips, longest first, then by id.
    static func candidates(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot
    ) -> [MediaSnapshot] {
        var overlap: [UInt32: Ticks] = [:]
        for other in snapshot.clips {
            guard case .media = other.source, let media = snapshot.media(for: other),
                  media.hasAudio
            else { continue }
            for clip in clips {
                let shared = min(other.end, clip.end) - max(other.start, clip.start)
                if shared > 0 { overlap[media.id, default: 0] += shared }
            }
        }
        return overlap.keys.compactMap { snapshot.media($0) }.sorted { a, b in
            if a.hasVideo != b.hasVideo { return !a.hasVideo }
            let (oa, ob) = (overlap[a.id] ?? 0, overlap[b.id] ?? 0)
            if oa != ob { return oa > ob }
            return a.id < b.id
        }
    }
}

/// A gated clip's gate, read off one handle's plan (`gates`, spec §11
/// CO-93) for the timeline's line (`TimelineView+GateLine.swift`). The plan
/// is decoded lazily, at most once, and only when a gated clip is drawn, so a
/// project without one never pays for it. `DuckCurves`' shape.
final class GateCurves {
    private let project: ReelProject
    private var byClip: [UInt32: [PlanRamp]]?

    init(_ project: ReelProject) {
        self.project = project
    }

    /// The clip's gate as ramps in the handle's time, or nil when the plan
    /// has no gate for it.
    func ramps(for clip: UInt32) -> [PlanRamp]? {
        if byClip == nil {
            var found: [UInt32: [PlanRamp]] = [:]
            for gate in project.plan?.gates ?? [] { found[gate.clip] = gate.ramps }
            byClip = found
        }
        return byClip?[clip]
    }
}
