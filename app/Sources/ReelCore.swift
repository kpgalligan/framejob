import AppKit

/// The ONLY file in the app that names an `rc_*` symbol. Everything the Rust
/// core can do reaches the rest of Reelcut as typed Swift here: `ReelProject`
/// (a handle plus its lazily decoded `ProjectSnapshot`), `ReelTime`,
/// `ReelSnap` and `ReelExport`, and the op ARGUMENTS an edit
/// is built out of — `MediaDescriptor`, the `dictionary` extensions on the
/// §5.2 property types, and the typed patches.
/// `ProjectSnapshot.swift` owns the read side of the same contract;
/// `core/include/reelcut_core.h` is the contract itself.
///
/// `ReelOp` and its one static factory per row of the op table are next door
/// in `ReelOps.swift`, the size payment this file owed at 2242 lines, and
/// what an op ANSWERS is in `ReelEdit.swift`, the payment it owed at 1507.
/// The compositor's recipe registry is in `RecipeSource.swift`, the payment
/// it owed at 1440 before road map 10's graphics wrappers, for the same
/// reason: it names no `rc_*` symbol.
/// Only `ReelOp.coreNames()` and `ReelOp.coreSchemas()` stayed behind — the
/// op table read BACK, its names and its arguments — because they read
/// `rc_op_names()` and `rc_op_schemas()` and the rule above admits no second
/// file.
///
/// Three conventions carried from Rasterize's `RasterCore.swift`:
///
///  - A handle is IMMUTABLE. Every edit returns a NEW handle, which is why
///    undo in `ProjectDocument` is a stack of these objects and why sharing
///    one across threads is safe.
///  - `deinit` frees the Rust allocation, and every `char *` the library
///    returns goes through `takeString` / `takeErrorMessage`, which free it.
///  - `rc_project_apply` returning NULL means three things — see
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

// MARK: - Recipe options

/// What a caller wants of a frame recipe BESIDES the time — the Swift side
/// of `rc_project_frame_recipe_opts` and of the core's `RecipeOptions`
/// (spec §7.3, road map 2's phase 7).
///
/// **Why an option lives here and not in the export overrides.** It changes
/// the PICTURE, so it travels with the description of the picture. The
/// override table (`export_overrides.rs`) ignores a key it does not know, on
/// purpose, so a newer UI still gets an export — which means an option posted
/// that way would vanish without a word and the export would report success
/// on a file it had not changed.
///
/// Nothing here is persisted. These are a question asked of a project, not a
/// property of one, so no format version moves when an option is added.
///
/// The default is every option OFF, and that is load-bearing: `none` takes
/// the plain `rc_project_frame_recipe` path, so a caller that says nothing
/// gets byte for byte the recipe it got before this type existed.
struct RecipeOptions: Equatable {
    /// Append a text layer showing the project timecode at `t` — last in the
    /// layer list, so topmost. The core builds it (`recipe_text.rs`); this
    /// side only asks.
    var burnInTimecode: Bool = false

    /// Every option off: the recipe as it has always been.
    static let none = RecipeOptions()

