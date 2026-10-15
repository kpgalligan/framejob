import AppKit

/// The typed, READ-ONLY mirror of the project JSON (spec §5.2) that
/// `rc_project_to_json` hands back. Every Swift view draws from a value in
/// this file; nothing here mutates, and nothing here builds an edit — edits
/// are `ReelOp` values in `ReelCore.swift`, which owns the other half of this
/// contract (the op table lives in the module doc of `core/src/edit.rs`).
///
/// Decoding rules, in one place because they are easy to get wrong:
///
///  - `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` (see
///    `ReelJSON`), so a property spelled `cornerRadius` matches the model's
///    `corner_radius` with no `CodingKeys` at all.
///  - **Pitfall:** that conversion is not symmetric for acronyms —
///    `required_track_ids` converts to `requiredTrackIds`, NOT
///    `requiredTrackIDs`. Any property whose Swift name capitalises an
///    acronym needs an explicit `CodingKeys` raw value spelled the way the
///    converter spells it. `PlanInstruction` (`CompositionPlan.swift`) is the
///    one such case.
///  - The three keys that cannot round-trip through the converter get custom
///    coding: `source` (internally tagged by `kind`, and one of its keys is
///    the Swift keyword `in`), `fps` (a two-element array, not an object),
///    and the recipe's tagged `source`.
///  - Every field the model gives a serde default decodes that same default
///    when absent, null, or the wrong shape (`lenient` below), so a
///    hand-written project JSON still loads. Only identity fields (`id`,
///    `track`, `path`, a clip's `source`) are required.

// MARK: - Scalars

/// Project time. Integer ticks at `ReelTime.perSecond` (600 000/s, spec
/// §5.1) — a timescale that divides every common frame duration exactly, so
/// no edit ever lands off the grid through rounding.
typealias Ticks = Int64

/// A frame rate as the exact rational the model stores. Serialized as the
/// two-element array `[num, den]`, which is why it codes by hand.
struct Fps: Codable, Equatable {
    let num: Int
    let den: Int

    init(num: Int, den: Int) {
        self.num = num
        self.den = den
    }

    /// The rate as a Double, for display and for arithmetic that does not
    /// have to be exact. 0 for a degenerate rate, never a division by zero.
    var double: Double { den == 0 ? 0 : Double(num) / Double(den) }

    /// One frame in ticks, exact for every rate in `Fps.common` — the step
    /// the arrow keys and frame-accurate seeks use. 0 for a degenerate rate.
    var frameDuration: Ticks {
        guard num > 0, den > 0 else { return 0 }
        return Ticks(ReelTime.perSecond) * Ticks(den) / Ticks(num)
    }

    /// "30", "29.97", "23.976" — the Document tab's spelling.
    var displayName: String {
        if den == 1 { return String(num) }
        let value = double
        return String(format: value < 100 ? "%.3f" : "%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
    }

    /// The rates the Document tab offers, in the order it lists them.
    static let common: [Fps] = [
        Fps(num: 24, den: 1), Fps(num: 24000, den: 1001), Fps(num: 25, den: 1),
        Fps(num: 30, den: 1), Fps(num: 30000, den: 1001), Fps(num: 50, den: 1),
        Fps(num: 60, den: 1),
    ]

    static let thirty = Fps(num: 30, den: 1)

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        num = try c.decode(Int.self)
        den = try c.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(num)
        try c.encode(den)
    }
}

/// A colour as the model stores it: four components 0…1, straight alpha.
/// Kept as an array rather than a struct so it round-trips byte-for-byte
/// through the core, which never inspects it.
typealias RGBA = [Double]

extension Array where Element == Double {
    /// The array read as an RGBA colour in sRGB. Missing components read as
    /// 0 except alpha, which reads as 1 — so a three-element `chroma.key`
    /// converts without a special case.
    var nsColor: NSColor {
        func component(_ i: Int) -> CGFloat {
            i < count ? CGFloat(Swift.min(Swift.max(self[i], 0), 1)) : (i == 3 ? 1 : 0)
        }
        return NSColor(
            srgbRed: component(0), green: component(1), blue: component(2),
            alpha: component(3))
    }
}

extension NSColor {
    /// The colour as the model's `[r, g, b, a]`. Converts to sRGB first;
    /// nil-safe (a colour with no RGB representation reads as opaque black),
    /// because a colour well can hand back a pattern or a catalog colour.
    var rgbaComponents: RGBA {
        guard let c = usingColorSpace(.sRGB) else { return [0, 0, 0, 1] }
        return [
            Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent),
            Double(c.alphaComponent),
        ]
    }
}

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// Decodes `key`, falling back to the model's documented default when it
    /// is absent, null, or the wrong shape. Deliberately non-throwing: a
    /// hand-written project with a missing optional field must still open.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// Decodes an optional-by-design field (`shadow`, `duck`, `outline`, …);
    /// nil when absent, null or malformed.
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Decodes a field where "absent" and "explicitly null" mean different
    /// things — the patch convention (§6 `set_action_end`: a key set to null
    /// REMOVES it, an absent key leaves it alone). Outer nil = absent.
    func nullable<T: Decodable>(_ key: Key) -> T?? {
        guard contains(key) else { return nil }
        return .some((try? decodeIfPresent(T.self, forKey: key)) ?? nil)
    }
}

/// The one configured decoder for everything the core emits — the project,
/// the plan, the recipe, export presets and settings. A fresh instance per
/// call on purpose: `JSONDecoder` is not documented as thread-safe and the
/// compositor decodes recipes on its own queue while the main thread decodes
/// snapshots.
enum ReelJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Encoder for the rare Swift → core direction. NOT the persistence
    /// path: `.framejob` stores `rc_project_to_json`'s own bytes, never a
    /// re-encoded snapshot, so the core stays the single writer of the file
    /// format.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder().decode(type, from: data)
    }
}

// MARK: - Enumerations

/// The shape kinds the Shape tab offers. A "rounded rectangle" is a
/// `rectangle` with a non-zero `radius`, not a kind of its own.
enum ShapeKind: String, Codable, CaseIterable {
    case rectangle, ellipse, line, arrow

    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        }
    }

    /// Line and arrow are the two kinds whose geometry is the `from`/`to`
    /// endpoints rather than the box, so they get endpoint handles.
    var isLinear: Bool { self == .line || self == .arrow }
}

