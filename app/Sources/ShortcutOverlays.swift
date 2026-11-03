import Foundation

/// Add Shortcut Overlays' Swift half (road map "creator-jobs" CU8, spec §11 CU-80…CU-84): the
/// settings, the bundled `keyboard-keys` template and the module rule (CU-81), and
/// `plan_overlays` asked of the core through `ReelCursor` (this file names no `rc_*`, CJ-8 (l))
/// with its answer read into ops. Both doors — Clip ▸ Add Shortcut Overlays
/// (`EditorViewController+ShortcutOverlays.swift`) and `add_shortcut_overlays`
/// (`AgentServer+ShortcutOverlays.swift`) — place through `prepared`. The cursor files are
/// found and read by `AutoZoom.cursorFiles` and `AutoZoom.readTracks`.

/// What a run places with (CU-80's defaults; the owner's answer: bottom, dark). Nothing is
/// remembered: the menu item has no sheet to change it.
struct ShortcutOverlaySettings: Equatable {
    var duration = 1.5
    var position = "bottom"
    var theme = "dark"

    static let durationRange: ClosedRange<Double> = 0.5...10
    static let positions = ["bottom", "center", "top"]
    static let themes = ["dark", "light"]
}

/// `plan_overlays`' answer: the ops in the core's order and its counts.
struct ShortcutOverlayPlan {
    let ops: [ReelOp]
    let added, dropped, merged: Int
    let track: UInt32
    let newTrack: Bool
    let overlays: [[String: Any]]
}

enum ShortcutOverlays {
    /// The undo step's name, both doors.
    static let actionName = "Add Shortcut Overlays"
    /// The bundled template the overlays are drawn by.
    static let templateName = "keyboard-keys"

    /// What a run that placed nothing says (CU-84).
    static let nothingSentence =
        "No shortcut was recorded in the selected clips' played windows, so nothing was added."

    /// What a run that dropped `n` presses says (CU-80).
    static func droppedSentence(_ n: Int) -> String {
        n == 1
            ? "1 shortcut came too close to show."
            : "\(n) shortcuts came too close to show."
    }

    /// The documents a menu run is reading cursor files for. Main only.
    private static var pending: Set<ObjectIdentifier> = []

    static func isPending(_ document: ProjectDocument) -> Bool {
        pending.contains(ObjectIdentifier(document))
    }

    static func setPending(_ document: ProjectDocument, _ on: Bool) {
        if on {
            pending.insert(ObjectIdentifier(document))
        } else {
            pending.remove(ObjectIdentifier(document))
        }
    }

    /// The bundled `keyboard-keys.js`: its URL, its bytes and the schema
    /// `GraphicTemplateLibrary` compiled from it. Main (the library's first read).
    static func template() throws -> (url: URL, bytes: Data, schema: [String: Any]) {
        guard let found = GraphicTemplateLibrary.shared.entry(named: templateName) else {
            throw AutoZoom.Refusal(
                message: "The bundled \(templateName) template is missing from this build.")
        }
        guard case .compiled(_, _, _, let schema) = found.entry,
            let bytes = try? Data(contentsOf: found.template.url)
        else {
            throw AutoZoom.Refusal(
                message: "The bundled \(templateName) template does not compile.")
        }
        return (found.template.url, bytes, schema)
    }

    /// CU-81: a module of `store` whose bytes equal the template's — `keyboard-keys` first,
    /// else the lowest name — or nil.
    static func reusableModule(in store: GraphicStore, bytes: Data) -> String? {
        let same = store.scan.modules.values.filter { $0.bytes == bytes }.map(\.name)
        return same.contains(templateName) ? templateName : same.min()
    }

