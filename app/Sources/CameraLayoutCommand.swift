import AppKit

/// The path Clip ▸ Camera Layout ▸ and the Picture sub-tab's Layout section share (road map
/// creator-jobs CO7, spec §11 CO-70, CO-72): the camera's focus read from its cached person
/// masks, the trial, then the commit or the nest offer. `keepsFocus` is the nested-camera test
/// the offer and `switch_layout`'s tool share.
enum CameraLayoutCommand {
    static let actionName = "Camera Layout"

    /// `choice` at the playhead for these roles. With the camera's masks cached for every
    /// frame it plays, the focus is read on `CameraLayoutFocus.queue` and the switch applied on
    /// main only if the project and scope are unchanged (else a beep and nothing changed);
    /// without them it runs at once. Main thread.
    static func run(
        _ choice: CameraLayoutChoice, camera: UInt32, screen: UInt32?, duration: Ticks?,
        document: ProjectDocument, window: NSWindow?
    ) {
        let at = document.playhead
        guard let inputs = CameraLayoutFocus.inputs(camera: camera, in: document) else {
            switchLayout(
                choice, camera: camera, screen: screen, at: at, duration: duration, focus: nil,
                document: document, window: window)
            return
        }
        let project = document.project
        let scope = document.scope
        CameraLayoutFocus.queue.async {
            let focus = CameraLayoutFocus.focus(inputs)
            DispatchQueue.main.async { [weak document, weak window] in
                guard let document else { return }
                guard document.project === project, document.scope == scope else {
                    NSSound.beep()
                    return
                }
                switchLayout(
                    choice, camera: camera, screen: screen, at: at, duration: duration,
                    focus: focus, document: document, window: window)
            }
        }
    }

    /// The trial, then the offer or the commit (CO-72).
    private static func switchLayout(
        _ choice: CameraLayoutChoice, camera: UInt32, screen: UInt32?, at: Ticks,
        duration: Ticks?, focus: (Double, Double)?, document: ProjectDocument, window: NSWindow?
    ) {
        let op = choice.op(
            camera: camera, screen: screen, at: at, duration: duration, focus: focus)
        if let window, case .refused(let refusal)? = try? document.project.applying(
            [addressed(op, document)])
        {
            var nested = choice.op(
                camera: camera, screen: screen, at: at, duration: duration, focus: focus,
                nest: true)
            if case .applied? = try? document.project.applying([addressed(nested, document)]) {
                if focus != nil, !keepsFocus(nested: nested, camera: camera, document: document) {
                    nested = choice.op(
                        camera: camera, screen: screen, at: at, duration: duration, nest: true)
                }
                LayoutOfferSheet.present(
                    refusal: refusal, nested: nested, document: document, window: window)
                return
            }
        }
        document.performGroupedEdit(actionName, [op])
    }

    /// `nested` carries `nest: true` and the filled focus. Trials it on `document.project`,
    /// scoped as `ProjectDocument.addressed` scopes it. False only when the trial applies and
    /// the camera id is absent from the applied project's view (`scope.flatMap { p.scoped($0) }
    /// ?? p`, then `snapshot.clip(camera) == nil`), i.e. the nest replaced the camera with a
    /// nest clip, where a focus in the camera media's pixels would miss (CO-70). Main thread.
    static func keepsFocus(nested: ReelOp, camera: UInt32, document: ProjectDocument) -> Bool {
        let op = addressed(nested, document)
        guard case .applied(let applied)? = try? document.project.applying([op]) else {
            return true
        }
        let view = op.scope.flatMap { applied.scoped($0) } ?? applied
        return view.snapshot.clip(camera) != nil
    }

    /// `ProjectDocument.addressed`'s rule for one op: the open nest stamped on an op that is not
    /// document-level and carries no scope of its own.
    private static func addressed(_ op: ReelOp, _ document: ProjectDocument) -> ReelOp {
        op.isDocumentLevel || op.scope != nil ? op : op.scoped(document.scope)
    }
}
