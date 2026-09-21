import AVFoundation

// MARK: - Transcriber: extraction

/// The extractor and what is made from it: a RANGE of any audio file written
/// to a mono 16 kHz 16-bit WAV (`extractAudio(url:name:range:to:cancel:)`),
/// the job form that names today's destination and calls it, the FLAC writer
/// C0's q2 chose for the upload, and `extractUpload`, which puts the two
/// together into the file a cloud run sends. `extractSettings` is the one
/// spelling of that format.
///
/// **The job form's behaviour is unchanged, and that is a claim.** The static
/// form is the block that was here verbatim, with the destination and the
/// range lifted out into its two arguments and `range.start` written where
/// the old code wrote the clip's `in`; the job form computes exactly the
/// destination and range the old code computed and calls it. The WAV a given
/// job extracts is byte-identical to the one the baseline tree's code wrote,
/// which is a row of `cloud_captions_probe.py` rather than a hope.
///
/// **The upload is a FLAC and the WAV is its fallback** (road map 6 §5a, §8).
/// C0's q2 measured a FLAC at 48.1% of the WAV's bytes whose decode is
/// sample-for-sample the same audio, with zero word-timing delta from the
/// service. It is written through `AVAudioFile`, NEVER `AVAssetWriter`:
/// `AVAssetWriter` has no `org.xiph.flac` file type on macOS 26 and refuses
/// it as an Objective-C exception, which Swift cannot catch (§3 q2). When the
/// FLAC write refuses for any other reason the WAV goes up instead and the
/// cache file records which was sent.
///
/// The on-device engine is untouched by all of it: it still hands the
/// recogniser the WAV of one clip's source window.
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
    ///
    /// Its whole body is the static form below, whose two arguments are the
    /// only things this adds: the destination and the range.
    func extractAudio(_ job: Job, cancel: CancelToken) throws -> (
        url: URL, seconds: Double
    ) {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reelcut-transcribe-\(UUID().uuidString).wav")
        let range = CMTimeRange(
            start: CompositionBuilder.time(job.sourceIn),
            duration: CompositionBuilder.time(max(1, job.sourceLength)))
        let frames = try Self.extractAudio(
            url: job.source, name: job.name, range: range, to: destination, cancel: cancel)
        return (destination, Double(frames) / Double(Self.extractSampleRate))
    }

    /// A range of ANY audio file to a mono 16 kHz 16-bit WAV at `destination`,
    /// answering the PCM frames written.
    ///
    /// `range` is a SOURCE range. `Transcriber.wholeAsset` is the whole
    /// track, which is what the cloud engine uploads (R6-3: one upload per
    /// media, every clip derived from it); a clip's own window is what the
    /// on-device engine asks for.
    ///
    /// `progress` fires with the running frame count on the calling thread,
    /// never hopped, `run`'s convention.
    static func extractAudio(
        url: URL, name: String, range: CMTimeRange, to destination: URL, cancel: CancelToken,
        progress: ((Int) -> Void)? = nil
    ) throws -> Int {
        let asset = AVURLAsset(
            url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        // The app's one synchronous track lookup, so the deprecation it costs
        // is paid once (`CompositionBuilder.firstTrack`'s doc).
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw TranscribeError.unreadable(name)
        }

        try? FileManager.default.removeItem(at: destination)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: destination, fileType: .wav)
        } catch {
            throw TranscribeError.failed(error.localizedDescription)
        }
        reader.timeRange = range

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: extractSettings)
        guard reader.canAdd(output) else { throw TranscribeError.unreadable(name) }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: extractSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw TranscribeError.unreadable(name) }
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
            progress?(frames)
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
            throw TranscribeError.unreadable(name)
        }
        return frames
    }

    // MARK: - What the cloud engine uploads

    /// What was actually sent (road map 6 §5b's `uploaded_format`).
    enum UploadFormat: String {
        case flac
        case wav
    }

    /// A file ready to upload, and everything the cache file needs to say
    /// about it.
    struct Upload: Equatable {
        let url: URL
        let format: UploadFormat
        /// PCM frames extracted, at `extractSampleRate`.
        let frames: Int
        /// `frames / 16000` — what was extracted, not what will be billed:
        /// `audio_duration` rounds UP (§3 q1).
        let seconds: Double
    }

    /// The whole audio track. `.positiveInfinity` rather than a measured
    /// duration on purpose: `AVAsset.duration` and `AVAssetTrack.timeRange`
    /// are deprecated getters whose replacements are `async`, and
    /// `AVAssetReader` clamps a range that runs past the end of the asset, so
    /// the number is not needed at all.
    static let wholeAsset = CMTimeRange(start: .zero, duration: .positiveInfinity)

    /// The WAV, decoded and re-encoded as a 16 kHz mono 16-bit FLAC.
    ///
    /// Streamed in 16 384-frame buffers, never the whole file in memory: the
    /// cloud engine's input is a media's WHOLE audio and ten hours of it is
    /// 1.1 GB of PCM. `cancel` is read per buffer, and `close()` — which
    /// `AVAudioFile` does on deinit — is forced before returning, because
    /// this function's contract is that the file is complete when it answers.
    ///
    /// The four settings are C0's, copied from
    /// `tools/proof/cloud_spike/extract.swift:167`, which is the run that
    /// measured the decode to be sample-for-sample the WAV's.
    static func writeFLAC(fromWAV wav: URL, to destination: URL, cancel: CancelToken) throws {
        try? FileManager.default.removeItem(at: destination)
        guard
            let source = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: Double(extractSampleRate), channels: 1,
                interleaved: true)
        else { throw TranscribeError.failed("the extract format could not be described") }
        do {
            let reading = try AVAudioFile(forReading: wav, commonFormat: .pcmFormatInt16,
                                          interleaved: true)
            var file: AVAudioFile? = try AVAudioFile(
                forWriting: destination,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatFLAC),
                    AVSampleRateKey: extractSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                ], commonFormat: .pcmFormatInt16, interleaved: true)
            var left = reading.length
            while left > 0 {
                if cancel.isCancelled {
                    file = nil
                    try? FileManager.default.removeItem(at: destination)
                    throw TranscribeError.cancelled
                }
                let count = AVAudioFrameCount(min(AVAudioFramePosition(flacBufferFrames), left))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: count)
                else { throw TranscribeError.failed("the FLAC buffer could not be made") }
                try reading.read(into: buffer, frameCount: count)
                guard buffer.frameLength > 0 else { break }
                try file?.write(from: buffer)
                left -= AVAudioFramePosition(buffer.frameLength)
            }
            // `AVAudioFile` has no `close()`; releasing it is the close, and
            // it is forced here rather than left to the end of the scope.
            file = nil
        } catch let error as TranscribeError {
            throw error
        } catch {
            throw TranscribeError.failed(error.localizedDescription)
        }
    }

    /// 16 384 frames is about a second at 16 kHz — the spike's number.
    private static let flacBufferFrames = 16_384

    /// A media's WHOLE audio as the file a cloud run uploads: the WAV first,
    /// then the FLAC beside it.
    ///
    /// **The fallback.** When `flac` throws anything but a cancellation the
    /// partial FLAC is removed and the WAV is answered as `.wav` — the upload
    /// is twice the bytes and the transcript is the same, which is a far
    /// better answer than refusing to transcribe because a codec was not
    /// there (§5a, §8). A cancellation is the person's instruction and
    /// propagates. On success the WAV goes, because it has done its job.
    ///
    /// `flac` is an argument so a probe can force the refusal and measure the
    /// fallback; its default IS `writeFLAC`, so the shipped path has one
    /// spelling.
    static func extractUpload(
        url: URL, name: String, cancel: CancelToken, progress: ((Int) -> Void)? = nil,
        flac: (URL, URL, CancelToken) throws -> Void = Transcriber.writeFLAC
    ) throws -> Upload {
        let stem = "reelcut-upload-\(UUID().uuidString)"
        let wav = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(stem).wav")
        let frames = try extractAudio(
            url: url, name: name, range: wholeAsset, to: wav, cancel: cancel, progress: progress)
        let seconds = Double(frames) / Double(extractSampleRate)
        let compressed = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(stem).flac")
        do {
            try flac(wav, compressed, cancel)
        } catch TranscribeError.cancelled {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: compressed)
            throw TranscribeError.cancelled
        } catch {
            try? FileManager.default.removeItem(at: compressed)
            return Upload(url: wav, format: .wav, frames: frames, seconds: seconds)
        }
        try? FileManager.default.removeItem(at: wav)
        return Upload(url: compressed, format: .flac, frames: frames, seconds: seconds)
    }
}
