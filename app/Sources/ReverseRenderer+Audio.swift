import AVFoundation

extension ReverseRenderer {
    /// One audio sample buffer's bytes, appended to the slice's run.
    static func appendAudioBytes(of sample: CMSampleBuffer, to bytes: inout [UInt8]) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return }
        var copied = [UInt8](repeating: 0, count: length)
        let status = copied.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: length, destination: base)
        }
        guard status == kCMBlockBufferNoErr else { return }
        bytes.append(contentsOf: copied)
    }

    // MARK: - Audio

    /// What comes out of the reader and goes into the file: 16-bit
    /// interleaved LPCM at 48 kHz stereo — `ExporterWriter.decodedAudioSettings`
    /// again, so a reversed clip mixes exactly like a forward one, and LPCM in
    /// rather than AAC so an intermediate costs no generation of its own.
    static let audioSampleRate = 48000
    static let audioChannels = 2
    static let audioBytesPerFrame = 4

    static let decodedAudioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: audioSampleRate,
        AVNumberOfChannelsKey: audioChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    static let audioSettings: [String: Any] = decodedAudioSettings

    /// The description every block written here carries: 48 kHz stereo,
    /// 16-bit signed, packed, little-endian — `decodedAudioSettings` spelled
    /// as an `AudioStreamBasicDescription`.
    ///
    /// Built rather than taken off the first sample the reader hands back,
    /// because a slice may legitimately contain no sound at all and still have
    /// to write silence into it (see `walkBackwards`). The two descriptions
    /// are the same one either way: the reader was ASKED for this format.
    static let audioFormat: CMFormatDescription? = {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(audioSampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(audioBytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(audioBytesPerFrame),
            mChannelsPerFrame: UInt32(audioChannels),
            mBitsPerChannel: 16,
            mReserved: 0)
        var format: CMFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr
        else { return nil }
        return format
    }()

    /// A time as a whole number of 48 kHz frames — the unit the audio input's
    /// stamps are counted in, so a slice boundary is an integer and not a
    /// rounding.
    static func audioFrames(in time: CMTime) -> Int64 {
        let scaled = CMTimeConvertScale(
            time, timescale: CMTimeScale(audioSampleRate), method: .roundHalfAwayFromZero)
        return scaled.isNumeric ? max(0, scaled.value) : 0
    }

    /// One slice's sound as writer-sized blocks, in output order, padded with
    /// silence out to `endFrame` — the frame the picture has reached by the
    /// end of this slice.
    ///
    /// The padding is what keeps the audio input fed through a stretch of the
    /// source that has none, and the blocks are what keep it from running away
    /// from the picture; `walkBackwards` explains why both matter. `written`
    /// is the running frame count, so the blocks are contiguous across slices
    /// and no boundary can round into a click.
    static func audioBlocks(
        _ bytes: [UInt8], format: CMFormatDescription, from written: inout Int64,
        covering endFrame: Int64
    ) -> [CMSampleBuffer] {
        let width = audioBytesPerFrame
        var run = reversedFrames(bytes)
        let reached = written + Int64(run.count / width)
        if reached < endFrame {
            run.append(
                contentsOf: [UInt8](repeating: 0, count: Int(endFrame - reached) * width))
        }
        // A quarter of a second: far inside the lead an `AVAssetWriter`
        // tolerates, far longer than the per-append cost is worth paying more
        // often.
        let blockFrames = audioSampleRate / 4
        var blocks: [CMSampleBuffer] = []
        var offset = 0
        while offset < run.count {
            let frames = min(blockFrames, (run.count - offset) / width)
            guard frames > 0 else { break }
            let block = Array(run[offset..<(offset + frames * width)])
            guard let sample = audioSample(
                block, format: format,
                at: CMTime(value: written, timescale: CMTimeScale(audioSampleRate)),
                frames: frames)
            else { break }
            blocks.append(sample)
            written += Int64(frames)
            offset += frames * width
        }
        return blocks
    }

    /// The slice's audio with its FRAMES reversed — the channels inside one
    /// frame keep their order, or the left and right would swap.
    static func reversedFrames(_ bytes: [UInt8]) -> [UInt8] {
        let width = audioBytesPerFrame
        let frames = bytes.count / width
        var out = [UInt8](repeating: 0, count: frames * width)
        for frame in 0..<frames {
            let from = (frames - 1 - frame) * width
            let to = frame * width
            for byte in 0..<width { out[to + byte] = bytes[from + byte] }
        }
        return out
    }

    /// One block of reversed LPCM as a sample buffer. Constant bytes per
    /// frame, so one timing entry and one size entry describe the lot —
    /// `ExporterWriter.chapterSample`'s construction with a different payload.
    static func audioSample(
        _ bytes: [UInt8], format: CMFormatDescription, at time: CMTime, frames: Int
    ) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let buffer = block,
            CMBlockBufferReplaceDataBytes(
                with: bytes, blockBuffer: buffer, offsetIntoDestination: 0,
                dataLength: bytes.count) == kCMBlockBufferNoErr
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(audioSampleRate)),
            presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = audioBytesPerFrame
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
            sampleCount: CMItemCount(frames), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}
