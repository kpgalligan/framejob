import AppKit

/// The export card's Speed row (codec-export C1, spec §11 CX-2, CX-12 (2)): "Speed:" under
/// Format (after Dynamic Range when an HLG project shows that), offering Faster, Balanced
/// and Smaller file — SVT-AV1's presets 8, 6 and 4 — Balanced the default. It is live only
/// on a row a bundled encoder writes (`ExportPreset.encoderSpeeds`, the `av1` row); on every
/// other row it is disabled and shows the last choice, as Quality does, and sends no
/// override. The choice is remembered with the rest of the card (`ExportChoice`).
extension ExportSheetController {
    /// The popup's items, each carrying its speed, and its wiring. Called from `loadView`
    /// before the remembered choice is applied.
    func configureSpeed() {
        for speed in EncoderSpeed.allCases {
            let item = NSMenuItem(title: speed.menuName, action: nil, keyEquivalent: "")
            item.representedObject = speed.rawValue
            speedPopup.menu?.addItem(item)
        }
        speedPopup.font = DS.sans(13)
        speedPopup.target = self
        speedPopup.action = #selector(speedChanged(_:))
        speedPopup.widthAnchor.constraint(equalToConstant: 186).isActive = true
        syncSpeed(Applies(currentPreset))
    }

    /// A pick: the choice, then a resolve, so the footnote follows the core's echo.
    @objc func speedChanged(_ sender: Any?) {
        guard let raw = speedPopup.selectedItem?.representedObject as? String,
            let speed = EncoderSpeed(rawValue: raw)
        else { return }
        encoderSpeedChoice = speed
        resolveCard()
    }

    /// The `encoder_speed` override: the choice on a row that takes one, nil elsewhere.
    func encoderSpeedOverride() -> String? {
        Applies(currentPreset).encoderSpeed ? encoderSpeedChoice.rawValue : nil
    }

    /// The popup follows the format: live on a row that takes a speed, disabled elsewhere,
    /// showing the choice either way.
    func syncSpeed(_ applies: Applies) {
        speedPopup.isEnabled = applies.encoderSpeed
        let shown = speedPopup.itemArray.first {
            $0.representedObject as? String == encoderSpeedChoice.rawValue
        }
        speedPopup.select(shown)
    }

    /// A stored choice's speed, Balanced when it names none (or one this build lacks).
    func applySpeed(_ choice: ExportChoice) {
        encoderSpeedChoice = choice.encoderSpeed.flatMap(EncoderSpeed.init(rawValue:)) ?? .balanced
    }
}
