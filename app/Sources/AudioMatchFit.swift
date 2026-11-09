import Foundation

/// Match EQ's arithmetic (road map "audio" AP12, spec §11 AU-125…AU-127):
/// two third-octave speech spectra (`SpeechSpectrumMeter`) in, the five
/// tonal slots of an `EqProps` out. Pure: no document, no render, no AppKit,
/// so `audio_ap12_probe.py` checks it against curves made by the EQ's own
/// response.
///
/// **The curve** (AU-125) is what the target lacks against the reference,
/// band by band, with its broadband level taken out — the level is Match
/// Loudness's — and smoothed. **The fit** (AU-126) is the EQ whose drawn
/// response (`AudioEQDesign.responseDB` of the five tonal slots at 48 kHz at
/// the band centres, the curve view's own function) best follows the curve,
/// every residual measured up to a constant offset: shelves first, then up
/// to three bells placed where the residual is largest, then
/// Levenberg–Marquardt over every placed parameter, then rounded.
enum AudioMatchFit {
    static let maxGainDB = 12.0
    static let contentRangeDB = 50.0
    static let minimumBands = 12
    static let minimumBellDB = 0.5

    /// The shelves' starting corners, Hz.
    static let lowShelfStart = 150.0
    static let highShelfStart = 6000.0
    static let maximumBells = 3
    /// A new bell sits more than this many bands from an earlier one.
    static let bellSpacingBands = 3
    static let qRange = 0.5...4.0
    static let lowShelfRange = 40.0...500.0
    static let highShelfRange = 2000.0...16_000.0
    static let bellRange = 60.0...12_000.0
    static let maximumIterations = 40
    static let sampleRate = 48_000.0

    /// The band centres the model is read at.
    static let frequencies: [Double] = SpeechSpectrumMeter.bandIndices.map {
        SpeechSpectrumMeter.centre($0)
    }

    /// The fit: only the five tonal slots set, `bypass` false; `rmsDB` the
    /// weighted RMS of the offset-free residual over the rounded slots.
    struct Fit: Equatable {
        let slots: EqProps
        let rmsDB: Double
    }

    // MARK: - The curve (AU-125)

    /// How many of `levels` are within `contentRangeDB` of their loudest.
    static func contentBands(_ levels: [Double]) -> Int {
        guard let top = levels.filter({ $0.isFinite }).max() else { return 0 }
        return levels.filter { $0.isFinite && $0 >= top - contentRangeDB }.count
    }

    /// The curve to fit and its weights: D = reference − target, weight 1
    /// where both are within `contentRangeDB` of their own loudest band; the
    /// weighted mean of D removed (a band of weight 0 reads 0); smoothed
    /// [1, 2, 1] over the weighted bands, renormalised to the taps present
    /// (`smoothed`). nil under `minimumBands`
    /// weighted bands, or for spectra of different lengths.
    static func target(reference: [Double], target: [Double])
        -> (curve: [Double], weights: [Double])?
    {
        let count = reference.count
        guard count == target.count, count >= 2,
            let refTop = reference.filter({ $0.isFinite }).max(),
            let tgtTop = target.filter({ $0.isFinite }).max()
        else { return nil }
        var weights = [Double](repeating: 0, count: count)
        for b in 0..<count
        where reference[b].isFinite && target[b].isFinite
            && reference[b] >= refTop - contentRangeDB && target[b] >= tgtTop - contentRangeDB
        {
            weights[b] = 1
        }
        guard weights.reduce(0, +) >= Double(minimumBands) else { return nil }
        var difference = (0..<count).map { weights[$0] > 0 ? reference[$0] - target[$0] : 0 }
        let mean = weightedMean(difference, weights)
        difference = (0..<count).map { weights[$0] > 0 ? difference[$0] - mean : 0 }
        return (smoothed(difference, weights: weights), weights)
    }

    /// [1, 2, 1] over a weighted band and its weighted neighbours,
    /// renormalised to the taps present: (2, 1)/3 at an end or beside a band
    /// of weight 0, the band alone when both neighbours are dropped. A band
    /// of weight 0 reads 0 and gives nothing to its neighbours (AU-125, #411).
    static func smoothed(_ values: [Double], weights: [Double]) -> [Double] {
        let count = values.count
        let weighted = { (b: Int) in b >= 0 && b < count && weights[b] > 0 }
        return (0..<count).map { b in
            guard weighted(b) else { return 0 }
            var total = 2 * values[b]
            var taps = 2.0
            for n in [b - 1, b + 1] where weighted(n) {
                total += values[n]
                taps += 1
            }
            return total / taps
        }
    }

