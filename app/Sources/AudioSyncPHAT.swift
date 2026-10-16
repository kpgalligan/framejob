import Accelerate
import Foundation

/// Synchronize Audio's sub-frame refinement (road map "audio-sync-2", AS-4;
/// spec §11 SY-20): band-limited GCC-PHAT on two files' cached 8 kHz samples
/// (`cache/sync/<media id>.pcm`), near a lag the features already found.
///
/// It is pure, as the match is: samples, speeds and a line in, a shift and
/// its z out. `AudioSync.plan` refines each chosen match's offset with it, and
/// drift (`AudioSyncDrift.swift`, SY-21) refines each of its windows.
///
/// **The line.** `lag(a) = intercept + rate·a`, a an anchor TIMELINE sample
/// and lag the anchor's sample minus the mover's of the same sound, both in
/// samples at `SyncFeatures.sampleRate`. Over a region of anchor samples the
/// anchor is read as it is and the mover along the line, at `a·(1 − rate) −
/// intercept`, so a residual delay is all that is left between the two; its
/// peak `shift` makes the true lag `line(a) + shift`.
///
/// **Why only near the line** (SY-20): PHAT whitens every bin, so any shared
/// stretch can own its global peak; the round's analysis found whole-file
/// PHAT fooled by a burst. The peak is taken within `reachSamples` of the
/// line and is used only when it is CLEAR; otherwise the caller keeps the
/// coarse value. The refinement never changes a match's confidence or tier.
enum AudioSyncPHAT {

    // MARK: - The numbers (SY-20)

    /// The speech band kept, in hertz.
    static let lowHertz = 300.0
    static let highHertz = 3400.0
    /// ±3 feature frames (48 ms): how far from the line the peak may lie.
    static let reachSamples = 384
    /// The z a peak needs to be clear: 8 at first, 15 by SY-20's calibration
    /// rule (the owner's recorder reversed, a null, read 10.24).
    static let clearZ = 15.0
    /// 30 s: the most samples one refinement correlates.
    static let maximumRegionSamples = 240_000
    /// 2 s: a region under this is not refined.
    static let minimumRegionSamples = 16_000
    /// The shared setup's size (SY-22): 524,288 ≥ 2·`maximumRegionSamples` − 1.
    static let planLog2n = 19

    /// One vDSP FFT setup a `plan` makes once and lends to every refinement
    /// (SY-22): read-only after `init`, so any thread may borrow it. Each
    /// correlation still transforms at its own least power of two.
    final class FFT {
        let log2n: Int
        fileprivate let setup: FFTSetup

