import AVFoundation
import AppKit
import ScreenCaptureKit

/// The recorder panel's choice: how the controls become one
/// `RecordingChoice`, how that choice is written to and read back from
/// `UserDefaults`, and the size note beside it. A pure move out of
/// `RecorderPanelController+Rows.swift` under road map "creator-jobs"
/// CU0a's toll U3.
extension RecorderPanelController {
    // MARK: - The choice, persisted and restored

    /// The controls as one value. `.picked` only while the picker's filter
    /// is held; a "Window…" row with no filter (the picker was cancelled and
    /// the row not reselected) falls back to the main display. `camera` is
    /// the Camera popup's id while a camera is wanted (Source Camera, or the
    /// box beside a screen source: CAM-11 (3)), and nil otherwise;
    /// `cameraFormat` the Format popup's spelling beside it, nil for Best.
    func currentChoice() -> RecordingChoice {
        var choice = RecordingChoice()
        if voiceOverSelected {
            choice.source = .voiceOver
        } else if cameraSelected {
            choice.source = .camera
        } else if sourcePopup.selectedItem?.tag == Self.windowTag, pickedFilter != nil {
            choice.source = .picked
        } else {
            choice.source = .display(selectedDisplayID)
        }
        if cameraWanted {
            choice.camera = selectedCameraID
            choice.cameraFormat = selectedCameraFormat
        }
        choice.includeFrameJobWindows = includeFrameJobCheckbox.state == .on
        choice.microphone = microphonePopup.selectedItem?.representedObject as? String
        choice.enhanceMicrophone = enhanceMicrophoneCheckbox.state == .on && choice.microphone != nil
        choice.systemAudio = systemAudioSwitch.state == .on
        choice.showClicks = showClicksSwitch.state == .on
        // CU-62: shortcuts only with a screen source; off for Microphone Only and Camera.
        choice.keys =
            recordShortcutsCheckbox.state == .on && !voiceOverSelected && !cameraSelected
            ? .shortcuts : .off
        // CU-36: the person's pick, nil for the source's default; none without a screen source.
        choice.cursor = voiceOverSelected || cameraSelected ? nil : cursorChosen
        choice.rate = Self.rates.contains(ratePopup.selectedTag()) ? ratePopup.selectedTag() : 60
        choice.resolution =
            RecordingResolution(rawValue: sizePopup.selectedItem?.representedObject as? String ?? "")
            ?? .nominal
        if let key = destinationPopup.selectedItem?.representedObject as? NSNumber {
            choice.destination = .document(recipeKey: key.intValue)
        } else {
            choice.destination = .newProject
        }
        applyPolish(to: &choice)
        applyCameraLanding(to: &choice)
        return choice
    }

    /// Writes every control but the destination (a `recipeKey` is minted per
    /// process) and a picked window (a filter is not a value). The display
    /// key is left alone while the Window row, Microphone Only or Camera (the
    /// two session-only rows) is selected. The camera key, and the format
    /// key beside it (`""` for Best), are written only while the Camera popup
    /// names one, so "None connected" forgets nothing. The box's key is written
    /// on every change (CAM-11 (2)).
    func persistChoices() {
        let defaults = UserDefaults.standard
        if sourcePopup.selectedItem?.tag != Self.windowTag, !voiceOverSelected, !cameraSelected {
            defaults.set(Int(selectedDisplayID), forKey: Self.displayKey)
        }
        defaults.set(
            microphonePopup.selectedItem?.representedObject as? String ?? "",
            forKey: Self.microphoneKey)
        if let camera = selectedCameraID {
            defaults.set(camera, forKey: Self.cameraKey)
            defaults.set(selectedCameraFormat ?? "", forKey: Self.cameraFormatKey)
        }
        defaults.set(systemAudioSwitch.state == .on, forKey: Self.systemAudioKey)
        defaults.set(showClicksSwitch.state == .on, forKey: Self.showClicksKey)
        defaults.set(
            includeFrameJobCheckbox.state == .on, forKey: Self.includeFrameJobWindowsKey)
        defaults.set(cameraBesideCheckbox.state == .on, forKey: Self.cameraBesideKey)
        defaults.set(enhanceMicrophoneCheckbox.state == .on, forKey: Self.enhanceMicrophoneKey)
        defaults.set(recordShortcutsCheckbox.state == .on, forKey: Self.keysKey)
        // CU-36 (d): the pick, never the row shown; `""` follows the source.
        defaults.set(cursorChosen?.rawValue ?? "", forKey: Self.cursorKey)
        defaults.set(currentChoice().rate, forKey: Self.rateKey)
        defaults.set(currentChoice().resolution.rawValue, forKey: Self.sizeKey)
        persistPolish(defaults)
        persistCameraLanding(defaults)
    }

