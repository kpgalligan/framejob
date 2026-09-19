import Foundation

// MARK: - The startup parity check's fifth part

/// Part 5 of `AgentServer.catalogParityFailure`: every op tool declares the
/// core's own arguments, and says what each one is FOR.
///
/// **What the first four cannot see.** Every one of them compares NAME SETS
/// — the catalog against the dispatch table, the core's op list against the
/// catalog, each schema's shape, the `scope` on every op tool — so not one
/// of them ever compares an op tool's `properties` to the core's row: part 3
/// reads a schema's shape and part 4 asks whether one key is in it, and
/// neither asks WHICH arguments are there. Road map 7's D3 is what makes
/// this part possible at all: until every op tool PRINTED the
/// core's published table (`AgentCatalog.opTool` over `rc_op_schemas`) each
/// tool's arguments were hand-written and there was no second spelling to
/// compare them against.
///
/// **Three ways an op tool can still be wrong, and each is a complaint.**
///
/// 1. It declares arguments that are not the core's — a hand-written
///    `tool(…)` schema that came back for an op, or an
///    `AgentServer.declarations` row naming an argument the table has
///    dropped. The comparison runs in BOTH directions, so an argument the
///    core has that the tool does not offer and an argument the tool offers
///    that no op has are both named, with the op, the argument and the side
///    that has it.
/// 2. It describes an argument it does not take. `AgentCatalog.opTool`
///    walks the CORE's published properties and hands each one its sentence,
///    so a prose key the table has never heard of reaches nothing and the
///    description is dropped in silence — the gap D3·3's review named and
///    left to this part. Nothing in the built catalog remembers it, which is
///    why `noteProse` below is state rather than a second read of the JSON.
/// 3. It declares an argument with no description at all. **The core says
///    what an argument IS and the app says what it is FOR**, so an argument
///    nobody wrote a sentence for reaches an agent as a bare type — spec
///    kpgalligan/reelcut#14's second user story, and the complaint
///    `AgentCatalog.declaredInput` promised this part would make.
///
/// **What it still cannot see, and the instrument that can.** It reads the
/// same table the catalog reads, so a constraint the app still ENFORCES that
/// the TABLE stops declaring moves both sides of this comparison together
/// and passes here. Twice in D3 exactly that happened
/// (`designs/reelcut-roadmap-7.md` §8.3 and §8.4). What catches that class is
/// a row that calls the RUNNING tool and reads its answer: the misspelt
/// argument sent to all fifty-seven ops in
/// `tools/proof/op_argument_proof.py`, and the behavioural sections of the
/// two catalog proofs.
///
/// **It is a file of its own** because `AgentServer.swift` is frozen at its
/// size (app/CLAUDE.md) and this is the longest of the five parts — part 4
/// is `AgentServer+Scope.swift`'s for the feature it is about, and parts 1
/// to 3 stay beside the private dispatch table they read. Its reporting is
/// identical to all four: an assertion in debug, a `Reelcut: ` line in
/// release, and the server starts either way.
extension AgentServer {

    /// The two keys `AgentCatalog.tool` injects — `project` into every
    /// tool's schema, `scope` into every op tool's. They belong to the
    /// envelope rather than to the op (spec §6), so the core's table has
    /// never heard of either and neither is compared here. In this order
    /// because the gate (`AgentServer+Gate.swift`) lists them last, after a
    /// tool's own arguments, in its refusal.
    static let envelopeKeys: [String] = ["project", "scope"]

    /// Prose `AgentCatalog.opTool` was handed for arguments the core's table
    /// has not got, keyed by op.
    ///
    /// It is collected while the catalog is BUILT because that is the only
    /// moment the evidence exists: `declaredInput` walks the core's
    /// published properties, so a sentence whose key is not one of them is
    /// attached to nothing and the built catalog remembers nothing about it.
    /// Written once per op tool by `noteProse` and read once by
    /// `argumentFailure`, both inside `AgentServer.start()`'s single catalog
    /// build on the main thread. Keyed by op rather than appended to, so a
    /// second build answers what the second catalog says rather than what
    /// both said.
    ///
    /// **The order is a data dependency, not a convention**, which is what
    /// makes this state safe where a global usually is not: the check takes
    /// the catalog STRING `catalogJSON()` returned, so a caller cannot ask
    /// the question without having built the catalog that answers it. The one
    /// residue is an op that stopped being an op tool between two builds in
    /// one process, whose entry would linger — and parts 1 and 2 complain
    /// about that tool first, because a tool with no op and an op with no
    /// tool are theirs.
    private(set) static var proseWithoutArgument: [String: [String]] = [:]

