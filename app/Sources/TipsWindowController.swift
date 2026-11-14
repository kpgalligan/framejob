import AppKit

/// The Tips dialog (spec §11 TIP-1, TIP-2): who a tip funds, "Leave a Tip"
/// and "Not Now".
///
/// **A window and not a sheet, deliberately.** It has three doors — the
/// editor's Tips button, Settings' Tips button and the automatic ask — and
/// two of them have no document to hold a sheet. It is modal to nothing, so
/// no window and no tool call ever waits on it. `SettingsWindowController`'s
/// mould: one instance, not released when closed, no frame autosave name.
/// It is built from the sheets' own pieces so it reads as one of them, and
/// it is left out of the Window menu because both buttons reopen it.
///
/// **Two ways to show it.** `show()` is a person's press: key and front, and
/// it writes nothing. `showAutomatic()` is the ask Frame Job makes by itself
/// (TIP-4): front WITHOUT key, so a Return typed into the editor can never
/// press "Leave a Tip". The two order calls are closures because a probe's
/// window is never key and could not tell the two apart otherwise.
///
/// **What "Leave a Tip" does.** Opens `TipsLink.url` in the browser, records
/// the press as an ask (TIP-5) and closes. Nothing here knows whether anyone
/// tipped.
final class TipsWindowController: NSWindowController {
    /// The app's one Tips dialog. A probe builds its own.
    static let shared = TipsWindowController()

    static let windowTitle = "Tips"
    static let heading = "Frame Job is free and open source"
    static let body =
        "Frame Job is made by one developer. It is free to use and its source is open. If it "
        + "is useful to you, a tip helps pay for the time to keep working on it. Tips are "
        + "voluntary, and nothing in Frame Job is locked without one."
    static let hint = "You can turn this reminder off in Frame Job ▸ Settings… ▸ Tips."
    static let notNowTitle = "Not Now"
    static let tipTitle = "Leave a Tip"

    private let ask: TipsAsk
    private let open: (URL) -> Void
    private let orderKey: (NSWindow) -> Void
    private let orderFront: (NSWindow) -> Void

    private(set) var notNowButton: NSButton!
    private(set) var tipButton: NSButton!

    init(
        ask: TipsAsk = .shared,
        open: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        orderKey: @escaping (NSWindow) -> Void = { $0.makeKeyAndOrderFront(nil) },
        orderFront: @escaping (NSWindow) -> Void = { $0.orderFront(nil) }
    ) {
        self.ask = ask
        self.open = open
        self.orderKey = orderKey
        self.orderFront = orderFront
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = Self.windowTitle
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        super.init(window: window)
        let content = buildContent()
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
        applyBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TipsWindowController does not support NSCoder")
    }

