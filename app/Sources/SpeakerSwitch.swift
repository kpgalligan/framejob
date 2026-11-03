import Foundation

/// Switch by Speaker's planner (road map "creator-jobs" SW2a, spec §11
/// SW-20…SW-25): which microphone is active on a 10 ms grid, the shots those
/// turns make on the angle tracks, and every refusal named at once. Nothing
/// here is visible yet; SW2b's sheet and tool write the shots onto a Program
/// track.
///
/// Pure (SW-25): `defaults`, `plan`, `labels` and `shots` read no document,
/// file or clock. `read` (`SpeakerSwitch+Read.swift`) is the one reader, and
/// the series it builds are `ClipLevelSeries`'. Names no `rc_*` but
/// `ReelTime.snapToFrame` and `ReelTime.format`.
enum SpeakerSwitch {
    static let actionName = "Switch by Speaker"
    static let maxAngles = 9

    /// What a qualifying crosstalk turn does: show the wide, or hold.
    enum Crosstalk: String { case wide, hold }

    /// Seconds and dB; the defaults are SW-S4's (SW-21) and SW-22's drafts.
    struct Settings: Equatable {
        var minShot = 2.0, minTurn = 1.0, lead = 0.2, crosstalkMin = 1.0, bridge = 0.5
        var crosstalk: Crosstalk = .wide
        var bleedDB = 15.0, dominanceDB = 8.0, floorMarginDB = 6.0, voiceThreshold: Float = 0.5
        /// nil = off.
        var wideAfter: Double? = nil
        /// The faces mode's label (SW-81): the top angle's activity over the next's, and the
        /// floor it must exceed.
        var faceRatio = FaceActivity.ratio, faceFloor = FaceActivity.floor
    }

    /// Who says who is talking (SW-83): each microphone its own person, or one microphone shared
    /// by two or more angles and their faces (`SpeakerSwitch+Faces.swift`).
    enum Mode: String { case microphones, faces }

    /// One face-speaker angle's mouth activity on the range's grid (SW-81): step k's activity,
    /// nil where none can be read. Empty: not read.
    struct FaceAngle: Equatable {
        let track: UInt32
        let activity: [Double?]
    }

    /// A person: their microphone track and the angle track that shows them.
    struct Speaker: Equatable { let mic: UInt32?; let angle: UInt32? }
    struct Pairing: Equatable { let speakers: [Speaker]; let wide: UInt32? }
    struct Span: Equatable { let clip: UInt32; let start: Ticks; let end: Ticks }
    /// An angle track and its picture clips (`SwitchAngle.pictureClips`), by start.
    struct AngleTrack: Equatable { let track: UInt32; let clips: [Span] }

    /// One microphone track on the range's grid: step k is
    /// `[from + k·step, from + (k+1)·step)`. Empty arrays: not read.
    struct Microphone: Equatable {
        let track: UInt32
        /// ℓ(k) in dB over the centred window; −∞ when silent.
        let level: [Double]
        /// v(k).
        let voice: [Float]
        /// A selected clip of this track plays at the step's midpoint.
        let covered: [Bool]
    }

    struct Input {
        let from: Ticks, to: Ticks, fps: Fps
        /// Front first.
        let angles: [AngleTrack]
        /// Front first.
        let microphones: [Microphone]
        let pairing: Pairing
        /// `read`'s: still analysed, no speech detection.
        let problems: [String]
        /// `ShotSplit.clipCount` of the document's project.
        let clipCount: Int
        let settings: Settings
        /// The faces mode's angles, front first (`readFaces`); empty in the microphones mode.
        var faces: [FaceAngle] = []
    }

    /// A step's label; `person` names the microphone track (in the faces mode, the angle's).
    enum Label: Equatable { case person(UInt32), crosstalk, nobody }
    struct Shot: Equatable { let angle: UInt32; let start: Ticks; let end: Ticks }
    enum Plan: Equatable { case refused([String]); case planned(shots: [Shot], added: Int) }

    // MARK: - SW-20's defaults

