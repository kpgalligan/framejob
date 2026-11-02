import AppKit

/// The Transcript tab's editor side (road map "creator-jobs" TX2a, spec §11
/// TX-20…TX-22): View ▸ Transcript ⌃⌘T, and the `TranscriptHost` the pane
/// reaches through `inspector.parent`. The command needs no validator arm: it
/// falls through to `validateUserInterfaceItem`'s closing `return true`, as
/// `showAssistant` does.
extension EditorViewController: TranscriptHost {

    /// View ▸ Transcript ⌃⌘T: the inspector shown if it is hidden, the
    /// Transcript tab picked, and its view made first responder.
    @objc func showTranscript(_ sender: Any?) {
        if inspectorContainer.isHidden { toggleInspector(sender) }
        inspector?.select(.transcript)
        guard let inspector, let pane = TranscriptPane.pane(in: inspector) else { return }
        view.window?.makeFirstResponder(pane.transcriptView)
    }

    var transcriptIsPlaying: Bool { playback.isPlaying }

    /// A word's or a timecode's seek: the frame-snapped playhead, playback
    /// going on if it was playing (TX-22).
    func transcriptSeek(to time: Ticks) {
        setPlayhead(time)
    }

    // MARK: - Deleting words (road map "creator-jobs" TX3a, spec §11 TX-31)

    /// The document's in/out range.
    var transcriptRange: TranscriptCut.Range? {
        document?.inOutRange.map { TranscriptCut.Range(start: $0.start, end: $0.end) }
    }

    /// A word selection's range, or nil to clear it: `set_range`'s door
    /// (`AgentServer+Project.swift`), so the timeline shades it and Loop
    /// plays it.
    func transcriptSetRange(_ range: TranscriptCut.Range?) {
        guard let document else { return }
        document.inOutRange = range.flatMap { $0.end > $0.start ? ($0.start, $0.end) : nil }
        viewStateDidChange()
        applyLoopRange()
    }

    /// One `ripple_delete_ranges` as the step `name` ("Delete Words", or
    /// "Delete Pause", TX-34); applied, the range clears and the playhead
    /// lands at the cut.
    @discardableResult func transcriptDelete(_ range: TranscriptCut.Range, name: String) -> Bool {
        guard let document else { return false }
        let before = document.project
        document.applyEdit(name, .rippleDeleteRanges(ranges: [(range.start, range.end)]))
        guard document.project !== before else { return false }
        document.inOutRange = nil
        setPlayhead(range.start)
        viewStateDidChange()
        applyLoopRange()
        return true
    }

    /// TX-32's refusal: a beep and the sentence at the inspector's foot.
    func transcriptRefuse(_ sentence: String) {
        NSSound.beep()
        inspector?.showRefusal(ReelRefusal(op: "ripple_delete_ranges", reason: sentence))
    }

    /// The window's first responder is a Transcript view with words or a
    /// pause selected: the delete family forwards to it (`+Timeline`).
    var transcriptHoldsWords: Bool {
        guard let shown = view.window?.firstResponder as? TranscriptView else { return false }
        return shown.selection != nil || shown.pauseSelection != nil
    }

    /// The delete family's forward: the Transcript pane deletes its words.
    func deleteTranscriptWords() {
        guard let inspector, let pane = TranscriptPane.pane(in: inspector) else {
            NSSound.beep()
            return
        }
        pane.deleteWords()
    }
}
