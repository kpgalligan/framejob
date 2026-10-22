import AVFoundation
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

    /// A PQ video track's HDR10 peak (spec §11 HD-12, HD-18), read when
    /// `probeAsset` runs: `{pq}` for a track whose description
    /// `InputConversion` reads as PQ — the core's reading of the
    /// description's mastering-display and content-light extensions, else,
    /// for an `av01` track, of its `av1C` record's and first sample's
    /// metadata OBUs, and for an `hvc1` or `hev1` track of the first sample's
    /// SEI (`firstSample`) — `{pq: {}}` when none reads; nil for any track
    /// that is not PQ. Synchronous (spec §11 W-8).
    static func detectedPQ(
        _ descriptions: [CMFormatDescription], track: AVAssetTrack, asset: AVAsset
    ) -> MediaColor? {
        guard let description = descriptions.first(where: {
            if case .pq = InputConversion.choose(for: $0) { return true }
            return false
        }) else { return nil }
        func data(_ key: CFString) -> Data? {
            CMFormatDescriptionGetExtension(description, extensionKey: key) as? Data
        }
        let mastering = data(kCMFormatDescriptionExtension_MasteringDisplayColorVolume)
        let contentLight = data(kCMFormatDescriptionExtension_ContentLightLevelInfo)
        if mastering == nil, contentLight == nil,
            CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_AV1
        {
            let atoms = CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                as? [String: Any]
            let read = ReelHDR10.av1Peak(
                config: atoms?["av1C"] as? Data, sample: firstSample(of: track, in: asset))
            return MediaColor(pq: read)
        }
        var sample: Data?
        var nalLength = 0
        if mastering == nil, contentLight == nil, let length = hevcNALLength(description) {
            nalLength = length
            sample = firstSample(of: track, in: asset)
        }
        let read = ReelHDR10.peak(
            mastering: mastering, contentLight: contentLight, sample: sample, nalLength: nalLength)
        return MediaColor(pq: read)
    }

    /// A PQ still's HDR10 peak (spec §11 HD-20 (b)), read when `probeImage`
    /// runs: `{pq}` for a still whose decoded space is PQ-based
    /// (`StillColor.conversion(at:)` answers `.pq`) — the core's reading of
    /// the file's bytes, a PNG's `cLLI`/`mDCV` or a HEIF or AVIF primary
    /// item's `clli`/`mdcv` — `{pq: {}}` when none reads; nil for any other
    /// still. ImageIO's properties are not read. Synchronous (spec §11 W-8).
    static func detectedStillPQ(_ url: URL) -> MediaColor? {
        guard case .pq = StillColor.conversion(at: url) else { return nil }
        let file = try? Data(contentsOf: url, options: .alwaysMapped)
        return MediaColor(pq: ReelHDR10.stillPeak(file: file))
    }

    /// An HEVC description's NAL length size (its `hvcC`'s), nil for any
    /// other codec or an unreadable record.
    private static func hevcNALLength(_ description: CMFormatDescription) -> Int? {
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        // 'hvc1' and 'hev1' (whose parameter sets may sit in the stream too).
        guard subtype == kCMVideoCodecType_HEVC || subtype == FourCharCode(0x6865_7631)
        else { return nil }
        var length: Int32 = 0
        let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            description, parameterSetIndex: 0, parameterSetPointerOut: nil,
            parameterSetSizeOut: nil, parameterSetCountOut: nil, nalUnitHeaderLengthOut: &length)
        return status == noErr && length > 0 ? Int(length) : nil
    }

    /// The bytes of the track's first sample with data, read unconverted
    /// (`outputSettings: nil`): an x265 track's first buffer holds no sample,
    /// so empty buffers are skipped. The reader is cancelled once it has one.
    private static func firstSample(of track: AVAssetTrack, in asset: AVAsset) -> Data? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        defer { reader.cancelReading() }
        guard reader.startReading() else { return nil }
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }
            var bytes = Data(count: length)
            let status = bytes.withUnsafeMutableBytes { out -> OSStatus in
                guard let base = out.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: length, destination: base)
            }
            return status == noErr ? bytes : nil
        }
        return nil
    }
}
