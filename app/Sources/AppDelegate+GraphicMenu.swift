import AppKit

/// The menu bar's graphics rows (road map 10's G5b): the Insert menu and its
/// Graphic submenu, and Help ▸ Graphics Reference's action; and File's three
/// graphic-file items (spec §11 G-30, issue batch B84). Insert holds
/// Adjustment Clip first, above Graphic (spec §11 GR-6): a nil-target
/// selector the editor implements and validates
/// (`EditorViewController+Adjustment.swift`), with no key equivalent.
///
/// **Insert ▸ Graphic lists the BUNDLED templates by file stem** —
/// `GraphicTemplates.list(in:)`, never a compile, because chrome probes build
/// this menu bar by instantiating `AppDelegate()` — then a separator and From
/// File…. A missing `GraphicTemplates/` lists only From File…. Every item is
/// a nil-target selector the editor implements and validates
/// (`EditorViewController+GraphicMenus.swift`); a template item carries its
/// URL in `representedObject`. No key equivalents: every bare letter belongs
/// to the editor's own `keyDown` (spec §9).
///
/// `showGraphicsReference` lives on the delegate, like `showSettings`, so it
/// resolves with no document open; `AppDelegate.validateMenuItem` enables it
/// while the bundled `GraphicsAPI.md` is there.
extension AppDelegate {

    /// "Insert", holding Adjustment Clip, then Graphic.
    func insertMenu() -> NSMenu {
        let menu = NSMenu(title: "Insert")
        menu.addItem(
            item("Adjustment Clip", #selector(EditorViewController.insertAdjustmentClip(_:))))
        menu.addItem(submenuItem(graphicMenu()))
        return menu
    }

    /// "Graphic": one item per bundled template, a separator, From File….
    func graphicMenu() -> NSMenu {
        let menu = NSMenu(title: "Graphic")
        for template in GraphicTemplates.list(in: GraphicTemplates.bundledDirectory) {
            let row = item(
                template.title, #selector(EditorViewController.insertGraphicTemplate(_:)))
            row.representedObject = template.url
            menu.addItem(row)
        }
        menu.addItem(.separator())
        menu.addItem(
            item("From File…", #selector(EditorViewController.insertGraphicFromFile(_:))))
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