/// A gradient fill's geometry (format version 6). Closed at two for
/// `ObscureKind`'s reason, which `model_props.rs` argues: each is a
/// different `CGGradient` call taking different arguments, not a parameter
/// of a shared one, so an unknown kind is a value nothing downstream could
/// repair and there is no neutral geometry to fall back to.
///
/// Nothing derives a NUMBER from this order — a gradient is drawn on the CPU
/// by `LayerRenderers.renderShape` and never reaches a shader, unlike
/// `BlendMode` — but each raw value is persisted, so a kind may be added at
/// the end and a rename is a migration.
enum GradientKind: String, Codable, CaseIterable {
    case linear, radial

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .radial: return "Radial"
        }
    }
}

/// The image filters of spec §4.2 (M3). Every one is a few lines in
/// `Compositor.metal`'s single pass — a filter needing its own render target
/// is not one of these.
enum FilterKind: String, Codable, CaseIterable {
    case blur, sharpen, pixelate, sepia, noir, vignette, invert

    var displayName: String {
        switch self {
        case .blur: return "Blur"
        case .sharpen: return "Sharpen"
        case .pixelate: return "Pixelate"
        case .sepia: return "Sepia"
        case .noir: return "Noir"
        case .vignette: return "Vignette"
        case .invert: return "Invert"
        }
    }

    /// The code the shader's uniform block carries. 0 means "no filter", so
    /// these count from 1 and the order is the model's declaration order —
    /// `Compositor.metal` reads them, so it must not be re-ordered here.
    var shaderCode: Int {
        (FilterKind.allCases.firstIndex(of: self) ?? 0) + 1
    }
}

/// How an obscured region hides what is under it (phase 3c).
///
/// Closed at two, and its own type rather than a `FilterKind` restricted to
/// two of its seven — `ObscureKind` in `model_regions.rs` argues it at length:
/// a range check saying "kind must be blur or pixelate" is a rule about a
/// type enforced a long way from it, and there is no neutral obscure kind for
/// a `"sepia"` out of a hand-written file to fall back to.
enum ObscureKind: String, Codable, CaseIterable {
    case blur, pixelate

    var displayName: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        }
    }

    /// The code the shader's uniform block carries, counted from 1 so 0 can
    /// mean "this slot holds no region" — `FilterKind.shaderCode`'s rule, for
    /// the same reason. `Compositor.metal` reads the number, so the case
    /// order here, in `model_regions.rs` and in the shader's `kObscure*`
    /// constants is one contract: a kind may be added at the END, never
    /// inserted.
    var shaderCode: Int {
        (ObscureKind.allCases.firstIndex(of: self) ?? 0) + 1
    }
}

/// How a layer combines with what is already on the canvas (format version
/// 6). Eight modes: `normal`, which is source-over and is what every project
/// drew before the key existed; six separable blends the fragment stage
/// computes from one source and one destination fragment; and `add`, which
/// is plus-lighter rather than a separable blend at all. The formulas live
/// once, in `Compositor.metal`'s `blendPremultiplied` — nothing on this side
/// computes a colour, it only says WHICH.
///
/// It belongs to the LAYER and not to a source kind: media, image, still,
/// text and shape all draw through one fragment stage, so all five blend.
/// The one clip that cannot is a NEST, and that is an op's refusal
/// (`edit_props.rs`'s `check_blend`) rather than a schema one — a nest is
/// flattened rather than composited offscreen, so a blend on it would
/// combine each inner layer separately against whatever was already there.
///
/// **The case order IS a contract**, `FilterKind`'s and `ObscureKind`'s rule
/// read again: `shaderCode` below is the case INDEX, `Compositor.metal`
/// compares against `kBlend*` constants in this order, and
/// `model_props.rs`'s `BlendMode` declares the same eight in the same order.
/// A mode may be added at the END; these eight may never be reordered or
/// removed, and a rename is a migration, since the raw values are persisted.
enum BlendMode: String, Codable, CaseIterable {
    case normal, multiply, screen, add, overlay, darken, lighten, difference

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .add: return "Add"
        case .overlay: return "Overlay"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .difference: return "Difference"
        }
    }

    /// The code the shader's uniform block carries: the case INDEX, with no
    /// `+1` — unlike `FilterKind.shaderCode` and `ObscureKind.shaderCode`,
    /// where 0 is reserved to mean "this slot holds no filter, no region".
    ///
    /// There is nothing to reserve here, because a layer has exactly one
    /// blend mode and so there is no empty slot to spell. And reserving one
    /// would cost the property that makes this field safe to add to a
    /// SHIPPED schema: three different absences must all draw what the app
    /// drew before phase 6, and each of them arrives as a zero. A uniform
    /// block whose `blendMode` Swift never wrote is zeroed; a recipe from an
    /// older core carries no `blend` key and `RecipeLayer` decodes
    /// `.normal`; a project file written before version 6 has none either
    /// and serde answers `BlendMode::Normal`. Zero is source-over, so all
    /// three render exactly as they always did with no code in between.
    var shaderCode: Int { BlendMode.allCases.firstIndex(of: self) ?? 0 }
}

/// A spotlight's region: the two shapes spec §4.2 names.
enum SpotShape: String, Codable, CaseIterable {
    case rect, ellipse

    var displayName: String {
        switch self {
        case .rect: return "Rectangle"
        case .ellipse: return "Ellipse"
        }
    }
}

/// An action's easing. Raw values are the model's spelling; the key decoding
/// strategy never touches VALUES, so these stay snake_case.
enum Curve: String, Codable, CaseIterable {
    case linear
    case easeIn = "ease_in"
    case easeOut = "ease_out"
    case easeInOut = "ease_in_out"

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        }
    }
}

/// The thirteen transitions of spec §5.2. A transition's DURATION is the
/// overlap with the previous clip on the track, so it lives in the timeline,
/// not here; this is only which one it is. The three wipe DIRECTIONS were
/// appended at format version 7 beside the original rightward `wipe`.
enum TransitionKind: String, Codable, CaseIterable {
    case crossDissolve = "cross_dissolve"
    case fadeBlack = "fade_black"
    case fadeWhite = "fade_white"
    case pushLeft = "push_left"
    case pushRight = "push_right"
    case pushUp = "push_up"
    case pushDown = "push_down"
    case wipe
    case slide
    case zoom
    case wipeLeft = "wipe_left"
    case wipeUp = "wipe_up"
    case wipeDown = "wipe_down"

    var displayName: String {
        switch self {
        case .crossDissolve: return "Cross Dissolve"
        case .fadeBlack: return "Fade Through Black"
        case .fadeWhite: return "Fade Through White"
        case .pushLeft: return "Push Left"
        case .pushRight: return "Push Right"
        case .pushUp: return "Push Up"
        case .pushDown: return "Push Down"
        case .wipe: return "Wipe"
        case .slide: return "Slide"
        case .zoom: return "Zoom"
        case .wipeLeft: return "Wipe Left"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        }
    }
}