    /// `AgentCatalog.opTool` says which sentences it was given for which op,
    /// and this keeps the ones the merge could not use.
    static func noteProse(
        _ prose: [String: String], of op: String, against published: ReelOpSchema
    ) {
        let orphans = prose.keys.filter { published.properties[$0] == nil }.sorted()
        if orphans.isEmpty {
            proseWithoutArgument.removeValue(forKey: op)
        } else {
            proseWithoutArgument[op] = orphans
        }
    }

    /// The fifth part itself. `tools` is the parsed catalog and `ops` the
    /// core's own op list, exactly as parts 2 and 4 take them; a tool the
    /// core calls no op is skipped by the same rule part 4 uses, because an
    /// app-state tool has no row to be compared to.
    ///
    /// The three complaints are reported one kind at a time, each naming
    /// EVERY offender, which is how parts 1, 2 and 4 report: a maintainer
    /// who has renamed an argument wants the whole list, not the first of
    /// twelve.
    static func argumentFailure(_ tools: [[String: Any]], _ ops: Set<String>) -> String? {
        var wrong: [String] = []
        var silent: [String] = []
        for tool in tools {
            guard let name = tool["name"] as? String, ops.contains(name) else { continue }
            let properties =
                ((tool["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
            let declared = Set(properties.keys).subtracting(envelopeKeys)
            let expected = expectedArguments(of: name)
            if declared != expected {
                var sides: [String] = []
                let extra = declared.subtracting(expected).sorted()
                let absent = expected.subtracting(declared).sorted()
                if !extra.isEmpty {
                    sides.append("declared by the tool and in neither the table nor the "
                        + "declarations: \(extra)")
                }
                if !absent.isEmpty {
                    sides.append("in the table or a declarations row and not declared by the "
                        + "tool: \(absent)")
                }
                wrong.append("\(name) — " + sides.joined(separator: ", "))
            }
            let undescribed = properties.keys.filter { key in
                !envelopeKeys.contains(key)
                    && (properties[key] as? [String: Any])?["description"] == nil
            }.sorted()
            if !undescribed.isEmpty { silent.append("\(name) — \(undescribed)") }
        }
        if !wrong.isEmpty {
            return "these op tools do not declare the core's own arguments: "
                + wrong.joined(separator: "; ")
                + " — every op tool prints core/src/op_table.rs through AgentCatalog.opTool, so "
                + "a difference is a hand-written schema that came back, or an "
                + "AgentServer.declarations row naming an argument the core no longer has"
        }
        let orphans = proseWithoutArgument.sorted { $0.key < $1.key }
            .map { "\($0.key) — \($0.value)" }
        if !orphans.isEmpty {
            return "these op tools carry a description for an argument they do not take: "
                + orphans.joined(separator: "; ")
                + " — AgentCatalog.opTool gives each sentence to the argument of the same name "
                + "and drops one that names nothing, so that prose never reaches an agent; it "
                + "is a misspelling or an argument the core has renamed"
        }
        if !silent.isEmpty {
            return "these op tool arguments reach an agent with no description: "
                + silent.joined(separator: "; ")
                + " — the core says what an argument IS and the catalog says what it is FOR, so "
                + "an argument added to the table arrives here until somebody writes its "
                + "sentence (AgentCatalog.opTool's prose map)"
        }
        return nil
    }

    /// Every argument the tool for `op` may declare: the core's published
    /// row, plus any argument `AgentServer.declarations` names for that op.
    ///
    /// The union is the core's row exactly today — all fourteen rows name an
    /// argument the table publishes, or a KIND, or a NAME — and it is
    /// written as a union anyway because the declarations list is where a
    /// deliberate difference belongs. A row naming an argument the core has
    /// NOT got is the case worth having: `declaredInput` emits nothing for
    /// it, so the tool cannot declare it, and this part says the row is
    /// stale — the staleness check `opsWithoutTools` has, at startup rather
    /// than in a proof script.
    private static func expectedArguments(of op: String) -> Set<String> {
        var names = Set((opSchemas[op]?.properties ?? [:]).keys)
        for declaration in declarations {
            if case let .argument(argument, of: owner) = declaration.subject, owner == op {
                names.insert(argument)
            }
        }
        return names
    }
}
