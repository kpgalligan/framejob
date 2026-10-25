import Foundation

/// What a canvas gesture edits (spec §11 CI-13): the clip's BASE props, or
/// the selected action's END state — the same choice the inspector's fields
/// make (CI-2), so a drag, a nudge and a typed value all write one place.
///
/// It reaches the canvas as a value on two channels: the refresh that already
/// follows a selection (`EditorViewController.refreshCanvas`) and the
/// playhead's own path (`canvasPlayheadMoved`, since the entry rule selects
/// an action without a refresh). A gesture captures it at mouse-down as
/// `PreviewCanvasView.gestureTarget` and writes through that for every tick,
/// and the sessions in `CanvasSessions.swift` ask it for their ops rather
/// than naming `set_video` themselves. A multi-selection is always `.base`:
/// no action is selected then (CI-1).
///
/// **The box on screen is still the frame at the PLAYHEAD.** A gesture
/// STARTS from `start(of:in:)` — the end state, for the selected action's
/// clip — and moves it by the pointer's travel: the inspector's "fields show
/// the value they write", carried to the handles.
struct CanvasEditTarget: Equatable {
    struct Selected: Equatable {
        let clip: UInt32
        let action: UInt32
        /// The action's end in CLIP time (`ActionSnapshot.endTime`).
        let endTime: Ticks
    }

    /// What a gesture starts from: the end state for `selected.clip`, the
    /// base for any other clip. `text` is carried because a text clip's
    /// wrap-width drag reads it (`PreviewCanvasView.beginScale`).
    struct Start {
        let video: VideoProps
        let text: TextProps?
    }

    /// nil: base props.
    let selected: Selected?

    static let base = CanvasEditTarget(selected: nil)

    /// The document's mode: the selected action of `singleSelectedClip`,
    /// else `.base`.
    static func current(_ document: ProjectDocument) -> CanvasEditTarget {
        guard let clip = document.singleSelectedClip,
              let action = document.selectedActionSnapshot
        else { return .base }
        return CanvasEditTarget(
            selected: Selected(clip: clip.id, action: action.id, endTime: action.endTime))
    }

    /// The action this target writes on `clip`, nil when `clip` is written
    /// at its base.
    private func action(on clip: UInt32) -> UInt32? {
        guard let selected, selected.clip == clip else { return nil }
        return selected.action
    }

    /// `set_action_end` for the selected action's clip, `set_video` for any
    /// other. The typed builder lifts a `.some(nil)` into `off` (CI-14).
    func op(video patch: VideoPatch, clip: UInt32) -> ReelOp {
        guard let action = action(on: clip) else { return .setVideo(clips: [clip], patch: patch) }
        return .setActionEnd(clip: clip, action: action, patch: ActionPatch(video: patch))
    }

    /// The same rule for a text clip's wrap width.
    func op(text patch: TextPatch, clip: UInt32) -> ReelOp {
        guard let action = action(on: clip) else { return .setText(clips: [clip], patch: patch) }
        return .setActionEnd(clip: clip, action: action, patch: ActionPatch(text: patch))
    }

    /// `clip_state` at `clip.start + endTime` decoded through
    /// `InspectorBinding.decode` — the inspector's own read of an END state,
    /// video and text from ONE call — for `selected.clip`; the clip's base
    /// props otherwise. A group the core does not answer falls back to base.
    func start(of clip: ClipSnapshot, in project: ReelProject?) -> Start {
        guard let selected, selected.clip == clip.id,
              let raw = project?.clipState(clip.id, at: clip.start + selected.endTime)
        else { return Start(video: clip.videoProps, text: clip.text) }
        return Start(
            video: InspectorBinding.decode(VideoProps.self, raw["video"]) ?? clip.videoProps,
            text: InspectorBinding.decode(TextProps.self, raw["text"]) ?? clip.text)
    }

    /// The target a SCALE on `clip` starts from and writes: `.base` for a
    /// shape, whose scale is its box — `set_shape` has no action form, and
    /// the `set_video` that pins the pivot must land beside it on the same
    /// state (CI-13) — and `self` for anything else.
    func forScale(of clip: ClipSnapshot) -> CanvasEditTarget {
        if case .shape = clip.source { return .base }
        return self
    }
}

extension VideoProps {
    /// These props with the crop zeroed and every other field kept — the
    /// rectangle the crop is taken out of (`CanvasLayerBox.uncroppedRect`,
    /// a session's start rect).
    var uncropped: VideoProps {
        var next = self
        next.crop = .zero
        return next
    }
}
