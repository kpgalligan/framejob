import Accelerate
import CoreMedia
import Foundation

/// A media's loudness cache as loaded (spec §11 AU-10, AU-63): one record per
/// 10 ms block of the media record, `width` Float32s each — mono `z, tp, h`,
/// stereo `zL, zR, zLR, tpL, tpR, hL, hR, hLR`. `z` is the MEAN of the
/// K-weighted samples squared over the block's frames (`zLR` the mean of
/// yL·yR), so a 400 ms gating block is the plain average of forty records at
/// any rate; `tp` is the block's true peak, linear: max(4× Annex 2
/// interpolation, |x|); `h` the mean of the raw samples through the
/// de-esser's default sidechain, a 6 kHz 24 dB/octave Butterworth high-pass,
/// squared (`hLR` the mean of the product), 0 where 6 kHz is at or above
/// 0.49·fs — what Enhance Voice's sibilant share reads.
struct MediaLoudness: Equatable {
    /// 1 or 2.
    let channels: Int
    /// Records: `⌈duration·100⌉` from the marker, `loadPeaks`' count.
    let count: Int
    /// `count × width` values, record-major.
    let records: [Float]

    var width: Int { channels == 1 ? 3 : 8 }

    /// Where a record's `h` values start: after `z, tp`, or after the five.
    var highOffset: Int { channels == 1 ? 2 : 5 }
}

extension MediaImporter {
    /// The loudness pass's accumulator: every sample buffer the reader yields,
    /// in order. A `PeakBuckets` is fed the same buffers and is the authority
    /// on validation, the failure latch, the frame count and `covers`, so a
    /// buffer the peaks cache refuses is refused here too and the two caches
    /// certify the same decode. Frames are placed by its rule verbatim: the
    /// PTS less the MP3 lead rounded to a frame once, frame f in block
    /// `⌊(startFrame + f)·100/rate⌋`. The K-weighting state and the true-peak
    /// FIR's 11-sample history run on across buffers (and across an edit gap,
    /// which reads as silence, as it plays); a frame outside `[0, count)` feeds
    /// the filters and lands in no record.
    struct LoudnessBlocks {
        private var peaks: PeakBuckets
        private let lead: CMTime
        private let count: Int
        private(set) var failed = false
        private(set) var channels: Int?
        private(set) var sampleRate: Double?
        private var stages: (LoudnessMeter.Biquad, LoudnessMeter.Biquad)?
        /// The high band's two sections (AU-63), nil where 6 kHz is at or
        /// above 0.49·fs.
        private var highStages: (LoudnessMeter.Biquad, LoudnessMeter.Biquad)?
        /// Per channel: `x1, x2, y1, y2` for each of the two sections.
        private var filterState: [[Double]] = []
        /// The same for the high band's sections.
        private var highState: [[Double]] = []
        /// Per channel: the last `peakTaps − 1` raw samples.
        private var history: [[Double]] = []
        /// Per block: Σ y² per channel, Σ yL·yR, frames, and the true peaks.
        private var sumL: [Double]
        private var sumR: [Double]
        private var sumLR: [Double]
        /// Per block: Σ x_hp² per channel and Σ xL_hp·xR_hp.
        private var highL: [Double]
        private var highR: [Double]
        private var highLR: [Double]
        private var frames: [Int]
        private var peakL: [Float]
        private var peakR: [Float]

        init(duration: Ticks, lead: CMTime = .zero) {
            peaks = PeakBuckets(duration: duration, lead: lead)
            self.lead = lead
            count = max(1, Int((Double(duration) / Double(ReelTime.perSecond)
                * Double(MediaImporter.peakBucketsPerSecond)).rounded(.up)))
            sumL = [Double](repeating: 0, count: count)
            sumR = sumL
            sumLR = sumL
            highL = sumL
            highR = sumL
            highLR = sumL
            frames = [Int](repeating: 0, count: count)
            peakL = [Float](repeating: 0, count: count)
            peakR = peakL
        }

        var acceptedFrames: Int { peaks.acceptedFrames }

        func covers(_ expectedRanges: [CMTimeRange]) -> Bool {
            !failed && peaks.covers(expectedRanges)
        }

