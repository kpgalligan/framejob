import Foundation

// MARK: - The argument gate: a call's keys against the tool's published schema

/// One comparison at dispatch, for all ninety-one tools: the keys a
/// caller wrote against the properties the tool PUBLISHED, and every
/// stranger refused by name before a handler reads a thing
/// (kpgalligan/reelcut#21; the measurement behind it is
/// `archive/roadmap-7.md` §11).
///
/// **The defect it closes.** No handler enumerates a caller's keys. Each
/// reads the names it knows out of the dictionary and builds a fresh op, so
/// a key nothing reads collides with nothing: a misspelt OPTIONAL argument
/// was dropped in silence and the edit applied without it, an argument no
/// op takes was ignored, and a misspelt REQUIRED argument was reported as
/// the right name missing rather than as the wrong one written. The core's
/// decoder would refuse every one of them by name (`Op` is
/// `deny_unknown_fields`) and never got the chance, because an op ARGUMENT
/// never reaches it — the app rebuilds the op first.
///
/// **Why a gate and not a forward.** Handing a caller's op to the core
/// unread would buy the same refusal and give up twenty-one the app makes on
/// its own account, six app-state defaults, eleven per-op transforms and one
/// correctness guard (§11.2). The gate keeps every one of them: it runs
/// before the handler and reads nothing but names.
///
/// **What it reads.** The catalog string `prepareCatalog()` built at launch
/// (spec §11 AI-3) — the same bytes `start()` registers with the server and a
/// caller sees over `tools/list` — parsed once into
/// each tool's property names. The startup parity check's five parts already
/// say that catalog is exactly the dispatch table, that every op tool prints
/// the core's own arguments and that `project` and `scope` are on the tools
/// they belong to (`AgentServer+Parity.swift`), so the set compared against
/// here is the one those five vouch for. It is state for
/// `proseWithoutArgument`'s reason: written once, by `prepareCatalog()` from
/// `main.swift` at launch, before any other thread exists, and only read
/// after — on the main thread and, for the `offMainTools`, on the lane's
/// caller's thread, which is safe because nothing writes it again.
///
/// **What it speaks.** The APP's sentence — the tool, the strangers and the
/// whole of what the tool does take — rather than the core's serde wording:
/// thirty tools have no core sentence to borrow, and `AgentIdScope.noSuchId`
/// set the house style ("No clip has id 17. get_project lists the clips.").
///
/// **What it cannot see.** A DECLARED argument no handler reads: the name
/// passes here and the handler ignores it, which is the class only a row
/// calling the running tool can catch — the optional half of section 3 in
/// `tools/proof/op_argument_proof.py`, which reads what the op DID. And a
/// value of the wrong TYPE under the right name, which is the argument
/// vocabulary's (`AgentServer+Arguments.swift`), one reader at a time.
///
/// A file of its own because `AgentServer.swift` is frozen at wiring
/// (app/CLAUDE.md) and this is neither a reader nor a startup check.
extension AgentServer {

    /// Every tool's published property names, keyed by tool, from the
    /// catalog `prepareCatalog()` built.
    private(set) static var publishedArguments: [String: Set<String>] = [:]

    /// Reads `catalog` — the string `catalogJSON()` answered, which
    /// `prepareCatalog()` memoises and `bindSocket()` hands to
    /// `ReelAgentSocket.start` — into `publishedArguments`. A
    /// tool the catalog does not describe, or describes with no properties,
    /// takes NOTHING: the parity check has already complained about that
    /// catalog, and a gate that waved a call through for want of a schema
    /// would be the silence this file exists to end.
    static func noteArguments(in catalog: String) {
        var names: [String: Set<String>] = [:]
        let tools =
            (try? JSONSerialization.jsonObject(with: Data(catalog.utf8))) as? [[String: Any]]
            ?? []
        for tool in tools {
            guard let name = tool["name"] as? String else { continue }
            let properties =
                ((tool["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
            names[name] = Set(properties.keys)
        }
        publishedArguments = names
    }

    /// The gate. Nothing when every key of `a` is one `tool` published;
    /// otherwise a `ToolError` naming the tool, the strangers and the whole
    /// of what the tool takes — its own arguments first, then the
    /// envelope's, so `trim_start`'s reads "clip, to, project and scope"
    /// rather than putting `to` after `scope`. A stranger whose value is
    /// null is still a stranger: the readers treat null as absent for a
    /// VALUE, and this is about a NAME the tool never published.
    static func checkArgumentNames(_ tool: String, _ a: [String: Any]) throws {
        let published = publishedArguments[tool] ?? []
        let strangers = a.keys.filter { !published.contains($0) }.sorted()
        guard !strangers.isEmpty else { return }
        let own = published.subtracting(envelopeKeys).sorted()
        let envelope = envelopeKeys.filter(published.contains)
        throw ToolError(
            message: "\(tool) does not take \(list(strangers)). It takes \(list(own + envelope)).")
    }

    /// "a", "a and b", "a, b and c".
    private static func list(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "nothing" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
