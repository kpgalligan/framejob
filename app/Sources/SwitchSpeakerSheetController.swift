import AppKit

/// Clip ▸ Switch by Speaker… (road map "creator-jobs" SW2b, spec §11 SW-26): a Program track cut
/// from the selected cameras, showing whoever talks on each microphone, applied as one undo step
/// "Switch by Speaker". `switch_by_speaker` (`AgentServer+Switch.swift`) takes the same values
/// and writes through the same `SpeakerSwitch.read`, `plan` and `edit`.
///
/// One row per speaker of SW-20's defaults (a Microphone popup and a Camera popup), then Wide,
/// Minimum shot, Cut before speech, Crosstalk shows, Ignore bleed (in the main grid: SW-S4's
/// excerpt arm is owed), "Cut to the wide after … s on one speaker" (off), "Mute the cameras' own
/// sound" (`muteDefault`) and, when a track qualifies, Write to. Every change plans again on main
/// and the summary says what Switch would do, or every refusal, one per line. Switch plans once
/// more on the document's current handle before it applies, because the ops name ids a trial
/// predicted; a refusal then stays in the summary with the sheet open. Minimum shot, Cut before
/// speech, Crosstalk shows and Ignore bleed are remembered, written only when changed.
///
/// **The one-microphone form** (SW8, spec §11 SW-85): when the implied pairing is the faces mode
/// (one microphone, two or more angles), a Microphone popup and "Cameras:" naming every angle
/// replace the speaker rows, Minimum shot opens at 3 s and is never remembered, there is no Ignore
/// bleed row, and the hedge leads the summary while the chosen pairing is the faces mode.
///
/// **The dev accept** (`-RCDevSwitchSpeakerAccept YES`, dev tools only): the sheet presses Switch
/// once its first edit exists, with its controls as set (AU-128's precedent).
final class SwitchSpeakerSheetController: NSViewController, NSTextFieldDelegate {
    /// The dev-only launch default that presses Switch.
    static let devAcceptKey = "RCDevSwitchSpeakerAccept"
    private static let width: CGFloat = 480

    private weak var document: ProjectDocument?
    private let opened: SpeakerSwitch.Settings
    private let pairing: SpeakerSwitch.Pairing
    /// The one-microphone form (SW-85).
    private let faces: Bool
    private let microphones: [UInt32]
    private let angles: [UInt32]
    private let names: [UInt32: String]
    private var accepted = false
    private var edit: SpeakerSwitch.Edit?

    private var micPopups: [NSPopUpButton] = []
    private var cameraPopups: [NSPopUpButton] = []
    private let widePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let crosstalkPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let writePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let minShotField = NSTextField(string: "")
    private let leadField = NSTextField(string: "")
    private let bleedField = NSTextField(string: "")
    private let wideAfterField = NSTextField(string: "")
    private let wideAfterBox = NSButton(
        checkboxWithTitle: "Cut to the wide after", target: nil, action: nil)
    private let muteBox = NSButton(
        checkboxWithTitle: "Mute the cameras' own sound", target: nil, action: nil)
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private var switchButton: NSButton?

