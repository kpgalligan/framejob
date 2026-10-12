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
    /// the source's colour labels (spec §11 PR-7).
    static let rendererVersion = 2

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

    static let none = ReverseResolution(ready: [:], pending: [])

    var isEmpty: Bool { ready.isEmpty && pending.isEmpty }
}

/// What the Video tab's Speed section says about one clip's reverse, and the
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

// MARK: - The renderer

/// Decodes one media file and writes it back to front, so AVFoundation can
/// play a reversed clip forward (spec §11: "reverse is not native; M3
/// pre-renders reversed segments").
///
/// **The reader-to-writer shape is `ExporterWriter`'s**, and deliberately so:
/// an `AVAssetReader` feeding an `AVAssetWriter`, cancelled by a flag every
/// sample checks, progress kept by hand because `AVAssetWriter` has none. What
/// differs is the ONE thing reversal forces — a writer's inputs take samples
/// in ascending presentation order, and the frames arrive in the opposite one,
/// so the file cannot be streamed through. Frames have to be held.
///
/// **Chunks, because holding the whole film is not an option.** The asset is
/// walked backwards a slice at a time: read `[t, t + Δ)` into memory, append
/// its frames newest-first, then step back to `[t − Δ, t)`. Δ is sized by
/// BYTES rather than by seconds — 4K frames are sixteen times a 720p frame —
/// so the resident cost is bounded whatever the source is, at the price of one
/// `AVAssetReader` per slice.
///
/// **The arithmetic that makes the reversed file line up with the model.**
/// The pivot is the media's own duration `T` as the model recorded it and the
/// subtraction is `ReverseMirror`'s, which states the convention and why the
/// app owns it; the reversal works only because it is exactly as long as the
/// original. Frame durations come out of the gaps between presentation stamps
/// rather than out of a nominal rate, which keeps a variable-rate source exact
/// instead of nearly right, and the written stream tiles `[0, T)` with no seam.
///
/// **What it does NOT do.**
/// * It does not carry the source's `preferredTransform`, and must not. A
///   custom compositor gets RAW decoded frames and turns the sampling itself
///   from the orientation code `CompositionBuilder.orientationCodes` reads off
///   the FORWARD asset (§7.5). The frames written here are the same coded
///   frames the forward file decodes to, so that one code is right for both;
///   baking a transform in would turn a portrait clip twice.
/// * It does not preserve an alpha channel. The intermediate (spec §11 PR-7)
///   is 10-bit 4:2:0 HEVC Main 10, or 10-bit 4:2:2 ProRes 422 when the source
///   has an odd width or height, so a reversed ProRes 4444 clip loses its
///   transparency — the price of an intermediate small enough to live in the
///   package, and not silent: the picture changes visibly when the clip is
///   reversed.
/// * It does not convert colour. The frames are read in the source's own
///   YCbCr at 10 bits, the held copy keeps the decoder's colour attachments,
///   and the encoder is given no colour properties, so the file carries the
///   source's own primaries, transfer and matrix — an HLG clip's reverse is
///   labelled HLG — and the compositor treats it exactly as it treats the
///   forward file (PR-2: HDR is tone-mapped there, not here).
final class ReverseRenderer {

    /// What one reverse is written as (spec §11 PR-7), from the source's
    /// coded size. HEVC 4:2:0 cannot hold an odd size — 1919×1079 came back
    /// 1918×1078 — and `videoSettings` says why the size must be exact, so an
    /// odd width or height takes ProRes 422, whose file is several times
    /// larger, for its exact size.
    enum Intermediate: Equatable {
        /// Even width and height: `x420` frames, HEVC Main 10.
        case hevcMain10
        /// An odd width or height: `x422` frames, ProRes 422.
        case proRes422

        init(_ dimensions: CMVideoDimensions) {
            self = dimensions.width % 2 != 0 || dimensions.height % 2 != 0 ? .proRes422 : .hevcMain10
        }

