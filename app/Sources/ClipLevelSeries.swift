import Foundation

/// A clip's sound on a 10 ms grid of PROJECT time (road map "creator-jobs"
/// SW2a, spec §11 SW-21): what Switch by Speaker asks of each microphone.
/// Step k is `[from + k·step, from + (k+1)·step)`, `step` the peaks grid
/// (`MediaPeaks.bucketTicks`).
///
/// - `energies`: the loudness cache's K-weighted mean square over each
///   step's source window, through the clip's `ChannelMatrix` (AU-35) —
///   `ClipLoudness.energy`, the reading's own arithmetic — taken through the
///   audio segment covering the step's midpoint (the later-starting one when
///   two do), mapped by `MediaPeaks.sourceTick` and, reversed, by
///   `ReverseMirror`. A step no segment covers is 0 and not covered.
/// - `levels`: 10·log10 of the mean energy over the CENTRED window
///   k − `before` … k + `after`, clipped to the series; −∞ when that mean is 0.
/// - `voice`: the speech cache's probability for the 32 ms chunk under the
///   step's midpoint, mirrored when reversed; 0 outside the cache or where
///   nothing covers.
///
/// Pure: it reads no document, file or clock (SW-25).
enum ClipLevelSeries {
    /// The level's window: steps k − 5 … k + 4, 100 ms centred on the step.
    static let before = 5, after = 4

    static var stepTicks: Ticks { MediaPeaks.bucketTicks }

    /// The index of the segment covering `tick`, the later-starting one when
    /// two do; nil when none does.
    static func covering(_ segments: [PlanSegment], at tick: Ticks) -> Int? {
        var found: Int?
        for (index, segment) in segments.enumerated()
        where segment.duration > 0 && segment.start <= tick && tick < segment.start + segment.duration {
            if let current = found, segments[current].start > segment.start { continue }
            found = index
        }
        return found
    }

    static func energies(
        _ cache: MediaLoudness, segments: [PlanSegment], pivots: [Ticks?],
        matrix: ClipLoudness.ChannelMatrix, from: Ticks, count: Int
    ) -> (energy: [Double], covered: [Bool]) {
        let step = stepTicks
        var energy = [Double](repeating: 0, count: max(0, count))
        var covered = [Bool](repeating: false, count: max(0, count))
        guard count > 0, step > 0 else { return (energy, covered) }
        for k in 0..<count {
            let a = from + Ticks(k) * step
            guard let index = covering(segments, at: a + step / 2) else { continue }
            let segment = segments[index]
            var low = MediaPeaks.sourceTick(segment, at: a)
            var high = MediaPeaks.sourceTick(segment, at: a + step)
            if index < pivots.count, let pivot = pivots[index] {
                low = ReverseMirror.mirrored(low, about: pivot)
                high = ReverseMirror.mirrored(high, about: pivot)
            }
            energy[k] = ClipLoudness.energy(cache, from: min(low, high), to: max(low, high), matrix)
                .energy
            covered[k] = true
        }
        return (energy, covered)
    }

    static func levels(_ energy: [Double]) -> [Double] {
        let count = energy.count
        var out = [Double](repeating: -.infinity, count: count)
        for k in 0..<count {
            let low = max(0, k - before)
            let high = min(count - 1, k + after)
            var sum = 0.0
            for j in low...high { sum += energy[j] }
            let mean = sum / Double(high - low + 1)
            out[k] = mean > 0 ? 10 * log10(mean) : -.infinity
        }
        return out
    }

    static func voice(
        _ p: [Float], segments: [PlanSegment], pivots: [Ticks?], from: Ticks, count: Int
    ) -> [Float] {
        let step = stepTicks
        var out = [Float](repeating: 0, count: max(0, count))
        guard count > 0, step > 0, !p.isEmpty else { return out }
        for k in 0..<count {
            let middle = from + Ticks(k) * step + step / 2
            guard let index = covering(segments, at: middle) else { continue }
            var source = MediaPeaks.sourceTick(segments[index], at: middle)
            if index < pivots.count, let pivot = pivots[index] {
                source = ReverseMirror.mirrored(source, about: pivot)
            }
            let chunk = MediaPeaks.bucketIndex(source, bucket: MediaSpeech.chunkTicks)
            if chunk >= 0, chunk < p.count { out[k] = p[chunk] }
        }
        return out
    }
}
