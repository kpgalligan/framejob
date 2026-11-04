import Foundation

/// The export's and the offline frame's wait for the masks they draw (road map creator-jobs
/// CO2b, spec §11 CO-6, CO-22 (e), (f); a picture's, CO10b, CO-106), in `withRampAudio`'s
/// shape: wanted on the lane before the build, so no frame is composed while a mask it draws is
/// still being made.
/// Both share every owner's open masks jobs by CO-22 (c)'s keep rule rather than queueing a
/// second one behind the document's.
///
/// **Deadlock.** `AnalysisLane.wait` asks `cancelled()` under the lane's lock, and an
/// `Exporter`'s last reference can drop there; `releaseMasks` therefore runs inside
/// `releaseRecipeKey`'s `ramp` closure, which `deinit` defers (as `RampAudioRenders.release`).
/// No owner's `alive` here takes a lock.
extension Exporter {
    /// How long `render_frame` and File ▸ Save Frame… wait for a frame's masks (CO-6).
    static let frameCutoutWait: TimeInterval = 30

    private static let maskOwnersLock = NSLock()
    /// An export's recipe key → its lane owner, made at its first want.
    private static var maskOwners: [Int: Int] = [:]

    /// The lane owner of the export writing under `key`, made on first use.
    private static func maskOwner(for key: Int) -> Int {
        maskOwnersLock.lock()
        defer { maskOwnersLock.unlock() }
        if let owner = maskOwners[key] { return owner }
        let owner = AnalysisLane.shared.newOwner()
        maskOwners[key] = owner
        return owner
    }

    /// Blocks until every mask the export's range draws is cached (CO-22 (e)): the windows of
    /// `plan`'s cut-out clips over `settings`' range, and of the cut pictures meeting it (CO-106),
    /// wanted under the export's own owner — the open jobs it shares plus the remainder, kind by
    /// kind — and waited on with no deadline but `cancelled`. No cache folder, an unreadable
    /// media or a failed job throws `cutoutFailed` naming the first window's clip of that media
    /// and kind (`foreground:` from that kind); a media still missing after a second landing too.
    /// Never main.
    static func waitForMasks(
        plan: CompositionPlan, urls: [UInt32: URL], settings: ExportSettings, key: Int,
        cancelled: @escaping () -> Bool
    ) throws {
        guard let project = RecipeSource.shared.project(for: key) else { return }
        let snapshot = project.snapshot
        let range = settings.start..<(settings.start + max(settings.duration, 0))
        let windows = CutoutWants.windows(plan: plan, snapshot: snapshot, range: range)
            + CutoutWants.imageWindows(snapshot: snapshot, range: range)
        guard let first = windows.first(where: { urls[$0.media] != nil }) else { return }
        func clip(of media: UInt32, kind: AnalysisKind) -> UInt32 {
            windows.first { $0.media == media && $0.kind == kind }?.clip ?? first.clip
        }
        guard let cacheDir = ReverseSource.shared.resolution(for: key).cache else {
            throw ExportError.cutoutFailed(
                clip: first.clip, message: "the project has no cache folder to keep the analysis in",
                foreground: first.kind == .foreground)
        }
        let owner = maskOwner(for: key)
        var landings = 0
        while true {
            let (requests, failures) = CutoutWants.wants(
                windows: windows, snapshot: snapshot, urls: urls, cacheDir: cacheDir)
            if let failure = failures.first {
                let kind = windows.first { $0.clip == failure.clip }?.kind ?? .masks
                throw ExportError.cutoutFailed(
                    clip: failure.clip, message: failure.message, foreground: kind == .foreground)
            }
            guard let missing = requests.first else { return }
            if landings >= 2 {
                throw ExportError.cutoutFailed(
                    clip: clip(of: missing.media.id, kind: missing.kind),
                    message: "its masks do not cover the frames it plays",
                    foreground: missing.kind == .foreground)
            }
            AnalysisLane.shared.want(requests, owner: owner, alive: { true }, settled: nil)
            #if FRAMEJOB_DEV_TOOLS
            CutoutWants.log(.export, owner: owner, requests)
            #endif
            switch AnalysisLane.shared.wait(
                for: requests, owner: owner, deadline: .distantFuture, cancelled: cancelled)
            {
            case .landed:
                landings += 1
            case .failed(let why):
                let failed = requests.first {
                    if case .failed? = AnalysisLane.shared.run(of: $0)?.outcome { return true }
                    return false
                } ?? missing
                throw ExportError.cutoutFailed(
                    clip: clip(of: failed.media.id, kind: failed.kind), message: why,
                    foreground: failed.kind == .foreground)
            case .cancelled, .timedOut:
                throw ExportError.cancelled
            }
        }
    }

