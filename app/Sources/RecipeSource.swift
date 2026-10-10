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
    /// Ungraded is on (spec §11 GR-4); `Exporter` mints keys of its own for an
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
        // The options go with the slot, never before it: `set(nil, for:)`
        // deliberately leaves them, because a key with no project published
        // right now is still the same ask.
        options.removeValue(forKey: key)
        mediaURLs.removeValue(forKey: key)
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
    /// `set`, from `Playback.update`).
    func setMediaURLs(_ urls: [UInt32: URL], for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        mediaURLs[key] = urls
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
