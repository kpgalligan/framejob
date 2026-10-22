import AVFoundation
import AppKit
import VideoToolbox

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
///   forward file (GR-15: HDR is converted there, at step 0, not here).
final class ReverseRenderer {

    /// What one reverse is written as (spec §11 PR-7), from the source's
    /// coded size. HEVC 4:2:0 cannot hold an odd size — 1919×1079 came back
    /// 1918×1078 — and `videoSettings` says why the size must be exact, so an
    /// odd width or height takes ProRes 422, whose file is several times
    /// larger, for its exact size.
    enum Intermediate: Equatable {
        /// Even width and height: `x420` frames, HEVC Main 10.
        case hevcMain10
        /// An odd width or height: `x422` frames, ProRes 422 — full-range
        /// frames when the source is flagged full range (PR-10).
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

        /// The format for a source whose forward video track is flagged
        /// `fullRange` (GR-22's flag, spec §11 PR-10): ProRes 422 reads
        /// full-range `x422`, because a full-range file read as video-range
        /// `x422` came back up to 90 codes off (log_proof L13, #289). The HEVC
        /// branch reads `pixelFormat` whatever the flag.
        func pixelFormat(fullRange: Bool) -> OSType {
            if fullRange && self == .proRes422 {
                return kCVPixelFormatType_422YpCbCr10BiPlanarFullRange
            }
            return pixelFormat
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
        let fullRange = videoTrack.map(CompositionBuilder.isFullRange) ?? false

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
            let format = intermediate.pixelFormat(fullRange: fullRange)
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
                    kCVPixelBufferPixelFormatTypeKey as String: Int(format),
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
                    : (intermediate?.pixelFormat(fullRange: fullRange)
                        ?? kCVPixelFormatType_32BGRA),
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