// MARK: - Canvas

/// The document's fixed canvas (spec §5.2 `canvas`).
struct CanvasSnapshot: Codable, Equatable {
    let width: Int
    let height: Int
    let fps: Fps
    let background: RGBA
    /// Fit a dropped clip that exceeds the canvas (§6 `add_clip`).
    let fitNewClips: Bool
    /// Timecode shows `HH:MM:SS:FF` when true, `HH:MM:SS.mmm` when false.
    let timecodeFrames: Bool

    init(
        width: Int = 1920, height: Int = 1080, fps: Fps = .thirty,
        background: RGBA = [0, 0, 0, 1], fitNewClips: Bool = true,
        timecodeFrames: Bool = true
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.background = background
        self.fitNewClips = fitNewClips
        self.timecodeFrames = timecodeFrames
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        fps = c.lenient(.fps, Fps.thirty)
        background = c.lenient(.background, [0, 0, 0, 1])
        fitNewClips = c.lenient(.fitNewClips, true)
        timecodeFrames = c.lenient(.timecodeFrames, true)
    }

    var size: CGSize { CGSize(width: width, height: height) }
    /// The canvas centre, the origin of every clip's `(x, y)` (§5.3).
    var center: CGPoint { CGPoint(x: Double(width) / 2, y: Double(height) / 2) }
    var aspect: Double { height == 0 ? 1 : Double(width) / Double(height) }
}

// MARK: - Tracks

/// One timeline track. Higher index = further front (§2); the ORDER of
/// `ProjectSnapshot.tracks` is that stacking order, index 0 = back.
struct TrackSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let name: String
    /// Contributes no video layers when true (audio still plays).
    let hidden: Bool
    let muted: Bool
    /// Locked tracks are not hit-tested and ripple/insert-time skip them.
    let locked: Bool
    /// While any track in its container is soloed, every track that is not
    /// is silent — audio only, and mute still wins on the same track. The
    /// core's envelopes apply it (`audio.rs`); the header only shows it.
    let solo: Bool
    /// The track's matte (format version 14, `TrackMatte.swift`); `.none`
    /// for an ordinary track and for a file that names no mode.
    let matte: TrackMatte

    init(
        id: UInt32, name: String = "Track", hidden: Bool = false, muted: Bool = false,
        locked: Bool = false, solo: Bool = false, matte: TrackMatte = .none
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.muted = muted
        self.locked = locked
        self.solo = solo
        self.matte = matte
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        name = c.lenient(.name, "Track")
        hidden = c.lenient(.hidden, false)
        muted = c.lenient(.muted, false)
        locked = c.lenient(.locked, false)
        solo = c.lenient(.solo, false)
        matte = c.lenient(.matte, TrackMatte.none)
    }
}

// MARK: - Clip property groups

/// Which halves of a clip are live. Detach Audio (§6) flips these across two
/// clips rather than moving samples.
struct EnabledFlags: Codable, Equatable {
    let video: Bool
    let audio: Bool

    init(video: Bool = true, audio: Bool = true) {
        self.video = video
        self.audio = audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = c.lenient(.video, true)
        audio = c.lenient(.audio, true)
    }
}

/// Crop insets in SOURCE pixels, one per edge. Cropping never shifts
/// content (§5.3) — see `canvasRect(of:in:sourceSize:video:)`.
struct CropInsets: Codable, Equatable {
    let l: Double
    let t: Double
    let r: Double
    let b: Double

    init(l: Double = 0, t: Double = 0, r: Double = 0, b: Double = 0) {
        self.l = l
        self.t = t
        self.r = r
        self.b = b
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        l = c.lenient(.l, 0)
        t = c.lenient(.t, 0)
        r = c.lenient(.r, 0)
        b = c.lenient(.b, 0)
    }

    static let zero = CropInsets()
    var isZero: Bool { l == 0 && t == 0 && r == 0 && b == 0 }
}

/// A drop shadow. `angle` is degrees with 0 pointing RIGHT and increasing
/// COUNTER-CLOCKWISE — the convention `model.rs` states and the one the
/// default 315° depends on, which is why it falls down-and-right on a y-down
/// canvas. `distance` and `blur` are SOURCE pixels, like the corner radius
/// and the crop, so `Compositor.encodeShadow` scales both by the layer's
/// scale before it resolves them into canvas-space offsets.
struct ShadowProps: Codable, Equatable {
    let color: RGBA
    let opacity: Double
    let blur: Double
    let angle: Double
    let distance: Double

    init(
        color: RGBA = [0, 0, 0, 1], opacity: Double = 0.5, blur: Double = 12,
        angle: Double = 315, distance: Double = 8
    ) {
        self.color = color
        self.opacity = opacity
        self.blur = blur
        self.angle = angle
        self.distance = distance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = c.lenient(.color, [0, 0, 0, 1])
        opacity = c.lenient(.opacity, 0.5)
        blur = c.lenient(.blur, 12)
        angle = c.lenient(.angle, 315)
        distance = c.lenient(.distance, 8)
    }
}

/// Chroma key (M3). `key` is a THREE-component colour — no alpha.
struct ChromaProps: Codable, Equatable {
    let key: [Double]
    let tolerance: Double
    let softness: Double
    let spill: Double

    init(
        key: [Double] = [0, 1, 0], tolerance: Double = 0.2, softness: Double = 0.1,
        spill: Double = 0.5
    ) {
        self.key = key
        self.tolerance = tolerance
        self.softness = softness
        self.spill = spill
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(.key, [0, 1, 0])
        tolerance = c.lenient(.tolerance, 0.2)
        softness = c.lenient(.softness, 0.1)
        spill = c.lenient(.spill, 0.5)
    }
}

/// One image filter and how much of it. Order matters: the compositor
/// applies `VideoProps.filters` in order, so blur-then-sepia and
/// sepia-then-blur are different pictures.
struct FilterProps: Codable, Equatable {
    let kind: FilterKind
    /// 0 = present but doing nothing, 1 = full effect.
    let amount: Double

    /// The most one layer may carry — `MAX_FILTERS` in `model.rs`. A shader
    /// budget, not taste: the uniform block holds four (kind, amount) pairs.
    static let max = 4

    init(kind: FilterKind = .blur, amount: Double = 0.5) {
        self.kind = kind
        self.amount = amount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, FilterKind.blur)
        amount = c.lenient(.amount, 0.5)
    }
}

