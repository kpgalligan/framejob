import AVFoundation

// MARK: - Chapters

/// One entry of the chapter list an export writes (spec §7.8).
///
/// Chapters come from the PROJECT, never from the composition plan: the plan
/// says what to decode and where to put it, and markers decode nothing, so
/// `evaluate.rs` emits no marker key at all. `Exporter` reads them off the
/// snapshot of the handle it was given and hands them over here, which is
/// also why an export shows the chapters the timeline had when the sheet was
/// confirmed rather than the ones it has when the write ends.
struct ExportChapter: Equatable {
    /// Timeline ticks, in the project's own time. Clamping into the exported
    /// range and rebasing to a zero-based file both happen when the samples
    /// are built, because only then is the range known.
    let start: Ticks
    /// What the chapter is called. Never empty — an unnamed marker becomes
    /// "Chapter <n>", because a chapter list of blank rows is worse in every
    /// player than no chapter list at all.
    let name: String

    /// The project's `chapter` markers, in time order and named.
    ///
    /// Numbering is over the CHAPTER markers only, so deleting a plain marker
    /// cannot renumber the chapters around it.
    static func list(from markers: [MarkerSnapshot]) -> [ExportChapter] {
        markers
            .filter(\.chapter)
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { index, marker in
                let name = marker.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return ExportChapter(
                    start: marker.time, name: name.isEmpty ? "Chapter \(index + 1)" : name)
            }
    }
}

// MARK: - The writer pipeline

/// Reads the composed movie back out of AVFoundation and writes it to a file:
/// the `AVAssetWriter` half of `Exporter` (spec §7.8).
///
/// **One movie, one description of it.** The reader is built over the SAME
/// `AVComposition`, the SAME `AVVideoComposition` and the SAME `AVAudioMix`
/// that `Playback` plays and `Exporter.renderFrame` samples — the custom
/// `Compositor` runs here exactly as it does on screen, from the same frame
/// recipes, through the same `RecipeSource` slot, and so do the audio mix's
/// processing taps (`addAudio`). Nothing in this file draws a pixel or mixes a
/// sample; it moves what AVFoundation composed into an encoder and adds the
/// three things a preset name cannot express: a chapter track, explicit
/// bitrates, and an output size the sheet actually promised.
///
/// **Why the read is a reader and not a second render.** The alternative —
/// driving the compositor by hand over an `AVAssetImageGenerator`, one frame
/// at a time — is a second rendering path with its own timing, and the whole
/// design exists so there is not one. `AVAssetReaderVideoCompositionOutput`
/// runs the video composition on AVFoundation's own schedule and hands back
/// the very buffers the compositor filled.
///
/// **Times are rebased, not mapped.** The reader's range starts at
/// `settings.start`; every sample is re-timed by subtracting it and the
/// writing session starts at zero, so an in/out export is a file that begins
/// at 00:00 like the session path's did. Letting `startSession(atSourceTime:)`
/// do the mapping instead would leave the container's edit list to decide,
/// which players disagree about.
///
/// **Cancellation and progress.** Every sample checks the flag, so a cancel
/// lands within one frame; `AVAssetWriter` has no `progress` of its own, so
/// the fraction is kept here from the presentation time of the last sample
/// appended and `Exporter`'s 0.1 s timer reads it.
final class ExportWriter {

    /// The composition, held for the whole write. Not merely tidiness: the
    /// compositor asks `RecipeSource` for a recipe per frame, and the
    /// instructions inside this object carry the key it asks under.
    private let built: BuiltComposition
    private let destination: URL
    /// The slice of the composition being written, in composition time.
    private let range: CMTimeRange
    /// `range.duration` in seconds, or 0 for a degenerate range — the
    /// denominator of `progress`.
    private let totalSeconds: Double

    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private var videoOutput: AVAssetReaderOutput?
    private var videoInput: AVAssetWriterInput?
    private var audioOutput: AVAssetReaderOutput?
    private var audioInput: AVAssetWriterInput?
    private var chapterInput: AVAssetWriterInput?
    private var chapterSamples: [CMSampleBuffer] = []

