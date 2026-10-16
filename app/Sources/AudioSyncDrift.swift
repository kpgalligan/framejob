import Foundation

/// Synchronize Audio's drift arithmetic (road maps "audio-sync", AS-2, and
/// "audio-sync-2", AS-4; spec §11 SY-6, SY-7, SY-21): moved out of
/// `AudioSyncMatch.swift`, where AS-1 measured drift from two windows (SY-5),
/// rewritten as a line in AS-2, and moved off the waveform's onsets onto the
/// features and the samples in AS-4.
///
/// It is pure, as the match is: features, masks and samples in, a line or a
/// sentence out.
///
/// **Drift is a least-squares line through many windows** (SY-7, SY-21). Over
/// the overlap O (anchor timeline frames both clips play at once), windows
/// of `driftWindowFrames` start at O's start every `max(312, ⌈(|O| −
/// 1250)/63⌉)` frames, plus one flush with O's end — at most
/// `driftMaximumWindows`. **Stage 1:** each is searched on the FEATURES by
/// `search` (SY-12, SY-17), its near placement within `driftSearchFrames`
/// of the coarse lag against a mover slice `driftSearchFrames` wider at each
/// end (so every searched lag overlaps the whole window), and kept when that
/// peak's z reaches `driftWindowZ`. The kept lags, in samples, pass the
/// robust filter (`inliers`: Theil–Sen, then MAD) and are fitted against
/// each window's centre by ordinary least squares — the line F. **Stage
/// 2:** each kept window is refined by PHAT along F (`AudioSyncPHAT.refine`,
/// SY-20); when enough of them are clear, and spread wide enough once
/// filtered alike, their points are refitted. The
/// slope ρ is the drift (`lag(a) = c + ρ·a`, a an anchor timeline sample), c
/// the intercept in samples. Its uncertainty is the slope's standard error,
/// widened by √(1250 / step) because windows that share frames are not the
/// independent data the formula counts them as.
extension AudioSyncMatch {

    // MARK: - The numbers (SY-5, SY-21)

    /// 20 s: each drift window.
    static let driftWindowFrames = 1250
    /// 60 s: the least overlap drift is measured over (SY-5).
    static let driftMinimumOverlapFrames = 3750
    /// ±0.992 s around the coarse lag, each drift window's search.
    static let driftSearchFrames = 62
    /// 4.992 s: the closest two windows' starts may be.
    static let driftWindowStepFrames = 312
    /// The most windows one overlap is cut into, the flush one included.
    static let driftMaximumWindows = 64
    /// The fewest matched windows a line is fitted through.
    static let driftMinimumWindows = 3
    /// The z a window's near placement needs to be kept (initial; SY-21's
    /// calibration rule).
    static let driftWindowZ = 6.0
    /// k: a point is an inlier when its residual about the Theil–Sen line is
    /// at most k·1.4826·MAD (SY-21; fixed, never calibrated).
    static let driftInlierScale = 3.0
    /// The inlier threshold's floor, in samples.
    static let driftInlierFloorSamples = 1.0

    // MARK: - Drift (SY-21)

    /// Which points the line was fitted through.
    enum DriftSource: String {
        case features, phat
    }

    struct Drift: Equatable {
        /// The mover's clock against the anchor's, in parts per million.
        let ppm: Double
        /// How far the two drift apart over the overlap, in milliseconds.
        let milliseconds: Double
        /// ρ: the fitted line's slope, the lag's change per anchor sample.
        let rate: Double
        /// c: the fitted lag at anchor timeline sample 0, in samples.
        let intercept: Double
        /// The slope's standard error, widened for the windows' overlap, as
        /// milliseconds over the overlap.
        let errorMilliseconds: Double
        /// How many windows matched and were fitted.
        let windows: Int
        /// Stage 1's features, or stage 2's PHAT points.
        var on: DriftSource = .features
    }

    enum DriftAnswer: Equatable {
        case measured(Drift)
        case notMeasured(String)
    }

