import Foundation

/// `reframe_clip {follow: speaker}`'s turns (road map "creator-jobs" VR6a,
/// spec §11 VR-60 (c)): who speaks when over the framed clip's span, read
/// through Switch by Speaker's own reader and rules so the framing and the
/// switch agree. `SpeakerSwitch.read` over the `mics` clips, each its track's
/// speaker with no angle and no wide, the range the clip's span and the
/// switch's default settings; `SpeakerSwitch.turns` on them; each turn's
/// track named back as its microphone's clip id.
///
/// `read`'s problems (still being analysed, no speech detection) and SW-24's
/// no-speech sentence refuse, in SW-24's words, as a `Refusal` carrying the
/// bare sentence: `reframe_clip` prefixes it "reframe_clip was refused: ",
/// `make_vertical_version` "make_vertical_version was refused: " and Make
/// Vertical's sheet shows it as it is (road map creator-jobs VR6b, spec §11
/// VR-64 (d), VR-66 (c)). A microphone `read` drops — its sound off — gets
/// no turn and no refusal here: the core names it (VR-60 (d)). Main thread
/// (it reads the document); names no `rc_*`.
enum FramingSpeaker {
    /// Why nobody's turns could be read: SW-24's sentence, with no prefix.
    struct Refusal: Error {
        let sentence: String
    }

    /// `[{from, to, mic}]` in the open container's timeline ticks, `mic` a clip
    /// id of `mics`.
    static func turns(document: ProjectDocument, clip: ClipSnapshot, mics: [UInt32]) throws
        -> [[String: Any]]
    {
        let snapshot = document.editedProject.snapshot
        var clipOf: [UInt32: UInt32] = [:]
        var speakers: [SpeakerSwitch.Speaker] = []
        for id in mics {
            guard let mic = snapshot.clip(id), clipOf[mic.track] == nil else { continue }
            clipOf[mic.track] = id
            speakers.append(SpeakerSwitch.Speaker(mic: mic.track, angle: nil))
        }
        guard
            let input = SpeakerSwitch.read(
                from: document, clips: mics,
                pairing: SpeakerSwitch.Pairing(speakers: speakers, wide: nil),
                range: (clip.start, clip.end), settings: SpeakerSwitch.Settings())
        else {
            throw Refusal(
                sentence: "the project's plan could not be read, so nobody's turns could be.")
        }
        let problems = input.problems + SpeakerSwitch.silentMicrophones(input)
        guard problems.isEmpty else {
            throw Refusal(sentence: problems.joined(separator: " "))
        }
        return SpeakerSwitch.turns(input).compactMap { turn in
            clipOf[turn.mic].map { ["from": turn.from, "to": turn.to, "mic": Int($0)] }
        }
    }
}
