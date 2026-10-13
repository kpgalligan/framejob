import CoreMedia
import CoreVideo
import simd

/// The primaries a converted source is read in: the gamut step 0's matrix
/// takes to BT.709 (spec §11 GR-15), and the camera gamuts of GR-16.
enum InputPrimaries: Equatable {
    case bt709, bt2020, p3D65, sGamut3Cine, sGamut3, vGamut, appleWideGamut

    /// A media's camera gamut (spec §11 GR-16).
    init(_ gamut: CameraGamut) {
        switch gamut {
        case .bt2020: self = .bt2020
        case .sGamut3Cine: self = .sGamut3Cine
        case .sGamut3: self = .sGamut3
        case .vGamut: self = .vGamut
        case .appleWideGamut: self = .appleWideGamut
        }
    }
}

/// Step 0's conversion of one source (spec §11 GR-15), chosen from its
/// buffer's colour labels: HLG or PQ to SDR Rec. 709, a wide-gamut SDR
/// source's matrix to BT.709, or an sRGB-transfer source's sRGB arm. nil —
/// the identity — for every other source, which is then sampled exactly as
/// before T3-1 (no pass, its own texture). A media's Camera Log (GR-16)
/// chooses before the labels: a maker's log curve and its camera gamut, or a
/// `lut` media's table.
enum InputConversion: Equatable {
    case hlg(InputPrimaries), pq(InputPrimaries), sdrWide(InputPrimaries), srgb(InputPrimaries)
    case log(LogCurve, InputPrimaries), lut(UInt32)

    /// Whether a source answering this makes its composition a converting
    /// one (`ConvertingCompositor`, GR-15 as amended). False only for
    /// `.srgb(.bt709)`: that arm runs inside a converting composition, so the
    /// clip renders there as it does alone, but never makes one.
    var startsConversion: Bool { self != .srgb(.bt709) }

    /// GR-15's selector, by TRANSFER first: a log transfer (Apple Log's
    /// `LogTransferFunction`, which carries BT.2020 primaries and an
    /// unspecified transfer) stays the identity until GR-16 assigns it a
    /// conversion; HLG and PQ convert whatever their primaries (absent or
    /// unknown read as BT.2020); the sRGB transfer takes the sRGB arm with
    /// its primaries (absent or other read as BT.709); the BT.709 and BT.2020
    /// transfers convert only with BT.2020 or P3 D65 primaries. Anything else
    /// is the identity.
    static func choose(
        transfer: String?, primaries: String?, logTransfer: String?
    ) -> InputConversion? {
        guard logTransfer == nil else { return nil }
        switch transfer {
        case Label.hlg: return .hlg(hdrPrimaries(primaries))
        case Label.pq: return .pq(hdrPrimaries(primaries))
        case Label.sRGB: return srgb(primaries)
        case Label.bt709, Label.bt2020: return wide(primaries)
        default: return nil
        }
    }

    /// GR-16's selector, over a media's Camera Log as a recipe layer's
    /// `input` carries it: its curve and gamut (the curve's first when none
    /// is stored), else its LUT; nil for neither.
    static func choose(input: MediaColor) -> InputConversion? {
        if let log = input.log, let gamut = input.effectiveGamut {
            return .log(log, InputPrimaries(gamut))
        }
        return input.lut.map { .lut($0) }
    }

    /// The selector over a decoded frame's own attachments — the labels
    /// AVFoundation hands a compositor that conforms colour itself.
    static func choose(for buffer: CVPixelBuffer) -> InputConversion? {
        func label(_ key: CFString) -> String? {
            CVBufferCopyAttachment(buffer, key, nil) as? String
        }
        return choose(
            transfer: label(kCVImageBufferTransferFunctionKey),
            primaries: label(kCVImageBufferColorPrimariesKey),
            logTransfer: label(kCVImageBufferLogTransferFunctionKey))
    }

    /// The selector over a track's format description: the same three labels,
    /// as its extensions (`CompositionBuilder.convertsSources`).
    static func choose(for description: CMFormatDescription) -> InputConversion? {
        func label(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(description, extensionKey: key) as? String
        }
        return choose(
            transfer: label(kCMFormatDescriptionExtension_TransferFunction),
            primaries: label(kCMFormatDescriptionExtension_ColorPrimaries),
            logTransfer: label(kCMFormatDescriptionExtension_LogTransferFunction))
    }