    /// Drops the export's mask wants (CO-22 (e)); from `releaseRecipeKey`'s `ramp` closure.
    static func releaseMasks(key: Int) {
        maskOwnersLock.lock()
        let owner = maskOwners.removeValue(forKey: key)
        maskOwnersLock.unlock()
        if let owner { AnalysisLane.shared.release(owner: owner) }
    }

    /// A media's masks of one kind: the frame wait's stamps and uncovered set are keyed by it.
    private struct MaskKey: Hashable {
        let kind: AnalysisKind
        let media: UInt32
    }

    /// Waits up to `limit` for the masks the recipe at `t` draws (CO-22 (f)) under a fresh owner,
    /// polling the store every `AnalysisLane.pollInterval` until each is covered, one of its
    /// requests failed, or the limit; answers the clips drawn uncut, ascending — an unreadable
    /// media's at once, every one with no cache folder. A cut picture's masks are waited for by
    /// their kind beside the movies' (CO-106). Never main: it blocks.
    static func waitForFrameMasks(
        project: ReelProject, urls: [UInt32: URL], key: Int, at t: Ticks,
        options: RecipeOptions, limit: TimeInterval
    ) -> [UInt32] {
        let windows = CutoutWants.frameWindows(project: project, at: t, options: options)
            .filter { urls[$0.media] != nil }
        guard !windows.isEmpty else { return [] }
        let snapshot = project.snapshot
        func clips(of keys: Set<MaskKey>) -> [UInt32] {
            Array(Set(windows.filter { keys.contains(MaskKey(kind: $0.kind, media: $0.media)) }
                .map(\.clip))).sorted()
        }
        guard let cacheDir = ReverseSource.shared.resolution(for: key).cache else {
            return clips(of: Set(windows.map { MaskKey(kind: $0.kind, media: $0.media) }))
        }
        var needs: [MaskKey: [ClosedRange<Int>]] = [:]
        for kind in Set(windows.map(\.kind)) {
            let byMedia = CutoutWants.needs(
                windows: windows.filter { $0.kind == kind }, snapshot: snapshot, urls: urls)
            for (media, need) in byMedia { needs[MaskKey(kind: kind, media: media)] = need }
        }
        let (requests, failures) = CutoutWants.wants(
            windows: windows, snapshot: snapshot, urls: urls, cacheDir: cacheDir)
        let unreadable = Set(failures.compactMap { failure in
            windows.first { $0.clip == failure.clip }.map { MaskKey(kind: $0.kind, media: $0.media) }
        })
        guard !requests.isEmpty else { return clips(of: unreadable) }
        // Each waited media's stamp, made once by its request; the polls only look up.
        var stamps: [MaskKey: AnalysisStamp] = [:]
        for request in requests {
            stamps[MaskKey(kind: request.kind, media: request.media.id)] = request.stamp
        }
        func uncovered() -> Set<MaskKey> {
            Set(stamps.filter { key, stamp in
                (needs[key] ?? []).contains {
                    if case .hit = AnalysisStore.lookup(
                        key.kind, media: key.media, stamp: stamp, need: $0, in: cacheDir)
                    {
                        return false
                    }
                    return true
                }
            }.keys)
        }
        let owner = AnalysisLane.shared.newOwner()
        defer { AnalysisLane.shared.release(owner: owner) }
        AnalysisLane.shared.want(requests, owner: owner, alive: { true }, settled: nil)
        #if FRAMEJOB_DEV_TOOLS
        CutoutWants.log(.frame, owner: owner, requests)
        #endif
        let deadline = Date().addingTimeInterval(limit)
        var missing = uncovered()
        while !missing.isEmpty, Date() < deadline,
            !requests.contains(where: {
                if case .failed? = AnalysisLane.shared.run(of: $0)?.outcome { return true }
                return false
            })
        {
            Thread.sleep(forTimeInterval: AnalysisLane.pollInterval)
            missing = uncovered()
        }
        return clips(of: missing.union(unreadable))
    }

    /// `render_frame`'s sentence for each clip drawn uncut (CO-22 (f)), ascending: a picture
    /// cut by its foreground (in `foreground`) names its foreground masks (CO-106).
    static func cutoutSentences(_ uncut: [UInt32], foreground: Set<UInt32> = []) -> [String] {
        uncut.sorted().map {
            "Clip \($0) is drawn uncut: its \(foreground.contains($0) ? "foreground" : "person") "
                + "masks were not ready within \(Int(frameCutoutWait)) s."
        }
    }
}