        /// The `.bin`: headerless little-endian Float32 records.
        var data: Data {
            let stereo = channels == 2
            var values: [Float] = []
            values.reserveCapacity(count * (stereo ? 8 : 3))
            for b in 0..<count {
                let n = Double(max(frames[b], 1))
                if stereo {
                    values += [Float(sumL[b] / n), Float(sumR[b] / n), Float(sumLR[b] / n),
                               peakL[b], peakR[b], Float(highL[b] / n), Float(highR[b] / n),
                               Float(highLR[b] / n)]
                } else {
                    values += [Float(sumL[b] / n), peakL[b], Float(highL[b] / n)]
                }
            }
            return values.withUnsafeBufferPointer { Data(buffer: $0) }
        }

        /// A buffer the peaks rule refuses, one of more than two channels, or
        /// one whose channel count or rate differs from the first latches
        /// failure, and nothing of it lands.
        mutating func add(_ sample: CMSampleBuffer) -> Bool {
            guard !failed else { return false }
            guard peaks.add(sample) else { failed = true; return false }
            let count = CMSampleBufferGetNumSamples(sample)
            if count == 0 { return true }
            guard let format = CMSampleBufferGetFormatDescription(sample),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                let block = CMSampleBufferGetDataBuffer(sample)
            else { failed = true; return false }
            let width = Int(asbd.mChannelsPerFrame)
            let rate = asbd.mSampleRate
            if channels == nil {
                guard (1...2).contains(width) else { failed = true; return false }
                channels = width
                sampleRate = rate
                stages = KWeighting.coefficients(sampleRate: rate)
                highStages = Self.highBand(sampleRate: rate)
                filterState = Array(repeating: [Double](repeating: 0, count: 8), count: width)
                highState = filterState
                history = Array(
                    repeating: [Double](repeating: 0, count: LoudnessMeter.peakTaps - 1),
                    count: width)
            }
            guard width == channels, rate == sampleRate, let stages else {
                failed = true; return false
            }
            var samples = [Float](repeating: 0, count: count * width)
            let copied = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: count * width * 4, destination: base)
            }
            guard copied == noErr else { failed = true; return false }
            let stamp = CMSampleBufferGetPresentationTimeStamp(sample)
            let time = lead == .zero ? stamp : CMTimeSubtract(stamp, lead)
            let startFrame = (CMTimeGetSeconds(time) * rate).rounded()

