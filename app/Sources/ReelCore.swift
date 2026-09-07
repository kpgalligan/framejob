import AppKit

/// The ONLY file in the app that names an `rc_*` symbol. Everything the Rust
/// core can do reaches the rest of Reelcut as typed Swift here: `ReelProject`
/// (a handle plus its lazily decoded `ProjectSnapshot`), `ReelOp` (one static
/// factory per row of the op table), `ReelTime`, `ReelSnap`, `ReelExport` and
/// `RecipeSource`. `ProjectSnapshot.swift` owns the read side of the same
/// contract; `core/include/reelcut_core.h` is the contract itself.
///
/// Three conventions carried from Rasterize's `RasterCore.swift`:
///
///  - A handle is IMMUTABLE. Every edit returns a NEW handle, which is why
///    undo in `ProjectDocument` is a stack of these objects and why sharing
///    one across threads is safe.
///  - `deinit` frees the Rust allocation, and every `char *` the library
///    returns goes through `takeString` / `takeErrorMessage`, which free it.
///  - `rc_project_apply` returning NULL means two different things — see
///    `applying(_:)`. Getting that wrong is a phantom undo step.

/// Error thrown by the Rust core, carrying the message from `err_out`.
struct ReelCoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Consumes a Rust-allocated error string and returns its contents.
private func takeErrorMessage(_ err: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
    guard let err = err else { return fallback }
    defer { rc_string_free(err) }
    return String(cString: err)
}

/// Consumes any Rust-allocated string and returns its contents. Every
/// `char *` this library hands back MUST come through here — the core
/// allocated it, only `rc_string_free` may release it.
private func takeString(_ s: UnsafeMutablePointer<CChar>?) -> String? {
    guard let s = s else { return nil }
    defer { rc_string_free(s) }
    return String(cString: s)
}

/// A JSON array of integers, built by hand rather than through
/// `JSONSerialization` because the core's parsers want plain `[1,2,3]` and
/// this cannot fail.
private func jsonArray<T: FixedWidthInteger>(_ values: [T]) -> String {
    "[" + values.map { String($0) } .joined(separator: ",") + "]"
}

extension Fps {
    /// The rate as the two `uint32_t` arguments every `rc_*` time function
    /// takes; nil for a degenerate or out-of-range rate — impossible in a
    /// document the core wrote, possible in a hand-written JSON.
    var ffiPair: (num: UInt32, den: UInt32)? {
        guard num > 0, den > 0, num <= Int(UInt32.max), den <= Int(UInt32.max) else { return nil }
        return (UInt32(num), UInt32(den))
    }
}

// MARK: - The project handle

/// Owning Swift wrapper around an `RcProject *`. Immutable: nothing here
/// mutates the Rust value, so a handle published to another thread (the
/// compositor, through `RecipeSource`) stays coherent forever — every edit
/// makes a NEW handle instead.
///
/// The memos below are the one piece of Swift state a handle carries. They
/// are pure functions of the immutable Rust value, so caching them changes
/// no answer; the lock is there because the compositor's queue asks for
/// recipes while the main thread asks for the snapshot.
final class ReelProject {
    let ptr: OpaquePointer

    private let lock = NSLock()
    private var memoJSON: String?
    private var memoSnapshot: ProjectSnapshot?
    private var memoPlanJSON: String?

    init(owning pointer: OpaquePointer) {
        self.ptr = pointer
    }

    deinit {
        rc_project_free(ptr)
    }

    /// A new empty project: one track, no media, no clips. nil for a zero
    /// dimension or a degenerate rate (the core's contract, checked here too
    /// so the `UInt32` conversions below cannot trap).
    static func new(width: Int, height: Int, fps: Fps) -> ReelProject? {
        guard width > 0, height > 0, width <= Int(UInt32.max), height <= Int(UInt32.max),
              let rate = fps.ffiPair
        else { return nil }
        return rc_project_new(UInt32(width), UInt32(height), rate.num, rate.den)
            .map { ReelProject(owning: $0) }
    }

    /// Parses project JSON of any format version this build knows.
    static func from(json: String) throws -> ReelProject {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let handle = rc_project_from_json(json, &err) else {
            throw ReelCoreError(
                message: takeErrorMessage(err, fallback: "The project could not be read."))
        }
        return ReelProject(owning: handle)
    }

    /// Deep-copies the handle. Rarely needed — handles are immutable — but
    /// the core offers it and a copy is what `NSDocument`'s duplicate wants.
    func clone() -> ReelProject? {
        rc_project_clone(ptr).map { ReelProject(owning: $0) }
    }

    /// The project as JSON at the current format version — the bytes
    /// `ProjectDocument` writes into the package. The core is the only
    /// writer of the file format; nothing re-encodes a `ProjectSnapshot`.
    var json: String {
        lock.lock()
        defer { lock.unlock() }
        return lockedJSON()
    }

