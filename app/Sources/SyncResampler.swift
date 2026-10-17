import Foundation

/// The sync pass's own 8 kHz resampler (#305; spec §11 SY-34): the reader
/// decodes a file at its native rate and this brings it to
/// `SyncFeatures.sampleRate`, so two passes over one file write the same
/// bytes — AVFoundation's own rate conversion did not (P25).
///
/// It is pure arithmetic, no AVFoundation: output n is the Kaiser-windowed
/// sinc low-pass (cutoff `cutoffHertz`, `halfWidth` output samples each
/// side, β `kaiserBeta`) evaluated at input position `n·inputRate/8000`
/// exactly — a symmetric kernel, so no delay — with every input sample
/// outside the file 0. (A rate that is not a whole number of hertz has its
/// position's fraction rounded to the nearest 1/`fractionalPhases` of an
/// input sample, so its kernels are a table per phase too.) A file of N
/// samples gives `⌈N·8000/inputRate⌉`.
/// Each output is summed in one fixed order from absolute input positions,
/// so the answer does not depend on how the input is split into pieces. At
/// 8,000 Hz it is the identity.
final class SyncResampler {

    static let outputRate = 8_000.0
    static let cutoffHertz = 3_600.0
    /// Output samples each side of the kernel's centre.
    static let halfWidth = 16
    static let kaiserBeta = 8.6
    /// The phases a rate that is not a whole number of hertz is rounded to.
    static let fractionalPhases = 1_024

    private let inputRate: Double
    /// `inputRate` when it is a whole number of hertz: positions are then
    /// exact integer arithmetic and the kernel a table per phase.
    private let wholeRate: Int?
    /// The kernel's reach, in input samples each side.
    private let reach: Double
    /// One kernel per phase (`n·rate mod 8000`, which moves in steps of
    /// `phaseStep`; for a rate not whole, the rounded fraction's
    /// 1/`fractionalPhases`), made when first needed: its first tap's offset from the
    /// position's whole part, and its weights, padded with zeros to `taps`.
    private var tables: [(first: Int, weights: [Float])?]
    private let phaseStep: Int
    private let taps: Int
    /// The input not yet consumed: element 0 is input sample `origin`.
    private var pending: [Float] = []
    private var origin = 0
    private var received = 0
    private var next = 0

    init(inputRate: Double) {
        self.inputRate = inputRate
        let whole = inputRate.rounded()
        wholeRate = inputRate == whole && whole >= 1 && whole <= 1e7 ? Int(whole) : nil
        reach = Double(Self.halfWidth) * inputRate / Self.outputRate
        taps = (Int(reach.rounded(.up)) * 2 + 2 + 7) / 8 * 8
        let output = Int(Self.outputRate)
        phaseStep = wholeRate.map { Self.gcd($0, output) } ?? output
        let phases = wholeRate == nil ? Self.fractionalPhases : output / phaseStep
        tables = [(first: Int, weights: [Float])?](repeating: nil, count: phases)
        // Input before the file is 0: enough of it that the first outputs'
        // taps lie inside `pending`.
        let lead = Int(reach.rounded(.up)) + 2
        pending = [Float](repeating: 0, count: lead)
        origin = -lead
    }

    /// The outputs `samples` completes, in order.
    func feed(_ samples: UnsafeBufferPointer<Float>) -> [Float] {
        received += samples.count
        if inputRate == Self.outputRate { return Array(samples) }
        pending.append(contentsOf: samples)
        return drain(upTo: Int.max)
    }

    /// Every output still owed, the input past the file read as 0.
    func finish() -> [Float] {
        if inputRate == Self.outputRate { return [] }
        let total: Int
        if let rate = wholeRate {
            total = (received * Int(Self.outputRate) + rate - 1) / rate
        } else {
            total = Int((Double(received) * Self.outputRate / inputRate).rounded(.up))
        }
        pending.append(contentsOf: [Float](repeating: 0, count: taps + 2))
        var out: [Float] = []
        while next < total {
            pending.append(contentsOf: [Float](repeating: 0, count: taps))
            out += drain(upTo: total)
        }
        return out
    }

    // MARK: - The arithmetic

