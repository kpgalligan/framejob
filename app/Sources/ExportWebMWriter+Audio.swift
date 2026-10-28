import AVFoundation

extension ExportWebMWriter {
    // MARK: - The audio pump

    /// Reads the mix to its end, encodes it and adds each packet, holding the newest back so
    /// the last one can carry the tail's DiscardPadding (CX-15 (5)), or stops at the flag
    /// before a read.
    ///
    /// **Times are the stamps'.** Each buffer is placed at its rebased stamp
    /// (`ExportAudioEnd.align`: silence for a gap, the covered head cut), so the stream the
    /// encoder is fed is the timeline's sound frame for frame from the range's start, and
    /// packet k's first frame is the one stamped k × 960 / 48 kHz — k × 20 ms, a whole tick of
    /// WebM's 1 ms timecode scale — which is the time it is added at.
    func pumpAudio(
        _ output: AVAssetReaderOutput, into webm: ReelWebM, through opus: ExportOpusEncoder
    ) {
        let gain = audioGain
        var held: Data?
        var added: Int64 = 0
        let packetNs = Int64(ExportOpusEncoder.framesPerPacket) * 1_000_000_000 / 48_000
        let add = { (packet: Data, padding: Int64) throws in
            try webm.add(
                track: ReelWebM.audio, ptsNs: added * packetNs, key: true,
                discardPaddingNs: padding, data: packet)
            added += 1
        }
        let feed = { (packets: [Data]) throws in
            for packet in packets {
                if let previous = held { try add(previous, 0) }
                held = packet
            }
        }
        var reads = 0
        do {
            while true {
                guard !isStopping else { return }
                reads += 1
                try fault?.beforeAudioRead(reads)
                guard let decoded = output.copyNextSampleBuffer() else {
                    if let error = readFailure(of: audioReader) {
                        stopped(with: error)
                        return
                    }
                    break
                }
                let time = CMSampleBufferGetPresentationTimeStamp(decoded) - range.start
                guard time.isNumeric, time >= .zero else { continue }
                if gain != nil, CMSampleBufferGetNumSamples(decoded) == 0 { continue }
                guard let sample = gain == nil ? decoded : gain?.apply(to: decoded) else {
                    stopped(with: Exporter.ExportError.failed(
                        "The loudness gain could not be applied to a sample."))
                    return
                }
                let frame = CMTimeConvertScale(
                    time, timescale: CMTimeScale(ExportAudioEnd.sampleRate),
                    method: .roundHalfAwayFromZero
                ).value
                for placed in audioEnd.align(sample, at: Int(frame)) {
                    guard let fitted = audioEnd.fit(placed) else { continue }
                    try feed(try opus.encode(fitted))
                }
            }
            for silence in audioEnd.padding() {
                try feed(try opus.encode(silence))
            }
            var tail = (held.map { [$0] } ?? []) + (try opus.finish())
            // The decoded length is packets × 960 − pre-skip; the surplus over #337's
            // target is cut whole packets first, then by the last one's DiscardPadding.
            var padding = (Int(added) + tail.count) * ExportOpusEncoder.framesPerPacket
                - opus.preSkip - audioEnd.target
            while padding >= ExportOpusEncoder.framesPerPacket, !tail.isEmpty {
                tail.removeLast()
                padding -= ExportOpusEncoder.framesPerPacket
            }
            guard padding >= 0, padding < ExportOpusEncoder.framesPerPacket else {
                stopped(with: Exporter.ExportError.failed(
                    "The audio could not be encoded to its exact length."))
                return
            }
            let paddingNs = (Int64(padding) * 1_000_000_000 + 24_000) / 48_000
            for (index, packet) in tail.enumerated() {
                try add(packet, index == tail.count - 1 ? paddingNs : 0)
            }
            try webm.endTrack(ReelWebM.audio)
        } catch {
            stopped(with: error)
        }
    }
}
