import AppKit

/// Clip ▸ Split at Shot Changes (spec §11 CJ-28, CJ-29; road map
/// "creator-jobs" CJ2b) — the menu half of `split_at_shots`. The planner is
/// `ShotSplit`, which the tool calls too; this file is the door: the
/// selection's targets, the Analyzing sheet when the shots analysis misses
/// the cache, and the edit.
///
/// With every window cached the split lands at once, in the menu's event
/// (`applyEdit`). Otherwise the sheet makes what is missing; its hand-back
/// is not an AppKit event, so the split goes through `performGroupedEdit`
/// (app/CLAUDE.md's undo pitfall, `finishSynchronizeAudio`'s shape), and
/// only onto the project handle and scope the press read. Nothing to split,
/// no window or a sheet already up beep; a refusal beeps and puts its
/// sentence at the inspector's foot (spec §11 CI-10).
extension EditorViewController {

    @objc func splitAtShotChanges(_ sender: Any?) {
        guard let document, let window = view.window, window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let targets = ShotSplit.targets(selectedClips.map(\.id), in: document.editedProject)
            .targets
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }
        let wants: [ShotSplit.Want]
        do {
            wants = try ShotSplit.wants(targets, in: document)
        } catch {
            refuseShotSplit(error.localizedDescription, document: document)
            return
        }
        guard !wants.isEmpty else {
            commitShotSplit(targets, document: document, grouped: false)
            return
        }
        let asked = document.project
        let scope = document.scope
        let rows = wants.map { AnalyzingSheetController.Row(name: $0.media.name, request: $0.request) }
        presentAsSheet(
            AnalyzingSheetController(
                document: document, command: ShotSplit.actionName, rows: rows
            ) { [weak self, weak document] outcome in
                guard let self, let document else { return }
                self.finishShotSplit(
                    outcome, targets: targets, asked: asked, scope: scope, document: document)
            })
    }

    /// The Analyzing sheet's answer: refused when the document's project or
    /// scope is no longer the one the press read; a failed analysis named;
    /// else the plan, as one grouped step.
    private func finishShotSplit(
        _ outcome: AnalyzingSheetController.Outcome, targets: [ShotSplit.Target],
        asked: ReelProject, scope: UInt32?, document: ProjectDocument
    ) {
        guard document.project === asked, document.scope == scope else {
            refuseShotSplit(
                "the project changed while \(ShotSplit.actionName) was analyzing, so nothing "
                    + "was split. Choose \(ShotSplit.actionName) again.", document: document)
            return
        }
        switch outcome {
        case .failed(let name, let why):
            refuseShotSplit("The shots analysis of “\(name)” failed: \(why).", document: document)
        case .landed:
            commitShotSplit(targets, document: document, grouped: true)
        }
    }

    /// Plans from the store and applies: in the menu's event when `grouped`
    /// is false, else as one explicit undo group. No cut beeps.
    private func commitShotSplit(
        _ targets: [ShotSplit.Target], document: ProjectDocument, grouped: Bool
    ) {
        let plan: ShotSplit.Plan
        do {
            plan = try ShotSplit.plan(targets, in: document)
        } catch {
            refuseShotSplit(error.localizedDescription, document: document)
            return
        }
        guard !plan.ops.isEmpty else {
            NSSound.beep()
            return
        }
        if grouped {
            document.performGroupedEdit(ShotSplit.actionName, plan.ops)
        } else {
            document.applyEdit(ShotSplit.actionName, plan.ops)
        }
    }

    /// A beep and the sentence at the inspector's foot.
    private func refuseShotSplit(_ reason: String, document: ProjectDocument) {
        NSSound.beep()
        NotificationCenter.default.post(
            name: .projectDocumentDidRefuse, object: document,
            userInfo: ["refusal": ReelRefusal(op: "split_at_shots", reason: reason)])
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case;
    /// nil for any other action. On when a selected clip is a target.
    func validateShotSplitAction(_ action: Selector) -> Bool? {
        guard action == #selector(splitAtShotChanges(_:)) else { return nil }
        guard let snapshot = document?.editedProject.snapshot else { return false }
        return selectedClips.contains { ShotSplit.qualifies($0, in: snapshot) }
    }
}
