import Foundation

/// The curves' spline (spec §11 GR-12, grading-2 G2-3), the one
/// implementation: the strip `CurveTextures` uploads for step 4c.2 and the
/// line `CurveEditorView` draws both come from `value(_:at:)`, so what the
/// editor shows is what the compositor applies. The core stores, checks and
/// interpolates the points and never samples the spline.
///
/// **Fritsch–Carlson, exactly** (F. N. Fritsch and R. E. Carlson, "Monotone
/// Piecewise Cubic Interpolation", SIAM J. Numer. Anal. 17(2), 1980): the
/// secants δk; the end tangents the end secants; an interior tangent the
/// mean of its two secants, or 0 where they differ in sign or one is 0; then
/// left to right per segment, a flat secant zeroes both its tangents, and
/// otherwise α = mk/δk and β = m(k+1)/δk are scaled by 3/√(α² + β²) when
/// α² + β² > 9. Cubic Hermite inside a segment, the first or last y outside
/// the first and last x, clamped to 0…1. It passes through every point and
/// never leaves a segment's y span, so a curve that only rises never dips.
///
/// **The hue curves' spline** (spec §11 GR-32) is the same rule made
/// periodic: n secants, the last from the last point to the first point one
/// period on; every tangent interior (indices mod n); the flat-secant and
/// α² + β² > 9 rules per segment in order, the wrap segment last; outside the
/// first and last x, the wrap segment; clamped to the domain's value range.
/// The tone spline is unchanged bit for bit.
enum CurveTable {
    static let stripSize = 1024

    /// The strip's rows: row 0 the tone composites, row 1 the hue curves.
    static let stripRows = 2

    /// The curve through `points` (x strictly rising) at `x`, clamped to the
    /// domain's values (0…1 for a tone curve). Fewer than two points is the
    /// identity. A caller sampling one curve many times builds a `Spline`
    /// once instead.
    static func value(
        _ points: [CurvePoint], at x: Double, domain: CurveDomain = .tone
    ) -> Double {
        Spline(points, domain: domain).value(at: x)
    }

    /// One curve's points and tangents, computed once and sampled often:
    /// the strip samples each curve 1,024 times, the editor once per plot
    /// point.
    struct Spline {
        let xs: [Double]
        let ys: [Double]
        let m: [Double]
        let domain: CurveDomain

        init(_ points: [CurvePoint], domain: CurveDomain = .tone) {
            xs = points.map(\.x)
            ys = points.map(\.y)
            self.domain = domain
            if let period = domain.period {
                m = points.count >= 2
                    ? CurveTable.periodicTangents(xs, ys, period: period) : []
            } else {
                m = points.count >= 2 ? CurveTable.tangents(xs, ys) : []
            }
        }

