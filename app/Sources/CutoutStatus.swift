import AppKit

// Where a cut-out clip's masks stand (road map creator-jobs CO3, spec §11 CO-30, CO-31; a
// picture's, CO10b, CO-108):
// the Background section's Status and Analyze Now, Clip ▸ Remove Background's targets, toggle
// and checkmark, and `analyze_cutout`'s answer, centroid included. Names no `rc_*` (CJ-8 (l)):
// the plans and snapshots come through `ReelProject`, the windows and the need rule are
// `CutoutWants`' (CO-22), the coverage the store's, the runs the lane's.

/// A clip's cutout state (CO-30 (c), CO-31 (a)).
enum CutoutState: Equatable {
    case off
    case noPicture
    /// 0…1, CO-31 (a)'s progress.
    case analyzing(Double)
    case ready
    case noPerson
    /// A picture cut by its foreground whose mask found none (spec §11 CO-108).
    case noSubject
    /// The reason, in the Status read-out's words.
    case failed(String)

    /// Whether `analyze_cutout` stops waiting on it.
    var isSettled: Bool {
        if case .analyzing = self { return false }
        return true
    }

    /// The same state, a progress apart aside.
    func sameKind(as other: CutoutState) -> Bool {
        switch (self, other) {
        case (.analyzing, .analyzing): return true
        default: return self == other
        }
    }
}

/// One clip's status (CO-31 (a)).
struct CutoutClipStatus: Equatable {
    let clip: UInt32
    let media: UInt32?
    let state: CutoutState
    /// The needed grid indices of the clip's windows, merged.
    let frames: Int
    /// Of those, the ones the store covers for the analysis's stamp.
    let covered: Int
    let subjectFound: Bool
    /// The tool's sentence when failed.
    let error: String?
}

enum CutoutStatus {

    /// What a status was read from: the media, the needed ranges, the stored coverage and the
    /// pack's file, and the document's lane owner — what the read-out's tick recomputes the
    /// progress from and `analyze_cutout` reads the centroid from, off main.
    struct Detail {
        let status: CutoutClipStatus
        let media: MediaSnapshot?
        let need: [ClosedRange<Int>]
        let coverage: [ClosedRange<Int>]
        let pack: URL?
        let owner: Int?
        /// The document's cache folder, when the status read one.
        let cacheDir: URL?
        /// The analysis kind of the clip's masks (`CutoutWants.kind(of:)`, CO-106).
        var kind: AnalysisKind = .masks
    }

    // MARK: - Which clips

    /// A media or still clip of a video file with pictures (CO-30 (a)), or an image clip of a
    /// picture (CO-108).
    static func canCutOut(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        switch clip.source {
        case .media, .still:
            guard let media = snapshot.media(for: clip) else { return false }
            return media.kind == .video && media.hasVideo
        case .image:
            return snapshot.media(for: clip)?.kind == .image
        default:
            return false
        }
    }

