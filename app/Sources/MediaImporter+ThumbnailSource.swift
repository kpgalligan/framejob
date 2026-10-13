import AVFoundation

/// Where a filmstrip's pictures come from (spec §11 GR-21): the plain asset,
/// or — for a media whose Camera Log converts, or whose video track is
/// labelled HLG or PQ — a one-clip composition around it, through
/// `CompositionBuilder` and step 0, so the strip is the preview's picture.
/// The strip's marker says which: the flat `CacheStamp` for a plain strip,
/// exactly as before, and a `ConvertedThumbsStamp` for a converted one.
///
/// Await-free (spec §11 W-8): the track's labels are read by key, as
/// `CompositionBuilder.convertsSources` reads them, and the awaiting stays in
/// `MediaImporter.thumbnails`, which asks `thumbnailReader` for its generator.

/// An HDR transfer step 0 converts and the plain generator does not draw as
/// step 0 does (GR-21's H0: HLG and PQ). SDR wide gamut is not one.
enum HDRTransfer: String, Codable, Equatable {
    case hlg, pq
}

/// What a strip is drawn through: a media's converting Camera Log (and its
/// LUT's file), or an HDR track's transfer.
struct ThumbnailInput: Equatable {
    /// The media's converting Camera Log; nil for an HDR input.
    let color: MediaColor?
    /// `urls[color.lut]` when `color.lut` is set; nil when it does not resolve.
    let lutURL: URL?
    /// Non-nil only when `color` is nil.
    let transfer: HDRTransfer?

    /// Camera Log: nil unless the media is a video with a picture whose
    /// `color` step 0 converts (`InputConversion.choose(input:)`).
    init?(media: MediaSnapshot, urls: [UInt32: URL]) {
        guard let color = Self.convertingColor(of: media) else { return nil }
        self.color = color
        lutURL = color.lut.flatMap { urls[$0] }
        transfer = nil
    }

    /// HLG or PQ: the first of the track's format descriptions for which
    /// `InputConversion.choose(for:)` answers `.hlg` or `.pq`; nil for every
    /// other answer, `.sdrWide` and `.srgb` included.
    init?(track: AVAssetTrack) {
        let descriptions =
            CompositionBuilder.keyed(track, "formatDescriptions") as? [CMFormatDescription] ?? []
        var found: HDRTransfer?
        for description in descriptions where found == nil {
            switch InputConversion.choose(for: description) {
            case .hlg: found = .hlg
            case .pq: found = .pq
            default: continue
            }
        }
        guard let found else { return nil }
        color = nil
        lutURL = nil
        transfer = found
    }

    /// The media's `color` when step 0 converts it, else nil — without URLs,
    /// so the document's observer and the cache ledger key on it.
    static func convertingColor(of media: MediaSnapshot) -> MediaColor? {
        guard media.kind == .video, media.hasVideo, let color = media.color,
            InputConversion.choose(input: color) != nil
        else { return nil }
        return color
    }
}

/// The marker of a strip drawn through step 0: the source's own
/// `CacheStamp`, and what converted it — the curve and gamut, or the LUT
/// named by its resolved path, size and modification second (so another
/// file of the same size and second is not taken for it), or the HDR
/// transfer. Nil fields are omitted on disk.
struct ConvertedThumbsStamp: Codable, Equatable {
    let source: MediaImporter.CacheStamp
    let log: LogCurve?
    let gamut: CameraGamut?
    let lutPath: String?
    let lutSize: Int64?
    let lutModified: Int64?
    let transfer: HDRTransfer?

    init(_ source: MediaImporter.CacheStamp, input: ThumbnailInput) {
        self.source = source
        let curve = input.color?.log
        log = curve
        gamut = curve == nil ? nil : input.color?.effectiveGamut
        let lut = curve == nil ? input.lutURL : nil
        let file = lut.flatMap(Self.fileStamp)
        lutPath = lut?.standardizedFileURL.path
        lutSize = file?.size
        lutModified = file?.modified
        transfer = input.transfer
    }

    /// The file's byte size and modification second, rounded as
    /// `CacheStamp` rounds; nil when it cannot be stat'ed.
    private static func fileStamp(_ url: URL) -> (size: Int64, modified: Int64)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.int64Value,
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return (size, Int64(modified.timeIntervalSince1970.rounded()))
    }

    /// An HDR strip's marker of `stamp`: its `source`, a `transfer` and
    /// nothing of a Camera Log.
    func holdsHDR(of stamp: MediaImporter.CacheStamp) -> Bool {
        source == stamp && transfer != nil && log == nil && gamut == nil && lutPath == nil
            && lutSize == nil && lutModified == nil
    }
}

/// The generator a strip pass reads, and what its marker records.
struct ThumbnailReader {
    let generator: AVAssetImageGenerator
    /// What the marker records: the caller's Camera Log input, else the
    /// track's HDR input, else nil (the flat stamp).
    let input: ThumbnailInput?
    /// False only when a converting input's one-clip build failed: the
    /// strip is then the plain asset's and no marker certifies it.
    let certifies: Bool
    /// The `RecipeSource` key the one-clip composition reads; nil on the
    /// plain path.
    let recipeKey: Int?

    func finish() {
        if let recipeKey { RecipeSource.shared.unregister(recipeKey) }
    }
}

extension MediaImporter {

