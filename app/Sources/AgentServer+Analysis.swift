import Foundation

/// `get_media_analysis` (spec §11 CJ-25; road map "creator-jobs" CJ2a): any
/// analysis kind of one media or clip, made on this Mac or read from its
/// cache — `shots`, the hard cuts, first. `get_transcript`'s counterpart for
/// pictures and sounds.
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
    private struct AnalysisCall {
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
    /// `media` and `clip`; an unknown id; not a media clip, or a media with
    /// no moving picture; the file missing; `to` ≤ `from`; the wait's bound;
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
            media = entry
            clip = AnalysisClipTimes(
                clip: snapshot, media: entry,
                map: document.editedProject.sourceMap(snapshot.id))
        } else {
            media = try mediaArg(a, "media", document)
        }
        guard media.kind == .video, media.hasVideo else {
            throw ToolError(
                message: "Media \(media.id) has no moving picture, so it has no "
                    + "\(kind.rawValue) to find.")
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

    /// The answer's cap on its `cuts` (CJ-25).
    static let analysisAnswerCap = 512 * 1024

    private static func analysisAnswer(_ call: AnalysisCall, ran: AnalysisRun?) throws
        -> [String: Any]
    {
        let grid = AnalysisGrid(media: call.media)
        let marker = AnalysisStore.readMarker(call.kind, media: call.media.id, in: call.cacheDir)
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
        var result: [String: Any] = [
            "ok": true, "kind": call.kind.rawValue, "media": Int(call.media.id),
            "from": call.from, "to": call.to, "size": [call.media.width, call.media.height],
            "cached": call.request == nil, "count": cuts.count, "cuts": cuts,
        ]
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

    /// The bound's sentence: how much of the window is covered, and to call
    /// again (CJ-25).
    private static func timedOutSentence(_ call: AnalysisCall) -> String {
        let grid = AnalysisGrid(media: call.media)
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
}

/// A clip's played source window and its times (CJ-25): source ticks of the
/// FORWARD media to clip ticks, through its source map when it ramps, its
/// speed when not, and the reversed mirror first when it plays backwards.
struct AnalysisClipTimes {
    let id: UInt32
    let start: Ticks
    let sourceIn: Ticks
    let speed: Double
    let pivot: Ticks?
    let map: SourceMap?
    /// The played window in the forward media's ticks, [lower, upper).
    let window: ClosedRange<Ticks>

    init(clip: ClipSnapshot, media: MediaSnapshot, map: SourceMap?) {
        id = clip.id
        start = clip.start
        speed = clip.speed > 0 && clip.speed.isFinite ? clip.speed : 1
        let ramp = map.flatMap { $0.ramped ? $0 : nil }
        self.map = ramp
        sourceIn = ramp?.sourceIn ?? clip.source.sourceIn
        let length = ramp?.sourceLength ?? Transcriber.contentLength(of: clip)
        pivot = clip.source.isReversed ? media.duration : nil
        let played = sourceIn...(sourceIn + length)
        let forward = pivot.map { ReverseMirror.mirrored(played, about: $0) } ?? played
        let low = min(max(0, forward.lowerBound), media.duration)
        window = low...max(low, min(media.duration, forward.upperBound))
    }

    /// Ticks from the clip's start, in its playing direction, at forward
    /// source tick `source`.
    func clipTime(ofSource source: Int64) -> Ticks {
        let played = pivot.map { ReverseMirror.mirrored(source, about: $0) } ?? source
        if let map { return Ticks(map.clip(atSource: Double(played)).rounded()) }
        return Ticks((Double(played - sourceIn) / speed).rounded())
    }
}
