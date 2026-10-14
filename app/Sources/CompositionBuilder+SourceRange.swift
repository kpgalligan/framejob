import AVFoundation

/// A log media's range flag, read once per build and carried per instruction,
/// per track, as orientation is (spec §11 GR-22).
///
/// Step 0 reads S-Log3 and V-Log in their code domain: AVFoundation decodes a
/// video-range file to s = (CV − 64)/876, so their signal is 876/1023·s +
/// 64/1023, and a full-range one to s = CV/1023, so their signal is s itself.
/// The compositor sees a decoded frame and never the file, so the flag is read
/// here, from the media's FORWARD video track — a reversed clip's intermediate
/// is written in video range from codes the decoder already rescaled, and
/// follows its media (GR-16's convention). Only media a video segment converts
/// with a log curve are read, so a composition with none reads nothing and
/// every instruction's set is empty.
extension CompositionBuilder {

    /// The media of `plan`'s log-converting video segments whose forward video
    /// track is flagged full range. Each is read once, through `sourceTrack`.
    static func fullRangeMedia(
        plan: CompositionPlan, urls: [UInt32: URL], assets: inout [UInt32: AVURLAsset]
    ) -> Set<UInt32> {
        var read = Set<UInt32>()
        var full = Set<UInt32>()
        for planTrack in plan.videoTracks {
            for segment in planTrack.segments where segment.input?.log != nil {
                guard read.insert(segment.media).inserted,
                    let track = sourceTrack(
                        for: segment.media, mediaType: .video, urls: urls, assets: &assets),
                    isFullRange(track)
                else { continue }
                full.insert(segment.media)
            }
        }
        return full
    }

    /// The composition tracks an instruction needs whose segment across it is
    /// one of `media`, chosen as `trackOrientations` chooses the segment: an
    /// instruction boundary falls wherever the visible clips change (§7.2), so
    /// a track shows exactly one segment inside one instruction.
    static func fullRangeTracks(
        plan: CompositionPlan, instruction: PlanInstruction, media: Set<UInt32>
    ) -> Set<Int> {
        guard !media.isEmpty else { return [] }
        var result = Set<Int>()
        for trackID in instruction.requiredTrackIDs {
            guard let planTrack = plan.videoTracks.first(where: { $0.id == trackID }),
                let segment = planTrack.segments.first(where: {
                    instruction.start >= $0.start && instruction.start < $0.start + $0.duration
                }),
                media.contains(segment.media)
            else { continue }
            result.insert(trackID)
        }
        return result
    }

    /// Whether `track`'s first format description carries
    /// `kCMFormatDescriptionExtension_FullRangeVideo` true; absent or false is
    /// video range. Read by KEY, for `oneFrame`'s reason.
    static func isFullRange(_ track: AVAssetTrack) -> Bool {
        guard let description = (keyed(track, "formatDescriptions") as? [CMFormatDescription])?
            .first
        else { return false }
        return CMFormatDescriptionGetExtension(
            description, extensionKey: kCMFormatDescriptionExtension_FullRangeVideo) as? Bool
            == true
    }
}
