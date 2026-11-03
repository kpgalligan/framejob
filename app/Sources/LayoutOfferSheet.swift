import AppKit

/// The nest offer (road map creator-jobs CO7, spec §11 CO-72): a switch the core refused because
/// a clip in its reach zooms or moves, offered again as `switch_layout {nest: true}` — the clips
/// nested first, so the layout moves the nest and the zoom keeps playing inside it. After R5-3's
/// no-footage sheet (`presentNoFootageForTransition` in
/// `EditorViewController+InspectorCommands.swift`): the core's sentence verbatim, then what the
/// button does. The completion is not an AppKit event, so Nest and Switch commits through
/// `performGroupedEdit` (app/CLAUDE.md's undo pitfall): ONE op, one undo step "Camera Layout".
enum LayoutOfferSheet {
    static let nestTitle = "Nest and Switch"
    static let title = "Lay out the clips in a nest?"
    static let explanation =
        "Nest and Switch puts those clips in a nest first, so the layout moves the nest and the "
        + "zoom keeps playing inside it. One Undo takes both back."

    /// Puts the offer on `window`. `nested` is the op Nest and Switch sends, its focus already
    /// decided (`CameraLayoutCommand.keepsFocus`, CO-70).
    static func present(
        refusal: ReelRefusal, nested: ReelOp, document: ProjectDocument, window: NSWindow
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = refusal.reason + "\n\n" + explanation
        alert.addButton(withTitle: nestTitle)
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak document] response in
            guard response == .alertFirstButtonReturn, let document else { return }
            document.performGroupedEdit(CameraLayoutCommand.actionName, [nested])
        }
    }
}
