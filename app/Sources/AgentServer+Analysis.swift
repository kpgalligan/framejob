import Foundation

/// `get_media_analysis` (spec §11 CJ-25; road map "creator-jobs" CJ2a): any
/// analysis kind of one media or clip, made on this Mac or read from its
/// cache — `shots`, the hard cuts, first, `masks`, the person masks' runs
/// (CO1, spec §11 CO-14, `AgentServer+AnalysisMasks.swift`), and `faces`, the
/// face samples (CJ3, spec §11 CJ-34, `AgentServer+AnalysisFaces.swift`),
/// and `sound_events`, Sound Analysis' groups per window (FC3, spec §11
/// FC-33, `AgentServer+AnalysisSoundEvents.swift`).
/// `get_transcript`'s counterpart for pictures and sounds.
///
/// An APP-STATE tool and a read: nothing is edited and no undo step is made.
/// **It runs on the SERVER thread** (`creatorOffMainTools`), for
/// `get_transcript`'s reason: a job runs seconds to a minute. ONE main-thread
/// hop resolves the document, the arguments, the cache folder, the file and
/// the request; the call wants it under an owner of its own (alive while the
/// document is open and the assistant's Stop has not been pressed), waits
/// HOLDING the agent lane's lock as `get_transcript` does, and releases the
/// owner on every exit. After the wait it reads captured values only, but for
/// the summary's last hop.
extension AgentServer {

    /// What the one main-thread hop resolves.
    struct AnalysisCall {
        let document: ProjectDocument
        let kind: AnalysisKind
        let media: MediaSnapshot
        let clip: AnalysisClipTimes?
        let from: Ticks
        let to: Ticks
        let request: AnalysisRequest?
        let cacheDir: URL
    }

    /// `get_media_analysis` — refused in CJ-25's order: not exactly one of
    /// `media` and `clip`; an unknown id; not a media clip; for
    /// `sound_events` a reversed clip (FC-33); a media with no moving picture
    /// (a picture kind) or no sound (`sound_events`); the file missing; `to` ≤ `from`; the wait's bound;
    /// the answer's cap.
    func getMediaAnalysis(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "get_media_analysis must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveAnalysisCall(a) }
        let lane = AnalysisLane.shared
        var ran: AnalysisRun?
        if let request = call.request {
            let owner = lane.newOwner()
            defer { lane.release(owner: owner) }
            let document = call.document
            lane.want(
                [request], owner: owner,
                alive: { document.isOpenForAnalysis && !(stop?.isCancelled ?? false) },
                settled: { document.packageContentsDidChangeOnDisk() })
            let outcome = lane.wait(
                for: [request], owner: owner,
                deadline: Date().addingTimeInterval(AnalysisLane.callWaitLimit),
                cancelled: { stop?.isCancelled ?? false })
            switch outcome {
            case .landed: ran = lane.run(of: request)
            case .failed(let why):
                throw ToolError(
                    message: "The \(call.kind.rawValue) analysis of media \(call.media.id) "
                        + "failed: \(why).")
            case .cancelled:
                throw ToolError(
                    message: "The \(call.kind.rawValue) analysis of media \(call.media.id) was "
                        + "stopped before it finished.")
            case .timedOut:
                throw ToolError(message: Self.timedOutSentence(call))
            }
        }
        var result = try Self.analysisAnswer(call, ran: ran)
        return try onMain {
            result["project"] = self.summary(call.document)
            return try self.jsonResult(result)
        }
    }

    // MARK: - The main-thread hop

