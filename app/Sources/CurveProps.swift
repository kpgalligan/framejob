import AppKit

// MARK: - The curves (spec §11 GR-12, grading-2 G2-3)

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

/// The four curves in the model's order: each one's picker title (and undo
/// "Reset <Title>") and its ink — the master's the strong text colour, each
/// colour's the parade's tint.
enum CurveChannel: String, CaseIterable {
    case master, red, green, blue

    var title: String { rawValue.capitalized }

    var tint: NSColor {
        let index: Int
        switch self {
        case .master: return DS.textStrong
        case .red: index = 0
        case .green: index = 1
        case .blue: index = 2
        }
        let (r, g, b) = ParadeView.tints[index]
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// `video.curves`: the four curves, each a list of 2–16 points with x
/// strictly rising. Read leniently: an absent, null or malformed channel is
/// the identity, as the core writes an absent one.
struct ColorCurves: Codable, Hashable {
    let master: [CurvePoint]
    let red: [CurvePoint]
    let green: [CurvePoint]
    let blue: [CurvePoint]

    /// The identity's shortest spelling, `[[0, 0], [1, 1]]`.
    static let identityCurve = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    init(
        master: [CurvePoint] = identityCurve, red: [CurvePoint] = identityCurve,
        green: [CurvePoint] = identityCurve, blue: [CurvePoint] = identityCurve
    ) {
        self.master = master
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func channel(_ key: CodingKeys) -> [CurvePoint] {
            let points: [CurvePoint] = c.lenient(key, Self.identityCurve)
            return points.count >= 2 ? points : Self.identityCurve
        }
        master = channel(.master)
        red = channel(.red)
        green = channel(.green)
        blue = channel(.blue)
    }

    static let identity = ColorCurves()

    /// The core's `curve_is_identity`: first x 0, last x 1, every y = x.
    static func isIdentity(_ curve: [CurvePoint]) -> Bool {
        guard let first = curve.first, let last = curve.last else { return false }
        return first.x == 0 && last.x == 1 && curve.allSatisfy { $0.y == $0.x }
    }

    var isIdentity: Bool { CurveChannel.allCases.allSatisfy { Self.isIdentity(points($0)) } }

    func points(_ channel: CurveChannel) -> [CurvePoint] {
        switch channel {
        case .master: return master
        case .red: return red
        case .green: return green
        case .blue: return blue
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

    init(
        master: [CurvePoint]?? = nil, red: [CurvePoint]?? = nil,
        green: [CurvePoint]?? = nil, blue: [CurvePoint]?? = nil
    ) {
        self.master = master
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        master = c.nullable(.master)
        red = c.nullable(.red)
        green = c.nullable(.green)
        blue = c.nullable(.blue)
    }

    /// The section's Reset on the base: all four null.
    static let reset = ColorCurvesPatch(
        master: .some(nil), red: .some(nil), green: .some(nil), blue: .some(nil))

    /// Reset inside an action: each named channel the identity curve, which
    /// an end keeps as "animate to neutral" (`null` there would remove the
    /// key instead).
    static func neutral(_ channels: [CurveChannel]) -> ColorCurvesPatch {
        var patch = ColorCurvesPatch()
        for channel in channels { patch = patch.setting(channel, .some(ColorCurves.identityCurve)) }
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
        }
    }

    var isEmpty: Bool { CurveChannel.allCases.allSatisfy { entry($0) == nil } }
}

extension LayerUniforms {
    /// The curves' flag (spec §11 GR-12): `curvesEnabled` 1 exactly when one
    /// of the four is not the identity, so an uncurved layer never enters
    /// step 4c.2 and renders byte-identical. The curves themselves travel in
    /// the strip at `texture(3)` (`CurveTextures`), not in the block.
    mutating func apply(curves: ColorCurves) {
        curvesEnabled = curves.isIdentity ? 0 : 1
    }
}
