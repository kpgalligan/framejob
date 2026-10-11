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
enum CurveTable {
    static let stripSize = 1024

    /// The curve through `points` (x strictly rising) at `x`, clamped 0…1.
    /// Fewer than two points is the identity. A caller sampling one curve
    /// many times builds a `Spline` once instead.
    static func value(_ points: [CurvePoint], at x: Double) -> Double {
        Spline(points).value(at: x)
    }

    /// One curve's points and tangents, computed once and sampled often:
    /// the strip samples each curve 1,024 times, the editor once per plot
    /// point.
    struct Spline {
        let xs: [Double]
        let ys: [Double]
        let m: [Double]

        init(_ points: [CurvePoint]) {
            xs = points.map(\.x)
            ys = points.map(\.y)
            m = points.count >= 2 ? CurveTable.tangents(xs, ys) : []
        }

        func value(at x: Double) -> Double {
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
    }

    /// The four channels' splines, so `strip` builds each once.
    private struct Splines {
        let master: Spline
        let red: Spline
        let green: Spline
        let blue: Spline

        init(_ curves: ColorCurves) {
            master = Spline(curves.master)
            red = Spline(curves.red)
            green = Spline(curves.green)
            blue = Spline(curves.blue)
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

    /// The strip step 4c.2 samples: `size` RGBA texels, texel i holding each
    /// colour's composite `channel(master(i / (size − 1)))` in r, g and b and
    /// 1 in a.
    static func strip(_ curves: ColorCurves, size: Int = stripSize) -> [Float] {
        let curves = Splines(curves)
        let n = max(size, 2)
        var out = [Float](repeating: 1, count: n * 4)
        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            let m = value(curves.master, at: x)
            out[4 * i] = Float(value(curves.red, at: m))
            out[4 * i + 1] = Float(value(curves.green, at: m))
            out[4 * i + 2] = Float(value(curves.blue, at: m))
        }
        return out
    }

    fileprivate static func unit(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
