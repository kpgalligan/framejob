import AppKit

/// The Synchronizing Audio sheet (road map "audio-sync-2", AS-4; spec §11
/// SY-22): up while `AudioSync.plan` runs on a background queue, so the
/// window never beach-balls on a long take.
///
/// `AudioSync.read` has already run on the main thread (it reads the
/// document); the sheet takes its `Input` — values only, safe to hand to
/// another thread — and runs the pure `plan` off main. While the sheet is
/// attached every editor action validates false
/// (`EditorViewController.validateUserInterfaceItem`), Synchronize Audio
/// included, which is the bargain Reverse and Consolidate strike. When the
/// plan comes back the sheet keeps it and dismisses itself; `finished` is
/// called once, on the main queue's next turn after `viewDidDisappear`, so a
/// Weak match sheet it brings up finds the window free. Cancel
/// dismisses at once and the late plan is dropped: nothing moves.
///
/// **The dev hold** (`-RCDevSyncHold <seconds>`, dev tools only): the run
/// waits that long before `plan`, so a proof can reach the sheet (S25, S26).
final class AudioSyncSheetController: NSViewController {
    /// The dev-only launch default that holds the run (SY-22).
    static let devHoldKey = "RCDevSyncHold"

    private let input: AudioSync.Input
    private let finished: (AudioSync.Plan) -> Void

    private let bar = NSProgressIndicator()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    /// Set in `loadView`; implicitly unwrapped for exactly that reason
    /// (app/CLAUDE.md).
    private var cancelButton: NSButton!
    private var hiddenButton: NSButton!

    private var didStart = false
    private var cancelled = false
    private var answered = false
    private var plan: AudioSync.Plan?

    init(input: AudioSync.Input, finished: @escaping (AudioSync.Plan) -> Void) {
        self.input = input
        self.finished = finished
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AudioSyncSheetController does not support NSCoder")
    }

    override func loadView() {
        bar.style = .bar
        bar.isIndeterminate = true
        bar.usesThreadedAnimation = true
        bar.widthAnchor.constraint(equalToConstant: sheetWidth - sheetInset * 2).isActive = true

        statusLabel.font = DS.sans(12)
        statusLabel.textColor = DS.textMuted
        statusLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2
        statusLabel.stringValue = "Matching the sound of \(input.readings.count) clips…"

        let content = NSStackView(views: [bar, statusLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8

        cancelButton = StickerButton(
            title: "Cancel", style: .secondary, target: self, action: #selector(cancelClicked(_:)))
        // Hidden AND disabled: Return finds no target, so Cancel (Escape) is
        // the only live button, Reverse's pattern.
        hiddenButton = StickerButton(title: "Apply", style: .primary, target: nil, action: nil)
        hiddenButton.isHidden = true
        hiddenButton.isEnabled = false

        view = makeSheetView(
            title: "Synchronizing Audio",
            hint: "Nothing moves until the match is found; Cancel leaves everything as it is.",
            content: content, buttonRow: makeButtonRow(cancel: cancelButton, apply: hiddenButton))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        bar.startAnimation(nil)
        let input = self.input
        var hold = 0.0
        #if FRAMEJOB_DEV_TOOLS
        hold = UserDefaults.standard.double(forKey: Self.devHoldKey)
        #endif
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if hold > 0 { Thread.sleep(forTimeInterval: hold) }
            let plan = AudioSync.plan(input)
            DispatchQueue.main.async {
                guard let self, !self.cancelled else { return }
                self.plan = plan
                self.dismiss(self)
            }
        }
    }

    /// The one hand-back: once, with the plan, and never after Cancel. On
    /// the next turn of the main queue, because while this runs the window
    /// still reports this sheet as attached, and a Weak match sheet asked for
    /// now would find the window taken (measured: S24 got a beep, no sheet).
    override func viewDidDisappear() {
        super.viewDidDisappear()
        bar.stopAnimation(nil)
        guard !answered, !cancelled, let plan else { return }
        answered = true
        let finished = self.finished
        DispatchQueue.main.async { finished(plan) }
    }

    @objc private func cancelClicked(_ sender: Any?) {
        guard !cancelled, plan == nil else { return }
        cancelled = true
        dismiss(self)
    }
}