            // Per channel: the true peak of each frame, the weighted run and
            // the high band.
            var weighted: [[Double]] = []
            var framePeaks: [[Double]] = []
            var high: [[Double]] = []
            for channel in 0..<width {
                let (run, peak, band) = process(samples, channel: channel, width: width,
                                                frames: count, stages: stages)
                weighted.append(run)
                framePeaks.append(peak)
                high.append(band)
            }
            // The blocks, grouped as `PeakBuckets` groups them.
            func blockOf(_ frame: Int) -> Double {
                floor((startFrame + Double(frame))
                      * Double(MediaImporter.peakBucketsPerSecond) / rate)
            }
            var frame = 0
            while frame < count {
                let blockDouble = blockOf(frame)
                var take = 1
                while frame + take < count, blockOf(frame + take) == blockDouble { take += 1 }
                if blockDouble >= 0, blockDouble < Double(self.count) {
                    accumulate(Int(blockDouble), from: frame, take: take,
                               weighted: weighted, framePeaks: framePeaks, high: high)
                }
                frame += take
            }
            return true
        }

        private mutating func accumulate(
            _ b: Int, from frame: Int, take: Int, weighted: [[Double]], framePeaks: [[Double]],
            high: [[Double]]
        ) {
            let n = vDSP_Length(take)
            var energy = 0.0
            var peak = 0.0
            weighted[0].withUnsafeBufferPointer { vDSP_svesqD($0.baseAddress! + frame, 1, &energy, n) }
            framePeaks[0].withUnsafeBufferPointer { vDSP_maxvD($0.baseAddress! + frame, 1, &peak, n) }
            sumL[b] += energy
            peakL[b] = max(peakL[b], Float(peak))
            var band = 0.0
            high[0].withUnsafeBufferPointer { vDSP_svesqD($0.baseAddress! + frame, 1, &band, n) }
            highL[b] += band
            if weighted.count == 2 {
                var cross = 0.0
                weighted[1].withUnsafeBufferPointer { vDSP_svesqD($0.baseAddress! + frame, 1, &energy, n) }
                framePeaks[1].withUnsafeBufferPointer { vDSP_maxvD($0.baseAddress! + frame, 1, &peak, n) }
                weighted[0].withUnsafeBufferPointer { l in
                    weighted[1].withUnsafeBufferPointer { r in
                        vDSP_dotprD(l.baseAddress! + frame, 1, r.baseAddress! + frame, 1, &cross, n)
                    }
                }
                sumR[b] += energy
                sumLR[b] += cross
                peakR[b] = max(peakR[b], Float(peak))
                high[1].withUnsafeBufferPointer { vDSP_svesqD($0.baseAddress! + frame, 1, &band, n) }
                high[0].withUnsafeBufferPointer { l in
                    high[1].withUnsafeBufferPointer { r in
                        vDSP_dotprD(l.baseAddress! + frame, 1, r.baseAddress! + frame, 1, &cross, n)
                    }
                }
                highR[b] += band
                highLR[b] += cross
            }
            frames[b] += take
        }

        /// One channel's run: each frame's true peak, max(|x|, the four
        /// interpolated phases' magnitudes at it) — `LoudnessMeter.process`'s
        /// FIR in Double, its history carried — then the K-weighted samples,
        /// and the raw samples through the high band (zeros without one).
        private mutating func process(
            _ samples: [Float], channel: Int, width: Int, frames count: Int,
            stages: (LoudnessMeter.Biquad, LoudnessMeter.Biquad)
        ) -> ([Double], [Double], [Double]) {
            let taps = LoudnessMeter.peakTaps
            let held = taps - 1
            var buffer = history[channel] + [Double](repeating: 0, count: count)
            samples.withUnsafeBufferPointer { src in
                buffer.withUnsafeMutableBufferPointer { dst in
                    vDSP_vspdp(src.baseAddress! + channel, vDSP_Stride(width),
                               dst.baseAddress! + held, 1, vDSP_Length(count))
                }
            }
            var peak = [Double](repeating: 0, count: count)
            buffer.withUnsafeBufferPointer { raw in
                vDSP_vabsD(raw.baseAddress! + held, 1, &peak, 1, vDSP_Length(count))
            }
            var phase = [Double](repeating: 0, count: count)
            for filter in LoudnessMeter.peakFilter {
                let reversed = Array(filter.reversed())
                vDSP_convD(buffer, 1, reversed, 1, &phase, 1, vDSP_Length(count), vDSP_Length(taps))
                vDSP_vabsD(phase, 1, &phase, 1, vDSP_Length(count))
                vDSP_vmaxD(phase, 1, peak, 1, &peak, 1, vDSP_Length(count))
            }
            history[channel] = Array(buffer[count..<(count + held)])

            let raw = Array(buffer[held...])
            var run = raw
            Self.cascade(&run, stages, state: &filterState[channel])
            var band = [Double](repeating: 0, count: count)
            if let highStages {
                band = raw
                Self.cascade(&band, highStages, state: &highState[channel])
            }
            return (run, peak, band)
        }

        /// Two sections in direct form I over `run` in place, `state` their
        /// `x1, x2, y1, y2` each, carried.
        private static func cascade(
            _ run: inout [Double], _ stages: (LoudnessMeter.Biquad, LoudnessMeter.Biquad),
            state: inout [Double]
        ) {
            for (index, section) in [stages.0, stages.1].enumerated() {
                var x1 = state[index * 4], x2 = state[index * 4 + 1]
                var y1 = state[index * 4 + 2], y2 = state[index * 4 + 3]
                for n in 0..<run.count {
                    let x = run[n]
                    let y = section.b0 * x + section.b1 * x1 + section.b2 * x2
                        - section.a1 * y1 - section.a2 * y2
                    x2 = x1
                    x1 = x
                    y2 = y1
                    y1 = y
                    run[n] = y
                }
                state[index * 4] = x1
                state[index * 4 + 1] = x2
                state[index * 4 + 2] = y1
                state[index * 4 + 3] = y2
            }
        }

        /// The high band's sections (AU-63): the de-esser's sidechain at its
        /// default 6 kHz, two Butterworth RBJ high-passes; nil at or above
        /// 0.49·fs, where no section is designed.
        static func highBand(sampleRate: Double) -> (LoudnessMeter.Biquad, LoudnessMeter.Biquad)? {
            let frequency = DeEsserProps().frequency
            guard sampleRate > 0, frequency < 0.49 * sampleRate else { return nil }
            func section(_ index: Int) -> LoudnessMeter.Biquad {
                let c = AudioEQDesign.highPass(
                    frequency, q: AudioEQDesign.butterworthQ(sections: 2, index: index),
                    sampleRate: sampleRate)
                return LoudnessMeter.Biquad(b0: c.b0, b1: c.b1, b2: c.b2, a1: c.a1, a2: c.a2)
            }
            return (section(0), section(1))
        }
    }
}
