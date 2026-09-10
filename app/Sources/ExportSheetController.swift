import AppKit
import UniformTypeIdentifiers

/// File ▸ Export… (⌘E) and the toolbar's Export button: pick a format and a
/// size, adjust the frame rate, the quality and the range, then a save panel
/// and a progress sheet (spec §7.8, §10 step 10).
///
/// Every number the sheet shows comes back from `rc_export_settings` — the
/// sheet never computes an output size, a rate or a duration itself. That is
/// the §7 rule ("Rust decides") applied to a dialog: the controls only say
/// what to ASK for, the core answers, and what the readout shows is exactly
/// what `Exporter` will be handed. It also means a format the core adds
/// tomorrow needs no change here: the Format popup is built from
/// `ReelExport.presets()` and the Size popup from `ReelExport.sizes`, so
/// GIF, APNG or anything else joins the menu the moment the core's table
/// lists it — with the sizes the core fits to this document — and `Applies`
/// (`ExportSheetOptions.swift`) decides which of this sheet's controls that
/// row can honestly take.
///
/// The one number the sheet DOES choose is the bit rate: a quality tier is a
/// request, like a custom size, not a readout. It is spelled as bits per
/// pixel per frame so it means the same picture at every size, and what the
/// core answers with is what the footnote reports.
///
/// Road map 2's phase 7 added four things to the card. The first three are one
/// idea — **the sheet's controls are a VALUE** (`ExportChoice`,
/// `ExportPresetsStore.swift`). The card reopens on the last choice that was
/// actually exported with; a Preset row saves a choice under a name and
/// applies it back; and a Burn in timecode checkbox is one more choice, though
/// it travels as a `RecipeOptions` rather than as an export override — it
/// changes the PICTURE, and the override table would drop a key it does not
/// know without a word. Applying a preset and restoring the remembered choice
/// are the SAME code (`apply(_:)` in `ExportSheetResolve.swift`), so there is
/// one account of what a stored choice means and it is the one a person gets
/// by clicking each control by hand. The fourth is 7e's Add to Queue, which is
/// Export…'s own commit handed to `ExportQueueController` rather than to a
/// progress sheet — ONE method, so two buttons cannot come to read one card
/// two ways.
///
/// Its own file rather than another section of `Sheets.swift` (frozen at its
/// current size), built from the same `makeSheetView`/`makeButtonRow` pieces
/// so it matches every other dialog.
///
/// This file is the CONTROLS: the state they hold, `loadView` making them,
/// `rebuildSizes` listing the Size rows, the actions they send, and the two
/// commits that end in a save panel. THREE extensions carry the rest, each cut
/// out when the card passed app/CLAUDE.md's ~600-line cap — the first two when
/// it stood at 1114, the third when phase 7's own additions put it back over.
/// `ExportSheetOptions.swift` is what a control MEANS before any of them has
/// been read, `ExportSheetResolve.swift` is the round trip that turns a
/// selection into the core's answer and the answer back into the readout, and
/// `ExportSheetPresets.swift` is the saved-preset LIST — the one part of the
/// card with a store behind it and a life longer than the sheet's.
/// The stored properties below are internal rather than private for exactly
/// that reason and no other: a stored property cannot live in an extension,
/// and `private` on an extension member reaches only its own file — the toll
/// `ExporterLoudness.swift` records paying first.
final class ExportSheetController: NSViewController {
    /// Weak: the editor owns the presentation, and a sheet must never be the
    /// reason a closing window's controller stays alive.
    weak var editor: EditorViewController?