    /// The strip's generator for `media`. The input is the caller's Camera
    /// Log, else the track's HDR transfer; none draws the plain asset exactly
    /// as before. A Camera Log whose LUT file does not resolve draws the
    /// plain asset (step 0 leaves it unconverted) and is certified as that
    /// input. Otherwise a one-clip project around the media — its display
    /// size, its rate, the media at 0, its Camera Log and LUT — is built as
    /// `Exporter.renderFrameReported` builds a frame (its own `RecipeSource`
    /// key, the composition, the generator over it; an HLG or PQ source makes
    /// it a `ConvertingCompositor` composition through `convertsSources`), and
    /// a build that fails draws the plain asset with `certifies` false.
    static func thumbnailReader(
        for media: MediaSnapshot, asset: AVURLAsset, track: AVAssetTrack?,
        input: ThumbnailInput?
    ) -> ThumbnailReader {
        let effective = input ?? track.flatMap(ThumbnailInput.init(track:))
        guard let effective, effective.color?.lut == nil || effective.lutURL != nil else {
            return ThumbnailReader(
                generator: plainGenerator(for: media, asset: asset), input: effective,
                certifies: true, recipeKey: nil)
        }
        let key = RecipeSource.shared.register()
        guard let built = oneClip(media, url: asset.url, input: effective, key: key) else {
            RecipeSource.shared.unregister(key)
            return ThumbnailReader(
                generator: plainGenerator(for: media, asset: asset), input: effective,
                certifies: false, recipeKey: nil)
        }
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        // The video composition already turns every source by its preferred
        // transform (`renderFrameReported` says why not twice).
        configure(generator, for: media, transform: false)
        return ThumbnailReader(
            generator: generator, input: effective, certifies: true, recipeKey: key)
    }

    /// The marker's head check. With a Camera Log, the converted marker of
    /// that input. Without one, the flat stamp, or a converted marker of the
    /// same source naming only a `transfer`: an HDR file's labels are fixed
    /// by its stamp, so the no-op pass opens no picture to ask them again.
    static func thumbsAreCurrent(
        _ stamp: CacheStamp, input: ThumbnailInput?, at marker: URL
    ) -> Bool {
        guard let input else {
            return readStamp(at: marker) == stamp
                || readConverted(at: marker)?.holdsHDR(of: stamp) == true
        }
        return readConverted(at: marker) == ConvertedThumbsStamp(stamp, input: input)
    }

    /// The flat stamp for a plain strip, exactly as before; the converted
    /// marker for one drawn through step 0.
    @discardableResult
    static func writeThumbsStamp(
        _ stamp: CacheStamp, input: ThumbnailInput?, to marker: URL
    ) -> Bool {
        guard let input else { return writeStamp(stamp, to: marker) }
        return writeStamp(ConvertedThumbsStamp(stamp, input: input), to: marker)
    }

    /// `readStamp`'s sibling for the converted shape; nil for a flat marker.
    private static func readConverted(at url: URL) -> ConvertedThumbsStamp? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ConvertedThumbsStamp.self, from: data)
    }

    /// Today's generator over the file itself.
    private static func plainGenerator(
        for media: MediaSnapshot, asset: AVURLAsset
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        configure(generator, for: media, transform: true)
        return generator
    }

    /// Half a second of tolerance each way (`thumbnails` says why) and the
    /// strip's tile size from `thumbnailHeight` and the media's aspect.
    private static func configure(
        _ generator: AVAssetImageGenerator, for media: MediaSnapshot, transform: Bool
    ) {
        generator.appliesPreferredTrackTransform = transform
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 2)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 2)
        let aspect = media.height > 0 ? Double(media.width) / Double(media.height) : 16.0 / 9.0
        generator.maximumSize = CGSize(
            width: max(16, (thumbnailHeight * aspect).rounded()), height: thumbnailHeight)
    }

    /// The one-clip project around `media` at `url`, published under `key`
    /// and built; nil for any refusal, identity, throw or empty plan.
    private static func oneClip(
        _ media: MediaSnapshot, url: URL, input: ThumbnailInput, key: Int
    ) -> BuiltComposition? {
        guard
            var project = ReelProject.new(
                width: media.width, height: media.height, fps: media.fps)
        else { return nil }
        var urls: [UInt32: URL] = [:]
        var lutID: UInt32?
        if let lutURL = input.lutURL {
            let lut = MediaDescriptor(path: lutURL.path, kind: .lut)
            guard let next = (try? project.applying(.addMedia(descriptor: lut))).project,
                let id = next.snapshot.media.last?.id
            else { return nil }
            project = next
            lutID = id
            urls[id] = lutURL
        }
        var descriptor = MediaDescriptor(media)
        descriptor.path = url.path
        descriptor.bookmark = nil
        descriptor.original = nil
        descriptor.color = input.color.map {
            MediaColor(log: $0.log, gamut: $0.gamut, lut: lutID, detected: false)
        }
        guard let withMedia = (try? project.applying(.addMedia(descriptor: descriptor))).project,
            let id = withMedia.snapshot.media.last?.id,
            let track = withMedia.snapshot.tracks.first?.id,
            let clipped = (try? withMedia.applying(.addClip(track: track, media: id, at: 0)))
                .project,
            let plan = clipped.plan, plan.duration > 0
        else { return nil }
        urls[id] = url
        RecipeSource.shared.set(clipped, for: key)
        return try? CompositionBuilder.build(
            plan: plan, planJSON: clipped.planJSON, urls: urls, recipeKey: key)
    }
}
