import Foundation

/// Clip ▸ Synchronize Audio and `sync_audio` (road maps "audio-sync", AS-1 and
/// AS-2, and "audio-sync-2", AS-3 and AS-4; spec §11 SY-1..SY-21): selected clips that
/// play sound are lined up by their sound. One ANCHOR stays where it is and every other clip moves by a
/// frame-snapped `move_clip`, its clock drift corrected by a `set_speed`, all
/// as one undo step — or the whole command refuses, naming every reason at
/// once (SY-1).
///
/// `AudioNormalize`'s shape: `read` takes everything off the document once
/// (the edited project's snapshot and plan, and each file's cached sync
/// features, samples and speech probabilities), and `plan` is pure — readings
/// in, ops or a refusal out. The menu item and the tool call the same pair,
/// so neither measures anything of its own. The signal arithmetic is
/// `AudioSyncMatch`'s, the sub-frame refinement `AudioSyncPHAT`'s (SY-20),
/// where to look and what to choose
/// `AudioSync+Search.swift`'s, and which planned moves are only WEAK — asked
/// about, never applied silently (SY-18, SY-19) — `AudioSync+Weak.swift`'s.
///
/// **Time.** A reading's `zero` is the project tick at which its file's
/// source tick 0 would play (`segment.start − round(segment.sourceIn /
/// speed)`), and its features are resampled onto its timeline grid (frame k
/// = source frame k·speed; themselves at ×1), and so are its speech masks
/// (SY-17, frame k = source frame round(k·speed)), so a sound at timeline
/// frame `f` plays at `zero + f·9600`; its samples are read at `t·speed`
/// where they are used (SY-20). A mover whose sound at frame `m` is the
/// anchor's at `m + lag` lines up when its zero becomes `zeroA + lag·9600`:
/// `delta = zeroA − zeroN + lag·9600`, snapped to the frame grid (SY-4),
/// because the model stores no sub-frame time.
///
/// **Drift and the refinement** (SY-6, SY-20, SY-21, SY-29). Over the overlap
/// the coarse delta gives, the lag is fitted as a line, `lag(a) = c + ρ·a` (a an
/// anchor timeline sample, 75 ticks each, c in samples); not measured, the
/// line is the coarse lag. PHAT along it over the overlap's centre 30 s —
/// the files' overlap at the lag when that played overlap is under 2 s —
/// shifts c by a clear peak's sub-sample shift. **The waveform gate**
/// (SY-29): a match of either tier stands only on that clear peak; a peak
/// that is not clear refuses the command (`incoherent`), and so does a
/// refinement that cannot run (`unconfirmed`) unless neither reading carries
/// samples at all, when the features' tier stands. Corrected
/// (SY-8), the mover's speed becomes `s' = s·(1 − ρ)` and, since `set_speed`
/// keeps its start S and in point I, source tick μ plays at `S + δ + (μ −
/// I)/s'` — on the anchor's line everywhere when `δ = snapToFrame(round(zeroA
/// + 75·c/(1 − ρ) − S + I/s'))` (`correctedDelta`). Left uncorrected, it is
/// placed by the line's value at the overlap's centre aMid, `delta =
/// snapToFrame(zeroA − zeroN + round((c + ρ·aMid)·75))`; not measured, by
/// the (refined) lag. Snapping leaves one constant offset of at most half a
/// frame.
///
/// **The head trim** (SY-16, the owner's choice): a mover that would start
/// before 0 loses the excess off its head by a `trim_start` between the
/// `set_speed` and the `move_clip`, so it starts at 0 and what remains plays
/// in sync. **What it refuses rather than lets the core decide** (SY-4):
/// `move_clip` clamps the earliest clip at 0, and on an overlap within the
/// overlap rule it ADDS a cross dissolve instead of refusing — so a mover
/// that would land on another clip of its own track is refused here, by
/// name — on the FINAL span, after any change of speed or trim (SY-10).
enum AudioSync {

    // MARK: - Vocabulary

    /// One reason the command will not run: about a clip ("clip N: …") or
    /// about the selection as a whole (the reason alone).
    struct Problem: Equatable {
        let clip: UInt32?
        let reason: String

