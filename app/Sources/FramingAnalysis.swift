import Foundation

/// What a VR command analyses (spec §11 VR-12; road map "creator-jobs" VR1):
/// for each media the named clips show, the windows those clips play plus
/// `margin` each side, in the order `kinds` — `shots`, `faces`, `subjects`.
/// CJ-20 stands: nothing runs at import; a command wants these requests and
/// waits, as Split at Shot Changes does. `reframe_clip`'s tool (VR2a2,
/// VR-28), VR2b's Clip ▸ Follow Subject… and `analysis_job {clips}` (dev, the
/// proof's door) call it; View ▸ Show Subjects never does (VR-13).
///
/// Names no `rc_*`; `requests` is main only (it reads the document).
enum FramingAnalysis {
    /// One second each side of a played window (VR-12).
    static let margin: Ticks = 600_000
    /// The kinds a framing reads, in the order they are wanted.
    static let kinds: [AnalysisKind] = [.shots, .faces, .subjects]

    /// One media's windows, in forward-media source ticks [lower, upper),
    /// merged where they overlap or touch, in time order.
    struct MediaWindows: Equatable {
        let media: UInt32
        let windows: [ClosedRange<Ticks>]
    }

    /// Each media clip among `clips` whose media has a moving picture, in
    /// order, its media grouped in the order of first appearance; each window
    /// the clip's played window (`AnalysisClipTimes`, through its source map,
    /// speed and reversal) widened by `margin` each side and clamped to
    /// 0…duration, merged per media. Text, shape, graphic, adjustment and nest
    /// clips, and clips of an audio file or a still, are skipped.
    static func windows(clips: [UInt32], in project: ReelProject) -> [MediaWindows] {
        let snapshot = project.snapshot
        var order: [UInt32] = []
        var found: [UInt32: [ClosedRange<Ticks>]] = [:]
        for id in clips {
            guard let clip = snapshot.clip(id), case .media(let mediaID, _, _) = clip.source,
                let media = snapshot.media(mediaID), media.kind == .video, media.hasVideo
            else { continue }
            let played = AnalysisClipTimes(clip: clip, media: media, map: project.sourceMap(id))
                .window
            let lower = max(0, played.lowerBound - margin)
            let upper = min(max(0, media.duration), played.upperBound + margin)
            guard lower <= upper else { continue }
            if found[mediaID] == nil { order.append(mediaID) }
            found[mediaID, default: []].append(lower...upper)
        }
        return order.map { MediaWindows(media: $0, windows: merged(found[$0] ?? [])) }
    }

    /// Every request `kinds` need over `windows(clips:in:)` of `project` —
    /// the document's open scope when nil, else the container a call named
    /// (`reframe_clip`'s, spec §11 VR-28): kind-major in `kinds` order, then
    /// media in the windows' order, each kind's need the windows' grid indices
    /// widened by its read margin
    /// (`ProjectDocument.analysisRequest(kind:media:url:urls:cacheDir:need:)`);
    /// a hit is omitted. Throws the request's own errors (a missing file, no
    /// cache folder, an unreadable file). Main thread.
    static func requests(
        clips: [UInt32], in document: ProjectDocument, project: ReelProject? = nil
    ) throws -> [AnalysisRequest] {
        let project = project ?? document.editedProject
        let all = windows(clips: clips, in: project)
        guard !all.isEmpty else { return [] }
        let urls = document.mediaURLs()
        guard let cacheDir = document.cacheDirectory else {
            throw ProjectDocument.AnalysisRequestError.noCache
        }
        var requests: [AnalysisRequest] = []
        for kind in kinds {
            for entry in all {
                guard let media = project.snapshot.media(entry.media) else { continue }
                guard let url = urls[entry.media] else {
                    throw ProjectDocument.AnalysisRequestError.missingFile(entry.media)
                }
                let grid = kind.grid(of: media)
                let need = entry.windows.compactMap {
                    grid.indices(from: $0.lowerBound, to: $0.upperBound)
                }.map { grid.need($0, margin: kind.margin) }
                guard !need.isEmpty else { continue }
                if let request = try ProjectDocument.analysisRequest(
                    kind: kind, media: media, url: url, urls: urls, cacheDir: cacheDir,
                    need: need)
                {
                    requests.append(request)
                }
            }
        }
        return requests
    }

    /// Tick ranges merged where they overlap or touch, in order.
    static func merged(_ ranges: [ClosedRange<Ticks>]) -> [ClosedRange<Ticks>] {
        var out: [ClosedRange<Ticks>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = out.last, range.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }
}
