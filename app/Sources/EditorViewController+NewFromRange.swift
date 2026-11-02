import AppKit

/// File ▸ New Project from Range… (spec §11 CJ-52; road map "creator-jobs"
/// CJ5b): the In–Out range of the top-level timeline opened as a new
/// untitled project, dirty, named "<source name> (range)", with the range as
/// its first state and no undo step. `ProjectDocument.derived(…)` is the
/// door; `new_project_from_range` mirrors it. The source document never
/// changes. A refusal or an error beeps and puts its sentence at the
/// inspector's foot (spec §11 CI-10, `refuseShotSplit`'s shape).
extension EditorViewController {

    @objc func newProjectFromRange(_ sender: Any?) {
        guard let document, let range = document.inOutRange, document.scope == nil,
            view.window?.attachedSheet == nil
        else {
            NSSound.beep()
            return
        }
        do {
            _ = try ProjectDocument.derived(
                from: document, handle: document.project, range: (from: range.start, to: range.end),
                path: nil, display: true, name: "\(document.displayStem) (range)")
        } catch {
            NSSound.beep()
            NotificationCenter.default.post(
                name: .projectDocumentDidRefuse, object: document,
                userInfo: [
                    "refusal": ReelRefusal(op: "keep_range", reason: error.localizedDescription)
                ])
        }
    }

    /// The menu arm, answered from `validateUserInterfaceItem`'s default case;
    /// nil for any other action. On with an In–Out range, no nest open and no
    /// sheet on the window.
    func validateNewFromRangeAction(_ action: Selector) -> Bool? {
        guard action == #selector(newProjectFromRange(_:)) else { return nil }
        guard let document else { return false }
        return document.inOutRange != nil && document.scope == nil
            && view.window?.attachedSheet == nil
    }
}
