import AppKit

/// Clip ▸ Motion ▸ (road map 5's E2): the In / Out / During submenus and
/// Preview — the menu half of the Clip tab's Motion section
/// (`VideoPane+Motion.swift`), and the UI paths `set_video`'s `motion`
/// mirror names.
///
/// The targets are the selected clips that put pixels on the canvas
/// (`InspectorTab.hasPixels`), the test the section and the timeline's
/// wedges gate on too. Every write is ONE `set_video` PER CLIP, because a
/// `motion` patch replaces the whole object and each clip keeps its own other
/// two slots; the ops go as one edit, so a selection is one undo step.
extension EditorViewController {

    // MARK: - Commands

    /// The sender's tag indexes `EdgeMotion.allCases`; −1 is None.
    @objc func setMotionIn(_ sender: Any?) { setMotionCommand(slot: .inEdge, sender: sender) }

    /// The sender's tag indexes `EdgeMotion.allCases`; −1 is None.
    @objc func setMotionOut(_ sender: Any?) { setMotionCommand(slot: .out, sender: sender) }

    /// The sender's tag indexes `DuringMotion.allCases`; −1 is None.
    @objc func setMotionDuring(_ sender: Any?) { setMotionCommand(slot: .during, sender: sender) }

    /// Preview: the in/out range set to the first target and Loop turned on,
    /// then play from its start. Both stay until the person clears them —
    /// the Preview button's tooltip says so.
    @objc func previewClipMotion(_ sender: Any?) {
        guard let document = document, let clip = motionTargets.first else {
            NSSound.beep()
            return
        }
        document.inOutRange = (clip.start, clip.end)
        if !loopEnabled {
            loopEnabled = true
            refreshToolbarControls()
        }
        viewStateDidChange()
        // Never `playback.loopRange` directly: `applyLoopRange` rewrites it
        // from `inOutRange`.
        applyLoopRange()
        setPlayhead(clip.start)
        playback.play()
    }

    private enum MotionSlot {
        case inEdge, out, during
    }

    /// The selected clips a motion applies to.
    private var motionTargets: [ClipSnapshot] {
        guard let document = document else { return [] }
        let snapshot = document.editedProject.snapshot
        return selectedClips.filter { InspectorTab.hasPixels($0, in: snapshot) }
    }

    private func setMotionCommand(slot: MotionSlot, sender: Any?) {
        let targets = motionTargets
        guard let document = document, let tag = (sender as? NSMenuItem)?.tag,
              !targets.isEmpty
        else {
            NSSound.beep()
            return
        }
        let count = slot == .during ? DuringMotion.allCases.count : EdgeMotion.allCases.count
        guard tag < 0 || tag < count else {
            NSSound.beep()
            return
        }
        var ops: [ReelOp] = []
        for clip in targets {
            let current = clip.videoProps.motion ?? MotionProps()
            let next: MotionProps
            switch slot {
            case .inEdge:
                next = current.with(inEdge: edge(tag, keeping: current.inEdge))
            case .out:
                next = current.with(out: edge(tag, keeping: current.out))
            case .during:
                next = current.with(during: during(tag, keeping: current.during))
            }
            ops.append(.setVideo(clips: [clip.id], patch: VideoPatch(motion: .some(next))))
        }
        // An all-identity batch is the core's refusal and beeps; a mixed one
        // lands (`ReelProject.applying` runs later ops past an identity).
        document.applyEdit("Set Motion", ops)
    }

    /// A chosen kind keeps the slot's stored duration, else `MotionEdge()`'s
    /// 0.5 s — the section's rule.
    private func edge(_ tag: Int, keeping stored: MotionEdge?) -> MotionEdge? {
        guard tag >= 0 else { return nil }
        let kind = EdgeMotion.allCases[tag]
        return MotionEdge(kind: kind, duration: stored?.duration ?? MotionEdge().duration)
    }

    /// A chosen kind keeps the stored amount and period, else the defaults.
    private func during(_ tag: Int, keeping stored: MotionDuring?) -> MotionDuring? {
        guard tag >= 0 else { return nil }
        let base = stored ?? MotionDuring()
        return MotionDuring(
            kind: DuringMotion.allCases[tag], amount: base.amount, period: base.period)
    }

    /// The kind the targets agree on in one slot: `.some(kind)` when every
    /// target carries it, `.some(nil)` when none carries the slot, and nil
    /// when they disagree — `sharedClipLabel`'s shape, so a checkmark is on a
    /// kind, on None, or on nothing.
    private func sharedMotionKind<K: Equatable>(_ read: (MotionProps?) -> K?) -> K?? {
        let kinds = motionTargets.map { read($0.videoProps.motion) }
        guard let first = kinds.first, kinds.allSatisfy({ $0 == first }) else { return nil }
        return .some(first)
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns; nil is "not
    /// mine".
    func validateMotionAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        let menuItem = item as? NSMenuItem
        let tag = menuItem?.tag ?? -1
        switch action {
        case #selector(setMotionIn(_:)):
            let shared = sharedMotionKind { $0?.inEdge?.kind }
            menuItem?.state = checked(shared, tagged: kindAt(EdgeMotion.allCases, tag))
        case #selector(setMotionOut(_:)):
            let shared = sharedMotionKind { $0?.out?.kind }
            menuItem?.state = checked(shared, tagged: kindAt(EdgeMotion.allCases, tag))
        case #selector(setMotionDuring(_:)):
            let shared = sharedMotionKind { $0?.during?.kind }
            menuItem?.state = checked(shared, tagged: kindAt(DuringMotion.allCases, tag))
        case #selector(previewClipMotion(_:)):
            break
        default:
            return nil
        }
        return !motionTargets.isEmpty
    }

    private func kindAt<K>(_ kinds: [K], _ tag: Int) -> K? {
        kinds.indices.contains(tag) ? kinds[tag] : nil
    }

    private func checked<K: Equatable>(_ shared: K??, tagged: K?) -> NSControl.StateValue {
        guard let shared = shared else { return .off }
        return shared == tagged ? .on : .off
    }
}
