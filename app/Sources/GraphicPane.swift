// app/Sources/GraphicPane.swift — the Clip tab's GRAPHIC sections (road map
// 10 §5j, G5a): Source (in `GraphicPane+Source.swift`), Properties from the
// module's schema (rows from `GraphicSchemaRows.swift`), Size and Timeline.
// With no action selected every write is `set_graphic`. With one selected, a
// Properties write — Reset's included — goes to the action's END with the
// module's current schema, one `set_action_end` naming `graphic.props.<key>`,
// except an `animate: false` prop's, which stays the clip's (spec §11 G-34
// (l), G-41 (d), G-42 (d)); Size and
// Timeline still write `set_graphic`, so their rows are ⊘. The core
// validates both.
//
// **Never shown itself**: like `ShapePane`, a factory `ClipPane` holds and
// calls when EVERY selected clip is a graphic clip.
//
// **Several graphic clips.** Source and Size always; Properties only when
// every clip is drawn by ONE module (one schema to build rows from, and the
// schema `set_graphic` needs), and Timeline only for one clip — its `in`
// and `length` are that clip's own. With different modules Source says so
// and names them (spec §11 G-15).
//
// **The schema is the registry's** (`GraphicRegistry.entry(named:for:)`,
// main only), the same read `AgentServer+Graphics.compiledModule` makes for
// the tool path. Nothing here rescans the store from an observer: `drain()`
// is not re-entrant (road map 10 §10.6 G3a).

import AppKit

extension InspectorBinding {
    /// The selected clips drawn by a module.
    var graphicClips: [ClipSnapshot] {
        clips.filter { clip in
            if case .graphic = clip.source { return clip.graphic != nil }
            return false
        }
    }
}

final class GraphicPane: InspectorPaneView {
    /// The report of each module/revision/library/frame hash/size seen, and
    /// the last report per clip — what a miss answers while a live gesture
    /// runs, so the signature holds still through a drag.
    var reportMemo: [String: GraphicClipReport] = [:]
    var lastReports: [UInt32: GraphicClipReport] = [:]
    /// The parsed schema of the last module asked, keyed "name|revision".
    var schemaMemo: (key: String, schema: GraphicSchema)?
    /// Each clip's recipe layer source under `layerProject`, the handle it
    /// was read from; emptied when the binding's project is another handle.
    weak var layerProject: ReelProject?
    var layerMemo: [UInt32: RecipeSourceRef] = [:]

    /// Whether the graphic sections apply: they write `set_graphic`, which
    /// errors on any other kind, so a mixed selection gets none of them.
    var allGraphic: Bool {
        !binding.clips.isEmpty && binding.graphicClips.count == binding.clips.count
    }

    /// The one module every selected graphic clip is drawn by.
    struct Shared {
        let name: String
        let file: GraphicModuleFile?
        let entry: GraphicRegistry.Entry?
    }

    /// nil when the selection's modules differ (or it holds no graphic).
    func shared() -> Shared? {
        let names = Set(binding.graphicClips.compactMap { $0.graphic?.name })
        guard names.count == 1, let name = names.first else { return nil }
        let document = binding.document
        return Shared(
            name: name, file: document?.graphicStore?.module(named: name),
            entry: document.flatMap {
                GraphicRegistry.shared.entry(named: name, for: $0.recipeKey)
            })
    }

    /// The compiled schema of `shared`, parsed in the module's order, and
    /// the registry's dictionary the ops carry. Parsed once per name and
    /// revision (`schemaMemo`).
    func schema(_ shared: Shared?) -> (schema: GraphicSchema, raw: [String: Any])? {
        guard let shared, case .compiled(let module, let revision, _, let raw)? = shared.entry
        else { return nil }
        let key = "\(shared.name)|\(revision)"
        if let memo = schemaMemo, memo.key == key { return (memo.schema, raw) }
        let parsed = GraphicSchema(describeJSON: module.describeJSON(), schema: raw)
        schemaMemo = (key, parsed)
        return (parsed, raw)
    }

    /// The selection's stored props, merged; the first clip holding a key wins.
    func storedProps() -> [String: GraphicPropValue] {
        var merged: [String: GraphicPropValue] = [:]
        for clip in binding.graphicClips {
            merged.merge(clip.graphic?.props ?? [:]) { first, _ in first }
        }
        return merged
    }

    /// The selected action's end props (G-34 (a)); none with no action
    /// selected. Its keys the schema lacks are the action's stale rows.
    func endProps() -> [String: GraphicPropValue] {
        binding.selectedAction?.end.graphic?.props ?? [:]
    }

    /// The asset folder's file names, sorted.
    func assetNames() -> [String] {
        (binding.document?.graphicStore?.scan.assets.map(\.name) ?? []).sorted()
    }