    /// The formats: the core's preset table, one row per encoding.
    let presets: [ExportPreset]
    /// The core's Size rows for the current format, in its order, repeats
    /// included — the list `rc_export_sizes` answered, whose first row is
    /// the format's default. Kept whole: it is the record of what the core
    /// said, and `visibleSizes` is a reading of it, not a replacement.
    var sizes: [ExportSize] = []
    /// The rows the Size popup shows: `sizes` minus every row whose numbers
    /// an earlier row already has. The popup's last item, "Custom…", is not
    /// one of them and sits at index `visibleSizes.count`, so this — never
    /// `sizes` — is what the popup's selection indexes.
    ///
    /// The hiding is the sheet's and not the core's, on purpose. A row's id
    /// is the `export` tool's vocabulary (`export_size.rs`), so `1080p` has
    /// to mean the same thing on every document, including the 1920 × 1080
    /// one where it is the document's own size — dropping it there would
    /// be the popup's tidiness leaking into an API. A person, though, reads
    /// the numbers, and one size under two names is a menu with a row that
    /// does nothing; the row that stays is the earliest, which is the one
    /// whose name says more ("Document size" over "1080p", "GIF default"
    /// over both on a document the cap already holds).
    var visibleSizes: [ExportSize] = []
    /// The preset id `sizes` was listed for, so that a format pick which
    /// lands on the format already chosen rebuilds nothing — NSPopUpButton
    /// sends its action on every pick, the current row included, and a
    /// rebuild would put the popup back on the default row and let
    /// `syncReadout` write over a typed custom size. The preset id is the
    /// whole key because the list's other input, the document, cannot
    /// change while the sheet is up (every editor action validates false
    /// with a sheet attached).
    private var sizesPreset: String?
    /// The message the core refused the size listing with, or nil when it
    /// answered. Held so `resolve()` can show it: a popup that silently
    /// held only "Custom…" would export the fields' clamped floor, 16 × 16,
    /// as if someone had asked for it.
    var sizesError: String?
    /// The in/out range at open time, if the document has one AND the card
    /// may spend it. Captured because the sheet blocks every edit while it is
    /// up, so it cannot move.
    ///
    /// Nil while a nest is open, which is the rule
    /// `ProjectDocument.inOutRange` states and argues: a range belongs to the
    /// container it was set in, an export always writes the whole timeline,
    /// and a nest-local pair of ticks is not timeline time. Nil is a state
    /// every path on this card already handles — the Range popup carries only
    /// "Whole project" and is disabled, `apply(_:)` degrades a remembered
    /// `in_out` to it, and `overrides()` writes no `range` key — so honouring
    /// the rule is this one capture and no special case anywhere below.
    let range: (start: Ticks, end: Ticks)?

    /// Whether the document HAS a live range that the nest scope is what
    /// suppressed, as against there being no range at all.
    ///
    /// The card cannot tell those two apart — both are a disabled Range popup
    /// reading "Whole project" — and only one of them would surprise the
    /// person who set the range a moment ago, so this is what lets that one
    /// say why (`loadView`).
    private let rangeIsTheNests: Bool

    /// The named presets a person has saved: this card's copy of the store,
    /// read when the sheet opens and RE-READ at every write
    /// (`ExportSheetPresets.swift`, which argues it — two windows can hold two
    /// cards, and `write()` replaces the file whole, so a save built from the
    /// snapshot this line took would drop what the other one added).
    var userPresets = ExportPresetsStore.load()

    /// The settings the core resolved for the current control values, and the
    /// message it refused with. Exactly one of the two is non-nil once
    /// `resolve()` has run.
    var resolved: ExportSettings?
    var resolveError: String?

    /// The saved-preset row, and the gear beside it carrying Save… and
    /// Delete. A pull-down rather than two more buttons because the control
    /// column is 258 points wide and a popup plus two titled buttons is not:
    /// the arithmetic is the size fields' and the Loudness row's, written down
    /// twice already below.
    ///
    /// Its rows carry their `ExportChoice` in `representedObject` and are read
    /// from `selectedItem`, never by index — and the menu is built out of
    /// `NSMenuItem`s rather than `addItem(withTitle:)`, which silently REMOVES
    /// an existing row with the same title (phase 4's caption-track defect).
    /// The store refuses two presets with one name anyway; building the menu
    /// this way means a hand-edited file cannot make the popup lose a row
    /// either.
    let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let presetMenuButton = NSPopUpButton(frame: .zero, pullsDown: true)
    /// Written into the picture on export and never into the preview. Not an
    /// export override — see the type doc — so it drives nothing on this card
    /// and is read once, at the commit, into a `RecipeOptions`.
    let burnInCheckbox = NSButton(
        checkboxWithTitle: "Burn in timecode", target: nil, action: nil)
    let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The custom size, on the row under the Size popup. Live only while
    /// "Custom…" is chosen; the rest of the time they mirror the core's
    /// answer, greyed, so picking Custom starts from the numbers of the row
    /// that was selected a moment before.
    let widthField = NSTextField(string: "")
    let heightField = NSTextField(string: "")
    let ratePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let qualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// Off, three targets, then "Custom…" — and the field beside it, live
    /// only for that last row, the same shape the Size popup and its two
    /// fields already have.
    let loudnessPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let loudnessField = NSTextField(string: "")
    let rangePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let summaryLabel = NSTextField(wrappingLabelWithString: "")
    let footnote = sheetFootnote("")
    var exportButton: NSButton!
    /// Add to Queue (road map 2's phase 7e). It takes `makeButtonRow`'s
    /// `secondary` slot — beside Cancel, not out at the far left by the
    /// footnote, where an affirmative button reads as something else entirely.
    var queueButton: NSButton!

