import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The await-free half of the media cache: where the two files the timeline
/// draws from live inside the package (`cache/thumbs/<id>/<n>.jpg`,
/// `cache/peaks/<id>.bin`), the three constants that size them, how they are
    /// read back (`loadThumbnail`, `thumbnailCount`, `loadPeaks` — synchronous,
/// because the timeline calls them from `draw(_:)`), the plumbing the two
/// writers stand on, and the notification that says a cache has landed.
///
/// It is an `extension MediaImporter` in a file of its own for one reason.
/// `async`/`await` is allowed in `MediaImporter.swift` and nowhere else
/// (app/CLAUDE.md, spec §11), and that file stood at 619 lines against the
/// ~600 cap with the §2a fix about to land on its cache code. A file at the
/// cap gives something up before it takes anything on, and the one-file rule
/// decides WHAT: the code that does not await — this — leaves, and
/// `generateCaches`, `thumbnails` and `peaks`, the three that do, keep the
/// file that holds the exception. An extension rather than a new type so that
/// every `MediaImporter.x` call site in the tree is exactly what it was.
///
/// Nothing here awaits. The one `Task` (`postCacheChange`) is a hop to the
/// main thread with nothing awaited inside it, and it is the first outside
/// `MediaImporter.swift` — said here because a reader grepping for the
/// keyword the rule names will not find it in this file and might wonder.
///
/// The move cost three widenings: `ensureDirectory`, `writeJPEG` and
/// `postCacheChange` were `private` and are internal, because `thumbnails`
/// and `peaks` call them and `private` does not cross a file. Everything
/// else was already internal for its callers in the timeline, the Media row
/// and the layer renderer, and moved with its doc comment verbatim.
///
/// The §2a fix itself is the "Completion markers" section: `CacheStamp`,
/// the two marker paths, the read/write plumbing, the two clears a pass
/// runs at its head (`clearThumbnails`, `clearPeaks`) and the one check it
/// runs before its marker (`stripHolds`). It is what makes "a cache already
/// on disk is not rebuilt" TRUE, and it lives here because none of it awaits.

/// Posted on the main thread when a media file's cache — its filmstrip
/// thumbnails or its waveform peaks — has landed on disk and the timeline
/// can now draw it, or, for peaks, has been WITHDRAWN: a rebuild removes
/// the old `.bin` at its head and posts at once, as does a pass for a media
/// that no longer has audio (#180), so a `peaks` post means
/// "re-read", and the re-read may find nothing until the pass lands. That
/// is the point — readers consult the marker now, and withdrawing the old
/// file also invalidates any memoized waveform until the pass publishes a
/// complete new one. `userInfo` carries
/// `MediaImporter.mediaIDKey` (the media id as `UInt32`) and
/// `MediaImporter.cacheKindKey` (`MediaImporter.thumbsKind` or
/// `MediaImporter.peaksKind`), and, on the FIRST post of a pass that
/// REPLACED a strip already on disk (a relink, a changed file, a partial
/// strip finished), `MediaImporter.replacedKey` as `true`. The kind stays
/// `thumbs` for those, so an observer that never heard of the flag behaves
/// exactly as it did; the timeline reads it to drop the decoded tiles it is
/// holding, which are the old film's. The voice cache's withdrawal post
/// (`MediaImporter.speech`, kind `speech`, at a stale head or for a media
/// with no audio left) is the flag's second carrier: it, too, opens a pass
/// that replaces a file already on disk. `peaks` posts without it.
///
/// Thumbnails post repeatedly as they accumulate, so an observer must be
/// cheap: mark the lane dirty and redraw, never rebuild the timeline.
extension Notification.Name {
    static let mediaCacheDidChange = Notification.Name("FrameJobMediaCacheDidChange")
}

extension MediaImporter {

    // MARK: - Notification keys

