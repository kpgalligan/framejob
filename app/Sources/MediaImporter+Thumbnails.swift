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

    /// The strip's length in seconds, at least one and at most `maxThumbnails`.
    ///
    /// `media.duration` is the RECORD's, and a file replaced in place
    /// keeps its record, so a file of another length at the old path
    /// sizes this strip — and `peaks`' bucket count — from the old
    /// duration. Recorded here rather than fixed: the marker rebuilds the
    /// strip for the changed file, at the old length — a longer file's
    /// tail is HELD below.
    static func thumbnailSeconds(for media: MediaSnapshot) -> Int {
        max(
            1,
            min(maxThumbnails, Int((Double(media.duration) / Double(ReelTime.perSecond)).rounded(.up))))
    }

    /// The seconds `thumbnails` holds and the times it asks the generator for.
    ///
    /// The seconds at or past `lastTime` are HELD: a suffix (the times are
    /// monotonic), asking for `lastTime` once, written under each of them.
    ///
    /// **What the generator answers between frames, measured** (the R0
    /// spike's own recordings and `tools/proof/remaining_probe.py`'s 5f
    /// fixtures): a second whose displayed frame is a SYNC sample lands
    /// however far after it — 24 s after a keyframe — and a real
    /// ScreenCaptureKit recording lands every second up to its track's end,
    /// 1.6 s after its last, non-sync sample; but an `ffmpeg`-made file of
    /// three frames 25 s apart FAILS (`-11821`, not `-11832`) at every second
    /// inside a non-sync frame's range that is not the frame's own time, and
    /// 0.7 ms after its last frame's time under the VideoToolbox encoder. So
    /// the held request is the frame's exact time and not the track's end
    /// less a frame: the end is stored in the movie timescale and rounds UP
    /// (50.0333 s is 50.034 at 1000), which the composition's window absorbs
    /// and the generator does not.
    static func thumbnailRequests(seconds: Int, lastTime: CMTime) -> (held: [Int], times: [CMTime]) {
        let last = CompositionBuilder.ticks(lastTime)
        let held = (0..<seconds).filter { Ticks($0) * ReelTime.perSecond >= last }
        var times = (0..<(seconds - held.count)).map {
            CompositionBuilder.time(Ticks($0) * ReelTime.perSecond)
        }
        if !held.isEmpty { times.append(lastTime) }
        return (held, times)
    }

    /// The tile indices a landed frame is written under.
    ///
    /// Named by the seconds that ASKED for the requested time, not
    /// by a counter: results arrive in request order today, and a
    /// counter would silently shift the whole strip by one if that
    /// ever stopped being true or a frame failed. `time` and
    /// `ticks` are exact inverses at the tick timescale, so an
    /// unheld second divides exactly; the held request is the one
    /// time in the list off the grid, compared as a time.
    static func tileIndices(requested: CMTime, lastTime: CMTime, held: [Int]) -> [Int] {
        requested == lastTime
            ? held : [Int(CompositionBuilder.ticks(requested) / ReelTime.perSecond)]
    }
}
