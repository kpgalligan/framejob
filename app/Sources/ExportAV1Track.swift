import AVFoundation

/// The `av1` row's track in the MP4 (spec §11 CX-12 (4), CX-14): the `av01` format
/// description holding the core's `av1C` record and the picture's video-range colour tags
/// (the `colr` box), with HDR10's `mdcv` and `clli` on PQ, one sample per SVT-AV1 packet,
/// and the written file's `ftyp` branded `av01` (AV1-ISOBMFF §2.1), which `AVAssetWriter`
/// leaves out.
enum ExportAV1Track {
    /// `av01` at `width` × `height` with `config`'s record and `picture`'s extensions: its
    /// colour tags, and on PQ its mastering display and content light level.
    static func formatDescription(
        width: Int, height: Int, config: ReelAV1.Config, picture: ExportAV1Picture
    ) throws -> CMVideoFormatDescription {
        var extensions: [String: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String: [
                "av1C": config.record
            ]
        ]
        extensions.merge(picture.formatExtensions) { _, picture in picture }
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_AV1,
            width: Int32(clamping: width), height: Int32(clamping: height),
            extensions: extensions as CFDictionary, formatDescriptionOut: &description)
        guard status == noErr, let description else {
            throw Exporter.ExportError.failed(
                "The AV1 track could not be described (status \(status)).")
        }
        return description
    }

    /// One packet as one sample: presented at `at` for `duration`, no decode stamp (AV1
    /// presents its temporal units in order). No sync attachment: the passthrough writer
    /// marks the track's sync samples from the bitstream's own key frames (CX-12 (3)).
    static func sample(
        _ data: Data, at time: CMTime, duration: CMTime, format: CMVideoFormatDescription
    ) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block) == kCMBlockBufferNoErr, let block
        else { return nil }
        let copied = data.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(
            duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var size = data.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
            let sample
        else { return nil }
        return sample
    }

    /// Rewrites the finished file's `ftyp` to carry `av01`, in place (the core's
    /// `rc_av1_ftyp_brand`: the first `mp41` becomes `av01`, no size or offset moves).
    /// Throws when the file's first box cannot take it, which fails the export (CX-12 (4)).
    static func brandFile(_ url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        var head = try handle.read(upToCount: 4096) ?? Data()
        switch ReelAV1.brandAV01(&head) {
        case 1:
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: head)
        case 0:
            return
        default:
            throw Exporter.ExportError.failed(
                "The AV1 file's ftyp box could not be made to carry the av01 brand.")
        }
    }
}
