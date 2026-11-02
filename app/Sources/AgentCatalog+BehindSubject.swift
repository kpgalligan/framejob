import Foundation

/// The catalog row of `text_behind_subject` (spec §11 CO-54; road map "creator-jobs" CO5),
/// spliced in by `creatorTools()` after `analyze_cutout`.
extension AgentServer {

    func behindSubjectTools() -> [[String: Any]] {
        [
            // It mirrors Insert ▸ Text Behind Subject (EditorViewController+BehindSubject.swift's
            // insertTextBehindSubject), through the same planner (BehindSubjectPlan.swift). An
            // app-state composite of ordinary ops: no `scope`, one undo step.
            tool(
                "text_behind_subject",
                "Puts a title behind the person in a video clip, the mirror of Insert ▸ Text "
                    + "Behind Subject: one undo step \"Text Behind Subject\" that adds a track "
                    + "named \"Behind Subject\" directly above the clip's track (and above any "
                    + "matte tracks in front of it), a text clip with the Title preset on it at "
                    + "at for 4 seconds or the rest of the clip if shorter, set_video "
                    + "{behind_subject: true} on the title, and — only when the clip has no "
                    + "cutout yet — set_video {cutout: {background: keep}} on the clip, so the "
                    + "camera stays whole and the person still hides the title. The person's "
                    + "masks are made ON THIS MAC (Vision), no key needed; analyze_cutout says "
                    + "where they stand. Without clip, it picks among the clips of a video "
                    + "file playing at at on a shown track that is not a matte track: the "
                    + "front-most selected one, else the front-most with a cutout, else the "
                    + "front-most. Works on the top-level timeline only (set_scope with no "
                    + "nest first). The selection is left as it was. Answers {ok, clip (the "
                    + "clip the title is behind), track (the new track's id), text (the "
                    + "title's clip id), duration (ticks), cutout_added, project}. Refused, "
                    + "nothing done: a nest open, an empty content, no such clip at at, or a "
                    + "named clip that is not a clip of a video file on a shown, non-matte "
                    + "track. Any drawing clip but an adjustment or nest clip can be put "
                    + "behind the subject by hand with set_video {behind_subject: true}.",
                [
                    "clip": [
                        "type": "integer",
                        "description": "The clip of a video file to put the title behind; "
                            + "picked at at when left out.",
                    ],
                    "at": [
                        "type": "integer",
                        "description": "Where the title starts, in ticks (600000 per "
                            + "second), snapped to the frame grid; the playhead when left out.",
                    ],
                    "content": [
                        "type": "string",
                        "description": "The title's text; the Title preset's when left out.",
                    ],
                ], required: []),
        ]
    }
}
