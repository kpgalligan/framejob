import AppKit

/// The sheet that stays up for the write itself: a bar, a Cancel that really
/// stops the session, and — once the file lands — the result and a Show in
/// Finder (spec §10 step 10).
///
/// It owns the `Exporter`, which is why the export survives everything the
/// editor does next: the sheet is retained by the presenting controller for
/// as long as it is on screen, and nothing else holds the session.
///
/// Its own file rather than the foot of `ExportSheetController.swift`, which
/// stood at 1114 lines against app/CLAUDE.md's ~600 cap. The seam is where
/// the two sheets stop having anything in common: the settings card is a
/// conversation with the core — every number it shows comes back from
/// `rc_export_settings`, and its controls only decide what to ask for — and
/// this one has already finished asking. It holds a project handle, a URL and
/// an `Exporter`, watches one number climb, and turns into its own result
/// panel; nothing on it can change what is being written.
///
/// Being a separate CLASS is what makes the cut free. `private` on an
/// extension member reaches only its own file, so splitting a type across
/// files costs every crossing member its privacy — the price
/// `ExporterLoudness.swift` records paying, and the price the two `extension
/// ExportSheetController` files beside this one pay. A type carries its own
/// scope, so every member below keeps the visibility it had, and
/// `EditorViewController+Export.swift` presenting it is the only name that
/// crosses.
final class ExportProgressSheetController: NSViewController {
    private let exporter = Exporter()
    /// The project handle as the export was confirmed. Handles are immutable
    /// (spec §5.5), so edits made after this point cannot reach the file.
    private let project: ReelProject
    private let urls: [UInt32: URL]
    private let settings: ExportSettings
    private let destination: URL
    /// What the export asks of the RECIPE rather than of the settings — the
    /// timecode burn-in (spec §7.3, road map 2's phase 7). It is a separate
    /// argument because it is a separate question: `ExportSettings` is what
    /// `rc_export_settings` resolved, and an option posted through the
    /// override table would be dropped in silence and the file reported a
    /// success. Defaulted, so a caller that does not burn in is written the
    /// way it always was.
    private let options: RecipeOptions
    /// The document's compiled graphics as the export was confirmed (G-13),
    /// pinned by `Exporter.export` for the write.
    private let graphics: GraphicSet?

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "Preparing…")
    private let percentLabel = NSTextField(labelWithString: "0 %")
    /// Set in `loadView`; the only implicitly-unwrapped optionals the file has
    /// (app/CLAUDE.md allows them for exactly this).
    private var stopButton: NSButton!
    private var revealButton: NSButton!

    private var didStart = false
    private var didFinish = false
    /// This export's booking in the encoder ledger (spec §11 CX-18): counted, never held —
    /// a person who chose Export… asked to write now. nil on an AVFoundation row and once
    /// it is over.
    private var ledgerToken: UInt64?

    init(
        project: ReelProject, urls: [UInt32: URL], settings: ExportSettings, to url: URL,
        options: RecipeOptions = .none, graphics: GraphicSet? = nil
    ) {
        self.project = project
        self.urls = urls
        self.settings = settings
        self.destination = url
        self.options = options
        self.graphics = graphics
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportProgressSheetController does not support NSCoder")
    }

    deinit {
        let token = ledgerToken
        ledgerToken = nil
        ExportEncoderLedger.shared.end(token)
    }

    override func loadView() {
        styleSheetProgressBar(bar)

        styleSheetStatusLabel(statusLabel)
        statusLabel.stringValue = "Preparing “\(destination.lastPathComponent)”…"

        percentLabel.font = DS.mono(11)
        percentLabel.textColor = DS.textFaint

        let content = makeProgressStack([bar, statusLabel, percentLabel])

        stopButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(stopClicked(_:)))
        revealButton = StickerButton(
            title: "Show in Finder", style: .primary, target: self,
            action: #selector(revealClicked(_:)))
        hideReturnTarget(revealButton)

        view = makeSheetView(
            title: "Exporting",
            content: content,
            buttonRow: makeButtonRow(cancel: stopButton, apply: revealButton))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        // Booked BEFORE `export`, whose early refusals finish synchronously inside it.
        ledgerToken = ExportEncoderLedger.shared.begin(settings)
        exporter.export(
            project: project, urls: urls, settings: settings, to: destination, options: options,
            graphics: graphics,
            progress: { [weak self] value in self?.progressed(value) },
            completion: { [weak self] result in self?.finished(result) })
    }

    // MARK: - Exporter callbacks

    private func progressed(_ value: Double) {
        guard !didFinish else { return }
        let clamped = min(max(value, 0), 1)
        bar.doubleValue = clamped
        percentLabel.stringValue = "\(Int((clamped * 100).rounded())) %"
        // The exporter names its own phase while it has one. Without this the
        // label would claim to be writing a file during the loudness
        // measurement — which on an audio-only export is half the wait, and
        // the half where nothing is on disk yet.
        if let phase = exporter.phaseDescription {
            statusLabel.stringValue = phase
        } else if clamped > 0 {
            statusLabel.stringValue = "Writing “\(destination.lastPathComponent)”…"
        }
    }

    /// The one exit for all three outcomes. Cancelling closes the sheet and
    /// removes the half-written file; success and failure both turn the sheet
    /// into its own result panel rather than trading it for an alert.
    private func finished(_ result: Result<URL, any Error>) {
        didFinish = true
        // Cleared before `end`, whose post may launch a held queue job.
        let token = ledgerToken
        ledgerToken = nil
        ExportEncoderLedger.shared.end(token)
        stopButton.isEnabled = true
        switch result {
        case .success(let url):
            bar.doubleValue = 1
            percentLabel.stringValue = "100 %"
            // What the file actually holds, normalised or not: the export
            // measured its own mix on the way through, so the numbers are a
            // report rather than a promise.
            let measured = exporter.loudnessReport.map { " \($0.summary)." } ?? ""
            // What the graphics warned while the file was drawn: a count on
            // the line, the list in its tooltip (G-24 (c)).
            let warnings = exporter.graphicWarnings
            statusLabel.stringValue = "Exported “\(url.lastPathComponent)”.\(measured)"
                + Exporter.graphicWarningSuffix(warnings)
            statusLabel.toolTip = Exporter.graphicWarningDetails(warnings)
            statusLabel.textColor = DS.textStrong
            stopButton.title = "Close"
            revealButton.isHidden = false
            revealButton.isEnabled = true
        case .failure(let error):
            if case Exporter.ExportError.cancelled = error {
                try? FileManager.default.removeItem(at: destination)
                dismiss(self)
                return
            }
            bar.doubleValue = 0
            percentLabel.stringValue = ""
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = DS.textStrong
            stopButton.title = "Close"
        }
    }

    // MARK: - Buttons

    /// Cancel while it runs, Close once it is over. One button because there
    /// is only ever one thing to do with a sheet that is busy.
    @objc private func stopClicked(_ sender: Any?) {
        guard !didFinish else {
            dismiss(self)
            return
        }
        stopButton.isEnabled = false
        statusLabel.stringValue = "Stopping…"
        exporter.cancel()
    }

    @objc private func revealClicked(_ sender: Any?) {
        guard didFinish else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        dismiss(self)
    }
}