/// A mirrored copy of the layer drawn below it, fading out (M3). `height`
/// and `falloff` are FRACTIONS of the layer's cropped height, not pixels, so
/// a reflection survives a scale change; `gap` is source pixels, like the
/// corner radius and the crop.
struct ReflectionProps: Codable, Equatable {
    let opacity: Double
    let height: Double
    let gap: Double
    /// 0 does not fade at all; 1 reaches transparent exactly at `height`.
    let falloff: Double

    init(opacity: Double = 0.35, height: Double = 0.5, gap: Double = 0, falloff: Double = 1) {
        self.opacity = opacity
        self.height = height
        self.gap = gap
        self.falloff = falloff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opacity = c.lenient(.opacity, 0.35)
        height = c.lenient(.height, 0.5)
        gap = c.lenient(.gap, 0)
        falloff = c.lenient(.falloff, 1)
    }
}

/// Darkens the canvas outside a rectangle or ellipse and optionally magnifies
/// what is inside it (M3) — the stand-in for a screencast editor's freehand callout.
///
/// A VIDEO prop even though spec §4.2 first listed it under Shape: the zoom
/// half can only be drawn by the layer that owns the pixels. The centre and
/// the box are SOURCE pixels from the centre of the cropped rect, the same
/// frame `cornerRadius` and `crop` use.
struct SpotlightProps: Codable, Equatable {
    let shape: SpotShape
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// Source pixels the edge is blurred over; 0 is a hard edge.
    let feather: Double
    /// How much darker everything OUTSIDE is; 1 is black.
    let dim: Double
    /// Magnification inside the region; 1 is none.
    let zoom: Double

    init(
        shape: SpotShape = .rect, x: Double = 0, y: Double = 0, width: Double = 480,
        height: Double = 270, feather: Double = 40, dim: Double = 0.6, zoom: Double = 1
    ) {
        self.shape = shape
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.feather = feather
        self.dim = dim
        self.zoom = zoom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = c.lenient(.shape, SpotShape.rect)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        width = c.lenient(.width, 480)
        height = c.lenient(.height, 270)
        feather = c.lenient(.feather, 40)
        dim = c.lenient(.dim, 0.6)
        zoom = c.lenient(.zoom, 1)
    }

    /// The region as a rect in the same source-pixel space, centred on
    /// `(x, y)` — what the overlay draws a handle box around.
    var box: CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }
}

/// One obscured region: a box on the layer whose contents are blurred or
/// pixelated so a bystander, a password field or a notification cannot be
/// read (schema version 4).
///
/// **The geometry is the spotlight's frame, exactly** — `x`/`y` are the
/// region's CENTRE as an offset in SOURCE pixels from the centre of the
/// cropped rect, `width` and `height` its size in the same pixels. So a
/// region rides with its layer through scale, move and rotation and stays on
/// the face it was put on; nothing here is in canvas pixels. `shape` is
/// `SpotShape` rather than a second rect/ellipse enum, for the reason
/// `ObscureRegion` in `model_regions.rs` gives: shared vocabulary has one home.
struct ObscureProps: Codable, Equatable {
    let shape: SpotShape
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// Source pixels the effect is ramped in over; 0 is a hard edge.
    let feather: Double
    let kind: ObscureKind
    /// 0 = the region is there but hides nothing, 1 = its full effect.
    let amount: Double

    /// The most one layer may carry — `MAX_OBSCURE` in `model_regions.rs`. The
    /// same shader budget `FilterProps.max` is: the uniform block carries
    /// four eight-field region slots.
    static let max = 4

    /// The core's own defaults (`impl Default for ObscureRegion`): the
    /// spotlight's 480 × 270 box, so the two region controls put the same
    /// rectangle on screen, pixelated at full strength because a region that
    /// only half hides has failed at the one job this feature has.
    init(
        shape: SpotShape = .rect, x: Double = 0, y: Double = 0, width: Double = 480,
        height: Double = 270, feather: Double = 20, kind: ObscureKind = .pixelate,
        amount: Double = 1
    ) {
        self.shape = shape
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.feather = feather
        self.kind = kind
        self.amount = amount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = c.lenient(.shape, SpotShape.rect)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        width = c.lenient(.width, 480)
        height = c.lenient(.height, 270)
        feather = c.lenient(.feather, 20)
        kind = c.lenient(.kind, ObscureKind.pixelate)
        amount = c.lenient(.amount, 1)
    }

    /// The region as a rect in the same source-pixel space, centred on
    /// `(x, y)` — `SpotlightProps.box`'s twin, and what the canvas grips
    /// are built on (spec §11 CI-16, `CanvasObscureSession.swift`).
    var box: CGRect {
        CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }
}

/// The pixel half of a clip. `x`/`y` are canvas pixels from the canvas
/// CENTRE, y down; `scale` 1 = native pixels; `rotation` degrees clockwise.
struct VideoProps: Codable, Equatable {
    let x: Double
    let y: Double
    let scale: Double
    let rotation: Double
    let opacity: Double
    let crop: CropInsets
    /// Rounds the CROPPED rectangle, in source pixels, before rotation.
    let cornerRadius: Double
    let shadow: ShadowProps?
    let color: ColorAdjust
    let chroma: ChromaProps?
    /// Applied in order, at most `FilterProps.max` of them (M3).
    let filters: [FilterProps]
    let reflection: ReflectionProps?
    let spotlight: SpotlightProps?
    /// The obscured regions, at most `ObscureProps.max` of them (phase 3c).
    /// An empty list is how they are cleared, which is why this is a plain
    /// array and not an optional.
    let obscure: [ObscureProps]
    /// How this layer combines with what is already on the canvas (format
    /// version 6). `.normal` is source-over, so it is both the default and
    /// how a blend is cleared; there is no null form.
    let blend: BlendMode
    /// What the clip DOES — an entrance, an exit, a continuous motion
    /// (format version 8). Nothing on this side reads it to DRAW: the core
    /// turns a preset into placement inside the recipe, so the inspector and
    /// the canvas see the clip UN-MOVED while the picture moves (spec §5.4),
    /// which is why a drag begun mid-motion starts from the base box.
    let motion: MotionProps?
    /// Lift, gamma and gain (spec §11 GR-11, `GradeProps.swift`).
    let wheels: ColorWheels
    /// The tone curves (spec §11 GR-12, `CurveProps.swift`).
    let curves: ColorCurves
    /// An adjustment clip's qualifier (spec §11 GR-13, `QualifierProps.swift`).
    let qualifier: ColorQualifier
    /// The clip's look (spec §11 GR-7, `LookProps.swift`); nil is none.
    let look: LookProps?