    /// Clip ▸ Remove Background's edit (CO-30 (e)): with every clip that can be cut out already
    /// cut out, a null to each; otherwise a whole default cutout to each one without. One base
    /// `set_video` per clip.
    static func toggleOps(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> [ReelOp] {
        let targets = clips.filter { canCutOut($0, in: snapshot) }
        guard !targets.isEmpty else { return [] }
        if targets.allSatisfy({ $0.video?.cutout != nil }) {
            return targets.map { .setVideo(clips: [$0.id], patch: VideoPatch(cutout: .some(nil))) }
        }
        return targets.filter { $0.video?.cutout == nil }.map {
            .setVideo(clips: [$0.id], patch: VideoPatch(cutout: .some(CutoutProps())))
        }
    }

    /// The menu item's checkmark: on when every clip that can be cut out is, mixed when some
    /// are, off when none is (or none can be).
    static func menuState(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot)
        -> NSControl.StateValue
    {
        let targets = clips.filter { canCutOut($0, in: snapshot) }
        let on = targets.filter { $0.video?.cutout != nil }.count
        if on == 0 { return .off }
        return on == targets.count ? .on : .mixed
    }

    // MARK: - The status (CO-31 (a))

    /// `clip`'s status in `document`. Main thread.
    static func status(of clip: UInt32, in document: ProjectDocument) -> CutoutClipStatus {
        detail(of: clip, in: document).status
    }

    /// `clip`'s status and what it was read from. Main thread.
    static func detail(of clip: UInt32, in document: ProjectDocument) -> Detail {
        let handles = document.scope == nil
            ? [document.project] : [document.project, document.editedProject]
        let owner = document.maskOwner
        var kind = AnalysisKind.masks
        func answer(
            _ state: CutoutState, media: MediaSnapshot? = nil, need: [ClosedRange<Int>] = [],
            coverage: [ClosedRange<Int>] = [], frames: Int = 0, covered: Int = 0,
            found: Bool = false, pack: URL? = nil, cache: URL? = nil
        ) -> Detail {
            var error: String?
            if case .failed(let why) = state {
                let noun = kind == .foreground ? "foreground" : "person"
                error = "Clip \(clip)'s \(noun) masks could not be made: \(why)."
            }
            return Detail(
                status: CutoutClipStatus(
                    clip: clip, media: media?.id, state: state, frames: frames, covered: covered,
                    subjectFound: found, error: error),
                media: media, need: need, coverage: coverage, pack: pack, owner: owner,
                cacheDir: cache, kind: kind)
        }
        let found = handles.lazy.compactMap { handle in
            (handle.snapshot.clips + handle.snapshot.nests.flatMap(\.clips)).first {
                $0.id == clip
            }
        }.first
        guard let snapshot = found, snapshot.video?.cutout != nil else { return answer(.off) }
        guard let id = snapshot.source.mediaID, let media = document.project.snapshot.media(id)
        else { return answer(.noPicture) }
        kind = CutoutWants.kind(of: snapshot)
        let grid = kind.grid(of: media)
        var windows: [CutoutWindow] = []
        var hull: ClosedRange<Ticks>?
        // A picture's one window `[0, 1)`, one frame (CO-106, CO-108).
        let picture: Bool
        if case .image = snapshot.source { picture = true } else { picture = false }
        for handle in handles where picture {
            windows += CutoutWants.imageWindows(snapshot: handle.snapshot, range: nil)
                .filter { $0.clip == clip && $0.media == id }
        }
        if picture, !windows.isEmpty { hull = 0...1 }
        for handle in handles where !picture {
            guard let plan = handle.plan else { continue }
            windows += CutoutWants.windows(plan: plan, snapshot: handle.snapshot, range: nil)
                .filter { $0.clip == clip && $0.media == id }
            if let window = CutoutPlan(plan: plan, snapshot: handle.snapshot)
                .window(clip: clip, media: id)
            {
                hull = hull.map {
                    min($0.lowerBound, window.lowerBound)...max($0.upperBound, window.upperBound)
                } ?? window
            }
        }
        let need = AnalysisStore.merged(windows.map { CutoutWants.need($0, grid: grid) })
        let frames = count(need)
        guard frames > 0 else { return answer(.noPicture, media: media) }
        let url = mediaURL(for: media)
        let cacheDir = document.intendedCacheDirectory
        let stamp = url.flatMap { url in
            cacheDir.flatMap {
                Self.stamp(media: media, url: url, cacheDir: $0, in: document, kind: kind)
            }
        }
        var coverage: [ClosedRange<Int>] = []
        var packURL: URL?
        if let stamp, let cacheDir,
            let marker = AnalysisStore.readMarker(kind, media: id, in: cacheDir),
            marker.answers(for: stamp), let file = marker.files.first
        {
            let payload = AnalysisStore.payloadURL(kind, media: id, file: file, in: cacheDir)
            if FileManager.default.fileExists(atPath: payload.path) {
                coverage = AnalysisStore.merged(marker.ranges)
                packURL = payload
            }
        }
        let covered = count(intersect(need, coverage))
        // Covered first: a clip whose masks are all stored is never failed by another
        // window's job (CO-31 (a)).
        if covered == frames {
            var subject = false
            if let packURL, let hull, let pack = try? MaskPack(contentsOf: packURL) {
                subject = CutoutLookup.subjectFound(
                    pack: pack, window: hull, coverage: coverage, grid: grid)
            }
            let none: CutoutState = kind == .foreground ? .noSubject : .noPerson
            return answer(
                subject ? .ready : none, media: media, need: need, coverage: coverage,
                frames: frames, covered: covered, found: subject, pack: packURL, cache: cacheDir)
        }
        func failed(_ why: String) -> Detail {
            answer(
                .failed(why), media: media, need: need, coverage: coverage, frames: frames,
                covered: covered, pack: packURL, cache: cacheDir)
        }
        guard url != nil else { return failed("the media file is missing") }
        guard let cacheDir else { return failed("no cache folder") }
        guard stamp != nil else { return failed("the media file cannot be read") }
        let requests = ownerRequests(owner, media: id, cacheDir: cacheDir, kind: kind)
        let uncovered = need.flatMap { AnalysisStore.missingRanges($0, covered: coverage) }
        for request in requests {
            guard case .failed(let why)? = AnalysisLane.shared.run(of: request)?.outcome,
                !intersect(uncovered, request.ranges).isEmpty
            else { continue }
            return failed(why)
        }
        let running = runningRequest(requests)
        let fraction = running.flatMap { AnalysisLane.shared.progress(of: $0) } ?? 0
        let progress = progress(
            need: need, covered: coverage, running: running?.ranges, fraction: fraction)
        return answer(
            .analyzing(progress), media: media, need: need, coverage: coverage, frames: frames,
            covered: covered, pack: packURL, cache: cacheDir)
    }

    /// `owner`'s requests of `kind` of media `media` in `cacheDir`; none without an owner. Any
    /// thread.
    static func ownerRequests(
        _ owner: Int?, media: UInt32, cacheDir: URL, kind: AnalysisKind = .masks
    ) -> [AnalysisRequest] {
        guard let owner else { return [] }
        let folder = cacheDir.standardizedFileURL
        return AnalysisLane.shared.requests(of: owner).filter {
            $0.kind == kind && $0.media.id == media && $0.cacheDir.standardizedFileURL == folder
        }
    }

    /// The first of `requests` started and not ended.
    static func runningRequest(_ requests: [AnalysisRequest]) -> AnalysisRequest? {
        requests.first { request in
            guard let run = AnalysisLane.shared.run(of: request) else { return false }
            return run.startedAt != nil && run.outcome == nil
        }
    }

    /// The Status read-out's words (CO-30 (c)).
    static func words(_ state: CutoutState) -> String {
        switch state {
        case .off: return "Off"
        case .noPicture: return "No picture to analyze"
        case .analyzing(let progress):
            return "Analyzing \(min(99, max(0, Int((progress * 100).rounded(.down))))) %"
        case .ready: return "Ready"
        case .noPerson: return "No person found"
        case .noSubject: return "No subject found"
        case .failed(let why): return "Failed: \(why)"
        }
    }

    // MARK: - Progress (CO-31 (a))

    /// `(C_out + f · R_in) / N`: N the needed indices, R_in those inside `running`'s ranges,
    /// C_out the covered needed indices outside them; with no running request, C / N. Pure,
    /// 0…1.
    static func progress(
        need: [ClosedRange<Int>], covered: [ClosedRange<Int>], running: [ClosedRange<Int>]?,
        fraction: Double
    ) -> Double {
        let need = AnalysisStore.merged(need)
        let total = count(need)
        guard total > 0 else { return 0 }
        let coveredNeed = intersect(need, covered)
        let c = count(coveredNeed)
        guard let running else { return Double(c) / Double(total) }
        let rIn = count(intersect(need, running))
        let cOut = c - count(intersect(coveredNeed, running))
        let f = min(1, max(0, fraction))
        return min(1, max(0, (Double(cOut) + f * Double(rIn)) / Double(total)))
    }

    /// How many indices `ranges` hold, merged first.
    static func count(_ ranges: [ClosedRange<Int>]) -> Int {
        AnalysisStore.merged(ranges).reduce(0) { $0 + $1.count }
    }

    /// The indices both hold, merged.
    static func intersect(_ a: [ClosedRange<Int>], _ b: [ClosedRange<Int>])
        -> [ClosedRange<Int>]
    {
        let a = AnalysisStore.merged(a), b = AnalysisStore.merged(b)
        var out: [ClosedRange<Int>] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            let low = max(a[i].lowerBound, b[j].lowerBound)
            let high = min(a[i].upperBound, b[j].upperBound)
            if low <= high { out.append(low...high) }
            if a[i].upperBound < b[j].upperBound { i += 1 } else { j += 1 }
        }
        return out
    }

