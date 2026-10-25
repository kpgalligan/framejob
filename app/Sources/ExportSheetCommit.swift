import AppKit
import UniformTypeIdentifiers

/// The export card's two commits, Export… and Add to Queue, which end in a save panel and hand
/// the resolved settings to the editor: `commit(queue:)` with the three button actions that
/// reach it, `recipeOptions`, `suggestedName` and `panelMessage`. An extension of
/// `ExportSheetController` in a file of its own, a pure move out of the controller before the
/// HDR road map's export range (hdr H-0).
extension ExportSheetController {
    // MARK: - Commit

    @objc func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// Export… — write it now, behind a progress sheet.
    @objc func exportClicked(_ sender: Any?) {
        commit(queue: false)
    }

    /// Add to Queue — write it later, behind nothing. The SAME commit, in one
    /// method, so the buttons cannot drift (road map 2's phase 7e).
    @objc func queueClicked(_ sender: Any?) {
        commit(queue: true)
    }

    /// Hands off to the save panel, then to `EditorViewController`'s
    /// `beginExport` — or, for Add to Queue, its `enqueueExport`. The settings
    /// are captured BEFORE the dismissal: after it this controller's window is
    /// gone and its controls are on their way out of the view tree. Everything
    /// above the handoff is the same for both buttons and is written once for
    /// that reason: a queued job is not a second kind of export, it is this
    /// one held until its turn.
    private func commit(queue: Bool) {
        // End any edit in a Custom field first. A mouse click on a button
        // does not take the first responder from a text field, so the value
        // typed there has not been committed — `controlTextDidEndEditing`,
        // and the resolve it runs, fire only when the field editor resigns —
        // and `resolved` still describes the size from BEFORE the edit.
        // Handing the first responder to nobody makes it resign now,
        // synchronously, so the read below sees the numbers on screen. A
        // field whose text its formatter rejects refuses to resign; that is
        // the person's to fix, so the click just beeps.
        guard endSheetFieldEditing() else { return }
        guard let editor = editor, let settings = resolved,
              let window = editor.view.window
        else {
            NSSound.beep()
            return
        }
        // Read while the controls still exist. `recipeOptions` is not part of
        // `settings` and never can be: the burn-in changes the PICTURE, so it
        // travels with the description of the picture rather than through the
        // override table, which drops a key it does not know without a word
        // (`RecipeOptions`).
        let options = recipeOptions
        // Remembered on the COMMIT and not on the dismissal: a card somebody
        // opened, fiddled with and cancelled is not a choice they made — and
        // queueing a job is as much a choice as exporting one, so both
        // buttons record it.
        currentChoice.remember()
        let name = suggestedName(for: settings, in: editor)
        dismiss(self)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = Self.panelMessage(for: settings)
        if let type = Exporter.contentType(for: settings) {
            panel.allowedContentTypes = [type]
        }
        // AppKit queues this behind the sheet that is on its way out, so the
        // panel appears once the settings card has finished leaving.
        panel.beginSheetModal(for: window) { [weak editor] response in
            guard response == .OK, let url = panel.url, let editor = editor else { return }
            // The handoff, and the only place the two buttons differ. The
            // project and its media are read on the far side of it, at the
            // moment the destination is known — which for a queued job is the
            // whole of what makes it immutable (`ExportQueueController`).
            if queue {
                editor.enqueueExport(settings: settings, to: url, options: options)
            } else {
                editor.beginExport(settings: settings, to: url, options: options)
            }
        }
    }

    /// What the card asks of the RECIPE rather than of the export settings —
    /// today, the burn-in and nothing else.
    var recipeOptions: RecipeOptions {
        RecipeOptions(burnInTimecode: burnInCheckbox.state == .on)
    }

    /// The document's name with the container's extension: `displayStem`, the
    /// title with the package's own extension off and NOTHING else off, so
    /// "Board v1.2" is `Board v1.2.mp4` (`ProjectDocument+DisplayStem.swift`).
    private func suggestedName(for settings: ExportSettings, in editor: EditorViewController)
        -> String
    {
        let stem = editor.document?.displayStem ?? ProjectDocument.untitledDisplayName
        return stem + "." + Exporter.fileExtension(for: settings)
    }

    /// The save panel's one line about what is being written. "As a movie"
    /// was wrong for half the table: a GIF or an APNG is an animated image
    /// and the audio-only row writes no picture at all. The classes are the
    /// sheet's own (`Applies`, `isFrameSequence`), so a format that is
    /// neither is a movie by the same reading that gave it a Size popup.
    private static func panelMessage(for settings: ExportSettings) -> String {
        if settings.isAudioOnly { return "Export the timeline's audio." }
        if isFrameSequence(container: settings.container) {
            return "Export the timeline as an animated \(settings.container.uppercased())."
        }
        return "Export the timeline as a movie."
    }
}
