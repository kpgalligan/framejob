import AppKit

/// The recorder panel's camera landing rows (road map "creator-jobs" CO8, spec §11 CO-80…CO-82):
/// the Layout pop-up — Corner, Rounded Corner, Circle, Side by Side, Camera Full — the camera
/// beside the screen lands in, and "Remove the camera's background when it lands", which runs
/// Remove Background on the landed camera clips as its own undo step (`RecordingCutout`).
/// `RecorderPanelController.swift`'s fourteenth file, NEW rather than cut, in `+Polish.swift`'s
/// shape: the base file, `+Rows`, `+Choices` and `+VoiceOver` learn it by a line each.
///
/// **The rows** sit after the camera's preview and before Microphone, and are live only while
/// idle with "Record the camera too" ticked beside a screen source (`cameraBesideSelected`);
/// otherwise each is greyed with its value kept. The pop-up is read from
/// `selectedItem.representedObject`, never by index (`+Rows.swift`'s rule). **The keys** are
/// the panel's seventeenth and eighteenth, written on change and restored on show: an absent
/// or stale layout reads `corner_square` (the owner's Corner, today's landing), and an absent
/// cutout reads off, tested by `object(forKey:) == nil`.
final class RecorderCameraLandingControls {
    let layoutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let cutoutCheckbox = NSButton(
        checkboxWithTitle: "Remove the camera's background when it lands", target: nil,
        action: nil)

    init() {
        for layout in RecordingCameraLayout.allCases {
            let item = NSMenuItem(title: layout.title, action: nil, keyEquivalent: "")
            item.representedObject = layout.rawValue
            layoutPopup.menu?.addItem(item)
        }
        layoutPopup.toolTip = "Where the camera lands beside the screen recording."
        cutoutCheckbox.toolTip =
            "After the recording lands, run Clip ▸ Remove Background on the camera's clips as "
            + "its own undo step, \"Remove Background\"."
    }

    /// The pop-up's layout; `.cornerSquare` for no row.
    var layout: RecordingCameraLayout {
        let raw = layoutPopup.selectedItem?.representedObject as? String ?? ""
        return RecordingCameraLayout(rawValue: raw) ?? .cornerSquare
    }

    /// Selects `layout`'s row.
    func select(_ layout: RecordingCameraLayout) {
        if let item = layoutPopup.itemArray.first(where: {
            $0.representedObject as? String == layout.rawValue
        }) {
            layoutPopup.select(item)
        }
    }
}

extension RecorderPanelController {
    /// The Layout pop-up's key (spec §11 CO-82): a `RecordingCameraLayout` raw value; absent or
    /// stale reads `corner_square`.
    static let cameraLayoutKey = "FrameJobRecordingCameraLayout"
    /// The Remove-background box's key; absent reads off.
    static let cameraCutoutKey = "FrameJobRecordingCameraCutout"

    /// The grid's rows: "Layout:" beside the pop-up, then the box under it with no label.
    func cameraLandingRows() -> [[NSView]] {
        [
            [fieldLabel("Layout:"), cameraLanding.layoutPopup],
            [NSGridCell.emptyContentView, cameraLanding.cutoutCheckbox],
        ]
    }

    /// The two into the choice: the pop-up's layout with the camera beside the screen, else
    /// `.cornerSquare`; the cutout only with the camera beside the screen.
    func applyCameraLanding(to choice: inout RecordingChoice) {
        choice.cameraLayout = cameraBesideSelected ? cameraLanding.layout : .cornerSquare
        choice.cameraCutout = cameraLanding.cutoutCheckbox.state == .on && cameraBesideSelected
    }

    /// Both values, written on each change.
    func persistCameraLanding(_ defaults: UserDefaults) {
        defaults.set(cameraLanding.layout.rawValue, forKey: Self.cameraLayoutKey)
        defaults.set(cameraLanding.cutoutCheckbox.state == .on, forKey: Self.cameraCutoutKey)
    }

    /// The stored values; an absent or stale layout is `corner_square`, an absent cutout off.
    func restoreCameraLanding(_ defaults: UserDefaults) {
        cameraLanding.select(
            RecordingCameraLayout(rawValue: defaults.string(forKey: Self.cameraLayoutKey) ?? "")
                ?? .cornerSquare)
        let cutout =
            defaults.object(forKey: Self.cameraCutoutKey) == nil
            ? false : defaults.bool(forKey: Self.cameraCutoutKey)
        cameraLanding.cutoutCheckbox.state = cutout ? .on : .off
    }

    /// Live only while idle with the camera beside a screen source. `syncControlsEnabled()`'s
    /// statement after the polish's.
    func syncCameraLandingControls() {
        let live = phase == .idle && cameraBesideSelected
        cameraLanding.layoutPopup.isEnabled = live
        cameraLanding.cutoutCheckbox.isEnabled = live
    }
}
