import AppKit

/// With its `ReelCore+<Area>.swift` files, the ONLY files in the app that name
/// an `rc_*` symbol (spec §11 CJ-8 (l)); a new wrapper goes in the file of its
/// area. Everything the Rust core can do reaches the rest of Frame Job as typed
/// Swift in them. This file holds `ReelProject` (a handle plus its lazily
/// decoded `ProjectSnapshot`), `ReelSnap`, `ReelTime`, `ReelColor`, `ReelExport`,
/// `ReelSpeed`, the op table read back and `ReelAgentSocket`;
/// `ReelCore+MediaFiles.swift` holds `ReelContainer`, `ReelCube`, `ReelHDR10`,
/// `ReelAV1` and `ReelWebM`, and `ReelCore+Graphics.swift` the graphics
/// engine's `GraphicLibrary`, `GraphicModule` and `ReelGraphicPackage`. The
/// `dictionary` extensions on the §5.2 property types are in
/// `OpDictionaries.swift`, because they name no `rc_*` symbol.
/// `ProjectSnapshot.swift` owns the read side of the same contract;
/// `core/include/framejob_core.h` is the contract itself.
///
/// Where each earlier size payment went, and why, is the `ReelCore.swift`
/// entry of `designs/adr/app-file-history.md`.
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

/// Consumes a Rust-allocated error string and returns its contents.
func takeErrorMessage(_ err: UnsafeMutablePointer<CChar>?, fallback: String) -> String {
    guard let err = err else { return fallback }
    defer { rc_string_free(err) }
    return String(cString: err)
}

/// Consumes any Rust-allocated string and returns its contents. Every
/// `char *` this library hands back MUST come through here — the core
/// allocated it, only `rc_string_free` may release it.
func takeString(_ s: UnsafeMutablePointer<CChar>?) -> String? {
    guard let s = s else { return nil }
    defer { rc_string_free(s) }
    return String(cString: s)
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
    private var memoSourceMaps: [UInt32: SourceMap?] = [:]

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
        CoreJSON.value(takeString(rc_project_clip_state(ptr, clip, t))) as? [String: Any]
    }

    /// A media clip's source map (spec §11 SR-20): its `ramped` flag and the
    /// core's own [clip tick, source tick] pairs, decoded and checked ONCE
    /// per handle and clip, so a reader per pixel or per bucket never pays
    /// for the check. nil for an unknown id, a clip that is not a media
    /// clip, one whose media is gone, or a map that fails `SourceMap`'s check.
    func sourceMap(_ clip: UInt32) -> SourceMap? {
        lock.lock()
        defer { lock.unlock() }
        if let memo = memoSourceMaps[clip] { return memo }
        let decoded = takeString(rc_project_source_map(ptr, clip)).flatMap(SourceMap.init(json:))
        memoSourceMaps[clip] = .some(decoded)
        return decoded
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
            raw = rc_project_snap_candidates(ptr, CoreJSON.array(clips))
        }
        guard let o = CoreJSON.value(takeString(raw)) else { return [] }
        return CoreJSON.snapTicks(o)
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
        let resolved = rc_snap_resolve(CoreJSON.array(candidates), t, threshold, &snapped)
        return (resolved, snapped)
    }
}

// MARK: - Time

/// Ticks, frames and timecode. Formatting and parsing are the core's so the
/// toolbar, the ruler, the inspector and the agent all spell a time the same
/// way (§4.1).
enum ReelTime {
    /// Rounds `t` to the nearest frame boundary. Every tick value that reaches
    /// an op goes through here first, except the audio ramps' lengths, kept off
    /// the grid (core/CLAUDE.md Times, §11 #355); no other sub-frame time is stored.
    static func snapToFrame(_ t: Ticks, fps: Fps) -> Ticks {
        guard let rate = fps.ffiPair else { return t }
        return rc_time_snap_to_frame(t, rate.num, rate.den)
    }

    /// Timecode: "HH:MM:SS:FF" when `frames` (non-drop at an NTSC rate, real
    /// seconds at any other fractional rate, spec §11 #532), else "HH:MM:SS.mmm".
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
        return try ExportSize.list(json)
    }

    /// Resolves `preset` plus optional `overrides` (size, fps, range, the two
    /// bitrates the Quality popup writes and the two loudness figures its
    /// Loudness popup does) against the project. Throws with the core's
    /// message for an unknown preset or bad overrides, so the sheet can show
    /// it verbatim — a depth on a row without one, `audio_bits` (spec §11
    /// AU-29), among them; a `peak_dbtp` alone is the master's ceiling and
    /// resolves (AU-27; `export_overrides.rs`).
    static func settings(
        _ p: ReelProject, preset: String, overrides: [String: Any]? = nil
    ) throws -> ExportSettings {
        let overridesJSON = try CoreJSON.overrides(overrides)
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
        return try ExportSettings.decoded(json)
    }
}

// MARK: - The op table, read back

extension ReelOp {
    /// Every op's arguments as JSON Schema, keyed by op name (`coreNames()`'s names):
    /// `rc_op_schemas`, the core's `OP_TABLE` projected by `op_schema.rs`. Empty means the
    /// core failed, and a caller refuses to build on it.
    static func coreSchemas() -> [String: ReelOpSchema] {
        guard let json = takeString(rc_op_schemas()) else { return [:] }
        return ReelOpSchema.table(from: json)
    }

    /// Every op name the core accepts, in its table's order: `rc_op_names` (`OP_NAMES`).
    /// Empty means the core failed.
    static func coreNames() -> [String] {
        guard let json = takeString(rc_op_names()) else { return [] }
        return ReelJSON.decode([String].self, from: json) ?? []
    }
}

// MARK: - Speed limits

enum ReelSpeed {
    /// Read once from the core (`SpeedLimits.decoded` says why it traps).
    static let limits = SpeedLimits.decoded(takeString(rc_speed_limits()))
}

// MARK: - The agent socket

/// The core's agent-socket listener (spec §11 MC-1); its policy is `AgentServer+Socket.swift`'s.
enum ReelAgentSocket {
    /// Binds at `path`, chmod 0600, or throws the core's sentence (a file already there is
    /// never unlinked; a second bind is refused); `handler` and `context` stay valid for the
    /// process's life.
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

    /// For quit: unlinks this listener's own socket file and abandons it, unjoined; safe
    /// when none is bound.
    static func release() {
        rc_agent_socket_release()
    }

    /// `text` handed back to the core as the tool handler's answer, `rc_agent_string_create`;
    /// the core frees it.
    static func answer(_ text: String) -> UnsafeMutablePointer<CChar>? {
        text.withCString { rc_agent_string_create($0) }
    }
}
