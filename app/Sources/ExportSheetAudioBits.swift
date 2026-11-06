import AppKit

/// The export card's Bit depth row (road map "audio" AP2 part 2, spec §11 AU-29): "Bit
/// depth:" after Quality, offering 16-bit and 24-bit — the master's rounding from the float
/// mix, never dithered — 16-bit the default. It is live only on a row that lists depths
/// (`ExportPreset.audioBits`, `audio_wav` and `audio_aiff`); on every other row it is
/// disabled and shows the last choice, as Speed does, and sends no override. The choice is
/// remembered with the rest of the card (`ExportChoice`).
extension ExportSheetController {
    /// The two depths the popup offers.
    static let audioBitDepths = [16, 24]

    /// The popup's items, each carrying its depth, and its wiring. Called from `loadView`
    /// before the remembered choice is applied.
    func configureAudioBits() {
        for bits in Self.audioBitDepths {
            let item = NSMenuItem(title: "\(bits)-bit", action: nil, keyEquivalent: "")
            item.representedObject = bits
            audioBitsPopup.menu?.addItem(item)
        }
        audioBitsPopup.font = DS.sans(13)
        audioBitsPopup.target = self
        audioBitsPopup.action = #selector(audioBitsChanged(_:))
        audioBitsPopup.widthAnchor.constraint(equalToConstant: 186).isActive = true
        syncAudioBits(Applies(currentPreset))
    }

    /// A pick: the choice, then a resolve, so the footnote follows the core's echo.
    @objc func audioBitsChanged(_ sender: Any?) {
        guard let bits = audioBitsPopup.selectedItem?.representedObject as? Int else { return }
        audioBitsChoice = bits
        presetEdited()
        resolveCard()
    }

    /// The `audio_bits` override: the choice on a row that takes one, nil elsewhere.
    func audioBitsOverride() -> Int? {
        Applies(currentPreset).audioBits ? audioBitsChoice : nil
    }

    /// The popup follows the format: live on a row that lists depths, disabled elsewhere,
    /// showing the choice either way.
    func syncAudioBits(_ applies: Applies) {
        audioBitsPopup.isEnabled = applies.audioBits
        let shown = audioBitsPopup.itemArray.first {
            $0.representedObject as? Int == audioBitsChoice
        }
        audioBitsPopup.select(shown)
    }

    /// A stored choice's depth, 16 when it names none (or one this build lacks).
    func applyAudioBits(_ choice: ExportChoice) {
        audioBitsChoice = choice.audioBits.flatMap {
            Self.audioBitDepths.contains($0) ? $0 : nil
        } ?? 16
    }
}
