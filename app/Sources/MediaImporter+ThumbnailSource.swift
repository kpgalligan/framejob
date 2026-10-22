import AVFoundation

/// Where a filmstrip's pictures come from (spec §11 GR-21): the plain asset,
/// or — for a media whose Camera Log converts, a PQ file with a peak (spec
/// §11 HD-12), or a video track labelled HLG or PQ — a one-clip composition
/// around it, through `CompositionBuilder` and step 0, so the strip is the
/// preview's picture. A still labelled HLG or PQ, or a PQ still with a peak,
/// draws its one tile the same way (`stillReader`, spec §11 HD-21).
/// The strip's marker says which: the flat `CacheStamp` for a plain strip,
/// exactly as before, and a `ConvertedThumbsStamp` for a converted one, which
/// records `fullRange` for an S-Log3 or V-Log media from a full-range source
/// (spec §11 GR-23), so a strip certified without it is drawn again.
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
/// LUT's file) or a PQ file's peak, or an HDR track's transfer.
struct ThumbnailInput: Equatable {
    /// The media's converting Camera Log or PQ peak; nil for an HDR input.
    let color: MediaColor?
    /// `urls[color.lut]` when `color.lut` is set; nil when it does not resolve.
    let lutURL: URL?
    /// Non-nil only when `color` is nil.
    let transfer: HDRTransfer?

    /// Camera Log or a PQ peak: nil unless the media is a video with a
    /// picture whose `color` step 0 converts, or a PQ still with a peak
    /// (`convertingColor(of:)`).
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

    /// HLG or PQ by the still's own label (spec §11 HD-21):
    /// `StillColor.conversion(at:)`, a header read with no decode, answers
    /// `.hlg` or `.pq`; nil for every other still, which keeps today's tile.
    init?(still url: URL) {
        switch StillColor.conversion(at: url) {
        case .hlg?: transfer = .hlg
        case .pq?: transfer = .pq
        default: return nil  // an SDR still keeps today's tile
        }
        color = nil
        lutURL = nil
    }

    /// Whether the strip's picture follows the source's range: S-Log3 and
    /// V-Log, whose code domain does (`InputConversions.codeDomain`); not
    /// Apple Log, a LUT or an HDR transfer.
    var readsRange: Bool {
        switch color?.log {
        case .slog3, .vlog: return true
        default: return false
        }
    }

    /// The media's `color` when step 0 converts by it — a Camera Log
    /// (`InputConversion.choose(input:)`), or a PQ file's effective peak
    /// (spec §11 HD-12), so a change of either redraws the strip — else nil;
    /// without URLs, so the document's observer and the cache ledger key on
    /// it. A PQ file with no peak keeps the HDR transfer's strip. A still
    /// answers only for a PQ peak (spec §11 HD-21), so a set, clear, undo or
    /// redo of it starts a pass.
    static func convertingColor(of media: MediaSnapshot) -> MediaColor? {
        if media.kind == .image, media.hasVideo, let color = media.color {
            return color.pq?.effectivePeak != nil ? color : nil  // HD-21
        }
        guard media.kind == .video, media.hasVideo, let color = media.color,
            InputConversion.choose(input: color) != nil || color.pq?.effectivePeak != nil
        else { return nil }
        return color
    }
}

/// The marker of a strip drawn through step 0: the source's own
/// `CacheStamp`, and what converted it — the curve and gamut, or the LUT
/// named by its resolved path, size and modification second (so another
/// file of the same size and second is not taken for it), or the HDR
/// transfer; `fullRange` true for a `readsRange` input from a source
/// flagged full range (spec §11 GR-23); and `peak`, a PQ file's effective
/// peak (spec §11 HD-12). Nil fields are omitted on disk, so every other
/// marker is the shape it was before, and a marker written before GR-23 or
/// HD-12 decodes with no `fullRange` or `peak`.
struct ConvertedThumbsStamp: Codable, Equatable {
    let source: MediaImporter.CacheStamp
    let log: LogCurve?
    let gamut: CameraGamut?
    let lutPath: String?
    let lutSize: Int64?
    let lutModified: Int64?
    let transfer: HDRTransfer?
    let fullRange: Bool?
    let peak: UInt32?

