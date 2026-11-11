import AppKit

/// `TranscriptView`'s keys and clicks (spec §11 TX-21). It takes ← and →
/// (one word, selected and sought, through `onActivate`), ↑ and ↓ (the word
/// nearest in x on the adjacent laid-out line, the same), ⇧ with any of them
/// (extend the selection, no seek), ⌘A (`selectAll(_:)`, which the nil-target
/// Edit ▸ Select All reaches first), Esc (clear the selection; with none, close
/// the find bar when it is open, spec §11 TX-37 (e), else pass the key up), and ⌫ and ⌦ with words selected (`deleteKey()`,
/// TX3a, spec §11 TX-31: one "Delete Words"; Edit ▸ Delete's bare ⌫ reaches
/// the editor's forward first). Since TX3b (TX-34) a click on a pause token
/// selects it; Esc, ⌫ and ⌦ act on it, and the arrows move from the word
/// before it. With nothing selected they pass up, and
/// Return passes up unchanged until TX5. `select(match:)` is the find field's
/// ⌘Return (TX-43), a click over a whole match. Every other key goes to
/// `super.keyDown`, so J, K, L, I, O and M reach `handleEditorKey` as from the
/// timeline; Space never arrives here (`SpaceKey.route` takes it at the
/// window). A click makes the view first responder; a drag selects
/// (`+Delete`). Every selection a person makes is told through `onSelect`.
extension TranscriptView {

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first?.value,
            flags.isSubset(of: [.shift])
        else {
            super.keyDown(with: event)
            return
        }
        let extend = flags.contains(.shift)
        let held = selection != nil || pauseSelection != nil
        switch scalar {
        case UInt32(NSLeftArrowFunctionKey): step(by: -1, extend: extend)
        case UInt32(NSRightArrowFunctionKey): step(by: 1, extend: extend)
        case UInt32(NSUpArrowFunctionKey): line(up: true, extend: extend)
        case UInt32(NSDownArrowFunctionKey): line(up: false, extend: extend)
        case 27 where !extend && held: select(nil)
        case 27 where !extend && onEscape?() == true: break  // the find bar closed (TX-37 (e))
        case 0x7F where !extend && held, UInt32(NSDeleteFunctionKey) where !extend && held:
            deleteKey()
        default: super.keyDown(with: event)
        }
    }

    override func selectAll(_ sender: Any?) {
        guard !tokenStarts.isEmpty else { return }
        select(0...(tokenStarts.count - 1))
    }

    /// The token a key moves from: the selection's moving end, else the
    /// word before a selected pause, else the highlighted word.
    private var caret: Int? {
        guard let selection else { return pauseSelection.map { pauses[$0].after } ?? highlighted }
        if let anchor = selectionAnchor, anchor == selection.upperBound, anchor != selection.lowerBound {
            return selection.lowerBound
        }
        return selection.upperBound
    }

    private func step(by delta: Int, extend: Bool) {
        guard !tokenStarts.isEmpty else { return }
        let from = caret ?? (delta > 0 ? -1 : tokenStarts.count)
        move(to: min(max(from + delta, 0), tokenStarts.count - 1), extend: extend)
    }

    private func line(up: Bool, extend: Bool) {
        guard let from = caret ?? (tokenStarts.isEmpty ? nil : 0),
            let target = tokenOnAdjacentLine(to: from, up: up)
        else {
            NSSound.beep()
            return
        }
        move(to: target, extend: extend)
    }

    /// Selects `index` and seeks there, or, extending, grows the selection
    /// from its anchor without a seek.
    private func move(to index: Int, extend: Bool) {
        if extend {
            let anchor = min(max(selectionAnchor ?? caret ?? index, 0), tokenStarts.count - 1)
            setSelection(min(anchor, index)...max(anchor, index))
            selectionAnchor = anchor
            onSelect?(selection)
        } else {
            select(index...index)
            onActivate?(index)
        }
        if let rect = rects(forToken: index).first, !visibleRect.contains(rect) {
            scrollToVisible(rect.insetBy(dx: 0, dy: -24))
            layoutViewport()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        personScrolled()  // a press pauses the follow, as a scroll does (TX-22 at CP1)
        let point = convert(event.locationInWindow, from: nil)
        if let paragraph = paragraphIndex(at: point) {
            onParagraph?(paragraph)
            return
        }
        if !event.modifierFlags.contains(.shift), let pause = pauseIndex(at: point) {
            clickPause(pause)
            return
        }
        guard let index = tokenIndex(at: point) else { return }
        if event.modifierFlags.contains(.shift) {
            move(to: index, extend: true)
        } else {
            click(token: index)
        }
    }

    /// A plain click on token `index`: it alone selected, and sought. The
    /// mouse's path, which `transcript_view`'s `click` takes too.
    func click(token index: Int) {
        select(index...index)
        onActivate?(index)
    }

    /// ⌘Return in the find field (spec §11 TX-43): a click over a match —
    /// every token of `tokens` selected, as a person's selection, and the
    /// first sought.
    func select(match tokens: ClosedRange<Int>) {
        select(tokens)
        onActivate?(tokens.lowerBound)
    }
}
