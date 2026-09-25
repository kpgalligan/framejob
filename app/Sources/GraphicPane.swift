// app/Sources/GraphicPane.swift — the Clip tab's GRAPHIC sections (road map
// 10 §5j, G5a): Source (in `GraphicPane+Source.swift`), Properties from the
// module's schema (rows from `GraphicSchemaRows.swift`), Size and Timeline.
// Every write is `set_graphic`, which the core validates.
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
    /// the registry's dictionary the ops carry.
    func schema(_ shared: Shared?) -> (schema: GraphicSchema, raw: [String: Any])? {
        guard case .compiled(let module, _, _, let raw)? = shared?.entry else { return nil }
        return (GraphicSchema(describeJSON: module.describeJSON(), schema: raw), raw)
    }

    /// The selection's stored props, merged; the first clip holding a key wins.
    func storedProps() -> [String: GraphicPropValue] {
        var merged: [String: GraphicPropValue] = [:]
        for clip in binding.graphicClips {
            merged.merge(clip.graphic?.props ?? [:]) { first, _ in first }
        }
        return merged
    }

    /// The asset folder's file names, sorted.
    func assetNames() -> [String] {
        (binding.document?.graphicStore?.scan.assets.map(\.name) ?? []).sorted()
    }

    /// The schema's keys and types, the stale keys, the asset popup's names
    /// and the diagnostics' messages — each one a row that appears or goes.
    /// Values, the revision and the playhead are NOT here: they are read
    /// fresh by `refresh()`.
    override var structureSignature: String {
        guard allGraphic else { return super.structureSignature + "|-" }
        let shared = self.shared()
        let parsed = schema(shared)
        let keys = parsed?.schema.entries.map { "\($0.key):\($0.type)" } ?? []
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
        return [
            super.structureSignature, shared?.name ?? "mixed", keys.joined(separator: ","),
            stale.joined(separator: ","), assetPopupNames(parsed?.schema).joined(separator: ","),
        ].joined(separator: "|") + "|" + messages.joined(separator: "|")
    }

    /// The asset popups' names: the folder's, then any an asset prop holds
    /// that the folder lacks — each one an item of a popup.
    private func assetPopupNames(_ schema: GraphicSchema?) -> [String] {
        let files = assetNames()
        let assetKeys = schema?.entries.filter { $0.type == "asset" }.map(\.key) ?? []
        guard !assetKeys.isEmpty else { return files }
        let stored = storedProps()
        let held = assetKeys.compactMap { key -> String? in
            if case .string(let text)? = stored[key] { return text }
            return nil
        }
        return files + Set(held).subtracting(files).sorted()
    }

    // MARK: - Properties

    /// One row per schema key in the module's order, then the stale keys,
    /// sorted. With no compiled schema every stored key is stale. Reset
    /// nulls every stored key; its `differs` folds from the rows.
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
