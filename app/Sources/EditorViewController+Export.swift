import AppKit

/// The editor's dialogs: Export… (⌘E and the toolbar button), Clip ▸ Speed…,
/// and the missing-media offer a document makes when its window appears.
///
/// The three are one file because they are one shape — capture what the sheet
/// needs, present it, and let it commit through `ProjectDocument` — and
/// because none of them owns any editor state. Everything durable lives in
/// the sheet controllers (`ExportSheetController`, `SpeedSheetController`,
/// `RelinkSheetController`); this is only the seam that puts them up.
///
/// **Every editor action is validated false while a sheet is attached**
/// (`EditorViewController.validateUserInterfaceItem`), which is what lets a
/// sheet capture a project handle and trust it: the document cannot change
/// under an open dialog.
extension EditorViewController {

    // MARK: - Export

    /// ⌘E, File ▸ Export…, and the toolbar's Export button. Refuses on an
    /// empty timeline rather than opening a dialog whose only honest answer
    /// is a zero-length movie.
    func exportProjectCommand() {
        guard let document = document, document.project.duration > 0 else {
            NSSound.beep()
            return
        }
        guard !ReelExport.presets().isEmpty else {
            NSSound.beep()
            return
        }
        playback.pause()
        presentAsSheet(ExportSheetController(editor: self))
    }

    /// Called by `ExportSheetController` once the save panel has a
    /// destination. The project handle is captured HERE rather than inside
    /// the exporter so the write is of the timeline as it was confirmed —
    /// handles are immutable (spec §5.5), so nothing the document does next
    /// can reach the file.
    ///
    /// `options` is what the export asks of the RECIPE — the timecode burn-in
    /// and nothing else today. It rides beside `settings` rather than inside
    /// it because the two are answered by different halves of the core: the
    /// settings are `rc_export_settings`' reply, and an option smuggled into
    /// the override table would be ignored without a word
    /// (`export_overrides.rs`) and the file reported as a success. The default
    /// is no options at all, so a caller that says nothing exports what it
    /// always did.
    func beginExport(settings: ExportSettings, to url: URL, options: RecipeOptions = .none) {
        guard let document = document else {
            NSSound.beep()
            return
        }
        playback.pause()
        presentAsSheet(
            ExportProgressSheetController(
                project: document.project, urls: document.mediaURLs(), settings: settings,
                to: url, options: options))
    }

    /// Called by `ExportSheetController`'s **Add to Queue** once the save
    /// panel has a destination — `beginExport`'s sibling, and the one place a
    /// queued job is built (road map 2's phase 7e).
    ///
    /// **The project handle AND the media URLs are read HERE, at the moment
    /// the destination is known, and that is the whole of what makes a queued
    /// job immutable.** The handle needs no clone — handles are immutable
    /// (spec §5.5) and every edit and undo makes a new one, so this one keeps
    /// the timeline as it was confirmed however the document changes, and
    /// `Exporter` publishes it on a `RecipeSource` key of its own so even the
    /// frames the compositor serves the write come from it. `mediaURLs()` is
    /// the half that would otherwise leak: it resolves each bookmark and asks
    /// the filesystem whether the file is there, so a job that called it at
    /// RUN time would silently pick up a Relink… or a moved file from after it
    /// was queued — the exact change an immutable job exists to exclude. A job
    /// therefore holds the answer and no document to ask again.
    ///
    /// Playback is NOT paused, unlike `beginExport`: a queued job runs behind
    /// the editor by design, and the person who chose not to wait for it did
    /// not ask for their preview to stop.
    func enqueueExport(settings: ExportSettings, to url: URL, options: RecipeOptions = .none) {
        guard let document = document else {
            NSSound.beep()
            return
        }
        ExportQueueController.shared.enqueue(
            project: document.project, urls: document.mediaURLs(), settings: settings,
            to: url, options: options)
        // Adding to a queue shows the queue: the job has no sheet of its own,
        // so this window is the only thing that says it exists.
        ExportQueueWindowController.shared.show()
    }

    // MARK: - Speed

    /// Clip ▸ Speed…. Only `media` clips can take `set_speed` (spec §6 makes
    /// it an error, not a refusal, on any other kind), so the sheet is opened
    /// on that subset and refused outright when the subset is empty.
    func presentSpeedSheet() {
        let clips = selectedClips.filter { $0.source.hasSourceBound }
        guard let document = document, !clips.isEmpty else {
            NSSound.beep()
            return
        }
        presentAsSheet(SpeedSheetController(document: document, clips: clips.map { $0.id }))
    }

    // MARK: - Missing media

    /// Offers Relink… once per document, when its window first appears
    /// (spec §5.6). Silent — not an alert — when nothing is missing, and it
    /// stands aside for any sheet already up, so an export or a save dialog
    /// is never elbowed out of the way by it.
    func offerRelinkIfNeeded() {
        guard let document = document, !document.missingMedia.isEmpty else { return }
        guard view.window?.attachedSheet == nil else { return }
        guard RelinkSheetController.markOffered(document) else { return }
        presentAsSheet(RelinkSheetController(document: document))
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateExportAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(exportProject(_:)):
            return document.project.duration > 0
        default:
            return nil
        }
    }
}
