import Foundation

/// A project's dynamic range (format version 23, spec §11 HD-2, HD-13),
/// mirroring `core/src/model.rs`'s `CanvasOutput`: `sdr` composes in
/// Rec. 709, as every project before format 23 did; `hlg` composes every
/// frame in HLG-encoded BT.2020 — step 0's HLG arms, every SDR source and
/// drawn layer lifted by HD-3's lift, the grade's BT.2020 constants, frames
/// labelled BT.2100 HLG and the 10-bit exports tagged HLG.
///
/// Read from `canvas.output` (the snapshot), the recipe's `canvas.output`
/// (what the compositor draws in) and the plan's `output` (what the
/// composition is built in); absent everywhere it is SDR.
enum CanvasOutput: String, Codable, CaseIterable {
    case sdr
    case hlg

    /// The Document tab's Colour summary row (HD-13 (k)).
    var colourName: String {
        switch self {
        case .sdr: return "SDR — Rec. 709"
        case .hlg: return "HDR — Rec. 2100 HLG"
        }
    }

    /// The Canvas section's Dynamic Range popup item (HD-13 (k)).
    var menuName: String {
        switch self {
        case .sdr: return "SDR"
        case .hlg: return "HDR (HLG)"
        }
    }
}

/// How a project's layers blend (format version 24, spec §11 GR-18, HD-16),
/// mirroring `core/src/model_canvas.rs`'s `CanvasBlending`: `encoded`, as
/// every project before format 24 blends (GR-3); `linear`, every layer
/// decoded to the project's own transfer as scene light after its grade,
/// blended there and encoded once by the output pass. Read from
/// `canvas.blending` (the snapshot) and the recipe's `canvas.blending`;
/// absent everywhere it is encoded.
enum CanvasBlending: String, Codable, CaseIterable {
    case encoded
    case linear

    /// The Canvas section's Blending popup item (HD-16 (g)).
    var menuName: String {
        switch self {
        case .encoded: return "Encoded"
        case .linear: return "Linear light"
        }
    }
}

extension RecipeCanvas {
    /// `rgb`, an encoded colour Frame Job clears or draws with (the
    /// background, a shadow's colour, each already lifted in an HLG
    /// project), as a linear canvas's destination holds it (spec §11 HD-16
    /// (d)): unchanged when encoded; else per channel, clamped to 0…1, the
    /// IEC 61966-2-1 EOTF in an SDR project and HLG's inverse OETF
    /// (BT.2100) in an HLG one — the shader's `blendDecode`.
    func blended(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        guard blending == .linear else { return rgb }
        let hlg = output == .hlg
        func decode(_ value: Float) -> Float {
            let c = min(max(value, 0), 1)
            if hlg { return InputConversions.hlgInverseOETF(c) }
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return SIMD3<Float>(decode(rgb.x), decode(rgb.y), decode(rgb.z))
    }
}
