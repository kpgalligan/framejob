import Foundation

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
/// the old one, so a recipe in flight stays coherent. `RecipeOptions` is a
/// value type of two words, so the same sentence covers it.
final class RecipeSource {
    static let shared = RecipeSource()

    private let lock = NSLock()
    private var projects: [Int: ReelProject] = [:]
    /// What each key wants of its recipes besides the time (phase 7).
    ///
    /// **Keyed the same way as the project and stored SEPARATELY from it, on
    /// purpose.** Options describe the ASK, not the project: a document
    /// republishes a new handle after every edit, and an export or an
    /// offline frame that asked for a burn-in must keep getting one across
    /// that. An absent entry is `RecipeOptions.none`, so a key nobody set
    /// options on answers exactly what it answered before this dictionary
    /// existed. A document's key asks only for `ungraded`, while View ▸ Show
    /// Ungraded is on (spec §11 GR-4), and `dynamicRange` `.sdr`, while View ▸
    /// Show SDR Version is (HD-14 (g)); `Exporter` mints keys of its own for an
    /// export and for an offline frame, which is why the switch never reaches
    /// them — never copy a document key's options onto one.
    private var options: [Int: RecipeOptions] = [:]
    /// Media id → file, as each document last published it (spec §11 GR-8):
    /// where a LUT look's `.cube` is read. The preview's composition keeps
    /// the URL map it was BUILT with (`RecipeInstruction.mediaURLs`), and
    /// adding, applying or relinking a LUT changes neither the plan nor the
    /// DSP, so no rebuild follows (`Playback.update`); a look therefore reads
    /// its URLs here. A key that never publishes — an export's or an offline
    /// frame's fresh one — falls back to its instruction's map, which was
    /// built from the project that key renders.
    private var mediaURLs: [Int: [UInt32: URL]] = [:]
    /// Media id → cursor file, as each key last published it (spec §11 CU-37): a document's
    /// from `setMediaURLs`, an export's or an offline frame's from `Exporter.waitForCursors`.
    /// A key that never publishes any — a thumbnail's, an analysis' — draws no cursor.
    private var cursorFiles: [Int: [UInt32: CursorFile]] = [:]
    /// What `cursorFiles` was resolved from, per key: each cursor media's record, duration and
    /// rate. The files are resolved again (bookmarks read) only when this changes.
    private var cursorSources: [Int: [UInt32: CursorSource]] = [:]
    /// The tracks each key last wanted of `CursorTracks`, so an edit that changes none wants
    /// nothing again.
    private var cursorWants: [Int: [CursorTrackRequest]] = [:]
    /// The keys that ever wanted a track: the owners `unregister` releases.
    private var cursorOwners = Set<Int>()
    /// The keys whose frames are delivered deeper than 8 bits (spec §11 PR-16): an export's
    /// for a row that keeps the depth, an offline frame's once it is known to come out deep.
    /// A document's own key is never marked, so the preview never is.
    private var deepKeys = Set<Int>()
    private var nextKey = 1

    /// What a key's cursor files are resolved from (`cursorSources`).
    private struct CursorSource: Equatable {
        let cursor: MediaCursor
        let duration: Ticks
        let fps: Fps
    }

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
        // The options go with the slot, never before it: `set(nil, for:)`
        // deliberately leaves them, because a key with no project published
        // right now is still the same ask.
        options.removeValue(forKey: key)
        mediaURLs.removeValue(forKey: key)
        cursorFiles.removeValue(forKey: key)
        cursorSources.removeValue(forKey: key)
        cursorWants.removeValue(forKey: key)
        deepKeys.remove(key)
        // Released off this thread, never under the lock (CU-37 (e)): `Exporter.deinit` can
        // run inside `CursorTracks.wait`'s `cancelled()`, which holds the registry's lock that
        // `release` takes. Keys are never reused, so a late release drops no newer want.
        if cursorOwners.remove(key) != nil {
            DispatchQueue.global(qos: .utility).async { CursorTracks.shared.release(owner: key) }
        }
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

    /// What `key` wants of its recipes. `RecipeOptions.none` for a key that
    /// never set any, which is every document's but one showing ungraded.
    ///
    /// Published by whoever owns the key and read on the compositor's queue,
    /// like the project beside it — and NOT main-thread-only, because
    /// `Exporter.renderFrame` mints a key, publishes to it and renders on
    /// whatever thread it was called on (its own doc says off the main one).
    /// The lock is what covers that, exactly as it already does for `set`.
    func setOptions(_ newOptions: RecipeOptions, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Store nothing for the default, so the dictionary holds only the
        // keys that are actually asking for something and "absent means
        // none" stays a fact rather than a convention.
        if newOptions == .none {
            options.removeValue(forKey: key)
        } else {
            options[key] = newOptions
        }
    }

