import AppKit
import ScreenCaptureKit

/// The recorder panel's window picker (road map 3, R1c) —
/// `RecorderPanelController.swift`'s fifth file, cut out of `+Recording.swift`
/// along the line `presentPicker` draws when the R1 review's fixes put that
/// file past the 400-line cap. The Source row's last item, "Window…",
/// presents `SCContentSharingPicker` in single-window mode; the filter it
/// answers with is held in `pickedFilter` beside the choice (a filter is not
/// a value, so `.picked` is the one source that cannot persist), and a
/// cancel or a failure puts the Source row back on the display the person
/// last chose. Record with the row reading "Window…" and no filter held is
/// refused by name in `+Recording.swift`, never answered by presenting the
/// picker from the guard.
extension RecorderPanelController {
    // MARK: - The window picker

    /// `SCContentSharingPicker` in single-window mode, Reelcut's own windows
    /// excluded from the LIST — `excludedBundleIDs` is documented "for
    /// picking" and says nothing about capture (R0 q3), which is why R1 hid
    /// the panel for a picked window alone; since R2 every recording hides
    /// it (decision 7), and the exclusion is about the list only. The
    /// observer is added once; the picker is activated for the presentation
    /// and deactivated when it answers.
    func presentPicker() {
        let picker = SCContentSharingPicker.shared
        if !pickerObserved {
            picker.add(self)
            pickerObserved = true
        }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present(using: .window)
    }

    /// Back to the display the person last chose (the persisted one), with
    /// the Window row reading "Window…" again.
    private func revertSourceRow() {
        pickedFilter = nil
        sourcePopup.menu?.item(withTag: Self.windowTag)?.title = "Window…"
        let stored = UserDefaults.standard.integer(forKey: Self.displayKey)
        selectDisplay(stored > 0 ? CGDirectDisplayID(clamping: stored) : CGMainDisplayID())
        refreshSizeNote()
    }
}

extension RecorderPanelController: SCContentSharingPickerObserver {
    /// The picker answers on a queue of its own; every arm hops to main.
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            picker.isActive = false
            self?.revertSourceRow()
        }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            picker.isActive = false
            self.pickedFilter = filter
            self.sourcePopup.menu?.item(withTag: Self.windowTag)?.title = "Window (picked)"
            _ = self.sourcePopup.selectItem(withTag: Self.windowTag)
            self.refreshSizeNote()
            self.setNote("")
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        DispatchQueue.main.async { [weak self] in
            SCContentSharingPicker.shared.isActive = false
            self?.revertSourceRow()
            self?.setNote("The window picker could not open: " + error.localizedDescription)
        }
    }
}
