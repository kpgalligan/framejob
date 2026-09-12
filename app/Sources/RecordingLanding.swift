// app/Sources/RecordingLanding.swift — where a finished recording goes
// (road map 3, phase R1b).
//
// A value type, `AudioNormalize`'s shape: a `RecordingResult` and a document
// in, an op list and the ids it will mint out, so the recorder panel and the
// `record_screen` tool provably land a recording the same way. **Nothing here
// commits.** The panel commits through `document.performGroupedEdit`, the
// tool through `AgentServer.performGroupedEdit`, and each door keeps its own
// posture on a refusal — a sheet, or an in-band error — which a document-side
// commit would collapse into the wrong one for the tool.
//
// The ops come back UNSCOPED. Inside an open nest the caller's door stamps the
// scope (`ProjectDocument.addressed`, `AgentServer+Scope.addressed`): the two
// `add_media` ops are document-level and travel unscoped, everything else
// carries the nest, and that is exactly what the trial below applies — so the
// commit runs the list the trial ran.
//
// The microphone half — the second clip's placement, the names its track and
// its undo step carry, and `untitled(around:)`'s microphone-only landing — is
// `RecordingLanding+Microphone.swift`, a pure move landed alone at the
// 400-line cap (road map 3, R2's toll); `addMedia`, `view` and `trimmed`
// widened from `private` to internal for it, because `private` does not
// cross a file.

import AppKit

struct RecordingLanding {
    /// The ops that land one recording, and the ids the core will mint for
    /// them — `next_id` read off a purely-applied result at each step, the
    /// documented contract (`core/src/edit.rs`: a new id is `next_id` from
    /// before the call). `clipId` is nil when nothing was placed
    /// (`place: false`); the two `mic…` ids are nil when the result carries
    /// no microphone file.
    struct Placement {
        let ops: [ReelOp]
        let mediaId: UInt32
        let clipId: UInt32?
        let micMediaId: UInt32?
        let micClipId: UInt32?
    }

    enum Target {
        case document(ProjectDocument)
        case newProject
    }

    /// The undo step's name, for both doors — the whole landing, picture
    /// and microphone in one list.
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
    /// `document` at its playhead, in the container it has open.
    ///
    /// The picture's media goes in first, applied purely against the
    /// DOCUMENT's handle (`add_media` is document-level, `ReelOp.documentLevelNames`)
    /// and its id read off the result; then, with `place`, its clip by the
    /// two-try track rule — the front track of the open container if the
    /// core accepts the clip there, else a new track in front of everything.
    /// The rule is `addGeneratedClip`'s (`EditorViewController+AddClips.swift`)
    /// but it cannot be that method: its probe runs against a project that
    /// does not hold the media yet, and `add_clip` naming an absent media is
    /// an `Err` — every recording would fall to the new-track branch, and the
    /// branch would then name the TRACK by the id `add_media` had consumed.
    /// `placeImageBackground` / `backgroundMedia(for:in:)` are the precedent:
    /// the probe runs over a project that already HOLDS the media.
    ///
    /// With a microphone file the second pair — its media, a new BACK track
    /// named "Microphone", its clip — is derived from the first pair's
    /// purely-applied result, never from one `next_id` read, because the
    /// first pair mints two or three ids and how many depends on which branch
    /// the track rule took. `place == false` lands the media (and the
    /// microphone's media) with no clip at all.
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
    /// (`tools/proof/recording_probe.py`, section 4, row 8). An earlier
    /// draft of this comment said the opposite, and it was never true.
    ///
    /// **One list, one limit.** The picture and the microphone are ONE
    /// grouped edit, so a microphone pair the core refuses takes the picture
    /// down with it. The case that reaches it: a document at `MAX_TRACKS`
    /// with an empty front track takes the picture alone (no track is
    /// added) and lands NEITHER once a microphone needs its own track. Kept
    /// on purpose — half a recording landed, with the voice missing and no
    /// undo step that says so, is worse than a refusal — and both doors
    /// name the FILE in the refusal, which is on disk whatever happened
    /// after it.
    static func placement(
        _ result: RecordingResult, in document: ProjectDocument, place: Bool
    ) throws -> Placement {
        assert(Thread.isMainThread)
        guard !document.isLiveEditing else {
            throw ReelCoreError(
                message: "A drag is in progress; the recording can be added when it ends.")
        }
        let scope = document.scope
        let playhead = document.playhead
        var trial = document.project
        var ops: [ReelOp] = []

        let mediaId = try addMedia(result.descriptor, to: &trial, ops: &ops)
        var clipId: UInt32?
        if place {
            clipId = try addClip(mediaId, at: playhead, scope: scope, to: &trial, ops: &ops)
        }
        var micMediaId: UInt32?
        var micClipId: UInt32?
        if let mic = result.micDescriptor {
            let id = try addMedia(mic, to: &trial, ops: &ops)
            micMediaId = id
            if place {
                micClipId = try addMicrophoneClip(
                    id, pictureAt: playhead, offset: result.micOffset, scope: scope,
                    to: &trial, ops: &ops)
            }
        }
        return Placement(
            ops: ops, mediaId: mediaId, clipId: clipId, micMediaId: micMediaId,
            micClipId: micClipId)
    }

    // MARK: - The steps, each applied purely and read back

    /// `add_media` applied purely; the id it minted, read off the result. A
    /// path already in the list is the documented IDENTITY (`Ok(None)`,
    /// `core/src/edit_track.rs`), not a failure, and then the id is the
    /// entry's, matched by the TRIMMED path because that is what the core
    /// stored — `backgroundMedia(for:in:)`'s rule. The op stays in the list
    /// either way: `applying(_ ops:)` runs every later op after an identity,
    /// so one shape serves both cases and the undo step is one.
    static func addMedia(
        _ descriptor: MediaDescriptor, to trial: inout ReelProject, ops: inout [ReelOp]
    ) throws -> UInt32 {
        let op = ReelOp.addMedia(descriptor: descriptor)
        ops.append(op)
        if let added = try trial.applying(op) {
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

    /// The two-try track rule over a `trial` that holds `media`. The front
    /// track of the open container first; a refusal there — the overlap rule
    /// is the only reason the core has — takes a new track in front of
    /// everything, whose id is `next_id` off the trial, and the clip's the
    /// `next_id` after that track is applied. `try?` on the first attempt
    /// collapses a throw and a nil into one answer on purpose: either way the
    /// front track will not take this clip.
    private static func addClip(
        _ media: UInt32, at: Ticks, scope: UInt32?, to trial: inout ReelProject,
        ops: inout [ReelOp]
    ) throws -> UInt32 {
        let container = try view(of: trial, scope: scope).snapshot
        if let front = container.tracks.last?.id {
            let op = ReelOp.addClip(track: front, media: media, at: at)
            if let placed = try? trial.applying(op.scoped(scope)) {
                let clip = trial.snapshot.nextId
                trial = placed
                ops.append(op)
                return clip
            }
        }
        // Index 0 is the BACK of the stack (§6), so the count is the front.
        let addTrack = ReelOp.addTrack(index: container.tracks.count)
        let track = trial.snapshot.nextId
        guard let withTrack = try trial.applying(addTrack.scoped(scope)) else {
            throw ReelCoreError(message: "A track for the recording could not be added.")
        }
        let clip = withTrack.snapshot.nextId
        let addClip = ReelOp.addClip(track: track, media: media, at: at)
        guard let placed = try withTrack.applying(addClip.scoped(scope)) else {
            throw ReelCoreError(message: "The recording could not be placed on a new track.")
        }
        trial = placed
        ops += [addTrack, addClip]
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
