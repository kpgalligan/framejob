import Foundation

/// The four scopes of View ▸ Scopes (spec §11 GR-5, GR-10), in the order the
/// pickers list them and every pass, delivery and sentence runs. The raw
/// values are `render_frame`'s argument names and its JSON files' suffixes
/// (`<path>.<raw>.json`).
enum ScopeKind: String, CaseIterable {
    case waveform, parade, vectorscope, histogram

    /// The picker's item.
    var title: String {
        switch self {
        case .waveform: return "Waveform"
        case .parade: return "Parade"
        case .vectorscope: return "Vectorscope"
        case .histogram: return "Histogram"
        }
    }
}

/// One pass the analyser runs: a scope and, for the vectorscope, its zoom
/// (spec §11 GR-31). Every other kind's zoom is 1, so a set of passes holds
/// one pass per kind but the vectorscope, which may hold one per zoom (two
/// vectorscope slots at different zooms).
struct ScopePass: Hashable {
    let kind: ScopeKind
    /// 1 for every kind but `.vectorscope`.
    let zoom: Int

    init(_ kind: ScopeKind, zoom: Int = 1) {
        self.kind = kind
        self.zoom = kind == .vectorscope ? zoom : 1
    }

    /// `passes` in the order every pass, delivery and sentence runs:
    /// `ScopeKind.allCases`, then zoom ascending.
    static func ordered(_ passes: Set<ScopePass>) -> [ScopePass] {
        passes.sorted { a, b in
            let ka = ScopeKind.allCases.firstIndex(of: a.kind) ?? 0
            let kb = ScopeKind.allCases.firstIndex(of: b.kind) ?? 0
            return ka != kb ? ka < kb : a.zoom < b.zoom
        }
    }
}

/// One frame's RGB parade (GR-10): R′, G′ and B′ each binned as
/// `WaveformTrace` bins Y′ — 256 column bins × 256 levels of the saturated
/// encoded values — so each channel IS a waveform trace, with its marks and
/// readouts.
struct ParadeTrace: Equatable {
    /// `counts[(channel * columns + column) * levels + level]`, channel 0 R′,
    /// 1 G′, 2 B′.
    let counts: [UInt32]
    let width: Int
    let height: Int

    static let channelNames = ["red", "green", "blue"]

    /// Channel `index` (0 R′, 1 G′, 2 B′) as a waveform trace of the same
    /// frame.
    func channel(_ index: Int) -> WaveformTrace {
        let size = WaveformTrace.columns * WaveformTrace.levels
        return WaveformTrace(
            counts: Array(counts[(index * size)..<((index + 1) * size)]), width: width,
            height: height)
    }

    /// What `render_frame {parade}` writes: each channel's counts as 256
    /// arrays by column, each indexed by level, and each channel's marks and
    /// clip counts, keyed red, green and blue.
    func json() -> [String: Any] {
        var byChannel: [String: Any] = [:]
        var marksHigh: [String: Any] = [:]
        var marksLow: [String: Any] = [:]
        var clippedHigh: [String: Any] = [:]
        var clippedLow: [String: Any] = [:]
        for (index, name) in Self.channelNames.enumerated() {
            let trace = channel(index)
            let one = trace.json()
            byChannel[name] = one["counts"]
            marksHigh[name] = one["marks_high"]
            marksLow[name] = one["marks_low"]
            clippedHigh[name] = trace.clippedHigh
            clippedLow[name] = trace.clippedLow
        }
        return [
            "columns": WaveformTrace.columns, "levels": WaveformTrace.levels, "width": width,
            "height": height, "counts": byChannel, "marks_high": marksHigh,
            "marks_low": marksLow, "clipped_high": clippedHigh, "clipped_low": clippedLow,
        ]
    }
}

