import Foundation

// MARK: - Catalog: files

/// The catalog's FILE half: the eleven tools whose every row is about a path
/// on disk — the six of Media (a file probed into the list, a caption file
/// read onto a track, the package consolidated, and the three raw media ops),
/// the two of Captions (a transcript made, a caption file written), the two
/// of Rendering and export (a frame, and the movie) and, since road map 3,
/// the one of Recording (a movie the app wrote itself). Three of the eleven
/// are ops (`add_media`, `relink_media`, `remove_media`), so they are built
/// with `opTool` — their arguments PRINTED from the core's published table
/// (road map 7's D3) — and get a `scope` as every op does; the other eight
/// are app-state tools of spec §7.9 with no op behind them and nothing to
/// read from that table, so they declare their schemas whole through `tool`.
/// `record_screen` is among those, declaring NO `scope` by construction,
/// since `tool` injects one for the core's op names only and the parity
/// check's fourth part reads those.
///
/// A pure move out of `AgentCatalog.swift`, which stood at 807 lines against
/// app/CLAUDE.md's ~600 cap — road map 2's phase 9 had put it back over the
/// cut `AgentCatalog+Clips.swift` bought — and whose own header named this
/// cut in advance. It is road map 3's R1·toll, paid first and alone. The
/// seam is the one the file had drawn: `// MARK: Media`, `// MARK: Captions`
/// and `// MARK: Rendering and export` came here whole, in their existing
/// order, with their bodies untouched, and so did the six hoisted locals
/// nothing outside them reads — `captionFormatNames` and its property,
/// `frameFormatNames` and its property, `burnInProperty`,
/// `exportPresetProperty` and `exportSizeProperty`.
///
/// **One hoisted local IS shared, and it arrives as an argument**, exactly as
/// the clip rows take three: `render_frame`'s `t` row reads `ticks`, which
/// the Projects and Markers groups read as well, so `ticks` stayed on the
/// other side and is handed in here. The old header's "none of them shares a
/// hoisted local with the groups that stay" was false by exactly that one,
/// and it is corrected there.
///
/// These three groups are the LAST three of the catalog, so the splice is an
/// append after the Canvas group and the catalog's order — the order an agent
/// reads the tools in — is what it always was; `tools/list` byte-identical
/// before and after the cut is the gate that says so. The move is about 400
/// lines rather than the 300 the old header guessed, which is the warning
/// this project keeps re-learning about budgeting a cut against the
/// pessimistic number.
extension AgentServer {

