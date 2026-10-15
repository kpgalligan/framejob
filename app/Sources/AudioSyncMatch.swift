import Accelerate
import Foundation

/// Synchronize Audio's signal arithmetic (road map "audio-sync", AS-1; spec
/// §11 SY-3, SY-5): two cached waveforms in, a lag and a confidence out.
///
/// It is pure — no AppKit, no document, no disk. `AudioSync.read` hands it
/// the `cache/peaks/<media id>.bin` floats of each file (one bucket per
/// 1/100 s of SOURCE time, `MediaPeaks`'s grid), and `AudioSync.plan` turns
/// what it answers into ops or a refusal.
///
/// **What it compares is ONSETS, not levels.** Two recordings of one event
/// differ in gain, microphone, room and noise floor, so their peak envelopes
/// differ by far more than a constant; what they share is WHEN the sound
/// rises. Each bucket is taken to decibels (`e = 20·log10(max(p, 1e-5))`),
/// the onset is the rise from the bucket before (`max(0, e[n] − e[n−1])`,
/// 0 for the first), and the mean is taken off so a constant level
/// correlates with nothing.
///
/// **The match is a full normalised cross-correlation** over every lag at
/// which the two files overlap by at least `minimumOverlapBuckets` (or the
/// shorter file, when it is shorter): `c[L] = Σ x[m+L]·y[m]` by zero-padded
/// FFT, each lag divided by the energies of the two stretches that actually
/// overlap there (prefix sums of squares), so a lag that overlaps a quiet
/// stretch is not favoured or penalised for its length. The peak is refined
/// parabolically, clamped to half a bucket. Its CONFIDENCE is the peak
/// against the best lag more than `exclusionBuckets` away from it (SY-3): a
/// unique peak stands far above every other lag, an unrelated pair's best
/// lag does not.
///
/// **Drift is measured, not corrected** (SY-5): the same search over two
/// windows at the ends of the overlap, the lag's change across them divided
/// by their distance apart. AS-1 reports it; AS-2 corrects it.
enum AudioSyncMatch {

    // MARK: - The numbers (SY-3, SY-5)

    /// The lowest normalised correlation a match may have.
    static let minimumCorrelation = 0.25
    /// How far the peak must stand above the runner-up, as a ratio.
    static let minimumPeakRatio = 1.5
    /// ±0.5 s around the peak are kept out of the runner-up: the peak's own
    /// shoulders are not a second candidate.
    static let exclusionBuckets = 50
    /// 10 s, or the shorter file when it is shorter: a lag that overlaps
    /// less is not scored at all.
    static let minimumOverlapBuckets = 1000
    /// 2 s: a file shorter than this is too short to match.
    static let minimumFileBuckets = 200
    /// 20 s: each of drift's two windows.
    static let driftWindowBuckets = 2000
    /// 60 s: the least overlap drift is measured over (SY-5).
    static let driftMinimumOverlapBuckets = 6000
    /// ±1 s around the coarse lag, each drift window's search.
    static let driftSearchBuckets = 100

    // MARK: - Onsets

    /// The mean-free onset envelope of a peaks array.
    static func onsets(_ peaks: [Float]) -> [Float] {
        guard !peaks.isEmpty else { return [] }
        var result = [Float](repeating: 0, count: peaks.count)
        var previous = 20 * log10(max(Double(peaks[0]), 1e-5))
        var sum = 0.0
        for index in 1..<peaks.count {
            let level = 20 * log10(max(Double(peaks[index]), 1e-5))
            let rise = max(0, level - previous)
            result[index] = Float(rise)
            sum += rise
            previous = level
        }
        let mean = Float(sum / Double(peaks.count))
        for index in result.indices { result[index] -= mean }
        return result
    }

    // MARK: - Matching

    /// One match: where the mover's sound sits in the anchor's file, and how
    /// sure the arithmetic is of it.
    struct Match: Equatable {
        /// Anchor bucket − mover bucket of the same sound, refined.
        let lag: Double
        /// The normalised correlation at the peak.
        let correlation: Double
        /// The best normalised correlation more than `exclusionBuckets` from
        /// the peak; nil when no scored lag lies that far out.
        let runnerUp: Double?

