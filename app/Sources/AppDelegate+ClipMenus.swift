import AppKit

/// The Clip menu's five submenus (spec §9): Add Background, Transition,
/// Motion (with its three slot menus), Look (the grading branch's GR5b) and
/// Label, and the label dot Label's rows carry.
///
/// A pure move out of `AppDelegate+Menus.swift` (grading GR1), which stood
/// near app/CLAUDE.md's ~600-line cap with grading's own menu rows still to
/// land: the builders came here whole, in their existing order, with their
/// bodies untouched. **The toll is visibility**: `clipMenu()`, which stayed,
/// calls the five builders, so they are internal rather than private, and
/// they build their rows with `tagged`, which is internal there now, as `item`
/// and `submenuItem` already were. `motionSlotMenu` and `labelDot` stay
/// `private`: each is called only from inside this file.
extension AppDelegate {

    /// Clip ▸ Add Background ▸ — the two ways to make a plate, which are two
    /// commands rather than one command with a source popup: the picture needs
    /// a file chooser and the colour needs nothing at all. Not built from an
    /// enum, so no tags: the ops themselves differ only in an argument, but
    /// the paths to them do not.
    func backgroundMenu() -> NSMenu {
        let menu = NSMenu(title: "Add Background")
        menu.addItem(
            item("Solid Color", #selector(EditorViewController.addSolidColorBackground(_:))))
        menu.addItem(item("Image…", #selector(EditorViewController.addImageBackground(_:))))
        return menu
    }

    /// Built from `TransitionKind.allCases` with the case's index as the tag,
    /// so adding a transition to the model adds it to this menu for free.
    func transitionMenu() -> NSMenu {
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

    /// Clip ▸ Motion: one submenu per slot, then Preview.
    func motionMenu() -> NSMenu {
        let menu = NSMenu(title: "Motion")
        let edges = EdgeMotion.allCases.map(\.displayName)
        menu.addItem(
            submenuItem(
                motionSlotMenu("In", edges, #selector(EditorViewController.setMotionIn(_:)))))
        menu.addItem(
            submenuItem(
                motionSlotMenu("Out", edges, #selector(EditorViewController.setMotionOut(_:)))))
        menu.addItem(
            submenuItem(
                motionSlotMenu(
                    "During", DuringMotion.allCases.map(\.displayName),
                    #selector(EditorViewController.setMotionDuring(_:)))))
        menu.addItem(.separator())
        menu.addItem(item("Preview", #selector(EditorViewController.previewClipMotion(_:))))
        return menu
    }

    /// Clip ▸ Look (spec §11 GR-7 [b]): the eight looks from `LookKind.allCases`
    /// with the index as the tag, a separator, None as −1 — the
    /// `transitionMenu()` idiom; `validateLookAction` checks and dashes them.
    /// `LookMenuFiller` puts the project's LUTs before None when it opens.
    func lookMenu() -> NSMenu {
        let menu = NSMenu(title: "Look")
        menu.delegate = LookMenuFiller.shared
        for (index, kind) in LookKind.builtIns.enumerated() {
            menu.addItem(tagged(kind.displayName, #selector(EditorViewController.setLook(_:)), index))
        }
        menu.addItem(.separator())
        menu.addItem(tagged("None", #selector(EditorViewController.setLook(_:)), -1))
        return menu
    }

    /// One slot's kinds, the `transitionMenu()` idiom: the index as the tag,
    /// a separator, None as −1.
    private func motionSlotMenu(_ title: String, _ names: [String], _ action: Selector) -> NSMenu {
        let menu = NSMenu(title: title)
        for (index, name) in names.enumerated() {
            menu.addItem(tagged(name, action, index))
        }
        menu.addItem(.separator())
        menu.addItem(tagged("None", action, -1))
        return menu
    }

    /// Built from `ClipLabel.allCases` with the case's index as the tag — the
    /// `transitionMenu()` idiom — so the six colours, their order and their
    /// inks come from the one file that owns them. Each item carries a dot in
    /// its colour: a label IS a colour, and a menu of six colour words that
    /// showed none would make the user picture them.
    func labelMenu() -> NSMenu {
        let menu = NSMenu(title: "Label")
        for (index, label) in ClipLabel.allCases.enumerated() {
            let entry = tagged(
                label.displayName, #selector(EditorViewController.setClipLabel(_:)), index)
            entry.image = Self.labelDot(label.color)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(tagged("None", #selector(EditorViewController.setClipLabel(_:)), -1))
        return menu
    }

    /// A 10 pt filled circle — the timeline strip's 6 pt label dot at menu
    /// size. Not a template image: the point of it is its colour.
    private static func labelDot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        return image
    }
}

/// Clip ▸ Look ▸'s LUT rows (spec §11 GR-8 [b]): between the eight's separator
/// and None, the project's `.cube` LUTs in media-list order, tag −2 with the
/// media id as `representedObject`, then a second separator — none of either
/// with no LUT. Rewritten each time the menu opens (`menuNeedsUpdate`), for
/// the main window's project; `UIMenu.fillDynamic` asks it for a named window.
final class LookMenuFiller: NSObject, NSMenuDelegate {
    static let shared = LookMenuFiller()

    func menuNeedsUpdate(_ menu: NSMenu) {
        fill(menu, for: NSApp.mainWindow)
    }

    func fill(_ menu: NSMenu, for window: NSWindow?) {
        let document = window?.windowController?.document as? ProjectDocument
        Self.fill(menu, luts: document.map { LookGallery.luts(in: $0.project.snapshot) } ?? [])
    }

    static func fill(_ menu: NSMenu, luts: [MediaSnapshot]) {
        guard let first = menu.items.firstIndex(where: \.isSeparatorItem) else { return }
        while menu.items.count > first + 2 { menu.removeItem(at: first + 1) }
        var at = first + 1
        for lut in luts {
            let item = NSMenuItem(
                title: LookGallery.lutName(lut),
                action: #selector(EditorViewController.setLook(_:)), keyEquivalent: "")
            item.tag = EditorViewController.lookLUTTag
            item.representedObject = NSNumber(value: lut.id)
            menu.insertItem(item, at: at)
            at += 1
        }
        if at > first + 1 { menu.insertItem(.separator(), at: at) }
    }
}
