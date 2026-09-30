import Foundation

/// The detector's vocabulary — `Span`, `Scope`, `Mode`, `Settings` and
/// `Outcome` — a pure move out of `SilenceDetector.swift`, #107's toll,
/// landed first and alone. The file that was to take on per-voice answers
/// sat at the cap, and these five types are the piece of it every caller
/// names (the sheet, the tool, the timeline's wash, Normalize Clip, the
/// recorder's landing, the probes) while none of them reads the walk. None
/// of it was `private`, so the cut widened nothing: the types came here
/// whole, in their order, with their bodies untouched.
extension SilenceDetector {

    // MARK: - Vocabulary

    /// One quiet span of project time, in ticks. Half-open: `end` is the
    /// first tick that is NOT removed, which is what the op's `[from, to]`
    /// pair means too.
    struct Span: Equatable {
        let start: Ticks
        let end: Ticks

        var length: Ticks { max(0, end - start) }
    }

    /// Which clips the quiet test is taken over.
    ///
    /// The rule is an INTERSECTION — a tick is quiet only where every clip in
    /// scope is quiet — so the scope is what stops a music bed under a
    /// voiceover from being cut away with the pauses in the speech.
    enum Scope: String, CaseIterable {
        /// The clips the user has selected — their AUDIBLE segments only.
        /// A selected clip that plays no sound, or none the mix lets
        /// through, simply contributes none (`detect` says why).
        case selected
        /// Every audio segment whose track envelope is not identically zero
        /// across it — i.e. everything actually audible in the mix.
        case audible

        var displayName: String {
            switch self {
            case .selected: return "Selected clips"
            case .audible: return "All audible clips"
            }
        }
    }

    /// How a moment is judged quiet — road map 4's S1. `voice` asks the
    /// cached Silero VAD probability (`cache/speech/<id>.bin`) and falls
    /// back to `level` per VOICE whose source window holds no voice, or for
    /// every media at once when the model cannot be used this process;
    /// `level` is today's rule, byte for byte. A media whose speech cache
    /// has NOT landed is judged by neither — see `Outcome.voicePending`.
    enum Mode: String, CaseIterable {
        case voice
        case level

        var displayName: String {
            switch self {
            case .voice: return "Voice"
            case .level: return "Level"
            }
        }
    }

    /// The four numbers the sheet and the `detect_silence` tool both spell.
    struct Settings: Equatable {
        /// The level, in dBFS, at or under which a moment counts as quiet —
        /// measured IN THE MIX (see the type's doc). −40 dBFS is roughly a
        /// quiet room's tone under a spoken take: low enough that breath and
        /// keyboard noise survive, high enough that a real pause reads as one.
        var thresholdDB: Double
        /// The shortest quiet run worth cutting. Half a second is about the
        /// length of a deliberate pause in speech; anything shorter is the gap
        /// between two words and removing it makes the delivery sound clipped.
        var minLength: Ticks
        /// How much of each end of a quiet run is KEPT, so a cut does not land
        /// on the attack of the next word. A tenth of a second is three frames
        /// at 30 fps — the smallest amount that reliably reads as breathing
        /// room rather than as an edit.
        var padding: Ticks
        var scope: Scope
        /// `voice` by default; the sheet opens in `level` when the model
        /// cannot be used this process.
        var mode: Mode
        /// The Silero probability at or above which a moment counts as
        /// speech, in `voice` mode. Read only in that mode — the tool
        /// refuses it in `level`, named rather than silently ignored.
        var voiceConfidence: Double

        static let defaultThresholdDB = -40.0
        static let defaultMinLength: Ticks = ReelTime.ticks(seconds: 0.5)
        static let defaultPadding: Ticks = ReelTime.ticks(seconds: 0.1)
        static let defaultVoiceConfidence = 0.5

        /// The ranges the sheet's controls and the tool's arguments clamp to.
        /// −80 dBFS is under any real recording's noise floor and −10 dBFS is
        /// well into speech, so the two ends are "cut nothing" and "cut
        /// almost everything" rather than arbitrary numbers.
        static let thresholdRange = -80.0...(-10.0)
        static let minLengthRange = 0.05...10.0
        static let paddingRange = 0.0...2.0
        static let voiceConfidenceRange = 0.1...0.9

        init(
            thresholdDB: Double = Settings.defaultThresholdDB,
            minLength: Ticks = Settings.defaultMinLength,
            padding: Ticks = Settings.defaultPadding,
            scope: Scope = .audible,
            mode: Mode = .voice,
            voiceConfidence: Double = Settings.defaultVoiceConfidence
        ) {
            self.thresholdDB = thresholdDB
            self.minLength = minLength
            self.padding = padding
            self.scope = scope
            self.mode = mode
            self.voiceConfidence = voiceConfidence
        }
    }