    private func resolveAnalysisCall(_ a: [String: Any]) throws -> AnalysisCall {
        func given(_ key: String) -> Bool { a[key] != nil && !(a[key] is NSNull) }
        guard given("media") != given("clip") else {
            throw ToolError(
                message: "Name exactly one of media and clip: the media file to analyse, or "
                    + "the clip whose part of its media to analyse.")
        }
        let name = try requiredString(a, "kind")
        guard let kind = AnalysisKind(rawValue: name) else {
            let kinds = AnalysisKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw ToolError(message: "kind must be one of \(kinds).")
        }
        let document = try target(a)
        let media: MediaSnapshot
        var clip: AnalysisClipTimes?
        if given("clip") {
            let snapshot = try clipArg(a, "clip", document)
            guard case .media(let id, _, _) = snapshot.source,
                let entry = document.editedProject.snapshot.media(id)
            else {
                throw ToolError(
                    message: "Clip \(snapshot.id) is not a media clip (it shows "
                        + "\(snapshot.source.kindName)), so it has no media to analyse.")
            }
            guard !(kind == .soundEvents && snapshot.source.isReversed) else {
                throw ToolError(
                    message: "Clip \(snapshot.id) plays in reverse, so its sound events are "
                        + "not read: its sound plays backwards.")
            }
            media = entry
            clip = AnalysisClipTimes(
                clip: snapshot, media: entry,
                map: document.editedProject.sourceMap(snapshot.id))
        } else {
            media = try mediaArg(a, "media", document)
        }
        if kind.usesSoundQueue {
            guard media.hasAudio else {
                throw ToolError(
                    message: "Media \(media.id) has no sound, so it has no \(kind.rawValue) to "
                        + "find.")
            }
        } else {
            guard media.kind == .video, media.hasVideo else {
                throw ToolError(
                    message: "Media \(media.id) has no moving picture, so it has no "
                        + "\(kind.rawValue) to find.")
            }
        }
        guard document.mediaURLs()[media.id] != nil else {
            throw ToolError(
                message: "Media \(media.id)'s file is missing. relink_media points it at the "
                    + "file.")
        }
        let bounds = clip?.window ?? (0...max(0, media.duration))
        let from = min(max(try intArg(a, "from").map { Ticks($0) } ?? bounds.lowerBound,
                           bounds.lowerBound), bounds.upperBound)
        let to = min(max(try intArg(a, "to").map { Ticks($0) } ?? bounds.upperBound,
                         bounds.lowerBound), bounds.upperBound)
        guard to > from else {
            throw ToolError(
                message: "to (\(to)) must be after from (\(from)), in the media's source ticks"
                    + (clip == nil ? "." : ", inside the clip's window \(bounds.lowerBound)…"
                        + "\(bounds.upperBound)."))
        }
        guard let cacheDir = document.cacheDirectory else {
            throw ToolError(message: "The project has no cache folder to keep the analysis in.")
        }
        let request: AnalysisRequest?
        do {
            request = try document.analysisRequest(kind: kind, media: media, window: from...to)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return AnalysisCall(
            document: document, kind: kind, media: media, clip: clip, from: from, to: to,
            request: request, cacheDir: cacheDir)
    }

    // MARK: - The answer, from captured values

    /// The answer's cap on its `cuts`, `runs` and `samples` (CJ-25, CO-14,
    /// CJ-34).
    static let analysisAnswerCap = 512 * 1024

    /// The common fields (`ok`, `kind`, `media`, `clip`, `from`, `to`,
    /// `size`, `cached`, `stamp`, `run`) and the kind's own.
    private static func analysisAnswer(_ call: AnalysisCall, ran: AnalysisRun?) throws
        -> [String: Any]
    {
        let marker = AnalysisStore.readMarker(call.kind, media: call.media.id, in: call.cacheDir)
        var result: [String: Any] = [
            "ok": true, "kind": call.kind.rawValue, "media": Int(call.media.id),
            "from": call.from, "to": call.to, "size": [call.media.width, call.media.height],
            "cached": call.request == nil,
        ]
        switch call.kind {
        case .shots: result.merge(try shotsFields(call)) { _, kind in kind }
        case .masks: result.merge(try masksFields(call)) { _, kind in kind }
        case .faces: result.merge(try facesFields(call)) { _, kind in kind }
        case .soundEvents: result.merge(try soundEventsFields(call)) { _, kind in kind }
        }
        if let clip = call.clip { result["clip"] = Int(clip.id) }
        if marker?.canned == true {
            result["stamp"] = NSNull()
            result["canned"] = true
        } else if let stamp = marker?.stamp,
            let object = try? JSONSerialization.jsonObject(
                with: JSONEncoder().encode(stamp))
        {
            result["stamp"] = object
        }
        if let ran {
            var run: [String: Any] = ["queued_at": ran.queuedAt]
            if let started = ran.startedAt { run["started_at"] = started }
            if let ended = ran.endedAt { run["ended_at"] = ended }
            result["run"] = run
        }
        return result
    }

    /// `shots`' fields: `count` and `cuts`, refused past the cap.
    private static func shotsFields(_ call: AnalysisCall) throws -> [String: Any] {
        let grid = AnalysisGrid(media: call.media)
        let data =
            AnalysisStore.readPayload(
                call.kind, media: call.media.id, file: AnalysisShots.payloadName,
                in: call.cacheDir) ?? Data()
        let records = AnalysisShots.decode(data, count: grid.count)
        let window = grid.indices(from: call.from, to: call.to)
        let frames = window.map { AnalysisShots.cuts(records, in: $0) } ?? []
        let cuts = frames.map { k -> [String: Any] in
            var row: [String: Any] = ["frame": k, "source": records[k].pts]
            if let clip = call.clip {
                let time = clip.clipTime(ofSource: records[k].pts)
                row["clip_time"] = time
                row["timeline"] = clip.start + time
            }
            return row
        }
        let encoded = try JSONSerialization.data(withJSONObject: cuts)
        if encoded.count > analysisAnswerCap {
            var size = 2
            var fits = call.from
            for row in cuts {
                size += (try JSONSerialization.data(withJSONObject: row)).count + 1
                if size > analysisAnswerCap {
                    fits = (row["source"] as? Int64) ?? call.from
                    break
                }
            }
            throw ToolError(
                message: "The cuts from \(call.from) to \(call.to) come to \(encoded.count) "
                    + "bytes of JSON, more than the \(analysisAnswerCap) an answer holds; call "
                    + "with to at most \(fits) from from \(call.from).")
        }
        return ["count": cuts.count, "cuts": cuts]
    }

    /// The bound's sentence: how much of the window is covered, and to call
    /// again (CJ-25).
    private static func timedOutSentence(_ call: AnalysisCall) -> String {
        let grid = call.kind.grid(of: call.media)
        let window = grid.indices(from: call.from, to: call.to)
        var covered = 0
        if let window, let stamp = call.request?.stamp,
            let marker = AnalysisStore.readMarker(call.kind, media: call.media.id, in: call.cacheDir),
            marker.answers(for: stamp)
        {
            covered = AnalysisStore.coveredCount(window, covered: marker.ranges)
        }
        let seconds = Double(covered) * grid.frameTicks / 600_000
        let total = Double(call.to - call.from) / 600_000
        return String(
            format: "The %@ analysis of media %u covered %.1f s of the window's %.1f s in the "
                + "%.0f s a call waits; what it covered is kept — call again to continue.",
            call.kind.rawValue, call.media.id, seconds, total, AnalysisLane.callWaitLimit)
    }

    // MARK: - split_at_shots

    /// `split_at_shots {clips?}` (spec §11 CJ-29; road map "creator-jobs"
    /// CJ2b) — mirrors Clip ▸ Split at Shot Changes
    /// (`EditorViewController+ShotSplit.swift`) through the same planner,
    /// `ShotSplit`, with no Analyzing sheet: it waits instead (CJ-28).
    /// `get_media_analysis`'s shape, on the server thread: one main hop
    /// resolves the document, the targets and what the store misses; the call
    /// wants that under an owner of its own and waits holding the agent
    /// lane's lock, at most `AnalysisLane.callWaitLimit`; a last main hop
    /// checks the project and scope are still the ones it read, plans and
    /// edits as one undo step. An app-state composite of `split`: no `scope`
    /// key; it acts in the document's current scope.
    func splitAtShots(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "split_at_shots must run on the server thread — its name is missing "
                    + "from AgentServer.creatorOffMainTools.")
        }
        let (document, targets, skipped, wants, asked, scope) = try onMain {
            let document = try target(a)
            let named = try optionalClipsArg(a, "clips", document)
            let ids = named ?? ShotSplit.unlockedCandidates(in: document.editedProject.snapshot)
            let (targets, skipped) = ShotSplit.targets(ids, in: document.editedProject)
            guard !targets.isEmpty else {
                throw ToolError(
                    message: ShotSplit.Refusal.nothingToSplit(named: named != nil)
                        .localizedDescription)
            }
            let wants: [ShotSplit.Want]
            do {
                wants = try ShotSplit.wants(targets, in: document)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            return (document, targets, skipped, wants, document.project, document.scope)
        }
        if !wants.isEmpty {
            try waitForShots(wants, document: document, stop: stop)
        }
        return try onMain {
            guard document.project === asked, document.scope == scope else {
                throw ToolError(
                    message: "the project changed while \(ShotSplit.actionName) was analyzing, "
                        + "so nothing was split. Call split_at_shots again.")
            }
            let plan: ShotSplit.Plan
            do {
                plan = try ShotSplit.plan(targets, in: document)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            let fields: [String: Any] = [
                "cuts": plan.cuts.map { ["clip": Int($0.clip), "at": $0.at] as [String: Any] },
                "added": plan.added, "skipped": skipped.map { Int($0) }, "cached": wants.isEmpty,
            ]
            guard !plan.ops.isEmpty else {
                var answer = fields
                answer["ok"] = true
                answer["note"] = "no hard cut lies inside the clips' played windows, so nothing "
                    + "was split"
                answer["project"] = summary(document)
                return try jsonResult(answer)
            }
            return try editResult(document, ShotSplit.actionName, plan.ops, fields)
        }
    }

    /// Wants every request under an owner of the call's own and waits;
    /// throws naming the first media not landed when one failed, the call
    /// was stopped, or the bound passed.
    private func waitForShots(
        _ wants: [ShotSplit.Want], document: ProjectDocument, stop: AgentCallCancel?
    ) throws {
        let lane = AnalysisLane.shared
        let requests = wants.map(\.request)
        let owner = lane.newOwner()
        defer { lane.release(owner: owner) }
        lane.want(
            requests, owner: owner,
            alive: { document.isOpenForAnalysis && !(stop?.isCancelled ?? false) },
            settled: { document.packageContentsDidChangeOnDisk() })
        let outcome = lane.wait(
            for: requests, owner: owner,
            deadline: Date().addingTimeInterval(AnalysisLane.callWaitLimit),
            cancelled: { stop?.isCancelled ?? false })
        let open = wants.first { lane.run(of: $0.request)?.outcome != .landed } ?? wants[0]
        let media = open.media.id
        switch outcome {
        case .landed: return
        case .failed(let why):
            throw ToolError(message: "The shots analysis of media \(media) failed: \(why).")
        case .cancelled:
            throw ToolError(
                message: "The shots analysis of media \(media) was stopped before it finished, "
                    + "so nothing was split.")
        case .timedOut:
            throw ToolError(
                message: "The shots analysis of media \(media) did not finish in the "
                    + "\(Int(AnalysisLane.callWaitLimit)) s a call waits; what it covered is "
                    + "kept — call split_at_shots again to continue.")
        }
    }
}
