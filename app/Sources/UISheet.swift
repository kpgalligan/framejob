import AppKit

#if FRAMEJOB_DEV_TOOLS
/// The sheet half of road map 11's V2b: what the settle after a
/// `perform_menu_item` or a `cancel_sheet` watches, and how `cancel_sheet`
/// closes the sheet an agent opened.
///
/// Every member is main-thread only. The settle loop itself is the server
/// thread's (`AgentServer+MenuItem.swift`): it sleeps `pollInterval`, reads
/// one `fingerprint` through `onMain`, and stops after `stablePolls` equal
/// reads in a row or at `bound`, so a sheet or window that arrives a
/// run-loop turn after the action returned is still in the answer.
///
/// **Cancel presses the sheet's own control, never an arbitrary one.** A
/// file panel (`NSSavePanel` and its `NSOpenPanel` subclass) is drawn out of
/// process and has no button here to press, so it is ended through its
/// parent with `.cancel` (V1's S2c path); any other sheet's Cancel is the
/// button whose key equivalent is Escape (`makeButtonRow`, `Sheets.swift`,
/// and `NSAlert`'s own Cancel); a sheet with exactly one button has that one.
/// Anything else is refused rather than guessed at.
enum UISheet {
    struct Fingerprint: Equatable {
        let sheet: ObjectIdentifier?
        let modal: ObjectIdentifier?
        let visible: [Int]
    }

    enum Cancel: String {
        case cancelButton = "cancel_button", onlyButton = "only_button", endSheet = "end_sheet"
    }

    static let pollInterval: TimeInterval = 0.02
    static let stablePolls = 5
    static let bound: TimeInterval = 3.0

    /// The window's attached sheet, the app-modal window and every visible
    /// window's number, sorted.
    static func fingerprint(_ window: NSWindow?) -> Fingerprint {
        Fingerprint(
            sheet: window?.attachedSheet.map { ObjectIdentifier($0) },
            modal: NSApp.modalWindow.map { ObjectIdentifier($0) },
            visible: visibleWindows().map(\.windowNumber).sorted())
    }

    static func visibleWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible }
    }

    /// Every enabled, shown button under `view`, pre-order.
    static func buttons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        func walk(_ node: NSView) {
            if let button = node as? NSButton, button.isEnabled,
                !button.isHiddenOrHasHiddenAncestor
            {
                found.append(button)
            }
            for child in node.subviews { walk(child) }
        }
        walk(view)
        return found
    }

    /// Closes `sheet` the way its own Cancel would, and says how; nil when
    /// there is nothing it may press.
    static func cancel(_ sheet: NSWindow) -> (how: Cancel, button: String?)? {
        if sheet is NSSavePanel {
            // Not reached for a parentless panel: `cancelSheet` refuses it
            // first, in its own words.
            guard let parent = sheet.sheetParent else { return nil }
            parent.endSheet(sheet, returnCode: .cancel)
            return (.endSheet, nil)
        }
        guard let root = sheet.contentView else { return nil }
        let all = buttons(in: root)
        if let escape = all.first(where: { $0.keyEquivalent == "\u{1b}" }) {
            escape.performClick(nil)
            return (.cancelButton, escape.title)
        }
        if all.count == 1, let only = all.first {
            only.performClick(nil)
            return (.onlyButton, only.title)
        }
        return nil
    }
}
#endif