    // MARK: - The centroid (CO-31 (c))

    /// The mean, over `pack`'s frames whose grid index lies in `need` and `coverage` and whose
    /// mask is `found`, of each frame's value-weighted centroid in mask texels (`Σ v·(x + 0.5) /
    /// Σ v`, likewise y), scaled to the media's upright pixels; nil when no frame counts. Any
    /// thread.
    static func centroid(
        pack: MaskPack, need: [ClosedRange<Int>], coverage: [ClosedRange<Int>],
        mediaWidth: Int, mediaHeight: Int
    ) throws -> CGPoint? {
        guard pack.width > 0, pack.height > 0 else { return nil }
        let need = AnalysisStore.merged(need), coverage = AnalysisStore.merged(coverage)
        var perSlot: [Int: (x: Double, y: Double)?] = [:]
        var sumX = 0.0, sumY = 0.0, frames = 0
        for frame in pack.frames {
            let index = Int(frame.index), slot = Int(frame.slot)
            guard need.contains(where: { $0.contains(index) }),
                coverage.contains(where: { $0.contains(index) }), pack.masks[slot].found
            else { continue }
            let point: (x: Double, y: Double)?
            if let known = perSlot[slot] {
                point = known
            } else {
                point = weighted(try pack.mask(slot: slot), width: pack.width, height: pack.height)
                perSlot[slot] = point
            }
            guard let point else { continue }
            sumX += point.x
            sumY += point.y
            frames += 1
        }
        guard frames > 0 else { return nil }
        return CGPoint(
            x: sumX / Double(frames) * Double(mediaWidth) / Double(pack.width),
            y: sumY / Double(frames) * Double(mediaHeight) / Double(pack.height))
    }

