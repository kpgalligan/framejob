import AppKit

/// Clip ▸ Retime Range… (road map "creator-jobs" CU9a, spec §11 CU-90 (d)):
/// the In–Out range of the container being edited — the timeline, or the
/// open nest — put up in `RetimeSheetController`, whose Apply commits one
/// `retime_range` through `SpeedAudioDrop.commit`. `retime_range`'s tool
/// mirrors it (`AgentServer+Retime.swift`).
extension EditorViewController {

    @objc func showRetimeSheet(_ sender: Any?) {
        guard let document, let range = document.inOutRange,
            view.window?.attachedSheet == nil
        else {
            NSSound.beep()
            return
        }
        presentAsSheet(
            RetimeSheetController(document: document, range: (from: range.start, to: range.end)))
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case;
    /// nil for any other action. On with an In–Out range and no sheet on the
    /// window; allowed inside a nest.
    func validateRetimeAction(_ action: Selector) -> Bool? {
        guard action == #selector(showRetimeSheet(_:)) else { return nil }
        guard let document else { return false }
        return document.inOutRange != nil && view.window?.attachedSheet == nil
    }
}
