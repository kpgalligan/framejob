import AppKit

/// The rate controls the Speed and Speed Ramp sheets share: the field, the
/// presets pull-down, the row they sit on and the range footnote (#359).
/// The rates themselves are `SpeedSheetController`'s statics — `rateRange`,
/// `presets` and `title(for:)` — which both sheets and the probes read.
enum SpeedRateControls {
    /// The rate field: a decimal formatter holding §6's clamp, so the field
    /// refuses a rate outside it rather than the core silently clamping a
    /// number the user typed.
    static func styleRateField(
        _ field: NSTextField, initial: Double, delegate: NSTextFieldDelegate
    ) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.minimum = NSNumber(value: SpeedSheetController.rateRange.lowerBound)
        formatter.maximum = NSNumber(value: SpeedSheetController.rateRange.upperBound)
        field.formatter = formatter
        field.delegate = delegate
        field.alignment = .right
        field.doubleValue = initial
        field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        DSField.style(field)
    }

    /// The presets pull-down. A pull-down's first item is its title and is
    /// never chosen, so it carries no rate; every other item carries its
    /// rate as an `NSNumber`.
    static func fillPresets(_ popup: NSPopUpButton, target: AnyObject, action: Selector) {
        popup.menu?.addItem(item("Presets", nil))
        for preset in SpeedSheetController.presets {
            popup.menu?.addItem(
                item(SpeedSheetController.title(for: preset), NSNumber(value: preset)))
        }
        popup.font = DS.sans(13)
        popup.target = target
        popup.action = action
        popup.widthAnchor.constraint(equalToConstant: 96).isActive = true
    }

    /// The rate the chosen preset carries; nil for the pull-down's face.
    static func preset(of popup: NSPopUpButton) -> Double? {
        (popup.selectedItem?.representedObject as? NSNumber)?.doubleValue
    }

    /// The field, its "×" and the presets, on one grid row.
    static func rateRow(field: NSTextField, presets: NSPopUpButton) -> NSStackView {
        sheetRow([field, sheetUnitLabel("×"), presets])
    }

    /// The rate range, "×min – ×max": the button row's footnote.
    static func rangeFootnote() -> NSTextField {
        let range = SpeedSheetController.rateRange
        return sheetFootnote(String(format: "×%g – ×%g", range.lowerBound, range.upperBound))
    }

    /// `rate` held inside §6's clamp.
    static func clamp(_ rate: Double) -> Double {
        let range = SpeedSheetController.rateRange
        return min(max(rate, range.lowerBound), range.upperBound)
    }

    private static func item(_ title: String, _ value: Any?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = value
        return item
    }
}
