import AppKit

/// The application delegate: the launch and terminate flow, the welcome
/// window's place in it, the two document commands and the Export Queue
/// window.
///
/// **The menu bar (spec §9) is `AppDelegate+Menus.swift`** — `buildMainMenu()`
/// and every menu under it — cut out when this file crossed app/CLAUDE.md's
/// ~600-line cap. What makes that split cost the reader nothing is the menu's
/// own rule: every item uses a **nil-target selector** so it is dispatched
/// down the responder chain and validated by whoever implements it —
/// `EditorViewController.validateUserInterfaceItem` for the editor's
/// commands, `NSDocument`'s own for save and revert. A menu row names a
/// selector and nothing else: no menu item reaches into a document or a view
/// controller directly, and the handful of selectors the delegate itself
/// implements are all below.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        // Shadow, backdrop and background colors all carry alpha.
        NSColorPanel.shared.showsAlpha = true
    }

    /// AppKit calls this only when the app is launched or reactivated with no
    /// documents open, so it cannot race a launch-time file open the way a
    /// check in `applicationDidFinishLaunching` would. Reelcut has no blank
    /// untitled document at launch: the welcome window (spec §3) offers Open
    /// Video…, New Project and Recent instead.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        WelcomeWindowController.shared.show()
        return false
    }

    /// The agent socket, at every launch (road map 14, spec §11 MC-1;
    /// `AgentServer+Socket.swift` logs why when it binds none).
    func applicationDidFinishLaunching(_ notification: Notification) {
        AgentServer.shared.bindSocket()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q with an export still being written.
    ///
    /// **A half-written export is not unsaved work, and the app already has a
    /// path for the other one.** `NSDocumentController` reviews modified
    /// documents FIRST — measured, not assumed: a probe whose document
    /// controller never answers `reviewUnsavedDocuments` never reaches this
    /// method at all, so implementing it takes nothing away from the document
    /// review and simply asks a second question after it. The question is
    /// about work in flight, and its stakes are the opposite way round: there
    /// is nothing to save and nothing to lose in the model, but there IS a
    /// file at a path the person chose, and `AVAssetWriter` has not written
    /// its moov atom into it yet. Quit without asking and they are left with a
    /// truncated movie that Finder cannot tell from a finished one.
    ///
    /// **Scoped to the QUEUE, deliberately, and the scope is the fix's whole
    /// argument.** Quitting during a sheet export truncates its file exactly
    /// the same way — the progress sheets go up through `presentAsSheet`,
    /// which is window-modal, so Quit stays live behind them — and that has
    /// been true since M1. What phase 7's queue changed is not the outcome but
    /// the ODDS: it is the first long write in this app with nothing on
    /// screen, its window is documented as stopping nothing when it closes,
    /// and `enqueueExport` deliberately does not pause playback, so the person
    /// goes back to editing and forgets. A sheet is a person watching a bar
    /// move; ⌘Q there is a deliberate act with the evidence in front of them.
    /// Covering the sheets too would mean a registry of running `Exporter`s
    /// that nothing else wants, and asking `attachedSheet` instead would
    /// prompt about "an export being written" over the export SETTINGS card,
    /// which is a lie. Left undone on purpose; if a registry ever arrives for
    /// another reason, this is the second caller.
    ///
    /// Answering `.terminateLater` rather than cancelling and quitting at once
    /// is what makes "Quit Anyway" mean what it says: `cancelAll()` only ASKS
    /// the exporter to stop, and the half-written file is removed later, in
    /// `ExportQueueController.finished`. Exiting before that callback would
    /// leave behind exactly the debris the prompt was raised about.
    ///
    /// One consequence of asking SECOND, said out loud because it looks like a
    /// bug: the document review has already run by the time this is reached,
    /// so Cancel here leaves an app whose modified documents were saved and
    /// closed on the way to a quit that then did not happen. That is AppKit's
    /// order and every delegate that can cancel a termination inherits it;
    /// nothing is lost, and asking first is not on offer.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // ⌘Q with a recording running (road map 3, R1c): cancel, stop nothing,
        // and put the recording's controls in front of the person — who, if
        // they meant to stop, presses Stop. A quit that silently finished the
        // recording would land a file into a document that is about to ask
        // whether to save, the wrong moment for both. This is a BACKSTOP
        // asked after the document review above; `RecorderPanelController`'s
        // doc records what that order means for the recording's target. The
        // panel is HIDDEN for every recording it runs (decision 7), so
        // `revealControls()` opens the status item's menu — Pause or Resume,
        // and Stop — where `show()` could only beep (R2 review: a person who
        // paused and forgot was beeped at); for a recording the panel does
        // not own (the tool's) it shows the panel as before.
        if ScreenRecorder.shared.isRecording {
            RecorderPanelController.shared.revealControls()
            return .terminateCancel
        }
        let queue = ExportQueueController.shared
        guard !queue.isIdle else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "An export is still being written."
        let running = queue.runningJob.map { "“\($0.name)”" } ?? "An export"
        let waiting = queue.waitingCount
        alert.informativeText =
            "\(running) is not finished"
            + (waiting > 0 ? ", and \(waiting) more \(waiting == 1 ? "is" : "are") waiting" : "")
            + ". Quitting now stops it and deletes the partly written file."
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        queue.cancelAll()
        if queue.isIdle { return .terminateNow }
        waitForQueueThenTerminate()
        return .terminateLater
    }

    /// Replies to `.terminateLater` once the queue has actually stopped — the
    /// cancel is asynchronous, and the file is removed on the way out.
    ///
    /// The deadline is not tidiness. `replyToApplicationShouldTerminate` is
    /// the only thing that can end a `.terminateLater`, so an exporter that
    /// never called back would leave a person unable to quit by any means but
    /// Force Quit. Five seconds is longer than a cancel has ever taken and
    /// short enough that nobody reaches for the Dock.
    private func waitForQueueThenTerminate() {
        var observer: (any NSObjectProtocol)? = nil
        var replied = false
        func reply() {
            guard !replied else { return }
            replied = true
            if let observer = observer { NotificationCenter.default.removeObserver(observer) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        observer = NotificationCenter.default.addObserver(
            forName: ExportQueueController.didChangeNotification,
            object: ExportQueueController.shared, queue: .main
        ) { _ in
            if ExportQueueController.shared.isIdle { reply() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { reply() }
    }

    /// The socket is released and not joined: its file is unlinked only
    /// while it is still this instance's, and its listener is abandoned to
    /// process exit, so a call in flight cannot hold the quit (its handler
    /// and context live for the process).
    func applicationWillTerminate(_ notification: Notification) {
        AgentServer.shared.unbindSocket()
    }

    // MARK: - Documents

    /// File > New Project and the welcome window's button. Straight to a
    /// blank 1920×1080 / 30 fps project — the canvas size and rate are
    /// changed afterwards in the Document tab, not in a dialog on the way in.
    @objc func newProject(_ sender: Any?) {
        do {
            _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Reelcut > About Reelcut. The standard panel, but with the mark drawn
    /// by `BrandMark` in place of the app icon: the icon carries the squircle
    /// tile and its ink rule, which is right in the Dock and wrong on a panel
    /// that is already a card. The untiled mark is what the identity handoff
    /// asks for here (Part 1, "Files in `logo/`").
    @objc func showAboutPanel(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: BrandMark.image(size: 128)
        ])
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(newRecording(_:)) {
            // File ▸ New Recording… reads Stop Recording while one runs — the
            // same item, retitled from live state (road map 3, R1c). The state read is the
            // RECORDER's, so the title also covers a recording the
            // `record_screen` tool started; `AppDelegate+Recording.swift`
            // routes the stop to whichever door owns it.
            item.title = ScreenRecorder.shared.isRecording ? "Stop Recording" : "New Recording…"
        }
        if item.action == #selector(pauseOrResumeRecording(_:)) {
            // File ▸ Pause Recording (#98) reads the RECORDER, as the retitle
            // above does, in the status item's own words, and is live only
            // while a recording runs; `AppDelegate+Recording.swift` routes it.
            item.title = RecorderStatusItem.menuTitles(paused: ScreenRecorder.shared.isPaused)[0]
            return ScreenRecorder.shared.state == .recording || ScreenRecorder.shared.state == .paused
        }
        if item.action == #selector(showGraphicsReference(_:)) {
            // Help ▸ Graphics Reference opens the bundled file, so it is live
            // exactly while the bundle holds one (road map 10's G5b).
            return FileManager.default.fileExists(atPath: GraphicStore.bundledReferenceURL.path)
        }
        return true
    }

    // MARK: - Windows

    /// Window ▸ Export Queue (road map 2's phase 7e). The queue outlives its
    /// window — a running export does not stop when the window is closed — so
    /// this only shows the one there is.
    @objc func showExportQueue(_ sender: Any?) {
        ExportQueueWindowController.shared.show()
    }
}
