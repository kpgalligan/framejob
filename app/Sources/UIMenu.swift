import AppKit

#if REELCUT_DEV_TOOLS
/// `perform_menu_item`'s main-thread half (road map 11's V2b): the main
/// menu's leaves, a path looked up in it, whether an item may be run at all,
/// which object answers it in a NAMED window's responder chain, whether that
/// object enables it, and the run itself.
///
/// Every member is main-thread only; the handler
/// (`AgentServer+MenuItem.swift`) reaches each through `onMain`.
///
/// **Delivery is never nil-targeted.** A nil-target `sendAction` or
/// `performActionForItem` walks the KEY window's chain, and an agent-driven
/// app is usually inactive with no key window, so the editor's actions would
/// fall through to the app delegate and do nothing (V1's S0). `responders`
/// walks the named window's own chain instead, the way AppKit would if that
/// window were key, then the app's tail; `target` is the first object in it
/// that answers the selector, and `perform` sends the action to THAT object.
///
/// **Refusal is an allow-table.** Only a selector `UIMenuTable.swift` reads
/// `none`, `sheet` or `window` may run: `framework` (AppKit's own quit, open,
/// save, close, undo …) and `modal` (a modal loop inside the call, which
/// holds the agent server's one request open) are refused by name, and so is
/// every selector with no row — AppKit's injected items and anything added
/// to the menu since the inventory was read.
///
/// **Undo.** An action run here is outside an AppKit event, so an edit it
/// makes would land in the implicit event group AppKit never closes and merge
/// with the next (app/CLAUDE.md "Undo and dirty tracking"). On a
/// `ProjectDocument`, `perform` runs the action inside
/// `inUndoGroupIfRegistered`: the explicit group opens at the item's first
/// undo registration, so an item's edits are one step (M3), and an item that
/// registers nothing — Zoom In — leaves undo and redo as they were (#167,
/// `v2_menu.py` U2). An `NSText` target on the document's own manager has
/// typing undo that bypasses `registerUndo`, so there, and for a target on
/// the document's manager on any other document, `perform` keeps the eager
/// group, `ProjectDocument.performGroupedEdit`'s discipline: event
/// grouping off, begin, act, close exactly what it opened, restore — never a
/// flush. The exception is `textReadOnlySelectors`, which change no text and
/// so register nothing: those run in `inUndoGroupIfRegistered` too (#176,
/// `v2_menu.py` U3). A target whose own `undoManager` is not the document's
/// — the Assistant composer, and every field editor, which answers its own
/// `NSCellUndoManager` — gets no eager group, since its text undo lands on
/// its own manager and the group could only be empty (#184,
/// `menu_undo_probe.py` M1, M2 and V1); on a `ProjectDocument` it runs in
/// `inUndoGroupIfRegistered`, so a document edit it commits during the
/// action (a `controlTextDidChange` commit) is still one step (F1).
enum UIMenu {
    /// V1's verdicts. `none` is spelled `.plain` so no `Optional.none`
    /// comparison is ever ambiguous.
    enum Verdict: String, CaseIterable { case plain = "none", sheet, window, modal, framework }
    enum Refusal: String { case noAction = "no_action", framework, modal, unclassified }

    /// The selectors an NSText target answers without changing its text, so
    /// without an undo registration (#176).
    static let textReadOnlySelectors: Set<String> = ["copy:", "selectAll:"]

    /// A menu item that is not a submenu, and the titles leading to it.
    struct Leaf {
        let item: NSMenuItem
        let path: [String]
    }

    enum Lookup {
        case item(NSMenuItem)
        /// `at` is the path up to and including the title not found; `titles`
        /// the visible titles of the level it was looked for in.
        case missing(at: [String], titles: [String])
        case submenu(titles: [String])
    }

    static func selector(of item: NSMenuItem) -> String? {
        item.action.map { NSStringFromSelector($0) }
    }

    /// Pre-order; separators skipped, hidden items kept. A submenu item is
    /// never a leaf itself.
    static func leaves(of menu: NSMenu, under path: [String] = []) -> [Leaf] {
        var found: [Leaf] = []
        for item in menu.items where !item.isSeparatorItem {
            let here = path + [item.title]
            if let submenu = item.submenu {
                found += leaves(of: submenu, under: here)
            } else {
                found.append(Leaf(item: item, path: here))
            }
        }
        return found
    }

    /// The item at `path` in the main menu. Each level is validated before
    /// its titles are read, since a validator may retitle an item (New
    /// Recording… reads Stop Recording while one runs); a hidden item never
    /// matches.
    static func lookup(_ path: [String], window: NSWindow?) -> Lookup {
        guard var menu = NSApp.mainMenu else { return .missing(at: path, titles: []) }
        for (index, title) in path.enumerated() {
            validate(menu, window: window)
            let visible = menu.items.filter { !$0.isSeparatorItem && !$0.isHidden }
            guard let item = visible.first(where: { $0.title == title }) else {
                return .missing(at: Array(path.prefix(index + 1)), titles: visible.map(\.title))
            }
            let last = index == path.count - 1
            if let submenu = item.submenu {
                if last {
                    validate(submenu, window: window)
                    return .submenu(
                        titles: submenu.items.filter { !$0.isSeparatorItem && !$0.isHidden }
                            .map(\.title))
                }
                menu = submenu
                continue
            }
            if last { return .item(item) }
            return .missing(at: Array(path.prefix(index + 2)), titles: [])
        }
        return .missing(at: [], titles: [])
    }

