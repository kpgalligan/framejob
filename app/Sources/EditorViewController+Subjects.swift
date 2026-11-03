import AppKit

/// View ▸ Show Subjects (spec §11 VR-13; road map "creator-jobs" VR1): a
/// checkmark toggle about the preview that draws the selected clip's cached
/// face, person and salient boxes at the playhead (`SubjectsOverlay`).
///
/// **View state, per window, never persisted**: the overlay is the canvas's
/// `subjects`, nil while off; nothing is written to `UserDefaults`, so a new
/// window starts with it off and a proof can drive it through
/// `perform_menu_item` without moving the defaults. **It never starts an
/// analysis**: an uncached clip shows "Not analyzed — Clip ▸ Follow Subject…
/// analyzes it"; `get_media_analysis` and Clip ▸ Follow Subject… make what it draws. No MCP tool
/// mirrors it (§7.9's Preview Quality exemption, as Show Ungraded): it edits
/// nothing, and `get_media_analysis {kind: "faces" | "subjects"}` answers
/// what it draws. Always enabled.
extension EditorViewController {

    @objc func toggleShowSubjects(_ sender: Any?) {
        guard let canvas = previewCanvas else { return }
        guard canvas.subjects == nil, let document else {
            canvas.subjects = nil
            return
        }
        canvas.subjects = SubjectsOverlay(document: document) { [weak canvas] in
            canvas?.overlay.needsDisplay = true
        }
    }

    /// The validator arm `validateSeeingAction` forwards to; nil for another
    /// action.
    func validateSubjectsAction(_ action: Selector, item: any NSValidatedUserInterfaceItem)
        -> Bool?
    {
        guard action == #selector(toggleShowSubjects(_:)) else { return nil }
        (item as? NSMenuItem)?.state = previewCanvas?.subjects != nil ? .on : .off
        return true
    }
}
