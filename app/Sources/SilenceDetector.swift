import Foundation

/// Remove Silences' detector (road map 2 phase 3a): the quiet spans of a
/// project, as project-time ranges the core's `ripple_delete_ranges` cuts.
///
/// **It reads the PLAN, not the peaks alone.** A bucket in
/// `cache/peaks/<media id>.bin` is a PRE-FADER magnitude — the file's own
/// loudness, knowing nothing about `volume`, a fade, a duck, a mute or a
/// solo. What the user means by "silent" is what they HEAR, so the level this
/// asks about is `peak × envelope`, and the envelope is the one the core
/// already published: `CompositionPlan`'s audio tracks carry `segments` (what
/// sound plays, from which file, from which source offset, over which project
/// span, already clamped to the file by `evaluate.rs`) and `ramps` (the
/// envelope over the track's whole extent, fades, volume actions and ducking
/// folded in).
///
/// That one decision is what keeps mute and solo out of this file. `audio.rs`
/// expresses both as a ZERO envelope rather than as an absent segment — by
/// deliberate design, so that unmuting never rebuilds the composition — which
/// means a muted clip is quiet here for free, with no second Swift copy of
/// `audio.rs`'s `silenced` to drift from the first.
///
/// **A nest is a wall, not a place to cut inside.** The plan FLATTENS a nest
/// into one segment per clip inside it (`core/src/nest.rs`), so the sound
/// measured over a nest clip is its CONTENTS' and nothing in the plan says
/// so — `segment.clip` is the inner clip's id and `snapshot.clip` cannot
/// find it. That is a trap, because `Source::Nest` has no in point: a nest
/// clip always plays its nest from the first frame, so splitting one leaves
/// two clips that each replay it from the top with the middle unreachable.
/// `ripple_delete_ranges` splits every unlocked track at both of a span's
/// bounds, so a candidate that reached into a nest would not take the dead
/// air out of it — it would strand its tail. A nest's sound therefore still
/// PROTECTS a span, exactly as any other sound does (it is what the ear
/// hears, and a loud nest keeps a tick out of a run), but no candidate may
/// INTERSECT one: `Input.nests` is the list of walls and `excludingNests`
/// cuts every run against them. **The dead air inside a nest is reached by
/// OPENING it** (⌘↓, or `set_scope`) — `Input.read` takes its snapshot and
/// its plan off `editedProject`, so with a nest open the walls are the ones
/// inside it and the runs are its own. Road map 2's phase 9 made that the
/// everyday path; the round trip (⇧⌘G, cut, ⌘G) still works and is no longer
/// the only way in. What has NOT changed is the rule above: whichever
/// container is open, a candidate may not intersect a nest IN it.
///
/// **A TRANSITION is a wall too** (road map 5's E1): an overlap on any
/// unlocked track is subtracted from every run, widened by its own length
/// each side, so no cut can leave one clip's tail sitting wholly under its
/// neighbour. `SilenceDetector+Walls.overlapWalls` is that list and argues
/// the widening; unlike a nest it is not REPORTED, because a transition is
/// something the person made and expects to survive rather than something
/// the sheet owes them an explanation for.
///
/// Nothing here is AppKit, a view or a document beyond one read: `Input.read`
/// is the seam that takes a snapshot, a plan, a selection and the peak files
/// off a `ProjectDocument` once, and everything after it is arithmetic over
/// values. That is what lets the sheet recompute synchronously on every
/// control change and lets the agent's `detect_silence` run the same code.
///
/// The units, once, because three of them are easy to confuse:
/// * a **bucket** is 1/100 s of SOURCE time — exactly
///   `ReelTime.perSecond / MediaImporter.peakBucketsPerSecond` ticks;
/// * a **segment** maps project time to source time at the speed the plan
///   already resolved (`duration / sourceDuration`);
/// * a **span** this answers with is PROJECT time, snapped to the frame grid.
///
/// The first two of those, and the reversed mirror they need, are
/// `MediaPeaks`' since road map 2 phase 5c: Normalise Clip asks the cache the
/// same question this does, and a second copy of the arithmetic would have
/// been the third project-to-source conversion in the app. **The envelope
/// followed them**, once phase 5's level meter had written its own copy of the
/// piecewise-linear ramp search: `MediaPeaks.envelope` is the app's one
/// spelling of the mix rule and this file is one of its two readers. Nothing
/// about the numbers changed when either moved.
enum SilenceDetector {