    /// What the graphics folder's scan skipped or could not watch, in its own
    /// sentences — the Source section's folder rows (G-24 (b)).
    func folderWarnings() -> [String] {
        binding.document?.graphicStore?.scan.warnings ?? []
    }

    /// The schema's entries whole (a default, bounds or options a row is
    /// built from), the stale keys (the clip's, then the selected action's
    /// end's, `actionStaleKeys`, a declared key no action may animate
    /// included, G-41), each asset popup's names (the selected end's
    /// included, G-42), the
    /// diagnostics' messages and the folder's warnings. Stored values, the
    /// revision and the playhead are NOT here: they are read fresh by
    /// `refresh()`.
    override var structureSignature: String {
        guard allGraphic else { return super.structureSignature + "|-" }
        let shared = self.shared()
        let parsed = schema(shared)
        let keys = parsed?.schema.entries.map { String(describing: $0) } ?? []
        let stale = GraphicSchemaRows.staleKeys(stored: storedProps(), schema: parsed?.schema)
        var messages = ["-", "-"]
        if let shared, let clip = binding.graphicClips.first, let document = binding.document {
            let version = GraphicRegistry.shared.snapshot(for: document.recipeKey)?.libraryVersion
            let report = self.report(for: clip, shared, libraryVersion: version ?? "")
            func spell(_ list: [GraphicDiagnostic]) -> String {
                list.map { "\($0.level):\($0.line ?? -1):\($0.column ?? -1):\($0.message)" }
                    .joined(separator: "¶")
            }
            messages = [spell(report.compile), spell(report.render)]
        }
        messages.append(folderWarnings().joined(separator: "¶"))
        return [
            super.structureSignature, shared?.name ?? "mixed", keys.joined(separator: ","),
            stale.joined(separator: ","), assetSignature(parsed?.schema),
            GraphicSchemaRows.actionStaleKeys(end: endProps(), schema: parsed?.schema)
                .joined(separator: ","),
        ].joined(separator: "|") + "|" + messages.joined(separator: "|")
    }

    /// Each asset entry's popup names, from the rows' own
    /// `GraphicSchemaRows.assetNames` call, the selected action's end's names
    /// counting (G-42 (d)): names joined by ",", entries by ";".
    private func assetSignature(_ schema: GraphicSchema?) -> String {
        let files = assetNames(), clips = binding.graphicClips
        return (schema?.entries ?? []).filter { $0.type == "asset" }.map {
            GraphicSchemaRows.assetNames(for: $0, files: files, clips: clips, end: endProps())
                .joined(separator: ",")
        }.joined(separator: ";")
    }

    // MARK: - Properties

    /// One row per schema key in the module's order, then the stale keys,
    /// sorted, then — with an action selected — the end's own stale keys
    /// (G-34 (l), O2), a declared key whose entry is not `animatable` among
    /// them (G-41 (c)). With no compiled schema every stored key is stale.
    /// Reset nulls every stored key; with an action selected it writes each
    /// declared default through the rows' own split, into the END (an
    /// asset's `null` as `""`, G-42 (d)), an `animate: false` prop's (G-41
    /// (d)) onto the clip (O7). Its `differs` folds from the rows.
    func propertiesSection() -> InspectorSection {
        let binding = self.binding
        let shared = self.shared()
        let parsed = schema(shared)
        let clips = { binding.graphicClips }
        let assets = { [weak self] in self?.assetNames() ?? [] }
        var rows: [NSView] = parsed?.schema.entries.map {
            GraphicSchemaRows.row(
                $0, binding, clips: clips, schema: parsed?.raw ?? [:], assets: assets)
        } ?? []
        let stored = storedProps()
        for key in GraphicSchemaRows.staleKeys(stored: stored, schema: parsed?.schema) {
            rows.append(
                GraphicSchemaRows.staleRow(
                    key: key, value: stored[key] ?? .null, binding, clips: clips))
        }
        let ends = endProps()
        let declared = Set(parsed?.schema.keys ?? [])
        for key in GraphicSchemaRows.actionStaleKeys(end: ends, schema: parsed?.schema) {
            rows.append(
                GraphicSchemaRows.actionStaleRow(
                    key: key, value: ends[key] ?? .null, declared: declared.contains(key), binding))
        }
        let note: String?
        if parsed == nil {
            note = "The module did not compile — see Source. Stored values are listed below."
        } else if parsed?.schema.entries.isEmpty == true {
            note = "The module declares no properties."
        } else {
            note = nil
        }
        let count = parsed?.schema.entries.count ?? 0
        return InspectorSection(
            id: "graphic.properties", title: "Properties",
            summary: { count == 1 ? "1 property" : "\(count) properties" },
            note: note.map { text -> () -> String? in { text } },
            reset: {
                if binding.selectedAction != nil {
                    let entries = parsed?.schema.entries ?? []
                    let defaults = Dictionary(
                        entries.map { ($0.key, $0.default) }, uniquingKeysWith: { first, _ in first })
                    binding.apply(
                        "Reset Graphic Properties",
                        binding.ops(
                            graphic: defaults, entries: entries, clips: clips(), schema: parsed?.raw))
                    return
                }
                let targets = clips()
                var keys = Set<String>()
                for clip in targets { keys.formUnion(clip.graphic?.props.keys.map { $0 } ?? []) }
                guard !keys.isEmpty else { return NSSound.beep() }
                binding.apply(
                    "Reset Graphic Properties",
                    [GraphicSchemaRows.op(
                        clips: targets,
                        props: Dictionary(uniqueKeysWithValues: keys.map { ($0, NSNull()) }),
                        schema: parsed?.raw)])
            },
            defaultExpanded: true,
            rows: rows)
    }

