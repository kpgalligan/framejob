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
/// `askOnlyWith` narrows an ask-first row to calls carrying that argument
/// (`new_project_from_range` asks only when it names `path`, CJ-52); declared
/// last, with a default, so every other row's init is unchanged. `refusesTaken`
/// says the tool refuses an occupied path, so an occupied path is not asked
/// about (spec §11 AI-21 (d)).
struct AssistantToolRow {
    let tool: String
    let rule: AssistantToolRule
    let onlyWith: (key: String, value: String)?
    let reason: String
    var askOnlyWith: String? = nil
    var refusesTaken: Bool = false
}

/// What the person is asked before an ask-first tool runs: the tool, the file
/// it will write, whether something is already there, and any other file the
/// call replaces. A call with no path is never asked about (spec §11 AI-21).
/// `alsoReplaces` is declared last, with a default, so an init naming the
/// first three is unchanged.
struct AssistantQuestion {
    let tool: String
    let path: String
    let exists: Bool
    var alsoReplaces: [String] = []

    /// "export writes <path>", "export REPLACES <path>" when a file is already
    /// there (A0 E2: `export` replaces without asking), then ", and REPLACES
    /// <a>, <b>" for `alsoReplaces`; `consolidate_media` says what it copies,
    /// and where.
    var sentence: String {
        if tool == "consolidate_media" {
            return "consolidate_media copies every referenced file into \(path)"
        }
        let said = exists ? "\(tool) REPLACES \(path)" : "\(tool) writes \(path)"
        guard !alsoReplaces.isEmpty else { return said }
        return said + ", and REPLACES " + alsoReplaces.joined(separator: ", ")
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
            reason: "Closing a project closes the window this conversation lives in; the "
                + "person closes it with File ▸ Close (⌘W)."),
        AssistantToolRow(
            tool: "transcribe", rule: .withheld, onlyWith: (key: "engine", value: "assemblyai"),
            reason: "Audio leaves the machine only by name, with the price in front of the "
                + "person. Use File ▸ Generate Captions… instead."),
        AssistantToolRow(
            tool: "transcribe_for_fillers", rule: .withheld, onlyWith: nil,
            reason: "Audio leaves the machine only by name, with the price in front of the "
                + "person. Use Clip ▸ Remove Filler Words… instead."),
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
        AssistantToolRow(
            tool: "export_graphic", rule: .askFirst, onlyWith: nil,
            reason: "It writes a .fjgraphic package where the model chose, replacing any file "
                + "already there."),
        AssistantToolRow(
            tool: "new_project_from_range", rule: .askFirst, onlyWith: nil,
            reason: "It writes a project package where the model chose, when the call names a "
                + "path.",
            askOnlyWith: "path", refusesTaken: true),
        AssistantToolRow(
            tool: "make_vertical_version", rule: .askFirst, onlyWith: nil,
            reason: "It writes a project package where the model chose, when the call names a "
                + "path.",
            askOnlyWith: "path", refusesTaken: true),
        AssistantToolRow(
            tool: "new_project", rule: .askFirst, onlyWith: nil,
            reason: "It writes a project package where the model chose, replacing any package "
                + "already there, when the call names a path.",
            askOnlyWith: "path"),
        AssistantToolRow(
            tool: "render_frame", rule: .askFirst, onlyWith: nil,
            reason: "It writes a picture where the model chose, replacing any file already "
                + "there, when the call names a path.",
            askOnlyWith: "path"),
        AssistantToolRow(
            tool: "render_graphic", rule: .askFirst, onlyWith: nil,
            reason: "It writes a contact sheet where the model chose, replacing any file already "
                + "there, when the call names a path.",
            askOnlyWith: "path"),
    ]

    /// The rows whose path is a project package, which another open project
    /// may hold.
    private static let packageTools: Set<String> = [
        "save_project", "new_project", "new_project_from_range", "make_vertical_version",
    ]

    static let devToolReason =
        "a developer tool: Distribution has none, and the assistant sees one catalog in both "
        + "builds."

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
    /// tool, for an ask-first row's call without its `askOnlyWith` argument, and
    /// for a call that can only be refused on its path, which the lane then runs
    /// unasked so the tool's own refusal answers (spec §11 AI-21 (d)). The path
    /// is the file the handler will write, read through the handler's own code
    /// (AI-21 (c)). Main only: it reads the document and the file system.
    static func question(
        tool: String, arguments: [String: Any], document: ProjectDocument
    ) -> AssistantQuestion? {
        assert(Thread.isMainThread)
        guard let entry = row(for: tool), entry.rule == .askFirst else { return nil }
        if let key = entry.askOnlyWith, arguments[key] == nil || arguments[key] is NSNull {
            return nil
        }
        // A `path` `stringArg` refuses: the tool's own refusal answers.
        if let raw = arguments["path"], !(raw is NSNull), !(raw is String) { return nil }
        let server = AgentServer.shared
        let given = (arguments["path"] as? String).map { ($0 as NSString).expandingTildeInPath }
        var alsoReplaces: [String] = []
        let path: String?
        switch tool {
        case "save_project":
            // Never `importSourceURL`: that is the movie, not where a save writes.
            path = given.map(packagePath) ?? document.fileURL?.path
        case "consolidate_media":
            path = document.fileURL.map { "\($0.path)/media" }
        case "export_graphic":
            // Where the tool will write: `.fjgraphic` added as `destinationURL` adds it.
            path = given.map {
                AgentServer.destinationURL($0, extension: GraphicPackage.fileExtension).path
            }
        case "new_project", "new_project_from_range", "make_vertical_version":
            path = given.map(packagePath)
        case "export":
            // The given path when the rest of the call can't be resolved (AI-21 (c)).
            path = (try? server.exportDestination(arguments, on: document))?.path ?? given
        case "export_captions":
            let requested = try? server.requestedFormat(arguments)
            path = given.map {
                AgentServer.captionDestination($0, requested: requested).url.path
            }
        case "render_frame":
            let requested = try? server.requestedFrameFormat(arguments)
            let named = given.map {
                AgentServer.namedFrameDestination($0, requested: requested).url
            }
            path = named?.path
            if let named {
                alsoReplaces = ScopeKind.allCases
                    .filter { (try? server.boolArg(arguments, $0.rawValue)) == true }
                    .map { AgentServer.scopeFile($0, beside: named).path }
                    .filter { FileManager.default.fileExists(atPath: $0) }
            }
        case "render_graphic":
            path = given.map { AgentServer.destinationURL($0, extension: "png").path }
        default:
            path = given
        }
        guard let path else { return nil }
        // The handler's own check, so a path being opened comes with it.
        if packageTools.contains(tool),
            (try? server.refuseHeldPath(
                URL(fileURLWithPath: path), except: tool == "save_project" ? document : nil,
                tool: tool)) == nil
        {
            return nil
        }
        let exists = FileManager.default.fileExists(atPath: path)
        if entry.refusesTaken && exists { return nil }
        return AssistantQuestion(
            tool: tool, path: path, exists: exists, alsoReplaces: alsoReplaces)
    }

    /// Where a project tool writes `path`: `.framejob` added as `destinationURL`
    /// adds it.
    private static func packagePath(_ path: String) -> String {
        AgentServer.destinationURL(path, extension: ProjectDocument.projectFileExtension).path
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