    // MARK: - Input

    /// One audio segment with everything the quiet test needs beside it.
    /// Built once per `Input`, because none of it depends on the settings.
    fileprivate struct Voice {
        let segment: PlanSegment
        /// The envelope of the composition track this segment plays on.
        let ramps: [PlanRamp]?
        /// The forward file's buckets, or nil when the cache is not on disk.
        let peaks: [Float]?
        /// The media's model duration when the clip plays BACKWARDS, which is
        /// the pivot `ReverseRenderer` mirrors about; nil otherwise.
        /// `MediaPeaks.reversedPivot` works it out and says why it cannot be
        /// read off the plan.
        let reversedPivot: Ticks?
        /// True when the track envelope is not identically zero over the
        /// segment. It is BOTH scopes' membership test, not just its
        /// namesake's — `detect` says why a silenced voice cannot be scoped.
        let audible: Bool
        /// The forward file's cached Silero VAD probabilities, or nil when
        /// the cache is not on disk — road map 4's voice mode.
        let speech: [Float]?

        var end: Ticks { segment.start + max(0, segment.duration) }
    }

    /// One nest clip a cut must not land inside, and its id so the sheet can
    /// name what it left alone.
    ///
    /// A nest on a LOCKED track is not one of these: `clear_range` neither
    /// splits nor removes there and `shift_clips` does not move it either,
    /// so nothing of it can be lost. Built once per `Input`, like `Voice`
    /// and for the same reason — it is a function of the snapshot alone.
    struct NestExtent {
        let clip: UInt32
        let span: Span
    }

    /// Everything a detection run reads, taken off the document ONCE.
    ///
    /// The document cannot change while a sheet is attached (every editor
    /// action validates false then), so the sheet builds one of these when it
    /// opens and recomputes from it on every control change without touching
    /// the document again. The agent's handler builds one per call.
    struct Input {
        let snapshot: ProjectSnapshot
        let selection: Set<UInt32>
        /// Every media in the timeline whose peaks are still missing, whether
        /// or not it is in scope — what the sheet names as "still analysing".
        let pendingMedia: [UInt32]
        /// `SileroVAD.isAvailable`, read once here so `detect` (pure and
        /// synchronous) never asks the model directly.
        let voiceAvailable: Bool
        /// Every media in the timeline whose `cache/speech/<id>.bin` is not
        /// on disk yet, whether or not it is in scope — `pendingMedia`'s
        /// shape for the voice cache. `MediaSpeech.Loader.pending`, sorted.
        let pendingSpeech: [UInt32]
        fileprivate let voices: [Voice]
        /// The spans no candidate may reach into — see `NestExtent`.
        fileprivate let nests: [NestExtent]
        /// The spans around every OVERLAP on every unlocked track, widened
        /// by the overlap's own length each side
        /// (`SilenceDetector+Walls.overlapWalls`). Subtracted exactly as the
        /// nest walls are and never REPORTED: a nest a cut was kept out of
        /// is something to explain, where a transition is a thing the person
        /// made on purpose and expects to survive.
        fileprivate let walls: [Span]

        /// False when the plan has no audio at all, which is the one case
        /// worth refusing the sheet outright for.
        var hasAudio: Bool { !voices.isEmpty }

        /// The scope to open with: the selection when it holds anything
        /// AUDIBLE, else everything audible. A selection of picture-only
        /// clips would otherwise open a sheet that can only say "nothing to
        /// analyse" — and a selection of MUTED ones has to answer `.audible`
        /// for the same reason the scope itself drops them: a silenced voice
        /// covers its span while reading quiet at every tick, so opening on
        /// it would propose cutting the whole clip, and everything under it,
        /// away. `SilenceSheetController` disables the "Selected clips" row
        /// off exactly this answer.
        var defaultScope: Scope {
            voices.contains { $0.audible && selection.contains($0.segment.clip) }
                ? .selected : .audible
        }
    }

