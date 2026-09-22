import AVFoundation
import Accelerate
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Everything that reads a media FILE: probing it into the `media[]`
/// descriptor `add_media` takes, and generating the two caches the timeline
/// draws from (spec §7.7).
///
/// This is the ONE file where `async`/`await` is allowed (app/CLAUDE.md):
/// AVFoundation's property loading is async-only going forward, and the
/// alternative — the deprecated synchronous accessors — blocks the main
/// thread on a network volume. Callers outside this file stay synchronous by
/// using the completion-handler wrappers (`probe(url:completion:)`,
/// `generateCaches(for:url:in:)`), which keep every `await` on this side of
/// the seam.
///
/// The other half of the media story lives in `ReelCore.swift`:
/// `MediaDescriptor` (what `probe` returns) and `mediaURL(for:)` /
/// `bookmarkString(for:)` (how a descriptor's path is resolved back to a
/// file).
enum MediaImporter {

    // MARK: - Probing

    /// The `media[]` descriptor for a file: duration, display size, rate and
    /// the two track flags (spec §7.7). Throws `ImportError` for a file
    /// nothing can open; never crashes on a truncated or hostile file.
    ///
    /// The size reported is the DISPLAY size — `naturalSize` through
    /// `preferredTransform` — so a portrait iPhone clip imports as
    /// 1080×1920, not 1920×1080 with a rotation nobody applied. Getting this
    /// wrong is invisible until the first phone clip lands sideways on the
    /// canvas, which is why it is the verification of M1 step 3.
    ///
    /// **AVFoundation only.** The opt-in ffmpeg step lives one level up, in
    /// `probeAllowingRewrap`, so this stays the pure "what does the system
    /// think of this file" question that the rewrap's own re-probe can ask
    /// without recursing.
    static func probe(url: URL) async throws -> MediaDescriptor {
        if isImage(url) { return try probeImage(url) }
        return try await probeAsset(url)
    }

    /// The queue the completion-handler face probes on. A serial queue, not
    /// the cooperative pool: a conversion (`FFmpegRewrap`) blocks its thread
    /// for as long as ffmpeg runs, which is exactly what a cooperative
    /// thread must never do, and serialising means a batch drop of four
    /// unreadable files asks four questions in order rather than stacking
    /// four alerts. `app/CLAUDE.md` names import as one of the documented
    /// `DispatchQueue` seams.
    private static let importQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.import", qos: .userInitiated)

