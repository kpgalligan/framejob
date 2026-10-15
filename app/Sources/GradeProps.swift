import AppKit

// MARK: - Grading's value types (road map grading, spec §11 GR-2)

/// Per-clip colour controls, all centred on 0 = no change.
struct ColorAdjust: Codable, Hashable {
    let brightness: Double
    let contrast: Double
    let saturation: Double
    /// Hue rotation in degrees.
    let hue: Double
    /// Tone (spec §11 GR-2): `model_props.rs`'s nine, in its order, each
    /// absent from the file at 0. Their helpers are below.
    let exposure: Double
    let temperature: Double
    let tint: Double
    let highlights: Double
    let shadows: Double
    let whites: Double
    let blacks: Double
    let vibrance: Double
    let fade: Double

    init(
        brightness: Double = 0, contrast: Double = 0, saturation: Double = 0, hue: Double = 0,
        exposure: Double = 0, temperature: Double = 0, tint: Double = 0, highlights: Double = 0,
        shadows: Double = 0, whites: Double = 0, blacks: Double = 0, vibrance: Double = 0,
        fade: Double = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.vibrance = vibrance
        self.fade = fade
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = c.lenient(.brightness, 0)
        contrast = c.lenient(.contrast, 0)
        saturation = c.lenient(.saturation, 0)
        hue = c.lenient(.hue, 0)
        exposure = c.lenient(.exposure, 0)
        temperature = c.lenient(.temperature, 0)
        tint = c.lenient(.tint, 0)
        highlights = c.lenient(.highlights, 0)
        shadows = c.lenient(.shadows, 0)
        whites = c.lenient(.whites, 0)
        blacks = c.lenient(.blacks, 0)
        vibrance = c.lenient(.vibrance, 0)
        fade = c.lenient(.fade, 0)
    }

    static let identity = ColorAdjust()
    var isIdentity: Bool { self == .identity }
}

/// What a colour write SENDS: any subset of `video.color`'s thirteen keys, in
/// the model's order, each nil when the write does not name it. The Light and
/// Color rows send only their own key, so a write over a multi-selection keeps
/// each clip's other values — `ColorAdjust`, the snapshot's read-only mirror,
/// is always all thirteen and would carry the first clip's values to every
/// other. An action's end decodes its `color` through this type too, so the
/// sub-tab's `◆N` sees exactly the keys an end holds.
struct ColorPatch: Codable, Equatable {
    var brightness: Double?
    var contrast: Double?
    var saturation: Double?
    var hue: Double?
    var exposure: Double?
    var temperature: Double?
    var tint: Double?
    var highlights: Double?
    var shadows: Double?
    var whites: Double?
    var blacks: Double?
    var vibrance: Double?
    var fade: Double?

    init(
        brightness: Double? = nil, contrast: Double? = nil, saturation: Double? = nil,
        hue: Double? = nil, exposure: Double? = nil, temperature: Double? = nil,
        tint: Double? = nil, highlights: Double? = nil, shadows: Double? = nil,
        whites: Double? = nil, blacks: Double? = nil, vibrance: Double? = nil,
        fade: Double? = nil
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hue = hue
        self.exposure = exposure
        self.temperature = temperature
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.vibrance = vibrance
        self.fade = fade
    }

    /// Every key, the whole group: what the canvas's eyedropper writes to
    /// neutralise a clip while it picks.
    init(_ whole: ColorAdjust) {
        self.init(
            brightness: whole.brightness, contrast: whole.contrast,
            saturation: whole.saturation, hue: whole.hue, exposure: whole.exposure,
            temperature: whole.temperature, tint: whole.tint, highlights: whole.highlights,
            shadows: whole.shadows, whites: whole.whites, blacks: whole.blacks,
            vibrance: whole.vibrance, fade: whole.fade)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = c.lenient(.brightness)
        contrast = c.lenient(.contrast)
        saturation = c.lenient(.saturation)
        hue = c.lenient(.hue)
        exposure = c.lenient(.exposure)
        temperature = c.lenient(.temperature)
        tint = c.lenient(.tint)
        highlights = c.lenient(.highlights)
        shadows = c.lenient(.shadows)
        whites = c.lenient(.whites)
        blacks = c.lenient(.blacks)
        vibrance = c.lenient(.vibrance)
        fade = c.lenient(.fade)
    }

