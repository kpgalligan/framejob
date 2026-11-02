import AppKit

// The pixel half of a clip, `VideoProps`: a pure move out of
// `ProjectSnapshot.swift` (road map creator-jobs CJ0d, T11).

/// The pixel half of a clip. `x`/`y` are canvas pixels from the canvas
/// CENTRE, y down; `scale` 1 = native pixels; `rotation` degrees clockwise.
struct VideoProps: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
    var opacity: Double
    var crop: CropInsets
    /// Rounds the CROPPED rectangle, in source pixels, before rotation.
    var cornerRadius: Double
    var shadow: ShadowProps?
    var color: ColorAdjust
    var chroma: ChromaProps?
    /// Applied in order, at most `FilterProps.max` of them (M3).
    var filters: [FilterProps]
    var reflection: ReflectionProps?
    var spotlight: SpotlightProps?
    /// The obscured regions, at most `ObscureProps.max` of them (phase 3c).
    /// An empty list is how they are cleared, which is why this is a plain
    /// array and not an optional.
    var obscure: [ObscureProps]
    /// How this layer combines with what is already on the canvas (format
    /// version 6). `.normal` is source-over, so it is both the default and
    /// how a blend is cleared; there is no null form.
    var blend: BlendMode
    /// What the clip DOES — an entrance, an exit, a continuous motion
    /// (format version 8). Nothing on this side reads it to DRAW: the core
    /// turns a preset into placement inside the recipe, so the inspector and
    /// the canvas see the clip UN-MOVED while the picture moves (spec §5.4),
    /// which is why a drag begun mid-motion starts from the base box.
    var motion: MotionProps?
    /// Lift, gamma and gain (spec §11 GR-11, `GradeProps.swift`).
    var wheels: ColorWheels
    /// The tone curves (spec §11 GR-12, `CurveProps.swift`).
    var curves: ColorCurves
    /// An adjustment clip's qualifier (spec §11 GR-13, `QualifierProps.swift`).
    var qualifier: ColorQualifier
    /// The clip's look (spec §11 GR-7, `LookProps.swift`); nil is none.
    var look: LookProps?
    /// The clip's drawn cursor (format 38, spec §11 CU-30,
    /// `CursorProps.swift`); nil is none written.
    var cursor: CursorProps?
    /// The clip's Remove Background (format 39, spec §11 CO-20,
    /// `CutoutProps.swift`); nil is none written.
    var cutout: CutoutProps?

    init(
        x: Double = 0, y: Double = 0, scale: Double = 1, rotation: Double = 0,
        opacity: Double = 1, crop: CropInsets = .zero, cornerRadius: Double = 0,
        shadow: ShadowProps? = nil, color: ColorAdjust = .identity,
        chroma: ChromaProps? = nil, filters: [FilterProps] = [],
        reflection: ReflectionProps? = nil, spotlight: SpotlightProps? = nil,
        obscure: [ObscureProps] = [], blend: BlendMode = .normal,
        motion: MotionProps? = nil, wheels: ColorWheels = .neutral,
        curves: ColorCurves = .identity, qualifier: ColorQualifier = .none,
        look: LookProps? = nil, cursor: CursorProps? = nil, cutout: CutoutProps? = nil
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
        self.cursor = cursor
        self.cutout = cutout
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
        cursor = c.lenient(.cursor)
        cutout = c.lenient(.cutout)
    }

    static let identity = VideoProps()
    /// The clip's offset from the canvas centre, as a point.
    var offset: CGPoint { CGPoint(x: x, y: y) }
}