    /// The drift between two clips already matched at `lag` (frames), over
    /// `overlap` — the anchor timeline frames both play at once. Features and
    /// masks are on the timeline grid; samples on the SOURCE grid, read at
    /// their speeds. `fft` is the caller's shared setup (SY-22), lent to
    /// every window's refinement.
    static func drift(
        anchor: [Float], mover: [Float], anchorSpeech: [Bool]?, moverSpeech: [Bool]?,
        anchorSamples: [Int16], moverSamples: [Int16], anchorSpeed: Double,
        moverSpeed: Double, lag: Double, overlap: Range<Int>, fft: AudioSyncPHAT.FFT? = nil
    ) -> DriftAnswer {
        guard overlap.count >= driftMinimumOverlapFrames else {
            let seconds = Ticks(driftMinimumOverlapFrames) * SyncFeatures.frameTicks
                / ReelTime.perSecond
            return .notMeasured(
                "the two play together for under \(seconds) s, too short to measure drift.")
        }
        let width = SyncFeatures.coefficients
        let hop = SyncFeatures.hop
        let anchorCount = anchor.count / width
        let moverCount = mover.count / width
        let length = overlap.count
        let reach = length - driftWindowFrames
        let gaps = driftMaximumWindows - 1
        let step = max(driftWindowStepFrames, (reach + gaps - 1) / gaps)
        let last = overlap.upperBound - driftWindowFrames
        var starts = Array(stride(from: overlap.lowerBound, through: last, by: step))
        if starts.last != last { starts.append(last) }

        func frames(_ values: [Float], _ range: Range<Int>) -> [Float] {
            Array(values[(range.lowerBound * width)..<(range.upperBound * width)])
        }
        func mask(_ values: [Bool]?, _ range: Range<Int>) -> [Bool]? {
            values.map { mask in range.map { $0 < mask.count && mask[$0] } }
        }

        // Stage 1: each window on the features.
        let shift = Int(lag.rounded())
        var kept: [Int] = []
        var centres: [Double] = []
        var lags: [Double] = []
        for start in starts {
            let anchorEnd = max(0, min(anchorCount, start + driftWindowFrames))
            let a = min(max(0, start), anchorEnd)..<anchorEnd
            let moverEnd = max(
                0, min(moverCount, start - shift + driftWindowFrames + driftSearchFrames))
            let m = min(max(0, start - shift - driftSearchFrames), moverEnd)..<moverEnd
            guard a.count > 0, m.count > 0,
                  let found = search(
                    anchor: frames(anchor, a), mover: frames(mover, m),
                    anchorSpeech: mask(anchorSpeech, a), moverSpeech: mask(moverSpeech, m),
                    offset: a.lowerBound - m.lowerBound, placementLag: lag,
                    radius: driftSearchFrames)?.nearPlacement,
                  found.z >= driftWindowZ
            else { continue }
            kept.append(start)
            centres.append((Double(start) + Double(driftWindowFrames) / 2) * Double(hop))
            lags.append(found.lag * Double(hop))
        }
        let firstKept = survivors(centres, lags)
        kept = zip(kept, firstKept).filter { $0.1 }.map { $0.0 }
        centres = zip(centres, firstKept).filter { $0.1 }.map { $0.0 }
        lags = zip(lags, firstKept).filter { $0.1 }.map { $0.0 }
        guard centres.count >= driftMinimumWindows else {
            return .notMeasured(
                "only \(centres.count) of the overlap's windows matched; drift needs at least "
                    + "\(driftMinimumWindows).")
        }
        let span = Double(reach * hop) / 2
        guard let low = centres.min(), let high = centres.max(), high - low >= span
        else {
            return .notMeasured(
                "the windows that matched cover too little of the overlap to measure drift.")
        }
        let features = line(centres, lags, length: length, step: step, on: .features)

        // Stage 2: each kept window refined by PHAT along F.
        let along = AudioSyncPHAT.Line(intercept: features.intercept, rate: features.rate)
        var phatCentres: [Double] = []
        var phatLags: [Double] = []
        for (start, centre) in zip(kept, centres) {
            guard let refined = AudioSyncPHAT.refine(
                anchor: anchorSamples, anchorSpeed: anchorSpeed, mover: moverSamples,
                moverSpeed: moverSpeed, line: along,
                region: (start * hop)..<((start + driftWindowFrames) * hop), fft: fft),
                refined.clear
            else { continue }
            phatCentres.append(centre)
            phatLags.append(features.intercept + features.rate * centre + refined.shift)
        }
        let clearKept = survivors(phatCentres, phatLags)
        phatCentres = zip(phatCentres, clearKept).filter { $0.1 }.map { $0.0 }
        phatLags = zip(phatLags, clearKept).filter { $0.1 }.map { $0.0 }
        if phatCentres.count >= driftMinimumWindows,
           let low = phatCentres.min(), let high = phatCentres.max(), high - low >= span {
            return .measured(line(phatCentres, phatLags, length: length, step: step, on: .phat))
        }
        return .measured(features)
    }