    /// The Color section's Reset: its four keys at 0, and nothing of Light's.
    static let neutralColor = ColorPatch(brightness: 0, contrast: 0, saturation: 0, hue: 0)

    /// The Light section's Reset: its nine keys at 0, and nothing of Color's.
    static let neutralLight = ColorPatch(
        exposure: 0, temperature: 0, tint: 0, highlights: 0, shadows: 0, whites: 0, blacks: 0,
        vibrance: 0, fade: 0)

    var isEmpty: Bool { self == ColorPatch() }
}

extension ColorAdjust {
    /// The Color section's four at 0 (its summary and its Reset's question).
    var isColorNeutral: Bool { brightness == 0 && contrast == 0 && saturation == 0 && hue == 0 }

    /// The Light section's nine at 0 — the tone keys `toneEnabled` reads.
    var isLightNeutral: Bool {
        exposure == 0 && temperature == 0 && tint == 0 && highlights == 0 && shadows == 0
            && whites == 0 && blacks == 0 && vibrance == 0 && fade == 0
    }
}

extension LayerUniforms {
    /// Tone's twelve floats (spec §11 GR-2): the nine in the model's order,
    /// and `toneEnabled` 1 exactly when one of them is not 0 — a negative
    /// value enables it as surely as a positive one. An untoned layer leaves
    /// the flag at 0 and never enters step 4c, so it renders byte-identical.
    mutating func apply(tone color: ColorAdjust) {
        let values = [
            color.exposure, color.temperature, color.tint, color.highlights, color.shadows,
            color.whites, color.blacks, color.vibrance, color.fade,
        ]
        exposure = Float(color.exposure)
        temperature = Float(color.temperature)
        tint = Float(color.tint)
        highlights = Float(color.highlights)
        shadows = Float(color.shadows)
        whites = Float(color.whites)
        blacks = Float(color.blacks)
        vibrance = Float(color.vibrance)
        fade = Float(color.fade)
        toneEnabled = values.contains { $0 != 0 } ? 1 : 0
    }
}

// MARK: - The wheels (spec §11 GR-11, grading-2 G2-2)

/// One wheel: the puck (`x`, `y`, inside the unit circle — its angle the hue,
/// 0° red, its distance the strength) and `master`, each −1…1, 0 neutral.
/// `model_grade.rs`'s `Wheel`, read leniently, each key absent at 0.
struct ColorWheel: Codable, Hashable {
    let x: Double
    let y: Double
    let master: Double

    init(x: Double = 0, y: Double = 0, master: Double = 0) {
        self.x = x
        self.y = y
        self.master = master
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x, 0)
        y = c.lenient(.y, 0)
        master = c.lenient(.master, 0)
    }

    static let neutral = ColorWheel()
    var isNeutral: Bool { self == .neutral }
}

/// `video.wheels`: lift, gamma and gain, in the model's order everywhere.
struct ColorWheels: Codable, Hashable {
    let lift: ColorWheel
    let gamma: ColorWheel
    let gain: ColorWheel

    init(lift: ColorWheel = .neutral, gamma: ColorWheel = .neutral, gain: ColorWheel = .neutral) {
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lift = c.lenient(.lift, ColorWheel.neutral)
        gamma = c.lenient(.gamma, ColorWheel.neutral)
        gain = c.lenient(.gain, ColorWheel.neutral)
    }

    static let neutral = ColorWheels()
    var isNeutral: Bool { self == .neutral }
}

