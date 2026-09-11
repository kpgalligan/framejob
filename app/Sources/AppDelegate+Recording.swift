import AppKit

/// File ▸ New Recording… (⌥⌘N) and the welcome window's third button —
/// road map 3, R1c. One `@objc` action and nothing stored, on purpose:
/// `AppDelegate` has no stored properties, and the chrome probes
/// (`phase6_chrome.py`, `phase9_probe.py`) instantiate `AppDelegate()` to
/// build the menu bar, so anything stored here would be built in every one
/// of them. The panel is `RecorderPanelController.shared` — one instance for
/// the life of the process, `ExportQueueWindowController`'s mould — because it
/// outlives documents and must exist with none open, and the recorder is
/// `ScreenRecorder.shared`.
///
/// It is a nil-target action, `newProject`'s shape (`AppDelegate.swift`): the
/// item resolves down the responder chain to the application delegate, which
/// is what lets it work from the welcome window and from a document window
/// alike. While a recording runs the same item reads "Stop Recording"
/// (`AppDelegate.validateMenuItem` retitles it from `ScreenRecorder.shared`),
/// and this action then stops instead of showing.
///
/// **Whose recording it is decides the route** (R1 review). The retitle reads
/// the RECORDER, which is one object shared by the panel and the
/// `record_screen` tool, so "Stop Recording" also shows over a recording the
/// tool started — and the panel's `stopRecording()` rightly beeps at one that
/// is not its own, which left the menu item a beep. So: the panel's own
/// recording (its phase `.recording` or `.starting`) stops through the
/// panel, which lands it exactly as its Stop button would; anything else the
/// recorder holds stops through `ScreenRecorder.shared.stop()` with no
/// completion, and the session's `onFinish` — the tool's — lands it; and
/// with nothing recording the panel is shown.
extension AppDelegate {
    @objc func newRecording(_ sender: Any?) {
        let panel = RecorderPanelController.shared
        switch panel.phase {
        case .recording, .starting:
            panel.stopRecording()
        default:
            if ScreenRecorder.shared.isRecording {
                ScreenRecorder.shared.stop()
            } else {
                panel.show()
            }
        }
    }
}