    /// The typed read-only view every Swift view draws from, decoded ONCE
    /// per handle. A decode failure falls back to `ProjectSnapshot.empty`
    /// rather than an optional, so no view needs an "unloaded" state.
    var snapshot: ProjectSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let memoSnapshot = memoSnapshot { return memoSnapshot }
        let decoded = ReelJSON.decode(ProjectSnapshot.self, from: lockedJSON()) ?? .empty
        memoSnapshot = decoded
        return decoded
    }

    /// End of the last clip, in ticks.
    var duration: Ticks { rc_project_duration(ptr) }

    /// The composition plan as RAW JSON. `Playback` keeps the current one
    /// and compares strings: equal means the edit was property-only and the
    /// player needs no rebuild (§7.6, §11). Do not "normalise" this string.
    var planJSON: String {
        lock.lock()
        defer { lock.unlock() }
        if let memoPlanJSON = memoPlanJSON { return memoPlanJSON }
        let value = takeString(rc_project_composition_plan(ptr)) ?? "{}"
        memoPlanJSON = value
        return value
    }

    /// The plan decoded, for `CompositionBuilder`. nil only when the core
    /// emitted something this build cannot read.
    var plan: CompositionPlan? {
        ReelJSON.decode(CompositionPlan.self, from: planJSON)
    }

    /// The frame recipe at project time `t`: the back-to-front layer list
    /// with every property already evaluated through actions. Asked once per
    /// composed frame and by the canvas overlay for hit-testing.
    func recipe(at t: Ticks) -> FrameRecipe? {
        recipeJSON(at: t).flatMap { ReelJSON.decode(FrameRecipe.self, from: $0) }
    }

    /// The same recipe as raw JSON, for the agent's `render_frame` reply and
    /// for debugging a composited frame.
    func recipeJSON(at t: Ticks) -> String? {
        takeString(rc_project_frame_recipe(ptr, t))
    }

    /// One clip's evaluated properties at project time `t`, for the
    /// inspector's "you are inside an action" read-out. Untyped on purpose:
    /// the shape is the union of the property groups a clip happens to have,
    /// and the inspector reads individual keys. nil for an unknown clip id.
    func clipState(_ clip: UInt32, at t: Ticks) -> [String: Any]? {
        guard let json = takeString(rc_project_clip_state(ptr, clip, t)),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object as? [String: Any]
    }

    /// Sorted, de-duplicated snap targets for a timeline drag: clip edges,
    /// markers and the like, with the dragged clips left out. The core
    /// groups them by kind; the timeline wants one flat list to resolve
    /// against, so they are merged here.
    func snapCandidates(excluding clips: [UInt32] = []) -> [Ticks] {
        let raw: UnsafeMutablePointer<CChar>?
        if clips.isEmpty {
            raw = rc_project_snap_candidates(ptr, nil)
        } else {
            raw = rc_project_snap_candidates(ptr, jsonArray(clips))
        }
        guard let json = takeString(raw), let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        var out = Set<Ticks>()
        func absorb(_ value: Any) {
            if let numbers = value as? [NSNumber] {
                for number in numbers { out.insert(number.int64Value) }
            }
        }
        if let grouped = object as? [String: Any] {
            for value in grouped.values { absorb(value) }
        } else {
            absorb(object)
        }
        return out.sorted()
    }

    /// Applies one op and returns the resulting project.
    ///
    /// Returns nil when the op is VALID but changes nothing — the core's
    /// NULL-with-`err_out`-untouched case. The caller registers NO undo step
    /// for that (an identity edit is a phantom undo step); the UI beeps or
    /// animates the gesture back. Throws when the op or its arguments are
    /// invalid, with the core's own message.
    func applying(_ op: ReelOp) throws -> ReelProject? {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let handle = rc_project_apply(ptr, op.json, &err) else {
            guard err == nil else {
                throw ReelCoreError(
                    message: takeErrorMessage(err, fallback: "The edit could not be applied."))
            }
            return nil
        }
        return ReelProject(owning: handle)
    }

    /// Applies ops in order, each to the result of the last. nil when EVERY
    /// op was an identity edit; a later op still runs after an earlier
    /// identity, so a compound gesture is not lost because its first step
    /// happened to change nothing.
    func applying(_ ops: [ReelOp]) throws -> ReelProject? {
        var current: ReelProject?
        for op in ops {
            if let next = try (current ?? self).applying(op) { current = next }
        }
        return current
    }

    /// Reads `memoJSON` while the lock is already held. NSLock is NOT
    /// recursive, so the public accessors must never call each other.
    private func lockedJSON() -> String {
        if let memoJSON = memoJSON { return memoJSON }
        let value = takeString(rc_project_to_json(ptr)) ?? "{}"
        memoJSON = value
        return value
    }
}

// MARK: - Snapping

/// The timeline's snap resolver. Candidates come from
/// `ReelProject.snapCandidates(excluding:)` (timeline) or are computed in
/// Swift from the layer rects (canvas, §4.2); the nearest-within-threshold
/// pick is the core's, so both sides behave identically.
enum ReelSnap {
    /// The nearest candidate to `t` within `threshold` ticks, and whether
    /// one was taken. Returns `(t, false)` unchanged with no candidates or a
    /// non-positive threshold — the ⌘-suppressed case.
    static func resolve(_ candidates: [Ticks], _ t: Ticks, threshold: Ticks) -> (Ticks, Bool) {
        guard !candidates.isEmpty, threshold > 0 else { return (t, false) }
        var snapped = false
        let resolved = rc_snap_resolve(jsonArray(candidates), t, threshold, &snapped)
        return (resolved, snapped)
    }
}

// MARK: - Time

/// Ticks, frames and timecode. Formatting and parsing are the core's so the
/// toolbar, the ruler, the inspector and the agent all spell a time the same
/// way (§4.1).
enum ReelTime {
    /// Ticks per second — `RC_TIMESCALE`. Divides every common frame
    /// duration exactly, and `CMTime` at this timescale round-trips.
    static let perSecond: Ticks = 600_000

    /// Rounds `t` to the nearest frame boundary. EVERY tick value that
    /// reaches an op goes through here first; the model never stores a
    /// sub-frame time (§5.1).
    static func snapToFrame(_ t: Ticks, fps: Fps) -> Ticks {
        guard let rate = fps.ffiPair else { return t }
        return rc_time_snap_to_frame(t, rate.num, rate.den)
    }

    /// Non-drop timecode: "HH:MM:SS:FF" when `frames`, else "HH:MM:SS.mmm".
    static func format(_ t: Ticks, fps: Fps, frames: Bool) -> String {
        guard let rate = fps.ffiPair,
              let text = takeString(rc_timecode_format(t, rate.num, rate.den, frames))
        else { return frames ? "00:00:00:00" : "00:00:00.000" }
        return text
    }

    /// Parses "HH:MM:SS:FF", "MM:SS", "SS.sss" and "HH:MM:SS.mmm"; nil when
    /// the text is not a time, which is how the timecode field refuses.
    static func parse(_ s: String, fps: Fps) -> Ticks? {
        guard let rate = fps.ffiPair else { return nil }
        var out: Int64 = 0
        guard rc_timecode_parse(s, rate.num, rate.den, &out) else { return nil }
        return out
    }

    /// Seconds to ticks, rounded. 0 for a non-finite input.
    static func ticks(seconds: Double) -> Ticks {
        guard seconds.isFinite else { return 0 }
        let scaled = (seconds * Double(perSecond)).rounded()
        guard scaled >= Double(Ticks.min), scaled <= Double(Ticks.max) else { return 0 }
        return Ticks(scaled)
    }

    /// Ticks to seconds, for `CMTime` and for anything measured in seconds
    /// in the inspector (fades, ducking attack/release).
    static func seconds(_ t: Ticks) -> Double {
        Double(t) / Double(perSecond)
    }
}

// MARK: - Export

/// One row of `rc_export_presets`. Decoded leniently: the core owns this
/// schema (§7.8) and may add fields this build does not know.
struct ExportPreset: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    /// "mov", "mp4", "m4a".
    let container: String
    /// "h264", "hevc", "prores_422", "aac".
    let codec: String
    /// Fixed output size, or nil for the document (canvas) size.
    let width: Int?
    let height: Int?
    let audioOnly: Bool

    /// The core spells the size as one `size: [w, h] | null` and audio-only
    /// as `video: false` (`export.rs`), so the size and the audio flag are
    /// read from those rather than from `width` / `height` / `audio_only`,
    /// which it never emits.
    private enum CodingKeys: String, CodingKey {
        case id, name, container, codec, size, video
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, "")
        name = c.lenient(.name, "")
        container = c.lenient(.container, "mov")
        codec = c.lenient(.codec, "h264")
        let size: [Int]? = c.lenient(.size)
        width = size?.count == 2 ? size?[0] : nil
        height = size?.count == 2 ? size?[1] : nil
        audioOnly = !c.lenient(.video, true)
    }
}