/// What a wheel write SENDS: any of a wheel's three keys, each nil when the
/// write does not name it. A puck sends only `x, y`, a strip or a field only
/// `master`, so a write over several clips keeps each one's other values.
struct ColorWheelPatch: Codable, Equatable {
    var x: Double?
    var y: Double?
    var master: Double?

    init(x: Double? = nil, y: Double? = nil, master: Double? = nil) {
        self.x = x
        self.y = y
        self.master = master
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = c.lenient(.x)
        y = c.lenient(.y)
        master = c.lenient(.master)
    }

    var isEmpty: Bool { self == ColorWheelPatch() }
}

/// A sparse `wheels` write: the wheels it names, each sparse in turn. An
/// action's end decodes its `wheels` through this type too, so the sub-tab's
/// `◆N` sees exactly the keys an end holds.
struct ColorWheelsPatch: Codable, Equatable {
    var lift: ColorWheelPatch?
    var gamma: ColorWheelPatch?
    var gain: ColorWheelPatch?

    init(lift: ColorWheelPatch? = nil, gamma: ColorWheelPatch? = nil, gain: ColorWheelPatch? = nil) {
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lift = c.lenient(.lift)
        gamma = c.lenient(.gamma)
        gain = c.lenient(.gain)
    }

    /// The Wheels section's Reset: all nine at 0.
    static let neutral = ColorWheelsPatch(
        lift: ColorWheelPatch(x: 0, y: 0, master: 0),
        gamma: ColorWheelPatch(x: 0, y: 0, master: 0),
        gain: ColorWheelPatch(x: 0, y: 0, master: 0))

    var isEmpty: Bool {
        (lift?.isEmpty ?? true) && (gamma?.isEmpty ?? true) && (gain?.isEmpty ?? true)
    }
}

/// The three wheels as the Wheels section's columns: each one's title (its
/// undo name), its value in a `ColorWheels` and a patch naming it alone.
enum ColorWheelKind: CaseIterable {
    case lift, gamma, gain

    var title: String {
        switch self {
        case .lift: return "Lift"
        case .gamma: return "Gamma"
        case .gain: return "Gain"
        }
    }

    func wheel(_ wheels: ColorWheels) -> ColorWheel {
        switch self {
        case .lift: return wheels.lift
        case .gamma: return wheels.gamma
        case .gain: return wheels.gain
        }
    }

    func patch(_ wheel: ColorWheelPatch) -> ColorWheelsPatch {
        switch self {
        case .lift: return ColorWheelsPatch(lift: wheel)
        case .gamma: return ColorWheelsPatch(gamma: wheel)
        case .gain: return ColorWheelsPatch(gain: wheel)
        }
    }
}

extension LayerUniforms {
    /// The wheels' twelve floats (spec §11 GR-11): the nine in the model's
    /// order, and `wheelsEnabled` 1 exactly when one of them is not 0 — a
    /// negative value enables it as surely as a positive one. An unwheeled
    /// layer leaves the flag at 0 and never enters step 4c.1, so it renders
    /// byte-identical. `curvesEnabled` and `hueCurvesEnabled` are not
    /// touched.
    mutating func apply(wheels: ColorWheels) {
        let values = [
            wheels.lift.x, wheels.lift.y, wheels.lift.master,
            wheels.gamma.x, wheels.gamma.y, wheels.gamma.master,
            wheels.gain.x, wheels.gain.y, wheels.gain.master,
        ]
        liftX = Float(wheels.lift.x)
        liftY = Float(wheels.lift.y)
        liftMaster = Float(wheels.lift.master)
        gammaX = Float(wheels.gamma.x)
        gammaY = Float(wheels.gamma.y)
        gammaMaster = Float(wheels.gamma.master)
        gainX = Float(wheels.gain.x)
        gainY = Float(wheels.gain.y)
        gainMaster = Float(wheels.gain.master)
        wheelsEnabled = values.contains { $0 != 0 } ? 1 : 0
    }
}
