// app/Sources/GraphicSchemaRows.swift — a graphic module's schema as the
// Graphic sub-tab's Properties rows (road map 10 §5j, G5a): the schema read
// in the MODULE's key order, one row per entry built with the inspector's
// existing builders, the stored keys the schema no longer has (G-4's
// leniency, made visible), and the two conversions a colour needs at the
// well's edge (G-12: a prop's colour is a CSS string, the well's is `RGBA`).
//
// **No state of its own.** Every function here is a function of its
// arguments, so a probe can drive each one without a window.
//
// **Where a write goes** (spec §11 G-34 (l)): with no action selected every
// row writes `set_graphic` to the clip; with one selected, a row reads the
// action's END state (`InspectorBinding.graphicProps`) and writes it — one
// `set_action_end` naming `graphic.props.<key>` with the module's schema —
// through `InspectorBinding.ops(graphic:…)`, an asset and a prop its module
// marks `animate: false` (G-41) still the clip's.
//
// **A value equal to the schema's default is written as `null`** to the
// clip (spec §11 G-15): the key leaves the stored props and the module
// draws its own default, which is exactly what Reset writes too. An end
// takes the value itself, since a `null` there removes (G-34 (j)). A colour is "equal" by
// its parsed channels, and a colour DEFAULT is read through the core's own
// G-12 (`ReelColor.normalise`, spec §11 G-25), so a name or `hsl()` default
// draws and matches as the colour it is; a default G-12 refuses does not
// compile (`model_graphic.rs`, the engine's `props.rs`).

import AppKit

enum GraphicSchemaRows {
    /// The swatch when a colour default is not a colour G-12 takes — which
    /// compile refuses, so only a schema no compile checked reaches it:
    /// transparent black.
    static let unparsedColor: RGBA = [0, 0, 0, 0]

