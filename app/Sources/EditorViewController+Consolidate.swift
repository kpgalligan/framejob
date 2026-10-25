import AppKit

/// File ▸ Consolidate Media… — the menu half of `MediaConsolidator`, which
/// owns the plan and the copying (and documents the four traps this command
/// walks around).
///
/// The shape is the export's: decide everything up front, put a sheet up, do
/// the work on another queue, and commit through `ProjectDocument` when it is
/// over. Every editor action validates false while a sheet is attached
/// (`EditorViewController.validateUserInterfaceItem`), which is what lets the
/// sheet trust the plan it was handed — the model cannot change under it.
extension EditorViewController {

    /// The menu item. An untitled project has no package to copy into, so
    /// instead of the greyed-out item that would leave the user guessing,
    /// this says so and offers the Save that fixes it.
    func consolidateMediaCommand() {
        guard let document = document, let window = view.window else {
            NSSound.beep()
            return
        }
        guard document.fileURL != nil else {
            offerSaveBeforeConsolidating(document, in: window)
            return
        }
        beginConsolidate(document, in: window)
    }

    private func offerSaveBeforeConsolidating(_ document: ProjectDocument, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Save this project first?"
        alert.informativeText =
            MediaConsolidator.ConsolidateError.untitled.localizedDescription
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            // NSDocument's own save — the Save panel for an untitled
            // document — with the callback that carries on where the user
            // left off. The selector shape is AppKit's, not ours.
            let didSave = #selector(
                EditorViewController.consolidateAfterSave(_:didSave:contextInfo:))
            document.save(withDelegate: self, didSave: didSave, contextInfo: nil)
        }
    }

    /// `save(withDelegate:didSave:contextInfo:)`'s callback. A cancelled
    /// Save panel arrives here with `didSave` false and stops the command,
    /// which is the right answer: there is still no package.
    @objc(consolidateDocument:didSave:contextInfo:)
    func consolidateAfterSave(
        _ saved: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        guard didSave, let document = document, saved === document,
              document.fileURL != nil, let window = view.window
        else { return }
        beginConsolidate(document, in: window)
    }

    private func beginConsolidate(_ document: ProjectDocument, in window: NSWindow) {
        let plan: MediaConsolidator.Plan
        do {
            plan = try MediaConsolidator.plan(for: document)
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }
        guard !plan.isEmpty else {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Nothing to consolidate."
            alert.informativeText =
                plan.missing.isEmpty
                ? "Every file this project uses is already inside the package."
                : "Every file this project can find is already inside the package. "
                    + "\(plan.missing.count) missing file"
                    + "\(plan.missing.count == 1 ? " needs" : "s need") relinking first."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }
        presentAsSheet(ConsolidateProgressSheetController(document: document, plan: plan))
    }

    /// The half of `validateUserInterfaceItem` this file owns. nil means
    /// "not mine" and leaves the other answers alone.
    func validateConsolidateAction(_ action: Selector) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(consolidateMedia(_:)):
            return !document.project.snapshot.media.isEmpty
        default:
            return nil
        }
    }
}

// MARK: - Progress

/// The sheet that stays up for the copying: a bar, the file being copied, a
/// Cancel that really stops between files, and the report when it is over.
///
/// It owns the run, which is why the copy survives whatever the editor does
/// next — the presenting controller retains the sheet for as long as it is
/// on screen, and nothing else holds the token.
///
/// **The queue.** Copying is the one seam this feature adds to the list in
/// app/CLAUDE.md: a library of footage takes long enough that doing it on the
/// main thread would beachball the app for minutes. Only `FileManager` work
/// happens there — the plan was computed on main, and the ops it earns are
/// applied back on main, so no model state is ever touched off it.
final class ConsolidateProgressSheetController: NSViewController {
    /// Weak: the sheet is presented BY this document's editor, so a strong
    /// reference would be a cycle for as long as the sheet is up.
    private weak var document: ProjectDocument?
    private let plan: MediaConsolidator.Plan
    private let token = MediaConsolidator.CancelToken()

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "Preparing…")
    private let detailLabel = NSTextField(labelWithString: "")
    /// Set in `loadView`; the only implicitly-unwrapped optionals here
    /// (app/CLAUDE.md allows them for exactly this).
    private var stopButton: NSButton!
    private var revealButton: NSButton!

    private var didStart = false
    private var didFinish = false

    init(document: ProjectDocument, plan: MediaConsolidator.Plan) {
        self.document = document
        self.plan = plan
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ConsolidateProgressSheetController does not support NSCoder")
    }

    override func loadView() {
        styleSheetProgressBar(bar)

        styleSheetStatusLabel(statusLabel)
        statusLabel.stringValue = summaryOfPlan()

        styleSheetDetailLabel(detailLabel)

        let content = makeProgressStack([bar, statusLabel, detailLabel])

        stopButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(stopClicked(_:)))
        revealButton = StickerButton(
            title: "Show in Finder", style: .primary, target: self,
            action: #selector(revealClicked(_:)))
        hideReturnTarget(revealButton)

        view = makeSheetView(
            title: "Consolidating Media",
            content: content,
            buttonRow: makeButtonRow(cancel: stopButton, apply: revealButton))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        let plan = self.plan
        let token = self.token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = MediaConsolidator.run(
                plan, cancel: token,
                progress: { fraction, name in
                    DispatchQueue.main.async { self?.progressed(fraction, name) }
                })
            DispatchQueue.main.async { self?.finished(outcome) }
        }
    }

    private func summaryOfPlan() -> String {
        let count = plan.copies.count
        let size = ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file)
        guard count > 0 else { return "Relinking \(plan.relinks.count + plan.aliases.count)…" }
        return "Copying \(count) file\(count == 1 ? "" : "s") (\(size)) into the package…"
    }

    // MARK: - Run callbacks

    private func progressed(_ fraction: Double, _ name: String) {
        guard !didFinish else { return }
        bar.doubleValue = min(max(fraction, 0), 1)
        detailLabel.stringValue = name
    }

    /// The one exit for all three outcomes — finished, part-failed and
    /// cancelled. The ops are applied here, on the main thread, through the
    /// grouped entry point: a queue completion is not an AppKit event
    /// (app/CLAUDE.md's undo pitfall).
    private func finished(_ outcome: MediaConsolidator.Outcome) {
        didFinish = true
        bar.doubleValue = 1
        // Unconditionally, and before the ops: a run that failed or was
        // cancelled may still have created `media/` inside the package, and
        // that alone is what makes NSDocument refuse every later save.
        document?.packageContentsDidChangeOnDisk()
        if !outcome.ops.isEmpty, let document = document {
            document.performGroupedEdit("Consolidate Media", outcome.ops)
            document.generateCaches()
        }
        statusLabel.stringValue = outcome.summary
        statusLabel.textColor = DS.textStrong
        detailLabel.stringValue = outcome.failures.first ?? ""
        stopButton.title = "Close"
        stopButton.isEnabled = true
        revealButton.isHidden = false
        revealButton.isEnabled = true
    }

    // MARK: - Buttons

    /// Cancel while it runs, Close once it is over. Cancelling stops between
    /// files and keeps what has already been copied — those files are
    /// relinked, the rest still point at their originals.
    @objc private func stopClicked(_ sender: Any?) {
        guard !didFinish else {
            dismiss(self)
            return
        }
        stopButton.isEnabled = false
        detailLabel.stringValue = "Stopping…"
        token.cancel()
    }

    @objc private func revealClicked(_ sender: Any?) {
        guard didFinish else { return }
        NSWorkspace.shared.activateFileViewerSelecting([plan.directory])
        dismiss(self)
    }
}
