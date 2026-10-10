import AppKit

/// The ONLY file in the app that names an `rc_*` symbol. Everything the Rust
/// core can do reaches the rest of Reelcut as typed Swift here: `ReelProject`
/// (a handle plus its lazily decoded `ProjectSnapshot`), `ReelTime`, `ReelColor`,
/// `ReelSnap`, `ReelExport`, the graphics engine's `GraphicLibrary` and
/// `GraphicModule`, `ReelAgentSocket`, and the op ARGUMENTS an edit is built
/// out of — the typed patches. The `dictionary` extensions on the §5.2
/// property types are in `OpDictionaries.swift`, for the same reason: they
/// name no `rc_*` symbol.
/// `ProjectSnapshot.swift` owns the read side of the same contract;
/// `core/include/reelcut_core.h` is the contract itself.
///
/// `ReelOp` and its one static factory per row of the op table are next door
/// in `ReelOps.swift`, the size payment this file owed at 2242 lines, and
/// what an op ANSWERS is in `ReelEdit.swift`, the payment it owed at 1507.
/// The compositor's recipe registry is in `RecipeSource.swift`, the payment
/// it owed at 1440 before road map 10's graphics wrappers, for the same
/// reason: it names no `rc_*` symbol. `MediaDescriptor`, `mediaURL(for:)`
/// and `bookmarkString(for:)` are in `MediaDescriptor.swift`, the payment it
/// owed at 1440 again before the engine's family list, for the same reason.
/// `ShapePatch` is in `ShapePatch.swift` (as `TextPatch` is in
/// `TextPatch.swift`), the payment it owed at 1280 before `ReelColor`. The
/// other typed patches are in `TypedPatches.swift`, the payment it owed at
/// 1211 before `ReelContainer`.
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
    /// string comes from `RecipeOptions.json`, built from two bools, so it is
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

// MARK: - Colour

/// G-12's colour grammar, the core's (spec §11 G-25 (c)): a schema's colour
/// default as the inspector's well reads it, through the same
/// `normalise_color` that stores a `color` prop — no third copy in Swift.
enum ReelColor {
    /// Lowercase `#rrggbb`, or `#rrggbbaa` when not opaque; nil when G-12
    /// refuses `text`.
    static func normalise(_ text: String) -> String? {
        takeString(rc_normalise_color(text))
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
    /// Whether this ENCODING carries an alpha channel — true for `prores_4444`,
    /// `hevc_alpha` and `apng`, and for nothing else the table offers.
    ///
    /// The rows are not alike and `apng`'s is the one to remember beside it:
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
        // False is the safe default: only `prores_4444`, `hevc_alpha` and
        // `apng` answer true, and a core that predates phase 7 does not emit
        // the key at all. Its silence UNDER-reports — that core has no
        // `prores_4444` row to describe, but its `apng` row wrote alpha then as it does
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
    /// "Document size" (or "Document (even)"), "GIF default", "4K"… — the
    /// sheet appends the numbers.
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

// MARK: - Speed limits

/// Every number about a clip's speed, as the core publishes it through
/// `rc_speed_limits` (spec §11 #190): the range `set_speed` clamps to and the
/// reader enforces, and the speed above which the plan leaves a clip's audio
/// out, in both pitch modes. No Swift file types one of these numbers; each
/// reads them here.
struct SpeedLimits: Decodable, Equatable {
    let min: Double
    let max: Double
    let audioMax: Double

    enum CodingKeys: String, CodingKey {
        case min, max
        case audioMax = "audio_max"
    }

    var range: ClosedRange<Double> { min...max }
}

enum ReelSpeed {
    /// Read once from the core. An answer that does not decode is a broken
    /// build, not a state the app can carry on in, so it stops here. A plain
    /// decoder, not `ReelJSON`'s: its snake-case conversion would turn
    /// `audio_max` into a key the explicit `CodingKeys` do not name.
    static let limits: SpeedLimits = {
        guard let json = takeString(rc_speed_limits()),
            let limits = try? JSONDecoder().decode(SpeedLimits.self, from: Data(json.utf8))
        else { preconditionFailure("rc_speed_limits did not answer its documented JSON") }
        return limits
    }()
}

// MARK: - Containers

/// A WebM or Matroska file's index (`RcContainer`, spec §11 #216-R): its
/// first video and audio track and where each frame's bytes lie, which
/// `ContainerRewrap` copies into a movie. `retime` comes before any sample
/// is read; after it, `count` and `sample` may be called from two threads at
/// once (the writer's two pumps), since neither changes the index.
final class ReelContainer {
    static let video = UInt32(RC_CONTAINER_VIDEO)
    static let audio = UInt32(RC_CONTAINER_AUDIO)
    private let handle: OpaquePointer

    /// Opens and indexes the file; throws the core's lowercase reason.
    init(path: String) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        guard let made = rc_container_open(path, &err) else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be read"))
        }
        handle = made
    }

