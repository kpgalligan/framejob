import AppKit

/// The export card's Stems row (road map "audio" AP10 part 2a, spec §11 AU-108): "Stems:"
/// after Bit depth, offering None, One per Track and One per Track Name — files beside the
/// mix, each a track's sound before the master — None the default. It is live only on a row
/// that lists modes (`ExportPreset.stems`, the three audio rows); on every other row it is
/// disabled and shows the last choice, as Bit depth does, and sends no override. The choice
/// is remembered with the rest of the card (`ExportChoice`).
extension ExportSheetController {
    /// The popup's items: its title and the core's word, nil for None.
    static let stemModes: [(title: String, mode: String?)] = [
        ("None", nil), ("One per Track", "tracks"), ("One per Track Name", "names"),
    ]

    /// The popup's items, each carrying its mode, and its wiring. Called from `loadView`
    /// before the remembered choice is applied.
    func configureStems() {
        for (title, mode) in Self.stemModes {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = mode
            stemsPopup.menu?.addItem(item)
        }
        stemsPopup.font = DS.sans(13)
        stemsPopup.target = self
        stemsPopup.action = #selector(stemsChanged(_:))
        stemsPopup.widthAnchor.constraint(equalToConstant: 186).isActive = true
        syncStems(Applies(currentPreset))
    }

    /// A pick: the choice, then a resolve, so the footnote follows the core's echo.
    @objc func stemsChanged(_ sender: Any?) {
        stemsChoice = stemsPopup.selectedItem?.representedObject as? String
        resolveCard()
    }

    /// The `stems` override: the choice on a row that takes one, nil elsewhere.
    func stemsOverride() -> String? {
        Applies(currentPreset).stems ? stemsChoice : nil
    }

    /// The popup follows the format: live on a row that lists modes, disabled elsewhere,
    /// showing the choice either way.
    func syncStems(_ applies: Applies) {
        stemsPopup.isEnabled = applies.stems
        let shown = stemsPopup.itemArray.first {
            $0.representedObject as? String == stemsChoice
        }
        stemsPopup.select(shown)
    }

    /// A stored choice's mode, None when it names none (or one this build lacks).
    func applyStems(_ choice: ExportChoice) {
        stemsChoice = choice.stems.flatMap { stored in
            Self.stemModes.contains { $0.mode == stored } ? stored : nil
        }
    }
}
