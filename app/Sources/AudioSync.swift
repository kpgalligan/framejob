import Foundation

/// Clip ▸ Synchronize Audio and `sync_audio` (road map "audio-sync", AS-1;
/// spec §11 SY-1..SY-5): selected clips that play sound are lined up by their
/// sound. One ANCHOR stays where it is and every other clip moves by a
/// frame-snapped `move_clip`, all as one undo step — or the whole command
/// refuses, naming every reason at once (SY-1).
///
/// `AudioNormalize`'s shape: `read` takes everything off the document once
/// (the edited project's snapshot and plan, and each file's cached waveform),
/// and `plan` is pure — readings in, ops or a refusal out. The menu item and
/// the tool call the same pair, so neither measures anything of its own.
/// The signal arithmetic is `AudioSyncMatch`'s.
///
/// **Time.** A reading's `zero` is the project tick at which its file's
/// source tick 0 would play (`segment.start − segment.sourceIn`), so a sound
/// at bucket `b` of a file plays at `zero + b·6000`. A mover whose sound at
/// bucket `m` is the anchor's at `m + lag` lines up when its zero becomes
/// `zeroA + lag·6000`: `delta = zeroA − zeroN + lag·6000`, snapped to the
/// frame grid (SY-4), because the model stores no sub-frame time.
///
/// **What it refuses rather than lets the core decide** (SY-4): `move_clip`
/// clamps the earliest clip at 0, and on an overlap within the overlap rule
/// it ADDS a cross dissolve instead of refusing — so a mover that would have
/// to start before the timeline, or would land on another clip of its own
/// track, is refused here, by name.
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
    /// onsets and the clips it shares its track with.
    struct Reading: Equatable {
        let clip: UInt32
        let media: UInt32
        let trackIndex: Int
        let start: Ticks
        let end: Ticks
        let zero: Ticks
        let hasVideo: Bool
        let onsets: [Float]
        let neighbours: [Neighbour]
    }

    /// Everything a run reads, taken off the document once.
    struct Input {
        let readings: [Reading]
        let problems: [Problem]
        /// The anchor the caller named, or nil for SY-2's rule.
        let anchor: UInt32?
        let fps: Fps
    }

    /// One mover's answer: its lag in ticks, the frame-snapped move, where it
    /// lands, how sure the match was and what drift it measured.
    struct Synced: Equatable {
        let clip: UInt32
        let media: UInt32
        let lag: Ticks
        let delta: Ticks
        let start: Ticks
        let correlation: Double
        let ratio: Double
        let drift: AudioSyncMatch.DriftAnswer
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

    /// Reads the edited project's snapshot, plan and peaks for `clips` (nil:
    /// the document's selection). nil only when the plan cannot be read; a
    /// clip that cannot be matched is a `Problem`.
    static func read(from document: ProjectDocument, clips: [UInt32]?, anchor: UInt32?)
        -> Input? {
        guard let plan = document.editedProject.plan else { return nil }
        let snapshot = document.editedProject.snapshot
        let loader = MediaPeaks.Loader(cacheDirectory: document.cacheDirectory)

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

        var onsetsByMedia: [UInt32: [Float]] = [:]
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
                problems.append(
                    Problem(
                        clip: id,
                        reason: "plays at ×\(String(format: "%g", rate)); Synchronize Audio "
                            + "lines up clips playing at ×1."))
                continue
            }
            if case .media(_, _, true) = clip.source {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "plays reversed; Synchronize Audio lines up clips playing "
                            + "forwards."))
                continue
            }
            guard let peaks = loader.peaks(for: first.media) else {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is still being analysed — its waveform has not been written "
                            + "yet. Try again in a moment."))
                continue
            }
            guard peaks.count >= AudioSyncMatch.minimumFileBuckets else {
                problems.append(
                    Problem(
                        clip: id,
                        reason: "is too short to match: its file holds under "
                            + "\(AudioSyncMatch.minimumFileBuckets / 100) s of sound."))
                continue
            }
            let onsets = onsetsByMedia[first.media] ?? AudioSyncMatch.onsets(peaks)
            onsetsByMedia[first.media] = onsets
            let neighbours = snapshot.clips
                .filter { $0.track == clip.track && $0.id != id }
                .map { Neighbour(clip: $0.id, start: $0.start, end: $0.start + $0.duration) }
            readings.append(
                Reading(
                    clip: id, media: first.media,
                    trackIndex: snapshot.tracks.firstIndex { $0.id == clip.track } ?? 0,
                    start: clip.start, end: clip.start + clip.duration,
                    zero: first.start - first.sourceIn, hasVideo: pictured.contains(id),
                    onsets: onsets, neighbours: neighbours))
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

    // MARK: - Planning (SY-1, SY-3, SY-4, SY-5)

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

        // A file with no onset energy cannot be matched; the problem is the
        // silent clip's own, so a silent anchor is named once, not on every mover.
        let silent = "has no sound that rises anywhere to line up by."
        let anchorSilent = !anchor.onsets.contains { $0 != 0 }
        if anchorSilent { problems.append(Problem(clip: anchor.clip, reason: silent)) }

        let bucket = Double(MediaPeaks.bucketTicks)
        var synced: [Synced] = []
        var ops: [ReelOp] = []
        for mover in readings where mover.clip != anchor.clip {
            guard mover.onsets.contains(where: { $0 != 0 }) else {
                problems.append(Problem(clip: mover.clip, reason: silent))
                continue
            }
            if anchorSilent { continue }
            guard let match = AudioSyncMatch.match(anchor: anchor.onsets, mover: mover.onsets)
            else {
                problems.append(Problem(clip: mover.clip, reason: silent))
                continue
            }
            guard match.runnerUp != nil else {
                problems.append(
                    Problem(
                        clip: mover.clip,
                        reason: "too little room to compare its sound with clip "
                            + "\(anchor.clip)'s."))
                continue
            }
            guard match.isConfident else {
                problems.append(
                    Problem(
                        clip: nil,
                        reason: "no matching sound found between clip \(anchor.clip) and clip "
                            + "\(mover.clip) (correlation "
                            + String(format: "%.2f", match.correlation) + ", peak ratio "
                            + String(format: "%.2f", match.ratio) + "; needs ≥ "
                            + "\(AudioSyncMatch.minimumCorrelation) and ≥ "
                            + "\(AudioSyncMatch.minimumPeakRatio))."))
                continue
            }
            let lagTicks = Ticks((match.lag * bucket).rounded())
            let delta = ReelTime.snapToFrame(anchor.zero - mover.zero + lagTicks, fps: input.fps)
            let start = mover.start + delta
            let end = mover.end + delta
            guard start >= 0 else {
                let seconds = Double(-start) / Double(ReelTime.perSecond)
                problems.append(
                    Problem(
                        clip: mover.clip,
                        reason: "would have to start " + String(format: "%.2f", seconds)
                            + " s before the timeline begins."))
                continue
            }
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
            if delta != 0,
               let hit = mover.neighbours.first(where: { start < $0.end && $0.start < end }) {
                problems.append(
                    Problem(
                        clip: mover.clip, reason: "would overlap clip \(hit.clip) on its track."))
                continue
            }
            let lower = Int(MediaPeaks.bucketIndex(overlapStart - anchor.zero))
            let upper = Int(MediaPeaks.bucketIndex(overlapEnd - anchor.zero))
            let drift = AudioSyncMatch.drift(
                anchor: anchor.onsets, mover: mover.onsets, lag: match.lag,
                overlap: max(0, lower)..<max(0, lower, upper))
            synced.append(
                Synced(
                    clip: mover.clip, media: mover.media, lag: lagTicks, delta: delta,
                    start: start, correlation: match.correlation, ratio: match.ratio,
                    drift: drift))
            if delta != 0 { ops.append(.moveClip(clips: [mover.clip], delta: delta)) }
        }
        guard problems.isEmpty else { return .refused(problems) }
        return .planned(anchor: anchor.clip, synced: synced, ops: ops)
    }
}