    deinit { rc_container_free(handle) }

    /// The header's describe JSON.
    var describeJSON: String { takeString(rc_container_describe(handle)) ?? "{}" }

    /// Snaps the video to `fps`'s grid when it lies on it; true when it did.
    func retime(_ fps: Fps) -> Bool {
        rc_container_retime(handle, Int64(fps.num), Int64(fps.den))
    }

    /// The copied samples of `track`.
    func count(_ track: UInt32) -> Int {
        Int(clamping: rc_container_sample_count(handle, track))
    }

    /// Sample `index` of `track`, in decode order; nil past the count.
    func sample(_ track: UInt32, at index: Int) -> RcContainerSample? {
        guard index >= 0 else { return nil }
        var out = RcContainerSample()
        return rc_container_sample(handle, track, UInt64(index), &out) ? out : nil
    }
}

// MARK: - LUTs

/// A `.cube` 3D LUT read by the core (`RcCube`, spec §11 GR-8), so the import
/// probe and the compositor read one file the same way.
enum ReelCube {
    /// The largest file the core reads; `MediaImporter.readLUT` reads one
    /// byte more, so a larger file is refused in the core's own sentence.
    static let maxBytes = Int(RC_CUBE_MAX_BYTES)

    /// The file's lattice; throws the core's lowercase sentence.
    static func parse(_ data: Data) throws -> CubeLattice {
        var err: UnsafeMutablePointer<CChar>? = nil
        // An empty file still needs a non-NULL pointer (NULL is the core's
        // "bytes is NULL"), so it lends one byte and passes a length of 0.
        let count = data.count
        let made: OpaquePointer? = (data.isEmpty ? Data([0]) : data).withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return rc_cube_parse(base, count, &err)
        }
        guard let cube = made else {
            throw ReelCoreError(message: takeErrorMessage(err, fallback: "it could not be read"))
        }
        defer { rc_cube_free(cube) }
        let size = Int(rc_cube_size(cube))
        var rgb = [Float](repeating: 0, count: size * size * size * 3)
        let copied = rgb.withUnsafeMutableBufferPointer { out in
            out.baseAddress.map { rc_cube_copy_rgb(cube, $0, out.count) } ?? false
        }
        guard size >= 2, copied else {
            throw ReelCoreError(message: "its table could not be read")
        }
        return CubeLattice(size: size, rgb: rgb)
    }
}

// MARK: - Graphics

/// One `{level, message, line, column, frame}` out of the graphics engine's
/// `diag_out` (road map 10 §5e).
struct GraphicDiagnostic: Decodable, Equatable {
    let level: String
    let message: String
    let line: Int?
    let column: Int?
    let frame: Int?
}

/// A graphic that did not compile, draw or rasterize: the engine's one error.
struct GraphicFailure: Error {
    let diagnostics: [GraphicDiagnostic]
}

/// One drawn frame: premultiplied BGRA rows `stride` bytes apart.
struct GraphicRaster {
    let width: Int
    let height: Int
    let stride: Int
    let bgra: [UInt8]
    let warnings: [GraphicDiagnostic]
}

/// Decodes and frees a `diag_out`. An unreadable one is one error saying so.
private func takeDiagnostics(_ raw: UnsafeMutablePointer<CChar>?) -> [GraphicDiagnostic] {
    guard let text = takeString(raw) else { return [] }
    guard let list = try? JSONDecoder().decode([GraphicDiagnostic].self, from: Data(text.utf8))
    else {
        return [GraphicDiagnostic(
            level: "error", message: "The core's diagnostics could not be read: \(text)",
            line: nil, column: nil, frame: nil)]
    }
    return list
}

/// The engine's fonts and assets (`RcGraphicLibrary`). Filled with
/// `addFont` / `addAsset` until the first compile or rasterize against it
/// FREEZES it; an add after that throws. A module compiled against it keeps
/// its fonts alive, so the two are freed in either order.
final class GraphicLibrary {
    /// The header's `RC_GRAPHIC_MAX_SIDE`, pinned to the engine's `MAX_SIDE`:
    /// a larger side is refused here, before a buffer is allocated for it.
    static let maxSide = Int(RC_GRAPHIC_MAX_SIDE)
    fileprivate let handle: OpaquePointer

    init() { handle = rc_graphic_library_new() }
    deinit { rc_graphic_library_free(handle) }

