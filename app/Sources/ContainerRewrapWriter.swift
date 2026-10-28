import AVFoundation
import CoreMedia

/// The copy itself (spec §11 #216-R): `AVAssetWriter` passthrough of a
/// `ReelContainer`'s samples into a QuickTime movie, each frame's bytes read
/// at the offset the core indexed and written unchanged.
///
/// What was measured to make it work: the video's format description carries
/// the core's `vpcC`/`av1C`/`avcC`/`hvcC`; an Opus cookie is OpusHead and
/// each packet carries its own sample count (`mVariableFramesInPacket`, with
/// `mFramesPerPacket` 0), where a fixed 960 mistimes 60 ms packets; a Vorbis
/// track is `vorb` with the Vorbis CodecPrivate (its three Xiph-laced
/// headers) as the cookie and each packet's own count, as AVFoundation's Ogg
/// reader describes it, and writes into `.mov` only (spec §11 #228-V); an
/// AAC cookie is the core's ES_Descriptor. The video input's `mediaTimeScale` is
/// the described timescale — the grid's numerator when the core snapped the
/// track (without it 30000/1001 lands at 600, off the grid), the raw
/// timescale otherwise (the numerator would merge frames 10 ms apart). It is
/// NEVER set on the audio input, where it raises an Objective-C exception
/// nothing can catch.
///
/// The MOVIE timescale — the grid of each track's edit and duration, not of
/// its samples — is the least common multiple of 600 and the written tracks'
/// timescales (`movieTimeScale`, spec §11 #232), so a track that starts off
/// the writer's default 1/600 s grid keeps its start. A copy already on disk
/// is reused as it was written (#232's accepted limit).
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
        var videoScale: Int64?
        var audioScale: Int64?
        var seconds = 0.0
        if let video = d.video, video.samples > 0 {
            let format = try videoFormat(video, failed)
            let input = AVAssetWriterInput(
                mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            if let scale = CMTimeScale(exactly: video.timescale) { input.mediaTimeScale = scale }
            pumps.append(try Pump(
                c, ReelContainer.video, input, format, CMTimeScale(clamping: video.timescale),
                source, label: "video"))
            videoScale = video.timescale
            seconds = max(seconds, end(c, ReelContainer.video, video.timescale, packet: 0))
        }
        if let audio = d.audio, audio.samples > 0 {
            let format = try audioFormat(audio, failed)
            let input = AVAssetWriterInput(
                mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            pumps.append(try Pump(
                c, ReelContainer.audio, input, format, CMTimeScale(clamping: audio.timescale),
                source, label: "audio"))
            audioScale = audio.timescale
            seconds = max(
                seconds,
                end(c, ReelContainer.audio, audio.timescale, packet: audio.framesPerPacket))
        }
        for pump in pumps {
            pump.input.expectsMediaDataInRealTime = false
            guard writer.canAdd(pump.input) else {
                throw failed("its \(pump.label) cannot be written into a movie")
            }
            writer.add(pump.input)
        }
        guard !pumps.isEmpty else { throw failed("it has nothing to copy") }
        if let scale = movieTimeScale(video: videoScale, audio: audioScale, seconds: seconds) {
            writer.movieTimeScale = scale
        }
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

    // MARK: - The movie timescale

    /// The copy's movie timescale (spec §11 #232), or nil to leave the
    /// writer's default. `video` and `audio` are the described timescale of
    /// each track that is written; nil or not positive is absent. The first
    /// of lcm(600, video, audio) and — with audio present — lcm(600, audio)
    /// that holds a movie of `seconds` (and one more) in 31 bits; an lcm
    /// that overflows does not fit. With neither track it answers 600, which
    /// `write` never asks: it refuses a file with no track first.
    static func movieTimeScale(video: Int64?, audio: Int64?, seconds: Double) -> CMTimeScale? {
        let video = video.flatMap { $0 > 0 ? $0 : nil }
        let audio = audio.flatMap { $0 > 0 ? $0 : nil }
        var candidates = [lcm(lcm(600, video ?? 1), audio ?? 1)]
        if let audio { candidates.append(lcm(600, audio)) }
        for case let candidate? in candidates {
            guard let scale = CMTimeScale(exactly: candidate),
                (seconds + 1) * Double(scale) <= Double(Int32.max)
            else { continue }
            return scale
        }
        return nil
    }

    /// The least common multiple of two positive numbers; nil on overflow.
    private static func lcm(_ a: Int64?, _ b: Int64) -> Int64? {
        guard let a else { return nil }
        var (x, y) = (a, b)
        while y != 0 { (x, y) = (y, x % y) }
        let (product, overflow) = (a / x).multipliedReportingOverflow(by: b)
        return overflow ? nil : product
    }

    /// Where `track`'s last decode-order sample ends, in seconds: its later
    /// time plus its duration for video, its time plus its sample count
    /// (`packet` when it carries 0) for audio.
    private static func end(
        _ c: ReelContainer, _ track: UInt32, _ timescale: Int64, packet: Int
    ) -> Double {
        guard timescale > 0, let s = c.sample(track, at: c.count(track) - 1) else { return 0 }
        let ticks = track == ReelContainer.video
            ? Double(max(s.pts, s.dts)) + Double(s.duration)
            : Double(s.pts) + Double(s.frames != 0 ? Int(s.frames) : packet)
        return ticks / Double(timescale)
    }

    // MARK: - Format descriptions

    private static func videoFormat(
        _ v: ContainerDescription.Video, _ failed: (String) -> ContainerRewrapError
    ) throws -> CMFormatDescription {
        var atoms: [String: Any] = [:]
        if let atom = v.atom, let hex = v.atomHex { atoms[atom] = data(hex: hex) }
        var extensions: [String: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: atoms
        ]
        // Spec §11 HD-18 (a), (b): a PQ copy (the Colour's transfer 16) carries
        // its HDR10 fields as HD-12's two blobs, and the PQ label; no other
        // copy's description changes.
        if v.transfer == pqTransfer {
            extensions.merge(hdr10Blobs(v)) { _, blob in blob }
            extensions.merge(pqLabels(v)) { _, label in label }
        }
        // Spec §11 HD-19 (b): an HLG copy (transfer 18) carries the HLG label,
        // which AVFoundation does not infer from the codec's own colour (H7h).
        if v.transfer == hlgTransfer {
            extensions.merge(hlgLabels(v)) { _, label in label }
        }
        // Spec §11 CX-16 (10): an SDR copy carries the colour its source states, so an SD
        // picture is not read through the matrix AVFoundation guesses from its size.
        if v.transfer != pqTransfer, v.transfer != hlgTransfer {
            extensions.merge(sdrLabels(v)) { _, label in label }
        }
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

    /// ISO/IEC 23091-2's transfer codes for SMPTE ST 2084 (PQ) and ARIB
    /// STD-B67 (HLG).
    private static let pqTransfer = 16
    private static let hlgTransfer = 18

    /// The Colour element's `mdcv` and `clli` blobs, each only when the file
    /// has it (spec §11 HD-18 (a)).
    private static func hdr10Blobs(_ v: ContainerDescription.Video) -> [String: Any] {
        var blobs: [String: Any] = [:]
        if let hex = v.mdcvHex {
            blobs[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] =
                data(hex: hex)
        }
        if let hex = v.clliHex {
            blobs[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] = data(hex: hex)
        }
        return blobs
    }

    /// The PQ label, and the primaries and matrix Core Video names for the
    /// Colour's codes (spec §11 HD-18 (b)).
    private static func pqLabels(_ v: ContainerDescription.Video) -> [String: Any] {
        labels(v, transfer: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
    }

    /// The HLG label, with `pqLabels`' primaries and matrix (spec §11 HD-19 (b)).
    private static func hlgLabels(_ v: ContainerDescription.Video) -> [String: Any] {
        labels(v, transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
    }

    /// `transfer` as the description's transfer function, and the primaries
    /// and matrix Core Video names for the Colour's codes when it names them.
    private static func labels(
        _ v: ContainerDescription.Video, transfer: String
    ) -> [String: Any] {
        var labels: [String: Any] = [
            kCMFormatDescriptionExtension_TransferFunction as String: transfer
        ]
        if let code = v.primaries,
            let name = CVColorPrimariesGetStringForIntegerCodePoint(Int32(clamping: code))
        {
            labels[kCMFormatDescriptionExtension_ColorPrimaries as String] =
                name.takeUnretainedValue() as String
        }
        if let code = v.matrix,
            let name = CVYCbCrMatrixGetStringForIntegerCodePoint(Int32(clamping: code))
        {
            labels[kCMFormatDescriptionExtension_YCbCrMatrix as String] =
                name.takeUnretainedValue() as String
        }
        return labels
    }

    /// An SDR copy's labels (spec §11 CX-16 (10)), each field on its own: the Colour's
    /// BT.709, BT.601 or BT.2020 matrix and primaries and its BT.709-class or sRGB transfer,
    /// as Core Video names them; else, for the matrix, a VP9 keyframe's `color_space`
    /// (`streamMatrix`). Nothing for a code outside those sets or one Core Video does not name.
    private static func sdrLabels(_ v: ContainerDescription.Video) -> [String: Any] {
        var labels: [String: Any] = [:]
        let matrix = v.matrix.flatMap { sdrMatrices.contains($0) ? $0 : nil } ?? v.streamMatrix
        if let code = matrix, sdrMatrices.contains(code),
            let name = CVYCbCrMatrixGetStringForIntegerCodePoint(Int32(code))
        {
            labels[kCMFormatDescriptionExtension_YCbCrMatrix as String] =
                name.takeUnretainedValue() as String
        }
        if let code = v.primaries, sdrPrimaries.contains(code),
            let name = CVColorPrimariesGetStringForIntegerCodePoint(Int32(code))
        {
            labels[kCMFormatDescriptionExtension_ColorPrimaries as String] =
                name.takeUnretainedValue() as String
        }
        if let code = v.transfer, sdrTransfers.contains(code),
            let name = CVTransferFunctionGetStringForIntegerCodePoint(Int32(code))
        {
            labels[kCMFormatDescriptionExtension_TransferFunction as String] =
                name.takeUnretainedValue() as String
        }
        return labels
    }

    /// ISO/IEC 23091-2's BT.709, BT.601 (two codes) and BT.2020 matrix and primaries codes,
    /// and the BT.709-class and sRGB transfer codes (spec §11 CX-16 (10)).
    private static let sdrMatrices: Set<Int> = [1, 5, 6, 9]
    private static let sdrPrimaries: Set<Int> = [1, 5, 6, 9]
    private static let sdrTransfers: Set<Int> = [1, 6, 13, 14, 15]

    private static func audioFormat(
        _ a: ContainerDescription.Audio, _ failed: (String) -> ContainerRewrapError
    ) throws -> CMFormatDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = a.sampleRate
        // 'opus' is kAudioFormatOpus and 'aac ' kAudioFormatMPEG4AAC; 'vorb'
        // has no SDK constant.
        asbd.mFormatID = ContainerRewrap.fourCharCode(a.fourcc ?? "")
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
            label: "com.kgalligan.framejob.rewrap.\(label)", qos: .userInitiated)
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
