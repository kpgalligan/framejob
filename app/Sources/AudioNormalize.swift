import Foundation

/// Normalise Clip (road map 2 phase 5c): peaks in, ops out.
///
/// It is `CaptionLayout`'s shape applied to sound. The Audio pane's Normalize
/// button and the agent's `normalize_clip` tool both call `read` and then
/// `plan`, and neither of them computes a gain of its own — which is what makes
/// "the button and the tool do the same thing" a fact about the code rather
/// than a claim in a comment, and what lets the arithmetic be checked without
/// clicking anything.
///
/// **What it measures.** The clip's own peak over the source window it plays,
/// read out of `cache/peaks/<media id>.bin` through `MediaPeaks`. That cache is
/// PRE-FADER: it knows nothing about `volume`, a fade, a duck, a mute or a
/// solo, which is exactly right here — normalise is a statement about the
/// material, not about the mix. (It is the opposite of `SilenceDetector`, which
/// asks what the ear hears and therefore multiplies the same peak by the plan's
/// envelope.)
///
/// **The window comes from the PLAN segment, not from the clip.** It is the
/// window that actually plays, `evaluate.rs` has already clamped it to the file
/// and resolved the speed — and, decisively, "this clip has no audio segment"
/// is ONE test that correctly refuses every case that should be refused: a clip
/// with no media, with missing media, with media that has no audio track, with
/// `enabled.audio` false anywhere up the chain, and a still. Deriving the
/// window from the clip snapshot would need five separate guards to reach the
/// same place and would get the reversed and missing-media cases subtly wrong.
///
/// **Neither nest case is one of them**, and that is why `read` has an arm the
/// segment test does not need. A clip INSIDE a nest never reaches the segment
/// test WHILE THE NEST IS CLOSED: `snapshot.clip(id)` searches the top level,
/// which is all `Project::clip` searches either. That used to end the matter
/// — no op could name such a clip at all — and since road map 2's phase 9 it
/// does not: OPEN the nest (⌘↓, or `set_scope`) and `read` takes its snapshot
/// and its plan off `editedProject`, where that clip IS at the top level and
/// Normalize works on it like any other. The arm below is still needed,
/// because the clip is still unreachable from OUTSIDE. And a NEST
/// CLIP is refused ahead of the test, because the test would describe it
/// wrongly — the plan FLATTENS a nest (`nest.rs`), so the sound a nest clip
/// plays is carried by segments named for the clips inside it, and the missing
/// segment would tell somebody that a clip they can hear plays no sound.
/// `canOffer` is the same fact asked before the press: a nest clip has audio
/// properties (`edit_nest.rs` gives it them whenever anything inside can make
/// a sound) and `InspectorTab.hasAudio` therefore says yes about a command
/// that could only ever refuse it.
///
/// **It REPLACES `audio.volume`; it does not multiply it.** The measurement
/// knows nothing about the volume the clip already carries, so multiplying
/// would compound every previous press of the button. Replacing makes the
/// command idempotent, which is what a user means by "normalise this".
/// `muted` is left alone: a mute is a switch, not a level.
///
/// **It always writes BASE props, even when the playhead is inside an action.**
/// Every other control in the inspector routes through `InspectorBinding.split`,
/// which sends a write made inside an action to `set_action_end` instead — and
/// that is right for a control the user is dragging while watching one instant.
/// Normalise is a statement about the whole clip, so honouring the playhead
/// would make one button mean two different things depending on where the head
/// happened to be. The recorded limit: a clip whose volume is animated has its
/// BASE level normalised and is then overridden for the action's whole span.
/// The tooltip and the tool description both say so.
///
/// **One gain per clip.** A selection of five clips gets five different gains,
/// each measured from its own material — not one gain that would make them
/// match. Matching levels across a selection is a different feature and should
/// be asked for by that name.
///
/// **One job's failure is one job's problem** (`transcribe`'s posture): a clip
/// that cannot be measured is reported under `skipped`, by name and with a
/// reason, and the rest are still normalised.
enum AudioNormalize {

