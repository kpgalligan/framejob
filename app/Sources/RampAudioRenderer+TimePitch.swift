import AVFoundation

/// Keep pitch on (spec §11 SR-13): Apple's time-pitch unit driven offline in
/// rate mode, its rate commanded a measured lead ahead of the map — still
/// Apple's algorithm (SY-41: no own time-stretch).
///
/// `AVAudioSourceNode` → `AVAudioUnitTimePitch` (pitch 0, the default
/// overlap) → the main mixer, in `AVAudioEngine`'s offline manual rendering
/// mode. The source is fed as is, sequentially, from ⌊p(0)⌋ − P (P = 4 800
/// frames always; a position before frame 0 reads zero, so a clip at source
/// 0 runs the same path). Before each 256-frame `renderOffline` the unit's
/// rate is (p̃(n+L+256) − p̃(n+L)) / 256 clamped to 1/32…32, n counted from
/// output frame round(P / r(0)) — the frame at which the pre-roll's input is
/// spent — and L the lead, because the unit's window follows the rate it is
/// given; the first round(P / r(0)) + the unit's latency output frames are
/// discarded, so kept frame 0 is p(0).
extension RampAudioRenderer {
    /// P: source frames fed before the clip's first.
    static let timePitchPreroll = 4800
    /// Output frames per `renderOffline`, the grain the rate changes on.
    static let timePitchBlock = 256
    static let timePitchMaxFrames: AVAudioFrameCount = 4096
    static let timePitchRates: ClosedRange<Double> = (1.0 / 32)...32
    /// L*, output frames: the lead SR-14's sweep picked, 56 ms (RK1's max
    /// |diff| 8.06 ms, RK2's 5.55 ms, every click found;
    /// `designs/speed-ramps.md`'s SR1d record). Apple's unpublished
    /// behaviour, pinned by `ramp_proof.py`'s L1 and L2; a deep slow-down
    /// still lands up to about 22 ms late (RK3, the owner's accepted limit,
    /// SR-15, pinned by L3) until SR1e.
    static let rateLeadFrames = 2688

    /// Feeds the source node: frame after frame from `next`, every channel,
    /// reading ahead and dropping behind. A read error is kept for the
    /// render loop, which cannot hear it from inside the render block.
    final class TimePitchFeeder: @unchecked Sendable {
        let source: RampSourceReader
        private(set) var next: Int64
        private(set) var fed: Int64 = 0
        private(set) var error: Error?

        init(source: RampSourceReader, from start: Int64) {
            self.source = source
            next = start
        }

        func feed(_ count: Int, into list: UnsafeMutablePointer<AudioBufferList>) {
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            do {
                try source.fill(through: next + Int64(count))
            } catch {
                self.error = error
            }
            source.drop(before: next)
            for (c, buffer) in buffers.enumerated() {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }
                let channel = min(c, source.channels - 1)
                for i in 0..<count { data[i] = source.sample(next + Int64(i), channel: channel) }
            }
            next += Int64(count)
            fed += Int64(count)
        }
    }

    /// Renders `frames` output frames into `writer`, the rate read `lead`
    /// output frames ahead; answers the unit's latency (frames) and the
    /// source frames pulled past p(0).
    static func renderTimePitch(
        _ map: RampAudioMap, source: RampSourceReader, frames: Int64, lead: Int,
        writer: RampCAFWriter, cancelled: () -> Bool, progress: ((Double) -> Void)?
    ) throws -> (latency: Int, pulled: Int64) {
        let channels = source.channels
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels))
        else { throw RenderError.failed("no \(channels)-channel float format") }
        let p0 = position(map, 0)
        let r0 = position(map, 1) - p0
        /// p extended before 0 at r(0); past the end the map's own slope.
        func extended(_ n: Int64) -> Double { n < 0 ? p0 + Double(n) * r0 : position(map, n) }

        let feeder = TimePitchFeeder(
            source: source, from: Int64(p0.rounded(.down)) - Int64(timePitchPreroll))
        let node = AVAudioSourceNode(format: format) { _, _, count, list in
            feeder.feed(Int(count), into: list)
            return noErr
        }
        let unit = AVAudioUnitTimePitch()
        unit.pitch = 0
        let engine = AVAudioEngine()
        engine.attach(node)
        engine.attach(unit)
        engine.connect(node, to: unit, format: format)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(
                .offline, format: format, maximumFrameCount: timePitchMaxFrames)
            try engine.start()
        } catch {
            throw RenderError.failed("the time-pitch engine did not start: \(error.localizedDescription)")
        }
        defer { engine.stop() }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat, frameCapacity: timePitchMaxFrames)
        else { throw RenderError.failed("no render buffer") }

        let latency = Int((unit.latency * Double(sampleRate)).rounded())
        let preroll = Int64((Double(timePitchPreroll) / r0).rounded())
        let discard = preroll + Int64(latency)
        let block = Int64(timePitchBlock)
        var out = [Float](repeating: 0, count: Int(timePitchMaxFrames) * channels)
        var rendered: Int64 = 0
        var written: Int64 = 0
        while written < frames {
            if cancelled() { throw RenderError.cancelled }
            let n = rendered - preroll + Int64(lead)
            let rate = (extended(n + block) - extended(n)) / Double(block)
            unit.rate = Float(min(max(rate, timePitchRates.lowerBound), timePitchRates.upperBound))
            let status: AVAudioEngineManualRenderingStatus
            do {
                status = try engine.renderOffline(AVAudioFrameCount(block), to: buffer)
            } catch {
                throw RenderError.failed("renderOffline: \(error.localizedDescription)")
            }
            if let error = feeder.error {
                throw RenderError.failed("the source: \(error.localizedDescription)")
            }
            guard status == .success, let data = buffer.floatChannelData else {
                throw RenderError.failed("renderOffline answered status \(status.rawValue)")
            }
            let got = Int64(buffer.frameLength)
            let from = max(0, discard - rendered)
            let upTo = min(got, discard + frames - rendered)
            if upTo > from {
                let count = Int(upTo - from)
                for i in 0..<count {
                    for c in 0..<channels { out[i * channels + c] = data[c][Int(from) + i] }
                }
                try writer.write(out, frames: count)
                written += Int64(count)
                progress?(Double(written) / Double(frames))
            }
            rendered += got
            if got == 0 { throw RenderError.failed("renderOffline rendered no frames") }
        }
        return (latency, feeder.fed - Int64(timePitchPreroll))
    }
}
