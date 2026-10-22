import AVFoundation
import simd

/// How an HLG project's chroma key reads a keyed layer (spec §11 HD-19 (c),
/// #312, the owner's "Key means SDR colour"): the colour it compares against
/// the stored key is the one an SDR project shows for that pixel, so a key
/// picked in an SDR project keys the same colour after the switch to HLG.
///
/// - `.hlg` — the layer's source is HLG: GR-15's HLG arm over BT.2020, applied
///   to the working colour. Exact for an HLG BT.2020 source; close for HLG
///   over P3 or BT.709, whose working colour was matrixed in scene light.
/// - `.pq` — the source is PQ: the working colour back to display light (the
///   inverse OETF, BT.2100's OOTF γ 1.2, × 1000/203), then GR-15's PQ arm's
///   matrix, gamut lift and shoulder to max(peak, 203)/203. Exact up to 1,000
///   cd/m²; close above, where BT.2390's EETF is not undone.
/// - `.log` — the layer's media has a built-in Camera Log (spec §11 HD-20
///   (a), #324): the working colour back to scene light (the inverse OETF,
///   HD-13 (e)'s BT.2020 reflection × `logHLGExposure`), × `logExposure /
///   logHLGExposure`, then GR-16's SDR arm's matrix, gamut lift and shoulder
///   to `logWhite`. Exact where the HLG arm floored no channel and did not
///   clip (reflection ≤ 3.74).
/// - `.unlift` — every other layer (LUT media, SDR sources, drawn layers):
///   HD-13 (h)'s inverse lift, unchanged, exact for a LUT media's output,
///   which HD-3 lifted.
///
/// The shader's `keyReadSDR` and `hlgUnliftSDR` read it from
/// `LayerUniforms.keyReading` (`uniform`); `sdr` is their CPU twin, and the
/// HLG eyedropper stores `pick` of the clicked colour.
enum KeyReading: Equatable {
    case unlift, hlg, pq(peak: UInt32?), log

    /// `LayerUniforms.keyReading`: 0 the un-lift, 1 the HLG arm, 2 the
    /// camera-log arm, and for PQ minus the shoulder's white, max(peak,
    /// 203)/203 with 1,000 cd/m² when none is named — never above −1, so the
    /// shader tells the four apart.
    var uniform: Float {
        switch self {
        case .unlift: return 0
        case .hlg: return 1
        case .log: return 2
        case .pq(let peak): return -InputConversions.pqShoulderWhite(peak: peak)
        }
    }

    /// The SDR colour this reading takes a working HLG colour to, unclamped:
    /// the shader's `keyReadSDR` (and, for `.unlift`, `hlgUnliftSDR`).
    func sdr(_ hlg: SIMD3<Float>) -> SIMD3<Float> {
        let scene = SIMD3<Float>(
            InputConversions.hlgInverseOETF(hlg.x), InputConversions.hlgInverseOETF(hlg.y),
            InputConversions.hlgInverseOETF(hlg.z))
        let ys = simd_dot(scene, InputConversions.luma2020)
        let light: SIMD3<Float>
        let white: Float
        switch self {
        case .unlift:
            return InputConversions.unliftSDR(hlg)
        case .hlg:
            light = ys > 1e-6
                ? InputConversions.hlgGain * scene * pow(ys, InputConversions.hlgSystemGamma - 1)
                : .zero
            white = InputConversions.hlgWhite
        case .pq(let peak):
            let display = ys > 0
                ? scene * pow(ys, InputConversions.hlgNominalGamma - 1) : .zero
            light = display * (InputConversions.pqWhite / InputConversions.pqReferenceWhite)
            white = InputConversions.pqShoulderWhite(peak: peak)
        case .log:
            light = scene * (InputConversions.logExposure / InputConversions.logHLGExposure)
            white = InputConversions.logWhite
        }
        let linear = Self.shoulder(
            Self.gamutLift(InputConversions.toBT709(from: .bt2020) * light), white: white)
        let encode = 1 / InputConversions.displayGamma
        return SIMD3<Float>(
            pow(max(linear.x, 0), encode), pow(max(linear.y, 0), encode),
            pow(max(linear.z, 0), encode))
    }

