import Foundation

/// Duck by Speech's Swift half (format 29, spec §11 AU-110, AU-111, AU-113):
/// the speech spans a media's voice-activity cache gives, the ops that save
/// them on the media in the same undo step that turns Speech ducking on, and
/// the plan's `ducks` read back for the timeline's line.
///
/// **Rust decides everything else.** The spans this writes are SOURCE ticks
/// of the forward file; where a clip plays them — reversed, at a rate, on a
/// speed ramp, inside a nest — and how loud the rest of the mix is around
/// them is `core/src/audio_duck_speech.rs`'s. Nothing here maps a span to the
/// timeline or computes a gain.
///
/// The spans are FROZEN at their first write (AU-111): a media that already
/// carries `speech` keeps it, and Duck by Speech on another of its clips
/// writes no second `set_media_speech`.
enum DuckSpeech {
    /// A reason Duck by Speech cannot be chosen, in a sentence that names
    /// the clip or the file.
    struct Refusal: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    /// A pause shorter than this between two runs of speech is bridged, so a
    /// breath between words does not lift the bed for a fifth of a second.
    static let bridge: Ticks = ReelTime.perSecond / 5

    /// The speech spans of one media's cached probabilities: the runs of
    /// chunks at or above `SilenceDetector.Settings.defaultVoiceConfidence`
    /// (the one copy of the threshold Remove Silences' voice mode uses),
    /// chunk i being `[i, i + 1) × MediaSpeech.chunkTicks` of source, gaps
    /// under `bridge` bridged, each end clamped to the media's `duration` —
    /// the cache rounds its chunk count up, so its last chunk runs past the
    /// file — and a span left empty dropped. `[[start, end], …]`, sorted.
    static func spans(_ p: [Float], duration: Ticks) -> [[Ticks]] {
        let threshold = Float(SilenceDetector.Settings.defaultVoiceConfidence)
        let chunk = MediaSpeech.chunkTicks
        var runs: [(Int, Int)] = []
        var open: Int?
        for (index, value) in p.enumerated() {
            if value >= threshold {
                if open == nil { open = index }
            } else if let start = open {
                runs.append((start, index))
                open = nil
            }
        }
        if let start = open { runs.append((start, p.count)) }
        var out: [[Ticks]] = []
        for (first, past) in runs {
            let from = Ticks(first) * chunk
            let to = min(Ticks(past) * chunk, duration)
            guard to > from else { continue }
            if let last = out.last, from - last[1] < bridge {
                out[out.count - 1][1] = to
            } else {
                out.append([from, to])
            }
        }
        return out
    }

    /// The `set_media_speech` ops Duck by Speech needs before its
    /// `set_audio`: one per media of `clips` that has no `speech` yet, with
    /// the spans of its cache. Throws a `Refusal` for a clip that is not a
    /// media clip with sound, or a media whose speech has not been detected
    /// yet; an empty answer means every media already has its spans.
    static func ops(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot, cacheDirectory: URL?
    ) throws -> [ReelOp] {
        var out: [ReelOp] = []
        for media in try needing(clips, in: snapshot) {
            guard let directory = cacheDirectory,
                  let p = MediaImporter.loadSpeech(for: media.id, in: directory)
            else { throw notDetected(media) }
            out.append(.setMediaSpeech(media: media.id, spans: spans(p, duration: media.duration)))
        }
        return out
    }