    /// The attachment values the selector reads, as strings.
    private enum Label {
        static let hlg = kCVImageBufferTransferFunction_ITU_R_2100_HLG as String
        static let pq = kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String
        static let bt709 = kCVImageBufferTransferFunction_ITU_R_709_2 as String
        static let bt2020 = kCVImageBufferTransferFunction_ITU_R_2020 as String
        static let sRGB = kCVImageBufferTransferFunction_sRGB as String
        static let primaries709 = kCVImageBufferColorPrimaries_ITU_R_709_2 as String
        static let primaries2020 = kCVImageBufferColorPrimaries_ITU_R_2020 as String
        static let p3D65 = kCVImageBufferColorPrimaries_P3_D65 as String
    }

    private static func hdrPrimaries(_ primaries: String?) -> InputPrimaries {
        switch primaries {
        case Label.p3D65: return .p3D65
        case Label.primaries709: return .bt709
        default: return .bt2020
        }
    }

    private static func srgb(_ primaries: String?) -> InputConversion? {
        switch primaries {
        case Label.primaries2020: return .srgb(.bt2020)
        case Label.p3D65: return .srgb(.p3D65)
        default: return .srgb(.bt709)
        }
    }

    private static func wide(_ primaries: String?) -> InputConversion? {
        switch primaries {
        case Label.primaries2020: return .sdrWide(.bt2020)
        case Label.p3D65: return .sdrWide(.p3D65)
        default: return nil
        }
    }

    /// The pass's uniform block for this conversion; `premultiplied` is the
    /// buffer's own label (spec §11 G-35 (b)).
    func uniforms(premultiplied: Bool) -> InputUniforms {
        let primaries: InputPrimaries
        var uniforms = InputUniforms()
        switch self {
        case .hlg(let p):
            uniforms.kind = InputUniforms.hlg
            uniforms.white = InputConversions.hlgWhite
            primaries = p
        case .pq(let p):
            uniforms.kind = InputUniforms.pq
            uniforms.white = InputConversions.pqWhite / InputConversions.pqReferenceWhite
            primaries = p
        case .sdrWide(let p):
            uniforms.kind = InputUniforms.sdrWide
            uniforms.white = 1
            primaries = p
        case .srgb(let p):
            uniforms.kind = InputUniforms.srgb
            uniforms.white = 1
            uniforms.encodePower = 1 / InputConversions.coreMedia709Gamma
            primaries = p
        case .log(let curve, let p):
            uniforms.kind = InputUniforms.kind(of: curve)
            uniforms.white = InputConversions.logWhite
            uniforms.exposure = InputConversions.logExposure
            let domain = InputConversions.codeDomain(curve)
            uniforms.codeScale = domain.scale
            uniforms.codeOffset = domain.offset
            primaries = p
        case .lut:
            // The table's output is taken as encoded Rec. 709: no matrix.
            uniforms.kind = InputUniforms.lut
            uniforms.white = 1
            primaries = .bt709
        }
        uniforms.premultiplied = premultiplied ? 1 : 0
        uniforms.systemGamma = InputConversions.hlgSystemGamma
        uniforms.hlgGain = InputConversions.hlgGain
        uniforms.knee = InputConversions.shoulderKnee
        uniforms.nitsScale = 10_000 / InputConversions.pqReferenceWhite
        if case .srgb = self {} else {
            uniforms.encodePower = 1 / InputConversions.displayGamma
        }
        uniforms.decodePower = InputConversions.displayGamma
        uniforms.setMatrix(InputConversions.toBT709(from: primaries))
        return uniforms
    }
}

/// Every number step 0 uses that Frame Job CHOSE or DERIVED (spec §11 GR-15,
/// T3-1's append); the shader holds only the standards' own constants (the
/// BT.2100 HLG inverse OETF's a, b, c, SMPTE ST 2084's m1, m2, c1–c3, the
/// BT.2020 and BT.709 luminance weights) and the formulas' shapes.
enum InputConversions {
    /// HLG's system gamma and gain: Frame Job's anchor to Apple's measured
    /// brightness (choice 2a), not BT.2100's nominal γ 1.2.
    static let hlgSystemGamma: Float = 0.96, hlgGain: Float = 1.07
    /// Where the shoulder starts, on the largest linear channel.
    static let shoulderKnee: Float = 0.39
    /// The linear value the shoulder maps to 1: HLG's at full signal (the gain).
    static let hlgWhite: Float = 1.07
    /// PQ's reference white (BT.2408, 203 cd/m², drawn as 1.0) and the
    /// brightness its shoulder reaches 1 at (1,000 cd/m²).
    static let pqReferenceWhite: Float = 203, pqWhite: Float = 1000
    /// BT.1886's display gamma: the encode is its inverse, `L^(1/2.4)`, and
    /// a wide-gamut SDR source's decode is `signal^2.4`.
    static let displayGamma: Float = 2.4
    /// The gamma of Core Media's BT.709 profile (its TRC, `curv` 502/256), which
    /// ColorSync reads a converted frame through: the sRGB arm's encode is its
    /// inverse, so an sRGB-transfer clip renders as it does alone (GR-15 as
    /// amended, measured M7).
    static let coreMedia709Gamma: Float = 502.0 / 256.0

