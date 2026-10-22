import AVFoundation

/// The await-free halves of the thumbnail pass — `writeImageThumbnail` (a still's one tile, its
/// marker and its post; an HLG or PQ still's tile drawn by `MediaImporter.thumbnails` through
/// `stillReader`, spec §11 HD-21) and `publishThumbnails` (a movie's marker and last post, after
/// `thumbnails(for:url:stamp:into:pass:input:)` has drawn its frames). An `extension
/// MediaImporter` in a file of its own for the same reason `MediaImporter+Speech.swift` is:
/// `async`/`await` is confined to `MediaImporter.swift`, and these pieces of the pass do not need
/// it (hdr H-0, a pure move).
extension MediaImporter {

    /// With no `input`, today's tile and flat marker exactly. With one, `drawn` (the one-clip
    /// composition's picture) and the converted marker; a `drawn` that failed writes today's
    /// tile and no marker, so the next open draws it again (spec §11 HD-21).
    static func writeImageThumbnail(
        for media: MediaSnapshot, url: URL, stamp: CacheStamp?, into cacheDir: URL,
        pass: CachePass?, directory: URL, marker: URL, replaced: Bool,
        input: ThumbnailInput?, drawn: CGImage?
    ) {
        // The indices `writeJPEG` succeeded on: what the marker vouches for.
        var written: Set<Int> = []
        if let image = drawn ?? decodeImage(url, maxPixelSize: Int(thumbnailHeight * 4)),
            pass?.isCurrent() ?? true,
            writeJPEG(image, to: directory.appendingPathComponent("0.jpg")) {
            written.insert(0)
        }
        if let stamp, input == nil || drawn != nil {
            CacheLedger.shared.publish(in: cacheDir, for: pass) {
                if stripHolds(written, in: directory) {
                    writeThumbsStamp(stamp, input: input, fullRange: false, to: marker)
                }
            }
        }
        // Posted whether or not the picture decoded: the old tile is
        // gone either way, and a memo still holding it would draw a
        // picture the package no longer has.
        postCacheChange(media: media.id, kind: thumbsKind, replaced: replaced)
    }

    /// AFTER the loop and never inside it: a hole left by a frame that
    /// would not decode is still a finished pass — complete is not a
    /// count. But only when the pass wrote at least one frame and every
    /// frame it wrote is still there (`stripHolds` argues both halves: a
    /// pass that wrote nothing is a failed reader to retry, and a frame
    /// that is gone is a titled document's save having swapped the
    /// package under the pass); otherwise NO marker, and the next open
    /// rebuilds, exactly as before the marker existed. And only for a
    /// stamp that exists; nothing certifies a strip made from a file that
    /// could not be measured. The listing and the marker run inside one
    /// publication, which no announced save overlaps.
    static func publishThumbnails(
        _ written: Set<Int>, reader: ThumbnailReader, for media: MediaSnapshot,
        stamp: CacheStamp?, into cacheDir: URL, pass: CachePass?, directory: URL,
        marker: URL, replaced: Bool
    ) {
        if let stamp, reader.certifies {
            CacheLedger.shared.publish(in: cacheDir, for: pass) {
                guard stripHolds(written, in: directory) else { return }
                writeThumbsStamp(stamp, input: reader.input, fullRange: reader.fullRange, to: marker)
            }
        }
        postCacheChange(media: media.id, kind: thumbsKind, replaced: replaced)
    }
}