/// A preset plus overrides resolved against the project into the concrete
/// numbers `Exporter` configures its pipeline with — `ExportWriter` or the
/// ImageIO frame sequence (§7.8).
struct ExportSettings: Decodable, Equatable {
    let preset: String
    let container: String
    let codec: String
    let width: Int
    let height: Int
    let fps: Fps
    /// The range to write — the whole timeline, or the in/out range.
    let start: Ticks
    let duration: Ticks
    /// The `AVAssetExportSession` preset name the row carries for the
    /// record; nil is the signal that AVFoundation cannot write this
    /// container and the frames go through ImageIO (`isImageSequence`).
    let avPreset: String?
    /// The `AVFileType` raw value, e.g. "com.apple.quicktime-movie".
    let fileType: String?
    let optimizeForNetwork: Bool
    let videoBitrate: Int?
    let audioBitrate: Int?

    /// Spelled out rather than synthesized because two keys do not follow
    /// from the property names: the core nests the resolved range under
    /// `range` (`export.rs`), and its preset name is `avf_preset`, which
    /// `.convertFromSnakeCase` turns into `avfPreset`. Decoding those as
    /// `start` / `duration` / `avPreset` silently produced a zero-length
    /// range — which disabled the export sheet's Export button and made the
    /// agent's `export` report `"duration": 0` — and threw the core's
    /// AVFoundation preset away.
    private enum CodingKeys: String, CodingKey {
        case preset, container, codec, width, height, fps, range
        case avPreset = "avfPreset"
        case fileType, optimizeForNetwork, videoBitrate, audioBitrate
    }

    private enum RangeKeys: String, CodingKey {
        case start, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = c.lenient(.preset, "")
        container = c.lenient(.container, "mov")
        codec = c.lenient(.codec, "h264")
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        fps = c.lenient(.fps, Fps.thirty)
        let range = try? c.nestedContainer(keyedBy: RangeKeys.self, forKey: .range)
        start = range?.lenient(.start, 0) ?? 0
        duration = range?.lenient(.duration, 0) ?? 0
        avPreset = c.lenient(.avPreset)
        fileType = c.lenient(.fileType)
        optimizeForNetwork = c.lenient(.optimizeForNetwork, true)
        videoBitrate = c.lenient(.videoBitrate)
        audioBitrate = c.lenient(.audioBitrate)
    }

    var renderSize: CGSize { CGSize(width: width, height: height) }
}

/// One row of the export sheet's Size popup, from `rc_export_sizes`: the
/// document's own size, an image format's cap, or a standard size fitted to
/// the document's aspect.
struct ExportSize: Decodable, Equatable, Identifiable {
    /// "document", "preset" (an image format's cap), "2160p", "1440p",
    /// "1080p" or "720p" — the vocabulary the `export` tool's `size` takes.
    let id: String
    /// "Document size", "GIF default", "4K", "1080p"… — the sheet appends
    /// the numbers.
    let name: String
    let width: Int
    let height: Int
}

/// Export presets and settings resolution — the core decides, `Exporter`
/// does (§7.8).
enum ReelExport {
    /// The presets — one per encoding — in the order the export sheet lists
    /// them; the first is the default the sheet opens on. Empty only if the
    /// core failed, which it does not.
    static func presets() -> [ExportPreset] {
        guard let json = takeString(rc_export_presets()) else { return [] }
        return ReelJSON.decode([ExportPreset].self, from: json) ?? []
    }

    /// The sizes the Size popup offers for `preset` against this project, in
    /// menu order; the first is the default. Throws with the core's message
    /// for an unknown preset.
    static func sizes(_ p: ReelProject, preset: String) throws -> [ExportSize] {
        var err: UnsafeMutablePointer<CChar>? = nil
        let raw = rc_export_sizes(p.ptr, preset, &err)
        guard let json = takeString(raw) else {
            throw ReelCoreError(
                message: takeString(err) ?? "The core could not list export sizes.")
        }
        guard let sizes = ReelJSON.decode([ExportSize].self, from: json) else {
            throw ReelCoreError(message: "The core's export sizes could not be read.")
        }
        return sizes
    }

    /// Resolves `preset` plus optional `overrides` (size, fps, range, and the
    /// two bitrates the Quality popup writes) against the project. Throws
    /// with the core's message for an unknown preset or bad overrides, so the
    /// sheet can show it verbatim.
    static func settings(
        _ p: ReelProject, preset: String, overrides: [String: Any]? = nil
    ) throws -> ExportSettings {
        var overridesJSON: String?
        if let overrides = overrides, !overrides.isEmpty {
            guard JSONSerialization.isValidJSONObject(overrides),
                  let data = try? JSONSerialization.data(
                    withJSONObject: overrides, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8)
            else { throw ReelCoreError(message: "The export overrides are not valid JSON.") }
            overridesJSON = text
        }
        var err: UnsafeMutablePointer<CChar>? = nil
        let raw: UnsafeMutablePointer<CChar>?
        if let overridesJSON = overridesJSON {
            raw = rc_export_settings(p.ptr, preset, overridesJSON, &err)
        } else {
            raw = rc_export_settings(p.ptr, preset, nil, &err)
        }
        guard let json = takeString(raw) else {
            throw ReelCoreError(
                message: takeErrorMessage(err, fallback: "Unknown export preset '\(preset)'."))
        }
        guard let settings = ReelJSON.decode(ExportSettings.self, from: json) else {
            throw ReelCoreError(
                message: "The core returned export settings this build cannot read.")
        }
        return settings
    }
}

// MARK: - Op arguments

/// Accumulates an op's arguments, DROPPING every nil so the core's serde
/// defaults apply — the rule for every optional argument in §6.
///
/// `put` is generic rather than taking `Any?` on purpose: a nil `Ticks?`
/// coerced to `Any?` can arrive as a non-nil `Any` wrapping a nil, which
/// would send `null` where the op wanted the key absent.
private struct OpArgs {
    private(set) var values: [String: Any] = [:]

    mutating func put<T>(_ key: String, _ value: T?) {
        if let value = value { values[key] = value }
    }

    /// An EXPLICIT JSON null — the spelling that clears a field (`kind:
    /// null` on `set_transition`, a removed key on `set_action_end`).
    mutating func putNull(_ key: String) {
        values[key] = NSNull()
    }
}

/// One edit, as the core's `{"op": "<name>", ...args}`.
///
/// The static factories below are one per row of the op table in spec §6 and
/// in the module doc of `core/src/edit.rs`. **The two move together**: an op
/// added, renamed or re-argumented in `edit.rs` is changed here in the same
/// commit, and nowhere else in the app is op JSON written by hand.
struct ReelOp {
    let name: String
    let args: [String: Any]

    /// The op as the JSON `rc_project_apply` takes. Keys are sorted so two
    /// equal ops compare equal as strings. `"{}"` — which the core rejects
    /// as an unknown op — if a value were not JSON-representable, which the
    /// typed factories make impossible.
    var json: String {
        var object = args
        object["op"] = name
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}

// MARK: - Op factories: clips

extension ReelOp {
    /// Whole media as one clip at `at`; Fit scale when the canvas says so.
    static func addClip(track: UInt32, media: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("media", media)
        a.put("at", at)
        return ReelOp(name: "add_clip", args: a.values)
    }