    // MARK: - The numbers

    /// The level a normalised clip's loudest moment lands on, in dBFS. −1 is
    /// the conventional ceiling: hot enough to use the format, with a decibel
    /// of room for the inter-sample peaks a lossy encoder can introduce past
    /// what any sample in the file reaches.
    static let defaultPeakDB = -1.0

    /// What a caller may ask for. Above 0 dBFS is a request to clip, and the
    /// bottom is well under anything anyone would call a level; a tool refuses
    /// outside this by name rather than clamping into it, which is the house
    /// rule for arguments (`edit_props.rs`).
    static let peakDBRange = -60.0...0.0

    /// The model's own ceiling on `audio.volume`: `MAX_GAIN` in
    /// `core/src/audio.rs`, enforced by `props_check.rs`'s `check_audio` and
    /// spelled 400 % by the pane's Volume row. A gain past it is not refused —
    /// see `Result.clamped`.
    static let maxGain = 4.0

    // MARK: - Vocabulary

    /// A clip that could not be measured, and why.
    ///
    /// `description` reads "clip 7: …", which is the form `import_captions`
    /// already reports under `skipped` and the form an agent can hand back
    /// unchanged.
    struct Problem: Equatable {
        let clip: UInt32
        let reason: String

        var description: String { "clip \(clip): \(reason)" }
    }

    /// One clip's measurement: everything the gain arithmetic needs, and
    /// nothing that depends on the target level.
    ///
    /// It is separate from `Result` so that `read` — which touches the
    /// document, the plan and the disk — happens once, and `plan` is pure
    /// arithmetic that can be run again at a different target for nothing.
    struct Reading: Equatable {
        let clip: UInt32
        let media: UInt32
        /// Linear magnitude, > 0. It may exceed 1: the cache is unclamped and
        /// a hot source really does read over full scale.
        let peak: Double
    }

    /// What one clip's normalise will do.
    struct Result: Equatable {
        let clip: UInt32
        let media: UInt32
        /// The measured peak as a level, in dBFS.
        let measuredDB: Double
        /// The volume written — `set_audio`'s `volume`, 0…4.
        let volume: Double
        /// Where that volume actually puts the clip's peak, in dBFS. It is the
        /// requested level unless `clamped`, and then it is lower.
        let resultDB: Double
        /// True when the clip wanted more than the model's 4× and got 4×. It
        /// is still normalised — to the loudest it can be — because refusing
        /// would be worse than doing the thing, and doing it silently would be
        /// worse than saying so.
        let clamped: Bool
    }

    /// Everything a normalise run reads, taken off the document ONCE — the
    /// `SilenceDetector.Input` seam, for the same reason: after this, a caller
    /// is doing arithmetic over values and nothing else.
    ///
    /// It carries no snapshot, unlike its neighbour: the ops name clip ids and
    /// the gains are already measured, so nothing after `read` has a question
    /// left for the project.
    struct Input {
        /// The clips that can be normalised, in the order they were asked for.
        let readings: [Reading]
        /// The clips that cannot, each with the reason it is not in `readings`.
        let problems: [Problem]

        var isEmpty: Bool { readings.isEmpty }
    }

    /// What a normalise run will do, before anything is applied: the ops, what
    /// each clip measured and landed at, and everything the caller has to tell
    /// the user about. The UI commits it through `InspectorBinding.apply`, the
    /// agent through `AgentServer.editResult`.
    struct Plan {
        /// The level asked for, after `plan`'s finiteness guard — report THIS
        /// rather than the argument, so a caller sees what actually ran.
        let peakDB: Double
        /// One `set_audio` per clip: the volumes differ, so they cannot share
        /// a patch the way the inspector's controls do.
        let ops: [ReelOp]
        let normalized: [Result]
        let skipped: [Problem]

        var isEmpty: Bool { ops.isEmpty }
    }

    // MARK: - Offering it

