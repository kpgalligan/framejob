import AVFoundation

/// `ExportWriter`'s sample re-timing, moved whole out of `ExporterWriter.swift` (codec-export
/// C1's toll T3, a pure move; `private` became internal so the writer's pump still reaches it).
extension ExportWriter {
    /// The same sample, `delta` earlier. Every timing entry moves, decode
    /// stamps included, so a codec that reorders frames stays coherent.
    static func retimed(_ sample: CMSampleBuffer, by delta: CMTime) -> CMSampleBuffer? {
        guard delta.isNumeric, delta != .zero else { return sample }
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr,
            count > 0
        else { return nil }
        var timings = [CMSampleTimingInfo](
            repeating: CMSampleTimingInfo(
                duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: Int(count))
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: nil) == noErr
        else { return nil }
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isNumeric {
                timings[index].presentationTimeStamp =
                    timings[index].presentationTimeStamp - delta
            }
            if timings[index].decodeTimeStamp.isNumeric {
                timings[index].decodeTimeStamp = timings[index].decodeTimeStamp - delta
            }
        }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: count,
            sampleTimingArray: &timings, sampleBufferOut: &copy) == noErr
        else { return nil }
        return copy
    }
}
