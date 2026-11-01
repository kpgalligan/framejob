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
    /// The dynamic range (format 23, `CanvasOutput.swift`); `.sdr` when absent.
    let output: CanvasOutput
    /// The blending (format 24, `CanvasOutput.swift`); `.encoded` when absent.
    let blending: CanvasBlending

    init(
        width: Int = 1920, height: Int = 1080, fps: Fps = .thirty,
        background: RGBA = [0, 0, 0, 1], fitNewClips: Bool = true,
        timecodeFrames: Bool = true, output: CanvasOutput = .sdr,
        blending: CanvasBlending = .encoded
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.background = background
        self.fitNewClips = fitNewClips
        self.timecodeFrames = timecodeFrames
        self.output = output
        self.blending = blending
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.lenient(.width, 1920)
        height = c.lenient(.height, 1080)
        fps = c.lenient(.fps, Fps.thirty)
        background = c.lenient(.background, [0, 0, 0, 1])
        fitNewClips = c.lenient(.fitNewClips, true)
        timecodeFrames = c.lenient(.timecodeFrames, true)
        output = c.lenient(.output, .sdr)
        blending = c.lenient(.blending, .encoded)
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
    /// The track's fader, linear 0…4, and its pan, −1…1 (format 35, spec
    /// §11 AU-102); the core's envelope and plan apply both.
    let volume: Double
    let pan: Double
    /// The track's compressor and limiter (format 36, spec §11 AU-150), nil
    /// when off; post-fader on the track's sub-mix (AU-151).
    let compressor: CompressorProps?
    let limiter: LimiterProps?

    init(
        id: UInt32, name: String = "Track", hidden: Bool = false, muted: Bool = false,
        locked: Bool = false, solo: Bool = false, matte: TrackMatte = .none,
        volume: Double = 1, pan: Double = 0, compressor: CompressorProps? = nil,
        limiter: LimiterProps? = nil
    ) {
        self.id = id
        self.name = name
        self.hidden = hidden
        self.muted = muted
        self.locked = locked
        self.solo = solo
        self.matte = matte
        self.volume = volume
        self.pan = pan
        self.compressor = compressor
        self.limiter = limiter
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
        volume = c.lenient(.volume, 1.0)
        pan = c.lenient(.pan, 0.0)
        compressor = c.lenient(.compressor)
        limiter = c.lenient(.limiter)
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
    var color: RGBA
    var opacity: Double
    var blur: Double
    var angle: Double
    var distance: Double

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
    var key: [Double]
    var tolerance: Double
    var softness: Double
    var spill: Double

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
    var opacity: Double
    var height: Double
    var gap: Double
    /// 0 does not fade at all; 1 reaches transparent exactly at `height`.
    var falloff: Double

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
/// what is inside it (M3) — a stand-in for a freehand callout.
///
/// A VIDEO prop even though spec §4.2 first listed it under Shape: the zoom
/// half can only be drawn by the layer that owns the pixels. The centre and
/// the box are SOURCE pixels from the centre of the cropped rect, the same
/// frame `cornerRadius` and `crop` use.
struct SpotlightProps: Codable, Equatable {
    var shape: SpotShape
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Source pixels the edge is blurred over; 0 is a hard edge.
    var feather: Double
    /// How much darker everything OUTSIDE is; 1 is black.
    var dim: Double
    /// Magnification inside the region; 1 is none.
    var zoom: Double

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
    var shape: SpotShape
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// Source pixels the effect is ramped in over; 0 is a hard edge.
    var feather: Double
    var kind: ObscureKind
    /// 0 = the region is there but hides nothing, 1 = its full effect.
    var amount: Double

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
/// does not move (§5.3).
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
