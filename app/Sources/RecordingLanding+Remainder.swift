// app/Sources/RecordingLanding+Remainder.swift — `untitled(around:)`'s
// remainder landing (camera-recording CR3-0): `remainderPlacement`
// (everything a fresh untitled document does not already hold), the two
// names its undo step can take (`microphoneActionName`,
// `segmentsActionName`), `remainderActionName(for:)`, the rule choosing
// between them, and `unplacedNote`, the sentence for a file with no first
// clip to follow. A PURE MOVE out of `RecordingLanding+Microphone.swift` at
// the 400-line cap, landed alone before camera + screen grows it;
// `unplacedNote` stays `private`, because nothing else calls it. The voices
// it lands are `+Microphone`'s `addMicrophones`, its stretches `+LeftOut`'s
// `remainderStretches`.

import AppKit

extension RecordingLanding {
    /// The undo step's name for `ProjectDocument.untitled(around:)`'s
    /// remainder edit when the remainder is a microphone ALONE — one segment
    /// with a voice. There the picture is the document — undoing the step
    /// removes the voice and keeps the picture — so a step called "Add
    /// Recording" would promise to take back what it cannot, and the Edit
    /// menu would read "Undo Add Recording" over a project the undo leaves
    /// with the recording in it. The `.document` landing keeps `actionName`:
    /// its one step really does add and remove both.
    static let microphoneActionName = "Add Microphone"

    /// The same step's name when the remainder holds more than a voice — a
    /// paused recording's later segments, with or without microphones.
    /// "Segments" and not "Recording" for the reason above: the FIRST
    /// segment is the document and stays under the undo; what the step takes
    /// back is the rest.
    static let segmentsActionName = "Add Recording Segments"

    /// Which of the two names `untitled(around:)`'s remainder edit takes:
    /// "Add Microphone" for one segment with any voice — its own (R1's
    /// landing, R1's name) or a left-out segment's — and "Add Recording
    /// Segments" otherwise. A one-segment recording with no voice has no
    /// remainder and no step, and the answer for it is never read.
    static func remainderActionName(for result: RecordingResult) -> String {
        if result.segments.count == 1,
            result.segments[0].micDescriptor != nil
                || result.unreadable.contains(where: { $0.micDescriptor != nil })
        {
            return microphoneActionName
        }
        return segmentsActionName
    }

    /// Everything a fresh untitled document does NOT already hold, for
    /// `ProjectDocument.untitled(around:)`, whose `makeProject` placed the
    /// FIRST segment's picture at 0 on track 1 before anything else could
    /// run: segments 2…n's media and their pictures on that same track from
    /// clip 1's end, then every segment's microphone by the floor rule. nil
    /// when there is nothing to add — one segment, no microphone.
    /// `placement(_:in:place:)` cannot serve it — the first picture's
    /// `add_media` would be the documented identity and its `add_clip` at 0
    /// would meet its own clip on the front track, refuse, and put the whole
    /// sequence a SECOND time on a new track. The answer reads as a whole
    /// landing: `mediaIds[0]` and `clipIds[0]` name the picture the document
    /// holds.
    ///
    /// Clip 1 is the FIRST clip whose source is the first segment's media,
    /// and the later pictures go on ITS track from ITS end — read off the
    /// document, not assumed to be track 1 at 0. That is exact for the one
    /// caller: `makeProject` places exactly one clip. A document holding the
    /// same media in several clips has no single answer here, and this
    /// method does not pretend to one — it is `untitled(around:)`'s, not a
    /// general "add the rest of a recording to a document" op. The later
    /// pictures take no two-try rule: a refusal on a fresh document's one
    /// track is not a track choice to fall back from but something wrong
    /// with a file, and is thrown by name.
    ///
    /// **Without clip 1** — `makeProject` tolerates a first picture the core
    /// refuses (a media with no duration) and opens the file in the Media
    /// tab — nothing on the timeline says where the recording is, so the
    /// remainder lands as MEDIA ONLY, `place: false`'s shape, with a
    /// sentence per file in `notes`. The first shape here placed every
    /// voice against a picture at 0, R1's one-segment fallback, which with
    /// several voices stacked each one under the last (the floor rule
    /// trimming a whole voice off) — a wrong sound where a Media-tab list
    /// is at least an honest one.
    ///
    /// **A left-out segment's readable voice** (#181 item 2) is a stretch:
    /// after clip 1 a gap the later pictures skip and a voice at its start;
    /// BEFORE clip 1, which is the document at 0, media only with
    /// `leadingVoiceNote`; without clip 1, media only with `unplacedNote`.
    static func remainderPlacement(
        _ result: RecordingResult, in document: ProjectDocument
    ) throws -> Placement? {
        assert(Thread.isMainThread)
        let hasMicrophone = result.segments.contains { $0.micDescriptor != nil }
        let hasLeftOutVoice = result.unreadable.contains { $0.micDescriptor != nil }
        guard result.segments.count > 1 || hasMicrophone || hasLeftOutVoice else { return nil }
        let path = trimmed(result.descriptor.path)
        let snapshot = document.editedProject.snapshot
        guard let mediaId = snapshot.media.first(where: { $0.path == path })?.id else {
            throw ReelCoreError(message: "\(path) is not in the document's media list.")
        }
        let first = snapshot.clips.first { clip in
            if case .media(let id, _, _) = clip.source { return id == mediaId }
            return false
        }
        let scope = document.scope
        var trial = document.project
        var ops: [ReelOp] = []
        var notes: [String] = []
        var mediaIds = [mediaId]
        for segment in result.segments.dropFirst() {
            mediaIds.append(try addMedia(segment.descriptor, to: &trial, ops: &ops))
        }
        var starts: [Ticks?]?
        var clips: [UInt32?] = result.stretches.map { _ in nil }
        if let first = first {
            let placed = try remainderStretches(
                result, after: first, mediaIds: mediaIds, firstPath: path, scope: scope,
                to: &trial, ops: &ops, notes: &notes)
            starts = placed.starts
            clips = placed.clips
        } else {
            for segment in result.segments.dropFirst() {
                notes.append(unplacedNote(segment.descriptor.path, behind: path))
            }
            for segment in result.segments {
                if let mic = segment.micDescriptor { notes.append(unplacedNote(mic.path, behind: path)) }
            }
            for left in result.unreadable {
                if let mic = left.micDescriptor { notes.append(unplacedNote(mic.path, behind: path)) }
            }
        }
        let microphones = try addMicrophones(
            voices(of: result), pictureStarts: starts,
            scope: scope, to: &trial, ops: &ops, notes: &notes)
        let micMedia = split(microphones.media, of: result)
        let micClips = split(microphones.clips, of: result)
        return Placement(
            ops: ops, mediaIds: mediaIds, clipIds: split(clips, of: result).segments,
            micMediaIds: micMedia.segments, micClipIds: micClips.segments, notes: notes,
            leftOutMicMediaIds: micMedia.leftOut, leftOutMicClipIds: micClips.leftOut)
    }

    /// The sentence for a file `remainderPlacement` lands as media because
    /// the first segment's picture has no clip to follow.
    private static func unplacedNote(_ path: String, behind first: String) -> String {
        "\(path) was added to the media list without a clip: \(first) has no clip on the "
            + "timeline for it to follow."
    }
}
