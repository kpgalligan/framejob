// app/Sources/EditorViewController+Cursor.swift — the preview's answer to a cursor track
// landing (road map creator-jobs CU3a2, spec §11 CU-37 (a)). The compositor draws only a
// track `CursorTracks` has made ready and draws the frame without it until then; when one of
// this document's files lands, a paused frame is recomposed by the one-tick round trip. A
// playing preview draws it on its next frame by itself.

import AppKit

extension EditorViewController {
    @objc func cursorTrackDidLand(_ note: Notification) {
        guard let document = document, let path = note.userInfo?["path"] as? String else { return }
        let files = RecipeSource.shared.cursorFiles(for: document.recipeKey)
        guard files.values.contains(where: { $0.url.path == path }) else { return }
        playback.refreshPausedFrame()
    }
}
