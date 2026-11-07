import AVFoundation

// MARK: - The writer pipeline

/// Reads the composed movie back out of AVFoundation and writes it to a file:
/// the `AVAssetWriter` half of `Exporter` (spec §7.8).
///
/// **One movie, one description of it.** The readers are built over the SAME
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
/// the sound's master (spec §11 AU-27): the preview and the file still share
/// one description of the sound (the mix, the ramps and the taps) and differ
/// by the loudness gain the export was asked for and the master limiter the
/// preview has none of. `Exporter` measured the gain a moment earlier from a
/// float read of the mix; every export reads the same float mix and
/// `ExportAudioMaster` gains it, limits it at the export's ceiling and
/// quantises it once to the 16- or 24-bit samples the encoder takes (#86,
/// AU-29). The other is
/// the alpha movie rows' picture (`prores_4444`, `hevc_alpha`): the
/// compositor's premultiplied frame is un-premultiplied, its transparent
/// pixels' colour filled from the nearest visible one, and labelled
/// straight (`ExportStraightAlpha`, spec §11 G-35); `h264`'s, `hevc`'s and
/// `hevc_alpha`'s are first rounded to 8 bits (`ExportFrames`, PR-3), and
/// every other row's frame goes to the encoder as the compositor drew it.
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
/// **One reader per output** (spec §11 #378, CX-15 (2)): the video composition
/// output and the audio mix output each have an `AVAssetReader` over the same
/// composition and range, so neither read can be starved by the other pump's stop.
///
/// **Cancellation and progress.** Every sample checks the flag, so a cancel
/// lands within one frame, and each pump cancels its own reader on its own
/// queue after its own last read (`cancel`); `AVAssetWriter` has no `progress` of its own, so
/// the fraction is kept here from the presentation time of the last sample
/// appended and `Exporter`'s 0.1 s timer reads it.
final class ExportWriter {

    /// The composition, held for the whole write. Not merely tidiness: the
    /// compositor asks `RecipeSource` for a recipe per frame, and the
    /// instructions inside this object carry the key it asks under.
    let built: BuiltComposition
    private let destination: URL
    /// The slice of the composition being written, in composition time.
    let range: CMTimeRange
    /// `range.duration` in seconds, or 0 for a degenerate range — the
    /// denominator of `progress`.
    private let totalSeconds: Double

    /// The video composition's reader, nil for an audio-only row, and the mix's,
    /// nil for a silent movie (#378); each cancelled only by its own pump.
    private let videoReader: AVAssetReader?
    let audioReader: AVAssetReader?
    let writer: AVAssetWriter
    private var videoOutput: AVAssetReaderOutput?
    var videoInput: AVAssetWriterInput?
    var audioRead: ExportMixRead?
    var audioInput: AVAssetWriterInput?
    var chapterInput: AVAssetWriterInput?
    var chapterSamples: [CMSampleBuffer] = []

    /// One serial queue per input, as `requestMediaDataWhenReady` requires.
    /// Separate queues rather than one shared serial queue: the audio pump
    /// must not sit behind a 4K frame being appended.
    private let videoQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export.audio", qos: .userInitiated)
    private let chapterQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export.chapters", qos: .userInitiated)

    /// Guards everything the pumps and the main thread both touch.
    private let lock = NSLock()
    private var progressValue: Double = 0
    private var cancelRequested = false
    private var failure: (any Error)?

    /// Called once, on the main thread, and then dropped.
    private var completion: ((Result<URL, any Error>) -> Void)?

    /// The sound's master (spec §11 AU-27): the gain, the limiter and the
    /// quantiser every audio buffer goes through; nil for a silent movie.
    ///
    /// Made by `addAudio` in `init`; its gain is set once, on the main thread,
    /// between `init` and `start`; read then only on `audioQueue`. Not under
    /// the lock for that reason and no other.
    var audioMaster: ExportAudioMaster?

    /// What the video pump makes of each frame (spec §11 G-35, PR-3;
    /// `frameForm`), set once by `addVideo` in `init` and read only by
    /// `start`; nil hands each frame on as drawn.
    private var frames: ExportFrames?

    /// The encoder row's video pump (`settings.writer`, spec §11 CX-12), set by `addVideo`;
    /// nil on every row AVFoundation encodes.
    private var encodePump: ExportEncodePump?

