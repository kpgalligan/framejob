import AppKit

/// Clip ▸ Look ▸ (spec §11 GR-7 [b], the grading branch's GR5b): the eight
/// looks, a separator and None — the menu half of the Color sub-tab's Look
/// section (`VideoPane+Look.swift`), and a UI path `set_video`'s `look`
/// mirror names.
///
/// The targets are `LookGallery.targets`: the selected clips that take a
/// grade (video, image, still, adjustment). A choice is ONE `set_video` over
/// all of them — a kind alone keeps each clip's amount (1 on a clip with
/// none), None is `look: null` — on the clips' own look, whatever action is
/// selected (GR-7 [b] (1)), one undo step "Look". The tags are the Motion
/// idiom: an index into `LookKind.allCases`, −1 None, and any other tag a
/// stranger that beeps and writes nothing.
extension EditorViewController {

    /// The selected clips a look applies to.
    private var lookTargets: [ClipSnapshot] {
        guard let document = document else { return [] }
        return LookGallery.targets(selectedClips, in: document.editedProject.snapshot)
    }

    /// The one tag that means None, as `lookMenu()` writes it.
    private static let lookNoneTag = -1

    /// The sender's tag indexes `LookKind.allCases`; −1 is None.
    @objc func setLook(_ sender: Any?) {
        let targets = lookTargets
        guard let document = document, let tag = (sender as? NSMenuItem)?.tag,
              !targets.isEmpty, let kind = lookKind(tag)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit("Look", [LookGallery.op(kind, clips: targets.map(\.id))])
    }

    /// What a tag SAYS: `.some(kind)` for an index into the vocabulary,
    /// `.some(nil)` for None, nil for a tag no builder writes.
    private func lookKind(_ tag: Int) -> LookKind?? {
        if tag == Self.lookNoneTag { return .some(nil) }
        return LookKind.builtIns.indices.contains(tag) ? .some(LookKind.builtIns[tag]) : nil
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns; nil is "not
    /// mine". An item is on when every target's OWN look is its kind (None:
    /// no look), dashed when some but not all are (GR-7 [b] (3)), off
    /// otherwise; enabled exactly when there is a target.
    func validateLookAction(_ action: Selector, item: any NSValidatedUserInterfaceItem) -> Bool? {
        guard action == #selector(setLook(_:)) else { return nil }
        let targets = lookTargets
        let menuItem = item as? NSMenuItem
        if let tagged = lookKind(menuItem?.tag ?? Int.min) {
            let carrying = targets.filter { $0.videoProps.look?.kind == tagged }.count
            menuItem?.state =
                carrying == 0 ? .off : (carrying == targets.count ? .on : .mixed)
        } else {
            menuItem?.state = .off
        }
        return !targets.isEmpty
    }
}
