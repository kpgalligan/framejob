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
        let (input, fullRange) = Self.analysisInput(media: media, url: url, urls: urls)
        guard
            let stamp = AnalysisStamp.make(
                kind: kind, media: media, url: url, input: input, fullRange: fullRange)
        else { throw AnalysisRequestError.unreadable(media.id) }
        let grid = AnalysisGrid(media: media)
        guard let indices = grid.indices(from: window.lowerBound, to: window.upperBound) else {
            return nil
        }
        let need = grid.need(indices, margin: kind.margin)
        switch AnalysisStore.lookup(kind, media: media.id, stamp: stamp, need: need, in: cacheDir) {
        case .hit: return nil
        case .miss(let ranges):
            return AnalysisRequest(
                kind: kind, cacheDir: cacheDir, media: media, url: url, stamp: stamp,
                input: input, ranges: ranges)
        }
    }

    /// The converted reader's input (CJ-23, CJ-S3 (c)): the media's converting
    /// Camera Log or PQ peak, else its track's HLG or PQ transfer; nil reads
    /// direct. `fullRange` as a converted filmstrip records it.
    static func analysisInput(
        media: MediaSnapshot, url: URL, urls: [UInt32: URL]
    ) -> (input: ThumbnailInput?, fullRange: Bool) {
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
