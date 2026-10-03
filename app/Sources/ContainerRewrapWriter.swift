import AVFoundation
import CoreMedia

/// The copy itself (spec §11 #216-R): `AVAssetWriter` passthrough of a
/// `ReelContainer`'s samples into a QuickTime movie, each frame's bytes read
/// at the offset the core indexed and written unchanged.
///
/// What was measured to make it work: the video's format description carries
/// the core's `vpcC`/`av1C`/`avcC`/`hvcC`; an Opus cookie is OpusHead and
/// each packet carries its own sample count (`mVariableFramesInPacket`, with
/// `mFramesPerPacket` 0), where a fixed 960 mistimes 60 ms packets; an AAC
/// cookie is the core's ES_Descriptor. The video input's `mediaTimeScale` is
/// the described timescale — the grid's numerator when the core snapped the
/// track (without it 30000/1001 lands at 600, off the grid), the raw
/// timescale otherwise (the numerator would merge frames 10 ms apart). It is
/// NEVER set on the audio input, where it raises an Objective-C exception
/// nothing can catch.
///
/// One serial queue per input, as `requestMediaDataWhenReady` requires
/// (feeding both in file order on one thread hung): `ExporterWriter.swift`'s
/// pattern, where each queue owns its own source — here the input's own
/// `FileHandle`, read only on that queue, so two pumps never share a seek.
/// Await-free: the finish is waited for through a semaphore (spec §11 W-8).
enum ContainerRewrapWriter {

    /// Writes the copied samples of `c` into a movie at `partial`. Throws
    /// with nothing left at `partial` by the writer when the write fails;
    /// `stopAfter` ends the copy after that many samples and then throws,
    /// leaving the short movie for the caller to remove; `refuseAudioAt`
    /// declares that audio sample 4096 bytes longer than its data, which
    /// fails the writer a few appends later (the probe's way to fail one).
    /// `progress` is told each appended sample's bytes; its Cancel stops each
    /// pump before its next sample, then the writer is cancelled and the
    /// write throws `.cancelled` (spec §11 #228-P).
    static func write(
        _ c: ReelContainer, _ d: ContainerDescription, from source: URL, to partial: URL,
        stopAfter: Int?, refuseAudioAt: Int? = nil, progress: RewrapProgress? = nil
    ) throws {
        let failed = { (reason: String) in ContainerRewrapError.failed(source, reason: reason) }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        } catch {
            throw failed("the movie could not be started (\(error.localizedDescription))")
        }
        let shared = PumpState(
            stopAfter: stopAfter, refuseAudioAt: refuseAudioAt, progress: progress)
        var pumps: [Pump] = []
        defer { pumps.forEach { try? $0.handle.close() } }
        if let video = d.video, video.samples > 0 {
            let format = try videoFormat(video, failed)
            let input = AVAssetWriterInput(
                mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            if let scale = CMTimeScale(exactly: video.timescale) { input.mediaTimeScale = scale }
            pumps.append(try Pump(
                c, ReelContainer.video, input, format, CMTimeScale(clamping: video.timescale),
                source, label: "video"))
        }
        if let audio = d.audio, audio.samples > 0 {
            let format = try audioFormat(audio, failed)
            let input = AVAssetWriterInput(
                mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            pumps.append(try Pump(
                c, ReelContainer.audio, input, format, CMTimeScale(clamping: audio.timescale),
                source, label: "audio"))
        }
        for pump in pumps {
            pump.input.expectsMediaDataInRealTime = false
            guard writer.canAdd(pump.input) else {
                throw failed("its \(pump.label) cannot be written into a movie")
            }
            writer.add(pump.input)
        }
        guard !pumps.isEmpty else { throw failed("it has nothing to copy") }
        guard writer.startWriting() else {
            throw failed(writer.error?.localizedDescription ?? "the movie could not be started")
        }
        writer.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        for pump in pumps { pump.run(writer, shared, group) }
        // In slices: once the writer has failed it may never ask the other
        // input for more, so that pump would never leave `group`. A failure
        // halts every pump from here instead, and so does a Cancel.
        while group.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            guard shared.failure != nil || writer.status == .failed
                || progress?.isCancelled == true
            else { continue }
            pumps.forEach { $0.halt(group) }
        }
        if progress?.isCancelled == true {
            writer.cancelWriting()
            throw ContainerRewrapError.cancelled(source)
        }
        if writer.status == .failed || (shared.failure != nil && !shared.stopped) {
            writer.cancelWriting()
            throw failed(
                shared.failure ?? writer.error?.localizedDescription
                    ?? "the movie could not be written")
        }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw failed(writer.error?.localizedDescription ?? "the movie could not be finished")
        }
        if let failure = shared.failure { throw failed(failure) }
    }

    // MARK: - Format descriptions

    private static func videoFormat(
        _ v: ContainerDescription.Video, _ failed: (String) -> ContainerRewrapError
    ) throws -> CMFormatDescription {
        var atoms: [String: Any] = [:]
        if let atom = v.atom, let hex = v.atomHex { atoms[atom] = data(hex: hex) }
        let extensions: [String: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: atoms
        ]
        var format: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: ContainerRewrap.fourCharCode(v.fourcc ?? ""),
            width: Int32(clamping: v.width), height: Int32(clamping: v.height),
            extensions: extensions as CFDictionary, formatDescriptionOut: &format)
        guard status == noErr, let format else {
            throw failed("its video could not be described (\(status))")
        }
        return format
    }

    private static func audioFormat(
        _ a: ContainerDescription.Audio, _ failed: (String) -> ContainerRewrapError
    ) throws -> CMFormatDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = a.sampleRate
        asbd.mFormatID = a.fourcc == "opus" ? kAudioFormatOpus : kAudioFormatMPEG4AAC
        asbd.mChannelsPerFrame = UInt32(clamping: a.channels)
        asbd.mFramesPerPacket = UInt32(clamping: a.framesPerPacket)
        let cookie = data(hex: a.cookieHex)
        var format: CMFormatDescription?
        let status = cookie.withUnsafeBytes { raw in
            CMAudioFormatDescriptionCreate(
                allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                magicCookieSize: raw.count, magicCookie: raw.baseAddress, extensions: nil,
                formatDescriptionOut: &format)
        }
        guard status == noErr, let format else {
            throw failed("its sound could not be described (\(status))")
        }
        return format
    }

    /// Bytes from lowercase hex, two digits a byte.
    static func data(hex: String) -> Data {
        var out = Data()
        var digits = hex.utf8.makeIterator()
        while let high = digits.next(), let low = digits.next() {
            let value = { (c: UInt8) -> UInt8 in c >= 97 ? c - 87 : (c >= 65 ? c - 55 : c - 48) }
            out.append(value(high) << 4 | value(low))
        }
        return out
    }
}

