import AppKit

/// The export sheet's SAVED PRESETS: the popup that lists them, the gear that
/// saves and deletes one, and the rule that a hand change to any control drops
/// the popup back to "Custom".
///
/// A fourth file for one card, and it is the same payment the other three
/// record: `ExportSheetController.swift` stood at the ~600-line cap and had to
/// give something up before it took this on. The seam is a clean one. The
/// controller BUILDS the card's controls and commits it; `Options` is what a
/// control means before any of them is read; `Resolve` turns a selection into
/// the core's answer and back; and this file owns the LIST — a thing that
/// outlives the sheet, lives in a file in Application Support, and is the only
/// part of the card with a store behind it. Nothing here computes an export
/// setting, and nothing here reads one.
///
/// What a preset IS lives next to the file that holds it
/// (`ExportPresetsStore.swift`), and applying one is `Resolve`'s `apply(_:)` —
/// the same method the remembered choice goes through, which is what makes a
/// saved preset provably the same thing as clicking each control by hand.
///
/// The toll is the split's usual one: `presetRow()`, `buildPresetMenuButton()`,
/// `presetEdited()` and `presetChanged(_:)` are internal because `loadView` and
/// the control actions in the controller call them, and every stored control
/// they touch was already internal for the same reason. `saveChoice` and
/// `deleteChoice` are internal for a different one, and it is the reason they
/// exist as a pair separate from the two gear items: the items run an app-modal
/// alert and a menu, neither of which a headless script can answer, so the two
/// WRITES sit under them where a probe compiled from `app/Sources` can drive
/// what the file actually does.
extension ExportSheetController {