    /// A text clip; `duration` defaults to 5 s and `text` to the Title
    /// preset in the core.
    ///
    /// The op's `text` argument is a `set_text` PATCH, not a string — the
    /// core merges it over the Title preset — so the whole of `TextPatch`
    /// is reachable at creation and the caller's words go in under
    /// `content`. Passing a bare string is what the core answers
    /// `text patch must be a json object` to.
    static func addTextClip(
        track: UInt32, at: Ticks, duration: Ticks? = nil, text: TextPatch? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        a.put("duration", duration)
        a.put("text", text.map { $0.dictionary })
        return ReelOp(name: "add_text_clip", args: a.values)
    }

    /// A shape clip; `duration` defaults to 5 s and `shape` to the core's
    /// default rectangle.
    ///
    /// As with `addTextClip`, the op's `shape` argument is a `set_shape`
    /// patch merged over that default (and over an arrow's head — see the
    /// op table), so the box and the paint are reachable at creation too.
    static func addShapeClip(
        track: UInt32, at: Ticks, duration: Ticks? = nil, shape: ShapePatch? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        a.put("duration", duration)
        a.put("shape", shape.map { $0.dictionary })
        return ReelOp(name: "add_shape_clip", args: a.values)
    }

    /// The kind-only shorthand for the one caller that wants nothing else:
    /// the Add Shape menu, which picks a kind and takes the core's box,
    /// paint and — for an arrow — its head. An overload rather than a job
    /// for the caller, so `EditorViewController+AddClips` never has to
    /// spell a patch, and so this stays the only file that knows a kind
    /// travels as `{"kind": …}`.
    static func addShapeClip(
        track: UInt32, at: Ticks, duration: Ticks? = nil, shape: ShapeKind
    ) -> ReelOp {
        addShapeClip(track: track, at: at, duration: duration, shape: ShapePatch(kind: shape))
    }

    /// The insert edit: makes room for the whole media at `at` on `track`
    /// — the clip `at` is inside on that track is cut first, then every
    /// unlocked track opens by the media's length — and places it. One op,
    /// so one undo step and one MCP tool. Refuses when the clip could not
    /// be placed after the room was made (a locked destination track);
    /// errors on an unknown track or media, or a media with no duration.
    static func insertClip(track: UInt32, media: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("media", media)
        a.put("at", at)
        return ReelOp(name: "insert_clip", args: a.values)
    }

    /// The overwrite edit: takes the room instead of making it. The span
    /// the media needs is cleared on `track` ALONE — cut at both bounds,
    /// the middles removed — and nothing shifts.
    ///
    /// A LOCKED destination is cleared like any other: the caller named the
    /// track, exactly as `rippleDelete` removes the clips it was given, and
    /// a lock decides only what may SHIFT — which here is nothing. That is
    /// the one place this differs from `insertClip`, which refuses on a
    /// locked track because the room it promises cannot be made there.
    /// Refuses when the clip could not be placed after the span was
    /// cleared; errors on an unknown track or media, or a media with no
    /// duration.
    static func overwriteClip(track: UInt32, media: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("media", media)
        a.put("at", at)
        return ReelOp(name: "overwrite_clip", args: a.values)
    }

    /// Every op name the core accepts, in the order of its table
    /// (`OP_NAMES` in `core/src/edit.rs`), read through the FFI rather than
    /// copied into Swift: a copy is one more spelling to drift, and the one
    /// caller — `AgentServer`'s startup parity check — exists precisely to
    /// catch drift. Empty only if the core failed, which it does not.
    static func coreNames() -> [String] {
        guard let json = takeString(rc_op_names()) else { return [] }
        return ReelJSON.decode([String].self, from: json) ?? []
    }

    /// Shifts clips by `delta` ticks and optionally to another track (the
    /// others keep their relative track offsets). Refuses when the overlap
    /// rule fails on the destination.
    static func moveClip(clips: [UInt32], delta: Ticks, track: UInt32? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("delta", delta)
        a.put("track", track)
        return ReelOp(name: "move_clip", args: a.values)
    }

    /// Front trim: the source in-point advances with the start, so later
    /// content stays where it is.
    static func trimStart(clip: UInt32, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to", to)
        return ReelOp(name: "trim_start", args: a.values)
    }

    static func trimEnd(clip: UInt32, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to", to)
        return ReelOp(name: "trim_end", args: a.values)
    }

    /// ⌥-drag on an edge: speed changes so the content fills the new length.
    /// Media sources only.
    static func rateStretch(clip: UInt32, toEnd: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to_end", toEnd)
        return ReelOp(name: "rate_stretch", args: a.values)
    }

    /// ⌥⇧-drag on a clip body: the source slides under a fixed clip.
    /// `delta` is TIMELINE ticks and the source moves by `delta × speed`;
    /// the start and duration do not move at all. Clamped inside the media,
    /// and a delta the clamps reduce to nothing is a refusal. A `still`
    /// moves the frame it holds; any other source is an error.
    static func slip(clip: UInt32, delta: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("delta", delta)
        return ReelOp(name: "slip", args: a.values)
    }

    /// ⌥⇧-drag on a clip edge: the hard cut between this clip and the one
    /// ending exactly at its start moves to `to`, and nothing else does.
    /// Refuses without a hard cut there — a gap, or an overlap, whose
    /// length is `setTransitionDuration`'s.
    static func roll(clip: UInt32, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to", to)
        return ReelOp(name: "roll", args: a.values)
    }

    /// Splits at `at`. OMITTING `clips` entirely — not passing a flag — is
    /// what means "every unlocked clip under the playhead", the
    /// ⌘T-with-no-selection case: the core's `Op::Split` carries
    /// `clips: Option<Vec<u32>>` and `deny_unknown_fields`, so any extra key
    /// here is an error rather than a silently ignored hint.
    static func split(clips: [UInt32]?, at: Ticks) -> ReelOp {
        var a = OpArgs()
        if let clips = clips, !clips.isEmpty {
            a.put("clips", clips)
        }
        a.put("at", at)
        return ReelOp(name: "split", args: a.values)
    }

    /// Removes clips and LEAVES the gaps.
    static func delete(clips: [UInt32]) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        return ReelOp(name: "delete", args: a.values)
    }