    /// Frame-rate overrides. Index 0 is "the project's rate", i.e. no
    /// override at all — the core then uses the canvas rate (§5.2).
    static let rates: [Fps] = Fps.common

    init(editor: EditorViewController) {
        self.editor = editor
        self.presets = ReelExport.presets()
        // `scope == nil` is the first half of the test, not an afterthought:
        // see the property's doc above and the rule at
        // `ProjectDocument.inOutRange`. A range set inside a nest is the
        // nest's, and this card writes the timeline.
        let bounds = editor.document?.inOutRange
        let live = bounds.map { $0.end > $0.start } ?? false
        let scoped = editor.document?.scope != nil
        self.range = live && !scoped ? bounds : nil
        self.rangeIsTheNests = live && scoped
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ExportSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        formatPopup.addItems(withTitles: presets.map { $0.name })
        // The sheet opens on the first row of each of the core's two lists:
        // the H.264 format (`export.rs`, `PRESETS`) and, in its Size popup,
        // the document's own size (`export_size.rs`), so that ⌘E exports the
        // document as it is unless a person picks otherwise. Each default
        // has one home — the order of its list — and this is only the
        // reading of it, made explicit, and guarded so that an empty table
        // reaches `resolve()`'s own message rather than a selection out of
        // range.
        if !presets.isEmpty { formatPopup.selectItem(at: 0) }
        formatPopup.font = DS.sans(13)
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        formatPopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

        sizePopup.font = DS.sans(13)
        sizePopup.target = self
        sizePopup.action = #selector(sizeChanged(_:))
        sizePopup.widthAnchor.constraint(equalToConstant: 240).isActive = true

        for field in [widthField, heightField] {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.allowsFloats = false
            formatter.minimum = NSNumber(value: Self.sizeRange.lowerBound)
            formatter.maximum = NSNumber(value: Self.sizeRange.upperBound)
            field.formatter = formatter
            field.delegate = self
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 72).isActive = true
            DSField.style(field)
        }

