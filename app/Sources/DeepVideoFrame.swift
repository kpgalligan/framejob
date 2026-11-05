import AVFoundation
import CoreMedia

/// Whether a frame is read deep, through export's reader rather than
/// `AVAssetImageGenerator` (spec §11 PR-9, PR-12): the one question
/// `Exporter.renderFrameReported` asks, after the composition is built, when
/// its caller's format keeps depth (`keepsDepth`, `FrameWriter.Format`'s
/// `carriesDepth`: `render_frame` and File ▸ Save Frame… as PNG or HEIC).
///
/// Two things make a frame deep. PR-9's: the recipe draws a still deeper than
/// 8 bits a component (`DeepStillFrame.shows`). PR-12's (issue batch B103,
/// #294): the frame shows a VP9 track deeper than 8 bits. The generator hands
/// back an 8-bit image of a 10-bit VP9 file, alone or beside anything, where
/// it hands back a 16-bit one of HEVC Main 10, HEVC Rext and ProRes 422 HQ
/// alone (`log_proof.py` L17's control), so only VP9 is asked about here.
///
/// Beside anything else the generator's depth follows the lowest track that
/// has video, so a 10-bit HEVC or ProRes clip above an 8-bit clip comes back
/// 8-bit. `showsDeepSource` is PR-14's question for that, asked after the
/// generator has answered 8 bits (`Exporter.renderFrameReported`).
///
/// It asks the RECIPE at the frame time, then the COMPOSITION: each `track`
/// layer's composition track, the segment of it at the frame time, and that
/// segment's own file. A VP9 clip elsewhere on the timeline is not on the
/// frame, and a reversed VP9 clip's segment reads PR-7's 10-bit intermediate,
/// not the VP9 file, so both keep the generator byte for byte.
///
/// Every caller is off the main thread already: `shows` opens each shown
/// file's asset and reads its first video track synchronously.
enum DeepVideoFrame {

    /// Every frame of an HLG project (spec §11 HD-13 (i): 16-bit, labelled
    /// BT.2100 HLG, whatever the caller's format); otherwise, when the
    /// caller's format `keepsDepth`, PR-9's still (`DeepStillFrame.shows`) or
    /// PR-12's track (`shows`), asked in that order.
    static func reads(
        _ project: ReelProject, _ built: BuiltComposition, urls: [UInt32: URL], at t: Ticks,
        options: RecipeOptions, keepsDepth: Bool
    ) -> Bool {
        project.plan?.output == .hlg
            || (keepsDepth
                && (DeepStillFrame.shows(project, urls: urls, at: t, options: options)
                    || shows(project, built, at: t, options: options)))
    }

    /// True when the recipe at `max(0, t)` (with `options`) has a `track`
    /// layer whose composition track's segment at that time reads a file
    /// whose first video description `isDeep`.
    static func shows(
        _ project: ReelProject, _ built: BuiltComposition, at t: Ticks, options: RecipeOptions
    ) -> Bool {
        guard let recipe = project.recipe(at: max(0, t), options: options) else { return false }
        let time = CompositionBuilder.time(max(0, t))
        for layer in recipe.layers {
            guard case .track(let id) = layer.source,
                let track = built.composition.track(withTrackID: CMPersistentTrackID(id))
            else { continue }
            if let shown = description(of: track, at: time), isDeep(shown) { return true }
        }
        return false
    }

    /// True when the recipe at `max(0, t)` (with `options`) has a `track`
    /// layer whose composition track's segment at that time reads a file
    /// whose first video description `isDeepSource` (spec §11 PR-14). A
    /// reversed clip counts through its 10-bit intermediate (PR-7).
    static func showsDeepSource(
        _ project: ReelProject, _ built: BuiltComposition, at t: Ticks, options: RecipeOptions
    ) -> Bool {
        guard let recipe = project.recipe(at: max(0, t), options: options) else { return false }
        let time = CompositionBuilder.time(max(0, t))
        return recipe.layers.contains { layer in
            guard case .track(let id) = layer.source,
                let track = built.composition.track(withTrackID: CMPersistentTrackID(id)),
                let shown = description(of: track, at: time)
            else { return false }
            return isDeepSource(shown)
        }
    }

    /// The first video description of the file `track`'s segment at `time`
    /// reads: nil for an empty segment, one whose target range does not hold
    /// the time, or one with no file.
    private static func description(
        of track: AVCompositionTrack, at time: CMTime
    ) -> CMFormatDescription? {
        guard let segment = track.segment(forTrackTime: time), !segment.isEmpty,
            segment.timeMapping.target.containsTime(time), let url = segment.sourceURL,
            let source = CompositionBuilder.firstTrack(of: AVURLAsset(url: url), mediaType: .video)
        else { return nil }
        return (CompositionBuilder.keyed(source, "formatDescriptions") as? [CMFormatDescription])?
            .first
    }

    /// A VP9 description whose `vpcC` record (the VP codec ISOBMFF binding,
    /// version 1: version, three flag bytes, profile, level, then bitDepth:4 |
    /// chromaSubsampling:3 | videoFullRangeFlag:1 — GR-23's layout) says more
    /// than 8 bits. Every VP9 MP4 carries the record, and so does the
    /// built-in rewrap's copy of a WebM (`container_codec.rs`'s `vpcc()`).
    /// Anything else — another codec, no record, one shorter than 7 bytes or
    /// of another version — is not deep.
    static func isDeep(_ description: CMFormatDescription) -> Bool {
        guard CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_VP9,
            let atoms = CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                as? [String: Any],
            let record = atoms["vpcC"] as? Data, record.count >= 7,
            record[record.startIndex] == 1
        else { return false }
        return record[record.startIndex + 6] >> 4 > 8
    }

    /// The ProRes rows, every one of them 10 bits or more.
    private static let proResSubtypes: Set<CMVideoCodecType> = [
        kCMVideoCodecType_AppleProRes422Proxy, kCMVideoCodecType_AppleProRes422LT,
        kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes422HQ,
        kCMVideoCodecType_AppleProRes4444, kCMVideoCodecType_AppleProRes4444XQ,
    ]

    /// `isDeep`, or an HEVC description whose `hvcC` record says more than 8
    /// bits (`bitDepthLumaMinus8`, the low 3 bits of byte 17, in a record of
    /// at least 18 bytes), or ProRes. AV1 is left out, as in PR-12: it does
    /// not decode on the host, so no depth of it has been measured.
    static func isDeepSource(_ description: CMFormatDescription) -> Bool {
        if isDeep(description) { return true }
        let atoms = CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            as? [String: Any]
        if let record = atoms?["hvcC"] as? Data, record.count >= 18,
            record[record.startIndex + 17] & 0x07 > 0
        {
            return true
        }
        return proResSubtypes.contains(CMFormatDescriptionGetMediaSubType(description))
    }
}
