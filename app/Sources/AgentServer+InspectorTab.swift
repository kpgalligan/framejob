import AppKit

#if FRAMEJOB_DEV_TOOLS
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
/// again; so is a `section` the shown pane does not hold, after which the tab
/// and the sub-tab it showed are picked again.
///
/// `section` (grading GR5b) scrolls the shown pane so that
/// section's top is the visible top, clamped — writing no preference and
/// opening nothing — and the answer says `look_thumbnails_pending` while a
/// Look gallery in the shown pane owes renders (spec §11 GR-7 [b]), which is
/// what a capture of its thumbnails waits out.
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
        let section = try stringArg(a, "section")
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
            if let section { try Self.scroll(inspector, to: section) }
            return try jsonResult(inspectorTabAnswer(inspector, project))
        }
        if sub != nil, inspector.selectedClips.isEmpty {
            throw ToolError(
                message: "sub_tab needs a selected clip: the Clip tab shows sub-tabs only for "
                    + "a selection (set_selection).")
        }

        let previous = inspector.tab
        let previousSub = previous == .clip ? Self.clipPane(in: inspector)?.activeSubTab : nil
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
        if let section {
            do {
                try Self.scroll(inspector, to: section)
            } catch {
                inspector.select(previous)
                if sub != nil, let previousSub { inspector.selectClipSubTab(previousSub) }
                throw error
            }
        }
        return try jsonResult(inspectorTabAnswer(inspector, project))
    }

    /// The scroll view the inspector shows its pane in, and that pane. Main
    /// thread.
    private static func shownPane(
        in inspector: InspectorViewController
    ) -> (NSScrollView, InspectorPaneView)? {
        var queue: [NSView] = [inspector.view]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scroll = view as? NSScrollView, let pane = scroll.documentView as? InspectorPaneView {
                return (scroll, pane)
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Scrolls the shown pane so section `id`'s top is the visible top,
    /// clamped to the pane; refused, naming the sections it holds, when it
    /// holds no such section. Writes no preference and opens nothing.
    private static func scroll(_ inspector: InspectorViewController, to id: String) throws {
        let shown = shownPane(in: inspector)
        let sections = shown?.1.sections ?? []
        guard let (scroll, pane) = shown, let section = sections.first(where: { $0.id == id })
        else {
            let ids = sections.map(\.id)
            throw ToolError(
                message: "The shown pane has no section \(id); its sections are "
                    + (ids.isEmpty ? "none" : ids.joined(separator: ", ")) + ".")
        }
        inspector.view.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let top = section.convert(section.bounds, to: pane).minY
        let bottom = max(0, pane.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, top), bottom)))
        scroll.reflectScrolledClipView(clip)
    }

    /// Whether a Look gallery in the shown pane owes renders. Main thread.
    private static func lookPending(in inspector: InspectorViewController) -> Bool {
        guard let pane = shownPane(in: inspector)?.1 else { return false }
        var queue: [NSView] = [pane]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let gallery = view as? LookGalleryView, gallery.isPending { return true }
            queue.append(contentsOf: view.subviews)
        }
        return false
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
        var answer: [String: Any] = [
            "ok": true,
            "project": project,
            "tab": inspector.tab.title.lowercased(),
            "sub_tab": sub,
            "sub_tabs": offered,
        ]
        if Self.lookPending(in: inspector) { answer["look_thumbnails_pending"] = true }
        return answer
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
                + "is forgotten when the selection changes, as a click's is. section (with or "
                + "without tab) then scrolls the shown pane so that section's top is the visible "
                + "top, writing no preference and opening nothing; a section the pane does not "
                + "hold is refused naming the ones it holds, with the tab and sub-tab put back. "
                + "While a Look gallery in the shown pane is open and still owes thumbnails the "
                + "answer carries look_thumbnails_pending: true, absent otherwise.",
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
                "section": [
                    "type": "string",
                    "description": "A section id in the shown pane (video.look, "
                        + "video.light, …) to scroll to the top of the inspector, after any "
                        + "tab and sub_tab pick.",
                ],
            ])
    }
}
#endif