        var description: String {
            guard let clip = clip else { return reason }
            return "clip \(clip): \(reason)"
        }
    }

    /// Another top-level clip on a reading's track, as the span it occupies.
    struct Neighbour: Equatable {
        let clip: UInt32
        let start: Ticks
        let end: Ticks
    }

    /// One clip that can be matched: where it sits, where its file's tick 0
    /// plays, whether it has pictures (the anchor rule, SY-2), its file's
    /// samples and sync features, and the clips it shares its track with.
    struct Reading: Equatable {
        let clip: UInt32
        let media: UInt32
        let trackIndex: Int
        let start: Ticks
        let end: Ticks
        let zero: Ticks
        let hasVideo: Bool
        /// Its file's 8 kHz samples (`cache/sync/<id>.pcm`) on the SOURCE grid.
        let samples: [Int16]
        /// Its file's `SyncFeatures` frames on the SOURCE grid, frame-major.
        let features: [Float]
        /// Which of those frames are speech (SY-17), one per frame on the
        /// SOURCE grid; nil when the voice model cannot be used.
        let speech: [Bool]?
        let neighbours: [Neighbour]
        /// The clip's playback rate, within SY-9's band.
        let speed: Double
        /// Its first audio segment's in point, in source ticks.
        let sourceIn: Ticks
    }

    /// Everything a run reads, taken off the document once.
    struct Input {
        let readings: [Reading]
        let problems: [Problem]
        /// The anchor the caller named, or nil for SY-2's rule.
        let anchor: UInt32?
        let fps: Fps
    }

    /// One mover's answer: its lag in ticks (refined, at the overlap's
    /// centre), the coarse lag and the refinement (SY-20), the frame-snapped
    /// move, where it lands, how sure the match was and how it was found,
    /// what drift it measured, its speed, duration and correction after the
    /// command, and the head it lost to start at 0 (SY-16).
    struct Synced: Equatable {
        let clip: UInt32
        let media: UInt32
        let lag: Ticks
        /// The coarse match's lag in ticks, before the refinement.
        let coarseLag: Ticks
        /// The PHAT refinement over the overlap; nil when none ran.
        let refinement: AudioSyncPHAT.Refinement?
        let delta: Ticks
        let start: Ticks
        /// The chosen lag's z-score (SY-12).
        let confidence: Double
        let search: Search
        let chosenBy: ChosenBy
        let matchedOn: AudioSyncMatch.MatchedOn
        let candidates: [CandidateMove]
        let drift: AudioSyncMatch.DriftAnswer
        let speed: Double
        let duration: Ticks
        let correction: Correction
        let trimmed: Ticks
    }

    enum Plan {
        case refused([Problem])
        case planned(anchor: UInt32, synced: [Synced], ops: [ReelOp])
    }

    // MARK: - Offering it

