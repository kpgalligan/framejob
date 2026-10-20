import AppKit

/// The export card's Dynamic Range row (hdr H-3, spec §11 HD-5, HD-14 (h)):
/// "Dynamic Range:" under Format, only in an HLG project, so an SDR project's
/// card is the card it was. On a row that carries HDR (`ExportPreset.carriesHDR`:
/// `hevc_10bit`, `prores_422`, `prores_4444`) it offers HDR (HLG), HDR10 (PQ)
/// and SDR version, HDR (HLG) first and the default; on every other row it is
/// disabled and shows "SDR version", the picture that row writes, and sends no
/// override (the core's default for it). The choice lives for the sheet alone:
/// it is not one of `ExportChoice`'s fields, so neither the remembered choice
/// nor a user preset carries it.
extension ExportSheetController {
    /// Whether the document is an HLG project (`canvas.output`), the only
    /// kind of project whose card has the row.
    var isHLGProject: Bool {
        editor?.document?.project.snapshot.canvas.output == .hlg
    }

    /// The popup's items and wiring, in an HLG project only. Called from
    /// `loadView` before the first resolve.
    func configureDynamicRange() {
        guard isHLGProject else { return }
        dynamicRangePopup.addItems(withTitles: DynamicRange.allCases.map { $0.menuName })
        dynamicRangePopup.selectItem(at: 0)
        dynamicRangePopup.font = DS.sans(13)
        dynamicRangePopup.target = self
        dynamicRangePopup.action = #selector(dynamicRangeChanged(_:))
        dynamicRangePopup.widthAnchor.constraint(equalToConstant: 186).isActive = true
    }

    /// A pick on a row that carries HDR: the choice, then a resolve, so the
    /// readout and Export… follow the core's answer for it.
    @objc func dynamicRangeChanged(_ sender: Any?) {
        let index = dynamicRangePopup.indexOfSelectedItem
        guard DynamicRange.allCases.indices.contains(index) else { return }
        dynamicRangeChoice = DynamicRange.allCases[index]
        resolveCard()
    }

    /// The `dynamic_range` override: the choice on a row that carries HDR in
    /// an HLG project, nil everywhere else.
    func dynamicRangeOverride() -> String? {
        guard isHLGProject, currentPreset?.carriesHDR == true else { return nil }
        return dynamicRangeChoice.rawValue
    }

    /// The popup follows the format: live with the choice on a row that
    /// carries HDR, disabled on "SDR version" on any other.
    func syncDynamicRange(_ applies: Applies) {
        guard isHLGProject else { return }
        dynamicRangePopup.isEnabled = applies.dynamicRange
        let shown = applies.dynamicRange ? dynamicRangeChoice : .sdr
        dynamicRangePopup.selectItem(at: DynamicRange.allCases.firstIndex(of: shown) ?? 0)
    }
}