    /// Whether Normalize can be OFFERED for a clip: the question the Audio
    /// pane's button asks in its `enabled` closure and the Clip menu's
    /// validator arm asks on every menu open, and the only question either can
    /// afford — `ReelProject.plan` decodes JSON on every access, so neither may
    /// ask the plan.
    ///
    /// It is `InspectorTab.hasAudio` minus the nest, and the nest is the whole
    /// reason it exists. A nest clip that holds anything audible gets an
    /// `AudioProps` of its own (`edit_nest.rs`), so `hasAudio` says yes and
    /// every audio control in the pane is right to be live on it — its volume,
    /// mute and fades multiply what is under it. Normalize is the one that
    /// cannot be: the plan flattens a nest, so the clip has no segment of its
    /// own and `read` can only refuse it. A command that can only refuse is a
    /// command that should not be enabled (the same rule the Normalize
    /// validator arm was added for in the first place), and the answer lives
    /// HERE so the button and the menu item cannot answer it differently.
    ///
    /// It is a cheap PRE-check and not a promise: a clip it says yes about can
    /// still be refused by `read` — no peaks yet, silence, `enabled.audio` off
    /// up the chain — and being told why is better than a greyed control. That
    /// is the right side to be wrong on, and it is why this asks the snapshot
    /// while `read` asks the plan.
    static func canOffer(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard InspectorTab.hasAudio(clip, in: snapshot) else { return false }
        if case .nest = clip.source { return false }
        return true
    }

    // MARK: - Reading

