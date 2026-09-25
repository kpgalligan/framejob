import Foundation

/// A graphic clip's description (format version 10, road map 10's G2a) —
/// the mirror of `core/src/model_graphic.rs`'s `GraphicProps`: which module
/// in the package's `graphics/` draws the clip, at what size, over which
/// stretch of its own timeline, with which props.
///
/// In its own file because `ProjectSnapshot.swift` is on the size ledger;
/// `ClipSnapshot` takes only the stored field and its decode line.
///
/// Decoding is LENIENT for `ProjectSnapshot.swift`'s reason — these are
/// values the CORE wrote — and every default mirrors the core's `Default`
/// (an empty name, a 0 × 0 size, `in` 0, no length, no props). A caller's
/// object is never decoded through it (app/CLAUDE.md).
struct GraphicSnapshot: Codable, Equatable {
    /// The module, `graphics/<name>.js` (G-3).
    let name: String
    /// The size the module draws at, in pixels — the layer's source size.
    let width: Int
    let height: Int
    /// The graphic's own frame the clip's first frame shows, in ticks. The
    /// core's key is `in`, a Swift keyword, hence the explicit coding key.
    let sourceIn: Ticks
    /// The graphic's own length in ticks; nil is "the clip's duration" (G-9).
    let length: Ticks?
    /// The values the module is drawn with.
    let props: [String: GraphicPropValue]

    private enum CodingKeys: String, CodingKey {
        case name, width, height, length, props
        case sourceIn = "in"
    }

    init(
        name: String = "", width: Int = 0, height: Int = 0, sourceIn: Ticks = 0,
        length: Ticks? = nil, props: [String: GraphicPropValue] = [:]
    ) {
        self.name = name
        self.width = width
        self.height = height
        self.sourceIn = sourceIn
        self.length = length
        self.props = props
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(.name, "")
        width = c.lenient(.width, 0)
        height = c.lenient(.height, 0)
        sourceIn = c.lenient(.sourceIn, 0)
        length = c.lenient(.length)
        props = c.lenient(.props, [:])
    }
}

/// One prop's value as the core stores it: a string (a colour is already a
/// normalised hex string, G-12), a number or a boolean. Anything else — an
/// array, an object — decodes as `.null` rather than failing the clip.
enum GraphicPropValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        case .null: try c.encodeNil()
        }
    }
}

/// The keys of a recipe layer's `graphic` source (spec §7.3; road map 10
/// §5d, G3b), read through a SECOND keyed container on the decoder
/// `RecipeSourceRef` decodes from — its own `CodingKeys` is private, and
/// `ProjectSnapshot.swift` is on the size ledger. `props_json` and
/// `ctx_json` arrive camel-cased by `ReelJSON.decoder()`'s converter.
enum GraphicSourceKeys: String, CodingKey {
    case name, hash, frame
    case propsJSON = "propsJson"
    case ctxJSON = "ctxJson"
}

extension RecipeSourceRef {
    /// The `graphic` arm's decode. Lenient, with "" and 0 as the defaults:
    /// an empty JSON text fails in the engine and the layer draws the slate.
    /// The two texts are the core's own serialization of `props` and `ctx`,
    /// handed to the engine untouched — never re-encoded here.
    static func graphic(from decoder: Decoder) -> RecipeSourceRef {
        guard let c = try? decoder.container(keyedBy: GraphicSourceKeys.self) else {
            return .graphic(name: "", hash: "", frame: 0, propsJSON: "", ctxJSON: "")
        }
        return .graphic(
            name: c.lenient(.name, ""), hash: c.lenient(.hash, ""), frame: c.lenient(.frame, 0),
            propsJSON: c.lenient(.propsJSON, ""), ctxJSON: c.lenient(.ctxJSON, ""))
    }

    /// The `graphic` arm's encode, beside the `kind` it shares with every arm.
    func encodeGraphic(to encoder: Encoder) throws {
        guard case .graphic(let name, let hash, let frame, let propsJSON, let ctxJSON) = self
        else { return }
        var kind = encoder.container(keyedBy: GraphicKindKey.self)
        try kind.encode("graphic", forKey: .kind)
        var c = encoder.container(keyedBy: GraphicSourceKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(hash, forKey: .hash)
        try c.encode(frame, forKey: .frame)
        try c.encode(propsJSON, forKey: .propsJSON)
        try c.encode(ctxJSON, forKey: .ctxJSON)
    }

    private enum GraphicKindKey: String, CodingKey { case kind }
}
