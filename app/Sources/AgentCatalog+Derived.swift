import Foundation

/// The catalog row of `new_project_from_range` (spec §11 CJ-52; road map
/// "creator-jobs" CJ5b), spliced in by `creatorTools()`.
extension AgentServer {

    func derivedTools() -> [[String: Any]] {
        [
            // It mirrors File ▸ New Project from Range… (`newProjectFromRange`
            // in EditorViewController+NewFromRange.swift): the range opened as
            // a new project through `ProjectDocument.derived(…)`. No op runs
            // on the source (`keep_range` is applied to the new document's
            // handle), so no `scope` and no undo step there.
            tool(
                "new_project_from_range",
                "Opens a NEW project holding exactly [from, to) of the top-level timeline, moved "
                    + "to start at 0 — what File ▸ New Project from Range… does with the In–Out "
                    + "range. Times are TIMELINE ticks (600000 per second), snapped to frames. "
                    + "A clip across an edge is cut there as split cuts it; a transition across "
                    + "an edge becomes a hard start or end; markers inside are kept; media no "
                    + "kept clip plays are left out. Each kept media's caches (filmstrips, "
                    + "waveforms, loudness, speech, sync, transcripts read on this Mac, the "
                    + "media analysis, reversed renders) and the graphic modules the kept clips "
                    + "draw, with every font and asset, are carried, so nothing is "
                    + "re-analysed; media files are never copied (the new project points at the "
                    + "same files), and a cloud transcript still owed a deletion stays behind. "
                    + "The project you name never changes and gets no undo step. Without path "
                    + "the new project opens untitled, with unsaved changes, named \"<name> "
                    + "(range)\"; with path it is saved there first. Refused while a nest is "
                    + "open, onto a path another open project holds or where anything already "
                    + "exists, and in the core's own sentence for a nest clip across an edge or "
                    + "a range where nothing plays. Answers {project, saved (with path), "
                    + "carried {files, bytes, seconds}}; name the new project by its path or "
                    + "name in later calls.",
                [
                    "from": [
                        "type": "integer",
                        "description": "Where the range starts on the TIMELINE, in ticks "
                            + "(600000 per second).",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Where the range ends on the TIMELINE, in ticks; must be "
                            + "after from.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to save the new project, an absolute path; "
                            + ".framejob is added when missing. Nothing may exist there yet. "
                            + "Without it the project opens untitled.",
                    ],
                ], required: ["from", "to"]),
        ]
    }
}