    static func weightedMean(_ values: [Double], _ weights: [Double]) -> Double {
        var total = 0.0
        var weight = 0.0
        for b in values.indices where weights[b] > 0 {
            total += weights[b] * values[b]
            weight += weights[b]
        }
        return weight > 0 ? total / weight : 0
    }

    // MARK: - The model

    /// The response of `slots` in dB at `frequencies`, 0 where nothing is
    /// designed.
    static func model(_ slots: EqProps) -> [Double] {
        guard let settings = AudioEQSettings(eq: slots, hum: nil) else {
            return [Double](repeating: 0, count: frequencies.count)
        }
        return AudioEQDesign.responseDB(settings, frequencies: frequencies, sampleRate: sampleRate)
    }

    /// AU-126's residual: curve − model with its weighted mean removed.
    static func residual(_ curve: [Double], _ model: [Double], _ weights: [Double]) -> [Double] {
        let raw = (0..<curve.count).map { curve[$0] - model[$0] }
        let mean = weightedMean(raw, weights)
        return raw.map { $0 - mean }
    }

    static func cost(_ residual: [Double], _ weights: [Double]) -> Double {
        var total = 0.0
        for b in residual.indices { total += weights[b] * residual[b] * residual[b] }
        return total
    }

    // MARK: - The fit (AU-126)

    /// The parameters LM moves: per slot, log f, gain and (bells) log Q.
    private struct Params {
        var low: (f: Double, g: Double)
        var high: (f: Double, g: Double)
        var bells: [(f: Double, g: Double, q: Double)]

        var vector: [Double] {
            var v = [log(low.f), low.g, log(high.f), high.g]
            for bell in bells { v += [log(bell.f), bell.g, log(bell.q)] }
            return v
        }

        init(low: (Double, Double), high: (Double, Double), bells: [(Double, Double, Double)]) {
            self.low = low
            self.high = high
            self.bells = bells.map { (f: $0.0, g: $0.1, q: $0.2) }
        }

        /// From a vector, clamped to AU-126's bounds.
        init(_ v: [Double], bells count: Int) {
            func clamp(_ x: Double, _ r: ClosedRange<Double>) -> Double {
                min(max(x, r.lowerBound), r.upperBound)
            }
            let gains = -AudioMatchFit.maxGainDB...AudioMatchFit.maxGainDB
            low = (clamp(exp(v[0]), lowShelfRange), clamp(v[1], gains))
            high = (clamp(exp(v[2]), highShelfRange), clamp(v[3], gains))
            bells = (0..<count).map { k in
                (f: clamp(exp(v[4 + 3 * k]), bellRange), g: clamp(v[5 + 3 * k], gains),
                 q: clamp(exp(v[6 + 3 * k]), qRange))
            }
        }

        var eq: EqProps {
            var eq = EqProps()
            eq.lowShelf = EqShelfProps(frequency: low.f, gainDb: low.g)
            eq.highShelf = EqShelfProps(frequency: high.f, gainDb: high.g)
            let sorted = bells.sorted { $0.f < $1.f }
            let slots = sorted.map { EqBandProps(frequency: $0.f, gainDb: $0.g, q: $0.q) }
            eq.band1 = slots.count > 0 ? slots[0] : nil
            eq.band2 = slots.count > 1 ? slots[1] : nil
            eq.band3 = slots.count > 2 ? slots[2] : nil
            return eq
        }
    }

