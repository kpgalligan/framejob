import Foundation

// MARK: - What the assistant may not call, and what it asks about first

/// Spec §11 AI-7 as ONE table: every tool the assistant may not call
/// (`withheld`) or must ask the person about first (`askFirst`), each row with
/// its reason. The lane reads it (`AgentLane.submit`); an MCP caller never
/// does, because the rule belongs to the assistant's lane and not to the tool.
enum AssistantToolRule {
    case withheld
    case askFirst
}

/// One row. `onlyWith` narrows the row to calls carrying that argument with
/// that string value (`transcribe` is withheld only for the cloud engine).
struct AssistantToolRow {
    let tool: String
    let rule: AssistantToolRule
    let onlyWith: (key: String, value: String)?
    let reason: String
}

/// What the person is asked before an ask-first tool runs: the tool, where it
/// writes, and whether something is already there.
struct AssistantQuestion {
    let tool: String
    let path: String?
    let exists: Bool

    /// "export writes <path>", "export REPLACES <path>" when a file is already
    /// there (A0 E2: `export` replaces without asking), "<tool> writes a file"
    /// with no path; `consolidate_media` says what it copies, and where.
    var sentence: String {
        if tool == "consolidate_media" {
            return "consolidate_media copies every referenced file into "
                + (path ?? "the project's package")
        }
        guard let path = path else { return "\(tool) writes a file" }
        return exists ? "\(tool) REPLACES \(path)" : "\(tool) writes \(path)"
    }
}

enum AssistantToolTable {
    /// The product tools the table names. The dev tools are withheld too, by
    /// `row(for:)`, from `AgentServer.devToolNames`, so a new dev tool needs no
    /// row here.
    static let rows: [AssistantToolRow] = [
        AssistantToolRow(
            tool: "record_screen", rule: .withheld, onlyWith: nil,
            reason: "Recording is a person at the Record button (File ▸ New Recording…)."),
        AssistantToolRow(
            tool: "close_project", rule: .withheld, onlyWith: nil,
            reason: "Closing a project closes the window this conversation lives in (AI-5); the "
                + "person closes it with File ▸ Close (⌘W)."),
        AssistantToolRow(
            tool: "transcribe", rule: .withheld, onlyWith: (key: "engine", value: "assemblyai"),
            reason: "Audio leaves the machine only by name, with the price in front of the "
                + "person (spec §11 R6-2). Use File ▸ Generate Captions…, which shows what is "
                + "uploaded and what it costs."),
        AssistantToolRow(
            tool: "transcribe_for_fillers", rule: .withheld, onlyWith: nil,
            reason: "Audio leaves the machine only by name, with the price in front of the "
                + "person (spec §11 R6-2). Use Clip ▸ Remove Filler Words…, which shows what is "
                + "uploaded and what it costs."),
        AssistantToolRow(
            tool: "export", rule: .askFirst, onlyWith: nil,
            reason: "It writes a movie where the model chose, replacing any file already there "
                + "(A0 E2)."),
        AssistantToolRow(
            tool: "export_captions", rule: .askFirst, onlyWith: nil,
            reason: "It writes a caption file."),
        AssistantToolRow(
            tool: "save_project", rule: .askFirst, onlyWith: nil,
            reason: "It writes the package."),
        AssistantToolRow(
            tool: "consolidate_media", rule: .askFirst, onlyWith: nil,
            reason: "It copies every referenced file into the package."),
    ]

    static let devToolReason =
        "a developer tool (spec §11 V-1): Distribution has none, and the assistant sees one "
        + "catalog in both builds."

    /// The row governing `tool`: every dev tool is withheld (V-1), else the
    /// table's own row, else nil (the tool is the assistant's to call).
    static func row(for tool: String) -> AssistantToolRow? {
        if AgentServer.devToolNames.contains(tool) {
            return AssistantToolRow(
                tool: tool, rule: .withheld, onlyWith: nil, reason: devToolReason)
        }
        return rows.first { $0.tool == tool }
    }

    /// The lane's refusal of a withheld call, or nil. A conditional row
    /// refuses only a call carrying its argument, and names it.
    static func refusal(tool: String, arguments: [String: Any]) -> String? {
        guard let entry = row(for: tool), entry.rule == .withheld else { return nil }
        var name = tool
        if let only = entry.onlyWith {
            guard arguments[only.key] as? String == only.value else { return nil }
            name = "\(tool) with \(only.key) \"\(only.value)\""
        }
        return "\(name) is not available to the assistant: \(entry.reason)"
    }

    /// The question an ask-first call puts to the person, or nil for any other
    /// tool. Main only: it reads the document and the file system.
    static func question(
        tool: String, arguments: [String: Any], document: ProjectDocument
    ) -> AssistantQuestion? {
        assert(Thread.isMainThread)
        guard row(for: tool)?.rule == .askFirst else { return nil }
        let given = (arguments["path"] as? String).map { ($0 as NSString).expandingTildeInPath }
        let path: String?
        switch tool {
        case "save_project":
            // Never `importSourceURL`: that is the movie, not where a save writes.
            path = given ?? document.fileURL?.path
        case "consolidate_media":
            path = document.fileURL.map { "\($0.path)/media" }
        default:
            path = given
        }
        let exists = path.map { FileManager.default.fileExists(atPath: $0) } ?? false
        return AssistantQuestion(tool: tool, path: path, exists: exists)
    }

    /// The catalog the assistant is handed: `tools` less every tool withheld
    /// outright. A conditional row (`transcribe`) keeps its tool, and the lane
    /// refuses the call it names.
    static func assistantCatalog(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.filter { tool in
            guard let name = tool["name"] as? String, let entry = row(for: name) else {
                return true
            }
            return !(entry.rule == .withheld && entry.onlyWith == nil)
        }
    }
}
