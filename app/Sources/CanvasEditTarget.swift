import Foundation

/// What a canvas gesture edits (spec §11 CI-13): the clip's BASE props, or
/// the selected action's END state — the same choice the inspector's fields
/// make (CI-2), so a drag, a nudge and a typed value all write one place.
/// The one exception is a clip's first-frame CUT (CI-17): a one-frame layout
/// action at clip time 0 holds the placement for every frame after the
/// first, so with no action selected a gesture goes to the cut (`holding`;
/// for a multi-selection each written clip's cut, in `held`, spec §11 #529),
/// and a gesture on a cut writes the base as well (`ops(video:clip:)`). A
/// typed value keeps the cut and the base together the same way
/// (`InspectorBinding.keepingCuts`, #530). Past any other finished action
/// whose end holds a key the gesture writes, a single clip's gesture
/// refuses, naming that action (CI-19): `heldRefusal`.
///
/// It reaches the canvas as a value on two channels: the refresh that already
/// follows a selection (`EditorViewController.refreshCanvas`) and the
/// playhead's own path (`canvasPlayheadMoved`, since the entry rule selects
/// an action without a refresh). A gesture captures it at mouse-down as
/// `PreviewCanvasView.gestureTarget` and writes through that for every tick,
/// and the sessions in `CanvasSessions.swift` ask it for their ops rather
/// than naming `set_video` themselves. A multi-selection has no action
/// selected (CI-1), so it writes the base but for its clips' cuts (`held`).
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
        /// The action is the clip's first-frame cut (`isCut`, CI-17).
        let cut: Bool
    }

    /// The keys a gesture writes, which `holding` asks a cut about: x, y · x, y,
    /// scale and text.width · rotation · crop. `width` is a text clip's side
    /// handle, which writes only `text.width`; CI-19 asks it (`heldKeys`), and
    /// `holding` never does.
    enum Gesture { case move, scale, width, rotate, crop }

    /// What a gesture starts from: the end state for `selected.clip`, the
    /// base for any other clip. `text` is carried because a text clip's
    /// wrap-width drag reads it (`PreviewCanvasView.beginScale`).
    struct Start {
        let video: VideoProps
        let text: TextProps?
    }

    /// nil: base props.
    let selected: Selected?
    /// #529: a multi-selection's clips written on their first-frame cut and their base, by clip id.
    /// Always empty for a single clip and for `current(_:)`.
    var held: [UInt32: Selected] = [:]

    static let base = CanvasEditTarget(selected: nil)

    /// The document's mode: the selected action of `singleSelectedClip`,
    /// else `.base`.
    static func current(_ document: ProjectDocument) -> CanvasEditTarget {
        guard let clip = document.singleSelectedClip,
              let action = document.selectedActionSnapshot
        else { return .base }
        let frame = document.editedProject.snapshot.canvas.fps.frameDuration
        return CanvasEditTarget(
            selected: Selected(
                clip: clip.id, action: action.id, endTime: action.endTime,
                cut: isCut(action, frame: frame)))
    }

    /// A first-frame cut (CO-61, CO-80 (b)): a layout action at clip time 0,
    /// at most one canvas frame long. Any longer and it is a move a person
    /// can see, which keeps CI-13's base.
    static func isCut(_ action: ActionSnapshot, frame: Ticks) -> Bool {
        action.start == 0 && action.duration <= frame && VerticalVersion.isLayoutAction(action)
    }

    /// The target a `gesture` on `clip` takes with no action selected: its
    /// first-frame cut when the cut's end holds a key the gesture writes,
    /// `self` otherwise (CI-17). A rotate stays on the base, because a cut
    /// holds no `rotation`, and the base shows it on every frame.
    func holding(_ gesture: Gesture, clip: ClipSnapshot, frame: Ticks) -> CanvasEditTarget {
        guard selected == nil,
              let cut = clip.actions.first(where: { Self.isCut($0, frame: frame) }),
              Self.holds(cut.end, gesture)
        else { return self }
        return CanvasEditTarget(
            selected: Selected(clip: clip.id, action: cut.id, endTime: cut.endTime, cut: true))
    }

    /// `holding(_:clip:frame:)` for each clip of a multi-selection: `held` names every clip whose cut
    /// holds a key `gesture` writes (`holds`). With `selected` non-nil, answers `self`.
    func holding(_ gesture: Gesture, clips: [ClipSnapshot], frame: Ticks) -> CanvasEditTarget {
        guard selected == nil else { return self }
        var next = self
        for clip in clips {
            if let cut = holding(gesture, clip: clip, frame: frame).selected { next.held[clip.id] = cut }
        }
        return next
    }

    /// Whether an end patch names any key `gesture` writes.
    private static func holds(_ end: ActionPatch, _ gesture: Gesture) -> Bool {
        let video = end.video
        switch gesture {
        case .move:
            return video?.x != nil || video?.y != nil
        case .scale:
            return video?.x != nil || video?.y != nil || video?.scale != nil
                || end.text?.width != nil
        case .width:
            return end.text?.width != nil
        case .rotate:
            return video?.rotation != nil
        case .crop:
            return video?.crop != nil
        }
    }

    /// What this target writes on `clip`: `selected` for its clip, else the
    /// clip's entry in `held`; nil when `clip` is written at its base.
    private func written(_ clip: UInt32) -> Selected? {
        if let selected, selected.clip == clip { return selected }
        return held[clip]
    }

    /// The action this target writes on `clip`, nil when `clip` is written
    /// at its base.
    private func action(on clip: UInt32) -> UInt32? {
        written(clip)?.action
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

    /// What a gesture sends: `op(video:clip:)`, and on a cut the same patch
    /// to the base, so frame 0 and the rest stay together (CI-17). One list,
    /// so one undo step.
    func ops(video patch: VideoPatch, clip: UInt32) -> [ReelOp] {
        let edit = op(video: patch, clip: clip)
        guard onCut(clip) else { return [edit] }
        return [edit, .setVideo(clips: [clip], patch: patch)]
    }

    /// The same for a text clip's wrap width.
    func ops(text patch: TextPatch, clip: UInt32) -> [ReelOp] {
        let edit = op(text: patch, clip: clip)
        guard onCut(clip) else { return [edit] }
        return [edit, .setText(clips: [clip], patch: patch)]
    }

    private func onCut(_ clip: UInt32) -> Bool { written(clip)?.cut == true }

    /// `clip_state` at `clip.start + endTime` decoded through
    /// `InspectorBinding.decode` — the inspector's own read of an END state,
    /// video and text from ONE call — for `selected.clip` and a clip in
    /// `held`; the clip's base props otherwise. A group the core does not
    /// answer falls back to base.
    func start(of clip: ClipSnapshot, in project: ReelProject?) -> Start {
        guard let selected = written(clip.id),
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

extension CanvasEditTarget.Gesture {
    /// The word CI-19's sentence names the gesture by.
    var refusalNoun: String {
        switch self {
        case .move: return "move"
        case .scale, .width: return "resize"
        case .rotate: return "rotation"
        case .crop: return "crop"
        }
    }
}

/// CI-19: past a finished action, not a cut, whose end holds a key a single
/// clip's gesture writes, the gesture refuses and names the action.
extension CanvasEditTarget {
    /// `.width` for a text-source clip's side handle (drivesX && !isCorner),
    /// `.scale` otherwise.
    static func scaleGesture(clip: ClipSnapshot, handle: CanvasHandle) -> Gesture {
        guard clip.text != nil, case .text = clip.source, handle.drivesX, !handle.isCorner
        else { return .scale }
        return .width
    }

    /// The names of the keys `gesture` writes that `end` holds, in the
    /// sentence's order; empty when none.
    static func heldKeys(_ end: ActionPatch, _ gesture: Gesture) -> [String] {
        let video = end.video
        let position = video?.x != nil || video?.y != nil
        switch gesture {
        case .move:
            return position ? ["position"] : []
        case .scale:
            return (position ? ["position"] : []) + (video?.scale != nil ? ["size"] : [])
        case .width:
            return end.text?.width != nil ? ["width"] : []
        case .rotate:
            return video?.rotation != nil ? ["rotation"] : []
        case .crop:
            return video?.crop != nil ? ["crop"] : []
        }
    }

    /// The latest action, not a cut, whose end is at or before `clipTime`
    /// and whose heldKeys are non-empty.
    static func holder(
        _ gesture: Gesture, clip: ClipSnapshot, at clipTime: Ticks, frame: Ticks
    ) -> ActionSnapshot? {
        clip.actions
            .filter { !isCut($0, frame: frame) && $0.endTime <= clipTime }
            .filter { !heldKeys($0.end, gesture).isEmpty }
            .max { ($0.endTime, $0.id) < ($1.endTime, $1.id) }
    }

    /// The sentence, naming `holder` by its number on `clip`'s lane
    /// (`ActionBands.ordered`).
    static func heldSentence(_ gesture: Gesture, holder: ActionSnapshot, on clip: ClipSnapshot)
        -> String
    {
        let n = (ActionBands.ordered(clip).firstIndex { $0.id == holder.id } ?? 0) + 1
        let what = heldKeys(holder.end, gesture).joined(separator: " and ")
        return "action \(n) on this clip's lane holds its \(what) at the playhead, so a "
            + "\(gesture.refusalNoun) here would show only before it. Select action \(n) first."
    }
}

/// A canvas drag CI-19 refused at its press: shown on its first drag tick.
struct CanvasRefusedGesture {
    let refusal: ReelRefusal
    var shown: Bool
}

extension PreviewCanvasView {
    /// nil unless CI-19 applies to clip `id`: no action selected, the
    /// selection exactly `[id]`, its track unlocked, not a scale on a shape
    /// (`set_shape` has no action form), and a holder at the playhead. The
    /// refusal's `op` is `set_text` for `.width`, `set_video` otherwise.
    func heldRefusal(_ gesture: CanvasEditTarget.Gesture, clip id: UInt32) -> ReelRefusal? {
        guard editTarget.selected == nil, selection == [id], let clip = snapshot.clip(id),
              snapshot.track(clip.track)?.locked != true
        else { return nil }
        if gesture == .scale, case .shape = clip.source { return nil }
        guard let holder = CanvasEditTarget.holder(
            gesture, clip: clip, at: playhead - clip.start,
            frame: snapshot.canvas.fps.frameDuration)
        else { return nil }
        return ReelRefusal(
            op: gesture == .width ? "set_text" : "set_video",
            reason: CanvasEditTarget.heldSentence(gesture, holder: holder, on: clip))
    }

    /// A begin*'s line: sets `refusedGesture` (nil, or the refusal not yet
    /// shown) and answers whether the gesture was refused.
    func refusesHeld(_ gesture: CanvasEditTarget.Gesture, clip id: UInt32) -> Bool {
        refusedGesture = heldRefusal(gesture, clip: id).map {
            CanvasRefusedGesture(refusal: $0, shown: false)
        }
        return refusedGesture != nil
    }

    /// continueGesture's: true while a refused gesture is held; calls
    /// `onRefuse` on its first tick only, so a press that only selects is
    /// silent.
    func continueRefusedGesture() -> Bool {
        guard var refused = refusedGesture else { return false }
        if !refused.shown {
            refused.shown = true
            refusedGesture = refused
            onRefuse?(refused.refusal)
        }
        return true
    }
}

extension PreviewCanvasView {
    /// The target a gesture starts from and writes: `editTarget` with an
    /// action selected or nothing selected, otherwise the clip's `holding`
    /// (CI-17), or each selected clip's for a multi-selection (#529). Asked at
    /// mouse-down and never written back: `editTarget` stays the document's
    /// mode, and the selection stays as it is.
    func heldTarget(_ gesture: CanvasEditTarget.Gesture) -> CanvasEditTarget {
        if editTarget.selected == nil, selection.count > 1 {
            return editTarget.holding(
                gesture, clips: selection.sorted().compactMap { snapshot.clip($0) },
                frame: snapshot.canvas.fps.frameDuration)
        }
        guard editTarget.selected == nil, selection.count == 1, let id = selection.first,
              let clip = snapshot.clip(id)
        else { return editTarget }
        return editTarget.holding(gesture, clip: clip, frame: snapshot.canvas.fps.frameDuration)
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

extension ClipSnapshot {
    /// The clip's first-frame cut (CI-17), the first action `CanvasEditTarget.isCut` answers; nil when none.
    func firstFrameCut(frame: Ticks) -> ActionSnapshot? {
        actions.first { CanvasEditTarget.isCut($0, frame: frame) }
    }
}

extension VideoPatch {
    /// This patch's keys whose `dictionary` name `end?.dictionary` also has (a sparse part such as
    /// `cutoutPart` counts under its parent's name, `cutout`); every other key nil. nil `end` → empty.
    /// #530's write to a cut: only what the cut already holds goes there.
    func held(by end: VideoPatch?) -> VideoPatch {
        guard let end else { return VideoPatch() }
        let names = Set(end.dictionary.keys)
        func kept<T>(_ value: T?, _ name: String) -> T? { names.contains(name) ? value : nil }
        var next = VideoPatch()
        next.x = kept(x, "x")
        next.y = kept(y, "y")
        next.scale = kept(scale, "scale")
        next.rotation = kept(rotation, "rotation")
        next.opacity = kept(opacity, "opacity")
        next.crop = kept(crop, "crop")
        next.cornerRadius = kept(cornerRadius, "corner_radius")
        next.shadow = kept(shadow, "shadow")
        next.color = kept(color, "color")
        next.chroma = kept(chroma, "chroma")
        next.filters = kept(filters, "filters")
        next.reflection = kept(reflection, "reflection")
        next.spotlight = kept(spotlight, "spotlight")
        next.obscure = kept(obscure, "obscure")
        next.blend = kept(blend, "blend")
        next.motion = kept(motion, "motion")
        next.look = kept(look, "look")
        next.wheels = kept(wheels, "wheels")
        next.curves = kept(curves, "curves")
        next.qualifier = kept(qualifier, "qualifier")
        next.cursor = kept(cursor, "cursor")
        next.cursorPart = kept(cursorPart, "cursor")
        next.cutout = kept(cutout, "cutout")
        next.cutoutPart = kept(cutoutPart, "cutout")
        next.behindSubject = kept(behindSubject, "behind_subject")
        next.motionBlur = kept(motionBlur, "motion_blur")
        next.hideSilent = kept(hideSilent, "hide_silent")
        return next
    }
}