    func addFont(_ bytes: Data) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        let ok = bytes.withUnsafeBytes { raw in
            rc_graphic_library_add_font(
                handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &err)
        }
        if !ok { throw ReelCoreError(message: takeErrorMessage(err, fallback: "No font added.")) }
    }

    func addAsset(name: String, bytes: Data) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        let ok = bytes.withUnsafeBytes { raw in
            rc_graphic_library_add_asset(
                handle, name, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &err)
        }
        if !ok { throw ReelCoreError(message: takeErrorMessage(err, fallback: "No asset added.")) }
    }

    /// The engine's own family names, sorted — the exact strings a
    /// `font-family` must match. FREEZES the library, as a compile would.
    func families() -> [String] {
        guard let json = takeString(rc_graphic_library_families(handle)) else { return [] }
        return ReelJSON.decode([String].self, from: json) ?? []
    }

    /// `svg` drawn at `width`×`height`, rows `width × 4` bytes apart.
    func rasterize(_ svg: String, width: Int, height: Int) throws -> GraphicRaster {
        let sides = 0...Self.maxSide
        guard sides.contains(width), sides.contains(height) else {
            throw GraphicFailure(diagnostics: [GraphicDiagnostic(
                level: "error", message: "\(width)×\(height) is outside 0…\(Self.maxSide)",
                line: nil, column: nil, frame: nil)])
        }
        let stride = width * 4
        var bgra = [UInt8](repeating: 0, count: max(height * stride, 1))
        var diag: UnsafeMutablePointer<CChar>? = nil
        let ok = bgra.withUnsafeMutableBufferPointer { out in
            rc_graphic_rasterize(
                handle, svg, UInt32(width), UInt32(height), out.baseAddress, stride, &diag)
        }
        let diagnostics = takeDiagnostics(diag)
        guard ok else { throw GraphicFailure(diagnostics: diagnostics) }
        return GraphicRaster(
            width: width, height: height, stride: stride, bgra: bgra, warnings: diagnostics)
    }
}

/// One compiled graphic module (`RcGraphic`). Holds its library strongly.
final class GraphicModule {
    let library: GraphicLibrary
    private let handle: OpaquePointer

    private init(library: GraphicLibrary, handle: OpaquePointer) {
        self.library = library
        self.handle = handle
    }

    deinit { rc_graphic_free(handle) }

    static func compile(
        library: GraphicLibrary, name: String, source: String, budgetMs: Int
    ) throws -> GraphicModule {
        var diag: UnsafeMutablePointer<CChar>? = nil
        let made = rc_graphic_compile(
            library.handle, name, source, UInt32(clamping: budgetMs), &diag)
        let diagnostics = takeDiagnostics(diag)
        guard let handle = made else { throw GraphicFailure(diagnostics: diagnostics) }
        return GraphicModule(library: library, handle: handle)
    }

    /// `{"meta":…,"schema":…,"revision":…,"warnings":[…]}`, the schema in the module's order.
    func describeJSON() -> String {
        takeString(rc_graphic_describe(handle)) ?? "{}"
    }

    func svg(
        frame: Int, propsJSON: String, ctxJSON: String, budgetMs: Int
    ) throws -> (svg: String, warnings: [GraphicDiagnostic]) {
        var diag: UnsafeMutablePointer<CChar>? = nil
        let out = rc_graphic_svg(
            handle, Int64(frame), propsJSON, ctxJSON, UInt32(clamping: budgetMs), &diag)
        let diagnostics = takeDiagnostics(diag)
        guard let svg = takeString(out) else { throw GraphicFailure(diagnostics: diagnostics) }
        return (svg, diagnostics)
    }
}

// MARK: - The agent socket

/// The core's Unix-socket listener for the agent server (road map 14, spec
/// §11 MC-1), the only listener since MC4 deleted the TCP one, serving the
/// catalog through `AgentServer`'s handler. Only the wrapper
/// lives here, for the one-file rule above; the path, the MC-2 policy and
/// the log lines are `AgentServer+Socket.swift`'s.
enum ReelAgentSocket {
    /// Binds at `path`, chmod 0600; throws the core's sentence. Never
    /// unlinks a file already there, and a second bind in one process is
    /// refused. `handler` and `context` must stay valid for the process's
    /// life, because `release()` never joins.
    static func start(
        path: String, serverName: String, version: String, toolsJSON: String,
        handler: RcAgentToolHandler, context: UnsafeMutableRawPointer?
    ) throws {
        var err: UnsafeMutablePointer<CChar>? = nil
        let bound = rc_agent_socket_start(
            path, serverName, version, toolsJSON, handler, context, &err)
        if !bound {
            throw ReelCoreError(
                message: takeErrorMessage(err, fallback: "could not bind the agent socket"))
        }
    }

    /// For quit: unlinks the socket file only if it is still this
    /// listener's, then abandons the listener without a join. Safe when
    /// none is bound.
    static func release() {
        rc_agent_socket_release()
    }
}
