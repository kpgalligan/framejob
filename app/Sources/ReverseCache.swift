import AVFoundation
import AppKit
import VideoToolbox

// MARK: - Where a reversed asset lives

/// The `cache/reversed/` half of the package (spec §5.6), and what makes one
/// of its files stale.
///
/// **Why inside the package.** §5.6 reserves `cache/` for data that is
/// regenerable and never required to open, and a reversed asset is exactly
/// that: delete it and the renderer makes it again from media the project
/// still references. It is regenerable in the strict sense and *expensive* in
/// the practical one — a ten-minute 4K clip is minutes of decode and encode —
/// so it belongs somewhere that travels with the edit rather than somewhere
/// that has to be rebuilt on the machine the package lands on.
/// `fileWrapper(ofType:)` already carries `cache/` across every save through
/// the LAZY `FileWrapper` the filmstrips ride, and `NSFileWrapper` hard-links
/// a child it is writing back over its own original — so a save in place pays
/// for the reverse once. A Save As, or an autosave to a new draft location,
/// really does copy it; that is the cost of a package that travels whole.
///
/// **Why not Application Support, where `FFmpegRewrap` puts its conversions.**
/// §11's reasoning for that choice does not transfer. A rewrap is the only
/// *decodable* copy of footage the app can open, so losing it loses the media;
/// a reverse is a derived rendering of media that is still there, so losing it
/// costs time. And a rewrap is made during an import, when the document is
/// usually still untitled and has no package — while a reverse is asked for
/// mid-edit, on a project that has one. An untitled document falls back to
/// `ProjectDocument`'s temporary cache directory exactly as filmstrips do, and
/// the first save copies the render into the package with everything else.
///
/// **Why the name carries a digest.** The contract's `<media id>.mov` names
/// the file by a project-scoped id, and ids outlive the file behind them:
/// Relink… can point media 3 at a completely different movie, and a reversed
/// asset for the old one would then be silently wrong — forward frames from
/// the wrong film. The digest is `FFmpegRewrap`'s (path, size, modification
/// second), for its reasons: it makes the render both reusable and
/// self-invalidating, and reading gigabytes to decide whether to re-encode
/// gigabytes is the wrong trade. It also covers `rendererVersion`, so a
/// render the renderer would now write differently — the 8-bit H.264/HEVC
/// files before spec §11 PR-7 — lands under a new name and is never reused;
/// `prune` deletes the old sibling when the new one arrives.
enum ReverseCache {
    /// The subdirectory of `cache/` this feature owns.
    static let directoryName = "reversed"

    /// What the renderer writes, as a number in the digest. Bump it whenever
    /// the written file changes, so every reverse already in a package is
    /// rendered again rather than played. 2: the 10-bit intermediate with
    /// the source's colour labels (spec §11 PR-7). 3: an odd-size reverse of
    /// full-range media read as full-range frames (spec §11 PR-10). 4: a VP9
    /// media's range read from its `vpcC` (spec §11 GR-23). 5: an MP3 read
    /// past the encoder delay Core Audio leaves in (spec §11 SY-42).
    static let rendererVersion = 5

