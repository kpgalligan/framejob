import CoreMedia
import CoreVideo

extension MediaImporter {
    private static let appleLogLabel = kCMFormatDescriptionLogTransferFunction_AppleLog as String
    private static let appleLog2Label = kCVImageBufferLogTransferFunction_AppleLog2 as String

    /// The Camera Log a video track's label names (spec §11 GR-16), read
    /// when `probeAsset` runs: Apple Log (`com.apple.rec2020.apple-log`,
    /// `kCMFormatDescriptionLogTransferFunction_AppleLog`) with BT.2020, or
    /// Apple Log 2 (`kCVImageBufferLogTransferFunction_AppleLog2`, whose file
    /// carries the same extension key) with Apple Wide Gamut, each
    /// `detected`; nil for any other label or none. S-Log3 and V-Log carry no
    /// label AVFoundation reads, so they are chosen by hand.
    static func detectedColor(_ descriptions: [CMFormatDescription]) -> MediaColor? {
        for description in descriptions {
            let label = CMFormatDescriptionGetExtension(
                description, extensionKey: kCMFormatDescriptionExtension_LogTransferFunction)
                as? String
            if label == Self.appleLogLabel {
                return MediaColor(log: .appleLog, gamut: .bt2020, detected: true)
            }
            if label == Self.appleLog2Label {
                return MediaColor(log: .appleLog2, gamut: .appleWideGamut, detected: true)
            }
        }
        return nil
    }
}