        /// The format the reader is asked for, held, and handed the writer.
        var pixelFormat: OSType {
            switch self {
            case .hevcMain10: return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            case .proRes422: return kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
            }
        }

        /// Bytes one held pixel costs: 10-bit samples in 16-bit words, one
        /// luma and half (4:2:0) or one (4:2:2) chroma sample a pixel.
        var bytesPerPixel: Int {
            switch self {
            case .hevcMain10: return 3
            case .proRes422: return 4
            }
        }
    }

    /// One media file to reverse, decided on the main thread against the
    /// document's snapshot so the render loop consults nothing that can move.
    struct Job: Equatable {
        let media: UInt32
        /// The media's display name, for the sheet's status line.
        let name: String
        let source: URL
        let destination: URL
        /// The media's duration as the MODEL has it — the pivot the reversal
        /// is measured about, and the number `in` is measured against.
        let duration: Ticks
        let fps: Fps
        let hasAudio: Bool
    }

    enum ReverseError: LocalizedError {
        /// Nothing in the file can be reversed: no readable track, or a
        /// duration the model does not believe in.
        case unreadable(String)
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return "“\(name)” has no video or audio that can be reversed."
            case .cancelled:
                return "The reverse was cancelled."
            case .failed(let reason):
                return "The reversed clip could not be rendered: \(reason)"
            }
        }
    }

    /// `MediaConsolidator.CancelToken`'s shape: one flag, one lock, safe from
    /// any thread and safe to set twice.
    final class CancelToken {
        private let lock = NSLock()
        private var flag = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }

        func cancel() {
            lock.lock()
            flag = true
            lock.unlock()
        }
    }

    /// How much decoded picture may be resident at once. One slice of the
    /// source is held whole, so this is the renderer's whole memory budget and
    /// not a soft target: half a gigabyte is about 86 frames of 1080p `x420`
    /// (under three seconds at 30 fps) or 21 of 4K, which keeps the per-slice
    /// reader overhead small without making the app a memory hog while it
    /// works. `sliceDuration` counts the held format's bytes.
    private static let bufferBudget = 512 * 1024 * 1024

    private let job: Job
    /// Written to first and moved into place only on success, so a cancel or a
    /// crash can never leave a half-reversed file that `ReverseCache.existing`
    /// would hand out as finished.
    private let partial: URL

    init(job: Job) {
        self.job = job
        self.partial = job.destination.appendingPathExtension("partial")
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ReverseRenderer does not support NSCoder")
    }

    /// Renders the whole file. Synchronous and disk-bound — call it OFF the
    /// main thread — and never throws: every outcome comes back as a
    /// `Result`, because the caller is a sheet that has to say something
    /// either way.
    func run(
        cancel: CancelToken? = nil, progress: ((Double) -> Void)? = nil
    ) -> Result<URL, any Error> {
        do {
            let url = try write(cancel: cancel, progress: progress)
            return .success(url)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            return .failure(error)
        }
    }

    // MARK: - The write

    private func write(cancel: CancelToken?, progress: ((Double) -> Void)?) throws -> URL {
        let asset = AVURLAsset(
            url: job.source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // The one synchronous track lookup in the app, shared with
        // `CompositionBuilder` so the deprecation it costs is paid once.
        let videoTrack = CompositionBuilder.firstTrack(of: asset, mediaType: .video)
        let audioTrack =
            job.hasAudio ? CompositionBuilder.firstTrack(of: asset, mediaType: .audio) : nil
        let total = CompositionBuilder.time(job.duration)
        guard videoTrack != nil || audioTrack != nil, total > .zero else {
            throw ReverseError.unreadable(job.name)
        }

        // The coded frame size, taken from a frame rather than from the
        // track's `naturalSize`: the async-only accessors are the reason
        // (app/CLAUDE.md keeps `await` inside `MediaImporter`), and a decoded
        // frame is in any case the more honest source of the number the
        // encoder has to match.
        let dimensions = videoTrack.flatMap { Self.dimensions(of: asset, track: $0, limit: total) }
        let intermediate = dimensions.map(Intermediate.init)

        try FileManager.default.createDirectory(
            at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: partial)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        } catch {
            throw ReverseError.failed(error.localizedDescription)
        }

        var videoInput: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        if let dimensions = dimensions, let intermediate = intermediate, dimensions.width > 0,
            dimensions.height > 0
        {
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: Self.videoSettings(
                    dimensions, fps: job.fps, intermediate: intermediate))
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw ReverseError.failed("this Mac cannot encode the format it needs")
            }
            writer.add(input)
            adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(intermediate.pixelFormat),
                    kCVPixelBufferWidthKey as String: Int(dimensions.width),
                    kCVPixelBufferHeightKey as String: Int(dimensions.height),
                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                ])
            videoInput = input
        }
        var audioInput: AVAssetWriterInput?
        if audioTrack != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }
        guard videoInput != nil || audioInput != nil else {
            throw ReverseError.unreadable(job.name)
        }
        guard writer.startWriting() else {
            throw ReverseError.failed(
                writer.error?.localizedDescription ?? "the file could not be opened for writing")
        }
        writer.startSession(atSourceTime: .zero)

        do {
            try walkBackwards(
                asset: asset, videoTrack: videoTrack, audioTrack: audioTrack, total: total,
                dimensions: dimensions,
                pixelFormat: videoInput == nil
                    ? kCVPixelFormatType_32BGRA
                    : (intermediate?.pixelFormat ?? kCVPixelFormatType_32BGRA),
                writer: writer, videoInput: videoInput, adaptor: adaptor,
                audioInput: audioInput, cancel: cancel, progress: progress)
        } catch {
            // A writer left in `.writing` keeps its file open and its encoder
            // alive until it is deallocated; cancelling closes both now and
            // takes the part-written file with it.
            writer.cancelWriting()
            throw error
        }

        if cancel?.isCancelled == true {
            writer.cancelWriting()
            throw ReverseError.cancelled
        }
        // `finishWriting` closes the container on a queue of its own, and this
        // method's contract is that the file exists when it returns.
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw ReverseError.failed(
                writer.error?.localizedDescription ?? "the write stopped before it finished")
        }

        try? FileManager.default.removeItem(at: job.destination)
        do {
            try FileManager.default.moveItem(at: partial, to: job.destination)
        } catch {
            throw ReverseError.failed(error.localizedDescription)
        }
        ReverseCache.prune(media: job.media, keeping: job.destination)
        return job.destination
    }

    /// Walks the source from its end to its start, one slice at a time,
    /// appending each slice's samples in reverse.
    ///
    /// **The timing.** `following` is the presentation stamp of the frame
    /// AFTER the one being written — the whole of the arithmetic, and the
    /// reason a slice boundary costs nothing: `ReverseMirror` mirrors it, and
    /// the next frame back supplies its own `following` when its turn comes.
    /// It starts at `T`, so the source's last frame lands at zero, and it
    /// decreases strictly, so every append is later than the last one.
    ///
    /// **Why the samples are fed on demand rather than in time order.** An
    /// `AVAssetWriter` interleaves its tracks and will not take from one input
    /// while it wants the other: `isReadyForMoreMediaData` goes false on the
    /// track it has enough of, and STAYS false until the other one catches
    /// up — for good, if nothing ever feeds it. Measured on this build, three
    /// ways: 150 frames of video beside an untouched audio input stall at
    /// frame 41; six seconds of audio beside an untouched video input stall
    /// too; and even strict output-time interleaving stalls, because the
    /// writer wanted sound that was already a tenth of a second AHEAD of the
    /// picture. There is no lead to tune. So this decodes a slice of both
    /// tracks, then feeds whichever input says it is hungry, and only reads
    /// the next slice when one of the two queues runs dry — which is
    /// `requestMediaDataWhenReady`'s bargain, made by polling because the
    /// producer here is a loop rather than a callback.
    ///
    /// **Silence, and why it is not a fudge.** A stretch of the source with no
    /// audio in it — a video track that outlasts its audio, the commonest
    /// cause — would leave the audio input starving and the picture stalled
    /// against it. It is filled with silence instead, which is also exactly
    /// what the source plays there and what the composition would have made of
    /// the forward file.
    private func walkBackwards(
        asset: AVURLAsset, videoTrack: AVAssetTrack?, audioTrack: AVAssetTrack?, total: CMTime,
        dimensions: CMVideoDimensions?, pixelFormat: OSType, writer: AVAssetWriter,
        videoInput: AVAssetWriterInput?, adaptor: AVAssetWriterInputPixelBufferAdaptor?,
        audioInput: AVAssetWriterInput?, cancel: CancelToken?, progress: ((Double) -> Void)?
    ) throws {
        let slice = Self.sliceDuration(dimensions: dimensions, fps: job.fps)
        let seconds = max(CMTimeGetSeconds(total), 0.000_001)
        var cursor = total
        var following = total
        var written: Int64 = 0

        // What has been decoded and not yet handed to the writer. Never more
        // than about two slices: the loop refills only when one of them empties.
        var pictures: [(time: CMTime, buffer: CVPixelBuffer)] = []
        var sounds: [CMSampleBuffer] = []

        /// Feeds hungry inputs. `untilOneEmpty` is the normal mode — stop as
        /// soon as either queue runs dry, so the caller can refill both before
        /// the writer has a chance to want the empty one. The final pass runs
        /// with it false and marks each input finished as its queue empties,
        /// which is what releases the other from the interleave.
        func feed(untilOneEmpty: Bool, videoDone: inout Bool, audioDone: inout Bool) throws {
            while true {
                if cancel?.isCancelled == true { throw ReverseError.cancelled }
                guard writer.status == .writing else {
                    throw ReverseError.failed(
                        writer.error?.localizedDescription ?? "the write stopped early")
                }
                let hasPicture = !pictures.isEmpty
                let hasSound = !sounds.isEmpty
                if untilOneEmpty {
                    // Only a track that EXISTS can run dry. Testing the
                    // picture unconditionally would make an audio-only source
                    // return on its first look and pile the whole file up in
                    // `sounds` before anything was written.
                    if videoInput != nil, !hasPicture { return }
                    if audioInput != nil, !hasSound { return }
                } else {
                    if !hasPicture, !videoDone, let input = videoInput {
                        input.markAsFinished()
                        videoDone = true
                        continue
                    }
                    if !hasSound, !audioDone, let input = audioInput {
                        input.markAsFinished()
                        audioDone = true
                        continue
                    }
                    if !hasPicture, !hasSound { return }
                }
                if hasPicture, let input = videoInput, let adaptor = adaptor,
                    input.isReadyForMoreMediaData
                {
                    let entry = pictures.removeFirst()
                    guard adaptor.append(entry.buffer, withPresentationTime: entry.time) else {
                        throw ReverseError.failed(
                            writer.error?.localizedDescription ?? "a frame could not be encoded")
                    }
                    continue
                }
                if hasSound, let input = audioInput, input.isReadyForMoreMediaData {
                    let entry = sounds.removeFirst()
                    guard input.append(entry) else {
                        throw ReverseError.failed(
                            writer.error?.localizedDescription ?? "the sound could not be written")
                    }
                    continue
                }
                // Both encoders are busy. 5 ms is far shorter than a frame and
                // far longer than a context switch.
                Thread.sleep(forTimeInterval: 0.005)
            }
        }

        var videoDone = videoInput == nil
        var audioDone = audioInput == nil
        while cursor > .zero {
            if cancel?.isCancelled == true { throw ReverseError.cancelled }
            let start = CMTimeMaximum(.zero, cursor - slice)
            // `sliceDuration` never returns zero, so this cannot fire — but a
            // loop that walks backwards on a background thread is not the
            // place to trust arithmetic, and the cost of being sure is a
            // comparison.
            guard start < cursor else { break }
            let read = try Self.read(
                asset: asset, range: CMTimeRange(start: start, end: cursor), limit: total,
                videoTrack: videoTrack, audioTrack: audioTrack, pixelFormat: pixelFormat,
                cancel: cancel)

            if adaptor != nil {
                for frame in read.frames.reversed() {
                    // Two frames at one stamp would append twice at the same
                    // output time, which a writer input refuses outright. It
                    // should not happen — the slice is sorted and a track has
                    // one frame per instant — so the answer is to drop the
                    // duplicate rather than lose the file over it.
                    guard frame.time < following else { continue }
                    pictures.append(
                        (time: ReverseMirror.mirrored(following, about: total),
                         buffer: frame.buffer))
                    following = frame.time
                }
            }
            if audioInput != nil, let format = Self.audioFormat {
                let forward = ReverseMirror.mirrored(start, about: total)
                sounds.append(
                    contentsOf: Self.audioBlocks(
                        read.audio, format: format, from: &written,
                        covering: Self.audioFrames(in: forward)))
            }

            try feed(untilOneEmpty: true, videoDone: &videoDone, audioDone: &audioDone)
            cursor = start
            progress?(min(max(1 - CMTimeGetSeconds(cursor) / seconds, 0), 1))
        }
        // The final pass drains both queues and marks each input finished as
        // it empties, so `write` has nothing left to do but close the file.
        try feed(untilOneEmpty: false, videoDone: &videoDone, audioDone: &audioDone)
    }

    // MARK: - Reading one slice

    /// One decoded frame, held until its turn to be written comes round.
    private struct Frame {
        let time: CMTime
        let buffer: CVPixelBuffer
    }

    private struct Slice {
        var frames: [Frame] = []
        /// Interleaved 16-bit LPCM, in source order; reversed on the way out.
        var audio: [UInt8] = []
    }

    /// Reads everything in `range` into memory.
    ///
    /// The two outputs are drained a sample at a time each rather than one
    /// after the other: an `AVAssetReader` decodes both tracks as it goes, and
    /// emptying one output while the other is untouched makes it buffer the
    /// second track's samples on our behalf, which is the one thing this
    /// method exists to avoid.
    ///
    /// Samples outside `[range.start, range.end)` are dropped rather than
    /// clipped. A reader may hand back a frame that begins before the range
    /// (the sync sample it had to decode from), and that frame belongs to the
    /// PREVIOUS slice, which has already written it — so admitting it here
    /// would write it twice and break the strictly-decreasing stamp the
    /// caller's arithmetic depends on.
    private static func read(
        asset: AVURLAsset, range: CMTimeRange, limit: CMTime, videoTrack: AVAssetTrack?,
        audioTrack: AVAssetTrack?, pixelFormat: OSType, cancel: CancelToken?
    ) throws -> Slice {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ReverseError.failed(error.localizedDescription)
        }
        reader.timeRange = range

        var videoOutput: AVAssetReaderTrackOutput?
        if let track = videoTrack {
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    // The intermediate's own format (`Intermediate`): 10-bit
                    // YCbCr in the source's matrix, so nothing converts
                    // between the decoder and the encoder and the frames
                    // keep their depth and their colour labels (PR-7).
                    kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                ])
            if reader.canAdd(output) {
                reader.add(output)
                videoOutput = output
            }
        }
        var audioOutput: AVAssetReaderTrackOutput?
        if let track = audioTrack {
            let output = AVAssetReaderTrackOutput(
                track: track, outputSettings: decodedAudioSettings)
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }
        guard reader.startReading() else {
            throw ReverseError.failed(
                reader.error?.localizedDescription ?? "the file could not be read")
        }

        var slice = Slice()
        var videoDone = videoOutput == nil
        var audioDone = audioOutput == nil
        while !videoDone || !audioDone {
            if cancel?.isCancelled == true {
                reader.cancelReading()
                throw ReverseError.cancelled
            }
            if !videoDone {
                if let sample = videoOutput?.copyNextSampleBuffer() {
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    if time.isNumeric, time >= range.start, time < range.end, time < limit,
                        let image = CMSampleBufferGetImageBuffer(sample),
                        let held = copyBuffer(image)
                    {
                        slice.frames.append(Frame(time: time, buffer: held))
                    }
                } else {
                    videoDone = true
                }
            }
            if !audioDone {
                if let sample = audioOutput?.copyNextSampleBuffer() {
                    appendAudioBytes(of: sample, to: &slice.audio)
                } else {
                    audioDone = true
                }
            }
        }
        let status = reader.status
        reader.cancelReading()
        guard status != .failed else {
            throw ReverseError.failed(
                reader.error?.localizedDescription ?? "the file could not be read to the end")
        }
        // Decompressed output arrives in display order on every path measured
        // here, but the reversal is only correct if it really is sorted, and a
        // slice is a few dozen frames.
        slice.frames.sort { $0.time < $1.time }
        return slice
    }

    /// A private copy of a decoded frame.
    ///
    /// The reader hands back buffers from a pool it means to recycle, and this
    /// renderer holds a whole slice of them at once — so they are copied out
    /// rather than retained, which is the difference between a bounded read
    /// and a reader that starves itself. A pool of our own would recycle
    /// nothing (every buffer in a slice is live at the same time), so these
    /// are plain allocations.
    ///
    /// Every plane is copied — the `x420` and `x422` frames are two — and the
    /// decoder's attachments go with them: the colour primaries, transfer
    /// function and matrix the writer labels the file by (spec §11 PR-7).
    private static func copyBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0 else { return nil }
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(source),
            [
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ] as CFDictionary, &created) == kCVReturnSuccess, let target = created
        else { return nil }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(target, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(target, []) }
        let planes = CVPixelBufferGetPlaneCount(source)
        guard planes == CVPixelBufferGetPlaneCount(target) else { return nil }
        if planes == 0 {
            guard let from = CVPixelBufferGetBaseAddress(source),
                let to = CVPixelBufferGetBaseAddress(target)
            else { return nil }
            copyRows(
                from: from, stride: CVPixelBufferGetBytesPerRow(source), to: to,
                stride: CVPixelBufferGetBytesPerRow(target), rows: height)
        }
        for plane in 0..<planes {
            guard let from = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                let to = CVPixelBufferGetBaseAddressOfPlane(target, plane)
            else { return nil }
            copyRows(
                from: from, stride: CVPixelBufferGetBytesPerRowOfPlane(source, plane), to: to,
                stride: CVPixelBufferGetBytesPerRowOfPlane(target, plane),
                rows: min(
                    CVPixelBufferGetHeightOfPlane(source, plane),
                    CVPixelBufferGetHeightOfPlane(target, plane)))
        }
        CVBufferPropagateAttachments(source, target)
        return target
    }

    /// `rows` rows from one buffer (or plane) to another, each the shorter of
    /// the two strides — the padding past a row's pixels is not picture.
    private static func copyRows(
        from: UnsafeMutableRawPointer, stride fromStride: Int, to: UnsafeMutableRawPointer,
        stride toStride: Int, rows: Int
    ) {
        let rowBytes = min(fromStride, toStride)
        for row in 0..<rows {
            memcpy(to + row * toStride, from + row * fromStride, rowBytes)
        }
    }

    /// One audio sample buffer's bytes, appended to the slice's run.
    private static func appendAudioBytes(of sample: CMSampleBuffer, to bytes: inout [UInt8]) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return }
        var copied = [UInt8](repeating: 0, count: length)
        let status = copied.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == kCMBlockBufferNoErr else { return }
        bytes.append(contentsOf: copied)
    }

    // MARK: - Audio

    /// What comes out of the reader and goes into the file: 16-bit
    /// interleaved LPCM at 48 kHz stereo — `ExporterWriter.decodedAudioSettings`
    /// again, so a reversed clip mixes exactly like a forward one, and LPCM in
    /// rather than AAC so an intermediate costs no generation of its own.
    private static let audioSampleRate = 48000
    private static let audioChannels = 2
    private static let audioBytesPerFrame = 4

    private static let decodedAudioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: audioSampleRate,
        AVNumberOfChannelsKey: audioChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    private static let audioSettings: [String: Any] = decodedAudioSettings

    /// The description every block written here carries: 48 kHz stereo,
    /// 16-bit signed, packed, little-endian — `decodedAudioSettings` spelled
    /// as an `AudioStreamBasicDescription`.
    ///
    /// Built rather than taken off the first sample the reader hands back,
    /// because a slice may legitimately contain no sound at all and still have
    /// to write silence into it (see `walkBackwards`). The two descriptions
    /// are the same one either way: the reader was ASKED for this format.
    private static let audioFormat: CMFormatDescription? = {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(audioSampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(audioBytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(audioBytesPerFrame),
            mChannelsPerFrame: UInt32(audioChannels),
            mBitsPerChannel: 16,
            mReserved: 0)
        var format: CMFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr
        else { return nil }
        return format
    }()

    /// A time as a whole number of 48 kHz frames — the unit the audio input's
    /// stamps are counted in, so a slice boundary is an integer and not a
    /// rounding.
    private static func audioFrames(in time: CMTime) -> Int64 {
        let scaled = CMTimeConvertScale(
            time, timescale: CMTimeScale(audioSampleRate), method: .roundHalfAwayFromZero)
        return scaled.isNumeric ? max(0, scaled.value) : 0
    }

    /// One slice's sound as writer-sized blocks, in output order, padded with
    /// silence out to `endFrame` — the frame the picture has reached by the
    /// end of this slice.
    ///
    /// The padding is what keeps the audio input fed through a stretch of the
    /// source that has none, and the blocks are what keep it from running away
    /// from the picture; `walkBackwards` explains why both matter. `written`
    /// is the running frame count, so the blocks are contiguous across slices
    /// and no boundary can round into a click.
    private static func audioBlocks(
        _ bytes: [UInt8], format: CMFormatDescription, from written: inout Int64,
        covering endFrame: Int64
    ) -> [CMSampleBuffer] {
        let width = audioBytesPerFrame
        var run = reversedFrames(bytes)
        let reached = written + Int64(run.count / width)
        if reached < endFrame {
            run.append(
                contentsOf: [UInt8](repeating: 0, count: Int(endFrame - reached) * width))
        }
        // A quarter of a second: far inside the lead an `AVAssetWriter`
        // tolerates, far longer than the per-append cost is worth paying more
        // often.
        let blockFrames = audioSampleRate / 4
        var blocks: [CMSampleBuffer] = []
        var offset = 0
        while offset < run.count {
            let frames = min(blockFrames, (run.count - offset) / width)
            guard frames > 0 else { break }
            let block = Array(run[offset..<(offset + frames * width)])
            guard let sample = audioSample(
                block, format: format,
                at: CMTime(value: written, timescale: CMTimeScale(audioSampleRate)),
                frames: frames)
            else { break }
            blocks.append(sample)
            written += Int64(frames)
            offset += frames * width
        }
        return blocks
    }

    /// The slice's audio with its FRAMES reversed — the channels inside one
    /// frame keep their order, or the left and right would swap.
    private static func reversedFrames(_ bytes: [UInt8]) -> [UInt8] {
        let width = audioBytesPerFrame
        let frames = bytes.count / width
        var out = [UInt8](repeating: 0, count: frames * width)
        for frame in 0..<frames {
            let from = (frames - 1 - frame) * width
            let to = frame * width
            for byte in 0..<width { out[to + byte] = bytes[from + byte] }
        }
        return out
    }

    /// One block of reversed LPCM as a sample buffer. Constant bytes per
    /// frame, so one timing entry and one size entry describe the lot —
    /// `ExporterWriter.chapterSample`'s construction with a different payload.
    private static func audioSample(
        _ bytes: [UInt8], format: CMFormatDescription, at time: CMTime, frames: Int
    ) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let buffer = block,
            CMBlockBufferReplaceDataBytes(
                with: bytes, blockBuffer: buffer, offsetIntoDestination: 0,
                dataLength: bytes.count) == kCMBlockBufferNoErr
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(audioSampleRate)),
            presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = audioBytesPerFrame
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
            sampleCount: CMItemCount(frames), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }

    // MARK: - Settings

    /// The coded frame size, read from one decoded frame at the head of the
    /// file. Nil means "no picture", which an audio-only source really has and
    /// an unreadable video track amounts to.
    private static func dimensions(
        of asset: AVURLAsset, track: AVAssetTrack, limit: CMTime
    ) -> CMVideoDimensions? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTimeMinimum(limit, CompositionBuilder.time(ReelTime.perSecond)))
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(),
            let format = CMSampleBufferGetFormatDescription(sample)
        else { return nil }
        return CMVideoFormatDescriptionGetDimensions(format)
    }

    /// The encoder settings for the picture.
    ///
    /// **The size is the source's, exactly.** Not rounded to even, not scaled:
    /// the compositor maps the model's `source_size` across whatever texture
    /// arrives, so a reversed asset that is one pixel narrower than the
    /// forward one would stretch the clip the moment it is reversed.
    ///
    /// **10 bits at every size (spec §11 PR-7).** HEVC pinned to Main 10 —
    /// `ExporterWriter`'s `hevc_10bit` pin — fed the `x420` frames the reader
    /// decoded, at HEVC's rate: generous because this is an intermediate, its
    /// pixels encoded again on the way to the export, where a stingy one is a
    /// generation of loss the user did not ask for. An odd size is ProRes 422
    /// (`Intermediate`), which takes no compression dictionary.
    ///
    /// **No colour properties.** Given none, the writer labels the file by the
    /// frames' own attachments, which `copyBuffer` carries, so an HLG or a
    /// BT.2020 source is labelled as itself. Forcing BT.709 here mislabelled
    /// those sources, and with the attachments kept it would convert them.
    private static func videoSettings(
        _ dimensions: CMVideoDimensions, fps: Fps, intermediate: Intermediate
    ) -> [String: Any] {
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        guard intermediate == .hevcMain10 else {
            return [
                AVVideoCodecKey: AVVideoCodecType.proRes422,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        }
        let rate = fps.double > 0 ? fps.double : 30
        let bits = Int(
            min(max(Double(max(1, width * height)) * rate * 0.12, 2_000_000), 240_000_000))
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bits,
            // A keyframe at least every two seconds, for the same reason the
            // export sets one: this file is scrubbed and seeked into on every
            // preview frame.
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            AVVideoExpectedSourceFrameRateKey: Int(rate.rounded()),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
        ]
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    /// How much of the source one slice covers: as many frames as the budget
    /// holds at the held format's bytes a pixel (`Intermediate`), turned back
    /// into time. An audio-only file has no frames to hold, so it takes long
    /// slices and pays for very few readers.
    private static func sliceDuration(dimensions: CMVideoDimensions?, fps: Fps) -> CMTime {
        let rate = fps.double > 0 ? fps.double : 30
        guard let dimensions = dimensions, dimensions.width > 0, dimensions.height > 0 else {
            return CompositionBuilder.time(ReelTime.perSecond * 30)
        }
        let bytes =
            Int(dimensions.width) * Int(dimensions.height)
            * Intermediate(dimensions).bytesPerPixel
        let frames = min(max(bufferBudget / max(1, bytes), 4), 300)
        let ticks = Ticks((Double(frames) / rate * Double(ReelTime.perSecond)).rounded())
        return CompositionBuilder.time(max(ticks, 1))
    }

}
