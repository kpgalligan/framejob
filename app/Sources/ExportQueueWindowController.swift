import AppKit

/// Window ▸ Export Queue — the queue's one window, and a READER of
/// `ExportQueueController` rather than the owner of anything.
///
/// It holds no job, starts nothing and stops nothing on its own: every button
/// here calls a method on the controller and then waits to be told what
/// happened, like every other view in this app. Closing the window does not
/// touch a running export, which is the whole point of a queue — the work
/// outlives the window that was watching it, and reopening from the menu finds
/// it where it was.
///
/// **It is deliberately not `WelcomeWindowController` with the words changed**,
/// and two of that class's decisions are exactly wrong here. It observes
/// `NSWindow.didBecomeMainNotification` and CLOSES itself as soon as any
/// document window becomes main — right for a welcome screen, and for a queue
/// it would mean the window vanishing the instant the person clicked back into
/// the editor, which is the first thing they will do after queueing a job. And
/// its window is deliberately not resizable, because its content is one fixed
/// lockup; this one is a LIST whose length is the user's business.
///
/// **`isExcludedFromWindowsMenu` is load-bearing.** `NSApp.windowsMenu` is set
/// (`AppDelegate.buildMainMenu`), so AppKit adds an entry for every window it
/// can see, titled after the window — and the Window menu would then carry
/// "Export Queue" twice, once as the item that opens it and once as AppKit's
/// own row that raises it.
final class ExportQueueWindowController: NSWindowController {
    static let shared = ExportQueueWindowController()

    /// The app's queue. Read, never replaced — a probe drives its own
    /// controller and never comes near this class.
    private let queue = ExportQueueController.shared

    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private var clearButton: NSButton!
    private var cancelAllButton: NSButton!

    /// The row views by job id, and the order they are in. The list is rebuilt
    /// only when the ids CHANGE: a change notification arrives ten times a
    /// second while an export runs, and rebuilding a view tree at that rate
    /// would rip the button out from under the pointer that is about to press
    /// it.
    private var rows: [UInt64: ExportQueueRowView] = [:]
    private var rowOrder: [UInt64] = []

    static let rowHeight: CGFloat = 52
    private static let inset: CGFloat = 16

