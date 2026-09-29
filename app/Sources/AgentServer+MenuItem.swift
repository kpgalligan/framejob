import AppKit

#if REELCUT_DEV_TOOLS
/// `perform_menu_item` and `cancel_sheet` — dev tools (road map 11's V2b,
/// spec §11 V-1..V-2): run a main-menu item by its path in a named
/// project's window, answered after the app settles, and close the sheet it
/// put up. They are what put a sheet, the Settings window or a panel up for
/// `snapshot_ui`.
///
/// **Both run on the SERVER thread** (`devOffMainTools`): the settle waits
/// `UISheet.pollInterval` between reads, and a wait may not hold the main
/// thread. Every AppKit touch is an `onMain` hop — one to resolve and check,
/// one to act, one per settle read, one for the result.
///
/// **Delivery never needs the app active or its window key.** The action
/// goes to the first object in the NAMED window's own responder chain that
/// answers it (`UIMenu.target`), never nil-targeted, which in an inactive
/// app would reach no editor at all (V1's S0). With no `project` it is the
/// frontmost project's window (`target(a)`), or the app's chain alone when
/// no project is open; app-level items (Settings…) resolve at the chain's
/// tail either way.
///
/// **What it refuses runs nothing**: an app-modal window already up, a path
/// that names no item or a submenu, an item with no action, a selector
/// `UIMenuTable.swift` reads `framework` or `modal` or does not list, an
/// item whose own target does not answer its action (disabled, as AppKit
/// shows it), an action nothing in the chain answers, and a disabled item
/// (its own validator's answer, as AppKit would ask it). `cancel_sheet`
/// refuses a sheet it has nothing to press, and a file panel with no parent
/// window to end it on.
///
/// **`sheet_at_return`** is whether the window had a sheet attached when the
/// action returned, read in the same main-thread hop; `sheet` is the one
/// after the settle, so a sheet that arrives later answers false and then
/// a sheet.
extension AgentServer {

    /// What the first hop resolved, carried to the next ones. Every
    /// reference in it is touched on main only.
    private struct MenuRun {
        let item: NSMenuItem
        let target: AnyObject
        let window: NSWindow?
        let project: Any
        let shown: String
        let selector: String
        let before: [(id: ObjectIdentifier, name: String, title: String)]
    }

    private struct SettleReport {
        let settled: Bool
        let ms: Int
        let polls: Int
    }

    func performMenuItem(_ a: [String: Any]) throws -> String {
        guard let path = try stringsArg(a, "path") else {
            return try jsonResult(onMain { try self.menuListing(a) })
        }
        guard !path.isEmpty else {
            throw ToolError(
                message: "path is empty: name a menu item, e.g. [\"File\", \"Export…\"]; omit "
                    + "path to list every item.")
        }
        let run = try onMain { try self.menuRun(a, path) }
        var performMs = 0
        var sheetAtReturn = false
        let sent = onMain { () -> Bool in
            let started = Date()
            let sent = UIMenu.perform(run.item, target: run.target, window: run.window)
            performMs = Self.milliseconds(since: started)
            sheetAtReturn = run.window?.attachedSheet != nil
            return sent
        }
        guard sent else {
            throw ToolError(
                message: "\(run.shown) (\(run.selector)) was sent to "
                    + "\(Self.className(run.target)) and nothing handled it.")
        }
        let settle = settleAfter(run.window)
        let result = onMain { () -> [String: Any] in
            let after = UISheet.visibleWindows()
            let known = Set(run.before.map(\.id))
            let still = Set(after.map { ObjectIdentifier($0) })
            return [
                "ok": true,
                "path": path,
                "title": run.item.title,
                "selector": run.selector,
                "verdict": UISnapshot.orNull(UIMenu.verdicts[run.selector]?.rawValue),
                "target": Self.className(run.target),
                "project": run.project,
                "perform_ms": performMs,
                "sheet_at_return": sheetAtReturn,
                "settled": settle.settled,
                "settle_ms": settle.ms,
                "polls": settle.polls,
                "sheet": run.window.map { UISnapshot.row($0)["sheet"] ?? NSNull() } ?? NSNull(),
                "windows_opened": after.filter { !known.contains(ObjectIdentifier($0)) }
                    .map(UISnapshot.row),
                "windows_closed": run.before.filter { !still.contains($0.id) }
                    .map { ["class": $0.name, "title": $0.title] },
                "modal_window": UISnapshot.orNull(
                    NSApp.modalWindow.map { NSStringFromClass(type(of: $0)) }),
                "active": NSApp.isActive,
                "window_facts": run.window.map { UISnapshot.facts($0) as Any } ?? NSNull(),
            ]
        }
        return try jsonResult(result)
    }

