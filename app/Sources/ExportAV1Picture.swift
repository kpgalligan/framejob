import CoreMedia

/// The picture the `av1` row writes (spec §11 CX-14): the SDR version or BT.709 (`sdr`), the
/// HLG master (`hlg`) or HDR10 (`pq`), read from the settings' `color` — which the core writes
/// only in an HLG project, so an SDR project is `.sdr`.
///
/// One value carries everything the three places that label the picture need, so they cannot
/// disagree: the luma weights `ExportI010.metal` converts with (CX-14 (3)), the CICP SVT-AV1
/// writes into the sequence header and the `colr` the `av01` entry carries (CX-14 (4)), and on
/// PQ alone HD-5's fixed HDR10 metadata, both as SVT's metadata OBUs and as the entry's
/// `mdcv`/`clli` (CX-14 (5)).
enum ExportAV1Picture: Equatable {
    case sdr, hlg, pq

    /// `hlg` and `pq` as named; anything else, absent included, is `.sdr`.
    init(color: String?) {
        switch color {
        case "hlg": self = .hlg
        case "pq": self = .pq
        default: self = .sdr
        }
    }

    /// The sequence header's `color_primaries`: BT.709, or BT.2020 for an HDR picture.
    var primaries: EbColorPrimaries {
        self == .sdr ? EB_CICP_CP_BT_709 : EB_CICP_CP_BT_2020
    }

    /// The sequence header's `transfer_characteristics`.
    var transfer: EbTransferCharacteristics {
        switch self {
        case .sdr: return EB_CICP_TC_BT_709
        case .hlg: return EB_CICP_TC_HLG
        case .pq: return EB_CICP_TC_SMPTE_2084
        }
    }

    /// The sequence header's `matrix_coefficients`: BT.709, or BT.2020 non-constant luminance.
    var matrix: EbMatrixCoefficients {
        self == .sdr ? EB_CICP_MC_BT_709 : EB_CICP_MC_BT_2020_NCL
    }

    /// The matrix's (Kr, Kb), the weights the kernel derives Y′, Cb′ and Cr′ from.
    var lumaWeights: (kr: Float, kb: Float) {
        self == .sdr ? (0.2126, 0.0722) : (0.2627, 0.0593)
    }

    /// The format description's colour extensions — the `colr` box, video range — and on PQ
    /// HD-5's mastering display and content light level (`OutputTransform`'s blobs, the `mdcv`
    /// and `clli` boxes).
    var formatExtensions: [String: Any] {
        var out: [String: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries as String: self == .sdr
                ? kCMFormatDescriptionColorPrimaries_ITU_R_709_2
                : kCMFormatDescriptionColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_YCbCrMatrix as String: self == .sdr
                ? kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
                : kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
            kCMFormatDescriptionExtension_FullRangeVideo as String: false,
        ]
        switch self {
        case .sdr:
            out[kCMFormatDescriptionExtension_TransferFunction as String] =
                kCMFormatDescriptionTransferFunction_ITU_R_709_2
        case .hlg:
            out[kCMFormatDescriptionExtension_TransferFunction as String] =
                kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        case .pq:
            out[kCMFormatDescriptionExtension_TransferFunction as String] =
                kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        }
        if carriesHDR10 {
            out[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] =
                OutputTransform.masteringDisplay
            out[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] =
                OutputTransform.contentLightLevel
        }
        return out
    }

    /// Whether HD-5's HDR10 metadata is written: on PQ alone.
    var carriesHDR10: Bool {
        self == .pq
    }

    /// `OutputTransform.masteringDisplay` in the form `svt_aom_parse_mastering_display` reads:
    /// P3's green, blue and red primaries and D65 as x, y, then the maximum and minimum
    /// luminance in cd/m².
    static let masteringDisplay =
        "G(0.265,0.690)B(0.150,0.060)R(0.680,0.320)WP(0.3127,0.3290)L(1000,0.005)"

    /// `OutputTransform.contentLightLevel` in the form `svt_aom_parse_content_light_level`
    /// reads: MaxCLL, MaxFALL.
    static let contentLightLevel = "1000,0"
}
