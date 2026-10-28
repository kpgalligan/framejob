import AVFoundation
import os

/// The WebM rows' pipeline (spec §11 CX-15, CX-16, CX-17): `av1_webm`, `vp9_webm` and
/// `vp9_alpha_webm`, the composed movie read back exactly as `ExportWriter` reads it, its
/// picture encoded by the same `ExportEncodePump` (SVT-AV1 or libvpx by `writer`, with the
/// alpha's second stream on `vp9_alpha_webm`) and its sound by `ExportOpusEncoder`, written
/// into a WebM by the core (`ReelWebM`). The alpha row is held to G-33's shape rule as the
/// other alpha movie rows are (`ExportWriter.checkAlphaSurvivesTheSize`).
///
/// **A second `ExportPipeline`, and the exception to §7.8's one writer (CX-15 (2)).**
/// `AVAssetWriter` writes no WebM, so this file is the WebM half of `ExportWriter` and
/// nothing more: the same reader outputs (`ExportWriter.videoReadOutput` /
/// `audioReadOutput`), each on a reader of its own (below), the same gain (`ExportAudioGain`), the same end of the sound
/// (`ExportAudioEnd`, #337), the same chapters (`ExportChapter.partition`), the same size and
/// rates (`encodedSize`, the pump). What is its own is the container: the core interleaves,
/// clusters, cues and closes the file. **A composition with no audio track is a silent
/// movie**, as in `ExportWriter.addAudio`: no audio output, encoder or queue, and the layout
/// has no audio track.
///
/// **Two pumps.** The video pump is `ExportEncodePump` on `videoQueue` into an
/// `ExportWebMPacketSink`. The audio pump reads, checks the time, applies the gain, cuts at
/// the range (`end.fit`), encodes and adds, on `audioQueue`; once the read is dry it encodes
/// the padding silence and the encoder's tail and cuts the surplus by DiscardPadding
/// (CX-15 (5)). The sound is placed at its stamps (`ExportAudioEnd.align`), so a dropped
/// straddling buffer or a hole in the stamps keeps later sound where it was. Neither waits
/// on the file: the core queues what the interleave holds.
///
/// **One `AVAssetReader` per output (CX-15 (2), (6)).** Two outputs of ONE reader are
/// coupled: an output nobody reads stalls the reader, so a pump that stopped could leave the
/// other blocked in `copyNextSampleBuffer` for good, and `cancelReading()` cannot wake it —
/// AVFoundation forbids it concurrently with a read, and it crashed (G-17). So the video
/// composition output and the audio mix output each have their own reader over the same
/// composition (measured: the same frames byte for byte and the same sound sample for
/// sample, `webm_export_proof.py` R1), neither read waits on the other, and each pump, once it
/// has left its loop on a stop, cancels its own reader on its own queue — no thread ever
/// cancels another's (G-17's rule). A silent movie has the video reader alone.
///
/// **Cancellation, failure and progress** are `ExportWriter`'s: a flag both pumps read
/// before each read, the first failure recorded once (`stopped(with:)`, logged), progress
/// from the frames submitted. A cancelled or failed export drops the writer and removes the
/// file; a finished one is closed by `ReelWebM.finish()` off the main thread and reported on
/// main. `-RCDevWebMFault` (`ExportWebMDevFault`, dev tools only) puts a fault in either
/// pump so a proof can time the stop.
final class ExportWebMWriter: ExportPipeline, ExportAudioNormalizing {
    private let built: BuiltComposition
    private let destination: URL
    let range: CMTimeRange
    private let totalSeconds: Double
    private let videoReader: AVAssetReader
    private let videoOutput: AVAssetReaderOutput
    /// The audio mix's own reader, nil for a silent movie; its output is added in `start`.
    let audioReader: AVAssetReader?
    private var audioOutput: AVAssetReaderOutput?
    let fault = ExportWebMDevFault.current()
    private let pump: ExportEncodePump
    private let opus: ExportOpusEncoder?
    let audioEnd: ExportAudioEnd
    private let layoutJSON: String
    private var webm: ReelWebM?
    /// Written once on main between `init` and `start`, then read only on `audioQueue`.
    private(set) var audioGain: ExportAudioGain?

    private let videoQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export.webm.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export.webm.audio", qos: .userInitiated)

