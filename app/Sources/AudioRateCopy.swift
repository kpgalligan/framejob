import AVFoundation

/// A non-48 kHz source's audio, read from a 48 kHz copy (spec §11 SY-23),
/// and an MP3's at any rate when Core Audio leaves its encoder delay in
/// (SY-36).
///
/// **Why:** an empty edit before a non-48 kHz segment on its composition
/// track is rate-converted wrongly, so the segment's sound lands off its
/// timeline place by an amount that grows with where it is placed (16 kHz
/// +39 ms at 10 s, lost past ±60 ms at 60 s; 44.1 kHz −12.7 ms at 10 s).
/// A 48 kHz source behind the same empty edit is exact, so the build reads
/// such a source's audio from a 48 kHz LPCM copy of it instead. An MP3 whose
/// LAME/Xing encoder delay no packet table removes (`MP3Gapless.leadingTrim`)
/// is copied at 48 kHz too, its read starting past that delay.
///
/// The copy is keyed by the FILE (its path, size and modification second,
/// and `version`), lives in `NSTemporaryDirectory()/FrameJob/AudioRate48/` —
/// regenerable, outside the package, purged by the OS, and not a §5.6 cache
/// entry — and is made on first need by the build, on the build's own queue,
/// blocking. One lock serialises the writing process-wide; a copy already on
/// disk is answered without taking it.
///
/// **The copy's sample 0 is the source track's time 0**: the read starts
/// where a leading empty edit ends, a gap before or between the reader's
/// buffers is written as zeros, and a buffer that starts before 0 or overlaps
/// the one before abandons the copy. With a trim, the copy's sample 0 is the
/// source's sample at the trim instead. A failed or
/// abandoned copy answers nil and the build reads the source as before, with
/// one log line.
enum AudioRateCopy {
    static let sampleRate = 48_000
    /// Part of every copy's key: bumping it orphans every copy written before.
    static let version = 2

    /// Zero-filled blocks for a gap, at most this many frames each.
    private static let silenceBlockFrames = 48_000

    private static let lock = NSLock()

    /// Every rate but 48 kHz converts, 96 kHz included, and so does an MP3
    /// with a trim at any rate (SY-36).
    static func needsCopy(_ signature: CompositionBuilder.AudioFormatSignature, trim: CMTime)
        -> Bool
    {
        signature.sampleRate != Double(sampleRate) || trim > .zero
    }

