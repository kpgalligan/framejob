import AppKit

#if REELCUT_DEV_TOOLS
/// `select_inspector_tab` — a dev tool (road map 11's V3, spec §11 V-1..V-2):
/// pick the inspector's tab, and the Clip tab's sub-tab, in a project's
/// editor window, so `snapshot_ui` can capture what a click there shows.
///
/// **It goes through the clicks' own paths.** The tab is
/// `InspectorViewController.select(_:)`, which the tab strip calls; the
/// sub-tab is `selectClipSubTab(_:)`, which the sub-tab strip calls. Nothing
/// here writes the inspector's state any other way, so what is captured is
/// what a person's click would have drawn.
///
/// It runs on MAIN (not in `devOffMainTools`): it waits for nothing, and
/// every step is one AppKit call.
///
/// **Every refusal leaves the inspector as it was.** Arguments are read and
/// refused before anything moves; a sub-tab the selection does not have is
/// found only after the tab is picked (the Clip pane is in the view tree
/// only then), so that refusal is sent after the tab it found is picked
/// again.
extension AgentServer {

    func selectInspectorTab(_ a: [String: Any]) throws -> String {
        let tabs = InspectorTab.allCases.map { $0.title.lowercased() }
        let subs = ClipSubTab.allCases.map(\.rawValue)
        var tab: InspectorTab?
        if let raw = try stringArg(a, "tab") {
            guard let found = InspectorTab.allCases.first(where: { $0.title.lowercased() == raw })
            else {
                throw ToolError(
                    message: "tab must be one of \(tabs.joined(separator: ", ")) (got \"\(raw)\").")
            }
            tab = found
        }
        var sub: ClipSubTab?
        if let raw = try stringArg(a, "sub_tab") {
            guard let found = ClipSubTab(rawValue: raw) else {
                throw ToolError(
                    message: "sub_tab must be one of \(subs.joined(separator: ", ")) "
                        + "(got \"\(raw)\").")
            }
            sub = found
        }
        if sub != nil, tab != .clip {
            throw ToolError(
                message: "sub_tab needs tab clip: the sub-tabs are the Clip tab's.")
        }

        let document = try target(a)
        guard let inspector = editor(document)?.inspector, inspector.isViewLoaded else {
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            throw ToolError(
                message: "The project \(name) has no window: select_inspector_tab reaches the "
                    + "inspector only through its editor window.")
        }
        let project = UISnapshot.orNull(Self.path(of: document))
        guard let tab else {
            return try jsonResult(inspectorTabAnswer(inspector, project))
        }
        if sub != nil, inspector.selectedClips.isEmpty {
            throw ToolError(
                message: "sub_tab needs a selected clip: the Clip tab shows sub-tabs only for "
                    + "a selection (set_selection).")
        }

        let previous = inspector.tab
        inspector.select(tab)
        if let sub {
            let offered = Self.clipPane(in: inspector)?.subTabs ?? []
            guard offered.contains(sub) else {
                inspector.select(previous)
                let names = offered.map(\.rawValue).joined(separator: ", ")
                throw ToolError(
                    message: "The selection has no \(sub.rawValue) sub-tab; its sub-tabs are "
                        + "\(names).")
            }
            inspector.selectClipSubTab(sub)
        }
        return try jsonResult(inspectorTabAnswer(inspector, project))
    }

    /// What the inspector shows now: the tab and, on the Clip tab with a
    /// selection, the active sub-tab and the ones on offer. Main thread.
    private func inspectorTabAnswer(
        _ inspector: InspectorViewController, _ project: Any
    ) -> [String: Any] {
        var sub: Any = NSNull()
        var offered: [String] = []
        if inspector.tab == .clip, !inspector.selectedClips.isEmpty,
            let pane = Self.clipPane(in: inspector)
        {
            sub = pane.activeSubTab.rawValue
            offered = pane.subTabs.map(\.rawValue)
        }
        return [
            "ok": true,
            "project": project,
            "tab": inspector.tab.title.lowercased(),
            "sub_tab": sub,
            "sub_tabs": offered,
        ]
    }

    /// The Clip pane among the inspector's descendants — there only while the
    /// Clip tab shows it. Main thread.
    private static func clipPane(in inspector: InspectorViewController) -> ClipPane? {
        var queue: [NSView] = [inspector.view]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let pane = view as? ClipPane { return pane }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    // MARK: - Catalog

    func selectInspectorTabTool() -> [String: Any] {
        tool(
            "select_inspector_tab",
            "DEV TOOL (absent from Distribution builds). Pick the inspector's tab, and the "
                + "Clip tab's sub-tab, in a project's editor window, through the same calls "
                + "the tab strip's and the sub-tab strip's clicks make — so snapshot_ui "
                + "captures what a click would show. With no tab, changes nothing and answers "
                + "what is shown. Answers the tab, and on the Clip tab with a selection the "
                + "active sub-tab and the sub-tabs on offer. Refused, changing nothing: a "
                + "sub_tab without tab clip, a sub_tab with no clip selected, and a sub_tab "
                + "the selection does not have (the refusal names the ones it has). The pick "
                + "is forgotten when the selection changes, as a click's is.",
            [
                "tab": [
                    "type": "string",
                    "enum": InspectorTab.allCases.map { $0.title.lowercased() },
                    "description": "The inspector tab to show. Omit to change nothing and "
                        + "answer what is shown.",
                ],
                "sub_tab": [
                    "type": "string", "enum": ClipSubTab.allCases.map(\.rawValue),
                    "description": "With tab clip: the sub-tab to show. The selection "
                        + "decides which it has (text, shape, graphic, picture, sound, and "
                        + "clip always).",
                ],
            ])
    }
}
#endif
