// app/Sources/RecordingLanding.swift — where a finished recording goes
// (road map 3, phase R1b; a SEQUENCE of segments since R2b).
//
// A value type, `AudioNormalize`'s shape: a `RecordingResult` and a document
// in, an op list and the ids it will mint out, so the recorder panel and the
// `record_screen` tool provably land a recording the same way. **Nothing here
// commits.** The panel commits through `document.performGroupedEdit`, the
// tool through `AgentServer.performGroupedEdit`, and each door keeps its own
// posture on a refusal — a sheet, or an in-band error — which a document-side
// commit would collapse into the wrong one for the tool.
//
// A recording is a sequence of segments (road map 3, decision 6: a pause
// closes one file and a resume opens the next over the one stream), and the
// landing places them back to back — one clip per segment, each at the
// previous one's END as the core reports it — so a paused recording is `n`
// ordinary media files and `n` clips on ONE track, touching, and the model
// learns nothing. An unpaused recording is the one-segment case of the same
// list, byte for byte R1's.
//
// **Every clip is READ BACK after its apply**, never assumed (the R2
// review): the core snaps a start to the frame grid, and at an inexact
// canvas rate — decision 3's 24981/1000, a document opened from a
// recording — a clip's end is a sum of two grid points, which is NOT a grid
// point, so an `add_clip` at it can snap DOWN by up to half a frame into a
// one-tick overlap the rule accepts and a cross dissolve minted between two
// halves of one recording. `placeClip` reads the landed start and, when it is
// under the floor, places again a frame up; the rule is **touching, or a
// sub-frame gap at an inexact rate — never an overlap, never a transition**,
// and the gap is the documented limit of such a rate. A file the core would
// refuse outright — one whose length snaps to no frame at all — lands as
// MEDIA with a sentence in `Placement.notes`, rather than taking every other
// segment down with it.
//
// The ops come back UNSCOPED. Inside an open nest the caller's door stamps the
// scope (`ProjectDocument.addressed`, `AgentServer+Scope.addressed`): every
// `add_media` op is document-level and travels unscoped, everything else
// carries the nest, and that is exactly what the trial below applies — so the
// commit runs the list the trial ran.
//
// The microphone half — each segment's voice on ONE new back track, the
// floor rule that keeps two voices from overlapping, the names its track and
// its undo steps carry, and `untitled(around:)`'s remainder landing — is
// `RecordingLanding+Microphone.swift`, a pure move landed alone at the
// 400-line cap (road map 3, R2's toll) before it grew, and the placing of
// one clip on the grid — `placeBackToBack`, `placeClip`, `tooShortNote`,
// `mediaEntry`, `milliseconds` — is `RecordingLanding+Placing.swift`, the
// same toll paid again when the read-backs arrived. `addMedia`, `view`,
// `clip(_:in:scope:)` and `trimmed` are internal for them, because
// `private` does not cross a file. A VOICE-OVER's landing — every file on one
// new back Microphone track — is `RecordingLanding+VoiceOver.swift`. The same
// toll paid twice more at camera-recording CR3-0 moved `Placement` and
// `Landed` to `RecordingLanding+Placement.swift`, and `untitled(around:)`'s
// remainder and its undo steps' names to `RecordingLanding+Remainder.swift`.
// A camera beside the screen (spec §11 CAM-10) — its media, ONE front track
// named "Camera", each clip by its segment's offset and the corner rule — is
// `RecordingLanding+Camera.swift`, called between the pictures and the
// microphones.

import AppKit

struct RecordingLanding {
    enum Target {
        case document(ProjectDocument)
        case newProject
    }

    /// The undo step's name, for both doors — the whole landing, every
    /// picture and every microphone in one list.
    static let actionName = "Add Recording"

    // MARK: - Where