    func cancelSheet(_ a: [String: Any]) throws -> String {
        let (window, project, sheetClass, pressed) = try onMain {
            () throws -> (NSWindow, Any, String, (how: UISheet.Cancel, button: String?)) in
            let (window, project) = try self.menuWindow(a)
            guard let window else {
                throw ToolError(
                    message: "No project window is open, so there is no sheet to cancel.")
            }
            guard let sheet = window.attachedSheet else {
                throw ToolError(message: "No sheet attached to the window \"\(window.title)\".")
            }
            let sheetClass = NSStringFromClass(type(of: sheet))
            // Unreachable as far as known: `sheet` is `window.attachedSheet`,
            // whose `sheetParent` is `window`. Refused in its own words
            // rather than as "nothing to press" should it ever be reached.
            if sheet is NSSavePanel, sheet.sheetParent == nil {
                throw ToolError(
                    message: "The \(sheetClass) sheet is a file panel with no parent window to "
                        + "end it on, so cancel_sheet cannot close it.")
            }
            guard let pressed = UISheet.cancel(sheet) else {
                let titles = sheet.contentView.map { UISheet.buttons(in: $0).map(\.title) } ?? []
                throw ToolError(
                    message: "The \(sheetClass) sheet has nothing cancel_sheet may press: no "
                        + "button with Escape as its key and not exactly one button (buttons: "
                        + "\(titles.isEmpty ? "none" : titles.joined(separator: ", "))).")
            }
            return (window, project, sheetClass, pressed)
        }
        let settle = settleAfter(window)
        let result = onMain { () -> [String: Any] in
            [
                "ok": true,
                "project": project,
                "sheet_class": sheetClass,
                "how": pressed.how.rawValue,
                "button": UISnapshot.orNull(pressed.button),
                "settled": settle.settled,
                "settle_ms": settle.ms,
                "polls": settle.polls,
                "sheet": UISnapshot.row(window)["sheet"] ?? NSNull(),
                "active": NSApp.isActive,
            ]
        }
        return try jsonResult(result)
    }

    // MARK: - Main-thread reads

    /// The window a call means and its project's path (or null). `project`
    /// given: that project's editor window, refused when it has none.
    /// Omitted: nil with no project open, else the frontmost project's
    /// window. Main thread.
    private func menuWindow(_ a: [String: Any]) throws -> (NSWindow?, Any) {
        let given = a["project"] != nil && !(a["project"] is NSNull)
        if !given, openProjects().isEmpty { return (nil, NSNull()) }
        let document = try target(a)
        let path = UISnapshot.orNull(Self.path(of: document))
        let window = editor(document)?.view.window
        if given, window == nil {
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            throw ToolError(
                message: "The project \(name) has no window: perform_menu_item reaches a "
                    + "project's items only through its editor window.")
        }
        return (window, path)
    }

    private func menuListing(_ a: [String: Any]) throws -> [String: Any] {
        let (window, project) = try menuWindow(a)
        return [
            "ok": true,
            "project": project,
            "window": window.map { UISnapshot.row($0) as Any } ?? NSNull(),
            "active": NSApp.isActive,
            "items": UIMenu.listing(window: window),
        ]
    }

