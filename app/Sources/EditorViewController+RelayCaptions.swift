import AppKit

/// File ▸ Re-lay Captions for This Canvas (road map "creator-jobs" VR4a, spec §11 VR-45): the
/// word caption tracks of the container being edited — the timeline, or the open nest at the
/// nest's size — re-paged on its canvas from their own words (`CaptionRelayout.plan`, VR-40)
/// as one undo step "Re-lay Captions". No sheet of its own: an informational sheet names each
/// caption track kept as placed, and none appears when every track was re-laid.
/// `relay_captions` mirrors it (`AgentServer+VerticalVersion.swift`).
extension EditorViewController {

    @objc func relayCaptions(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil,
            !ScreenRecorder.shared.isRecording
        else {
            NSSound.beep()
            return
        }
        let planned: (ops: [ReelOp], outcome: CaptionRelayout.Outcome)
        do {
            planned = try CaptionRelayout.plan(document.editedProject)
        } catch {
            showRelayCaptionsNotice(error.localizedDescription)
            return
        }
        guard !planned.ops.isEmpty else {
            if let nothing = CaptionRelayout.noticeText(planned.outcome) {
                showRelayCaptionsNotice(nothing)
            } else {
                NSSound.beep()
            }
            return
        }
        document.performGroupedEdit(CaptionRelayout.actionName, planned.ops)
        if let text = CaptionRelayout.noticeText(planned.outcome) {
            showRelayCaptionsNotice(text)
        }
    }

    /// An informational sheet on the editor's window: the notice's first line as its message,
    /// the kept tracks' lines as its informative text (`showShortcutOverlayNotice`'s shape);
    /// nothing with no window or a sheet already up.
    private func showRelayCaptionsNotice(_ text: String) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        var lines = text.components(separatedBy: "\n")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = lines.removeFirst()
        alert.informativeText = lines.joined(separator: "\n")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any
    /// other action. On with a document, no sheet on the window, no recording running and at
    /// least one recognised caption track in the container being edited; allowed inside a
    /// nest.
    func validateRelayCaptionsAction(_ action: Selector) -> Bool? {
        guard action == #selector(relayCaptions(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil,
            !ScreenRecorder.shared.isRecording
        else { return false }
        return !CaptionRelayout.survey(document.editedProject.snapshot).recognised.isEmpty
    }
}
