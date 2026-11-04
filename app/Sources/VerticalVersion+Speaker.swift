import Foundation

/// Make Vertical's `follow: speaker` (road map "creator-jobs" VR6b, spec §11 VR-64, VR-66): which
/// tracks are microphones, which pictures are framed by who is talking and with which of them,
/// the turns filled on main, and what the sheet reads to confirm the match. The step itself is
/// `VerticalVersion+Plan.swift`'s; the match is the core's (`ReelProject.speakerMatch`, VR-65).
/// Swift restates none of VR-60's refusals: a microphone the core will not take reaches the
/// clip's entry in its own sentence. Names no `rc_*`.
extension VerticalVersion {
    /// A track the sheet offers as a microphone (VR-66 (b)): its name, and the clip that stands
    /// for it in `mics`, the earliest that plays a sound file.
    struct Microphone: Equatable {
        let track: UInt32
        let name: String
        let clip: UInt32
    }

    /// A picture framed by who is talking (VR-64 (b)), with its own microphones — one clip per
    /// microphone track that sounds under it, in `mics`' order — and their faces when given.
    struct SpeakerClip: Equatable {
        let clip: UInt32
        let mics: [UInt32]
        let micFaces: [UInt32]?
    }

    /// A clip the step framed with `speaker` (VR-64 (f)): its microphones and the face of each,
    /// given or the core's own match.
    struct SpeakerFraming: Equatable {
        let clip: UInt32
        let mics: [UInt32]
        let faces: [UInt32]
    }

    /// What the sheet reads for Speaker (VR-66 (c)): a refusal's sentence, or the subjects with
    /// their turns, the reference clip and the core's match on it.
    enum SpeakerReading {
        case refused(String)
        case ready(subjects: [UInt32: [String: Any]], reference: UInt32, match: SpeakerMatch?)
    }

    /// The tool's refusal with no speaker clip (VR-64 (e)).
    static let noSpeakerClip =
        "make_vertical_version found no full-frame movie clip playing beside two of the "
        + "microphones in mics, so nobody is framed by who is talking."

    /// The sheet's sentence with no speaker clip (VR-66 (c)).
    static let noSpeakerClipSheet =
        "No full-frame movie clip plays beside two of the ticked microphones, so nobody can be "
        + "framed by who is talking."

    /// VR-66 (b): each track, front to back, holding a clip `SpeakerSwitch.playsSound` takes
    /// whose media has no picture; its `clip` the earliest such clip (ties: the lower id).
    static func microphones(_ project: ReelProject) -> [Microphone] {
        let snapshot = project.snapshot
        return snapshot.tracks.reversed().compactMap { track in
            let sounding = snapshot.clips(onTrack: track.id).filter {
                SpeakerSwitch.playsSound($0, in: snapshot)
                    && snapshot.media(for: $0)?.hasVideo == false
            }
            guard let first = sounding.min(by: { ($0.start, $0.id) < ($1.start, $1.id) })
            else { return nil }
            return Microphone(track: track.id, name: track.name, clip: first.id)
        }
    }

    /// VR-64 (b): the present, cursor-free class-3 media pictures off the microphone tracks whose
    /// span overlaps a clip with audio on at least two of them, in id order; [] unless `follow`
    /// is `speaker`. Each one's `mics` are, per microphone in order, the media clip with audio on
    /// that microphone's track with the greatest overlap (ties: the earlier start, then the lower
    /// id); a track with none is left out with its `micFaces` entry. A `micFaces` that is not
    /// one per microphone is passed as given, for the core to refuse in its own sentence.
    static func speakerClips(
        _ project: ReelProject, settings: VerticalSettings, missing: Set<UInt32>
    ) -> [SpeakerClip] {
        guard settings.follow == .speaker else { return [] }
        let snapshot = project.snapshot
        let micTracks = settings.mics.map { snapshot.clip($0)?.track }
        let onMics = Set(micTracks.compactMap { $0 })
        let given = settings.micFaces
        let filters = given.map { $0.count == settings.mics.count } ?? false
        var out: [SpeakerClip] = []
        for id in mediaPictures(classify(project), in: snapshot) where !missing.contains(id) {
            guard let clip = snapshot.clip(id), snapshot.media(for: clip)?.cursor == nil,
                !onMics.contains(clip.track)
            else { continue }
            var mics: [UInt32] = []
            var faces: [UInt32] = []
            for (n, track) in micTracks.enumerated() {
                guard let track, let best = loudest(on: track, under: clip, in: snapshot)
                else { continue }
                mics.append(best)
                if filters, let given { faces.append(given[n]) }
            }
            guard mics.count >= 2 else { continue }
            out.append(SpeakerClip(clip: id, mics: mics, micFaces: filters ? faces : given))
        }
        return out
    }

    /// The media clip with audio on `track` that overlaps `clip` most (ties: the earlier start,
    /// then the lower id); nil when none overlaps it.
    private static func loudest(
        on track: UInt32, under clip: ClipSnapshot, in snapshot: ProjectSnapshot
    ) -> UInt32? {
        func overlap(_ other: ClipSnapshot) -> Ticks {
            max(0, min(other.end, clip.end) - max(other.start, clip.start))
        }
        let sounding = snapshot.clips(onTrack: track).filter { other in
            guard case .media = other.source, snapshot.media(for: other)?.hasAudio == true
            else { return false }
            return overlap(other) > 0
        }
        return sounding.min { a, b in
            (-overlap(a), a.start, a.id) < (-overlap(b), b.start, b.id)
        }?.id
    }

    /// VR-64 (d): each speaker clip's subjects with `turns`, read through `FramingSpeaker.turns`
    /// over its own microphones; a clip with no subjects is left as it is. Main thread (it reads
    /// the document); throws `FramingSpeaker.Refusal`.
    static func withTurns(
        _ subjects: [UInt32: [String: Any]], speaker: [SpeakerClip], document: ProjectDocument
    ) throws -> [UInt32: [String: Any]] {
        var out = subjects
        let snapshot = document.editedProject.snapshot
        for entry in speaker {
            guard var own = out[entry.clip], let clip = snapshot.clip(entry.clip) else { continue }
            own["turns"] = try FramingSpeaker.turns(
                document: document, clip: clip, mics: entry.mics)
            out[entry.clip] = own
        }
        return out
    }

    /// VR-66 (c): the sheet's reading for Speaker on `project` with the ticked microphones in
    /// `settings.mics` — the turns filled, then the core's match on the reference clip (the
    /// longest speaker clip, ties to the lower id) with its own microphones. Main thread.
    static func speakerReading(
        document: ProjectDocument, project: ReelProject, settings: VerticalSettings,
        subjects: [UInt32: [String: Any]], missing: Set<UInt32>
    ) -> SpeakerReading {
        let clips = speakerClips(project, settings: settings, missing: missing)
        let snapshot = project.snapshot
        let reference = clips.min { a, b in
            let (da, db) = (snapshot.clip(a.clip)?.duration ?? 0, snapshot.clip(b.clip)?.duration ?? 0)
            return (-da, a.clip) < (-db, b.clip)
        }
        guard let reference else { return .refused(noSpeakerClipSheet) }
        let filled: [UInt32: [String: Any]]
        do {
            filled = try withTurns(subjects, speaker: clips, document: document)
        } catch let refusal as FramingSpeaker.Refusal {
            return .refused(refusal.sentence)
        } catch {
            return .refused(error.localizedDescription)
        }
        let match = filled[reference.clip].flatMap {
            project.speakerMatch(clip: reference.clip, mics: reference.mics, subjects: $0)
        }
        return .ready(subjects: filled, reference: reference.clip, match: match)
    }
}