    /// Hop 1: every refusal, then what the run needs. Main thread.
    private func menuRun(_ a: [String: Any], _ path: [String]) throws -> MenuRun {
        let shown = path.joined(separator: " ▸ ")
        if let modal = NSApp.modalWindow {
            throw ToolError(
                message: "An app-modal window is up (\(NSStringFromClass(type(of: modal))), "
                    + "\"\(modal.title)\"): \(shown) is not run while it is.")
        }
        let (window, project) = try menuWindow(a)
        let item: NSMenuItem
        switch UIMenu.lookup(path, window: window) {
        case .missing(let at, let titles):
            let level = at.dropLast().joined(separator: " ▸ ")
            let wanted = at.last ?? ""
            throw ToolError(
                message: "\(shown) not found: "
                    + (level.isEmpty ? "the menu bar" : level) + " has no item \"\(wanted)\""
                    + (titles.isEmpty
                        ? "." : "; its items are: \(titles.joined(separator: ", "))."))
        case .submenu(let titles):
            throw ToolError(
                message: "\(shown) is a submenu, not an item; its items are: "
                    + "\(titles.joined(separator: ", ")).")
        case .item(let found):
            item = found
        }
        let selector = UIMenu.selector(of: item) ?? ""
        switch UIMenu.refusal(for: item) {
        case .noAction?:
            throw ToolError(message: "\(shown) has no action to run.")
        case .framework?:
            throw ToolError(
                message: "\(shown) (\(selector)) is refused: framework — AppKit's own "
                    + "implementation (quit, open, save, close, undo …), which a dev tool never "
                    + "runs. Use the product tool for it where there is one (undo, redo, "
                    + "save_project, open_project).")
        case .modal?:
            throw ToolError(
                message: "\(shown) (\(selector)) is refused: modal — it can run an app-modal "
                    + "loop inside the call, which would hold the agent server until a person "
                    + "dismissed it.")
        case .unclassified?:
            throw ToolError(
                message: "\(shown) (\(selector)) is refused: unclassified — the selector has no "
                    + "row in UIMenuTable.swift (tools/proof/capture_spike/inventory.json), so "
                    + "whether it runs a modal loop is unknown.")
        case nil:
            break
        }
        guard let target = UIMenu.target(for: item, window: window) else {
            if let own = item.target {
                throw ToolError(
                    message: "\(shown) (\(selector)) is disabled here: its own target "
                        + "\(Self.className(own)) does not answer \(selector).")
            }
            throw ToolError(
                message: "\(shown) (\(selector)): nothing in the "
                    + (window == nil ? "app's" : "project window's")
                    + " responder chain answers it.")
        }
        guard UIMenu.isEnabled(item, target: target) else {
            throw ToolError(
                message: "\(shown) (\(selector)) is disabled here: "
                    + "\(Self.className(target))'s validator answers false.")
        }
        let before = UISheet.visibleWindows().map {
            (id: ObjectIdentifier($0), name: NSStringFromClass(type(of: $0)), title: $0.title)
        }
        return MenuRun(
            item: item, target: target, window: window, project: project, shown: shown,
            selector: selector, before: before)
    }

    // MARK: - The settle

    /// Reads `UISheet.fingerprint` every `pollInterval` until `stablePolls`
    /// reads in a row agree (settled) or `bound` passes (not settled, still
    /// an answer). Server thread; each read is its own hop.
    private func settleAfter(_ window: NSWindow?) -> SettleReport {
        let started = Date()
        var last: UISheet.Fingerprint?
        var run = 0
        var polls = 0
        while true {
            Thread.sleep(forTimeInterval: UISheet.pollInterval)
            let next = onMain { UISheet.fingerprint(window) }
            polls += 1
            run = next == last ? run + 1 : 1
            last = next
            let elapsed = Self.milliseconds(since: started)
            if run >= UISheet.stablePolls {
                return SettleReport(settled: true, ms: elapsed, polls: polls)
            }
            if Date().timeIntervalSince(started) >= UISheet.bound {
                return SettleReport(settled: false, ms: elapsed, polls: polls)
            }
        }
    }

    private static func milliseconds(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    private static func className(_ object: AnyObject) -> String {
        NSStringFromClass(type(of: object))
    }

    // MARK: - Catalog

    func performMenuItemTool() -> [String: Any] {
        tool(
            "perform_menu_item",
            "DEV TOOL (absent from Distribution builds). Run a main-menu item by its path, "
                + "e.g. [\"File\", \"Export…\"], in a project's window — delivered to that "
                + "window's own responder chain, so it works with the app inactive and its "
                + "window behind others — and answer after the app settles (a sheet or window "
                + "that arrives a moment later is in the answer; bounded at 3 s). It is what "
                + "puts a sheet, the Settings window or a panel up for snapshot_ui. Refused, "
                + "by name and running nothing: a disabled item, a submenu, an item AppKit "
                + "owns (framework: Quit, Open…, Save, Close, Undo …), one that can run a "
                + "modal loop (modal: New Project, Allow Agent Connections), one the inventory "
                + "does not classify, and one whose own target does not answer its action. "
                + "The answer: the target, how long the action and the settle took, whether "
                + "a sheet was attached when the action returned (sheet_at_return) and the "
                + "sheet attached after the settle, the windows opened and closed, the modal "
                + "window and whether the app is active. With no path, lists every item: path, "
                + "selector, verdict, refusal, enabled, state and hidden. cancel_sheet closes "
                + "a sheet it opened.",
            [
                "path": [
                    "type": "array", "items": ["type": "string"],
                    "description": "The item's titles from the menu bar down, as the menu "
                        + "shows them. Omit to list every item instead.",
                ],
            ])
    }

    func cancelSheetTool() -> [String: Any] {
        tool(
            "cancel_sheet",
            "DEV TOOL (absent from Distribution builds). Close the sheet attached to a "
                + "project's window the way its own Cancel would: a file panel is ended with "
                + "cancel, any other sheet's button whose key is Escape is pressed, or its only "
                + "button when it has exactly one; anything else is refused with the buttons' "
                + "titles, and a file panel with no parent window is refused in its own words. "
                + "Answers after the app settles, with how it closed the sheet and "
                + "whether one is still attached.",
            [:])
    }
}
#endif
