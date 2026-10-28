import AVFoundation

/// Where `ExportEncodePump`'s packets go, once the pump has made them the container's bytes
/// (AV1's temporal delimiters stripped) and put them in order (spec §11 CX-12, CX-15, CX-16):
/// the MP4 row's passthrough `AVAssetWriterInput`, or the WebM rows' core writer. Both are called on the pump's encode
/// queue alone, so a sink needs no lock of its own.
protocol ExportPacketSink: AnyObject {
    /// Writes one packet presented at `time` for `duration`; `key` is a KEY_FRAME; `alpha` is
    /// the frame's alpha stream packet on `vp9_alpha_webm` (CX-17 (5)), else nil. nil once
    /// written; `ExportPacketSinkStopped` when the export stopped first (nothing to report);
    /// any other error fails the export.
    func append(
        _ data: Data, alpha: Data?, at time: CMTime, duration: CMTime, key: Bool,
        isStopping: () -> Bool
    ) -> (any Error)?
    /// No packet follows: the pump's one exit calls it exactly once, clean or not.
    func finish()
}

/// A sink's answer when the export stopped while it waited: the stop is already recorded
/// (a cancel, or another pump's failure), so the pump reports nothing for it.
struct ExportPacketSinkStopped: Error {}

/// The `av1` row's sink: each packet as one `av01` sample (`ExportAV1Track.sample`) into the
/// passthrough input, after waiting for it to take more; `finish` marks the input finished.
final class ExportMP4PacketSink: ExportPacketSink {
    private let input: AVAssetWriterInput
    /// The `av01` description; nil (never on the `av1` row) makes every packet unwritable.
    private let format: CMVideoFormatDescription?

    init(input: AVAssetWriterInput, format: CMVideoFormatDescription?) {
        self.input = input
        self.format = format
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportMP4PacketSink does not support NSCoder")
    }

    func append(
        _ data: Data, alpha: Data?, at time: CMTime, duration: CMTime, key: Bool,
        isStopping: () -> Bool
    ) -> (any Error)? {
        // An MP4 has nowhere to put a VP9 alpha (CX-1: no VP9 in MP4).
        guard alpha == nil else {
            return Exporter.ExportError.failed("An MP4 cannot carry a packet's alpha.")
        }
        guard let format, let sample = ExportAV1Track.sample(
            data, at: time, duration: duration, format: format)
        else {
            return Exporter.ExportError.failed("An AV1 packet could not be made a sample.")
        }
        while !input.isReadyForMoreMediaData {
            guard !isStopping() else { return ExportPacketSinkStopped() }
            usleep(1000)
        }
        guard input.append(sample) else {
            return Exporter.ExportError.failed("The file could not be written.")
        }
        return nil
    }

    func finish() {
        input.markAsFinished()
    }
}

/// The WebM rows' sink: each packet into the core's writer as the video track's block at its
/// time in nanoseconds, the key flag the encoder's (spec §11 CX-15 (3), CX-16 (6)), with its
/// alpha on `vp9_alpha_webm` (CX-17 (5)). The core queues
/// what the interleave holds back, so this never waits. `finish` ends the video track; a
/// failure there is the writer's `finish`'s to report.
final class ExportWebMPacketSink: ExportPacketSink {
    private let webm: ReelWebM
    /// `-RCDevWebMFault video@N` (`ExportWebMDevFault`, dev tools only), else nil.
    private let fault: ExportWebMDevFault?
    private var packets = 0

    init(webm: ReelWebM, fault: ExportWebMDevFault? = nil) {
        self.webm = webm
        self.fault = fault
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportWebMPacketSink does not support NSCoder")
    }

    func append(
        _ data: Data, alpha: Data?, at time: CMTime, duration: CMTime, key: Bool,
        isStopping: () -> Bool
    ) -> (any Error)? {
        packets += 1
        if let error = fault?.videoPacket(packets) { return error }
        do {
            if let alpha {
                try webm.addVideo(
                    ptsNs: Self.nanoseconds(time), key: key, data: data, alpha: alpha)
                return nil
            }
            try webm.add(
                track: ReelWebM.video, ptsNs: Self.nanoseconds(time), key: key,
                discardPaddingNs: 0, data: data)
        } catch {
            return Exporter.ExportError.failed(
                "The WebM file could not be written: \(error.localizedDescription)")
        }
        return nil
    }

    func finish() {
        try? webm.endTrack(ReelWebM.video)
    }

    /// `time` in nanoseconds, rounded half away from zero.
    static func nanoseconds(_ time: CMTime) -> Int64 {
        CMTimeConvertScale(time, timescale: 1_000_000_000, method: .roundHalfAwayFromZero).value
    }
}
