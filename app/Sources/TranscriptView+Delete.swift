import AppKit

/// `TranscriptView`'s part in deleting words (road map "creator-jobs" TX3a,
/// spec §11 TX-31): a drag selects from the word the press selected, ⌫ and ⌦
/// with words selected ask the pane to delete them (`onDelete`), and the pane
/// hands its widened selection back through `adopt`, which tells nobody.
extension TranscriptView {

    /// A drag from a selected word: the selection runs from its anchor to
    /// the word under the pointer (the last word starting before it, between
    /// words), told through `onSelect` whenever it changes.
    override func mouseDragged(with event: NSEvent) {
        guard let anchor = selectionAnchor, selection != nil, !tokenStarts.isEmpty else { return }
        personScrolled()  // the follow waits while the person selects (TX-22 at CP1)
        autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard let offset = characterOffset(at: point) else { return }
        let index = token(atOrBefore: offset) ?? 0
        let range = min(anchor, index)...max(anchor, index)
        guard range != selection else { return }
        setSelection(range)
        selectionAnchor = anchor
        onSelect?(range)
    }

    /// ⌫ or ⌦ with words or a pause selected (TX-34).
    func deleteKey() {
        guard selection != nil || pauseSelection != nil else { return }
        onDelete?()
    }

    /// The pane's widened selection, shown without telling `onSelect`; the
    /// ⇧ anchor kept when it lies inside, else the selection's start.
    func adopt(_ range: ClosedRange<Int>) {
        guard range.lowerBound >= 0, range.upperBound < tokenStarts.count else { return }
        let anchor = selectionAnchor.flatMap { range.contains($0) ? $0 : nil } ?? range.lowerBound
        if range != selection { setSelection(range) }
        selectionAnchor = anchor
    }
}
