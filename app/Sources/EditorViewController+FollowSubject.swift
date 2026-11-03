import AppKit

/// Clip ▸ Follow Subject… (road map "creator-jobs" VR2b2, spec §11 VR-29) — the menu door over
/// `reframe_clip`: the selection's targets (`FollowSubject.targets`), the sheet
/// (`FollowSubjectSheetController`), and, when the sheet's Follow needs an analysis made, the
/// Analyzing sheet and the commit. The sheet commits itself when nothing is missing, or for
/// Center, which never analyzes.
///
/// The Analyzing sheet's hand-back is not an AppKit event, so the plan goes through
/// `performGroupedEdit` (Split at Shot Changes' shape), and only onto the project handle and
/// scope the hand-off read: a changed project is refused in VR-29 (d)'s sentence. The subjects
/// are read off main, then the project is checked again. Every refusal beeps and puts its
/// sentence at the inspector's foot (spec §11 CI-10).
extension EditorViewController {

    @objc func showFollowSubjectSheet(_ sender: Any?) {
        guard let document, view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let targets = FollowSubject.targets(document.selection, in: document.editedProject)
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }
        presentAsSheet(
            FollowSubjectSheetController(document: document, clips: targets) {
                [weak self, weak document] settings, requests in
                guard let self, let document else { return }
                self.analyzeForFollow(
                    settings, requests: requests, targets: targets, document: document)
            })
    }

    /// The sheet's hand-off: the Analyzing sheet over every missing request, one row each.
    private func analyzeForFollow(
        _ settings: FollowSubjectSettings, requests: [AnalysisRequest], targets: [UInt32],
        document: ProjectDocument
    ) {
        guard view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let asked = document.project
        let scope = document.scope
        let rows = requests.map {
            AnalyzingSheetController.Row(name: FollowSubject.rowName($0), request: $0)
        }
        presentAsSheet(
            AnalyzingSheetController(
                document: document, command: FollowSubject.actionName, rows: rows
            ) { [weak self, weak document] outcome in
                guard let self, let document else { return }
                self.finishFollow(
                    outcome, rows: rows, settings: settings, targets: targets, asked: asked,
                    scope: scope, document: document)
            })
    }

    /// The Analyzing sheet's answer: refused when the project or scope changed, a failed
    /// analysis named; else the subjects read off main and the plan committed.
    private func finishFollow(
        _ outcome: AnalyzingSheetController.Outcome, rows: [AnalyzingSheetController.Row],
        settings: FollowSubjectSettings, targets: [UInt32], asked: ReelProject, scope: UInt32?,
        document: ProjectDocument
    ) {
        guard document.project === asked, document.scope == scope else {
            refuseFollow(Self.followChanged, document: document)
            return
        }
        switch outcome {
        case .failed(let name, let why):
            let request = rows.first { $0.name == name }?.request
            let kind = request?.kind.rawValue ?? "framing"
            let file = request?.media.name ?? name
            refuseFollow("The \(kind) analysis of “\(file)” failed: \(why).", document: document)
        case .landed:
            guard let cacheDir = document.cacheDirectory else {
                refuseFollow(
                    ProjectDocument.AnalysisRequestError.noCache.localizedDescription,
                    document: document)
                return
            }
            let project = document.editedProject
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak document] in
                let subjects = FollowSubject.subjects(targets, in: project, cacheDir: cacheDir)
                DispatchQueue.main.async {
                    guard let self, let document else { return }
                    guard document.project === asked, document.scope == scope else {
                        self.refuseFollow(Self.followChanged, document: document)
                        return
                    }
                    self.commitFollow(
                        targets, subjects: subjects, settings: settings, document: document)
                }
            }
        }
    }

    /// The plan on the current handle, as one explicit undo group; nothing framed is refused
    /// with the summary's lines.
    private func commitFollow(
        _ targets: [UInt32], subjects: [UInt32: [String: Any]], settings: FollowSubjectSettings,
        document: ProjectDocument
    ) {
        let answer: FollowSubject.Answer
        do {
            answer = try FollowSubject.plan(
                targets, subjects: subjects, settings: settings, project: document.editedProject)
        } catch {
            refuseFollow(error.localizedDescription, document: document)
            return
        }
        switch answer {
        case .refused(let why):
            refuseFollow(why, document: document)
        case .plan(let plan) where plan.ops.isEmpty:
            refuseFollow(FollowSubject.summary(plan), document: document)
        case .plan(let plan):
            document.performGroupedEdit(FollowSubject.actionName, plan.ops)
        }
    }

    private static let followChanged =
        "the project changed while \(FollowSubject.actionName) was analyzing, so nothing was "
        + "framed. Choose \(FollowSubject.actionName) again."

    /// A beep and the sentence at the inspector's foot.
    private func refuseFollow(_ reason: String, document: ProjectDocument) {
        NSSound.beep()
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: "reframe_clip", reason: reason)])
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any other
    /// action. On when a selected clip of the edited container has a moving picture and no
    /// sheet is on the window; allowed inside a nest.
    func validateFollowSubjectAction(_ action: Selector) -> Bool? {
        guard action == #selector(showFollowSubjectSheet(_:)) else { return nil }
        guard let document, view.window?.attachedSheet == nil else { return false }
        return !FollowSubject.targets(document.selection, in: document.editedProject).isEmpty
    }
}
