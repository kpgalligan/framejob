import AppKit

/// Reading `video.motion` out of a `set_video` patch (format version 8, road
/// map 5's E2).
///
/// **The UI path this mirrors** is the Clip tab's Motion section
/// (`VideoPane+Motion.swift`) and Clip ▸ Motion ▸ In / Out / During, both of
/// which send the WHOLE `MotionProps` on every row, nil slots as `null`.
/// This argument does the same, and the rule lives at these two edges and
/// deliberately NOT in the core: a raw core patch DEEP-MERGES `motion`
/// (`merge_group` → `actions::merge`), so `{"motion": {"in": …}}` sent to
/// the op keeps a stored `out`, which is what makes a hand-written patch
/// able to change one slot at a time.
///
/// **Why it is hand-built.** `patchArg`'s round trip (`AgentServer+Arguments
/// .swift`) decodes a patch, re-encodes it and compares, which cannot see
/// inside a nested object — one level down every field has a real default,
/// so a value that decoded TO that default is indistinguishable from an
/// absent one. A motion has TWO levels of nested objects, so going through
/// the generic decoder would mean `{"in": {"durration": 1}}` silently
/// becoming a half-second fade and the caller told it worked, which is what
/// `shadow`, `chroma`, `obscure` and `animation` all still do. `gradientArg`
/// is the precedent for the other posture and this follows it: a misspelt
/// key at EVERY level, a kind outside either vocabulary and a wrong type are
/// all refused by name. `setVideo` strips `"motion"` out of the dictionary
/// before `patchArg` runs, so the two readers never see each other's key.
///
/// What is NOT decided here is the RANGE of anything: `in.duration` and
/// `out.duration` being non-negative, `during.amount` sitting in 0–1 and
/// `during.period` being at least one tick are `props_check.rs`'s, and its
/// messages name the field the same way these do. The two tick values ARE
/// snapped here, through `optionalTimeArg` — the rule for every tick that
/// reaches an op (spec §6), and the reason this reader takes the targeted
/// `ProjectDocument`: the grid a duration lands on is the project's, and a
/// second spelling of the snap is exactly the drift
/// `AgentServer+Arguments.swift` exists to prevent. The core deliberately
/// does not snap a preset's durations itself (`props_check.rs`,
/// `text.animation`'s precedent), so this reader and the inspector are
/// where it happens.
extension AgentServer {

    /// `null` clears the whole field; an object REPLACES it, a slot left out
    /// or written `null` meaning that slot is empty. Absent leaves it alone.
    func motionPatchArg(
        _ object: [String: Any], _ key: String, _ document: ProjectDocument
    ) throws -> MotionProps?? {
        guard let raw = object[key] else { return nil }
        if raw is NSNull { return .some(nil) }
        guard let motion = raw as? [String: Any] else {
            throw ToolError(
                message: "\(key) must be null or {\"in\": {\"kind\": \"slide_up\", "
                    + "\"duration\": 300000}, \"out\": …, \"during\": {\"kind\": \"pulse\", "
                    + "\"amount\": 0.5, \"period\": 600000}} — any slot may be null.")
        }
        let allowed: Set<String> = ["in", "out", "during"]
        if let first = motion.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw ToolError(
                message: "Unknown \(key) key \"\(first)\" — allowed keys are "
                    + allowed.sorted().joined(separator: ", ") + ".")
        }
        return .some(
            MotionProps(
                inEdge: try edgeArg(motion, "in", key, document),
                out: try edgeArg(motion, "out", key, document),
                during: try duringArg(motion, "during", key, document)))
    }

    /// One edge slot. Absent OR `null` is an empty slot — the handler
    /// replaces the whole object, so there is no third state to carry.
    private func edgeArg(
        _ motion: [String: Any], _ slot: String, _ key: String, _ document: ProjectDocument
    ) throws -> MotionEdge? {
        guard let raw = motion[slot], !(raw is NSNull) else { return nil }
        let path = "\(key).\(slot)"
        guard let edge = raw as? [String: Any] else {
            throw ToolError(
                message: "\(path) must be null or {\"kind\": \"slide_up\", "
                    + "\"duration\": 300000}.")
        }
        let allowed: Set<String> = ["kind", "duration"]
        if let first = edge.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw ToolError(
                message: "Unknown \(path) key \"\(first)\" — allowed keys are "
                    + allowed.sorted().joined(separator: ", ") + ".")
        }
        // Every key defaults, the way the core's `#[serde(default)]` on the
        // container makes them default, so `{"in": {}}` means here exactly
        // what it means in a hand-written op: half a second of fade.
        let fallback = MotionEdge()
        var kind = fallback.kind
        if let name = try stringArg(edge, "kind") {
            guard let read = EdgeMotion(rawValue: name) else {
                throw ToolError(
                    message: "\(path).kind must be one of "
                        + EdgeMotion.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + " (got \"\(name)\").")
            }
            kind = read
        }
        let duration = try optionalTimeArg(renamed(edge, "duration", "\(path).duration"),
                                           "\(path).duration", document)
        return MotionEdge(kind: kind, duration: duration ?? fallback.duration)
    }

    /// The continuous slot, on `edgeArg`'s terms.
    private func duringArg(
        _ motion: [String: Any], _ slot: String, _ key: String, _ document: ProjectDocument
    ) throws -> MotionDuring? {
        guard let raw = motion[slot], !(raw is NSNull) else { return nil }
        let path = "\(key).\(slot)"
        guard let during = raw as? [String: Any] else {
            throw ToolError(
                message: "\(path) must be null or {\"kind\": \"pulse\", \"amount\": 0.5, "
                    + "\"period\": 600000}.")
        }
        let allowed: Set<String> = ["kind", "amount", "period"]
        if let first = during.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw ToolError(
                message: "Unknown \(path) key \"\(first)\" — allowed keys are "
                    + allowed.sorted().joined(separator: ", ") + ".")
        }
        let fallback = MotionDuring()
        var kind = fallback.kind
        if let name = try stringArg(during, "kind") {
            guard let read = DuringMotion(rawValue: name) else {
                throw ToolError(
                    message: "\(path).kind must be one of "
                        + DuringMotion.allCases.map { $0.rawValue }.joined(separator: ", ")
                        + " (got \"\(name)\").")
            }
            kind = read
        }
        let period = try optionalTimeArg(renamed(during, "period", "\(path).period"),
                                         "\(path).period", document)
        return MotionDuring(
            kind: kind,
            amount: try doubleArg(during, "amount") ?? fallback.amount,
            period: period ?? fallback.period)
    }

    /// One value of `object` re-keyed by its DOTTED path, so
    /// `optionalTimeArg` — which names a key in its refusal — names
    /// `motion.in.duration` rather than a bare `duration`.
    ///
    /// Six lines rather than a second tick reader: the snap is spec §6's
    /// rule for every tick that reaches an op, and a reader with its own
    /// copy of it is the drift `AgentServer+Arguments.swift` exists to
    /// prevent. A negative duration is passed THROUGH to the core, whose
    /// `props_check.rs` names the field — this reader's job is the type and
    /// the grid, never the range.
    private func renamed(
        _ object: [String: Any], _ key: String, _ path: String
    ) -> [String: Any] {
        guard let raw = object[key] else { return [:] }
        return [path: raw]
    }
}