    /// The stored choices, each falling back to `RecordingChoice`'s default
    /// for an absent or stale value: a display no longer attached is the
    /// main one, a microphone no longer connected is Off, a camera no longer
    /// connected is the default camera, system audio is ON
    /// when nothing is stored (`bool(forKey:)` of an absent key is false, so
    /// the absence is tested by name).
    func restoreChoices() {
        let defaults = UserDefaults.standard
        if pickedFilter == nil, !voiceOverSelected, !cameraSelected {
            let stored = defaults.integer(forKey: Self.displayKey)
            selectDisplay(stored > 0 ? CGDirectDisplayID(clamping: stored) : CGMainDisplayID())
        }
        let mic = defaults.string(forKey: Self.microphoneKey) ?? ""
        selectMicrophone(mic.isEmpty ? nil : mic)
        let camera = defaults.string(forKey: Self.cameraKey) ?? ""
        selectCamera(camera.isEmpty ? nil : camera)
        let systemAudio =
            defaults.object(forKey: Self.systemAudioKey) == nil
            ? RecordingChoice().systemAudio : defaults.bool(forKey: Self.systemAudioKey)
        systemAudioSwitch.state = systemAudio ? .on : .off
        showClicksSwitch.state = defaults.bool(forKey: Self.showClicksKey) ? .on : .off
        includeFrameJobCheckbox.state =
            defaults.bool(forKey: Self.includeFrameJobWindowsKey) ? .on : .off
        cameraBesideCheckbox.state = defaults.bool(forKey: Self.cameraBesideKey) ? .on : .off
        enhanceMicrophoneCheckbox.state =
            defaults.bool(forKey: Self.enhanceMicrophoneKey) ? .on : .off
        recordShortcutsCheckbox.state = defaults.bool(forKey: Self.keysKey) ? .on : .off
        cursorChosen = RecordingCursor(rawValue: defaults.string(forKey: Self.cursorKey) ?? "")
        let rate = defaults.integer(forKey: Self.rateKey)
        _ = ratePopup.selectItem(withTag: Self.rates.contains(rate) ? rate : RecordingChoice().rate)
        let size = defaults.string(forKey: Self.sizeKey) ?? ""
        let resolution = RecordingResolution(rawValue: size) ?? RecordingChoice().resolution
        sizePopup.selectItem(at: RecordingResolution.allCases.firstIndex(of: resolution) ?? 0)
        restorePolish(defaults)
        restoreCameraLanding(defaults)
    }

    /// The Cursor popup shows the person's pick, else the screen source's
    /// default: Separate for every screen source (spec §11 CU-36, amended at
    /// CU0d). Left as it is for Microphone Only and Camera, whose row is
    /// greyed with its value kept.
    func syncCursorPopup() {
        guard !voiceOverSelected, !cameraSelected else { return }
        let shown = cursorChosen ?? .defaultFor(currentChoice().source)
        if let item = cursorPopup.itemArray.first(where: {
            $0.representedObject as? String == shown.rawValue
        }) {
            cursorPopup.select(item)
        }
    }

    /// `1728×1117 points · 3456×2234 pixels` for the chosen display; a picked
    /// window records at its own size, which the panel cannot know; a
    /// voice-over has no picture; a camera records at its best format. The
    /// Cursor popup is synced FIRST, before the three early returns, so the
    /// Window row (no `selectedScreen`) follows its source too.
    func refreshSizeNote() {
        syncCursorPopup()
        if voiceOverSelected {
            sizeNote.stringValue = Self.voiceOverSizeNote
            return
        }
        if cameraSelected {
            sizeNote.stringValue = selectedCameraSizeNote
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
