import Foundation

// MARK: - Catalog: captions

/// The catalog's CAPTION rows: `import_captions`, the file reader of the
/// Media group, and `transcribe` and `export_captions`, the two app-state
/// tools of spec §7.9 that make and write captions — three of the eleven
/// `fileTools` publishes, and the ones road map 6's C1 goes on to change.
///
/// A pure move out of `AgentCatalog+Files.swift`, which stood at 601 lines
/// against app/CLAUDE.md's ~600 cap: road map 6's C1 toll 2, paid first and
/// alone. `AgentCatalog+Audio.swift`'s header is the model. The three rows
/// came here whole, in their existing order, with their bodies untouched,
/// and are SPLICED back in at the two points they left — `import_captions`
/// after `import_media`, `transcribe` and `export_captions` after
/// `remove_media` — so the catalog's order, which `recording_probe.py`
/// reads and `tools/list` publishes, is byte-identical before and after
/// the cut. `captionFormatNames` and `captionFormatProperty`, the hoisted
/// local only `export_captions` reads, moved with them; nothing arrived
/// widened, since `fileTools` and these two are members of the same
/// internal extension of `AgentServer`.
extension AgentServer {

    /// `import_captions`' row, spliced into `fileTools`'s Media group
    /// where it has always been, after `import_media`.
    func captionImportTools() -> [[String: Any]] {
        return [
            tool(
                "import_captions",
                "Reads a SubRip (.srt) caption file and lays it out as TEXT CLIPS, one per cue, "
                    + "on a new track of its own — File ▸ Import Captions…. They are ordinary "
                    + "text clips in the Caption preset, so they render in the preview, in "
                    + "render_frame and in an export (burn-in) with no further step, and any of "
                    + "them can be retimed with move_clip or restyled with set_text. Times snap "
                    + "to the frame grid; a cue that overlapped the next one is shortened to "
                    + "meet it. The result reports how many cues landed and, under skipped, "
                    + "every entry the file was too malformed to read, with its line number.",
                [
                    "path": [
                        "type": "string",
                        "description": "Absolute or ~ path to the .srt file.",
                    ],
                    "track": [
                        "type": "integer",
                        "description": "Put the captions on this existing track instead of a "
                            + "new one. Cues the overlap rule refuses there are dropped, so "
                            + "prefer omitting it.",
                    ],
                ], required: ["path"]),
        ]
    }