/// What both pumps share: the first failure, the count `stopAfter` reads,
/// and the copy's progress and Cancel.
private final class PumpState {
    private let lock = NSLock()
    private var failureText: String?
    private var appended = 0
    private var stoppedByLimit = false
    let stopAfter: Int?
    let refuseAudioAt: Int?
    let progress: RewrapProgress?

    init(stopAfter: Int?, refuseAudioAt: Int?, progress: RewrapProgress?) {
        self.stopAfter = stopAfter
        self.refuseAudioAt = refuseAudioAt
        self.progress = progress
    }

    var failure: String? {
        lock.lock()
        defer { lock.unlock() }
        return failureText
    }

    /// Whether the failure is `stopAfter`'s rather than the write's.
    var stopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stoppedByLimit
    }

    func fail(_ reason: String) {
        lock.lock()
        defer { lock.unlock() }
        if failureText == nil { failureText = reason }
    }

    /// Counts one appended sample; false once the copy should stop.
    func count() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        appended += 1
        guard let limit = stopAfter, appended >= limit else { return true }
        if failureText == nil {
            failureText = "it was stopped after \(limit) samples"
            stoppedByLimit = true
        }
        return false
    }
}

/// One input's pump: its serial queue, its own `FileHandle` and its place in
/// the track.
private final class Pump {
    let input: AVAssetWriterInput
    let handle: FileHandle
    let label: String
    private let container: ReelContainer
    private let track: UInt32
    private let format: CMFormatDescription
    private let timescale: CMTimeScale
    private let queue: DispatchQueue
    private let total: Int
    private var index = 0
    private var finished = false

