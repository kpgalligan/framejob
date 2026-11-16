import AppKit

/// The editor's half of its document's close (spec §11 #568).
extension EditorViewController {
    /// Called by `ProjectDocument.releaseOnClose()` for each of the document's editors, while
    /// the window may still be alive: the player drops its item now and builds no other.
    /// `deinit` still runs its own teardown later; both are safe to run twice.
    func shutDownForClose() {
        playback.shutDown()
    }
}