    /// Output n's position as its whole part and its phase key; the phase's
    /// kernel.
    private func kernel(_ n: Int) -> (base: Int, first: Int, weights: [Float]) {
        if let rate = wholeRate {
            let numerator = n * rate
            let output = Int(Self.outputRate)
            let base = numerator / output
            let phase = numerator % output
            if let table = tables[phase / phaseStep] { return (base, table.first, table.weights) }
            let table = makeTable(fraction: Double(phase) / Self.outputRate)
            tables[phase / phaseStep] = table
            return (base, table.first, table.weights)
        }
        let position = Double(n) * inputRate / Self.outputRate
        var base = Int(position.rounded(.down))
        let steps = Double(Self.fractionalPhases)
        var phase = Int(((position - Double(base)) * steps).rounded())
        if phase == Self.fractionalPhases {
            base += 1
            phase = 0
        }
        if let table = tables[phase] { return (base, table.first, table.weights) }
        let table = makeTable(fraction: Double(phase) / steps)
        tables[phase] = table
        return (base, table.first, table.weights)
    }

    /// The kernel at a position `fraction` past a whole input sample: taps
    /// from `⌈fraction − reach⌉`, each `2fc·sinc(2fc·d)·kaiser(d/reach)` at
    /// its distance d (fc the cutoff in cycles per input sample), scaled to
    /// sum to 1, then zeros to `taps`.
    private func makeTable(fraction: Double) -> (first: Int, weights: [Float]) {
        let first = Int((fraction - reach).rounded(.up))
        let last = Int((fraction + reach).rounded(.down))
        let fc = Self.cutoffHertz / inputRate
        let i0Beta = Self.besselI0(Self.kaiserBeta)
        var values: [Double] = []
        for i in first...last {
            let d = Double(i) - fraction
            let x = 2 * fc * d
            let sinc = x == 0 ? 1 : sin(Double.pi * x) / (Double.pi * x)
            let t = d / reach
            let window = abs(t) <= 1
                ? Self.besselI0(Self.kaiserBeta * (1 - t * t).squareRoot()) / i0Beta : 0
            values.append(2 * fc * sinc * window)
        }
        let sum = values.reduce(0, +)
        var weights = values.map { Float($0 / sum) }
        weights += [Float](repeating: 0, count: max(0, taps - weights.count))
        return (first, weights)
    }

    /// Every output whose taps `pending` holds, up to (not including) `limit`.
    private func drain(upTo limit: Int) -> [Float] {
        var out: [Float] = []
        let end = origin + pending.count
        pending.withUnsafeBufferPointer { input in
            while next < limit {
                let (base, first, weights) = kernel(next)
                let start = base + first
                guard start + weights.count <= end else { break }
                out.append(Self.dot(input, from: start - origin, weights))
                next += 1
            }
        }
        // Keep what the next output's taps start at, and nothing before.
        let keep = kernel(next)
        let drop = min(max(0, keep.base + keep.first - origin), pending.count)
        if drop > 0 {
            pending.removeFirst(drop)
            origin += drop
        }
        return out
    }

    /// `Σ input[from + j]·weights[j]` in eight lanes by j mod 8, the lanes
    /// summed in order: one fixed order whatever the memory's alignment.
    private static func dot(_ input: UnsafeBufferPointer<Float>, from: Int, _ weights: [Float])
        -> Float {
        var lanes = SIMD8<Float>(repeating: 0)
        guard let base = input.baseAddress else { return 0 }
        weights.withUnsafeBufferPointer { w in
            guard let taps = w.baseAddress else { return }
            var j = 0
            while j < w.count {
                let x = UnsafeRawPointer(base + from + j).loadUnaligned(as: SIMD8<Float>.self)
                let y = UnsafeRawPointer(taps + j).loadUnaligned(as: SIMD8<Float>.self)
                lanes += x * y
                j += 8
            }
        }
        var sum: Float = 0
        for lane in 0..<8 { sum += lanes[lane] }
        return sum
    }

    /// The zeroth-order modified Bessel function of the first kind, by its
    /// series to a relative 1e-15.
    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        var k = 1.0
        while term > 1e-15 * sum {
            term *= (x / (2 * k)) * (x / (2 * k))
            sum += term
            k += 1
        }
        return sum
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
