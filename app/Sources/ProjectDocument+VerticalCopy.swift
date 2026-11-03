import AppKit

/// Make Vertical's copy (spec §11 VR-30, VR-31; road map "creator-jobs" VR3a): CJ5b's derived
/// document handed the source's handle unchanged (`range: nil`, so every media stays and
/// every cache and analysis is carried), named "<source> (<shape>)", with the step applied
/// there as its one undo step, "Make Vertical". The source is never edited and gains no undo
/// step. Its doors are `make_vertical_version` (`AgentServer+VerticalVersion.swift`) and File ▸
/// Make Vertical Version… (`EditorViewController+VerticalVersion.swift`, VR3b).
extension ProjectDocument {

    /// The copy, and what was carried. Main only. A copy the step did not change is closed,
    /// its package at `path` removed, and the call refused.
    static func verticalCopy(
        from source: ProjectDocument, plan: VerticalVersion.Plan, shape: VerticalShape,
        path: URL?, display: Bool
    ) throws -> (document: ProjectDocument, carried: DerivedCarry.Report) {
        assert(Thread.isMainThread)
        let made = try derived(
            from: source, handle: source.project, range: nil, path: path, display: display,
            name: "\(source.displayStem) (\(shape.rawValue))")
        let opened = made.document.project
        made.document.performGroupedEdit(VerticalVersion.actionName, plan.ops)
        guard made.document.project !== opened else {
            made.document.close()
            if let path { try? FileManager.default.removeItem(at: path) }
            throw ReelCoreError(
                message: "Make Vertical did not apply to the copy, so nothing was made.")
        }
        return made
    }
}
