import Foundation

// MARK: - The qualifier (spec §11 GR-13)

/// A hue band, in degrees: fully selected within `width / 2` of `center`
/// (wrapping at 360), falling to nothing across `softness` outside each
/// edge. The core's `HueRange`.
struct QualifierHue: Codable, Hashable {
    var center: Double
    var width: Double
    var softness: Double

    /// What ticking Hue on writes (`{}`, the core's default): the skin band.
    static let initial = QualifierHue(center: 30, width: 50, softness: 25)
}

/// A saturation or luma band, in 0…1: fully selected from `low` to `high`,
/// falling to nothing across `softness` outside each edge. The core's
/// `LevelRange`.
struct QualifierLevels: Codable, Hashable {
    var low: Double
    var high: Double
    var softness: Double

    /// What ticking a level range on writes (`{}`): everything passes.
    static let initial = QualifierLevels(low: 0, high: 1, softness: 0.1)
}

/// `video.qualifier` (format 18): which of the destination's pixels an
/// adjustment clip grades. A range that is nil is off; `invert` takes the
/// complement of the product; `blur` (format 21, spec §11 GR-35), 0…1,
/// softens the product by a Gaussian of σ = 24·blur canvas pixels.
struct ColorQualifier: Codable, Hashable {
    var hue: QualifierHue?
    var saturation: QualifierLevels?
    var luma: QualifierLevels?
    var invert: Bool
    var blur: Double

    init(
        hue: QualifierHue? = nil, saturation: QualifierLevels? = nil,
        luma: QualifierLevels? = nil, invert: Bool = false, blur: Double = 0
    ) {
        self.hue = hue
        self.saturation = saturation
        self.luma = luma
        self.invert = invert
        self.blur = blur
    }

    /// Lenient, like every reader of the core's JSON: an absent or malformed
    /// range is off, an absent `invert` is false, an absent `blur` 0.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hue = c.lenient(.hue)
        saturation = c.lenient(.saturation)
        luma = c.lenient(.luma)
        invert = c.lenient(.invert, false)
        blur = c.lenient(.blur, 0)
    }

    /// No range, not inverted, no blur: no key, and the pass weighs as before.
    static let none = ColorQualifier()

    var isNeutral: Bool {
        hue == nil && saturation == nil && luma == nil && !invert && blur == 0
    }

    /// σ at blur 1, in CANVAS pixels (GR-35, owner choice 2): the blur
    /// filter's 24 px reach.
    static let blurSigmaMax: Double = 24

    /// Whether the pass blurs q (GR-35): a range on and a blur above 0. A blur
    /// with no range is kept and saved, and draws nothing.
    var blursSelection: Bool {
        (hue != nil || saturation != nil || luma != nil) && blur > 0
    }

    /// The Gaussian's σ in DESTINATION pixels: blur · 24 canvas pixels over
    /// `canvasPerDest`, so a Half or Quarter preview blurs the same share of
    /// the picture as an export; capped at `MetalRenderer.maxShadowSigma`.
    /// Nil — today's inline pass, byte-identical — unless `blursSelection`
    /// and σ ≥ `MetalRenderer.minShadowSigma`.
    func selectionSigma(canvasPerDest: Float) -> Float? {
        guard blursSelection, canvasPerDest > 0 else { return nil }
        let sigma = Float(blur * Self.blurSigmaMax) / canvasPerDest
        guard sigma >= MetalRenderer.minShadowSigma else { return nil }
        return min(sigma, MetalRenderer.maxShadowSigma)
    }

    /// The level range `range` names (nil for `.hue`).
    func levels(_ range: QualifierRange) -> QualifierLevels? {
        switch range {
        case .hue: return nil
        case .saturation: return saturation
        case .luma: return luma
        }
    }

    /// Whether `range` is on.
    func isOn(_ range: QualifierRange) -> Bool {
        range == .hue ? hue != nil : levels(range) != nil
    }

    /// The section's summary: "off" only when neutral, or the ranges on, plus
    /// " · inverted", plus "blur N%" (whole percent) when the blur is above 0.
    var summary: String {
        let blurred = blur > 0 ? ["blur \(Int((blur * 100).rounded()))%"] : []
        let parts = QualifierRange.allCases.filter(isOn).map(\.short)
            + (invert ? ["inverted"] : []) + blurred
        return parts.isEmpty ? "off" : parts.joined(separator: " · ")
    }
}