    /// The eyedropper's stored key in an HLG project: a picked HLG colour
    /// read through `sdr`, each channel clamped to [0, 1], its alpha kept.
    /// `.unlift`'s is `InputConversions.unliftedPick` itself, so the probe's
    /// P6 and P12 read one function.
    func pick(_ color: RGBA) -> RGBA {
        if self == .unlift { return InputConversions.unliftedPick(color) }
        guard color.count >= 3 else { return color }
        let rgb = sdr(SIMD3<Float>(Float(color[0]), Float(color[1]), Float(color[2])))
        return [rgb.x, rgb.y, rgb.z].map { Double(min(max($0, 0), 1)) } + color.dropFirst(3)
    }

    /// The reading of a source whose SDR-project step-0 choice is
    /// `conversion` — a frame's `choose(input:buffer:output: .sdr)` or a
    /// still's `StillColor` arm — with its media's effective PQ peak: a
    /// built-in Camera Log `.log`, a LUT (and no conversion) `.unlift`.
    static func of(_ conversion: InputConversion?, peak: UInt32?) -> KeyReading {
        switch conversion {
        case .hlg: return .hlg
        case .pq: return .pq(peak: peak)
        case .log: return .log
        default: return .unlift
        }
    }

    /// The reading of a media, for the eyedropper, which has no frame: a
    /// still by its colour space with its effective PQ peak (spec §11 HD-20
    /// (b)); a video by its Camera Log when one converts it (GR-16 chooses
    /// before the labels: a built-in curve `.log`, a LUT `.unlift`), else by
    /// its track's labels (`ThumbnailInput(track:)`, await-free) with its
    /// effective PQ peak; every other media, or none at `url`, `.unlift`. Off
    /// the main thread: the track lookup reads the file.
    static func of(media: MediaSnapshot, url: URL?) -> KeyReading {
        guard let url else { return .unlift }
        switch media.kind {
        case .image:
            // By the file's colour space. Should Core Graphics refuse the
            // still's HDR bitmap at draw time, the layer falls back to the SDR
            // path and the shader reads `.unlift` against this pick: rare, and
            // a re-pick fixes it.
            return of(StillColor.conversion(at: url), peak: media.color?.pq?.effectivePeak)
        case .video:
            if let color = media.color, let chosen = InputConversion.choose(input: color) {
                return of(chosen, peak: nil)
            }
            let track = CompositionBuilder.firstTrack(of: AVURLAsset(url: url), mediaType: .video)
            switch track.flatMap(ThumbnailInput.init(track:))?.transfer {
            case .hlg: return .hlg
            case .pq: return .pq(peak: media.color?.pq?.effectivePeak)
            case nil: return .unlift
            }
        case .audio, .lut:
            return .unlift
        }
    }

    /// The keyed clips' one reading: theirs when every one agrees, else (and
    /// for none) the un-lift.
    static func common(_ readings: [KeyReading]) -> KeyReading {
        guard let first = readings.first, readings.allSatisfy({ $0 == first }) else {
            return .unlift
        }
        return first
    }

    /// GR-15's gamut lift (the shader's `inputLift`): a colour with a negative
    /// channel moves toward its BT.709 luminance until its lowest channel is 0.
    private static func gamutLift(_ l: SIMD3<Float>) -> SIMD3<Float> {
        let low = min(l.x, l.y, l.z)
        guard low < 0 else { return l }
        let y = simd_dot(l, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        return y <= 0 ? .zero : y + (l - y) * (y / (y - low))
    }

    /// GR-15's shoulder (the shader's `inputShoulder`) from
    /// `InputConversions.shoulderKnee`, reaching 1 at `white`.
    private static func shoulder(_ l: SIMD3<Float>, white: Float) -> SIMD3<Float> {
        let knee = InputConversions.shoulderKnee
        let m = max(l.x, l.y, l.z)
        guard m > knee else { return l }
        var s: Float = 1
        if m < white {
            let t = (m - knee) / (1 - knee)
            let tw = (white - knee) / (1 - knee)
            s = knee + (1 - knee) * t * (1 + t / (tw * tw)) / (1 + t)
        }
        return l * (s / m)
    }
}