    /// The angles, microphones and pairing a selection implies, front first.
    static func defaults(selection: [ClipSnapshot], in snapshot: ProjectSnapshot)
        -> (angles: [UInt32], microphones: [UInt32], pairing: Pairing)
    {
        let front = snapshot.tracks.reversed().map(\.id)
        func holds(_ track: UInt32, _ test: (ClipSnapshot) -> Bool) -> Bool {
            selection.contains { $0.track == track && test($0) }
        }
        let angles = front.filter { holds($0) { isPicture($0, in: snapshot) } }
        let files = front.filter {
            holds($0) { playsSound($0, in: snapshot) && snapshot.media(for: $0)?.hasVideo == false }
        }
        let microphones = files.isEmpty
            ? angles.filter { holds($0) { playsSound($0, in: snapshot) } } : files

        var speakers: [Speaker] = []
        var used: Set<UInt32> = []
        for mic in microphones where angles.contains(mic) {
            used.insert(mic)
        }
        var free = angles.filter { !used.contains($0) }.makeIterator()
        for mic in microphones {
            if angles.contains(mic) {
                speakers.append(Speaker(mic: mic, angle: mic))
            } else if let angle = free.next() {
                used.insert(angle)
                speakers.append(Speaker(mic: mic, angle: angle))
            } else {
                speakers.append(Speaker(mic: mic, angle: nil))
            }
        }
        let left = angles.filter { !used.contains($0) }
        // SW-83: one microphone shared by every angle, and no wide (the faces mode).
        if microphones.count == 1, angles.count >= 2, let mic = microphones.first {
            return (angles, microphones,
                    Pairing(speakers: angles.map { Speaker(mic: mic, angle: $0) }, wide: nil))
        }
        return (angles, microphones,
                Pairing(speakers: speakers, wide: left.count == 1 ? left.first : nil))
    }

    /// A `detach_audio` half: the sound of a file with pictures.
    static func isDetachedSound(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        !clip.enabled.video && clip.linked != nil && snapshot.media(for: clip)?.hasVideo == true
    }

    /// A media clip with a picture that may make its track an angle.
    static func isPicture(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard case .media = clip.source, snapshot.sourceSize(of: clip) != nil else { return false }
        return !(clip.enabled.video == false && clip.linked != nil)
    }

    /// A media clip that sounds, by the snapshot alone (no plan here): its
    /// media has audio, its sound is on, and it is no detached camera sound.
    static func playsSound(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard case .media = clip.source, clip.enabled.audio,
            snapshot.media(for: clip)?.hasAudio == true
        else { return false }
        return !isDetachedSound(clip, in: snapshot)
    }

    // MARK: - The plan

    static func plan(_ input: Input) -> Plan {
        let refusals = refusals(input)
        if !refusals.isEmpty { return .refused(refusals) }
        let step = stepTicks
        let count = step > 0 ? Int(max(0, input.to - input.from) / step) : 0
        let faces = mode(input.pairing) == .faces
        let all = faces
            ? faceLabels(input)
            : labels(input.microphones.filter { $0.level.count == count }, settings: input.settings)
        let planned = shots(
            labels: all, from: input.from, to: input.to, fps: input.fps,
            pairing: faces ? facePairing(input.pairing) : input.pairing,
            angles: input.angles, settings: input.settings)
        let added = clipsAdded(planned, angles: input.angles, from: input.from, to: input.to)
        let most = Int(RC_MAX_CLIPS)
        if input.clipCount + added > most {
            return .refused([
                "Switch by Speaker would add \(added) clips to \(input.clipCount); the most is "
                    + "\(most) — raise the minimum shot."
            ])
        }
        return .planned(shots: planned, added: added)
    }

