import AppKit

/// The whole menu bar (spec §9): `buildMainMenu()`, the ten menus it hangs off
/// it (the eleventh, Insert, is `AppDelegate+GraphicMenu.swift`'s), the
/// submenus under those but the Clip menu's (`AppDelegate+ClipMenus.swift`'s,
/// a pure move, grading GR1), and the three helpers every row is made with —
/// `item`, `tagged` and `submenuItem`.
///
/// **The seam is the one `AppDelegate.swift`'s own doc already promised.** A
/// menu item here names a **nil-target selector** and nothing else: it is
/// dispatched down the responder chain and validated by whoever implements it,
/// so no line in this file reaches into a document or a view controller. What
/// stays behind in `AppDelegate.swift` is therefore everything with a life of
/// its own — the launch and terminate callbacks, the document plumbing, the
/// agent-server switch, and the handful of `@objc` actions the delegate itself
/// implements for the selectors named here.
///
/// The cut is the size payment `AppDelegate.swift` owed at 625 lines against
/// app/CLAUDE.md's ~600 cap, taken BEFORE the View menu grew phase 8's Preview
/// Quality submenu and Preview Window item — which it now has, and which is the
/// order `ExportSheetOptions.swift` and `ExporterSettings.swift` were both
/// taken in.
/// It is a pure move: the same declarations, in the same order, with the same
/// bodies.
///
/// **The toll is visibility**. `private` on an extension member reaches only
/// its own file, so `buildMainMenu()` is internal now —
/// `applicationWillFinishLaunching` calls it from the other half — and so are
/// `item` and `submenuItem`, which `AppDelegate+GraphicMenu.swift` builds the
/// Insert menu with (road map 10's G5b), and `tagged`, which
/// `AppDelegate+ClipMenus.swift`'s builders use (grading GR1), as `clipMenu()`
/// here calls theirs. The other builders and helpers stay
/// `private`, because Swift's `private` covers a type's extensions within one
/// file and each is called only from inside this one. Nothing needed to
/// become a stored property either, which is what makes an extension a legal
/// home for it: the menu bar is built out
/// of selectors, `TransitionKind.allCases` and `ClipLabel.allCases`, and holds
/// no state at all once it is hung off `NSApp`.
extension AppDelegate {

