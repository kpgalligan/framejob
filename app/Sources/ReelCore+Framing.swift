import Foundation

// The framing queries' wrapper (spec §11 CJ-8 (l)): `ReelProject.speakerMatch` over
// `rc_project_speaker_match` (road map "creator-jobs" VR6b, spec §11 VR-65), the one caller.

/// The face-to-microphone match `reframe_clip {follow: speaker}` would make on a clip, as the
/// core answers it (`core/src/reframe_speaker_match.rs`): the faces found, numbered 1… left to
/// right, with each one's median centre x (0…1 across) and sample count; each microphone's
/// agreement with each face (`[mic][face]`); the face per microphone; and whether the match is
/// sure. With fewer faces than microphones every list is empty and `sure` false. Swift computes
/// none of it (VR-65).
struct SpeakerMatch: Equatable {
    struct Face: Equatable {
        let face: UInt32
        let x: Double
        let samples: Int
    }

    let faces: [Face]
    let agreement: [[Double]]
    let assignment: [UInt32]
    let sure: Bool
}

extension ReelProject {
    /// The match on `clip` with `mics` (clip ids, in order) over `subjects` as `reframe_clip`
    /// takes them, its `turns` filled; nil where the core answers NULL (an unknown or non-media
    /// clip, `mics` empty or over four, subjects it will not read) or the answer will not decode.
    func speakerMatch(clip: UInt32, mics: [UInt32], subjects: [String: Any]) -> SpeakerMatch? {
        let args: [String: Any] = ["mics": mics.map { Int($0) }, "subjects": subjects]
        guard JSONSerialization.isValidJSONObject(args),
            let data = try? JSONSerialization.data(withJSONObject: args),
            let text = String(data: data, encoding: .utf8),
            let object = CoreJSON.value(takeString(rc_project_speaker_match(ptr, clip, text)))
                as? [String: Any],
            let faces = object["faces"] as? [[String: Any]],
            let agreement = object["agreement"] as? [[NSNumber]],
            let assignment = object["assignment"] as? [NSNumber],
            let sure = object["sure"] as? Bool
        else { return nil }
        var decoded: [SpeakerMatch.Face] = []
        for face in faces {
            guard let number = face["face"] as? NSNumber, let x = face["x"] as? NSNumber,
                let samples = face["samples"] as? NSNumber
            else { return nil }
            decoded.append(
                SpeakerMatch.Face(face: number.uint32Value, x: x.doubleValue, samples: samples.intValue))
        }
        return SpeakerMatch(
            faces: decoded, agreement: agreement.map { $0.map(\.doubleValue) },
            assignment: assignment.map(\.uint32Value), sure: sure)
    }
}
