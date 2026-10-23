import AVFoundation

/// Keep pitch on (spec §11 SR-8): resample, then pitch-shift — still Apple's
/// algorithm (SY-41: no own time-stretch).
///
/// Stage 1 is the keep-pitch-off glide (`RampVarispeedStream`) at 48 kHz × K,
/// K = `oversampling(map)`, from stage frame −P·K. Stage 2 is
/// `AVAudioSourceNode` (stage 1) → `AVAudioUnitTimePitch` (rate 1, the
/// default overlap) → the main mixer, in `AVAudioEngine`'s offline manual
/// rendering at 48 kHz × K: before each 256-frame `renderOffline` producing
/// stage-2 frames s … s + 255 the unit's `pitch` is −1200·log₂ r cents
/// (clamped to ±2400: past ×0.25–×4 the excess glides like tape), r the
/// map's rate over stage frames k … k + 256, k = s − P·K − D_K. Kept stage-2
/// frame i is stage-2 frame i + P·K + D_K. Stage 3 (K > 1) decimates by K:
/// output frame m is `RampAudioResampler` at rate K at kept position K·m;
/// with K = 1 output frame m is kept frame m.
extension RampAudioRenderer {
    /// P: output frames of pre-roll before the clip's first.
    static let timePitchPreroll = 4800
    /// Stage-2 frames per `renderOffline`, the grain the pitch changes on.
    static let timePitchBlock = 256
    static let timePitchMaxFrames: AVAudioFrameCount = 4096
    static let timePitchCents: ClosedRange<Double> = -2400...2400
    static let timePitchMaxOversampling = 4
    /// D_K for K = 1 … 4, stage-2 frames: the unit's own delay at ×1,
    /// measured by SR1c's render-only run with every D_K 0 (the median of a
    /// K's constant RC-on renders' signed median click offsets: K = 1
    /// +0.060 and 0.000 ms, K = 2 +0.006 and +0.077, K = 3 −0.060, each
    /// within 0.1 ms, so 0; K = 4 +0.9375 ms × 192 = 180;
    /// `designs/speed-ramps.md`'s SR1c record).
    static let timePitchDelayFrames: [Int] = [0, 0, 0, 180]

    /// K: the map's steepest rate rounded up, 1 … 4.
    static func oversampling(_ map: RampAudioMap) -> Int {
        let steepest = RampVarispeedStream.steepest(map)
        return min(timePitchMaxOversampling, max(1, Int((steepest - 1e-9).rounded(.up))))
    }

    /// The unit's pitch for a local rate: −1200·log₂ rate cents, clamped.
    static func pitchCents(rate: Double) -> Double {
        min(max(-1200 * log2(rate), timePitchCents.lowerBound), timePitchCents.upperBound)
    }

    /// Feeds the source node from the stage-1 stream, de-interleaving into
    /// the node's buffers. A read error is kept for the render loop, which
    /// cannot hear it from inside the render block.
    final class TimePitchFeeder: @unchecked Sendable {
        let stream: RampVarispeedStream
        private var scratch: [Float] = []
        private(set) var error: Error?

        init(stream: RampVarispeedStream) { self.stream = stream }

