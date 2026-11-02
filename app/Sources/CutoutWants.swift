import Foundation

// What a cutout asks of the analysis lane (road map creator-jobs CO2b, spec §11 CO-22): the windows
// a cut-out clip plays, the grid indices CO-24's lookup can ask of each, which open masks jobs a
// caller shares, and the requests it wants. Names no `rc_*` (CJ-8 (l)): the plan and the snapshot
// come through `ReelProject`. The document (`ProjectDocument+Masks.swift`), an export and a frame
// (`Exporter+Masks.swift`) are its three callers.

/// One window of a cut-out clip, in FORWARD source ticks of its media, `[lower, upper)`.
struct CutoutWindow: Equatable {
    let clip: UInt32
    let media: UInt32
    let lower: Ticks
    let upper: Ticks
}

/// Who wanted a request (the dev log's `role`).
enum CutoutWantRole: String {
    case document, export, frame
}

/// A media whose request could not be made, named by the first window's clip of that media.
struct CutoutWantFailure: Equatable {
    let clip: UInt32
    let message: String
}

/// A request's state on the lane, from `AnalysisLane.run(of:)`: started and not ended, queued and
/// not started, or ended (or unknown).
enum CutoutRunState {
    case running, queued, ended
}

enum CutoutWants {
    /// The documents' wants, in order: every `ensureMasks()` builds and wants here.
    static let queue = DispatchQueue(label: "com.kgalligan.framejob.cutout-wants", qos: .utility)

    // MARK: - Windows (CO-22 (a))

    /// Every plan video segment (duration > 0) of a clip whose BASE `video.cutout` is set, clipped
    /// to `range` (nil: the whole segment), as a forward window — mirrored about the clip's pivot
    /// when it plays reversed. A segment `range` misses gives none.
    static func windows(
        plan: CompositionPlan, snapshot: ProjectSnapshot, range: Range<Ticks>?
    ) -> [CutoutWindow] {
        var cutOut = Set<UInt32>()
        for clip in snapshot.clips + snapshot.nests.flatMap(\.clips) where clip.video?.cutout != nil {
            cutOut.insert(clip.id)
        }
        guard !cutOut.isEmpty else { return [] }
        let pivots = CutoutPlan(plan: plan, snapshot: snapshot).pivots
        var out: [CutoutWindow] = []
        for track in plan.videoTracks {
            for segment in track.segments where segment.duration > 0 && cutOut.contains(segment.clip) {
                var a = segment.start
                var b = segment.start + segment.duration
                if let range {
                    a = max(a, range.lowerBound)
                    b = min(b, range.upperBound)
                }
                guard a < b else { continue }
                let window = window(segment, from: a, to: b, pivot: pivots[segment.clip])
                if !out.contains(window) { out.append(window) }
            }
        }
        return out
    }

    /// The windows a frame at `t` draws cut out: the recipe layers with `background` remove, a
    /// media mask and a composition-track source, each through the segment covering `t` (of the
    /// mask's media), over `[t, t + 1)`.
    static func frameWindows(project: ReelProject, at t: Ticks, options: RecipeOptions)
        -> [CutoutWindow]
    {
        let layers = project.recipe(at: t, options: options)?.layers ?? []
        let cut = layers.filter {
            $0.cutout?.background == .remove && $0.cutout?.mask.kind == .media
        }
        guard !cut.isEmpty else { return [] }
        let plan = CutoutPlan(project: project)
        var out: [CutoutWindow] = []
        for layer in cut {
            guard let cutout = layer.cutout, case .track(let track) = layer.source,
                let segment = plan.covering(track: track, at: t), segment.media == cutout.mask.media
            else { continue }
            let window = window(segment, from: t, to: t + 1, pivot: plan.pivots[segment.clip])
            if !out.contains(window) { out.append(window) }
        }
        return out
    }

    /// `[a, b)` of `segment` in forward source ticks.
    private static func window(_ segment: PlanSegment, from a: Ticks, to b: Ticks, pivot: Ticks?)
        -> CutoutWindow
    {
        let sa = CutoutLookup.sourceTick(segment, at: a)
        let sb = CutoutLookup.sourceTick(segment, at: b)
        let low = min(sa, sb), high = max(sa, sb)
        if let pivot {
            return CutoutWindow(
                clip: segment.clip, media: segment.media, lower: pivot - high, upper: pivot - low)
        }
        return CutoutWindow(clip: segment.clip, media: segment.media, lower: low, upper: high)
    }

    // MARK: - The need rule

    /// The grid indices CO-24's lookup can ask of `window`: `⌊lower·rate + 1e-9⌋ …
    /// grid.index(of: max(lower, upper − 1))`, clamped to the grid.
    static func need(_ window: CutoutWindow, grid: AnalysisGrid) -> ClosedRange<Int> {
        let low = min(
            grid.lastIndex, max(0, Int((Double(window.lower) * grid.rate + 1e-9).rounded(.down))))
        let high = grid.index(of: max(window.lower, window.upper - 1))
        return min(low, high)...high
    }