    init(_ source: MediaImporter.CacheStamp, input: ThumbnailInput, fullRange: Bool) {
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
        self.fullRange = fullRange && input.readsRange ? true : nil
        peak = input.color?.pq?.effectivePeak
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
            && lutSize == nil && lutModified == nil && peak == nil
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
    /// What the marker records as `fullRange`: a `readsRange` input over a
    /// track flagged full range (`CompositionBuilder.isFullRange`).
    let fullRange: Bool
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
        let fullRange =
            effective?.readsRange == true && track.map(CompositionBuilder.isFullRange) == true
        guard let effective, effective.color?.lut == nil || effective.lutURL != nil else {
            return ThumbnailReader(
                generator: plainGenerator(for: media, asset: asset), input: effective,
                certifies: true, fullRange: fullRange, recipeKey: nil)
        }
        let key = RecipeSource.shared.register()
        guard let built = oneClip(media, url: asset.url, input: effective, key: key) else {
            RecipeSource.shared.unregister(key)
            return ThumbnailReader(
                generator: plainGenerator(for: media, asset: asset), input: effective,
                certifies: false, fullRange: fullRange, recipeKey: nil)
        }
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        // The video composition already turns every source by its preferred
        // transform (`renderFrameReported` says why not twice).
        configure(generator, for: media, transform: false)
        return ThumbnailReader(
            generator: generator, input: effective, certifies: true, fullRange: fullRange,
            recipeKey: key)
    }

    /// A still's one tile through step 0 (spec §11 HD-21): GR-21's one-clip
    /// project around it (its pixel size, its rate, the still at 0, its `pq`
    /// only with a peak), built as `Exporter.renderFrameReported` builds a
    /// frame and read at 0 with zero tolerance, its longest side at most
    /// `thumbnailHeight` × 4, today's still bound. Nil when the build fails,
    /// its key then unregistered; the caller's `finish()` unregisters it
    /// otherwise.
    static func stillReader(
        for media: MediaSnapshot, url: URL, input: ThumbnailInput
    ) -> ThumbnailReader? {
        let key = RecipeSource.shared.register()
        guard let built = oneClip(media, url: url, input: input, key: key) else {
            RecipeSource.shared.unregister(key)
            return nil
        }
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: thumbnailHeight * 4, height: thumbnailHeight * 4)
        return ThumbnailReader(
            generator: generator, input: input, certifies: true, fullRange: false,
            recipeKey: key)
    }

    /// The marker's head check. With a Camera Log, the converted marker of
    /// that input — and, for S-Log3 or V-Log alone, of `url`'s range, read
    /// from its first video track's format description (no picture
    /// decoded; spec §11 GR-23). Without one, the flat stamp, or a converted
    /// marker of the same source naming only a `transfer`: an HDR file's
    /// labels are fixed by its stamp, so the no-op pass opens no picture to
    /// ask them again.
    static func thumbsAreCurrent(
        _ stamp: CacheStamp, input: ThumbnailInput?, url: URL, at marker: URL
    ) -> Bool {
        guard let input else {
            return readStamp(at: marker) == stamp
                || readConverted(at: marker)?.holdsHDR(of: stamp) == true
        }
        var assets: [UInt32: AVURLAsset] = [:]
        let track =
            input.readsRange
            ? CompositionBuilder.assetTrack(at: url, key: 0, mediaType: .video, assets: &assets)
            : nil
        let fullRange = track.map(CompositionBuilder.isFullRange) == true
        let current = ConvertedThumbsStamp(stamp, input: input, fullRange: fullRange)
        return readConverted(at: marker) == current
    }

    /// The flat stamp for a plain strip, exactly as before; the converted
    /// marker for one drawn through step 0, with the reader's `fullRange`.
    @discardableResult
    static func writeThumbsStamp(
        _ stamp: CacheStamp, input: ThumbnailInput?, fullRange: Bool, to marker: URL
    ) -> Bool {
        guard let input else { return writeStamp(stamp, to: marker) }
        return writeStamp(
            ConvertedThumbsStamp(stamp, input: input, fullRange: fullRange), to: marker)
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
        descriptor.color?.pq = input.color?.pq
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
