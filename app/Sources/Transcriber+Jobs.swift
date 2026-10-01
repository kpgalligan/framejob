import Foundation

// MARK: - Transcriber: what can be transcribed

/// What a run is given to do: `jobs(for:in:urls:)`, which turns the clips a
/// caller named into `Job`s and says in `CaptionLayout.Problem`'s vocabulary
/// why it refused the rest, `contentLength(of:)`, the one place a clip's
/// source window is measured for them, and `hasTranscribableClip(in:)`, the
/// cheap question the menu's validator asks.
///
/// It arrived as a pure move out of `Transcriber.swift` (road map 6's C1
/// toll 1), and it is no longer one: c1-run added `maxSourceTicks`, the
/// bound on `Job.sourceIn`, the clamp inside `contentLength(of:)` and
/// `placed(offset:in:)`, the one door every `Double → Ticks` conversion on
/// the caption path goes through. One widening survives from the move:
/// `contentLength(of:)` is internal rather than `private` (road map 6 §5h
/// names it), which no compiler error demanded — its one caller, `jobs`,
/// moved with it.
///
/// **Why anything here is bounded at all — spec §11's R6-10.** A clip's
/// `speed` is bounded to 0.1–10 by the OPS (`core/src/edit_clip_timing.rs`'s
/// `SPEED_MIN`/`SPEED_MAX`: `set_speed` clamps, `rate_stretch` is an
/// identity outside) and, since R6-10's amendment (#41), by the reader too
/// — `Project::validate`'s `check_clips` refuses a clip outside them — so
/// no opened project reaches this code with a tiny or huge speed. The
/// clamps here stay as the second layer R6-10 keeps, because if one ever
/// did, the two ends of the arithmetic would fail in two places: a huge
/// speed overflows the SOURCE LENGTH here, and a tiny one overflows the
/// OFFSET in the two mappings. Both clamp in `Double`, before the
/// conversion, because a `Ticks(_:)` on an out-of-range `Double` traps.
extension Transcriber {

    /// The ceiling on any source time this file answers: 1e15 ticks, about
    /// 1.9 billion seconds, some fifty years of media.
    ///
    /// Deliberately NOT `Ticks.max`, which is what the core's own
    /// `content_length_in_source` saturates at (`core/src/source_window.rs`
    /// casts an `f64` and an out-of-range cast saturates in Rust rather than
    /// trapping). The core never ADDS that number to anything; Swift does.
    /// `MediaTranscript.words` adds it to `sourceIn` for the window's end,
    /// and `TranscribeSheetController.refresh` sums it over every job, at
    /// most `MAX_CLIPS` = 4096 of them — and 4096 × 1e15 is under 2^63 with
    /// three orders of magnitude to spare, where 4096 × `Ticks.max` is not.
    static let maxSourceTicks: Ticks = 1_000_000_000_000_000

    /// One offset in ticks, as a `Double`, landed in the clip — the ONE
    /// door both caption mappings convert through.
    ///
    /// The clamp is into `[0, duration]` and it happens in `Double`: an
    /// offset divided by a speed of 1e-300 is a finite `Double` far larger
    /// than `Ticks.max`, and `Ticks(_:)` on it traps rather than saturating.
    /// Rounded half away from zero, the rule both mappings had. NaN — which
    /// is what `0 / 0` answers when a word sits exactly on a zero-speed
    /// clip's `in` point — is 0, the clip's own start: the beginning of the
    /// clip is the one answer that is always inside it.
    static func placed(offset: Double, in job: Job) -> Ticks {
        guard !offset.isNaN else { return job.start }
        let bounded = min(max(offset, 0), Double(job.duration))
        return job.start + Ticks(bounded.rounded(.toNearestOrAwayFromZero))
    }

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
                    clip: clip.id, media: media, name: snapshot.name(of: clip), source: url,
                    sourceIn: min(max(0, sourceIn), maxSourceTicks),
                    sourceLength: contentLength(of: clip),
                    start: clip.start, duration: clip.duration, speed: clip.speed))
        }
        return (jobs, problems)
    }

    /// How much SOURCE time a clip plays — `Project::content_length_in_source`
    /// (`core/src/source_window.rs`) in Swift, because the extract's range is
    /// a source range and the core owns what that means.
    ///
    /// It does NOT saturate where the core saturates. The core's cast tops
    /// out at `i64::MAX`; this one tops out at `maxSourceTicks`, for the
    /// reason that constant's own doc gives — Swift sums this answer and the
    /// core does not. Every speed the ops can write (0.1–10) is orders of
    /// magnitude below the bound and answers exactly what it always did;
    /// R6-10 keeps it for speeds the reader now refuses (#41). The
    /// clamp is applied in `Double`: `Ticks(_:)` traps on an out-of-range
    /// one. The degenerate fallback is unchanged and is bounded too, since a
    /// hand-written `duration` can be as large as `Ticks` allows.
    ///
    /// A product that overflows to `+infinity` — which `duration × 1e308`
    /// does — is the bound and not the fallback: the honest answer to "how
    /// much source does this play" is "more than there can be", which is
    /// `maxSourceTicks`, where the clip's own duration would be a number
    /// pulled out of the air. `NaN`, a negative and `-infinity` all fail the
    /// `>= 1` test and take the fallback, as they always did.
    static func contentLength(of clip: ClipSnapshot) -> Ticks {
        let scaled = Double(clip.duration) * clip.speed
        guard scaled >= 1 else { return min(max(clip.duration, 1), maxSourceTicks) }
        return Ticks(min(scaled, Double(maxSourceTicks)).rounded())
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

extension Transcriber.Job {
    /// The job's clip on the timeline, `[start, start + duration)` — the ONE
    /// spelling of it. `CaptionPages` confines every page it makes for this
    /// job to it (road map 8's W4a), so pages of two abutting clips abut at
    /// most. `duration` is positive: `jobs(for:in:urls:)` refuses a clip
    /// whose length is not.
    var span: Range<Ticks> { start ..< start + duration }
}
