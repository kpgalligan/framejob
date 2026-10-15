import AppKit

// MARK: - Frame recipe (spec §7.3)

/// The canvas facts a recipe carries, so the compositor never needs the
/// project to clear a frame.
struct RecipeCanvas: Codable, Equatable {
    let width: Int
    let height: Int
    let background: RGBA

    init(width: Int = 1920, height: Int = 1080, background: RGBA = [0, 0, 0, 1]) {
        self.width = width
        self.height = height
        self.background = background
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        background = c.lenient(.background, [0, 0, 0, 1])
    }

    var size: CGSize { CGSize(width: width, height: height) }
}

/// Where a recipe layer's pixels come from. Internally tagged by `kind`.
enum RecipeSourceRef: Codable, Equatable {
    /// A composition video track, named by the same id `CompositionBuilder`
    /// passed as `preferredTrackID` (§7.2).
    case track(Int)
    /// A still image file; Swift decodes with ImageIO and caches the texture.
    case image(UInt32)
    /// Resolved text, its computed reveal, and a stable content hash to cache
    /// the texture by — one hash over BOTH, so a half-revealed frame can
    /// never collide with the whole text's texture.
    case text(hash: String, props: TextProps, reveal: RecipeReveal)
    case shape(hash: String, props: ShapeProps)
    case graphic(name: String, hash: String, frame: Int, propsJSON: String, ctxJSON: String)
    /// The media could not be resolved — draw a slate.
    case missing
    /// An adjustment clip (spec §11 GR-6): no picture; the layer grades the
    /// destination behind it (`Compositor+Adjustment.swift`), weighted by its
    /// `qualifier` (GR-13; `.none` when the source carries none). `selection`
    /// is Show Selection's mark: the pass writes the qualifier's selection
    /// as grey instead of grading.
    case adjustment(qualifier: ColorQualifier, selection: Bool)

    private enum CodingKeys: String, CodingKey {
        case kind, media, hash, text, shape, qualifier, selection
        // `track_id` converts to `trackId`, not `trackID`; spell it the way
        // the converter does or this key silently never matches.
        case trackID = "trackId"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(.kind, "missing")
        switch kind {
        case "track":
            self = .track(c.lenient(.trackID, 0))
        case "image":
            self = .image(c.lenient(.media, 0))
        case "text":
            // The amount falls back to 1 and the kind to nil, so a recipe
            // this build cannot read draws the whole text rather than none
            // of it.
            self = .text(
                hash: c.lenient(.hash, ""), props: c.lenient(.text, TextProps()),
                reveal: RecipeReveal(siblingsOf: decoder))
        case "shape":
            self = .shape(hash: c.lenient(.hash, ""), props: c.lenient(.shape, ShapeProps()))
        case "graphic": self = RecipeSourceRef.graphic(from: decoder)
        case "adjustment":
            self = .adjustment(
                qualifier: c.lenient(.qualifier, ColorQualifier.none),
                selection: c.lenient(.selection, false))
        default:
            self = .missing
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .track(let id):
            try c.encode("track", forKey: .kind)
            try c.encode(id, forKey: .trackID)
        case .image(let id):
            try c.encode("image", forKey: .kind)
            try c.encode(id, forKey: .media)
        case .text(let hash, let props, let reveal):
            try c.encode("text", forKey: .kind)
            try c.encode(hash, forKey: .hash)
            try c.encode(props, forKey: .text)
            try reveal.encodeSiblings(to: encoder)
        case .shape(let hash, let props):
            try c.encode("shape", forKey: .kind)
            try c.encode(hash, forKey: .hash)
            try c.encode(props, forKey: .shape)
        case .graphic: try encodeGraphic(to: encoder)
        case .missing:
            try c.encode("missing", forKey: .kind)
        case .adjustment(let qualifier, let selection):
            try c.encode("adjustment", forKey: .kind)
            if !qualifier.isNeutral { try c.encode(qualifier, forKey: .qualifier) }
            if selection { try c.encode(true, forKey: .selection) }
        }
    }

    /// The texture-cache key for the kinds `LayerRenderers` rasterizes;
    /// nil for track sources, which come from the decoder. For text the core
    /// has already folded the reveal into this string, so it stays the WHOLE
    /// key — nothing here may append anything of its own to it.
    var cacheHash: String? {
        switch self {
        case .text(let hash, _, _), .shape(let hash, _): return hash
        case .graphic(_, let hash, _, _, _): return hash
        case .track, .image, .missing, .adjustment: return nil
        }
    }

    /// The composition track this layer samples, when it samples one.
    var trackID: Int? {
        if case .track(let id) = self { return id }
        return nil
    }
}

/// A transition the compositor draws as ONE pass over a pair of adjacent
/// layers: both carry the same `kind` and `progress`, one with role "out",
/// one with role "in" (§7.3).
struct RecipeTransition: Codable, Equatable {
    let kind: TransitionKind
    /// 0…1 across the overlap.
    let progress: Double
    /// "in" or "out".
    let role: String
    /// The other clip of the pair.
    let partner: UInt32