    /// Guards everything the pumps and the main thread both touch.
    private let lock = NSLock()
    private var progressValue: Double = 0
    private var cancelRequested = false
    private var failure: (any Error)?
    /// Called once, on the main thread, and then dropped.
    private var completion: ((Result<URL, any Error>) -> Void)?

    /// Builds the readers, the video output, the encoder pump, the Opus encoder when there is
    /// sound and the file's layout, or throws the `Exporter.ExportError` the sheet shows.
    /// Nothing is read or written until `start`.
    init(
        built: BuiltComposition, settings: ExportSettings, chapters: [ExportChapter], to url: URL
    ) throws {
        guard settings.writer == ExportEncodePump.av1Writer
            || settings.writer == ExportEncodePump.vp9Writer
        else {
            throw Exporter.ExportError.presetUnavailable(ExportWriter.presetName(settings))
        }
        self.built = built
        destination = url
        range = Exporter.timeRange(settings, composition: built.composition)
        totalSeconds = max(0, CMTimeGetSeconds(range.duration))
        audioEnd = ExportAudioEnd(range: range)
        videoReader = try Self.reader(built.composition, range: range)
        // `ExportWriter.addVideo`'s guard: the placeholder track makes this never empty.
        guard !built.composition.tracks(withMediaType: .video).isEmpty else {
            throw Exporter.ExportError.emptyTimeline
        }
        let canvas = built.videoComposition.renderSize
        try ExportWriter.checkAlphaSurvivesTheSize(settings, canvas: canvas)
        videoOutput = ExportWriter.videoReadOutput(built, settings: settings)
        guard videoReader.canAdd(videoOutput) else {
            throw Exporter.ExportError.failed("The composition could not be read for export.")
        }
        videoReader.add(videoOutput)
        pump = try ExportEncodePump(settings: settings, canvas: canvas, range: range)
        // The silent movie (CX-15 (2)): no sound, no reader, encoder or audio track.
        let hasAudio = !built.composition.tracks(withMediaType: .audio).isEmpty
        audioReader = hasAudio ? try Self.reader(built.composition, range: range) : nil
        opus = hasAudio
            ? try ExportOpusEncoder(
                bitRate: settings.audioBitrate.map { max(1, $0) }
                    ?? ExportOpusEncoder.defaultBitRate)
            : nil
        layoutJSON = try ExportWebMLayout(
            settings: settings, range: range, codec: pump.webmCodec, picture: pump.picture,
            preSkip: opus?.preSkip, chapters: chapters
        ).json()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportWebMWriter does not support NSCoder")
    }

    /// A reader of `composition` over `range`, for one output.
    private static func reader(_ composition: AVComposition, range: CMTimeRange) throws
        -> AVAssetReader
    {
        do {
            let reader = try AVAssetReader(asset: composition)
            reader.timeRange = range
            return reader
        } catch {
            throw Exporter.ExportError.failed(error.localizedDescription)
        }
    }

    /// `ExportWriter.normalizeAudio`'s rule: a non-finite, non-positive or unit gain is
    /// ignored, so an export that was not normalised reads the 16-bit decode.
    func normalizeAudio(byLinearGain gain: Float) {
        guard gain.isFinite, gain > 0, gain != 1 else { return }
        audioGain = ExportAudioGain(linearGain: gain)
    }

    // MARK: - Running

