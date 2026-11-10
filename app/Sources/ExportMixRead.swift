import AVFoundation
import Accelerate

/// The export's float read of the mix (spec §11 AU-152): one output, or the
/// tracks' sub-mixes read in lockstep, each through its track's compressor and
/// limiter, summed before the master.
///
/// **One output when no track asks.** When no timeline track in the read (a
/// stem's `audioSelection` honoured) has a compressor or a limiter, the read is
/// `ExportWriter.audioReadOutput(built)` and `next()` is its
/// `copyNextSampleBuffer()` — the bytes every export read before part 2b.
///
/// **Otherwise one output per track with dynamics, and one for the rest**, all
/// on the one reader, each over only its own composition tracks' input
/// parameters, so each tap sits in exactly one output (S3 E9). A track's
/// sub-mix is its post-fader sound: the taps, the envelope and the track's pan
/// already ran inside the mix output, so the stage after it is post-fader by
/// construction (AU-151). Per group, each buffer is placed by its stamp from
/// `origin` at 48 kHz (`ExportAudioMaster`'s rule: a hole is zeros, an overlap
/// cuts the covered head), run through the group's stage as it arrives, the
/// stage's latency dropped at the head and flushed with zeros at the group's
/// end, so group frame k is timeline frame k. `next()` reads from the live
/// group with the least buffered — an `AVAssetReader` with several outputs
/// has to be read in step — counts an ended group as zeros, and hands back up
/// to 4,096 summed frames stamped `origin + frame` until every group is
/// drained, in `floatMixSettings`' format, which is what the master and the
/// measurement take.
///
/// The export's audio pump queue (or the build queue's measurement) only.
final class ExportMixRead {

    /// The most frames `next()` sums at once.
    static let blockFrames = 4096
    private static let channels = 2
    private static let sampleRate = 48_000

    private let origin: CMTime
    private let single: AVAssetReaderAudioMixOutput?
    private let groups: [Group]
    private weak var reader: AVAssetReader?
    private var emitted = 0
    private var sum: [Float] = []
    private var format: CMAudioFormatDescription?

    /// Whether the read is sub-mixed (some track in it has dynamics).
    var isSubMixed: Bool { single == nil }

    init(_ built: BuiltComposition, origin: CMTime) {
        self.origin = origin
        let read = built.composition.tracks(withMediaType: .audio).map(\.trackID).filter {
            built.audioSelection?.contains($0) ?? true
        }
        var owned: [UInt32: Set<CMPersistentTrackID>] = [:]
        var rest: Set<CMPersistentTrackID> = []
        for id in read {
            if let owner = built.audioOwners[id], built.trackDynamics[owner] != nil {
                owned[owner, default: []].insert(id)
            } else {
                rest.insert(id)
            }
        }
        guard !owned.isEmpty else {
            single = ExportWriter.audioReadOutput(built)
            groups = []
            return
        }
        single = nil
        var groups = owned.keys.sorted().map { owner in
            Group(
                output: ExportWriter.audioReadOutput(built, only: owned[owner]),
                settings: built.trackDynamics[owner])
        }
        if !rest.isEmpty {
            groups.append(Group(output: ExportWriter.audioReadOutput(built, only: rest), settings: nil))
        }
        self.groups = groups
    }

    /// Adds every output to `reader`; false when it refuses one (there is no
    /// 16-bit fallback, the master and the meter wanting float).
    func add(to reader: AVAssetReader) -> Bool {
        let outputs = single.map { [$0] } ?? groups.map(\.output)
        guard outputs.allSatisfy({ reader.canAdd($0) }) else { return false }
        outputs.forEach { reader.add($0) }
        self.reader = reader
        return true
    }

    /// The next buffer of the mix, nil once it is all read or the read failed
    /// (the caller asks the reader which). Throws on a buffer it cannot read.
    func next() throws -> CMSampleBuffer? {
        if let single { return single.copyNextSampleBuffer() }
        while true {
            if reader?.status == .failed { return nil }
            let live = groups.filter { !$0.ended }
            if let starved = live.min(by: { $0.available < $1.available }),
                starved.available < Self.blockFrames
            {
                try starved.pull(origin: origin)
                continue
            }
            // The last drain is capped too: a group can end holding up to a
            // block less one frame plus its stage's flush (#414).
            let ready = live.isEmpty
                ? min(groups.map(\.available).max() ?? 0, Self.blockFrames)
                : Self.blockFrames
            guard ready > 0 else { return nil }
            return try emit(ready)
        }
    }

