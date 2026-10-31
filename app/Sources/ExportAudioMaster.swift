import Accelerate
import AVFoundation

/// The export's master (spec §11 AU-27, AU-29): every buffer of the float mix
/// placed by its stamp, multiplied by the loudness gain, held under the
/// export's true-peak ceiling by `AudioLimiterStage`, and quantised once to
/// 16- or 24-bit packed signed integers — the one place an export's sound is
/// made into the samples its encoder takes.
///
/// **One read, one quantisation.** Every export with sound reads the composed
/// mix as 32-bit float through `floatMixSettings`, the very dictionary the
/// measurement pass reads (`ExporterLoudness`), so the gain is applied to the
/// signal that was measured, overshoot and all, and nothing is saturated by a
/// 16-bit decode before the gain or the limiter can act (#86).
///
/// **The limiter.** `AudioLimiterStage` exactly as the clip limiter runs it
/// (AU-20: the Kaiser and Annex 2 detector, the hold, the box mean, one gain
/// for both channels) at a ceiling of `peak_dbtp`, −1 dBTP when not asked,
/// released over 100 ms. It is always on; a mix under the ceiling passes it
/// with a gain of exactly 1.
///
/// **Its latency is compensated in the file.** The stage delays 158 frames;
/// the stream's first 158 output frames are dropped and `finish()` flushes the
/// last 158 with zeros, so output frame k is input frame k and a mix under
/// the ceiling is written exactly as the float mix rounded.
///
/// **Placed by stamp first** (CX-15 (5)'s rule, `ExportAudioEnd.align`'s
/// arithmetic): each buffer's frame is its stamp from `origin` at 48 kHz,
/// rounded half away from zero; the stream starts at the first buffer's frame;
/// a later buffer that starts past the position has the hole fed to the
/// limiter as zeros, one that starts before it has its covered head cut, and
/// one covered whole contributes nothing. So the output, stamped by count
/// from the first buffer's frame, is stamped at the timeline's frames: a
/// buffer's first sample came from the frame its stamp names.
///
/// **Rounding.** `vDSP_vfixr16` / `vDSP_vfixr32` round to nearest, after a
/// clip, because both wrap rather than saturate. No dither at either depth
/// (AU-29).
///
/// The export's audio pump queue only: every buffer is this object's own.
final class ExportAudioMaster {

    /// What every export reads the mix as: 48 kHz, 2 channels, 32-bit float,
    /// little-endian, interleaved. The measurement reads it too, which is what
    /// makes "the gain is applied to what was measured" true by construction.
    static let floatMixSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// The master's release, fixed (AU-27): the number the gain's model reads.
    static let releaseSeconds = ExportLoudness.masterReleaseSeconds
    /// The most frames the limiter is handed at once.
    static let chunkFrames = 4096

    private static let sampleRate = 48_000
    private static let channels = 2

    /// 16 or 24: the depth handed to the encoder.
    let bits: Int
    /// The ceiling, linear: 10^(dBTP/20).
    let ceiling: Float
    /// The export range's start, the stamp of stream frame 0.
    let origin: CMTime
    /// The loudness gain (`ExportWriter.normalizeAudio`); 1 when not normalised.
    var linearGain: Float = 1

    private let stage: AudioLimiterStage
    private let settings: AudioLimiterSettings
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private let planes: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>
    private var input: [Float] = []
    private var output: [Float] = []
    private var integers: [Int32] = []

    /// The stream's first frame (the first buffer's), nil before one.
    private var firstFrame: Int?
    /// The next frame the limiter is fed.
    private var position = 0
    /// Frames handed on so far, after the latency.
    private var emitted = 0
    /// Limiter output frames still to drop: the latency.
    private var toDrop = AudioLimiterStage.latency
    private var finished = false
    private var format: CMAudioFormatDescription?

