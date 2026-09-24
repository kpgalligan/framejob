import AVFoundation

/// The audio half of `CompositionBuilder.build`: the composition audio tracks
/// a plan's audio tracks become, with their mix parameters and meters.
extension CompositionBuilder {

    /// One placeholder video track id, one past the plan's audio numbering —
    /// `addPlaceholderIfNeeded`'s own expression, named so the audio tracks
    /// can number past it.
    static func placeholderTrackID(_ plan: CompositionPlan) -> Int {
        (plan.audioTracks.map(\.id).max() ?? 0) + 1
    }

    /// The asset track one segment reads from: the reversed copy when it is
    /// ready, nil while it is pending, else the media's own track.
    static func resolveSource(
        for segment: PlanSegment, mediaType: AVMediaType, urls: [UInt32: URL],
        reverse: ReverseResolution, assets: inout [UInt32: AVURLAsset],
        reversedAssets: inout [UInt32: AVURLAsset]
    ) -> AVAssetTrack? {
        if let reversed = reverse.ready[segment.clip] {
            return assetTrack(
                at: reversed, key: segment.media, mediaType: mediaType,
                assets: &reversedAssets)
        } else if reverse.pending.contains(segment.clip) {
            return nil
        } else {
            return sourceTrack(
                for: segment.media, mediaType: mediaType, urls: urls, assets: &assets)
        }
    }

    /// Every plan audio track as composition audio tracks, with one
    /// input-parameter block per composition track and, on a metering build,
    /// one meter per composition track.
    static func addAudioTracks(
        to composition: AVMutableComposition, plan: CompositionPlan, urls: [UInt32: URL],
        reverse: ReverseResolution, dsp: AudioDSPParameters, metering: Bool,
        assets: inout [UInt32: AVURLAsset], reversedAssets: inout [UInt32: AVURLAsset]
    ) throws -> (inputParameters: [AVAudioMixInputParameters], meters: [LevelMeterTrack]) {
        var inputParameters: [AVAudioMixInputParameters] = []
        var meters: [LevelMeterTrack] = []
        for planTrack in plan.audioTracks {
            let track = try makeTrack(in: composition, mediaType: .audio, id: planTrack.id)
            try fill(
                track, segments: planTrack.segments, mediaType: .audio, urls: urls,
                reverse: reverse, assets: &assets, reversedAssets: &reversedAssets)
            let sink = metering ? LevelMeterSink() : nil
            if let sink = sink {
                meters.append(
                    LevelMeterTrack(id: planTrack.id, ramps: planTrack.ramps, sink: sink))
            }
            inputParameters.append(
                audioParameters(
                    for: track, segments: planTrack.segments, ramps: planTrack.ramps,
                    dsp: dsp.isEmpty
                        ? nil : AudioTrackDSP(segments: planTrack.segments, parameters: dsp),
                    meter: sink))
        }
        return (inputParameters, meters)
    }
}
