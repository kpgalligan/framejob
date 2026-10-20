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