    private init() {
        let size = NSSize(width: 560, height: 320)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Export Queue"
        window.minSize = NSSize(width: 460, height: 220)
        // See the type doc: without this the Window menu lists the queue
        // twice.
        window.isExcludedFromWindowsMenu = true
        // The controller owns the window for the life of the process, so
        // closing it must not release it. `NSWindowController` sets this for
        // a window it loads from a nib; one handed to it in code says so
        // itself.
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list

        emptyLabel.stringValue =
            "Nothing queued. The Export card's Add to Queue button puts a confirmed export "
            + "here instead of waiting for it, and they run one at a time while you keep "
            + "editing."
        emptyLabel.font = DS.sans(13)
        emptyLabel.textColor = DS.textMuted
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.preferredMaxLayoutWidth = size.width - Self.inset * 4

        summaryLabel.font = DS.mono(11)
        summaryLabel.textColor = DS.textFaint
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clearButton = StickerButton(
            title: "Clear Finished", style: .secondary, target: self,
            action: #selector(clearFinishedClicked(_:)))
        cancelAllButton = StickerButton(
            title: "Cancel All", style: .secondary, target: self,
            action: #selector(cancelAllClicked(_:)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let buttons = NSStackView(views: [summaryLabel, spacer, clearButton, cancelAllButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.addSubview(scroll)
        root.addSubview(emptyLabel)
        root.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.inset),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.inset),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.inset),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            // The house list shape (`RelinkSheetController`): the document
            // view's width is the clip view's, its top is the clip view's, and
            // nothing fixes its height — so the rows do.
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(
                lessThanOrEqualTo: scroll.widthAnchor, constant: -Self.inset * 2),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.inset),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.inset),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.inset),
        ])
        window.contentView = root
        applyBackground()

        NotificationCenter.default.addObserver(
            self, selector: #selector(queueChanged(_:)),
            name: ExportQueueController.didChangeNotification, object: queue)
        // The three ways this window comes back on screen without anybody
        // calling `show()`. See `queueChanged` for why one is not enough.
        NotificationCenter.default.addObserver(
            self, selector: #selector(cameBack(_:)),
            name: NSWindow.didDeminiaturizeNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(cameBack(_:)),
            name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(cameBack(_:)),
            name: NSApplication.didUnhideNotification, object: nil)
        sync()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportQueueWindowController does not support NSCoder")
    }

    private func applyBackground() {
        window?.backgroundColor = DS.chromeBackground
        window?.contentView?.layer?.backgroundColor = DS.chromeBackground.cgColor
    }

    /// Window ▸ Export Queue, and what `EditorViewController.enqueueExport`
    /// calls so that adding a job shows the thing it was added to.
    func show() {
        applyBackground()
        sync()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Painting

    /// Only while the window is on screen. A closed queue window still gets
    /// every notification — the observer is installed for the life of the
    /// process — and laying out rows nobody can see ten times a second is work
    /// for no one.
    ///
    /// **Skipping is only safe because everything that puts the window back on
    /// screen syncs**, and `show()` was not everything. `isVisible` is false
    /// for a MINIATURIZED window and for every window of a HIDDEN app (⌘H
    /// orders them out), and neither deminiaturizing nor unhiding goes through
    /// `show()` — so a job that finished while the queue was in the Dock left
    /// the window painting `Writing · 41 %` for good, with a button reading
    /// Cancel over a job that was done, Cancel All enabled with nothing to
    /// cancel, Clear Finished disabled over finished rows and Show hidden over
    /// a file that had landed. Once the queue goes idle there is no further
    /// notification to repair any of it. `cameBack` is the repair, and it is
    /// three notifications rather than one because there are three ways back.
    @objc private func queueChanged(_ note: Notification) {
        guard window?.isVisible == true else { return }
        sync()
    }

    /// The window is on screen again after a spell where notifications were
    /// dropped. Unconditional and idempotent: `sync` rebuilds only when the
    /// job IDS have changed, so paying for it on every key change is cheaper
    /// than tracking whether anything was missed.
    @objc private func cameBack(_ note: Notification) {
        sync()
    }

    private func sync() {
        let jobs = queue.jobs
        let ids = jobs.map { $0.id }
        if ids != rowOrder { rebuild(jobs) }
        for job in jobs { rows[job.id]?.update(job) }

        emptyLabel.isHidden = !jobs.isEmpty
        let finished = jobs.filter { $0.state.isFinished }.count
        clearButton.isEnabled = finished > 0
        cancelAllButton.isEnabled = !queue.isIdle
        summaryLabel.stringValue = Self.summary(
            running: queue.runningJob != nil, waiting: queue.waitingCount, finished: finished)
    }

    /// The one line under the list. Written from the counts rather than from
    /// the rows, so it says the same thing a script reading the controller
    /// would.
    private static func summary(running: Bool, waiting: Int, finished: Int) -> String {
        if !running && waiting == 0 && finished == 0 { return "" }
        var parts: [String] = []
        if running { parts.append("1 exporting") }
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if finished > 0 { parts.append("\(finished) finished") }
        return parts.joined(separator: " · ")
    }

    private func rebuild(_ jobs: [ExportQueueController.Job]) {
        for view in list.arrangedSubviews {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rows = [:]
        rowOrder = jobs.map { $0.id }
        for job in jobs {
            let row = ExportQueueRowView(job: job, owner: self)
            rows[job.id] = row
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
    }

    // MARK: - Buttons

    /// A row's one button, in whichever of its two meanings it is showing.
    /// Both go through the controller, which is the only thing that knows
    /// whether a job can be stopped or dropped.
    func act(on id: UInt64) {
        guard let job = queue.job(id) else { return }
        if job.state.isFinished {
            queue.remove(id)
        } else {
            queue.cancel(id)
        }
    }

    /// Shows the finished file in the Finder — the progress sheet's Show in
    /// Finder, on a row.
    ///
    /// The file is checked for rather than assumed: a completed row is a
    /// record of what this app wrote, and the Finder is free to have moved or
    /// deleted it since. `activateFileViewerSelecting` on a path that is gone
    /// opens the enclosing folder with nothing selected, which reads as the
    /// button having worked.
    func reveal(_ id: UInt64) {
        guard let job = queue.job(id), job.state == .completed, !job.superseded,
            FileManager.default.fileExists(atPath: job.destination.path)
        else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([job.destination])
    }

    @objc private func clearFinishedClicked(_ sender: Any?) {
        queue.clearFinished()
    }

    @objc private func cancelAllClicked(_ sender: Any?) {
        queue.cancelAll()
    }
}

// MARK: - A row

/// One job: what it is writing, where it has got to, and the one button that
/// applies to it — Cancel while there is something to stop, Remove once there
/// is not.
///
/// `RelinkRowView`'s shape, which is the house list row: a text column that
/// gives way under pressure, a control at the trailing edge that does not, and
/// a hairline drawn along the bottom.
final class ExportQueueRowView: NSView {
    private let id: UInt64
    private weak var owner: ExportQueueWindowController?
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let revealButton: NSButton
    private let button: NSButton

    init(job: ExportQueueController.Job, owner: ExportQueueWindowController) {
        self.id = job.id
        self.owner = owner
        // Target and action are set below: `self` does not exist yet here.
        self.revealButton = StickerButton(
            title: "Show", style: .secondary, target: nil, action: nil)
        self.button = StickerButton(title: "Cancel", style: .secondary, target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = DS.sans(13, weight: .semibold)
        nameLabel.textColor = DS.textStrong
        nameLabel.lineBreakMode = .byTruncatingMiddle

        statusLabel.font = DS.mono(10)
        statusLabel.textColor = DS.textFaint
        statusLabel.lineBreakMode = .byTruncatingTail

        // A label resists compression by default, which would push the button
        // off the row instead of shortening the sentence.
        for label in [nameLabel, statusLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true

        revealButton.target = self
        revealButton.action = #selector(revealClicked(_:))
        revealButton.isHidden = true
        button.target = self
        button.action = #selector(buttonClicked(_:))

        let text = NSStackView(views: [nameLabel, statusLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        // The trailing controls are a STACK and not three pinned views,
        // because two of the three come and go: an `NSStackView` drops a
        // hidden arranged subview out of its layout, so the bar's 110 points
        // and Show's width are reclaimed by the name rather than left as a
        // hole. Raw constraints would keep both gaps whatever `isHidden` said.
        let controls = NSStackView(views: [bar, revealButton, button])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        addSubview(controls)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: ExportQueueWindowController.rowHeight),
            text.leadingAnchor.constraint(equalTo: leadingAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(
                lessThanOrEqualTo: controls.leadingAnchor, constant: -10),
            bar.widthAnchor.constraint(equalToConstant: 110),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update(job)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportQueueRowView does not support NSCoder")
    }

    /// Repaints from the job. Called on every change notification, so it must
    /// be cheap and must not rebuild anything.
    func update(_ job: ExportQueueController.Job) {
        nameLabel.stringValue = job.name
        statusLabel.stringValue = Self.status(job)
        toolTip = Self.toolTip(for: job)
        bar.isHidden = job.state != .running
        bar.doubleValue = job.progress
        // The progress sheet's two buttons, on a row: Cancel while there is
        // something to stop and Remove once there is not, with Show in Finder
        // beside it for a file that actually landed.
        button.title = job.state.isFinished ? "Remove" : "Cancel"
        revealButton.isHidden = job.state != .completed || job.superseded
    }

    /// The full path and what the file will be — the row is narrow and the
    /// name alone cannot say which of two exports of one project this is —
    /// then the memory hold's whole sentence while a job waits on it (the status label
    /// truncates its tail, so the row alone may cut it short; CX-18), then each graphic
    /// warning a completed job gave, one per line.
    static func toolTip(for job: ExportQueueController.Job) -> String {
        var tip =
            job.destination.path + "\n"
            + "\(job.settings.container.uppercased()) · \(job.settings.width) × "
            + "\(job.settings.height) · \(job.settings.fps.displayName) fps"
        if job.state == .waiting, let held = job.message { tip += "\n" + held }
        return Exporter.graphicWarningDetails(job.graphicWarnings).map { tip + "\n" + $0 } ?? tip
    }

    /// The row's status line; internal so a probe reads it (CX-18).
    static func status(_ job: ExportQueueController.Job) -> String {
        switch job.state {
        case .waiting:
            // The memory hold's sentence when the encoder ledger holds it (CX-18).
            return job.message ?? "Waiting"
        case .running:
            // A message set mid-flight ("Stopping…") is the person's own
            // request and outranks the percentage they stopped watching.
            if let message = job.message { return message }
            let percent = Int((min(max(job.progress, 0), 1) * 100).rounded())
            return "\(job.phase ?? "Writing") · \(percent) %"
        case .completed where job.superseded:
            // REPLACING the "Exported …" line rather than appending to it: the
            // label truncates its TAIL, so a note added on the end is the half
            // that disappears in a narrow window and the stale claim is the
            // half that survives. The row's own name already says which file.
            return "Overwritten by a later export to the same file."
        case .completed, .cancelled, .failed:
            return job.message ?? job.state.rawValue
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func revealClicked(_ sender: Any?) {
        owner?.reveal(id)
    }

    @objc private func buttonClicked(_ sender: Any?) {
        owner?.act(on: id)
    }
}
