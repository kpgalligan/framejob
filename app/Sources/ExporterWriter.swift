import AVFoundation

// MARK: - The writer pipeline

/// Reads the composed movie back out of AVFoundation and writes it to a file:
/// the `AVAssetWriter` half of `Exporter` (spec §7.8).
///
/// **One movie, one description of it.** The reader is built over the SAME
/// `AVComposition`, the SAME `AVVideoComposition` and the SAME `AVAudioMix`
/// that `Playback` plays and `Exporter.renderFrame` samples — the custom
/// `Compositor` runs here exactly as it does on screen, from the same frame
/// recipes, through the same `RecipeSource` slot, and so do the audio mix's
/// processing taps (`addAudioOutput`). Nothing in this file draws a pixel;
/// beyond the alpha rows' straightening (below), it moves what AVFoundation
/// composed into an encoder and adds the three things a preset name cannot
/// express: a chapter track, explicit bitrates, and an output size the sheet
/// actually promised.
///
/// **The two samples it touches** are made here because this is where the
/// export's samples exist, and both are export-only by definition. One is
/// the loudness normalisation's gain: the preview and the file still share
/// one description of the sound (the mix, the ramps and the taps) and differ
/// only by a number the export was asked for. `Exporter` measured that
/// number a moment earlier from a float read of the mix; a gained export
/// reads the same float mix and `ExportAudioGain` multiplies and quantises it
/// once to the 16-bit format every encoder here takes (spec §11 #86). An
/// export with no gain reads the 16-bit decode it always read. The other is
/// the alpha movie rows' picture (`prores_4444`, `hevc_alpha`): the
/// compositor's premultiplied frame is un-premultiplied, its transparent
/// pixels' colour filled from the nearest visible one, and labelled
/// straight (`ExportStraightAlpha`, spec §11 G-35); every other row's frame
/// goes to the encoder as the compositor drew it.
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
/// lands within one frame, and the reader is torn down only once every pump
/// has left its loop (`cancel`); `AVAssetWriter` has no `progress` of its own, so
/// the fraction is kept here from the presentation time of the last sample
/// appended and `Exporter`'s 0.1 s timer reads it.
final class ExportWriter {

    /// The composition, held for the whole write. Not merely tidiness: the
    /// compositor asks `RecipeSource` for a recipe per frame, and the
    /// instructions inside this object carry the key it asks under.
    private let built: BuiltComposition
    private let destination: URL
    /// The slice of the composition being written, in composition time.
    let range: CMTimeRange
    /// `range.duration` in seconds, or 0 for a degenerate range — the
    /// denominator of `progress`.
    private let totalSeconds: Double

    private let reader: AVAssetReader
    let writer: AVAssetWriter
    private var videoOutput: AVAssetReaderOutput?
    var videoInput: AVAssetWriterInput?
    private var audioOutput: AVAssetReaderOutput?
    var audioInput: AVAssetWriterInput?
    var chapterInput: AVAssetWriterInput?
    var chapterSamples: [CMSampleBuffer] = []

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

    /// The loudness normalisation's gain, or nil when there is none — and
    /// nil is not a multiply by one: the audio is then read as the 16-bit
    /// decode and `pump` never enters the gain path, so an export that was
    /// not normalised is byte-identical to one from before this file knew
    /// what loudness was, by construction rather than by argument.
    ///
    /// Written once, on the main thread, between `init` and `start`; read
    /// by `start` and then only on `audioQueue`. Not under the lock for that
    /// reason and no other.
    private var audioGain: ExportAudioGain?

