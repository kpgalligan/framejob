import Foundation

// MARK: - The creator-jobs seam: road map "creator-jobs"'s tools join dispatch here

/// Where road map "creator-jobs"'s tools join dispatch (spec §11 CJ-8 (d);
/// creator-jobs CJ0c, T8).
///
/// A tool of the road map is a handler row in `creatorHandlers` and, when it
/// runs off the main thread, a member of `creatorOffMainTools`, and nothing
/// in `AgentServer.swift`, which is frozen. That file merges both tables by
/// its two lines: `handlers` is `withDevHandlers(withCreatorHandlers(
/// productHandlers))` — creator into product first, the dev tools last — and
/// `offMainTools` is the union of the product, creator and dev sets. A
/// creator tool that reuses a product tool's name keeps the PRODUCT handler,
/// traps on Debug and logs a `Frame Job: ` line on Release, the way the
/// startup parity check complains. The tool's catalog row goes in the phase's
/// own `AgentCatalog+<Area>.swift`.
extension AgentServer {
    /// `product` with `creatorHandlers` merged in. A creator-jobs tool that
    /// reuses a product tool's name keeps the PRODUCT handler and complains the
    /// way the startup parity check does.
    static func withCreatorHandlers(_ product: [String: ToolHandler]) -> [String: ToolHandler] {
        var merged = product
        for (name, handler) in creatorHandlers.sorted(by: { $0.key < $1.key }) {
            if merged[name] != nil {
                let msg = "creator-jobs tool \(name) reuses a product tool's name"
                assertionFailure(msg)
                NSLog("Frame Job: %@", msg)
                continue
            }
            merged[name] = handler
        }
        return merged
    }

    /// Road map "creator-jobs"'s tool handlers, by tool name.
    private static let creatorHandlers: [String: ToolHandler] = [
        // AgentServer+Analysis.swift (CJ2a, spec §11 CJ-25)
        "get_media_analysis": { $0.getMediaAnalysis },
        // AgentServer+Analysis.swift (CJ2b, spec §11 CJ-29)
        "split_at_shots": { $0.splitAtShots },
        // AgentServer+TimelineTranscript.swift (TX1, spec §11 TX-13)
        "get_timeline_transcript": { $0.getTimelineTranscript },
        // AgentServer+Derived.swift (CJ5b, spec §11 CJ-52)
        "new_project_from_range": { $0.newProjectFromRange },
        // AgentServer+Retime.swift (CU9a, spec §11 CU-90)
        "retime_range": { $0.retimeRange },
        // AgentServer+Cutout.swift (CO3, spec §11 CO-31)
        "analyze_cutout": { $0.analyzeCutout },
        // AgentServer+BehindSubject.swift (CO5, spec §11 CO-54)
        "text_behind_subject": { $0.textBehindSubject },
        // AgentServer+Cursor.swift (CU5, spec §11 CU-50, CU-53)
        "set_media_cursor": { $0.setMediaCursor },
        "get_cursor_events": { $0.getCursorEvents },
        // AgentServer+AutoZoom.swift (CU7, spec §11 CU-76)
        "auto_zoom": { $0.autoZoom },
        // AgentServer+ShortcutOverlays.swift (CU8, spec §11 CU-84)
        "add_shortcut_overlays": { $0.addShortcutOverlays },
        // AgentServer+SpeedUpTyping.swift (CU9b, spec §11 CU-93)
        "speed_up_typing": { $0.speedUpTyping },
    ]

    /// The road map's tools that run off the main thread, unioned into
    /// `AgentServer.offMainTools`.
    static let creatorOffMainTools: Set<String> = [
        "get_media_analysis", "split_at_shots", "get_timeline_transcript",
        "new_project_from_range", "analyze_cutout", "get_cursor_events", "auto_zoom",
        "add_shortcut_overlays", "speed_up_typing",
    ]

    /// The road map's catalog rows, in catalog order: `get_media_analysis`
    /// (CJ2a) and `split_at_shots` (CJ2b), both `AgentCatalog+Analysis.swift`,
    /// then `get_timeline_transcript` (TX1, `AgentCatalog+Transcript.swift`),
    /// then `new_project_from_range` (CJ5b, `AgentCatalog+Derived.swift`),
    /// then the op tool `retime_range` (CU9a, `AgentCatalog+Retime.swift`), then
    /// `analyze_cutout` (CO3, `AgentCatalog+Cutout.swift`), then
    /// `text_behind_subject` (CO5, `AgentCatalog+BehindSubject.swift`), then the
    /// op tool `set_media_cursor` and `get_cursor_events` (CU5,
    /// `AgentCatalog+Cursor.swift`), then `auto_zoom` (CU7,
    /// `AgentCatalog+AutoZoom.swift`), then `add_shortcut_overlays` (CU8,
    /// `AgentCatalog+ShortcutOverlays.swift`), then `speed_up_typing` (CU9b,
    /// `AgentCatalog+SpeedUpTyping.swift`).
    /// `catalogJSON()` splices them in immediately before the dev tools' rows,
    /// so the dev block still runs straight into `import_media` and the file
    /// groups stay last.
    func creatorTools() -> [[String: Any]] {
        var tools: [[String: Any]] = analysisTools() + transcriptTools() + derivedTools()
        tools += retimeTools() + cutoutTools()
        tools += behindSubjectTools()
        tools += cursorTools()
        tools += autoZoomTools()
        tools += shortcutOverlayTools()
        tools += speedUpTypingTools()
        return tools
    }
}
