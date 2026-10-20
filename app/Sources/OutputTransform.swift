import AVFoundation

/// The picture an HLG project is drawn as (spec §11 HD-5, HD-14), mirroring
/// `core/src/dynamic_range.rs`'s `DynamicRange`: `hlg`, the working space
/// itself; `pq`, HDR10; `sdr`, the SDR version (HD-4). The export settings'
/// `color`, the recipe option `dynamic_range` and the recipe canvas's
/// `dynamic_range` all spell it so.
enum DynamicRange: String, Codable, CaseIterable {
    case hlg
    case pq
    case sdr

    /// The export sheet's Dynamic Range popup item (HD-14 (h)).
    var menuName: String {
        switch self {
        case .hlg: return "HDR (HLG)"
        case .pq: return "HDR10 (PQ)"
        case .sdr: return "SDR version"
        }
    }
}

/// A composition's colour, the three `AVVideoComposition` keys; nil each for
/// a composition that names none (an SDR project that does not convert).
struct VideoColour: Equatable {
    let primaries: String?
    let transfer: String?
    let matrix: String?
}

/// The output pass's uniform block (`framejob_output_fragment`'s
/// `OutputUniforms`, sixteen bytes): `mode` 1 draws the SDR version, 2 PQ;
/// `linearLight` 1 when the destination holds linear light (spec §11 HD-16
/// (f)), with `hlgOutput` 1 when that light is HLG's scene light — mode 0
/// then encodes it by the project's own transfer.
struct OutputUniforms {
    var mode: Float
    var knee: Float
    var linearLight: Float = 0
    var hlgOutput: Float = 0
}

/// The one final pass an HLG project's picture takes on its way out (spec
/// §11 HD-14 (b)), and the colour a composition is labelled with to carry it:
/// chosen by the recipe options of the key being drawn, so the preview's Show
/// SDR Version, `render_frame {sdr_version}`, a JPEG frame and an export's
/// SDR version or PQ share one path. `hlg` and every SDR project draw no
/// pass, so their pixels are the ones they were.
enum OutputTransform {
    /// The SDR version's knee (HD-14 (a)): on the largest linear BT.709
    /// channel over reference white, GR-15's shoulder above it to 1000/203.
    static let sdrKnee: Float = 0.9

    /// The composition's colour (HD-14 (b)): an SDR project's as it always
    /// was (BT.709 when it converts, none when it does not); an HLG project's
    /// BT.2020/HLG, BT.2020/PQ for `pq`, BT.709 for its SDR version.
    static func compositionColour(hlg: Bool, converts: Bool, range: DynamicRange?) -> VideoColour {
        guard hlg else {
            return converts
                ? VideoColour(
                    primaries: AVVideoColorPrimaries_ITU_R_709_2,
                    transfer: AVVideoTransferFunction_ITU_R_709_2,
                    matrix: AVVideoYCbCrMatrix_ITU_R_709_2)
                : VideoColour(primaries: nil, transfer: nil, matrix: nil)
        }
        switch range {
        case .sdr:
            return VideoColour(
                primaries: AVVideoColorPrimaries_ITU_R_709_2,
                transfer: AVVideoTransferFunction_ITU_R_709_2,
                matrix: AVVideoYCbCrMatrix_ITU_R_709_2)
        case .pq:
            return VideoColour(
                primaries: AVVideoColorPrimaries_ITU_R_2020,
                transfer: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                matrix: AVVideoYCbCrMatrix_ITU_R_2020)
        case .hlg, nil:
            return VideoColour(
                primaries: AVVideoColorPrimaries_ITU_R_2020,
                transfer: AVVideoTransferFunction_ITU_R_2100_HLG,
                matrix: AVVideoYCbCrMatrix_ITU_R_2020)
        }
    }

    /// The pass's block for `canvas`, or nil when no pass is drawn: an HLG
    /// canvas whose key asked for the SDR version or PQ, and every linear
    /// canvas (spec §11 HD-16 (f)) — mode 0 an SDR project's or an HLG
    /// master's encode, modes 1 and 2 from the linear scene light. An
    /// encoded canvas's answer is what it was before HD-16.
    static func uniforms(for canvas: RecipeCanvas) -> OutputUniforms? {
        guard canvas.blending == .linear else { return encodedUniforms(for: canvas) }
        let hlg: Float = canvas.output == .hlg ? 1 : 0
        var u = encodedUniforms(for: canvas) ?? OutputUniforms(mode: 0, knee: sdrKnee)
        u.linearLight = 1
        u.hlgOutput = hlg
        return u
    }

    /// An encoded canvas's block: only an HLG canvas whose key asked for the
    /// SDR version or PQ.
    private static func encodedUniforms(for canvas: RecipeCanvas) -> OutputUniforms? {
        guard canvas.output == .hlg else { return nil }
        switch canvas.dynamicRange {
        case .sdr: return OutputUniforms(mode: 1, knee: sdrKnee)
        case .pq: return OutputUniforms(mode: 2, knee: sdrKnee)
        case .hlg, nil: return nil
        }
    }

    /// HDR10's mastering display (HD-5, HD-14 (d)), SMPTE ST 2086 in the order
    /// H.265's SEI 137 carries it: P3's green, blue and red primaries and D65
    /// as x, y in 0.00002, then the maximum (1,000 cd/m²) and minimum (0.005
    /// cd/m²) luminance in 0.0001, big-endian.
    static let masteringDisplay = Data([
        0x33, 0xC2, 0x86, 0xC4, 0x1D, 0x4C, 0x0B, 0xB8, 0x84, 0xD0, 0x3E, 0x80,
        0x3D, 0x13, 0x40, 0x42, 0x00, 0x98, 0x96, 0x80, 0x00, 0x00, 0x00, 0x32,
    ])

    /// HDR10's content light level (CTA-861.3): MaxCLL 1,000 cd/m², MaxFALL
    /// 0 ("unknown"), big-endian.
    static let contentLightLevel = Data([0x03, 0xE8, 0x00, 0x00])
}