        init?(log2n: Int) {
            guard let setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2))
            else { return nil }
            self.log2n = log2n
            self.setup = setup
        }

        deinit { vDSP_destroy_fftsetup(setup) }
    }

    /// One sample in ticks: exactly 75, written as the division for
    /// `SyncFeatures.frameTicks`' reason.
    static var sampleTicks: Ticks {
        ReelTime.perSecond / Ticks(SyncFeatures.sampleRate)
    }

    /// `lag(a) = intercept + rate·a`, in samples, a the anchor's timeline
    /// sample.
    struct Line: Equatable {
        let intercept: Double
        let rate: Double
    }

    /// The peak's offset from the line (refined, in samples), its z over
    /// every lag, and whether it is clear (SY-20).
    struct Refinement: Equatable {
        let shift: Double
        let z: Double
        let clear: Bool
    }

    // MARK: - Reading the samples

    /// `count` samples of a file playing at `speed`: element k is the linear
    /// interpolation at source position `(start + k·step)·speed`, as
    /// Int16/32768, and 0 outside `[0, samples.count − 1]`.
    static func slice(_ samples: [Int16], speed: Double, start: Double, step: Double, count: Int)
        -> [Float] {
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        let last = samples.count - 1
        guard last >= 0 else { return out }
        samples.withUnsafeBufferPointer { source in
            for k in 0..<count {
                let position = (start + Double(k) * step) * speed
                guard position >= 0, position <= Double(last) else { continue }
                let index = Int(position)
                let fraction = position - Double(index)
                let low = Double(source[index])
                let high = index < last ? Double(source[index + 1]) : low
                out[k] = Float((low + (high - low) * fraction) / 32768)
            }
        }
        return out
    }

    // MARK: - The correlation (SY-20)

    /// The band-limited PHAT correlation `r[L]` for L from −(ny−1) to nx−1, at
    /// index L + ny − 1: n the least power of two holding every lag, one
    /// zero-padded `vDSP_fft_zrip` each (`summedCorrelation`'s pattern), the
    /// cross-spectrum `X·conj(Y)` kept on the bins `1..<n/2` whose `k·8000/n`
    /// lies in [`lowHertz`, `highHertz`], each divided by its magnitude (0
    /// under 1e-20), DC and Nyquist 0, then one inverse: `r[L] = (1/n)·Σ_k
    /// W_k·e^{2πikL/n}` over all n bins. `fft`'s setup is borrowed when its
    /// `log2n` is at least the one needed; otherwise one is made and destroyed.
    static func correlation(_ x: [Float], _ y: [Float], fft: FFT? = nil) -> [Double] {
        let nx = x.count
        let ny = y.count
        guard nx > 0, ny > 0 else { return [] }
        let lags = nx + ny - 1
        var log2n = 1
        while (1 << log2n) < lags { log2n += 1 }
        let n = 1 << log2n
        let half = n / 2
        let borrowed = fft.flatMap { $0.log2n >= log2n ? $0 : nil }
        guard let owner = borrowed ?? FFT(log2n: log2n) else {
            return [Double](repeating: 0, count: lags)
        }
        // The setup lives as long as its owner: held to the end of this call.
        defer { withExtendedLifetime(owner) {} }
        let setup = owner.setup

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
        // X · conj(Y), whitened on the band. DC (real[0]) and Nyquist
        // (imaginary[0]) stay 0.
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        let binHertz = Double(SyncFeatures.sampleRate) / Double(n)
        for bin in 1..<half {
            let hertz = Double(bin) * binHertz
            guard hertz >= lowHertz, hertz <= highHertz else { continue }
            let re = Double(xr[bin]) * Double(yr[bin]) + Double(xi[bin]) * Double(yi[bin])
            let im = Double(xi[bin]) * Double(yr[bin]) - Double(xr[bin]) * Double(yi[bin])
            let magnitude = (re * re + im * im).squareRoot()
            guard magnitude >= 1e-20 else { continue }
            real[bin] = Float(re / magnitude)
            imaginary[bin] = Float(im / magnitude)
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
        // The whitened spectrum carries no forward scale; the inverse sums n bins.
        let scale = 1 / Double(n)
        var result = [Double](repeating: 0, count: lags)
        for index in 0..<lags {
            let lag = index - (ny - 1)
            result[index] = Double(circular[lag >= 0 ? lag : n + lag]) * scale
        }
        return result
    }

    // MARK: - The refinement (SY-20)

    /// The anchor's samples over `region` (anchor timeline samples) against
    /// the mover's along `line`: nil when the region is under
    /// `minimumRegionSamples` or either slice is all 0. z is over EVERY lag;
    /// the peak is the highest r with `|L| ≤ reachSamples`; it is clear when
    /// z ≥ `clearZ`, `|L| < reachSamples` and r[L] is strictly above both
    /// neighbours; `shift = L` plus `AudioSyncMatch.refine`'s parabola.
    static func refine(
        anchor: [Int16], anchorSpeed: Double, mover: [Int16], moverSpeed: Double, line: Line,
        region: Range<Int>, fft: FFT? = nil
    ) -> Refinement? {
        guard region.count >= minimumRegionSamples else { return nil }
        let x = slice(
            anchor, speed: anchorSpeed, start: Double(region.lowerBound), step: 1,
            count: region.count)
        let y = slice(
            mover, speed: moverSpeed,
            start: Double(region.lowerBound) * (1 - line.rate) - line.intercept,
            step: 1 - line.rate, count: region.count)
        guard x.contains(where: { $0 != 0 }), y.contains(where: { $0 != 0 }) else { return nil }
        let r = correlation(x, y, fft: fft)
        let lags = r.count
        guard lags > 0 else { return nil }

        let mean = r.reduce(0, +) / Double(lags)
        let sd = (r.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lags)).squareRoot()
        let zero = y.count - 1
        let low = max(0, zero - reachSamples)
        let high = min(lags - 1, zero + reachSamples)
        guard low <= high else { return nil }
        var peak = low
        for index in low...high where r[index] > r[peak] { peak = index }
        let lag = peak - zero
        let z = sd > 0 ? (r[peak] - mean) / sd : 0
        let left = peak > 0 ? r[peak - 1] : nil
        let right = peak + 1 < lags ? r[peak + 1] : nil
        let clear = z >= clearZ && abs(lag) < reachSamples
            && left.map { r[peak] > $0 } ?? false && right.map { r[peak] > $0 } ?? false
        let shift = Double(lag) + AudioSyncMatch.refine(left: left, centre: r[peak], right: right)
        return Refinement(shift: shift, z: z, clear: clear)
    }
}
