import AppKit

/// The View menu (spec §9) and its two submenus, Timeline Track Height and
/// Preview Quality.
///
/// A pure move out of `AppDelegate+Menus.swift` (road map "creator-jobs"
/// CJ0c, T5), which stood near app/CLAUDE.md's ~600-line cap with the road
/// map's own menu rows still to land: the builders came here whole, in their
/// existing order, with their bodies untouched. **The toll is visibility**:
/// `buildMainMenu()`, which stayed, calls `viewMenu()`, so it is internal
/// rather than private. `trackHeightMenu` and `previewQualityMenu` stay
/// `private`: each is called only from inside this file.
extension AppDelegate {

    func viewMenu() -> NSMenu {
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
        menu.addItem(
            item(
                "Assistant", #selector(EditorViewController.showAssistant(_:)), "a",
                [.command, .control]))
        menu.addItem(submenuItem(trackHeightMenu()))
        menu.addItem(.separator())
        // Road map 2's phase 8: a group of their own, because both are about
        // the PREVIEW rather than about the editor's own panes. Preview
        // Quality carries the checkmark for the current row, like Timeline
        // Track Height above it; Preview Window carries one for whether the
        // panel is on screen, like Snapping and Safe Areas.
        menu.addItem(submenuItem(previewQualityMenu()))
        menu.addItem(
            item(
                "Preview Window", #selector(EditorViewController.togglePreviewWindow(_:)), "p",
                [.command, .shift]))
        // Grading GR3 and grading-2 G2-1 and G2-4 (spec §11 GR-4, GR-5, GR-10,
        // GR-13; hdr H-3, HD-14 (g)): checkmark toggles about the preview, view
        // state that nothing persists. Show Selection and Show SDR Version have
        // no shortcut.
        menu.addItem(
            item(
                "Show Ungraded", #selector(EditorViewController.toggleShowUngraded(_:)), "u",
                [.command, .control]))
        menu.addItem(
            item("Show Selection", #selector(EditorViewController.toggleShowSelection(_:))))
        menu.addItem(
            item("Show SDR Version", #selector(EditorViewController.toggleShowSDRVersion(_:))))
        menu.addItem(
            item(
                "Scopes", #selector(EditorViewController.toggleScopes(_:)), "w",
                [.command, .control]))
        // Road map "audio" AP7 (spec §11 AU-75): the live loudness column,
        // view state like Scopes.
        menu.addItem(
            item(
                "Loudness Meter", #selector(EditorViewController.toggleLoudnessMeter(_:)), "l",
                [.command, .control]))
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

    /// The rows are `PreviewQuality`'s own, tagged with its raw values, so the
    /// menu cannot list a quality the enum does not have or spell one
    /// differently from the checkmark that validates it. No key equivalents:
    /// every bare letter belongs to the editor's `keyDown`, and this is a
    /// setting somebody changes once.
    private func previewQualityMenu() -> NSMenu {
        let menu = NSMenu(title: "Preview Quality")
        for quality in PreviewQuality.allCases {
            menu.addItem(
                tagged(
                    quality.title, #selector(EditorViewController.setPreviewQuality(_:)),
                    quality.rawValue))
        }
        return menu
    }
}
