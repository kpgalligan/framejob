import Foundation

/// The catalog row of `get_timeline_transcript` (spec §11 TX-13; road map
/// "creator-jobs" TX1), spliced in by `creatorTools()`.
extension AgentServer {

    func transcriptTools() -> [[String: Any]] {
        [
            // It mirrors the words the Transcript tab (TX2a) will show: the
            // edited container's heard words, read on this Mac once per media
            // (`TranscriptFill`). `get_transcript` stays one clip. A read: no
            // op, no `scope`, no undo step.
            tool(
                "get_timeline_transcript",
                "Answers every word HEARD on the timeline (or inside the nest set_scope has "
                    + "open), in timeline order, nested clips included: words is [{text, start, "
                    + "end, clip, track, media, engine, filler, speaker?, editable, why?, id, "
                    + "cut_start, cut_end}], "
                    + "times in TIMELINE ticks (600000 per second), ordered by start, then end, "
                    + "then the front track first. A clip that is muted, soloed out or at volume "
                    + "0 is not heard and gives no words. track is the timeline track the word "
                    + "plays on (a nested word's is its nest clip's). editable is false, with "
                    + "why, for a word inside a nest, under a transition or on a locked track. "
                    + "id {nest_path, media, source, k} names the word across edits: the nest "
                    + "clips it plays through, its media, its start in the media's SOURCE ticks "
                    + "as the recogniser put it and k, counting earlier words with the same "
                    + "three (0 unless one piece of the source plays twice). An engine apple "
                    + "word's start is where its sound begins, read from the media's voice and "
                    + "waveform caches; until the voice cache exists it is the recogniser's, "
                    + "often early, and notes says so. cut_start and cut_end are the range the "
                    + "Transcript tab cuts that word by when it alone is deleted, snapped to "
                    + "frames: from the word's onset (where its sound starts, read from the voice "
                    + "cache) to the next word's onset, at most 1 s past the word's end, widened "
                    + "over any other track's word it would cut into. To cut a run of words, call "
                    + "ripple_delete_ranges once with one range from its first word's cut_start to "
                    + "its last word's cut_end. Each media's words come from its cached "
                    + "transcript (engine assemblyai) when it has a current one, else this "
                    + "Mac's own recogniser, which reads the WHOLE file once (about 0.7 s per "
                    + "minute of speech on an M2 Max) and keeps it in the project's cache, so a "
                    + "later call answers at once. It NEVER makes a network request and needs no "
                    + "API key. media is [{media, engine, language, fillers_reported}] for each "
                    + "media read; no_words lists the media clips that cannot be read, "
                    + "[{clip, nest_path, tag, reason}]; notes names two clips carrying the same "
                    + "speech, says when the words were not transcribed with filler words and "
                    + "names a media whose word starts are not yet moved to their sound. "
                    + "filler is true for um, uh, hmm, mhm, uh-huh, ah, huh, hm, m, er and erm. "
                    + "With from or to it answers only the words that overlap that part of the "
                    + "timeline (a word across an edge whole), echoed as from and to. At most "
                    + "2000 words come back: then truncated is true and next_from is where to "
                    + "call again (pass it as from; a word overlapping it may come back again "
                    + "with the same id). It edits nothing and makes no undo step.",
                [
                    "from": [
                        "type": "integer",
                        "description": "Where on the TIMELINE to start reading, in ticks "
                            + "(600000 per second), snapped to frames; the timeline's start by "
                            + "default. A word across this edge comes back whole.",
                    ],
                    "to": [
                        "type": "integer",
                        "description": "Where on the TIMELINE to stop reading, in ticks, "
                            + "snapped to frames; the timeline's end by default. Must be after "
                            + "from.",
                    ],
                    "tracks": [
                        "type": "array", "items": ["type": "integer"],
                        "description": "Only the words playing on these timeline tracks (ids "
                            + "from get_project); every track by default.",
                    ],
                    "language": [
                        "type": "string",
                        "description": "A language tag, e.g. en-US, for this Mac's recogniser "
                            + "only (a cached transcript answers in its own language). This "
                            + "Mac's own language by default; each language is kept apart in "
                            + "the cache. A tag speech recognition does not know is refused "
                            + "with the tags it knows, and one whose on-device model is not "
                            + "installed is refused as not installed — this tool never "
                            + "downloads.",
                    ],
                ], required: []),
        ]
    }
}
