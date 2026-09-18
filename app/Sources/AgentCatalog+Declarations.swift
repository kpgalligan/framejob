import Foundation

// MARK: - Catalog: what a tool declares that its op does not

/// One place a tool's schema deliberately differs from its op's row in the
/// core's published table (`core/src/op_table.rs`, road map 7's D3).
///
/// The core says what an argument IS and the app says what it is FOR, so a
/// tool that takes a spelling the op has never heard of — or asks for a key
/// the op calls optional — is saying something the table cannot. The rule
/// that decides which side a fact belongs on is the ticket's amendment:
///
/// > **A bound the core REFUSES outside belongs in the op table and is
/// > published. A bound the core merely CLAMPS to, a null that MEANS
/// > something, and a bare-string shorthand are the app's — declared, with
/// > a reason each.**
///
/// Every row carries the op, the argument, what the app adds, and why, and
/// `AgentServer.opTool` emits it, so **an agent can SEE a shorthand rather
/// than discover it**. It takes the shape of `AgentServer.opsWithoutTools`,
/// the "ops that deliberately have no tool" list that has stood empty since
/// it was written: the bar for an entry is high, and an entry is a decision
/// with a reason rather than an accident.
struct AgentDeclaration {

    /// What a row is about.
    ///
    /// The two plural forms exist because the shared argument vocabulary
    /// (`AgentServer+Arguments.swift`) reads a whole CLASS of argument the
    /// same way — every boolean, every clip list — and a row per op would
    /// be the same sentence written twelve times, which is the duplication
    /// this whole candidate is deleting.
    enum Subject {
        /// One op's one argument.
        case argument(String, of: String)
        /// Every argument the core publishes as this JSON type, whatever op
        /// it belongs to.
        case everyArgumentTyped(String)
        /// Every argument with this NAME, whatever op it belongs to.
        case everyArgumentNamed(String)
    }

    /// What a tool says about required-ness where the core's `required`
    /// disagrees. Both directions exist and they are opposite mistakes: a
    /// null that means something must not be reachable by FORGETTING the
    /// key, and a default the app takes from its own state must not be made
    /// compulsory by the core's word.
    enum Requirement {
        /// The core's answer stands, which is every argument but five.
        case theCores
        /// The tool asks for an argument the core calls optional.
        case required
        /// The tool does not ask for one the core requires.
        case optional
    }

    let subject: Subject
    /// JSON types this tool accepts beyond the one the core publishes.
    let alsoTypes: [String]
    let requirement: Requirement
    /// Schema keys this tool adds over the core's fragment.
    let alsoKeys: [String: Any]
    /// Why, in one sentence. It is documentation and not agent-facing
    /// prose: what an agent needs to KNOW is in the tool's own description,
    /// and this is the reason the row is allowed to exist at all.
    let why: String

    init(
        _ subject: Subject, alsoTypes: [String] = [], requirement: Requirement = .theCores,
        alsoKeys: [String: Any] = [:], why: String
    ) {
        self.subject = subject
        self.alsoTypes = alsoTypes
        self.requirement = requirement
        self.alsoKeys = alsoKeys
        self.why = why
    }

    /// Whether this row is about `argument` of `op`, whose published JSON
    /// type is `type`.
    func covers(_ op: String, _ argument: String, type: Any?) -> Bool {
        switch subject {
        case let .argument(name, of: owner): return owner == op && name == argument
        case let .everyArgumentTyped(published): return (type as? String) == published
        case let .everyArgumentNamed(name): return name == argument
        }
    }

    /// The core's fragment for one argument, widened by this row.
    ///
    /// A `null` added to a closed vocabulary is added to its `enum` too:
    /// the members are the whole of what the value may be, so a schema that
    /// says `["string", "null"]` and lists only the names contradicts
    /// itself. That is the one rule here that is not a plain overwrite, and
    /// it exists so the null does not cost the tool the core's member list.
    ///
    /// **`alsoKeys` is a blind merge, and the rule a row must obey is that
    /// it may NARROW what the core published and never relax it** — a
    /// `minimum` tighter than the core's is a truer promise, one looser than
    /// the core's is a false one, and nothing here can tell the two apart.
    /// The one row that uses it today (`set_speed.rate`) narrows a kind the
    /// core published unbounded, which is why the rule is written down
    /// rather than enforced: a guard that silently dropped the key would put
    /// a row in the list that does nothing, which is the trap this file's
    /// one shared predicate exists to avoid.
    func applied(to fragment: [String: Any]) -> [String: Any] {
        var property = fragment
        if !alsoTypes.isEmpty, let core = property["type"] as? String {
            property["type"] = [core] + alsoTypes
            if alsoTypes.contains("null"), let members = property["enum"] as? [Any] {
                property["enum"] = members + [NSNull()]
            }
        }
        for (key, value) in alsoKeys { property[key] = value }
        return property
    }
}