    /// The five tonal slots that best follow `curve` under `weights`.
    static func fit(curve: [Double], weights: [Double]) -> Fit {
        let count = frequencies.count
        guard curve.count == count, weights.count == count else {
            return Fit(slots: EqProps(), rmsDB: 0)
        }
        // (a) The shelves' gains, by weighted least squares on their 1 dB
        // responses, each offset-free.
        let zero = [Double](repeating: 0, count: count)
        let unitLow = residual(
            model(EqProps(lowShelf: EqShelfProps(frequency: lowShelfStart, gainDb: 1))), zero,
            weights)
        let unitHigh = residual(
            model(EqProps(highShelf: EqShelfProps(frequency: highShelfStart, gainDb: 1))), zero,
            weights)
        let centred = residual(curve, zero, weights)
        var a11 = 0.0, a12 = 0.0, a22 = 0.0, b1 = 0.0, b2 = 0.0
        for b in 0..<count {
            let w = weights[b]
            a11 += w * unitLow[b] * unitLow[b]
            a12 += w * unitLow[b] * unitHigh[b]
            a22 += w * unitHigh[b] * unitHigh[b]
            b1 += w * unitLow[b] * centred[b]
            b2 += w * unitHigh[b] * centred[b]
        }
        let det = a11 * a22 - a12 * a12
        var gl = 0.0, gh = 0.0
        if abs(det) > 1e-12 {
            gl = (b1 * a22 - b2 * a12) / det
            gh = (a11 * b2 - a12 * b1) / det
        }
        var params = Params(
            low: (lowShelfStart, min(max(gl, -maxGainDB), maxGainDB)),
            high: (highShelfStart, min(max(gh, -maxGainDB), maxGainDB)), bells: [])
        // The shelves refined alone, corners too: when they leave no band at
        // or above the bell threshold the curve is a tilt, and they are the
        // start (no bell will be placed); else the corners stay where they
        // started, for the bells to work around.
        let shelves = refined(params, curve: curve, weights: weights)
        let left = residual(curve, model(shelves.eq), weights)
        if left.indices.allSatisfy({ weights[$0] == 0 || abs(left[$0]) < minimumBellDB }) {
            params = shelves
        }

        // (b) Up to three bells, greedily, where the residual is largest.
        var placed: [Int] = []
        for _ in 0..<maximumBells {
            let r = residual(curve, model(params.eq), weights)
            var best: Int?
            for b in 0..<count where weights[b] > 0 && abs(r[b]) >= minimumBellDB {
                guard placed.allSatisfy({ abs($0 - b) > bellSpacingBands }) else { continue }
                if best == nil || abs(r[b]) > abs(r[best!]) { best = b }
            }
            guard let b = best else { break }
            placed.append(b)
            var run = 1
            for direction in [-1, 1] {
                var k = b + direction
                while k >= 0, k < count, weights[k] > 0, r[k].sign == r[b].sign,
                    abs(r[k]) >= abs(r[b]) / 2
                {
                    run += 1
                    k += direction
                }
            }
            let octaves = Double(run) / 3
            let q = min(max(pow(2, octaves / 2) / (pow(2, octaves) - 1), qRange.lowerBound),
                qRange.upperBound)
            params.bells.append(
                (f: min(max(frequencies[b], bellRange.lowerBound), bellRange.upperBound),
                 g: min(max(r[b], -maxGainDB), maxGainDB), q: q))
        }

        // (c) Levenberg–Marquardt over every placed parameter.
        params = refined(params, curve: curve, weights: weights)

        // (d) Rounded; a slot under 0.1 dB is off.
        let slots = rounded(params.eq)
        let r = residual(curve, model(slots), weights)
        let total = weights.reduce(0, +)
        return Fit(slots: slots, rmsDB: total > 0 ? (cost(r, weights) / total).squareRoot() : 0)
    }