    /// Reads a document's snapshot, plan, selection and peak caches.
    ///
    /// `selection` overrides the document's own, which is what the agent's
    /// `detect_silence {clips}` argument needs; the sheet passes nil.
    /// nil is answered only when the core emitted a plan this build cannot
    /// read — the same failure `CompositionBuilder` treats as fatal.
    static func read(from document: ProjectDocument, selection: Set<UInt32>? = nil) -> Input? {
        // The EDITED project (road map 2's phase 9): with a nest open the
        // scope, the plan and the ranges `ripple_delete_ranges` is sent are
        // all the NEST's, in the nest's own time, and the op carries the
        // scope. At the top level this is `document.project` as before.
        guard let plan = document.editedProject.plan else { return nil }
        let snapshot = document.editedProject.snapshot
        let cacheDirectory = document.cacheDirectory

        // One read per media, however many segments cite it — `MediaPeaks.Loader`
        // is that memo, and its `pending` set is what this reports as "still
        // analysing".
        let loader = MediaPeaks.Loader(cacheDirectory: cacheDirectory)
        // One read per media, exactly `loader`'s shape, for the voice cache.
        let speechLoader = MediaSpeech.Loader(cacheDirectory: cacheDirectory)

        var voices: [Voice] = []
        for track in plan.audioTracks {
            for segment in track.segments where segment.duration > 0 {
                let span = (segment.start, segment.start + segment.duration)
                voices.append(
                    Voice(
                        segment: segment, ramps: track.ramps,
                        peaks: loader.peaks(for: segment.media),
                        reversedPivot: MediaPeaks.reversedPivot(for: segment, in: snapshot),
                        audible: isAudible(track.ramps, over: span),
                        speech: speechLoader.probabilities(for: segment.media)))
            }
        }
        let nests = nestExtents(in: snapshot)
        return Input(
            snapshot: snapshot, selection: selection ?? document.selection,
            pendingMedia: loader.pending.sorted(), voiceAvailable: SileroVAD.isAvailable,
            pendingSpeech: speechLoader.pending.sorted(), voices: voices, nests: nests,
            walls: overlapWalls(snapshot))
    }

    // MARK: - Detection