    /// Reads a document's snapshot, plan and peak caches for `clips`.
    ///
    /// `clips` is the caller's list — the pane passes the selected clips that
    /// carry audio, the tool passes its `clips` argument. nil takes the
    /// document's own selection, which is the sheet-less equivalent of
    /// `SilenceDetector.read`'s selection override.
    ///
    /// nil is answered only when the core emitted a plan this build cannot
    /// read — the same failure `CompositionBuilder` treats as fatal. A clip
    /// that simply cannot be normalised is a `Problem`, not a nil.
    static func read(from document: ProjectDocument, clips: [UInt32]? = nil) -> Input? {
        // The EDITED project: a clip inside a nest is normalised against the
        // plan of the project it is IN, which is the only one holding an
        // audio segment for it (road map 2's phase 9).
        guard let plan = document.editedProject.plan else { return nil }
        let snapshot = document.editedProject.snapshot
        let loader = MediaPeaks.Loader(cacheDirectory: document.cacheDirectory)

        // Every audio segment in the timeline, indexed by the clip it plays.
        // A clip normally has exactly one; the list is kept whole because
        // nothing in §7.2 promises that, and taking the loudest of several is
        // the conservative reading (the clip ends up quieter than asked,
        // never clipped).
        var segments: [UInt32: [PlanSegment]] = [:]
        for track in plan.audioTracks {
            for segment in track.segments where segment.duration > 0 {
                segments[segment.clip, default: []].append(segment)
            }
        }

        var readings: [Reading] = []
        var problems: [Problem] = []
        var seen: Set<UInt32> = []
        for id in clips ?? document.selection.sorted() where seen.insert(id).inserted {
            guard let clip = snapshot.clip(id) else {
                problems.append(Problem(clip: id, reason: "is not a clip in this project."))
                continue
            }
            // A nest is refused HERE rather than by the segment test below,
            // and the reason is the message. A nest clip is audible — its own
            // volume and mute multiply every voice under it (`audio.rs`) — but
            // the plan flattens it, so every segment it plays carries an INNER
            // clip's id and `segments[id]` is empty for the nest itself. The
            // generic refusal would therefore say "plays no sound in this
            // timeline" about a clip the user can hear, which is the one thing
            // a refusal must not do; and there is no level to measure anyway,
            // because the peaks cache is per MEDIA and a nest holds clips that
            // each have their own.
            if case .nest = clip.source {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is a nest, and a nest has no level of its own to measure: the "
                            + "waveform cache is per media file and the clips inside a nest "
                            + "each have their own. Un-nest it (⇧⌘G), normalize the clips "
                            + "inside, and nest them again — or set the nest clip's own volume "
                            + "by hand."))
                continue
            }
            guard let cited = segments[id], !cited.isEmpty else {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "plays no sound in this timeline, so there is no level to "
                            + "measure. A still, a clip whose media has no audio track and a "
                            + "clip with audio switched off all read this way."))
                continue
            }
            // The core refuses `set_audio` on a clip with no audio group by
            // name ("clip N has no audio properties"), and that message would
            // otherwise reach a dialog from a button press. It cannot happen
            // for a clip that has a segment — `add_clip` gives an audio group
            // to exactly the clips whose media has sound — but a project is
            // JSON somebody may have edited, and the pre-check costs a line.
            guard clip.audio != nil else {
                problems.append(
                    Problem(clip: id, reason: "has no audio properties to write a volume into."))
                continue
            }

            // A missing peaks file means UNKNOWN, never silent: the cache is
            // written by a fire-and-forget task at open, so a project opened a
            // second ago or a just-relinked movie has none. Measuring against
            // it would compute a gain from a peak of 0 — the one failure this
            // feature must not have — so it is refused by name, and the caller
            // is told to ask again.
            var loudest = 0.0
            var missing = false
            for segment in cited {
                guard let peaks = loader.peaks(for: segment.media) else {
                    missing = true
                    break
                }
                let window = MediaPeaks.peak(
                    peaks, over: segment, from: segment.start,
                    to: segment.start + segment.duration,
                    reversedPivot: MediaPeaks.reversedPivot(for: segment, in: snapshot))
                loudest = max(loudest, Double(window))
            }
            guard !missing else {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is still being analysed — its waveform has not been written "
                            + "yet. Try again in a moment."))
                continue
            }
            // Exactly 0 is not quiet, it is nothing: there is no gain that
            // makes silence reach a level, and `target / 0` is an infinity
            // that would be written as a volume.
            guard loudest > 0 else {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is silent over the part of it that plays, so there is no level "
                            + "to normalise."))
                continue
            }
            readings.append(Reading(clip: id, media: cited[0].media, peak: loudest))
        }
        return Input(readings: readings, problems: problems)
    }

    // MARK: - Planning

    /// The ops, from a reading and a target level. Pure arithmetic: no
    /// document, no disk, no AppKit.
    ///
    /// `peakDB` is the caller's, validated by the caller — the pane passes the
    /// constant and the tool refuses anything outside `peakDBRange` by name. A
    /// non-finite one would put a NaN in every volume, so it falls back to the
    /// default here and the fallback is REPORTED as `Plan.peakDB`, the way
    /// `detect_silence` names back the settings it actually ran with.
    static func plan(_ input: Input, peakDB: Double = defaultPeakDB) -> Plan {
        let level = peakDB.isFinite ? peakDB : defaultPeakDB
        // Double `pow`, not `AudioDSP.gain(fromDecibels:)`: that one is the
        // render thread's single-precision fast path, written so a per-sample
        // conversion costs one `expf`. This is a model value, computed once
        // and stored in the project.
        let target = pow(10, level / 20)

        var ops: [ReelOp] = []
        var normalized: [Result] = []
        for reading in input.readings {
            let wanted = target / reading.peak
            let volume = min(maxGain, max(0, wanted))
            ops.append(.setAudio(clips: [reading.clip], patch: AudioPatch(volume: volume)))
            normalized.append(
                Result(
                    clip: reading.clip, media: reading.media,
                    measuredDB: decibels(reading.peak), volume: volume,
                    resultDB: decibels(reading.peak * volume), clamped: wanted > maxGain))
        }
        return Plan(peakDB: level, ops: ops, normalized: normalized, skipped: input.problems)
    }

    /// A linear magnitude as a level. The same expression as
    /// `AudioProps.decibels`, which is about a gain rather than about a peak —
    /// one line, two subjects, and no shared home worth making for it.
    private static func decibels(_ magnitude: Double) -> Double {
        magnitude <= 0 ? -.infinity : 20 * log10(magnitude)
    }
}
