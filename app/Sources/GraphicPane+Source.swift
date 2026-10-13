// app/Sources/GraphicPane+Source.swift — the Graphic sub-tab's Source
// section (road map 10 §5j, G5a): which module draws the clip, the three
// buttons (Open in Editor, Reveal in Finder, Duplicate as New Graphic…), and
// what the module says about the clip, each group under its own heading
// (#221): "Compiling the module" over its compile (an error, or what its top
// level warned), when there is any; the clip's FIRST frame drawn and
// rasterized at the clip's own size, when one was drawn, so a missing font
// or a size mismatch shows here (G3c's owed warning, road map 10 §10.6); and
// "In the graphics folder" over what the folder's scan skipped or could not
// watch, each with Reveal (G-24 (b)).
//
// **The report is the paused frame's own two calls** — `module.svg` then
// `library.rasterize` at `graphic.width × height`
// (`LayerRenderersGraphic.swift`) — memoised by module, revision, library,
// the recipe's frame hash and the size, so a miss costs one paused frame.
// While a live gesture runs nothing is recomputed: a miss answers the
// clip's last report.

import AppKit

/// What a graphic clip's module says about it: its compile's diagnostics,
/// and the first frame's — drawn at the graphic's `frame`.
struct GraphicClipReport: Equatable {
    let compile: [GraphicDiagnostic]
    let render: [GraphicDiagnostic]
    let frame: Int?

    static let empty = GraphicClipReport(compile: [], render: [], frame: nil)
}

