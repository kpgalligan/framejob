import AppKit

/// The recorder panel's "When it lands:" boxes (road map "creator-jobs" CU10, spec §11
/// CU-102 (a)): Zoom in on clicks, Show shortcuts and Speed up typing, each running its command
/// on the landed screen clips as its own undo step after the landing (`RecordingPolish`).
/// `RecorderPanelController.swift`'s thirteenth file, NEW rather than cut: the base file,
/// `+Rows`, `+Choices` and `+VoiceOver` learn it by a line each.
///
/// **The rows** sit under the Record shortcuts note and before Rate. Zoom in on clicks is live
/// only while idle with a screen source (a display, the Window row); Show shortcuts and Speed up
/// typing only then AND with Record shortcuts ticked, because without it the cursor file holds
/// no shortcut and no typing. Greyed, each keeps its value. **The keys** are the panel's
/// fourteenth to sixteenth, written on change and restored on show; an absent key reads on, on
/// and off (the owner, 2026-11-01), tested by `object(forKey:) == nil` because
/// `bool(forKey:)` of an absent key is false.
final class RecorderPolishBoxes {
    let autoZoom = NSButton(checkboxWithTitle: "Zoom in on clicks", target: nil, action: nil)
    let shortcutOverlays = NSButton(checkboxWithTitle: "Show shortcuts", target: nil, action: nil)
    let speedUpTyping = NSButton(checkboxWithTitle: "Speed up typing", target: nil, action: nil)

    /// The three, in the grid's order (and `RecordingPolish.Command.allCases`').
    var all: [NSButton] { [autoZoom, shortcutOverlays, speedUpTyping] }

    init() {
        autoZoom.toolTip = RecordingPolish.tooltip(.autoZoom)
        shortcutOverlays.toolTip = RecordingPolish.tooltip(.shortcutOverlays)
        speedUpTyping.toolTip = RecordingPolish.tooltip(.speedUpTyping)
    }
}

extension RecorderPanelController {
    /// Zoom in on clicks (spec §11 CU-102 (a)); an absent key reads as on.
    static let autoZoomKey = "FrameJobRecordingAutoZoom"
    /// Show shortcuts; an absent key reads as on.
    static let shortcutOverlaysKey = "FrameJobRecordingShortcutOverlays"
    /// Speed up typing; an absent key reads as off.
    static let speedUpTypingKey = "FrameJobRecordingSpeedUpTyping"

    /// The grid's rows: "When it lands:" beside Zoom in on clicks, then the other two under it.
    func polishRows() -> [[NSView]] {
        [
            [fieldLabel("When it lands:"), polishBoxes.autoZoom],
            [NSGridCell.emptyContentView, polishBoxes.shortcutOverlays],
            [NSGridCell.emptyContentView, polishBoxes.speedUpTyping],
        ]
    }

    /// The boxes into the choice: Auto Zoom with a screen source, the other two only with
    /// Record shortcuts (`choice.keys`, which `currentChoice` sets for a screen source alone).
    func applyPolish(to choice: inout RecordingChoice) {
        choice.autoZoom = polishBoxes.autoZoom.state == .on && screenSourceSelected
        choice.shortcutOverlays =
            polishBoxes.shortcutOverlays.state == .on && choice.keys == .shortcuts
        choice.speedUpTyping = polishBoxes.speedUpTyping.state == .on && choice.keys == .shortcuts
    }

    /// Every box's state, written on each change.
    func persistPolish(_ defaults: UserDefaults) {
        defaults.set(polishBoxes.autoZoom.state == .on, forKey: Self.autoZoomKey)
        defaults.set(polishBoxes.shortcutOverlays.state == .on, forKey: Self.shortcutOverlaysKey)
        defaults.set(polishBoxes.speedUpTyping.state == .on, forKey: Self.speedUpTypingKey)
    }

    /// The stored states; an absent key reads on, on and off (the owner's defaults).
    func restorePolish(_ defaults: UserDefaults) {
        func stored(_ key: String, absent: Bool) -> NSControl.StateValue {
            let on = defaults.object(forKey: key) == nil ? absent : defaults.bool(forKey: key)
            return on ? .on : .off
        }
        polishBoxes.autoZoom.state = stored(Self.autoZoomKey, absent: true)
        polishBoxes.shortcutOverlays.state = stored(Self.shortcutOverlaysKey, absent: true)
        polishBoxes.speedUpTyping.state = stored(Self.speedUpTypingKey, absent: false)
    }

    /// Live only while idle with a screen source; the last two also need Record shortcuts.
    /// `syncControlsEnabled()`'s last statement, after the camera's locks.
    func syncPolishControls() {
        let screen = phase == .idle && screenSourceSelected
        polishBoxes.autoZoom.isEnabled = screen
        let keys = screen && recordShortcutsCheckbox.state == .on
        polishBoxes.shortcutOverlays.isEnabled = keys
        polishBoxes.speedUpTyping.isEnabled = keys
    }
}
