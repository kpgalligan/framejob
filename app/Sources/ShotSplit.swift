import Foundation

/// Clip ▸ Split at Shot Changes and `split_at_shots` (spec §11 CJ-29; road
/// map "creator-jobs" CJ2b): the planner both doors call, so the menu and the
/// tool cannot mean different things (SY-1's shape). A composite of `split`
/// (CJ-8 (f)): no core, FFI or format change.
///
/// **Targets** are media clips showing a moving picture — the media a video
/// with `hasVideo`, the clip's `enabled.video` on; any other clip named is
/// skipped. **Wants** are one `shots` request per media over the UNION of
/// its targets' played windows, never their hull: `analysisRequest` once per
/// window and the misses' ranges merged, so a gap no clip plays is never
/// read. **The plan** reads the store, maps each cut inside a target's window
/// to timeline time on the canvas grid, drops one within a canvas frame of
/// either edge, counts the ceiling with the linked partners `split` also
/// cuts BEFORE any op, and answers one `split` per cut, latest first, so the
/// original id keeps the head.
enum ShotSplit {
    static let actionName = "Split at Shot Changes"

    struct Target {
        let clip: ClipSnapshot
        let media: MediaSnapshot
        let times: AnalysisClipTimes
    }

    struct Want {
        let media: MediaSnapshot
        let request: AnalysisRequest
    }

    struct Plan {
        let ops: [ReelOp]
        let cuts: [(clip: UInt32, at: [Ticks])]
        let added: Int
    }

    enum Refusal: LocalizedError {
        /// `named`: the caller named the clips (the tool's `clips`).
        case nothingToSplit(named: Bool)
        case ceiling(added: Int, room: Int)
        case notCached(UInt32)

        var errorDescription: String? {
            switch self {
            case .nothingToSplit(let named):
                return (named ? "None of clips is" : "No clip on an unlocked track is")
                    + " a media clip showing a moving picture, so there are no shot changes "
                    + "to find."
            case .ceiling(let added, let room):
                // The composite's own reading (D2-1), as `CaptionLayout`'s
                // `tooMany`: the core's "too many clips" would name neither.
                return "\(ShotSplit.actionName) would add \(added) clips — each split counted "
                    + "with the linked clip it also cuts — more than this project has room "
                    + "for: \(room) more clip\(room == 1 ? "" : "s") would fit, out of "
                    + "\(Int(RC_MAX_CLIPS))."
            case .notCached(let media):
                return "The shot analysis of media \(media) is no longer in the project's "
                    + "cache; choose \(ShotSplit.actionName) again."
            }
        }
    }

    // MARK: - Targets

    /// Whether `clip` is a target: a media clip whose media is a video with
    /// pictures, its picture switched on.
    static func qualifies(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard case .media(let id, _, _) = clip.source, clip.enabled.video,
            let media = snapshot.media(id)
        else { return false }
        return media.kind == .video && media.hasVideo
    }

    /// Every target on an unlocked track: the tool's `clips` left out.
    static func unlockedCandidates(in snapshot: ProjectSnapshot) -> [UInt32] {
        snapshot.clips.filter { clip in
            snapshot.track(clip.track).map { !$0.locked } == true && qualifies(clip, in: snapshot)
        }.map(\.id)
    }

    /// The targets among `ids` in `project` (the edited, scoped one), and the
    /// ids skipped.
    static func targets(_ ids: [UInt32], in project: ReelProject)
        -> (targets: [Target], skipped: [UInt32])
    {
        let snapshot = project.snapshot
        var targets: [Target] = []
        var skipped: [UInt32] = []
        for id in ids where !targets.contains(where: { $0.clip.id == id }) {
            guard let clip = snapshot.clip(id), qualifies(clip, in: snapshot),
                let media = snapshot.media(for: clip)
            else {
                if !skipped.contains(id) { skipped.append(id) }
                continue
            }
            targets.append(Target(
                clip: clip, media: media,
                times: AnalysisClipTimes(clip: clip, media: media, map: project.sourceMap(id))))
        }
        return (targets, skipped)
    }

    // MARK: - Wants