    /// The core's `opts_json`, or nil for "ask the un-optioned export".
    ///
    /// Spelled by hand rather than encoded. There is one key and it is a
    /// bool, a recipe is asked for once per composed frame, and
    /// `JSONSerialization` would allocate a dictionary and a `Data` for a
    /// twenty-five-byte constant. The key name is written once, here, and is
    /// the only place in the app that has to match the header's
    /// `{"burn_in_timecode": bool}`.
    ///
    /// A nil is not a failure — it is the argument `rc_project_frame_recipe`
    /// itself passes, and the core documents the two exports as one
    /// implementation.
    var json: String? {
        burnInTimecode ? "{\"burn_in_timecode\":true}" : nil
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

    /// The project INSIDE nest `id` — its tracks and clips at the top level,
    /// its frozen size as the canvas, this document's rate, media, nests and
    /// next id, and no markers (`core/src/scope.rs`, spec §7.4).
    ///
    /// **The READ half of a scope, and the reason the whole feature is
    /// possible.** An edit inside a nest goes to THIS handle with the op
    /// carrying `scope` (`ReelOp.scoped(_:)`), and what comes back is a whole
    /// parent project, so undo is still a stack of parent handles. But the
    /// timeline, the canvas, the player and every snapshot read need a
    /// project whose top level IS the nest, and that is this. The core builds
    /// both out of one function, so what the app draws and what its edits
    /// land in cannot drift apart — a second view builder on this side would
    /// be exactly that drift.
    ///
    /// The answer is an ordinary immutable handle, memoised the same way, and
    /// **it is for reading**. Applying an op to it would edit the VIEW and
    /// throw the parent away; nothing enforces that, and
    /// `ProjectDocument.editedProject` is the one place it is held.
    /// The exception is a PROBE — `applying` on a scoped handle with plain
    /// ops is how a gesture learns the ids the core is about to mint inside a
    /// nest, and it is legitimate for the reason every probe is: the result
    /// is dropped (`EditorViewController+Timeline.swift`).
    ///
    /// nil for a nest id this project has not got. The core's message
    /// (`no nest with id N`) is dropped rather than thrown, because every
    /// caller here is a VIEW asking about view state it has already clamped
    /// — `ProjectDocument.clampViewState` clears a scope whose nest is gone
    /// before anything reads one — so a nil is a race with an undo, not a
    /// user-facing failure, and it falls back to the parent.
    func scoped(_ id: UInt32) -> ReelProject? {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let handle = rc_project_scoped(ptr, id, &err) else {
            _ = takeErrorMessage(err, fallback: "")
            return nil
        }
        return ReelProject(owning: handle)
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
    ///
    /// `options` is what the caller wants BESIDES the time (`RecipeOptions`);
    /// its default asks exactly what this method asked before phase 7.
    func recipe(at t: Ticks, options: RecipeOptions = .none) -> FrameRecipe? {
        recipeJSON(at: t, options: options)
            .flatMap { ReelJSON.decode(FrameRecipe.self, from: $0) }
    }

    /// The same recipe as raw JSON, for the agent's `render_frame` reply and
    /// for debugging a composited frame.
    ///
    /// **Why there are two exports and this picks between them.** The core
    /// documents `rc_project_frame_recipe` as `rc_project_frame_recipe_opts`
    /// with the defaults — one implementation, so the two cannot drift — and
    /// this takes the plain one when there is nothing to ask, because then
    /// the un-optioned path stays byte-identical to the shipped one BY
    /// CONSTRUCTION rather than by a core test alone, and no string is built
    /// per composed frame.
    ///
    /// **What a nil means, and what it does not.** The query exports carry no
    /// `err_out` — a query has nothing to report but its answer — so an
    /// `opts_json` the core cannot parse comes back as NULL, indistinguishable
    /// from a NULL project. That is not a hazard this side can reach: the
    /// string comes from `RecipeOptions.json`, which is a constant, so it is
    /// always parseable. A nil here therefore keeps the meaning it has always
    /// had — the core had nothing to say — and every caller already handles
    /// it: `Compositor` renders the canvas background (a frame past the end
    /// takes the same path) and `render_frame` refuses. Do NOT add a
    /// fallback to the un-optioned export for a nil: it would turn a
    /// mis-spelled option into a silently un-burnt frame, which is the exact
    /// failure this whole option travels through the recipe to avoid.
    func recipeJSON(at t: Ticks, options: RecipeOptions = .none) -> String? {
        guard let opts = options.json else {
            return takeString(rc_project_frame_recipe(ptr, t))
        }
        return takeString(rc_project_frame_recipe_opts(ptr, t, opts))
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

    /// Applies one op and returns what the core answered — `ReelEdit`, next
    /// door, says what each of its three arms means and which one is an undo
    /// step. Throws when the op or its ARGUMENTS are invalid, with the core's
    /// own message: that is the fourth answer, and the only one that is about
    /// the request rather than about the project.
    func applying(_ op: ReelOp) throws -> ReelEdit {
        var err: UnsafeMutablePointer<CChar>? = nil
        var reason: UnsafeMutablePointer<CChar>? = nil
        guard let handle = rc_project_apply(ptr, op.json, &err, &reason) else {
            // The header's three NULLs, read in its order. The two channels
            // are never both written, and either is freed by being read.
            if let why = takeString(reason) {
                return .refused(ReelRefusal(op: op.name, reason: why))
            }
            guard err == nil else {
                throw ReelCoreError(
                    message: takeErrorMessage(err, fallback: "The edit could not be applied."))
            }
            return .identity
        }
        return .applied(ReelProject(owning: handle))
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
    /// The integrated loudness target the written file is normalised to, in
    /// LUFS (`export_overrides.rs`'s `loudness_lufs`, −70…0), or nil for "do
    /// not normalise" — which is what an ABSENT key means, the same rule the
    /// two bitrates follow. The export sheet's Loudness popup and the
    /// `export` tool are the two callers that set it.
    let loudnessLufs: Double?
    /// The true-peak ceiling the normalising gain is capped against, in dBTP
    /// (`peak_dbtp`, −20…0). The core refuses one with no `loudnessLufs`
    /// beside it, so this is nil whenever that is; nil WITH a target is a
    /// script's "no ceiling but full scale", and `ExportLoudness.resolve`
    /// supplies 0 dBTP for it.
    let peakDbtp: Double?
    /// Whether this ENCODING carries an alpha channel — true for
    /// `prores_4444` and `apng`, and for nothing else the table offers.
    ///
    /// The two rows are not alike and the second one is the one to remember:
    /// `gif` is FALSE though a GIF can show a transparent pixel, because one
    /// palette index is not a channel and nothing partial survives it, where
    /// APNG carries a real fourth channel (`export_table.rs`'s field doc is
    /// where that argument lives, and the header repeats it). A reader who
    /// takes this for `prores_4444` alone reads the export sheet's footnote
    /// and the Document tab's note as bugs — which is what the phase's own
    /// review found this sentence doing.
    ///
    /// **It is a capability of the row, NOT a statement about the project**,
    /// and the obvious reading of the name is the wrong one. `export_settings`
    /// resolves one flat object for every row alike, so a flag derived from
    /// the canvas background would report `alpha: true` on an H.264, a GIF
    /// and a WAV, none of which can hold one. It follows `audio`'s own
    /// precedent in `export_table.rs`: "a fact about the CONTAINER rather
    /// than a decision about the project". A translucent canvas is a
    /// separate, orthogonal fact, and what this answers is whether the file
    /// would keep it.
    let alpha: Bool

    /// Spelled out rather than synthesized because two keys do not follow
    /// from the property names: the core nests the resolved range under
    /// `range` (`export.rs`), and its preset name is `avf_preset`, which
    /// `.convertFromSnakeCase` turns into `avfPreset`. Decoding those as
    /// `start` / `duration` / `avPreset` silently produced a zero-length
    /// range — which disabled the export sheet's Export button and made the
    /// agent's `export` report `"duration": 0` — and threw the core's
    /// AVFoundation preset away.
    ///
    /// The two loudness keys are NOT of that kind: `loudness_lufs` and
    /// `peak_dbtp` convert to `loudnessLufs` and `peakDbtp` on their own.
    /// They are listed for the reason every other well-behaved key is —
    /// a `CodingKeys` enum is exhaustive, and a case left out is a field
    /// that silently decodes as nil. `alpha` (phase 7) is the newest of
    /// those, and it decodes as FALSE when left out, which would have read
    /// as "no row can carry alpha" — a defect that looks like a working
    /// build.
    ///
    /// **Two keys the core emits are still absent, deliberately: `audio` and
    /// `video`.** Nothing decodes them, so adding cases would add two stored
    /// properties no reader consults; `isAudioOnly` answers the same question
    /// from `avPreset` and the container and predates both. `alpha` is the
    /// first of the three anything actually reads, which is why it is the
    /// only one here. A future reader of `audio` or `video` adds the case —
    /// it does not infer the answer from this list's silence.
    private enum CodingKeys: String, CodingKey {
        case preset, container, codec, width, height, fps, range
        case avPreset = "avfPreset"
        case fileType, optimizeForNetwork, videoBitrate, audioBitrate
        case loudnessLufs, peakDbtp, alpha
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
        loudnessLufs = c.lenient(.loudnessLufs)
        peakDbtp = c.lenient(.peakDbtp)
        // False is the safe default: only `prores_4444` and `apng` answer
        // true, and a core that predates phase 7 does not emit the key at
        // all. Its silence UNDER-reports — that core has no `prores_4444`
        // row to describe, but its `apng` row wrote alpha then as it does
        // now — and under-reporting is the direction that cannot hurt: this
        // key only ADDS the footnote's "alpha" and ARMS
        // `ExportWriter.checkAlphaSurvivesTheSize`, so false promises less
        // than the file holds where true would promise more.
        alpha = c.lenient(.alpha, false)
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

    /// Resolves `preset` plus optional `overrides` (size, fps, range, the two
    /// bitrates the Quality popup writes and the two loudness figures its
    /// Loudness popup does) against the project. Throws with the core's
    /// message for an unknown preset or bad overrides, so the sheet can show
    /// it verbatim — including the one PAIRING rule among them, that a
    /// `peak_dbtp` with no `loudness_lufs` is refused rather than accepted
    /// and left inert (`export_overrides.rs`).
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

// MARK: - The op table, read back

extension ReelOp {
    /// Every op's arguments as JSON Schema, keyed by op name — `OP_TABLE`
    /// in `core/src/op_table.rs`, projected by `core/src/op_schema.rs` and
    /// read through the FFI rather than restated in Swift, which is the
    /// whole point of the export: the catalog can print what the core
    /// accepts instead of keeping a hand copy that can be wrong about a
    /// type, a vocabulary or a required list and still pass every part of
    /// the startup parity check.
    ///
    /// The keys are `coreNames()`'s names, and neither list is derived from
    /// the other on this side: they are two views of one table in the core.
    ///
    /// Empty only if the core failed or its answer could not be read, which
    /// it does not — and an empty answer is a catastrophe rather than "no
    /// arguments", so a caller treats it the way `AgentCatalog` already
    /// treats an empty `coreNames()`: it refuses to build on one.
    ///
    /// The second member of `ReelOp` that did NOT go to `ReelOps.swift`,
    /// for `coreNames()`'s reason: it names an `rc_*` symbol, and this file
    /// is the only one that may.
    static func coreSchemas() -> [String: ReelOpSchema] {
        guard let json = takeString(rc_op_schemas()),
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let map = object as? [String: Any]
        else { return [:] }
        var schemas: [String: ReelOpSchema] = [:]
        for (name, value) in map {
            // A row that is not an object is dropped rather than defaulted:
            // the op then has no schema at all, which the caller's own
            // check can see, where an empty one would look like an op that
            // takes nothing.
            guard let schema = value as? [String: Any] else { continue }
            schemas[name] = ReelOpSchema(
                properties: schema["properties"] as? [String: Any] ?? [:],
                required: schema["required"] as? [String] ?? [])
        }
        return schemas
    }

    /// Every op name the core accepts, in the order of its table
    /// (`OP_NAMES` in `core/src/edit.rs`), read through the FFI rather than
    /// copied into Swift: a copy is one more spelling to drift, and its one
    /// reader — `AgentCatalog.opNames`, which three things share — is there
    /// to catch it. Empty only if the core failed, which it does not.
    ///
    /// The first member of `ReelOp` that did NOT go to `ReelOps.swift` with
    /// the struct and its factories: it names an `rc_*` symbol, and this
    /// file is the only one that may. `coreSchemas()` above stayed for the
    /// same rule.
    static func coreNames() -> [String] {
        guard let json = takeString(rc_op_names()) else { return [] }
        return ReelJSON.decode([String].self, from: json) ?? []
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
/// `ReelCore.swift` and `ReelOps.swift` ever writes an op argument.
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

extension ObscureProps {
    var dictionary: [String: Any] {
        [
            "shape": shape.rawValue, "x": x, "y": y, "width": width, "height": height,
            "feather": feather, "kind": kind.rawValue, "amount": amount,
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

extension TextAnimation {
    /// `in` and `out` are DURATIONS in ticks, not times, and the first of them
    /// is a Swift keyword — which is why the Swift properties are
    /// `inDuration` / `outDuration` and the model's key names are written out
    /// here. The spelling is a contract with `core/src/model_props.rs`'s
    /// `#[serde(rename = "in")]`, the same one `TextAnimation.CodingKeys`
    /// keeps on the way back.
    var dictionary: [String: Any] {
        ["kind": kind.rawValue, "in": inDuration, "out": outDuration]
    }
}

extension StrokeProps {
    var dictionary: [String: Any] { ["width": width, "color": color] }
}

extension GradientStop {
    var dictionary: [String: Any] { ["at": at, "color": color] }
}

extension Gradient {
    /// The stops go out in the order they are HELD, not `sortedStops` — the
    /// model does not police the order and the renderer sorts on the way to
    /// `CGGradient`, so sorting here would silently rewrite a list the user
    /// is in the middle of dragging through and make a stop jump back under
    /// the pointer.
    var dictionary: [String: Any] {
        ["kind": kind.rawValue, "stops": stops.map { $0.dictionary }, "angle": angle]
    }
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
///
/// **`obscure` is a single optional for exactly the same reason** (phase 3c):
/// `VideoProps.obscure` is a `Vec<ObscureRegion>` with no null form either,
/// so `nil` leaves the regions alone, `[]` clears them, and adding, removing
/// or re-ordering a region is one whole-array `set_video`. A second rule for
/// the second list would be a rule to remember; there is one rule, and it is
/// "a list is replaced whole".
///
/// **`blend` is a single optional too** (phase 6). `VideoProps.blend` is a
/// plain `BlendMode` with no null form — `.normal` is how a blend is cleared
/// — so nothing here needs the third state, and a `BlendMode??` read through
/// `nullable` would be worse than unnecessary: a value it could not read
/// would decode to `.some(nil)` and reach the core as an explicit null the
/// caller never wrote, which on a field that DOES take one is a silent clear
/// — the gap app/CLAUDE.md records against the ten `T??` patch fields.
///
/// **What used to hang on that choice no longer does** (deepening D1). The
/// pairing with `lenient` was once load-bearing for a misspelt MODE, because
/// the agent door decoded a caller's patch through this type. Nothing a
/// caller wrote is decoded through these types now — they are the APP's
/// writers, built from controls that cannot misspell anything — and the core
/// answers a typo at every door.
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
    var obscure: [ObscureProps]?
    var blend: BlendMode?
    /// **`motion` is a `T??` like the four object-valued fields above, and
    /// since D1·3 no agent's patch reaches it** (format version 8): the MCP
    /// door forwards the caller's object to the core unread, where
    /// `patch.rs` walks a motion's two levels of nested objects and refuses a
    /// misspelt key or kind by its dotted path. This type is the APP's
    /// writer now — the inspector's Motion section and Clip ▸ Motion ▸ — so
    /// it has no gap in the `T??` family app/CLAUDE.md records because
    /// nothing a caller wrote is decoded through it. `.some(nil)` AND
    /// `.some(an empty MotionProps)` both write `NSNull`, since the core
    /// normalises an all-`None` motion to `None` anyway.
    var motion: MotionProps??

    init(
        x: Double? = nil, y: Double? = nil, scale: Double? = nil, rotation: Double? = nil,
        opacity: Double? = nil, crop: CropInsets? = nil, cornerRadius: Double? = nil,
        shadow: ShadowProps?? = nil, color: ColorAdjust? = nil, chroma: ChromaProps?? = nil,
        filters: [FilterProps]? = nil, reflection: ReflectionProps?? = nil,
        spotlight: SpotlightProps?? = nil, obscure: [ObscureProps]? = nil,
        blend: BlendMode? = nil, motion: MotionProps?? = nil
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
        self.obscure = obscure
        self.blend = blend
        self.motion = motion
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
        obscure = c.lenient(.obscure)
        // `lenient`, never `nullable` — the struct doc says what that buys.
        blend = c.lenient(.blend)
        // `nullable`, because a motion HAS a null form. Since D1·3 nothing
        // decodes an agent's `motion` through this initialiser at all — the
        // caller's object goes to the core unread — so the gap the other
        // `T??` fields carry does not arise here either.
        motion = c.nullable(.motion)
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
        if let obscure = obscure { d["obscure"] = obscure.map { $0.dictionary } }
        if let blend = blend { d["blend"] = blend.rawValue }
        if let motion = motion {
            if let motion = motion, !motion.isEmpty {
                d["motion"] = motion.dictionary
            } else {
                d["motion"] = NSNull()
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

/// A sparse patch of shape properties. Not `Codable`: unlike the other
/// three it never appears inside an action's end patch (§5.4 patches cover
/// video, audio and text only).
///
/// **`gradient` is a three-state double optional**, `stroke` and `fill`'s
/// shape (phase 6): the model field is an `Option<Gradient>`, so `nil`
/// leaves it alone, `.some(nil)` sends the explicit null that CLEARS it —
/// which is the inspector's Reset, and the exact inverse of setting one,
/// since a gradient never clears the `fill` underneath it — and
/// `.some(value)` sets it.
///
/// It is a nested object, so the core MERGES it key by key into a stored
/// one (§5.2). The writers here still send the whole gradient, and the
/// reason is the OTHER case: a stored `null` is not an object, so turning a
/// gradient on replaces the null with what the patch carries and the keys
/// left out come from `Gradient::default()`. A section that knows every key
/// is right whichever of the two a clip is in. Since deepening D1·4 a key
/// misspelt inside a gradient is refused by the CORE, by its dotted path
/// with the stop's index in it, at this door and every other.
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
    var gradient: Gradient??

    init(
        kind: ShapeKind? = nil, width: Double? = nil, height: Double? = nil,
        stroke: StrokeProps?? = nil, fill: RGBA?? = nil, arrowStart: Bool? = nil,
        arrowEnd: Bool? = nil, radius: Double? = nil, from: [Double]? = nil,
        to: [Double]? = nil, gradient: Gradient?? = nil
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
        self.gradient = gradient
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
        if let gradient = gradient {
            if let gradient = gradient {
                d["gradient"] = gradient.dictionary
            } else {
                d["gradient"] = NSNull()
            }
        }
        return d
    }

    var isEmpty: Bool { dictionary.isEmpty }
}

/// A patch of a clip's IDENTITY — `set_clip`'s argument. Both keys are
/// three-state, exactly as `TextPatch.width` is: nil leaves the field
/// alone, `.some(nil)` sends an explicit JSON null (the fallback name comes
/// back, or the label goes), `.some(value)` sets it. The core trims a name
/// and clears on an empty one, so a field's raw text may be sent as it is.
///
/// A label is a colour NAME from `ClipLabel`'s vocabulary. The core stores
/// it unvalidated — the `Marker.color` policy — so the builder does not
/// check it either; `ClipLabel.color(named:)` absorbs a name this build
/// does not know.
///
/// A WRITER only — `Equatable`, not `Codable`, `ShapePatch`'s shape. Its
/// lenient `init(from:)` read the agent door's `set_clip` argument until
/// D1·4 sent that argument to the core unread, and D1·6 deleted it rather
/// than leave a lenient reading of a caller's object in the tree.
struct ClipPatch: Equatable {
    var name: String??
    var label: String??

    init(name: String?? = nil, label: String?? = nil) {
        self.name = name
        self.label = label
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let name = name {
            if let name = name { d["name"] = name } else { d["name"] = NSNull() }
        }
        if let label = label {
            if let label = label { d["label"] = label } else { d["label"] = NSNull() }
        }
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