    /// SY-21's robust filter where there are at least `driftMinimumWindows`
    /// points to filter; with fewer, every point goes on.
    private static func survivors(_ xs: [Double], _ ys: [Double]) -> [Bool] {
        xs.count >= driftMinimumWindows ? inliers(xs, ys) : [Bool](repeating: true, count: xs.count)
    }

    /// Which points are inliers about the Theil–Sen line: its slope b the
    /// median of `(yⱼ − yᵢ)/(xⱼ − xᵢ)` over every pair with xⱼ ≠ xᵢ, its
    /// intercept the median of `y − b·x`; a point is in when its residual is
    /// at most `max(driftInlierScale·1.4826·MAD, driftInlierFloorSamples)`,
    /// MAD the median absolute residual. Every point with fewer than 2, or no
    /// pair to take a slope of.
    private static func inliers(_ xs: [Double], _ ys: [Double]) -> [Bool] {
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            let middle = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        }
        var slopes: [Double] = []
        for i in xs.indices {
            for j in xs.indices where j > i && xs[j] != xs[i] {
                slopes.append((ys[j] - ys[i]) / (xs[j] - xs[i]))
            }
        }
        guard xs.count >= 2, !slopes.isEmpty else { return [Bool](repeating: true, count: xs.count) }
        let b = median(slopes)
        let a = median(zip(xs, ys).map { $1 - b * $0 })
        let r = zip(xs, ys).map { $1 - a - b * $0 }
        let threshold = max(
            driftInlierScale * 1.4826 * median(r.map { abs($0) }), driftInlierFloorSamples)
        return r.map { abs($0) <= threshold }
    }

    /// The ordinary least-squares line through (`xs`, `ys`), in samples, as a
    /// `Drift` over an overlap of `length` frames cut every `step` frames.
    private static func line(
        _ xs: [Double], _ ys: [Double], length: Int, step: Int, on source: DriftSource
    ) -> Drift {
        let count = Double(xs.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        var sxx = 0.0
        var sxy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        let rate = sxy / sxx
        let intercept = meanY - rate * meanX
        var squares = 0.0
        for (x, y) in zip(xs, ys) {
            let residual = y - intercept - rate * x
            squares += residual * residual
        }
        let standardError = (squares / (count - 2) / sxx).squareRoot()
        let widened = step < driftWindowFrames
            ? (Double(driftWindowFrames) / Double(step)).squareRoot() : 1
        // ρ's milliseconds over the overlap: |O|·128 samples at 8 samples a ms.
        let overlapMilliseconds = Double(length * SyncFeatures.hop)
            / (Double(SyncFeatures.sampleRate) / 1000)
        return Drift(
            ppm: rate * 1e6, milliseconds: rate * overlapMilliseconds, rate: rate,
            intercept: intercept, errorMilliseconds: standardError * widened * overlapMilliseconds,
            windows: xs.count, on: source)
    }
}