    /// AU-126 (c): LM on the weighted residual, a central-difference
    /// Jacobian, λ from 1e−2 (÷10 better, ×10 worse), clamped each step, at
    /// most `maximumIterations` or a relative cost change under 1e−6.
    private static func refined(_ start: Params, curve: [Double], weights: [Double]) -> Params {
        let bells = start.bells.count
        let root = weights.map { $0.squareRoot() }
        func errors(_ v: [Double]) -> [Double] {
            let r = residual(curve, model(Params(v, bells: bells).eq), weights)
            return r.indices.map { root[$0] * r[$0] }
        }
        func squares(_ e: [Double]) -> Double { e.reduce(0) { $0 + $1 * $1 } }
        var v = Params(start.vector, bells: bells).vector
        var e = errors(v)
        var current = squares(e)
        var lambda = 1e-2
        let m = v.count
        let n = e.count
        for _ in 0..<maximumIterations {
            var jacobian = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
            for p in 0..<m {
                let h = 1e-3
                var plus = v
                var minus = v
                plus[p] += h
                minus[p] -= h
                let ep = errors(plus)
                let em = errors(minus)
                for i in 0..<n { jacobian[i][p] = (ep[i] - em[i]) / (2 * h) }
            }
            var jtj = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
            var jte = [Double](repeating: 0, count: m)
            for i in 0..<n {
                for p in 0..<m {
                    jte[p] += jacobian[i][p] * e[i]
                    for q in 0..<m { jtj[p][q] += jacobian[i][p] * jacobian[i][q] }
                }
            }
            var system = jtj
            for p in 0..<m { system[p][p] += lambda * max(jtj[p][p], 1e-9) }
            guard let step = solve(system, jte.map { -$0 }) else { break }
            let trial = Params(zip(v, step).map { $0 + $1 }, bells: bells).vector
            let te = errors(trial)
            let cost = squares(te)
            if cost < current {
                let change = (current - cost) / max(current, 1e-30)
                v = trial
                e = te
                current = cost
                lambda /= 10
                if change < 1e-6 { break }
            } else {
                lambda *= 10
                if lambda > 1e12 { break }
            }
        }
        return Params(v, bells: bells)
    }

    /// Gaussian elimination with partial pivoting; nil when singular.
    private static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = a
        var y = b
        for c in 0..<n {
            var pivot = c
            for r in c + 1..<n where abs(m[r][c]) > abs(m[pivot][c]) { pivot = r }
            guard abs(m[pivot][c]) > 1e-15 else { return nil }
            m.swapAt(c, pivot)
            y.swapAt(c, pivot)
            for r in c + 1..<n {
                let f = m[r][c] / m[c][c]
                guard f != 0 else { continue }
                for k in c..<n { m[r][k] -= f * m[c][k] }
                y[r] -= f * y[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var total = y[r]
            for k in r + 1..<n { total -= m[r][k] * x[k] }
            x[r] = total / m[r][r]
        }
        return x
    }

    /// AU-126 (d): f to 1 Hz, gain to 0.1 dB, Q to 0.01; |gain| < 0.1 dB off.
    static func rounded(_ eq: EqProps) -> EqProps {
        func gain(_ g: Double) -> Double? {
            let r = (g * 10).rounded() / 10
            return abs(r) < 0.1 ? nil : r
        }
        func shelf(_ s: EqShelfProps?) -> EqShelfProps? {
            guard let s, let g = gain(s.gainDb) else { return nil }
            return EqShelfProps(frequency: s.frequency.rounded(), gainDb: g)
        }
        func bell(_ s: EqBandProps?) -> EqBandProps? {
            guard let s, let g = gain(s.gainDb) else { return nil }
            return EqBandProps(
                frequency: s.frequency.rounded(), gainDb: g, q: (s.q * 100).rounded() / 100)
        }
        let bells = [bell(eq.band1), bell(eq.band2), bell(eq.band3)].compactMap { $0 }
        return EqProps(
            lowShelf: shelf(eq.lowShelf), band1: bells.count > 0 ? bells[0] : nil,
            band2: bells.count > 1 ? bells[1] : nil, band3: bells.count > 2 ? bells[2] : nil,
            highShelf: shelf(eq.highShelf))
    }

    // MARK: - The write (AU-127)

    /// The target's EQ after the match: its five tonal slots replaced by the
    /// fit's, its high- and low-pass kept, `bypass` false.
    static func applied(_ fit: Fit, to current: EqProps?) -> EqProps {
        var eq = current ?? EqProps()
        eq.lowShelf = fit.slots.lowShelf
        eq.band1 = fit.slots.band1
        eq.band2 = fit.slots.band2
        eq.band3 = fit.slots.band3
        eq.highShelf = fit.slots.highShelf
        eq.bypass = false
        return eq
    }

    /// The EQ a target's spectrum is measured through: its own with the
    /// tonal slots off, `bypass` false (the passes kept, so the fit is
    /// around them).
    static func trialEQ(_ current: EqProps?) -> EqProps {
        var eq = current ?? EqProps()
        eq.lowShelf = nil
        eq.band1 = nil
        eq.band2 = nil
        eq.band3 = nil
        eq.highShelf = nil
        eq.bypass = false
        return eq
    }
}