extension AgentServer {

    /// Every declaration, in one list (`AgentDeclaration`'s doc has the rule
    /// an entry has to pass). Eleven rows over five kinds of difference: two
    /// bare-string shorthands, one reading of a whole JSON kind, two nulls
    /// that mean something, one range the core clamps to rather than
    /// refusing, three times the tool takes from the app what the op would
    /// have made the caller send, and twice a list the tool will not accept
    /// empty although the op reads one.
    ///
    /// **What is deliberately NOT here.** The argument vocabulary is lenient
    /// in ways no tool has ever declared — a lone id read as a one-element
    /// list, an id spelled as a string, a bare `[from, to]` read as one
    /// range — and this ticket declared none of them, because it changed
    /// none of them. The direction is what makes that safe: a schema
    /// narrower than what is accepted costs a caller nothing, where one
    /// wider than what is accepted is a promise the app breaks. Each of
    /// those is a row this list can gain the day someone decides the
    /// shorthand is worth offering.
    static let declarations: [AgentDeclaration] = [

        // ---- a bare string where the op takes a patch --------------------

        AgentDeclaration(
            .argument("text", of: "add_text_clip"), alsoTypes: ["string"],
            why: "The op takes a set_text PATCH; a bare string is the words, expanded to "
                + "{\"content\": …} by AgentServer+Clips.swift's newClipPatchArg before the "
                + "core ever sees it. It cannot be ambiguous — a JSON string is never a JSON "
                + "object — and a string is what this tool declared for most of its life, so "
                + "no caller written against it has to be rewritten."),
        AgentDeclaration(
            .argument("shape", of: "add_shape_clip"), alsoTypes: ["string"],
            why: "The same reader and the same reason as add_text_clip's text: a bare string "
                + "is the geometry, expanded to {\"kind\": …}, where the op takes a set_shape "
                + "patch."),

        // ---- a whole kind the argument vocabulary reads more of -----------

        AgentDeclaration(
            .everyArgumentTyped("boolean"), alsoTypes: ["string"],
            why: "boolArg (AgentServer+Arguments.swift) reads \"true\", \"1\", \"false\" and "
                + "\"0\" as well as a JSON boolean, for every boolean argument of every op, "
                + "which is why this row names a KIND rather than an argument. A number also "
                + "answers there, through NSNumber bridging rather than through a spelling "
                + "the vocabulary chose, and is deliberately not declared: the schema may be "
                + "narrower than what is accepted, never wider than what is."),

        // ---- a null that MEANS something ----------------------------------

        AgentDeclaration(
            .argument("kind", of: "set_transition"), alsoTypes: ["null"], requirement: .required,
            why: "null CLEARS the transition, and the op cannot tell an absent kind from a "
                + "null one — an optional argument absent and an explicit null are one thing "
                + "to the envelope (core/src/edit.rs). So the tool declares the null AND asks "
                + "for the key, which is the one place the difference can be made: a "
                + "forgotten kind would otherwise silently remove a transition. The handler "
                + "refuses the omission by name."),
        AgentDeclaration(
            .argument("region", of: "add_zoom_action"), alsoTypes: ["null"],
            requirement: .required,
            why: "null is a zoom BACK to the clip's own scale and position, and the op reads "
                + "an absent region the same way, so a forgotten rectangle would become the "
                + "opposite edit. Declared nullable and required for that one reason; "
                + "zoomRegionArg refuses the omission by name and says what to send."),

        // ---- a range the core clamps to rather than refusing --------------

        AgentDeclaration(
            .argument("rate", of: "set_speed"), alsoKeys: ["minimum": 0.1, "maximum": 10],
            why: "The core CLAMPS a rate into 0.1–10 rather than refusing outside it "
                + "(core/src/edit_clip.rs), so the range is not a rule the table may publish "
                + "and it is guidance the tool gives instead. What the core does refuse is a "
                + "non-positive or non-finite rate, which no JSON-Schema bound this table "
                + "carries can say; the handler refuses it by name first."),

        // ---- a list the tool will not take empty ---------------------------

        AgentDeclaration(
            .everyArgumentNamed("clips"), alsoKeys: ["minItems": 1],
            why: "optionalClipsArg refuses an empty list by name — \"clips is empty — name at "
                + "least one clip\" — for every op that takes one, where the core would read "
                + "it as an identity. An op over no clips is a mistake in the asking rather "
                + "than an edit that changed nothing, which is a check about the CALL and so "
                + "the app's to make (app/CLAUDE.md, spec §11's D2-1)."),
        AgentDeclaration(
            .argument("groups", of: "paste_attributes"), alsoKeys: ["minItems": 1],
            why: "The handler refuses an empty list by name and says which four to choose "
                + "from. Leaving `groups` out already means every group both clips have, so "
                + "an empty list cannot be a way of saying \"none\" and is a mistake."),

        // ---- a default the app takes from its own state --------------------

        AgentDeclaration(
            .argument("at", of: "split"), requirement: .optional,
            why: "The op requires a time; the TOOL takes the playhead when the call leaves it "
                + "out, exactly as ⌘K does with nothing typed. The playhead is app state, "
                + "which the core has not got, so an argument the core calls required is one "
                + "an agent may omit here."),
        AgentDeclaration(
            .argument("at", of: "paste"), requirement: .optional,
            why: "The playhead again, for ⌘V: split's reason, at the other end of the "
                + "clipboard."),
        AgentDeclaration(
            .argument("at", of: "freeze_frame"), requirement: .optional,
            why: "The playhead again, for ⇧⌘F: the moment to freeze defaults to where the "
                + "window is looking."),
    ]

