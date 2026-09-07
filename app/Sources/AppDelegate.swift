import AppKit

/// The application delegate: the whole menu bar (spec §9), the welcome
/// window's place in the launch flow, and the agent server switch.
///
/// Every menu item uses a **nil-target selector** so it is dispatched down
/// the responder chain and validated by whoever implements it —
/// `EditorViewController.validateUserInterfaceItem` for the editor's
/// commands, `NSDocument`'s own for save and revert. The consequence is that
/// this file names selectors and nothing else: no menu item reaches into a
/// document or a view controller directly.
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

    /// The launch flag of spec §7.9: `-AgentServerEnabled YES` puts the value
    /// in NSUserDefaults' argument domain, which is the same key the menu item
    /// persists — so one read starts the server for a scripted launch and for
    /// a user who left it on.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: AgentServer.enabledDefaultsKey) {
            startAgentServer()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The server holds a pointer to its handler for as long as it runs, and
    /// its thread must be joined before the process goes away.
    func applicationWillTerminate(_ notification: Notification) {
        AgentServer.shared.stop()
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

    // MARK: - Agent server

    /// Tools > Allow Agent Connections: hosts an MCP endpoint on localhost so
    /// an external agent can drive the editor (spec §7.9, default port 4817,
    /// `RC_AGENT_PORT` overrides). Off by default; the preference persists
    /// across launches, and the endpoint is unauthenticated while it runs.
    @objc func toggleAgentServer(_ sender: Any?) {
        if AgentServer.shared.isRunning {
            AgentServer.shared.stop()
            UserDefaults.standard.set(false, forKey: AgentServer.enabledDefaultsKey)
        } else if startAgentServer() {
            UserDefaults.standard.set(true, forKey: AgentServer.enabledDefaultsKey)
        }
    }

    /// Starting can fail (a port in use with no ephemeral fallback left), and
    /// that failure IS user-facing: an alert, not a beep, because the menu
    /// item would otherwise just look stuck.
    @discardableResult
    private func startAgentServer() -> Bool {
        do {
            try AgentServer.shared.start()
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Start Agent Server"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleAgentServer(_:)) {
            // The item carries the endpoint while it is up, so the address to
            // point a client at never has to be guessed.
            let server = AgentServer.shared
            item.state = server.isRunning ? .on : .off
            item.title =
                server.isRunning
                ? "Allow Agent Connections (127.0.0.1:\(server.port)/mcp)"
                : "Allow Agent Connections"
        }
        return true
    }

    // MARK: - Menu construction

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")
        mainMenu.addItem(submenuItem(appMenu()))
        mainMenu.addItem(submenuItem(fileMenu()))
        mainMenu.addItem(submenuItem(editMenu()))
        mainMenu.addItem(submenuItem(clipMenu()))
        mainMenu.addItem(submenuItem(trackMenu()))
        mainMenu.addItem(submenuItem(markMenu()))
        mainMenu.addItem(submenuItem(viewMenu()))
        mainMenu.addItem(submenuItem(toolsMenu()))

        let windowMenu = self.windowMenu()
        mainMenu.addItem(submenuItem(windowMenu))
        NSApp.windowsMenu = windowMenu

        let helpMenu = self.helpMenu()
        mainMenu.addItem(submenuItem(helpMenu))
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    private func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    /// A tagged item — the idiom for a menu built from an enum's cases, so
    /// the menu and the enum can never drift apart.
    private func tagged(_ title: String, _ action: Selector?, _ tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        return item
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Reelcut")
        menu.addItem(item("About Reelcut", #selector(AppDelegate.showAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Reelcut", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(
            item(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Reelcut", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Project", #selector(newProject(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))

        // AppKit auto-populates a submenu whose sole item's action is
        // clearRecentDocuments: as the Open Recent menu.
        let openRecent = NSMenu(title: "Open Recent")
        openRecent.addItem(
            item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        openRecentItem.submenu = openRecent
        menu.addItem(openRecentItem)

        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(.separator())
        menu.addItem(
            item(
                "Add Media…", #selector(EditorViewController.addMediaFiles(_:)), "i",
                [.command, .shift]))
        menu.addItem(
            item("Import Captions…", #selector(EditorViewController.importCaptions(_:))))
        menu.addItem(
            item("Consolidate Media…", #selector(EditorViewController.consolidateMedia(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Export…", #selector(EditorViewController.exportProject(_:)), "e"))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        // NSUndoManager answers these through the responder chain; the
        // document owns the manager, so there is nothing to implement here.
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(EditorViewController.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(EditorViewController.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(EditorViewController.paste(_:)), "v"))
        menu.addItem(
            item("Duplicate", #selector(EditorViewController.duplicateClips(_:)), "d"))
        // Bare ⌫: U+0008 (NSBackspaceCharacter) is what AppKit matches the
        // Delete key against and what it draws as ⌫ (U+007F is forward
        // delete, ⌦). A modifier-less key equivalent is resolved ahead of the
        // first responder, so EditorViewController.validateUserInterfaceItem
        // must keep this item disabled unless there is something to delete
        // and no text is being edited — otherwise it swallows every Delete.
        menu.addItem(
            item("Delete", #selector(EditorViewController.deleteClips(_:)), "\u{8}", []))
        menu.addItem(
            item(
                "Ripple Delete", #selector(EditorViewController.rippleDeleteClips(_:)),
                "\u{8}", [.command]))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(EditorViewController.selectAll(_:)), "a"))
        menu.addItem(
            item(
                "Select After Playhead", #selector(EditorViewController.selectAfterPlayhead(_:)),
                "a", [.command, .option]))
        return menu
    }

    private func clipMenu() -> NSMenu {
        let menu = NSMenu(title: "Clip")
        menu.addItem(item("Split", #selector(EditorViewController.splitAtPlayhead(_:)), "t"))
        // W and E are BARE keys (spec §9), handled in the editor's keyDown so
        // they can never be stolen from a text field the way a modifier-less
        // key equivalent would be.
        menu.addItem(
            item("Trim Start to Playhead", #selector(EditorViewController.trimStartToPlayhead(_:))))
        menu.addItem(
            item("Trim End to Playhead", #selector(EditorViewController.trimEndToPlayhead(_:))))
        menu.addItem(.separator())
        menu.addItem(
            item(
                "Freeze Frame", #selector(EditorViewController.freezeFrame(_:)), "f",
                [.command, .shift]))
        menu.addItem(
            item(
                "Detach Audio", #selector(EditorViewController.detachAudio(_:)), "d",
                [.command, .option]))
        menu.addItem(
            item(
                "Add Action", #selector(EditorViewController.addActionAtPlayhead(_:)), "k",
                [.command, .option]))
        menu.addItem(item("Speed…", #selector(EditorViewController.showSpeedSheet(_:))))
        menu.addItem(submenuItem(transitionMenu()))
        menu.addItem(.separator())
        menu.addItem(item("Nest", #selector(EditorViewController.nestClips(_:)), "g"))
        menu.addItem(
            item("Un-nest", #selector(EditorViewController.unnestClips(_:)), "g", [.command, .shift]))
        return menu
    }

    /// Built from `TransitionKind.allCases` with the case's index as the tag,
    /// so adding a transition to the model adds it to this menu for free.
    private func transitionMenu() -> NSMenu {
        let menu = NSMenu(title: "Transition")
        for (index, kind) in TransitionKind.allCases.enumerated() {
            menu.addItem(
                tagged(kind.displayName, #selector(EditorViewController.setTransitionKind(_:)), index))
        }
        menu.addItem(.separator())
        menu.addItem(
            tagged("None", #selector(EditorViewController.setTransitionKind(_:)), -1))
        return menu
    }

    private func trackMenu() -> NSMenu {
        let menu = NSMenu(title: "Track")
        menu.addItem(
            item("New Track", #selector(EditorViewController.newTrack(_:)), "n", [.command, .shift]))
        menu.addItem(item("Remove Track", #selector(EditorViewController.removeTrack(_:))))
        menu.addItem(
            item("Remove Empty Tracks", #selector(EditorViewController.removeEmptyTracks(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Video", #selector(EditorViewController.toggleTrackHidden(_:))))
        menu.addItem(item("Mute Audio", #selector(EditorViewController.toggleTrackMuted(_:))))
        menu.addItem(item("Lock Track", #selector(EditorViewController.toggleTrackLocked(_:))))
        return menu
    }

    private func markMenu() -> NSMenu {
        let menu = NSMenu(title: "Mark")
        // M, I and O are bare keys (spec §9), handled in keyDown.
        menu.addItem(item("Add Marker", #selector(EditorViewController.addMarker(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Set In", #selector(EditorViewController.setInPoint(_:))))
        menu.addItem(item("Set Out", #selector(EditorViewController.setOutPoint(_:))))
        menu.addItem(
            item("Clear Range", #selector(EditorViewController.clearInOutRange(_:)), "x", [.option]))
        menu.addItem(.separator())
        menu.addItem(item("Next Marker", #selector(EditorViewController.nextMarker(_:))))
        menu.addItem(item("Previous Marker", #selector(EditorViewController.previousMarker(_:))))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Zoom In", #selector(EditorViewController.zoomIn(_:)), "+"))
        // Hidden alternate so plain ⌘= also zooms in.
        let zoomInEquals = item("Zoom In", #selector(EditorViewController.zoomIn(_:)), "=")
        zoomInEquals.isHidden = true
        zoomInEquals.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInEquals)
        menu.addItem(item("Zoom Out", #selector(EditorViewController.zoomOut(_:)), "-"))
        menu.addItem(item("Zoom to Fit", #selector(EditorViewController.zoomToFit(_:)), "0"))
        // ⇧Z is a bare key equivalent in spec §9; keyDown owns it.
        menu.addItem(item("Fit Timeline", #selector(EditorViewController.fitTimeline(_:))))
        menu.addItem(.separator())
        // N is likewise bare; the item carries the state checkmark only.
        menu.addItem(item("Snapping", #selector(EditorViewController.toggleSnapping(_:))))
        menu.addItem(item("Safe Areas", #selector(EditorViewController.toggleSafeAreas(_:))))
        menu.addItem(
            item(
                "Hide Inspector", #selector(EditorViewController.toggleInspector(_:)), "i",
                [.command, .option]))
        menu.addItem(submenuItem(trackHeightMenu()))
        return menu
    }

    private func trackHeightMenu() -> NSMenu {
        let menu = NSMenu(title: "Timeline Track Height")
        for (index, title) in ["Small", "Medium", "Large"].enumerated() {
            menu.addItem(
                tagged(title, #selector(EditorViewController.setTrackHeight(_:)), index))
        }
        return menu
    }

    private func toolsMenu() -> NSMenu {
        let menu = NSMenu(title: "Tools")
        menu.addItem(item("Allow Agent Connections", #selector(toggleAgentServer(_:))))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Reelcut Help", #selector(NSApplication.showHelp(_:))))
        return menu
    }
}
