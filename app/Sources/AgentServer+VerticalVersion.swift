import Foundation

/// `make_vertical_version` (spec §11 VR-36, VR-37; road map "creator-jobs" VR3a): the project's
/// 9:16, 4:5 or 1:1 version made by `VerticalVersion.plan`, opened as a copy through
/// `ProjectDocument.verticalCopy` (the default; saved at `path` when given) or, with
/// `copy: false`, applied to the addressed project in place as one undo step "Make Vertical".
/// Its UI path is File ▸ Make Vertical Version… (road map creator-jobs VR3b, spec §11 VR-39:
/// `EditorViewController+VerticalVersion.swift` and `VerticalVersionSheetController.swift`). It
/// never asks the person and reads no `UserDefaults`.
///
/// **Runs on the SERVER thread** (`creatorOffMainTools`), in hops:
/// - the first main hop resolves and refuses in VR-36's order, runs a DRY plan with no
///   subjects (so the core's own error for a bad argument is answered before any analysis is
///   asked for) and, for a following kind, asks `FramingAnalysis.requests` on the SOURCE over
///   the media pictures whose file is present (VR-37);
/// - the wait is `reframe_clip`'s (`waitForAnalysis`); past CJ-25's bound the answer is
///   `analyzing` and nothing is made; the subjects are read off main from the source's cache;
/// - the last main hop refuses a changed project or scope, plans on the current handle and
///   applies in place or opens the copy; with `path` the copy is saved on the server thread.
///
/// A media picture whose media has a cursor file (`analysisTargets`' `cursor`, spec §11 VR-51)
/// is never analysed: its cursor is read off main beside the analysis's subjects
/// (`FramingCursor.subjects`), and the plan follows it with `replace: true` (VR-52).
///
/// `follow: speaker` (road map creator-jobs VR6b, spec §11 VR-64) takes `mics` and `mic_faces`,
/// analyses as a following kind does, and frames each speaker clip (`VerticalVersion.speakerClips`)
/// on whoever is talking: the last main hop fills their turns (`VerticalVersion.withTurns`,
/// Switch by Speaker's reading), a `FramingSpeaker.Refusal` refusing the call, and the answer
/// carries `speaker`. Its UI path is the sheet's Follow Speaker.
extension AgentServer {

    /// What the first main hop resolves.
    private struct VerticalCall {
        let document: ProjectDocument
        let settings: VerticalSettings
        let copy: Bool
        let url: URL?
        /// Media pictures whose media file is missing (kept, not followed).
        let missing: Set<UInt32>
        /// The media pictures whose subjects are read: the following kinds' only.
        let targets: [UInt32]
        /// The media pictures whose cursor is read (VR-51): the following kinds' only.
        let cursor: [UInt32]
        let requests: [AnalysisRequest]
        let cacheDir: URL?
        let asked: ReelProject
        let scope: UInt32?
    }

    /// The last main hop's answer: in place, the finished answer; a copy, the document.
    private enum VerticalOutcome {
        case applied(String)
        case copied(
            (
                document: ProjectDocument, carried: DerivedCarry.Report,
                templates: VerticalVersion.TemplateReport
            ))
    }

    #if FRAMEJOB_DEV_TOOLS
    /// The dev-only launch default naming a `path`'s last component whose save fails, so a proof
    /// can see the copy closed and its package removed (#460).
    static let verticalSaveFaultKey = "RCDevVerticalSaveFault"
    #endif

