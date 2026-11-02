// app/Sources/EditorViewController+Cutout.swift — the preview's answer to a masks publish (road
// map creator-jobs CO2b, spec §11 CO-22 (d)). The compositor draws a cut-out clip uncut until its
// masks are cached (CO-6) and re-reads the pack on the marker's stat (CO-25); when a publish lands
// in this document's cache folder, a paused frame is recomposed by the one-tick round trip. A
// playing preview draws it on its next frame by itself, and the plan did not change, so nothing
// rebuilds.

import AppKit

extension EditorViewController {
    @objc func analysisDidPublish(_ note: Notification) {
        guard let document = document,
            note.userInfo?["kind"] as? String == AnalysisKind.masks.rawValue,
            let folder = note.userInfo?["cacheDir"] as? String,
            document.intendedCacheDirectory?.standardizedFileURL.path == folder
        else { return }
        playback.refreshPausedFrame()
    }
}
