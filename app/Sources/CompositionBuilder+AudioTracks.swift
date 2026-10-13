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
        /// Spans of the segments (duration > 0) whose source resolved —
        /// exactly what `fill` inserts media for, and the only ticks at which
        /// the meter counts this track (`LevelMeterTrack`, #65).
        var sounding: [Range<Ticks>] = []
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
    /// part-way — an AAC clip then a WAV — stalls (measured,
    /// kpgalligan/reelcut#34), and `AVComposition.h` promises nothing more; the same
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
            // The source first, then its signature: a resolved source is what
            // `fill` inserts media for, and so what the meter counts (#65).
            let source = segment.duration > 0
                ? resolveSource(
                    for: segment, mediaType: .audio, urls: urls, reverse: reverse,
                    assets: &assets, reversedAssets: &reversedAssets)
                : nil
            let span = segment.start..<(segment.start + max(0, segment.duration))
            guard let key = source.flatMap(audioFormatSignature(of:)) else {
                if families.isEmpty {
                    families.append(AudioFamily(id: planTrack.id, signature: nil, segments: []))
                }
                families[0].segments.append(segment)
                if source != nil { families[0].sounding.append(span) }
                continue
            }
            if let index = families.firstIndex(where: { $0.signature == key }) {
                families[index].segments.append(segment)
                families[index].sounding.append(span)
            } else if let first = families.first, first.signature == nil {
                families[0].signature = key
                families[0].segments.append(segment)
                families[0].sounding.append(span)
            } else if families.isEmpty {
                families.append(
                    AudioFamily(
                        id: planTrack.id, signature: key, segments: [segment], sounding: [span]))
            } else {
                families.append(
                    AudioFamily(id: nextID, signature: key, segments: [segment], sounding: [span]))
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
    /// one meter per composition track, carrying its family's sounding spans
    /// so `LevelMeterTrack.mix` counts it only while one of them holds the
    /// playhead (#65). A family's members never sound at the same instant, so
    /// the sum over the meters that sound is right.
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
                        LevelMeterTrack(
                            id: family.id, ramps: planTrack.ramps, sounding: family.sounding,
                            sink: sink))
                }
                inputParameters.append(
                    audioParameters(
                        for: track, segments: family.segments, ramps: planTrack.ramps,
                        onset: family.sounding.map(\.lowerBound).min(),
                        dsp: dsp.isEmpty
                            ? nil : AudioTrackDSP(segments: family.segments, parameters: dsp),
                        meter: sink))
            }
        }
        return (inputParameters, meters)
    }

    // MARK: - Audio

    /// One input-parameter block per composition audio track: the plan's
    /// piecewise-linear envelope as volume ramps, the time-pitch algorithm its
    /// segments asked for, and — when any clip on the track asks for one, or
    /// when this build is metering — the processing tap that runs pan, the
    /// mono fold, the compressor and noise reduction (`AudioTap.swift`).
    ///
    /// **A track with nothing to do still gets no tap**, on an export. `dsp`
    /// is nil, or its `isActive` is false, for every project that does not use
    /// the four sample-level audio properties, and the object built here is
    /// then exactly the one this function built before they existed. A
    /// pass-through tap measures bit-transparent, so this is a
    /// cost-and-clarity decision rather than a fidelity one — but it does mean
    /// an untouched project's audio needs no argument about transparency at
    /// all. A metering build breaks that rule deliberately and only for the
    /// preview, where there is no file to be identical to.
    ///
    /// **`mono` IS expressed now**, in the tap, at the head of the Mix stage
    /// (`AudioDSPChain.process`). It could not be expressed here in any case:
    /// `AVMutableAudioMixInputParameters` applies gain over time and cannot
    /// combine channels, which is why spec §7.2's old sentence about a
    /// per-segment flag "Swift applies with `AVMutableAudioMixInputParameters`
    /// where possible" described something the API cannot do — and the plan
    /// carries no such flag either. A project that saved `mono: true` before
    /// this landed does now sound different, which is the feature.
    static func audioParameters(
        for track: AVMutableCompositionTrack, segments: [PlanSegment], ramps: [PlanRamp]?,
        onset: Ticks?, dsp: AudioTrackDSP?, meter: LevelMeterSink?
    ) -> AVAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        if let pitch = segments.compactMap({ $0.pitch }).first {
            switch pitch {
            case "spectral": parameters.audioTimePitchAlgorithm = .spectral
            case "off": parameters.audioTimePitchAlgorithm = .varispeed
            case "time_domain": parameters.audioTimePitchAlgorithm = .timeDomain
            default: break
            }
        }
        for leg in volumeLegs(ramps: ramps ?? [], onset: onset) {
            parameters.setVolumeRamp(
                fromStartVolume: Float(leg.from), toEndVolume: Float(leg.to),
                timeRange: CMTimeRange(start: time(leg.start), duration: time(leg.duration)))
        }
        if let tap = AudioTap.make(for: dsp, meter: meter) {
            parameters.audioTapProcessor = tap
        }
        return parameters
    }

    /// One volume ramp as `audioParameters` sets it on a composition track:
    /// a plan ramp, a plan ramp clipped at the hold's end, or the hold.
    struct VolumeLeg: Equatable {
        let start: Ticks
        let duration: Ticks
        let from: Double
        let to: Double
    }

    /// The plan's ramps for one composition track, with the envelope's value
    /// at the track's own first sounding segment (`onset`: one whose source
    /// resolved; a missing or pending-reverse segment is empty time) HELD
    /// from time 0 to it.
    ///
    /// **Why** (kpgalligan/reelcut#87, spec §11 #87; measured on a standalone
    /// composition read at 48 kHz): before a track's first volume ramp an
    /// audio-mix input sits at the default 1.0, and the host slews every
    /// volume change by at most full scale per 1200 frames (25 ms), starting
    /// AT the change — so a clip that opens its track muted or fading in
    /// played its first 25 ms sliding down from 1.0. And a second format
    /// family's track is handed the PLAN track's ramps, which carry the
    /// earlier clips' gain up to its own first segment, where the same slide
    /// followed. Holding the value at the onset — the first sounding segment
    /// (one whose source resolved; a missing or pending-reverse segment is
    /// empty time, #217) — from 0 leaves nothing to slew there. Nothing at
    /// or after the hold's end changes, apart from a leg that straddles it
    /// being clipped on its own line; nothing is added before a segment that
    /// has sound before it on the same track, so a shared track's hard cut
    /// keeps the slew — the accepted limit.
    static func volumeLegs(ramps: [PlanRamp], onset: Ticks?) -> [VolumeLeg] {
        let legs = ramps.filter { $0.duration > 0 }.map {
            VolumeLeg(start: $0.start, duration: $0.duration, from: $0.from, to: $0.to)
        }
        guard let first = legs.first, let onset = onset else { return legs }
        let holdEnd = max(onset, first.start)
        guard holdEnd > 0 else { return legs }
        let value: Double
        if let holding = legs.first(where: {
            $0.start <= holdEnd && holdEnd < $0.start + $0.duration
        }) {
            let u = Double(holdEnd - holding.start) / Double(holding.duration)
            value = holding.from + (holding.to - holding.from) * u
        } else {
            value = legs.last(where: { $0.start + $0.duration <= holdEnd })?.to ?? first.from
        }
        var held = [VolumeLeg(start: 0, duration: holdEnd, from: value, to: value)]
        for leg in legs {
            let end = leg.start + leg.duration
            if end <= holdEnd { continue }
            if leg.start < holdEnd {
                held.append(
                    VolumeLeg(start: holdEnd, duration: end - holdEnd, from: value, to: leg.to))
            } else {
                held.append(leg)
            }
        }
        return held
    }
}
