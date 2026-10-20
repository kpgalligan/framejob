import AVFoundation

/// View ▸ Preview Quality's composition copy. A pure move out of `Playback.swift`, which sat at the
/// 600-line cap (issue batch B21); `setPreviewQuality` stays there because it reads `player`.
extension Playback {
    /// The composition to hand the player: the one the plan built at Full, and
    /// otherwise the builder's configuration with a smaller `renderSize` (#91).
    ///
    /// **The copy is the whole design.** `CompositionBuilder.build` is shared
    /// by the preview, both export passes and the offline one-frame render, so
    /// scaling there — even behind an argument — would put the export within
    /// one wrong parameter of the preview's setting. Copying here means the
    /// export path never sees a scaled composition at all;
    /// `ExportWriter.videoComposition(_:settings:)` does exactly this to
    /// `frameDuration` for the same reason.
    ///
    /// It reads the size off the BUILT configuration every time rather than
    /// remembering one, so it is idempotent: two quality changes in a row both
    /// scale the pristine canvas size and never a size already scaled.
    ///
    /// The configuration carries the plan's `RecipeInstruction`s through, a
    /// CUSTOM class rather than one of AVFoundation's (`Compositor.swift`), as
    /// the item's own `copy` of `videoComposition` always has. Static, so
    /// `phase8_chrome.py`'s probe calls it rather than a copy of it.
    ///
    /// At Full — and at any quality a coprime canvas degrades to Full — the
    /// guard returns the builder's own object with no new one made at all, so a
    /// preview at the default setting is byte for byte the preview this file
    /// built before the setting existed.
    ///
    /// An HLG plan's copy is also labelled as Show SDR Version asks (spec §11
    /// HD-14 (g)): BT.709 for the SDR version, BT.2020/HLG otherwise; an SDR
    /// plan's colour is never touched.
    static func previewComposition(
        _ built: BuiltComposition, quality: PreviewQuality, sdrVersion: Bool = false
    ) -> AVVideoComposition {
        var configuration = built.videoConfiguration
        let wanted = quality.renderSize(for: configuration.renderSize)
        var changed = wanted != configuration.renderSize
        configuration.renderSize = wanted
        if built.output == .hlg {
            let colour = OutputTransform.compositionColour(
                hlg: true, converts: true, range: sdrVersion ? .sdr : .hlg)
            changed = changed || colour.primaries != configuration.colorPrimaries
                || colour.transfer != configuration.colorTransferFunction
                || colour.matrix != configuration.colorYCbCrMatrix
            configuration.colorPrimaries = colour.primaries
            configuration.colorTransferFunction = colour.transfer
            configuration.colorYCbCrMatrix = colour.matrix
        }
        guard changed else { return built.videoComposition }
        return AVVideoComposition(configuration: configuration)
    }
}
