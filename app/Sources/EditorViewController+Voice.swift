import AppKit

/// Clip ▸ Voice ▸ (spec §11 AU-158, #390): the sixteen voice effects under
/// their four group headers, a separator and None — the menu half of the
/// Sound tab's Voice Effect section (`AudioPane+Voice.swift`), and a UI path
/// `set_audio`'s `voice` mirror names.
///
/// The decisions are `VoiceMenu`'s: the targets are the selected clips with
/// sound, a kind keeps each clip's own amount and clears its pitch, None is
/// `voice: null`, all on the clips' own value whatever action is selected
/// (AU-140), one undo step "Voice Effect". A tag no builder writes is a
/// stranger that beeps and writes nothing.
extension EditorViewController {

    /// The selected clips a voice effect goes to.
    private var voiceTargets: [ClipSnapshot] {
        guard let document = document else { return [] }
        return VoiceMenu.targets(selectedClips, in: document.editedProject.snapshot)
    }

    /// The sender's tag indexes `VoiceKind.allCases`; −1 is None.
    @objc func setVoiceEffect(_ sender: Any?) {
        let targets = voiceTargets
        guard let document = document, let tag = (sender as? NSMenuItem)?.tag,
            let kind = VoiceMenu.kind(tag: tag), !targets.isEmpty
        else {
            NSSound.beep()
            return
        }
        document.applyEdit("Voice Effect", VoiceMenu.ops(kind, targets: targets))
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns; nil is "not
    /// mine". The item's mark is `VoiceMenu.state` (off for a stranger tag);
    /// enabled exactly when there is a target.
    func validateVoiceAction(_ action: Selector, item: any NSValidatedUserInterfaceItem) -> Bool? {
        guard action == #selector(setVoiceEffect(_:)) else { return nil }
        let targets = voiceTargets
        let menuItem = item as? NSMenuItem
        if let kind = VoiceMenu.kind(tag: menuItem?.tag ?? Int.min) {
            menuItem?.state = VoiceMenu.state(kind, targets: targets)
        } else {
            menuItem?.state = .off
        }
        return !targets.isEmpty
    }
}
