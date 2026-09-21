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

            tool(
                "transcribe",
                "Transcribes clips with ON-DEVICE speech recognition and lays the result out as "
                    + "TEXT CLIPS, one per cue, on a new track of its own — File ▸ Generate "
                    + "Captions…. They are ordinary text clips in the Caption preset, exactly "
                    + "what import_captions makes, so they render in the preview, in "
                    + "render_frame and in an export (burn-in) and can be retimed with "
                    + "move_clip or restyled with set_text. Cues are at most two lines of 42 "
                    + "characters and at most 6 s, with a frame between them. THE GRANT: macOS "
                    + "gates speech recognition, and this tool never asks for it — the system "
                    + "prompt needs the app to be frontmost and an agent-driven app never is, "
                    + "so without the grant the call is refused with the authorization status "
                    + "named and nothing is changed; somebody has to run File ▸ Generate "
                    + "Captions… once from the app. Recognition also stops after about a "
                    + "minute per clip: when it does, the result says so under truncated with "
                    + "the time it stopped at, rather than ending quietly. The result carries "
                    + "the cues themselves in TICKS whether or not they were placed, and "
                    + "reports under skipped every clip you named that cannot be transcribed.",
                [
                    "clips": [
                        "type": "array", "items": ["type": "integer"], "minItems": 1,
                        "description": "Transcribe only these clips — the sheet's scope. Omit "
                            + "for every clip in the project that has recorded sound. Only a "
                            + "clip playing a movie or sound file can be transcribed, and not "
                            + "one played in REVERSE, whose words would come out backwards; a "
                            + "clip you name that cannot be is reported under skipped.",
                    ],
                    "language": [
                        "type": "string",
                        "description": "A language tag, e.g. en-US. Default: this Mac's own "
                            + "language. The two ways a tag can be wrong are two different "
                            + "problems with two different fixes, so they are refused "
                            + "SEPARATELY and the message says which you have. A tag speech "
                            + "recognition has never heard of is a misspelling: it is refused "
                            + "with the tags it does know, and answered before the grant is "
                            + "even read, so you get that answer on a machine nobody has "
                            + "granted yet. A tag it knows that this Mac has no on-device "
                            + "MODEL for is a download instead: that refusal names System "
                            + "Settings ▸ Keyboard ▸ Dictation and lists the languages ready "
                            + "here, and it comes after the grant, because an ungranted Mac "
                            + "cannot be asked which models it has.",
                    ],
                    "place": [
                        "type": "boolean",
                        "description": "Place the cues as text clips (default true), as ONE "
                            + "undo step. false returns the cues and changes nothing at all — "
                            + "no edit, no undo step — which is the way to check a transcript "
                            + "before committing to it.",
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
                            + "must exist.",
                    ],
                    "format": captionFormatProperty,
                ], required: ["path"]),
        ]
    }
}