    /// `frames` summed frames off every group's head, an ended group's
    /// missing frames as zeros, stamped at the stream's next frame.
    private func emit(_ frames: Int) throws -> CMSampleBuffer {
        let count = frames * Self.channels
        if sum.count != count { sum = [Float](repeating: 0, count: count) }
        sum.withUnsafeMutableBufferPointer { out in
            guard let base = out.baseAddress else { return }
            base.update(repeating: 0, count: count)
            for group in groups { group.take(frames, into: base) }
        }
        let time = CMTimeAdd(
            origin, CMTime(value: CMTimeValue(emitted), timescale: CMTimeScale(Self.sampleRate)))
        emitted += frames
        return try sample(frames: frames, at: time)
    }

    /// `sum` as a float stereo interleaved buffer, `floatMixSettings`' format.
    private func sample(frames: Int, at time: CMTime) throws -> CMSampleBuffer {
        let length = frames * Self.channels * MemoryLayout<Float>.size
        var created: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &created) == kCMBlockBufferNoErr,
            let block = created,
            sum.withUnsafeBytes({ raw in
                guard let base = raw.baseAddress else { return false }
                return CMBlockBufferReplaceDataBytes(
                    with: base, blockBuffer: block, offsetIntoDestination: 0,
                    dataLength: length) == kCMBlockBufferNoErr
            }),
            let format = floatFormat()
        else { throw Self.failure }
        var made: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, presentationTimeStamp: time, packetDescriptions: nil,
            sampleBufferOut: &made) == noErr,
            let made
        else { throw Self.failure }
        return made
    }

    /// The packed float32 stereo description, made once.
    private func floatFormat() -> CMAudioFormatDescription? {
        if let format { return format }
        let bytesPerFrame = UInt32(MemoryLayout<Float>.size * Self.channels)
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(Self.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(Self.channels), mBitsPerChannel: 32, mReserved: 0)
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

    static var failure: any Error {
        Exporter.ExportError.failed("The audio mix could not be read for export.")
    }

    // MARK: - One group

    /// One sub-mix: its output, its stage (nil for the tracks without
    /// dynamics), and its processed frames waiting to be summed.
    final class Group {
        let output: AVAssetReaderAudioMixOutput
        private let settings: AudioTrackDynamicsSettings?
        private let stage: AudioTrackDynamicsStage?
        private let left: UnsafeMutablePointer<Float>
        private let right: UnsafeMutablePointer<Float>
        private let planes: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>
        private var input: [Float] = []
        /// Processed interleaved frames from `head` on.
        private var pending: [Float] = []
        private var head = 0
        /// The next timeline frame the stage is fed.
        private var position = 0
        /// Stage output frames still to drop: its latency.
        private var toDrop: Int
        private(set) var ended = false

        init(output: AVAssetReaderAudioMixOutput, settings: AudioTrackDynamicsSettings?) {
            self.output = output
            self.settings = settings
            let stage = settings.map { _ in
                AudioTrackDynamicsStage(
                    channelCount: ExportMixRead.channels,
                    sampleRate: Double(ExportMixRead.sampleRate),
                    maxFrames: ExportMixRead.blockFrames)
            }
            self.stage = stage
            toDrop = Group.latency(stage, settings)
            left = .allocate(capacity: ExportMixRead.blockFrames)
            right = .allocate(capacity: ExportMixRead.blockFrames)
            planes = .allocate(capacity: ExportMixRead.channels)
            planes[0] = left
            planes[1] = right
        }

        deinit {
            left.deallocate()
            right.deallocate()
            planes.deallocate()
        }

        /// The stage's latency under its settings, 0 for the plain group.
        private static func latency(
            _ stage: AudioTrackDynamicsStage?, _ settings: AudioTrackDynamicsSettings?
        ) -> Int {
            guard let stage, let settings else { return 0 }
            return stage.latency(settings)
        }

        /// Frames processed and not yet taken.
        var available: Int { (pending.count - head) / ExportMixRead.channels }

        /// One buffer from the output, placed and processed; at the output's
        /// end, the stage's latency flushed with zeros and the group ended.
        func pull(origin: CMTime) throws {
            guard let sample = output.copyNextSampleBuffer() else {
                let tail = Group.latency(stage, settings)
                if tail > 0 { feedZeros(tail) }
                ended = true
                return
            }
            let frames = CMSampleBufferGetNumSamples(sample)
            let stamp = CMSampleBufferGetPresentationTimeStamp(sample)
            guard frames > 0, stamp.isNumeric else { return }
            let count = frames * ExportMixRead.channels
            let bytes = count * MemoryLayout<Float>.size
            guard let description = CMSampleBufferGetFormatDescription(sample),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                asbd.mBitsPerChannel == 32,
                asbd.mChannelsPerFrame == UInt32(ExportMixRead.channels),
                let block = CMSampleBufferGetDataBuffer(sample),
                CMBlockBufferGetDataLength(block) == bytes
            else { throw ExportMixRead.failure }
            if input.count < count { input = [Float](repeating: 0, count: count) }
            let copied = input.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: bytes, destination: base)
            }
            guard copied == kCMBlockBufferNoErr else { throw ExportMixRead.failure }
            let frame = Int(
                CMTimeConvertScale(
                    stamp - origin, timescale: CMTimeScale(ExportMixRead.sampleRate),
                    method: .roundHalfAwayFromZero
                ).value)
            var skip = 0
            if frame > position {
                feedZeros(frame - position)
            } else if frame < position {
                skip = position - frame
            }
            guard skip < frames else { return }
            input.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                feed(base + skip * ExportMixRead.channels, frames: frames - skip)
            }
        }

        /// `frames` frames off the head, added into `out`; zeros past what is
        /// there.
        func take(_ frames: Int, into out: UnsafeMutablePointer<Float>) {
            let have = min(frames, available) * ExportMixRead.channels
            guard have > 0 else { return }
            pending.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                vDSP_vadd(base + head, 1, out, 1, out, 1, vDSP_Length(have))
            }
            head += have
            if head == pending.count {
                pending.removeAll(keepingCapacity: true)
                head = 0
            } else if head >= ExportMixRead.blockFrames * ExportMixRead.channels * 4 {
                pending.removeFirst(head)
                head = 0
            }
        }

        private func feed(_ samples: UnsafePointer<Float>, frames: Int) {
            var one: Float = 1
            var offset = 0
            while offset < frames {
                let length = min(ExportMixRead.blockFrames, frames - offset)
                let at = samples + offset * ExportMixRead.channels
                vDSP_vsmul(at, 2, &one, left, 1, vDSP_Length(length))
                vDSP_vsmul(at + 1, 2, &one, right, 1, vDSP_Length(length))
                run(frames: length)
                offset += length
            }
            position += frames
        }

        private func feedZeros(_ frames: Int) {
            var offset = 0
            while offset < frames {
                let length = min(ExportMixRead.blockFrames, frames - offset)
                left.update(repeating: 0, count: length)
                right.update(repeating: 0, count: length)
                run(frames: length)
                offset += length
            }
            position += frames
        }

        /// The stage over `left` and `right`, interleaved onto `pending`
        /// after the latency's frames are dropped.
        private func run(frames: Int) {
            if let stage, let settings {
                stage.process(planes, count: ExportMixRead.channels, frames: frames, settings: settings)
            }
            let drop = min(toDrop, frames)
            toDrop -= drop
            let keep = frames - drop
            guard keep > 0 else { return }
            let base = pending.count
            pending.append(contentsOf: repeatElement(0, count: keep * ExportMixRead.channels))
            var one: Float = 1
            pending.withUnsafeMutableBufferPointer { pointer in
                guard let out = pointer.baseAddress else { return }
                vDSP_vsmul(left + drop, 1, &one, out + base, 2, vDSP_Length(keep))
                vDSP_vsmul(right + drop, 1, &one, out + base + 1, 2, vDSP_Length(keep))
            }
        }
    }
}