    /// Whether the command can be offered: at least two selected clips pass
    /// `AudioNormalize.canOffer` (sound, and not a nest). A cheap pre-check
    /// of the snapshot, never the plan — `read` may still refuse.
    static func canOffer(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> Bool {
        clips.filter { AudioNormalize.canOffer($0, in: snapshot) }.count >= 2
    }

    // MARK: - Reading

    /// Reads the edited project's snapshot, plan, sync features and samples
    /// and (with the voice model) speech probabilities for `clips` (nil:
    /// the document's selection). nil only when the plan cannot be read; a
    /// clip that cannot be matched is a `Problem`.
    static func read(from document: ProjectDocument, clips: [UInt32]?, anchor: UInt32?)
        -> Input? {
        guard let plan = document.editedProject.plan else { return nil }
        let snapshot = document.editedProject.snapshot

        var audio: [UInt32: [PlanSegment]] = [:]
        for track in plan.audioTracks {
            for segment in track.segments where segment.duration > 0 {
                audio[segment.clip, default: []].append(segment)
            }
        }
        var pictured: Set<UInt32> = []
        for track in plan.videoTracks {
            for segment in track.segments where segment.duration > 0 {
                pictured.insert(segment.clip)
            }
        }

        var samplesByMedia: [UInt32: [Int16]] = [:]
        var featuresByMedia: [UInt32: [Float]] = [:]
        var speechByMedia: [UInt32: [Float]] = [:]
        let voice = SileroVAD.isAvailable
        var readings: [Reading] = []
        var problems: [Problem] = []
        var seen: Set<UInt32> = []
        for id in clips ?? document.selection.sorted() where seen.insert(id).inserted {
            guard let clip = snapshot.clip(id) else {
                problems.append(Problem(clip: id, reason: "is not a clip in this project."))
                continue
            }
            if case .nest = clip.source {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is a nest, and a nest has no sound of its own to match: the "
                            + "waveform cache is per media file and the clips inside a nest "
                            + "each have their own. Open it (⌘↓) and synchronize the clips "
                            + "inside."))
                continue
            }
            guard let segments = audio[id]?.sorted(by: { $0.start < $1.start }),
                  let first = segments.first
            else {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "plays no sound in this timeline, so there is nothing to line "
                            + "it up by. A still, a clip whose media has no audio track and a "
                            + "clip with audio switched off all read this way."))
                continue
            }
            if clip.speed != 1 || segments.contains(where: { $0.isTimeScaled }) {
                let scaled = segments.first { $0.isTimeScaled } ?? first
                let rate = clip.speed != 1
                    ? clip.speed : Double(scaled.sourceDuration) / Double(max(scaled.duration, 1))
                // At speed 1 a time-scaled segment is a stretch the clip's
                // speed does not say, so neither `zero` nor `set_speed` can
                // read it: refused, as AS-1 did (SY-9).
                if let problem = rateProblem(rate) ?? (clip.speed == 1 ? stretched(rate) : nil) {
                    problems.append(Problem(clip: id, reason: problem))
                    continue
                }
            }
            if case .media(_, _, true) = clip.source {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "plays reversed; Synchronize Audio lines up clips playing "
                            + "forwards."))
                continue
            }
            let cached = featuresByMedia[first.media] ?? document.cacheDirectory.flatMap {
                MediaImporter.loadSyncFeatures(for: first.media, in: $0)
            }
            let probabilities = !voice ? nil : speechByMedia[first.media]
                ?? document.cacheDirectory.flatMap {
                    MediaImporter.loadSpeech(for: first.media, in: $0)
                }
            let pcm = samplesByMedia[first.media] ?? document.cacheDirectory.flatMap {
                MediaImporter.loadSyncSamples(for: first.media, in: $0)
            }
            // The samples are the features' own: a count that disagrees is a
            // pass not finished, read as not written.
            let written = cached.flatMap { features in
                pcm.flatMap {
                    SyncFeatures.frameCount(samples: $0.count)
                        == features.count / SyncFeatures.coefficients ? $0 : nil
                }
            }
            guard let features = cached, let samples = written, !voice || probabilities != nil
            else {
                // The waveform can be on the timeline while the features
                // and speech that land after it are not: say which.
                let missing = written == nil
                    ? " for Synchronize Audio — its sound features have not been written yet."
                    : " for Synchronize Audio — its speech has not been detected yet."
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is still being analysed" + missing + " Try again in a moment."))
                continue
            }
            featuresByMedia[first.media] = features
            samplesByMedia[first.media] = samples
            if let probabilities { speechByMedia[first.media] = probabilities }
            let frames = features.count / SyncFeatures.coefficients
            guard frames >= AudioSyncMatch.minimumStretchFrames else {
                let seconds = String(
                    format: "%g",
                    Double(Ticks(AudioSyncMatch.minimumStretchFrames) * SyncFeatures.frameTicks)
                        / Double(ReelTime.perSecond))
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is too short to match: its file holds under \(seconds) s of "
                            + "sound."))
                continue
            }
            let neighbours = snapshot.clips
                .filter { $0.track == clip.track && $0.id != id }
                .map { Neighbour(clip: $0.id, start: $0.start, end: $0.start + $0.duration) }
            readings.append(
                Reading(
                    clip: id, media: first.media,
                    trackIndex: snapshot.tracks.firstIndex { $0.id == clip.track } ?? 0,
                    start: clip.start, end: clip.start + clip.duration,
                    zero: first.start - Ticks((Double(first.sourceIn) / clip.speed).rounded()),
                    hasVideo: pictured.contains(id), samples: samples, features: features,
                    speech: probabilities.map { AudioSyncMatch.speechMask($0, frames: frames) },
                    neighbours: neighbours,
                    speed: clip.speed, sourceIn: first.sourceIn))
        }
        return Input(
            readings: readings, problems: problems, anchor: anchor, fps: snapshot.canvas.fps)
    }

    // MARK: - The anchor (SY-2)

    /// The named reading; else, among the readings with pictures (all of them
    /// when none has), the earliest start, then the rearmost track, then the
    /// lowest id.
    static func chooseAnchor(_ readings: [Reading], named: UInt32?) -> Reading? {
        if let named = named { return readings.first { $0.clip == named } }
        let pictured = readings.filter { $0.hasVideo }
        let pool = pictured.isEmpty ? readings : pictured
        return pool.min { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.trackIndex != b.trackIndex { return a.trackIndex < b.trackIndex }
            return a.clip < b.clip
        }
    }

    // MARK: - Planning (SY-1, SY-4, SY-6..SY-10, SY-12..SY-16)

    /// The ops, or every reason there are none. All or nothing: one problem
    /// anywhere refuses the whole command.
    static func plan(_ input: Input) -> Plan {
        guard input.problems.isEmpty else { return .refused(input.problems) }
        let readings = input.readings
        guard readings.count >= 2 else {
            return .refused([
                Problem(clip: nil, reason: "Synchronize Audio needs at least two clips with sound.")
            ])
        }
        guard let anchor = chooseAnchor(readings, named: input.anchor) else {
            return .refused([
                Problem(
                    clip: input.anchor,
                    reason: "is not one of the clips being synchronized, so it cannot be the "
                        + "anchor.")
            ])
        }

        var problems: [Problem] = []
        var byTrack: [Int: [UInt32]] = [:]
        for reading in readings { byTrack[reading.trackIndex, default: []].append(reading.clip) }
        for index in byTrack.keys.sorted() {
            guard let ids = byTrack[index], ids.count > 1 else { continue }
            let names = ids.map { "clip \($0)" }.joined(separator: " and ")
            problems.append(
                Problem(
                    clip: nil,
                    reason: "\(names) are on one track; Synchronize Audio lines up clips on "
                        + "different tracks."))
        }

        // A file with no sound cannot be matched; the problem is the silent
        // clip's own, so a silent anchor is named once, not on every mover.
        let silent = "has no sound to line up by."
        let anchorSilent = AudioSyncMatch.isSilent(anchor.features)
        if anchorSilent { problems.append(Problem(clip: anchor.clip, reason: silent)) }
        let anchorFrames = AudioSyncMatch.resampledFrames(anchor.features, speed: anchor.speed)
        let anchorSpeech = anchor.speech.map {
            AudioSyncMatch.resampledMask($0, speed: anchor.speed)
        }

        let hop = Double(SyncFeatures.hop)
        let sample = Double(AudioSyncPHAT.sampleTicks)
        // SY-22: one setup for every refinement this plan makes.
        let fft = AudioSyncPHAT.FFT(log2n: AudioSyncPHAT.planLog2n)
        var synced: [Synced] = []
        var ops: [ReelOp] = []
        for mover in readings where mover.clip != anchor.clip {
            guard !AudioSyncMatch.isSilent(mover.features) else {
                problems.append(Problem(clip: mover.clip, reason: silent))
                continue
            }
            if anchorSilent { continue }
            let moverFrames = AudioSyncMatch.resampledFrames(mover.features, speed: mover.speed)
            let moverSpeech = mover.speech.map {
                AudioSyncMatch.resampledMask($0, speed: mover.speed)
            }
            let found: Found
            switch find(
                anchor: anchor, anchorFrames: anchorFrames, anchorSpeech: anchorSpeech,
                mover: mover, moverFrames: moverFrames, moverSpeech: moverSpeech, fps: input.fps)
            {
            case .refused(let problem):
                problems.append(problem)
                continue
            case .found(let answer):
                found = answer
            }
            let lagTicks = Ticks((found.lag * Double(SyncFeatures.frameTicks)).rounded())
            let coarse = ReelTime.snapToFrame(anchor.zero - mover.zero + lagTicks, fps: input.fps)
            let lower = frameIndex(max(anchor.start, mover.start + coarse) - anchor.zero)
            let upper = frameIndex(min(anchor.end, mover.end + coarse) - anchor.zero)
            let window = max(0, lower)..<max(0, lower, upper)
            var drift = AudioSyncMatch.drift(
                anchor: anchorFrames, mover: moverFrames, anchorSpeech: anchorSpeech,
                moverSpeech: moverSpeech, anchorSamples: anchor.samples,
                moverSamples: mover.samples, anchorSpeed: anchor.speed, moverSpeed: mover.speed,
                lag: found.lag, overlap: window, fft: fft)
            // SY-20: PHAT along the line over the overlap's centre 30 s; under
            // 2 s played, over the files' overlap at the lag instead (SY-29).
            var line = AudioSyncPHAT.Line(intercept: found.lag * hop, rate: 0)
            if case .measured(let fit) = drift {
                line = AudioSyncPHAT.Line(intercept: fit.intercept, rate: fit.rate)
            }
            let played = region(window)
            let width = SyncFeatures.coefficients
            let reach = played.count >= AudioSyncPHAT.minimumRegionSamples
                ? played
                : region(
                    filesOverlap(
                        lag: found.lag, anchorFrames: anchorFrames.count / width,
                        moverFrames: moverFrames.count / width))
            let refinement = AudioSyncPHAT.refine(
                anchor: anchor.samples, anchorSpeed: anchor.speed, mover: mover.samples,
                moverSpeed: mover.speed, line: line, region: reach, fft: fft)
            // SY-29, the waveform gate: either tier stands only on a clear
            // peak; a refinement that could not run refuses too, unless
            // neither reading carries samples at all.
            if let refinement, !refinement.clear {
                problems.append(
                    Problem(
                        clip: nil,
                        reason: incoherent(
                            anchor: anchor.clip, mover: mover.clip, delta: coarse,
                            confidence: found.confidence, refinement: refinement)))
                continue
            }
            if refinement == nil, !(anchor.samples.isEmpty && mover.samples.isEmpty) {
                problems.append(
                    Problem(
                        clip: nil,
                        reason: unconfirmed(
                            anchor: anchor.clip, mover: mover.clip, delta: coarse,
                            confidence: found.confidence)))
                continue
            }
            var refinedTicks = lagTicks
            var delta = coarse
            if let refinement, refinement.clear {
                if case .measured(let fit) = drift {
                    drift = .measured(
                        AudioSyncMatch.Drift(
                            ppm: fit.ppm, milliseconds: fit.milliseconds, rate: fit.rate,
                            intercept: fit.intercept + refinement.shift,
                            errorMilliseconds: fit.errorMilliseconds, windows: fit.windows,
                            on: fit.on))
                } else {
                    refinedTicks = Ticks(((found.lag * hop + refinement.shift) * sample).rounded())
                    delta = ReelTime.snapToFrame(
                        anchor.zero - mover.zero + refinedTicks, fps: input.fps)
                }
            }
            let correction = Self.correction(for: drift, speed: mover.speed)
            var newSpeed: Double?
            if case .measured(let fit) = drift {
                let centre = Double(window.lowerBound + window.upperBound) / 2 * hop
                let line = Ticks(((fit.intercept + fit.rate * centre) * sample).rounded())
                refinedTicks = line
                delta = ReelTime.snapToFrame(anchor.zero - mover.zero + line, fps: input.fps)
                if case .apply(let speed) = correction {
                    newSpeed = speed
                    delta = correctedDelta(
                        anchor: anchor, mover: mover, drift: fit, speed: speed, fps: input.fps)
                }
            }
            let duration = mover.end - mover.start
            let newDuration = newSpeed.map {
                durationAtSpeed(duration, from: mover.speed, to: $0, fps: input.fps)
            } ?? duration
            // SY-16: what would fall before 0 is trimmed off the mover's head.
            let excess = max(0, -(mover.start + delta))
            let start = mover.start + delta + excess
            let end = mover.start + delta + newDuration
            guard newDuration - excess >= input.fps.frameDuration else {
                let seconds = Double(excess) / Double(ReelTime.perSecond)
                problems.append(
                    Problem(
                        clip: mover.clip,
                        reason: "would have to lose " + String(format: "%.2f", seconds)
                            + " s of its head to start at 0, leaving under a frame of it."))
                continue
            }
            // Corrected and growing, `set_speed` runs first and spans [S, S + d').
            let grown = excess > 0 && newDuration > duration
            let overlapStart = max(anchor.start, start)
            let overlapEnd = min(anchor.end, end)
            guard overlapStart < overlapEnd else {
                problems.append(
                    Problem(
                        clip: mover.clip,
                        reason: "once lined up it would not play at any moment clip "
                            + "\(anchor.clip) plays."))
                continue
            }
            if delta != 0 || newDuration != duration,
               let hit = mover.neighbours.first(where: {
                   (start < $0.end && $0.start < end)
                       || (grown && mover.start < $0.end && $0.start < mover.start + newDuration)
               }) {
                problems.append(
                    Problem(
                        clip: mover.clip, reason: "would overlap clip \(hit.clip) on its track."))
                continue
            }
            synced.append(
                Synced(
                    clip: mover.clip, media: mover.media, lag: refinedTicks,
                    coarseLag: lagTicks, refinement: refinement, delta: delta,
                    start: start, confidence: found.confidence, search: found.search,
                    chosenBy: found.chosenBy, matchedOn: found.matchedOn,
                    candidates: found.candidates, drift: drift,
                    speed: newSpeed ?? mover.speed, duration: newDuration - excess,
                    correction: correction, trimmed: excess))
            ops += Self.ops(
                clip: mover.clip, delta: delta, from: mover.speed, to: newSpeed,
                duration: duration, newDuration: newDuration,
                trimTo: excess > 0 ? mover.start + excess : nil)
        }
        guard problems.isEmpty else { return .refused(problems) }
        return .planned(anchor: anchor.clip, synced: synced, ops: ops)
    }

    /// The anchor timeline frame holding `ticks` after its zero: `⌊ticks /
    /// frameTicks⌋`.
    private static func frameIndex(_ ticks: Ticks) -> Int {
        let step = SyncFeatures.frameTicks
        let quotient = ticks / step
        return Int(ticks % step < 0 ? quotient - 1 : quotient)
    }

    /// SY-20's region: `overlap` (anchor timeline frames) in samples, its
    /// centre `maximumRegionSamples` when it is longer.
    private static func region(_ overlap: Range<Int>) -> Range<Int> {
        let hop = SyncFeatures.hop
        let low = overlap.lowerBound * hop
        let high = overlap.upperBound * hop
        let cap = AudioSyncPHAT.maximumRegionSamples
        guard high - low > cap else { return low..<high }
        let start = (low + high) / 2 - cap / 2
        return start..<(start + cap)
    }

    /// SY-29's fallback region: the anchor timeline frames where the two
    /// files (`anchorFrames` and `moverFrames` frames on their timeline
    /// grids) overlap at `lag`, rounded outward — `[max(0, ⌊lag⌋), min(anchorFrames,
    /// moverFrames + ⌈lag⌉))` — so every lag a search can score holds at
    /// least `minimumOverlapFrames` (a sample read past a file's end is 0).
    private static func filesOverlap(lag: Double, anchorFrames: Int, moverFrames: Int)
        -> Range<Int> {
        let lo = max(0, Int(lag.rounded(.down)))
        let hi = max(lo, min(anchorFrames, moverFrames + Int(lag.rounded(.up))))
        return lo..<hi
    }
}
