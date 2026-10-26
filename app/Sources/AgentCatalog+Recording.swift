import Foundation

// MARK: - Catalog: recording

/// The catalog's RECORDING row: `record_screen`, File ▸ New Recording…
/// without the panel (road map 3) — the last of the thirteen `fileTools`
/// publishes, with the four paragraphs of its description hoisted above it.
///
/// A pure move out of `AgentCatalog+Files.swift`, which stood at 409 lines
/// against the 400-line cap a camera source would have grown: camera
/// recording's CR1-0, paid first and alone, on the seam
/// `designs/adr/app-file-history.md` named. `AgentCatalog+Render.swift`'s
/// header is the model. The row under the file's own `// MARK: Recording`
/// came here whole, with its body untouched, and so did the four hoisted
/// clauses only it reads (`recordingPauseClause`,
/// `recordingUnreadableClause`, `recordingResultClause` and
/// `recordingVoiceOverClause`), still hoisted for the type checker's budget.
/// It is SPLICED back in where it left — LAST, after `cancel_export` — so the
/// catalog's order, which `recording_probe.py` reads and `tools/list`
/// publishes, and the description `recording_proof.py` section 0 reads, are
/// unchanged by the cut. Nothing arrived widened, since `fileTools` and
/// `recordingTools` are members of the same internal extension of
/// `AgentServer`.
extension AgentServer {