    static let mediaIDKey = "media"
    static let cacheKindKey = "cache"
    static let thumbsKind = "thumbs"
    static let peaksKind = "peaks"
    static let speechKind = "speech"
    static let transcriptsKind = "transcripts"
    /// Present (and `true`) only on the first post from a pass that replaced
    /// a file that was on disk — a `thumbs` rebuild, or the `speech`
    /// withdrawal at `MediaImporter.speech`'s head, a media with no audio's
    /// included; absent otherwise, never `false`.
    static let replacedKey = "replaced"

    // MARK: - Cache layout

    /// Filmstrip height in pixels. One thumbnail per second, capped, so a
    /// long recording costs a bounded amount of disk (§5.6).
    static let thumbnailHeight = 160.0
    static let maxThumbnails = 600
    /// Waveform resolution: 100 buckets a second, the `cache/peaks` format.
    static let peakBucketsPerSecond = 100

    /// `cache/thumbs/<media id>/` inside the document package.
    static func thumbsDirectory(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent(String(media), isDirectory: true)
    }

    /// `cache/peaks/<media id>.bin` inside the document package.
    static func peaksURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("peaks", isDirectory: true)
            .appendingPathComponent("\(media).bin")
    }

    /// `cache/speech/<media id>.bin` inside the document package — one Float32
    /// per Silero VAD chunk (`MediaSpeech.chunkTicks`), `peaksURL`'s shape.
    static func speechURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("speech", isDirectory: true)
            .appendingPathComponent("\(media).bin")
    }

    /// `cache/speech/<media id>.complete.json`, `peaksMarkerURL`'s shape: a
    /// sidecar beside the `.bin`, not a child, so either can be deleted
    /// without the other.
    static func speechMarkerURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("speech", isDirectory: true)
            .appendingPathComponent("\(media).complete.json")
    }

    // MARK: - Completion markers

    /// What a finished pass writes LAST, and the only thing that lets the
    /// next pass skip. Its content is the stamp of the file the pass read.
    ///
    /// Existence alone could never be the test. `thumbs/<id>/` and
    /// `peaks/<id>.bin` are named by a media ID, and an id outlives the file
    /// behind it — Relink… keeps the id and changes the file
    /// (`core/src/edit_relink.rs`), so the directory of a relinked media is
    /// already there, holding the OLD film's frames, and a pass that skipped
    /// on existence would leave them there for ever: a wrong picture, and
    /// wrong edits, because Remove Silences and Normalize read the peaks of
    /// the old file. The directory also outlives a pass that was cut short —
    /// a first save while a pass runs copies whatever frames had landed into
    /// the package while the task keeps writing into the temporary directory
    /// it captured, and process death does the same — so "it exists" says
    /// neither that the pass FINISHED nor that it read THIS file. The marker
    /// says both: it is written after the last frame (a hole left by a frame
    /// that would not decode is still a finished pass — complete is not a
    /// count, and `thumbnailCount` can never define it), and a pass skips
    /// only when the marker decodes EQUAL to the stamp of the file the media
    /// points at now.
    ///
    /// In the stamp: the source file's byte size and modification SECOND
    /// (rounded, the reversed cache's convention); the media-record fields
    /// that SIZE the caches — `duration` sets the frame count and the bucket
    /// count, `width`/`height` the tile's aspect, `hasVideo`/`hasAudio`
    /// which halves exist; and the three generator constants, so a build
    /// that changes any of them invalidates every cache written under the
    /// old value rather than serving a 160 px strip to a lane that asked for
    /// 200. The record's fields, not the file's: a file replaced in place
    /// keeps its record, so a longer file at the old path keeps the old
    /// `duration`, and the strip it sizes is the old length — a limit
    /// (`thumbnails` records it) that the marker inherits rather than fixes.
    ///
    /// NOT in it, deliberately: the path. The tree's two digests
    /// (`ReverseCache.digest`, `FFmpegRewrap.digest`) hash the path in
    /// because each names a file inside a directory SHARED with other
    /// sources, and the path is what keeps two sources apart there. This
    /// marker sits inside one media's own cache and has nothing to
    /// disambiguate against — and leaving the path out is exactly what lets a
    /// moved package, a consolidated copy (`copyItem` keeps the modification
    /// date; measured by `tools/proof/remaining_proof.py`) and a copy on
    /// another disk keep every filmstrip. Nor is it a content hash, for the
    /// reason those two give: reading gigabytes to decide whether to decode
    /// gigabytes is the wrong trade, and size with modification second
    /// already distinguishes every file this will see.
    ///
    /// `nil` when the file cannot be stat'ed, and a nil stamp NEVER skips and
    /// NEVER writes a marker: the pass runs as it always did and leaves
    /// nothing behind that a later pass could trust.
    struct CacheStamp: Codable, Equatable {
        let size: Int64
        let modified: Int64
        let duration: Ticks
        let width: Int
        let height: Int
        let hasVideo: Bool
        let hasAudio: Bool
        let thumbnailHeight: Double
        let maxThumbnails: Int
        let peakBucketsPerSecond: Int

        static func stamp(for media: MediaSnapshot, url: URL) -> CacheStamp? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = (attributes[.size] as? NSNumber)?.int64Value,
                let modified = attributes[.modificationDate] as? Date
            else { return nil }
            return CacheStamp(
                size: size, modified: Int64(modified.timeIntervalSince1970.rounded()),
                duration: media.duration, width: media.width, height: media.height,
                hasVideo: media.hasVideo, hasAudio: media.hasAudio,
                thumbnailHeight: MediaImporter.thumbnailHeight,
                maxThumbnails: MediaImporter.maxThumbnails,
                peakBucketsPerSecond: MediaImporter.peakBucketsPerSecond)
        }
    }

    /// The strip's marker is INSIDE the strip's own directory —
    /// `cache/thumbs/<media id>/complete.json` — so deleting the directory
    /// deletes the marker with it and nothing can certify a strip that is
    /// gone. It ends in `.json`, not `.jpg`: `thumbnailCount` counts the
    /// `.jpg` suffix and a marker must never be counted as a frame.
    static let thumbsMarkerName = "complete.json"

    static func thumbsMarkerURL(for media: UInt32, in cacheDir: URL) -> URL {
        thumbsDirectory(for: media, in: cacheDir).appendingPathComponent(thumbsMarkerName)
    }

    /// `cache/peaks/<media id>.complete.json`, a SIDECAR beside the `.bin`,
    /// which keeps its name: `cache/peaks/<media id>.bin` is spelled by spec
    /// §5.6, by `MediaPeaks`, `SilenceDetector` and `AgentServer+Audio`, and
    /// by the phase 3 and phase 5 proofs, and the reversed cache's
    /// `<id>-<digest>` naming would break every one of them. A sibling can be
    /// deleted without its marker, so `peaks` asks for both.
    static func peaksMarkerURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("peaks", isDirectory: true)
            .appendingPathComponent("\(media).complete.json")
    }

    /// The stamp a marker holds, or nil when there is no marker or it will
    /// not decode — a marker of a different shape (an older build's) reads
    /// as absent, which is the answer that rebuilds.
    static func readStamp(at url: URL) -> CacheStamp? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheStamp.self, from: data)
    }

    /// Sorted keys make repeat markers of the same kind byte-identical;
    /// `.atomic`, so a marker is whole or
    /// absent and never a truncated file that decodes to nothing. Generic
    /// since `SpeechStamp` wraps a `CacheStamp` rather than sharing its
    /// type. `CacheStamp` itself is unchanged; peaks use their own versioned
    /// wrapper, while thumbnail and speech identities remain independent.
    @discardableResult
    static func writeStamp<S: Encodable>(_ stamp: S, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stamp) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// The stamp `cache/speech/<id>.complete.json` carries — a `CacheStamp`
    /// plus the model and chunk size that made the file, so a build that
    /// changes either rebuilds every speech cache without touching the
    /// thumbs or peaks markers, which share `source`'s underlying stamp.
    struct SpeechStamp: Codable, Equatable {
        let source: CacheStamp
        let speechModel: String
        let speechChunkSamples: Int

        init(_ source: CacheStamp) {
            self.source = source
            self.speechModel = SileroVAD.modelName
            self.speechChunkSamples = SileroVAD.chunkSamples
        }
    }

    /// `readStamp`'s sibling for the speech marker.
    static func readSpeechStamp(at url: URL) -> SpeechStamp? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpeechStamp.self, from: data)
    }

    /// Clears a strip a pass is about to rebuild. The marker goes FIRST, so
    /// a crash anywhere after this line leaves no marker over a half strip;
    /// then every `.jpg`, because they are the old film, or a partial strip
    /// whose indices would otherwise mix with the new pass's. Returns
    /// whether anything was there — the `replaced` flag the pass posts.
    static func clearThumbnails(in directory: URL) -> Bool {
        let manager = FileManager.default
        var removed = false
        let marker = directory.appendingPathComponent(thumbsMarkerName)
        if manager.fileExists(atPath: marker.path) {
            try? manager.removeItem(at: marker)
            removed = true
        }
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasSuffix(".jpg") {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
            removed = true
        }
        return removed
    }

    /// Clears a waveform a pass is about to rebuild — `clearThumbnails`'
    /// posture for the other half. The marker goes FIRST, for the same
    /// reason; then the `.bin`, because it is the old file's. `loadPeaks` is
    /// the ONE reader; the timeline, `MediaPeaks.Loader` (Remove Silences and
    /// Normalize) and the Media row all read through it, and each memoises
    /// what it read as a hit. The old file must be withdrawn rather than
    /// left for a later marker to recertify after a pass
    /// that returned early (a file replaced in place by one with no audio
    /// track keeps its record, `hasAudio` true, and returns at the track
    /// load). Returns
    /// whether a `.bin` was REMOVED — the fact that requires a reader
    /// notification — and the pass posts at
    /// once when it was, so every memo drops the withdrawn floats and the
    /// detector reports the media as pending rather than measuring them. A
    /// media with no audio left (#180) runs it too, and posts the same way.
    static func clearPeaks(for media: UInt32, in cacheDir: URL) -> Bool {
        let manager = FileManager.default
        try? manager.removeItem(at: peaksMarkerURL(for: media, in: cacheDir))
        let file = peaksURL(for: media, in: cacheDir)
        guard manager.fileExists(atPath: file.path) else { return false }
        return (try? manager.removeItem(at: file)) != nil
    }

    /// Whether a pass can vouch for the strip it wrote: `frames`, the
    /// indices its `writeJPEG` succeeded on, is not empty, and every one of
    /// them is in the directory NOW, read in one listing. The marker is
    /// written only when this answers true, which folds two refusals into
    /// one rule.
    ///
    /// EMPTY refuses because a pass that wrote nothing is not a strip with
    /// holes, it is a reader that failed — a stalled volume, a file
    /// AVFoundation refuses today — and a marker over it would stop every
    /// retry until the file's size or date moved, where the peaks half's
    /// silent returns deliberately write no marker and try again.
    ///
    /// MISSING refuses because of what a save of a TITLED document does
    /// while a pass is running: NSDocument lists `thumbs/<id>/` once for its
    /// lazy wrapper and later SWAPS the new package in, so a frame written
    /// between the listing and the swap goes with the old directory, while
    /// every frame after the swap lands by path in the new one. The pass
    /// cannot see the swap, but it can see the holes — a frame it wrote that
    /// is not there — and a strip with holes it will never fill is exactly
    /// what a marker must not certify; without one the next open rebuilds,
    /// as it did before the marker existed. The listing and the marker run
    /// inside one `CacheLedger.publish`, which no announced save overlaps.
    static func stripHolds(_ frames: Set<Int>, in directory: URL) -> Bool {
        guard !frames.isEmpty,
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return false }
        let present = Set(names)
        return frames.allSatisfy { present.contains("\($0).jpg") }
    }

    // MARK: - Thumbnails

    /// One cached thumbnail, or nil when that second has not been generated
    /// (or failed). Synchronous — the timeline calls it from `draw(_:)`.
    static func loadThumbnail(for media: UInt32, index: Int, in cacheDir: URL) -> CGImage? {
        guard index >= 0 else { return nil }
        let url = thumbsDirectory(for: media, in: cacheDir)
            .appendingPathComponent("\(index).jpg")
        return decodeImage(url, maxPixelSize: 0)
    }

    /// How many thumbnails are on disk for `media` — what the timeline needs
    /// to decide whether a filmstrip is worth drawing at all.
    static func thumbnailCount(for media: UInt32, in cacheDir: URL) -> Int {
        let directory = thumbsDirectory(for: media, in: cacheDir)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".jpg") }.count
    }

    // MARK: - Peaks

    /// The cached waveform, or nil until a complete decode is certified by
    /// the versioned marker. Legacy and malformed cache files are never
    /// treated as silence. Magnitudes above one remain unclamped.
    static func loadPeaks(for media: UInt32, in cacheDir: URL) -> [Float]? {
        guard let marker = readPeaksStamp(at: peaksMarkerURL(for: media, in: cacheDir)) else {
            return nil
        }
        let duration = Double(marker.source.duration) / Double(ReelTime.perSecond)
        let count = (duration * Double(peakBucketsPerSecond)).rounded(.up)
        guard count.isFinite, count >= 1, count < Double(Int.max / 4) else { return nil }
        let expectedBytes = max(1, Int(count)) * MemoryLayout<Float>.size
        let url = peaksURL(for: media, in: cacheDir)
        guard let data = try? Data(contentsOf: url), data.count == expectedBytes else { return nil }
        let values = data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return values
    }

    /// The cached Silero VAD probabilities, or nil when they have not been
    /// generated — `loadPeaks`' shape for `cache/speech/<id>.bin`.
    static func loadSpeech(for media: UInt32, in cacheDir: URL) -> [Float]? {
        let url = speechURL(for: media, in: cacheDir)
        guard let data = try? Data(contentsOf: url), data.count >= 4 else { return nil }
        return data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }

    /// `clearPeaks`' shape: the marker first, then the `.bin`. Returns
    /// whether a `.bin` was removed. A media with no audio left runs it too
    /// (#180), and its post carries `replaced`, as the stale head's does.
    @discardableResult
    static func clearSpeech(for media: UInt32, in cacheDir: URL) -> Bool {
        let manager = FileManager.default
        try? manager.removeItem(at: speechMarkerURL(for: media, in: cacheDir))
        let file = speechURL(for: media, in: cacheDir)
        guard manager.fileExists(atPath: file.path) else { return false }
        return (try? manager.removeItem(at: file)) != nil
    }

    // MARK: - Small shared plumbing

    static func ensureDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)) != nil
            || FileManager.default.fileExists(atPath: url.path)
    }

    /// ImageIO decode bounded by `maxPixelSize` (0 = the file's own size).
    /// Used for still media and for reading a cached thumbnail back.
    static func decodeImage(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if maxPixelSize > 0 { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Whether the file was finalised — what `thumbnails` records per index
    /// so `stripHolds` checks only frames that were actually written.
    @discardableResult
    static func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Announces a landed cache on the main thread. Fired from a detached
    /// task, so the hop is not optional: an AppKit observer redrawing from a
    /// background thread is the classic import-time crash. `replaced` adds
    /// `replacedKey` — present only when true, so an observer that tests for
    /// the key and one that reads its value agree.
    static func postCacheChange(media: UInt32, kind: String, replaced: Bool = false) {
        var info: [String: Any] = [mediaIDKey: media, cacheKindKey: kind]
        if replaced { info[replacedKey] = true }
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .mediaCacheDidChange, object: nil, userInfo: info)
        }
    }
}