    func makeVerticalVersion(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "make_vertical_version must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveVertical(a) }
        var subjects: [UInt32: [String: Any]] = [:]
        if !call.requests.isEmpty {
            let clips = call.targets.count
            if let analyzing = try waitForAnalysis(
                call.requests, document: call.document, stop: stop, unmade: "nothing was made",
                note: { percent in
                    "Still analyzing the media of \(clips) \(clips == 1 ? "clip" : "clips") "
                        + "(\(percent) %); call make_vertical_version again to make the version."
                })
            {
                return analyzing
            }
        }
        if let cacheDir = call.cacheDir, !call.targets.isEmpty {
            subjects = FollowSubject.subjects(call.targets, in: call.asked, cacheDir: cacheDir)
        }
        subjects.merge(FramingCursor.subjects(call.cursor, in: call.asked)) { _, new in new }
        var fields: [String: Any] = ["cached": call.requests.isEmpty]
        let outcome: VerticalOutcome = try onMain {
            let document = call.document
            guard document.project === call.asked, document.scope == call.scope else {
                throw ToolError(
                    message: "the project changed while make_vertical_version read the "
                        + "analysis, so nothing was made. Call make_vertical_version again.")
            }
            // VR-64 (d): who talks when, read on this hop from the microphones' caches.
            var filled = subjects
            do {
                filled = try VerticalVersion.withTurns(
                    subjects,
                    speaker: VerticalVersion.speakerClips(
                        document.project, settings: call.settings, missing: call.missing),
                    document: document)
            } catch let refusal as FramingSpeaker.Refusal {
                throw ToolError(message: "make_vertical_version was refused: " + refusal.sentence)
            }
            let plan = try self.verticalPlan(
                document.project, call.settings, subjects: filled, missing: call.missing)
            guard call.copy else {
                // In place nothing is written: the old template copies are listed (VR-44 (c)).
                let survey = VerticalVersion.templateSurvey(
                    document.project, store: document.graphicStore)
                fields.merge(
                    VerticalVersion.answerFields(
                        plan, templates: VerticalVersion.templateReport(survey, copy: false))
                ) { _, new in new }
                return .applied(
                    try self.editResult(document, VerticalVersion.actionName, plan.ops, fields))
            }
            do {
                let made = try ProjectDocument.verticalCopy(
                    from: document, plan: plan, shape: call.settings.shape, path: call.url,
                    display: Self.derivedDisplay)
                // The copy's own report: what it updated and what it listed.
                fields.merge(VerticalVersion.answerFields(plan, templates: made.templates)) {
                    _, new in new
                }
                return .copied(made)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
        }
        let made: (
            document: ProjectDocument, carried: DerivedCarry.Report,
            templates: VerticalVersion.TemplateReport
        )
        switch outcome {
        case .applied(let answer): return answer
        case .copied(let copy): made = copy
        }
        if let url = call.url {
            // A failed save leaves nothing behind: the copy closed and its package removed, as
            // `verticalCopy` does for a copy the step did not change (#460).
            do {
                #if FRAMEJOB_DEV_TOOLS
                if let fault = UserDefaults.standard.string(forKey: Self.verticalSaveFaultKey),
                    !fault.isEmpty, url.lastPathComponent == fault
                {
                    throw ToolError(
                        message: "\(url.lastPathComponent) could not be saved (the "
                            + "\(Self.verticalSaveFaultKey) fault).")
                }
                #endif
                try save(made.document, to: url, operation: .saveOperation)
            } catch {
                onMain { made.document.close() }
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            fields["saved"] = url.path
        }
        return try onMain {
            var result: [String: Any] = ["ok": true]
            result.merge(fields) { _, new in new }
            result["carried"] = [
                "files": made.carried.files, "bytes": made.carried.bytes,
                "seconds": made.carried.seconds,
            ]
            result["project"] = self.summary(made.document)
            return try self.jsonResult(result)
        }
    }

    /// The plan on `project`, its refusal thrown in the step's own sentence and the core's
    /// invalid input as its message. Main thread.
    private func verticalPlan(
        _ project: ReelProject, _ settings: VerticalSettings, subjects: [UInt32: [String: Any]],
        missing: Set<UInt32>
    ) throws -> VerticalVersion.Plan {
        let answer: VerticalVersion.Answer
        do {
            answer = try VerticalVersion.plan(
                project, settings: settings, subjects: subjects, missing: missing)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        switch answer {
        case .plan(let plan): return plan
        case .refused(let why): throw ToolError(message: why)
        }
    }

    /// VR-36's first hop, its refusals in order.
    private func resolveVertical(_ a: [String: Any]) throws -> VerticalCall {
        let document = try target(a)
        let shape = try requiredEnumArg(a, "shape", VerticalShape.self)
        var follow = FramingFollow.subject
        if let raw = try stringArg(a, "follow") {
            guard let kind = FramingFollow(rawValue: raw), VerticalVersion.follows.contains(kind)
            else {
                throw ToolError(
                    message: "follow must be subject, face, person, salient, speaker or center, "
                        + "not \(raw).")
            }
            follow = kind
        }
        let zoom = try doubleArg(a, "zoom") ?? 1
        let whereEmpty = try enumArg(a, "where_empty", FramingWhereEmpty.self) ?? .fit
        let copy = try boolArg(a, "copy") ?? true
        let captions = try boolArg(a, "captions") ?? true
        let path = try stringArg(a, "path")
        guard document.scope == nil else {
            throw ToolError(
                message: "make_vertical_version works on the top-level timeline: set_scope with "
                    + "no nest first.")
        }
        if path != nil, !copy {
            throw ToolError(
                message: "make_vertical_version writes path only for a copy: drop path, or copy.")
        }
        let url = path.map {
            Self.destinationURL($0, extension: ProjectDocument.projectFileExtension)
        }
        if let url {
            try refuseHeldPath(url, except: nil, tool: "make_vertical_version")
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw ToolError(
                    message: "\(url.path) already exists, so make_vertical_version did not "
                        + "write there: pass a new path.")
            }
        }
        let project = document.project
        let canvas = project.snapshot.canvas
        let size = shape.size(from: canvas)
        guard size.width != canvas.width || size.height != canvas.height else {
            throw ToolError(
                message: "the canvas is already \(canvas.width) × \(canvas.height), so there is "
                    + "no \(shape.rawValue) version to make.")
        }
        do {
            if case .refused(let why) = try VerticalVersion.opening(
                project, width: size.width, height: size.height)
            {
                throw ToolError(message: why)
            }
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        // VR-64 (a), (e): the microphones, read only with speaker.
        var mics: [UInt32] = []
        var micFaces: [UInt32]?
        if follow == .speaker {
            guard let given = try numbersArg(a, "mics"), !given.isEmpty else {
                throw ToolError(
                    message: "make_vertical_version's follow speaker needs mics: two to four "
                        + "clips, one on each microphone's track.")
            }
            for id in given { _ = try clipArg(["clip": Int(id)], "clip", document) }
            mics = given
            micFaces = try numbersArg(a, "mic_faces")
        }
        let settings = VerticalSettings(
            shape: shape, follow: follow, zoom: zoom, whereEmpty: whereEmpty, captions: captions,
            mics: mics, micFaces: micFaces)
        let (present, missing, cursor) = VerticalVersion.analysisTargets(
            project, urls: document.mediaURLs())
        if follow == .speaker,
            VerticalVersion.speakerClips(project, settings: settings, missing: missing).isEmpty
        {
            throw ToolError(message: VerticalVersion.noSpeakerClip)
        }
        // The dry plan: the core's error for a bad argument, before any analysis. Its
        // refusal and its plan are discarded.
        do {
            _ = try VerticalVersion.plan(
                project, settings: settings, subjects: [:], missing: missing)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        let analysed = VerticalVersion.analyses(follow)
        let targets = analysed ? present : []
        var requests: [AnalysisRequest] = []
        var cacheDir: URL?
        if !targets.isEmpty {
            guard let folder = document.cacheDirectory else {
                throw ToolError(
                    message: ProjectDocument.AnalysisRequestError.noCache.localizedDescription)
            }
            cacheDir = folder
            do {
                requests = try FramingAnalysis.requests(
                    clips: targets, in: document, project: project)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
        }
        return VerticalCall(
            document: document, settings: settings, copy: copy, url: url, missing: missing,
            targets: targets, cursor: analysed ? cursor : [],
            requests: requests, cacheDir: cacheDir, asked: project, scope: document.scope)
    }

    /// `relay_captions` (road map "creator-jobs" VR4a, spec §11 VR-45): the word caption
    /// tracks of the container `set_scope` has open re-paged on its canvas as one undo step
    /// "Re-lay Captions" — what File ▸ Re-lay Captions for This Canvas does
    /// (`EditorViewController+RelayCaptions.swift`). Main thread; no `scope` argument, since
    /// dispatch reads `scope` only for op names; it plans on `editedProject` and
    /// `performGroupedEdit` addresses the ops.
    func relayCaptions(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let planned: (ops: [ReelOp], outcome: CaptionRelayout.Outcome)
        do {
            planned = try CaptionRelayout.plan(document.editedProject)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        guard !planned.ops.isEmpty else {
            let kept = planned.outcome.kept.map { "\"\($0.name)\": \($0.reason)" }
            throw ToolError(
                message: "relay_captions found no caption track it can re-lay: "
                    + (kept.isEmpty
                        ? "there is no track named Captions holding only text clips"
                        : kept.joined(separator: "; ")))
        }
        return try editResult(
            document, CaptionRelayout.actionName, planned.ops,
            CaptionRelayout.answerFields(planned.outcome))
    }
}