        /// `correlation / max(runnerUp ?? 0, 0)`; +∞ when that floor is 0.
        var ratio: Double {
            let floor = max(runnerUp ?? 0, 0)
            return floor > 0 ? correlation / floor : .infinity
        }

        /// Confident when there was a runner-up to beat, the peak is high
        /// enough, and it stands far enough above the runner-up (SY-3).
        var isConfident: Bool {
            runnerUp != nil && correlation >= AudioSyncMatch.minimumCorrelation
                && ratio >= AudioSyncMatch.minimumPeakRatio
        }
    }

    /// The lag at which `mover`'s onsets best line up with `anchor`'s; nil
    /// when either has no onset energy (a silent or constant file).
    static func match(anchor: [Float], mover: [Float]) -> Match? {
        let na = anchor.count
        let nb = mover.count
        guard na > 0, nb > 0, energy(anchor) > 0, energy(mover) > 0 else { return nil }
        let raw = crossCorrelation(anchor, mover)
        let squaresA = prefixSquares(anchor)
        let squaresB = prefixSquares(mover)
        let needed = min(minimumOverlapBuckets, min(na, nb))

        // Index i holds lag L = i − (nb − 1).
        let lags = na + nb - 1
        var scores = [Double?](repeating: nil, count: lags)
        for index in 0..<lags {
            let lag = index - (nb - 1)
            let lower = max(0, -lag)
            let upper = min(nb, na - lag)
            guard upper - lower >= needed else { continue }
            let ex = squaresA[upper + lag] - squaresA[lower + lag]
            let ey = squaresB[upper] - squaresB[lower]
            let denominator = (ex * ey).squareRoot()
            scores[index] = denominator > 0 ? raw[index] / denominator : 0
        }

        var best: Int?
        for index in 0..<lags {
            guard let score = scores[index] else { continue }
            if best == nil || score > (scores[best!] ?? -.infinity) { best = index }
        }
        guard let peak = best, let peakScore = scores[peak] else { return nil }

        var runnerUp: Double?
        for index in 0..<lags where abs(index - peak) > exclusionBuckets {
            guard let score = scores[index] else { continue }
            runnerUp = max(runnerUp ?? -.infinity, score)
        }

        let offset = refine(
            left: peak > 0 ? scores[peak - 1] : nil, centre: peakScore,
            right: peak + 1 < lags ? scores[peak + 1] : nil)
        return Match(
            lag: Double(peak - (nb - 1)) + offset, correlation: peakScore, runnerUp: runnerUp)
    }

    // MARK: - Drift (SY-5)

    struct Drift: Equatable {
        /// The mover's clock against the anchor's, in parts per million.
        let ppm: Double
        /// How far the two drift apart over the overlap, in milliseconds.
        let milliseconds: Double
    }

    enum DriftAnswer: Equatable {
        case measured(Drift)
        case notMeasured(String)
    }