    init(document: ProjectDocument) {
        self.document = document
        let snapshot = document.editedProject.snapshot
        let selection = document.selection.sorted().compactMap { snapshot.clip($0) }
        let implied = SpeakerSwitch.defaults(selection: selection, in: snapshot)
        let faces = SpeakerSwitch.mode(implied.pairing) == .faces
        var opened = SpeakerSwitch.Settings.remembered(.standard)
        if faces { opened.minShot = FaceActivity.minShot }
        self.opened = opened
        self.faces = faces
        self.pairing = implied.pairing
        self.angles = implied.angles
        self.microphones = SpeakerSwitch.microphoneChoices(selection, in: snapshot)
        var names = SpeakerSwitch.titles(implied.angles, in: snapshot)
        for (track, name) in SpeakerSwitch.titles(microphones, in: snapshot) where names[track] == nil {
            names[track] = name
        }
        self.names = names
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SwitchSpeakerSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        guard let document else {
            view = NSView()
            return
        }
        let snapshot = document.editedProject.snapshot
        let first = SpeakerSwitch.read(
            from: document, clips: nil, pairing: nil, range: nil, settings: opened)
        let micTitles = SpeakerSwitch.titles(microphones, in: snapshot)
        let angleTitles = SpeakerSwitch.titles(angles, in: snapshot)

        var rows: [[NSView]] = []
        if faces {
            let mic = popup(
                microphones.map { (micTitles[$0] ?? "", $0) }, selected: pairing.speakers.first?.mic,
                none: nil)
            mic.setAccessibilityIdentifier("switchspeaker.mic.0")
            micPopups.append(mic)
            let cameras = sheetUnitLabel(angles.map { angleTitles[$0] ?? "" }.joined(separator: ", "))
            cameras.setAccessibilityIdentifier("switchspeaker.cameras")
            rows.append([fieldLabel("Microphone:"), mic])
            rows.append([fieldLabel("Cameras:"), cameras])
        }
        for (index, speaker) in pairing.speakers.enumerated() where !faces {
            let mic = popup(
                microphones.map { (micTitles[$0] ?? "", $0) }, selected: speaker.mic,
                none: speaker.mic == nil ? "None" : nil)
            let camera = popup(
                angles.map { (angleTitles[$0] ?? "", $0) }, selected: speaker.angle,
                none: speaker.angle == nil ? "None" : nil)
            mic.setAccessibilityIdentifier("switchspeaker.mic.\(index)")
            camera.setAccessibilityIdentifier("switchspeaker.camera.\(index)")
            micPopups.append(mic)
            cameraPopups.append(camera)
            rows.append([
                fieldLabel("Speaker \(index + 1):"),
                sheetRow([mic, sheetUnitLabel("on"), camera]),
            ])
        }
        fill(widePopup, angles.map { (angleTitles[$0] ?? "", $0) }, selected: pairing.wide, none: "None")
        rows.append([fieldLabel("Wide:"), widePopup])

        style(minShotField, range: SpeakerSwitch.Settings.minShotRange, value: opened.minShot)
        style(leadField, range: SpeakerSwitch.Settings.leadRange, value: opened.lead)
        style(bleedField, range: SpeakerSwitch.Settings.bleedRange, value: opened.bleedDB)
        style(
            wideAfterField, range: SpeakerSwitch.Settings.wideAfterRange,
            value: opened.wideAfter ?? SpeakerSwitch.Settings.wideAfterOffered)
        rows.append([fieldLabel("Minimum shot:"), sheetRow([minShotField, sheetUnitLabel("s")])])
        rows.append([fieldLabel("Cut:"), sheetRow([leadField, sheetUnitLabel("s before speech")])])
        for title in ["Wide", "Current speaker"] {
            crosstalkPopup.addItem(withTitle: title)
        }
        crosstalkPopup.selectItem(at: opened.crosstalk == .wide ? 0 : 1)
        crosstalkPopup.font = DS.sans(13)
        crosstalkPopup.target = self
        crosstalkPopup.action = #selector(controlChanged(_:))
        rows.append([fieldLabel("Crosstalk:"), sheetRow([sheetUnitLabel("shows"), crosstalkPopup])])
        if !faces {
            rows.append([
                fieldLabel("Ignore bleed:"),
                sheetRow([bleedField, sheetUnitLabel("dB below a speaker's own level")]),
            ])
        }
        for (box, on) in [
            (wideAfterBox, opened.wideAfter != nil),
            (muteBox, first.map(SpeakerSwitch.muteDefault) ?? true),
        ] {
            box.state = on ? .on : .off
            box.font = DS.sans(13)
            box.target = self
            box.action = #selector(controlChanged(_:))
        }
        wideAfterField.isEnabled = wideAfterBox.state == .on
        rows.append([
            NSGridCell.emptyContentView,
            sheetRow([wideAfterBox, wideAfterField, sheetUnitLabel("s on one speaker")]),
        ])
        rows.append([NSGridCell.emptyContentView, muteBox])

        let replaceable = first.map {
            SpeakerSwitch.replaceable($0, selection: document.selection, in: snapshot)
        } ?? []
        if !replaceable.isEmpty {
            let titles = SpeakerSwitch.titles(replaceable, in: snapshot)
            fill(
                writePopup, replaceable.map { ("Replace the shots on \(titles[$0] ?? "")", $0) },
                selected: nil, none: "A new Program track")
            rows.append([fieldLabel("Write to:"), writePopup])
        }

        summaryLabel.font = DS.sans(12)
        summaryLabel.textColor = DS.textMuted
        summaryLabel.preferredMaxLayoutWidth = Self.width - sheetInset * 2
        summaryLabel.setAccessibilityIdentifier("switchspeaker.summary")

        let cancel = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let apply = StickerButton(
            title: "Switch", style: .primary, target: self, action: #selector(switchClicked(_:)))
        apply.isEnabled = false
        switchButton = apply
        view = makeSheetView(
            title: "Switch by Speaker",
            hint: "Cuts a Program track from the cameras, showing whoever talks on each "
                + "microphone. Run Synchronize Audio first. One undo step.",
            content: sheetColumn([makeSheetGrid(rows), summaryLabel]),
            buttonRow: makeButtonRow(cancel: cancel, apply: apply), width: Self.width)
        replan()
    }

    /// A popup of `(title, track)` rows, `none` (track nil) first when given.
    private func popup(_ rows: [(String, UInt32)], selected: UInt32?, none: String?)
        -> NSPopUpButton
    {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        fill(button, rows, selected: selected, none: none)
        return button
    }

    private func fill(
        _ button: NSPopUpButton, _ rows: [(String, UInt32)], selected: UInt32?, none: String?
    ) {
        if let none { button.addItem(withTitle: none) }
        for (title, track) in rows {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = NSNumber(value: track)
            button.menu?.addItem(item)
        }
        let index = selected.flatMap { track in
            button.itemArray.firstIndex { ($0.representedObject as? NSNumber)?.uint32Value == track }
        }
        button.selectItem(at: index ?? 0)
        button.font = DS.sans(13)
        button.target = self
        button.action = #selector(controlChanged(_:))
    }

    private func track(of button: NSPopUpButton) -> UInt32? {
        (button.selectedItem?.representedObject as? NSNumber)?.uint32Value
    }

    private func style(_ field: NSTextField, range: ClosedRange<Double>, value: Double) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        field.formatter = formatter
        field.delegate = self
        field.alignment = .right
        field.doubleValue = value
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        DSField.style(field)
    }

