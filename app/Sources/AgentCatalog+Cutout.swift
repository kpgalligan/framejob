import Foundation

/// The catalog row of `analyze_cutout` (spec §11 CO-31; road map "creator-jobs" CO3), spliced
/// in by `creatorTools()`.
extension AgentServer {

    func cutoutTools() -> [[String: Any]] {
        [
            // It mirrors the Clip tab's Picture ▸ Background section — its Status read-out and
            // its Analyze Now button (VideoPane+Cutout.swift, EditorViewController+Cutout.swift's
            // analyzeCutoutNow) — whose checkbox and Clip ▸ Remove Background are `set_video`'s
            // `cutout`. An app-state read that makes masks: no op, no `scope`, no undo step.
            tool(
                "analyze_cutout",
                "Answers where Remove Background stands for cut-out clips (a clip whose "
                    + "set_video cutout is set) and makes their masks now — the mirror of the "
                    + "Clip tab's Picture ▸ Background section's Status and its Analyze Now "
                    + "button; Clip ▸ Remove Background and the section's checkbox turn a "
                    + "cutout on (set_video {cutout: {}}). The masks are made ON THIS MAC "
                    + "(Vision's person segmentation, or for a picture with subject foreground "
                    + "its foreground instance mask) — no upload, no network request, no API "
                    + "key — and kept per media in the project's cache, so frames already "
                    + "analysed are never analysed again. A picture (an image clip) is one "
                    + "frame, made from the picture itself. A call wants every frame the clips "
                    + "play and runs again an analysis that failed or was stopped, then waits "
                    + "up to wait seconds (0 when left out: the status now, at most 60) for "
                    + "every clip to settle; it never refuses for time — call again to keep "
                    + "waiting. Answers clips [{clip, media, state, progress, quality, frames, "
                    + "covered, ready, subject_found, centroid, error?}]: state is analyzing, "
                    + "ready (every frame analysed and a person, or a picture's foreground "
                    + "subject, found), no_person (every frame analysed and no person in the "
                    + "clip's window: the clip draws whole), no_subject (a picture with subject "
                    + "foreground whose mask found no subject: it draws whole), failed or "
                    + "no_picture (the clip plays no frame of its file); progress 0–1; quality "
                    + "the clip's; frames the frames of its file the clip plays (1 for a "
                    + "picture) and covered how many are analysed; ready whether covered equals "
                    + "frames; subject_found whether a subject was found; centroid {x, y}, the "
                    + "subject's mean center over those frames in the media's upright pixels "
                    + "(origin top left, y down), null unless ready; error, when failed, the "
                    + "sentence saying why. Refused, nothing done: wait outside 0–60, a clip "
                    + "that does not exist, a named clip with no cutout, and, with clips left "
                    + "out, no cut-out clip in the scope set_scope has open. It edits nothing "
                    + "and makes no undo step.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"],
                        "description": "The cut-out clips to answer for; every cut-out clip in "
                            + "the open scope, in timeline order, when left out.",
                    ],
                    "wait": [
                        "type": "number",
                        "description": "How many seconds to wait for every clip to settle, 0 "
                            + "to 60; 0 (answer now) when left out.",
                    ],
                ], required: []),
        ]
    }
}