/// The three ranges, in model order.
enum QualifierRange: String, CaseIterable {
    case hue, saturation, luma

    /// The checkbox's title and the range's undo name.
    var title: String {
        switch self {
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .luma: return "Luma"
        }
    }

    /// The summary's word.
    var short: String {
        switch self {
        case .hue: return "hue"
        case .saturation: return "sat"
        case .luma: return "luma"
        }
    }
}

/// One range's write: `null` turns it off, `{}` turns it on at the core's
/// default (a range already on keeps its values: `{}` merges nothing), and a
/// whole range replaces it.
enum QualifierWrite<T: Codable & Equatable>: Equatable, Codable {
    case off, on, set(T)

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .off
        } else if let value = try? single.decode(T.self) {
            self = .set(value)
        } else {
            self = .on
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .off:
            var single = encoder.singleValueContainer()
            try single.encodeNil()
        case .on:
            _ = encoder.container(keyedBy: QualifierNoKeys.self)
        case .set(let value):
            try value.encode(to: encoder)
        }
    }
}

/// `QualifierWrite.on`'s empty object.
private enum QualifierNoKeys: CodingKey {}

/// `VideoPatch.qualifier`: the ranges a write names, `invert` and `blur`.
struct ColorQualifierPatch: Codable, Equatable {
    var hue: QualifierWrite<QualifierHue>?
    var saturation: QualifierWrite<QualifierLevels>?
    var luma: QualifierWrite<QualifierLevels>?
    var invert: Bool?
    var blur: Double?

    init(
        hue: QualifierWrite<QualifierHue>? = nil, saturation: QualifierWrite<QualifierLevels>? = nil,
        luma: QualifierWrite<QualifierLevels>? = nil, invert: Bool? = nil, blur: Double? = nil
    ) {
        self.hue = hue
        self.saturation = saturation
        self.luma = luma
        self.invert = invert
        self.blur = blur
    }

    /// The section's Reset: every range off, Invert off and Blur 0.
    static let reset = ColorQualifierPatch(
        hue: .off, saturation: .off, luma: .off, invert: false, blur: 0)

    var isEmpty: Bool {
        hue == nil && saturation == nil && luma == nil && invert == nil && blur == nil
    }

    /// A write of one level range.
    static func levels(_ range: QualifierRange, _ write: QualifierWrite<QualifierLevels>)
        -> ColorQualifierPatch
    {
        range == .saturation ? ColorQualifierPatch(saturation: write)
            : ColorQualifierPatch(luma: write)
    }

    /// `range` turned on (`{}`) or off (`null`) — the row's checkbox.
    static func toggle(_ range: QualifierRange, _ on: Bool) -> ColorQualifierPatch {
        switch range {
        case .hue: return ColorQualifierPatch(hue: on ? .on : .off)
        case .saturation, .luma: return .levels(range, on ? .on : .off)
        }
    }
}

// MARK: - The shader's block

/// The adjustment pass's `buffer(1)` (`Compositor.metal`'s
/// `QualifierUniforms`, field for field: sixteen scalar floats, 64 bytes).
struct QualifierUniforms {
    var hueEnabled: Float = 0
    var hueCenter: Float = 0
    var hueWidth: Float = 0
    var hueSoftness: Float = 0
    var satEnabled: Float = 0
    var satLow: Float = 0
    var satHigh: Float = 0
    var satSoftness: Float = 0
    var lumaEnabled: Float = 0
    var lumaLow: Float = 0
    var lumaHigh: Float = 0
    var lumaSoftness: Float = 0
    var invert: Float = 0
    var selection: Float = 0
    var enabled: Float = 0
    /// 1 when the pass reads q from the blurred map at `texture(0)` instead
    /// of computing it (spec §11 GR-35); set only by `drawAdjustment`.
    var blurred: Float = 0

