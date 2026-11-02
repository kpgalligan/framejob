import AppKit

/// The Picture sub-tab's Behind Subject section (road map creator-jobs CO5, spec §11 CO-55),
/// right after Transform: one checkbox writing `video.behind_subject` — an end inside an action,
/// where the flag switches at the action's end (CO-52) — one undo step "Behind Subject", mixed
/// over a selection that disagrees, Reset writing false. With one clip selected and its flag on,
/// a note says when no cut-out clip is behind it at the playhead: the document's recipe there
/// names no subject group in the clip's cut (`BehindSubjectPlan.isCutBySubject`).
extension VideoPane {

    /// The section's gate: no nest open, and a selection with pixels holding no adjustment clip
    /// and no nest clip — the two kinds the core refuses the flag on (CO-52).
    var allBehindable: Bool {
        guard binding.document?.scope == nil else { return false }
        let clips = binding.clips
        return !clips.isEmpty && !binding.videoClips.isEmpty
            && !clips.contains { clip in
                if case .nest = clip.source { return true }
                return InspectorTab.isAdjustment(clip)
            }
    }

    func behindSubjectSection() -> InspectorSection {
        let binding = self.binding
        func on() -> Bool { binding.videoProps.behindSubject }
        func ops(_ value: Bool) -> [ReelOp] {
            binding.ops(video: VideoPatch(behindSubject: value))
        }
        func note() -> String? {
            guard binding.isSingle, let clip = binding.videoClips.first, on(),
                let document = binding.document, document.scope == nil,
                let recipe = document.project.recipe(at: document.playhead)
            else { return nil }
            return BehindSubjectPlan.isCutBySubject(clip: clip.id, in: recipe) == true
                ? nil : "No cut-out clip is behind it at the playhead."
        }
        return InspectorSection(
            id: "video.behind_subject", title: "Behind Subject",
            summary: { on() ? "on" : "off" },
            note: note,
            reset: { binding.apply("Behind Subject", ops(false)) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Behind subject", binding, name: "Behind Subject", read: on, ops: ops,
                    mixed: { binding.mixedVideo { $0.behindSubject } })
            ])
    }
}
