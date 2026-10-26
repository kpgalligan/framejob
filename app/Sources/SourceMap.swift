import Foundation

/// A clip id's source map, or nil — how a reader is handed the maps of the
/// handle its snapshot came from (`ReelProject.sourceMap`), so a reader
/// never asks the core itself (spec §11 SR-20 (d)).
typealias SourceMaps = (UInt32) -> SourceMap?

/// One sample of the core's rate profile (spec §11 SR-26): the rate the clip
/// plays at clip tick `tick`.
struct RatePoint: Equatable {
    let tick: Ticks
    let rate: Double
}

/// A media clip's source map (spec §11 SR-20): the core's own
/// `[clip tick, source tick]` pairs from `rc_project_source_map`, or a plan
/// ramp segment's map, and the ONE place Swift reads between them — linearly,
/// as `RampAudioRenderer` plays them. Swift computes no rate (spec §11 D2-1):
/// a ramped clip's pairs come from the core's S, a constant clip's two points
/// from its `in` and its length in source.
///
/// **Checked once, read by binary search** (SR-20 (c)). A ramp's map holds a
/// point every 600 ticks — about 100 000 for a 60 s ramp — and the waveform
/// reads it per pixel column, the silence walk per 10 ms bucket. So the list
/// is checked ONCE, when it is decoded (`init(ramped:points:)`, O(n)), and a
/// reading finds its bracketing pair by binary search, O(log n), in either
/// direction. There is no static or per-call form: a reading never re-checks
/// the list.
struct SourceMap: Equatable {
    /// Whether the clip ramps. A reader takes the map only when it does
    /// (SR-20 (b)); a constant clip keeps its own arithmetic byte for byte.
    let ramped: Bool
    /// `[clip tick, source tick]`, the core's own, both columns strictly
    /// increasing from clip tick 0.
    let points: [[Ticks]]
    /// The core's `rate` list, checked (spec §11 SR-26): what the action
    /// lanes draw (`RateGraph`). [] for a constant map, a missing key, or a
    /// list that fails the check — which never costs the map its `points`.
    let rate: [RatePoint]

    /// The one check: at least two pairs, each of two, the first at clip
    /// tick 0, both columns strictly increasing. nil otherwise, and a nil map
    /// sends its reader down the constant path. `rate` is kept on a ramped
    /// map when it has at least two points, the first at tick 0 and the last
    /// at the map's last clip tick, ticks never falling, every rate finite
    /// and above 0; otherwise it is [].
    init?(ramped: Bool, points: [[Ticks]], rate: [RatePoint] = []) {
        guard points.count >= 2, let first = points.first, first.count == 2, first[0] == 0
        else { return nil }
        var previous = first
        for pair in points.dropFirst() {
            guard pair.count == 2, pair[0] > previous[0], pair[1] > previous[1] else { return nil }
            previous = pair
        }
        self.ramped = ramped
        self.points = points
        self.rate = ramped && Self.rateHolds(rate, end: previous[0]) ? rate : []
    }

    /// `rate`'s check, against the map's last clip tick `end`.
    private static func rateHolds(_ rate: [RatePoint], end: Ticks) -> Bool {
        guard rate.count >= 2, rate[0].tick == 0, rate[rate.count - 1].tick == end else {
            return false
        }
        var previous = rate[0].tick
        for point in rate {
            guard point.tick >= previous, point.rate.isFinite, point.rate > 0 else { return false }
            previous = point.tick
        }
        return true
    }

    /// `rc_project_source_map`'s answer, `{"ramped": bool, "map": [[c, s], …]}`
    /// and, on a ramped clip, `"rate": [[c, r], …]`, decoded and then checked
    /// by the initialiser above; a `rate` row that is not two numbers makes
    /// the whole list [].
    init?(json: String) {
        guard let object = CoreJSON.value(json) as? [String: Any],
              let ramped = object["ramped"] as? Bool,
              let rows = object["map"] as? [[NSNumber]]
        else { return nil }
        let rateRows = object["rate"] as? [[NSNumber]] ?? []
        let rate = rateRows.allSatisfy { $0.count == 2 }
            ? rateRows.map { RatePoint(tick: $0[0].int64Value, rate: $0[1].doubleValue) } : []
        self.init(
            ramped: ramped, points: rows.map { row in row.map { $0.int64Value } }, rate: rate)
    }

    /// The source tick at the clip's first tick.
    var sourceIn: Ticks { points[0][1] }

    /// How many source ticks the clip reads, first pair to last.
    var sourceLength: Ticks { points[points.count - 1][1] - points[0][1] }

    /// The source tick (unrounded) at clip tick `t`, `t` clamped to the
    /// map's clip ticks [0, D]; linear between the bracketing pair, exact at
    /// every pair.
    func source(atClip t: Double) -> Double {
        interpolate(t, from: 0, to: 1)
    }

    /// The clip tick (unrounded) at source tick `s`, `s` clamped to the
    /// map's source ticks; linear between the bracketing pair, exact at
    /// every pair.
    func clip(atSource s: Double) -> Double {
        interpolate(s, from: 1, to: 0)
    }

    /// Column `to` at `value` on column `from`: the pair bracketing `value`
    /// found by binary search (both columns rise, so either can be searched),
    /// then the chord between them.
    private func interpolate(_ value: Double, from: Int, to: Int) -> Double {
        let lastIndex = points.count - 1
        let x = min(max(value, Double(points[0][from])), Double(points[lastIndex][from]))
        // Invariant: points[lo][from] <= x, and x < points[hi][from] or hi is the last.
        var lo = 0
        var hi = lastIndex
        while hi - lo > 1 {
            let mid = lo + (hi - lo) / 2
            if Double(points[mid][from]) <= x { lo = mid } else { hi = mid }
        }
        let a = points[lo]
        let b = points[hi]
        return Double(a[to])
            + (x - Double(a[from])) * Double(b[to] - a[to]) / Double(b[from] - a[from])
    }
}