    /// The audio pump's `end`: the sound cut at the range, padded to it (#337).
    private let audioEnd: ExportAudioEnd

    /// `-RCDevExportFault` (`ExportWebMDevFault`, dev tools only, #378), else nil.
    let fault = ExportWebMDevFault.current(key: ExportWebMDevFault.writerKey)

    /// Builds the readers, the writer and every track, or throws the
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
        self.audioEnd = ExportAudioEnd(range: range, bits: settings.audioBits ?? 16)

        let hasAudio = !built.composition.tracks(withMediaType: .audio).isEmpty
        do {
            videoReader = settings.isAudioOnly ? nil : try AVAssetReader(asset: built.composition)
            audioReader = hasAudio ? try AVAssetReader(asset: built.composition) : nil
            writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        } catch {
            throw Exporter.ExportError.failed(error.localizedDescription)
        }
        videoReader?.timeRange = range
        audioReader?.timeRange = range
        writer.shouldOptimizeForNetworkUse = settings.optimizeForNetwork

        try addVideo(settings: settings)
        try addAudio(settings: settings)
        addChapters(chapters, settings: settings)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportWriter does not support NSCoder")
    }

    /// Sets the master's gain, which multiplies every audio sample on the way
    /// to the limiter — the second half of a loudness-normalised export
    /// (`Exporter`'s measurement pass is the first).
    ///
    /// Main thread, after `init` and before `start`: the gain is the
    /// measurement's answer, and the measurement runs on the build queue
    /// while this object is being constructed. `Exporter.startWriting` is
    /// the one caller.
    ///
    /// A non-finite or non-positive gain is ignored rather than obeyed. A
    /// gain is a number derived from a measurement, and a measurement of
    /// digital silence is −∞; multiplying a file by that would be a silent
    /// export reported as a success. A gain of exactly 1 is the master's own.
    func normalizeAudio(byLinearGain gain: Float) {
        guard gain.isFinite, gain > 0, gain != 1 else { return }
        audioMaster?.linearGain = gain
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
        let output = Self.videoReadOutput(built, settings: settings)
        guard videoReader!.canAdd(output) else {
            throw Exporter.ExportError.failed(
                "The composition could not be read for export.")
        }
        videoReader!.add(output)

        // An encoder row's packets go in as they are (`ExportEncodePump`).
        let pump = settings.writer == ExportEncodePump.av1Writer
            ? try ExportEncodePump(settings: settings, canvas: canvas, range: range) : nil
        let input = try pump.map {
            AVAssetWriterInput(
                mediaType: .video, outputSettings: nil, sourceFormatHint: $0.formatDescription)
        } ?? AVAssetWriterInput(
            mediaType: .video, outputSettings: try Self.videoSettings(settings, canvas: canvas))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw Exporter.ExportError.presetUnavailable(Self.presetName(settings))
        }
        writer.add(input)
        videoOutput = output
        videoInput = input
        encodePump = pump
        frames = Self.frameForm(settings).map { ExportFrames(form: $0) }
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
        if let videoReader, !videoReader.startReading() {
            writer.cancelWriting()
            report(.failure(videoReader.error ?? Exporter.ExportError.failed(
                "The composition could not be read for export.")))
            return
        }
        // A reader not yet started is started (as `ExportWebMWriter` does).
        if let audioReader, audioReader.status == .unknown, !audioReader.startReading() {
            videoReader?.cancelReading()
            writer.cancelWriting()
            report(.failure(audioReader.error ?? Exporter.ExportError.failed(
                "The audio mix could not be read for export.")))
            return
        }
        // Zero, not `range.start`: the samples are rebased on the way in, so
        // the file's timeline is its own.
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        if let input = videoInput, let output = videoOutput, let encodePump {
            encodePump.run(
                sink: ExportMP4PacketSink(input: input, format: encodePump.formatDescription),
                output: output, on: videoQueue, group: group,
                isStopping: { [weak self] in self?.isStopping ?? true },
                readFailure: { [weak self] in self?.readFailure(of: self?.videoReader) },
                fail: { [weak self] error in self?.stopped(with: error) },
                advance: { [weak self] time in self?.advance(to: time) })
            // The video reader's own cancel, on its queue after the pump's read loop (#378).
            group.enter()
            videoQueue.async { [weak self] in
                defer { group.leave() }
                if let self, self.isStopping { self.videoReader?.cancelReading() }
            }
        } else if let input = videoInput, let output = videoOutput, let videoReader {
            pump(
                input, read: { output.copyNextSampleBuffer() }, reading: videoReader,
                on: videoQueue, group: group, tracksProgress: true, frames: frames)
        }
        if let input = audioInput, let read = audioRead, let audioReader {
            // Audio drives the bar only when there is no picture to drive it,
            // and it is the only pump with a master.
            pump(
                input, read: { try read.next() }, reading: audioReader, on: audioQueue,
                group: group, tracksProgress: videoInput == nil, master: audioMaster,
                end: audioEnd)
        }
        if let input = chapterInput {
            pumpChapters(input, on: chapterQueue, group: group)
        }
        group.notify(queue: .main) { [weak self] in self?.allInputsFinished() }
    }

    /// Stops as soon as the pumps notice — within one sample. Safe from any
    /// thread and safe to call twice. It ONLY sets the flag: each pump cancels
    /// its own reader on its own queue after its own last read, and the writer
    /// is cancelled in `allInputsFinished`, after every pump has left its loop
    /// (spec §11 #378).
    ///
    /// **Cancelling the reader from here crashed the app** (road map 10
    /// §10.6, G3c). `reader.cancelReading()` on main while a pump was inside
    /// `copyNextSampleBuffer` tore the reader down under it: EXC_BREAKPOINT
    /// in `CMVideoFormatDescriptionMatchesImageBuffer` on the video queue, in
    /// 12 of 30 mid-export cancels of a 4K graphic project — the sheet's and
    /// the queue's Cancel path — and 16 of 40 exports stopped by a failing
    /// graphic. The cost is that a pump blocked on a slow read finishes that
    /// one sample before it stops. A pump can no longer be starved by the
    /// other's stop, each output having its own reader (#378); a
    /// `copyNextSampleBuffer` that never returns for another reason (a volume
    /// that stops answering) is not woken, and accepted (spec §11 G-17). A
    /// cancel before `start` is refused there; `cancelReading()` before
    /// `startReading()` would raise.
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

    // MARK: - Finishing

    /// True once anything has asked the write to stop.
    var isStopping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested || failure != nil
    }

    /// Records the first failure; later ones are noise from the other pumps
    /// unwinding. The other pumps see it before their next sample, and each
    /// reader is cancelled by its own pump (`cancel`'s doc says why).
    func stopped(with error: any Error) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
    }

    /// `reader`'s error once its read failed, else nil — each pump's question at
    /// the end of its read.
    func readFailure(of reader: AVAssetReader?) -> (any Error)? {
        guard let reader, reader.status == .failed else { return nil }
        return reader.error
            ?? Exporter.ExportError.failed("The composition could not be read to the end.")
    }

    func advance(to time: CMTime) {
        guard totalSeconds > 0 else { return }
        let fraction = CMTimeGetSeconds(time) / totalSeconds
        lock.lock()
        progressValue = min(max(fraction, progressValue), 1)
        lock.unlock()
    }

    /// Main thread, once every input has marked itself finished — each reader
    /// already cancelled by its own pump on a stop (#378): the writer is
    /// cancelled or finished.
    private func allInputsFinished() {
        lock.lock()
        let error = failure
        let cancelled = cancelRequested
        lock.unlock()
        if fault != nil {
            let state = { (reader: AVAssetReader?) in
                reader.map { "\($0.status.rawValue)" } ?? "none"
            }
            let shared = audioReader != nil && audioReader === videoReader ? " (one reader)" : ""
            fault?.note(
                "readers: video \(state(videoReader)), audio \(state(audioReader))" + shared)
        }
        encodePump?.close()
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
        // "I do not want this file": `Exporter.finish` removes the file on a
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
        // The `av01` brand AVAssetWriter leaves out (spec §11 CX-12 (4)).
        if encodePump != nil {
            do {
                try ExportAV1Track.brandFile(destination)
            } catch {
                report(.failure(error))
                return
            }
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
}
