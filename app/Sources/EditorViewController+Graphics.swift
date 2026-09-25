// app/Sources/EditorViewController+Graphics.swift — the preview's answer to
// a module, font or asset changing on disk (road map 10 G3b; G-13, preview
// follows the newest revision). The plan does not change when a module
// does, so the §7.6 rebuild rule would skip it; the registry has already
// swapped the compiled set in, and a paused frame is recomposed by the
// one-tick round trip. A playing preview picks the new set up on its next
// frame by itself.

import AppKit

extension EditorViewController {
    @objc func graphicsDidChange(_ note: Notification) {
        guard let document = document, note.object as? ProjectDocument === document else { return }
        playback.refreshPausedFrame()
        inspector?.refresh(isLive: false)
    }
}
