// app/Sources/RecordingLanding+Placement.swift — the landing's answer
// (camera-recording CR3-0): `Placement`, the ops that land one recording
// and the ids the core will mint for them, and `Landed`, one segment's
// picture as the sequence placed it. A PURE MOVE out of
// `RecordingLanding.swift` at the 400-line cap, landed alone before camera
// + screen grows the landing, as `+Microphone` and `+Placing` were. Both
// types are still nested in `RecordingLanding`, so every reader spells them
// as before (`RecordingLanding.Placement`).

import AppKit

extension RecordingLanding {
    /// The ops that land one recording, and the ids the core will mint for
    /// them — `next_id` read off a purely-applied result at each step, the
    /// documented contract (`core/src/edit.rs`: a new id is `next_id` from
    /// before the call).
    ///
    /// **Every list has ONE entry per segment, in segment order** (the R2
    /// review's rule: the first shape aligned the two `mic…` lists with "the
    /// segments that have a microphone file", and a voice that mints no clip
    /// — one shorter than its head, one under a frame — then misaligned the
    /// media list with the clip list by an iterator nobody could see).
    /// `mediaIds` is never empty. `clipIds[k]` is nil where segment `k`'s
    /// picture minted no clip — every entry with `place: false`, or a
    /// picture too short for a frame, which `notes` says. `micMediaIds[k]`
    /// is nil for a segment with no microphone file; `micClipIds[k]` is nil
    /// where no microphone clip was minted — no file, `place: false`, or a
    /// voice wholly under the previous one, again in `notes`. The four
    /// singulars are the FIRST segment's, R1's fields kept so a reader
    /// written against one recording still compiles and still reads "the
    /// recording's" ids. `notes` carries a sentence per thing the landing
    /// could not place, each naming the file, for both doors to append to
    /// their note; empty when everything landed.
    ///
    /// Three shapes, then: every media with every clip (`place: true`),
    /// every media and no clip (`place: false`, and `remainderPlacement`
    /// with no clip 1 to follow), and every media with SOME clips — the
    /// third is what `notes` exists for, and each nil in the lists above has
    /// its sentence there.
    ///
    /// The two `leftOut…` lists have ONE entry per `RecordingResult.unreadable`
    /// segment (#181 item 2): the media and the clip its readable voice
    /// landed as, nil where it has no voice or minted no clip; empty for a
    /// result with nothing left out.
    ///
    /// The two `camera…` lists (spec §11 CAM-10) have ONE entry per segment
    /// as well: the media and the clip segment `k`'s `(Camera).mov` landed
    /// as, nil where it has no camera file, with `place: false`, or where it
    /// minted no clip (its sentence in `notes`). An empty list passed to the
    /// initialiser is stored as one nil per segment, so a landing with no
    /// camera need not spell them.
    struct Placement {
        let ops: [ReelOp]
        let mediaIds: [UInt32]
        let clipIds: [UInt32?]
        let micMediaIds: [UInt32?]
        let micClipIds: [UInt32?]
        let notes: [String]
        let leftOutMicMediaIds: [UInt32?]
        let leftOutMicClipIds: [UInt32?]
        let cameraMediaIds: [UInt32?]
        let cameraClipIds: [UInt32?]

        var mediaId: UInt32 { mediaIds[0] }
        var clipId: UInt32? { clipIds.first ?? nil }
        var micMediaId: UInt32? { micMediaIds.first ?? nil }
        var micClipId: UInt32? { micClipIds.first ?? nil }

        init(
            ops: [ReelOp], mediaIds: [UInt32], clipIds: [UInt32?], micMediaIds: [UInt32?],
            micClipIds: [UInt32?], notes: [String] = [], leftOutMicMediaIds: [UInt32?] = [],
            leftOutMicClipIds: [UInt32?] = [], cameraMediaIds: [UInt32?] = [],
            cameraClipIds: [UInt32?] = []
        ) {
            precondition(!mediaIds.isEmpty, "a Placement lands at least one segment's media")
            precondition(
                clipIds.count == mediaIds.count && micMediaIds.count == mediaIds.count
                    && micClipIds.count == mediaIds.count,
                "a Placement's four lists have one entry per segment")
            precondition(
                leftOutMicMediaIds.count == leftOutMicClipIds.count,
                "a Placement's two left-out lists have one entry per left-out segment")
            precondition(
                (cameraMediaIds.isEmpty || cameraMediaIds.count == mediaIds.count)
                    && (cameraClipIds.isEmpty || cameraClipIds.count == mediaIds.count),
                "a Placement's two camera lists are empty or have one entry per segment")
            self.ops = ops
            self.mediaIds = mediaIds
            self.clipIds = clipIds
            self.micMediaIds = micMediaIds
            self.micClipIds = micClipIds
            self.notes = notes
            self.leftOutMicMediaIds = leftOutMicMediaIds
            self.leftOutMicClipIds = leftOutMicClipIds
            let none: [UInt32?] = mediaIds.map { _ in nil }
            self.cameraMediaIds = cameraMediaIds.isEmpty ? none : cameraMediaIds
            self.cameraClipIds = cameraClipIds.isEmpty ? none : cameraClipIds
        }
    }

    /// One segment's picture as the sequence placed it: its clip as the core
    /// reports it, or nil for a picture too short for a frame — and `at`,
    /// where the segment BEGINS on the timeline either way, which is the
    /// clip's start or, with no clip, the point the sequence carried on
    /// from. The microphone rule reads `at`, so a voice whose picture minted
    /// no clip is still placed where its content began.
    struct Landed {
        let clip: ClipSnapshot?
        let at: Ticks
    }
}
