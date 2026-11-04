import AppKit

/// File ▸ Make Vertical Version… (road map "creator-jobs" VR3b, spec §11 VR-39) — the menu door
/// over VR3a's step (`VerticalVersion.plan`) and copy (`ProjectDocument.verticalCopy`): the
/// sheet (`VerticalVersionSheetController`), and its hand-off — the Analyzing sheet when an
/// analysis is missing, then the copy opened in front or the step applied in place as one undo
/// step "Make Vertical". `make_vertical_version` is the mirror (`AgentServer+VerticalVersion.swift`).
///
/// The sheet never edits. Its hand-off is not an AppKit event, so the step in place goes through
/// `performGroupedEdit` (Follow Subject's shape), and only onto the project handle and scope the
/// sheet read: a changed project is refused before anything is made, again when the Analyzing
/// sheet lands, and again after the subjects are read off main. Stop is the Analyzing sheet's
/// own and makes nothing. Every refusal beeps and puts its sentence at the inspector's foot
/// (spec §11 CI-10).
extension EditorViewController {

    @objc func showVerticalVersionSheet(_ sender: Any?) {
        guard let document, validateVerticalVersionAction(#selector(showVerticalVersionSheet(_:)))
            == true
        else {
            NSSound.beep()
            return
        }
        presentAsSheet(
            VerticalVersionSheetController(document: document) {
                [weak self, weak document] handOff in
                guard let self, let document else { return }
                self.analyzeForVertical(handOff, document: document)
            })
    }

    /// The sheet's hand-off: refused when the project or scope changed since the sheet read it;
    /// else committed at once, or the Analyzing sheet over every missing request, one row each.
    private func analyzeForVertical(_ handOff: VerticalHandOff, document: ProjectDocument) {
        guard document.project === handOff.asked, document.scope == handOff.scope else {
            refuseVertical(
                handOff.requests.isEmpty ? Self.verticalSheetChanged : Self.verticalChanged,
                document: document)
            return
        }
        guard !handOff.requests.isEmpty else {
            commitVertical(handOff, subjects: handOff.subjects, document: document)
            return
        }
        guard view.window?.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let rows = handOff.requests.map {
            AnalyzingSheetController.Row(name: FollowSubject.rowName($0), request: $0)
        }
        presentAsSheet(
            AnalyzingSheetController(
                document: document, command: VerticalVersion.actionName, rows: rows
            ) { [weak self, weak document] outcome in
                guard let self, let document else { return }
                self.finishVertical(outcome, rows: rows, handOff: handOff, document: document)
            })
    }

    /// The Analyzing sheet's answer: refused when the project or scope changed, a failed
    /// analysis named; else the subjects read off main, checked again, and committed.
    private func finishVertical(
        _ outcome: AnalyzingSheetController.Outcome, rows: [AnalyzingSheetController.Row],
        handOff: VerticalHandOff, document: ProjectDocument
    ) {
        guard document.project === handOff.asked, document.scope == handOff.scope else {
            refuseVertical(Self.verticalChanged, document: document)
            return
        }
        switch outcome {
        case .failed(let name, let why):
            let request = rows.first { $0.name == name }?.request
            let kind = request?.kind.rawValue ?? "framing"
            let file = request?.media.name ?? name
            refuseVertical("The \(kind) analysis of “\(file)” failed: \(why).", document: document)
        case .landed:
            guard let cacheDir = document.cacheDirectory else {
                refuseVertical(
                    ProjectDocument.AnalysisRequestError.noCache.localizedDescription,
                    document: document)
                return
            }
            let targets = handOff.targets
            let cursor = handOff.cursor
            let asked = handOff.asked
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak document] in
                var subjects = FollowSubject.subjects(targets, in: asked, cacheDir: cacheDir)
                // A cursor beside the analysis (spec §11 VR-51).
                subjects.merge(FramingCursor.subjects(cursor, in: asked)) { _, new in new }
                DispatchQueue.main.async {
                    guard let self, let document else { return }
                    guard document.project === handOff.asked, document.scope == handOff.scope
                    else {
                        self.refuseVertical(Self.verticalChanged, document: document)
                        return
                    }
                    self.commitVertical(handOff, subjects: subjects, document: document)
                }
            }
        }
    }

    /// VR-39 (g): the plan again on the current handle, then the copy opened in front, or the
    /// step applied in place as one explicit undo group.
    private func commitVertical(
        _ handOff: VerticalHandOff, subjects: [UInt32: [String: Any]], document: ProjectDocument
    ) {
        let answer: VerticalVersion.Answer
        do {
            answer = try VerticalVersion.plan(
                document.project, settings: handOff.settings, subjects: subjects,
                missing: handOff.missing)
        } catch {
            refuseVertical(error.localizedDescription, document: document)
            return
        }
        let plan: VerticalVersion.Plan
        switch answer {
        case .refused(let why):
            refuseVertical(why, document: document)
            return
        case .plan(let made):
            plan = made
        }
        guard handOff.copy else {
            document.performGroupedEdit(VerticalVersion.actionName, plan.ops)
            return
        }
        do {
            _ = try ProjectDocument.verticalCopy(
                from: document, plan: plan, shape: handOff.settings.shape, path: nil,
                display: true)
        } catch {
            refuseVertical(error.localizedDescription, document: document)
        }
    }

    private static let verticalSheetChanged =
        "the project changed while the Make Vertical Version sheet was open, so nothing was "
        + "made. Choose Make Vertical Version again."

    private static let verticalChanged =
        "the project changed while \(VerticalVersion.actionName) was analyzing, so nothing was "
        + "made. Choose Make Vertical Version again."

    /// A beep and the sentence at the inspector's foot.
    private func refuseVertical(_ reason: String, document: ProjectDocument) {
        NSSound.beep()
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: "set_canvas", reason: reason)])
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case; nil for any other
    /// action. On with a document, no nest open, no sheet on the window, no recording running
    /// and at least one clip in the project (VR-39 (a)).
    func validateVerticalVersionAction(_ action: Selector) -> Bool? {
        guard action == #selector(showVerticalVersionSheet(_:)) else { return nil }
        guard let document else { return false }
        return document.scope == nil && view.window?.attachedSheet == nil
            && !ScreenRecorder.shared.isRecording && !document.project.snapshot.clips.isEmpty
    }
}
