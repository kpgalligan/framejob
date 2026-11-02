import AppKit

/// The Analyzing sheet (spec §11 CJ-28; road map "creator-jobs" CJ2b): up
/// while the analysis a menu command plans with is made on this Mac, one row
/// per media whose request missed the cache — its file name, a determinate
/// bar, and "Waiting" until the job's first frame, then "NN %", then "Done".
/// The first command is Clip ▸ Split at Shot Changes (CJ-29); any kind whose
/// result a command plans with comes through here (CO-6 amends it for a
/// render-substituted kind). A tool call shows no sheet and waits.
///
/// **One owner.** The sheet wants every row's request under one lane owner
/// (alive while the document is open; `settled` tells the document its
/// package changed) when it appears, and releases it in `viewDidDisappear` —
/// its ONE release, on every exit: Stop, landing, failure, the window
/// closing. A disappearance with no outcome and no Stop (the window ordered
/// out, as a minimize does) clears `didStart`, so the next `viewDidAppear`
/// wants again what has not landed and restarts the poll. What a job already
/// published stays cached (CJ-21).
///
/// **Polled, not told:** a 0.1 s `Timer` in the `.common` modes reads
/// `AnalysisLane.progress(of:)` and `run(of:)`. When every run has landed, or
/// one failed, the sheet keeps the outcome and dismisses itself; `finished`
/// is called once, on the main queue's next turn after `viewDidDisappear`
/// (`AudioSyncSheetController`'s reason: the window still reports the sheet
/// attached while it disappears). Stop only dismisses and calls nothing, so
/// no edit lands. While the sheet is attached every editor action validates
/// false (`EditorViewController.validateUserInterfaceItem`).
final class AnalyzingSheetController: NSViewController {
    struct Row {
        let name: String
        let request: AnalysisRequest
    }

    enum Outcome {
        case landed
        case failed(name: String, why: String)
    }

    static let pollInterval: TimeInterval = 0.1

    private let document: ProjectDocument
    private let command: String
    private let rows: [Row]
    private let finished: (Outcome) -> Void
    private let lane = AnalysisLane.shared
    private let owner: Int

    private var bars: [NSProgressIndicator] = []
    private var statuses: [NSTextField] = []
    /// Set in `loadView`; implicitly unwrapped for exactly that reason
    /// (app/CLAUDE.md).
    private var stopButton: NSButton!
    private var hiddenButton: NSButton!

    private var timer: Timer?
    private var didStart = false
    private var reappearing = false
    private var answered = false
    private var stopped = false
    private var outcome: Outcome?

    init(
        document: ProjectDocument, command: String, rows: [Row],
        finished: @escaping (Outcome) -> Void
    ) {
        self.document = document
        self.command = command
        self.rows = rows
        self.finished = finished
        owner = AnalysisLane.shared.newOwner()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AnalyzingSheetController does not support NSCoder")
    }

    override func loadView() {
        var views: [NSView] = []
        for row in rows {
            let name = NSTextField(labelWithString: row.name)
            name.font = DS.sans(13)
            name.textColor = DS.textStrong
            name.lineBreakMode = .byTruncatingMiddle
            name.widthAnchor.constraint(lessThanOrEqualToConstant: sheetWidth - sheetInset * 2)
                .isActive = true
            let bar = NSProgressIndicator()
            styleSheetProgressBar(bar)
            let status = NSTextField(labelWithString: "Waiting")
            styleSheetStatusLabel(status)
            bars.append(bar)
            statuses.append(status)
            views += [name, bar, status]
        }
        let content = makeProgressStack(views)

        stopButton = StickerButton(
            title: "Stop", style: .secondary, target: self, action: #selector(stopClicked(_:)))
        hiddenButton = StickerButton(title: command, style: .primary, target: nil, action: nil)
        hideReturnTarget(hiddenButton)

        view = makeSheetView(
            title: "Analyzing",
            hint: "\(command) needs what Frame Job finds in these files on this Mac, kept in the "
                + "project's cache. Nothing changes until it is found; Stop leaves everything as "
                + "it is.",
            content: content, buttonRow: makeButtonRow(cancel: stopButton, apply: hiddenButton))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didStart else { return }
        didStart = true
        let document = self.document
        // Back from being ordered out: a run that landed while this sheet
        // wanted it is not run again. The first want takes every row, since
        // the lane re-runs a request it once landed but the cache missed.
        let wanted = rows.map(\.request).filter {
            guard reappearing, case .landed? = lane.run(of: $0)?.outcome else { return true }
            return false
        }
        lane.want(
            wanted, owner: owner, alive: { document.isOpenForAnalysis },
            settled: { document.packageContentsDidChangeOnDisk() })
        let tick = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        poll()
    }

    /// The sheet's one release of its owner, on every exit, and the one
    /// hand-back: once, with the outcome, never after Stop.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        timer?.invalidate()
        timer = nil
        lane.release(owner: owner)
        if outcome == nil, !stopped {
            didStart = false
            reappearing = true
        }
        guard !answered, !stopped, let outcome else { return }
        answered = true
        let finished = self.finished
        DispatchQueue.main.async { finished(outcome) }
    }

    /// Each row's state from the lane; the outcome once every run landed or
    /// one failed.
    private func poll() {
        guard outcome == nil, !stopped else { return }
        var landed = true
        for (index, row) in rows.enumerated() {
            switch lane.run(of: row.request)?.outcome {
            case .landed?:
                bars[index].doubleValue = 1
                statuses[index].stringValue = "Done"
            case .failed(let why)?:
                settle(.failed(name: row.name, why: why))
                return
            default:
                landed = false
                if let fraction = lane.progress(of: row.request) {
                    bars[index].doubleValue = fraction
                    statuses[index].stringValue = "\(Int((fraction * 100).rounded(.down))) %"
                } else {
                    statuses[index].stringValue = "Waiting"
                }
            }
        }
        if landed { settle(.landed) }
    }

    private func settle(_ outcome: Outcome) {
        self.outcome = outcome
        timer?.invalidate()
        timer = nil
        dismiss(self)
    }

    /// Stop: dismisses, and nothing else — `viewDidDisappear` releases the
    /// owner, and with no outcome nothing is handed back.
    @objc private func stopClicked(_ sender: Any?) {
        guard outcome == nil, !stopped else { return }
        stopped = true
        timer?.invalidate()
        timer = nil
        dismiss(self)
    }
}
