import AppKit

/// What a key does in the in-canvas text editor (spec §11 K-2,
/// kpgalligan/framejob#37): a bare Return applies, a modified Return is a new
/// line, Esc leaves or asks.
enum TextEditKeyRoute: Equatable {
    case apply, newline, escape
}

enum TextEditKey {
    /// nil unless `event` is a key-down of Return (36), keypad Enter (76) or
    /// Esc (53) with no marked text — an input method owns all three while it
    /// composes. Return with ⇧, ⌘, ⌥ or ⌃ is a new line, one rule for all
    /// four; ⇪, fn and the keypad flag are not modifiers here. Pure.
    static func route(_ event: NSEvent, hasMarkedText: Bool) -> TextEditKeyRoute? {
        guard event.type == .keyDown, !hasMarkedText else { return nil }
        switch event.keyCode {
        case 36, 76:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let modifiers: NSEvent.ModifierFlags = [.shift, .command, .option, .control]
            return flags.intersection(modifiers).isEmpty ? .apply : .newline
        case 53:
            return .escape
        default:
            return nil
        }
    }
}

extension PreviewCanvasView {
    /// Esc in the editor. An unchanged string leaves at once; a changed one
    /// asks Cancel / Revert / Apply in a sheet, Apply the default (Return).
    ///
    /// The editor's blur-commit is suspended while the sheet is up — a blur
    /// that commits behind the question is the bug the sheet exists to
    /// prevent — and restored on Cancel. The completion is not an AppKit
    /// event, so Apply sends through `onGroupedEdit` (app/CLAUDE.md's undo
    /// pitfall); an editor torn down under the sheet (the clip removed by an
    /// agent) makes the answer a no-op.
    func escapeTextEditing() {
        guard let editor = textEditor, let id = editingClip, let window = window,
              snapshot.clip(id)?.text?.content != editor.string
        else {
            cancelTextEditing()
            return
        }
        let blur = editor.onBlur
        editor.onBlur = nil
        let alert = NSAlert()
        alert.messageText = "Apply your changes to this text?"
        alert.informativeText = "Return applies while you type; ⇧Return starts a new line."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Revert")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self, weak editor] response in
            guard let self = self, let editor = editor, self.textEditor === editor else { return }
            switch response {
            case .alertFirstButtonReturn:
                let value = editor.string
                self.cancelTextEditing()
                guard self.snapshot.clip(id)?.text?.content != value else { return }
                self.onGroupedEdit?(
                    "Edit Text", [.setText(clips: [id], patch: TextPatch(content: value))])
            case .alertSecondButtonReturn:
                self.cancelTextEditing()
            default:
                editor.onBlur = blur
                self.window?.makeFirstResponder(editor)
            }
        }
    }
}
