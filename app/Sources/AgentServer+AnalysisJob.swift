#if FRAMEJOB_DEV_TOOLS
import Foundation

/// `analysis_job`, a DEV TOOL (spec §11 CJ-27; road map "creator-jobs"
/// CJ2a): a proof's stand-in for a document's command owner (CJ2b's
/// Analyzing sheet). The MCP server answers one request at a time, so no
/// call can overlap a held `get_media_analysis`; this tool wants a job and
/// returns at once, and later reads every job a dev owner wanted, with an
/// optional bounded wait.
///
/// One dev owner per document (alive while it is open), each want passing
/// the owner's earlier requests too, so a later want never withdraws an
/// earlier one.
final class AnalysisDevOwners: @unchecked Sendable {
    static let shared = AnalysisDevOwners()

    struct Wanted {
        let project: String?
        let request: AnalysisRequest
    }

    private let lock = NSLock()
    private var owners: [Int: (owner: Int, requests: [AnalysisRequest])] = [:]
    private var wanted: [Wanted] = []

    /// Wants `request` under `recipeKey`'s dev owner, with its earlier ones.
    func want(
        _ request: AnalysisRequest, recipeKey: Int, project: String?, document: ProjectDocument
    ) {
        lock.lock()
        var entry = owners[recipeKey] ?? (AnalysisLane.shared.newOwner(), [])
        if !entry.requests.contains(request) { entry.requests.append(request) }
        owners[recipeKey] = entry
        wanted.append(Wanted(project: project, request: request))
        let requests = entry.requests
        lock.unlock()
        AnalysisLane.shared.want(
            requests, owner: entry.owner,
            alive: { RecipeSource.shared.project(for: recipeKey) != nil },
            settled: { [weak document] in document?.packageContentsDidChangeOnDisk() })
    }

    /// Every request a dev owner wanted since launch, in order.
    var all: [Wanted] {
        lock.lock()
        defer { lock.unlock() }
        return wanted
    }
}

extension AgentServer {