    /// The file rows of `catalogJSON()`'s array, in its order: Media,
    /// Captions, Rendering and export, then Recording — appended LAST, so
    /// the eighty-four rows before it list in the order they always did.
    func fileTools(ticks: String) -> [[String: Any]] {
        // `render_frame`'s three image containers, read off `FrameWriter`'s
        // own enum rather than restated, and hoisted for the same budget
        // reason.
        let frameFormatNames = FrameWriter.Format.allCases.map { $0.rawValue }
        let frameFormatProperty: [String: Any] = [
            "type": "string", "enum": frameFormatNames,
            "description": "The container to write. Default: the path's own extension when it "
                + "is one of those (.jpg counts as jpeg), else png — so a call with no path "
                + "and no format writes a PNG, as it always has. An explicit format WINS and "
                + "the path's extension is REPLACED rather than appended to, so {path: "
                + "\"shot.jpg\", format: \"png\"} writes shot.png. png and heic keep the "
                + "canvas's alpha; \(FrameWriter.flattenNote)",
        ]
        // The burn-in argument, written ONCE and shared by `render_frame` and
        // `export`: the two are the same question about the same layer, and
        // two spellings of it would drift the first time either was edited.
        let burnInProperty: [String: Any] = [
            "type": "boolean",
            "description": "Draw the project timecode over the picture, topmost — the export "
                + "sheet's Burn in timecode checkbox. Default: false. It is a review copy's "
                + "reference, so it reads the DOCUMENT'S timecode in the document's own "
                + "spelling (the toolbar's, non-drop, HH:MM:SS:FF or HH:MM:SS.mmm), and it "
                + "shows PROJECT time even in a file written from the in/out range: a range "
                + "export starting at 00:00:10:00 begins at 00:00 carrying a burn-in that "
                + "reads 00:00:10:00, which is the number a note about that frame needs.",
        ]
        // `export`'s two alpha-bearing arguments, hoisted for the budget
        // reason above and because both had to grow the same sentence.
        //
        // **A capability an agent cannot read is a capability it does not
        // have.** Phase 7b gave the table two rows that keep a transparent
        // canvas and gave `ExportWriter` a refusal for one of them, and
        // neither reached the schema — so the tool promised a letterbox where
        // the build throws, and the row to ask for was named nowhere a caller
        // could see it. The refusal is `prores_4444`'s alone: `apng` takes
        // the ImageIO path, which FITS instead of padding.
        let exportPresetProperty: [String: Any] = [
            "type": "string",
            "description": "Export preset id — one per encoding, a container and a codec with "
                + "no size of its own (that is size's). h264 is what the export sheet opens "
                + "on. Two rows keep a transparent canvas transparent: prores_4444 (the movie "
                + "row — see size, which it constrains) and apng. gif is not one of them: it "
                + "can show a transparent pixel but has no alpha channel, so nothing partial "
                + "survives it. Pass a wrong one once and the error lists them all.",
        ]
        let exportSizeProperty: [String: Any] = [
            "type": ["string", "array"],
            "items": ["type": "integer"], "minItems": 2, "maxItems": 2,
            "description": "Output size — the sheet's Size popup. A row id: document (the "
                + "default, the document's own size), 1080p, 720p, 1440p or 2160p (the number "
                + "is the SHORT edge and the long edge follows the document's aspect, rounded "
                + "to even, so a vertical project's 1080p is 1080 × 1920), or preset for an "
                + "image format's cap (gif and apng, where it is the default) — or an explicit "
                + "[width, height] in px, the sheet's Custom…. Every row exists on every "
                + "document — a 1920 × 1080 project's 1080p is its own size and is listed "
                + "anyway — so an id means the same thing wherever it is sent; only preset is "
                + "confined to gif and apng. Omit for the document size or the image format's "
                + "cap; a wrong id's error lists the ids. A movie is written at exactly the "
                + "size asked for, letterboxed if the aspect differs — except on prores_4444, "
                + "where a size of a DIFFERENT ASPECT from the canvas is refused rather than "
                + "written, because the padding destroys the alpha channel that row is chosen "
                + "for; every row id is already the document's own aspect, so this only bites "
                + "on a [width, height] of another shape. On gif and apng a size — the cap, a "
                + "row, or [width, height] — is a box the picture is fitted inside, aspect "
                + "kept and never upscaled, and the width and height reported back are the "
                + "file's: a vertical 1080 × 1920 project's GIF default is 152 × 270.",
        ]
        // `record_screen`'s pause paragraph and its result paragraph (road
        // map 3, R2d), hoisted for the budget reason above: the entry's
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
            + "person's Stop from Reelcut's menu-bar item or the File menu, user_stopped "
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
            + "include_reelcut_windows are refused by name with source voice_over, and so is microphone: false (true is implied); "
            + "source is read right after seconds, and only the Microphone grant is read — "
            + "never the Screen Recording one. The result's path is the first .m4a, its "
            + "width and height 0, with no mic_path, and mic_offset 0; a microphone that "
            + "stops on its own ends the voice-over, what it wrote lands, and mic_problem "
            + "and the note say so."
        var rows: [[String: Any]] = [
            // MARK: Media

            tool(
                "import_media",
                "Probes a movie, sound file or picture and adds it to the project's media list, "
                    + "returning its new media id — File ▸ Add Media…. It is NOT on the timeline "
                    + "yet: place it with add_clip {track, media, at}. The result also reports "
                    + "what the probe found (kind, duration, display size, frame rate, whether "
                    + "it has video, audio or an alpha channel), which is what you need to place "
                    + "and size it. A WebM or Matroska file is copied into a .mov first: the "
                    + "result's path is the copy and its original is the file you named, which "
                    + "the media is named after. A file the opt-in ffmpeg step converts is "
                    + "recorded the same way.",
                ["path": ["type": "string", "description": "Absolute or ~ path to the file."]],
                required: ["path"]),
        ]
        // import_captions is `AgentCatalog+Captions.swift`'s, spliced in HERE
        // rather than appended, so the catalog's order is unchanged — road
        // map 6's C1 toll 2. It reads no hoisted local.
        rows += captionImportTools()
        rows += [
            tool(
                "consolidate_media",
                "Copies every file the project references into media/ inside the .reelcut "
                    + "package and relinks the project at the copies — File ▸ Consolidate "
                    + "Media…. Afterwards the package is the whole edit: it can be moved or "
                    + "archived and still open with its original footage deleted. The project "
                    + "must have been saved (call save_project with a path first); files that "
                    + "are already inside are left alone, missing files are reported rather "
                    + "than guessed at, and a file that cannot be copied leaves its media entry "
                    + "pointing at the original, so the project always still opens. This can "
                    + "take a while and copies as many bytes as the footage weighs.",
                [:]),
            opTool(
                "add_media",
                "The raw op behind import_media: adds a media entry from a descriptor you "
                    + "supply — the media[] element of the project JSON minus its id (path, "
                    + "bookmark, kind, duration, width, height, fps [num, den], has_video, "
                    + "has_audio, has_alpha, original {path, bookmark?} — the file a .mov copy "
                    + "or conversion was made from). Probing files is the host's job, so "
                    + "unless you are replaying a project's own JSON, call import_media and let "
                    + "it probe.",
                ["descriptor": "The media entry to add; only path is required."]),
            opTool(
                "relink_media",
                "Points a media entry at a file that moved — the Relink… sheet. The host probes "
                    + "the new file as import_media does, and the entry takes that file's "
                    + "duration, size, frame rate and audio/video/alpha flags. A file of another "
                    + "kind (audio for a video entry, say) is refused. A clip that runs past the "
                    + "end of a shorter file is shortened to end with it. A bookmark for the new "
                    + "location is stored so the next move is followed automatically. A WebM or "
                    + "Matroska file is copied into a .mov first and recorded as the entry's new "
                    + "original (the result's original), and a file the opt-in ffmpeg step "
                    + "converts is recorded the same way; any other file clears it. "
                    + "get_project's missing_media names the entries that need this.",
                [
                    "media": "Media id.",
                    "path": "Where the file is now.",
                    "bookmark": "Base64 security bookmark; omit and one is made for you.",
                ]),
            opTool(
                "remove_media",
                "Removes a media entry from the project. Media still used by clips is refused "
                    + "unless with_clips is true, which removes those clips with it.",
                [
                    "media": "Media id.",
                    "with_clips": "Remove the clips using it too (default false).",
                ]),
        ]
        // transcribe and export_captions are `AgentCatalog+Captions.swift`'s
        // as well, with their `// MARK: Captions` note and the one hoisted
        // local only they read, spliced in HERE for the same reason.
        rows += captionTools()
        rows += [

            // MARK: Rendering and export

            tool(
                "render_frame",
                "Renders one frame of the finished timeline as a picture so you can SEE the "
                    + "result — the verification hook. It goes through the same composition and "
                    + "the same Metal compositor an export does, so this is what the file will "
                    + "contain at that moment, not a preview of it. The image comes back both "
                    + "as an image block and as a file on disk whose path the text names. Use it "
                    + "before and after every edit. It writes a PNG to a temporary file unless "
                    + "path or format says otherwise, so a call that names neither is exactly "
                    + "the call it always was. When a graphic in the frame warned or failed, a "
                    + "sentence before the last names the graphic, its frame and the "
                    + "diagnostic; a failed graphic draws its error card in the picture.",
                [
                    "t": [
                        "type": "integer",
                        "description": "The moment to render, \(ticks) Default: the playhead.",
                    ],
                    "max_width": [
                        "type": "integer", "minimum": 16, "maximum": 8192,
                        "description": "Cap the image's width in px, aspect kept and never "
                            + "upscaled. Default: the canvas's own size.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write the file, e.g. ~/Desktop/shot.png. The "
                            + "folder must exist. Omit for a temporary file; either way the "
                            + "text block's last sentence names the file that was written. "
                            + "This is the same writer File ▸ Save Frame… uses, so a PNG "
                            + "written here and one saved from the menu are byte-identical.",
                    ],
                    "format": frameFormatProperty,
                    "burn_in_timecode": burnInProperty,
                ]),
            tool(
                "export",
                "Writes the timeline to a file and waits for it to finish — ⌘E, the export "
                    + "sheet's six controls (format, size, frame rate, quality, loudness, "
                    + "range) in the sheet's own vocabulary, all but the frame rate — this "
                    + "exports at the "
                    + "document's rate, or on gif and apng at the format's own rate (12.5 and "
                    + "25 fps). The preset is the ENCODING only and the size a separate "
                    + "choice defaulting to the document's own, or on gif and apng to the "
                    + "format's cap; the core resolves both into concrete settings "
                    + "(container, codec, size, rate, range) and hands them to the same "
                    + "exporter the sheet uses, so an agent export and a menu export cannot "
                    + "disagree. An existing file at the path is replaced, and the "
                    + "container's extension is added when the path has none. The result "
                    + "reports the settings that were used, the file's size, and — for every "
                    + "format that carries sound, normalised or not — what that sound "
                    + "MEASURED on the way through, under loudness: integrated_lufs, "
                    + "true_peak_dbtp and the gain_db that was applied. Those are read off "
                    + "the mix that was written, so they are what the file holds rather than "
                    + "what was asked for. A graphic clip whose module does not compile "
                    + "refuses the export before it starts; a graphic that fails during it "
                    + "stops the export with no file left, naming the graphic and the frame. "
                    + "graphic_warnings [{name, frame, message}]: each distinct warning a "
                    + "graphic gave while the file was drawn, absent when none.",
                [
                    "preset": exportPresetProperty,
                    "path": [
                        "type": "string",
                        "description": "Where to write, e.g. ~/Movies/cut.mp4. The folder must "
                            + "exist.",
                    ],
                    "size": exportSizeProperty,
                    "range": [
                        "type": "string",
                        "enum": ["project", "in_out"],
                        "description": "What to write: the whole timeline (default), or just "
                            + "the in/out range set_range set — the sheet's Range popup.",
                    ],
                    "video_bitrate": [
                        "type": "integer", "minimum": 1,
                        "description": "Target video rate in BITS per second (8000000 is "
                            + "8 Mbps) — the sheet's Quality popup. Omit to let the preset's "
                            + "own encoder settings decide. Ignored by presets that carry no "
                            + "rate of their own: ProRes is fixed by its profile, and GIF and "
                            + "APNG have no bitrate at all.",
                    ],
                    "audio_bitrate": [
                        "type": "integer", "minimum": 1,
                        "description": "Target AAC rate in BITS per second (192000 is "
                            + "192 kbps) — the sheet's Quality popup. Omit for the preset's "
                            + "own. Ignored where the sound is not AAC: ProRes, WAV and AIFF "
                            + "all write LPCM, whose rate is its sample format.",
                    ],
                    "loudness_lufs": [
                        "type": "number", "minimum": -70, "maximum": 0,
                        "description": "Normalise the whole mix to this integrated loudness, "
                            + "in LUFS — the sheet's Loudness popup, whose rows are -14 "
                            + "(streaming), -16 (podcast) and -23 (EBU R 128 broadcast). The "
                            + "export measures itself first and then applies ONE gain to "
                            + "everything, so relative levels inside the timeline are "
                            + "untouched and no limiter is involved. Omit not to normalise: "
                            + "the export still measures and still reports. Ignored where "
                            + "there is no sound to measure (gif, apng).",
                    ],
                    "peak_dbtp": [
                        "type": "number", "minimum": -20, "maximum": 0,
                        "description": "The true-peak ceiling that gain is capped against, in "
                            + "dBTP. The sheet fixes it at -1 and this is the knob for "
                            + "anything else. Because normalisation is gain-only, a ceiling "
                            + "with no loudness_lufs beside it would have nothing to cap and "
                            + "is REFUSED rather than accepted and left inert. When the "
                            + "ceiling bites, the file lands quieter than the target asked "
                            + "for and the result's capped_by_peak says so.",
                    ],
                    "burn_in_timecode": burnInProperty,
                ], required: ["preset", "path"]),

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
                    + "▸ New Recording…, without the panel. The file goes to ~/Movies/Reelcut "
                    + "Recordings (or the folder path names), named Screen Recording "
                    + "<date> at <time>.mov, and is then imported exactly as import_media "
                    + "imports a file: a media entry, and with place (the default) one clip "
                    + "at the playhead on the front track of whatever container is open — "
                    + "inside a nest when set_scope has one open. With no project open, or "
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
                    + "sentence. A Reelcut launched from a shell runs under the TERMINAL's "
                    + "grants, not the app icon's, and both refusals then also name the "
                    + "launching process (its pid) and the way out — relaunch with open -a "
                    + "Reelcut.app, or grant the terminal. THE REFUSAL ORDER is fixed: your own "
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
                            + "include_reelcut_windows and microphone: false are refused "
                            + "by name.",
                    ],
                    "display": [
                        "type": "integer", "minimum": 0,
                        "description": "Which display, as an index into the shareable "
                            + "displays with 0 the MAIN display (default 0). Reelcut's own "
                            + "windows are left out of a display recording unless "
                            + "include_reelcut_windows is true, so by default the app's "
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
                            + "Reelcut, so the timeline can play meanwhile and not be in "
                            + "it — as the movie's one stereo 48 kHz track (default true). "
                            + "false writes a movie with no audio track, and has_audio "
                            + "reports false.",
                    ],
                    "show_clicks": [
                        "type": "boolean",
                        "description": "Draw a circle around each mouse click (default "
                            + "false). The cursor itself is always in the picture.",
                    ],
                    // The recorder panel's Include Reelcut windows checkbox.
                    "include_reelcut_windows": [
                        "type": "boolean",
                        "description": "Put Reelcut's own windows — the editor, the preview — "
                            + "in a DISPLAY recording (default false, which leaves them out). "
                            + "Reelcut's own sound stays out either way, and with window it "
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
                        "description": "A FOLDER to record into instead of ~/Movies/Reelcut "
                            + "Recordings, created if it does not exist. The file's name is "
                            + "always the dated one — this names the folder, never the file — "
                            + "and the answer's path is the file that was written. Trimmed; "
                            + "an empty or blank string means the default folder.",
                    ],
                ], required: ["seconds"]),
        ]
        return rows
    }
}