    /// `plan_overlays`' request JSON for `clips` (container ticks `from`/`to`, nil for none).
    static func request(
        _ clips: [UInt32], settings: ShortcutOverlaySettings, module: String,
        schema: [String: Any], from: Ticks?, to: Ticks?
    ) -> String {
        var args: [String: Any] = [
            "clips": clips.map { Int($0) }, "duration": settings.duration,
            "position": settings.position, "theme": settings.theme, "module": module,
            "schema": schema,
        ]
        if let from { args["from"] = from }
        if let to { args["to"] = to }
        let data =
            (try? JSONSerialization.data(withJSONObject: ["plan_overlays": args])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Asks the core for the plan over `clips` of `project` (the edited one, so inside a nest
    /// the nest's), one track per clip; throws the core's sentence as a `Refusal`.
    static func plan(
        _ clips: [ClipSnapshot], tracks: [UInt32: ReelCursor], project: ReelProject,
        settings: ShortcutOverlaySettings, module: String, schema: [String: Any],
        from: Ticks?, to: Ticks?
    ) throws -> ShortcutOverlayPlan {
        var ordered: [ReelCursor] = []
        for clip in clips {
            guard case .media(let id, _, _) = clip.source, let track = tracks[id] else {
                throw AutoZoom.Refusal(message: "Clip \(clip.id)'s cursor file was not read.")
            }
            ordered.append(track)
        }
        let text: String
        do {
            text = try ReelCursor.query(
                request(
                    clips.map(\.id), settings: settings, module: module, schema: schema,
                    from: from, to: to),
                tracks: ordered, project: project)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw AutoZoom.Refusal(message: AutoZoom.sentence(reason))
        }
        guard let answer = try? JSONSerialization.jsonObject(with: Data(text.utf8))
            as? [String: Any]
        else { throw AutoZoom.Refusal(message: "The overlays' plan could not be read.") }
        let ops = try ((answer["ops"] as? [[String: Any]]) ?? []).map(op)
        func count(_ key: String) -> Int { (answer[key] as? NSNumber)?.intValue ?? 0 }
        return ShortcutOverlayPlan(
            ops: ops, added: count("added"), dropped: count("dropped"),
            merged: count("merged"),
            track: (answer["track"] as? NSNumber)?.uint32Value ?? 0,
            newTrack: (answer["new_track"] as? Bool) ?? false,
            overlays: (answer["overlays"] as? [[String: Any]]) ?? [])
    }

    /// Both doors' run, on main, after the files are read: the module chosen by CU-81, the
    /// plan, and — only when the plan places something and no module could be reused — the
    /// template written into `graphics/` (not undoable, G-3) and the plan made again when the
    /// written name is not the one predicted.
    static func prepared(
        _ document: ProjectDocument, clips ids: [UInt32], tracks: [UInt32: ReelCursor],
        settings: ShortcutOverlaySettings, from: Ticks?, to: Ticks?
    ) throws -> (plan: ShortcutOverlayPlan, module: String, written: Bool) {
        guard let store = document.graphicStore else {
            throw AutoZoom.Refusal(message: ProjectDocument.noGraphicsFolderSentence + ".")
        }
        let template = try template()
        let snapshot = document.editedProject.snapshot
        let clips = ids.compactMap { snapshot.clip($0) }
        func planned(_ module: String) throws -> ShortcutOverlayPlan {
            try plan(
                clips, tracks: tracks, project: document.editedProject, settings: settings,
                module: module, schema: template.schema, from: from, to: to)
        }
        if let reused = reusableModule(in: store, bytes: template.bytes) {
            return (try planned(reused), reused, false)
        }
        let predicted = store.uniqueModuleName(templateName)
        let first = try planned(predicted)
        guard first.added > 0 else { return (first, predicted, false) }
        let written: String
        do {
            written = try document.writeGraphicModule(from: template.url)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw AutoZoom.Refusal(message: AutoZoom.sentence(reason))
        }
        guard written != predicted else { return (first, written, true) }
        return (try planned(written), written, true)
    }

    /// One op of the answer, through `ReelOps.swift`'s factories.
    private static func op(_ o: [String: Any]) throws -> ReelOp {
        func ticks(_ key: String) -> Ticks { (o[key] as? NSNumber)?.int64Value ?? 0 }
        switch o["op"] as? String {
        case "add_track":
            return .addTrack(
                index: (o["index"] as? NSNumber)?.intValue ?? 0, name: o["name"] as? String)
        case "add_graphic_clip":
            return .addGraphicClipRaw(
                track: (o["track"] as? NSNumber)?.uint32Value ?? 0, at: ticks("at"),
                duration: ticks("duration"), name: (o["name"] as? String) ?? "",
                props: o["props"], schema: o["schema"])
        default:
            throw AutoZoom.Refusal(message: "The overlays' plan named an op it does not make.")
        }
    }
}