    /// Removes clips and closes the gaps across every unlocked track.
    static func rippleDelete(clips: [UInt32]) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        return ReelOp(name: "ripple_delete", args: a.values)
    }

    /// The in/out-range form: splits every unlocked clip at both bounds,
    /// removes the middles, then shifts.
    static func rippleDeleteRange(from: Ticks, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("from", from)
        a.put("to", to)
        return ReelOp(name: "ripple_delete_range", args: a.values)
    }

    /// The same cut without the close: ⌫ with a range and nothing
    /// selected. Every clip after the range keeps the moment it had.
    static func liftRange(from: Ticks, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("from", from)
        a.put("to", to)
        return ReelOp(name: "lift_range", args: a.values)
    }

    /// Shifts every unlocked clip starting at or after `at` right by
    /// `length`; straddling clips stay put.
    static func insertTime(at: Ticks, length: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("at", at)
        a.put("length", length)
        return ReelOp(name: "insert_time", args: a.values)
    }

    /// Closes the empty span on `track` that contains `at`, shifting
    /// everything past it left across every unlocked track. Refuses on a
    /// locked track, on an `at` that is on a clip, with nothing after the
    /// gap, and when the shift would break the overlap rule — a gap closes
    /// fully or not at all.
    static func closeGap(track: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        return ReelOp(name: "close_gap", args: a.values)
    }

    /// Media sources only; actions keep their clip-relative fraction.
    static func setSpeed(clip: UInt32, rate: Double, keepPitch: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("rate", rate)
        a.put("keep_pitch", keepPitch)
        return ReelOp(name: "set_speed", args: a.values)
    }

    /// Plays a media clip back to front, or forward again.
    ///
    /// A FACT about the clip and not a plan change: the core's recipe and
    /// composition plan come out identical either way, and it is Swift that
    /// resolves it by substituting a pre-rendered reversed asset for that
    /// media's segments (spec §11). The in point is measured in the direction
    /// the clip plays, so flipping this keeps `in` and therefore shows
    /// different frames — the tail of the file instead of its head.
    ///
    /// Media sources only: any other kind is an `Err`, not a refusal (the
    /// non-media rule, §6).
    static func setReversed(clip: UInt32, reversed: Bool) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("reversed", reversed)
        return ReelOp(name: "set_reversed", args: a.values)
    }

    /// Split, insert time, then a one-source-frame `still` filling the gap.
    /// `duration` defaults to 2 s.
    static func freezeFrame(clip: UInt32, at: Ticks, duration: Ticks? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("at", at)
        a.put("duration", duration)
        return ReelOp(name: "freeze_frame", args: a.values)
    }

    /// Mutes the clip's audio and puts it on its own clip below. Refuses
    /// when the media has no audio or the audio is already detached.
    static func detachAudio(clip: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        return ReelOp(name: "detach_audio", args: a.values)
    }

    /// Copies placed after the originals' span on the same tracks.
    static func duplicate(clips: [UInt32]) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        return ReelOp(name: "duplicate", args: a.values)
    }

    /// Inserts a clipboard payload's clips with fresh ids, the earliest one
    /// landing exactly at `at` and the rest keeping their offsets from it.
    ///
    /// `payload` is what Copy wrote to the pasteboard —
    /// `{"clips": [...], "media": [...]}` — and
    /// `EditorViewController+Clipboard.swift` is the only place that builds
    /// one. **A payload clip's `track` is a DEPTH from the front of the stack**
    /// (0 = front-most), not a track id: the ids in it belong to whichever
    /// document was copied from. `track` here, by contrast, IS an id of this
    /// project, naming where depth 0 lands; omitted, that is the front track.
    static func paste(at: Ticks, track: UInt32? = nil, payload: [String: Any]) -> ReelOp {
        var a = OpArgs()
        a.put("at", at)
        a.put("track", track)
        a.put("payload", payload)
        return ReelOp(name: "paste", args: a.values)
    }

    /// Collapses `clips` into ONE clip showing a nest — ⌘G.
    ///
    /// The clips move whole (ids, props, actions, transitions) into the
    /// nest's own tracks, keeping their relative times with the earliest at
    /// 0; the nest clip lands on the front-most track the selection occupied
    /// and covers exactly the span the selection covered. `name` defaults to
    /// `Nest <n>` in the core. Refused on an empty selection, on a lone nest
    /// clip, and when the nest clip would break the overlap rule.
    static func nest(clips: [UInt32], name: String? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("name", name)
        return ReelOp(name: "nest", args: a.values)
    }

    /// Puts a nest clip's contents back on the timeline and removes it —
    /// ⇧⌘G. The inverse of `nest`, ids aside: each clip returns at
    /// `clip.start +` its own start, on tracks counted back from the nest
    /// clip's own, and a clip the overlap rule refuses goes on a new track in
    /// front rather than being dropped.
    ///
    /// A nest clip trimmed shorter than its contents gives ALL of them back —
    /// `Source::Nest` has no in point, so trimming one hid content rather
    /// than cutting it. An `Err` on any other kind of clip.
    static func unnest(clip: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        return ReelOp(name: "unnest", args: a.values)
    }

    /// Merges `patch` into the clips' base video props. Refuses when
    /// nothing changes, which is what keeps a live gesture from registering
    /// undo steps for frames that moved nowhere.
    static func setVideo(clips: [UInt32], patch: VideoPatch) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch.dictionary)
        return ReelOp(name: "set_video", args: a.values)
    }

    static func setAudio(clips: [UInt32], patch: AudioPatch) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch.dictionary)
        return ReelOp(name: "set_audio", args: a.values)
    }

    static func setText(clips: [UInt32], patch: TextPatch) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch.dictionary)
        return ReelOp(name: "set_text", args: a.values)
    }

    static func setShape(clips: [UInt32], patch: ShapePatch) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch.dictionary)
        return ReelOp(name: "set_shape", args: a.values)
    }

    /// Per-clip visibility and mute — the two halves Detach Audio flips.
    static func setEnabled(clip: UInt32, video: Bool? = nil, audio: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("video", video)
        a.put("audio", audio)
        return ReelOp(name: "set_enabled", args: a.values)
    }

    /// Sets the transition INTO `clip`; nil sends an explicit null, which
    /// clears it. The duration is the overlap, not an argument here.
    static func setTransition(clip: UInt32, kind: TransitionKind?) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        if let kind = kind {
            a.put("kind", kind.rawValue)
        } else {
            a.putNull("kind")
        }
        return ReelOp(name: "set_transition", args: a.values)
    }

    /// Moves the clip so the overlap equals `duration`, subject to the
    /// overlap rule.
    static func setTransitionDuration(clip: UInt32, duration: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("duration", duration)
        return ReelOp(name: "set_transition_duration", args: a.values)
    }
}

// MARK: - Op factories: actions

extension ReelOp {
    /// `at` is CLIP time. Refuses on an overlap with another action or a
    /// span past the clip end. The end patch starts empty.
    static func addAction(clip: UInt32, at: Ticks, duration: Ticks? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("at", at)
        a.put("duration", duration)
        return ReelOp(name: "add_action", args: a.values)
    }

    /// Moves or re-curves an action; the same overlap checks apply.
    static func setAction(
        clip: UInt32, action: UInt32, start: Ticks? = nil, duration: Ticks? = nil,
        curve: Curve? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("action", action)
        a.put("start", start)
        a.put("duration", duration)
        a.put("curve", curve?.rawValue)
        return ReelOp(name: "set_action", args: a.values)
    }

    /// Merges into the action's end patch. A key the patch sets to null is
    /// REMOVED from the end state — see `VideoPatch.shadow`'s double
    /// optional, which is how "clear it" is spelled.
    static func setActionEnd(clip: UInt32, action: UInt32, patch: ActionPatch) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("action", action)
        a.put("patch", patch.dictionary)
        return ReelOp(name: "set_action_end", args: a.values)
    }

    static func removeAction(clip: UInt32, action: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("action", action)
        return ReelOp(name: "remove_action", args: a.values)
    }
}

// MARK: - Op factories: tracks, markers, canvas, media

