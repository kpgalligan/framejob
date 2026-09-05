import AVFoundation
import Accelerate
import AppKit
import ImageIO
import UniformTypeIdentifiers

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

    // MARK: - Notification keys

    static let mediaIDKey = "media"
    static let cacheKindKey = "cache"
    static let thumbsKind = "thumbs"
    static let peaksKind = "peaks"

    // MARK: - Errors

    /// Import refusals. Every one is shown in an alert and never crashes;
    /// `unreadable` is also what a relink of a moved file reports.
    enum ImportError: LocalizedError {
        case unreadable(URL)
        case noTracks(URL)
        case timedOut(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "Could not read \(url.lastPathComponent)."
            case .noTracks(let url):
                return "\(url.lastPathComponent) has no video or audio the app can open."
            case .timedOut(let url):
                return "Timed out reading \(url.lastPathComponent)."
            }
        }
    }

    // MARK: - Probing

    /// Still-image types ImageIO decodes and AVFoundation would refuse.
    /// Probed with ImageIO and imported as `kind: image` (§7.7).
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .gif, .bmp, .webP]

    /// Whether `url` is a still picture rather than a movie. Type-based, not
    /// extension-based, so a `.heic` written by a camera and a `.jpeg` with
    /// no extension both land in the same branch.
    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return imageTypes.contains { type.conforms(to: $0) }
    }

    /// The `media[]` descriptor for a file: duration, display size, rate and
    /// the two track flags (spec §7.7). Throws `ImportError` for a file
    /// nothing can open; never crashes on a truncated or hostile file.
    ///
    /// The size reported is the DISPLAY size — `naturalSize` through
    /// `preferredTransform` — so a portrait iPhone clip imports as
    /// 1080×1920, not 1920×1080 with a rotation nobody applied. Getting this
    /// wrong is invisible until the first phone clip lands sideways on the
    /// canvas, which is why it is the verification of M1 step 3.
    static func probe(url: URL) async throws -> MediaDescriptor {
        if isImage(url) { return try probeImage(url) }
        return try await probeAsset(url)
    }

    /// The synchronous face of `probe` for the rest of the app: the result
    /// arrives on the main thread, so the caller can go straight to
    /// `add_media` + `add_clip` without ever writing `await`.
    static func probe(
        url: URL, completion: @escaping (Result<MediaDescriptor, any Error>) -> Void
    ) {
        Task {
            do {
                let descriptor = try await probe(url: url)
                await MainActor.run { completion(.success(descriptor)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    /// Carries one probe's outcome across the semaphore in `probeBlocking`.
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

    /// ImageIO's view of a still: pixel size, and alpha from the file's own
    /// properties. Duration 0 — an `image` clip has no source bound and any
    /// duration (§5.2).
    private static func probeImage(_ url: URL) throws -> MediaDescriptor {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            CGImageSourceGetCount(source) > 0,
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw ImportError.unreadable(url)
        }
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard width > 0, height > 0 else { throw ImportError.unreadable(url) }
        let hasAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
        // `hasVideo` is true for a still: it contributes pixels, so
        // `enabled.video` means something on its clips. It still gets NO
        // composition track — the recipe names an image layer `image`, not
        // `track` (§7.2), and the plan never lists it.
        return MediaDescriptor(
            path: url.path, bookmark: bookmarkString(for: url), kind: .image, duration: 0,
            width: width, height: height, fps: .thirty, hasVideo: true, hasAudio: false,
            hasAlpha: hasAlpha)
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

    /// The rates a container is allowed to round: the integer rates and the
    /// three NTSC /1001 rates (§7.7). Anything else keeps three decimals as
    /// `[round(fps × 1000), 1000]`, which is exact enough to place source
    /// frames and never pretends a 47.3 fps screen recording is 48.
    static let commonRates: [Fps] = [
        Fps(num: 24, den: 1), Fps(num: 24000, den: 1001), Fps(num: 25, den: 1),
        Fps(num: 30, den: 1), Fps(num: 30000, den: 1001), Fps(num: 48, den: 1),
        Fps(num: 50, den: 1), Fps(num: 60, den: 1), Fps(num: 60000, den: 1001),
    ]

    /// Tolerance for that match, in frames per second. 0.01 is wide enough
    /// for a float's error at 60 fps and narrower than the 0.03 gap between
    /// 29.97 and 30 — the pair this must never confuse.
    static let rateTolerance = 0.01

    static func rationalFrameRate(_ nominal: Double) -> Fps {
        guard nominal.isFinite, nominal > 0 else { return .thirty }
        for candidate in commonRates where abs(candidate.double - nominal) <= rateTolerance {
            return candidate
        }
        return Fps(num: Int((nominal * 1000).rounded()), den: 1000)
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

    /// Kicks off both caches in the background and returns immediately —
    /// the synchronous entry point the import path and document-open path
    /// call. The work is detached so a cancelled import (the document
    /// closing) never blocks; the caches are regenerable, so a half-written
    /// one is simply regenerated next time.
    static func generateCaches(for media: MediaSnapshot, url: URL, in cacheDir: URL) {
        Task.detached(priority: .utility) {
            await thumbnails(for: media, url: url, into: cacheDir)
            await peaks(for: media, url: url, into: cacheDir)
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
    static func thumbnails(for media: MediaSnapshot, url: URL, into cacheDir: URL) async {
        guard media.hasVideo else { return }
        let directory = thumbsDirectory(for: media.id, in: cacheDir)
        guard ensureDirectory(directory) else { return }

        if media.kind == .image {
            if let image = decodeImage(url, maxPixelSize: Int(thumbnailHeight * 4)) {
                writeJPEG(image, to: directory.appendingPathComponent("0.jpg"))
                postCacheChange(media: media.id, kind: thumbsKind)
            }
            return
        }

        let seconds = max(
            1,
            min(maxThumbnails, Int((Double(media.duration) / Double(ReelTime.perSecond)).rounded(.up))))
        let last = max(0, media.duration - max(1, media.fps.frameDuration))
        let times: [CMTime] = (0..<seconds).map { index in
            CompositionBuilder.time(min(Ticks(index) * ReelTime.perSecond, last))
        }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        let aspect = media.height > 0 ? Double(media.width) / Double(media.height) : 16.0 / 9.0
        generator.maximumSize = CGSize(
            width: max(16, (thumbnailHeight * aspect).rounded()), height: thumbnailHeight)

        var sinceLastPost = 0
        for await result in generator.images(for: times) {
            switch result {
            case .success(requestedTime: let requested, image: let image, actualTime: _):
                // Named by the REQUESTED second, not by a counter: results
                // arrive in request order today, and a counter would silently
                // shift the whole strip by one if that ever stopped being true
                // or a frame failed.
                let index = Int(
                    (Double(CompositionBuilder.ticks(requested)) / Double(ReelTime.perSecond))
                        .rounded())
                writeJPEG(image, to: directory.appendingPathComponent("\(index).jpg"))
            case .failure:
                // A frame that will not decode leaves a hole in the strip;
                // the timeline draws the clip's tint there and carries on.
                break
            @unknown default:
                break
            }
            sinceLastPost += 1
            if sinceLastPost >= 16 {
                sinceLastPost = 0
                postCacheChange(media: media.id, kind: thumbsKind)
            }
        }
        postCacheChange(media: media.id, kind: thumbsKind)
    }

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

    /// Writes the waveform for `media`: one Float32 per bucket, 100 buckets a
    /// second, each the MAX MAGNITUDE over the bucket across every channel —
    /// a mono envelope, which is what a waveform lane draws. Written to
    /// `cache/peaks/<id>.bin` as raw little-endian floats, so reading it back
    /// is one `Data` read and a rebind.
    ///
    /// Max, not RMS: a waveform's job is to show where the transients are,
    /// and an RMS envelope hides a clipped peak.
    static func peaks(for media: MediaSnapshot, url: URL, into cacheDir: URL) async {
        guard media.hasAudio, media.duration > 0 else { return }
        let asset = AVURLAsset(url: url)
        guard let track = (try? await asset.loadTracks(withMediaType: .audio))?.first,
            let reader = try? AVAssetReader(asset: asset)
        else { return }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else { return }

        let bucketCount = max(
            1,
            Int(
                (Double(media.duration) / Double(ReelTime.perSecond)
                    * Double(peakBucketsPerSecond)).rounded(.up)))
        var buckets = [Float](repeating: 0, count: bucketCount)
        // Frames consumed so far, so a bucket that spans two sample buffers
        // still lands in one place.
        var frameCursor = 0.0
        var sampleRate = 48000.0
        var channels = 1

        while let sample = output.copyNextSampleBuffer() {
            if let description = CMSampleBufferGetFormatDescription(sample),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                sampleRate = asbd.pointee.mSampleRate > 0 ? asbd.pointee.mSampleRate : sampleRate
                channels = max(1, Int(asbd.pointee.mChannelsPerFrame))
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount >= 4 else { continue }
            var samples = [Float](repeating: 0, count: byteCount / 4)
            let copied = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                // Copy rather than point into the block: a block buffer may be
                // several non-contiguous chunks, and pointing at the first one
                // silently truncates the buffer.
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: byteCount, destination: base)
            }
            guard copied == noErr else { continue }

            let framesPerBucket = max(1.0, sampleRate / Double(peakBucketsPerSecond))
            let frames = samples.count / channels
            var frame = 0
            while frame < frames {
                let bucket = Int(frameCursor / framesPerBucket)
                guard bucket >= 0 else { break }
                if bucket >= bucketCount {
                    frame = frames
                    break
                }
                let bucketEnd = Double(bucket + 1) * framesPerBucket
                let take = max(1, min(frames - frame, Int(bucketEnd - frameCursor)))
                var magnitude: Float = 0
                samples.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    vDSP_maxmgv(
                        base + frame * channels, 1, &magnitude, vDSP_Length(take * channels))
                }
                buckets[bucket] = max(buckets[bucket], magnitude)
                frame += take
                frameCursor += Double(take)
            }
        }
        reader.cancelReading()

        let file = peaksURL(for: media.id, in: cacheDir)
        guard ensureDirectory(file.deletingLastPathComponent()) else { return }
        let data = buckets.withUnsafeBufferPointer { Data(buffer: $0) }
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        postCacheChange(media: media.id, kind: peaksKind)
    }

    /// The cached waveform, or nil when it has not been generated. One float
    /// per 1/100 s, magnitudes 0…1 (louder than full scale is possible and
    /// is not clamped — the lane clamps when it draws).
    static func loadPeaks(for media: UInt32, in cacheDir: URL) -> [Float]? {
        let url = peaksURL(for: media, in: cacheDir)
        guard let data = try? Data(contentsOf: url), data.count >= 4 else { return nil }
        return data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }

    // MARK: - Small shared plumbing

    private static func ensureDirectory(_ url: URL) -> Bool {
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

    private static func writeJPEG(_ image: CGImage, to url: URL) {
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
    private static func postCacheChange(media: UInt32, kind: String) {
        let info: [String: Any] = [mediaIDKey: media, cacheKindKey: kind]
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .mediaCacheDidChange, object: nil, userInfo: info)
        }
    }
}
