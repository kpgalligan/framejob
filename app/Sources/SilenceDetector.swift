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

        static let defaultThresholdDB = -40.0
        static let defaultMinLength: Ticks = ReelTime.ticks(seconds: 0.5)
        static let defaultPadding: Ticks = ReelTime.ticks(seconds: 0.1)

        /// The ranges the sheet's controls and the tool's arguments clamp to.
        /// −80 dBFS is under any real recording's noise floor and −10 dBFS is
        /// well into speech, so the two ends are "cut nothing" and "cut
        /// almost everything" rather than arbitrary numbers.
        static let thresholdRange = -80.0...(-10.0)
        static let minLengthRange = 0.05...10.0
        static let paddingRange = 0.0...2.0

        init(
            thresholdDB: Double = Settings.defaultThresholdDB,
            minLength: Ticks = Settings.defaultMinLength,
            padding: Ticks = Settings.defaultPadding,
            scope: Scope = .audible
        ) {
            self.thresholdDB = thresholdDB
            self.minLength = minLength
            self.padding = padding
            self.scope = scope
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

        var removed: Ticks { spans.reduce(0) { $0 + $1.length } }
        var isEmpty: Bool { spans.isEmpty }
    }

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

        var end: Ticks { segment.start + max(0, segment.duration) }
    }

    /// One nest clip a cut must not land inside, and its id so the sheet can
    /// name what it left alone.
    ///
    /// A nest on a LOCKED track is not one of these: `clear_range` neither
    /// splits nor removes there and `shift_clips` does not move it either,
    /// so nothing of it can be lost. Built once per `Input`, like `Voice`
    /// and for the same reason — it is a function of the snapshot alone.
    fileprivate struct NestExtent {
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
        fileprivate let voices: [Voice]
        /// The spans no candidate may reach into — see `NestExtent`.
        fileprivate let nests: [NestExtent]

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

        var voices: [Voice] = []
        for track in plan.audioTracks {
            for segment in track.segments where segment.duration > 0 {
                let span = (segment.start, segment.start + segment.duration)
                voices.append(
                    Voice(
                        segment: segment, ramps: track.ramps,
                        peaks: loader.peaks(for: segment.media),
                        reversedPivot: MediaPeaks.reversedPivot(for: segment, in: snapshot),
                        audible: isAudible(track.ramps, over: span)))
            }
        }
        // The walls. Top-level clips only, which is exactly right: a nest
        // INSIDE a nest is already behind the outer one's wall, and the op
        // can only ever split what `Project::clip` can name.
        let nests: [NestExtent] = snapshot.clips.compactMap { clip in
            guard case .nest = clip.source, clip.duration > 0,
                  // A track this build cannot find is treated as unlocked:
                  // the conservative reading, since being wrong the other
                  // way is the one that loses material.
                  snapshot.track(clip.track)?.locked != true
            else { return nil }
            return NestExtent(
                clip: clip.id, span: Span(start: clip.start, end: clip.start + clip.duration))
        }
        return Input(
            snapshot: snapshot, selection: selection ?? document.selection,
            pendingMedia: loader.pending.sorted(), voices: voices, nests: nests)
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
                protectedNests: [])
        }

        let step = MediaPeaks.bucketTicks
        let limit = Double(AudioDSP.gain(fromDecibels: Float(settings.thresholdDB)))
        let ordered = scoped.sorted { $0.segment.start < $1.segment.start }
        let domainStart = max(0, ordered.map { $0.segment.start }.min() ?? 0)
        let domainEnd = ordered.map { $0.end }.max() ?? domainStart

        // The walk is aligned to absolute multiples of a bucket rather than to
        // the first segment, so two projects that differ only in where their
        // audio starts round the same way.
        var t = (domainStart / step) * step
        var next = 0
        var active: [Voice] = []
        var runStart: Ticks?
        var runs: [Span] = []
        while t < domainEnd {
            let slotEnd = t + step
            while next < ordered.count, ordered[next].segment.start < slotEnd {
                active.append(ordered[next])
                next += 1
            }
            active.removeAll { $0.end <= t }

            var covered = false
            var quiet = true
            for voice in active {
                let from = max(t, voice.segment.start)
                let to = min(slotEnd, voice.end)
                guard to > from else { continue }
                covered = true
                if level(of: voice, from: from, to: to, step: step) > limit {
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
        return Outcome(
            spans: refine(outside, settings: settings, fps: input.snapshot.canvas.fps),
            scope: settings.scope, clips: clips, pendingMedia: pending,
            protectedNests: walled)
    }

    /// Length filter, then padding, then the frame grid — in that order,
    /// because the minimum is about the RUN the ear heard and the padding is
    /// about the CUT that replaces it.
    ///
    /// Both bounds snap INWARD: up for the start, down for the end. Inward is
    /// the conservative direction for an edit that deletes material — it can
    /// leave a frame of room tone, which is inaudible, where outward would
    /// clip the attack of the next word, which is not. A frame at 30 fps is
    /// 20 000 ticks against a bucket's 6 000, so nearest-snapping could move a
    /// cut by more than the detection resolution, and in the wrong direction
    /// half the time.
    private static func refine(_ runs: [Span], settings: Settings, fps: Fps) -> [Span] {
        var out: [Span] = []
        for run in runs {
            guard run.length >= settings.minLength else { continue }
            let padded = Span(
                start: run.start + settings.padding, end: run.end - settings.padding)
            guard padded.end > padded.start else { continue }
            let snapped = Span(
                start: snapUpToFrame(padded.start, fps: fps),
                end: snapDownToFrame(padded.end, fps: fps))
            guard snapped.start >= 0, snapped.end > snapped.start else { continue }
            out.append(snapped)
        }
        return out
    }

    // MARK: - The walls

    /// Every run cut into the pieces that lie OUTSIDE every nest clip, with
    /// the nests that took a cut's worth of quiet away named alongside.
    ///
    /// A piece may end exactly where a nest begins, and that is safe:
    /// `clear_range` cuts its bounds with `split_under_playhead`, which
    /// splits only what a tick falls STRICTLY inside, so a bound on a nest
    /// clip's own edge splits nothing and the ripple then moves the whole
    /// nest clip left — a move, not a cut into it. Nor can the op weld two
    /// pieces back together across a nest: it merges spans that overlap or
    /// TOUCH, and these are a nest clip's whole length apart.
    ///
    /// The second answer is the sheet's, and it names a nest only when the
    /// quiet inside it was long enough to have BEEN a cut — a stray bucket
    /// of room tone behind a wall is not something to explain.
    private static func excludingNests(
        _ runs: [Span], _ nests: [NestExtent], minLength: Ticks
    ) -> ([Span], [UInt32]) {
        guard !nests.isEmpty else { return (runs, []) }
        var walled: Set<UInt32> = []
        for nest in nests {
            for run in runs where overlap(run, nest.span) >= max(1, minLength) {
                walled.insert(nest.clip)
            }
        }
        // Merged first, so two nest clips that abut do not leave a
        // zero-length piece between them.
        let walls = merged(nests.map { $0.span })
        var out: [Span] = []
        for run in runs {
            var start = run.start
            for wall in walls {
                if wall.end <= start { continue }
                if wall.start >= run.end { break }
                if wall.start > start { out.append(Span(start: start, end: wall.start)) }
                start = wall.end
                if start >= run.end { break }
            }
            if start < run.end { out.append(Span(start: start, end: run.end)) }
        }
        return (out, walled.sorted())
    }

    /// The length two spans share, or 0.
    private static func overlap(_ a: Span, _ b: Span) -> Ticks {
        max(0, min(a.end, b.end) - max(a.start, b.start))
    }

    /// Overlapping and touching spans folded together, in start order — the
    /// same rule `edit_time.rs`'s `union` applies to the ranges the op is
    /// finally handed.
    private static func merged(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for span in spans.sorted(by: { $0.start < $1.start }) where span.end > span.start {
            guard let last = out.last, span.start <= last.end else {
                out.append(span)
                continue
            }
            out[out.count - 1] = Span(start: last.start, end: max(last.end, span.end))
        }
        return out
    }

    // MARK: - The quiet test

    /// `peak × envelope` for one segment over one step of project time.
    ///
    /// The envelope is sampled at both ends of the step and the LOUDER taken,
    /// so a step that straddles a fade's edge is judged by the loud side.
    /// A zero envelope short-circuits: a muted, solo-silenced or fully faded
    /// segment is silent in the mix whatever its file holds, which is the
    /// whole reason the test is written against the plan.
    private static func level(of voice: Voice, from: Ticks, to: Ticks, step: Ticks) -> Double {
        let gain = max(
            MediaPeaks.envelope(voice.ramps, at: from),
            MediaPeaks.envelope(voice.ramps, at: max(from, to - 1)))
        guard gain > 0 else { return 0 }
        // No peaks on disk yet: never quiet. Treating a missing cache as
        // silence would propose deleting the whole clip, which is the one
        // failure this feature must not have.
        guard let peaks = voice.peaks else { return .infinity }
        let magnitude = MediaPeaks.peak(
            peaks, over: voice.segment, from: from, to: to, reversedPivot: voice.reversedPivot)
        return Double(magnitude) * gain
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

    // MARK: - Frame snapping, directionally

    /// The core has `snap_up_to_frame` / `snap_down_to_frame` (the directional
    /// pair phase 1 added for exactly this), but neither crosses the FFI —
    /// `rc_time_snap_to_frame` is the whole C surface for time. So the two are
    /// composed here from the two pieces Swift DOES have, `ReelTime.snapToFrame`
    /// and `Fps.frameDuration`, rather than re-deriving a grid: the nearest
    /// boundary is asked for, and when it fell the wrong way the neighbouring
    /// one is asked for instead.
    private static func snapUpToFrame(_ t: Ticks, fps: Fps) -> Ticks {
        let nearest = ReelTime.snapToFrame(t, fps: fps)
        guard nearest < t else { return nearest }
        return ReelTime.snapToFrame(nearest + max(fps.frameDuration, 1), fps: fps)
    }

    private static func snapDownToFrame(_ t: Ticks, fps: Fps) -> Ticks {
        let nearest = ReelTime.snapToFrame(t, fps: fps)
        guard nearest > t else { return nearest }
        return ReelTime.snapToFrame(nearest - max(fps.frameDuration, 1), fps: fps)
    }
}