    /// The menu bar itself, hung off `NSApp` in
    /// `applicationWillFinishLaunching`. Internal rather than private for
    /// exactly that reason and no other: its one caller is the lifecycle half
    /// of the class, in `AppDelegate.swift`.
    func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "MainMenu")
        mainMenu.addItem(submenuItem(appMenu()))
        mainMenu.addItem(submenuItem(fileMenu()))
        mainMenu.addItem(submenuItem(editMenu()))
        mainMenu.addItem(submenuItem(insertMenu()))
        mainMenu.addItem(submenuItem(clipMenu()))
        mainMenu.addItem(submenuItem(trackMenu()))
        mainMenu.addItem(submenuItem(markMenu()))
        mainMenu.addItem(submenuItem(viewMenu()))

        let windowMenu = self.windowMenu()
        mainMenu.addItem(submenuItem(windowMenu))
        NSApp.windowsMenu = windowMenu

        let helpMenu = self.helpMenu()
        mainMenu.addItem(submenuItem(helpMenu))
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    func item(
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
    func tagged(_ title: String, _ action: Selector?, _ tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        return item
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Reelcut")
        menu.addItem(item("About Reelcut", #selector(AppDelegate.showAboutPanel(_:))))
        menu.addItem(.separator())
        // Road map 6 §5d: the app's first window for something PERSISTED,
        // in the place macOS puts one. ⌘, is unclaimed by spec §9's table —
        // the nudge pair is the BARE `,` and `.`.
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
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
        // Directly under New Project with no separator, because both make a
        // document out of nothing (road map 3 §4). ⌥⌘N: ⌘N and ⇧⌘N are
        // taken, and the modifier keeps the key off the first responder. It
        // reads "Stop Recording" while one runs — `AppDelegate.validateMenuItem`
        // retitles it, the agent-server item's precedent.
        menu.addItem(
            item(
                "New Recording…", #selector(AppDelegate.newRecording(_:)), "n",
                [.command, .option]))
        // Retitled Resume Recording and enabled only while a recording runs
        // (`validateMenuItem`); no key (#98).
        menu.addItem(item("Pause Recording", #selector(AppDelegate.pauseOrResumeRecording(_:))))
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
        // The three caption items sit together, in the order a caption track
        // comes into being and leaves again: read one in, make one from
        // speech, write one back out. None of the three takes a key
        // equivalent — spec §9's "proposed, not yet bound" table claims no
        // row for phase 4, and a modifier-less menu key would be resolved
        // ahead of the first responder and steal a letter the editor's own
        // `keyDown` owns (the reason recorded at Remove Silences… below).
        menu.addItem(
            item("Import Captions…", #selector(EditorViewController.importCaptions(_:))))
        menu.addItem(
            item("Generate Captions…", #selector(EditorViewController.generateCaptions(_:))))
        menu.addItem(
            item("Export Captions…", #selector(EditorViewController.exportCaptions(_:))))
        menu.addItem(
            item("Consolidate Media…", #selector(EditorViewController.consolidateMedia(_:))))
        // Road map 10's G5b: a face or a picture into the package's
        // graphics/, `import_graphic_font`'s and `import_graphic_asset`'s
        // body. No key equivalents, the caption items' reason above.
        menu.addItem(
            item("Add Font to Graphics…", #selector(EditorViewController.addGraphicFont(_:))))
        menu.addItem(
            item("Add Image to Graphics…", #selector(EditorViewController.addGraphicImage(_:))))
        addGraphicFileItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(item("Export…", #selector(EditorViewController.exportProject(_:)), "e"))
        // Save Frame… is the still-image sibling of Export… and sits beside
        // it under the same letter (road map 2's phase 7a): ⌘E writes the
        // movie, ⌥⌘E writes the one frame under the playhead. Spec §9's
        // "proposed, not yet bound" table claimed ⌥⌘E for this phase and the
        // row has been promoted into the bound table above it. The modifier
        // matters: a modifier-less menu key equivalent is resolved ahead of
        // the first responder, which is why the caption items take none, but
        // ⌥⌘ is nobody's bare key.
        menu.addItem(
            item(
                "Save Frame…", #selector(EditorViewController.saveFrame(_:)), "e",
                [.command, .option]))
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
            item(
                "Paste Attributes", #selector(EditorViewController.pasteAttributes(_:)), "v",
                [.command, .option]))
        menu.addItem(
            item(
                "Paste Graphic Properties",
                #selector(EditorViewController.pasteGraphicProperties(_:))))
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
        // The two placement edits for the Media tab's selected file. No key
        // equivalent: they are reached often enough from the row's own
        // context menu and from an ⌥ / ⇧⌥ drop, and the letters a cutter
        // expects for them (F and D) are both taken.
        menu.addItem(
            item(
                "Insert at Playhead", #selector(EditorViewController.insertMediaAtPlayhead(_:))))
        menu.addItem(
            item(
                "Overwrite at Playhead",
                #selector(EditorViewController.overwriteMediaAtPlayhead(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(EditorViewController.selectAll(_:)), "a"))
        menu.addItem(
            item(
                "Select After Playhead", #selector(EditorViewController.selectAfterPlayhead(_:)),
                "a", [.command, .option]))
        menu.addItem(
            item(
                "Select All on Track", #selector(EditorViewController.selectAllClipsOnTrack(_:))))
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
        // Road map 2's phase 5c, next to Detach Audio because those two are
        // the Clip menu's only sound commands. It duplicates the Audio
        // section's button deliberately (contract D-C8): a command reachable
        // from a pane alone can be lost — Add Shape's lesson — and a menu item
        // is what gives the `normalize_clip` mirror a UI path to name.
        //
        // No key equivalent: spec §9's "proposed, not yet bound" table claims
        // no row for phase 5, and a modifier-less menu key would be resolved
        // ahead of the first responder and steal a letter the editor's own
        // `keyDown` owns (the reason spelled out at Remove Silences… below).
        //
        // The title is the button's title and the string `AgentCatalog`'s
        // `normalize_clip` description names as this command's UI path. Three
        // spellings of one command is how the halves drift.
        menu.addItem(item("Normalize", #selector(EditorViewController.normalizeClips(_:))))
        menu.addItem(
            item(
                "Add Action", #selector(EditorViewController.addActionAtPlayhead(_:)), "k",
                [.command, .option]))
        menu.addItem(item("Speed…", #selector(EditorViewController.showSpeedSheet(_:))))
        menu.addItem(
            item("Close Gap", #selector(EditorViewController.closeGapAtPlayhead(_:))))
        // Road map 2's phase 3a — a cutting command, so it sits with Close Gap
        // rather than in the identity group below the separator. No key
        // equivalent, deliberately: every bare letter belongs to the editor's
        // own `keyDown` (spec §9), and a modifier-less menu key would be
        // resolved ahead of the first responder and steal it back.
        menu.addItem(
            item("Remove Silences…", #selector(EditorViewController.removeSilences(_:))))
        menu.addItem(submenuItem(transitionMenu()))
        // Road map 5's E2, beside Transition ▸: the two "how the clip arrives"
        // submenus together (a recorded deviation from §5f's "after Label").
        // No key equivalent, for Remove Silences…' reason above.
        menu.addItem(submenuItem(motionMenu()))
        // Grading's GR5b (spec §11 GR-7): Look ▸ right after Motion ▸, the menu
        // half of the Color sub-tab's Look section. No key equivalent, for
        // Remove Silences…' reason above.
        menu.addItem(submenuItem(lookMenu()))
        menu.addItem(.separator())
        // Road map 2's phase 6c — what goes BEHIND the picture, in a group of
        // its own because neither item edits the selection: both put a clip on
        // a new back-most track (`core/src/edit_background.rs`).
        //
        // Add Background is a SUBMENU rather than one dialog. Its two rows are
        // two different commands, not two settings of one: Solid Color takes
        // no dialog at all — hence no ellipsis — because the plate is
        // re-coloured in the Clip tab's Fill row afterwards, which is also how
        // a full-canvas gradient is reached, while Image… is an open panel.
        //
        // Neither takes a key equivalent, and neither claims a row in spec
        // §9's "proposed, not yet bound" table: every bare letter belongs to
        // the editor's own `keyDown`, and a modifier-less menu key would be
        // resolved ahead of the first responder and steal it back (the reason
        // recorded at Remove Silences… above).
        menu.addItem(submenuItem(backgroundMenu()))
        menu.addItem(
            item(
                "Add Blurred Background",
                #selector(EditorViewController.addBlurredBackground(_:))))
        menu.addItem(.separator())
        // Identity (format version 3): the clip's own name and its label.
        menu.addItem(
            item(
                "Rename…", #selector(EditorViewController.renameClip(_:)), "r",
                [.command, .shift]))
        menu.addItem(submenuItem(labelMenu()))
        menu.addItem(.separator())
        menu.addItem(item("Nest", #selector(EditorViewController.nestClips(_:)), "g"))
        menu.addItem(
            item("Un-nest", #selector(EditorViewController.unnestClips(_:)), "g", [.command, .shift]))
        // Road map 2's phase 9, in the grouping group because going inside a
        // nest is the third thing you do with one. ⌘↓ and ⌘↑ are the pair
        // spec §9's "proposed, not yet bound" table claimed for this phase
        // and the row has been promoted into the bound table above it.
        //
        // **A modifier does not keep a menu key equivalent out of the first
        // responder's way**, and this comment claimed it did until the phase
        // was read back. `NSApplication.sendEvent` offers every main-menu
        // equivalent the key-down BEFORE the window dispatches it, modifier
        // or none; what the modifier changes is only WHICH of the field
        // editor's bindings is displaced — here `moveToBeginningOfDocument:`
        // and `moveToEndOfDocument:`. So this pair is validated DEAD while
        // text is being edited, the bare ⌫ above's rule exactly
        // (`EditorViewController+NestScope.swift`'s
        // `validateNestScopeAction`). What a modifier-less letter would cost
        // on top of that is the editor's own `keyDown` map, which owns every
        // bare key (spec §9) and is the reason phases 4, 5 and 6 took no key
        // equivalent at all.
        //
        // Two items rather than one toggle, unlike View ▸ Preview Window: in
        // and out are different distances — ⌘↑ comes out ONE level of a stack
        // that can be eight deep — so a single checkmarked row could not say
        // what it would do.
        menu.addItem(
            item("Open Nest", #selector(EditorViewController.openNest(_:)), "\u{F701}", [.command]))
        menu.addItem(
            item("Close Nest", #selector(EditorViewController.closeNest(_:)), "\u{F700}", [.command]))
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
        // The checkmark is the validator's (EditorViewController+Identity.swift).
        menu.addItem(item("Solo", #selector(EditorViewController.toggleTrackSolo(_:))))
        menu.addItem(submenuItem(trackMatteMenu()))
        return menu
    }

    /// Track ▸ Matte (spec §11 MT-7): `TrackMatte`'s rows, tagged with their
    /// case index, checked by the validator for the current track's mode.
    private func trackMatteMenu() -> NSMenu {
        let menu = NSMenu(title: "Matte")
        for (index, mode) in TrackMatte.allCases.enumerated() {
            menu.addItem(
                tagged(mode.displayName, #selector(EditorViewController.setTrackMatte(_:)), index))
        }
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
        // Grading GR3 and grading-2 G2-1 (spec §11 GR-4, GR-5, GR-10): two
        // checkmark toggles about the preview, view state that nothing persists.
        menu.addItem(
            item(
                "Show Ungraded", #selector(EditorViewController.toggleShowUngraded(_:)), "u",
                [.command, .control]))
        menu.addItem(
            item(
                "Scopes", #selector(EditorViewController.toggleScopes(_:)), "w",
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

    /// The queue's window sets `isExcludedFromWindowsMenu`, and it has to: this
    /// menu is `NSApp.windowsMenu`, so AppKit appends a row for every window it
    /// can see, titled after the window — and "Export Queue" would appear
    /// twice, once as the item below and once as AppKit's own.
    ///
    /// No key equivalent. Spec §9's "proposed, not yet bound" table claims no
    /// row for phase 7e, and every bare letter belongs to the editor's own
    /// `keyDown`.
    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Export Queue", #selector(showExportQueue(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Reelcut Help", #selector(NSApplication.showHelp(_:))))
        menu.addItem(
            item("Graphics Reference", #selector(AppDelegate.showGraphicsReference(_:))))
        return menu
    }
}