    /// The requests the targets still need, one per media in first-target
    /// order: each target's window asked of the store, a media's misses
    /// merged into one request. Empty when every window is a hit. Main
    /// thread; throws `analysisRequest`'s errors.
    static func wants(_ targets: [Target], in document: ProjectDocument) throws -> [Want] {
        var order: [UInt32] = []
        var groups: [UInt32: [Target]] = [:]
        for target in targets {
            if groups[target.media.id] == nil { order.append(target.media.id) }
            groups[target.media.id, default: []].append(target)
        }
        var wants: [Want] = []
        for id in order {
            let group = groups[id] ?? []
            guard let media = group.first?.media else { continue }
            let spans = group.map(\.times.window)
            var misses: [AnalysisRequest] = []
            for window in spans {
                if let request = try document.analysisRequest(
                    kind: .shots, media: media, window: window)
                {
                    misses.append(request)
                }
            }
            guard let first = misses.first else { continue }
            let request = AnalysisRequest(
                kind: first.kind, cacheDir: first.cacheDir, media: first.media, url: first.url,
                stamp: first.stamp, input: first.input,
                ranges: AnalysisStore.merged(misses.flatMap(\.ranges)))
            wants.append(Want(media: media, request: request))
        }
        return wants
    }

    // MARK: - The plan

    /// The ops and what they cut, from the store. Main thread. Throws
    /// `notCached` when a window misses again, `ceiling` when the splits
    /// would pass the clip ceiling, and `analysisRequest`'s errors.
    static func plan(_ targets: [Target], in document: ProjectDocument) throws -> Plan {
        if let missing = try wants(targets, in: document).first {
            throw Refusal.notCached(missing.media.id)
        }
        guard let cacheDir = document.cacheDirectory else {
            throw ProjectDocument.AnalysisRequestError.noCache
        }
        let edited = document.editedProject.snapshot
        let fps = edited.canvas.fps
        let frame = fps.frameDuration
        var records: [UInt32: [AnalysisShots.Record]] = [:]
        var ops: [ReelOp] = []
        var cuts: [(clip: UInt32, at: [Ticks])] = []
        var added = 0
        for target in targets {
            let clip = target.clip
            let grid = AnalysisGrid(media: target.media)
            let held = records[target.media.id] ?? AnalysisShots.decode(
                AnalysisStore.readPayload(
                    .shots, media: target.media.id, file: AnalysisShots.payloadName,
                    in: cacheDir) ?? Data(),
                count: grid.count)
            records[target.media.id] = held
            guard let window = grid.indices(
                from: target.times.window.lowerBound, to: target.times.window.upperBound)
            else { continue }
            var times = Set<Ticks>()
            for k in AnalysisShots.cuts(held, in: window) {
                let time = target.times.clipTime(ofSource: held[k].pts)
                let t = ReelTime.snapToFrame(clip.start + time, fps: fps)
                if t - clip.start <= frame || clip.end - t <= frame { continue }
                times.insert(t)
            }
            guard !times.isEmpty else { continue }
            let partner = clip.linked.flatMap { edited.clip($0) }.flatMap { other in
                other.linked == clip.id && edited.track(other.track).map { !$0.locked } == true
                    ? other : nil
            }
            for t in times {
                added += 1
                if let partner, partner.start < t, t < partner.end { added += 1 }
            }
            let sorted = times.sorted()
            cuts.append((clip: clip.id, at: sorted))
            ops += sorted.reversed().map { ReelOp.split(clips: [clip.id], at: $0) }
        }
        let room = Int(RC_MAX_CLIPS) - clipCount(document.project.snapshot)
        guard added <= room else { throw Refusal.ceiling(added: added, room: max(0, room)) }
        return Plan(ops: ops, cuts: cuts, added: added)
    }

    /// Every clip the core's `check_caps` counts: the top level's and every
    /// nest's. Only ever handed the UNSCOPED project's snapshot.
    static func clipCount(_ snapshot: ProjectSnapshot) -> Int {
        snapshot.clips.count + snapshot.nests.reduce(0) { $0 + $1.clips.count }
    }
}
