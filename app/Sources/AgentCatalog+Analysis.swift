import Foundation

/// The catalog rows of `get_media_analysis` (spec §11 CJ-25; road map
/// "creator-jobs" CJ2a; `masks` CO-14, `faces` CJ-34, `sound_events` FC-33) and
/// `split_at_shots`
/// (CJ-29, CJ2b), spliced in by `creatorTools()`.
extension AgentServer {

    func analysisTools() -> [[String: Any]] {
        let rateText = AnalysisFaces.rateName
        return [
            // It mirrors what the Analyzing sheet's command (CJ2b, Clip ▸ Split
            // at Shot Changes) reads: a media's analysis on this Mac,
            // made or reused. `get_transcript` is its counterpart for words.
            // A read: no op, no `scope`, no undo step. `masks` (CO1) and
            // `faces` (CJ3) have no menu or pane of their own: a cut-out clip
            // draws masks, and nothing in the app reads faces yet; nor does
            // anything read `sound_events` (FC3) until Find Clips (FC4).
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
                    + "show as one cut. kind \"masks\" finds a person's outline in every frame "
                    + "(Vision's person segmentation, on the Mac) and answers its runs, never "
                    + "pixels: mask_size [w, h] (the masks' own size), frames (frames held in "
                    + "the window), subject_found (whether any frame holds a person: at least "
                    + "0.5 % of the mask above half), count and runs [{from, to, subject_found, "
                    + "frames}] in SOURCE ticks — a run is consecutive analysed frames that "
                    + "agree on subject_found. Remove Background (Clip ▸ Remove Background, the "
                    + "Clip tab's Picture ▸ Background section, set_video cutout) draws them, "
                    + "and analyze_cutout makes a cut-out clip's masks and says where they "
                    + "stand. kind \"faces\" finds every face "
                    + "(Vision's face rectangles and landmarks, on the Mac) at \(rateText) "
                    + "samples a second of source time and answers rate, count and samples "
                    + "[{source, frame, faces: [{box: [x, y, w, h], confidence, roll, yaw, "
                    + "mouth_gap, mouth_width}]}]: source the sample's instant in SOURCE ticks, "
                    + "frame the presentation time of the frame it read (the first at or after "
                    + "source, within one sample) or null; box 0…1 of the upright picture from "
                    + "its top-left; roll and yaw in radians; mouth_gap the inner lips' height "
                    + "and mouth_width the outer lips' width, each over the face box's height "
                    + "(gap over width is how open the mouth is). Faces are ordered left to "
                    + "right and carry no identity: follow one by its box from sample to "
                    + "sample. Values are rounded to 4 decimals; null where Vision gave none. "
                    + "A sample row with one face is about 176 bytes (221 with clip), so one "
                    + "answer holds about 296 s of samples (236 s with clip), less when more "
                    + "faces are in frame: read a longer media in from/to windows of at most "
                    + "that, e.g. 2 minutes. kind \"sound_events\" listens to the media's "
                    + "first sound track (Apple's Sound Analysis classifier, on the Mac) in "
                    + "windows of \(SoundEvents.windowTicks) ticks (1.5 s) every "
                    + "\(SoundEvents.hopTicks) (0.75 s) and answers window and hop (ticks), "
                    + "groups [{name, labels, first_class, threshold}] — laughter, applause, "
                    + "cheering, crowd, music, speech, each the classifier labels it is the "
                    + "highest confidence of; none is first_class yet, so read the values as "
                    + "hints, never alone as a finding, and threshold is null — count and "
                    + "windows [{source, laughter, applause, cheering, crowd, music, speech}]: "
                    + "source the window's start in SOURCE ticks and each group's confidence "
                    + "0…1, rounded to 4 decimals, null where the classifier gave none (a "
                    + "window running past the sound's end). It needs a media with sound, a "
                    + "video or an audio file; a reversed clip is refused, since its sound "
                    + "plays backwards. A row is about 130 bytes, so one answer holds about "
                    + "an hour of windows. With "
                    + "clip, from and to default to and are held inside "
                    + "the clip's played window, and each cut, sample or window also has clip_time "
                    + "(ticks from "
                    + "the clip's start, in its playing direction — through its speed, ramp "
                    + "and reversal) and timeline (the clip's start plus clip_time). cached "
                    + "says whether the answer came from the cache alone; run "
                    + "({queued_at, started_at, ended_at}, seconds of process uptime) is "
                    + "present only when this call ran the analysis. size is the media's "
                    + "upright picture size; stamp what the cache was made with. A call waits "
                    + "at most \(Int(AnalysisLane.callWaitLimit)) s and then refuses naming "
                    + "how much of the window was covered — what was covered is kept, so call "
                    + "again to continue; an answer over 512 KiB of cuts, runs, samples or "
                    + "windows is "
                    + "refused naming the largest to that fits. It edits nothing and makes no "
                    + "undo step.",
                [
                    "media": [
                        "type": "integer",
                        "description": "The media whose picture or sound to analyse — exactly "
                            + "one of media and clip.",
                    ],
                    "clip": [
                        "type": "integer",
                        "description": "A media clip: its media analysed over the part the "
                            + "clip plays — exactly one of media and clip.",
                    ],
                    "kind": [
                        "type": "string", "enum": AnalysisKind.allCases.map(\.rawValue),
                        "description": "What to find: shots, the hard cuts; masks, a person's "
                            + "masks' runs; faces, every face per sample (box, roll, yaw, "
                            + "mouth); sound_events, laughter, applause, cheering, crowd, "
                            + "music and speech per window of sound.",
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
                ], required: ["kind"]),
            // Mirrors Clip ▸ Split at Shot Changes
            // (EditorViewController+ShotSplit.swift): the same planner,
            // `ShotSplit`, waiting where the menu shows the Analyzing sheet.
            // An app-state composite of `split`: no `scope` key; it acts in
            // the document's current scope, one undo step.
            tool(
                "split_at_shots",
                "Splits media clips at every hard cut (shot change) inside the part of their "
                    + "media they play, as ONE undo step \"\(ShotSplit.actionName)\" — the "
                    + "mirror of Clip ▸ Split at Shot Changes. The cuts are found ON THIS MAC "
                    + "(get_media_analysis's kind shots: no network request, no API key) and "
                    + "kept in the project's cache, so a second call answers from it. A target "
                    + "is a clip of a video file with its picture on; other clips named are "
                    + "answered under skipped. Each cut is mapped to the timeline through the "
                    + "clip's speed, ramp and reversal and snapped to the canvas's frame grid; a "
                    + "cut within one frame of either end of the clip is not split. Each split "
                    + "is split's: a clip on a locked track is still cut when named, and its "
                    + "linked partner is cut too when the partner is on an unlocked track. The "
                    + "whole call is refused before any split when it would pass the project's "
                    + "\(Int(RC_MAX_CLIPS))-clip ceiling, counting each linked partner it also "
                    + "cuts, naming how many it would add and how many fit. It waits at most "
                    + "\(Int(AnalysisLane.callWaitLimit)) s for the analysis and then refuses — "
                    + "what was covered is kept, so call again to continue. A cut inside a "
                    + "gradual dissolve is not found, and a dissolve between flat-coloured "
                    + "pictures (slides, title cards) can be found as one cut. Answers cuts "
                    + "([{clip, at: [timeline ticks]}]), added (the clips the splits made), "
                    + "skipped, cached (whether the analysis came from the cache alone), the "
                    + "new clip ids and project; with no cut inside any clip, added 0 and a "
                    + "note, and no undo step. It acts in the scope set_scope has open.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"],
                        "description": "The clips to split; every clip of a video file on an "
                            + "unlocked track in the open scope when left out.",
                    ]
                ], required: []),
        ]
    }
}