    /// Whether the video pump straightens each frame (spec §11 G-35): the
    /// row's `alpha`, set once by `addVideo` in `init` and read only by
    /// `start`.
    private var straightensAlpha = false

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
        addChapters(chapters, settings: settings)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportWriter does not support NSCoder")
    }

    /// Multiplies every audio sample by `gain` on the way to the encoder —
    /// the second half of a loudness-normalised export (`Exporter`'s
    /// measurement pass is the first).
    ///
    /// Main thread, after `init` and before `start`: the gain is the
    /// measurement's answer, and the measurement runs on the build queue
    /// while this object is being constructed. `Exporter.startWriting` is
    /// the one caller.
    ///
    /// A non-finite or non-positive gain is ignored rather than obeyed. A
    /// gain is a number derived from a measurement, and a measurement of
    /// digital silence is −∞; multiplying a file by that would be a silent
    /// export reported as a success. A gain of exactly 1 is ignored too, so
    /// it keeps the un-normalised read.
    func normalizeAudio(byLinearGain gain: Float) {
        guard gain.isFinite, gain > 0, gain != 1 else { return }
        audioGain = ExportAudioGain(linearGain: gain)
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
        let canvas = built.videoComposition.renderSize
        try Self.checkAlphaSurvivesTheSize(settings, canvas: canvas)
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
        output.videoComposition = Self.videoComposition(built, settings: settings)
        // AVFoundation's default, kept explicit: `ExportStraightAlpha` rewrites an
        // alpha row's frame in place, which is safe only on the reader's own copy.
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else {
            throw Exporter.ExportError.failed(
                "The composition could not be read for export.")
        }
        reader.add(output)

        let input = AVAssetWriterInput(
            mediaType: .video, outputSettings: try Self.videoSettings(settings, canvas: canvas))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw Exporter.ExportError.presetUnavailable(Self.presetName(settings))
        }
        writer.add(input)
        videoOutput = output
        videoInput = input
        straightensAlpha = settings.alpha
    }

    /// The audio half: every composition audio track through the plan's mix.
    ///
    /// **`addAudioOutput`'s `audioMix` line is where the preview and the file
    /// agree about sound.**
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
    ///
    /// This adds the writer INPUT only. The reader output is added by `start`
    /// (`addAudioOutput`), because its format depends on the gain, which
    /// arrives after `init`.
    private func addAudio(settings: ExportSettings) throws {
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            if settings.isAudioOnly { throw Exporter.ExportError.emptyTimeline }
            return
        }
        let input = AVAssetWriterInput(
            mediaType: .audio, outputSettings: Self.audioSettings(settings))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw Exporter.ExportError.presetUnavailable(Self.presetName(settings))
        }
        writer.add(input)
        audioInput = input
    }

    /// The mix's reader output: the 16-bit decode, or with a gain the float
    /// mix the measurement read (`ExportAudioGain.floatMixSettings`). False
    /// when the reader refuses it; there is no 16-bit fallback for a gained
    /// export, because the gain would then meet a decode that already clipped.
    private func addAudioOutput() -> Bool {
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: built.composition.tracks(withMediaType: .audio),
            audioSettings: audioGain == nil
                ? Self.decodedAudioSettings : ExportAudioGain.floatMixSettings)
        output.audioMix = built.audioMix
        // AVFoundation's own default, kept explicit because the other reader
        // in this tree (`MediaImporter.peaks`) turns it off.
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        audioOutput = output
        return true
    }

    // MARK: - Running

    /// Starts the write. Main thread; `completion` is called exactly once, on
    /// the main thread, and may be called before this returns if the writer
    /// refuses to start at all.
    func start(completion: @escaping (Result<URL, any Error>) -> Void) {
        self.completion = completion
        // A cancel that arrived BEFORE this call is honoured here, before the
        // reader or the writer has started, rather than one sample later.
        lock.lock()
        let cancelledAlready = cancelRequested
        lock.unlock()
        guard !cancelledAlready else {
            report(.failure(Exporter.ExportError.cancelled))
            return
        }
        if audioInput != nil, !addAudioOutput() {
            report(.failure(Exporter.ExportError.failed(
                "The audio mix could not be read for export.")))
            return
        }
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
            pump(
                input, from: output, on: videoQueue, group: group, tracksProgress: true,
                straightAlpha: straightensAlpha)
        }
        if let input = audioInput, let output = audioOutput {
            // Audio drives the bar only when there is no picture to drive it,
            // and it is the only pump that can carry a gain.
            pump(
                input, from: output, on: audioQueue, group: group,
                tracksProgress: videoInput == nil, gain: audioGain)
        }
        if let input = chapterInput {
            pumpChapters(input, on: chapterQueue, group: group)
        }
        group.notify(queue: .main) { [weak self] in self?.allInputsFinished() }
    }

    /// Stops as soon as the pumps notice — within one sample. Safe from any
    /// thread and safe to call twice. It ONLY sets the flag: the reader and
    /// the writer are cancelled in `allInputsFinished`, after every pump has
    /// left its loop.
    ///
    /// **Cancelling the reader from here crashed the app** (road map 10
    /// §10.6, G3c). `reader.cancelReading()` on main while a pump was inside
    /// `copyNextSampleBuffer` tore the reader down under it: EXC_BREAKPOINT
    /// in `CMVideoFormatDescriptionMatchesImageBuffer` on the video queue, in
    /// 12 of 30 mid-export cancels of a 4K graphic project — the sheet's and
    /// the queue's Cancel path — and 16 of 40 exports stopped by a failing
    /// graphic. The cost is that a pump blocked on a slow read finishes that
    /// one sample before it stops — and a `copyNextSampleBuffer` that never
    /// returns (a pump starved because the other stopped reading) can no
    /// longer be woken by a cancel, so the completion would never fire; not
    /// seen in 70 runs, and accepted (spec §11 G-17). A cancel before `start` is refused there;
    /// `cancelReading()` before `startReading()` would raise.
    func cancel() {
        lock.lock()
        cancelRequested = true
        lock.unlock()
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
    ///
    /// `gain` is nil for every pump but the audio one, and nil for the audio
    /// one too unless the export asked to be normalised — which is what
    /// keeps an ordinary export on exactly the samples it had before.
    /// `straightAlpha` is true only for the video pump of an alpha row: each
    /// frame is then straightened and labelled (`ExportStraightAlpha`).
    private func pump(
        _ input: AVAssetWriterInput, from output: AVAssetReaderOutput, on queue: DispatchQueue,
        group: DispatchGroup, tracksProgress: Bool, gain: ExportAudioGain? = nil,
        straightAlpha: Bool = false
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
                guard let decoded = output.copyNextSampleBuffer() else {
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
                let time = CMSampleBufferGetPresentationTimeStamp(decoded) - self.range.start
                // A sample that starts before the range does not belong to
                // this file. The reader clips to `timeRange`, so this is a
                // boundary frame, not a common case.
                guard time.isNumeric, time >= .zero else { continue }
                // An empty buffer has nothing to gain and is not malformed:
                // it is skipped, as the old Int16 kernel passed it through.
                if gain != nil, CMSampleBufferGetNumSamples(decoded) == 0 { continue }
                // The gain makes a NEW 16-bit buffer from the float one,
                // before `retimed`; with no gain the decode goes on as read.
                guard let sample = gain == nil ? decoded : gain?.apply(to: decoded) else {
                    self.stopped(
                        with: Exporter.ExportError.failed(
                            "The loudness gain could not be applied to a sample."))
                    stop()
                    return
                }
                // An alpha row's frame, un-premultiplied and labelled straight
                // (spec §11 G-35), before `retimed`; any other goes on as read.
                guard let ready = straightAlpha ? ExportStraightAlpha.straighten(sample) : sample
                else {
                    self.stopped(
                        with: Exporter.ExportError.failed(
                            "A frame's transparency could not be written straight."))
                    stop()
                    return
                }
                guard let rebased = Self.retimed(ready, by: self.range.start) else {
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

    // MARK: - Finishing

    /// True once anything has asked the write to stop.
    var isStopping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested || failure != nil
    }

    /// Records the first failure; later ones are noise from the other pumps
    /// unwinding. The other pumps see it before their next sample, and the
    /// read is cancelled in `allInputsFinished` (`cancel`'s doc says why).
    private func stopped(with error: any Error) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
    }

    private func advance(to time: CMTime) {
        guard totalSeconds > 0 else { return }
        let fraction = CMTimeGetSeconds(time) / totalSeconds
        lock.lock()
        progressValue = min(max(fraction, progressValue), 1)
        lock.unlock()
    }

    /// Main thread, once every input has marked itself finished — so no pump
    /// is inside `copyNextSampleBuffer`, and the reader can be cancelled.
    private func allInputsFinished() {
        lock.lock()
        let error = failure
        let cancelled = cancelRequested
        lock.unlock()
        if error != nil || cancelled { reader.cancelReading() }
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