    static func directory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FrameJob", isDirectory: true)
            .appendingPathComponent("AudioRate48", isDirectory: true)
    }

    /// `<16-hex FNV-1a of "path|size|mtime-second|v<version>">.caf` in
    /// `directory()`; nil when the source cannot be stat'ed.
    static func destination(for source: URL) -> URL? {
        let path = source.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = (attributes[.size] as? NSNumber)?.uint64Value,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let second = Int64(modified.timeIntervalSince1970.rounded(.down))
        let key = "\(path)|\(size)|\(second)|v\(version)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let name = String(format: "%016llx", hash)
        return directory().appendingPathComponent(name).appendingPathExtension("caf")
    }

    /// The 48 kHz copy of `source`'s audio `track`, read from `trim`: the one
    /// on disk, else written now (blocking). Nil when it cannot be made. The
    /// key is the file's, since the trim is a function of the file.
    static func copy(of source: URL, track: AVAssetTrack, trim: CMTime) -> URL? {
        guard let destination = destination(for: source) else {
            log(source, "the source cannot be read")
            return nil
        }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        do {
            try FileManager.default.createDirectory(
                at: directory(), withIntermediateDirectories: true)
        } catch {
            log(source, error.localizedDescription)
            return nil
        }
        let partial = destination.deletingPathExtension()
            .appendingPathExtension("partial-\(getpid())")
            .appendingPathExtension("caf")
        try? FileManager.default.removeItem(at: partial)
        if let failure = write(track: track, source: source, trim: trim, to: partial) {
            try? FileManager.default.removeItem(at: partial)
            log(source, failure)
            return nil
        }
        guard rename(partial.path, destination.path) == 0 else {
            try? FileManager.default.removeItem(at: partial)
            log(source, "the copy could not be moved into place (errno \(errno))")
            return nil
        }
        return destination
    }

    /// The copy's format: 24-bit signed integer LPCM at 48 kHz, interleaved,
    /// with the source's channels up to two.
    private static func settings(channels: Int) -> [String: Any] {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag =
            channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
        return [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVChannelLayoutKey: Data(
                bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    /// Reads `track` as the copy's format from `trim` and writes it to `url`
    /// under the copy-timing rule. Nil on success, else why not.
    private static func write(track: AVAssetTrack, source: URL, trim: CMTime, to url: URL)
        -> String?
    {
        let channels = Int(
            min(max(CompositionBuilder.audioFormatSignature(of: track)?.channels ?? 2, 1), 2))
        let settings = settings(channels: channels)
        let asset = track.asset ?? AVURLAsset(url: source)
        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: url, fileType: .caf)
        } catch {
            return error.localizedDescription
        }
        // The read starts where a leading empty edit ends: the reader would
        // fill that edit itself, rate-converted to the wrong length, so the
        // gap padding below writes it at exactly 48 kHz instead.
        let head = leadingEmptyEnd(of: track)
        if head > .zero {
            reader.timeRange = CMTimeRange(start: head, duration: .positiveInfinity)
        }
        // An MP3's encoder delay Core Audio left in (SY-36): the read starts
        // past it.
        if trim > .zero {
            reader.timeRange = CMTimeRange(start: trim, duration: .positiveInfinity)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return "the reader refused the track" }
        reader.add(output)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { return "the writer refused the input" }
        writer.add(input)
        guard reader.startReading() else {
            return reader.error?.localizedDescription ?? "the reader did not start"
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            return writer.error?.localizedDescription ?? "the writer did not start"
        }
        // With a trim, frame 0 is the first buffer's first frame and the
        // session starts at its time; else both are zero.
        var origin: Int64? = trim > .zero ? nil : 0
        if origin != nil { writer.startSession(atSourceTime: .zero) }

        var failure: String?
        var end: Int64 = 0
        while failure == nil, let buffer = output.copyNextSampleBuffer() {
            let frames = Int64(CMSampleBufferGetNumSamples(buffer))
            guard frames > 0 else { continue }
            let stamp = CMTimeConvertScale(
                CMSampleBufferGetPresentationTimeStamp(buffer),
                timescale: CMTimeScale(sampleRate), method: .roundHalfAwayFromZero)
            guard stamp.isNumeric else {
                failure = "a buffer has no time"
                break
            }
            if origin == nil {
                origin = stamp.value
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
            }
            let zero = origin ?? 0
            let start = stamp.value - zero
            if start < 0 || end - start > 1 {
                failure = "a buffer starts at frame \(start), before frame \(end)"
                break
            }
            if start - end > 1 {
                var at = end
                while failure == nil, at < start {
                    let count = Int(min(Int64(silenceBlockFrames), start - at))
                    guard let zeros = silence(
                        frames: count,
                        at: CMTime(value: zero + at, timescale: CMTimeScale(sampleRate)),
                        like: buffer)
                    else {
                        failure = "the gap's silence could not be made"
                        break
                    }
                    failure = append(zeros, to: input, writer: writer)
                    at += Int64(count)
                }
                if failure != nil { break }
            }
            failure = append(buffer, to: input, writer: writer)
            end = start + frames
        }
        if failure == nil, reader.status == .failed {
            failure = reader.error?.localizedDescription ?? "the reader failed"
        }
        if let failure = failure {
            reader.cancelReading()
            writer.cancelWriting()
            return failure
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            return writer.error?.localizedDescription ?? "the writer did not finish"
        }
        return nil
    }

    /// The end of `track`'s empty edit at track time 0, else zero. Waited for
    /// on the build's own queue (`loadSegment`'s completion handler, no `async`).
    private static func leadingEmptyEnd(of track: AVAssetTrack) -> CMTime {
        final class Box: @unchecked Sendable { var end = CMTime.zero }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        track.loadSegment(forTrackTime: .zero) { segment, _ in
            if let segment = segment, segment.isEmpty,
                segment.timeMapping.target.end.isNumeric
            {
                box.end = segment.timeMapping.target.end
            }
            done.signal()
        }
        done.wait()
        return box.end
    }

    /// Appends once the input is ready; nil on success, else why not.
    private static func append(
        _ buffer: CMSampleBuffer, to input: AVAssetWriterInput, writer: AVAssetWriter
    ) -> String? {
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else {
                return writer.error?.localizedDescription ?? "the writer stopped"
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard input.append(buffer) else {
            return writer.error?.localizedDescription ?? "an append failed"
        }
        return nil
    }

    /// `frames` frames of zeros at `start`, in `buffer`'s format.
    static func silence(frames: Int, at start: CMTime, like buffer: CMSampleBuffer)
        -> CMSampleBuffer?
    {
        guard frames > 0, let format = CMSampleBufferGetFormatDescription(buffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            asbd.mBytesPerFrame > 0
        else { return nil }
        let length = frames * Int(asbd.mBytesPerFrame)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == kCMBlockBufferNoErr,
            let data = block,
            CMBlockBufferFillDataBytes(
                with: 0, blockBuffer: data, offsetIntoDestination: 0,
                dataLength: length) == kCMBlockBufferNoErr
        else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: format,
            sampleCount: CMItemCount(frames), presentationTimeStamp: start,
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }

    /// The one line a failed or abandoned copy leaves; never "Frame Job: ",
    /// the startup parity check's prefix.
    private static func log(_ source: URL, _ why: String) {
        NSLog("AudioRateCopy: no 48 kHz copy of %@ (%@); its own audio is read", source.path, why)
    }
}

extension CompositionBuilder {
    /// `urls` with every audio-track media whose audio is not 48 kHz, or is
    /// an MP3 with an encoder delay to trim (SY-36, computed once per media),
    /// pointed at its 48 kHz copy (spec §11 SY-23); a media whose copy fails
    /// keeps its own file. Video never reads these, and neither does a reversed
    /// clip (`resolveSource`'s reversed branch), so a media only reversed
    /// clips play is not copied.
    static func audioURLs(
        plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution,
        assets: inout [UInt32: AVURLAsset]
    ) -> [UInt32: URL] {
        var result = urls
        var seen: Set<UInt32> = []
        for planTrack in plan.audioTracks {
            for segment in planTrack.segments
            where !seen.contains(segment.media) && reverse.ready[segment.clip] == nil
                && !reverse.pending.contains(segment.clip)
            {
                seen.insert(segment.media)
                guard let url = urls[segment.media],
                    let track = assetTrack(
                        at: url, key: segment.media, mediaType: .audio, assets: &assets),
                    let signature = audioFormatSignature(of: track),
                    case let trim = MP3Gapless.leadingTrim(of: url, track: track),
                    AudioRateCopy.needsCopy(signature, trim: trim),
                    let copy = AudioRateCopy.copy(of: url, track: track, trim: trim)
                else { continue }
                result[segment.media] = copy
            }
        }
        return result
    }
}