    // MARK: - Values

    /// What the controls say, each number inside its range; `min_turn` and `dominance_db` keep
    /// their defaults (SW-26 (d)).
    private var settings: SpeakerSwitch.Settings {
        func clamped(_ field: NSTextField, _ range: ClosedRange<Double>) -> Double {
            min(max(field.doubleValue, range.lowerBound), range.upperBound)
        }
        var s = opened
        s.minShot = clamped(minShotField, SpeakerSwitch.Settings.minShotRange)
        s.lead = clamped(leadField, SpeakerSwitch.Settings.leadRange)
        s.bleedDB = clamped(bleedField, SpeakerSwitch.Settings.bleedRange)
        s.crosstalk = crosstalkPopup.indexOfSelectedItem == 1 ? .hold : .wide
        s.wideAfter = wideAfterBox.state == .on
            ? clamped(wideAfterField, SpeakerSwitch.Settings.wideAfterRange) : nil
        return s
    }

    private var chosenPairing: SpeakerSwitch.Pairing {
        if faces {
            // SW-85: every angle with the one microphone, less a shared speaker on the Wide.
            let mic = micPopups.first.flatMap { track(of: $0) }
            return SpeakerSwitch.withoutWide(SpeakerSwitch.Pairing(
                speakers: angles.map { SpeakerSwitch.Speaker(mic: mic, angle: $0) },
                wide: track(of: widePopup)))
        }
        return SpeakerSwitch.Pairing(
            speakers: zip(micPopups, cameraPopups).map {
                SpeakerSwitch.Speaker(mic: track(of: $0), angle: track(of: $1))
            },
            wide: track(of: widePopup))
    }