    /// Starts the write. Main thread; `completion` is called exactly once, on main.
    func start(completion: @escaping (Result<URL, any Error>) -> Void) {
        self.completion = completion
        guard !isStopping else { return report(.failure(Exporter.ExportError.cancelled)) }
        if let audioReader {
            let output = ExportWriter.audioReadOutput(built, gained: audioGain != nil)
            guard audioReader.canAdd(output) else {
                return report(.failure(Exporter.ExportError.failed(
                    "The audio mix could not be read for export.")))
            }
            audioReader.add(output)
            audioOutput = output
        }
        let webm: ReelWebM
        do {
            webm = try ReelWebM(path: destination.path, layoutJSON: layoutJSON)
        } catch {
            // The core creates the file before it writes the header: remove what it left.
            discard()
            return report(.failure(Exporter.ExportError.failed(
                "The WebM file could not be made: \(error.localizedDescription)")))
        }
        self.webm = webm
        guard videoReader.startReading() else {
            discard()
            return report(.failure(videoReader.error ?? Exporter.ExportError.failed(
                "The composition could not be read for export.")))
        }
        // A reader not yet started is started; the video one is (nothing reads either yet).
        if let audioReader, audioReader.status == .unknown, !audioReader.startReading() {
            videoReader.cancelReading()
            discard()
            return report(.failure(audioReader.error ?? Exporter.ExportError.failed(
                "The audio mix could not be read for export.")))
        }
        let group = DispatchGroup()
        pump.run(
            sink: ExportWebMPacketSink(webm: webm, fault: fault), output: videoOutput,
            on: videoQueue, group: group, isStopping: { [weak self] in self?.isStopping ?? true },
            readFailure: { [weak self] in self?.readFailure(of: self?.videoReader) },
            fail: { [weak self] error in self?.stopped(with: error) },
            advance: { [weak self] time in self?.advance(to: time) })
        // The video reader's own cancel, on its queue after the pump's read loop (G-17).
        group.enter()
        videoQueue.async { [self] in
            defer { group.leave() }
            if isStopping { videoReader.cancelReading() }
        }
        if let opus, let output = audioOutput, let audioReader {
            group.enter()
            audioQueue.async { [self] in
                defer { group.leave() }
                pumpAudio(output, into: webm, through: opus)
                // Its own reader, after its own last read (G-17).
                if isStopping { audioReader.cancelReading() }
            }
        }
        group.notify(queue: .main) { [weak self] in self?.allPumpsLeft() }
    }

    /// Sets the flag; both pumps see it before their next sample. Any thread, any time.
    func cancel() {
        lock.lock()
        cancelRequested = true
        lock.unlock()
    }

    var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        return progressValue
    }

    // MARK: - Finishing

    var isStopping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested || failure != nil
    }

    func stopped(with error: any Error) {
        lock.lock()
        let first = failure == nil
        if first { failure = error }
        lock.unlock()
        // The unified log (not stdout or the proofs' log), so a stop names its cause.
        let which = first ? "first" : "later"
        let why = error.localizedDescription
        Self.log.error(
            "WebM export stopped (\(which, privacy: .public)): \(why, privacy: .public)")
    }

    private static let log = Logger(subsystem: "com.kgalligan.FrameJob", category: "export.webm")

    func readFailure(of reader: AVAssetReader?) -> (any Error)? {
        guard let reader, reader.status == .failed else { return nil }
        return reader.error
            ?? Exporter.ExportError.failed("The composition could not be read to the end.")
    }

    private func advance(to time: CMTime) {
        guard totalSeconds > 0 else { return }
        let fraction = CMTimeGetSeconds(time) / totalSeconds
        lock.lock()
        progressValue = min(max(fraction, progressValue), 1)
        lock.unlock()
    }

    /// Main thread, once both pumps have left (each reader already cancelled by its own
    /// pump on a stop): the encoder closed, then the file finished off main or dropped and
    /// removed.
    private func allPumpsLeft() {
        lock.lock()
        let error = failure
        let cancelled = cancelRequested
        lock.unlock()
        if fault != nil {
            let shared = audioReader === videoReader ? " (one reader)" : ""
            ExportWebMDevFault.log(
                "readers: video \(videoReader.status.rawValue), audio "
                    + (audioReader.map { "\($0.status.rawValue)" } ?? "none") + shared)
        }
        pump.close()
        if let error { return finishFailed(error) }
        if cancelled { return finishFailed(Exporter.ExportError.cancelled) }
        guard let webm else { return finishFailed(Exporter.ExportError.cancelled) }
        videoQueue.async { [weak self] in
            let closed: (any Error)?
            do {
                try webm.finish()
                closed = nil
            } catch {
                closed = Exporter.ExportError.failed(
                    "The WebM file could not be finished: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { self?.fileClosed(closed) }
        }
    }

    private func fileClosed(_ error: (any Error)?) {
        lock.lock()
        let cancelled = cancelRequested
        lock.unlock()
        if let error { return finishFailed(error) }
        // A cancel while the file was being closed still means "I do not want this file".
        if cancelled { return finishFailed(Exporter.ExportError.cancelled) }
        lock.lock()
        progressValue = 1
        lock.unlock()
        report(.success(destination))
    }

    private func finishFailed(_ error: any Error) {
        discard()
        report(.failure(error))
    }

    /// Drops the writer and removes the part-written file.
    private func discard() {
        webm = nil
        try? FileManager.default.removeItem(at: destination)
    }

    /// The one exit, main thread, at most once.
    private func report(_ result: Result<URL, any Error>) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }
}
