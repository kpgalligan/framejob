import AppKit

// MARK: - Sheet: the commit and the command

/// The run's one exit and the menu command that opens the sheet: `finish`,
/// the single place all four outcomes land (`summary` and `truncationText`
/// are the two sentences it writes), `viewDidDisappear`, which cancels a
/// run the sheet is dismissed out from under, and File ▸ Generate
/// Captions… itself with the validator arm that greys it.
///
/// A pure move out of `TranscribeSheetController.swift`, road map 6's C1
/// toll 3. Both blocks came here whole and in their own order, with every
/// line byte-identical. One widening in the move — `finish` is internal
/// rather than `private`, which the compiler forces, since `begin` stayed
/// behind and calls it — and nine in the file it left, the stored
/// properties `finish` and `viewDidDisappear` read. `summary` and
/// `truncationText` stay `private`: only `finish` calls them, and it
/// moved with them.
extension TranscribeSheetController {

    // MARK: - Commit

    /// The one exit for all four outcomes — finished, finished with something
    /// to say, failed and cancelled.
    ///
    /// The plan is built HERE, against the document's CURRENT handle, not
    /// against the snapshot this sheet opened with: recognition is minutes
    /// long and an agent can edit a document while a sheet is up, and
    /// `CaptionLayout.place` reads ids off a probe of the handle it is given.
    /// The commit goes through `performGroupedEdit` because a queue completion
    /// is not an AppKit event — the road map says `applyEdit` here, and
    /// following it would silently merge the captions into whatever edit came
    /// before them (app/CLAUDE.md's undo pitfall).
    func finish(_ outcome: Result<Transcriber.Outcome, any Error>) {
        guard !didFinish else { return }
        didFinish = true
        bar.doubleValue = 1
        stopButton.title = "Close"
        stopButton.isEnabled = true
        detailLabel.stringValue = ""

        let result: Transcriber.Outcome
        switch outcome {
        case .failure(let error):
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = DS.textStrong
            return
        case .success(let value):
            result = value
        }
        guard let document = document else {
            statusLabel.stringValue = "The project closed before the captions could be placed."
            return
        }
        let plan: CaptionLayout.Plan
        do {
            plan = try CaptionLayout.place(
                result.cues, problems: result.problems, in: document.editedProject)
        } catch {
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = DS.textStrong
            return
        }
        document.performGroupedEdit("Generate Captions", plan.ops)

        // A clean run has nothing to say that the timeline does not already
        // show, so it leaves rather than making the user dismiss a receipt.
        guard plan.report.isEmpty, result.truncations.isEmpty else {
            statusLabel.stringValue = [summary(plan), truncationText(result), plan.report]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            statusLabel.textColor = DS.textStrong
            return
        }
        dismiss(self)
    }

    private func summary(_ plan: CaptionLayout.Plan) -> String {
        "\(plan.clips) caption\(plan.clips == 1 ? "" : "s") added"
            + (plan.trackName.map { " on “\($0)”." } ?? ".")
    }

    /// The one-minute ceiling, in words. Never left unsaid: a caption run that
    /// stopped at sixty seconds and reported success is the failure this
    /// sentence exists to prevent.
    private func truncationText(_ outcome: Transcriber.Outcome) -> String {
        guard !outcome.truncations.isEmpty else { return "" }
        let fps = snapshot.canvas.fps
        let listed = outcome.truncations.prefix(3).map { entry in
            "clip \(entry.clip) stopped at "
                + ReelTime.format(entry.stoppedAt, fps: fps, frames: false)
        }.joined(separator: ", ")
        let count = outcome.truncations.count
        return "Recognition stopped early on \(count) clip\(count == 1 ? "" : "s") — \(listed). "
            + "macOS stops a speech task after about a minute; split the clip and run it again "
            + "to caption the rest."
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        // A sheet that goes away mid-run must not leave a recognition holding
        // a temporary file and somebody's compute.
        if didStart, !didFinish { token.cancel() }
    }
}

// MARK: - The menu command

/// The command half, at the foot of the file that owns the feature —
/// `CaptionImporter.swift`'s precedent, which keeps File ▸ Import Captions…
/// beside the importer it opens.
extension EditorViewController {

    /// File ▸ Generate Captions… — the body of the frozen file's one-line
    /// `@objc func generateCaptions(_:)` forward.
    ///
    /// The refusal happens HERE rather than in the sheet, so a dialog whose
    /// only possible answer is "there is nothing with speech in it" never
    /// opens — `removeSilencesCommand`'s rule.
    func generateCaptionsCommand() {
        guard let document = document, view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        guard Transcriber.hasTranscribableClip(in: document.editedProject.snapshot) else {
            NSSound.beep()
            return
        }
        // Recognition is minutes of somebody else's compute and the sheet is
        // up for all of it; a playhead running under it buys nothing.
        playback.pause()
        presentAsSheet(TranscribeSheetController(document: document))
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateTranscribeAction(_ action: Selector) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(EditorViewController.generateCaptions(_:)):
            return Transcriber.hasTranscribableClip(in: document.editedProject.snapshot)
        default:
            return nil
        }
    }
}