    init(bits: Int, ceilingDBTP: Double, origin: CMTime) {
        self.bits = bits == 24 ? 24 : 16
        let dbtp = ceilingDBTP.isFinite ? ceilingDBTP : ExportLoudness.defaultCeiling
        ceiling = Float(pow(10, dbtp / 20))
        self.origin = origin
        stage = AudioLimiterStage(
            channelCount: Self.channels, sampleRate: Double(Self.sampleRate),
            maxFrames: Self.chunkFrames)
        settings = AudioLimiterSettings(ceiling: ceiling, releaseSeconds: Self.releaseSeconds)
        left = .allocate(capacity: Self.chunkFrames)
        right = .allocate(capacity: Self.chunkFrames)
        planes = .allocate(capacity: Self.channels)
        planes[0] = left
        planes[1] = right
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportAudioMaster does not support NSCoder")
    }

    deinit {
        left.deallocate()
        right.deallocate()
        planes.deallocate()
    }

    /// A float stereo buffer in; a NEW packed signed-integer little-endian
    /// buffer of `bits` out, stamped at its first frame's timeline position —
    /// or nil while the stream's head is still inside the latency, for an
    /// empty buffer, for one covered whole, and for one with no numeric stamp
    /// (which the pump skipped before the master existed). Throws on
    /// malformed input or a CoreMedia failure.
    func apply(to sample: CMSampleBuffer) throws -> CMSampleBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
            asbd.mFormatID == kAudioFormatLinearPCM,
            asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
            asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
            asbd.mBitsPerChannel == 32, asbd.mChannelsPerFrame == UInt32(Self.channels)
        else { throw Self.failure("The audio master was handed a sample it cannot read.") }
        let frames = CMSampleBufferGetNumSamples(sample)
        let stamp = CMSampleBufferGetPresentationTimeStamp(sample)
        guard frames > 0, stamp.isNumeric, !finished else { return nil }
        let count = frames * Self.channels
        let bytes = count * MemoryLayout<Float>.size
        guard let block = CMSampleBufferGetDataBuffer(sample),
            CMBlockBufferGetDataLength(block) == bytes
        else { throw Self.failure("The audio master was handed a sample it cannot read.") }
        if input.count < count { input = [Float](repeating: 0, count: count) }
        // `CMBlockBufferCopyDataBytes`, because a block may be several chunks
        // and the first one's pointer silently truncates (`MediaImporter.peaks`).
        let copied = input.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: bytes, destination: base)
        }
        guard copied == kCMBlockBufferNoErr else {
            throw Self.failure("The audio master could not read a sample.")
        }

        let frame = Int(
            CMTimeConvertScale(
                stamp - origin, timescale: CMTimeScale(Self.sampleRate),
                method: .roundHalfAwayFromZero
            ).value)
        let start = firstFrame ?? frame
        if firstFrame == nil {
            firstFrame = frame
            position = frame
        }
        output.removeAll(keepingCapacity: true)
        var skip = 0
        if frame > position {
            feedZeros(frame - position)
            position = frame
        } else if frame < position {
            skip = position - frame
        }
        if skip < frames {
            input.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                feed(base + skip * Self.channels, frames: frames - skip, gain: linearGain)
            }
            position += frames - skip
        }
        return try quantised(at: start)
    }

    /// The last `AudioLimiterStage.latency` frames, flushed with zeros once;
    /// nil when nothing was ever fed, or on a second call.
    func finish() throws -> CMSampleBuffer? {
        guard let start = firstFrame, !finished else { return nil }
        finished = true
        output.removeAll(keepingCapacity: true)
        feedZeros(AudioLimiterStage.latency)
        return try quantised(at: start)
    }

    // MARK: - The limiter

    /// `frames` interleaved stereo frames, × `gain`, through the stage.
    private func feed(_ samples: UnsafePointer<Float>, frames: Int, gain: Float) {
        var gain = gain
        var offset = 0
        while offset < frames {
            let length = min(Self.chunkFrames, frames - offset)
            let at = samples + offset * Self.channels
            vDSP_vsmul(at, 2, &gain, left, 1, vDSP_Length(length))
            vDSP_vsmul(at + 1, 2, &gain, right, 1, vDSP_Length(length))
            run(frames: length)
            offset += length
        }
    }

    private func feedZeros(_ frames: Int) {
        var offset = 0
        while offset < frames {
            let length = min(Self.chunkFrames, frames - offset)
            left.update(repeating: 0, count: length)
            right.update(repeating: 0, count: length)
            run(frames: length)
            offset += length
        }
    }

    /// The stage over `left` and `right`, its output interleaved onto
    /// `output` after the latency's frames are dropped.
    private func run(frames: Int) {
        stage.process(planes, count: Self.channels, frames: frames, settings: settings)
        let drop = min(toDrop, frames)
        toDrop -= drop
        let keep = frames - drop
        guard keep > 0 else { return }
        let base = output.count
        output.append(contentsOf: repeatElement(0, count: keep * Self.channels))
        var one: Float = 1
        output.withUnsafeMutableBufferPointer { pointer in
            guard let out = pointer.baseAddress else { return }
            vDSP_vsmul(left + drop, 1, &one, out + base, 2, vDSP_Length(keep))
            vDSP_vsmul(right + drop, 1, &one, out + base + 1, 2, vDSP_Length(keep))
        }
    }

    // MARK: - The quantiser

    /// `output` rounded to `bits` into a new buffer stamped at stream frame
    /// `start + emitted`; nil when `output` is empty.
    private func quantised(at start: Int) throws -> CMSampleBuffer? {
        let frames = output.count / Self.channels
        guard frames > 0 else { return nil }
        let count = frames * Self.channels
        let width = bits / 8
        let length = count * width
        var created: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &created) == kCMBlockBufferNoErr,
            let block = created
        else { throw Self.failure("The audio master could not make a sample.") }
        var contiguous = 0
        var pointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: &contiguous, totalLengthOut: nil,
            dataPointerOut: &pointer) == kCMBlockBufferNoErr,
            contiguous == length, let pointer
        else { throw Self.failure("The audio master could not make a sample.") }

        let n = vDSP_Length(count)
        if bits == 24 {
            if integers.count < count { integers = [Int32](repeating: 0, count: count) }
            var scale: Float = 8_388_608
            var low: Float = -8_388_608
            var high: Float = 8_388_607
            output.withUnsafeMutableBufferPointer { floats in
                guard let f = floats.baseAddress else { return }
                vDSP_vsmul(f, 1, &scale, f, 1, n)
                vDSP_vclip(f, 1, &low, &high, f, 1, n)
                integers.withUnsafeMutableBufferPointer { ints in
                    guard let i = ints.baseAddress else { return }
                    vDSP_vfixr32(f, 1, i, 1, n)
                }
            }
            pointer.withMemoryRebound(to: UInt8.self, capacity: length) { out in
                for index in 0..<count {
                    let value = UInt32(bitPattern: integers[index])
                    out[3 * index] = UInt8(truncatingIfNeeded: value)
                    out[3 * index + 1] = UInt8(truncatingIfNeeded: value >> 8)
                    out[3 * index + 2] = UInt8(truncatingIfNeeded: value >> 16)
                }
            }
        } else {
            var scale: Float = 32768
            var low = Float(Int16.min)
            var high = Float(Int16.max)
            output.withUnsafeMutableBufferPointer { floats in
                guard let f = floats.baseAddress else { return }
                vDSP_vsmul(f, 1, &scale, f, 1, n)
                vDSP_vclip(f, 1, &low, &high, f, 1, n)
                pointer.withMemoryRebound(to: Int16.self, capacity: count) {
                    vDSP_vfixr16(f, 1, $0, 1, n)
                }
            }
        }

        guard let format = outputFormat() else {
            throw Self.failure("The audio master could not describe its sample.")
        }
        let time = CMTimeAdd(
            origin,
            CMTime(value: CMTimeValue(start + emitted), timescale: CMTimeScale(Self.sampleRate)))
        var made: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, presentationTimeStamp: time, packetDescriptions: nil,
            sampleBufferOut: &made) == noErr,
            let made
        else { throw Self.failure("The audio master could not make a sample.") }
        emitted += frames
        return made
    }

    /// The packed signed-integer stereo description at `bits`, made once.
    private func outputFormat() -> CMAudioFormatDescription? {
        if let format { return format }
        let bytesPerFrame = UInt32(bits / 8 * Self.channels)
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(Self.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(Self.channels), mBitsPerChannel: UInt32(bits), mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        var built: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description,
            layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &built) == noErr
        else { return nil }
        format = built
        return built
    }

    private static func failure(_ message: String) -> any Error {
        Exporter.ExportError.failed(message)
    }
}
