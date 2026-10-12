import CoreMedia
import CoreVideo
import simd

/// The primaries a converted source is read in: the gamut step 0's matrix
/// takes to BT.709 (spec §11 GR-15).
enum InputPrimaries: Equatable {
    case bt709, bt2020, p3D65
}

/// Step 0's conversion of one source (spec §11 GR-15), chosen from its
/// buffer's colour labels: HLG or PQ to SDR Rec. 709, a wide-gamut SDR
/// source's matrix to BT.709, or an sRGB-transfer source's sRGB arm. nil —
/// the identity — for every other source, which is then sampled exactly as
/// before T3-1 (no pass, its own texture).
enum InputConversion: Equatable {
    case hlg(InputPrimaries), pq(InputPrimaries), sdrWide(InputPrimaries), srgb(InputPrimaries)

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

/// Every number step 0 uses that Reelcut CHOSE or DERIVED (spec §11 GR-15,
/// T3-1's append); the shader holds only the standards' own constants (the
/// BT.2100 HLG inverse OETF's a, b, c, SMPTE ST 2084's m1, m2, c1–c3, the
/// BT.2020 and BT.709 luminance weights) and the formulas' shapes.
enum InputConversions {
    /// HLG's system gamma and gain: Reelcut's anchor to Apple's measured
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

    /// Published chromaticities (x, y) of red, green and blue: ITU-R BT.709,
    /// ITU-R BT.2020, and P3 D65 (SMPTE EG 432-1); every white is D65.
    private static func chromaticities(_ primaries: InputPrimaries) -> [SIMD2<Double>] {
        switch primaries {
        case .bt709: return [[0.640, 0.330], [0.300, 0.600], [0.150, 0.060]]
        case .bt2020: return [[0.708, 0.292], [0.170, 0.797], [0.131, 0.046]]
        case .p3D65: return [[0.680, 0.320], [0.265, 0.690], [0.150, 0.060]]
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