    /// One serial queue per input, as `requestMediaDataWhenReady` requires.
    /// Separate queues rather than one shared serial queue: the audio pump
    /// must not sit behind a 4K frame being appended.
    private let videoQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.export.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.export.audio", qos: .userInitiated)
    private let chapterQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.export.chapters", qos: .userInitiated)

    /// Guards everything the pumps and the main thread both touch.
    private let lock = NSLock()
    private var progressValue: Double = 0
    private var cancelRequested = false
    private var failure: (any Error)?

    /// Called once, on the main thread, and then dropped.
    private var completion: ((Result<URL, any Error>) -> Void)?

    /// Builds the reader, the writer and every track, or throws the
    /// `Exporter.ExportError` the sheet should show. Nothing is read or
    /// written until `start`.
    init(
        built: BuiltComposition, settings: ExportSettings, chapters: [ExportChapter], to url: URL
    ) throws {
        guard let fileType = Exporter.fileType(for: settings) else {
            throw Exporter.ExportError.fileTypeUnsupported(settings.container)
        }
        self.built = built
        self.destination = url
        self.range = Exporter.timeRange(settings, composition: built.composition)
        self.totalSeconds = max(0, CMTimeGetSeconds(range.duration))

        do {
            reader = try AVAssetReader(asset: built.composition)
            writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        } catch {
            throw Exporter.ExportError.failed(error.localizedDescription)
        }
        reader.timeRange = range
        writer.shouldOptimizeForNetworkUse = settings.optimizeForNetwork

        try addVideo(settings: settings)
        try addAudio(settings: settings)
        addChapters(chapters)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportWriter does not support NSCoder")
    }

    // MARK: - Tracks

    /// The video half: the composition's video tracks through the video
    /// composition, into one encoder input.
    ///
    /// An audio-only preset gets NO video at all, for the reason the session
    /// path gives: attaching the video composition asks the custom compositor
    /// to render frames nothing will write.
    private func addVideo(settings: ExportSettings) throws {
        guard !settings.isAudioOnly else { return }
        let tracks = built.composition.tracks(withMediaType: .video)
        // CompositionBuilder gives a text-and-shapes-only timeline a
        // placeholder track precisely so this is never empty; if it still is,
        // the bundled resource is missing and there is nothing to compose
        // against.
        guard !tracks.isEmpty else { throw Exporter.ExportError.emptyTimeline }

        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [
                // The one format the compositor produces and the shader
                // samples (`Compositor.requiredPixelBufferAttributes…`).
                // Asking for it here means no conversion between the render
                // context and the encoder.
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
        output.videoComposition = Self.videoComposition(built.videoComposition, settings: settings)
        guard reader.canAdd(output) else {
            throw Exporter.ExportError.failed(
                "The composition could not be read for export.")
        }
        reader.add(output)

        let input = AVAssetWriterInput(
            mediaType: .video, outputSettings: try Self.videoSettings(settings))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw Exporter.ExportError.presetUnavailable(Self.presetName(settings))
        }
        writer.add(input)
        videoOutput = output
        videoInput = input
    }