extension ReelOp {
    /// Inserts a track; index 0 is the BACK of the stack.
    static func addTrack(index: Int, name: String? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("index", index)
        a.put("name", name)
        return ReelOp(name: "add_track", args: a.values)
    }

    /// Refuses on a non-empty track unless `withClips`.
    static func removeTrack(track: UInt32, withClips: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("with_clips", withClips)
        return ReelOp(name: "remove_track", args: a.values)
    }

    static func moveTrack(track: UInt32, index: Int) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("index", index)
        return ReelOp(name: "move_track", args: a.values)
    }

    static func setTrack(
        track: UInt32, name: String? = nil, hidden: Bool? = nil, muted: Bool? = nil,
        locked: Bool? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("name", name)
        a.put("hidden", hidden)
        a.put("muted", muted)
        a.put("locked", locked)
        return ReelOp(name: "set_track", args: a.values)
    }

    static func removeEmptyTracks() -> ReelOp {
        ReelOp(name: "remove_empty_tracks", args: [:])
    }

    /// Markers snap to frames and two may not share a time.
    static func addMarker(
        at: Ticks, name: String? = nil, chapter: Bool? = nil, color: String? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("at", at)
        a.put("name", name)
        a.put("chapter", chapter)
        a.put("color", color)
        return ReelOp(name: "add_marker", args: a.values)
    }

    static func setMarker(
        marker: UInt32, time: Ticks? = nil, name: String? = nil, chapter: Bool? = nil,
        color: String? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("marker", marker)
        a.put("time", time)
        a.put("name", name)
        a.put("chapter", chapter)
        a.put("color", color)
        return ReelOp(name: "set_marker", args: a.values)
    }

    static func removeMarker(marker: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("marker", marker)
        return ReelOp(name: "remove_marker", args: a.values)
    }

    /// `rescaleClips` multiplies every clip's `x`, `y` and `scale` by the
    /// size ratio; changing `fps` re-snaps every clip start and duration.
    static func setCanvas(
        width: Int? = nil, height: Int? = nil, fps: Fps? = nil, background: RGBA? = nil,
        rescaleClips: Bool? = nil, fitNewClips: Bool? = nil, timecodeFrames: Bool? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("width", width)
        a.put("height", height)
        a.put("fps", fps.map { [$0.num, $0.den] })
        a.put("background", background)
        a.put("rescale_clips", rescaleClips)
        a.put("fit_new_clips", fitNewClips)
        a.put("timecode_frames", timecodeFrames)
        return ReelOp(name: "set_canvas", args: a.values)
    }

    /// Adds a probed file to the media list. The new id is read back from
    /// the resulting snapshot (`nextId` before the op), because the op
    /// entry point returns a project, not a value.
    static func addMedia(descriptor: MediaDescriptor) -> ReelOp {
        var a = OpArgs()
        a.put("descriptor", descriptor.dictionary)
        return ReelOp(name: "add_media", args: a.values)
    }

    /// Points a media entry at a new file after a move — the Relink… path.
    static func relinkMedia(media: UInt32, path: String, bookmark: String? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("media", media)
        a.put("path", path)
        a.put("bookmark", bookmark)
        return ReelOp(name: "relink_media", args: a.values)
    }

    /// Refuses while the media is in use unless `withClips`.
    static func removeMedia(media: UInt32, withClips: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("media", media)
        a.put("with_clips", withClips)
        return ReelOp(name: "remove_media", args: a.values)
    }
}

// MARK: - Media descriptors

/// A `media[]` element minus its id — what `MediaImporter.probe` produces
/// and `add_media` takes. The host probes the file; the core only stores
/// what came out (§6, §7.7).
struct MediaDescriptor: Equatable {
    var path: String
    var bookmark: String?
    var kind: MediaKind
    var duration: Ticks
    var width: Int
    var height: Int
    var fps: Fps
    var hasVideo: Bool
    var hasAudio: Bool
    var hasAlpha: Bool

    init(
        path: String, bookmark: String? = nil, kind: MediaKind = .video, duration: Ticks = 0,
        width: Int = 0, height: Int = 0, fps: Fps = .thirty, hasVideo: Bool = false,
        hasAudio: Bool = false, hasAlpha: Bool = false
    ) {
        self.path = path
        self.bookmark = bookmark
        self.kind = kind
        self.duration = duration
        self.width = width
        self.height = height
        self.fps = fps
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.hasAlpha = hasAlpha
    }

    /// Re-describes an existing entry, for Relink… and for the agent's
    /// echo of what it imported.
    init(_ media: MediaSnapshot) {
        self.init(
            path: media.path, bookmark: media.bookmark, kind: media.kind,
            duration: media.duration, width: media.width, height: media.height, fps: media.fps,
            hasVideo: media.hasVideo, hasAudio: media.hasAudio, hasAlpha: media.hasAlpha)
    }

    /// The descriptor under the model's own key names. `bookmark` is omitted
    /// rather than null when absent, so the core's serde default applies.
    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "path": path,
            "kind": kind.rawValue,
            "duration": duration,
            "width": width,
            "height": height,
            "fps": [fps.num, fps.den],
            "has_video": hasVideo,
            "has_audio": hasAudio,
            "has_alpha": hasAlpha,
        ]
        if let bookmark = bookmark { d["bookmark"] = bookmark }
        return d
    }
}

// MARK: - Value types as op-JSON dictionaries

/// These emit the model's own key names (§5.2). They live here rather than
/// beside the types because op JSON is this file's business: nothing outside
/// `ReelCore.swift` ever writes an op argument.
extension CropInsets {
    var dictionary: [String: Any] { ["l": l, "t": t, "r": r, "b": b] }
}

extension ShadowProps {
    var dictionary: [String: Any] {
        ["color": color, "opacity": opacity, "blur": blur, "angle": angle, "distance": distance]
    }
}

extension ColorAdjust {
    var dictionary: [String: Any] {
        ["brightness": brightness, "contrast": contrast, "saturation": saturation, "hue": hue]
    }
}

extension ChromaProps {
    var dictionary: [String: Any] {
        ["key": key, "tolerance": tolerance, "softness": softness, "spill": spill]
    }
}

extension FilterProps {
    var dictionary: [String: Any] { ["kind": kind.rawValue, "amount": amount] }
}

extension ReflectionProps {
    var dictionary: [String: Any] {
        ["opacity": opacity, "height": height, "gap": gap, "falloff": falloff]
    }
}

extension SpotlightProps {
    var dictionary: [String: Any] {
        [
            "shape": shape.rawValue, "x": x, "y": y, "width": width, "height": height,
            "feather": feather, "dim": dim, "zoom": zoom,
        ]
    }
}

extension DuckProps {
    var dictionary: [String: Any] { ["level": level, "attack": attack, "release": release] }
}

extension CompressorProps {
    var dictionary: [String: Any] {
        [
            "threshold_db": thresholdDb, "ratio": ratio, "attack": attack, "release": release,
            "makeup_db": makeupDb,
        ]
    }
}

extension OutlineProps {
    var dictionary: [String: Any] { ["width": width, "color": color] }
}