    /// The synchronous face of `probe` for the rest of the app: the result
    /// arrives on the main thread, so the caller can go straight to
    /// `add_media` + `add_clip` without ever writing `await`.
    static func probe(
        url: URL, completion: @escaping (Result<MediaDescriptor, any Error>) -> Void
    ) {
        importQueue.async {
            let outcome = Result { try probeAllowingRewrap(url) }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// The AVFoundation probe plus spec §11's opt-in ffmpeg step, and the
    /// body of both synchronous faces.
    ///
    /// The two halves are deliberately not nested inside `probe(url:)`.
    /// `waitForProbe` puts a 30-second ceiling on AVFoundation, which is
    /// right for reading headers and catastrophically wrong for a transcode;
    /// `FFmpegRewrap.assist` therefore runs OUTSIDE it, unbounded, and its
    /// result is probed with a fresh ceiling of its own. `assist` also needs
    /// the main thread for its consent alert, which it can only have because
    /// this function's callers are never the thread being waited on.
    ///
    /// Every one of the four import paths funnels through here — document
    /// open (`ProjectDocument.readMediaFile`), File ▸ Add Media… and Finder
    /// drops (`ProjectDocument.probeNext`), and the agent's `import_media`
    /// (`AgentServer+Media.probe`) — so an MKV opens the same way in all of
    /// them, and `assist` answering `nil` leaves all four with exactly the
    /// failure they report on a machine that has no ffmpeg.
    ///
    /// **Known cost of the document-open path.** Three of those four callers
    /// are already off the main thread, so ffmpeg runs with the UI live. The
    /// fourth, `read(from:ofType:)`, is *allowed* to run on main (its own
    /// comment says NSDocumentController does not always take the concurrent
    /// read queue), and there it blocks: opening a WebM straight from the
    /// Finder can beachball for the length of the encode. The consent alert
    /// states the cost first, which is the mitigation available from here —
    /// a progress sheet would need a seam in `ProjectDocument`, which owns
    /// the sheet-presenting side of every long operation.
    private static func probeAllowingRewrap(_ url: URL) throws -> MediaDescriptor {
        do {
            return try waitForProbe(url)
        } catch let failure as ImportError where failure.invitesFFmpeg && !isImage(url) {
            // Images are excluded because ImageIO's refusal means the picture
            // is corrupt, not that the container is exotic — and a PNG is not
            // something to hand to a video converter.
            guard let rewrapped = try FFmpegRewrap.assist(url) else { throw failure }
            do {
                return try waitForProbe(rewrapped)
            } catch {
                // ffmpeg wrote a file AVFoundation still will not open. The
                // conversion is cached by name, so leaving it there would
                // hand the same broken result back for ever; throwing it away
                // makes the next attempt a real attempt. The error reported
                // is the ORIGINAL one, because the file the user chose is the
                // one they are being told about.
                FFmpegRewrap.discard(rewrapped)
                throw failure
            }
        }
    }

    /// Carries one probe's outcome across the semaphore in `waitForProbe`.
    /// Unchecked because the join is the synchronisation: the detached task
    /// writes it, signals, and never touches it again; the waiter reads it
    /// only after the wait returns.
    private final class ProbeBox: @unchecked Sendable {
        var outcome: Result<MediaDescriptor, any Error>?
    }

    /// The BLOCKING face of `probe`, for `ProjectDocument.read(from:ofType:)`.
    ///
    /// That method is synchronous by contract and CAN run on the main thread
    /// — NSDocumentController's open path does not always take the concurrent
    /// read queue, and every agent tool call hops to main before it opens
    /// anything. So this must never wait on the main actor. The obvious
    /// spelling (a completion delivered through `MainActor.run`, joined with
    /// a `DispatchGroup`) deadlocks exactly there: the waiter is holding the
    /// one thread the completion needs, and the open dies on the timeout
    /// instead of the file. Here the work runs on the cooperative pool and
    /// the result comes back through a plain semaphore, so the waiting thread
    /// is never the thread being waited on.
    static func probeBlocking(url: URL) throws -> MediaDescriptor {
        try probeAllowingRewrap(url)
    }

    /// One AVFoundation probe, waited for from whatever thread called —
    /// `probeBlocking`'s original body, now shared with the
    /// completion-handler face and used twice per assisted import (once on
    /// the file the user chose, once on what ffmpeg made of it).
    private static func waitForProbe(_ url: URL) throws -> MediaDescriptor {
        let box = ProbeBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do {
                box.outcome = .success(try await probe(url: url))
            } catch {
                box.outcome = .failure(error)
            }
            semaphore.signal()
        }
        // Generous, and only a backstop: a probe reads headers, not samples.
        // A file on a stalled network mount is the case this exists for.
        guard semaphore.wait(timeout: .now() + 30) == .success,
            let outcome = box.outcome
        else {
            throw ImportError.timedOut(url)
        }
        return try outcome.get()
    }

    /// AVFoundation's view of a movie or a sound file.
    private static func probeAsset(_ url: URL) async throws -> MediaDescriptor {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let duration = try? await asset.load(.duration), duration.isNumeric else {
            throw ImportError.unreadable(url)
        }
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
            throw ImportError.noTracks(url)
        }

        var width = 0
        var height = 0
        var fps = Fps.thirty
        var hasAlpha = false
        if let track = videoTracks.first {
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            // `applying` maps the whole rectangle, so a 90° preferred
            // transform swaps the components and negates one of them; the
            // magnitudes are the display size.
            let mapped = natural.applying(transform)
            width = Int(abs(mapped.width).rounded())
            height = Int(abs(mapped.height).rounded())
            fps = await frameRate(of: track)
            hasAlpha = await hasAlphaChannel(track)
        }

        let kind: MediaKind = videoTracks.isEmpty ? .audio : .video
        return MediaDescriptor(
            path: url.path, bookmark: bookmarkString(for: url), kind: kind,
            duration: CompositionBuilder.ticks(duration), width: width, height: height, fps: fps,
            hasVideo: !videoTracks.isEmpty, hasAudio: !audioTracks.isEmpty, hasAlpha: hasAlpha)
    }

