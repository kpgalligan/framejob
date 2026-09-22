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

    /// The one tag that means None. `motionSlotMenu`
    /// (`AppDelegate+Menus.swift`) writes it and nothing else negative, so a
    /// tag that is neither this nor an index into the vocabulary came from
    /// nowhere this app knows and is refused rather than read as None.
    static let motionNoneTag = -1

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
        // None is EXACTLY −1, the one negative tag `motionSlotMenu` writes
        // (`AppDelegate+Menus.swift`). Any other tag out of range is a
        // stranger — an item nothing in this app built — and clearing a
        // person's arrival because a tag was −7 is a write they did not ask
        // for. It beeps and writes nothing.
        guard tag == Self.motionNoneTag || (tag >= 0 && tag < count) else {
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
        // Three answers, not two. An all-identity batch is the core's refusal
        // and beeps; a mixed one LANDS (`ReelProject.applying` runs later ops
        // past an identity). But `set_video` re-checks the whole stored group,
        // so a clip already carrying an out-of-range value — `paste` does not
        // range-check its payload — makes the op an `Err`, `applying` THROWS,
        // and the batch lands nothing and puts up the core's own message
        // (`core/tests/motion_edges.rs`'s
        // `a_motion_patch_on_a_clip_already_out_of_range_is_an_error`).
        document.applyEdit("Set Motion", ops)
    }

    /// A chosen kind keeps the slot's stored duration, else `MotionEdge()`'s
    /// 0.5 s — the section's rule. The caller's gate has already refused
    /// every tag but None and a real index, so `tag >= 0` is exactly "not
    /// None" here.
    private func edge(_ tag: Int, keeping stored: MotionEdge?) -> MotionEdge? {
        guard tag >= 0 else { return nil }
        let kind = EdgeMotion.allCases[tag]
        return MotionEdge(kind: kind, duration: stored?.duration ?? MotionEdge().duration)
    }

    /// A chosen kind keeps the stored amount and period, else the defaults.
    /// The caller's gate has already refused a stranger, as in [`edge`].
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
            if let kind = slotAt(EdgeMotion.allCases, tag) ?? nil {
                menuItem?.title = MotionEdge.menuTitle(
                    for: kind, among: motionTargets.map { $0.videoProps.motion?.inEdge })
            }
            let shared = sharedMotionKind { $0?.inEdge?.kind }
            menuItem?.state = checked(shared, tagged: slotAt(EdgeMotion.allCases, tag))
        case #selector(setMotionOut(_:)):
            if let kind = slotAt(EdgeMotion.allCases, tag) ?? nil {
                menuItem?.title = MotionEdge.menuTitle(
                    for: kind, among: motionTargets.map { $0.videoProps.motion?.out })
            }
            let shared = sharedMotionKind { $0?.out?.kind }
            menuItem?.state = checked(shared, tagged: slotAt(EdgeMotion.allCases, tag))
        case #selector(setMotionDuring(_:)):
            let shared = sharedMotionKind { $0?.during?.kind }
            menuItem?.state = checked(shared, tagged: slotAt(DuringMotion.allCases, tag))
        case #selector(previewClipMotion(_:)):
            break
        default:
            return nil
        }
        return !motionTargets.isEmpty
    }

    /// What a tag SAYS, in the same three-valued shape `sharedMotionKind`
    /// answers in: `.some(kind)` for an index into the vocabulary,
    /// `.some(nil)` for None, and nil for a tag no builder writes — which
    /// checks nothing rather than reading as None.
    private func slotAt<K>(_ kinds: [K], _ tag: Int) -> K?? {
        if tag == Self.motionNoneTag { return .some(nil) }
        return kinds.indices.contains(tag) ? .some(kinds[tag]) : nil
    }

    private func checked<K: Equatable>(_ shared: K??, tagged: K??) -> NSControl.StateValue {
        guard let shared = shared, let tagged = tagged else { return .off }
        return shared == tagged ? .on : .off
    }
}
