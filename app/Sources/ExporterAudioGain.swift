import Accelerate
import AVFoundation

/// The loudness normalisation's gain, applied where an export's samples
/// exist: float mix in, 16-bit LPCM out (spec §11 #86).
///
/// **One read, one quantisation.** A normalised export reads the composed
/// mix as 32-bit float through `floatMixSettings`, the very dictionary the
/// measurement pass reads (`ExporterLoudness`), so the gain is applied to
/// the signal that was measured, overshoot and all. Each buffer is
/// multiplied, clipped to the 16-bit range and rounded ONCE into a new
/// buffer in the format the encoders have always been handed
/// (`ExportWriter.decodedAudioSettings`' shape). Before #86 the write pass
/// decoded to Int16 first, which saturated a mix past full scale before the
/// gain could turn it down and rounded every sample twice.
///
/// **An un-normalised export never meets this class.** `ExportWriter` builds
/// one only for a gain that is not 1, and otherwise reads the Int16 decode
/// it always read, so those files keep their bytes.
///
/// **Rounding.** `vDSP_vfixr16` rounds to nearest, which does not bias quiet
/// material toward zero the way truncation would. The clip comes first
/// because `vDSP_vfixr16` wraps rather than saturates: an over-range sample
/// would come back as its own opposite, a click rather than a clip. The
/// true-peak ceiling (≤ 0 dBTP) keeps a gained mix inside full scale, so in
/// practice the clip never fires.
///
/// The export's audio pump queue only: the scratch buffer and the cached
/// format are this object's own state.
final class ExportAudioGain {

    /// What a gained export reads: 48 kHz, 2 channels, 32-bit float,
    /// little-endian, interleaved. The measurement reads it too, which is
    /// what makes "the gain is applied to what was measured" true by
    /// construction.
    static let floatMixSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// The depth handed to the encoder. Its one spelling: #86's part 2
    /// (24-bit WAV/AIFF) is not decided, and this is where it would start.
    private static let outputBits = 16

    /// The linear multiplier, never 1 (`ExportWriter.normalizeAudio`).
    let linearGain: Float

    private var scratch: UnsafeMutablePointer<Float>?
    private var scratchCount = 0
    private var inputFormat: CMFormatDescription?
    private var outputFormat: CMAudioFormatDescription?

    init(linearGain: Float) {
        self.linearGain = linearGain
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportAudioGain does not support NSCoder")
    }

    deinit { scratch?.deallocate() }

    /// A float LPCM buffer in, a NEW interleaved 16-bit signed little-endian
    /// packed buffer out: the same frame count, the same presentation time,
    /// the input's channel layout, its attachments propagated. nil on any
    /// malformed input or CoreMedia failure, which the caller reports as a
    /// failed write rather than appending ungained audio.
    ///
    /// The floats are copied out with `CMBlockBufferCopyDataBytes` because a
    /// `CMBlockBuffer` may be several non-contiguous chunks, and
    /// `CMBlockBufferGetDataPointer` on the first one silently truncates
    /// (the trap `MediaImporter.peaks` records). The output block is this
    /// method's own, one contiguous allocation.
    func apply(to sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
            let input = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            input.mFormatID == kAudioFormatLinearPCM,
            input.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            input.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
            input.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
            input.mBitsPerChannel == 32, input.mChannelsPerFrame > 0,
            let block = CMSampleBufferGetDataBuffer(sample),
            let output = outputFormat(for: format, input: input)
        else { return nil }
        let frames = CMSampleBufferGetNumSamples(sample)
        let count = frames * Int(input.mChannelsPerFrame)
        let inBytes = count * MemoryLayout<Float>.size
        guard frames > 0, CMBlockBufferGetDataLength(block) == inBytes,
            let floats = scratch(ofAtLeast: count),
            CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: inBytes, destination: floats)
                == kCMBlockBufferNoErr
        else { return nil }

        let outBytes = count * MemoryLayout<Int16>.size
        var outBlock: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: outBytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: outBytes, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &outBlock) == kCMBlockBufferNoErr,
            let outBlock = outBlock
        else { return nil }
        var contiguous = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            outBlock, atOffset: 0, lengthAtOffsetOut: &contiguous, totalLengthOut: nil,
            dataPointerOut: &pointer) == kCMBlockBufferNoErr,
            contiguous == outBytes, let pointer = pointer
        else { return nil }

        let n = vDSP_Length(count)
        var scale = linearGain * 32768
        var low = Float(Int16.min)
        var high = Float(Int16.max)
        vDSP_vsmul(floats, 1, &scale, floats, 1, n)
        vDSP_vclip(floats, 1, &low, &high, floats, 1, n)
        pointer.withMemoryRebound(to: Int16.self, capacity: count) {
            vDSP_vfixr16(floats, 1, $0, 1, n)
        }

        var gained: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: outBlock, formatDescription: output,
            sampleCount: frames,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
            packetDescriptions: nil, sampleBufferOut: &gained) == noErr,
            let gained = gained
        else { return nil }
        CMPropagateAttachments(sample, destination: gained)
        return gained
    }

    /// The 16-bit description for `format`'s rate and channels, with its
    /// channel layout. Rebuilt only when the input's format changes.
    private func outputFormat(
        for format: CMFormatDescription, input: AudioStreamBasicDescription
    ) -> CMAudioFormatDescription? {
        if let cached = outputFormat, let previous = inputFormat,
            CMFormatDescriptionEqual(previous, otherFormatDescription: format)
        {
            return cached
        }
        let bytesPerFrame = UInt32(Self.outputBits / 8) * input.mChannelsPerFrame
        var description = AudioStreamBasicDescription(
            mSampleRate: input.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: input.mChannelsPerFrame, mBitsPerChannel: UInt32(Self.outputBits),
            mReserved: 0)
        var layoutSize = 0
        let layout = CMAudioFormatDescriptionGetChannelLayout(format, sizeOut: &layoutSize)
        var built: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: layout == nil ? 0 : layoutSize, layout: layout,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &built) == noErr,
            let built = built
        else { return nil }
        inputFormat = format
        outputFormat = built
        return built
    }

    private func scratch(ofAtLeast count: Int) -> UnsafeMutablePointer<Float>? {
        if scratchCount < count {
            scratch?.deallocate()
            scratch = .allocate(capacity: count)
            scratchCount = count
        }
        return scratch
    }
}
