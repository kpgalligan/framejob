import AppKit

/// `new_project_from_range` (spec §11 CJ-52; road map "creator-jobs" CJ5b),
/// mirroring File ▸ New Project from Range…
/// (`EditorViewController+NewFromRange.swift`): the top-level timeline's
/// `[from, to)` opened as a new project through `ProjectDocument.derived(…)`,
/// with the kept media's caches and the drawn graphics carried. Saved at
/// `path` when given, as `new_project` saves; untitled and dirty otherwise.
/// The source document never changes, so it makes no undo step there.
extension AgentServer {

    /// Runs on the server thread (`creatorOffMainTools`), its body one main
    /// hop: the target, the nest refusal, the times, the path's refusals,
    /// then the door.
    func newProjectFromRange(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "new_project_from_range must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let path = try stringArg(a, "path")
        let display = Self.derivedDisplay
        return try onMain {
            let document = try target(a)
            guard document.scope == nil else {
                throw ToolError(
                    message: "new_project_from_range works on the top-level timeline: set_scope "
                        + "with no nest first.")
            }
            let from = try timeArg(a, "from", document)
            let to = try timeArg(a, "to", document)
            let url = path.map {
                Self.destinationURL($0, extension: ProjectDocument.projectFileExtension)
            }
            if let url {
                try refuseHeldPath(url, except: nil, tool: "new_project_from_range")
                guard !FileManager.default.fileExists(atPath: url.path) else {
                    throw ToolError(
                        message: "\(url.path) already exists, so new_project_from_range did not "
                            + "write there: pass a new path.")
                }
            }
            let made: (document: ProjectDocument, carried: DerivedCarry.Report)
            do {
                made = try ProjectDocument.derived(
                    from: document, handle: document.project, range: (from: from, to: to),
                    path: url, display: display, name: "\(document.displayStem) (range)")
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            var result: [String: Any] = [
                "project": summary(made.document),
                "carried": [
                    "files": made.carried.files, "bytes": made.carried.bytes,
                    "seconds": made.carried.seconds,
                ],
            ]
            if let url { result["saved"] = url.path }
            return try jsonResult(result)
        }
    }

    #if FRAMEJOB_DEV_TOOLS
    /// The dev-only launch default that opens the derived document with no
    /// window (`display: false`), so a proof can see the windowless door.
    static let derivedHiddenKey = "RCDevDerivedHidden"
    #endif

    /// True but under `-RCDevDerivedHidden YES` in a build with the dev tools.
    private static var derivedDisplay: Bool {
        #if FRAMEJOB_DEV_TOOLS
        return !UserDefaults.standard.bool(forKey: derivedHiddenKey)
        #else
        return true
        #endif
    }
}