    /// What one detection run found.
    struct Outcome {
        let spans: [Span]
        /// The scope the run actually used — the sheet SAYS which, because
        /// "nothing was found" and "nothing was looked at" are different
        /// answers and the user cannot tell them apart otherwise.
        let scope: Scope
        /// Distinct clip ids that contributed a segment, sorted.
        let clips: [UInt32]
        /// Media in scope whose `cache/peaks/<id>.bin` has not been written
        /// yet. Their segments are treated as NEVER quiet, so a project opened
        /// a second ago proposes no cuts rather than proposing to delete a
        /// whole clip because its waveform has not landed.
        let pendingMedia: [UInt32]
        /// Nest clips that held quiet the detector declined to propose, so
        /// the sheet can say why it found fewer cuts than the timeline
        /// looks like it holds. Empty is the ordinary answer.
        let protectedNests: [UInt32]
        /// The mode the run actually used — `settings.mode`, echoed back for
        /// the same reason `scope` is.
        let mode: Mode
        /// Distinct media, in scope, with at least one scoped voice whose
        /// source window holds no voice and was therefore judged by level
        /// even in `voice` mode. Always `[]` in `level` mode. Which CLIPS
        /// were is `answers`' (`judgedByLevelClips`).
        let judgedByLevel: [UInt32]
        /// Distinct media, in scope, whose `cache/speech/<id>.bin` has not
        /// landed yet — never quiet by the model, and not judged by level
        /// either: a missing cache must not read as silence. Always `[]` in
        /// `level` mode.
        let voicePending: [UInt32]
        /// Distinct media a span in `spans` actually lands inside, sorted.
        /// It is what the sheet and the tool make their "nothing inside is
        /// proposed" promise about while a cache is still landing: the gain
        /// FLOOR is asked before either cache (`isQuiet`), so a clip the mix
        /// has turned down, faded or ducked is quiet with nothing on disk at
        /// all, and the promise used to deny the ranges printed beside it
        /// (the reader review, road map 4 §8, R3·1).
        let proposedMedia: [UInt32]
        /// One answer per scoped voice, sorted by start and then clip; `[]`
        /// when nothing was in scope. The media sets above cannot tell two
        /// clips of one file apart — one ducked, one not — so the notes name
        /// the CLIP from these (#107).
        let answers: [VoiceAnswer]

        var removed: Ticks { spans.reduce(0) { $0 + $1.length } }
        var isEmpty: Bool { spans.isEmpty }
    }

    /// One scoped voice's own answer (#107): which clip, over which span,
    /// judged how, and whether the answer proposes anything inside it.
    struct VoiceAnswer: Equatable {
        /// `PlanSegment.clip`. Under a nest that is the INNER clip's id,
        /// which `snapshot.clip` cannot find — `label(in:)` falls back.
        let clip: UInt32
        let media: UInt32
        /// The segment's project span, `[start, start + duration)`.
        let span: Span
        /// Its source window holds no voice, so it was judged by level.
        let judgedByLevel: Bool
        /// The cache the quiet test reads after the gain floor has not
        /// landed: the waveform in `level` mode or for a by-level voice,
        /// else the speech cache. A waiting voice is quiet by the FLOOR or
        /// not at all, so one that is also `proposed` is quiet by the mix.
        let waiting: Bool
        /// A span in `Outcome.spans` overlaps this voice's own span.
        let proposed: Bool

        /// "<clip name> at <timecode>", the sheet's name for a clip — the
        /// media's name, then "clip <id>", when the snapshot cannot find it.
        func label(in snapshot: ProjectSnapshot) -> String {
            let name = snapshot.clip(clip).map { snapshot.name(of: $0) }
                ?? snapshot.media(media)?.name ?? "clip \(clip)"
            return "\(name) at "
                + ReelTime.format(span.start, fps: snapshot.canvas.fps, frames: true)
        }

        /// One label per distinct clip and start, in the order given.
        static func labels(_ answers: [VoiceAnswer], in snapshot: ProjectSnapshot) -> [String] {
            var seen: [(UInt32, Ticks)] = []
            var labels: [String] = []
            for answer in answers {
                let key = (answer.clip, answer.span.start)
                guard !seen.contains(where: { $0 == key }) else { continue }
                seen.append(key)
                labels.append(answer.label(in: snapshot))
            }
            return labels
        }
    }
}

extension SilenceDetector.Outcome {
    /// Distinct clips, ascending, judged by level — `judgedByLevel` by clip.
    var judgedByLevelClips: [UInt32] {
        Set(answers.filter { $0.judgedByLevel }.map { $0.clip }).sorted()
    }

    /// Distinct clips, ascending, that a span lands inside while the cache
    /// their quiet test reads is still missing: proposed by the mix alone.
    var proposedByMixClips: [UInt32] {
        Set(answers.filter { $0.proposed && $0.waiting }.map { $0.clip }).sorted()
    }

    /// The answers, in order, of those voices over `media`.
    func mixAnswers(inside media: Set<UInt32>) -> [SilenceDetector.VoiceAnswer] {
        answers.filter { media.contains($0.media) && $0.proposed && $0.waiting }
    }
}
