import AppKit

/// Clip ▸ Add Shortcut Overlays (road map "creator-jobs" CU8, spec §11 CU-84): the selected
/// clips of the container being edited — the timeline, or the open nest — get one
/// `keyboard-keys` clip per recorded shortcut, placed by `ShortcutOverlays.prepared` with the
/// defaults (bottom, dark, 1.5 s) as one undo step "Add Shortcut Overlays". No sheet: the cursor
/// files are read off the main thread, and an informational sheet says what did not go as
/// asked. `add_shortcut_overlays` mirrors it (`AgentServer+ShortcutOverlays.swift`).
extension EditorViewController {

    /// The selected clips the menu offers overlays on, in id order; empty when any of them is
    /// not a media clip whose media has a cursor file. Reads no file.
    private func shortcutOverlayClips(_ document: ProjectDocument) -> [UInt32] {
        let snapshot = document.editedProject.snapshot
        let clips = document.selection.sorted().compactMap { snapshot.clip($0) }
        guard clips.count == document.selection.count,
            AutoZoom.canOffer(clips, in: snapshot)
        else { return [] }
        return clips.map(\.id)
    }

    @objc func addShortcutOverlays(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil,
            !ShortcutOverlays.isPending(document)
        else {
            NSSound.beep()
            return
        }
        let ids = shortcutOverlayClips(document)
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        let snapshot = document.editedProject.snapshot
        let files: [UInt32: URL]
        do {
            files = try AutoZoom.cursorFiles(ids.compactMap { snapshot.clip($0) }, in: snapshot)
        } catch {
            showShortcutOverlayNotice(error.localizedDescription)
            return
        }
        let asked = document.project
        let scope = document.scope
        ShortcutOverlays.setPending(document, true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let read = Result { try AutoZoom.readTracks(files) }
            DispatchQueue.main.async {
                ShortcutOverlays.setPending(document, false)
                self?.placeShortcutOverlays(document, ids, read, asked: asked, scope: scope)
            }
        }
    }

    /// The run's main half: refuse a changed project, place, and say what did not go as asked.
    private func placeShortcutOverlays(
        _ document: ProjectDocument, _ ids: [UInt32], _ read: Result<[UInt32: ReelCursor], Error>,
        asked: ReelProject, scope: UInt32?
    ) {
        let tracks: [UInt32: ReelCursor]
        switch read {
        case .success(let value): tracks = value
        case .failure(let error):
            showShortcutOverlayNotice(error.localizedDescription)
            return
        }
        guard document.project === asked, document.scope == scope else {
            showShortcutOverlayNotice(
                "The project changed while the cursor files were read, so no overlay was "
                    + "added. Choose Clip ▸ Add Shortcut Overlays again.")
            return
        }
        do {
            let run = try ShortcutOverlays.prepared(
                document, clips: ids, tracks: tracks, settings: ShortcutOverlaySettings(),
                from: nil, to: nil)
            guard !run.plan.ops.isEmpty else {
                showShortcutOverlayNotice(ShortcutOverlays.nothingSentence)
                return
            }
            document.performGroupedEdit(ShortcutOverlays.actionName, run.plan.ops)
            if run.plan.dropped > 0 {
                showShortcutOverlayNotice(ShortcutOverlays.droppedSentence(run.plan.dropped))
            }
        } catch {
            showShortcutOverlayNotice(error.localizedDescription)
        }
    }

    /// An informational sheet on the editor's window saying `text` (`showGraphicNotice`'s
    /// shape); nothing with no window or a sheet already up.
    private func showShortcutOverlayNotice(_ text: String) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = text
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any
    /// other action. On with at least one selected clip, each a media clip whose media has a
    /// cursor file, no sheet on the window and no run pending; allowed inside a nest. It never
    /// reads a file.
    func validateShortcutOverlaysAction(_ action: Selector) -> Bool? {
        guard action == #selector(addShortcutOverlays(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil,
            !ShortcutOverlays.isPending(document)
        else { return false }
        return !shortcutOverlayClips(document).isEmpty
    }
}
