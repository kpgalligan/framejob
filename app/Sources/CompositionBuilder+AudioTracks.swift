import AVFoundation

/// The audio half of `CompositionBuilder.build`: the composition audio tracks
/// a plan's audio tracks become, with their mix parameters and meters.
extension CompositionBuilder {

    /// What a source's audio IS, as far as a composition track's decoder is
    /// concerned: the stream description's format, rate, channels, flags and
    /// bit depth. Two sources with equal signatures may share one composition
    /// track; two with different ones may not (spec §11 R2-1).
    struct AudioFormatSignature: Hashable {
        let formatID: AudioFormatID
        let sampleRate: Double
        let channels: UInt32
        let formatFlags: AudioFormatFlags
        let bitsPerChannel: UInt32
    }

    /// The segments of one plan audio track that read one source format, and
    /// the composition track id they go on. Family 0 keeps the plan's id; a
    /// nil signature is a segment with no readable source (empty time).
    struct AudioFamily {
        let id: Int
        var signature: AudioFormatSignature?
        var segments: [PlanSegment]
    }

    /// The first audio format description on `track`, read by KEY for
    /// `oneFrame`'s reason — the named getter is a deprecation warning and
    /// `load(.formatDescriptions)` is `async`. Nil for a track with none.
    static func audioFormatSignature(of track: AVAssetTrack) -> AudioFormatSignature? {
        guard let descriptions = keyed(track, "formatDescriptions") as? [CMFormatDescription],
            let audio = descriptions.first(where: {
                CMFormatDescriptionGetMediaType($0) == kCMMediaType_Audio
            }),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audio)?.pointee
        else { return nil }
        return AudioFormatSignature(
            formatID: asbd.mFormatID, sampleRate: asbd.mSampleRate,
            channels: asbd.mChannelsPerFrame, formatFlags: asbd.mFormatFlags,
            bitsPerChannel: asbd.mBitsPerChannel)
    }

    /// One placeholder video track id, one past the plan's audio numbering —
    /// `addPlaceholderIfNeeded`'s own expression, named so the audio tracks
    /// can number past it.
    static func placeholderTrackID(_ plan: CompositionPlan) -> Int {
        (plan.audioTracks.map(\.id).max() ?? 0) + 1
    }

    /// The first id an extra audio family may take: past the placeholder and
    /// every plan id, video and audio, so no composition track id collides.
    static func firstExtraTrackID(_ plan: CompositionPlan) -> Int {
        let planIDs = plan.videoTracks.map(\.id) + plan.audioTracks.map(\.id)
        return max(placeholderTrackID(plan), planIDs.max() ?? 0) + 1
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

    /// One plan audio track split by source format, in segment order.
    ///
    /// **Why:** an `AVPlayerItem` whose tapped audio track changes format
    /// part-way — an AAC clip then a WAV — stalls (measured, kpgalligan/
    /// reelcut#34), and `AVComposition.h` promises nothing more; the same
    /// segments on two tracks play. A segment with no source (missing,
    /// pending reverse) joins family 0, which adopts the first real format
    /// it meets; a same-format track answers one family with the plan's id
    /// and all its segments, exactly the track it was before. Extra families
    /// take `nextID`, shared across every plan track.
    static func audioFamilies(
        of planTrack: PlanTrack, nextID: inout Int, urls: [UInt32: URL],
        reverse: ReverseResolution, assets: inout [UInt32: AVURLAsset],
        reversedAssets: inout [UInt32: AVURLAsset]
    ) -> [AudioFamily] {
        var families: [AudioFamily] = []
        for segment in planTrack.segments {
            // A zero-length segment is one `fill` skips, so it names no family.
            let key = segment.duration > 0
                ? resolveSource(
                    for: segment, mediaType: .audio, urls: urls, reverse: reverse,
                    assets: &assets, reversedAssets: &reversedAssets
                ).flatMap(audioFormatSignature(of:))
                : nil
            guard let key = key else {
                if families.isEmpty {
                    families.append(AudioFamily(id: planTrack.id, signature: nil, segments: []))
                }
                families[0].segments.append(segment)
                continue
            }
            if let index = families.firstIndex(where: { $0.signature == key }) {
                families[index].segments.append(segment)
            } else if let first = families.first, first.signature == nil {
                families[0].signature = key
                families[0].segments.append(segment)
            } else if families.isEmpty {
                families.append(AudioFamily(id: planTrack.id, signature: key, segments: [segment]))
            } else {
                families.append(AudioFamily(id: nextID, signature: key, segments: [segment]))
                nextID += 1
            }
        }
        if families.isEmpty {
            families.append(AudioFamily(id: planTrack.id, signature: nil, segments: []))
        }
        return families
    }

    /// Every plan audio track as composition audio tracks, with one
    /// input-parameter block per composition track and, on a metering build,
    /// one meter per composition track. A family's members never sound at the
    /// same instant, so `Playback.meterReading`'s sum over meters is right.
    static func addAudioTracks(
        to composition: AVMutableComposition, plan: CompositionPlan, urls: [UInt32: URL],
        reverse: ReverseResolution, dsp: AudioDSPParameters, metering: Bool,
        assets: inout [UInt32: AVURLAsset], reversedAssets: inout [UInt32: AVURLAsset]
    ) throws -> (inputParameters: [AVAudioMixInputParameters], meters: [LevelMeterTrack]) {
        var inputParameters: [AVAudioMixInputParameters] = []
        var meters: [LevelMeterTrack] = []
        var nextID = firstExtraTrackID(plan)
        for planTrack in plan.audioTracks {
            let families = audioFamilies(
                of: planTrack, nextID: &nextID, urls: urls, reverse: reverse,
                assets: &assets, reversedAssets: &reversedAssets)
            for family in families {
                let track = try makeTrack(in: composition, mediaType: .audio, id: family.id)
                try fill(
                    track, segments: family.segments, mediaType: .audio, urls: urls,
                    reverse: reverse, assets: &assets, reversedAssets: &reversedAssets)
                let sink = metering ? LevelMeterSink() : nil
                if let sink = sink {
                    meters.append(
                        LevelMeterTrack(id: family.id, ramps: planTrack.ramps, sink: sink))
                }
                inputParameters.append(
                    audioParameters(
                        for: track, segments: family.segments, ramps: planTrack.ramps,
                        dsp: dsp.isEmpty
                            ? nil : AudioTrackDSP(segments: family.segments, parameters: dsp),
                        meter: sink))
            }
        }
        return (inputParameters, meters)
    }
}
