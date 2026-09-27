import Foundation

// MARK: - The dev-tools seam: tools compiled only under REELCUT_DEV_TOOLS

/// Where the dev tools live (road map 11, spec §11 V-1 and V-2).
///
/// **The flag.** `REELCUT_DEV_TOOLS` is a Swift compilation condition that
/// Debug and Release set and the Distribution configuration does not
/// (`project.yml`), so every proof and agent session, which launch Release,
/// has the dev tools and the binary `make dist` builds has none of their
/// code (V-1). A dev tool is an ORDINARY tool (V-2): a handler in
/// `devHandlers`, a row from `devTools()`, and nothing else — the parity
/// check, the argument gate and the schema checks cover it as they cover a
/// product tool, in both builds, because both tables are merged before any
/// of them reads.
///
/// **Why the check greps a marker, not tool names.** Swift string literals
/// of 15 UTF-8 bytes or fewer are stored inline in the code of an `-O`
/// binary, not as contiguous bytes, so a short tool name such as
/// `snapshot_ui` (11) can never be found in either build and an absence
/// check on it would pass for nothing. `tools/proof/dist_check.py` reads
/// `devToolsMarker` out of this file instead — at least 16 bytes — and
/// requires it present in Release's binary and absent from Distribution's.
///
/// **What keeps the marker live.** The flag-on `devTools()` logs it, so the
/// optimiser cannot drop the literal. V2 adds rows and handlers here with no
/// edit to the check.
///
/// **Where the rows go.** `catalogJSON()` splices `devTools()` in
/// immediately BEFORE the file tools, never at the end: the catalog's last
/// eleven names are the file group plus `record_screen`, which
/// `recording_probe.py` asserts. Swift takes no `#if` inside a dictionary
/// literal, so `AgentServer.swift` merges `devHandlers` through
/// `withDevHandlers` and `devOffMainTools` by a union, one line each.
extension AgentServer {
    typealias ToolHandler = (AgentServer) -> ([String: Any]) throws -> String

    /// `product` with `devHandlers` merged in. A dev tool that reuses a
    /// product tool's name keeps the PRODUCT handler and complains the way
    /// the startup parity check does.
    static func withDevHandlers(_ product: [String: ToolHandler]) -> [String: ToolHandler] {
        var merged = product
        for (name, handler) in devHandlers.sorted(by: { $0.key < $1.key }) {
            if merged[name] != nil {
                let msg = "dev tool \(name) reuses a product tool's name"
                assertionFailure(msg)
                NSLog("Reelcut: %@", msg)
                continue
            }
            merged[name] = handler
        }
        return merged
    }

    #if REELCUT_DEV_TOOLS
    // dist_check.py parses the next line (D1) and requires it bare — nothing after the
    // closing quote — at least 16 bytes, present in Release's binary, absent from Distribution's.
    static let devToolsMarker = "reelcut-dev-tools-compiled-in"

    private static let devHandlers: [String: ToolHandler] = [
        // AgentServer+Snapshot.swift
        "snapshot_ui": { $0.snapshotUI },
        // AgentServer+MenuItem.swift
        "perform_menu_item": { $0.performMenuItem },
        "cancel_sheet": { $0.cancelSheet },
    ]

    static let devOffMainTools: Set<String> = ["snapshot_ui", "perform_menu_item", "cancel_sheet"]

    /// The dev tools' catalog rows, in catalog order: `snapshot_ui` (V2a),
    /// `perform_menu_item` and `cancel_sheet` (V2b). The log is what keeps
    /// `devToolsMarker` in the optimised binary; it never says `Reelcut: `,
    /// the prefix a proof reads as the parity check complaining.
    func devTools() -> [[String: Any]] {
        let rows: [[String: Any]] = [snapshotUITool(), performMenuItemTool(), cancelSheetTool()]
        NSLog("Reelcut agent server: %@, %ld dev tools", Self.devToolsMarker, rows.count)
        return rows
    }
    #else
    private static let devHandlers: [String: ToolHandler] = [:]

    static let devOffMainTools: Set<String> = []

    /// Distribution ships no dev tools.
    func devTools() -> [[String: Any]] {
        []
    }
    #endif
}
