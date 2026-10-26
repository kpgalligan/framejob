import AVFoundation

/// Where an export's sound ends: exactly round(range × 48 000) frames, cut at
/// the range's end and made up with silence after a read that ends early
/// (spec §11 #337).
///
/// **Why the read is not trusted to end on the range.** An
/// `AVAssetReaderAudioMixOutput` over a time-scaled segment hands back whole
/// buffers past `reader.timeRange`'s end (a ×2 clip's `prores_422` ran up to
/// 4 095 frames over, by a different amount run to run), and a keep-pitch
/// read or a composition whose audio tracks end early stops short of it. So
/// the writer counts what it has handed on, in order — never from the
/// stamps — keeps only the target's frames of the buffer that crosses it,
/// drops every buffer after, and appends zeros up to the target once the
/// read is dry. A read that already ended exactly on the target passes
/// through untouched, so its bytes are what they were.
///
/// One instance per export, used only on `ExportWriter`'s audio queue.
final class ExportAudioEnd {

    static let sampleRate = 48_000
    private static let channels = 2
    private static let bytesPerFrame = channels * MemoryLayout<Int16>.size
    /// The longest silence one pad buffer carries: one second.
    private static let padChunk = sampleRate

    /// ⌊(ticks · 48 000 + perSecond/2) / ReelTime.perSecond⌋, integers only
    /// (round half up): the frames a range of `ticks` holds.
    static func frames(ofTicks ticks: Ticks) -> Int {
        let perSecond = ReelTime.perSecond
        return Int((max(0, ticks) * Ticks(sampleRate) + perSecond / 2) / perSecond)
    }

    let target: Int
    /// Frames handed on so far, counted IN ORDER, not from presentation stamps.
    private(set) var written = 0
    /// The silence still to append once the read is dry; nil until then.
    private var pending: [CMSampleBuffer]?

    init(range: CMTimeRange) {
        target = Self.frames(ofTicks: CompositionBuilder.ticks(range.duration))
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportAudioEnd does not support NSCoder")
    }

    var isComplete: Bool { written >= target }

    /// True once the read has run dry and the silence is being appended.
    var isPadding: Bool { pending != nil }

    /// `sample` (already rebased) unchanged when it ends at or before the
    /// target; its first (target − written) frames when it crosses it; nil
    /// past it — and nil, too, for a crossing buffer CoreMedia will not cut,
    /// whose frames the padding then makes up as silence.
    func fit(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard !isComplete else { return nil }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard written + frames > target else {
            written += frames
            return sample
        }
        let keep = target - written
        var cut: CMSampleBuffer?
        guard CMSampleBufferCopySampleBufferForRange(
            allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleRange: CFRange(location: 0, length: keep), sampleBufferOut: &cut) == noErr,
            let cut = cut
        else { return nil }
        written = target
        return cut
    }

    /// Zero buffers from `written` to `target` in the shape of
    /// `ExportWriter.decodedAudioSettings` (48 kHz, 2 channels, signed 16-bit
    /// little-endian, interleaved), at most one second each, stamped
    /// contiguously from written / 48 000; sets `written` to `target`. Empty
    /// when none is owed, or when CoreMedia refuses a buffer.
    func padding() -> [CMSampleBuffer] {
        guard written < target, let format = Self.padFormat() else { return [] }
        var buffers: [CMSampleBuffer] = []
        var at = written
        while at < target {
            let count = min(Self.padChunk, target - at)
            guard let buffer = Self.silence(
                frames: count, at: CMTime(value: CMTimeValue(at), timescale: CMTimeScale(Self.sampleRate)),
                format: format)
            else { return [] }
            buffers.append(buffer)
            at += count
        }
        written = target
        return buffers
    }

    /// Appends the silence `padding` owes while `input` has room: true once
    /// all of it is in, false when the input refused a buffer, nil when the
    /// input is full — call again when it asks for more.
    func pad(_ input: AVAssetWriterInput) -> Bool? {
        if pending == nil { pending = padding() }
        while let next = pending?.first {
            guard input.isReadyForMoreMediaData else { return nil }
            guard input.append(next) else { return false }
            pending?.removeFirst()
        }
        return true
    }

    // MARK: - The silence

    private static func padFormat() -> CMAudioFormatDescription? {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame), mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16, mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr
        else { return nil }
        return format
    }

    private static func silence(
        frames: Int, at time: CMTime, format: CMAudioFormatDescription
    ) -> CMSampleBuffer? {
        let bytes = frames * bytesPerFrame
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == kCMBlockBufferNoErr,
            let block = block,
            CMBlockBufferFillDataBytes(
                with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
                == kCMBlockBufferNoErr
        else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, presentationTimeStamp: time, packetDescriptions: nil,
            sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}
