import Accelerate
import Foundation

/// The vDSP real-FFT plumbing Synchronize Audio's two correlations share
/// (`AudioSyncMatch.summedCorrelation` and `AudioSyncPHAT.correlation`): a
/// zero-padded buffer packed and transformed forward, a spectrum transformed
/// back and unpacked, the least power of two that holds every lag, and the
/// circular answer read back in lag order.
///
/// It owns no setup. Each caller makes or borrows its own (spec §11 SY-22:
/// `summedCorrelation` makes one per call, `AudioSyncPHAT` borrows the plan's
/// `FFT` or makes one) and decides what a failed setup answers, so this is
/// only the calls between, in the order both sites made them.
enum RealFFT {

    /// Least log2n ≥ 1 with 1 << log2n ≥ count.
    static func log2n(holding count: Int) -> Int {
        var log2n = 1
        while (1 << log2n) < count { log2n += 1 }
        return log2n
    }

    /// `padded` (n = 1 << log2n floats) packed by `vDSP_ctoz`, then one
    /// forward `vDSP_fft_zrip`: the packed spectrum, n/2 real and n/2
    /// imaginary, every value scaled by 2 as vDSP leaves it.
    static func forward(_ setup: FFTSetup, log2n: Int, padded: [Float])
        -> (real: [Float], imaginary: [Float])
    {
        let half = (1 << log2n) / 2
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

    /// One inverse `vDSP_fft_zrip` of the packed spectrum, in place, then
    /// `vDSP_ztoc` into the n-float circular buffer it answers, unscaled.
    static func inverse(
        _ setup: FFTSetup, log2n: Int, real: inout [Float], imaginary: inout [Float]
    ) -> [Float] {
        let n = 1 << log2n
        let half = n / 2
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
        return circular
    }

    /// The circular correlation in lag order: `result[i]` is the value at
    /// lag `i − (ny − 1)`, read at that index when it is not negative and
    /// `n + lag` when it is, times `scale`, for `i < lags`.
    static func lagOrdered(_ circular: [Float], lags: Int, ny: Int, scale: Double) -> [Double] {
        let n = circular.count
        var result = [Double](repeating: 0, count: lags)
        for index in 0..<lags {
            let lag = index - (ny - 1)
            result[index] = Double(circular[lag >= 0 ? lag : n + lag]) * scale
        }
        return result
    }
}
