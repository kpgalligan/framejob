import AVFoundation
import AppKit
import ScreenCaptureKit

/// The recorder panel's rows: how they are built into the card, what fills
/// the Source, Microphone and Record Into popups, how the controls become one
/// `RecordingChoice`, and how that choice is written to and read back from
/// `UserDefaults` — `RecorderPanelController.swift`'s second file, cut at the
/// 400-line cap.
///
/// Two rules live here. **The Source rows come from `NSScreen`, never from
/// `SCShareableContent`** — listing shareable content needs the Screen
/// Recording grant, and the panel must open, show the displays and explain
/// the refusal without one; the `CGDirectDisplayID` each row carries is what
/// `ScreenRecorder.filter(for:in:excluding:)` looks up once the grant is there. And
/// **every popup built from model objects carries the object in
/// `representedObject` and is read from `selectedItem`**: a display id, a
/// microphone's `uniqueID`, a document's `recipeKey` — never an index, and
/// never `addItem(withTitle:)`, which removes a same-titled row (phase 4's
/// defect; two untitled documents read alike).
extension RecorderPanelController {
    // MARK: - Rows

    func buildRows(into content: NSStackView) {
        for popup in [sourcePopup, microphonePopup, ratePopup, sizePopup, destinationPopup] {
            popup.font = DS.sans(13)
            popup.target = self
            popup.action = #selector(controlChanged(_:))
        }
        for popup in [sourcePopup, ratePopup, sizePopup, destinationPopup] {
            popup.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        }
        microphonePopup.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        for toggle in [systemAudioSwitch, showClicksSwitch] {
            toggle.target = self
            toggle.action = #selector(controlChanged(_:))
        }
        includeFrameJobCheckbox.font = DS.sans(13)
        includeFrameJobCheckbox.target = self
        includeFrameJobCheckbox.action = #selector(controlChanged(_:))
        for rate in Self.rates {
            let item = NSMenuItem(title: "\(rate) fps", action: nil, keyEquivalent: "")
            item.tag = rate
            ratePopup.menu?.addItem(item)
        }
        for resolution in RecordingResolution.allCases {
            let item = NSMenuItem(
                title: resolution == .nominal ? "Nominal (points)" : "Best (pixels)",
                action: nil, keyEquivalent: "")
            item.representedObject = resolution.rawValue
            sizePopup.menu?.addItem(item)
        }
        // 120 pt exactly: the meter hugs at priority 1 and draws nothing under
        // 40, so without a width of its own the row would starve it.
        meterView.widthAnchor.constraint(equalToConstant: LevelMeterView.intrinsicWidth)
            .isActive = true
        meterView.setAccessibilityLabel("Microphone level")
        let microphoneRow = NSStackView(views: [microphonePopup, meterView])
        microphoneRow.orientation = .horizontal
        microphoneRow.alignment = .centerY
        microphoneRow.spacing = 8

        sizeNote.font = DS.mono(11)
        sizeNote.textColor = DS.textFaint

        let grid = NSGridView(views: [
            [fieldLabel("Source:"), sourcePopup],
            [NSGridCell.emptyContentView, includeFrameJobCheckbox],
            [fieldLabel("Microphone:"), microphoneRow],
            [fieldLabel("System Audio:"), systemAudioSwitch],
            [fieldLabel("Show Clicks:"), showClicksSwitch],
            [fieldLabel("Rate:"), ratePopup],
            [fieldLabel("Size:"), sizePopup],
            [NSGridCell.emptyContentView, sizeNote],
            [fieldLabel("Record Into:"), destinationPopup],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 106

        let inner = Self.cardWidth - sheetInset * 2
        countdownLabel.font = DS.display(56)
        countdownLabel.textColor = DS.meterClip
        countdownLabel.alignment = .center
        countdownLabel.widthAnchor.constraint(equalToConstant: inner).isActive = true
        countdownLabel.isHidden = true

        // `TranscribeSheetController`'s note: sans 11, faint, wrapping, hidden
        // when there is nothing to say.
        noteLabel.font = DS.sans(11)
        noteLabel.textColor = DS.textFaint
        noteLabel.preferredMaxLayoutWidth = inner
        noteLabel.isHidden = true

        statusLabel.font = DS.mono(10)
        statusLabel.textColor = DS.textFaint
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.addArrangedSubview(grid)
        content.addArrangedSubview(countdownLabel)
        content.addArrangedSubview(noteLabel)
    }

    // MARK: - Sources, microphones, destinations

    /// One row per `NSScreen`, by `localizedName`, carrying its
    /// `CGDirectDisplayID`; then "Window…", which presents the picker, and
    /// "Microphone Only" (`+VoiceOver.swift`). Built
    /// from `NSScreen` and NOT from `SCShareableContent`, because listing
    /// shareable content needs the Screen Recording grant and the panel must
    /// open without one. Reselects Microphone Only, the picked row or the
    /// current display.
    func rebuildSources() {
        let current = selectedDisplayID
        let voiceOver = voiceOverSelected
        let picked = pickedFilter != nil && sourcePopup.selectedItem?.tag == Self.windowTag
        sourcePopup.removeAllItems()
        for screen in NSScreen.screens {
            let item = NSMenuItem(title: screen.localizedName, action: nil, keyEquivalent: "")
            item.representedObject = NSNumber(value: Self.displayID(of: screen))
            sourcePopup.menu?.addItem(item)
        }
        sourcePopup.menu?.addItem(.separator())
        let window = NSMenuItem(
            title: picked ? "Window (picked)" : "Window…", action: nil, keyEquivalent: "")
        window.tag = Self.windowTag
        sourcePopup.menu?.addItem(window)
        let microphoneOnly = NSMenuItem(
            title: Self.microphoneOnlyTitle, action: nil, keyEquivalent: "")
        microphoneOnly.tag = Self.voiceOverTag
        sourcePopup.menu?.addItem(microphoneOnly)
        if voiceOver {
            sourcePopup.select(microphoneOnly)
        } else if picked {
            sourcePopup.select(window)
        } else {
            selectDisplay(current)
        }
    }

    /// "Off", then every microphone the discovery session lists, carrying its
    /// `uniqueID` — the same session `ScreenRecorder.microphone(withID:)` asks,
    /// so a row here is a device the recorder can find.
    func rebuildMicrophones() {
        let current = microphonePopup.selectedItem?.representedObject as? String
        microphonePopup.removeAllItems()
        microphonePopup.menu?.addItem(NSMenuItem(title: "Off", action: nil, keyEquivalent: ""))
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
        for device in devices {
            let item = NSMenuItem(title: device.localizedName, action: nil, keyEquivalent: "")
            item.representedObject = device.uniqueID
            microphonePopup.menu?.addItem(item)
        }
        selectMicrophone(current)
    }

    /// "New Project" first, then every open document by `displayName` with
    /// its `recipeKey` in `representedObject`. The selection is the person's
    /// own choice while its document is still open, else the front document,
    /// else New Project.
    ///
    /// **Idle only** (R1 review). The rows used to follow the front document
    /// through a recording, so a person who pressed Record over "Untitled 2"
    /// and then clicked into "Untitled 3" to record it watched the row change
    /// to a document the recording was never going to land in — the choice
    /// was captured at the countdown's end. The guard is HERE rather than in
    /// the sync timer alone because the timer is not the only caller:
    /// `show()`, which the quit guard runs during a recording, rebuilds too.
    /// `landed()` sets the phase idle before its own rebuild, which is what
    /// moves the rows again.
    func rebuildDestinations() {
        guard phase == .idle else { return }
        let rows = Self.destinationRows()
        let listed = destinationPopup.itemArray.dropFirst().map { item in
            (item.title, (item.representedObject as? NSNumber)?.intValue ?? 0)
        }
        if destinationPopup.numberOfItems == 0 || !listed.elementsEqual(rows, by: { $0 == $1 }) {
            destinationPopup.removeAllItems()
            destinationPopup.menu?.addItem(
                NSMenuItem(title: "New Project", action: nil, keyEquivalent: ""))
            for (title, key) in rows {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.representedObject = NSNumber(value: key)
                destinationPopup.menu?.addItem(item)
            }
        }
        var wanted: Int?
        switch chosenDestination {
        case .some(.document(let key)) where rows.contains(where: { $0.1 == key }):
            wanted = key
        case .some(.newProject):
            wanted = nil
        default:
            chosenDestination = nil
            wanted = Self.frontDocument()?.recipeKey
        }
        let index =
            wanted.flatMap { key in
                destinationPopup.itemArray.firstIndex {
                    ($0.representedObject as? NSNumber)?.intValue == key
                }
            } ?? 0
        if destinationPopup.indexOfSelectedItem != index { destinationPopup.selectItem(at: index) }
    }

    static func destinationRows() -> [(String, Int)] {
        NSDocumentController.shared.documents.compactMap { $0 as? ProjectDocument }.map {
            ($0.displayName ?? "Untitled", $0.recipeKey)
        }
    }

    /// `currentDocument` first (nil when the app is not active), then the
    /// front of `orderedDocuments` — `AgentServer.target`'s rule.
    static func frontDocument() -> ProjectDocument? {
        if let current = NSDocumentController.shared.currentDocument as? ProjectDocument {
            return current
        }
        return NSApp.orderedDocuments.compactMap { $0 as? ProjectDocument }.first
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    var selectedDisplayID: CGDirectDisplayID {
        (sourcePopup.selectedItem?.representedObject as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
    }

    var selectedScreen: NSScreen? {
        guard sourcePopup.selectedItem?.tag != Self.windowTag, !voiceOverSelected else { return nil }
        let id = selectedDisplayID
        return NSScreen.screens.first { Self.displayID(of: $0) == id }
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        let index =
            sourcePopup.itemArray.firstIndex {
                ($0.representedObject as? NSNumber)?.uint32Value == id
            } ?? 0
        sourcePopup.selectItem(at: index)
    }

    func selectMicrophone(_ id: String?) {
        let index =
            id.flatMap { wanted in
                microphonePopup.itemArray.firstIndex { $0.representedObject as? String == wanted }
            } ?? 0
        microphonePopup.selectItem(at: index)
    }

    // MARK: - The choice, persisted and restored

    /// The controls as one value. `.picked` only while the picker's filter
    /// is held; a "Window…" row with no filter (the picker was cancelled and
    /// the row not reselected) falls back to the main display.
    func currentChoice() -> RecordingChoice {
        var choice = RecordingChoice()
        if voiceOverSelected {
            choice.source = .voiceOver
        } else if sourcePopup.selectedItem?.tag == Self.windowTag, pickedFilter != nil {
            choice.source = .picked
        } else {
            choice.source = .display(selectedDisplayID)
        }
        choice.includeFrameJobWindows = includeFrameJobCheckbox.state == .on
        choice.microphone = microphonePopup.selectedItem?.representedObject as? String
        choice.systemAudio = systemAudioSwitch.state == .on
        choice.showClicks = showClicksSwitch.state == .on
        choice.rate = Self.rates.contains(ratePopup.selectedTag()) ? ratePopup.selectedTag() : 60
        choice.resolution =
            RecordingResolution(rawValue: sizePopup.selectedItem?.representedObject as? String ?? "")
            ?? .nominal
        if let key = destinationPopup.selectedItem?.representedObject as? NSNumber {
            choice.destination = .document(recipeKey: key.intValue)
        } else {
            choice.destination = .newProject
        }
        return choice
    }

    /// Writes every control but the destination (a `recipeKey` is minted per
    /// process) and a picked window (a filter is not a value). The display
    /// key is left alone while the Window row or Microphone Only (a
    /// session-only row) is selected.
    func persistChoices() {
        let defaults = UserDefaults.standard
        if sourcePopup.selectedItem?.tag != Self.windowTag, !voiceOverSelected {
            defaults.set(Int(selectedDisplayID), forKey: Self.displayKey)
        }
        defaults.set(
            microphonePopup.selectedItem?.representedObject as? String ?? "",
            forKey: Self.microphoneKey)
        defaults.set(systemAudioSwitch.state == .on, forKey: Self.systemAudioKey)
        defaults.set(showClicksSwitch.state == .on, forKey: Self.showClicksKey)
        defaults.set(
            includeFrameJobCheckbox.state == .on, forKey: Self.includeFrameJobWindowsKey)
        defaults.set(currentChoice().rate, forKey: Self.rateKey)
        defaults.set(currentChoice().resolution.rawValue, forKey: Self.sizeKey)
    }

    /// The stored choices, each falling back to `RecordingChoice`'s default
    /// for an absent or stale value: a display no longer attached is the
    /// main one, a microphone no longer connected is Off, system audio is ON
    /// when nothing is stored (`bool(forKey:)` of an absent key is false, so
    /// the absence is tested by name).
    func restoreChoices() {
        let defaults = UserDefaults.standard
        if pickedFilter == nil, !voiceOverSelected {
            let stored = defaults.integer(forKey: Self.displayKey)
            selectDisplay(stored > 0 ? CGDirectDisplayID(clamping: stored) : CGMainDisplayID())
        }
        let mic = defaults.string(forKey: Self.microphoneKey) ?? ""
        selectMicrophone(mic.isEmpty ? nil : mic)
        let systemAudio =
            defaults.object(forKey: Self.systemAudioKey) == nil
            ? RecordingChoice().systemAudio : defaults.bool(forKey: Self.systemAudioKey)
        systemAudioSwitch.state = systemAudio ? .on : .off
        showClicksSwitch.state = defaults.bool(forKey: Self.showClicksKey) ? .on : .off
        includeFrameJobCheckbox.state =
            defaults.bool(forKey: Self.includeFrameJobWindowsKey) ? .on : .off
        let rate = defaults.integer(forKey: Self.rateKey)
        _ = ratePopup.selectItem(withTag: Self.rates.contains(rate) ? rate : RecordingChoice().rate)
        let size = defaults.string(forKey: Self.sizeKey) ?? ""
        let resolution = RecordingResolution(rawValue: size) ?? RecordingChoice().resolution
        sizePopup.selectItem(at: RecordingResolution.allCases.firstIndex(of: resolution) ?? 0)
    }

    /// `1728×1117 points · 3456×2234 pixels` for the chosen display; a picked
    /// window records at its own size, which the panel cannot know; a
    /// voice-over has no picture.
    func refreshSizeNote() {
        if voiceOverSelected {
            sizeNote.stringValue = Self.voiceOverSizeNote
            return
        }
        guard let screen = selectedScreen else {
            sizeNote.stringValue = "the picked window's own size"
            return
        }
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        sizeNote.stringValue =
            "\(Int(size.width))×\(Int(size.height)) points · "
            + "\(Int((size.width * scale).rounded()))×\(Int((size.height * scale).rounded())) pixels"
    }
}
