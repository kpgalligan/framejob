import Foundation

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
