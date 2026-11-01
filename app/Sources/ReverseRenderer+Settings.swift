import AVFoundation
import VideoToolbox

extension ReverseRenderer {
    // MARK: - Settings

    /// The coded frame size, read from one decoded frame at the head of the
    /// file. Nil means "no picture", which an audio-only source really has and
    /// an unreadable video track amounts to.
    static func dimensions(
        of asset: AVURLAsset, track: AVAssetTrack, limit: CMTime
    ) -> CMVideoDimensions? {
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTimeMinimum(limit, CompositionBuilder.time(ReelTime.perSecond)))
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer(),
            let format = CMSampleBufferGetFormatDescription(sample)
        else { return nil }
        return CMVideoFormatDescriptionGetDimensions(format)
    }

    /// The encoder settings for the picture.
    ///
    /// **The size is the source's, exactly.** Not rounded to even, not scaled:
    /// the compositor maps the model's `source_size` across whatever texture
    /// arrives, so a reversed asset that is one pixel narrower than the
    /// forward one would stretch the clip the moment it is reversed.
    ///
    /// **10 bits at every size (spec §11 PR-7).** HEVC pinned to Main 10 —
    /// `ExporterWriter`'s `hevc_10bit` pin — fed the `x420` frames the reader
    /// decoded, at HEVC's rate: generous because this is an intermediate, its
    /// pixels encoded again on the way to the export, where a stingy one is a
    /// generation of loss the user did not ask for. An odd size is ProRes 422
    /// (`Intermediate`), which takes no compression dictionary.
    ///
    /// **No colour properties.** Given none, the writer labels the file by the
    /// frames' own attachments, which `copyBuffer` carries, so an HLG or a
    /// BT.2020 source is labelled as itself. Forcing BT.709 here mislabelled
    /// those sources, and with the attachments kept it would convert them.
    static func videoSettings(
        _ dimensions: CMVideoDimensions, fps: Fps, intermediate: Intermediate
    ) -> [String: Any] {
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        guard intermediate == .hevcMain10 else {
            return [
                AVVideoCodecKey: AVVideoCodecType.proRes422,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        }
        let rate = fps.double > 0 ? fps.double : 30
        let bits = Int(
            min(max(Double(max(1, width * height)) * rate * 0.12, 2_000_000), 240_000_000))
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bits,
            // A keyframe at least every two seconds, for the same reason the
            // export sets one: this file is scrubbed and seeked into on every
            // preview frame.
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            AVVideoExpectedSourceFrameRateKey: Int(rate.rounded()),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
        ]
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    /// How much of the source one slice covers: as many frames as the budget
    /// holds at the held format's bytes a pixel (`Intermediate`), turned back
    /// into time. An audio-only file has no frames to hold, so it takes long
    /// slices and pays for very few readers.
    static func sliceDuration(dimensions: CMVideoDimensions?, fps: Fps) -> CMTime {
        let rate = fps.double > 0 ? fps.double : 30
        guard let dimensions = dimensions, dimensions.width > 0, dimensions.height > 0 else {
            return CompositionBuilder.time(ReelTime.perSecond * 30)
        }
        let bytes =
            Int(dimensions.width) * Int(dimensions.height)
            * Intermediate(dimensions).bytesPerPixel
        let frames = min(max(bufferBudget / max(1, bytes), 4), 300)
        let ticks = Ticks((Double(frames) / rate * Double(ReelTime.perSecond)).rounded())
        return CompositionBuilder.time(max(ticks, 1))
    }
}