extension BackdropProps {
    var dictionary: [String: Any] { ["color": color, "padding": padding, "radius": radius] }
}

extension StrokeProps {
    var dictionary: [String: Any] { ["width": width, "color": color] }
}

// MARK: - Typed patches

/// A sparse patch of video properties. Every field is optional and only the
/// set ones are sent, so `set_video` merges rather than replaces.
///
/// **The double optionals** (`shadow`, `chroma`, `reflection`, `spotlight`)
/// carry the third state the model needs: `nil` leaves the field alone,
/// `.some(nil)` sends an explicit JSON null (clear it), `.some(value)` sets
/// it. A single optional cannot say "clear".
///
/// **`filters` is a SINGLE optional** and deliberately so: the model field is
/// `Vec<Filter>`, not `Option<Vec<Filter>>`, so there is no null form to
/// send. `nil` leaves the stack alone and `[]` clears it. Every write sends
/// the whole array — `actions::merge` replaces arrays wholesale — which is
/// what makes add, remove and reorder ordinary `set_video` patches rather
/// than three new ops.
struct VideoPatch: Codable, Equatable {
    var x: Double?
    var y: Double?
    var scale: Double?
    var rotation: Double?
    var opacity: Double?
    var crop: CropInsets?
    var cornerRadius: Double?
    var shadow: ShadowProps??
    var color: ColorAdjust?
    var chroma: ChromaProps??
    var filters: [FilterProps]?
    var reflection: ReflectionProps??
    var spotlight: SpotlightProps??

    init(
        x: Double? = nil, y: Double? = nil, scale: Double? = nil, rotation: Double? = nil,
        opacity: Double? = nil, crop: CropInsets? = nil, cornerRadius: Double? = nil,
        shadow: ShadowProps?? = nil, color: ColorAdjust? = nil, chroma: ChromaProps?? = nil,
        filters: [FilterProps]? = nil, reflection: ReflectionProps?? = nil,
        spotlight: SpotlightProps?? = nil
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.crop = crop
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.color = color
        self.chroma = chroma
        self.filters = filters
        self.reflection = reflection
        self.spotlight = spotlight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x)
        y = c.lenient(.y)
        scale = c.lenient(.scale)
        rotation = c.lenient(.rotation)
        opacity = c.lenient(.opacity)
        crop = c.lenient(.crop)
        cornerRadius = c.lenient(.cornerRadius)
        shadow = c.nullable(.shadow)
        color = c.lenient(.color)
        chroma = c.nullable(.chroma)
        filters = c.lenient(.filters)
        reflection = c.nullable(.reflection)
        spotlight = c.nullable(.spotlight)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let x = x { d["x"] = x }
        if let y = y { d["y"] = y }
        if let scale = scale { d["scale"] = scale }
        if let rotation = rotation { d["rotation"] = rotation }
        if let opacity = opacity { d["opacity"] = opacity }
        if let crop = crop { d["crop"] = crop.dictionary }
        if let cornerRadius = cornerRadius { d["corner_radius"] = cornerRadius }
        if let shadow = shadow {
            if let shadow = shadow {
                d["shadow"] = shadow.dictionary
            } else {
                d["shadow"] = NSNull()
            }
        }
        if let color = color { d["color"] = color.dictionary }
        if let chroma = chroma {
            if let chroma = chroma {
                d["chroma"] = chroma.dictionary
            } else {
                d["chroma"] = NSNull()
            }
        }
        if let filters = filters { d["filters"] = filters.map { $0.dictionary } }
        if let reflection = reflection {
            if let reflection = reflection {
                d["reflection"] = reflection.dictionary
            } else {
                d["reflection"] = NSNull()
            }
        }
        if let spotlight = spotlight {
            if let spotlight = spotlight {
                d["spotlight"] = spotlight.dictionary
            } else {
                d["spotlight"] = NSNull()
            }
        }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

/// A sparse patch of audio properties; `duck` uses the same three-state
/// double optional as `VideoPatch.shadow`.
struct AudioPatch: Codable, Equatable {
    var volume: Double?
    var muted: Bool?
    var fadeIn: Ticks?
    var fadeOut: Ticks?
    var duck: DuckProps??
    var mono: Bool?
    var keepPitch: Bool?
    var pan: Double?
    var compressor: CompressorProps??
    var noiseReduction: Double?