        ratePopup.addItem(withTitle: "Project rate")
        ratePopup.addItems(withTitles: Self.rates.map { "\($0.displayName) fps" })
        ratePopup.font = DS.sans(13)
        ratePopup.target = self
        ratePopup.action = #selector(rangeOrRateChanged(_:))
        ratePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        qualityPopup.addItem(withTitle: "Format default")
        // Bare names now; `syncQualityTitles` puts the rate each tier would
        // ask for beside them as soon as the first resolve has run.
        qualityPopup.addItems(withTitles: Self.tiers.map { $0.name })
        qualityPopup.font = DS.sans(13)
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged(_:))
        qualityPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true

        loudnessPopup.addItem(withTitle: "Off")
        loudnessPopup.addItems(withTitles: Self.loudnessTargets.map { Self.loudnessTitle($0) })
        loudnessPopup.addItem(withTitle: "Custom…")
        loudnessPopup.font = DS.sans(13)
        loudnessPopup.target = self
        loudnessPopup.action = #selector(loudnessChanged(_:))
        loudnessPopup.widthAnchor.constraint(equalToConstant: 186).isActive = true

        let loudnessFormatter = NumberFormatter()
        loudnessFormatter.numberStyle = .decimal
        loudnessFormatter.allowsFloats = true
        loudnessFormatter.maximumFractionDigits = 1
        loudnessFormatter.minimum = NSNumber(value: Self.loudnessRange.lowerBound)
        loudnessFormatter.maximum = NSNumber(value: Self.loudnessRange.upperBound)
        loudnessField.formatter = loudnessFormatter
        loudnessField.delegate = self
        loudnessField.alignment = .right
        loudnessField.placeholderString = "LUFS"
        loudnessField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        DSField.style(loudnessField)

        rangePopup.addItem(withTitle: "Whole project")
        if range != nil { rangePopup.addItem(withTitle: "In/out range") }
        rangePopup.font = DS.sans(13)
        rangePopup.target = self
        rangePopup.action = #selector(rangeOrRateChanged(_:))
        rangePopup.isEnabled = range != nil
        rangePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        // A disabled Range popup ordinarily means "this document has no
        // range". Inside a nest it means something else — "the range there is
        // belongs to the nest you are editing inside" — and the two are the
        // same picture, so the one that would surprise somebody carries the
        // sentence. A tooltip rather than a row: an "In/out range" row that
        // refused the moment it was picked would be a control lying about
        // what it does, and the card's `hint` is one paragraph written for
        // every export rather than for this session's. The tooltip lands
        // because this is a stock `NSPopUpButton` — the app's dead-tooltip
        // pitfall is about custom controls that clear their own tracking
        // areas and take `NSToolTipManager`'s with them.
        if rangeIsTheNests {
            rangePopup.toolTip =
                "The in/out range belongs to the nest you are editing inside. An export "
                + "writes the whole timeline, so it cannot use it — leave the nest (⌘↑) "
                + "and set a range on the timeline."
        }

        burnInCheckbox.font = DS.sans(13)
        burnInCheckbox.target = self
        burnInCheckbox.action = #selector(burnInChanged(_:))

        presetPopup.font = DS.sans(13)
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        presetPopup.widthAnchor.constraint(equalToConstant: 216).isActive = true
        buildPresetMenuButton()
        rebuildPresetPopup(selecting: nil)

        // THE ORDER BELOW IS LOAD-BEARING and `apply(_:)` is where it is
        // written down. The remembered choice has to reach the format popup
        // BEFORE the sizes are listed and the size popup AFTER, because
        // `rebuildSizes()` lists for the format that is selected and then puts
        // the popup back on row 0 unconditionally. Nothing remembered takes
        // the path this sheet has always taken — the first format, the
        // format's default size — so a first run is byte for byte the card it
        // was before phase 7.
        if let remembered = ExportChoice.remembered {
            apply(remembered)
        } else {
            rebuildSizes()
        }

        summaryLabel.font = DS.mono(11)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2

        let grid = NSGridView(views: [
            // The Preset row is FIRST because it is the row that sets every
            // other one: reading down the card is then "this is the shape of
            // export I want" followed by what that shape means.
            [fieldLabel("Preset:"), presetRow()],
            [fieldLabel("Format:"), formatPopup],
            [fieldLabel("Size:"), sizePopup],
            // The custom fields get a row of their own under the popup: the
            // card is 420 wide with 22 insets and a 106 label column, so a
            // 240 popup fits beside its label and the popup plus two fields
            // does not.
            [NSGridCell.emptyContentView, sizeRow()],
            [fieldLabel("Frame rate:"), ratePopup],
            [fieldLabel("Quality:"), qualityPopup],
            // ONE row, popup and field together: 186 + 6 + 64 fits the 258
            // points the 420-wide card leaves beside a 106 label column,
            // where the Size popup's 240 does not.
            [fieldLabel("Loudness:"), loudnessRow()],
            [fieldLabel("Range:"), rangePopup],
            // No label: the checkbox carries its own, the way
            // `SpeedSheetController`'s "Preserve pitch" does.
            [NSGridCell.emptyContentView, burnInCheckbox],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 106

        // The readout sits UNDER the grid rather than in its second column:
        // it is a full sentence and would run past the card's edge from an
        // indented start.
        let content = NSStackView(views: [grid, summaryLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        exportButton = StickerButton(
            title: "Export…", style: .primary, target: self, action: #selector(exportClicked(_:)))
        queueButton = StickerButton(
            title: "Add to Queue", style: .secondary, target: self,
            action: #selector(queueClicked(_:)))
        view = makeSheetView(
            title: "Export",
            hint: "The format decides the codec and the container. Size, frame rate and "
                + "range start as the document's and quality as the format's; a GIF or an "
                + "APNG starts at its own cap and rate. Loudness normalises the whole mix "
                + "by one gain — no limiter — capped so its true peak stays under "
                + "−1 dBTP. A preset remembers the choices on this card rather than the "
                + "numbers they resolve to, so it means the same thing on a document of "
                + "another size. Burn in timecode writes the time into the picture on "
                + "export only — the preview never shows it — and it reads PROJECT time, "
                + "so a file written from an in/out range starting at 00:00:10:00 begins "
                + "at 00:00 with a burn-in reading 00:00:10:00, which is what a review "
                + "copy wants. Add to Queue writes the same file without the wait — the "
                + "job keeps this project as it is now and runs behind the editor, one at "
                + "a time, in Window ▸ Export Queue.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: exportButton, secondary: queueButton,
                leading: [footnote]))

        resolveCard()
    }

    /// `resolve()` plus the one repaint that cannot live beside it.
    ///
    /// `syncReadout` (`ExportSheetResolve.swift`) turns the single fact that
    /// decides a commit — whether the core resolved these settings — into
    /// Export…'s enabled state, and Add to Queue commits that same `resolved`
    /// through that same code. So it reads Export…'s ANSWER rather than asking
    /// `resolved` again, because two readings of one fact can disagree.
    /// **Every path that re-resolves this card calls THIS, not `resolve()`.**
    func resolveCard() {
        resolve()
        queueButton?.isEnabled = exportButton?.isEnabled ?? false
    }

    private func sizeRow() -> NSStackView {
        let times = NSTextField(labelWithString: "×")
        times.font = DS.sans(13)
        times.textColor = DS.textMuted
        let stack = NSStackView(views: [widthField, times, heightField])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private func loudnessRow() -> NSStackView {
        let stack = NSStackView(views: [loudnessPopup, loudnessField])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    /// Lists the core's rows for the current format, refills the Size popup
    /// with the ones worth showing (`visibleSizes`) and puts it back on the
    /// first — that format's default — so a size picked under one format
    /// cannot follow the person into another whose default is different
    /// (GIF's is its cap, H.264's is the document). Called once from
    /// `loadView` and then only when the format actually changes
    /// (`formatChanged`), which is what lets a custom size survive a pick.
    ///
    /// A listing the core refuses leaves only "Custom…" in the popup, and
    /// its message in `sizesError` for `resolve()` to show — there, not
    /// here, because the readout is repainted by every resolve and a
    /// message written into it now would be gone by the next one.
    ///
    /// Internal, not private, for the split's usual reason: `apply(_:)` in
    /// `ExportSheetResolve.swift` calls it BETWEEN the format it selects and
    /// the size it selects, which is the whole of that method's order.
    func rebuildSizes() {
        sizes = []
        sizesError = nil
        sizesPreset = currentPreset?.id
        if let project = editor?.document?.project, let preset = currentPreset {
            do {
                sizes = try ReelExport.sizes(project, preset: preset.id)
            } catch {
                sizesError = error.localizedDescription
            }
        }
        visibleSizes = sizes.reduce(into: []) { shown, row in
            if !shown.contains(where: { $0.width == row.width && $0.height == row.height }) {
                shown.append(row)
            }
        }
        sizePopup.removeAllItems()
        sizePopup.addItems(
            withTitles: visibleSizes.map { "\($0.name) · \($0.width) × \($0.height)" })
        sizePopup.addItem(withTitle: "Custom…")
        sizePopup.selectItem(at: 0)
    }

    // MARK: - Controls

    /// A new format means a new Size list — its default may differ — so the
    /// popup is rebuilt before the resolve. The rate, quality and range
    /// choices stay where they are; `Applies` decides whether they count.
    ///
    /// The SAME format, picked again, is not a change: NSPopUpButton sends
    /// its action for every pick, and rebuilding here would reset the Size
    /// popup to its default and overwrite a typed custom size with the
    /// core's answer for it (`sizesPreset`). Nothing else moved either, so
    /// there is nothing to resolve.
    @objc private func formatChanged(_ sender: Any?) {
        guard currentPreset?.id != sizesPreset else { return }
        presetEdited()
        rebuildSizes()
        resolveCard()
    }

    /// Picking "Custom…" needs no pre-fill of its own: `syncReadout` kept
    /// the fields mirroring the core's answer for the row that was selected,
    /// so they hold that row's numbers at the moment they come live.
    @objc private func sizeChanged(_ sender: Any?) {
        presetEdited()
        resolveCard()
    }

    @objc private func rangeOrRateChanged(_ sender: Any?) {
        presetEdited()
        resolveCard()
    }

    @objc private func qualityChanged(_ sender: Any?) {
        presetEdited()
        resolveCard()
    }

    @objc private func loudnessChanged(_ sender: Any?) {
        presetEdited()
        resolveCard()
    }

    /// The burn-in is not an override, so nothing about the resolved settings
    /// moves with it and there is nothing to ask the core. It is still one of
    /// the choices a preset stores, so the popup falls back like any other.
    @objc private func burnInChanged(_ sender: Any?) {
        presetEdited()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// Export… — write it now, behind a progress sheet.
    @objc private func exportClicked(_ sender: Any?) {
        commit(queue: false)
    }

    /// Add to Queue — write it later, behind nothing. The SAME commit, in one
    /// method, so the buttons cannot drift (road map 2's phase 7e).
    @objc private func queueClicked(_ sender: Any?) {
        commit(queue: true)
    }

    /// Hands off to the save panel, then to `EditorViewController`'s
    /// `beginExport` — or, for Add to Queue, its `enqueueExport`. The settings
    /// are captured BEFORE the dismissal: after it this controller's window is
    /// gone and its controls are on their way out of the view tree. Everything
    /// above the handoff is the same for both buttons and is written once for
    /// that reason: a queued job is not a second kind of export, it is this
    /// one held until its turn.
    private func commit(queue: Bool) {
        // End any edit in a Custom field first. A mouse click on a button
        // does not take the first responder from a text field, so the value
        // typed there has not been committed — `controlTextDidEndEditing`,
        // and the resolve it runs, fire only when the field editor resigns —
        // and `resolved` still describes the size from BEFORE the edit.
        // Handing the first responder to nobody makes it resign now,
        // synchronously, so the read below sees the numbers on screen. A
        // field whose text its formatter rejects refuses to resign; that is
        // the person's to fix, so the click just beeps.
        if let sheetWindow = view.window, !sheetWindow.makeFirstResponder(nil) {
            NSSound.beep()
            return
        }
        guard let editor = editor, let settings = resolved,
              let window = editor.view.window
        else {
            NSSound.beep()
            return
        }
        // Read while the controls still exist. `recipeOptions` is not part of
        // `settings` and never can be: the burn-in changes the PICTURE, so it
        // travels with the description of the picture rather than through the
        // override table, which drops a key it does not know without a word
        // (`RecipeOptions`).
        let options = recipeOptions
        // Remembered on the COMMIT and not on the dismissal: a card somebody
        // opened, fiddled with and cancelled is not a choice they made — and
        // queueing a job is as much a choice as exporting one, so both
        // buttons record it.
        currentChoice.remember()
        let name = suggestedName(for: settings, in: editor)
        dismiss(self)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.message = Self.panelMessage(for: settings)
        if let type = Exporter.contentType(for: settings) {
            panel.allowedContentTypes = [type]
        }
        // AppKit queues this behind the sheet that is on its way out, so the
        // panel appears once the settings card has finished leaving.
        panel.beginSheetModal(for: window) { [weak editor] response in
            guard response == .OK, let url = panel.url, let editor = editor else { return }
            // The handoff, and the only place the two buttons differ. The
            // project and its media are read on the far side of it, at the
            // moment the destination is known — which for a queued job is the
            // whole of what makes it immutable (`ExportQueueController`).
            if queue {
                editor.enqueueExport(settings: settings, to: url, options: options)
            } else {
                editor.beginExport(settings: settings, to: url, options: options)
            }
        }
    }

    /// What the card asks of the RECIPE rather than of the export settings —
    /// today, the burn-in and nothing else.
    var recipeOptions: RecipeOptions {
        RecipeOptions(burnInTimecode: burnInCheckbox.state == .on)
    }

    /// The document's name with the container's extension: `displayStem`, the
    /// title with the package's own extension off and NOTHING else off, so
    /// "Board v1.2" is `Board v1.2.mp4` (`ProjectDocument+DisplayStem.swift`).
    private func suggestedName(for settings: ExportSettings, in editor: EditorViewController)
        -> String
    {
        let stem = editor.document?.displayStem ?? ProjectDocument.untitledDisplayName
        return stem + "." + Exporter.fileExtension(for: settings)
    }

    /// The save panel's one line about what is being written. "As a movie"
    /// was wrong for half the table: a GIF or an APNG is an animated image
    /// and the audio-only row writes no picture at all. The classes are the
    /// sheet's own (`Applies`, `isFrameSequence`), so a format that is
    /// neither is a movie by the same reading that gave it a Size popup.
    private static func panelMessage(for settings: ExportSettings) -> String {
        if settings.isAudioOnly { return "Export the timeline's audio." }
        if isFrameSequence(container: settings.container) {
            return "Export the timeline as an animated \(settings.container.uppercased())."
        }
        return "Export the timeline as a movie."
    }
}

// MARK: - Size fields

extension ExportSheetController: NSTextFieldDelegate {
    /// A custom size or a custom loudness target is re-resolved on commit,
    /// not per keystroke: every resolve is an FFI round trip, and a
    /// half-typed "19" is not a size anyone means. A commit is Return, Tab, a
    /// click into another field, or `exportClicked` ending the edit on its
    /// way to the save panel.
    func controlTextDidEndEditing(_ obj: Notification) {
        guard isCustomSize || isCustomLoudness else { return }
        presetEdited()
        resolveCard()
    }
}