    /// Publishes a document's media URLs under `key` (main thread, beside
    /// `set`, from `Playback.update`), and its cursor files with them: the
    /// files are resolved again only when a cursor media's record, duration
    /// or rate changed, and the key wants its clips' tracks of `CursorTracks`
    /// only when what they want changed (spec §11 CU-37 (a)).
    func setMediaURLs(_ urls: [UInt32: URL], project: ReelProject, for key: Int) {
        let snapshot = project.snapshot
        var sources: [UInt32: CursorSource] = [:]
        for media in snapshot.media {
            guard let cursor = media.cursor, !cursor.inPicture else { continue }
            sources[media.id] = CursorSource(
                cursor: cursor, duration: media.duration, fps: media.fps)
        }
        lock.lock()
        mediaURLs[key] = urls
        let known = cursorSources[key] ?? [:]
        let stored = cursorFiles[key] ?? [:]
        lock.unlock()
        let files = sources == known ? stored : CursorFiles.files(of: snapshot)
        setCursorFiles(files, sources: sources, for: key)
        let requests = CursorFiles.requests(of: snapshot, files: files)
        lock.lock()
        let changed = (cursorWants[key] ?? []) != requests
        if changed {
            cursorWants[key] = requests
            if !requests.isEmpty { cursorOwners.insert(key) }
        }
        lock.unlock()
        if changed { CursorTracks.shared.want(requests, owner: key) }
    }

    /// Publishes `key`'s cursor files (`Exporter.waitForCursors`, before it
    /// waits): what `cursorFiles(for:)` answers the compositor.
    func setCursorFiles(_ files: [UInt32: CursorFile], for key: Int) {
        setCursorFiles(files, sources: nil, for: key)
    }

    private func setCursorFiles(
        _ files: [UInt32: CursorFile], sources: [UInt32: CursorSource]?, for key: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        cursorFiles[key] = files.isEmpty ? nil : files
        cursorSources[key] = sources
        // `waitForCursors` wants under this key through `CursorTracks.wait`.
        if sources == nil, !files.isEmpty { cursorOwners.insert(key) }
    }

    /// The cursor files published under `key`; `[:]` for one that published none.
    func cursorFiles(for key: Int) -> [UInt32: CursorFile] {
        lock.lock()
        defer { lock.unlock() }
        return cursorFiles[key] ?? [:]
    }

    /// The cursor files a layer under `instruction` reads: those published
    /// under its `recipeKey`; `[:]` for nil or a key that published none (CU-37 (d)).
    func cursorFiles(for instruction: RecipeInstruction?) -> [UInt32: CursorFile] {
        guard let instruction = instruction else { return [:] }
        return cursorFiles(for: instruction.recipeKey)
    }

    /// The media URLs a LUT look under `instruction` reads: the map published
    /// under its `recipeKey`, else the instruction's own (a fresh export or
    /// frame key publishes none); `[:]` with no instruction. One lock hold.
    func lookURLs(for instruction: RecipeInstruction?) -> [UInt32: URL] {
        guard let instruction = instruction else { return [:] }
        lock.lock()
        defer { lock.unlock() }
        return mediaURLs[instruction.recipeKey] ?? instruction.mediaURLs
    }

    /// Marks `key`'s frames as delivered deeper than 8 bits (spec §11 PR-16), until the key
    /// is unregistered. Beside each of PR-15's marks, with or without a graphic set.
    func markDeep(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        deepKeys.insert(key)
    }

    /// Whether `key`'s frames are delivered deeper than 8 bits: what a gradient shape's
    /// texture depth follows (`LayerRenderers.shape`). False for a key never marked.
    func deliversDeep(_ key: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return deepKeys.contains(key)
    }

    /// The options published under `key`, for a caller that has to carry
    /// them somewhere the compositor cannot reach — an image-sequence write
    /// renders each frame through a key of its own.
    func options(for key: Int) -> RecipeOptions {
        lock.lock()
        defer { lock.unlock() }
        return options[key] ?? .none
    }

    /// The recipe at `t` for one document, WITH whatever that key asked for.
    ///
    /// The project and the options are read under ONE hold, which is what
    /// makes "this key's options" true of the answer rather than of some
    /// instant near it — and is why the compositor asks for a recipe rather
    /// than for the two halves. It deliberately does NOT hold the lock
    /// across the FFI call and the JSON decode — only across the dictionary
    /// reads — so a slow frame never blocks the main thread's next publish.
    func recipe(for key: Int, at t: Ticks) -> FrameRecipe? {
        lock.lock()
        let project = projects[key]
        let asked = options[key] ?? .none
        lock.unlock()
        return project?.recipe(at: t, options: asked)
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
