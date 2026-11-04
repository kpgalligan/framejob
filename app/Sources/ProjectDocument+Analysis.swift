import AVFoundation

/// A document's side of the analysis lane (spec §11 CJ-21, CJ-22; road map
/// "creator-jobs" CJ2a), so `ProjectDocument.swift` takes nothing: whether it
/// is still open, read from any thread, and the request a window of one of
/// its media needs.
extension ProjectDocument {

    enum AnalysisRequestError: LocalizedError {
        case missingFile(UInt32)
        case noCache
        case unreadable(UInt32)

        var errorDescription: String? {
            switch self {
            case .missingFile(let id):
                return "Media \(id)'s file is missing. relink_media points it at the file."
            case .noCache: return "The project has no cache folder to keep the analysis in."
            case .unreadable(let id): return "Media \(id)'s file cannot be read."
            }
        }
    }

    /// Whether the document is open — its `RecipeSource` slot still holds a
    /// project, which `close()` drops. Any thread: an owner's `alive()`.
    nonisolated var isOpenForAnalysis: Bool {
        RecipeSource.shared.project(for: recipeKey) != nil
    }

    /// The request `kind` needs over `window` (forward-media source ticks,
    /// [lower, upper)) of `media`: nil when the store already answers it (a
    /// hit, or a window holding no grid index). Main thread.
    func analysisRequest(
        kind: AnalysisKind, media: MediaSnapshot, window: ClosedRange<Ticks>
    ) throws -> AnalysisRequest? {
        let urls = mediaURLs()
        guard let url = urls[media.id] else { throw AnalysisRequestError.missingFile(media.id) }
        guard let cacheDir = cacheDirectory else { throw AnalysisRequestError.noCache }
        let grid = kind.grid(of: media)
        // No index in the window is no need: the stamp is still made first, so an unreadable
        // file throws as it always did.
        let need = grid.indices(from: window.lowerBound, to: window.upperBound)
            .map { [grid.need($0, margin: kind.margin)] } ?? []
        return try Self.analysisRequest(
            kind: kind, media: media, url: url, urls: urls, cacheDir: cacheDir, need: need)
    }

    /// The request `kind` needs over the grid indices `need` of `media` at `url` (road map
    /// creator-jobs CO2b, spec §11 CO-22): nil when every range is a hit; else one request
    /// holding the merged missing ranges. Throws `.unreadable` when the stamp cannot be made.
    /// Any thread: a cutout's wants build here off main.
    nonisolated static func analysisRequest(
        kind: AnalysisKind, media: MediaSnapshot, url: URL, urls: [UInt32: URL],
        cacheDir: URL, need: [ClosedRange<Int>]
    ) throws -> AnalysisRequest? {
        // A sound kind reads raw sound: no picture input, so `set_media_color`
        // never changes its stamp (spec §11 FC-31).
        let (input, fullRange) =
            kind.usesSoundQueue
            ? (nil, false) : analysisInput(media: media, url: url, urls: urls)
        guard
            let stamp = AnalysisStamp.make(
                kind: kind, media: media, url: url, input: input, fullRange: fullRange)
        else { throw AnalysisRequestError.unreadable(media.id) }
        var missing: [ClosedRange<Int>] = []
        for range in need {
            switch AnalysisStore.lookup(kind, media: media.id, stamp: stamp, need: range, in: cacheDir)
            {
            case .hit: continue
            case .miss(let ranges): missing += ranges
            }
        }
        guard !missing.isEmpty else { return nil }
        return AnalysisRequest(
            kind: kind, cacheDir: cacheDir, media: media, url: url, stamp: stamp,
            input: input, ranges: AnalysisStore.merged(missing))
    }

    /// The converted reader's input (CJ-23, CJ-S3 (c)): the media's converting
    /// Camera Log or PQ peak, else its track's HLG or PQ transfer; nil reads
    /// direct. `fullRange` as a converted filmstrip records it. A media that is not a video —
    /// a picture's masks (spec §11 CO-105) — reads direct, with no asset made.
    nonisolated static func analysisInput(
        media: MediaSnapshot, url: URL, urls: [UInt32: URL]
    ) -> (input: ThumbnailInput?, fullRange: Bool) {
        guard media.kind == .video else { return (nil, false) }
        var assets: [UInt32: AVURLAsset] = [:]
        let track = CompositionBuilder.assetTrack(
            at: url, key: media.id, mediaType: .video, assets: &assets)
        let input = ThumbnailInput(media: media, urls: urls)
            ?? track.flatMap(ThumbnailInput.init(track:))
        let fullRange =
            input?.readsRange == true && track.map(CompositionBuilder.isFullRange) == true
        return (input, fullRange)
    }
}
