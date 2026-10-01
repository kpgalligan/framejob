// app/Sources/RecordingLanding+LeftOut.swift — a left-out segment's readable
// microphone in the landing (#181 item 2, spec §11 recording: "A left-out
// segment's readable microphone lands without its picture").
//
// A segment the walker left out (`RecordingResult.unreadable`) whose
// microphone file read carries it as `micDescriptor`, with `position` its
// place among the landed segments; `RecordingResult.stretches` lists the
// landed segments and those voices in recording order. Here is what the
// landing makes of that list: the PICTURE side as `PictureStretch`es — a
// landed segment's media, or a GAP the length of the voice snapped down to
// the frame, so the picture track stays empty there and the next picture
// starts at the slot's end — and the MICROPHONE side as `Voice`s, one per
// stretch, a voice-only one at offset 0 because no picture is there to align
// it to. `split` maps a per-stretch answer back to the `Placement`'s
// per-segment lists and its per-left-out-segment lists; `remainderStretches`
// is `remainderPlacement`'s clip-1 branch over the same list. With no
// left-out voice every stretch is a segment and every list is the one it was.
//
// In its own file because `RecordingLanding+Microphone.swift` stood at 381
// lines against the 400-line cap for a new file; `view` and `trimmed` are
// the base file's, internal for it.

import AppKit

extension RecordingLanding {
    /// One stretch of the picture track: a landed segment's media, placed
    /// by `placeBackToBack`, or a gap of `Ticks` it leaves empty.
    enum PictureStretch {
        case picture(UInt32)
        case gap(Ticks)
    }

    /// One stretch's microphone: its file when one landed (nil when none),
    /// and the offset its clip is placed by — a segment's measured
    /// `micOffset`, or 0 for a left-out voice.
    struct Voice {
        let descriptor: MediaDescriptor?
        let offset: Ticks
    }

    /// One `Voice` per stretch of `result`, in order.
    static func voices(of result: RecordingResult) -> [Voice] {
        result.stretches.map { stretch in
            switch stretch {
            case .segment(let k):
                return Voice(
                    descriptor: result.segments[k].micDescriptor,
                    offset: result.segments[k].micOffset)
            case .voiceOnly(let i):
                return Voice(descriptor: result.unreadable[i].micDescriptor, offset: 0)
            }
        }
    }

    /// One `PictureStretch` per stretch of `result`: segment `k`'s picture
    /// as `mediaIds[k]` (the ids its `add_media` answered, one per segment),
    /// and a left-out voice as a gap of `slotLength`, measured against the
    /// container `trial` and `scope` name.
    static func pictureStretches(
        of result: RecordingResult, mediaIds: [UInt32], in trial: ReelProject, scope: UInt32?
    ) throws -> [PictureStretch] {
        try result.stretches.map { stretch in
            switch stretch {
            case .segment(let k):
                return .picture(mediaIds[k])
            case .voiceOnly(let i):
                guard let voice = result.unreadable[i].micDescriptor else { return .gap(0) }
                return .gap(try slotLength(voice, in: trial, scope: scope))
            }
        }
    }

    /// The slot a voice-only stretch takes on the picture track: the file's
    /// length snapped DOWN to the container's frame — the length its clip
    /// takes (`SilenceDetector.snapDownToFrame`, the one Swift spelling of
    /// that snap, `rc_time_snap_to_frame` over the FFI) — and 0 for a file
    /// under a frame, which mints no clip and so takes no time.
    static func slotLength(_ voice: MediaDescriptor, in trial: ReelProject, scope: UInt32?) throws
        -> Ticks
    {
        let fps = try view(of: trial, scope: scope).snapshot.canvas.fps
        return max(0, SilenceDetector.snapDownToFrame(voice.duration, fps: fps))
    }

    /// A per-stretch list, `result.stretches`' order, split into one entry
    /// per landed segment and one per left-out segment (nil for a left-out
    /// segment with no voice, which has no stretch).
    static func split(_ list: [UInt32?], of result: RecordingResult)
        -> (segments: [UInt32?], leftOut: [UInt32?])
    {
        var segments: [UInt32?] = result.segments.map { _ in nil }
        var leftOut: [UInt32?] = result.unreadable.map { _ in nil }
        for (stretch, id) in zip(result.stretches, list) {
            switch stretch {
            case .segment(let k): segments[k] = id
            case .voiceOnly(let i): leftOut[i] = id
            }
        }
        return (segments, leftOut)
    }

    /// `remainderPlacement`'s clip-1 branch over the stretches: a left-out
    /// voice BEFORE clip 1 — the document at 0 — gets no start (media only)
    /// and `leadingVoiceNote`; clip 1 is its own stretch; everything after
    /// it goes on clip 1's track from clip 1's end by `placeBackToBack`, a
    /// voice's gap included, a refusal thrown by name (no two-try rule on a
    /// fresh document's one track). Answers one start and one picture clip
    /// id per stretch, for `addMicrophones` and `split`.
    static func remainderStretches(
        _ result: RecordingResult, after first: ClipSnapshot, mediaIds: [UInt32],
        firstPath: String, scope: UInt32?, to trial: inout ReelProject, ops: inout [ReelOp],
        notes: inout [String]
    ) throws -> (starts: [Ticks?], clips: [UInt32?]) {
        let stretches = result.stretches
        let lead = stretches.firstIndex(of: .segment(0)) ?? 0
        var starts: [Ticks?] = stretches.map { _ in nil }
        var clips: [UInt32?] = stretches.map { _ in nil }
        for case .voiceOnly(let i) in stretches[..<lead] {
            if let mic = result.unreadable[i].micDescriptor {
                notes.append(leadingVoiceNote(mic.path, before: firstPath))
            }
        }
        starts[lead] = first.start
        clips[lead] = first.id
        let rest = Array(
            try pictureStretches(of: result, mediaIds: mediaIds, in: trial, scope: scope)[
                (lead + 1)...])
        guard !rest.isEmpty else { return (starts, clips) }
        guard
            let placed = try placeBackToBack(
                rest, on: first.track, from: first.end, scope: scope, to: &trial, ops: &ops,
                notes: &notes)
        else {
            throw ReelCoreError(
                message: "The recording's later segments could not be placed after its first.")
        }
        for (k, landed) in placed.enumerated() {
            starts[lead + 1 + k] = landed.at
            clips[lead + 1 + k] = landed.clip?.id
        }
        return (starts, clips)
    }

    /// The sentence for a left-out voice recorded BEFORE a new project's
    /// first segment, which is the document at 0: there is no timeline
    /// before it, so the voice lands as media only.
    static func leadingVoiceNote(_ path: String, before first: String) -> String {
        "\(path) was added to the media list without a clip: it was recorded before \(first), "
            + "which starts the new project at 0."
    }
}