    init(
        _ container: ReelContainer, _ track: UInt32, _ input: AVAssetWriterInput,
        _ format: CMFormatDescription, _ timescale: CMTimeScale, _ source: URL, label: String
    ) throws {
        do {
            handle = try FileHandle(forReadingFrom: source)
        } catch {
            throw ContainerRewrapError.unreadable(source, reason: error.localizedDescription)
        }
        self.container = container
        self.track = track
        self.input = input
        self.format = format
        self.timescale = timescale
        self.label = label
        total = container.count(track)
        queue = DispatchQueue(
            label: "com.kgalligan.reelcut.rewrap.\(label)", qos: .userInitiated)
    }

    /// Feeds the input until the track is copied, a sample fails, the
    /// other pump fails, the copy is cancelled or `stopAfter` is reached;
    /// leaves `group` once.
    func run(_ writer: AVAssetWriter, _ shared: PumpState, _ group: DispatchGroup) {
        group.enter()
        input.requestMediaDataWhenReady(on: queue) { [weak self, weak writer] in
            guard let self else { return }
            while self.input.isReadyForMoreMediaData {
                guard !self.finished else { return }
                guard shared.failure == nil, shared.progress?.isCancelled != true,
                    self.index < self.total
                else {
                    self.stop(group)
                    return
                }
                do {
                    let refused = self.track == ReelContainer.audio
                        && self.index == shared.refuseAudioAt
                    let (buffer, size) = try self.sampleBuffer(self.index, refused: refused)
                    guard self.input.append(buffer) else {
                        shared.fail(writer?.error?.localizedDescription ?? "a sample was refused")
                        self.stop(group)
                        return
                    }
                    shared.progress?.add(bytes: UInt64(size))
                } catch {
                    shared.fail((error as? PumpFailure)?.description ?? error.localizedDescription)
                    self.stop(group)
                    return
                }
                self.index += 1
                if !shared.count() {
                    self.stop(group)
                    return
                }
            }
        }
    }

    /// Stops the pump from outside its queue, waiting out a block in flight.
    func halt(_ group: DispatchGroup) { queue.sync { stop(group) } }

    /// Marks the input finished and leaves `group`, once; on `queue` only.
    private func stop(_ group: DispatchGroup) {
        guard !finished else { return }
        finished = true
        input.markAsFinished()
        group.leave()
    }

    /// Sample `i` of the track as a ready buffer of its own bytes, and their
    /// count; `refused` declares an audio packet longer than its bytes.
    private func sampleBuffer(_ i: Int, refused: Bool) throws -> (CMSampleBuffer, UInt32) {
        guard let s = container.sample(track, at: i) else { throw PumpFailure.noSample(i) }
        try handle.seek(toOffset: s.offset)
        guard let bytes = try handle.read(upToCount: Int(s.size)), bytes.count == Int(s.size)
        else { throw PumpFailure.shortRead(s.offset) }
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes.count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw PumpFailure.status(status) }
        status = bytes.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: raw.count)
        }
        guard status == noErr else { throw PumpFailure.status(status) }
        var buffer: CMSampleBuffer?
        if track == ReelContainer.video {
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: s.duration, timescale: timescale),
                presentationTimeStamp: CMTime(value: s.pts, timescale: timescale),
                decodeTimeStamp: CMTime(value: s.dts, timescale: timescale))
            var size = bytes.count
            status = CMSampleBufferCreateReady(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                sampleSizeArray: &size, sampleBufferOut: &buffer)
        } else {
            var packet = AudioStreamPacketDescription(
                mStartOffset: 0, mVariableFramesInPacket: s.frames,
                mDataByteSize: UInt32(bytes.count) + (refused ? 4096 : 0))
            status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                presentationTimeStamp: CMTime(value: s.pts, timescale: timescale),
                packetDescriptions: &packet, sampleBufferOut: &buffer)
        }
        guard status == noErr, let buffer else { throw PumpFailure.status(status) }
        if !s.sync,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                buffer, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        {
            let first = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                first, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return (buffer, s.size)
    }
}

/// Why a pump could not make a sample, in the failure's own words.
private enum PumpFailure: Error, CustomStringConvertible {
    case noSample(Int)
    case shortRead(UInt64)
    case status(OSStatus)

    var description: String {
        switch self {
        case .noSample(let i): return "its index has no sample \(i)"
        case .shortRead(let offset): return "the file ended inside the frame at byte \(offset)"
        case .status(let status): return "a sample could not be made (\(status))"
        }
    }
}
