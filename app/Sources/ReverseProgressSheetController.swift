import AppKit

// MARK: - Progress

/// The sheet that stays up while reversed assets are rendered: a bar, the file
/// being reversed, a Cancel that stops within one slice, and the report when
/// it is over.
///
/// **Why a sheet and not a background job with a badge.** A reversed clip that
/// has not been rendered draws a slate, so the timeline is telling the truth
/// but the picture is missing — and a user who ticked Reverse two seconds ago
/// needs to be told that the missing picture is being made, how far along it
/// is, and how to stop it. The sheet is also what stops the timeline moving
/// under a render: every editor action validates false while one is attached
/// (`EditorViewController.validateUserInterfaceItem`), which is the same
/// bargain Export and Consolidate Media strike.
///
/// It owns the run, so the render survives whatever the editor does next — the
/// presenting controller retains the sheet while it is on screen, and nothing
/// else holds the token.
final class ReverseProgressSheetController: NSViewController {
    /// Weak: the sheet is presented BY this document's editor, so a strong
    /// reference would be a cycle for as long as it is up.
    private weak var document: ProjectDocument?
    private let jobs: [ReverseRenderer.Job]
    private let token = ReverseRenderer.CancelToken()

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "Preparing…")
    private let detailLabel = NSTextField(labelWithString: "")
    /// Set in `loadView`; the only implicitly-unwrapped optionals here
    /// (app/CLAUDE.md allows them for exactly this).
    private var stopButton: NSButton!
    private var closeButton: NSButton!

    private var didStart = false
    private var didFinish = false

    init(document: ProjectDocument, jobs: [ReverseRenderer.Job]) {
        self.document = document
        self.jobs = jobs
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReverseProgressSheetController does not support NSCoder")
    }

    override func loadView() {
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.usesThreadedAnimation = true
        bar.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2).isActive = true

        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        statusLabel.stringValue =
            jobs.count == 1
            ? "Rendering a reversed copy of “\(jobs[0].name)”…"
            : "Rendering reversed copies of \(jobs.count) files…"

        detailLabel.font = DS.mono(11)
        detailLabel.textColor = DS.textFaint
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2)
            .isActive = true

        let content = NSStackView(views: [bar, statusLabel, detailLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8

        stopButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(stopClicked(_:)))
        closeButton = StickerButton(
            title: "Close", style: .primary, target: self, action: #selector(closeClicked(_:)))
        // Hidden AND disabled while it runs: AppKit skips both when it looks
        // for the Return key's target, so Cancel is the only live button until
        // there is a result to read.
        closeButton.isHidden = true
        closeButton.isEnabled = false

        view = makeSheetView(
            title: "Reversing", hint: "AVFoundation cannot play a clip backwards, so Reelcut "
                + "renders the reversed frames once and keeps them in the project package.",
            content: content, buttonRow: makeButtonRow(cancel: stopButton, apply: closeButton))
    }

    /// Reversing a SECOND clip while this sheet is up leaves that one queued
    /// and nothing running — `ensureReversedMedia` refuses to stack sheets. So
    /// the document is asked to look again once this one is off the screen,
    /// which is here rather than in `reverseRenderDidFinish` because a sheet
    /// dismissed a moment ago is still `window.attachedSheet` and the next
    /// presentation would be refused for the same reason. Media the user
    /// stopped or that failed is remembered as refused, so this cannot loop.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        document?.ensureReversedMedia()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        let jobs = self.jobs
        let token = self.token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var rendered: [UInt32] = []
            var failures: [String] = []
            var cancelled = false
            for (index, job) in jobs.enumerated() {
                if token.isCancelled {
                    cancelled = true
                    break
                }
                DispatchQueue.main.async { self?.detailLabel.stringValue = job.name }
                let result = ReverseRenderer(job: job).run(
                    cancel: token,
                    progress: { fraction in
                        let overall = (Double(index) + fraction) / Double(jobs.count)
                        DispatchQueue.main.async { self?.progressed(overall) }
                    })
                switch result {
                case .success:
                    rendered.append(job.media)
                case .failure(let error):
                    if case ReverseRenderer.ReverseError.cancelled = error {
                        cancelled = true
                    } else {
                        failures.append("\(job.name): \(error.localizedDescription)")
                    }
                }
                if cancelled { break }
            }
            let outcome = (rendered: rendered, failures: failures, cancelled: cancelled)
            DispatchQueue.main.async { self?.finished(outcome) }
        }
    }

    private func progressed(_ fraction: Double) {
        guard !didFinish else { return }
        bar.doubleValue = min(max(fraction, 0), 1)
    }

    /// The one exit for all three outcomes. The document is told before
    /// anything is said on screen, because it is what republishes the
    /// resolution and makes the preview stop drawing slates.
    private func finished(
        _ outcome: (rendered: [UInt32], failures: [String], cancelled: Bool)
    ) {
        didFinish = true
        document?.reverseRenderDidFinish(
            rendered: outcome.rendered, failures: outcome.failures, cancelled: outcome.cancelled)
        guard !outcome.failures.isEmpty || outcome.cancelled else {
            // Nothing to report and nothing to decide: the picture is back.
            bar.doubleValue = 1
            dismiss(self)
            return
        }
        statusLabel.textColor = DS.textStrong
        statusLabel.stringValue =
            outcome.cancelled
            ? "Stopped. Clips that are still reversed show a slate until their frames are "
                + "rendered — reach the Speed section of the Video tab to try again."
            : "\(outcome.failures.count) file"
                + "\(outcome.failures.count == 1 ? "" : "s") could not be reversed. Those clips "
                + "show a slate rather than play forwards."
        detailLabel.stringValue = outcome.failures.first ?? ""
        stopButton.isHidden = true
        stopButton.isEnabled = false
        closeButton.isHidden = false
        closeButton.isEnabled = true
    }

    /// Cancelling stops inside the current slice and keeps the files already
    /// finished; the ones left over stay pending, and their clips stay slated.
    @objc private func stopClicked(_ sender: Any?) {
        guard !didFinish else { return }
        stopButton.isEnabled = false
        detailLabel.stringValue = "Stopping…"
        token.cancel()
    }

    @objc private func closeClicked(_ sender: Any?) {
        dismiss(self)
    }
}
