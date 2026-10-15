import Foundation

/// Synchronize Audio's drift arithmetic (road map "audio-sync", AS-2; spec
/// §11 SY-6, SY-7): moved out of `AudioSyncMatch.swift`, where AS-1 measured
/// drift from two windows (SY-5), and rewritten as a line.
///
/// It is pure, as the match is: onset arrays in, a line or a sentence out.
///
/// **Drift is a least-squares line through many windows** (SY-7). Over the
/// overlap O (anchor buckets both clips play at once), windows of
/// `driftWindowBuckets` start at O's start every `max(500, ⌈(|O| − 2000)/63⌉)`
/// buckets, plus one flush with O's end — at most `driftMaximumWindows`. Each
/// is searched ±`driftSearchBuckets` around the coarse lag with the match's
/// normalisation, refined parabolically, and kept when its peak reaches
/// `minimumCorrelation`. The kept lags are fitted against each window's
/// centre by ordinary least squares: the slope ρ is the drift (`lag(a) = c +
/// ρ·a`), c the intercept at anchor bucket 0. Its uncertainty is the slope's
/// standard error, widened by √(2000 / step) because windows that share
/// buckets are not the independent data the formula counts them as.
///
/// **Resampling** (SY-6) puts a clip that plays at a near-×1 rate on its
/// TIMELINE grid: bucket k of the answer is source bucket k·speed, so a
/// corrected mover's sound is compared where it now plays, not where its
/// file holds it. At ×1 it is the onsets themselves, so AS-1's arithmetic is
/// unchanged for every clip that plays at ×1.
extension AudioSyncMatch {

    // MARK: - The numbers (SY-5, SY-7)

    /// 20 s: each drift window.
    static let driftWindowBuckets = 2000
    /// 60 s: the least overlap drift is measured over (SY-5).
    static let driftMinimumOverlapBuckets = 6000
    /// ±1 s around the coarse lag, each drift window's search.
    static let driftSearchBuckets = 100
    /// 5 s: the closest two windows' starts may be.
    static let driftWindowStepBuckets = 500
    /// The most windows one overlap is cut into, the flush one included.
    static let driftMaximumWindows = 64
    /// The fewest matched windows a line is fitted through.
    static let driftMinimumWindows = 3

    // MARK: - Drift (SY-7)

    struct Drift: Equatable {
        /// The mover's clock against the anchor's, in parts per million.
        let ppm: Double
        /// How far the two drift apart over the overlap, in milliseconds.
        let milliseconds: Double
        /// ρ: the fitted line's slope, the lag's change per anchor bucket.
        let rate: Double
        /// c: the fitted lag at anchor bucket 0, in buckets.
        let intercept: Double
        /// The slope's standard error, widened for the windows' overlap, as
        /// milliseconds over the overlap.
        let errorMilliseconds: Double
        /// How many windows matched and were fitted.
        let windows: Int
    }

    enum DriftAnswer: Equatable {
        case measured(Drift)
        case notMeasured(String)
    }