    /// `analysis_job {project?, media? | clips?, kind?, from?, to?, wait?}`
    /// (CJ-27; `clips` and `lane_queued` spec §11 VR-16).
    func analysisJob(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "analysis_job must run on the server thread — its name is missing "
                    + "from AgentServer.devOffMainTools.")
        }
        let waitSeconds = try doubleArg(a, "wait")
        if let waitSeconds, !(0...AnalysisLane.callWaitLimit).contains(waitSeconds) {
            throw ToolError(
                message: "wait must be 0…\(Int(AnalysisLane.callWaitLimit)) seconds.")
        }
        var result: [String: Any] = ["ok": true]
        let named = { (key: String) in a[key] != nil && !(a[key] is NSNull) }
        if named("media"), named("clips") {
            throw ToolError(message: "Name media or clips, not both.")
        }
        if named("clips") {
            // What a VR command analyses (VR-12): every FramingAnalysis request of
            // the clips, wanted under the document's dev owner.
            let made = try onMain { () -> (ProjectDocument, String?, [UInt32], [AnalysisRequest]) in
                let document = try self.target(a)
                let clips = try self.clipsArg(a, "clips", document)
                do {
                    let requests = try FramingAnalysis.requests(clips: clips, in: document)
                    return (document, Self.path(of: document), clips, requests)
                } catch {
                    throw ToolError(message: error.localizedDescription)
                }
            }
            let (document, path, clips, requests) = made
            for request in requests {
                AnalysisDevOwners.shared.want(
                    request, recipeKey: document.recipeKey, project: path, document: document)
            }
            result["wanted"] = [
                "project": path ?? NSNull(), "clips": clips.map { Int($0) },
                "requests": requests.count,
            ] as [String: Any]
        }
        if named("media") {
            let made = try onMain { () -> (ProjectDocument, String?, UInt32, AnalysisRequest?) in
                let document = try self.target(a)
                let media = try self.mediaArg(a, "media", document)
                let name = try self.requiredString(a, "kind")
                guard let kind = AnalysisKind(rawValue: name) else {
                    throw ToolError(message: "kind must be one of "
                        + AnalysisKind.allCases.map(\.rawValue).joined(separator: ", ") + ".")
                }
                if kind.usesSoundQueue {
                    guard media.hasAudio else {
                        throw ToolError(message: "Media \(media.id) has no sound.")
                    }
                } else {
                    guard media.kind == .video, media.hasVideo else {
                        throw ToolError(message: "Media \(media.id) has no moving picture.")
                    }
                }
                let end = max(0, media.duration)
                let from = min(max(try self.intArg(a, "from").map { Ticks($0) } ?? 0, 0), end)
                let to = min(max(try self.intArg(a, "to").map { Ticks($0) } ?? end, 0), end)
                guard to > from else {
                    throw ToolError(message: "to (\(to)) must be after from (\(from)).")
                }
                do {
                    let request = try document.analysisRequest(
                        kind: kind, media: media, window: from...to)
                    return (document, Self.path(of: document), media.id, request)
                } catch {
                    throw ToolError(message: error.localizedDescription)
                }
            }
            let (document, path, mediaID, request) = made
            if let request {
                AnalysisDevOwners.shared.want(
                    request, recipeKey: document.recipeKey, project: path, document: document)
            }
            result["wanted"] = [
                "project": path ?? NSNull(), "media": Int(mediaID), "hit": request == nil,
            ] as [String: Any]
        }
        let lane = AnalysisLane.shared
        if let waitSeconds {
            let deadline = Date().addingTimeInterval(waitSeconds)
            let requests = AnalysisDevOwners.shared.all.map(\.request)
            while Date() < deadline,
                requests.contains(where: { lane.run(of: $0)?.outcome == nil })
            {
                Thread.sleep(forTimeInterval: AnalysisLane.pollInterval)
            }
        }
        result["now"] = ProcessInfo.processInfo.systemUptime
        result["lane_queued"] = lane.queuedTotal()
        result["jobs"] = AnalysisDevOwners.shared.all.map { wanted -> [String: Any] in
            let request = wanted.request
            var row: [String: Any] = [
                "project": wanted.project ?? NSNull(), "media": Int(request.media.id),
                "kind": request.kind.rawValue,
                "ranges": request.ranges.map { [$0.lowerBound, $0.upperBound] },
            ]
            if let run = lane.run(of: request) {
                row["queued_at"] = run.queuedAt
                if let started = run.startedAt { row["started_at"] = started }
                if let ended = run.endedAt { row["ended_at"] = ended }
                switch run.outcome {
                case .landed?: row["outcome"] = "landed"
                case .failed(let why)?:
                    row["outcome"] = "failed"
                    row["error"] = why
                case .cancelled?: row["outcome"] = "cancelled"
                case .timedOut?, nil: break
                }
            }
            return row
        }
        // Every want a cutout made (spec §11 CO-22 (h)): the document's, an export's, a frame's.
        result["mask_wants"] = CutoutWants.logged.map { entry -> [String: Any] in
            let request = entry.request
            var row: [String: Any] = [
                "role": entry.role.rawValue, "owner": entry.owner, "media": Int(request.media.id),
                "kind": request.kind.rawValue,
                "ranges": request.ranges.map { [$0.lowerBound, $0.upperBound] },
                "wanted": lane.requests(of: entry.owner).contains(request),
            ]
            if let run = lane.run(of: request) {
                row["queued_at"] = run.queuedAt
                if let started = run.startedAt { row["started_at"] = started }
                if let ended = run.endedAt { row["ended_at"] = ended }
                switch run.outcome {
                case .landed?: row["outcome"] = "landed"
                case .failed(let why)?:
                    row["outcome"] = "failed"
                    row["error"] = why
                case .cancelled?: row["outcome"] = "cancelled"
                case .timedOut?, nil: break
                }
            }
            return row
        }
        return try jsonResult(result)
    }

    func analysisJobTool() -> [String: Any] {
        tool(
            "analysis_job",
            "DEV TOOL (absent from Distribution builds). A proof's stand-in for a document's "
                + "command owner (the Analyzing sheet, CJ2b), since the MCP server answers one "
                + "request at a time and no call can overlap a held get_media_analysis (spec "
                + "CJ-27). With media (then kind is required; from and to as "
                + "get_media_analysis's media form) it wants that window's missing ranges "
                + "under the document's dev owner — one per document, alive while it is open, "
                + "keeping its earlier wants — and returns at once. With clips instead (spec "
                + "VR-16) it wants what a VR command analyses (FramingAnalysis, VR-12): for "
                + "each media the clips show, the windows they play plus 1 s each side, in "
                + "kinds shots, faces, subjects, answering wanted: {project, clips, requests}; "
                + "kind, from and to are not read with clips. "
                + "With wait (seconds, 0…"
                + "\(Int(AnalysisLane.callWaitLimit))) it then waits until every job a dev "
                + "owner wanted has ended. Answers {ok, now (process uptime), wanted: "
                + "{project, media, hit}, lane_queued (requests the lane queued since "
                + "launch), jobs: [{project, media, kind, ranges, queued_at, "
                + "started_at, ended_at, outcome}], mask_wants: [{role, owner, media, kind, "
                + "ranges, wanted, outcome, error, queued_at, started_at, ended_at}]}: every "
                + "job a dev owner wanted since launch, and every want a cutout made (role "
                + "document, export or frame; wanted while that owner wants it now). Without "
                + "media it targets no document.",
            [
                "media": [
                    "type": "integer", "description": "The media whose window to want.",
                ],
                "clips": [
                    "type": "array", "items": ["type": "integer"],
                    "description": "Clips whose framing analyses to want (not with media).",
                ],
                "kind": [
                    "type": "string", "enum": AnalysisKind.allCases.map(\.rawValue),
                    "description": "The analysis kind; required with media.",
                ],
                "from": [
                    "type": "integer",
                    "description": "The window's start in the media's source ticks (0).",
                ],
                "to": [
                    "type": "integer",
                    "description": "The window's end in the media's source ticks (its end).",
                ],
                "wait": [
                    "type": "number",
                    "description": "Seconds to wait for every dev-wanted job to end.",
                ],
            ])
    }
}
#endif