    /// The document a `.document(recipeKey:)` destination names, looked up
    /// among the open documents by `recipeKey` — minted by
    /// `RecipeSource.register()`, monotonic and never reused, so a document
    /// that closed mid-recording is a lookup that fails and not a dangling
    /// pointer or (the `ObjectIdentifier` trap `RelinkSheetController`
    /// records) the next document allocated at the same address. A miss, and
    /// `.newProject`, both answer `.newProject`. Main thread.
    static func resolve(_ destination: RecordingDestination) -> Target {
        assert(Thread.isMainThread)
        guard case .document(let key) = destination else { return .newProject }
        let open = NSDocumentController.shared.documents.compactMap { $0 as? ProjectDocument }
        guard let document = open.first(where: { $0.recipeKey == key }) else {
            return .newProject
        }
        return .document(document)
    }

    // MARK: - What

    /// PURE: the op list and the predicted ids for landing `result` in
    /// `document` at its playhead, in the container it has open — every
    /// segment, as ONE grouped edit.
    ///
    /// Each segment's picture media goes in first, in order, applied purely
    /// against the DOCUMENT's handle (`add_media` is document-level,
    /// `ReelOp.documentLevelNames`) and its id read off the result; then,
    /// with `place`, the pictures as a sequence on ONE track by the two-try
    /// track rule — all of them on the front track of the open container if
    /// the core accepts every one there, else all on a new track in front of
    /// everything (`addSequence`). The rule is `addGeneratedClip`'s
    /// (`EditorViewController+AddClips.swift`) but it cannot be that method:
    /// its probe runs against a project that does not hold the media yet,
    /// and `add_clip` naming an absent media is an `Err` — every recording
    /// would fall to the new-track branch, and the branch would then name
    /// the TRACK by the id `add_media` had consumed. `placeImageBackground`
    /// / `backgroundMedia(for:in:)` are the precedent: the probe runs over a
    /// project that already HOLDS the media.
    ///
    /// With microphone files the second half — each one's media, ONE new
    /// BACK track named "Microphone", each one's clip — is derived from the
    /// pictures' purely-applied result, never from one `next_id` read,
    /// because the pictures mint `n` or `n + 1` ids and which depends on the
    /// branch the track rule took. `place == false` lands every media (the
    /// microphones' included) with no clip at all.
    ///
    /// **A camera beside the screen** (spec §11 CAM-10) lands between the
    /// two: each segment's `(Camera).mov` as media, then — with `place` —
    /// ONE new FRONT track named "Camera" and each camera clip at its screen
    /// segment's start plus its `cameraOffset`, cornered (`addCameras`).
    /// The pictures → cameras → microphones order is the one grouped edit's.
    ///
    /// **A left-out segment's readable voice** (#181 item 2, spec §11
    /// recording) is a stretch of its own (`RecordingResult.stretches`): on
    /// the picture side a GAP of its slot's length (`pictureStretches`), so
    /// the pictures after it start at the slot's end, and on the microphone
    /// side a voice at offset 0 at the slot's start, by the same floor rule
    /// (`voices(of:)`); `split` reads the answers back per segment and per
    /// left-out segment. With no left-out voice the list is the segments.
    ///
    /// The playhead is nest-local while a nest is open, the ops are unscoped,
    /// and the trial stamps the document's scope on the container ops exactly
    /// as the commit will. Two refusals are thrown by name rather than
    /// answered with a list that would beep: a live gesture (the caller
    /// retries when it ends, rather than committing over the gesture's base
    /// handle) and anything the core refuses, with the core's own sentence.
    ///
    /// **The trial sees everything the commit will, the caps included.**
    /// Each scoped op is applied to the PARENT handle —
    /// `trial.applying(op.scoped(scope))` IS the scoped apply, not a view of
    /// it — so `check_caps` and `check_nesting`, which phase 9 runs once on
    /// the MERGED parent (`core/src/scope.rs`, `Project::finish`), refuse
    /// here with the core's own sentence exactly as they would at the
    /// commit: a document at `MAX_TRACKS` throws "too many tracks" before
    /// any list is answered, inside a nest or out of one
    /// (`tools/proof/recording_probe.py`, section 4, row 8).
    ///
    /// **One list, one limit.** The pictures and the microphones are ONE
    /// grouped edit, so a microphone pair the core refuses takes every
    /// picture down with it. The case that reaches it: a document at
    /// `MAX_TRACKS` with an empty front track takes the pictures alone (no
    /// track is added) and lands NOTHING once a microphone needs its own
    /// track. Kept on purpose — half a recording landed, with the voice
    /// missing and no undo step that says so, is worse than a refusal — and
    /// both doors name the FILES in the refusal, which are on disk whatever
    /// happened after them. What is NOT a refusal is a file the core cannot
    /// make a clip of at all: it lands as media, with a sentence in `notes`.
    static func placement(
        _ result: RecordingResult, in document: ProjectDocument, place: Bool
    ) throws -> Placement {
        assert(Thread.isMainThread)
        guard !document.isLiveEditing else {
            throw ReelCoreError(
                message: "A drag is in progress; the recording can be added when it ends.")
        }
        if result.isVoiceOver { return try voiceOverPlacement(result, in: document, place: place) }
        let scope = document.scope
        var trial = document.project
        var ops: [ReelOp] = []
        var notes: [String] = []

        var mediaIds: [UInt32] = []
        for segment in result.segments {
            mediaIds.append(try addMedia(segment.descriptor, to: &trial, ops: &ops))
        }
        var pictures: [Landed] = []
        if place {
            let stretches = try pictureStretches(
                of: result, mediaIds: mediaIds, in: trial, scope: scope)
            pictures = try addSequence(
                stretches, from: document.playhead, scope: scope, to: &trial, ops: &ops,
                notes: &notes)
        }
        let cameras = try addCameras(
            result, screenStarts: place ? segmentStarts(pictures.map { $0.at }, of: result) : nil,
            scope: scope, to: &trial, ops: &ops, notes: &notes)
        let microphones = try addMicrophones(
            voices(of: result), pictureStarts: place ? pictures.map { $0.at } : nil,
            scope: scope, to: &trial, ops: &ops, notes: &notes)
        let micMedia = split(microphones.media, of: result)
        let micClips = split(microphones.clips, of: result)
        return Placement(
            ops: ops, mediaIds: mediaIds,
            clipIds: place
                ? split(pictures.map { $0.clip?.id }, of: result).segments
                : mediaIds.map { _ in nil },
            micMediaIds: micMedia.segments, micClipIds: micClips.segments, notes: notes,
            leftOutMicMediaIds: micMedia.leftOut, leftOutMicClipIds: micClips.leftOut,
            cameraMediaIds: cameras.media, cameraClipIds: cameras.clips)
    }

