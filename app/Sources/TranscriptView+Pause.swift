import AppKit

/// `TranscriptView`'s pause tokens (road map "creator-jobs" TX3b, spec §11
/// TX-34): the hit test on a pause's text, a click on one — the word
/// selection cleared, the pause selected and told through `onSelectPause` —
/// and the selected pause's mark, drawn behind the text as a word
/// selection's is.
extension TranscriptView {

    /// The pause whose text is under `point`.
    func pauseIndex(at point: NSPoint) -> Int? {
        guard !pauseRanges.isEmpty, let offset = characterOffset(at: point) else { return nil }
        var low = 0
        var high = pauseRanges.count
        while low < high {
            let mid = (low + high) / 2
            if pauseRanges[mid].location <= offset { low = mid + 1 } else { high = mid }
        }
        for index in [low - 1, low] where pauseRanges.indices.contains(index) {
            if rects(for: pauseRanges[index]).contains(where: { $0.insetBy(dx: -2, dy: 0).contains(point) }) {
                return index
            }
        }
        return nil
    }

    /// A click on pause `index`: the words' selection cleared, the pause
    /// selected, and told. The mouse's path, which `transcript_view`'s
    /// `select_pause` takes too.
    func clickPause(_ index: Int) {
        guard pauses.indices.contains(index) else { return }
        selectionAnchor = nil
        setSelection(nil)
        setPauseSelection(index)
        onSelectPause?(index)
    }

    /// The selected pause, behind its text.
    func drawPauseMark(in dirtyRect: NSRect) {
        guard let index = pauseSelection, pauseRanges.indices.contains(index) else { return }
        DS.selectionFill.setFill()
        for rect in rects(for: pauseRanges[index]) where rect.intersects(dirtyRect) {
            rect.fill()
        }
    }
}
