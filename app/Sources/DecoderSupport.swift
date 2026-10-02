import AVFoundation
import CoreMedia
import VideoToolbox

/// What this Mac can decode, asked of the decoders themselves (spec §11
/// #216). macOS ships VP9 and AV1 decoders that a process must opt in to,
/// and the opt-in is per process: `enable()` is called at launch, before a
/// cache pass, before a composition looks up a track, and in the harness and
/// the formats probe. An import then decodes one frame of its video track
/// (`decodesFirstFrame`), because `isPlayable` answers yes for files no
/// decoder here reads (VP9 Profile 1, AV1 on an M1/M2), and a refusal names
/// the codec (`refusal`).
///
/// Await-free: `AVAssetReader` is synchronous, as in `writePeaks`; `async`
/// stays in `MediaImporter.swift` (spec §11 W-8).
enum DecoderSupport {

    /// The registration, run once by the first `enable()`. A `static let`'s
    /// initialiser runs exactly once, on whichever thread gets there first.
    private static let registration: Void = {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_AV1)
    }()

    /// Opts this process in to the supplemental VP9 and AV1 decoders.
    /// Idempotent and callable from any thread.
    static func enable() {
        _ = registration
    }

    /// The reader errors that mean "nothing here decodes this": no decoder
    /// (-11833), and a decoder that cannot read this format (-11855, VP9
    /// Profile 1/3). Every other failure — damaged or truncated data in a
    /// codec this Mac decodes (-11821, -11880) — imports as it did before.
    static let refusingErrorCodes: Set<Int> = [
        AVError.Code.decoderNotFound.rawValue, AVError.Code.undecodableMediaData.rawValue,
    ]

    /// Whether `track`'s first frame decodes to 32BGRA. False ONLY when the
    /// reader fails with one of `refusingErrorCodes`; an image buffer, a
    /// track that completes with none, a reader that cannot be made and any
    /// other error all answer true. Reads at most until the first image.
    static func decodesFirstFrame(of track: AVAssetTrack, in asset: AVAsset) -> Bool {
        enable()
        guard let reader = try? AVAssetReader(asset: asset) else { return true }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return true }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else { return !refuses(reader.error) }
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetImageBuffer(sample) != nil { return true }
        }
        // Read the status before the deferred cancel: cancelling first would
        // erase the difference between completion and a decoder failure.
        return reader.status != .failed || !refuses(reader.error)
    }

    /// Whether a reader's error is one of the codes that refuse an import.
    private static func refuses(_ error: (any Error)?) -> Bool {
        guard let error = error as NSError?, error.domain == AVFoundationErrorDomain else {
            return false
        }
        let code = error.code
        return Self.refusingErrorCodes.contains(code)
    }

    /// The `profile` byte of a VP9 description's `vpcC` record: byte 4,
    /// after the version byte and three flag bytes. Nil when absent or short.
    static func vp9Profile(of description: CMFormatDescription) -> Int? {
        guard let atoms = CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            as? [String: Any],
            let record = atoms["vpcC"] as? Data, record.count > 4
        else { return nil }
        return Int(record[record.startIndex + 4])
    }

    /// 'vp08'. CoreMedia names no constant for VP8.
    private static let vp8: FourCharCode = 0x7670_3038

    /// The refusal sentence for a video track that will not decode.
    static func refusal(
        fileName: String, codec: FourCharCode, vp9Profile: Int?, av1Hardware: Bool
    ) -> String {
        switch codec {
        case kCMVideoCodecType_AV1 where !av1Hardware:
            return "\(fileName) is AV1 video, which needs an M3 or later Mac."
        case kCMVideoCodecType_AV1:
            return "\(fileName) is AV1 video, which this Mac cannot decode."
        case kCMVideoCodecType_VP9:
            if let profile = vp9Profile, profile == 1 || profile == 3 {
                return "\(fileName) is VP9 Profile \(profile) video, which this Mac cannot decode;"
                    + " VP9 Profiles 0 and 2 import."
            }
            return "\(fileName) is VP9 video, which this Mac cannot decode."
        case vp8:
            return "\(fileName) is VP8 video, which this Mac cannot decode."
        case 0:
            return "\(fileName) is video this Mac cannot decode."
        default:
            let code = String([24, 16, 8, 0].map {
                Character(Unicode.Scalar(UInt8((codec >> UInt32($0)) & 0xFF)))
            })
            return "\(fileName) is '\(code)' video, which this Mac cannot decode."
        }
    }

    /// The sentence for a track with these descriptions: the first one's
    /// codec and VP9 profile, and whether this Mac decodes AV1 in hardware.
    static func refusal(fileName: String, descriptions: [CMFormatDescription]) -> String {
        let first = descriptions.first
        return refusal(
            fileName: fileName, codec: first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0,
            vp9Profile: first.flatMap { vp9Profile(of: $0) },
            av1Hardware: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
    }
}
