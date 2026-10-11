import AppKit

/// The Color sub-tab's **Qualifier** section (spec §11 GR-13, grading-2
/// G2-4), on adjustment clips only, after Adjustment: which of the pixels
/// behind the clip its grade reaches.
///
/// Per range two rows — its checkbox (Hue, Saturation, Luma) in the label
/// column then its strip (`RangeStripControl`), then three captioned fields
/// (Centre, Width, Soft in whole degrees; Low, High, Soft to two decimals) —
/// then Invert, then Pick from Canvas and the Show Selection switch, both
/// sent to the editor as commands (`EditorViewController+Qualifier.swift`,
/// `+Seeing`). A checkbox writes `{}` or `null` (one step named after the
/// range); a strip drag is the live trio; a field one commit; each sends the
/// WHOLE range to every selected clip, the first clip's values being the
/// ones shown (the mixed badge says when the others differ). Every row
/// writes `video.qualifier`, so a keyed action marks them all as one key.
extension VideoPane {
    // MARK: Qualifier

    func qualifierSection() -> InspectorSection {
        let binding = self.binding
        func qualifier() -> ColorQualifier { binding.videoProps.qualifier }
        func ops(_ patch: ColorQualifierPatch) -> [ReelOp] {
            binding.ops(video: VideoPatch(qualifier: patch))
        }
        var rows: [NSView] = []
        for range in QualifierRange.allCases {
            rows += qualifierRows(range, read: qualifier, ops: ops)
        }
        rows.append(
            inspectorCheckRow(
                "Invert", binding, name: "Qualifier",
                read: { qualifier().invert },
                ops: { ops(ColorQualifierPatch(invert: $0)) },
                mixed: { binding.mixedVideo { $0.qualifier.invert } }))
        let pick = OptionButtonControl(
            title: "Pick from Canvas",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.pickQualifier(_:)))
            },
            enabled: { true }, onEdit: {})
        pick.toolTip = "Click the preview to centre the ranges on a colour (Esc cancels)"
        let show = OptionCheckboxControl(
            label: "Show Selection",
            read: { [weak self] in
                guard let key = self?.inspector?.document?.recipeKey else { return false }
                return RecipeSource.shared.options(for: key).selection != nil
            },
            write: { [weak self] _ in
                self?.inspector?.onCommand?(
                    #selector(EditorViewController.toggleShowSelection(_:)))
            },
            enabled: { true }, onEdit: {})
        rows.append(inspectorButtonRow([pick, show]))
        return InspectorSection(
            id: "video.qualifier", title: "Qualifier",
            summary: { qualifier().summary },
            reset: { binding.apply("Qualifier", ops(.reset)) },
            differs: { !qualifier().isNeutral },
            defaultExpanded: false,
            rows: rows)
    }

    /// One range's two rows: the checkbox and the strip, then the fields.
    private func qualifierRows(
        _ range: QualifierRange, read: @escaping () -> ColorQualifier,
        ops: @escaping (ColorQualifierPatch) -> [ReelOp]
    ) -> [NSView] {
        let binding = self.binding
        let name = range.title
        func on() -> Bool { read().isOn(range) }
        let check = OptionCheckboxControl(
            label: name, read: on,
            write: { [weak binding] value in
                binding?.apply(name, ops(.toggle(range, value)))
            },
            enabled: { true },
            onEdit: { [weak binding] in binding?.edited() })
        check.translatesAutoresizingMaskIntoConstraints = false
        check.widthAnchor.constraint(equalToConstant: InspectorMetrics.labelWidth).isActive = true
        let strip = RangeStripControl(
            kind: range, read: read,
            begin: { [weak binding] in binding?.liveBegin() },
            update: { [weak binding] patch in binding?.liveUpdate(ops(patch)) },
            end: { [weak binding] in binding?.liveEnd(name) })
        let mixed: () -> Bool
        switch range {
        case .hue: mixed = { binding.mixedVideo { $0.qualifier.hue } }
        case .saturation: mixed = { binding.mixedVideo { $0.qualifier.saturation } }
        case .luma: mixed = { binding.mixedVideo { $0.qualifier.luma } }
        }
        let stripRow = inspectorRow(
            nil, [check, strip], mixed: mixed, binding: binding, writes: ops(.reset),
            default: InspectorRowDefault(
                name: name, differs: on, ops: { ops(.toggle(range, false)) }))
        let gutter = stripRow.gutter
        strip.keyed = { [weak gutter] in gutter?.isKeyed == true }
        return [stripRow, qualifierFields(range, read: read, ops: ops)]
    }

    /// The range's three captioned fields across one row.
    private func qualifierFields(
        _ range: QualifierRange, read: @escaping () -> ColorQualifier,
        ops: @escaping (ColorQualifierPatch) -> [ReelOp]
    ) -> NSView {
        let binding = self.binding
        let name = range.title
        func on() -> Bool { read().isOn(range) }
        typealias Field = (caption: String, max: Double, get: (ColorQualifier) -> Double,
                           put: (ColorQualifier, Double) -> ColorQualifierPatch)
        let fields: [Field]
        if range == .hue {
            func hue(_ q: ColorQualifier) -> QualifierHue { q.hue ?? .initial }
            fields = [
                ("Centre", 360, { hue($0).center },
                 { q, v in var h = hue(q); h.center = v; return ColorQualifierPatch(hue: .set(h)) }),
                ("Width", 360, { hue($0).width },
                 { q, v in var h = hue(q); h.width = v; return ColorQualifierPatch(hue: .set(h)) }),
                ("Soft", 180, { hue($0).softness },
                 { q, v in var h = hue(q); h.softness = v; return ColorQualifierPatch(hue: .set(h)) }),
            ]
        } else {
            func levels(_ q: ColorQualifier) -> QualifierLevels { q.levels(range) ?? .initial }
            fields = [
                ("Low", 1, { levels($0).low },
                 { q, v in
                     var l = levels(q)
                     l.low = min(v, l.high)
                     return .levels(range, .set(l))
                 }),
                ("High", 1, { levels($0).high },
                 { q, v in
                     var l = levels(q)
                     l.high = max(v, l.low)
                     return .levels(range, .set(l))
                 }),
                ("Soft", 1, { levels($0).softness },
                 { q, v in var l = levels(q); l.softness = v; return .levels(range, .set(l)) }),
            ]
        }
        var controls: [NSView] = []
        for field in fields {
            let caption = InspectorRowLabel(field.caption)
            caption.font = DS.sans(10)
            caption.setContentCompressionResistancePriority(.required, for: .horizontal)
            controls.append(caption)
            controls.append(
                OptionFieldControl(
                    width: 41, unit: range == .hue ? "°" : "", decimals: range == .hue ? 0 : 2,
                    min: 0, max: field.max,
                    read: { field.get(read()) },
                    write: { [weak binding] value in
                        binding?.apply(name, ops(field.put(read(), value)))
                    },
                    enabled: on,
                    onEdit: { [weak binding] in binding?.edited() }))
        }
        return inspectorRow(nil, controls, binding: binding, writes: ops(.reset))
    }
}