    init(
        x: Double = 0, y: Double = 0, scale: Double = 1, rotation: Double = 0,
        opacity: Double = 1, crop: CropInsets = .zero, cornerRadius: Double = 0,
        shadow: ShadowProps? = nil, color: ColorAdjust = .identity,
        chroma: ChromaProps? = nil, filters: [FilterProps] = [],
        reflection: ReflectionProps? = nil, spotlight: SpotlightProps? = nil,
        obscure: [ObscureProps] = [], blend: BlendMode = .normal,
        motion: MotionProps? = nil, wheels: ColorWheels = .neutral,
        curves: ColorCurves = .identity, qualifier: ColorQualifier = .none,
        look: LookProps? = nil
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.crop = crop
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.color = color
        self.chroma = chroma
        self.filters = filters
        self.reflection = reflection
        self.spotlight = spotlight
        self.obscure = obscure
        self.blend = blend
        self.motion = motion
        self.wheels = wheels
        self.curves = curves
        self.qualifier = qualifier
        self.look = look
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        scale = c.lenient(.scale, 1)
        rotation = c.lenient(.rotation, 0)
        opacity = c.lenient(.opacity, 1)
        crop = c.lenient(.crop, CropInsets.zero)
        cornerRadius = c.lenient(.cornerRadius, 0)
        shadow = c.lenient(.shadow)
        color = c.lenient(.color, ColorAdjust.identity)
        chroma = c.lenient(.chroma)
        filters = c.lenient(.filters, [])
        reflection = c.lenient(.reflection)
        spotlight = c.lenient(.spotlight)
        // A version-3 file has no `obscure` key at all, and reads as the
        // empty list — the same answer `#[serde(default)]` gives the core,
        // which is why version 4 needs no migrate step.
        obscure = c.lenient(.obscure, [])
        // And a version-5 file has no `blend` key, which reads as `.normal`
        // — source-over, what the app drew before the key existed. Same
        // shape of argument, same reason version 6 needs no migrate step.
        blend = c.lenient(.blend, BlendMode.normal)
        // And a version-7 file has no `motion` key, which reads as nil —
        // what every clip did before it existed. Same argument again, same
        // reason version 8 needs no migrate step.
        motion = c.lenient(.motion)
        wheels = c.lenient(.wheels, ColorWheels.neutral)
        curves = c.lenient(.curves, ColorCurves.identity)
        qualifier = c.lenient(.qualifier, ColorQualifier.none)
        look = c.lenient(.look)
    }

    static let identity = VideoProps()
    /// The clip's offset from the canvas centre, as a point.
    var offset: CGPoint { CGPoint(x: x, y: y) }
}

/// Ducking: "lower other audio to `level` while this clip plays" (§4.3).
/// By clip extent, never by voice activity — the core folds it into every
/// other track's envelope.
struct DuckProps: Codable, Equatable {
    let level: Double
    let attack: Ticks
    let release: Ticks

    init(level: Double = 0.2, attack: Ticks = 300_000, release: Ticks = 600_000) {
        self.level = level
        self.attack = attack
        self.release = release
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = c.lenient(.level, 0.2)
        attack = c.lenient(.attack, 300_000)
        release = c.lenient(.release, 600_000)
    }
}

/// "Smooth volume levels" (§4.3): a downward compressor over the clip's own
/// samples. Unlike ducking, which the core resolves into ramps on other
/// clips' envelopes, this one depends on the samples — so the model carries
/// the parameters and the DSP happens on this side.
struct CompressorProps: Codable, Equatable {
    /// dBFS above which gain reduction starts.
    let thresholdDb: Double
    /// N:1 — 1 is no compression, 20 is effectively a limiter.
    let ratio: Double
    let attack: Ticks
    let release: Ticks
    /// dB applied after compression, to win back what it took.
    let makeupDb: Double

    init(
        thresholdDb: Double = -18, ratio: Double = 3, attack: Ticks = 6000,
        release: Ticks = 120_000, makeupDb: Double = 0
    ) {
        self.thresholdDb = thresholdDb
        self.ratio = ratio
        self.attack = attack
        self.release = release
        self.makeupDb = makeupDb
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thresholdDb = c.lenient(.thresholdDb, -18)
        ratio = c.lenient(.ratio, 3)
        attack = c.lenient(.attack, 6000)
        release = c.lenient(.release, 120_000)
        makeupDb = c.lenient(.makeupDb, 0)
    }
}

/// The sample half of a clip. `volume` may exceed 1, up to 4 (§5.2).
struct AudioProps: Codable, Equatable {
    let volume: Double
    let muted: Bool
    let fadeIn: Ticks
    let fadeOut: Ticks
    let duck: DuckProps?
    let mono: Bool
    /// Preserve pitch through a speed change (`scaleTimeRange` + a
    /// time-pitch algorithm; the plan carries it per segment).
    let keepPitch: Bool
    /// -1 hard left, 0 centred, +1 hard right (M3).
    let pan: Double
    let compressor: CompressorProps?
    /// How much background noise to remove: 0 is off (M3).
    let noiseReduction: Double

    init(
        volume: Double = 1, muted: Bool = false, fadeIn: Ticks = 0, fadeOut: Ticks = 0,
        duck: DuckProps? = nil, mono: Bool = false, keepPitch: Bool = true,
        pan: Double = 0, compressor: CompressorProps? = nil, noiseReduction: Double = 0
    ) {
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.duck = duck
        self.mono = mono
        self.keepPitch = keepPitch
        self.pan = pan
        self.compressor = compressor
        self.noiseReduction = noiseReduction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = c.lenient(.volume, 1)
        muted = c.lenient(.muted, false)
        fadeIn = c.lenient(.fadeIn, 0)
        fadeOut = c.lenient(.fadeOut, 0)
        duck = c.lenient(.duck)
        mono = c.lenient(.mono, false)
        keepPitch = c.lenient(.keepPitch, true)
        pan = c.lenient(.pan, 0)
        compressor = c.lenient(.compressor)
        noiseReduction = c.lenient(.noiseReduction, 0)
    }

    /// Volume in dB for the Audio tab's read-out; -inf shows as silence.
    var decibels: Double { volume <= 0 ? -.infinity : 20 * log10(volume) }
}

// MARK: - Clips