    /// Runs every validator of one level, as AppKit does before it shows it.
    private static func validate(_ menu: NSMenu, window: NSWindow?) {
        for item in menu.items where item.action != nil {
            _ = isEnabled(item, target: target(for: item, window: window))
        }
    }

    /// nil when the item may run; else why not.
    static func refusal(for item: NSMenuItem) -> Refusal? {
        guard let name = selector(of: item) else { return .noAction }
        guard let verdict = verdicts[name] else { return .unclassified }
        switch verdict {
        case .framework: return .framework
        case .modal: return .modal
        case .plain, .sheet, .window: return nil
        }
    }

    /// The window's responder chain from its first responder — or its
    /// content view, when the window itself holds first responder — then the
    /// window, its delegate, its controller and document; then the app, its
    /// delegate and the document controller. Each object once.
    static func responders(for window: NSWindow?) -> [AnyObject] {
        var chain: [AnyObject] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ object: AnyObject?) {
            guard let object, seen.insert(ObjectIdentifier(object)).inserted else { return }
            chain.append(object)
        }
        if let window {
            var responder: NSResponder? = window.firstResponder
            if responder == nil || responder === window { responder = window.contentView }
            while let next = responder, !seen.contains(ObjectIdentifier(next)) {
                add(next)
                responder = next.nextResponder
            }
            add(window)
            add(window.delegate)
            add(window.windowController)
            add(window.windowController?.document)
        }
        add(NSApp)
        add(NSApp.delegate)
        add(NSDocumentController.shared)
        return chain
    }

    /// The item's own target when it answers the action — nil when it does
    /// not, with no fallback to the chain, since AppKit greys such an item —
    /// else the first object in the chain that answers it.
    static func target(for item: NSMenuItem, window: NSWindow?) -> AnyObject? {
        guard let action = item.action else { return nil }
        if let own = item.target {
            return (own as? NSObjectProtocol)?.responds(to: action) == true ? own : nil
        }
        return responders(for: window).first {
            ($0 as? NSObjectProtocol)?.responds(to: action) == true
        }
    }

    /// AppKit's rule: a menu that does not auto-enable keeps the item's own
    /// flag; else the target's `validateMenuItem(_:)`, else its
    /// `validateUserInterfaceItem(_:)`, else enabled. Never writes `isEnabled`.
    static func isEnabled(_ item: NSMenuItem, target: AnyObject?) -> Bool {
        if let menu = item.menu, !menu.autoenablesItems { return item.isEnabled }
        guard let target else { return false }
        if let validator = target as? NSMenuItemValidation {
            return validator.validateMenuItem(item)
        }
        if let validator = target as? NSUserInterfaceValidations {
            return validator.validateUserInterfaceItem(item)
        }
        return true
    }

    /// Every leaf of the main menu, validated for `window`, with its verdict
    /// and refusal.
    static func listing(window: NSWindow?) -> [[String: Any]] {
        guard let main = NSApp.mainMenu else { return [] }
        var enabled: [ObjectIdentifier: Bool] = [:]
        for leaf in leaves(of: main) where leaf.item.action != nil {
            let item = leaf.item
            enabled[ObjectIdentifier(item)] = isEnabled(
                item, target: target(for: item, window: window))
        }
        // Walked again: validation can retitle a leaf.
        return leaves(of: main).map { leaf in
            let item = leaf.item
            let name = selector(of: item)
            let state: String
            switch item.state {
            case .on: state = "on"
            case .mixed: state = "mixed"
            default: state = "off"
            }
            return [
                "path": leaf.path,
                "selector": UISnapshot.orNull(name),
                "verdict": UISnapshot.orNull(name.flatMap { verdicts[$0]?.rawValue }),
                "refusal": UISnapshot.orNull(refusal(for: item)?.rawValue),
                "enabled": enabled[ObjectIdentifier(item)].map { $0 as Any } ?? NSNull(),
                "state": state,
                "hidden": item.isHidden,
            ]
        }
    }

    /// Sends the item's action to `target`, its undo in one explicit group on
    /// the window's document's manager (the header's **Undo.**); an `NSText`
    /// target's group is eager unless the selector is one of
    /// `textReadOnlySelectors`. A target with an undo manager of its own gets
    /// no eager group, only `inUndoGroupIfRegistered` on a `ProjectDocument`.
    /// False when nothing handled it.
    static func perform(_ item: NSMenuItem, target: AnyObject, window: NSWindow?) -> Bool {
        guard let action = item.action else { return false }
        let document = window?.windowController?.document as? NSDocument
        guard let manager = document?.undoManager else {
            return NSApp.sendAction(action, to: target, from: item)
        }
        if let own = (target as? NSResponder)?.undoManager, own !== manager {
            // Its text undo is its own; a document edit it commits is one step.
            guard let document = document as? ProjectDocument else {
                return NSApp.sendAction(action, to: target, from: item)
            }
            return document.inUndoGroupIfRegistered { NSApp.sendAction(action, to: target, from: item) }
        }
        if let document = document as? ProjectDocument,
            !(target is NSText) || textReadOnlySelectors.contains(NSStringFromSelector(action))
        {
            return document.inUndoGroupIfRegistered {
                NSApp.sendAction(action, to: target, from: item)
            }
        }
        let groupsByEvent = manager.groupsByEvent
        if groupsByEvent { manager.groupsByEvent = false }
        let level = manager.groupingLevel
        manager.beginUndoGrouping()
        let sent = NSApp.sendAction(action, to: target, from: item)
        // Close exactly what this call opened — never a group it did not.
        while manager.groupingLevel > level { manager.endUndoGrouping() }
        if groupsByEvent { manager.groupsByEvent = true }
        return sent
    }
}
#endif
