import Foundation

/// One op's ARGUMENTS as the core declares them — the published half of the
/// op table (`core/src/op_table.rs`, projected by `core/src/op_schema.rs`
/// and carried out by `rc_op_schemas`).
///
/// It holds the two things `AgentServer.tool(_:_:_:required:)` takes and
/// nothing else: a JSON-Schema fragment per argument, and which of them the
/// core will not do without. **What an argument is FOR never travels here**
/// — the prose naming the menu item a tool mirrors and the app state a
/// default comes from is the catalog's, and stays there.
///
/// `properties` is `[String: Any]` as `JSONSerialization` read it rather
/// than a typed mirror of the core's kinds, for the reason the whole export
/// exists: a Swift type per kind would be a third spelling of the table, and
/// a third spelling is the thing this deletes.
///
/// **It lives here rather than in `ReelCore.swift` for `ReelEdit.swift`'s
/// reason**: it names no `rc_*` symbol, so the rule that keeps every one of
/// those in one file does not keep this, and that file is over its cap. The
/// reader that DOES name one, `ReelOp.coreSchemas()`, stayed behind.
struct ReelOpSchema {
    /// One JSON-Schema fragment per argument, keyed by argument name.
    let properties: [String: Any]
    /// The arguments the core requires, in table order.
    let required: [String]
}
