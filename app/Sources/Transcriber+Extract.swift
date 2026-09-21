import AVFoundation

// MARK: - Transcriber: extraction

/// The extractor: a job's SOURCE WINDOW written to a temporary mono 16 kHz
/// 16-bit WAV, which is what the recogniser is handed instead of the
/// project's media file (`Transcriber.swift`'s header argues why), with
/// `extractSettings` the one spelling of that format.
///
/// A pure move out of `Transcriber.swift`, road map 6's C1 toll 1. The block
/// came here whole and in its own order, with every line byte-identical.
/// One widening: `extractAudio(_:cancel:)` is internal rather than
/// `private`, which the compiler forces — `transcribe`, its one caller,
/// stayed behind. `extractSampleRate` and `extractSettings` stay `private`.
extension Transcriber {

    // MARK: - Extraction

    /// What the recogniser is handed: 16 kHz mono 16-bit LPCM in a `.wav`.
    ///
    /// Mono and 16 kHz because that is what speech recognition works in — a
    /// minute of it is under two megabytes, where the app's own 48 kHz stereo
    /// mix (`ExporterWriter.decodedAudioSettings`) would be eleven — and LPCM
    /// because an intermediate should cost no generation of its own. The
    /// stereo→mono downmix and the rate conversion are the reader's:
    /// `AVAssetReaderTrackOutput` does both, with no channel layout needed for
    /// one channel out.
    private static let extractSampleRate = 16000

    private static let extractSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: extractSampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// Writes the clip's source window to a temporary file and answers where
    /// it went and how long it really is.
    ///
    /// The length is counted in PCM frames rather than read back off the
    /// written asset: `AVAsset.duration` is deprecated in favour of an
    /// `async` accessor this file may not use (app/CLAUDE.md), and frames
    /// divided by a known sample rate is the more exact number anyway. It is
    /// what the truncation test compares against, so it has to be the audio
    /// the recogniser was actually given, not the range that was asked for —
    /// a clip whose source window runs past the end of its file gets a
    /// shorter extract and must not be called truncated for it.
    ///
    /// The file goes in `NSTemporaryDirectory()`, never inside the package:
    /// it is an input to one recognition and is deleted the moment that
    /// recognition ends, unlike a reversed render, which is expensive enough
    /// to be worth carrying (`ReverseCache`'s doc argues the other side).
    func extractAudio(_ job: Job, cancel: CancelToken) throws -> (
        url: URL, seconds: Double
    ) {
        let asset = AVURLAsset(
            url: job.source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // The app's one synchronous track lookup, so the deprecation it costs
        // is paid once (`CompositionBuilder.firstTrack`'s doc).
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw TranscribeError.unreadable(job.name)
        }

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reelcut-transcribe-\(UUID().uuidString).wav")
        try? FileManager.default.removeItem(at: destination)

        let range = CMTimeRange(
            start: CompositionBuilder.time(job.sourceIn),
            duration: CompositionBuilder.time(max(1, job.sourceLength)))
        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: destination, fileType: .wav)
        } catch {
            throw TranscribeError.failed(error.localizedDescription)
        }
        reader.timeRange = range

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: Self.extractSettings)
        guard reader.canAdd(output) else { throw TranscribeError.unreadable(job.name) }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.extractSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw TranscribeError.unreadable(job.name) }
        writer.add(input)

        guard reader.startReading() else {
            throw TranscribeError.failed(
                reader.error?.localizedDescription ?? "the audio could not be read")
        }
        guard writer.startWriting() else {
            throw TranscribeError.failed(
                writer.error?.localizedDescription ?? "the extract could not be opened")
        }
        // The session begins where the window does, so the first sample lands
        // at zero of the extract — which is what makes `project(_:in:)` a
        // single division with no `in` term in it.
        writer.startSession(atSourceTime: range.start)

        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            if cancel.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: destination)
                throw TranscribeError.cancelled
            }
            // 5 ms is far shorter than any buffer and far longer than a
            // context switch — `ReverseRenderer`'s number, for its reason.
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            guard input.append(sample) else {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: destination)
                throw TranscribeError.failed(
                    writer.error?.localizedDescription ?? "the extract could not be written")
            }
            frames += CMSampleBufferGetNumSamples(sample)
        }
        guard reader.status == .completed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw TranscribeError.failed(
                reader.error?.localizedDescription ?? "the audio stopped before it finished")
        }
        input.markAsFinished()
        // `finishWriting` closes the container on a queue of its own, and this
        // method's contract is that the file exists when it returns.
        let closed = DispatchSemaphore(value: 0)
        writer.finishWriting { closed.signal() }
        closed.wait()
        guard writer.status == .completed, frames > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw TranscribeError.unreadable(job.name)
        }
        return (destination, Double(frames) / Double(Self.extractSampleRate))
    }
}
