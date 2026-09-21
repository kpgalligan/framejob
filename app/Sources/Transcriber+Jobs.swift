import Foundation

// MARK: - Transcriber: what can be transcribed

/// What a run is given to do: `jobs(for:in:urls:)`, which turns the clips a
/// caller named into `Job`s and says in `CaptionLayout.Problem`'s vocabulary
/// why it refused the rest, `contentLength(of:)`, the one place a clip's
/// source window is measured for them, and `hasTranscribableClip(in:)`, the
/// cheap question the menu's validator asks.
///
/// A pure move out of `Transcriber.swift`, road map 6's C1 toll 1. The block
/// came here whole and in its own order, with every line byte-identical.
/// One widening: `contentLength(of:)` is internal rather than `private`
/// (road map 6 §5h names it), which no compiler error demanded — its one
/// caller, `jobs`, moved with it.
extension Transcriber {

    // MARK: - What can be transcribed

    /// Turns clips into jobs, and says why it refused the rest.
    ///
    /// Only a `media` clip whose file exists and has sound can be
    /// transcribed. A `still`, `image`, `text`, `shape` or `nest` source
    /// cannot — `edit.rs`'s non-media rule, in five names — and neither can a
    /// **reversed** clip, whose audio plays backwards and whose transcript
    /// would be nonsense presented as fact.
    ///
    /// "Has sound" is `InspectorTab.hasAudio`'s question and not the media's:
    /// the FILE having an audio track is only half of it, and `enabled.audio`
    /// is the other half (`audio.rs` gives such a clip no voice at all, so the
    /// timeline plays nothing for it). Detach Audio is what makes the
    /// difference visible — it leaves the picture clip with `enabled.audio`
    /// false and puts an audio-only twin with the SAME media, `in`, `start`
    /// and `speed` on the track below, so asking the media would recognise one
    /// recording twice, place two identical cues at one time, and then report
    /// the pile-up it made as captions that had to be shortened.
    static func jobs(
        for clips: [ClipSnapshot], in snapshot: ProjectSnapshot, urls: [UInt32: URL]
    ) -> (jobs: [Job], problems: [CaptionLayout.Problem]) {
        var jobs: [Job] = []
        var problems: [CaptionLayout.Problem] = []
        for clip in clips.sorted(by: { $0.start < $1.start }) {
            let tag = "clip \(clip.id)"
            guard case .media(let media, let sourceIn, let reversed) = clip.source else {
                problems.append(
                    CaptionLayout.Problem(
                        tag: tag, reason: "its source is not a media file, so it has no speech"))
                continue
            }
            guard !reversed else {
                problems.append(
                    CaptionLayout.Problem(
                        tag: tag,
                        reason: "it plays in reverse, so its speech cannot be transcribed"))
                continue
            }
            guard let entry = snapshot.media(media), entry.hasAudio else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its media has no audio track"))
                continue
            }
            guard clip.enabled.audio else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its audio is switched off"))
                continue
            }
            guard let url = urls[media] else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its media file is missing"))
                continue
            }
            guard clip.speed.isFinite, clip.speed > 0, clip.duration > 0 else {
                problems.append(
                    CaptionLayout.Problem(tag: tag, reason: "its speed or length is degenerate"))
                continue
            }
            jobs.append(
                Job(
                    clip: clip.id, name: snapshot.name(of: clip), source: url,
                    sourceIn: max(0, sourceIn), sourceLength: contentLength(of: clip),
                    start: clip.start, duration: clip.duration, speed: clip.speed))
        }
        return (jobs, problems)
    }

    /// How much SOURCE time a clip plays — `Project::content_length_in_source`
    /// (`core/src/source_window.rs`) in Swift, saturating the same way, because
    /// the extract's range is a source range and the core owns what that
    /// means.
    static func contentLength(of clip: ClipSnapshot) -> Ticks {
        let scaled = Double(clip.duration) * clip.speed
        guard scaled.isFinite, scaled >= 1 else { return max(clip.duration, 1) }
        return Ticks(scaled.rounded())
    }

    /// Whether anything in this project could be transcribed at all — the
    /// menu item's validator, deliberately the cheap snapshot question rather
    /// than a plan, because a validator runs on every menu open.
    ///
    /// It asks the same three things `jobs` asks and in the same order, minus
    /// the two a snapshot cannot answer without the document's media URLs, so
    /// the item can only be enabled where a run would find work. `enabled.audio`
    /// is one of the three: a timeline whose every audible clip has had its
    /// sound switched off has nothing to transcribe, and a menu item that
    /// opens a sheet whose only answer is "nothing to transcribe" is the
    /// dialog `generateCaptionsCommand`'s guard exists to prevent.
    static func hasTranscribableClip(in snapshot: ProjectSnapshot) -> Bool {
        snapshot.clips.contains { clip in
            guard case .media(let media, _, let reversed) = clip.source, !reversed,
                  clip.enabled.audio
            else {
                return false
            }
            return snapshot.media(media)?.hasAudio ?? false
        }
    }
}
