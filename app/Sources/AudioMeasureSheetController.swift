import AppKit

/// The Measuring Sound sheet (road map "audio" AP6, spec §11 AU-65): up
/// while a `LoudnessMeasureRun` renders its clips through their chains
/// (AU-64), so the window never beach-balls on a long clip.
/// `AudioSyncSheetController`'s shape: a bar, "Clip n of N…" and Cancel.
///
/// The run was built on the main thread from what the press read; the sheet
/// starts it when it appears. While the sheet is attached every editor action
/// validates false (`EditorViewController.validateUserInterfaceItem`), the
/// bargain Synchronize Audio strikes. When the outcome comes back the sheet
/// keeps it and dismisses itself; `finished` is called once, on the main
/// queue's next turn after `viewDidDisappear`. Cancel stops the render in
/// flight, releases the run's render wants and dismisses at once: nothing
/// changes.
final class AudioMeasureSheetController: NSViewController {
    private let run: LoudnessMeasureRun
    private let sheetTitle: String
    private let finished: (LoudnessMeasureRun.Outcome) -> Void

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    /// Set in `loadView`; implicitly unwrapped for exactly that reason
    /// (app/CLAUDE.md).
    private var cancelButton: NSButton!
    private var hiddenButton: NSButton!

    private var didStart = false
    private var cancelled = false
    private var answered = false
    private var outcome: LoudnessMeasureRun.Outcome?

    init(
        run: LoudnessMeasureRun, title: String,
        finished: @escaping (LoudnessMeasureRun.Outcome) -> Void
    ) {
        self.run = run
        self.sheetTitle = title
        self.finished = finished
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AudioMeasureSheetController does not support NSCoder")
    }

    override func loadView() {
        styleSheetProgressBar(bar, indeterminate: true)

        styleSheetStatusLabel(statusLabel)
        statusLabel.stringValue = "Measuring the sound through each clip's processing…"

        let content = makeProgressStack([bar, statusLabel])

        cancelButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(cancelClicked(_:)))
        hiddenButton = StickerButton(title: "Apply", style: .primary, target: nil, action: nil)
        hideReturnTarget(hiddenButton)

        view = makeSheetView(
            title: sheetTitle,
            hint: "Nothing changes until every clip is measured; Cancel leaves everything as "
                + "it is.",
            content: content, buttonRow: makeButtonRow(cancel: cancelButton, apply: hiddenButton))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        bar.startAnimation(nil)
        run.progress = { [weak self] clip, count in
            self?.statusLabel.stringValue = "Clip \(clip) of \(count)…"
        }
        run.start { [weak self] outcome in
            guard let self, !self.cancelled else { return }
            guard let outcome else {
                self.cancelled = true
                self.run.finish()
                self.dismiss(self)
                return
            }
            self.outcome = outcome
            self.dismiss(self)
        }
    }

    /// The one hand-back: once, with the outcome, and never after Cancel. On
    /// the next turn of the main queue, because while this runs the window
    /// still reports this sheet as attached.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        bar.stopAnimation(nil)
        guard !answered, !cancelled, let outcome else { return }
        answered = true
        let finished = self.finished
        DispatchQueue.main.async { finished(outcome) }
    }

    @objc private func cancelClicked(_ sender: Any?) {
        guard !cancelled, outcome == nil else { return }
        cancelled = true
        run.cancel()
        run.finish()
        dismiss(self)
    }
}
