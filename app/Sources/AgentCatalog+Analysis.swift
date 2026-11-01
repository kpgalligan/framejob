import Foundation

/// The catalog row of `get_media_analysis` (spec §11 CJ-25; road map
/// "creator-jobs" CJ2a), spliced in by `creatorTools()`.
extension AgentServer {

    func analysisTools() -> [[String: Any]] {
        [
            // It mirrors what the Analyzing sheet's command (CJ2b, Clip ▸ Split
            // at Shot Changes…) will read: a media's analysis on this Mac,
            // made or reused. `get_transcript` is its counterpart for words.
            // A read: no op, no `scope`, no undo step.
            tool(
                "get_media_analysis",
                "Answers an analysis of one media file, or of the part of it one clip plays, "
                    + "made ON THIS MAC — no network request, no upload, no API key — and kept "
                    + "per media in the project's cache, so a later call over a window already "
                    + "analysed answers at once. kind \"shots\" finds the hard cuts: cuts is "
                    + "[{frame, source}] sorted by time, frame the media's frame index and "
                    + "source its presentation time in the media's own SOURCE ticks (600000 "
                    + "per second, of the file played forwards), with count. A cut inside a "
                    + "gradual dissolve is not reported, and a single flash frame is not a "
                    + "cut; a dissolve between flat-coloured pictures (slides, title cards) can "
                    + "show as one cut. With clip, from and to default to and are held inside "
                    + "the clip's played window, and each cut also has clip_time (ticks from "
                    + "the clip's start, in its playing direction — through its speed, ramp "
                    + "and reversal) and timeline (the clip's start plus clip_time). cached "
                    + "says whether the answer came from the cache alone; run "
                    + "({queued_at, started_at, ended_at}, seconds of process uptime) is "
                    + "present only when this call ran the analysis. size is the media's "
                    + "upright picture size; stamp what the cache was made with. A call waits "
                    + "at most \(Int(AnalysisLane.callWaitLimit)) s and then refuses naming "
                    + "how much of the window was covered — what was covered is kept, so call "
                    + "again to continue; an answer over 512 KiB of cuts is refused naming the "
                    + "largest to that fits. It edits nothing and makes no undo step.",
                [
                    "media": [
                        "type": "integer",
                        "description": "The media whose picture to analyse — exactly one of "
                            + "media and clip.",
                    ],
                    "clip": [
                        "type": "integer",
                        "description": "A media clip: its media analysed over the part the "
                            + "clip plays — exactly one of media and clip.",
                    ],
                    "kind": [
                        "type": "string", "enum": AnalysisKind.allCases.map(\.rawValue),
                        "description": "What to find: shots, the hard cuts.",
                    ],
                    "from": [
                        "type": "integer",
                        "description": "Where to start, in the media's SOURCE ticks (the file "
                            + "played forwards, 600000 per second), not snapped: 0, or the "
                            + "clip's played window's start, by default.",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Where to stop (not included), in the media's SOURCE "
                            + "ticks: the media's end, or the clip's played window's end, by "
                            + "default; must be after from.",
                    ],
                ], required: ["kind"])
        ]
    }
}
