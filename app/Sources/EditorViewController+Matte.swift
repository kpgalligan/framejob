import AppKit

/// Track ▸ Matte ▸ Off / Alpha / Inverted Alpha / Luma / Inverted Luma (spec
/// §11 MT-7): the current track's matte mode. The track context menu's Matte
/// submenu (`TimelineView+TrackMenu.swift`) makes the same edit on the CLICKED
/// track; `set_track {matte}` is their MCP mirror (`AgentServer+Tracks.swift`).
/// The checkmark is the validator's arm in `EditorViewController+Identity.swift`,
/// beside Solo's.
extension EditorViewController {
    /// The sender's tag indexes `TrackMatte.allCases`. One `set_track` on
    /// `currentTrack`, undo "Track Matte"; the mode the track already has is
    /// the core's identity, which beeps and makes no step.
    @objc func setTrackMatte(_ sender: Any?) {
        guard let document = document, let track = currentTrack,
              let tag = (sender as? NSMenuItem)?.tag, TrackMatte.allCases.indices.contains(tag)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit(
            "Track Matte", .setTrack(track: track.id, matte: TrackMatte.allCases[tag]))
    }
}