    init(kind: TransitionKind, progress: Double, role: String, partner: UInt32) {
        self.kind = kind
        self.progress = progress
        self.role = role
        self.partner = partner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
        progress = c.lenient(.progress, 0)
        role = c.lenient(.role, "in")
        partner = c.lenient(.partner, 0)
    }

    var isIncoming: Bool { role == "in" }
}

/// The rotated canvas rectangle a layer is clipped to (§7.3 `clip_rect`).
///
/// Only a nest ever sets one — a layer flattened out of a nest is clipped to
/// that nest's canvas rect (the innermost one, `nest.rs`) — so a layer from
/// the top-level timeline carries `null` here. The compositor implements the
/// clip once, against this one recipe shape, however deep the nesting.
struct RecipeClipRect: Codable, Equatable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    /// Degrees, about the rectangle's centre, like a layer's own rotation.
    let rotation: Double

    init(x: Double, y: Double, w: Double, h: Double, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.rotation = rotation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        w = c.lenient(.w, 0)
        h = c.lenient(.h, 0)
        rotation = c.lenient(.rotation, 0)
    }

    /// The unrotated rectangle, centred on `(x, y)` in canvas pixels.
    var rect: CGRect { CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h) }
}

/// A layer's part in the frame's mattes (spec §7.3 `matte`, §11 MT-5): the
/// group it is drawn INTO — never onto the canvas — when its track is a
/// matte track, and the listed groups that CUT it, ascending. Ids name a
/// `RecipeMatteGroup`.
struct RecipeLayerMatte: Codable, Equatable {
    let into: Int?
    let cut: [Int]

    init(into: Int?, cut: [Int]) {
        self.into = into
        self.cut = cut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        into = c.lenient(.into)
        cut = c.lenient(.cut, [])
    }
}

/// One routed dissolve or zoom a layer is a half of (spec §7.3 `dissolve`,
/// §11 MT-8): the compositor draws each half into a target of its own and
/// mixes the two (`Compositor+Dissolve.swift`). `id` names the dissolve in
/// this frame; `anchor` is the canvas point (top-left frame) the half is
/// placed at, read for a `zoom` only.
struct RecipeLayerDissolve: Codable, Equatable {
    let id: Int
    let kind: TransitionKind
    /// "in" or "out".
    let role: String
    /// Eased, 0…1.
    let progress: Double
    let anchor: [Double]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, 0)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
        role = c.lenient(.role, "in")
        progress = c.lenient(.progress, 0)
        anchor = c.lenient(.anchor, [0, 0])
    }

    var isIncoming: Bool { role == "in" }
}

/// One matte the compositor draws before the destination pass (spec §7.3
/// `mattes`, §11 MT-6): its group id and how it cuts.
struct RecipeMatteGroup: Codable, Equatable {
    let group: Int
    let mode: TrackMatte

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = c.lenient(.group, 0)
        mode = c.lenient(.mode, TrackMatte.alpha)
    }
}