    /// The audio half: every composition audio track through the plan's mix.
    ///
    /// **This one line is where the preview and the file agree about sound.**
    /// The mix carries the plan's volume envelope AND, for any track whose
    /// clips use pan, the compressor or noise reduction, the
    /// `MTAudioProcessingTap` that runs them (`AudioTap.swift`). Those taps
    /// were long believed to be an AVPlayer-only feature — true of the
    /// `AVAssetExportSession` this pipeline replaced, and the reason the
    /// effects were left unimplemented — but measured against
    /// `AVAssetReaderAudioMixOutput` they run here as well: a tap that
    /// silenced its buffers produced a silent file, one tap per track saw only
    /// its own track, and with `reader.timeRange` set for an in/out export the
    /// tap is handed COMPOSITION time, so a clip's settings still line up with
    /// the clip. Nothing had to be re-implemented for the export; the DSP has
    /// one implementation and this reads through it.
    ///
    /// The one thing the file and the preview do not share is the reducer's
    /// 512-sample delay on a track that uses it, which both paths have and
    /// neither compensates: 10.7 ms of audio lag at 48 kHz, well inside every
    /// A/V sync tolerance, on tracks the user asked to clean.
    ///
    /// A timeline with no audio at all is not an error — it is a silent
    /// movie, and the track is simply not added. It IS an error when the
    /// preset writes nothing else.
    private func addAudio(settings: ExportSettings) throws {
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            if settings.isAudioOnly { throw Exporter.ExportError.emptyTimeline }
            return
        }
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks, audioSettings: Self.decodedAudioSettings)
        output.audioMix = built.audioMix
        guard reader.canAdd(output) else {
            throw Exporter.ExportError.failed("The audio mix could not be read for export.")
        }
        reader.add(output)

        let input = AVAssetWriterInput(
            mediaType: .audio, outputSettings: Self.audioSettings(settings))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw Exporter.ExportError.presetUnavailable(Self.presetName(settings))
        }
        writer.add(input)
        audioOutput = output
        audioInput = input
    }

    /// The chapter track: a text track carrying one sample per chapter,
    /// associated with the movie's own track through
    /// `AVTrackAssociationTypeChapterList`, which is what writes the `chap`
    /// track reference every reader (QuickTime, `ffprobe -show_chapters`)
    /// looks for.
    ///
    /// Additive, never fatal: a build of macOS that will not take the text
    /// track loses the chapters, not the movie. The track is marked disabled
    /// so no player tries to draw the names over the picture.
    private func addChapters(_ chapters: [ExportChapter]) {
        guard !chapters.isEmpty, let host = videoInput ?? audioInput,
            let format = Self.textFormat()
        else { return }
        let samples = Self.chapterSamples(chapters, in: range, format: format)
        guard !samples.isEmpty else { return }

        let input = AVAssetWriterInput(
            mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        input.marksOutputTrackAsEnabled = false
        guard writer.canAdd(input) else { return }
        writer.add(input)
        host.addTrackAssociation(
            withTrackOf: input, type: AVAssetTrack.AssociationType.chapterList.rawValue)
        chapterInput = input
        chapterSamples = samples
    }

    // MARK: - Running

    /// Starts the write. Main thread; `completion` is called exactly once, on
    /// the main thread, and may be called before this returns if the writer
    /// refuses to start at all.
    func start(completion: @escaping (Result<URL, any Error>) -> Void) {
        self.completion = completion
        guard writer.startWriting() else {
            report(.failure(writer.error ?? Exporter.ExportError.failed(
                "The file could not be opened for writing.")))
            return
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            report(.failure(reader.error ?? Exporter.ExportError.failed(
                "The composition could not be read for export.")))
            return
        }
        // Zero, not `range.start`: the samples are rebased on the way in, so
        // the file's timeline is its own.
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        if let input = videoInput, let output = videoOutput {
            pump(input, from: output, on: videoQueue, group: group, tracksProgress: true)
        }
        if let input = audioInput, let output = audioOutput {
            // Audio drives the bar only when there is no picture to drive it.
            pump(
                input, from: output, on: audioQueue, group: group,
                tracksProgress: videoInput == nil)
        }
        if let input = chapterInput {
            pumpChapters(input, on: chapterQueue, group: group)
        }
        group.notify(queue: .main) { [weak self] in self?.allInputsFinished() }
    }

    /// Stops as soon as the pumps notice — within one sample. Safe from any
    /// thread and safe to call twice; cancelling the READER is what wakes a
    /// pump that is blocked inside `copyNextSampleBuffer`.
    func cancel() {
        lock.lock()
        let alreadyCancelled = cancelRequested
        cancelRequested = true
        lock.unlock()
        guard !alreadyCancelled else { return }
        reader.cancelReading()
    }

    /// 0…1, from the last sample appended. `AVAssetWriter` has no progress of
    /// its own, so this is it.
    var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        return progressValue
    }

    // MARK: - The pumps

    /// Moves one output's samples into one input until the output runs dry,
    /// the write fails, or the export is cancelled.
    ///
    /// `requestMediaDataWhenReady` re-enters this block whenever the encoder
    /// has room, so the "have I already finished?" flag lives outside it and
    /// is only ever touched on `queue`, which is serial.
    private func pump(
        _ input: AVAssetWriterInput, from output: AVAssetReaderOutput, on queue: DispatchQueue,
        group: DispatchGroup, tracksProgress: Bool
    ) {
        group.enter()
        var finished = false
        let stop: () -> Void = {
            guard !finished else { return }
            finished = true
            input.markAsFinished()
            group.leave()
        }
        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self = self else { return }
            while input.isReadyForMoreMediaData {
                guard !finished else { return }
                guard !self.isStopping else {
                    stop()
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    // Dry for one of three reasons: the range is written, the
                    // read was cancelled (which `allInputsFinished` reports),
                    // or the read failed — and only the last is ours to name.
                    if self.reader.status == .failed {
                        self.stopped(
                            with: self.reader.error
                                ?? Exporter.ExportError.failed(
                                    "The composition could not be read to the end."))
                    }
                    stop()
                    return
                }
                let time = CMSampleBufferGetPresentationTimeStamp(sample) - self.range.start
                // A sample that starts before the range does not belong to
                // this file. The reader clips to `timeRange`, so this is a
                // boundary frame, not a common case.
                guard time.isNumeric, time >= .zero else { continue }
                guard let rebased = Self.retimed(sample, by: self.range.start) else {
                    self.stopped(
                        with: Exporter.ExportError.failed(
                            "A sample could not be re-timed for the file."))
                    stop()
                    return
                }
                guard input.append(rebased) else {
                    self.stopped(
                        with: self.writer.error
                            ?? Exporter.ExportError.failed("The file could not be written."))
                    stop()
                    return
                }
                if tracksProgress { self.advance(to: time) }
            }
        }
    }

    /// The chapter samples are a handful of tiny text buffers, all known
    /// before the write starts, so this pump has nothing to read — it drains
    /// its own array.
    private func pumpChapters(
        _ input: AVAssetWriterInput, on queue: DispatchQueue, group: DispatchGroup
    ) {
        group.enter()
        var pending = chapterSamples
        var finished = false
        let stop: () -> Void = {
            guard !finished else { return }
            finished = true
            input.markAsFinished()
            group.leave()
        }
        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self = self else { return }
            while input.isReadyForMoreMediaData {
                guard !finished else { return }
                guard !self.isStopping, !pending.isEmpty else {
                    stop()
                    return
                }
                let sample = pending.removeFirst()
                guard input.append(sample) else {
                    // A chapter that will not write is not worth losing the
                    // movie over: the text track simply ends here.
                    stop()
                    return
                }
            }
        }
    }

    // MARK: - Finishing

    /// True once anything has asked the write to stop.
    private var isStopping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested || failure != nil
    }

    /// Records the first failure; later ones are noise from the other pumps
    /// unwinding. Cancels the read so those pumps come back promptly.
    private func stopped(with error: any Error) {
        lock.lock()
        let first = failure == nil
        if first { failure = error }
        lock.unlock()
        guard first else { return }
        reader.cancelReading()
    }

    private func advance(to time: CMTime) {
        guard totalSeconds > 0 else { return }
        let fraction = CMTimeGetSeconds(time) / totalSeconds
        lock.lock()
        progressValue = min(max(fraction, progressValue), 1)
        lock.unlock()
    }

    /// Main thread, once every input has marked itself finished.
    private func allInputsFinished() {
        lock.lock()
        let error = failure
        let cancelled = cancelRequested
        lock.unlock()

        if let error = error {
            writer.cancelWriting()
            report(.failure(error))
            return
        }
        if cancelled {
            // `cancelWriting` deletes the part-written file itself, which is
            // the same outcome the progress sheet arranges for a cancel.
            writer.cancelWriting()
            report(.failure(Exporter.ExportError.cancelled))
            return
        }
        writer.finishWriting { [weak self] in
            // AVFoundation calls this on a queue of its own.
            DispatchQueue.main.async { self?.writingFinished() }
        }
    }

    private func writingFinished() {
        lock.lock()
        let cancelled = cancelRequested
        lock.unlock()
        // A cancel that lands while the container is being closed still means
        // "I do not want this file": the sheet removes the destination on a
        // cancelled result, and a file the user cancelled out of is not one to
        // hand back because the timing was unlucky.
        guard !cancelled else {
            report(.failure(Exporter.ExportError.cancelled))
            return
        }
        guard writer.status == .completed else {
            report(
                .failure(
                    writer.error
                        ?? Exporter.ExportError.failed("The export stopped before it finished.")))
            return
        }
        lock.lock()
        progressValue = 1
        lock.unlock()
        report(.success(destination))
    }

    /// The one exit, main thread, at most once.
    private func report(_ result: Result<URL, any Error>) {
        guard let completion = completion else { return }
        self.completion = nil
        completion(result)
    }

    // MARK: - Settings → AVFoundation

    /// The video composition to render through: the one the plan built,
    /// unless the settings ask for a different frame rate.
    ///
    /// `CompositionBuilder` ticks the composition at the PROJECT's rate, and
    /// the sheet's Frame-rate popup overrides `settings.fps` — which the
    /// session path could not honour at all (a preset name carries no rate),
    /// so the readout promised 25 fps and the file held 30. A copy with the
    /// asked-for `frameDuration` samples the same timeline at the asked-for
    /// instants; the recipes are evaluated per frame at whatever tick is
    /// requested, so nothing else has to know.
    private static func videoComposition(
        _ videoComposition: AVVideoComposition, settings: ExportSettings
    ) -> AVVideoComposition {
        let fps = settings.fps
        guard fps.num > 0, fps.den > 0 else { return videoComposition }
        let wanted = CompositionBuilder.frameDuration(fps)
        guard wanted != videoComposition.frameDuration,
            let copy = videoComposition.mutableCopy() as? AVMutableVideoComposition
        else { return videoComposition }
        copy.frameDuration = wanted
        return copy
    }

    /// The encoder settings for the picture.
    ///
    /// **Size.** The composition renders at the CANVAS size (§7.2), and the
    /// core resolves the export size from the preset or the sheet's fields —
    /// they are not the same number, and the session path simply dropped the
    /// second one on the floor: the preset scaled to fit whatever it liked,
    /// so the sheet's "1920 × 1080" was a wish. Here the encoder is told the
    /// size the sheet promised and `AVVideoScalingModeResizeAspect` fits the
    /// canvas inside it, letterboxing rather than distorting when the two
    /// aspects differ. Dimensions are forced even because H.264 and HEVC
    /// require it.
    ///
    /// **Bitrate.** `settings.videoBitrate` when the core resolved one. When
    /// it did not, a rate computed from the frame — bits per pixel per frame,
    /// halved for HEVC — rather than none at all: with no
    /// `AVVideoAverageBitRateKey` VideoToolbox picks a conservative default
    /// that visibly under-runs a 4K timeline. ProRes gets neither: its rate
    /// is a property of the profile.
    private static func videoSettings(_ settings: ExportSettings) throws -> [String: Any] {
        guard let codec = codecType(for: settings.codec) else {
            throw Exporter.ExportError.presetUnavailable(presetName(settings))
        }
        var output: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: evenDimension(settings.width),
            AVVideoHeightKey: evenDimension(settings.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            // The compositor works in SDR sRGB/709 and tone-maps HDR sources
            // on the way in (§7.5), so tagging the output 709 is a statement
            // of what the pixels ARE, not a conversion.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        guard codec != .proRes422, codec != .proRes4444 else { return output }

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.videoBitrate.map { max(1, $0) }
                ?? defaultVideoBitrate(settings, codec: codec),
            // A keyframe at least every two seconds. Deliberate, not a
            // default: an exported movie is scrubbed and re-cut, and
            // VideoToolbox's own interval is long enough to make that
            // painful.
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
        ]
        if settings.fps.double > 0 {
            compression[AVVideoExpectedSourceFrameRateKey] = Int(settings.fps.double.rounded())
        }
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        output[AVVideoCompressionPropertiesKey] = compression
        return output
    }

    /// The core's codec name as an `AVVideoCodecType`. nil is a refusal, not
    /// a fallback: writing H.264 because "vp9" was not understood would put a
    /// file on disk that is not the one asked for.
    private static func codecType(for codec: String) -> AVVideoCodecType? {
        switch codec.lowercased() {
        case "h264", "avc", "avc1": return .h264
        case "hevc", "h265", "hvc1": return .hevc
        case "prores_422", "prores", "prores422": return .proRes422
        case "prores_4444", "prores4444": return .proRes4444
        default: return nil
        }
    }

    /// What to call the settings in a refusal: the core's preset id when it
    /// gave one, else the codec that could not be written.
    private static func presetName(_ settings: ExportSettings) -> String {
        settings.preset.isEmpty ? settings.codec : settings.preset
    }

    /// Bits per second for a frame of this size at this rate. The constants
    /// are the usual delivery figures — about 9 Mbps for 1080p30 H.264 and
    /// half that for HEVC — clamped so a tiny canvas still gets a usable rate
    /// and a huge one cannot ask for a file no disk wants.
    private static func defaultVideoBitrate(
        _ settings: ExportSettings, codec: AVVideoCodecType
    ) -> Int {
        let pixels = Double(max(1, settings.width)) * Double(max(1, settings.height))
        let rate = settings.fps.double > 0 ? settings.fps.double : 30
        let perPixel = codec == .hevc ? 0.07 : 0.14
        return Int(min(max(pixels * rate * perPixel, 1_000_000), 200_000_000))
    }

    /// Even, and never zero — H.264 and HEVC macroblocks come in pairs.
    private static func evenDimension(_ value: Int) -> Int {
        let clamped = max(2, value)
        return clamped - (clamped % 2)
    }

    /// What comes OUT of the mix: 16-bit interleaved LPCM. The same format
    /// the ProRes path writes, and one every encoder here takes without a
    /// conversion in between.
    private static let decodedAudioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// The encoder settings for the sound: LPCM under ProRes, so a master
    /// stays a master, and AAC everywhere else. `settings.audioBitrate` when
    /// the core resolved one, else 192 kbps — stereo AAC's transparent-enough
    /// rate and what the M1 presets landed on.
    private static func audioSettings(_ settings: ExportSettings) -> [String: Any] {
        if settings.codec.lowercased().hasPrefix("prores") {
            return decodedAudioSettings
        }
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: settings.audioBitrate.map { max(1, $0) } ?? 192_000,
        ]
    }

    // MARK: - Chapter samples

    /// The format one chapter sample is written in: a QuickTime text
    /// (`'text'`) description, in every container this build writes.
    ///
    /// **Why the byte structure and not `CMFormatDescriptionCreate`.** A
    /// description created from a media type and a subtype alone carries no
    /// extensions, and `AVAssetWriter` cannot serialise that into a sample
    /// description — it fails the whole write at `finishWriting` with
    /// `kCMFormatDescriptionBridgeError_InvalidParameter` (-12712), losing
    /// the movie, not just the chapters (measured). Handing the bridge the
    /// big-endian `TextDescription` the QuickTime file format specifies is
    /// exactly the shape it will write back out, so there is nothing left to
    /// guess at.
    ///
    /// **Why QuickTime text rather than 3GPP `tx3g` in the MPEG-4 family.**
    /// A `'text'` sample entry is what Apple's own chapter tracks use inside
    /// `.m4a`/`.m4v`/`.mp4`, and both QuickTime and `ffprobe`'s MOV demuxer
    /// read chapters from it; `tx3g` would mean a second byte layout and a
    /// font table for no gain.
    private static func textFormat() -> CMFormatDescription? {
        var description = Data()
        func be16(_ value: UInt16) { description.append(contentsOf: [
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
        func be32(_ value: UInt32) { be16(UInt16(truncatingIfNeeded: value >> 16))
            be16(UInt16(truncatingIfNeeded: value)) }

        be32(60)                                   // descSize, this whole record
        be32(0x7465_7874)                          // 'text'
        be32(0)                                    // reserved
        be16(0)                                    // reserved
        be16(1)                                    // data reference index
        be32(0)                                    // display flags: none
        be32(0)                                    // text justification: left
        be16(0); be16(0); be16(0)                  // background colour: black
        be16(0); be16(0); be16(0); be16(0)         // default text box: empty
        be32(0)                                    // default style: start char
        be16(0); be16(0)                           // height, ascent
        be16(0); be16(0); be16(12)                 // font, face, size
        be16(0xFFFF); be16(0xFFFF); be16(0xFFFF)   // foreground colour: white
        description.append(0)                      // font name, an empty
        description.append(0)                      //   Pascal string, padded

        var format: CMFormatDescription?
        let status = description.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            // A nil flavor is the QuickTime Movie one.
            return CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault, bigEndianTextDescriptionData: base,
                size: description.count, flavor: nil, mediaType: kCMMediaType_Text,
                formatDescriptionOut: &format)
        }
        return status == noErr ? format : nil
    }

    /// The chapters as samples, clamped into `range` and rebased to zero.
    ///
    /// Each chapter runs until the next one, and the last until the end of
    /// the range — a chapter list is a partition of the movie, not a set of
    /// points. A chapter that began BEFORE an in/out range is not dropped:
    /// the last of them is pinned to the start of the range, because the
    /// exported piece really is inside that chapter and a file whose first
    /// minutes belong to no chapter reads as a bug.
    private static func chapterSamples(
        _ chapters: [ExportChapter], in range: CMTimeRange, format: CMFormatDescription
    ) -> [CMSampleBuffer] {
        let start = CompositionBuilder.ticks(range.start)
        let end = start + CompositionBuilder.ticks(range.duration)
        guard end > start else { return [] }

        var inside: [ExportChapter] = []
        for chapter in chapters where chapter.start < end {
            if chapter.start <= start {
                inside = [ExportChapter(start: start, name: chapter.name)]
            } else {
                inside.append(chapter)
            }
        }
        guard !inside.isEmpty else { return [] }

        var samples: [CMSampleBuffer] = []
        for (index, chapter) in inside.enumerated() {
            let next = index + 1 < inside.count ? inside[index + 1].start : end
            guard next > chapter.start else { continue }
            let timeRange = CMTimeRange(
                start: CompositionBuilder.time(chapter.start - start),
                duration: CompositionBuilder.time(next - chapter.start))
            guard let sample = chapterSample(chapter.name, timeRange: timeRange, format: format)
            else { continue }
            samples.append(sample)
        }
        return samples
    }

    /// One text sample: a 16-bit big-endian byte count followed by the UTF-8
    /// name, which is the payload both QuickTime text and 3GPP timed text
    /// carry. Names are truncated at the length that count can express —
    /// 64 KB of chapter title is not a case worth failing an export over.
    private static func chapterSample(
        _ name: String, timeRange: CMTimeRange, format: CMFormatDescription
    ) -> CMSampleBuffer? {
        var text = Array(name.utf8)
        if text.count > 0xFFFF { text = Array(text.prefix(0xFFFF)) }
        var payload: [UInt8] = [UInt8(text.count >> 8), UInt8(text.count & 0xFF)]
        payload.append(contentsOf: text)

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: payload.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let buffer = block,
            CMBlockBufferReplaceDataBytes(
                with: payload, blockBuffer: buffer, offsetIntoDestination: 0,
                dataLength: payload.count) == kCMBlockBufferNoErr
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: timeRange.duration, presentationTimeStamp: timeRange.start,
            decodeTimeStamp: .invalid)
        var size = payload.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }

    // MARK: - Time

    /// The same sample, `delta` earlier. Every timing entry moves, decode
    /// stamps included, so a codec that reorders frames stays coherent.
    private static func retimed(_ sample: CMSampleBuffer, by delta: CMTime) -> CMSampleBuffer? {
        guard delta.isNumeric, delta != .zero else { return sample }
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr,
            count > 0
        else { return nil }
        var timings = [CMSampleTimingInfo](
            repeating: CMSampleTimingInfo(
                duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: Int(count))
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: nil) == noErr
        else { return nil }
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isNumeric {
                timings[index].presentationTimeStamp =
                    timings[index].presentationTimeStamp - delta
            }
            if timings[index].decodeTimeStamp.isNumeric {
                timings[index].decodeTimeStamp = timings[index].decodeTimeStamp - delta
            }
        }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: count,
            sampleTimingArray: &timings, sampleBufferOut: &copy) == noErr
        else { return nil }
        return copy
    }
}