    /// A track's rate as an exact rational. `nominalFrameRate` is a Float and
    /// lies slightly (29.97003 for 30000/1001), so it is matched against the
    /// common rates rather than trusted; a file that reports nothing falls
    /// back to `minFrameDuration`, which IS exact when the container carries
    /// it.
    private static func frameRate(of track: AVAssetTrack) async -> Fps {
        var nominal = Double((try? await track.load(.nominalFrameRate)) ?? 0)
        if !(nominal > 0), let minimum = try? await track.load(.minFrameDuration),
            minimum.isNumeric, minimum.seconds > 0 {
            nominal = 1 / minimum.seconds
        }
        return rationalFrameRate(nominal)
    }

    /// Whether the codec carries alpha. The format description's own flag
    /// first (ProRes 4444 and animation-with-alpha set it); the codec type is
    /// the fallback for files whose writer omitted the extension.
    private static func hasAlphaChannel(_ track: AVAssetTrack) async -> Bool {
        guard let descriptions = try? await track.load(.formatDescriptions) else { return false }
        for description in descriptions {
            if let flag = CMFormatDescriptionGetExtension(
                description, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel)
                as? Bool, flag {
                return true
            }
            switch CMFormatDescriptionGetMediaSubType(description) {
            // 'ap4h' ProRes 4444, 'ap4x' ProRes 4444 XQ, 'rle ' animation.
            case 0x6170_3468, 0x6170_3478, 0x726C_6520:
                return true
            default:
                continue
            }
        }
        return false
    }

    // MARK: - Cache generation