/// One frame's vectorscope (GR-10): Rec. 709 `Cb = (B′ − Y′)/1.8556` and
/// `Cr = (R′ − Y′)/1.5748` of the saturated encoded values, Y′ being GR-5's,
/// in 256 × 256 bins centred on neutral — `bin = clamp(128 + round(255·c),
/// 0, 255)` — so a grey is mid-bin 128. Cb runs right and Cr up.
///
/// **At a zoom** (GR-31) the bins are `128 + round(255·zoom·c)`: clamped at
/// ×1 as above, and at ×2 and ×4 a pixel whose bin falls off 0…255 is not
/// counted; `offPlot` is how many were not.
struct VectorscopeTrace: Equatable {
    static let bins = 256
    /// The neutral bin on both axes.
    static let centre = 128
    /// The bins the kernel counts in threadgroup memory on both axes.
    static let central = 96..<160
    /// The zooms a slot and `render_frame {vectorscope_zoom}` offer.
    static let zooms = [1, 2, 4]

    /// `counts[crBin * bins + cbBin]`.
    let counts: [UInt32]
    let width: Int
    let height: Int
    /// The zoom the counts were binned at.
    var zoom: Int = 1
    /// Pixels not counted, off the plot: `width·height − Σcounts`, 0 at ×1.
    var offPlot: Int = 0

    /// Rec. 709 Cb and Cr of an encoded colour, each 0…1 component.
    static func chroma(r: Double, g: Double, b: Double) -> (cb: Double, cr: Double) {
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return ((b - luma) / 1.8556, (r - luma) / 1.5748)
    }

    /// A Cb or Cr value's bin, as the kernel bins it at ×1.
    static func bin(_ c: Double) -> Int {
        min(bins - 1, max(0, centre + Int((255 * c).rounded())))
    }

    /// A Cb or Cr value's bin at `zoom`, as the kernel bins it: at ×1
    /// `bin(_:)`, clamped; above it nil when the bin is off the plot.
    static func bin(_ c: Double, zoom: Int) -> Int? {
        guard zoom > 1 else { return bin(c) }
        let raw = centre + Int((255 * Double(zoom) * c).rounded())
        return (0..<bins).contains(raw) ? raw : nil
    }

    /// The six 75 % colour-bar targets, computed through `chroma`.
    static let targets: [(name: String, cb: Double, cr: Double)] = [
        ("R", 0.75, 0.0, 0.0), ("Mg", 0.75, 0.0, 0.75), ("B", 0.0, 0.0, 0.75),
        ("Cy", 0.0, 0.75, 0.75), ("G", 0.0, 0.75, 0.0), ("Yl", 0.75, 0.75, 0.0),
    ].map { name, r, g, b in
        let c = chroma(r: r, g: g, b: b)
        return (name, c.cb, c.cr)
    }

    /// The skin line's angle, counter-clockwise from +Cb: the hue of the
    /// ColorChecker Classic "light skin" patch's published sRGB (194, 150,
    /// 130) through the matrix (GR-10: 123.3°).
    static let skinLineDegrees: Double = {
        let c = chroma(r: 194.0 / 255, g: 150.0 / 255, b: 130.0 / 255)
        return atan2(c.cr, c.cb) * 180 / .pi
    }()

    /// Pixels in the neutral bin (128, 128).
    var neutral: Int { Int(counts[Self.centre * Self.bins + Self.centre]) }

    /// The neutral bin's share of the frame, in percent.
    var neutralPercent: Double { 100 * Double(neutral) / Double(max(width * height, 1)) }

    /// The share of the frame left off the plot, in percent.
    var offPlotPercent: Double { 100 * Double(offPlot) / Double(max(width * height, 1)) }

    /// A target's bins at `zoom`, or nil when either is off the plot.
    static func targetBins(cb: Double, cr: Double, zoom: Int) -> (cb: Int, cr: Int)? {
        guard let x = bin(cb, zoom: zoom), let y = bin(cr, zoom: zoom) else { return nil }
        return (x, y)
    }

