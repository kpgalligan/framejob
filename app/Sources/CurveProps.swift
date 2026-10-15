import AppKit

// MARK: - The curves (spec §11 GR-12, grading-2 G2-3; GR-32, grading-4 T4-2)

/// One curve point, `[x, y]` in JSON (`model_grade.rs`'s `CurvePoint`): the
/// input and the output, each 0…1.
struct CurvePoint: Hashable, Codable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

/// What a channel's numbers mean (spec §11 GR-32, `model_grade.rs`'s
/// `CurveDomain`): a tone curve maps 0…1 to 0…1; a hue curve maps a hue in
/// degrees (periodic, 0 ≤ x < 360) to a shift in degrees (−180…180, 0 none)
/// or a gain (0…2, 1 none). Everything the editor, the fields and the strip
/// need to treat the three alike.
enum CurveDomain: Equatable {
    case tone, hueShift, hueGain

    /// The lowest point a point may take (x, then y).
    var lower: CurvePoint {
        switch self {
        case .tone: return CurvePoint(x: 0, y: 0)
        case .hueShift: return CurvePoint(x: 0, y: -180)
        case .hueGain: return CurvePoint(x: 0, y: 0)
        }
    }

    /// The highest point a point may take: a hue point stops at 359.9, below
    /// the wrap (owner choice 6).
    var upper: CurvePoint {
        switch self {
        case .tone: return CurvePoint(x: 1, y: 1)
        case .hueShift: return CurvePoint(x: 359.9, y: 180)
        case .hueGain: return CurvePoint(x: 359.9, y: 2)
        }
    }

    /// The plot's axes from `lower`: x across, y up.
    var span: CurvePoint {
        switch self {
        case .tone: return CurvePoint(x: 1, y: 1)
        case .hueShift: return CurvePoint(x: 360, y: 360)
        case .hueGain: return CurvePoint(x: 360, y: 2)
        }
    }

    /// The x period: none for a tone curve, a turn for a hue curve.
    var period: Double? { self == .tone ? nil : 360 }

    /// The value that changes nothing: none for a tone curve (y = x).
    var neutral: Double? {
        switch self {
        case .tone: return nil
        case .hueShift: return 0
        case .hueGain: return 1
        }
    }

    /// How close a dragged point may come to a neighbour's x.
    var minGap: Double { self == .tone ? 0.001 : 0.1 }

    /// An arrow key's step, and ⇧'s (owner choice 7).
    var nudge: CurvePoint {
        switch self {
        case .tone: return CurvePoint(x: 0.01, y: 0.01)
        case .hueShift: return CurvePoint(x: 1, y: 1)
        case .hueGain: return CurvePoint(x: 1, y: 0.01)
        }
    }

    var bigNudge: CurvePoint {
        switch self {
        case .tone: return CurvePoint(x: 0.1, y: 0.1)
        case .hueShift: return CurvePoint(x: 10, y: 10)
        case .hueGain: return CurvePoint(x: 10, y: 0.1)
        }
    }

    /// The identity's shortest spelling, as the core writes an absent
    /// channel: `[[0, 0], [1, 1]]`, `[[0, 0], [180, 0]]`, `[[0, 1], [180, 1]]`.
    var identity: [CurvePoint] {
        switch self {
        case .tone: return ColorCurves.identityCurve
        case .hueShift: return [CurvePoint(x: 0, y: 0), CurvePoint(x: 180, y: 0)]
        case .hueGain: return [CurvePoint(x: 0, y: 1), CurvePoint(x: 180, y: 1)]
        }
    }

    /// The core's identity: a tone curve's `ColorCurves.isIdentity`; a hue
    /// curve with a point whose every value is the neutral, whatever its x's.
    func isIdentity(_ points: [CurvePoint]) -> Bool {
        guard let neutral else { return ColorCurves.isIdentity(points) }
        return !points.isEmpty && points.allSatisfy { $0.y == neutral }
    }
}

/// The six curves in the model's order: each one's picker title (and undo
/// "Reset <Title>") and its ink — the master's and the hue curves' the
/// strong text colour, each colour's the parade's tint.
enum CurveChannel: String, CaseIterable {
    case master, red, green, blue, hueHue = "hue_hue", hueSat = "hue_sat"

    var title: String {
        switch self {
        case .hueHue: return "Hue"
        case .hueSat: return "Sat"
        default: return rawValue.capitalized
        }
    }

    var domain: CurveDomain {
        switch self {
        case .master, .red, .green, .blue: return .tone
        case .hueHue: return .hueShift
        case .hueSat: return .hueGain
        }
    }