    /// A JSON value from `JSONSerialization` as a prop value.
    static func value(_ any: Any?) -> GraphicPropValue {
        if let string = any as? String { return .string(string) }
        if let number = any as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? .bool(number.boolValue) : .number(number.doubleValue)
        }
        return .null
    }

    /// A prop value as the JSON a patch carries.
    static func json(_ value: GraphicPropValue) -> Any {
        switch value {
        case .string(let string): return string
        case .number(let number): return number
        case .bool(let bool): return bool
        case .null: return NSNull()
        }
    }

    /// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`, any case, as channels 0–1.
    static func rgba(css: String) -> RGBA? {
        let text = css.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("#") else { return nil }
        let hex = Array(text.dropFirst())
        guard [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        let pairs: [String] = hex.count <= 4
            ? hex.map { String([$0, $0]) }
            : stride(from: 0, to: hex.count, by: 2).map { String(hex[$0..<$0 + 2]) }
        var channels = pairs.map { Double(UInt8($0, radix: 16) ?? 0) / 255 }
        if channels.count == 3 { channels.append(1) }
        return channels
    }

    /// `#rrggbb`, or `#rrggbbaa` when the alpha is below 1 — the core's own
    /// normalised form, lowercase.
    static func css(_ color: RGBA) -> String {
        let channels = (0..<4).map { index -> Int in
            let value = color.indices.contains(index) ? color[index] : 1
            return Int((Swift.min(Swift.max(value, 0), 1) * 255).rounded())
        }
        let rgb = channels[0..<3].map { String(format: "%02x", $0) }.joined()
        return "#" + rgb + (channels[3] == 255 ? "" : String(format: "%02x", channels[3]))
    }

    /// The colour a `color` entry's default draws as in the well.
    static func defaultColor(_ entry: GraphicSchemaEntry) -> RGBA {
        if case .string(let text) = entry.default, let hex = ReelColor.normalise(text),
           let color = rgba(css: hex) {
            return color
        }
        return unparsedColor
    }

    /// What a write sends for `value`: `null` when it equals the default,
    /// else the value itself.
    static func patchValue(_ value: GraphicPropValue, for entry: GraphicSchemaEntry) -> Any {
        if entry.type == "color" {
            if case .string(let text) = value, rgba(css: text) == defaultColor(entry) {
                return NSNull()
            }
        } else if value == entry.default {
            return NSNull()
        }
        return json(value)
    }

    /// A base write's props: each value through `patchValue` against its
    /// entry, and a key no entry declares as it is.
    static func patchProps(
        _ values: [String: GraphicPropValue], entries: [GraphicSchemaEntry]
    ) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, value) in values {
            if let entry = entries.first(where: { $0.key == key }) {
                props[key] = patchValue(value, for: entry)
            } else {
                props[key] = json(value)
            }
        }
        return props
    }

    /// The stored keys `schema` does not declare, sorted — all of them when
    /// there is no compiled schema.
    static func staleKeys(stored: [String: GraphicPropValue], schema: GraphicSchema?) -> [String] {
        let declared = Set(schema?.keys ?? [])
        return stored.keys.filter { !declared.contains($0) }.sorted()
    }

    /// The keys the selected action's END names that no row writes into it,
    /// sorted: each `schema` does not declare and each whose entry is not
    /// `animatable` (G-41 (c)); every key with no compiled schema. The
    /// undeclared keys are `staleKeys`' own.
    static func actionStaleKeys(end: [String: GraphicPropValue], schema: GraphicSchema?) -> [String] {
        let held = Set((schema?.entries ?? []).filter { !$0.animatable }.map(\.key))
        let declaredHeld = end.keys.filter { held.contains($0) }
        return (staleKeys(stored: end, schema: schema) + declaredHeld).sorted()
    }

    /// A number row's decimals: with a `step`, 2 below 1 and else 0; with
    /// none, 2 when the default, `min` or `max` has a fraction, else 0.
    static func decimals(for entry: GraphicSchemaEntry) -> Int {
        if let step = entry.step { return step < 1 ? 2 : 0 }
        var values = [entry.min, entry.max].compactMap { $0 }
        if case .number(let number) = entry.default { values.append(number) }
        return values.contains { $0 != $0.rounded() } ? 2 : 0
    }

    /// An asset entry's popup names: the folder's `files`, then, sorted,
    /// every name a clip holds under `entry.key`, and a string default, that
    /// `files` lacks. The rows and the pane's signature both call this.
    static func assetNames(
        for entry: GraphicSchemaEntry, files: [String], clips: [ClipSnapshot]
    ) -> [String] {
        var held = clips.compactMap { clip -> String? in
            if case .string(let text)? = clip.graphic?.props[entry.key] { return text }
            return nil
        }
        if case .string(let text) = entry.default { held.append(text) }
        return files + Set(held).subtracting(files).sorted()
    }

    /// `set_graphic {clips, patch: {props}, schema}` over `clips`.
    static func op(clips: [ClipSnapshot], props: [String: Any], schema: [String: Any]?) -> ReelOp {
        .setGraphicRaw(clips: clips.map(\.id), patch: ["props": props], schema: schema)
    }

    // MARK: - Rows

    /// One schema entry's row. Every `read` answers the default in the
    /// binding's `.defaults` mode, so the builders' derived Reset works, and
    /// otherwise the binding's mode's value (the selected action's end, its
    /// start, the playhead); every write is `InspectorBinding.ops(graphic:…)`
    /// over `clips()`.
    static func row(
        _ entry: GraphicSchemaEntry, _ binding: InspectorBinding,
        clips: @escaping () -> [ClipSnapshot], schema: [String: Any],
        assets: @escaping () -> [String]
    ) -> NSView {
        let key = entry.key, name = "Graphic " + entry.label
        func stored() -> GraphicPropValue? {
            clips().first.map { binding.graphicProps($0)[key] } ?? nil
        }
        func current() -> GraphicPropValue { stored() ?? entry.default }
        func ops(_ value: GraphicPropValue) -> [ReelOp] {
            binding.ops(graphic: value, for: entry, clips: clips(), schema: schema)
        }
        let mixed = { binding.mixed(clips()) { binding.graphicProps($0)[key] } }
        let view: NSView
        switch entry.type {
        case "number":
            let fallback: Double = {
                if case .number(let number) = entry.default { return number }
                return 0
            }()
            let bounded = entry.min != nil && entry.max != nil
            view = inspectorValueRow(
                entry.label, binding, name: name,
                decimals: decimals(for: entry),
                min: entry.min ?? -1e9, max: entry.max ?? 1e9, slider: bounded,
                read: {
                    if case .number(let number) = current() { return number }
                    return fallback
                },
                ops: { ops(.number($0)) }, mixed: mixed)
        case "boolean":
            view = inspectorCheckRow(
                entry.label, binding, name: name,
                read: {
                    if case .bool(let bool) = current() { return bool }
                    if case .bool(let bool) = entry.default { return bool }
                    return false
                },
                ops: { ops(.bool($0)) }, mixed: mixed)
        case "color":
            view = inspectorColorRow(
                entry.label, binding, name: name,
                read: {
                    if case .string(let text)? = stored(), let color = rgba(css: text) {
                        return color
                    }
                    return defaultColor(entry)
                },
                ops: { ops(.string(css($0))) }, mixed: mixed)
        case "enum":
            let options = entry.options
            view = inspectorPopupRow(
                entry.label, binding, name: name, items: options,
                read: {
                    if case .string(let text) = current(), let index = options.firstIndex(of: text) {
                        return index
                    }
                    if case .string(let text) = entry.default,
                       let index = options.firstIndex(of: text)
                    {
                        return index
                    }
                    return 0
                },
                ops: { index in options.indices.contains(index) ? ops(.string(options[index])) : [] },
                mixed: mixed)
        case "asset":
            view = assetRow(entry, binding, name: name, clips: clips, assets: assets,
                            current: current, ops: ops, mixed: mixed)
        case "string":
            view = stringRow(entry, binding, name: name, current: current, ops: ops, mixed: mixed)
        default:
            view = inspectorRow(
                entry.label, [inspectorReadout { "type \"\(entry.type)\" is not supported" }])
        }
        view.toolTip = entry.help
        return view
    }

    /// The asset popup: "None" first when the default is null, the folder's
    /// files, then any name a clip holds (or the default names) that the
    /// folder does not.
    private static func assetRow(
        _ entry: GraphicSchemaEntry, _ binding: InspectorBinding, name: String,
        clips: @escaping () -> [ClipSnapshot], assets: @escaping () -> [String],
        current: @escaping () -> GraphicPropValue,
        ops: @escaping (GraphicPropValue) -> [ReelOp], mixed: @escaping () -> Bool
    ) -> NSView {
        let none = entry.default == .null
        let names = assetNames(for: entry, files: assets(), clips: clips())
        let items = (none ? ["None"] : []) + names
        let offset = none ? 1 : 0
        return inspectorPopupRow(
            entry.label, binding, name: name, items: items,
            read: {
                if case .string(let text) = current(), let index = names.firstIndex(of: text) {
                    return index + offset
                }
                return 0
            },
            ops: { index in
                if none, index == 0 { return ops(.null) }
                let at = index - offset
                return names.indices.contains(at) ? ops(.string(names[at])) : []
            },
            mixed: mixed)
    }

    /// A string entry: a one-line field, or a text area when `multiline`.
    /// `OptionFieldControl` is numeric, so the row is assembled here with an
    /// explicit default rather than through `inspectorValueRow`.
    private static func stringRow(
        _ entry: GraphicSchemaEntry, _ binding: InspectorBinding, name: String,
        current: @escaping () -> GraphicPropValue,
        ops: @escaping (GraphicPropValue) -> [ReelOp], mixed: @escaping () -> Bool
    ) -> NSView {
        let read: () -> String = {
            if case .string(let text) = current() { return text }
            return ""
        }
        let write: (String) -> [ReelOp] = { ops(.string($0)) }
        let control: NSView = entry.multiline
            ? InspectorTextArea(
                read: read, write: { [weak binding] in binding?.apply(name, write($0)) },
                enabled: { true }, onEdit: { [weak binding] in binding?.edited() })
            : InspectorNameField(
                read: read, write: { [weak binding] in binding?.apply(name, write($0)) },
                enabled: { true }, onEdit: { [weak binding] in binding?.edited() })
        if !entry.multiline {
            // 170 wide, giving way only to the "at end" tag while the
            // selected action keys the row (G-34 (l), O1).
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(lessThanOrEqualToConstant: 170).isActive = true
            let width = control.widthAnchor.constraint(equalToConstant: 170)
            width.priority = NSLayoutConstraint.Priority(249)
            width.isActive = true
            control.setContentCompressionResistancePriority(
                NSLayoutConstraint.Priority(248), for: .horizontal)
        }
        return inspectorRow(
            entry.label, [control], mixed: mixed, binding: binding, writes: write(read()),
            discrete: true, default: .derived(binding, name: name, read: read, ops: write))
    }

    /// A stored key the schema no longer declares: the key dimmed, its value,
    /// and ⌫, which writes `{key: null}` — a null always removes (G-4).
    static func staleRow(
        key: String, value: GraphicPropValue, _ binding: InspectorBinding,
        clips: @escaping () -> [ClipSnapshot]
    ) -> NSView {
        let (label, readout) = staleLabels(key: key, value: value)
        let remove = OptionButtonControl(
            title: "⌫",
            action: { [weak binding] in
                let targets = clips()
                binding?.apply(
                    "Remove Graphic Property",
                    targets.isEmpty ? [] : [op(clips: targets, props: [key: NSNull()], schema: nil)])
            },
            enabled: { true }, onEdit: {})
        remove.toolTip = "The module no longer declares \(key) — remove the stored value"
        return inspectorRow(nil, [label, readout, remove])
    }

    /// A key the selected action's END names that the schema no longer
    /// declares (G-34 (l), O2), or `declared` but not `animatable` (G-41 (c)):
    /// its row beside the clip's own, marked as the end's, with ⌫ taking it
    /// out of the end — `clearOps`, no schema.
    static func actionStaleRow(
        key: String, value: GraphicPropValue, declared: Bool, _ binding: InspectorBinding
    ) -> NSView {
        let (label, readout) = staleLabels(key: key, value: value)
        let ops = binding.clearOps(["graphic.props." + key])
        let remove = OptionButtonControl(
            title: "⌫",
            action: { [weak binding] in binding?.apply("Remove from Action", ops) },
            enabled: { true }, onEdit: {})
        let number = binding.selectedActionNumber.map { String($0) } ?? ""
        remove.toolTip = declared
            ? "The module does not let \(key) be animated — remove it from action \(number)"
            : "The module no longer declares \(key) — remove it from action \(number)"
        return inspectorRow(nil, [label, readout, remove], binding: binding, writes: ops)
    }

    /// A stale row's key, dimmed, and its value.
    private static func staleLabels(
        key: String, value: GraphicPropValue
    ) -> (InspectorRowLabel, NSView) {
        let label = InspectorRowLabel(key)
        label.textColor = DS.textFaint
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: InspectorMetrics.labelWidth).isActive = true
        let shown: String
        switch value {
        case .string(let text): shown = "\"\(text)\""
        case .number(let number): shown = String(format: "%g", number)
        case .bool(let bool): shown = bool ? "true" : "false"
        case .null: shown = "null"
        }
        let readout = inspectorReadout(width: 110) { shown }
        readout.alphaValue = 0.55
        return (label, readout)
    }
}
