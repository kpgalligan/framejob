import AppKit

/// The editor's two doors to `SpeedAudioDrop`'s question (#212, spec §11
/// #190): the inspector's Speed section (Rate, its presets, Keep pitch,
/// Reset, Fit to) and the timeline's ⌥-drag rate stretch. The Speed sheet
/// asks from its own Apply; an agent is told in its answer instead.
extension EditorViewController {
    /// `inspector.onEdit`: every inspector commit lands here. An edit that
    /// takes no clip with sound above the ceiling is applied as it always
    /// was; one that does asks first, and Cancel puts the fields back.
    func inspectorEdit(_ name: String, _ ops: [ReelOp]) {
        guard let document = document else { return }
        SpeedAudioDrop.commit(
            name, ops, to: document, asking: view.window,
            declined: { [weak self] in self?.refreshInspector(isLive: false) })
    }

    /// `timeline.onLiveUpdate` and `inspector.onLiveUpdate` (the Clip tab
    /// lane's band drags): one tick, and its ops remembered when the
    /// tick applied, so a stretch put back for the question can be re-applied
    /// exactly as the person last saw it.
    func timelineLiveUpdated(_ ops: [ReelOp]) {
        guard let document = document else { return }
        let before = document.project
        document.updateLiveEdit(ops)
        if document.project !== before { lastLiveOps = ops }
    }

    /// `timeline.onLiveEnd` and `inspector.onLiveEnd`: the captions the
    /// gesture re-times are added as one more tick (spec §11 SR-27), so they
    /// jump at mouse-up and the step is named "and Re-time Captions". A
    /// gesture that crossed the ceiling is put back
    /// BEFORE the question (no step, no change count), so nothing is live
    /// while it is up — a save writes the base and an agent call is not held
    /// (spec §11 AI-12). Set Speed re-applies the last applied ops as one
    /// step, planned again when the document changed while the question was
    /// up (SR-27 (h)); Cancel leaves the base.
    func timelineLiveEnded(_ name: String) {
        let (rawName, rawOps) = (name, lastLiveOps)
        var ops = rawOps
        lastLiveOps = []
        guard let document = document else { return }
        guard let base = document.liveEditBase else {
            document.endLiveEdit(name)
            return
        }
        let plan = CaptionRetime.plan(ops, on: document.scope.flatMap { base.scoped($0) } ?? base)
        if !plan.isEmpty {
            ops += plan.ops
            document.updateLiveEdit(ops)
        }
        let name = plan.undoName(name)
        let clips =
            SpeedAudioDrop.mayCross(ops)
            ? SpeedAudioDrop.crossing(from: base.snapshot, to: document.project.snapshot) : []
        guard !clips.isEmpty else {
            document.endLiveEdit(name)
            return
        }
        document.endLiveEdit(name, cancelled: true)
        guard let window = view.window else {
            NSSound.beep()
            return
        }
        SpeedAudioDrop.ask(clips, on: window) { [weak document] confirmed in
            guard confirmed, let document else { return }
            let step =
                document.project === base
                ? (name: name, ops: ops)
                : CaptionRetime.withRetime(rawName, rawOps, on: document.editedProject)
            document.performGroupedEdit(step.name, step.ops)
        }
    }
}
