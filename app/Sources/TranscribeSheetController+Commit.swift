import AppKit

// MARK: - Sheet: the commit and the command

/// The run's one exit and the menu command that opens the sheet: `finish`,
/// the single place all four outcomes land (`summary` is the sentence it
/// writes), `viewDidDisappear`, which cancels a
/// run the sheet is dismissed out from under, and File ▸ Generate
/// Captions… itself with the validator arm that greys it.
///
/// A pure move out of `TranscribeSheetController.swift`, road map 6's C1
/// toll 3. Both blocks came here whole and in their own order, with every
/// line byte-identical. One widening in the move — `finish` is internal
/// rather than `private`, which the compiler forces, since `begin` stayed
/// behind and calls it — and nine in the file it left, the stored
/// properties `finish` and `viewDidDisappear` read. `summary` stays
/// `private`: only `finish` calls it, and it moved with it. W2 deleted
/// `truncationText` with the ceiling it reported (spec §11 W-8).
///
/// **c1-chrome added the cloud engine's three lines** (road map 6 §5e), and
/// it is no longer only a move. `cloudReportLines` turns the run's `Report`
/// into what the card says beside today's counts — R6-8's fallback, the
/// language that was DETECTED and how sure the service was, and any media
/// whose remote delete is still owed. They are added in BOTH arms: a run
/// that failed can still have uploaded one media and owe a delete for it,
/// and a card that printed only the error would lose the one record a
/// person has of that.
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

        let cloudLines = cloudReport.map {
            Self.cloudReportLines($0, names: mediaNames, detected: cloudDetected)
        } ?? []
        let result: Transcriber.Outcome
        switch outcome {
        case .failure(let error):
            statusLabel.stringValue = ([error.localizedDescription] + cloudLines)
                .joined(separator: "\n")
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
            let replacing = replaceExisting
                ? CaptionLayout.replaceableTracks(
                    in: document.editedProject.snapshot, jobs: jobs(in: scope))
                : []
            plan = try CaptionLayout.place(
                result.cues, problems: result.problems, in: document.editedProject,
                style: style, replacing: replacing)
        } catch {
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = DS.textStrong
            return
        }
        document.performGroupedEdit("Generate Captions", plan.ops)

        // A clean run has nothing to say that the timeline does not already
        // show, so it leaves rather than making the user dismiss a receipt.
        guard plan.report.isEmpty, cloudLines.isEmpty else {
            statusLabel.stringValue =
                ([summary(plan), plan.report] + cloudLines)
                .filter { !$0.isEmpty }.joined(separator: "\n")
            statusLabel.textColor = DS.textStrong
            return
        }
        dismiss(self)
    }

    /// The media names this sheet opened with, by id — the report card names
    /// FILES, because a person chose files and an id is the tool's
    /// vocabulary.
    private var mediaNames: [UInt32: String] {
        var out: [UInt32: String] = [:]
        for entry in snapshot.media { out[entry.id] = entry.name }
        return out
    }

    /// The cloud run's extra lines, in a fixed order: R6-8's fallback, the
    /// detected language, what is still owed a delete, then any fetched
    /// transcript that could not be kept for reuse.
    ///
    /// The owed list is `Report.deletionWarnings`'s rule: once per media
    /// id, because a media can be in `janitorFailed` (an id owed from an
    /// earlier run) AND in `uploaded` with `remoteDeleted` false (one owed
    /// from this run), and saying it twice would read as two transcripts. A
    /// media R6-11 HELD gets one more clause, because "it will be retried"
    /// is only half of what happened to it.
    static func cloudReportLines(
        _ report: CloudTranscriber.Report, names: [UInt32: String], detected: Bool
    ) -> [String] {
        func name(_ id: UInt32) -> String { names[id] ?? "media \(id)" }
        var lines: [String] = []
        let preferred = TranscriptOptions.shippedModels.first ?? "universal-3-5-pro"
        for row in report.uploaded {
            guard let model = row.speechModelUsed, model != preferred else { continue }
            lines.append(
                "“\(name(row.media))” was transcribed with \(model), not \(preferred).")
        }
        if detected {
            for row in report.uploaded {
                guard let code = row.languageCode else { continue }
                let spoken = AssemblyAILanguages.entry(code: code)?.displayName ?? code
                guard let confidence = row.languageConfidence else {
                    lines.append("“\(name(row.media))”: detected \(spoken).")
                    continue
                }
                let percent = Int((min(max(confidence, 0), 1) * 100).rounded())
                lines.append(
                    "“\(name(row.media))”: detected \(spoken) (\(percent)% confidence).")
            }
        }
        lines.append(contentsOf: report.deletionWarnings { "“\(name($0))”" })
        lines.append(contentsOf: report.cacheWarnings { "“\(name($0))”" })
        return lines
    }

    private func summary(_ plan: CaptionLayout.Plan) -> String {
        "\(plan.clips) caption\(plan.clips == 1 ? "" : "s") added"
            + (plan.trackName.map { " on “\($0)”." } ?? ".")
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