        func feed(_ count: Int, into list: UnsafeMutablePointer<AudioBufferList>) {
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            let channels = stream.channels
            if scratch.count < count * channels {
                scratch = [Float](repeating: 0, count: count * channels)
            }
            do {
                try scratch.withUnsafeMutableBufferPointer { try stream.read(count, into: $0) }
            } catch {
                if self.error == nil { self.error = error }
                for i in 0..<(count * channels) { scratch[i] = 0 }
            }
            for (c, buffer) in buffers.enumerated() {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                    continue
                }
                let channel = min(c, channels - 1)
                for i in 0..<count { data[i] = scratch[i * channels + channel] }
            }
        }
    }

    /// Kept stage-2 frames, interleaved, held forward and dropped behind
    /// stage 3's reach (as `RampSourceReader`); a frame not held reads zero.
    final class TimePitchKept {
        let channels: Int
        private var base: Int64
        private var samples: [Float] = []
        /// A dead prefix is cut once it is at least this many frames.
        private static let dropFrames: Int64 = 65_536

        var end: Int64 { base + Int64(samples.count / channels) }

        init(channels: Int, from start: Int64) {
            self.channels = channels
            base = start
        }

        func sample(_ k: Int64, channel c: Int) -> Float {
            guard k >= base, k < end else { return 0 }
            return samples[Int(k - base) * channels + c]
        }

        func append(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
            samples.reserveCapacity(samples.count + frames * channels)
            for i in 0..<frames {
                for c in 0..<channels { samples.append(data[c][i]) }
            }
        }

        func drop(before k: Int64) {
            let dead = min(k, end) - base
            guard dead >= Self.dropFrames else { return }
            samples.removeFirst(Int(dead) * channels)
            base += dead
        }
    }

    /// Renders `frames` output frames into `writer`; answers the unit's
    /// reported latency (stage-2 frames) and the stage-1 frames it pulled
    /// past kept frame 0.
    static func renderTimePitch(
        _ map: RampAudioMap, stream: RampVarispeedStream, frames: Int64, writer: RampCAFWriter,
        cancelled: () -> Bool, progress: ((Double) -> Void)?
    ) throws -> (latency: Int, pulled: Int64) {
        let channels = stream.channels
        let k = stream.per
        let stageRate = Double(sampleRate * k)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: stageRate, channels: AVAudioChannelCount(channels))
        else { throw RenderError.failed("no \(channels)-channel float format at \(Int(stageRate)) Hz") }

        let feeder = TimePitchFeeder(stream: stream)
        let node = AVAudioSourceNode(format: format) { _, _, count, list in
            feeder.feed(Int(count), into: list)
            return noErr
        }
        let unit = AVAudioUnitTimePitch()
        unit.rate = 1
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
            throw RenderError.failed(
                "the time-pitch engine did not start at \(Int(stageRate)) Hz: "
                    + error.localizedDescription)
        }
        defer { engine.stop() }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat, frameCapacity: timePitchMaxFrames)
        else { throw RenderError.failed("no render buffer") }

        let latency = Int((unit.latency * stageRate).rounded())
        let lead = Int64(timePitchPreroll * k + timePitchDelayFrames[k - 1])
        let block = Int64(timePitchBlock)
        let kept = TimePitchKept(channels: channels, from: -lead)
        let decimator = RampAudioResampler()
        let reach = Int64(RampAudioResampler.reach(rate: Double(k)))
        let capacity = Int(timePitchMaxFrames)
        var out = [Float](repeating: 0, count: capacity * channels)
        var rendered: Int64 = 0
        var written: Int64 = 0
        while written < frames {
            if cancelled() { throw RenderError.cancelled }
            let at = rendered - lead
            let rate = Double(k) * (position(map, at + block, per: k) - position(map, at, per: k))
                / Double(block)
            unit.pitch = Float(pitchCents(rate: rate))
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
            let got = Int(buffer.frameLength)
            if got == 0 { throw RenderError.failed("renderOffline rendered no frames") }
            kept.append(data, frames: got)
            rendered += Int64(got)

            var count = 0
            while count < capacity, written + Int64(count) < frames {
                let m = written + Int64(count)
                if k == 1 {
                    guard m < kept.end else { break }
                    for c in 0..<channels { out[count * channels + c] = kept.sample(m, channel: c) }
                } else {
                    guard Int64(k) * m + reach < kept.end else { break }
                    for c in 0..<channels {
                        out[count * channels + c] = decimator.value(
                            at: Double(Int64(k) * m), rate: Double(k)
                        ) { kept.sample($0, channel: c) }
                    }
                }
                count += 1
            }
            if count > 0 {
                try writer.write(out, frames: count)
                written += Int64(count)
                progress?(Double(written) / Double(frames))
            }
            kept.drop(before: Int64(k) * written - reach - 1)
        }
        return (latency, stream.next)
    }
}