/// What a clip plays. Internally tagged by `kind`, and one of its keys is
/// the Swift keyword `in` — so it codes by hand rather than through the
/// snake_case strategy.
enum ClipSource: Codable, Equatable {
    /// A video or audio file. `in` is the source time of the first frame —
    /// in the REVERSED stream when `reversed` is set, which has the same
    /// duration, so no time math anywhere changes with the flag.
    case media(id: UInt32, in: Ticks, reversed: Bool)
    /// A freeze frame: one source frame held. `at` is the source time.
    case still(id: UInt32, at: Ticks)
    /// A still picture file (PNG/JPEG/HEIC).
    case image(id: UInt32)
    case text
    case shape
    /// Drawn by a module in the package's `graphics/` (format version 10).
    /// The description is the clip's `graphic` key, decoded as
    /// `ClipSnapshot.graphic` (`ProjectSnapshot+Graphic.swift`).
    case graphic
    /// A group of tracks and clips shown as one clip, by nest id
    /// (`ProjectSnapshot.nests`).
    ///
    /// A NUMBER since format version 2. It was a path in version 1 while
    /// this side already decoded a `UInt32` — `lenient` swallowed the
    /// mismatch to 0, so a nest clip silently lost its identity crossing
    /// the FFI. The two sides now agree.
    case nest(project: UInt32)
    case adjustment  // no picture: grades what is behind it (spec §11 GR-6)

    private enum CodingKeys: String, CodingKey {
        case kind, media, at, project, reversed
        case sourceIn = "in"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(.kind, "media")
        switch kind {
        case "media":
            self = .media(
                id: c.lenient(.media, 0), in: c.lenient(.sourceIn, 0),
                reversed: c.lenient(.reversed, false))
        case "still":
            self = .still(id: c.lenient(.media, 0), at: c.lenient(.at, 0))
        case "image":
            self = .image(id: c.lenient(.media, 0))
        case "text": self = .text
        case "shape": self = .shape
        case "graphic": self = .graphic
        case "adjustment": self = .adjustment
        case "nest":
            self = .nest(project: c.lenient(.project, 0))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown clip source kind '\(kind)'")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kindName, forKey: .kind)
        switch self {
        case .media(let id, let sourceIn, let reversed):
            try c.encode(id, forKey: .media)
            try c.encode(sourceIn, forKey: .sourceIn)
            try c.encode(reversed, forKey: .reversed)
        case .still(let id, let at):
            try c.encode(id, forKey: .media)
            try c.encode(at, forKey: .at)
        case .image(let id):
            try c.encode(id, forKey: .media)
        case .text, .shape, .graphic, .adjustment: break
        case .nest(let project):
            try c.encode(project, forKey: .project)
        }
    }

    /// The media this clip references, or nil for the generated kinds.
    var mediaID: UInt32? {
        switch self {
        case .media(let id, _, _), .still(let id, _), .image(let id): return id
        case .text, .shape, .graphic, .nest, .adjustment: return nil
        }
    }

    /// The nest this clip shows, or nil for every other kind.
    var nestID: UInt32? {
        if case .nest(let project) = self { return project }
        return nil
    }

    /// True when the clip plays its media backwards, which is what
    /// `CompositionBuilder` substitutes a pre-rendered reversed asset for.
    var isReversed: Bool {
        if case .media(_, _, let reversed) = self { return reversed }
        return false
    }

    /// The model's tag, for op JSON, timeline tinting and agent replies.
    var kindName: String {
        switch self {
        case .media: return "media"
        case .still: return "still"
        case .image: return "image"
        case .text: return "text"
        case .shape: return "shape"
        case .graphic: return "graphic"
        case .nest: return "nest"
        case .adjustment: return "adjustment"
        }
    }

    /// Source time of the clip's first frame; 0 for kinds with no source
    /// bound (§5.2 — `still`, `image`, `text`, `shape` may take any length).
    var sourceIn: Ticks {
        switch self {
        case .media(_, let sourceIn, _): return sourceIn
        case .still(_, let at): return at
        case .image, .text, .shape, .graphic, .nest, .adjustment: return 0
        }
    }

    /// Only `media` clips are limited by their source's length, and only
    /// they accept `set_speed` / `rate_stretch` (§6).
    var hasSourceBound: Bool {
        if case .media = self { return true }
        return false
    }
}

/// One clip on one track. The bar the timeline draws and the layer the
/// compositor composites.
struct ClipSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let track: UInt32
    /// Project time of the clip's first frame.
    let start: Ticks
    let duration: Ticks
    let source: ClipSource
    let enabled: EnabledFlags
    /// Playback rate; `media` sources only (§6 `set_speed`).
    let speed: Double
    let video: VideoProps?
    let audio: AudioProps?
    let text: TextProps?
    let shape: ShapeProps?
    let graphic: GraphicSnapshot?
    let actions: [ActionSnapshot]
    /// The transition into this clip. Its DURATION is the overlap with the
    /// previous clip on the track; with no overlap it is ignored.
    let transitionIn: TransitionSnapshot?
    /// The clip's OWN name (format version 3); nil means "call it what it
    /// shows", and `ProjectSnapshot.name(of:)` holds that fallback.
    let name: String?
    /// A colour name from `ClipLabel`'s vocabulary, or nil for no label.
    /// Stored unvalidated on both sides, so draw it through
    /// `ClipLabel.color(named:)`, which absorbs a name this build lacks.
    let label: String?

    init(
        id: UInt32, track: UInt32, start: Ticks = 0, duration: Ticks = 0,
        source: ClipSource = .text, enabled: EnabledFlags = EnabledFlags(),
        speed: Double = 1, video: VideoProps? = nil, audio: AudioProps? = nil,
        text: TextProps? = nil, shape: ShapeProps? = nil,
        graphic: GraphicSnapshot? = nil,
        actions: [ActionSnapshot] = [], transitionIn: TransitionSnapshot? = nil,
        name: String? = nil, label: String? = nil
    ) {
        self.id = id
        self.track = track
        self.start = start
        self.duration = duration
        self.source = source
        self.enabled = enabled
        self.speed = speed
        self.video = video
        self.audio = audio
        self.text = text
        self.shape = shape
        self.graphic = graphic
        self.actions = actions
        self.transitionIn = transitionIn
        self.name = name
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        track = try c.decode(UInt32.self, forKey: .track)
        start = c.lenient(.start, 0)
        duration = c.lenient(.duration, 0)
        source = try c.decode(ClipSource.self, forKey: .source)
        enabled = c.lenient(.enabled, EnabledFlags())
        speed = c.lenient(.speed, 1)
        video = c.lenient(.video)
        audio = c.lenient(.audio)
        text = c.lenient(.text)
        shape = c.lenient(.shape)
        graphic = c.lenient(.graphic)
        actions = c.lenient(.actions, [])
        transitionIn = c.lenient(.transitionIn)
        name = c.lenient(.name)
        label = c.lenient(.label)
    }

