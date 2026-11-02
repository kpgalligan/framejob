// app/Sources/EditorViewController+Cutout.swift — the preview's answer to a masks publish (road
// map creator-jobs CO2b, spec §11 CO-22 (d)). The compositor draws a cut-out clip uncut until its
// masks are cached (CO-6) and re-reads the pack on the marker's stat (CO-25); when a publish lands
// in this document's cache folder, a paused frame is recomposed by the one-tick round trip. A
// playing preview draws it on its next frame by itself, and the plan did not change, so nothing
// rebuilds.
//
// Clip ▸ Remove Background and the Background section's Analyze Now (road map creator-jobs CO3,
// spec §11 CO-30 (c), (e)), with their validator arm — the UI paths `analyze_cutout` and
// `set_video`'s `cutout` name.

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

    /// The selected clips in the open scope that can be cut out (CO-30 (e)).
    private var cutoutTargets: [ClipSnapshot] {
        guard let document = document else { return [] }
        let snapshot = document.editedProject.snapshot
        return selectedClips.filter { CutoutStatus.canCutOut($0, in: snapshot) }
    }

    /// Clip ▸ Remove Background: every target cut out → all off; otherwise the ones without a
    /// cutout on, each cut-out clip's own values kept. One undo step, one base `set_video` per
    /// clip as Clip ▸ Motion ▸ writes.
    @objc func toggleRemoveBackground(_ sender: Any?) {
        guard let document = document else {
            NSSound.beep()
            return
        }
        let ops = CutoutStatus.toggleOps(selectedClips, in: document.editedProject.snapshot)
        guard !ops.isEmpty else {
            NSSound.beep()
            return
        }
        document.applyEdit("Remove Background", ops)
    }

    /// The Background section's Analyze Now: the wants made again, then a failed run retried
    /// (`ProjectDocument.analyzeMasksNow`).
    @objc func analyzeCutoutNow(_ sender: Any?) {
        guard let document = document else {
            NSSound.beep()
            return
        }
        document.analyzeMasksNow()
    }

    /// The half of `validateUserInterfaceItem` this file owns; nil is "not mine". Remove
    /// Background's checkmark is on, mixed or off as every, some or none of the targets is cut
    /// out.
    func validateCutoutAction(_ action: Selector, item: NSValidatedUserInterfaceItem?) -> Bool? {
        switch action {
        case #selector(toggleRemoveBackground(_:)):
            guard let document = document else { return false }
            (item as? NSMenuItem)?.state = CutoutStatus.menuState(
                selectedClips, in: document.editedProject.snapshot)
            return !cutoutTargets.isEmpty
        case #selector(analyzeCutoutNow(_:)):
            guard let document = document else { return false }
            return cutoutTargets.filter { $0.video?.cutout != nil }.contains { clip in
                switch CutoutStatus.status(of: clip.id, in: document).state {
                case .analyzing, .failed: return true
                default: return false
                }
            }
        default:
            return nil
        }
    }
}
