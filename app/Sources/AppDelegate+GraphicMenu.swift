import AppKit

/// The menu bar's graphics rows (road map 10's G5b; spec §11 G-45): the
/// Insert menu, and Help ▸ Graphics Reference's action; and File's three
/// graphic-file items (spec §11 G-30, issue batch B84). Insert holds
/// Adjustment Clip first (spec §11 GR-6), then one item, Graphic…, which
/// puts up the graphic browser (`GraphicBrowserSheetController.swift`), whose
/// From File… button replaced the old submenu's item. Both are nil-target
/// selectors the editor implements and validates
/// (`EditorViewController+Adjustment.swift`,
/// `EditorViewController+GraphicMenus.swift`), with no key equivalent: every
/// bare letter belongs to the editor's own `keyDown` (spec §9).
///
/// **The menu bar compiles nothing and lists no template**: chrome probes
/// build it by instantiating `AppDelegate()`, and the browser compiles the
/// templates (`GraphicTemplateLibrary`) only when it is opened.
///
/// `showGraphicsReference` lives on the delegate, like `showSettings`, so it
/// resolves with no document open; `AppDelegate.validateMenuItem` enables it
/// while the bundled `GraphicsAPI.md` is there.
extension AppDelegate {

    /// "Insert", holding Adjustment Clip, then Graphic….
    func insertMenu() -> NSMenu {
        let menu = NSMenu(title: "Insert")
        menu.addItem(
            item("Adjustment Clip", #selector(EditorViewController.insertAdjustmentClip(_:))))
        menu.addItem(item("Graphic…", #selector(EditorViewController.showGraphicBrowser(_:))))
        return menu
    }

    /// File's graphic-file group (spec §11 G-30 (a)): a separator, then
    /// Rename Graphic…, Delete Graphic… and Restore Graphic Version…, each a
    /// nil-target selector the editor implements and validates
    /// (`EditorViewController+GraphicFiles.swift`). No key equivalents, the
    /// caption items' reason.
    func addGraphicFileItems(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(
            item(
                GraphicFileAct.rename.menuTitle, #selector(EditorViewController.renameGraphic(_:))))
        menu.addItem(
            item(
                GraphicFileAct.delete.menuTitle, #selector(EditorViewController.deleteGraphic(_:))))
        menu.addItem(
            item(
                GraphicFileAct.restore.menuTitle,
                #selector(EditorViewController.restoreGraphicVersion(_:))))
    }

    /// Help ▸ Graphics Reference: the bundled `GraphicsAPI.md` in the
    /// person's default app for Markdown — the file `graphic_reference`
    /// answers.
    @objc func showGraphicsReference(_ sender: Any?) {
        NSWorkspace.shared.open(GraphicStore.bundledReferenceURL)
    }
}