    /// What `render_frame {vectorscope}` writes: the counts as 256 arrays by
    /// Cr bin, each indexed by Cb bin, the neutral count, the zoom and the
    /// off-plot count, the targets' bins at the zoom (null off the plot) and
    /// the skin line.
    func json() -> [String: Any] {
        let side = Self.bins
        let byCr = (0..<side).map { cr in
            counts[(cr * side)..<((cr + 1) * side)].map { Int($0) }
        }
        var targets: [String: Any] = [:]
        for target in Self.targets {
            let at = Self.targetBins(cb: target.cb, cr: target.cr, zoom: zoom)
            targets[target.name] = at.map { [$0.cb, $0.cr] as Any } ?? NSNull()
        }
        return [
            "bins": side, "centre": Self.centre, "width": width, "height": height,
            "matrix": "Rec. 709", "values": "encoded", "counts": byCr, "neutral": neutral,
            "zoom": zoom, "off_plot": offPlot,
            "targets": targets, "skin_line_degrees": Self.skinLineDegrees,
        ]
    }
}

/// One frame's histogram (GR-10): R′, G′, B′ and Y′ counts per 256 levels of
/// the saturated encoded values (GR-5's level rule), with the waveform's two
/// clipping readouts read from Y′.
struct HistogramTrace: Equatable {
    /// `counts[plane * levels + level]`, plane 0 R′, 1 G′, 2 B′, 3 Y′.
    let counts: [UInt32]
    let width: Int
    let height: Int

    static let planeNames = ["red", "green", "blue", "luma"]

    /// Plane `index`'s 256 counts.
    func plane(_ index: Int) -> [UInt32] {
        let levels = WaveformTrace.levels
        return Array(counts[(index * levels)..<((index + 1) * levels)])
    }

    /// Pixels whose Y′ is at level 255.
    var clippedHigh: Int { Int(counts[3 * WaveformTrace.levels + WaveformTrace.levels - 1]) }
    /// Pixels whose Y′ is at level 0.
    var clippedLow: Int { Int(counts[3 * WaveformTrace.levels]) }

    var highlightsPercent: Double { percent(clippedHigh) }
    var shadowsPercent: Double { percent(clippedLow) }

    var highlightsReadout: String {
        "Highlights clipped " + WaveformTrace.spelled(highlightsPercent)
    }
    var shadowsReadout: String { "Shadows clipped " + WaveformTrace.spelled(shadowsPercent) }

    /// What `render_frame {histogram}` writes: each plane's 256 counts and
    /// both clipping figures.
    func json() -> [String: Any] {
        var body: [String: Any] = [
            "levels": WaveformTrace.levels, "width": width, "height": height,
            "clipped_high": clippedHigh, "clipped_low": clippedLow,
            "highlights": highlightsPercent, "shadows": shadowsPercent,
        ]
        for (index, name) in Self.planeNames.enumerated() {
            body[name] = plane(index).map { Int($0) }
        }
        return body
    }

    private func percent(_ count: Int) -> Double {
        100 * Double(count) / Double(max(width * height, 1))
    }
}

/// Any one scope's trace, as the analyser answers it and the panel's slots
/// draw it.
enum ScopeTrace: Equatable {
    case waveform(WaveformTrace)
    case parade(ParadeTrace)
    case vectorscope(VectorscopeTrace)
    case histogram(HistogramTrace)

    var kind: ScopeKind {
        switch self {
        case .waveform: return .waveform
        case .parade: return .parade
        case .vectorscope: return .vectorscope
        case .histogram: return .histogram
        }
    }

    /// What `render_frame` writes to `<path>.<kind>.json`.
    func json() -> [String: Any] {
        switch self {
        case .waveform(let trace): return trace.json()
        case .parade(let trace): return trace.json()
        case .vectorscope(let trace): return trace.json()
        case .histogram(let trace): return trace.json()
        }
    }
}