    /// The quiet spans, in project ticks, snapped to the frame grid.
    ///
    /// The walk is over PROJECT time in bucket-sized steps, so the resolution
    /// is one bucket (10 ms) however fast or slow a clip is playing. Within
    /// one step a segment's loudness is the MAX over every bucket the step
    /// covers, which is the conservative reading for a destructive edit: a
    /// clip at ×2 covers two buckets per step and taking the louder of them
    /// can only keep material, never cut more.
    ///
    /// A tick covered by NO segment in scope is not a candidate. "Remove
    /// Silences" means "take the dead air out of my recording", not "close
    /// every gap in my edit" — a hole between a title card and the footage is
    /// deliberate spacing and shading it would promise a cut nobody asked for.
    static func detect(_ input: Input, settings: Settings) -> Outcome {
        // `audible` is asked of BOTH scopes, not only of its namesake. A
        // voice the mix has silenced — muted, silenced by another track's
        // solo, turned down, faded to nothing — reads as quiet at every tick
        // by construction, because `level` short-circuits on a zero envelope.
        // In scope it would therefore COVER its whole span while never
        // failing the quiet test, and a selected muted music bed would
        // propose one cut across the entire song, taking the audible
        // voiceover under it with the ripple. Dropping it keeps the reading
        // this file is built on — a silenced clip does not BLOCK a cut — and
        // leaves a span nothing audible covers a hole, which is never a
        // candidate.
        let scoped = input.voices.filter { voice in
            guard voice.audible else { return false }
            switch settings.scope {
            case .selected: return input.selection.contains(voice.segment.clip)
            case .audible: return true
            }
        }
        let clips = Set(scoped.map { $0.segment.clip }).sorted()
        let pending = Set(scoped.filter { $0.peaks == nil }.map { $0.segment.media }).sorted()
        guard !scoped.isEmpty else {
            return Outcome(
                spans: [], scope: settings.scope, clips: [], pendingMedia: [],
                protectedNests: [], mode: settings.mode, judgedByLevel: [], voicePending: [],
                proposedMedia: [], answers: [])
        }

        // Road map 4's voice mode, judged PER VOICE: a window holding no
        // voice falls back to level for its whole span and names its media
        // (and, through `answers`, its clip), mixed or not; a pending cache
        // is never quiet by the model. Both sets stay empty in `.level` mode.
        var judgedByLevelMedia: Set<UInt32> = []
        var voicePendingMedia: Set<UInt32> = []
        let judged: [(voice: Voice, byLevel: Bool)] = scoped.map { voice in
            guard settings.mode == .voice else { return (voice, false) }
            guard let speech = voice.speech else {
                voicePendingMedia.insert(voice.segment.media)
                return (voice, false)
            }
            let whole = Double(
                MediaSpeech.speechMax(
                    speech, over: voice.segment, from: voice.segment.start, to: voice.end,
                    reversedPivot: voice.reversedPivot))
            guard whole < settings.voiceConfidence else { return (voice, false) }
            judgedByLevelMedia.insert(voice.segment.media)
            return (voice, true)
        }

        let step = MediaPeaks.bucketTicks
        let limit = Double(AudioDSP.gain(fromDecibels: Float(settings.thresholdDB)))
        let ordered = judged.sorted { $0.voice.segment.start < $1.voice.segment.start }
        let domainStart = max(0, ordered.map { $0.voice.segment.start }.min() ?? 0)
        let domainEnd = ordered.map { $0.voice.end }.max() ?? domainStart

        // The walk is aligned to absolute multiples of a bucket rather than to
        // the first segment, so two projects that differ only in where their
        // audio starts round the same way.
        var t = (domainStart / step) * step
        var next = 0
        var active: [(voice: Voice, byLevel: Bool)] = []
        var runStart: Ticks?
        var runs: [Span] = []
        while t < domainEnd {
            let slotEnd = t + step
            while next < ordered.count, ordered[next].voice.segment.start < slotEnd {
                active.append(ordered[next])
                next += 1
            }
            active.removeAll { $0.voice.end <= t }

            var covered = false
            var quiet = true
            for entry in active {
                let from = max(t, entry.voice.segment.start)
                let to = min(slotEnd, entry.voice.end)
                guard to > from else { continue }
                covered = true
                if !isQuiet(
                    entry.voice, from: from, to: to, limit: limit, mode: settings.mode,
                    voiceConfidence: settings.voiceConfidence, byLevel: entry.byLevel) {
                    quiet = false
                    break
                }
            }

            if covered && quiet {
                if runStart == nil { runStart = max(t, domainStart) }
            } else if let start = runStart {
                runs.append(Span(start: start, end: min(t, domainEnd)))
                runStart = nil
            }
            t = slotEnd
        }
        if let start = runStart, domainEnd > start {
            runs.append(Span(start: start, end: domainEnd))
        }

        // The walls go in BEFORE the minimum length, not after: cutting a
        // run against a nest first is what turns a run whose middle is a
        // nest into two SHORT pieces the minimum then drops, where filtering
        // first would leave one long candidate spanning the nest.
        let (outside, walled) = excludingNests(
            runs, input.nests, minLength: settings.minLength)
        // The transition walls, subtracted on the same terms and in the same
        // place — before the minimum length, for the reason above — but
        // never REPORTED: `excludingNests`' second answer is the sheet's
        // list of protected NESTS, and an overlap is not one.
        let clear =
            input.walls.isEmpty
            ? outside
            : excludingNests(
                outside, input.walls.map { NestExtent(clip: 0, span: $0) },
                minLength: settings.minLength
            ).0
        let spans = refine(clear, settings: settings, fps: input.snapshot.canvas.fps)
        // Which media the answer proposes a span INSIDE — `Outcome.proposedMedia`
        // says why the two notes need it.
        let proposed = Set(
            scoped.filter { voice in
                spans.contains { $0.start < voice.end && voice.segment.start < $0.end }
            }.map { $0.segment.media })
        // And each voice's OWN answer (#107): its own overlap test, never
        // the media's membership above, so of two clips of one file only the
        // one a span lands inside is proposed. `waiting` is the cache
        // `isQuiet` reads after the floor.
        let answers = judged.map { entry -> VoiceAnswer in
            let voice = entry.voice
            let inside = spans.contains { $0.start < voice.end && voice.segment.start < $0.end }
            let waiting =
                settings.mode == .level || entry.byLevel
                ? voice.peaks == nil : voice.speech == nil
            return VoiceAnswer(
                clip: voice.segment.clip, media: voice.segment.media,
                span: Span(start: voice.segment.start, end: voice.end),
                judgedByLevel: entry.byLevel, waiting: waiting, proposed: inside)
        }.sorted { ($0.span.start, $0.clip) < ($1.span.start, $1.clip) }
        return Outcome(
            spans: spans,
            scope: settings.scope, clips: clips, pendingMedia: pending,
            protectedNests: walled, mode: settings.mode,
            judgedByLevel: judgedByLevelMedia.sorted(), voicePending: voicePendingMedia.sorted(),
            proposedMedia: proposed.sorted(), answers: answers)
    }