    /// The drift between two files already matched at `lag`, over `overlap`
    /// — the anchor-source buckets both play at once.
    static func drift(anchor: [Float], mover: [Float], lag: Double, overlap: Range<Int>)
        -> DriftAnswer {
        guard overlap.count >= driftMinimumOverlapBuckets else {
            return .notMeasured(
                "the two play together for under \(driftMinimumOverlapBuckets / 100) s, too "
                    + "short to measure drift.")
        }
        let first = overlap.lowerBound..<(overlap.lowerBound + driftWindowBuckets)
        let last = (overlap.upperBound - driftWindowBuckets)..<overlap.upperBound
        guard let early = windowLag(anchor, mover, first, around: lag),
              let late = windowLag(anchor, mover, last, around: lag)
        else {
            return .notMeasured(
                "the sound at one end of the overlap did not match clearly enough to measure "
                    + "drift.")
        }
        let distance = Double(last.lowerBound - first.lowerBound)
        let rate = (late - early) / distance
        return .measured(Drift(ppm: rate * 1e6, milliseconds: rate * Double(overlap.count) * 10))
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

    // MARK: - Arithmetic

    /// The vertex of the parabola through three neighbouring scores, as an
    /// offset from the centre, clamped to ±0.5; 0 without both neighbours or
    /// when the three do not bend down.
    static func refine(left: Double?, centre: Double, right: Double?) -> Double {
        guard let left = left, let right = right else { return 0 }
        let bend = left - 2 * centre + right
        guard bend < 0 else { return 0 }
        let offset = 0.5 * (left - right) / bend
        return min(0.5, max(-0.5, offset))
    }

    private static func energy(_ values: [Float]) -> Double {
        values.reduce(0) { $0 + Double($1) * Double($1) }
    }

    /// `squares[k]` = Σ values[0..<k]².
    private static func prefixSquares(_ values: [Float]) -> [Double] {
        var squares = [Double](repeating: 0, count: values.count + 1)
        for index in values.indices {
            squares[index + 1] = squares[index] + Double(values[index]) * Double(values[index])
        }
        return squares
    }

    /// `c[L] = Σ x[m+L]·y[m]` for L from −(ny−1) to nx−1, at index L + ny − 1,
    /// by a zero-padded real FFT (`vDSP_fft_zrip`, as `AudioDSP.swift` uses
    /// it: DC packed in real[0], Nyquist in imaginary[0]).
    static func crossCorrelation(_ x: [Float], _ y: [Float]) -> [Double] {
        let nx = x.count
        let ny = y.count
        let lags = nx + ny - 1
        var log2n = 1
        while (1 << log2n) < lags { log2n += 1 }
        let n = 1 << log2n
        let half = n / 2
        guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2)) else {
            return direct(x, y)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        func spectrum(_ values: [Float]) -> ([Float], [Float]) {
            var padded = [Float](repeating: 0, count: n)
            padded.replaceSubrange(0..<values.count, with: values)
            var real = [Float](repeating: 0, count: half)
            var imaginary = [Float](repeating: 0, count: half)
            real.withUnsafeMutableBufferPointer { re in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                    padded.withUnsafeBufferPointer { source in
                        source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                        }
                    }
                    vDSP_fft_zrip(
                        setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Forward))
                }
            }
            return (real, imaginary)
        }

        let (xr, xi) = spectrum(x)
        let (yr, yi) = spectrum(y)
        // X · conj(Y). DC and Nyquist are real and multiply on their own.
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        real[0] = xr[0] * yr[0]
        imaginary[0] = xi[0] * yi[0]
        for bin in 1..<half {
            real[bin] = xr[bin] * yr[bin] + xi[bin] * yi[bin]
            imaginary[bin] = xi[bin] * yr[bin] - xr[bin] * yi[bin]
        }
        var circular = [Float](repeating: 0, count: n)
        real.withUnsafeMutableBufferPointer { re in
            imaginary.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft_zrip(
                    setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Inverse))
                circular.withUnsafeMutableBufferPointer { out in
                    out.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(half))
                    }
                }
            }
        }
        // Each forward spectrum is scaled by 2 and the inverse by n.
        let scale = 1 / (4 * Double(n))
        var result = [Double](repeating: 0, count: lags)
        for index in 0..<lags {
            let lag = index - (ny - 1)
            result[index] = Double(circular[lag >= 0 ? lag : n + lag]) * scale
        }
        return result
    }

    /// The same sums, one by one: the fallback when no FFT setup can be made.
    private static func direct(_ x: [Float], _ y: [Float]) -> [Double] {
        let ny = y.count
        var result = [Double](repeating: 0, count: x.count + ny - 1)
        for index in result.indices {
            let lag = index - (ny - 1)
            var sum = 0.0
            for m in max(0, -lag)..<min(ny, x.count - lag) {
                sum += Double(x[m + lag]) * Double(y[m])
            }
            result[index] = sum
        }
        return result
    }
}