    /// GR-16's display transform for camera log (choice 4a, "42%, as
    /// planned"): 18 % grey encodes to this mid-grey (107/255, near BT.709's
    /// 0.409), so scene light is scaled by the exposure 0.42^2.4/0.18
    /// (≈ 0.6927) before the matrix, and the shoulder reaches 1 at the white
    /// 64·0.42^2.4 (≈ 7.98), six stops over 18 % grey.
    static let logMidGrey: Float = 0.42
    static let logExposure: Float = pow(logMidGrey, displayGamma) / 0.18
    static let logWhite: Float = 64 * pow(logMidGrey, displayGamma)
    /// Sony's and Panasonic's curves read the STORED 10-bit code over 1023,
    /// and a video-range file decodes to s = (code − 64)/876: their signal is
    /// s·876/1023 + 64/1023. Apple's is the normalized signal itself (GR-16's
    /// code domains).
    static let videoCodeScale: Float = 876.0 / 1023.0, videoCodeOffset: Float = 64.0 / 1023.0

    /// A curve's code domain as the pass's `codeScale` and `codeOffset`.
    static func codeDomain(_ curve: LogCurve) -> (scale: Float, offset: Float) {
        switch curve {
        case .appleLog, .appleLog2: return (1, 0)
        case .slog3, .vlog: return (videoCodeScale, videoCodeOffset)
        }
    }

    /// Published chromaticities (x, y) of red, green and blue: ITU-R BT.709,
    /// ITU-R BT.2020, and P3 D65 (SMPTE EG 432-1); the camera gamuts from
    /// their makers' documents (GR-16's append): Sony's S-Gamut3.Cine and
    /// S-Gamut3, Panasonic's V-Gamut, Apple's Apple Wide Gamut. Every white
    /// is D65.
    private static func chromaticities(_ primaries: InputPrimaries) -> [SIMD2<Double>] {
        switch primaries {
        case .bt709: return [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]]
        case .bt2020: return [[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]]
        case .p3D65: return [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]]
        case .sGamut3Cine: return [[0.766, 0.275], [0.225, 0.800], [0.089, -0.087]]
        case .sGamut3: return [[0.730, 0.280], [0.140, 0.855], [0.100, -0.050]]
        case .vGamut: return [[0.730, 0.280], [0.165, 0.840], [0.100, -0.030]]
        case .appleWideGamut: return [[0.725, 0.301], [0.221, 0.814], [0.068, -0.076]]
        }
    }

    private static let d65 = SIMD2<Double>(0.3127, 0.3290)

    /// Linear RGB → XYZ for `primaries` and D65, by the standard derivation:
    /// each primary's XYZ at Y = 1 as a column, scaled so white sums to D65.
    private static func rgbToXYZ(_ primaries: InputPrimaries) -> simd_double3x3 {
        let columns = chromaticities(primaries).map {
            SIMD3<Double>($0.x / $0.y, 1, (1 - $0.x - $0.y) / $0.y)
        }
        let unscaled = simd_double3x3(columns: (columns[0], columns[1], columns[2]))
        let white = SIMD3<Double>(d65.x / d65.y, 1, (1 - d65.x - d65.y) / d65.y)
        let scale = unscaled.inverse * white
        return simd_double3x3(
            columns: (columns[0] * scale.x, columns[1] * scale.y, columns[2] * scale.z))
    }

    /// Linear `primaries` RGB → linear BT.709 RGB, derived (never copied)
    /// from the chromaticities and D65; exactly the identity for BT.709.
    static func toBT709(from primaries: InputPrimaries) -> simd_float3x3 {
        guard primaries != .bt709 else { return matrix_identity_float3x3 }
        let m = rgbToXYZ(.bt709).inverse * rgbToXYZ(primaries)
        let rows = (0..<3).map { r in SIMD3<Float>((0..<3).map { c in Float(m[c][r]) }) }
        return simd_float3x3(rows: rows)
    }
}