    /// Kicks off both caches in the background and returns immediately —
    /// the synchronous entry point every call site uses: the open path, the
    /// import path, the three relink paths, Consolidate and Add Background,
    /// all through `ProjectDocument.generateCaches`'s whole-media loop. That
    /// loop is cheap to run over media whose caches are done: the task stats
    /// the file ONCE into a `CacheStamp` (`MediaCacheFiles.swift`) and hands
    /// it to both halves, each of which reads its completion marker and
    /// returns when the two are equal — one stat, a marker read per half and
    /// a `fileExists` for the `.bin` per media with nothing to do, and a
    /// decode only for one whose file is new, changed, or whose last pass
    /// never finished. One stamp for both halves is also what keeps the two
    /// markers from disagreeing when the file changes between them. A nil
    /// stamp (the file cannot be stat'ed) is enqueued and runs like any
    /// other: it can neither skip nor mark, and running is the conservative
    /// direction — the cache is made, and nothing certifies it.
    ///
    /// Nothing cancels the task — not the document closing, not a save — so
    /// a half-written strip is never a cancelled one. It is one of three,
    /// and since a marker is written after the last frame and never before,
    /// all three leave a strip with no marker for the next call to rebuild.
    /// A FIRST SAVE while a pass runs: the task keeps writing into the
    /// temporary directory it captured while `fileWrapper(ofType:)` copies
    /// into the package only the frames that had landed, and nothing re-runs
    /// the pass after a save. Process death. And a save of a TITLED document
    /// straddling a pass, which SWAPS the package under it: NSDocument lists
    /// `thumbs/<id>/` once for its lazy wrapper and swaps the new package in,
    /// so a frame written between the listing and the swap goes with the old
    /// directory while every frame after the swap lands by path in the new
    /// one — holes the pass will never fill, which a marker written by path
    /// would have certified for ever. `thumbnails` therefore checks, before
    /// its marker, that every frame it wrote is still there (`stripHolds`)
    /// and writes none when any is missing.
    ///
    /// One pass per (cache directory, media id) at a time. Two passes for
    /// one media can be asked for in quick succession — open then relink,
    /// relink twice, import then Consolidate — and used to run concurrently:
    /// each thumbnail is written whole (ImageIO stages and renames), but
    /// frames from two SOURCES could interleave in one `thumbs/<id>/`, and
    /// under a marker the later-finishing pass would certify the mixed strip
    /// until the source next changed. So the new task awaits the previous
    /// pass's before it runs, and because each pass re-checks the marker at
    /// its head, a queued redundant pass costs the no-op price above. The
    /// bookkeeping is `CacheLedger` (`MediaCacheFiles.swift`, where nothing
    /// awaits); the awaiting is here, inside the task, so this stays
    /// synchronous. The tasks run in the order they were asked for, which
    /// is load-bearing — the ledger's doc says why. The ledger's price: a
    /// pass that never completes (a stalled network volume) holds every
    /// later pass for that media behind it, a relink AWAY from the stalled
    /// file included, where before the ledger the relink's pass ran beside
    /// it and finished. The escape — cancel the previous pass when the URL
    /// differs — is not built: it cannot reach a pass stuck inside one
    /// AVFoundation call, and for a pass that is merely slow it brings back
    /// the interleave the ledger exists to prevent.
    static func generateCaches(for media: MediaSnapshot, url: URL, in cacheDir: URL) {
        CacheLedger.shared.enqueue(cacheDir: cacheDir, media: media.id) { previous, done in
            Task.detached(priority: .utility) {
                await previous?.value
                // After the await: the stamp is of the file as THIS pass
                // finds it, not as it was when the pass was asked for.
                let stamp = CacheStamp.stamp(for: media, url: url)
                await thumbnails(for: media, url: url, stamp: stamp, into: cacheDir)
                await peaks(for: media, url: url, stamp: stamp, into: cacheDir)
                await speech(for: media, url: url, stamp: stamp, into: cacheDir)
                done()
            }
        }
    }

    // MARK: - Thumbnails

