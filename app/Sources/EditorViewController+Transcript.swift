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
}
