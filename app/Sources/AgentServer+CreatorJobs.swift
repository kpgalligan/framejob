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
    ]

    /// The road map's tools that run off the main thread, unioned into
    /// `AgentServer.offMainTools`.
    static let creatorOffMainTools: Set<String> = ["get_media_analysis"]

    /// The road map's catalog rows, in catalog order: `get_media_analysis`
    /// (CJ2a, `AgentCatalog+Analysis.swift`). `catalogJSON()` splices them in
    /// immediately before the dev tools' rows, so the dev block still runs
    /// straight into `import_media` and the file groups stay last.
    func creatorTools() -> [[String: Any]] {
        analysisTools()
    }
}
