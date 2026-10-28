import AVFoundation

/// The video pump of a row a bundled encoder writes (`settings.writer`, spec §11 CX-12,
/// CX-15): the composed frames converted to I010 on the export's video queue and encoded by
/// SVT-AV1 on a serial encode queue of its own, whose packets go to an `ExportPacketSink` —
/// the `av1` row's passthrough `AVAssetWriterInput` as `av01` samples, or the `av1_webm`
/// row's core writer.
///
/// **Two queues, one owner each.** The video queue reads, converts and hands each frame on,
/// bounded to three in flight (`slots`) so a slow encoder holds the read back; the encode
/// queue owns the encoder and the sink — every `send`, every packet, every append, the
/// flush and the sink's `finish`. Progress is counted by frames SUBMITTED (the encoder's lag
/// is under a second); a cancel is the writer's flag, read before each read, each send and
/// each wait in the sink.
///
/// **The finish** runs once on the encode queue, after every frame queued before it: at the
/// end of a clean read, the end of stream and a drain to the last packet; on a stop (a
/// cancel, a failed read, another pump's failure), the end of stream and a drain that
/// discards; after an encoder error, neither. Every exit finishes the sink and leaves the
/// group exactly once. The encoder itself is torn down by `close()`, after the writer's
/// pumps have all left, as the reader is (G-17).
final class ExportEncodePump {
    /// The settings' `writer` this pump serves.
    static let writer = "svt_av1"

    let formatDescription: CMVideoFormatDescription
    /// The `av1C` record and the sequence header's colour, and the picture the frames are
    /// (the WebM layout's track, `ExportWebMLayout`).
    let config: ReelAV1.Config
    let picture: ExportAV1Picture

    private var encoder: SVTAV1Encoder?
    private let converter: ExportI010Converter
    private let encodeQueue = DispatchQueue(
        label: "com.kgalligan.framejob.export.encode", qos: .userInitiated)
    private let range: CMTimeRange
    private let frameDuration: CMTime
    private let slots = DispatchSemaphore(value: 3)

    // The encode queue's own state.
    private var times: [Int64: CMTime] = [:]
    private var lastTime = CMTime.negativeInfinity
    private var encoderFailed = false
    private var finished = false

    init(settings: ExportSettings, canvas: CGSize, range: CMTimeRange) throws {
        let frame = ExportWriter.encodedSize(settings)
        let speed = settings.encoderSpeed ?? .balanced
        let rate = settings.videoBitrate.map { max(1, $0) }
            ?? ExportWriter.defaultVideoBitrate(settings, bitsPerPixel: 0.07)
        let picture = ExportAV1Picture(color: settings.color)
        let encoder = try SVTAV1Encoder(
            width: frame.width, height: frame.height, fps: settings.fps, bitsPerSecond: rate,
            speed: speed, picture: picture)
        do {
            config = try ReelAV1.config(sequenceHeader: encoder.sequenceHeader)
        } catch {
            throw Exporter.ExportError.failed(
                "SVT-AV1's sequence header could not be read: \(error.localizedDescription)")
        }
        formatDescription = try ExportAV1Track.formatDescription(
            width: frame.width, height: frame.height, config: config, picture: picture)
        converter = try ExportI010Converter(
            width: frame.width, height: frame.height, canvas: canvas,
            fills: ExportWriter.fillsTheBox(settings, canvas: canvas), picture: picture, pool: 3)
        self.encoder = encoder
        self.picture = picture
        self.range = range
        self.frameDuration = CompositionBuilder.frameDuration(settings.fps)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportEncodePump does not support NSCoder")
    }