    /// The drift between two files already matched at `lag`, over `overlap`
    /// — the anchor buckets both play at once.
    static func drift(anchor: [Float], mover: [Float], lag: Double, overlap: Range<Int>)
        -> DriftAnswer {
        guard overlap.count >= driftMinimumOverlapBuckets else {
            return .notMeasured(
                "the two play together for under \(driftMinimumOverlapBuckets / 100) s, too "
                    + "short to measure drift.")
        }
        let length = overlap.count
        let reach = length - driftWindowBuckets
        let gaps = driftMaximumWindows - 1
        let step = max(driftWindowStepBuckets, (reach + gaps - 1) / gaps)
        let last = overlap.upperBound - driftWindowBuckets
        var starts = Array(stride(from: overlap.lowerBound, through: last, by: step))
        if starts.last != last { starts.append(last) }

        var centres: [Double] = []
        var lags: [Double] = []
        for start in starts {
            guard let found = windowLag(
                anchor, mover, start..<(start + driftWindowBuckets), around: lag)
            else { continue }
            centres.append(Double(start) + Double(driftWindowBuckets) / 2)
            lags.append(found)
        }
        guard centres.count >= driftMinimumWindows else {
            return .notMeasured(
                "only \(centres.count) of the overlap's windows matched; drift needs at least "
                    + "\(driftMinimumWindows).")
        }
        guard let low = centres.min(), let high = centres.max(),
              high - low >= Double(reach) / 2
        else {
            return .notMeasured(
                "the windows that matched cover too little of the overlap to measure drift.")
        }

        let count = Double(centres.count)
        let meanX = centres.reduce(0, +) / count
        let meanY = lags.reduce(0, +) / count
        var sxx = 0.0
        var sxy = 0.0
        for (x, y) in zip(centres, lags) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        let rate = sxy / sxx
        let intercept = meanY - rate * meanX
        var squares = 0.0
        for (x, y) in zip(centres, lags) {
            let residual = y - intercept - rate * x
            squares += residual * residual
        }
        let standardError = (squares / (count - 2) / sxx).squareRoot()
        let widened = step < driftWindowBuckets
            ? (Double(driftWindowBuckets) / Double(step)).squareRoot() : 1
        return .measured(
            Drift(
                ppm: rate * 1e6, milliseconds: rate * Double(length) * 10, rate: rate,
                intercept: intercept,
                errorMilliseconds: standardError * widened * Double(length) * 10,
                windows: centres.count))
    }

    /// One drift window's refined lag, searched over `lag ± driftSearchBuckets`
    /// with the match's normalisation; nil when its peak is under
    /// `minimumCorrelation`.
    private static func windowLag(
        _ anchor: [Float], _ mover: [Float], _ window: Range<Int>, around lag: Double
    ) -> Double? {
        let centre = Int(lag.rounded())
        let span = (centre - driftSearchBuckets)...(centre + driftSearchBuckets)
        var scores: [Double?] = []
        for candidate in span {
            var cross = 0.0
            var ex = 0.0
            var ey = 0.0
            var count = 0
            for a in window where a >= 0 && a < anchor.count {
                let m = a - candidate
                guard m >= 0, m < mover.count else { continue }
                let x = Double(anchor[a])
                let y = Double(mover[m])
                cross += x * y
                ex += x * x
                ey += y * y
                count += 1
            }
            guard count > 0 else {
                scores.append(nil)
                continue
            }
            let denominator = (ex * ey).squareRoot()
            scores.append(denominator > 0 ? cross / denominator : 0)
        }
        var best: Int?
        for index in scores.indices {
            guard let score = scores[index] else { continue }
            if best == nil || score > (scores[best!] ?? -.infinity) { best = index }
        }
        guard let peak = best, let peakScore = scores[peak], peakScore >= minimumCorrelation
        else { return nil }
        let offset = refine(
            left: peak > 0 ? scores[peak - 1] : nil, centre: peakScore,
            right: peak + 1 < scores.count ? scores[peak + 1] : nil)
        return Double(span.lowerBound + peak) + offset
    }

    // MARK: - Resampling (SY-6)

    /// `onsets` on the timeline grid of a clip playing at `speed`: bucket k
    /// is source bucket k·speed, interpolated linearly between its two
    /// neighbours. The onsets themselves at ×1 (or a degenerate speed).
    static func resampled(_ onsets: [Float], speed: Double) -> [Float] {
        guard speed != 1, speed.isFinite, speed > 0, onsets.count > 1 else { return onsets }
        let lastIndex = onsets.count - 1
        let count = Int((Double(lastIndex) / speed).rounded(.down)) + 1
        return (0..<count).map { k in
            let x = Double(k) * speed
            let index = min(Int(x), lastIndex)
            guard index < lastIndex else { return onsets[lastIndex] }
            let fraction = x - Double(index)
            return Float(
                Double(onsets[index]) * (1 - fraction) + Double(onsets[index + 1]) * fraction)
        }
    }
}