    static func directory(in cache: URL) -> URL {
        cache.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Where `media`'s reversal of `source` goes. nil when the source cannot
    /// be measured, which is the same answer as "there is nothing to reverse".
    static func destination(media: UInt32, source: URL, in cache: URL) -> URL? {
        guard let digest = digest(of: source) else { return nil }
        return directory(in: cache).appendingPathComponent("\(media)-\(digest).mov")
    }

    /// A finished reversal already on disk, if there is one.
    static func existing(media: UInt32, source: URL, in cache: URL) -> URL? {
        guard let url = destination(media: media, source: source, in: cache),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// Throws away the reversals of `media` that a fresh one has just made
    /// obsolete — the previous digest's file after a relink, and any partial
    /// left by a render that died.
    ///
    /// Refuses to delete anything that is not a sibling of `keep` inside a
    /// directory named `reversed`, and refuses to delete `keep` itself. This
    /// takes a URL and removes files, which is the shape of function a bug
    /// elsewhere turns into data loss, so the guard is not a formality
    /// (`FFmpegRewrap.discard` makes the same one).
    static func prune(media: UInt32, keeping keep: URL) {
        let directory = keep.deletingLastPathComponent()
        guard directory.lastPathComponent == directoryName,
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        let kept = keep.lastPathComponent
        for name in names where name != kept && name.hasPrefix("\(media)-") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// FNV-1a over path, byte size, modification second and `rendererVersion`
    /// — `FFmpegRewrap`'s digest plus the version, spelled again here rather
    /// than shared because that one is private to its own naming scheme and
    /// this one keys a different directory. Not a content hash, for the
    /// reason that file gives.
    private static func digest(of source: URL) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value else { return nil }
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(source.path)|\(size)|\(Int64(modified.rounded()))|v\(rendererVersion)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

// MARK: - What the composition is told

/// Which clips play from a reversed file, and which are still waiting for one.
///
/// Keyed by CLIP and not by media, because reversal is a property of the clip:
/// the same movie forward on one track and backwards on another — the
/// boomerang every editor has made — is one media entry, two clips, and only
/// one of them may read the reversed file.
struct ReverseResolution: Equatable {
    /// Clip id → the pre-rendered file its segments read from instead of the
    /// media's own.
    let ready: [UInt32: URL]
    /// Clips that are reversed and have NO file yet: the render has not run,
    /// was cancelled, or failed. `CompositionBuilder` holds their place with
    /// empty time and marks them missing, so they draw §5.6's slate.
    ///
    /// This is the whole point of publishing pending clips rather than simply
    /// omitting them. A reversed clip with no reversed asset used to play
    /// FORWARD — the picture silently disagreed with the model — and a slate
    /// is the honest answer: something is meant to be here and is not.
    let pending: Set<UInt32>
    /// The document's `cache/ramp-audio/` (spec §11 SR-12 (b)), published
    /// beside the plan with the rest: a ramp segment plays its render when
    /// the file `RampAudioCache` names is in it when the composition is
    /// built, and is silent otherwise. Nil with no cache folder.
    var rampAudio: URL? = nil

    static let none = ReverseResolution(ready: [:], pending: [])

    var isEmpty: Bool { ready.isEmpty && pending.isEmpty }
}

/// What the Clip tab's Timing section says about one clip's reverse, and the
/// state machine behind the "Render Reverse" button.
///
/// There is no state that means "reversed and playing forwards", which is the
/// point: every state below either has the frames or says out loud that it
/// does not.
enum ReverseStatus: Equatable {
    /// Not reversed — or reversed media that needs no rendering, which a
    /// still picture is.
    case off
    /// Reversed, with the backwards copy on disk.
    case ready
    /// Reversed, and its frames are being made or about to be.
    case pending
    /// Reversed, and the render was cancelled or failed. Nothing will retry it
    /// on its own; the button does.
    case stopped
    /// Reversed, but the media itself is missing or has no length — the clip
    /// is already drawing a missing-media slate for a different reason.
    case unavailable

    /// The row's own words.
    var summary: String {
        switch self {
        case .off: return "—"
        case .ready: return "Rendered"
        case .pending: return "Rendering…"
        case .stopped: return "Not rendered"
        case .unavailable: return "Media missing"
        }
    }
}

/// The process-wide place `CompositionBuilder` finds a document's reverse
/// resolution, keyed by the same `RecipeSource` slot the compositor reads
/// recipes under — `AudioDSPSource`'s shape, for `AudioDSPSource`'s reasons.
///
/// The two mirrors exist for the same underlying fact: `CompositionBuilder` is
/// handed the composition PLAN, and the plan is `plan.rs`'s structural
/// description of what to decode. `Source::Media.reversed` is deliberately not
/// in it — the core does no pixel work, so reversal changes neither the plan
/// nor the recipe (spec §11) — which leaves exactly one place for the answer
/// to arrive: beside the plan, published by the document.
///
/// **A key with no entry is answered by the handle, not by a search.** An
/// export mints a FRESH `RecipeSource` key so a queued frame cannot be
/// composed from a project the user changed mid-write, and nothing publishes
/// under that new key — but it does publish the project HANDLE under it, and a
/// handle is one object that exactly one document published. So the lookup
/// asks `RecipeSource` which handle the key was registered with and takes the
/// entry that published that same object.
///
/// It was once a scan for the document whose plan JSON matched. Reversal is
/// deliberately absent from the plan, so a reversed clip and a forward one
/// produce the SAME plan string: two such documents open at once were
/// indistinguishable to the scan, and the ambiguous answer — slate everything
/// either candidate called reversed — left a correctly rendered reversed clip
/// showing the missing-media plate in the preview and in the export, with no
/// way back. Measured, not theorised. Identity cannot be ambiguous, so the
/// case is gone rather than handled.
///
/// A key whose handle nobody published is still `.none`: no document claims
/// that composition, so no clip in it reads from a reversed file.
///
/// **And that handle search is only enough while the document has not moved
/// on, which is what a PIN is for.** The search names a document by the
/// object it published, and a document publishes a NEW object after every
/// edit, undo and live drag — `ProjectDocument.projectDidChange` calls
/// `publishReverseResolution`, which overwrites the document's one entry with
/// the current handle — and drops the entry outright when it closes. An
/// export that started a moment ago and finishes a moment later is never
/// caught by that; a QUEUED export, whose whole contract is that the person
/// goes back to editing while it waits, is caught by it every time. The
/// answer was `.none`, and `.none` is the one state this file's `ReverseStatus`
/// says cannot exist: `CompositionBuilder.fill` finds the clip in neither
/// `ready` nor `pending`, inserts the FORWARD asset track, and — because the
/// plan's `source_in` is measured in the REVERSED stream (`Source::Media` in
/// `core/src/model.rs`) — reads the mirrored window of the forward file, so a
/// trimmed clip shows different frames entirely. Unslated, unreported, in the
/// picture and in the sound alike, and measured by the loudness pass too.
///
/// So a caller that has captured a resolution and must keep it across an
/// edit PINS it to the handle it belongs to, and the pin is consulted only
/// AFTER the handle search fails. The order is deliberate: while the document
/// still holds that very handle, its own entry is the more current truth
/// about the disk — a reverse render that finished in the meantime republishes
/// under the SAME handle — so the pin answers exactly when the document has
/// moved on or gone, and nothing that worked before it existed behaves
/// differently. `ExportQueueController` is its one caller today; see
/// `pin(_:for:)` for what a caller owes.
final class ReverseSource {
    static let shared = ReverseSource()

    private struct Entry {
        /// The handle this resolution was computed from. Compared, never
        /// dereferenced — it is here to name a document, and holding it
        /// strongly would keep a closed document's Rust project alive.
        let project: ObjectIdentifier
        let resolution: ReverseResolution
    }

    /// A resolution held against one handle for the length of one write.
    ///
    /// Unlike `Entry` this RETAINS its project, and the difference is the
    /// point rather than an oversight: an `Entry` names a document that may
    /// close, where a pin names the handle a job is writing from right now.
    /// Holding it makes "a pin can never name a dead object" true here
    /// instead of true only while the caller happens to be retaining it too,
    /// and so closes the one way a pin could go wrong — an identity reused by
    /// a later allocation, answering some other project's frames.
    private struct Pin {
        let project: ReelProject
        let resolution: ReverseResolution
    }

    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var pins: [ObjectIdentifier: Pin] = [:]

    private init() {}

    /// Publishes a document's resolution. Main thread, after every edit and
    /// after every render that finishes.
    func publish(_ resolution: ReverseResolution, project: ReelProject, for key: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = Entry(project: ObjectIdentifier(project), resolution: resolution)
    }

    /// Drops a document's slot, the way `RecipeSource.unregister` does.
    func unpublish(_ key: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    /// The resolution published for one HANDLE, whatever key it was published
    /// under — what a caller reads when it wants to keep the answer.
    ///
    /// Deliberately blind to the pins: this is the CAPTURE, and it must see
    /// the document's own current answer rather than something an earlier
    /// capture pinned.
    func resolution(publishedFor project: ReelProject) -> ReverseResolution {
        let handle = ObjectIdentifier(project)
        lock.lock()
        defer { lock.unlock() }
        return entries.values.first { $0.project == handle }?.resolution ?? .none
    }

    /// Holds `resolution` against `project` until `unpin`, so a composition
    /// built from that handle still finds it after the document has edited,
    /// undone or closed its way onto a different one.
    ///
    /// **What the caller owes: exactly one `unpin` per `pin`, and a pin per
    /// handle at a time.** The table is keyed by identity, so a second pin of
    /// one handle replaces the first rather than stacking — the queue holds
    /// at most one because it runs one job at a time, which is where that
    /// invariant is stated and kept. A pin never released retains the Rust
    /// project behind the handle for the life of the process.
    func pin(_ resolution: ReverseResolution, for project: ReelProject) {
        lock.lock()
        defer { lock.unlock() }
        pins[ObjectIdentifier(project)] = Pin(project: project, resolution: resolution)
    }

    /// Releases what `pin` held. Safe to call twice and safe to call for a
    /// handle that was never pinned.
    func unpin(_ project: ReelProject) {
        lock.lock()
        defer { lock.unlock() }
        pins.removeValue(forKey: ObjectIdentifier(project))
    }

    /// What is pinned against `project`, or nil. Nothing in the app reads
    /// this — the resolution lookup below consults the table directly — and
    /// it is here so that a proof can assert the two halves a rendered frame
    /// cannot show: that a running job HAS pinned its captured answer, and
    /// that an idle queue has released every one of them.
    func pinnedResolution(for project: ReelProject) -> ReverseResolution? {
        lock.lock()
        defer { lock.unlock() }
        return pins[ObjectIdentifier(project)]?.resolution
    }

    /// The resolution for the composition being built under `key`: the entry
    /// published under that key, the one published for the very handle the key
    /// was registered with, or — when the document has moved on from that
    /// handle — whatever a caller pinned to it. See the type's own comment for
    /// why the pin comes last.
    func resolution(for key: Int) -> ReverseResolution {
        lock.lock()
        let own = entries[key]
        lock.unlock()
        if let own = own { return own.resolution }
        guard let project = RecipeSource.shared.project(for: key) else { return .none }
        let handle = ObjectIdentifier(project)
        lock.lock()
        defer { lock.unlock() }
        if let published = entries.values.first(where: { $0.project == handle }) {
            return published.resolution
        }
        return pins[handle]?.resolution ?? .none
    }
}