    /// `record_screen`'s one row, spliced into `fileTools(ticks:)` last.
    func recordingTools() -> [[String: Any]] {
        // `record_screen`'s pause paragraph and its result paragraph (road
        // map 3, R2d), hoisted for the type checker's budget: the entry's
        // description is one `+` chain of some seventy literals, and the two
        // paragraphs a paused recording added would have taken it past the
        // type checker's budget in the one place `fileTools` cannot be split.
        // `tools/proof/recording_proof.py` section 0 reads the phrases and
        // every result key off the finished string, so the keys are named
        // here exactly as `AgentServer+RecordingResult.swift` writes them.
        // #97's unreadable paragraph is a third, for the same reason.
        let recordingPauseClause: String =
            "While it records, a status item in the menu bar shows the elapsed time with a "
            + "menu offering Pause Recording and Stop Recording — Resume Recording and Stop "
            + "Recording while it is paused — and File ▸ Pause Recording (Resume Recording "
            + "while paused) and File ▸ Stop Recording work too. A "
            + "person's Stop from the menu bar or the File menu ends an agent's recording "
            + "EARLY and it still lands, with stopped_by: stopped — the same value the "
            + "tool's own stop at the span's end yields — and a duration shorter than the "
            + "span, which is what says so; user_stopped is only the SYSTEM's own "
            + "screen-recording indicator, and system_stopped a display that slept. PAUSE: "
            + "the span is wall clock, so a person's pause SHORTENS what the call records — "
            + "the paused stretch is in no file — and the result's pauses says how many "
            + "times Pause was pressed (0 when never; a pause with no resume before the stop "
            + "still counts). A paused "
            + "recording is a SEQUENCE of files, one per stretch between a start or resume "
            + "and a pause or the stop, each named by its own start time and, with a "
            + "microphone, carrying its own microphone file with its own measured "
            + "mic_offset; every segment lands as its own clip placed at the previous one's "
            + "end on ONE track, touching and never overlapping, and each microphone file as "
            + "its own clip on the Microphone track at its own offset. segments carries one "
            + "entry per file (exactly one for an unpaused recording) and duration is the "
            + "TOTAL recorded across them. "
        let recordingUnreadableClause: String =
            "A segment whose movie will not read (an empty file, from a pause in the instant "
            + "after a resume), or whose writer failed after the segment closed, is LEFT OUT "
            + "rather than failing the recording: the readable "
            + "segments land, and the result's unreadable lists each one left out — path, "
            + "kept_files (what it left on disk), reason, and mic_path, mic_duration, mic_media "
            + "and mic_clip when its microphone file reads, which lands without its picture in "
            + "the slot the picture would have had — with the note naming them; "
            + "only a recording with NO readable movie fails, naming every file. "
        let recordingResultClause: String =
            "The call blocks for seconds plus about a second of start and finish, and up to "
            + "75 s more if the writers are slow to close the files — 60 s more for each "
            + "further segment of a paused recording, whose files are probed in turn; a "
            + "timeout names the movies, which may still finish on their own. THE RESULT "
            + "carries: path (the FIRST segment's movie — the recording's file, the one a "
            + "new project is addressed by); mic_offset (ALWAYS present — the first "
            + "segment's, 0 without a microphone); mic_path and mic_duration (the first "
            + "segment's) when its microphone file landed, and mic_problem — every "
            + "segment's sentence, joined — when a microphone was asked for and any "
            + "segment's did not land, which can stand beside a mic_path when it was a "
            + "later segment's; media and clip (the first segment's ids; clip and mic_clip "
            + "absent with place: false), mic_media and mic_clip (its microphone's); "
            + "duration (ticks — the TOTAL recorded, every segment's summed, which for an "
            + "unpaused recording is the movie's own); width, height, fps [num, den], "
            + "has_audio and audio_tracks — the FIRST segment's movie's (what it holds: "
            + "audio_tracks is 1 with system_audio, else 0 — the microphone is never a "
            + "track of it); pauses (an integer, the count of Pause presses); segments (an "
            + "array, ALWAYS present, one entry per file in order, each with path, "
            + "duration, started_at — the screen's own start as an ISO-8601 UTC timestamp "
            + "to the millisecond — its OWN width, height and fps, because a screen "
            + "recording's rate is whatever the screen did and differs per segment, and "
            + "mic_path, mic_duration, mic_offset and mic_problem on the same terms as the "
            + "top level for THAT segment's files, plus media, clip, mic_media and mic_clip "
            + "when they are known); stopped_by — stopped for the tool's own stop and for a "
            + "person's Stop from Frame Job's menu-bar item or the File menu, user_stopped "
            + "for the system's own screen-recording indicator, system_stopped for a "
            + "display that slept; landed (document or new_project); note, when "
            + "there is something to say; project, the usual summary; and for a document "
            + "landing the created ids as every edit reports them — new_media, new_clips, "
            + "and new_tracks when a track was minted — plus scope and document_ops when it "
            + "landed inside a nest. A failure AFTER the files were written names every one "
            + "of them: \"The recording was saved at <path> but could not be added: …\", the "
            + "movies comma-separated and the microphone files after them. UNDO: for a "
            + "document landing, undo removes every segment's media and clip(s) in ONE step "
            + "and leaves the files on disk, as undoing Add Media… does; a recording that "
            + "opened as a new project has no undo step for its first segment — that "
            + "picture IS the document — and with a microphone on an unpaused recording, "
            + "undo removes the microphone pair (the step is named Add Microphone) and "
            + "leaves the picture, while a PAUSED recording's later segments and every "
            + "microphone clip are one step named Add Recording Segments, so undo leaves "
            + "the first picture alone in the document."
        // #99's voice-over paragraph, hoisted for the same budget reason.
        let recordingVoiceOverClause: String =
            " A VOICE-OVER: source: \"voice_over\" records the DEFAULT microphone alone — the "
            + "panel's Source row Microphone Only — with no picture, into files named "
            + "Voice-over <date> at <time>.m4a, one file per stretch between pauses. Every "
            + "file lands touching, from the playhead, on ONE new back track named "
            + "Microphone, in one undo step (Add Recording); as a new project the first file "
            + "IS the document, 1920×1080 at rate, and the later files touch it on its one "
            + "track. display, window, system_audio, show_clicks, size and "
            + "include_framejob_windows are refused by name with source voice_over, and so is microphone: false (true is implied); "
            + "source is read right after seconds, and only the Microphone grant is read — "
            + "never the Screen Recording one. The result's path is the first .m4a, its "
            + "width and height 0, with no mic_path, and mic_offset 0; a microphone that "
            + "stops on its own ends the voice-over, what it wrote lands, and mic_problem "
            + "and the note say so."
        return [
            // MARK: Recording
            //
            // File ▸ New Recording… (road map 3, R1d; `AgentServer+Recording.swift`).
            // An app-state tool like `transcribe`: no op runs of its own — the
            // landing is `add_media` + `add_clip` through `RecordingLanding`,
            // as the panel's is — so it takes no `scope` (`tool` injects one
            // for the core's op names only) and follows the OPEN container
            // the way the panel does.

            tool(
                "record_screen",
                "Records the screen for seconds and lands the movie as ORDINARY MEDIA — File "
                    + "▸ New Recording…, without the panel. The file goes to ~/Movies/Frame Job "
                    + "Recordings (or the folder path names), named Screen Recording "
                    + "<date> at <time>.mov, and is then imported as import_media imports a "
                    + "file — a media entry — and, with place (the default), placed at the "
                    + "playhead on the front track of whatever container is open (inside a "
                    + "nest when set_scope has one open), or, when that track has no room "
                    + "there, on a new track in front of everything; a paused recording lands "
                    + "one clip per segment (below). With no project open, or "
                    + "when the target document closed while the recording ran, it opens as a "
                    + "NEW untitled project instead and landed says new_project; that document "
                    + "is then addressable by project: <the recording's path>, which is the "
                    + "path get_project reports for it. The canvas of that new project takes "
                    + "rate, while the media record keeps the file's OWN frame rate — for a "
                    + "screen recording that is whatever the screen did, since ScreenCaptureKit "
                    + "delivers a frame only when something changes, so a mostly-still screen "
                    + "reports a low, fractional fps; that is the file, not a defect, and the "
                    + "picture holds its last frame to the end of the sound. A microphone is a "
                    + "SECOND file (<stem> (Microphone).m4a) landing as a second clip on a new "
                    + "back track named Microphone, at the picture's start minus mic_offset — "
                    + "the measured lead of one file over the other, in ticks, positive meaning "
                    + "the picture began after the microphone; a negative start is the head "
                    + "trimmed, not a clip placed late. A microphone that never started, whose "
                    + "writer failed or whose file will not read does NOT fail the recording: "
                    + "the picture lands, that segment's mic_path and mic ids are absent, and "
                    + "mic_problem carries the sentence (the note repeats it). THE GRANTS: this tool never "
                    + "asks for one and never opens the picker. The Screen Recording grant "
                    + "(and the Microphone grant when microphone is true) must already be held "
                    + "by this process — the panel is where somebody grants them — and a "
                    + "missing one is refused by name with the System Settings pane in the "
                    + "sentence. A Frame Job launched from a shell runs under the TERMINAL's "
                    + "grants, not the app icon's, and both refusals then also name the "
                    + "launching process (its pid) and the way out — relaunch with open -a "
                    + "\"Frame Job\", or grant the terminal. THE REFUSAL ORDER is fixed: your own "
                    + "mistakes first (seconds missing or outside 1…600, display and window "
                    + "both given, a rate or size outside the vocabulary, microphone: true "
                    + "without the Microphone grant, a project naming nothing open), then the "
                    + "Screen Recording grant, then the display or window lookup — where a "
                    + "console that is locked or asleep lists NO display and is refused as "
                    + "that, by name — then the recording itself. " + recordingPauseClause
                    + recordingUnreadableClause + recordingResultClause + recordingVoiceOverClause,
                [
                    "seconds": [
                        "type": "number", "minimum": 1, "maximum": 600,
                        "description": "How long to record, 1…600 s. The call returns after "
                            + "the recording has finished, been probed and landed.",
                    ],
                    "source": [
                        "type": "string",
                        "enum": AgentServer.RecordingSourceKind.allCases.map(\.rawValue),
                        "description": "What is recorded: screen (default) — a display or a "
                            + "window — or voice_over, the default microphone alone with no "
                            + "picture (the panel's Microphone Only). With voice_over, "
                            + "display, window, system_audio, show_clicks, size, "
                            + "include_framejob_windows and microphone: false are refused "
                            + "by name.",
                    ],
                    "display": [
                        "type": "integer", "minimum": 0,
                        "description": "Which display, as an index into the shareable "
                            + "displays with 0 the MAIN display (default 0). Frame Job's own "
                            + "windows are left out of a display recording unless "
                            + "include_framejob_windows is true, so by default the app's "
                            + "panel and editor are not in the picture. Exclusive with "
                            + "window.",
                    ],
                    "window": [
                        "type": "integer", "minimum": 0,
                        "description": "A CGWindowID to record on its own — that window's "
                            + "frame, at its own size — instead of a display. Exclusive with "
                            + "display; an id that names no shareable window is refused by "
                            + "name.",
                    ],
                    "microphone": [
                        "type": "boolean",
                        "description": "Record the DEFAULT microphone to a second file beside "
                            + "the movie (default false). Needs the Microphone grant, which "
                            + "only the panel can ask for; without it the call is refused "
                            + "with the grant's status word (notDetermined, denied or "
                            + "restricted) in the sentence.",
                    ],
                    "system_audio": [
                        "type": "boolean",
                        "description": "Capture what the system plays — every application but "
                            + "Frame Job, so the timeline can play meanwhile and not be in "
                            + "it — as the movie's one stereo 48 kHz track (default true). "
                            + "false writes a movie with no audio track, and has_audio "
                            + "reports false.",
                    ],
                    "show_clicks": [
                        "type": "boolean",
                        "description": "Draw a circle around each mouse click (default "
                            + "false). The cursor itself is always in the picture.",
                    ],
                    // The recorder panel's Include Frame Job windows checkbox.
                    "include_framejob_windows": [
                        "type": "boolean",
                        "description": "Put Frame Job's own windows — the editor, the preview — "
                            + "in a DISPLAY recording (default false, which leaves them out). "
                            + "Frame Job's own sound stays out either way, and with window it "
                            + "changes nothing: that window is recorded on its own.",
                    ],
                    "rate": [
                        "type": "integer", "enum": [30, 60],
                        "description": "The capture's frame rate, 30 or 60 (default 60) — the "
                            + "most frames a second the file may hold — and the canvas rate "
                            + "of a new project the recording opens as. The file's own fps "
                            + "is whatever the screen did.",
                    ],
                    "size": [
                        "type": "string", "enum": RecordingResolution.allCases.map { $0.rawValue },
                        "description": "nominal (default) records the display's POINT size; "
                            + "best its PIXEL size, twice the points on a Retina display. An "
                            + "odd dimension is rounded up to even by the encoder.",
                    ],
                    "place": [
                        "type": "boolean",
                        "description": "Put the clip (and the microphone's) on the timeline at "
                            + "the playhead (default true), in ONE undo step with the media. "
                            + "false adds the media to the list and no clip — import_media's "
                            + "shape — and the answer carries no clip or mic_clip id. For a "
                            + "NEW project the picture is the document, so its clips — one "
                            + "per segment, the first at 0 — are on the timeline whatever "
                            + "place says, and the answer notes it.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "A FOLDER to record into instead of ~/Movies/Frame Job "
                            + "Recordings, created if it does not exist. The file's name is "
                            + "always the dated one — this names the folder, never the file — "
                            + "and the answer's path is the file that was written. Trimmed; "
                            + "an empty or blank string means the default folder.",
                    ],
                ], required: ["seconds"]),
        ]
    }
}