    /// One op tool's declared input: the core's published structure, each
    /// argument's prose, and this op's rows from `declarations`.
    ///
    /// The three sources meet HERE and nowhere else, which is what makes
    /// `opTool` a printing of the table rather than a copy of it. An
    /// argument with no prose is emitted with the core's structure and no
    /// description — the fifth part of the startup parity check is what
    /// turns that into a complaint, and it is a later ticket's.
    static func declaredInput(
        of op: String, _ published: ReelOpSchema, _ prose: [String: String]
    ) -> (properties: [String: Any], required: [String]) {
        // ONE question, asked the same way everywhere below: which rows are
        // about this argument? The published TYPE is part of the question,
        // since a row may name a KIND, and it is read from the CORE's own
        // fragment rather than from a fragment another row has already
        // widened — so the answer does not depend on the order the rows are
        // applied in, and a `.required` row on a kind or a name cannot be
        // silently inert the way a `.argument`-only reading left it.
        func rows(about argument: String) -> [AgentDeclaration] {
            let fragment = published.properties[argument] as? [String: Any]
            return declarations.filter { $0.covers(op, argument, type: fragment?["type"]) }
        }
        var properties: [String: Any] = [:]
        for (argument, fragment) in published.properties {
            var property = fragment as? [String: Any] ?? [:]
            for declaration in rows(about: argument) {
                property = declaration.applied(to: property)
            }
            if let sentence = prose[argument] { property["description"] = sentence }
            properties[argument] = property
        }
        // The core's own order, less what a row calls optional, plus what a
        // row asks for — so a tool's required list stays the table's reading
        // wherever nothing declares otherwise. The additions are read in
        // ARGUMENT order and not in list order, because `properties` is a
        // dictionary and a tool's required list may not vary per process.
        var required = published.required.filter { argument in
            !rows(about: argument).contains { $0.requirement == .optional }
        }
        for argument in properties.keys.sorted() where !required.contains(argument) {
            guard rows(about: argument).contains(where: { $0.requirement == .required })
            else { continue }
            required.append(argument)
        }
        return (properties, required)
    }
}
