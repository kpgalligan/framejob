import AppKit

/// The Picture sub-tab's Cursor section (road map creator-jobs CU3b, spec §11 CU-38 (b)), after
/// Background and before Shadow: one checkbox, Show cursor, writing a sparse `{cursor: {show}}`
/// (`VideoPatch.cursorPart`) — an end inside an action, where `show` switches at the end (CU-30)
/// — one undo step "Show Cursor", mixed over a selection that disagrees, Reset writing true. CU4
/// adds the section's other rows.
extension VideoPane {

    /// The section's gate: every selected clip is a media or still clip whose media has a cursor
    /// file the movie's picture does not already show (`media.cursor` with `in_picture` false).
    /// `ClipPane.structureSignature` carries it, so a relink, an undo or a landing that changes
    /// the media's `cursor` under a fixed selection adds or removes the section.
    var allCursored: Bool {
        let clips = binding.clips
        let snapshot = binding.snapshot
        return !clips.isEmpty
            && clips.allSatisfy { clip in
                switch clip.source {
                case .media, .still:
                    guard let cursor = snapshot.media(for: clip)?.cursor else { return false }
                    return !cursor.inPicture
                default:
                    return false
                }
            }
    }

    func cursorSection() -> InspectorSection {
        let binding = self.binding
        func on() -> Bool { binding.videoProps.cursor?.show ?? true }
        func ops(_ value: Bool) -> [ReelOp] {
            binding.ops(video: VideoPatch(cursorPart: CursorPatch(show: value)))
        }
        return InspectorSection(
            id: "video.cursor", title: "Cursor",
            summary: { on() ? "on" : "off" },
            reset: { binding.apply("Show Cursor", ops(true)) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Show cursor", binding, name: "Show Cursor", read: on, ops: ops,
                    mixed: { binding.mixedVideo { $0.cursor?.show ?? true } })
            ])
    }
}