    /// Why Duck by Speech cannot be chosen for `clips`, or nil when it can —
    /// `ops`' refusals without reading a cache, for the popup's enabled
    /// state: a cache counts as there when its marker is current, as
    /// `MediaImporter.loadSpeech` first asks.
    static func problem(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot, cacheDirectory: URL?
    ) -> String? {
        do {
            for media in try needing(clips, in: snapshot) {
                guard let directory = cacheDirectory,
                      MediaImporter.readSpeechStamp(
                        at: MediaImporter.speechMarkerURL(for: media.id, in: directory))?.version
                        == MediaImporter.speechVersion
                else { throw notDetected(media) }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The media of `clips` that have no `speech` yet, each once, in clip
    /// order; throws for a clip that is not a media clip with sound.
    private static func needing(
        _ clips: [ClipSnapshot], in snapshot: ProjectSnapshot
    ) throws -> [MediaSnapshot] {
        var seen: Set<UInt32> = []
        var out: [MediaSnapshot] = []
        for clip in clips {
            guard case .media = clip.source, let media = snapshot.media(for: clip),
                  media.hasAudio
            else {
                throw Refusal(
                    message: "Clip \(clip.id) is not a media clip with sound, so it cannot "
                        + "duck by speech.")
            }
            guard media.speech == nil, seen.insert(media.id).inserted else { continue }
            out.append(media)
        }
        return out
    }

    private static func notDetected(_ media: MediaSnapshot) -> Refusal {
        Refusal(
            message: "\(media.name) cannot duck by speech — its speech has not been "
                + "detected yet. Try again in a moment.")
    }

    // MARK: Hide while silent (spec §11 CO-94)

    /// The `set_media_speech` a clip that hides while `media` is silent needs
    /// before its `set_video`, in the same undo step: none for a media that
    /// already has `speech` (frozen, AU-111) or is not in `snapshot` (the core
    /// then refuses by name), else one from its cache's spans. Throws a
    /// `Refusal` for a media with no sound, or one whose speech has not been
    /// detected yet.
    static func ops(
        forMedia media: UInt32, in snapshot: ProjectSnapshot, cacheDirectory: URL?
    ) throws -> [ReelOp] {
        guard let row = try hideNeeding(media, in: snapshot) else { return [] }
        guard let directory = cacheDirectory,
              let p = MediaImporter.loadSpeech(for: row.id, in: directory)
        else { throw hideNotDetected(row) }
        return [.setMediaSpeech(media: row.id, spans: spans(p, duration: row.duration))]
    }

    /// Why a clip cannot hide while `media` is silent, or nil when it can —
    /// `ops(forMedia:)`'s refusals without reading the cache: a cache counts
    /// as there when its marker is current.
    static func problem(
        forMedia media: UInt32, in snapshot: ProjectSnapshot, cacheDirectory: URL?
    ) -> String? {
        do {
            guard let row = try hideNeeding(media, in: snapshot) else { return nil }
            guard let directory = cacheDirectory,
                  MediaImporter.readSpeechStamp(
                    at: MediaImporter.speechMarkerURL(for: row.id, in: directory))?.version
                    == MediaImporter.speechVersion
            else { throw hideNotDetected(row) }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The media when it still needs its spans; nil when it has them or is
    /// not in `snapshot`; throws for a media with no sound.
    private static func hideNeeding(
        _ media: UInt32, in snapshot: ProjectSnapshot
    ) throws -> MediaSnapshot? {
        guard let row = snapshot.media(media) else { return nil }
        guard row.hasAudio else {
            throw Refusal(
                message: "\(row.name) has no sound, so a clip cannot hide while it is silent.")
        }
        return row.speech == nil ? row : nil
    }

    private static func hideNotDetected(_ media: MediaSnapshot) -> Refusal {
        Refusal(
            message: "\(media.name)'s speech has not been detected yet, so a clip cannot hide "
                + "while it is silent. Try again in a moment.")
    }
}

/// A speech ducker's own multiplier, read off one handle's plan (`ducks`,
/// spec §11 AU-113) for the timeline's line (`TimelineView+DuckCurve.swift`).
/// The plan is decoded lazily, at most once, and only when a speech ducker
/// is drawn, so a project without one never pays for it.
final class DuckCurves {
    private let project: ReelProject
    private var byClip: [UInt32: [PlanRamp]]?

    init(_ project: ReelProject) {
        self.project = project
    }

    /// The ducker's ramps in the handle's time, or nil when `clip` is not a
    /// speech ducker.
    func ramps(for clip: UInt32) -> [PlanRamp]? {
        if byClip == nil {
            var found: [UInt32: [PlanRamp]] = [:]
            for duck in project.plan?.ducks ?? [] { found[duck.clip] = duck.ramps }
            byClip = found
        }
        return byClip?[clip]
    }
}