    /// Writes the filmstrip for `media`: 160 px tall JPEGs, one per second up
    /// to `maxThumbnails`, into `cache/thumbs/<id>/<index>.jpg`. Posts
    /// `.mediaCacheDidChange` as batches land so the timeline fills in while
    /// the rest is still decoding.
    ///
    /// Tolerance is deliberately half a second in both directions: a
    /// filmstrip wants the nearest keyframe, not an exact frame, and zero
    /// tolerance here makes a long clip take minutes instead of seconds.
    ///
    /// **A second at or past the VIDEO track's last frame asks for that
    /// frame** (road map 3's R0 surprise). A screen recording's picture ends
    /// at the last screen change while its sound runs on, and the record's
    /// `duration` is the asset's — the sound's — so every second past the
    /// picture's end FAILED (`AVFoundationErrorDomain -11832`) and left a
    /// tinted hole under a marker that certified it: a narrated still screen
    /// read as a strip of holes. The cure is at the REQUEST, not in the
    /// failure arm: the last frame's own time is read off the TRACK
    /// (`lastFrameTime`, in the one file that may `await`), the held seconds
    /// ask for it ONCE, and the one decode is written under each of them — a
    /// static ten-minute recording costs one tail decode, not six hundred —
    /// and the strip is TRUE, since `CompositionBuilder.fill` holds that same
    /// frame over the same tail. It is the TRACK's frame and never the
    /// record's: a sparse recording's `nominalFrameRate` is its frame count
    /// over its length — three frames in 50 s read as 0.06 fps, a 16.7 s
    /// "frame" — so a tail measured from the record's rate held the slide
    /// BEFORE the last one from 34 s on while the composition showed the
    /// last. Copying the last landed tile under a FAILED request instead
    /// would have drawn a freeze wherever a frame inside the picture will not
    /// decode; a failure still leaves a hole. A file with no video track, or
    /// none AVFoundation can open, has no end to read and runs as it always
    /// did. The every-16 post counts TILES, so a held tail posts as its
    /// seconds land and an ordinary strip posts as it did.
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
    ///
    /// Skipped outright when `thumbs/<id>/complete.json` holds `stamp` — the
    /// file's `CacheStamp` as `generateCaches` measured it: no decode, no
    /// post. Otherwise whatever is on disk is cleared first and the marker
    /// is written after the loop, so the marker means "a pass over this file
    /// finished, and what it wrote is here" and nothing weaker.
    static func thumbnails(
        for media: MediaSnapshot, url: URL, stamp: CacheStamp?, into cacheDir: URL
    ) async {
        guard media.hasVideo else { return }
        let directory = thumbsDirectory(for: media.id, in: cacheDir)
        let marker = thumbsMarkerURL(for: media.id, in: cacheDir)
        // The head check. A nil stamp (the file cannot be stat'ed) never
        // skips, and never writes a marker below either.
        if let stamp, readStamp(at: marker) == stamp { return }
        guard ensureDirectory(directory) else { return }
        // What is on disk is the old film or a partial pass. The marker goes
        // first, then the frames (`clearThumbnails` says why in that order).
        // `replaced` rides the FIRST post of this pass and no other. The
        // timeline memoises decoded tiles, so the old film's are in its memo
        // and the first post must drop them; the first also suffices,
        // because nothing of the old film is on disk once `clearThumbnails`
        // returns — every tile memoised after that post is this pass's, and
        // a miss is cleared by every post anyway. On every post it would
        // empty the whole media's memo every sixteen frames for nothing.
        var replaced = clearThumbnails(in: directory)
        // The indices `writeJPEG` succeeded on: what the marker vouches for.
        var written: Set<Int> = []

        if media.kind == .image {
            if let image = decodeImage(url, maxPixelSize: Int(thumbnailHeight * 4)),
                writeJPEG(image, to: directory.appendingPathComponent("0.jpg")) {
                written.insert(0)
            }
            if let stamp, stripHolds(written, in: directory) { writeStamp(stamp, to: marker) }
            // Posted whether or not the picture decoded: the old tile is
            // gone either way, and a memo still holding it would draw a
            // picture the package no longer has.
            postCacheChange(media: media.id, kind: thumbsKind, replaced: replaced)
            return
        }

        // `media.duration` is the RECORD's, and `relink_media` never
        // re-probes (`core/src/edit_track.rs` replaces path and bookmark
        // only), so a relink to a file of another length sizes this strip —
        // and `peaks`' bucket count — from the old duration. Pre-existing,
        // recorded here rather than fixed: the marker rebuilds the strip on
        // a relink, at the old length — a longer file's tail is HELD below.
        let seconds = max(
            1,
            min(maxThumbnails, Int((Double(media.duration) / Double(ReelTime.perSecond)).rounded(.up))))
        // Precise timing, so a sample cursor lands on the exact sample
        // (`AVAssetTrack.h`); the generator parses the table anyway.
        let asset = AVURLAsset(
            url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // The held request: the last frame's own time on the track, or — no
        // track, or none the file can open — one record frame before the
        // record's end, which is where an ordinary strip always ended.
        var lastTime = CompositionBuilder.time(
            max(0, media.duration - max(1, media.fps.frameDuration)))
        if let track = (try? await asset.loadTracks(withMediaType: .video))?.first,
            let frame = await lastFrameTime(of: track) {
            lastTime = frame
        }
        let last = CompositionBuilder.ticks(lastTime)
        // The seconds at or past `last` are HELD: a suffix (the times are
        // monotonic), asking for `lastTime` once, written under each of them.
        let held = (0..<seconds).filter { Ticks($0) * ReelTime.perSecond >= last }
        var times = (0..<(seconds - held.count)).map {
            CompositionBuilder.time(Ticks($0) * ReelTime.perSecond)
        }
        if !held.isEmpty { times.append(lastTime) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        let aspect = media.height > 0 ? Double(media.width) / Double(media.height) : 16.0 / 9.0
        generator.maximumSize = CGSize(
            width: max(16, (thumbnailHeight * aspect).rounded()), height: thumbnailHeight)

        var sinceLastPost = 0
        for await result in generator.images(for: times) {
            var tiles = 1
            switch result {
            case .success(requestedTime: let requested, image: let image, actualTime: _):
                // Named by the seconds that ASKED for the requested time, not
                // by a counter: results arrive in request order today, and a
                // counter would silently shift the whole strip by one if that
                // ever stopped being true or a frame failed. `time` and
                // `ticks` are exact inverses at the tick timescale, so an
                // unheld second divides exactly; the held request is the one
                // time in the list off the grid, compared as a time.
                let indices =
                    requested == lastTime
                    ? held : [Int(CompositionBuilder.ticks(requested) / ReelTime.perSecond)]
                for index in indices
                where writeJPEG(image, to: directory.appendingPathComponent("\(index).jpg")) {
                    written.insert(index)
                }
                tiles = indices.count
            case .failure:
                // A frame that will not decode leaves a hole in the strip;
                // the timeline draws the clip's tint there and carries on.
                break
            @unknown default:
                break
            }
            sinceLastPost += tiles
            if sinceLastPost >= 16 {
                sinceLastPost = 0
                postCacheChange(media: media.id, kind: thumbsKind, replaced: replaced)
                replaced = false
            }
        }
        // AFTER the loop and never inside it: a hole left by a frame that
        // would not decode is still a finished pass — complete is not a
        // count. But only when the pass wrote at least one frame and every
        // frame it wrote is still there (`stripHolds` argues both halves: a
        // pass that wrote nothing is a failed reader to retry, and a frame
        // that is gone is a titled document's save having swapped the
        // package under the pass); otherwise NO marker, and the next open
        // rebuilds, exactly as before the marker existed. And only for a
        // stamp that exists; nothing certifies a strip made from a file that
        // could not be measured.
        if let stamp, stripHolds(written, in: directory) { writeStamp(stamp, to: marker) }
        postCacheChange(media: media.id, kind: thumbsKind, replaced: replaced)
    }

    /// The presentation time of `track`'s last frame on the track's own
    /// timeline — what the held seconds ask the generator for. A sample
    /// cursor at the end of the sample table (a table read, no decode), whose
    /// time is the MEDIA's and is mapped through the edit that places it: an
    /// x264 file with B-frames starts its media 1/30 s in, and `-vsync vfr`
    /// put a 50 s media offset on a three-frame file. A mapping at any other
    /// rate, or a file that offers no cursor, falls back to one
    /// `minFrameDuration` before the track's end — the composition's own
    /// window, exact wherever the end is; nil for a track with no numeric
    /// extent, which then runs on the record's arithmetic.
    private static func lastFrameTime(of track: AVAssetTrack) async -> CMTime? {
        guard let range = try? await track.load(.timeRange), range.end.isNumeric else { return nil }
        if (try? await track.load(.canProvideSampleCursors)) == true,
            let mapping = (try? await track.load(.segments))?.last(where: { !$0.isEmpty })?
                .timeMapping,
            mapping.source.duration == mapping.target.duration,
            let cursor = track.makeSampleCursor(presentationTimeStamp: mapping.source.end),
            cursor.presentationTimeStamp.isNumeric {
            return mapping.target.start + (cursor.presentationTimeStamp - mapping.source.start)
        }
        let frame = (try? await track.load(.minFrameDuration)) ?? .invalid
        let step = frame.isNumeric && frame > .zero ? frame : CompositionBuilder.time(1)
        return CMTimeMaximum(.zero, range.end - step)
    }

    // MARK: - Peaks

    /// Writes the waveform for `media` to `cache/peaks/<id>.bin`: the
    /// reader's every sample buffer through `PeakBuckets`
    /// (`MediaPeakBuckets.swift`), then one atomic write of its floats after
    /// successful whole-track coverage.
    ///
    /// Skipped when `peaks/<id>.complete.json` holds `PeaksStamp(stamp)` AND
    /// its `.bin` is valid — the marker is a sibling, not a child, so either can be
    /// deleted without the other. Otherwise BOTH go, before anything below
    /// can fail, and a removed `.bin` is posted at once (`clearPeaks` says
    /// why: readers may memoize a waveform, so a withdrawal must invalidate
    /// it). No track, unusable extent, reader failure or incomplete decode
    /// writes no marker or `.bin`; the next normal pass retries it.
    static func peaks(
        for media: MediaSnapshot, url: URL, stamp: CacheStamp?, into cacheDir: URL
    ) async {
        guard media.hasAudio, media.duration > 0 else { return }
        if peaksAreCurrent(for: media, stamp: stamp, in: cacheDir) { return }
        if clearPeaks(for: media.id, in: cacheDir) {
            postCacheChange(media: media.id, kind: peaksKind)
        }
        let asset = AVURLAsset(url: url)
        guard let track = (try? await asset.loadTracks(withMediaType: .audio))?.first else {
            return
        }
        guard let trackRange = try? await track.load(.timeRange),
            let segments = try? await track.load(.segments),
            let expected = expectedPeaksRanges(trackRange: trackRange, segments: segments)
        else { return }
        writePeaks(for: media, asset: asset, track: track, expectedRanges: expected,
                   stamp: stamp, into: cacheDir)
    }

    // MARK: - Speech

    /// Writes `cache/speech/<id>.bin` — road map 4's voice cache, run AFTER
    /// `peaks` in `generateCaches`'s order (never before it), so the `.bin`
    /// withdrawal at `peaks`' own head is never held behind a full-file
    /// decode and an inference pass.
    ///
    /// Skipped when `speechIsCurrent` (`MediaImporter+Speech.swift`'s head
    /// check) says the marker, the model and the chunk size all still agree,
    /// or when there is no audio at all. A stale cache is cleared and posted
    /// at once — `clearSpeech`'s doc argues the order — and that withdrawal is
    /// the first post of a pass replacing a `.bin` on disk, so it carries
    /// `replaced` (§4g claim 14), the one way it differs from `peaks`'. Then
    /// `SileroVAD.isAvailable` is asked exactly once: a model already marked
    /// unavailable this process (a nil bundle, an earlier thrown prediction) is
    /// not retried, so a project full of media pays for it once, not per file.
    static func speech(
        for media: MediaSnapshot, url: URL, stamp: CacheStamp?, into cacheDir: URL
    ) async {
        guard media.hasAudio, media.duration > 0 else { return }
        guard !speechIsCurrent(for: media, stamp: stamp, in: cacheDir) else { return }
        if clearSpeech(for: media.id, in: cacheDir) {
            postCacheChange(media: media.id, kind: speechKind, replaced: true)
        }
        guard SileroVAD.isAvailable else { return }
        let asset = AVURLAsset(url: url)
        guard let track = (try? await asset.loadTracks(withMediaType: .audio))?.first else {
            return
        }
        writeSpeech(for: media, asset: asset, track: track, stamp: stamp, into: cacheDir)
    }
}
