import AppKit

/// The agent's filler tool: the read half of a future Clip ▸ Remove Filler
/// Words… (road map "cut-by-transcript" CT-3), and today the agent's path to
/// the cut (spec §11 TR-4, TR-9).
///
/// `detect_fillers` is an APP-STATE tool, not an op — it changes nothing and
/// registers no undo step, as `detect_silence` does
/// (`AgentServer+Silence.swift`, whose posture this follows). The words are
/// a Swift cache (`cache/transcripts/`), so an agent that could only call
/// `ripple_delete_ranges` would have nothing to cut by; this answers the
/// ranges and `ripple_delete_ranges` makes the one undo step.
///
/// It stays on the MAIN thread, out of `AgentServer.offMainTools`, for
/// `detect_silence`'s reason: reading a few cached transcripts and one pass
/// of arithmetic waits on nothing and has no completion to deliver. It never
/// makes a network call: only a cached AssemblyAI transcript that asked for
/// filler words is read (TR-7).
extension AgentServer {

    /// `detect_fillers` — the read half of Clip ▸ Remove Filler Words… (CT-3);
    /// today the agent's path. Nothing is edited: feed `ranges` to
    /// `ripple_delete_ranges` to make the cut.
    func detectFillers(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try optionalClipsArg(a, "clips", document)
        let input = FillerDetector.read(from: document, clips: clips)
        let outcome = FillerDetector.detect(input)

        var result: [String: Any] = [
            "ok": true,
            "ranges": outcome.spans.map { [$0.start, $0.end] },
            "count": outcome.spans.count,
            "removes": outcome.removed,
            "scope": outcome.scope.rawValue,
            "clips": outcome.clips.map { Int($0) },
            "fillers": outcome.candidates.map { candidate -> [String: Any] in
                [
                    "clip": Int(candidate.clip), "words": candidate.words,
                    "range": [candidate.span.start, candidate.span.end],
                ]
            },
            "dropped": outcome.dropped.map { drop -> [String: Any] in
                ["clip": Int(drop.clip), "words": drop.words, "reason": Self.sentence(drop.reason)]
            },
            "needs_transcript": outcome.needsTranscript.map { Int($0) },
            "locked": outcome.locked.map { Int($0) },
        ]
        if clips != nil, !outcome.skipped.isEmpty {
            result["skipped"] = outcome.skipped.map { $0.description }
        }
        var notes: [String] = []
        if outcome.clips.isEmpty, outcome.needsTranscript.isEmpty, outcome.locked.isEmpty {
            notes.append("Nothing in scope plays speech from a media file, so nothing was read.")
        }
        if !outcome.needsTranscript.isEmpty {
            notes.append(
                "Media \(Self.fillerList(outcome.needsTranscript)) has no transcript made with "
                    + "filler words, so its fillers cannot be found: filler removal needs an "
                    + "AssemblyAI transcript (spec §11 TR-7). transcribe with engine "
                    + "\"assemblyai\" makes one; over a transcript made before filler words "
                    + "were asked for, add refresh: true (a paid upload).")
        }
        if !outcome.locked.isEmpty {
            notes.append(
                "Clip \(Self.fillerList(outcome.locked)) is on a locked track, which "
                    + "ripple_delete_ranges neither cuts nor moves, so its fillers were not read.")
        }
        if !notes.isEmpty { result["note"] = notes.joined(separator: " ") }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// A drop reason as the answer's sentence.
    private static func sentence(_ reason: FillerDetector.DropReason) -> String {
        switch reason {
        case .tooShort:
            return "too short to cut once its edges are on the 32 ms grid and the frame grid"
        case .overlapsWord(let clip, let text):
            return "it overlaps \"\(text)\" in clip \(clip)"
        case .nest(let clip):
            return "it crosses nest clip \(clip), which a cut must not split"
        case .transition:
            return "it crosses a transition"
        }
    }

    /// "3, 7, 9".
    private static func fillerList(_ ids: [UInt32]) -> String {
        ids.map { String($0) }.joined(separator: ", ")
    }
}
