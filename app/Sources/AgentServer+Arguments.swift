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
            (raw as? NSNumber)?.intValue ?? (raw as? String).flatMap(Int.init)
        }
    }

    func doubleArg(_ a: [String: Any], _ key: String) throws -> Double? {
        try scalarArg(a, key, "a number") { raw in
            (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init)
        }
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

    func clipArg(
        _ a: [String: Any], _ key: String = "clip", _ document: ProjectDocument
    ) throws -> ClipSnapshot {
        let id = try idArg(a, key)
        guard let clip = document.project.snapshot.clip(id) else {
            throw ToolError(message: "No clip has id \(id). get_project lists the clips.")
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
        let snapshot = document.project.snapshot
        var ids: [UInt32] = []
        for value in raw {
            guard let number = (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init),
                number >= 0, number <= Int(UInt32.max)
            else {
                throw ToolError(message: "\(key) must contain clip ids (integers).")
            }
            let id = UInt32(number)
            guard snapshot.clip(id) != nil else {
                throw ToolError(message: "No clip has id \(id). get_project lists the clips.")
            }
            ids.append(id)
        }
        return ids
    }

    func trackArg(
        _ a: [String: Any], _ key: String = "track", _ document: ProjectDocument
    ) throws -> TrackSnapshot {
        let id = try idArg(a, key)
        guard let track = document.project.snapshot.track(id) else {
            throw ToolError(message: "No track has id \(id). get_project lists the tracks.")
        }
        return track
    }

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

    func markerArg(
        _ a: [String: Any], _ key: String = "marker", _ document: ProjectDocument
    ) throws -> MarkerSnapshot {
        let id = try idArg(a, key)
        guard let marker = document.project.snapshot.marker(id) else {
            throw ToolError(message: "No marker has id \(id). get_project lists the markers.")
        }
        return marker
    }

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
        guard let number = (raw as? NSNumber)?.doubleValue
            ?? (raw as? String).flatMap(Double.init), number.isFinite,
            number >= -9.0e15, number <= 9.0e15
        else {
            throw ToolError(message: "\(key) must be a time in ticks (600000 per second).")
        }
        let ticks = Ticks(number.rounded())
        return ReelTime.snapToFrame(ticks, fps: document.project.snapshot.canvas.fps)
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