    /// `q`'s block, `enabled` 1 exactly when the qualifier is not neutral,
    /// so an unqualified pass skips the reading and weighs as it did.
    /// `blurred` stays 0: only `drawAdjustment` knows whether a map was made.
    init(_ q: ColorQualifier, selection: Bool) {
        if let hue = q.hue {
            hueEnabled = 1
            hueCenter = Float(hue.center)
            hueWidth = Float(hue.width)
            hueSoftness = Float(hue.softness)
        }
        if let s = q.saturation {
            satEnabled = 1
            satLow = Float(s.low)
            satHigh = Float(s.high)
            satSoftness = Float(s.softness)
        }
        if let l = q.luma {
            lumaEnabled = 1
            lumaLow = Float(l.low)
            lumaHigh = Float(l.high)
            lumaSoftness = Float(l.softness)
        }
        invert = q.invert ? 1 : 0
        self.selection = selection ? 1 : 0
        enabled = q.isNeutral ? 0 : 1
    }
}

// MARK: - The pick (owner choice 8)

/// One pixel read as the shader reads it (GR-13), in Double: HSV hue in
/// degrees (0 with no chroma), chroma C = max − min, the GUARDED saturation
/// S′ = (C / max) · smoothstep(0.03, 0.10, max), and Rec. 709 Y′.
struct QualifierSample {
    let hue: Double
    let chroma: Double
    let saturation: Double
    let luma: Double

    init(_ rgb: RGBA) {
        let r = rgb.count > 0 ? rgb[0] : 0
        let g = rgb.count > 1 ? rgb[1] : 0
        let b = rgb.count > 2 ? rgb[2] : 0
        let mx = max(r, g, b)
        let c = mx - min(r, g, b)
        var h = 0.0
        if c > 0 {
            if mx == r {
                h = 60 * ((g - b) / c + 6).truncatingRemainder(dividingBy: 6)
            } else if mx == g {
                h = 60 * ((b - r) / c + 2)
            } else {
                h = 60 * ((r - g) / c + 4)
            }
        }
        hue = h
        chroma = c
        saturation = (mx > 0 ? c / mx : 0) * Self.smoothstep(0.03, 0.10, mx)
        luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Metal's `smoothstep`, Hermite.
    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

extension ColorQualifier {
    /// The chroma below which a pick has no hue (GR-13's guard's full point).
    static let pickChroma = 0.06

    /// What a pick of `s` writes (owner choice 8): hue and saturation on and
    /// centred on the pixel — a range already on keeps its width and
    /// softness; one off takes hue width 30° softness 15° and saturation
    /// ±0.15 softness 0.1 — and luma re-centred only if already on. A level
    /// range that would cross 0 or 1 is SHIFTED back inside with its width
    /// kept, so the pixel stays inside. A pixel with C below 0.06 turns hue
    /// off; Invert is unchanged.
    func picked(_ s: QualifierSample) -> ColorQualifierPatch {
        var patch = ColorQualifierPatch()
        if s.chroma < Self.pickChroma {
            patch.hue = .off
        } else {
            let width = hue?.width ?? 30
            let softness = hue?.softness ?? 15
            let center = min(max(s.hue, 0), 360)
            patch.hue = .set(QualifierHue(center: center, width: width, softness: softness))
        }
        let saturated = saturation ?? QualifierLevels(low: 0, high: 0.3, softness: 0.1)
        patch.saturation = .set(Self.centred(saturated, on: s.saturation))
        if let luma {
            patch.luma = .set(Self.centred(luma, on: s.luma))
        }
        return patch
    }

    /// `range` moved so its middle is `value`, its width and softness kept,
    /// then shifted back inside 0…1 whole.
    static func centred(_ range: QualifierLevels, on value: Double) -> QualifierLevels {
        let width = min(max(range.high - range.low, 0), 1)
        var low = value - width / 2
        low = min(max(low, 0), 1 - width)
        return QualifierLevels(low: low, high: min(low + width, 1), softness: range.softness)
    }
}