    /// `transcribe`'s and `export_captions`' rows with their own
    /// `// MARK: Captions` note, spliced into `fileTools` after
    /// `remove_media` where they have always been.
    func captionTools() -> [[String: Any]] {
        // `export_captions`' container list, read off the exporter's own enum
        // rather than restated, and hoisted for the type-checker budget reason
        // `AgentCatalog+Clips.swift`'s own hoisted clauses record.
        let captionFormatNames = CaptionExporter.Format.allCases.map { $0.rawValue }
        let captionFormatProperty: [String: Any] = [
            "type": "string", "enum": captionFormatNames,
            "description": "srt (SubRip) or vtt (WebVTT). Default: the path's own extension "
                + "when it is one of those, else srt. An explicit format WINS, and the path's "
                + "extension is replaced rather than appended to — the result reports the file "
                + "that was really written.",
        ]
        return [

            // MARK: Captions
            //
            // `import_captions` is up in Media with the other file readers;
            // these two are the app-state tools of spec §7.9 that make and
            // write captions rather than reading a file into the project.

            // It mirrors File ▸ Generate Captions… — the sheet's clip scope,
            // its language popup, its ENGINE popup, its three cloud rows and
            // its progress bar are these arguments, this result and nothing
            // else. The two the sheet has and this tool deliberately has not:
            // the REGION, which is a person's setting and no tool's (R6-12),
            // and the sheet's memory of the engine, which an agent call never
            // reads (R6-2). c1-chrome landed them; the sentence that said
            // they had not is gone (the reader review, §10.13, R5·1).
            tool(
                "transcribe",
                "Transcribes clips and lays the result out as TEXT CLIPS, one per cue, on a new "
                    + "track of its own — File ▸ Generate Captions…. They are ordinary text "
                    + "clips in the Caption preset, exactly what import_captions makes, so they "
                    + "render in the preview, in render_frame and in an export (burn-in) and "
                    + "can be retimed with move_clip or restyled with set_text. Cues are at "
                    + "most two lines of 42 characters and at most 6 s, with a frame between "
                    + "them. A word caption STYLE (every style but subtitles) makes PAGES "
                    + "instead: each page is filled to the width it will MEASURE on this "
                    + "canvas in that style — at most 0.86 of the canvas width — not to a word "
                    + "count, on one line (karaoke: up to two); a page also closes at a "
                    + "change of speaker, a gap of 0.25 s or more, a word ending . ? ! or …, "
                    + "3 s on screen, and one_word's single word; a lone word too wide "
                    + "shrinks to 80% before it wraps. Pages stay within their own clip and "
                    + "abut the next page where the gap is under 0.25 s, else hold 0.5 s "
                    + "after the last word. Each placed page is a text clip in the style's "
                    + "face, case and word_style carrying its words' timings, so the word "
                    + "being said is drawn as the style says. The result carries the cues "
                    + "themselves in TICKS whether or not they were placed — with a word "
                    + "style each cue adds words, [{start, end, text}] in timeline ticks, and "
                    + "size where a lone word shrank — names the engine that ran, reports "
                    + "under skipped every clip you named that cannot be transcribed, and, "
                    + "whenever replace was given, lists under replaced the tracks it "
                    + "removed. "
                    + "ENGINE \"apple\" (the default) is ON-DEVICE speech recognition and "
                    + "nothing leaves this Mac. It needs no grant and has no length ceiling. "
                    + "Its models are installed per Mac: a language whose model is not "
                    + "installed is refused by name and nothing is changed — this tool never "
                    + "downloads one; a person installs it from File ▸ Generate Captions…'s "
                    + "Download row. "
                    + "ENGINE \"assemblyai\" sends the audio of every media file behind the "
                    + "clips you named — the WHOLE file, not just the parts in use — to "
                    + "AssemblyAI, a cloud service that transcribes it and is billed for it, "
                    + "and the transcript is deleted from AssemblyAI once the words have been "
                    + "read back; do not choose it for somebody else's recording without their "
                    + "say-so. New transcription needs an API key (Reelcut ▸ Settings ▸ "
                    + "Transcription, or RC_ASSEMBLYAI_KEY); a nonempty batch whose every "
                    + "media has a current packaged transcript can be reused without a key "
                    + "or network request, unless refresh is true. Pending remote deletion "
                    + "is reported as deferred until a later run with the originating "
                    + "account and region's key can safely retry it. It needs no grant "
                    + "and caches one transcript per media file "
                    + "inside the project package, so a second run over the same files makes no "
                    + "request and reports them under cached. It adds uploaded, cached, "
                    + "audio_seconds (what was billed), speech_model_used, language_detected, "
                    + "endpoint (the host alone of the server a keyed run's requests go to; "
                    + "absent when no API key is set) and, when there is something to say, note.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Transcribe only these clips — the sheet's scope. Omit "
                            + "for every clip in the project that has recorded sound. Only a "
                            + "clip playing a movie or sound file can be transcribed, and not "
                            + "one played in REVERSE, whose words would come out backwards; a "
                            + "clip you name that cannot be is reported under skipped.",
                    ],
                    "engine": [
                        "type": "string", "enum": ["apple", "assemblyai"],
                        "description": "Where the recognition happens: apple (default) on this "
                            + "Mac, assemblyai in the cloud. Anything else is refused with both "
                            + "spellings named. The default is NEVER what the sheet last chose "
                            + "— an agent that wants the cloud says so every time.",
                    ],
                    "language": [
                        "type": "string",
                        "description": "A language tag, e.g. en-US. WITH apple: this Mac's own "
                            + "language by default. The two ways a tag can be wrong are two "
                            + "different problems with two different fixes, so they are refused "
                            + "SEPARATELY and the message says which you have. A tag speech "
                            + "recognition has never heard of is a misspelling: it is refused "
                            + "with the tags it does know. A tag it knows whose on-device "
                            + "MODEL is not installed on this Mac is refused as not installed, "
                            + "with the languages ready here: a person has to install it from "
                            + "the Generate Captions sheet, and this tool never downloads. "
                            + "WITH assemblyai: \"auto\" "
                            + "(the default) detects it and the result reports what was "
                            + "detected and how sure it was; a code is passed through "
                            + "unchecked, and one AssemblyAI does not support comes back as its "
                            + "own sentence after the upload.",
                    ],
                    "place": [
                        "type": "boolean",
                        "description": "Place the cues as text clips (default true), as ONE "
                            + "undo step. false returns the cues and changes nothing at all — "
                            + "no edit, no undo step — which is the way to check a transcript "
                            + "before committing to it.",
                    ],
                    "style": [
                        "type": "string", "enum": CaptionStyle.allCases.map { $0.rawValue },
                        "description": "subtitles (default: two-line cues in the Caption "
                            + "preset, unchanged) or a word caption style that shows each "
                            + "word as it is said: highlight (Montserrat Black, upper case, "
                            + "the word in yellow with a pop), pill (Montserrat ExtraBold, "
                            + "upper case, the word on a violet pill), karaoke (Montserrat "
                            + "ExtraBold as written, up to two lines, words turning yellow), "
                            + "build (Anton, upper case, words appearing one by one) or "
                            + "one_word (Bebas Neue, one large word at a time). Anything else "
                            + "is refused with the six named. A style is a display choice: "
                            + "a cached transcript is reused whatever style is asked for, "
                            + "and restyling is running transcribe again with replace.",
                    ],
                    "replace": [
                        "type": "boolean",
                        "description": "With a word style and place true only — refused by "
                            + "name with subtitles or with place false. true removes, in the "
                            + "SAME undo step, every caption track this command could have "
                            + "made over these clips: named Captions or Captions N, holding "
                            + "only text clips, each of which overlaps a clip being "
                            + "transcribed. The result lists them under replaced.",
                    ],
                    "refresh": [
                        "type": "boolean",
                        "description": "engine \"assemblyai\" only. Ignore the cached "
                            + "transcript and upload again (default false). Refused by name "
                            + "with engine \"apple\", which has no cache.",
                    ],
                    "speakers": [
                        "type": "boolean",
                        "description": "engine \"assemblyai\" only. Ask for speaker labels "
                            + "(default false); a change of speaker then starts a new cue. "
                            + "Refused by name with engine \"apple\".",
                    ],
                    "vocabulary": [
                        "type": "array", "items": ["type": "string"],
                        "description": "engine \"assemblyai\" only. Words and phrases to expect "
                            + "— product names, people, identifiers. Trimmed, de-duplicated "
                            + "keeping the first spelling, and capped at 1000 terms with the "
                            + "cap named in note. Refused by name with engine \"apple\".",
                    ],
                ]),
            tool(
                "export_captions",
                "Writes one text track out as a subtitle file — File ▸ Export Captions…. Every "
                    + "text clip on the track becomes one cue at the time it sits at, in the "
                    + "order they play. THE TRACK IS NEVER GUESSED: the default is the single "
                    + "track whose clips are ALL text clips, and with none or with more than "
                    + "one the call is refused and the candidates listed by id and name — "
                    + "writing the wrong track and reporting success is the failure this rule "
                    + "prevents. WebVTT escapes &, < and > where SubRip does not, so on text "
                    + "containing none of the three the two files differ only by the WEBVTT "
                    + "header, the missing index lines and a . where SubRip writes a , in the "
                    + "timestamps. A round trip back through import_captions returns every cue "
                    + "to the TICK it was written from, at every ordinary frame rate: a "
                    + "timestamp is rounded to the nearest millisecond, at most 300 ticks, and "
                    + "half a frame is 10,000 ticks even at 30 fps, so the snap on the way "
                    + "back in lands on the frame the cue left. What is not exact is the "
                    + "FILE: import_captions snaps every cue to the frame grid, so a source "
                    + "whose times are off that grid comes back written onto it — at 30 fps "
                    + "00:00:04,120 returns as 00:00:04,133 — and byte identity with the file "
                    + "you imported needs cue times already on the grid AND a frame that is a "
                    + "whole number of milliseconds, which is 25 or 50 fps. Nothing is edited "
                    + "and no undo step is registered.",
                [
                    "track": [
                        "type": "integer",
                        "description": "The track to write. Omit when the project has exactly "
                            + "one all-text track; a track that is not one of the candidates "
                            + "is refused by name, since a clip with no words would export as "
                            + "a blank cue.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write, e.g. ~/Movies/talk.srt. The folder "
                            + "must exist. A trailing .srt or .vtt is replaced by the format's "
                            + "own; any other extension is kept as part of the name (chart.png "
                            + "→ chart.png.srt).",
                    ],
                    "format": captionFormatProperty,
                ], required: ["path"]),
        ]
    }
}