extension GraphicPane {
    /// The module, its file and revision, the three buttons and the
    /// diagnostics. With clips of different modules, a note naming them.
    func sourceSection() -> InspectorSection {
        guard let first = shared() else {
            let names = Set(binding.graphicClips.compactMap { $0.graphic?.name }).sorted()
            let listed = names.joined(separator: ", ")
            return InspectorSection(
                id: "graphic.source", title: "Source", summary: { "\(names.count) modules" },
                defaultExpanded: false,
                rows: [
                    InspectorNoteLabel { "Drawn by different modules: \(listed)" },
                    InspectorNoteLabel { "Select one module's clips to edit its properties." },
                ])
        }
        let current = { [weak self] in self?.shared() }
        func metaName() -> String {
            if case .compiled(_, _, let meta, _)? = current()?.entry,
               let name = meta["name"] as? String, !name.isEmpty
            {
                return name
            }
            return current()?.name ?? first.name
        }
        func revision() -> String {
            guard let file = current()?.file else { return "missing" }
            return String(file.revision.prefix(8))
        }
        let open: () -> Void = { [weak self] in self?.openFile() }
        let hasFile = { current()?.file != nil }
        let duplicate = OptionButtonControl(
            title: "Duplicate as New Graphic…",
            action: { [weak self] in
                guard let self, let shared = current(), let file = shared.file else {
                    return NSSound.beep()
                }
                self.duplicateAsNewGraphic(file, schema: self.schema(shared)?.raw)
            },
            enabled: hasFile, onEdit: {})
        var rows: [NSView] = [
            inspectorRow("Name", [inspectorReadout(width: 170) { metaName() }]),
            inspectorRow("File", [inspectorReadout(width: 170) { "\(first.name).js" }]),
            inspectorRow("Revision", [inspectorReadout(width: 170) { revision() }]),
            inspectorButtonRow([
                OptionButtonControl(
                    title: "Open in Editor", action: open, enabled: hasFile, onEdit: {}),
                OptionButtonControl(
                    title: "Reveal in Finder",
                    action: {
                        guard let url = current()?.file?.url else { return NSSound.beep() }
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    enabled: hasFile, onEdit: {}),
            ]),
            inspectorButtonRow([duplicate]),
        ]
        var report = GraphicClipReport.empty
        if let clip = binding.graphicClips.first, let document = binding.document {
            let version = GraphicRegistry.shared.snapshot(for: document.recipeKey)?.libraryVersion
            report = self.report(for: clip, first, libraryVersion: version ?? "")
        }
        let diagnostics = report.compile + report.render
        if !report.compile.isEmpty {
            rows.append(InspectorNoteLabel { "Compiling the module" })
            rows += report.compile.map { GraphicDiagnosticRow($0, onOpen: open) }
        }
        if report.frame != nil {
            let checked = report.render.isEmpty
                ? "No errors or warnings at the clip's first frame"
                : "Checked at the clip's first frame"
            rows.append(InspectorNoteLabel { checked })
            rows += report.render.map { GraphicDiagnosticRow($0, onOpen: open) }
        }
        let folder = folderWarnings()
        if !folder.isEmpty {
            let reveal: () -> Void = { [weak self] in
                guard let url = self?.binding.document?.graphicStore?.folderURL,
                      FileManager.default.fileExists(atPath: url.path)
                else { return NSSound.beep() }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            rows.append(InspectorNoteLabel { "In the graphics folder" })
            rows += folder.map {
                GraphicDiagnosticRow(
                    GraphicDiagnostic(
                        level: "warning", message: $0, line: nil, column: nil, frame: nil),
                    openTitle: "Reveal", help: "Reveal the graphics folder in Finder",
                    onOpen: reveal)
            }
        }
        let errors = diagnostics.filter { $0.level == "error" }.count
        let warnings = diagnostics.count - errors + folder.count
        return InspectorSection(
            id: "graphic.source", title: "Source",
            summary: {
                errors > 0 ? (errors == 1 ? "1 error" : "\(errors) errors")
                    : warnings > 0 ? (warnings == 1 ? "1 warning" : "\(warnings) warnings")
                    : metaName()
            },
            defaultExpanded: false,
            rows: rows)
    }

    /// Opens the shared module's file in the app the system gives `.js`.
    func openFile() {
        guard let url = shared()?.file?.url else { return NSSound.beep() }
        NSWorkspace.shared.open(url)
    }

    /// The module's compile, and `clip`'s first frame drawn and rasterized at
    /// the clip's own size — through the memo, and never recomputed while a
    /// live gesture runs.
    func report(
        for clip: ClipSnapshot, _ shared: Shared, libraryVersion: String
    ) -> GraphicClipReport {
        let module: GraphicModule, revision: String
        switch shared.entry {
        case nil:
            return GraphicClipReport(
                compile: [GraphicDiagnostic(
                    level: "error", message: "No module named \"\(shared.name)\" in graphics/",
                    line: nil, column: nil, frame: nil)],
                render: [], frame: nil)
        case .failed(let diagnostics, _)?:
            return GraphicClipReport(compile: diagnostics, render: [], frame: nil)
        case .compiled(let compiled, let hash, _, _)?:
            module = compiled
            revision = hash
        }
        guard let graphic = clip.graphic, let document = binding.document else { return .empty }
        if document.isLiveEditing { return lastReports[clip.id] ?? .empty }
        guard let set = GraphicRegistry.shared.snapshot(for: document.recipeKey),
              let source = layerSource(of: clip),
              case .graphic(_, let hash, let frame, let propsJSON, let ctxJSON) = source
        else { return .empty }
        let key = [
            shared.name, revision, libraryVersion, hash, "\(graphic.width)×\(graphic.height)",
        ].joined(separator: "|")
        if let hit = reportMemo[key] {
            lastReports[clip.id] = hit
            return hit
        }
        var render: [GraphicDiagnostic] = []
        do {
            let drawn = try module.svg(
                frame: frame, propsJSON: propsJSON, ctxJSON: ctxJSON,
                budgetMs: GraphicRegistry.previewBudgetMs)
            render += drawn.warnings
            do {
                let raster = try set.library.rasterize(
                    drawn.svg, width: graphic.width, height: graphic.height)
                render += raster.warnings
            } catch {
                render += Self.diagnostics(of: error)
            }
        } catch {
            render += Self.diagnostics(of: error)
        }
        let report = GraphicClipReport(
            compile: module.compileWarnings, render: render, frame: frame)
        if reportMemo.count >= 64 { reportMemo.removeAll() }
        reportMemo[key] = report
        lastReports[clip.id] = report
        return report
    }

    /// `clip`'s layer source in the recipe at its start, through
    /// `layerMemo`: `recipe(at:)` is asked only on a miss, and the memo is
    /// emptied when the binding's project is another handle.
    func layerSource(of clip: ClipSnapshot) -> RecipeSourceRef? {
        guard let project = binding.project else { return nil }
        if project !== layerProject {
            layerMemo = [:]
            layerProject = project
        }
        if let hit = layerMemo[clip.id] { return hit }
        guard let layer = project.recipe(at: clip.start)?.layers
            .first(where: { $0.clip == clip.id })
        else { return nil }
        layerMemo[clip.id] = layer.source
        return layer.source
    }

    /// The engine's diagnostics out of a thrown error, else one error
    /// saying what was thrown.
    private static func diagnostics(of error: any Error) -> [GraphicDiagnostic] {
        if let failure = error as? GraphicFailure, !failure.diagnostics.isEmpty {
            return failure.diagnostics
        }
        return [GraphicDiagnostic(
            level: "error", message: error.localizedDescription, line: nil, column: nil,
            frame: nil)]
    }

    /// Copies the module's file under a new name the person types, then
    /// repoints the selected clips at it with `set_graphic {name}` — the
    /// copy is not undoable (G-3), the repoint is one step. The MCP mirror is
    /// `write_graphic` of the source under the new name, then `set_graphic`.
    func duplicateAsNewGraphic(_ file: GraphicModuleFile, schema: [String: Any]?) {
        guard let store = binding.document?.graphicStore else { return NSSound.beep() }
        let suggestion = store.uniqueModuleName(file.name + "-copy")
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Duplicate \(file.name).js as a new graphic"
        alert.informativeText =
            "The copy is written into the package's graphics/ folder and the selected clips "
            + "are drawn by it. Writing the file cannot be undone; switching the clips can."
        let field = NSTextField(string: suggestion)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        field.placeholderString = "Module name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Duplicate")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        func refuse(_ sentence: String) {
            NSAlert(error: NSError(
                domain: "FrameJob", code: 1, userInfo: [NSLocalizedDescriptionKey: sentence]))
                .runModal()
        }
        guard GraphicStore.isModuleName(name) else { return refuse(GraphicStore.nameSentence(name)) }
        guard !store.holdsModule(named: name) else {
            return refuse("graphics/\(name).js already exists")
        }
        do {
            try store.write(name: name, source: String(decoding: file.bytes, as: UTF8.self))
        } catch {
            return refuse("graphics/\(name).js could not be written: \(error.localizedDescription)")
        }
        store.rescan()
        let clips = binding.graphicClips.map(\.id)
        binding.apply(
            "Duplicate Graphic",
            clips.isEmpty ? [] : [.setGraphicRaw(clips: clips, patch: ["name": name], schema: schema)])
    }
}

/// One diagnostic: "line L, column C — message", an error in the strong
/// ink and a warning in the muted one. A click on it, or on its Open, opens
/// the module in the editor; a folder row's button is Reveal instead.
final class GraphicDiagnosticRow: NSView {
    let diagnostic: GraphicDiagnostic
    private let onOpen: () -> Void
    let label = NSTextField(wrappingLabelWithString: "")

    init(
        _ d: GraphicDiagnostic, openTitle: String = "Open",
        help: String = "Open the module in the editor", onOpen: @escaping () -> Void
    ) {
        diagnostic = d
        self.onOpen = onOpen
        super.init(frame: .zero)
        var place = ""
        if let line = d.line {
            place = d.column.map { "line \(line), column \($0) — " } ?? "line \(line) — "
        }
        label.stringValue = place + d.message
        label.font = DS.sans(11)
        label.textColor = d.level == "error" ? DS.textStrong : DS.textMuted
        label.isSelectable = false
        label.preferredMaxLayoutWidth = 200
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let open = OptionButtonControl(
            title: openTitle, action: { [weak self] in self?.onOpen() }, enabled: { true },
            onEdit: {})
        open.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, open])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: InspectorMetrics.markGutter),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        toolTip = help
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GraphicDiagnosticRow does not support NSCoder")
    }

    override func mouseDown(with event: NSEvent) {
        onOpen()
    }
}