    /// The Preset popup and its gear, together on one row: 216 + 6 + 36 is
    /// the 258 points the 420-wide card leaves beside its 106 label column.
    /// The card is NOT widened for it — `makeSheetView` takes a `width:`, but
    /// widening this one moves every row already on it.
    func presetRow() -> NSStackView {
        let stack = NSStackView(views: [presetPopup, presetMenuButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    /// The gear: a pull-down, whose item 0 is its own face rather than a row.
    ///
    /// `autoenablesItems` stays ON and `validateMenuItem` answers for Delete.
    /// The pitfall recorded for the Remove Silences sheet is the same
    /// mechanism read the other way — a popup's menu validates its own rows,
    /// so an item disabled by hand is switched straight back on unless
    /// autoenabling is turned off first. Rather than turn it off and then
    /// re-synchronise Delete from four places, this uses the validation it
    /// would have been fighting.
    func buildPresetMenuButton() {
        let menu = NSMenu()
        let face = NSMenuItem()
        face.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Presets")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        // A build with no SF Symbol still needs a face somebody can hit — and
        // the image-only position has to go with the image, or the fallback
        // draws nothing at all.
        if face.image == nil {
            face.title = "⋯"
        } else {
            presetMenuButton.imagePosition = .imageOnly
        }
        menu.addItem(face)
        for (title, action) in [
            ("Save…", #selector(savePreset(_:))), ("Delete", #selector(deletePreset(_:))),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        presetMenuButton.menu = menu
        presetMenuButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        // Icon-only, so the tooltip is the only thing that names it.
        presetMenuButton.toolTip = "Save these settings as a preset, or delete the chosen one"
    }

    /// Refills the Preset popup from `userPresets` and selects `name`, or the
    /// "Custom" row when there is no such preset — which is also what a fresh
    /// sheet, a delete and any hand change to a control land on.
    func rebuildPresetPopup(selecting name: String?) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: Self.customPresetTitle, action: nil, keyEquivalent: ""))
        if !userPresets.presets.isEmpty {
            menu.addItem(.separator())
            for choice in userPresets.presets {
                let item = NSMenuItem(title: choice.name, action: nil, keyEquivalent: "")
                item.representedObject = choice
                menu.addItem(item)
            }
        }
        presetPopup.menu = menu
        if let name = name,
            let item = menu.items.first(where: {
                ($0.representedObject as? ExportChoice).map {
                    ExportPresetsStore.normalized($0.name) == ExportPresetsStore.normalized(name)
                } ?? false
            })
        {
            presetPopup.select(item)
        } else {
            presetPopup.selectItem(at: 0)
        }
    }

    /// The popup's first row: not a preset, and the state of a card whose
    /// controls match none of them. `DocumentPane`'s Canvas popup spells the
    /// same case the same way, one tab away.
    static let customPresetTitle = "Custom"

    /// The saved preset the popup is on, or nil for "Custom".
    var selectedUserPreset: ExportChoice? {
        presetPopup.selectedItem?.representedObject as? ExportChoice
    }

    // MARK: - Choosing, saving, deleting

    /// Applies a saved preset, or does nothing at all for the "Custom" row.
    ///
    /// Nothing, and not a beep: "Custom" is reachable by moving any control,
    /// so picking it is a request to leave the card alone rather than one the
    /// sheet cannot honour. (`DocumentPane`'s Canvas popup beeps on the same
    /// row, because there picking Custom is a request for a size the popup
    /// has no way to supply.)
    @objc func presetChanged(_ sender: Any?) {
        guard let choice = selectedUserPreset else { return }
        apply(choice)
        resolveCard()
    }

    /// Any hand change to a control drops the popup back to "Custom": the row
    /// names a set of choices, and once one of them has moved the card is no
    /// longer that preset.
    ///
    /// It does NOT compare the card against the preset — changing a value back
    /// does not re-arm the row. A comparison would have to answer whether a
    /// size row hidden as a duplicate of the document's own counts as the same
    /// choice (`visibleSizes`), and be wrong in one direction or the other;
    /// "you changed it" needs no such answer and is what every preset popup a
    /// person has met already does.
    func presetEdited() {
        if presetPopup.indexOfSelectedItem > 0 { presetPopup.selectItem(at: 0) }
    }

    /// Gear ▸ Save…. Names the card's current choices and writes them.
    @objc private func savePreset(_ sender: Any?) {
        // The same first-responder commit `exportClicked` makes, and for the
        // same reason: a typed custom size or loudness has not been committed
        // while its field editor still has it, so the choice read below would
        // be the one from before the edit. It is also what makes the guard
        // under it read the CURRENT card — ending the edit runs
        // `controlTextDidEndEditing`, which re-resolves.
        if let window = view.window, !window.makeFirstResponder(nil) {
            NSSound.beep()
            return
        }
        // **A card that cannot be exported cannot be named**, which is the
        // same fact `commit(queue:)` guards on one file over and the one
        // Export… is greyed out by. Without it Save… was the single
        // unguarded reader of `currentChoice`, and `currentChoice` has no
        // refusals in it: an empty Custom width reads through
        // `clampedSize` as the 16-pixel floor `resolve()` explicitly refuses
        // to export ("an export nobody asked for"), so the file got
        // `"custom_size": [16, 1080]` — a preset that applies cleanly,
        // resolves, and exports a 16-pixel movie from a card whose readout
        // said "Type a width and a height". The Custom LOUDNESS field has the
        // identical hole and this closes it too: `currentLoudness` answers nil
        // on an empty field, so the preset would have recorded Off while the
        // popup showed "Custom…".
        //
        // A beep and not a greyed-out row, deliberately: `validateMenuItem`
        // runs when the gear's menu OPENS, and a click on a button does not
        // end a field's edit (`commit(queue:)`'s own comment), so `resolved`
        // there can still describe the card from before the number now on
        // screen — it would grey out Save… on a card the person has just
        // fixed. Here, after the responder commit, the fact is current.
        guard resolved != nil else {
            NSSound.beep()
            return
        }
        guard let typed = askPresetName(suggesting: selectedUserPreset?.name ?? "") else { return }
        let name = ExportPresetsStore.normalized(typed)
        // The one name a preset may not take: it would read as the popup's
        // own first row, which is not a preset and cannot be deleted.
        guard !name.isEmpty,
            name.caseInsensitiveCompare(Self.customPresetTitle) != .orderedSame
        else {
            NSSound.beep()
            return
        }
        var choice = currentChoice
        choice.name = name
        guard saveChoice(choice) else {
            NSSound.beep()
            return
        }
        rebuildPresetPopup(selecting: name)
    }

    /// Gear ▸ Delete, on the preset the popup is showing.
    ///
    /// No confirmation, and that is a considered answer rather than an
    /// omission: deleting leaves every control exactly where the preset put
    /// them, so Save… under the same name puts it straight back. There is
    /// nothing to lose that the card is not still holding.
    @objc private func deletePreset(_ sender: Any?) {
        guard let choice = selectedUserPreset, deleteChoice(named: choice.name) else {
            NSSound.beep()
            return
        }
        rebuildPresetPopup(selecting: nil)
    }

    // MARK: - The two writes

    /// Adds or replaces one preset on disk and adopts the result. Answers
    /// whether the write landed, so the caller can beep.
    ///
    /// **The store is re-READ here rather than written from the snapshot the
    /// sheet opened with**, and that is the whole of these two methods.
    /// `userPresets` is loaded once per controller and a controller is built
    /// per ⌘E, so one window that opens, saves and closes is always current —
    /// but a sheet is WINDOW-modal, two documents can hold two cards at once
    /// (and two app instances one file), and `write()` replaces the file
    /// whole. Saving "Master" from a card whose snapshot predates the other
    /// window's "Web" would have written a file holding only "Master", with
    /// "Web" still listed in the popup that had just saved it — exactly the
    /// promise `savePreset` makes and cannot keep from a stale value. Reading
    /// first costs one small file read per Save… and brings the other
    /// window's additions into this popup for free.
    ///
    /// What re-reading cannot fix is the OTHER card's popup, which goes on
    /// listing a preset this one deleted until it is rebuilt. That is display
    /// staleness rather than loss: the store's promise is about the write, and
    /// this is what keeps the write honest.
    ///
    /// Written FIRST, and adopted only if the write landed, so the popup can
    /// never list a preset the file does not hold. Internal so a probe
    /// compiled from `app/Sources` can drive it: the action above runs an
    /// app-modal alert, which no headless script can answer.
    @discardableResult
    func saveChoice(_ choice: ExportChoice) -> Bool {
        let updated = ExportPresetsStore.load().saving(choice)
        guard updated.write() else { return false }
        userPresets = updated
        return true
    }

    /// Removes one preset from disk and adopts the result, on the same terms:
    /// the file is re-read first, so a delete cannot take a preset another
    /// open card saved after this one's snapshot down with it.
    @discardableResult
    func deleteChoice(named name: String) -> Bool {
        let updated = ExportPresetsStore.load().removing(named: name)
        guard updated.write() else { return false }
        userPresets = updated
        return true
    }

    /// The name prompt: an app-modal alert with a text field in it.
    ///
    /// An alert rather than a second sheet, because a sheet presented out of
    /// a sheet's own action is refused (the note
    /// `TranscribeSheetController.swift` carries), and app-modal rather than
    /// sheet-modal because the answer is needed HERE, in the middle of an
    /// action — `FFmpegRewrap.ask` is the house precedent for exactly that
    /// shape. The card stays visible behind it, which is the point: the
    /// choices being named are the ones on screen.
    private func askPresetName(suggesting suggestion: String) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Save these export settings as a preset"
        alert.informativeText =
            "A preset stores the choices on this card — format, size, frame rate, quality, "
            + "loudness, range and burn-in — not the numbers they resolve to. Saving under "
            + "a name that already exists replaces that preset, and “"
            + ExportSheetController.customPresetTitle
            + "” is the popup's own first row rather than a name a preset may take."
        let field = NSTextField(string: suggestion)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        field.placeholderString = "Preset name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}

// MARK: - The gear's rows

extension ExportSheetController: NSMenuItemValidation {
    /// Delete is live only while the popup is on a saved preset. Save… always
    /// is, and refuses in its own body instead — a card the core will not
    /// resolve cannot be named, but `resolved` is stale while a field editor
    /// is still open and a menu opens without closing one, so the test belongs
    /// after `savePreset`'s first-responder commit and not here.
    ///
    /// This is the gear's menu asking, which is the mechanism the Remove
    /// Silences sheet had to switch OFF to disable a row by hand. Answering it
    /// is the cheaper half of that trade — no stored menu item, and no fourth
    /// place to remember to re-synchronise when the selection moves.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(deletePreset(_:)) { return selectedUserPreset != nil }
        return true
    }
}

