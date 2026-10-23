import Foundation

/// The keep-pitch-off arm's kernel (spec §11 SR-6): band-limited
/// interpolation at a fractional source position with a cutoff that follows
/// the local rate — a tape glide with no rate boundary in it.
///
/// y(p) = fc · Σₖ x[k] · g(fc · |p − k|), fc = min(1, 1/r), over
/// |p − k| ≤ Z / fc, where g(u) = sinc(u) · kaiser(u / Z, β) is read from a
/// table of `phasesPerCrossing` phases per zero crossing with linear
/// interpolation between phases. Kaiser β = 9 puts the stop band near
/// −90 dB, under the 16-bit export's own floor; fc < 1 anti-aliases a
/// speed-up. The table's zeros at every crossing are written exactly, so at
/// ×1 on an integer position the sum is the source's own sample — a constant
/// ×1 render is the identity.
///
/// One per render: the table is built once (≈ 16 k entries) and read only.
struct RampAudioResampler {
    static let zeroCrossings = 32
    static let phasesPerCrossing = 512
    static let beta = 9.0

    /// g at u = i / phasesPerCrossing for i = 0 … Z · phases, then one
    /// guard zero, so `table[i + 1]` is always in range.
    private let table: [Double]
    private let last: Int

    init() {
        let phases = Self.phasesPerCrossing
        let last = Self.zeroCrossings * phases
        var table = [Double](repeating: 0, count: last + 2)
        let norm = Self.besselI0(Self.beta)
        for i in 1..<last where i % phases != 0 {
            let u = Double(i) / Double(phases)
            let w = u / Double(Self.zeroCrossings)
            let window = Self.besselI0(Self.beta * (1 - w * w).squareRoot()) / norm
            table[i] = sin(Double.pi * u) / (Double.pi * u) * window
        }
        table[0] = 1
        self.table = table
        self.last = last
    }

    /// y at fractional source position p (48 kHz frames) for local rate r,
    /// reading `sample(k)` (zero outside the file); reach ±zeroCrossings /
    /// min(1, 1/r) frames.
    func value(at p: Double, rate r: Double, _ sample: (Int64) -> Float) -> Float {
        let fc = r > 1 ? 1 / r : 1
        let reach = Double(Self.zeroCrossings) / fc
        let lo = Int64((p - reach).rounded(.up))
        let hi = Int64((p + reach).rounded(.down))
        let scale = fc * Double(Self.phasesPerCrossing)
        var sum = 0.0
        var k = lo
        while k <= hi {
            let x = abs(p - Double(k)) * scale
            let i = Int(x)
            if i < last {
                let low = table[i]
                let g = low + (table[i + 1] - low) * (x - Double(i))
                if g != 0 { sum += Double(sample(k)) * g }
            }
            k += 1
        }
        return Float(sum * fc)
    }

    /// The kernel's reach in source frames at local rate `rate`, rounded up.
    static func reach(rate: Double) -> Int {
        let fc = rate > 1 ? 1 / rate : 1
        return Int((Double(zeroCrossings) / fc).rounded(.up))
    }

    /// The modified Bessel function of the first kind, order 0, by its
    /// power series (converges fast for the window's arguments, ≤ β).
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let quarter = x * x / 4
        var k = 1.0
        while term > sum * 1e-17 {
            term *= quarter / (k * k)
            sum += term
            k += 1
        }
        return sum
    }
}
