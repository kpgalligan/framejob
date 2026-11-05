import AppKit

/// Audio while scrubbing (road map "audio" AP13, spec §11 AU-130…AU-136):
/// the ruler drag's two calls into `ScrubAudio`. The press and every drag
/// position arrive through `timelineScrubbed`, after `setPlayhead` has
/// snapped and seeked; mouse-up through `TimelineView.onScrubEnded`. The
/// ruler drag is the only path: **Go** in the Document tab's Markers list,
/// Next and Previous Marker, `set_playhead` and the transport keys are seeks
/// and play no grain (AU-135).
extension EditorViewController {

    func scrubAudioMoved() {
        guard let document = document else { return }
        scrubAudio.move(
            to: document.playhead, duration: document.editedProject.duration,
            player: playback.built?.composition
        ) {
            let project = document.editedProject
            guard let plan = project.plan else { return nil }
            return ScrubSource(
                plan: plan, planJSON: project.planJSON, urls: document.mediaURLs(),
                recipeKey: playback.recipeKey)
        }
    }

    func scrubAudioEnded() {
        scrubAudio.end()
    }
}