        func value(at x: Double) -> Double {
            if let period = domain.period { return periodic(at: x, period: period) }
            guard xs.count >= 2, let firstX = xs.first, let lastX = xs.last else {
                return unit(x)
            }
            if x <= firstX { return unit(ys[0]) }
            if x >= lastX { return unit(ys[ys.count - 1]) }
            var k = 0
            while k < xs.count - 2 && x >= xs[k + 1] { k += 1 }
            let h = xs[k + 1] - xs[k]
            guard h > 0 else { return unit(ys[k]) }
            let t = (x - xs[k]) / h
            let t2 = t * t
            let t3 = t2 * t
            let y = (2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h * m[k]
                + (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h * m[k + 1]
            return unit(y)
        }

        /// The periodic spline at `x` taken into one period: inside a
        /// segment its own Hermite, before the first x or from the last x on
        /// the wrap segment, from the last point to the first one period on.
        private func periodic(at x: Double, period: Double) -> Double {
            let n = xs.count
            guard n >= 2 else { return domain.neutral ?? 0 }
            var x = x.truncatingRemainder(dividingBy: period)
            if x < 0 { x += period }
            var k = n - 1
            var h = xs[0] + period - xs[n - 1]
            if x < xs[0] {
                x += period
            } else if x < xs[n - 1] {
                k = 0
                while k < n - 2 && x >= xs[k + 1] { k += 1 }
                h = xs[k + 1] - xs[k]
            }
            let j = (k + 1) % n
            guard h > 0 else { return ranged(ys[k]) }
            let t = (x - xs[k]) / h
            let t2 = t * t
            let t3 = t2 * t
            let y = (2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h * m[k]
                + (-2 * t3 + 3 * t2) * ys[j] + (t3 - t2) * h * m[j]
            return ranged(y)
        }

        /// A hue curve's value inside its domain's range.
        private func ranged(_ value: Double) -> Double {
            value.isNaN ? domain.neutral ?? 0 : min(max(value, domain.lower.y), domain.upper.y)
        }
    }

    /// The six channels' splines, so `strip` builds each once.
    private struct Splines {
        let master: Spline
        let red: Spline
        let green: Spline
        let blue: Spline
        let hueHue: Spline
        let hueSat: Spline

        init(_ curves: ColorCurves) {
            master = Spline(curves.master)
            red = Spline(curves.red)
            green = Spline(curves.green)
            blue = Spline(curves.blue)
            hueHue = Spline(curves.hueHue, domain: .hueShift)
            hueSat = Spline(curves.hueSat, domain: .hueGain)
        }
    }

    private static func value(_ spline: Spline, at x: Double) -> Double {
        spline.value(at: x)
    }

    /// The Fritsch–Carlson tangents of the points `(xs[k], ys[k])`.
    static func tangents(_ xs: [Double], _ ys: [Double]) -> [Double] {
        let n = xs.count
        guard n >= 2 else { return [Double](repeating: 0, count: n) }
        let secants = (0..<(n - 1)).map { k -> Double in
            let h = xs[k + 1] - xs[k]
            return h > 0 ? (ys[k + 1] - ys[k]) / h : 0
        }
        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        for k in stride(from: 1, to: n - 1, by: 1) {
            let before = secants[k - 1]
            let after = secants[k]
            tangents[k] = before * after <= 0 ? 0 : (before + after) / 2
        }
        for k in 0..<(n - 1) {
            let delta = secants[k]
            if delta == 0 {
                tangents[k] = 0
                tangents[k + 1] = 0
                continue
            }
            let alpha = tangents[k] / delta
            let beta = tangents[k + 1] / delta
            let squared = alpha * alpha + beta * beta
            if squared > 9 {
                let tau = 3 / squared.squareRoot()
                tangents[k] = tau * alpha * delta
                tangents[k + 1] = tau * beta * delta
            }
        }
        return tangents
    }

    /// The periodic Fritsch–Carlson tangents (spec §11 GR-32) of the points
    /// `(xs[k], ys[k])`, 0 ≤ x < `period`: n secants, the last wrapping to
    /// the first point one period on; every tangent the mean of the secants
    /// either side of it (indices mod n), or 0 where they differ in sign or
    /// one is 0; then each segment in order, the wrap segment last, its flat
    /// secant zeroing both its tangents and α² + β² > 9 scaling them.
    static func periodicTangents(_ xs: [Double], _ ys: [Double], period: Double) -> [Double] {
        let n = xs.count
        guard n >= 2 else { return [Double](repeating: 0, count: n) }
        let slopes = (0..<n).map { k -> Double in
            let last = k == n - 1
            let run = last ? xs[0] + period - xs[k] : xs[k + 1] - xs[k]
            let rise = (last ? ys[0] : ys[k + 1]) - ys[k]
            return run > 0 ? rise / run : 0
        }
        var out = (0..<n).map { k -> Double in
            let into = slopes[(k + n - 1) % n]
            let from = slopes[k]
            return into * from > 0 ? (into + from) / 2 : 0
        }
        for k in 0..<n {
            let slope = slopes[k]
            let j = (k + 1) % n
            if slope == 0 {
                out[k] = 0
                out[j] = 0
                continue
            }
            let a = out[k] / slope
            let b = out[j] / slope
            let length = a * a + b * b
            if length > 9 {
                let scale = 3 / length.squareRoot()
                out[k] = scale * a * slope
                out[j] = scale * b * slope
            }
        }
        return out
    }

    /// The strip step 4c.2 samples: `size` × 2 RGBA texels, row 0 first.
    /// Row 0's texel i holds each colour's composite
    /// `channel(master(i / (size − 1)))` in r, g and b and 1 in a; row 1's
    /// (spec §11 GR-32) the hue curves at the hue h = 360·i / (size − 1):
    /// Hue vs Hue's shift in turns (degrees / 360) in r, Hue vs Sat's gain in
    /// g, 0 in b and 1 in a.
    static func strip(_ curves: ColorCurves, size: Int = stripSize) -> [Float] {
        let curves = Splines(curves)
        let n = max(size, 2)
        var out = [Float](repeating: 1, count: n * 4 * stripRows)
        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            let m = value(curves.master, at: x)
            out[4 * i] = Float(value(curves.red, at: m))
            out[4 * i + 1] = Float(value(curves.green, at: m))
            out[4 * i + 2] = Float(value(curves.blue, at: m))
        }
        for i in 0..<n {
            let hue = 360 * Double(i) / Double(n - 1)
            let at = 4 * (n + i)
            out[at] = Float(curves.hueHue.value(at: hue) / 360)
            out[at + 1] = Float(curves.hueSat.value(at: hue))
            out[at + 2] = 0
        }
        return out
    }

    fileprivate static func unit(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