    var tint: NSColor {
        let index: Int
        switch self {
        case .master, .hueHue, .hueSat: return DS.textStrong
        case .red: index = 0
        case .green: index = 1
        case .blue: index = 2
        }
        let (r, g, b) = ParadeView.tints[index]
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// `video.curves`: the four tone curves and the two hue curves (spec §11
/// GR-32), each a list of 2–16 points with x strictly rising. Read
/// leniently: an absent, null or malformed channel is its domain's identity,
/// as the core writes an absent one.
struct ColorCurves: Codable, Hashable {
    let master: [CurvePoint]
    let red: [CurvePoint]
    let green: [CurvePoint]
    let blue: [CurvePoint]
    let hueHue: [CurvePoint]
    let hueSat: [CurvePoint]

    /// The tone identity's shortest spelling, `[[0, 0], [1, 1]]`.
    static let identityCurve = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    init(
        master: [CurvePoint] = identityCurve, red: [CurvePoint] = identityCurve,
        green: [CurvePoint] = identityCurve, blue: [CurvePoint] = identityCurve,
        hueHue: [CurvePoint] = CurveDomain.hueShift.identity,
        hueSat: [CurvePoint] = CurveDomain.hueGain.identity
    ) {
        self.master = master
        self.red = red
        self.green = green
        self.blue = blue
        self.hueHue = hueHue
        self.hueSat = hueSat
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func channel(_ key: CodingKeys, _ domain: CurveDomain) -> [CurvePoint] {
            let points: [CurvePoint] = c.lenient(key, domain.identity)
            return points.count >= 2 ? points : domain.identity
        }
        master = channel(.master, .tone)
        red = channel(.red, .tone)
        green = channel(.green, .tone)
        blue = channel(.blue, .tone)
        hueHue = channel(.hueHue, .hueShift)
        hueSat = channel(.hueSat, .hueGain)
    }

    static let identity = ColorCurves()

    /// The core's `curve_is_identity` for a TONE curve: first x 0, last x 1,
    /// every y = x. A channel's own test is `channel.domain.isIdentity`.
    static func isIdentity(_ curve: [CurvePoint]) -> Bool {
        guard let first = curve.first, let last = curve.last else { return false }
        return first.x == 0 && last.x == 1 && curve.allSatisfy { $0.y == $0.x }
    }

    /// The four tone curves all the identity: `curvesEnabled` is 0.
    var toneIsIdentity: Bool {
        [CurveChannel.master, .red, .green, .blue].allSatisfy { Self.isIdentity(points($0)) }
    }

    /// Both hue curves the identity: `hueCurvesEnabled` is 0.
    var hueIsIdentity: Bool {
        CurveDomain.hueShift.isIdentity(hueHue) && CurveDomain.hueGain.isIdentity(hueSat)
    }

    /// All six the identity: the strip is the placeholder.
    var isIdentity: Bool { toneIsIdentity && hueIsIdentity }

    func points(_ channel: CurveChannel) -> [CurvePoint] {
        switch channel {
        case .master: return master
        case .red: return red
        case .green: return green
        case .blue: return blue
        case .hueHue: return hueHue
        case .hueSat: return hueSat
        }
    }
}

/// What a curve write SENDS: the channels it names, each a whole list (a
/// list replaces) or `.some(nil)`, null, which removes it. An action's end
/// decodes its `curves` through this type too, so the sub-tab's `◆N` sees
/// exactly what an end holds.
struct ColorCurvesPatch: Codable, Equatable {
    var master: [CurvePoint]??
    var red: [CurvePoint]??
    var green: [CurvePoint]??
    var blue: [CurvePoint]??
    var hueHue: [CurvePoint]??
    var hueSat: [CurvePoint]??

    init(
        master: [CurvePoint]?? = nil, red: [CurvePoint]?? = nil,
        green: [CurvePoint]?? = nil, blue: [CurvePoint]?? = nil,
        hueHue: [CurvePoint]?? = nil, hueSat: [CurvePoint]?? = nil
    ) {
        self.master = master
        self.red = red
        self.green = green
        self.blue = blue
        self.hueHue = hueHue
        self.hueSat = hueSat
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        master = c.nullable(.master)
        red = c.nullable(.red)
        green = c.nullable(.green)
        blue = c.nullable(.blue)
        hueHue = c.nullable(.hueHue)
        hueSat = c.nullable(.hueSat)
    }

    /// The section's Reset on the base: all six null.
    static let reset = ColorCurvesPatch(
        master: .some(nil), red: .some(nil), green: .some(nil), blue: .some(nil),
        hueHue: .some(nil), hueSat: .some(nil))

    /// Reset inside an action: each named channel its domain's identity,
    /// which an end keeps as "animate to neutral" (`null` there would remove
    /// the key instead).
    static func neutral(_ channels: [CurveChannel]) -> ColorCurvesPatch {
        var patch = ColorCurvesPatch()
        for channel in channels { patch = patch.setting(channel, .some(channel.domain.identity)) }
        return patch
    }

    /// One channel's whole list, or nil to remove it.
    static func channel(_ channel: CurveChannel, _ points: [CurvePoint]?) -> ColorCurvesPatch {
        ColorCurvesPatch().setting(channel, .some(points))
    }

    /// This patch with `channel`'s entry replaced: nil leaves the channel
    /// out of the write, `.some(nil)` removes it, a list replaces it.
    func setting(_ channel: CurveChannel, _ entry: [CurvePoint]??) -> ColorCurvesPatch {
        var patch = self
        switch channel {
        case .master: patch.master = entry
        case .red: patch.red = entry
        case .green: patch.green = entry
        case .blue: patch.blue = entry
        case .hueHue: patch.hueHue = entry
        case .hueSat: patch.hueSat = entry
        }
        return patch
    }

    /// The channel's entry: nil when the write does not name it.
    func entry(_ channel: CurveChannel) -> [CurvePoint]?? {
        switch channel {
        case .master: return master
        case .red: return red
        case .green: return green
        case .blue: return blue
        case .hueHue: return hueHue
        case .hueSat: return hueSat
        }
    }

    var isEmpty: Bool { CurveChannel.allCases.allSatisfy { entry($0) == nil } }
}

extension LayerUniforms {
    /// The curves' flags (spec §11 GR-12, GR-32): `curvesEnabled` 1 exactly
    /// when one of the four tone curves is not the identity, and
    /// `hueCurvesEnabled` 1 exactly when a hue curve is not, so a layer
    /// without them never enters either half of step 4c.2 and renders
    /// byte-identical. The curves themselves travel in the strip at
    /// `texture(3)` (`CurveTextures`), not in the block.
    mutating func apply(curves: ColorCurves) {
        curvesEnabled = curves.toneIsIdentity ? 0 : 1
        hueCurvesEnabled = curves.hueIsIdentity ? 0 : 1
    }
}
