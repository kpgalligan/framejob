import AppKit

/// The window's one assistant session (spec §11 AI-4): opened on first ask,
/// replaced once it has closed (a dead helper), and closed with the window.
/// The stored `assistant` is in `EditorViewController.swift`. Road map 12 A1;
/// A2's pane is its first person-facing caller.
extension EditorViewController {

    /// The live session, else a new one for this window's project. Main only.
    func assistantSession() -> Result<AssistantSession, AssistantOpenError> {
        if let live = assistant, live.phase != .closed { return .success(live) }
        guard let document else {
            return .failure(AssistantOpenError(message: "This window has no project."))
        }
        switch AssistantSession.open(document: document) {
        case .failure(let error):
            return .failure(error)
        case .success(let session):
            assistant = session
            if let window = view.window {
                let center = NotificationCenter.default
                center.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
                center.addObserver(
                    self, selector: #selector(assistantWindowWillClose(_:)),
                    name: NSWindow.willCloseNotification, object: window)
            }
            return .success(session)
        }
    }

    /// Closing the window ends its conversation: a pending question is
    /// declined (AI-7) and the helper's stdin is closed.
    @objc func assistantWindowWillClose(_ note: Notification) {
        assistant?.close()
        assistant = nil
    }
}
