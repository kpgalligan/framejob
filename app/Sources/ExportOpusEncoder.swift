import AVFoundation

/// The `av1_webm` row's sound (spec §11 CX-7, CX-15 (5)): the export's 16-bit interleaved
/// 48 kHz stereo mix (`ExportWriter.decodedAudioSettings`, or `ExportAudioGain`'s output in
/// that shape) encoded to Opus by AudioToolbox's `AVAudioConverter`, in 20 ms packets.
///
/// **A 960-frame FIFO** sits in front of the converter, so it is handed whole packets'
/// worth of frames whatever size the reader's buffers come in; packet k is timed at
/// k × 20 ms. **The pre-skip** is the converter's `primeInfo.leadingFrames` (312 measured),
/// which the WebM's OpusHead and CodecDelay carry. **The end:** `finish()` feeds `preSkip`
/// frames of silence through the FIFO (and zeros to a whole packet), then the end of stream,
/// so the packets cover every frame fed — packets × 960 ≥ pre-skip + frames fed — and the
/// writer cuts the surplus with DiscardPadding.
///
/// One instance per export, used only on the WebM writer's audio queue.
final class ExportOpusEncoder {
    /// The AAC rows' own default (spec §11 CX-15 (5)).
    static let defaultBitRate = 192_000
    static let framesPerPacket = 960
    private static let channels = 2

    let preSkip: Int
    /// Frames handed to the FIFO, silence from `finish` included.
    private(set) var framesFed = 0
    /// Packets the converter has answered.
    private(set) var packetsOut = 0

    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    /// Interleaved samples not yet handed to the converter.
    private var fifo: [Int16] = []
    private var finished = false

    /// A converter at `bitRate` bits per second, snapped to the nearest rate it offers.
    init(bitRate: Int) throws {
        var opus = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(Self.framesPerPacket),
            mBytesPerFrame: 0, mChannelsPerFrame: UInt32(Self.channels), mBitsPerChannel: 0,
            mReserved: 0)
        guard let input = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 48_000,
            channels: AVAudioChannelCount(Self.channels), interleaved: true),
            let output = AVAudioFormat(streamDescription: &opus),
            let converter = AVAudioConverter(from: input, to: output)
        else {
            throw Exporter.ExportError.failed("The Opus encoder could not be started.")
        }
        let offered = (converter.applicableEncodeBitRates ?? []).map(\.intValue)
        if let nearest = offered.min(by: { abs($0 - bitRate) < abs($1 - bitRate) }) {
            converter.bitRate = nearest
        } else {
            converter.bitRate = max(1, bitRate)
        }
        self.converter = converter
        inputFormat = input
        outputFormat = output
        preSkip = Int(converter.primeInfo.leadingFrames)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportOpusEncoder does not support NSCoder")
    }

    /// Feeds `sample`'s frames and answers every packet the converter makes of whole
    /// 960-frame chunks. The frames are counted from the buffer's BYTES (4 a frame), so a
    /// buffer of any length — one cut short at the range's end included — goes through the
    /// FIFO whole. Throws, in a sentence, when its bytes are not a whole number of 16-bit
    /// stereo frames, when they cannot be read, or when the converter fails.
    func encode(_ sample: CMSampleBuffer) throws -> [Data] {
        guard let block = CMSampleBufferGetDataBuffer(sample) else {
            guard CMSampleBufferGetNumSamples(sample) == 0 else {
                throw Exporter.ExportError.failed("A sound buffer could not be read for Opus.")
            }
            return []
        }
        let bytes = CMBlockBufferGetDataLength(block)
        let frameBytes = Self.channels * MemoryLayout<Int16>.size
        guard bytes % frameBytes == 0 else {
            throw Exporter.ExportError.failed(
                "A sound buffer of \(bytes) bytes is not a whole number of 16-bit stereo "
                    + "frames, so it could not be encoded to Opus.")
        }
        let frames = bytes / frameBytes
        guard frames > 0 else { return [] }
        let start = fifo.count
        fifo.append(contentsOf: repeatElement(0, count: frames * Self.channels))
        let copied = fifo.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: bytes,
                destination: base + start * MemoryLayout<Int16>.size)
        }
        guard copied == kCMBlockBufferNoErr else {
            throw Exporter.ExportError.failed("A sound buffer could not be read for Opus.")
        }
        framesFed += frames
        return try drain()
    }

    /// The pre-skip's silence, zeros to a whole packet, then the end of stream: every packet
    /// that yields.
    func finish() throws -> [Data] {
        guard !finished else { return [] }
        finished = true
        fifo.append(contentsOf: repeatElement(0, count: preSkip * Self.channels))
        framesFed += preSkip
        let partial = (fifo.count / Self.channels) % Self.framesPerPacket
        if partial > 0 {
            fifo.append(contentsOf: repeatElement(
                0, count: (Self.framesPerPacket - partial) * Self.channels))
        }
        var packets = try drain()
        while true {
            let (more, ended) = try convert(nil)
            packets += more
            if ended || more.isEmpty { break }
        }
        return packets
    }

    // MARK: - The converter

    /// Hands every whole chunk in the FIFO to the converter.
    private func drain() throws -> [Data] {
        var packets: [Data] = []
        let chunk = Self.framesPerPacket * Self.channels
        while fifo.count >= chunk {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(Self.framesPerPacket)),
                let samples = buffer.int16ChannelData?[0]
            else {
                throw Exporter.ExportError.failed("A sound buffer could not be made for Opus.")
            }
            buffer.frameLength = AVAudioFrameCount(Self.framesPerPacket)
            fifo.withUnsafeBufferPointer { from in
                guard let base = from.baseAddress else { return }
                samples.update(from: base, count: chunk)
            }
            fifo.removeFirst(chunk)
            packets += try convert(buffer).packets
        }
        return packets
    }

    /// One call of the converter with `buffer` as its only input (nil: the end of stream),
    /// answering the packets it wrote and whether the stream has ended.
    private func convert(_ buffer: AVAudioPCMBuffer?) throws -> (packets: [Data], ended: Bool) {
        let size = max(converter.maximumOutputPacketSize, 1_500)
        let out = AVAudioCompressedBuffer(
            format: outputFormat, packetCapacity: 8, maximumPacketSize: size)
        var given = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if let buffer, !given {
                given = true
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = buffer == nil ? .endOfStream : .noDataNow
            return nil
        }
        if status == .error {
            throw Exporter.ExportError.failed(
                "The sound could not be encoded to Opus: "
                    + (error?.localizedDescription ?? "the converter gave no reason"))
        }
        var packets: [Data] = []
        if let descriptions = out.packetDescriptions {
            for i in 0..<Int(out.packetCount) {
                let d = descriptions[i]
                packets.append(Data(
                    bytes: out.data + Int(d.mStartOffset), count: Int(d.mDataByteSize)))
            }
        }
        packetsOut += packets.count
        return (packets, status == .endOfStream)
    }
}