    /// Project time one tick past the clip's last frame.
    var end: Ticks { start + duration }
    /// The clip's span in project time.
    var range: Range<Ticks> { start..<max(start, end) }
    /// Whether project time `t` falls inside the clip.
    func contains(_ t: Ticks) -> Bool { t >= start && t < end }
    /// Project time `t` as clip time; negative or past `duration` outside.
    func clipTime(_ t: Ticks) -> Ticks { t - start }

    /// The pixel properties with the model's defaults filled in — what every
    /// view should draw from, so a clip that has never been transformed is
    /// not a special case.
    var videoProps: VideoProps { video ?? .identity }
    /// The sample properties with defaults filled in.
    var audioProps: AudioProps { audio ?? AudioProps() }

    /// The clip's label in the timeline when there is no media name to use:
    /// the text itself for a text clip, else the kind.
    var fallbackName: String {
        switch source {
        case .text:
            let content = text?.content ?? ""
            return content.isEmpty ? "Text" : content
        case .shape: return shape?.kind.displayName ?? "Shape"
        case .graphic: return "Graphic"
        case .still: return "Freeze Frame"
        case .nest: return "Nest"
        case .adjustment: return "Adjustment"
        case .media, .image: return "Clip"
        }
    }
}

/// The transition into a clip (§5.2 `transition_in`).
///
/// `curve` and `audio` are format version 7's. Their defaults here are the
/// FILE defaults — linear and silent — and not what the core MINTS (spec
/// §11, R5-2), because this type decodes files: a version-6 project carries
/// neither key and must read as what it always rendered.
struct TransitionSnapshot: Codable, Equatable {
    let kind: TransitionKind
    let curve: Curve
    let audio: Bool

    init(kind: TransitionKind = .crossDissolve, curve: Curve = .linear, audio: Bool = false) {
        self.kind = kind
        self.curve = curve
        self.audio = audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(.kind, TransitionKind.crossDissolve)
        curve = c.lenient(.curve, Curve.linear)
        audio = c.lenient(.audio, false)
    }
}

// MARK: - Markers

/// A named point on the ruler; `chapter` markers become a chapter track on
/// export (M2).
struct MarkerSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let time: Ticks
    let name: String
    let color: String
    let chapter: Bool

    init(
        id: UInt32, time: Ticks = 0, name: String = "", color: String = "red",
        chapter: Bool = false
    ) {
        self.id = id
        self.time = time
        self.name = name
        self.color = color
        self.chapter = chapter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        time = c.lenient(.time, 0)
        name = c.lenient(.name, "")
        color = c.lenient(.color, "red")
        chapter = c.lenient(.chapter, false)
    }
}

// MARK: - Nests

/// A group of tracks and clips the timeline shows as ONE clip (§5.2,
/// `source.kind = "nest"`).
///
/// **Not a nested project.** Its tracks and clips live in the PARENT's one
/// id space and reference the parent's `media`, and its times are measured
/// from its own start. That is what keeps `ProjectDocument.mediaURLs()`, the
/// plan's clip-keyed track map and `next_id` working unchanged when a nest
/// is flattened at evaluation time; a second id space would mean re-minting
/// every inner id on the way out.
struct NestSnapshot: Codable, Equatable, Identifiable {
    let id: UInt32
    let name: String
    /// The nest's own canvas, frozen at the size the parent had when it was
    /// made — a later canvas change must not re-lay-out a nest.
    let width: UInt32
    let height: UInt32
    /// Back to front, index 0 rearmost, like `ProjectSnapshot.tracks`.
    let tracks: [TrackSnapshot]
    /// Times are relative to the nest: its earliest clip starts at 0.
    let clips: [ClipSnapshot]

    init(
        id: UInt32, name: String = "", width: UInt32 = 1920, height: UInt32 = 1080,
        tracks: [TrackSnapshot] = [], clips: [ClipSnapshot] = []
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.tracks = tracks
        self.clips = clips
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UInt32.self, forKey: .id)
        name = c.lenient(.name, "")
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        tracks = c.lenient(.tracks, [])
        clips = c.lenient(.clips, [])
    }

    /// The nest's canvas as a size, for laying its contents out.
    var canvasSize: CGSize { CGSize(width: Int(width), height: Int(height)) }

    /// End of the last clip inside; 0 when empty. What a nest CLIP's
    /// duration is measured against — never the parent's.
    var duration: Ticks { clips.map(\.end).max() ?? 0 }
}

// MARK: - The project

/// The whole document, decoded once per `ReelProject` handle
/// (`ReelProject.snapshot`). Selection, playhead, zoom and panel sizes are
/// deliberately NOT here — that is view state and lives in Swift (§5.2).
struct ProjectSnapshot: Codable, Equatable {
    let version: Int
    let canvas: CanvasSnapshot
    let media: [MediaSnapshot]
    /// Back to front: index 0 is the rearmost track.
    let tracks: [TrackSnapshot]
    let clips: [ClipSnapshot]
    let markers: [MarkerSnapshot]
    let nextId: UInt32
    /// The groups every `nest` clip points at (format version 2). Empty in
    /// anything written before it, which is what the model's serde defaults
    /// buy: a version-1 file opens with no nests rather than not at all.
    let nests: [NestSnapshot]

    init(
        version: Int = ProjectSnapshot.formatVersion, canvas: CanvasSnapshot = CanvasSnapshot(),
        media: [MediaSnapshot] = [], tracks: [TrackSnapshot] = [],
        clips: [ClipSnapshot] = [], markers: [MarkerSnapshot] = [], nextId: UInt32 = 1,
        nests: [NestSnapshot] = []
    ) {
        self.version = version
        self.canvas = canvas
        self.media = media
        self.tracks = tracks
        self.clips = clips
        self.markers = markers
        self.nextId = nextId
        self.nests = nests
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.lenient(.version, ProjectSnapshot.formatVersion)
        canvas = c.lenient(.canvas, CanvasSnapshot())
        media = c.lenient(.media, [])
        tracks = c.lenient(.tracks, [])
        clips = c.lenient(.clips, [])
        markers = c.lenient(.markers, [])
        nextId = c.lenient(.nextId, 1)
        nests = c.lenient(.nests, [])
    }

    /// `RC_FORMAT_VERSION` — the version the core always writes, read from
    /// the header so a decode that never saw the key still reports the truth.
    /// The C header is the contract; this is a fallback, not a second source.
    static let formatVersion = Int(RC_FORMAT_VERSION)

    /// The value a failed decode falls back to, so `ReelProject.snapshot`
    /// can stay non-optional and no view needs an "unloaded" state.
    static let empty = ProjectSnapshot()

    // MARK: Lookups

