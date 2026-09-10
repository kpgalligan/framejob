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

/// Posted on the main thread when a media file's cache — its filmstrip
/// thumbnails or its waveform peaks — has landed on disk and the timeline
/// can now draw it. `userInfo` carries `MediaImporter.mediaIDKey` (the
/// media id as `UInt32`) and `MediaImporter.cacheKindKey`
/// (`MediaImporter.thumbsKind` or `MediaImporter.peaksKind`).
///
/// Thumbnails post repeatedly as they accumulate, so an observer must be
/// cheap: mark the lane dirty and redraw, never rebuild the timeline.
extension Notification.Name {
    static let mediaCacheDidChange = Notification.Name("ReelcutMediaCacheDidChange")
}

extension MediaImporter {

    // MARK: - Notification keys

    static let mediaIDKey = "media"
    static let cacheKindKey = "cache"
    static let thumbsKind = "thumbs"
    static let peaksKind = "peaks"

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

    /// The cached waveform, or nil when it has not been generated. One float
    /// per 1/100 s, magnitudes 0…1 (louder than full scale is possible and
    /// is not clamped — the lane clamps when it draws).
    static func loadPeaks(for media: UInt32, in cacheDir: URL) -> [Float]? {
        let url = peaksURL(for: media, in: cacheDir)
        guard let data = try? Data(contentsOf: url), data.count >= 4 else { return nil }
        return data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
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

    static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    /// Announces a landed cache on the main thread. Fired from a detached
    /// task, so the hop is not optional: an AppKit observer redrawing from a
    /// background thread is the classic import-time crash.
    static func postCacheChange(media: UInt32, kind: String) {
        let info: [String: Any] = [mediaIDKey: media, cacheKindKey: kind]
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .mediaCacheDidChange, object: nil, userInfo: info)
        }
    }
}