    /// `read` → `plan` → `edit` over the document's current handle: the edit and the summary's
    /// text, or the refusals one per line.
    private func planned(_ document: ProjectDocument) -> (SpeakerSwitch.Edit?, String) {
        guard let input = SpeakerSwitch.read(
            from: document, clips: nil, pairing: chosenPairing, range: nil, settings: settings)
        else {
            return (nil, "The project's audio plan could not be read. Try again in a moment.")
        }
        switch SpeakerSwitch.plan(input) {
        case .refused(let reasons):
            return (nil, reasons.joined(separator: "\n"))
        case .planned(let shots, let added):
            let container = document.editedProject
            let replacing = writePopup.numberOfItems > 0 ? track(of: writePopup) : nil
            if let replacing, let why = SpeakerSwitch.replaceRefusal(
                replacing, input: input, selection: document.selection, in: container.snapshot)
            {
                return (nil, why)
            }
            do {
                switch try SpeakerSwitch.edit(
                    shots, input: input, muteCameras: muteBox.state == .on, replacing: replacing,
                    selection: document.selection, in: container)
                {
                case .edit(let edit):
                    return (edit, SpeakerSwitch.summary(shots, added: added, names: names))
                case .refused(let why):
                    return (nil, why)
                }
            } catch {
                return (nil, error.localizedDescription)
            }
        }
    }

    /// Plans again on main and says what Switch would do.
    private func replan() {
        guard let document else { return }
        let (edit, text) = planned(document)
        self.edit = edit
        // SW-82: the hedge leads the summary while the pairing is the faces mode.
        summaryLabel.stringValue = SpeakerSwitch.mode(chosenPairing) == .faces
            ? FaceActivity.hedge + (edit == nil ? "\n" : " ") + text : text
        switchButton?.isEnabled = edit != nil
        acceptIfAsked()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        acceptIfAsked()
    }

    /// The dev accept: Switch pressed once, async, at the first edit with the sheet up.
    private func acceptIfAsked() {
        #if FRAMEJOB_DEV_TOOLS
        guard edit != nil, !accepted, view.window != nil,
            UserDefaults.standard.bool(forKey: Self.devAcceptKey)
        else { return }
        accepted = true
        DispatchQueue.main.async { [weak self] in self?.switchClicked(nil) }
        #endif
    }

    // MARK: - Controls

    @objc private func controlChanged(_ sender: Any?) {
        wideAfterField.isEnabled = wideAfterBox.state == .on
        replan()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        let range: ClosedRange<Double>
        switch field {
        case minShotField: range = SpeakerSwitch.Settings.minShotRange
        case leadField: range = SpeakerSwitch.Settings.leadRange
        case bleedField: range = SpeakerSwitch.Settings.bleedRange
        default: range = SpeakerSwitch.Settings.wideAfterRange
        }
        field.doubleValue = min(max(field.doubleValue, range.lowerBound), range.upperBound)
        replan()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    @objc private func switchClicked(_ sender: Any?) {
        replan()
        guard let document, let edit else { return }
        var settings = self.settings
        // SW-85: the one-microphone form's Minimum shot is never remembered.
        if faces { settings.minShot = opened.minShot }
        dismiss(self)
        document.applyEdit(SpeakerSwitch.actionName, edit.ops)
        document.selection = edit.selection
        settings.remember(changedFrom: opened, in: .standard)
    }
}