    // MARK: - Size

    /// Width and height, fanned out one op per clip in one apply, and Fit to
    /// Canvas: the canvas's size, centred at scale 1.
    func sizeSection() -> InspectorSection {
        let binding = self.binding
        func first() -> GraphicSnapshot? { binding.graphicClips.first?.graphic }
        func side(_ key: String, _ value: Double) -> [ReelOp] {
            binding.graphicClips.map {
                .setGraphicRaw(clips: [$0.id], patch: [key: Int(value.rounded())])
            }
        }
        return InspectorSection(
            id: "graphic.size", title: "Size",
            summary: { first().map { "\($0.width) × \($0.height)" } },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Width", binding, name: "Graphic Size", unit: " px", min: 1,
                    max: Double(GraphicLibrary.maxSide), slider: false,
                    width: InspectorMetrics.wideFieldWidth,
                    read: { Double(first()?.width ?? 0) }, ops: { side("width", $0) },
                    mixed: { binding.mixed(binding.graphicClips) { $0.graphic?.width } },
                    resets: false),
                inspectorValueRow(
                    "Height", binding, name: "Graphic Size", unit: " px", min: 1,
                    max: Double(GraphicLibrary.maxSide), slider: false,
                    width: InspectorMetrics.wideFieldWidth,
                    read: { Double(first()?.height ?? 0) }, ops: { side("height", $0) },
                    mixed: { binding.mixed(binding.graphicClips) { $0.graphic?.height } },
                    resets: false),
                inspectorButtonRow([
                    inspectorButton(
                        "Fit to Canvas", binding, name: "Fit Graphic to Canvas",
                        ops: { Self.fitToCanvasOps(clips: binding.graphicClips, canvas: binding.canvas) }),
                ]),
            ])
    }

    /// Per clip: the canvas's size, then the layer centred at scale 1.
    static func fitToCanvasOps(clips: [ClipSnapshot], canvas: CanvasSnapshot) -> [ReelOp] {
        clips.flatMap { clip -> [ReelOp] in
            [
                .setGraphicRaw(
                    clips: [clip.id], patch: ["width": canvas.width, "height": canvas.height]),
                .setVideo(clips: [clip.id], patch: VideoPatch(x: 0, y: 0, scale: 1)),
            ]
        }
    }

    // MARK: - Timeline

    /// The graphic's own timeline (G-9): In, read-only — the point
    /// `trim_start`, `roll` and `split` move — and Length, typed, which pins
    /// it; Follow Clip gives it back to the clip's duration (`null`).
    ///
    /// Binds by clip ID and reads fresh through it, `timingSection`'s rule.
    func timelineSection(_ id: UInt32) -> InspectorSection {
        let binding = self.binding
        func clip() -> ClipSnapshot? { binding.snapshot.clip(id) }
        func fps() -> Fps { binding.canvas.fps }
        func frames() -> Bool { binding.canvas.timecodeFrames }
        func length() -> Ticks {
            guard let clip = clip() else { return 0 }
            return clip.graphic?.length ?? clip.duration
        }
        let field = InspectorTimecodeField(
            read: length,
            write: { value in
                binding.apply("Graphic Length", [.setGraphicRaw(clips: [id], patch: ["length": value])])
            },
            fps: fps, frames: frames,
            onEdit: { binding.edited() })
        field.toolTip = "How long the graphic's own timeline runs — typing pins it"
        return InspectorSection(
            id: "graphic.timeline", title: "Timeline",
            summary: { ReelTime.format(length(), fps: fps(), frames: frames()) },
            defaultExpanded: false,
            rows: [
                inspectorRow("In", [inspectorReadout {
                    ReelTime.format(clip()?.graphic?.sourceIn ?? 0, fps: fps(), frames: frames())
                }]),
                inspectorRow("Length", [field]),
                inspectorCheckRow(
                    "Follow Clip", binding, name: "Graphic Follow Clip",
                    read: { clip()?.graphic.map { $0.length == nil } ?? true },
                    ops: { on in
                        [.setGraphicRaw(
                            clips: [id], patch: ["length": on ? NSNull() : length() as Any])]
                    },
                    resets: false),
            ])
    }
}
