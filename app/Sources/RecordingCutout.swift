import AppKit

/// "Remove the camera's background when it lands" (road map "creator-jobs" CO8, spec §11
/// CO-81): Remove Background run over a finished recording's CAMERA clips as a follow-up to the
/// landing — never part of it — as its own undo step, "Remove Background", in AU-68's pattern
/// with no wait: the masks are wanted by the edit itself (`ensureMasks`, after every edit), so
/// nothing need be measured first. Both doors call `apply` right after the landing's commit and
/// before Enhance Voice and the polish (CU-101 (a)): the panel's two branches
/// (`RecorderPanelController+Landing.swift`) and the tool's `landAndEnhance`. On-device, so
/// never keyed (CJ-3). Names no `rc_*`; main thread.
enum RecordingCutout {
    /// The undo step's name, Clip ▸ Remove Background's.
    static let actionName = "Remove Background"
    /// The tool's `camera_cutout_error` when no camera clip took the cutout.
    static let noCameraSentence =
        "No camera clip landed on the timeline, so Remove Background did not run."

    /// Every segment's camera file, in segment order; empty paths dropped, each path once. Pure.
    static func cameraPaths(of result: RecordingResult) -> [String] {
        var seen: Set<String> = []
        return result.segments.compactMap { $0.cameraDescriptor?.path }
            .map(RecordingLanding.trimmed)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Every clip of the open container whose media is one of `paths`, that can be cut out
    /// (`CutoutStatus.canCutOut`) and has no cutout yet, in id order. Main.
    static func cameraClips(_ paths: [String], in document: ProjectDocument) -> [UInt32] {
        let wanted = Set(paths)
        guard !wanted.isEmpty else { return [] }
        let snapshot = document.editedProject.snapshot
        return snapshot.clips.filter { clip in
            guard let media = snapshot.media(for: clip), wanted.contains(media.path) else {
                return false
            }
            return CutoutStatus.canCutOut(clip, in: snapshot) && clip.video?.cutout == nil
        }.map(\.id).sorted()
    }

    /// One base `set_video {cutout}` per clip, the whole default cutout, as Clip ▸ Remove
    /// Background writes. Pure over the ids.
    static func ops(_ clips: [UInt32], in document: ProjectDocument) -> [ReelOp] {
        clips.map { .setVideo(clips: [$0], patch: VideoPatch(cutout: .some(CutoutProps()))) }
    }

    /// When the recording's choice asks for it, its camera clips cut out as ONE grouped step
    /// "Remove Background" (`performGroupedEdit`: a landing is not an AppKit event). Answers the
    /// clips the step was asked for, empty when the choice did not ask or no camera clip
    /// qualifies (the panel is then quiet; the tool answers `noCameraSentence`). Main.
    @discardableResult static func apply(_ result: RecordingResult, in document: ProjectDocument)
        -> [UInt32]
    {
        assert(Thread.isMainThread)
        guard result.choice.cameraCutout else { return [] }
        let clips = cameraClips(cameraPaths(of: result), in: document)
        guard !clips.isEmpty else { return [] }
        document.performGroupedEdit(actionName, ops(clips, in: document))
        return clips
    }
}