    // MARK: - The quiet test

    /// The mix envelope at a step, the LOUDER of its two ends — a step that
    /// straddles a fade's edge is judged by the loud side. Factored out of
    /// `level` for road map 4's floor: a step whose envelope alone lands the
    /// quiet threshold at or under full scale is quiet whatever the file
    /// holds, in either mode, before either test below is asked.
    private static func gain(of voice: Voice, from: Ticks, to: Ticks) -> Double {
        max(
            MediaPeaks.envelope(voice.ramps, at: from),
            MediaPeaks.envelope(voice.ramps, at: max(from, to - 1)))
    }

    /// `peak × envelope` for one segment over one step of project time — the
    /// LEVEL test, byte-identical to what it always answered. A zero
    /// envelope short-circuits: a muted, solo-silenced or fully faded
    /// segment is silent in the mix whatever its file holds, which is the
    /// whole reason the test is written against the plan.
    private static func level(of voice: Voice, from: Ticks, to: Ticks, step: Ticks) -> Double {
        let g = gain(of: voice, from: from, to: to)
        guard g > 0 else { return 0 }
        // No peaks on disk yet: never quiet. Treating a missing cache as
        // silence would propose deleting the whole clip, which is the one
        // failure this feature must not have.
        guard let peaks = voice.peaks else { return .infinity }
        let magnitude = MediaPeaks.peak(
            peaks, over: voice.segment, from: from, to: to, reversedPivot: voice.reversedPivot)
        return Double(magnitude) * g
    }

    /// Whether one voice reads quiet over `[from, to)` — the per-step test
    /// the walk asks, in the order road map 4's S1 settled on. `gain <=
    /// limit` is the FLOOR: a full-scale sample at that gain lands at or
    /// under `thresholdDB`, so a turned-down, faded or ducked voice never
    /// holds a cut up, in EITHER mode, before the model is ever consulted —
    /// the mix promise the sheet's hint and the tool's catalog entry both
    /// make. `byLevel` (this VOICE's source window holds no voice, computed
    /// once per voice over its whole segment) and `.level` mode both fall
    /// through to the level test unchanged; otherwise a pending cache is
    /// never quiet, and the model's answer is the MAX Silero probability
    /// over the step, never the mean.
    private static func isQuiet(
        _ voice: Voice, from: Ticks, to: Ticks, limit: Double, mode: Mode, voiceConfidence: Double,
        byLevel: Bool
    ) -> Bool {
        let g = gain(of: voice, from: from, to: to)
        guard g > limit else { return true }
        if mode == .level || byLevel {
            return level(of: voice, from: from, to: to, step: 0) <= limit
        }
        guard let speech = voice.speech else { return false }
        return Double(
            MediaSpeech.speechMax(
                speech, over: voice.segment, from: from, to: to,
                reversedPivot: voice.reversedPivot)) < voiceConfidence
    }

    /// Whether a track's envelope is anything but zero across a span. The
    /// ramps cover a track's whole extent with no gaps, so a span nothing
    /// covers is a plan this build does not understand — believe the segment
    /// rather than silence it.
    private static func isAudible(_ ramps: [PlanRamp]?, over span: (Ticks, Ticks)) -> Bool {
        guard let ramps = ramps, !ramps.isEmpty else { return true }
        var covered = false
        for ramp in ramps {
            let end = ramp.start + max(0, ramp.duration)
            guard end > span.0, ramp.start < span.1 else { continue }
            covered = true
            if max(ramp.from, ramp.to) > 0 { return true }
        }
        return !covered
    }

}