    init(
        volume: Double? = nil, muted: Bool? = nil, fadeIn: Ticks? = nil, fadeOut: Ticks? = nil,
        duck: DuckProps?? = nil, mono: Bool? = nil, keepPitch: Bool? = nil, pan: Double? = nil,
        compressor: CompressorProps?? = nil, noiseReduction: Double? = nil
    ) {
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.duck = duck
        self.mono = mono
        self.keepPitch = keepPitch
        self.pan = pan
        self.compressor = compressor
        self.noiseReduction = noiseReduction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = c.lenient(.volume)
        muted = c.lenient(.muted)
        fadeIn = c.lenient(.fadeIn)
        fadeOut = c.lenient(.fadeOut)
        duck = c.nullable(.duck)
        mono = c.lenient(.mono)
        keepPitch = c.lenient(.keepPitch)
        pan = c.lenient(.pan)
        compressor = c.nullable(.compressor)
        noiseReduction = c.lenient(.noiseReduction)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let volume = volume { d["volume"] = volume }
        if let muted = muted { d["muted"] = muted }
        if let fadeIn = fadeIn { d["fade_in"] = fadeIn }
        if let fadeOut = fadeOut { d["fade_out"] = fadeOut }
        if let duck = duck {
            if let duck = duck { d["duck"] = duck.dictionary } else { d["duck"] = NSNull() }
        }
        if let mono = mono { d["mono"] = mono }
        if let keepPitch = keepPitch { d["keep_pitch"] = keepPitch }
        if let pan = pan { d["pan"] = pan }
        if let compressor = compressor {
            if let compressor = compressor {
                d["compressor"] = compressor.dictionary
            } else {
                d["compressor"] = NSNull()
            }
        }
        if let noiseReduction = noiseReduction { d["noise_reduction"] = noiseReduction }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

/// A sparse patch of text properties. `width` is three-state as well: nil
/// leaves the box alone, `.some(nil)` restores auto-sizing, `.some(w)` fixes
/// the width and wraps.
struct TextPatch: Codable, Equatable {
    var content: String?
    var font: String?
    var size: Double?
    var color: RGBA?
    var align: String?
    var valign: String?
    var lineSpacing: Double?
    var tracking: Double?
    var outline: OutlineProps??
    var backdrop: BackdropProps??
    var width: Double??

    init(
        content: String? = nil, font: String? = nil, size: Double? = nil, color: RGBA? = nil,
        align: String? = nil, valign: String? = nil, lineSpacing: Double? = nil,
        tracking: Double? = nil, outline: OutlineProps?? = nil, backdrop: BackdropProps?? = nil,
        width: Double?? = nil
    ) {
        self.content = content
        self.font = font
        self.size = size
        self.color = color
        self.align = align
        self.valign = valign
        self.lineSpacing = lineSpacing
        self.tracking = tracking
        self.outline = outline
        self.backdrop = backdrop
        self.width = width
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = c.lenient(.content)
        font = c.lenient(.font)
        size = c.lenient(.size)
        color = c.lenient(.color)
        align = c.lenient(.align)
        valign = c.lenient(.valign)
        lineSpacing = c.lenient(.lineSpacing)
        tracking = c.lenient(.tracking)
        outline = c.nullable(.outline)
        backdrop = c.nullable(.backdrop)
        width = c.nullable(.width)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let content = content { d["content"] = content }
        if let font = font { d["font"] = font }
        if let size = size { d["size"] = size }
        if let color = color { d["color"] = color }
        if let align = align { d["align"] = align }
        if let valign = valign { d["valign"] = valign }
        if let lineSpacing = lineSpacing { d["line_spacing"] = lineSpacing }
        if let tracking = tracking { d["tracking"] = tracking }
        if let outline = outline {
            if let outline = outline {
                d["outline"] = outline.dictionary
            } else {
                d["outline"] = NSNull()
            }
        }
        if let backdrop = backdrop {
            if let backdrop = backdrop {
                d["backdrop"] = backdrop.dictionary
            } else {
                d["backdrop"] = NSNull()
            }
        }
        if let width = width {
            if let width = width { d["width"] = width } else { d["width"] = NSNull() }
        }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

/// A sparse patch of shape properties. Not `Codable`: unlike the other
/// three it never appears inside an action's end patch (§5.4 patches cover
/// video, audio and text only).
struct ShapePatch: Equatable {
    var kind: ShapeKind?
    var width: Double?
    var height: Double?
    var stroke: StrokeProps??
    var fill: RGBA??
    var arrowStart: Bool?
    var arrowEnd: Bool?
    var radius: Double?
    var from: [Double]?
    var to: [Double]?

    init(
        kind: ShapeKind? = nil, width: Double? = nil, height: Double? = nil,
        stroke: StrokeProps?? = nil, fill: RGBA?? = nil, arrowStart: Bool? = nil,
        arrowEnd: Bool? = nil, radius: Double? = nil, from: [Double]? = nil, to: [Double]? = nil
    ) {
        self.kind = kind
        self.width = width
        self.height = height
        self.stroke = stroke
        self.fill = fill
        self.arrowStart = arrowStart
        self.arrowEnd = arrowEnd
        self.radius = radius
        self.from = from
        self.to = to
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let kind = kind { d["kind"] = kind.rawValue }
        if let width = width { d["width"] = width }
        if let height = height { d["height"] = height }
        if let stroke = stroke {
            if let stroke = stroke {
                d["stroke"] = stroke.dictionary
            } else {
                d["stroke"] = NSNull()
            }
        }
        if let fill = fill {
            if let fill = fill { d["fill"] = fill } else { d["fill"] = NSNull() }
        }
        if let arrowStart = arrowStart { d["arrow_start"] = arrowStart }
        if let arrowEnd = arrowEnd { d["arrow_end"] = arrowEnd }
        if let radius = radius { d["radius"] = radius }
        if let from = from { d["from"] = from }
        if let to = to { d["to"] = to }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

extension ActionPatch {
    /// The end patch as op JSON. Only the groups that are set appear, and
    /// within them only the set keys, so `set_action_end` merges.
    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let video = video { d["video"] = video.dictionary }
        if let audio = audio { d["audio"] = audio.dictionary }
        if let text = text { d["text"] = text.dictionary }
        return d
    }
}

// MARK: - The compositor's recipe registry

/// The atomic reference the Metal compositor reads on every frame (§7.6).
///
/// AVFoundation instantiates the `AVVideoCompositing` class ITSELF, so it
/// can never be handed a reference to the document — the only channel is
/// something process-wide. Keying by an `Int` rather than using one global
/// slot is what keeps two open documents from cross-reading each other: the
/// key travels in the video composition's instructions.
///
/// Storage is guarded by an `NSLock` because the compositor calls from its
/// own serial queue while the main thread publishes edits. The published
/// value itself needs no protection: a `ReelProject` handle is read-only
/// once published, and an edit produces a NEW handle rather than mutating
/// the old one, so a recipe in flight stays coherent.
final class RecipeSource {
    static let shared = RecipeSource()

    private let lock = NSLock()
    private var projects: [Int: ReelProject] = [:]
    private var nextKey = 1

    private init() {}

    /// A fresh key for a document. `ProjectDocument` holds it for its life
    /// and passes it to `CompositionBuilder`.
    func register() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let key = nextKey
        nextKey += 1
        return key
    }

    /// Drops a document's slot. Call it when the document closes, or the
    /// last handle — and the Rust project behind it — leaks for the life of
    /// the process.
    func unregister(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        projects.removeValue(forKey: key)
    }

    /// Publishes the project the compositor should read from now. Called on
    /// the main thread after every edit, live or not.
    func set(_ project: ReelProject?, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let project = project {
            projects[key] = project
        } else {
            projects.removeValue(forKey: key)
        }
    }

    /// The recipe at `t` for one document. Deliberately does NOT hold the
    /// lock across the FFI call and the JSON decode — only across the
    /// dictionary read — so a slow frame never blocks the main thread's
    /// next publish.
    func recipe(for key: Int, at t: Ticks) -> FrameRecipe? {
        lock.lock()
        let project = projects[key]
        lock.unlock()
        return project?.recipe(at: t)
    }

    /// The handle published under `key`, for the mirrors that sit beside this
    /// one and need something a frame recipe does not carry —
    /// `AudioDSPSource` reads per-clip audio settings off it.
    ///
    /// This is what makes a key ENOUGH. Every caller that builds a
    /// composition publishes the project here first, including the two in
    /// `Exporter` that mint a fresh key of their own, so a mirror handed a
    /// key it has no entry for can still derive its answer from exactly the
    /// project being built instead of guessing at which open document that
    /// key belongs to.
    func project(for key: Int) -> ReelProject? {
        lock.lock()
        defer { lock.unlock() }
        return projects[key]
    }
}

// MARK: - Media files

/// Resolves a media entry to a file URL: the bookmark first (it survives a
/// move or a rename), the stored path as the fallback. NO security scope —
/// the app is not sandboxed (§11), so a resolved URL is usable as is and
/// there is nothing to stop accessing.
///
/// nil means the file is gone: the clip draws a missing slate and Relink…
/// is offered.
func mediaURL(for media: MediaSnapshot) -> URL? {
    if let bookmark = media.bookmark, let data = Data(base64Encoded: bookmark) {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
            bookmarkDataIsStale: &stale),
            FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    guard !media.path.isEmpty, FileManager.default.fileExists(atPath: media.path) else {
        return nil
    }
    return URL(fileURLWithPath: media.path)
}

/// The base64 bookmark the model stores beside a path. nil when the URL
/// cannot be bookmarked (an unreachable volume), which is not an error —
/// the path alone still opens the file today.
func bookmarkString(for url: URL) -> String? {
    let data = try? url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    return data?.base64EncodedString()
}