    /// One mask's value-weighted centroid in texels; nil for an empty mask.
    private static func weighted(_ mask: [UInt8], width: Int, height: Int)
        -> (x: Double, y: Double)?
    {
        var total = 0.0, x = 0.0, y = 0.0
        for row in 0..<height {
            var rowSum = 0.0
            for column in 0..<width {
                let v = Double(mask[row * width + column])
                rowSum += v
                x += v * (Double(column) + 0.5)
            }
            total += rowSum
            y += rowSum * (Double(row) + 0.5)
        }
        guard total > 0 else { return nil }
        return (x / total, y / total)
    }

    // MARK: - The stamp, once per cache folder, media and URL (main only)

    private struct StampKey: Hashable {
        let folder: String
        let kind: AnalysisKind
        let media: UInt32
        let url: URL
    }

    private struct StampEntry {
        let media: MediaSnapshot
        let lut: URL?
        let stamp: AnalysisStamp?
    }

    private static var stamps: [StampKey: StampEntry] = [:]

    /// The stamp of `kind` `ProjectDocument.analysisRequest` would make for `media` at `url`:
    /// its asset read only when the media, its URL or its LUT's URL changed; a nil stamp is never
    /// memoised. Main thread.
    static func stamp(
        media: MediaSnapshot, url: URL, cacheDir: URL, in document: ProjectDocument,
        kind: AnalysisKind = .masks
    ) -> AnalysisStamp? {
        let lutID = media.color?.lut
        let lut = lutID.flatMap { document.project.snapshot.media($0) }.flatMap(mediaURL(for:))
        let key = StampKey(
            folder: cacheDir.standardizedFileURL.path, kind: kind, media: media.id, url: url)
        if let entry = stamps[key], entry.media == media, entry.lut == lut { return entry.stamp }
        var urls = [media.id: url]
        if let lutID, let lut { urls[lutID] = lut }
        let (input, fullRange) = ProjectDocument.analysisInput(media: media, url: url, urls: urls)
        let stamp = AnalysisStamp.make(
            kind: kind, media: media, url: url, input: input, fullRange: fullRange)
        guard let stamp else {
            stamps[key] = nil  // read again next time: the file may only be absent now (#438)
            return nil
        }
        stamps[key] = StampEntry(media: media, lut: lut, stamp: stamp)
        return stamp
    }
}