    private func buildContent() -> NSView {
        let width = sheetWidth - sheetInset * 2
        let bodyLabel = NSTextField(wrappingLabelWithString: Self.body)
        bodyLabel.font = DS.sans(13)
        bodyLabel.textColor = DS.textStrong
        bodyLabel.preferredMaxLayoutWidth = width
        bodyLabel.setAccessibilityIdentifier("tips.body")

        let hintLabel = NSTextField(wrappingLabelWithString: Self.hint)
        hintLabel.font = DS.sans(12)
        hintLabel.textColor = DS.textMuted
        hintLabel.preferredMaxLayoutWidth = width
        hintLabel.setAccessibilityIdentifier("tips.hint")

        notNowButton = StickerButton(
            title: Self.notNowTitle, style: .secondary, target: self,
            action: #selector(notNowClicked(_:)))
        notNowButton.setAccessibilityIdentifier("tips.notnow")
        tipButton = StickerButton(
            title: Self.tipTitle, style: .primary, target: self,
            action: #selector(tipClicked(_:)))
        tipButton.setAccessibilityIdentifier("tips.tip")

        return makeSheetView(
            title: Self.heading, content: sheetColumn([bodyLabel, hintLabel]),
            buttonRow: makeButtonRow(cancel: notNowButton, apply: tipButton))
    }

    private func applyBackground() {
        window?.backgroundColor = DS.chromeBackground
        window?.contentView?.layer?.backgroundColor = DS.chromeBackground.cgColor
    }

    // MARK: - Showing

    /// A person's press of a Tips button: key and front. Writes nothing.
    func show() {
        guard let window else { return }
        applyBackground()
        orderKey(window)
    }

    /// The ask Frame Job makes by itself: front, never key (TIP-4).
    func showAutomatic() {
        guard let window else { return }
        applyBackground()
        orderFront(window)
    }

    // MARK: - Buttons

    @objc func notNowClicked(_ sender: Any?) {
        close()
    }

    @objc func tipClicked(_ sender: Any?) {
        if let url = URL(string: TipsLink.url) { open(url) }
        ask.noteTipPageOpened()
        close()
    }
}

// MARK: - The export doors

/// The two places an export reaches Tips (TIP-4): the Export… sheet's success
/// and a queued job, which is a person's Add to Queue
/// (`EditorViewController+Export.swift`) or the agent's `export`
/// (`AgentServer+Export.swift`, the Assistant's too). Both doors do nothing in
/// a scratch instance (`counts`, TIP-8). The ask, the dialog, the queue and
/// that rule are parameters so a probe runs the doors on its own. Main thread.
final class TipsDoors {
    static let shared = TipsDoors()

    private let ask: TipsAsk
    private let dialog: () -> TipsWindowController
    private let queue: ExportQueueController
    private let counts: () -> Bool
    private var follower: TipsQueueFollower?
    private var queueObserver: NSObjectProtocol?
    /// The result sheets still up after a counted success, each waiting for
    /// its window's sheet to end.
    private var sheetEnds: [TipsSheetEnd] = []

    init(
        ask: TipsAsk = .shared,
        dialog: @escaping () -> TipsWindowController = { TipsWindowController.shared },
        queue: ExportQueueController = .shared,
        counts: @escaping () -> Bool = { TipsInstance.isPersons }
    ) {
        self.ask = ask
        self.dialog = dialog
        self.queue = queue
        self.counts = counts
    }

    deinit {
        if let queueObserver { NotificationCenter.default.removeObserver(queueObserver) }
    }

    /// An Export… the person confirmed has succeeded: counted now. The ask
    /// waits until `window`'s sheet — the export's own result panel — ends,
    /// and one main-queue turn more so the sheet has left; with no sheet
    /// attached it is asked at once. Nothing in a scratch instance.
    func exportSucceeded(sheetOn window: NSWindow?) {
        guard counts() else { return }  // the Export… door
        ask.countExport()
        guard let window, window.attachedSheet != nil else {
            askIfDue()
            return
        }
        sheetEnds.append(
            TipsSheetEnd(window: window) { [weak self] watch in
                guard let self else { return }
                self.sheetEnds.removeAll { $0 === watch }
                self.askIfDue()
            })
    }

    /// A queued job, a person's Add to Queue or the agent's `export`:
    /// followed to its end by id. A completion counts and asks; a cancel or a
    /// failure does neither. Not followed at all in a scratch instance.
    func follow(queueJob id: UInt64) {
        guard counts() else { return }  // the queue door
        if follower == nil {
            follower = TipsQueueFollower(
                state: { [queue] in queue.job($0)?.state },
                completed: { [weak self] in
                    self?.ask.countExport()
                    self?.askIfDue()
                })
            queueObserver = NotificationCenter.default.addObserver(
                forName: ExportQueueController.didChangeNotification, object: queue, queue: nil
            ) { [weak self] _ in self?.follower?.settle() }
        }
        follower?.follow(id)
    }

    /// Shows the dialog when the schedule says so, recording the ask at the
    /// moment it is shown.
    private func askIfDue() {
        guard ask.takeAsk() else { return }
        dialog().showAutomatic()
    }
}

/// One wait for a window's sheet to end, then one main-queue turn.
private final class TipsSheetEnd: NSObject {
    private let then: (TipsSheetEnd) -> Void

    init(window: NSWindow, then: @escaping (TipsSheetEnd) -> Void) {
        self.then = then
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(ended(_:)), name: NSWindow.didEndSheetNotification,
            object: window)
    }

    @objc private func ended(_ note: Notification) {
        NotificationCenter.default.removeObserver(self)
        DispatchQueue.main.async { self.then(self) }
    }
}

// MARK: - The command

/// The command half, at the foot of the file that owns the feature
/// (`SettingsWindowController.swift`'s precedent): a nil-target selector, so
/// the editor's Tips button resolves it through the responder chain.
extension AppDelegate {
    @objc func showTips(_ sender: Any?) {
        TipsWindowController.shared.show()
    }
}