    // MARK: - The steps, each applied purely and read back

    /// `add_media` applied purely; the id it minted, read off the result. A
    /// path already in the list is the documented IDENTITY
    /// (`core/src/edit_track.rs`), not a failure, and then the id is the
    /// entry's, matched by the TRIMMED path because that is what the core
    /// stored — `backgroundMedia(for:in:)`'s rule. The op stays in the list
    /// either way: `applying(_ ops:)` runs every later op after an identity,
    /// so one shape serves both cases and the undo step is one.
    static func addMedia(
        _ descriptor: MediaDescriptor, to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws -> UInt32 {
        let op = ReelOp.addMedia(descriptor: descriptor)
        ops.append(op)
        if let added = try trial.applying(op).project {
            trial = added
            guard let id = added.snapshot.media.last?.id else {
                throw ReelCoreError(message: "\(descriptor.path) was added and is not listed.")
            }
            return id
        }
        let path = trimmed(descriptor.path)
        guard let id = trial.snapshot.media.first(where: { $0.path == path })?.id else {
            throw ReelCoreError(message: "\(path) could not be added to the media list.")
        }
        return id
    }

    /// The two-try track rule over a SEQUENCE, for a `trial` that holds
    /// every `media`: all of them back to back on the front track of the
    /// open container, from `at`; if any one REFUSES there — the overlap
    /// rule is the only reason the core has — ALL of them on a new track in
    /// front of everything, from the same `at`. The sequence never splits: a
    /// recording whose first segment sits on one track and whose second on
    /// another would read as two recordings, so a refusal part-way discards
    /// the front track's half-placed trial whole (it was a copy) and starts
    /// the new track's from the trial that holds the media and no clip. The
    /// new track's id is `next_id` off the trial, and each clip's is
    /// `next_id` off the trial before its own `add_clip`.
    ///
    /// Only a REFUSAL (nil) falls through to the new track. An `Err` from
    /// the first attempt propagates: the caps are the same on either track,
    /// so a `try?` here — R1's shape — turned "too many clips" on a full
    /// document into a second attempt that added a track and then reported
    /// "too many tracks", the wrong cap, when the document was at both.
    /// `notes` takes the winning attempt's sentences (the same either way —
    /// a picture too short for a frame is too short on any track). The
    /// sequence is the whole stretch list, a left-out voice's gap included,
    /// so the rule sees every picture where it will land.
    private static func addSequence(
        _ stretches: [PictureStretch], from at: Ticks, scope: UInt32?,
        to trial: inout ReelProject, ops: inout [ReelOp], notes: inout [String]
    ) throws -> [Landed] {
        let container = try view(of: trial, scope: scope).snapshot
        if let front = container.tracks.last?.id {
            var attempt = trial
            var attemptOps: [ReelOp] = []
            var attemptNotes: [String] = []
            if let placed = try placeBackToBack(
                stretches, on: front, from: at, scope: scope, to: &attempt, ops: &attemptOps,
                notes: &attemptNotes)
            {
                trial = attempt
                ops += attemptOps
                notes += attemptNotes
                return placed
            }
        }
        // Index 0 is the BACK of the stack (§6), so the count is the front.
        let addTrack = ReelOp.addTrack(index: container.tracks.count)
        let track = trial.snapshot.nextId
        guard let withTrack = try trial.applying(addTrack.scoped(scope)).project else {
            throw ReelCoreError(message: "A track for the recording could not be added.")
        }
        var attempt = withTrack
        var attemptOps: [ReelOp] = [addTrack]
        var attemptNotes: [String] = []
        guard
            let placed = try placeBackToBack(
                stretches, on: track, from: at, scope: scope, to: &attempt, ops: &attemptOps,
                notes: &attemptNotes)
        else {
            throw ReelCoreError(message: "The recording could not be placed on a new track.")
        }
        trial = attempt
        ops += attemptOps
        notes += attemptNotes
        return placed
    }

    /// The clip `id` as the core reports it, read off the CONTAINER the ops
    /// are measured against — the nest's view while a scope is open, since
    /// a nested clip is not in the parent's `clips`. An id the trial does
    /// not list after its own `add_clip` accepted it is a throw, not a
    /// guess.
    static func clip(_ id: UInt32, in trial: ReelProject, scope: UInt32?) throws -> ClipSnapshot {
        let container = try view(of: trial, scope: scope).snapshot
        guard let clip = container.clips.first(where: { $0.id == id }) else {
            throw ReelCoreError(message: "Clip \(id) was placed and is not listed.")
        }
        return clip
    }

    /// The container the clip ops are measured against: the nest's view
    /// while a scope is open (its tracks and clips at the top level, its
    /// `next_id` the parent's), else the trial itself. A scope naming a nest
    /// the trial has not got is a refusal, not a fallback — `clampViewState`
    /// clears one before anything reads it, so this arm is a race with an
    /// undo and the caller should not land on the timeline by accident.
    static func view(of trial: ReelProject, scope: UInt32?) throws -> ReelProject {
        guard let nest = scope else { return trial }
        guard let view = trial.scoped(nest) else {
            throw ReelCoreError(message: "The open nest (id \(nest)) is no longer in the project.")
        }
        return view
    }

    static func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
