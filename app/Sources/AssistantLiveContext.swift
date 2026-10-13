import Foundation

/// The window's live context, as it is when the person sends a message: the
/// block `AssistantPrompt.message` puts in front of the person's text (spec
/// §11 AI-15). The system prompt is fixed for a session, so what changes
/// between turns — the playhead, the selection, the open nest — rides on the
/// message instead. Each label is a key of `get_project`'s answer, and the
/// system prompt names the block by `tag`. Road map 12 A3.
struct AssistantLiveContext: Equatable {
    let name: String
    let path: String?
    let scope: UInt32?
    let playhead: Ticks
    /// Ascending.
    let selection: [UInt32]

    /// The block's element name; the system prompt interpolates it.
    static let tag = "framejob_context"

    init(name: String, path: String?, scope: UInt32?, playhead: Ticks, selection: [UInt32]) {
        self.name = name
        self.path = path
        self.scope = scope
        self.playhead = playhead
        self.selection = selection
    }

    /// The document's context, read as `get_project` reads it. Main only.
    init(document: ProjectDocument) {
        assert(Thread.isMainThread)
        self.init(
            name: document.displayName ?? "Untitled", path: AgentServer.path(of: document),
            scope: document.scope, playhead: document.playhead,
            selection: document.selection.sorted())
    }

    /// The block, with no trailing newline.
    var text: String {
        let seconds = String(format: "%.3f", Double(playhead) / Double(ReelTime.perSecond))
        let lines = [
            "<\(Self.tag)>",
            "name: \(name)",
            "path: " + (path ?? "none (never saved)"),
            "scope: "
                + (scope.map { "\($0) (a nest is open: ids and times are its own)" }
                    ?? "none (the timeline is open)"),
            "playhead: \(playhead) (\(seconds) s)",
            "selection: "
                + (selection.isEmpty ? "none" : selection.map(String.init).joined(separator: ", ")),
            "</\(Self.tag)>",
        ]
        return lines.joined(separator: "\n")
    }
}