    func clip(_ id: UInt32) -> ClipSnapshot? { clips.first { $0.id == id } }
    func track(_ id: UInt32) -> TrackSnapshot? { tracks.first { $0.id == id } }
    func media(_ id: UInt32) -> MediaSnapshot? { media.first { $0.id == id } }
    func marker(_ id: UInt32) -> MarkerSnapshot? { markers.first { $0.id == id } }
    func nest(_ id: UInt32) -> NestSnapshot? { nests.first { $0.id == id } }

    /// The nest a clip shows, when it shows one.
    func nest(for clip: ClipSnapshot) -> NestSnapshot? {
        clip.source.nestID.flatMap { nest($0) }
    }

    /// One track's clips in timeline order — the order the overlap rule and
    /// every transition lookup assume.
    func clips(onTrack id: UInt32) -> [ClipSnapshot] {
        clips.filter { $0.track == id }.sorted { $0.start < $1.start }
    }

    /// End of the last clip; 0 for an empty project. Mirrors
    /// `rc_project_duration` so views can answer without an FFI call.
    var duration: Ticks { clips.map(\.end).max() ?? 0 }

    /// Stacking index of a track: 0 = back, `tracks.count - 1` = front.
    func trackIndex(of id: UInt32) -> Int? { tracks.firstIndex { $0.id == id } }

    /// The media backing a clip, when it has one.
    func media(for clip: ClipSnapshot) -> MediaSnapshot? {
        clip.source.mediaID.flatMap { media($0) }
    }

    /// The timeline's label for a clip: its own name when it has one, else
    /// the nest's name for a nest clip, the media file name where there is
    /// one, else the kind.
    ///
    /// The clip's own name comes first because it is the only one of the
    /// four the user gave THIS clip; the nest next, because `nest` takes a
    /// `name` and ⌘G's default `Nest <n>` is what distinguishes one grey bar
    /// from the next. The trim mirrors the core's `set_clip`, so a name that
    /// is nothing but whitespace — which only a hand-written file can hold —
    /// reads as no name rather than as a blank strip.
    func name(of clip: ClipSnapshot) -> String {
        if let own = clip.name?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty {
            return own
        }
        if let nest = nest(for: clip), !nest.name.isEmpty { return nest.name }
        return media(for: clip)?.name ?? clip.fallbackName
    }

    /// The clip's UNCROPPED source rectangle size in source pixels — the
    /// input to `canvasRect`. nil for text, where only `LayerRenderers` can
    /// measure a layout (§5.3).
    ///
    /// **A nest's is its own canvas**, frozen at the size the project had
    /// when it was made. That is exactly the rectangle the core clips a
    /// nest's flattened layers to (`clip_rect`, spec §7.3), so a nest clip's
    /// handles, its Fit/Fill and its scale drags all act on the box its
    /// contents actually occupy. Reading the PROJECT's canvas here instead
    /// would be a second, disagreeing answer the moment `set_canvas` runs.
    func sourceSize(of clip: ClipSnapshot) -> CGSize? {
        switch clip.source {
        case .media(let id, _, _), .still(let id, _), .image(let id):
            guard let m = media(id), m.width > 0, m.height > 0 else { return nil }
            return m.pixelSize
        case .shape:
            guard let s = clip.shape, s.width > 0, s.height > 0 else { return nil }
            return s.boxSize
        case .nest:
            guard let n = nest(for: clip), n.width > 0, n.height > 0 else { return nil }
            return n.canvasSize
        case .text, .adjustment:
            return nil
        case .graphic:
            guard let g = clip.graphic, g.width > 0, g.height > 0 else { return nil }
            return CGSize(width: g.width, height: g.height)
        }
    }

    /// Clips that contribute PIXELS at project time `t`, back to front — the
    /// order the compositor draws in and the canvas hit-tests in reverse.
    /// Hidden tracks, disabled video and audio-only media drop out here so
    /// no caller repeats the test. Not a substitute for the frame recipe:
    /// this is the clip list, not the evaluated one.
    func layers(at t: Ticks) -> [ClipSnapshot] {
        let order = Dictionary(
            uniqueKeysWithValues: tracks.enumerated().map { ($0.element.id, $0.offset) })
        return clips
            .filter { clip in
                guard clip.contains(t), clip.enabled.video else { return false }
                guard track(clip.track)?.hidden != true else { return false }
                if let m = media(for: clip) { return m.hasVideo || m.kind == .image }
                return true
            }
            .sorted {
                let (a, b) = (order[$0.track] ?? 0, order[$1.track] ?? 0)
                return a == b ? $0.start < $1.start : a < b
            }
    }
}

// MARK: - Placement (spec §5.3)

/// The ONE placement rule. Every view that hit-tests, draws a handle or
/// snaps calls this — never re-derives it, because the pitfall is subtle:
/// cropping removes edges IN PLACE, so a cropped clip's rectangle is a
/// sub-rectangle of where the uncropped one sat, and the content under it
/// does not move (a screencast editor's behaviour, §5.3).
///
/// Returns the CROPPED rectangle in CANVAS pixel space with the origin at
/// the canvas's top-left and **y increasing downward** — the model's
/// convention, matching CoreVideo. A view in AppKit's flipped-or-not space
/// converts on the way out.
///
/// Rotation is deliberately NOT applied: it belongs to the caller, which
/// must rotate about `canvasAnchor(of:in:)` — the centre of the UNCROPPED
/// rectangle, not the centre of the returned one.
func canvasRect(
    of clip: ClipSnapshot, in canvas: CanvasSnapshot, sourceSize: CGSize, video: VideoProps
) -> CGRect {
    let scale = video.scale
    let full = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let anchor = canvasAnchor(of: clip, in: canvas, video: video)
    let originX = anchor.x - full.width / 2
    let originY = anchor.y - full.height / 2
    // Crop insets are SOURCE pixels, so they scale with the layer.
    let l = video.crop.l * scale
    let t = video.crop.t * scale
    let r = video.crop.r * scale
    let b = video.crop.b * scale
    return CGRect(
        x: originX + l, y: originY + t,
        width: max(0, full.width - l - r), height: max(0, full.height - t - b))
}

/// The point a layer is placed on and rotated about: the canvas centre plus
/// the clip's `(x, y)`, in the same y-down canvas space as `canvasRect`.
/// Cropping never moves it — that is exactly why it is separate.
func canvasAnchor(of clip: ClipSnapshot, in canvas: CanvasSnapshot, video: VideoProps) -> CGPoint {
    CGPoint(x: canvas.center.x + video.x, y: canvas.center.y + video.y)
}