    /// Reads `output` to its end on `queue` and encodes it into `sink`; `group` is left once
    /// the sink is finished. `readFailure` answers the reader's error when the read failed;
    /// `fail` records the first failure; `advance` is each submitted frame's file time.
    func run(
        sink: any ExportPacketSink, output: AVAssetReaderOutput, on queue: DispatchQueue,
        group: DispatchGroup, isStopping: @escaping () -> Bool,
        readFailure: @escaping () -> (any Error)?, fail: @escaping (any Error) -> Void,
        advance: @escaping (CMTime) -> Void
    ) {
        group.enter()
        let finish: (Bool) -> Void = { [self] clean in
            encodeQueue.async {
                self.finish(
                    clean: clean, sink: sink, group: group, isStopping: isStopping, fail: fail)
            }
        }
        queue.async { [self] in
            var index: Int64 = 0
            while true {
                guard !isStopping() else { return finish(false) }
                guard let sample = output.copyNextSampleBuffer() else {
                    // Dry: the range is read, or the read failed — never a branded, done
                    // file after a failed read.
                    if let error = readFailure() {
                        fail(error)
                        return finish(false)
                    }
                    return finish(true)
                }
                let time = CMSampleBufferGetPresentationTimeStamp(sample) - range.start
                guard time.isNumeric, time >= .zero else { continue }
                slots.wait()
                guard let pixels = CMSampleBufferGetImageBuffer(sample),
                    let frame = converter.convert(pixels)
                else {
                    slots.signal()
                    fail(Exporter.ExportError.failed(
                        "A frame could not be prepared for the encoder."))
                    return finish(false)
                }
                let at = index
                index += 1
                encodeQueue.async {
                    self.encode(
                        frame, index: at, time: time, sink: sink, isStopping: isStopping,
                        fail: fail)
                }
                advance(time)
            }
        }
    }

    /// The encoder's teardown, on the encode queue, once every input is finished.
    func close() {
        encodeQueue.async { [self] in encoder = nil }
    }

    // MARK: - The encode queue

    private func encode(
        _ frame: I010Frame, index: Int64, time: CMTime, sink: any ExportPacketSink,
        isStopping: () -> Bool, fail: (any Error) -> Void
    ) {
        defer {
            converter.recycle(frame)
            slots.signal()
        }
        guard !finished, !encoderFailed, !isStopping(), let encoder else { return }
        do {
            try encoder.send(frame, index: index)
            times[index] = time
            while let packet = try encoder.nextPacket(wait: false) {
                guard write(packet, sink: sink, isStopping: isStopping, fail: fail) else {
                    return
                }
            }
        } catch {
            encoderFailed = true
            fail(error)
        }
    }

    /// One packet into the file: false once the export cannot go on.
    private func write(
        _ packet: SVTAV1Encoder.Packet, sink: any ExportPacketSink, isStopping: () -> Bool,
        fail: (any Error) -> Void
    ) -> Bool {
        guard !packet.data.isEmpty else { return true }
        var data = packet.data
        guard ReelAV1.stripTemporalDelimiters(&data) else {
            fail(Exporter.ExportError.failed("SVT-AV1 wrote a packet the core could not read."))
            return false
        }
        guard let time = times.removeValue(forKey: packet.pts), time > lastTime else {
            fail(Exporter.ExportError.failed("SVT-AV1 wrote a frame out of order."))
            return false
        }
        lastTime = time
        if let error = sink.append(
            data, at: time, duration: frameDuration, key: packet.isKey, isStopping: isStopping)
        {
            if !(error is ExportPacketSinkStopped) { fail(error) }
            return false
        }
        return true
    }

    /// The one exit: the end of stream and the drain as `clean` and the encoder allow, then
    /// the sink finished and the group left, exactly once.
    private func finish(
        clean: Bool, sink: any ExportPacketSink, group: DispatchGroup, isStopping: () -> Bool,
        fail: (any Error) -> Void
    ) {
        guard !finished else { return }
        finished = true
        defer {
            sink.finish()
            group.leave()
        }
        guard !encoderFailed, let encoder else { return }
        do {
            try encoder.sendEndOfStream()
            var writing = clean && !isStopping()
            while let packet = try encoder.nextPacket(wait: true) {
                if writing {
                    writing = write(packet, sink: sink, isStopping: isStopping, fail: fail)
                }
                if packet.isLast { break }
            }
        } catch {
            encoderFailed = true
            if clean { fail(error) }
        }
    }
}