    /// Each media's merged need over `windows`, for media with a file in `urls`.
    static func needs(windows: [CutoutWindow], snapshot: ProjectSnapshot, urls: [UInt32: URL])
        -> [UInt32: [ClosedRange<Int>]]
    {
        var out: [UInt32: [ClosedRange<Int>]] = [:]
        for window in windows where urls[window.media] != nil {
            guard let media = snapshot.media(window.media) else { continue }
            out[window.media, default: []].append(need(window, grid: AnalysisGrid(media: media)))
        }
        return out.mapValues(AnalysisStore.merged)
    }

    // MARK: - The keep rule (CO-22 (c))

    /// Of `previous` (every owner's open masks requests), a running one whose ranges meet its
    /// media's need, and a queued one whose every range lies inside it; never an ended one.
    static func kept(
        previous: [AnalysisRequest], need: [UInt32: [ClosedRange<Int>]],
        state: (AnalysisRequest) -> CutoutRunState
    ) -> [AnalysisRequest] {
        previous.filter { request in
            guard let ranges = need[request.media.id], !ranges.isEmpty else { return false }
            switch state(request) {
            case .running:
                return request.ranges.contains { range in ranges.contains { $0.overlaps(range) } }
            case .queued:
                return request.ranges.allSatisfy {
                    AnalysisStore.missingRanges($0, covered: ranges).isEmpty
                }
            case .ended:
                return false
            }
        }
    }

    /// `request`'s state on the shared lane.
    static func state(_ request: AnalysisRequest) -> CutoutRunState {
        guard let run = AnalysisLane.shared.run(of: request), run.outcome == nil else { return .ended }
        return run.startedAt == nil ? .queued : .running
    }

    // MARK: - Requests

    /// What a caller wants: per media with a file and a miss, the `keeping` requests of that media
    /// plus a new request holding the needed, uncovered indices outside their ranges. A media
    /// whose stamp cannot be made is a failure named by its first window's clip.
    static func requests(
        windows: [CutoutWindow], snapshot: ProjectSnapshot, urls: [UInt32: URL], cacheDir: URL,
        keeping: [AnalysisRequest]
    ) -> (requests: [AnalysisRequest], failures: [CutoutWantFailure]) {
        let needs = needs(windows: windows, snapshot: snapshot, urls: urls)
        var order: [UInt32] = []
        for window in windows where needs[window.media] != nil && !order.contains(window.media) {
            order.append(window.media)
        }
        var requests: [AnalysisRequest] = []
        var failures: [CutoutWantFailure] = []
        for id in order {
            guard let media = snapshot.media(id), let url = urls[id], let need = needs[id] else {
                continue
            }
            let missing: AnalysisRequest?
            do {
                missing = try ProjectDocument.analysisRequest(
                    kind: .masks, media: media, url: url, urls: urls, cacheDir: cacheDir,
                    need: need)
            } catch {
                let clip = windows.first { $0.media == id }?.clip ?? 0
                let why = error.localizedDescription
                failures.append(CutoutWantFailure(
                    clip: clip, message: why.hasSuffix(".") ? String(why.dropLast()) : why))
                continue
            }
            guard let missing else { continue }
            let kept = keeping.filter { $0.media.id == id }
            requests += kept
            let taken = kept.flatMap(\.ranges)
            let rest = AnalysisStore.merged(
                missing.ranges.flatMap { AnalysisStore.missingRanges($0, covered: taken) })
            if !rest.isEmpty {
                requests.append(AnalysisRequest(
                    kind: .masks, cacheDir: cacheDir, media: missing.media, url: missing.url,
                    stamp: missing.stamp, input: missing.input, ranges: rest))
            }
        }
        return (requests, failures)
    }

    // MARK: - The dev log (CO-22 (h))

    #if FRAMEJOB_DEV_TOOLS
    private static let logLock = NSLock()
    private static var entries: [(role: CutoutWantRole, owner: Int, request: AnalysisRequest)] = []
    private static let logLimit = 512

    /// Records each of `requests` once per (role, owner, request), the last `logLimit` kept.
    static func log(_ role: CutoutWantRole, owner: Int, _ requests: [AnalysisRequest]) {
        logLock.lock()
        defer { logLock.unlock() }
        for request in requests
        where !entries.contains(where: {
            $0.role == role && $0.owner == owner && $0.request == request
        }) {
            entries.append((role, owner, request))
        }
        if entries.count > logLimit { entries.removeFirst(entries.count - logLimit) }
    }

    /// Every logged want, oldest first.
    static var logged: [(role: CutoutWantRole, owner: Int, request: AnalysisRequest)] {
        logLock.lock()
        defer { logLock.unlock() }
        return entries
    }
    #endif
}
