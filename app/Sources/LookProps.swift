import Foundation

// MARK: - Looks' value types (road map grading, spec §11 GR-7)

/// The eight built-in looks, in `model_look.rs`'s declaration order — the
/// gallery's and the menu's order (append, never reorder) — and `lut`, an
/// imported `.cube` file (spec §11 GR-8), which is not one of `builtIns`.
/// Closed, and
/// decoded by RAW VALUE, so `JSONDecoder`'s `.convertFromSnakeCase` never
/// touches these spellings. The core is the one place a look is DEFINED; this
/// side only names them and reads the definition the recipe publishes.
enum LookKind: String, Codable, CaseIterable {
    case warm
    case cool
    case tealOrange = "teal_orange"
    case vivid
    case faded
    case vintage
    case dramatic
    case blackWhite = "black_white"
    case lut

    /// The eight built-in looks, the gallery's tiles and the menu's items.
    static let builtIns: [LookKind] = allCases.filter { $0 != .lut }

    var displayName: String {
        switch self {
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .tealOrange: return "Teal & Orange"
        case .vivid: return "Vivid"
        case .faded: return "Faded"
        case .vintage: return "Vintage"
        case .dramatic: return "Dramatic"
        case .blackWhite: return "Black & White"
        case .lut: return "LUT"
        }
    }
}

/// A clip's stored look, `video.look`: which, and how much (0…1), and for a
/// `lut` look its media id (GR-8). Absent — nil on `VideoProps` — is no
/// look. A `look` with no readable kind decodes as nil, which is what the
/// core makes of one too.
struct LookProps: Codable, Equatable {
    let kind: LookKind
    let amount: Double
    let media: UInt32?

    init(kind: LookKind, amount: Double = 1, media: UInt32? = nil) {
        self.kind = kind
        self.amount = amount
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(LookKind.self, forKey: .kind)
        amount = c.lenient(.amount, 1)
        media = c.lenient(.media)
    }
}

/// What a look write SENDS: a kind, an amount, or both, and a LUT's `media`
/// with kind `lut` (GR-8). A kind alone keeps each clip's amount (1 on a clip
/// with none, the core's default); an amount alone is refused by the core on
/// a clip with no look. Removing the look is `VideoPatch.look = .some(nil)`.
struct LookPatch: Codable, Equatable {
    var kind: LookKind?
    var amount: Double?
    var media: UInt32?

    init(kind: LookKind? = nil, amount: Double? = nil, media: UInt32? = nil) {
        self.kind = kind
        self.amount = amount
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind)
        amount = c.lenient(.amount)
        media = c.lenient(.media)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let kind = kind { d["kind"] = kind.rawValue }
        if let amount = amount { d["amount"] = amount }
        if let media = media { d["media"] = media }
        return d
    }
}

/// A look's split tone, as the recipe publishes it: two hues in degrees,
/// each with an amount 0…1. Mirrors `model_look.rs`'s `SplitTone`.
struct SplitTone: Codable, Hashable {
    let shadowHue: Double
    let shadowAmount: Double
    let highlightHue: Double
    let highlightAmount: Double

    static let none = SplitTone(shadowHue: 0, shadowAmount: 0, highlightHue: 0, highlightAmount: 0)
}

extension SplitTone {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shadowHue = c.lenient(.shadowHue, 0)
        shadowAmount = c.lenient(.shadowAmount, 0)
        highlightHue = c.lenient(.highlightHue, 0)
        highlightAmount = c.lenient(.highlightAmount, 0)
    }
}

/// What a look IS — the colour (all thirteen keys) and split tone its
/// lattice is baked from, read off the recipe. Hashable because it is
/// `LookTextures`' cache key: two layers with one definition share a bake.
struct LookDefinition: Codable, Hashable {
    let color: ColorAdjust
    let split: SplitTone

    /// The definition that bakes the identity lattice.
    static let identity = LookDefinition(color: .identity, split: .none)
}

extension LookDefinition {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.lenient(.color, ColorAdjust.identity)
        split = c.lenient(.split, SplitTone.none)
    }
}

/// A recipe layer's `look` (spec §7.3): how much, and the definition to
/// bake — or, for a LUT look (GR-8), the media whose `.cube` file to draw,
/// with no definition. The core publishes `null` for no look, an amount of 0
/// and an ungraded frame, so a non-nil one always has an amount above 0; its
/// kind is on the wire for a reader and is not needed to draw.
struct RecipeLook: Codable, Equatable {
    let amount: Double
    let definition: LookDefinition
    let media: UInt32?

    init(amount: Double, definition: LookDefinition, media: UInt32? = nil) {
        self.amount = amount
        self.definition = definition
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = c.lenient(.amount, 0)
        definition = c.lenient(.definition, LookDefinition.identity)
        media = c.lenient(.media)
    }
}

extension LayerUniforms {
    /// The look's two floats (spec §11 GR-7): step 4d's mix, 0…1, and
    /// `lookEnabled`, 1 exactly when there is a look with an amount above 0
    /// — the effects gate's term, so a look-less layer never samples
    /// `texture(2)` and renders byte-identical.
    mutating func apply(look: RecipeLook?) {
        let amount = look?.amount ?? 0
        lookAmount = Float(min(max(amount, 0), 1))
        lookEnabled = look != nil && amount > 0 ? 1 : 0
    }
}