    /// SW-24's list, in its order; empty when nothing is refused.
    static func refusals(_ input: Input) -> [String] {
        var out: [String] = []
        let angles = input.angles.map(\.track)
        if angles.count < 2 {
            out.append(
                "Switch by Speaker needs at least two angles: tracks holding a selected clip "
                    + "with a picture.")
        }
        if angles.count > maxAngles {
            out.append(
                "Switch by Speaker takes at most nine angles; \(angles.count) tracks hold a "
                    + "selected clip with a picture.")
        }
        let microphones = input.microphones.map(\.track)
        let faces = mode(input.pairing) == .faces
        // SW-83: in the faces mode a speaker on the wide takes no part.
        for speaker in input.pairing.speakers
        where !(faces && speaker.angle != nil && speaker.angle == input.pairing.wide) {
            guard let mic = speaker.mic, microphones.contains(mic) else {
                let track = speaker.angle ?? speaker.mic ?? 0
                out.append("The speaker on track \(track) has no microphone.")
                continue
            }
            if speaker.angle.map({ !angles.contains($0) }) ?? true {
                out.append("The microphone on track \(mic) has no angle to show its speaker.")
            }
        }
        var counted: [UInt32] = []
        for mic in input.pairing.speakers.compactMap(\.mic) where !faces && !counted.contains(mic) {
            counted.append(mic)
            let n = input.pairing.speakers.filter { $0.mic == mic }.count
            if n > 1 {
                out.append(
                    "Track \(mic) is the microphone for \(n) speakers; each person needs their "
                        + "own microphone.")
            }
        }
        out += input.problems
        let count = stepTicks > 0 ? Int(max(0, input.to - input.from) / stepTicks) : 0
        let a = ReelTime.format(input.from, fps: input.fps, frames: true)
        let b = ReelTime.format(input.to, fps: input.fps, frames: true)
        for mic in input.microphones where mic.voice.count == count {
            let speaks = mic.voice.indices.contains {
                mic.covered[$0] && mic.voice[$0] >= input.settings.voiceThreshold
            }
            if !speaks {
                out.append(
                    "The microphone on track \(mic.track) has no speech between \(a) and \(b), "
                        + "so it never says who is talking.")
            }
        }
        // SW-84: a read angle with no step whose mouth can be read.
        for angle in input.faces where angle.activity.count == count
            && !angle.activity.contains(where: { $0 != nil })
        {
            out.append(
                "The camera on track \(angle.track) shows no face whose mouth can be read between "
                    + "\(a) and \(b), so it never says who is talking.")
        }
        if let gap = firstGap(input.angles, from: input.from, to: input.to) {
            out.append(
                "No angle has a picture between "
                    + "\(ReelTime.format(gap.from, fps: input.fps, frames: true)) and "
                    + "\(ReelTime.format(gap.to, fps: input.fps, frames: true)).")
        }
        return out
    }

    /// The first stretch of `[from, to)` no angle covers.
    static func firstGap(_ angles: [AngleTrack], from: Ticks, to: Ticks)
        -> (from: Ticks, to: Ticks)?
    {
        var t = from
        while t < to {
            if let end = angles.compactMap({ reach($0, from: t) }).max() {
                t = end
                continue
            }
            let next = angles.flatMap(\.clips).map(\.start).filter { $0 > t }.min() ?? to
            return (t, min(next, to))
        }
        return nil
    }

    /// How far `angle`'s clips cover contiguously from `t`; nil when they
    /// do not cover `t` (SW-13's rule).
    static func reach(_ angle: AngleTrack, from t: Ticks) -> Ticks? {
        var reached = angle.clips.filter { $0.start <= t && $0.end > t }.map(\.end).max()
        // A clip starting at or before the edge extends it (abutting files
        // cover their join): loop until the edge no longer moves.
        while let end = reached {
            let further = angle.clips.filter { $0.start <= end && $0.end > end }.map(\.end).max()
            guard let further else { break }
            reached = further
        }
        return reached
    }

    /// SW-24's N: per shot, the angle clips it overlaps (the later one
    /// taking over where two overlap, SW-15 (d)), plus a split for each
    /// angle clip straddling `from` and each straddling `to`.
    static func clipsAdded(_ shots: [Shot], angles: [AngleTrack], from: Ticks, to: Ticks) -> Int {
        var n = 0
        for shot in shots {
            guard let angle = angles.first(where: { $0.track == shot.angle }) else { continue }
            let crossing = angle.clips.filter { $0.end > shot.start && $0.start < shot.end }
            for (index, clip) in crossing.enumerated() {
                let next = index + 1 < crossing.count ? crossing[index + 1].start : shot.end
                if min(clip.end, next, shot.end) > max(clip.start, shot.start) { n += 1 }
            }
        }
        for clip in angles.flatMap(\.clips) {
            if clip.start < from && from < clip.end { n += 1 }
            if clip.start < to && to < clip.end { n += 1 }
        }
        return n
    }
}