/// One layer of a composed frame, every property already evaluated through
/// the clip's actions.
struct RecipeLayer: Codable, Equatable {
    let clip: UInt32
    let source: RecipeSourceRef
    /// Media pixel size, the shape box, or nil for text (the renderer
    /// measures it).
    let sourceSize: [Double]?
    let crop: CropInsets
    let x: Double
    let y: Double
    let scale: Double
    let rotation: Double
    let opacity: Double
    /// How this layer combines with what is already on the canvas, in the
    /// recipe's own key order (format version 6).
    ///
    /// **The recipe's blend is what DRAWS, and it is not always the clip's.**
    /// A layer carrying a transition is emitted as `normal` whatever the
    /// model says, because the outgoing half of a dissolve carries a weight
    /// correction that is the exact algebraic inverse of the destination
    /// factor its incoming partner is about to apply, and a non-normal blend
    /// on either half invalidates it. The CORE decides that, in
    /// `recipe.rs::layer`, so preview, `render_frame` and both export
    /// writers cannot disagree — which means nothing on this side may
    /// second-guess it. The inspector reads the MODEL's value through
    /// `clip_state`, so during an overlap the popup says `multiply` while
    /// the frame composites `normal`; both are honest, and a reader who
    /// knows about the dissolve divisor should look for the rule in
    /// `recipe.rs` rather than here or in `Compositor.swift`.
    let blend: BlendMode
    let cornerRadius: Double
    let shadow: ShadowProps?
    let color: ColorAdjust
    /// Step 4c.1's wheels (spec §11 GR-11): all nine values, each at 0 when
    /// neutral (the core always writes the key; `ungraded` writes it at 0).
    let wheels: ColorWheels
    /// Step 4c.2's curves (spec §11 GR-12, GR-32): all six, an identity one
    /// as its domain's (the core always writes the key; `ungraded` writes all
    /// six so). Absent or malformed reads as the identity. A channel blended
    /// inside an action (GR-34) is `{from, to, t}`, read as its `from` points
    /// with the blend in `blends`.
    let curves: ColorCurves
    /// Step 4d's look (spec §11 GR-7): its amount and the definition
    /// `LookTextures` bakes; nil for no look, which the core also publishes
    /// for an amount of 0 and an ungraded frame.
    let look: RecipeLook?
    let chroma: ChromaProps?
    /// Applied in order, at most `FilterProps.max` of them.
    let filters: [FilterProps]
    let reflection: ReflectionProps?
    let spotlight: SpotlightProps?
    /// The obscured regions, at most `ObscureProps.max` of them.
    let obscure: [ObscureProps]
    /// The rectangle this layer is clipped to; nil unless it came out of a
    /// nest — see `RecipeClipRect`.
    let clipRect: RecipeClipRect?
    let transition: RecipeTransition?
    /// Nil for a layer no matte touches (format version 14). A layer with a
    /// non-nil `into` is never drawn on the canvas — the core also cleared
    /// its blend, shadow and reflection (MT-4) — and is drawn into its
    /// group's target only when the recipe lists that group.
    let matte: RecipeLayerMatte?
    /// The routed dissolves and zooms this layer is a half of, outermost
    /// first; empty for most layers (`null` in the recipe). A layer in one
    /// carries no `transition` for it and draws `normal` (§11 MT-8).
    let dissolve: [RecipeLayerDissolve]
    /// What step 0 converts this layer's source with — its media's Camera
    /// Log (spec §11 GR-16); nil for none, when the source's own labels
    /// decide (GR-15). Show Ungraded keeps it.
    let input: MediaColor?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = c.lenient(.clip, 0)
        source = c.lenient(.source, RecipeSourceRef.missing)
        sourceSize = c.lenient(.sourceSize)
        crop = c.lenient(.crop, CropInsets.zero)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        scale = c.lenient(.scale, 1)
        rotation = c.lenient(.rotation, 0)
        opacity = c.lenient(.opacity, 1)
        // A recipe from a core older than version 6 carries no `blend` key,
        // and reads as source-over — the picture that build drew.
        blend = c.lenient(.blend, BlendMode.normal)
        cornerRadius = c.lenient(.cornerRadius, 0)
        shadow = c.lenient(.shadow)
        color = c.lenient(.color, ColorAdjust.identity)
        wheels = c.lenient(.wheels, ColorWheels.neutral)
        curves = c.lenient(.curves, ColorCurves.identity)
        look = c.lenient(.look)
        chroma = c.lenient(.chroma)
        filters = c.lenient(.filters, [])
        reflection = c.lenient(.reflection)
        spotlight = c.lenient(.spotlight)
        obscure = c.lenient(.obscure, [])
        clipRect = c.lenient(.clipRect)
        transition = c.lenient(.transition)
        matte = c.lenient(.matte)
        dissolve = c.lenient(.dissolve, [])
        input = c.lenient(.input)
    }

    /// `sourceSize` as a size; nil for text, whose size only the renderer
    /// knows.
    var sourceSizeCG: CGSize? {
        guard let s = sourceSize, s.count >= 2, s[0] > 0, s[1] > 0 else { return nil }
        return CGSize(width: s[0], height: s[1])
    }

    /// The layer's properties as a `VideoProps`, so the overlay can reuse
    /// `canvasRect` on an evaluated layer instead of the base clip.
    ///
    /// Every parameter has a default, so a field left out here is dropped
    /// SILENTLY on the overlay's path with no diagnostic anywhere: pass
    /// each new one through as it lands.
    var videoProps: VideoProps {
        VideoProps(
            x: x, y: y, scale: scale, rotation: rotation, opacity: opacity, crop: crop,
            cornerRadius: cornerRadius, shadow: shadow, color: color, chroma: chroma,
            filters: filters, reflection: reflection, spotlight: spotlight,
            obscure: obscure, blend: blend, wheels: wheels, curves: curves)
    }
}

/// The composed frame at one time: back-to-front layers with everything
/// resolved. Asked once per composed frame and by the canvas overlay for
/// hit-testing and handles.
struct FrameRecipe: Codable, Equatable {
    let t: Ticks
    let canvas: RecipeCanvas
    /// Back to front.
    let layers: [RecipeLayer]
    /// The mattes to draw before the destination pass, deepest container
    /// first (format version 14); empty when no matte cuts anything.
    let mattes: [RecipeMatteGroup]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = c.lenient(.t, 0)
        canvas = c.lenient(.canvas, RecipeCanvas())
        layers = c.lenient(.layers, [])
        mattes = c.lenient(.mattes, [])
    }
}
