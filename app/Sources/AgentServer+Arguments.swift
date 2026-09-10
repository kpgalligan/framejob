import AppKit

/// The shared argument vocabulary every agent handler reads its call with:
/// the scalar coercions Rasterize's `AgentServer` carries, plus Reelcut's own
/// id lookups (which validate against the snapshot so a wrong id is a message
/// naming the tool that lists the right ones), the tick rule, and the patch
/// decoders.
///
/// It lives beside `AgentServer.swift` rather than inside it because that file
/// is frozen at wiring (app/CLAUDE.md) and this is the piece every
/// `AgentServer+<Area>` handler builds on.
///
/// **Since road map 2's phase 9 the id lookups answer about a CONTAINER**,
/// not about the timeline: the call's `scope` decides, and `idScope`
/// (`AgentServer+Scope.swift`) is what they ask. The change is entirely
/// inside their bodies — every one of them already took `_ document:
/// ProjectDocument`, so not one of the sixty call sites moved, and there is
/// no half-converted state in which some ops can name a nested clip and
/// others cannot. `scopeArg` below is the envelope key itself; `timeArg`,
/// `optionalTimeArg`, `snappedTick` and `rangesArg` need nothing at all,
/// because they snap against `canvas.fps` and a view keeps the document's
/// rate (`core/src/scope.rs`: there is only one frame grid).
extension AgentServer {
    /// The shared body of the four scalar readers: nil when `key` is absent
    /// or null, the value when `read` recognises it, and a `ToolError`
    /// naming the key and the type it wanted when it does not.
    ///
    /// **Why they throw.** nil out of these means "absent" and nothing else.
    /// A reader that also answered nil for a present-but-wrong-typed value
    /// would make `boolArg(a, "muted") ?? false` and
    /// `stringArg(a, "text")` indistinguishable from the omitted case, so a
    /// mistyped argument would be dropped in silence and the model would
    /// believe an edit it never made — exactly the failure `patchArg` below
    /// refuses an unknown key BY NAME to avoid, and exactly how
    /// `add_text_clip`'s `text` came to swallow the object its own op
    /// documents. An argument of the wrong type is a caller bug and is
    /// reported like one.
    ///
    /// **What is still coerced.** A string spelling of a number or a flag
    /// (`"30"`, `"true"`) is a JSON-typing slip, not a semantic one, and
    /// every one of them is unambiguous, so those keep working. `"yes"`,
    /// `[]` and `{}` are not among them and are now errors.
    private func scalarArg<T>(
        _ a: [String: Any], _ key: String, _ expected: String, _ read: (Any) -> T?
    ) throws -> T? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        guard let value = read(raw) else {
            throw ToolError(message: "\(key) must be \(expected).")
        }
        return value
    }

    func intArg(_ a: [String: Any], _ key: String) throws -> Int? {
        try scalarArg(a, key, "a whole number") { raw in
            Self.numeric(raw)?.intValue ?? (raw as? String).flatMap(Int.init)
        }
    }

    func doubleArg(_ a: [String: Any], _ key: String) throws -> Double? {
        try scalarArg(a, key, "a number") { raw in
            Self.numeric(raw)?.doubleValue ?? (raw as? String).flatMap(Double.init)
        }
    }

    /// `raw` as a number, or nil for a JSON boolean. `JSONSerialization`
    /// hands `true` over as an `NSNumber` too, and reading it as 1 would
    /// let `video_bitrate: true` reach the core as one bit per second — a
    /// wrong-typed value taken silently, which is the failure every reader
    /// here exists to refuse. Only the type id tells the two apart.
    private static func numeric(_ raw: Any) -> NSNumber? {
        guard let number = raw as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return number
    }

    func boolArg(_ a: [String: Any], _ key: String) throws -> Bool? {
        try scalarArg(a, key, "true or false") { raw in
            if let number = raw as? NSNumber { return number.boolValue }
            switch raw as? String {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
    }

    func stringArg(_ a: [String: Any], _ key: String) throws -> String? {
        try scalarArg(a, key, "a string") { $0 as? String }
    }

    /// A required, non-empty string. A present value of the wrong type is
    /// `stringArg`'s error, which names the type, rather than this one's —
    /// "Missing required argument: shape" for a shape that was passed as an
    /// object is a true statement about the wrong thing.
    func requiredString(_ a: [String: Any], _ key: String) throws -> String {
        guard let value = try stringArg(a, key), !value.isEmpty else {
            throw ToolError(message: "Missing required argument: \(key)")
        }
        return value
    }

    /// A list of strings (`paste_attributes`'s `groups`), or nil when `key`
    /// is absent or null. A lone string is taken as a one-element list — the
    /// courtesy `clipsArg` extends to a lone id, for the same reason — and an
    /// element of any other type is an error naming the key, under the same
    /// rule as the scalar readers above. What the strings may SAY, and
    /// whether an empty list is a mistake, are the caller's to decide: an
    /// empty list means different things to different ops.
    func stringsArg(_ a: [String: Any], _ key: String) throws -> [String]? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        if let one = raw as? String { return [one] }
        guard let array = raw as? [Any] else {
            throw ToolError(message: "\(key) must be an array of strings.")
        }
        var values: [String] = []
        for value in array {
            guard let string = value as? String else {
                throw ToolError(message: "\(key) must contain strings only.")
            }
            values.append(string)
        }
        return values
    }

    /// The envelope's `scope` (spec §6, `core/src/scope.rs`): a nest id, or
    /// nil for absent and for an explicit null, which the envelope reads the
    /// same way.
    ///
    /// It is `scope::read`'s Swift twin and answers in the core's own words,
    /// deliberately. A negative number, a fraction, a numeric STRING and a
    /// bool all land in the refusal — where `intArg` would take the string
    /// and the bool — because a scope decides which CONTAINER an edit lands
    /// in, and guessing at one is the last thing to do. Read once per call,
    /// by `AgentServer.dispatch`, and only for a tool whose schema declares
    /// it.
    func scopeArg(_ a: [String: Any]) throws -> UInt32? {
        guard let raw = a["scope"], !(raw is NSNull) else { return nil }
        guard let number = Self.numeric(raw), number.doubleValue >= 0,
            number.doubleValue <= Double(UInt32.max),
            number.doubleValue == number.doubleValue.rounded()
        else {
            throw ToolError(message: "scope must be a nest id, not \(Self.describe(raw))")
        }
        return UInt32(number.doubleValue)
    }

    /// A value as short text for a message — `describe` in
    /// `core/src/export_overrides.rs`, in Swift, truncated for its reason: a
    /// caller who passed a whole object where an id belongs must not turn the
    /// refusal into a megabyte.
    ///
    /// A JSON boolean is spelled out, and that is not cosmetic: `true`
    /// arrives as an `NSNumber` (which is why `numeric` above exists at all),
    /// and `String(describing:)` renders it "1" — so "scope must be a nest
    /// id, not 1" would be the answer to `scope: true`, naming a value that
    /// IS a plausible id and hiding the mistake that was made.
    static func describe(_ raw: Any) -> String {
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        let text = (raw as? String).map { "\"\($0)\"" } ?? String(describing: raw)
        return text.count <= 40 ? text : String(text.prefix(40)) + " …"
    }

    /// An id argument. Ids are unique across kinds in one project (spec §5.2),
    /// so this only checks the range; the lookups below check existence.
    func idArg(_ a: [String: Any], _ key: String) throws -> UInt32 {
        guard let value = try intArg(a, key) else {
            throw ToolError(message: "Missing required argument: \(key) (an id)")
        }
        guard value >= 0, value <= Int(UInt32.max) else {
            throw ToolError(message: "\(key) is not an id: \(value)")
        }
        return UInt32(value)
    }

    /// A clip id, checked against the container the call is editing.
    ///
    /// **The container is the phase-9 change and it is entirely in the
    /// BODY**: `idScope` answers the timeline's clips, or — inside a
    /// `scope` — the nest's own (`AgentServer+Scope.swift`), so all sixty
    /// call sites of the six id readers were untouched and cannot be
    /// half-converted. Without it a `trim_start {clip: <inside the nest>,
    /// scope: 4}` was refused by the APP, with "No clip has id 17", before
    /// the core ever saw the scope.
    func clipArg(
        _ a: [String: Any], _ key: String = "clip", _ document: ProjectDocument
    ) throws -> ClipSnapshot {
        let id = try idArg(a, key)
        let scope = try idScope(document)
        guard let clip = scope.clip(id) else {
            throw ToolError(message: scope.noSuchId("clip", id))
        }
        return clip
    }

    /// A list of clip ids, every one checked against the snapshot. Also
    /// accepts a single number, because "clips: 17" is the mistake a model
    /// makes most and refusing it teaches nothing.
    func clipsArg(
        _ a: [String: Any], _ key: String = "clips", _ document: ProjectDocument
    ) throws -> [UInt32] {
        guard let ids = try optionalClipsArg(a, key, document) else {
            throw ToolError(message: "Missing required argument: \(key) (an array of clip ids)")
        }
        return ids
    }

    /// `clipsArg` for an op whose clip list is optional (`split`). nil when
    /// the key is absent; a present-but-empty list is an error, since an op
    /// over no clips is a mistake, not a no-op.
    func optionalClipsArg(
        _ a: [String: Any], _ key: String = "clips", _ document: ProjectDocument
    ) throws -> [UInt32]? {
        let raw: [Any]
        if let array = a[key] as? [Any] {
            raw = array
        } else if a[key] != nil, !(a[key] is NSNull) {
            raw = [a[key] ?? NSNull()]
        } else {
            return nil
        }
        guard !raw.isEmpty else {
            throw ToolError(message: "\(key) is empty — name at least one clip.")
        }
        let scope = try idScope(document)
        var ids: [UInt32] = []
        for value in raw {
            guard let number = (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init),
                number >= 0, number <= Int(UInt32.max)
            else {
                throw ToolError(message: "\(key) must contain clip ids (integers).")
            }
            let id = UInt32(number)
            guard scope.clip(id) != nil else {
                throw ToolError(message: scope.noSuchId("clip", id))
            }
            ids.append(id)
        }
        return ids
    }

    func trackArg(
        _ a: [String: Any], _ key: String = "track", _ document: ProjectDocument
    ) throws -> TrackSnapshot {
        let id = try idArg(a, key)
        let scope = try idScope(document)
        guard let track = scope.track(id) else {
            throw ToolError(message: scope.noSuchId("track", id))
        }
        return track
    }

    /// **Media is deliberately NOT scoped**, and it is the one id reader
    /// that is not. A nest references the parent's `media[]` in the parent's
    /// one id space (spec §5.2), and `scoped_view` hands the view that very
    /// list — so the timeline's media IS the nest's, and an `add_clip`
    /// inside a nest names a file exactly as it does outside one. Narrowing
    /// this to "the media the nest's clips use" would refuse a file that has
    /// not been used in there YET, which is every file the first time.
    func mediaArg(
        _ a: [String: Any], _ key: String = "media", _ document: ProjectDocument
    ) throws -> MediaSnapshot {
        let id = try idArg(a, key)
        guard let media = document.project.snapshot.media(id) else {
            throw ToolError(
                message: "No media has id \(id). get_project lists the media; import_media adds "
                    + "a file.")
        }
        return media
    }

    /// **Markers are not scoped either, and here the reason is the message.**
    /// A nest has no `markers[]` at all, so `scoped_view` gives the view
    /// none — but the only two tools that read this argument are `set_marker`
    /// and `remove_marker`, both of which the core refuses inside a scope BY
    /// NAME ("set_marker has no meaning inside nest 4"). Looking the id up in
    /// an empty list would answer "No marker has id 12" first and hide the
    /// sentence that actually explains the refusal, so the timeline's markers
    /// stay the ones this resolves against and the core gets to answer.
    func markerArg(
        _ a: [String: Any], _ key: String = "marker", _ document: ProjectDocument
    ) throws -> MarkerSnapshot {
        let id = try idArg(a, key)
        guard let marker = document.project.snapshot.marker(id) else {
            throw ToolError(message: "No marker has id \(id). get_project lists the markers.")
        }
        return marker
    }

    /// An action id, checked against the clip that holds it — so it is
    /// scoped by construction, since the clip came from `clipArg` above and
    /// a nest's clips carry their own actions with them.
    func actionArg(
        _ a: [String: Any], _ key: String = "action", _ clip: ClipSnapshot
    ) throws -> ActionSnapshot {
        let id = try idArg(a, key)
        guard let action = clip.actions.first(where: { $0.id == id }) else {
            throw ToolError(
                message: "Clip \(clip.id) has no action \(id). get_project lists each clip's "
                    + "actions.")
        }
        return action
    }

    /// A required time in ticks, SNAPPED to the document's frame grid — the
    /// rule for every tick value that reaches an op (spec §6). The agent
    /// speaks the same ticks the model does: 600000 per second.
    func timeArg(
        _ a: [String: Any], _ key: String, _ document: ProjectDocument
    ) throws -> Ticks {
        guard let value = try optionalTimeArg(a, key, document) else {
            throw ToolError(
                message: "Missing required argument: \(key) (ticks, 600000 per second)")
        }
        return value
    }

    func optionalTimeArg(
        _ a: [String: Any], _ key: String, _ document: ProjectDocument
    ) throws -> Ticks? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        return try snappedTick(raw, key, document)
    }

    /// One time value read and SNAPPED to the document's frame grid, named by
    /// `key` when it cannot be read.
    ///
    /// Factored out of `optionalTimeArg` when `rangesArg` below arrived and
    /// wanted the same thing per element: the snap is spec §6's rule for
    /// every tick that reaches an op ("never store a sub-frame time",
    /// core/CLAUDE.md), and a second reader with its own copy of it is the
    /// exact drift this file exists to prevent. Bucket edges, drag positions
    /// and hand-written numbers all land on the grid here or nowhere.
    private func snappedTick(
        _ raw: Any, _ key: String, _ document: ProjectDocument
    ) throws -> Ticks {
        guard let number = (raw as? NSNumber)?.doubleValue
            ?? (raw as? String).flatMap(Double.init), number.isFinite,
            number >= -9.0e15, number <= 9.0e15
        else {
            throw ToolError(message: "\(key) must be a time in ticks (600000 per second).")
        }
        let ticks = Ticks(number.rounded())
        return ReelTime.snapToFrame(ticks, fps: document.project.snapshot.canvas.fps)
    }

    /// A list of time RANGES — `ripple_delete_ranges`' `ranges`, spelled
    /// `[[from, to], …]` as the op parses it — with every tick snapped
    /// through `snappedTick`, the same path `optionalTimeArg` takes.
    ///
    /// nil when the key is absent or null. A present-but-empty list comes
    /// back EMPTY rather than as an error: whether "no ranges" is a mistake
    /// or a no-op differs by op (the core answers "nothing to do" for this
    /// one), so the caller decides, as it does for `stringsArg`. A lone pair
    /// written flat — `[from, to]` rather than `[[from, to]]` — is taken as
    /// one range, the courtesy `clipsArg` extends to a lone id: a two-element
    /// array of numbers cannot mean anything else, and refusing it teaches
    /// nothing.
    ///
    /// A REVERSED pair is passed through untouched. `ordered_range` in the
    /// core puts every pair in order, so a reversed range is the same range,
    /// and a reader that quietly rewrote its argument would make the result a
    /// caller reads back disagree with the call it made.
    ///
    /// It lives here rather than beside the one tool that reads it today
    /// because a range list is not one op's private shape — the finding tools
    /// and any later range op want exactly this reader, and a private copy is
    /// where the snapping rule would go missing.
    func rangesArg(
        _ a: [String: Any], _ key: String, _ document: ProjectDocument
    ) throws -> [(from: Ticks, to: Ticks)]? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        guard let array = raw as? [Any] else {
            throw ToolError(
                message: "\(key) must be an array of [from, to] pairs, each a time in ticks.")
        }
        if array.count == 2, array.allSatisfy({ !($0 is [Any]) }) {
            return [try rangePair(array, key, document)]
        }
        var ranges: [(from: Ticks, to: Ticks)] = []
        for (index, element) in array.enumerated() {
            guard let pair = element as? [Any], pair.count == 2 else {
                throw ToolError(
                    message: "\(key) must contain [from, to] pairs — two times in ticks each.")
            }
            ranges.append(try rangePair(pair, "\(key)[\(index)]", document))
        }
        return ranges
    }

    /// One `[from, to]` element, each end named by its own path so a bad
    /// value says which end of which pair it was.
    private func rangePair(
        _ pair: [Any], _ path: String, _ document: ProjectDocument
    ) throws -> (from: Ticks, to: Ticks) {
        let from = try snappedTick(pair[0], "\(path)[0]", document)
        let to = try snappedTick(pair[1], "\(path)[1]", document)
        return (from: from, to: to)
    }

    /// A number one level down inside a shaped argument (`add_zoom_action`'s
    /// `region`), named by its PATH — `region.width`, not `width`.
    ///
    /// `patchArg`'s round trip is the guard against a wrong-typed value at
    /// the top level, and its own doc says why it cannot recurse: one level
    /// down every field has a real default, so a member set TO its default
    /// decodes the same as an absent one. A shaped argument that is not a
    /// patch has no such excuse — its members are all required — so it reads
    /// them here, one by one, and a `{"width": "wide"}` is refused rather
    /// than dropped.
    func nestedNumberArg(
        _ object: [String: Any], _ path: String, _ key: String
    ) throws -> Double? {
        guard let raw = object[key], !(raw is NSNull) else { return nil }
        guard let value = Self.numeric(raw)?.doubleValue
            ?? (raw as? String).flatMap(Double.init), value.isFinite
        else {
            throw ToolError(message: "\(path).\(key) must be a number.")
        }
        return value
    }

    /// A patch object (`set_video` and its siblings) decoded into its typed
    /// Swift form. Deliberately STRICTER than the core's serde on both counts
    /// a silent drop can happen: an unknown key is refused by NAME, and a key
    /// whose value the patch could not read is refused too, rather than either
    /// one leaving the model believing an edit it never made.
    ///
    /// **Why the second check is a round trip and not a type table.** Every
    /// `…Patch` decodes leniently, field by field, so the core can add a
    /// property without breaking this build (`ProjectSnapshot.lenient`) — and
    /// leniency is exactly wrong for a value a CALLER wrote: `{"content":
    /// "X", "color": "amber"}` decoded to the words with the colour dropped
    /// and nothing said (measured). Spelling out a type per key would mean a
    /// fourth mirror of the patch schemas to fall out of step with, so the
    /// test is behavioural instead: decode again with the key removed, and if
    /// that changes nothing then the key changed nothing.
    ///
    /// The check covers the patch's TOP-LEVEL keys and does not recurse. It
    /// is sound there because every field of a `…Patch` is optional, so a
    /// value that read correctly can never decode to the same thing as no
    /// value at all — there is no way for this to refuse a patch that would
    /// have worked. One level down that stops holding: `shadow` and `crop`
    /// are concrete structs with real defaults, and a field set TO its default
    /// would decode identically with the field removed, so recursing would
    /// refuse perfectly good patches. A wrong-typed value INSIDE a nested
    /// object is therefore still dropped silently; `checkActionPatch` catches
    /// its name, nothing catches its type.
    func patchArg<T: Decodable & Equatable>(
        _ a: [String: Any], _ key: String, _ type: T.Type, allowed: Set<String>
    ) throws -> T {
        guard let object = a[key] as? [String: Any] else {
            throw ToolError(
                message: "\(key) must be a JSON object of the properties to change, e.g. "
                    + "{\"scale\": 0.5}")
        }
        let unknown = object.keys.filter { !allowed.contains($0) }.sorted()
        if let first = unknown.first {
            throw ToolError(
                message: "Unknown \(key) key \"\(first)\" — allowed keys are "
                    + allowed.sorted().joined(separator: ", ") + ".")
        }
        guard let decoded = Self.decodePatch(object, type) else {
            throw ToolError(message: "\(key) could not be read as a property patch.")
        }
        // A null is not a dropped value: for a field that takes one it means
        // "clear it", and for one that does not the documented reading is
        // "leave it alone" — either way the key is doing what it says.
        for name in object.keys.sorted() where !(object[name] is NSNull) {
            var without = object
            without.removeValue(forKey: name)
            guard Self.decodePatch(without, type) == decoded else { continue }
            throw ToolError(
                message: "\(key).\(name) is not a value this key takes, so it would have "
                    + "been ignored. Check its type against the tool's schema.")
        }
        return decoded
    }

    /// One decode of a patch object, or nil when it could not be read at all.
    /// Split out of `patchArg` so the round-trip check runs the very same
    /// normalisation and decoder the real answer came from — a check against a
    /// different pipeline would be testing the check.
    private static func decodePatch<T: Decodable>(
        _ object: [String: Any], _ type: T.Type
    ) -> T? {
        let normalized = withOpaqueColors(object)
        guard JSONSerialization.isValidJSONObject(normalized),
            let data = try? JSONSerialization.data(withJSONObject: normalized),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return ReelJSON.decode(type, from: text)
    }

    /// Fills in the alpha of every `[r, g, b]` written under a `color` key,
    /// at any depth — the patch-shaped half of what `colorArg` does for a
    /// flat argument.
    ///
    /// The model spells a colour `[r, g, b, a]` (`core/src/model.rs`), but
    /// `set_canvas`'s `background` and every `set_shape` colour go through
    /// `colorArg` and take three components, so a caller learns that three is
    /// allowed and then writes `{"color": [1, 0, 0]}` in a text or shadow
    /// patch. Without this the array reaches serde intact and the core answers
    /// `invalid length 3, expected an array of length 4` — true, but naming
    /// neither the key nor the patch, which is exactly the message a model
    /// cannot correct itself from. Keyed on the NAME `color` and applied only
    /// to a three-number array, so `video.color` (a `ColorAdjust` object) and
    /// `chroma.key` — the one colour the core really does spell `[r, g, b]` —
    /// are both left alone.
    private static func withOpaqueColors(_ object: [String: Any]) -> [String: Any] {
        var out = object
        for (key, value) in object {
            if let nested = value as? [String: Any] {
                out[key] = withOpaqueColors(nested)
            } else if key == "color", let array = value as? [Any], array.count == 3,
                array.allSatisfy({ ($0 as? NSNumber)?.doubleValue.isFinite == true })
            {
                out[key] = array + [1.0]
            }
        }
        return out
    }

    /// A colour argument as the model spells one: `[r, g, b, a]` floats 0–1,
    /// alpha optional. nil when the key is absent.
    func colorArg(_ a: [String: Any], _ key: String) throws -> RGBA? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        guard let array = raw as? [Any], array.count == 3 || array.count == 4 else {
            throw ToolError(
                message: "\(key) must be [r, g, b] or [r, g, b, a], each 0–1.")
        }
        var components: [Double] = []
        for value in array {
            guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else {
                throw ToolError(message: "\(key) must contain numbers 0–1.")
            }
            components.append(min(max(number, 0), 1))
        }
        if components.count == 3 { components.append(1) }
        return components
    }

    /// `colorArg` where the colour is not optional — the nested `color` of a
    /// stroke, an outline or a backdrop, whose absence is a malformed object
    /// rather than "leave it alone".
    func requiredColorArg(_ a: [String: Any], _ key: String) throws -> RGBA {
        guard let color = try colorArg(a, key) else {
            throw ToolError(message: "\(key) must be [r, g, b] or [r, g, b, a], each 0–1.")
        }
        return color
    }
}
