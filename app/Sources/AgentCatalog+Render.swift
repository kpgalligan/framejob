import Foundation

// MARK: - Catalog: rendering and export

/// The catalog's RENDERING rows: `render_frame`, the verification hook, and
/// `export`, the movie — two of the eleven `fileTools` publishes, and the
/// ones grading-2's G2-1 goes on to change (`render_frame`'s scope
/// booleans, spec §11 GR-10).
///
/// A pure move out of `AgentCatalog+Files.swift`, which stood at 579 lines
/// against app/CLAUDE.md's ~600 cap with no seam named: grading-2's G2-0,
/// paid first and alone. `AgentCatalog+Captions.swift`'s header is the
/// model. The rows under the file's own `// MARK: Rendering and export` came here whole,
/// with its bodies untouched, and is SPLICED back in at the point it left —
/// after `export_captions`, before `record_screen` — so the catalog's order,
/// which `recording_probe.py` reads and `tools/list` publishes, is
/// byte-identical before and after the cut. The five hoisted locals only
/// these two rows read moved with them: `frameFormatNames` and
/// `frameFormatProperty`, `burnInProperty` (shared by the two),
/// `exportPresetProperty` and `exportSizeProperty`. `render_frame`'s `t`
/// row reads `ticks`, which the Projects and Markers groups read as well, so
/// it arrives as an argument, as it does in `fileTools`. Nothing arrived
/// widened, since `fileTools` and `renderTools` are members of the same
/// internal extension of `AgentServer`.
extension AgentServer {

    /// `render_frame` and `export`, in that order: the rows `fileTools`
    /// splices in after the Captions group and before Recording.
    func renderTools(ticks: String) -> [[String: Any]] {
        // `render_frame`'s three image containers, read off `FrameWriter`'s
        // own enum rather than restated, and hoisted for the type checker's
        // budget.
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
        // `export`'s two alpha-bearing arguments, hoisted for the type checker's
        // budget and because both had to grow the same sentence.
        //
        // **A capability an agent cannot read is a capability it does not
        // have.** Phase 7b gave the table two rows that keep a transparent
        // canvas and gave `ExportWriter` a refusal for one of them, and
        // neither reached the schema — so the tool promised a letterbox where
        // the build throws, and the row to ask for was named nowhere a caller
        // could see it. There are three such rows since G-33, and the refusal
        // is the two MOVIE rows', `prores_4444` and `hevc_alpha`: `apng`
        // takes the ImageIO path, which FITS instead of padding.
        let exportPresetProperty: [String: Any] = [
            "type": "string",
            "description": "Export preset id — one per encoding, a container and a codec with "
                + "no size of its own (that is size's). h264 is what the export sheet opens "
                + "on. Three rows keep a transparent canvas transparent: prores_4444 and "
                + "hevc_alpha (the movie rows — see size, which constrains them) and apng. "
                + "gif is not one of them: it can show a transparent pixel but has no alpha "
                + "channel, so nothing partial survives it. prores_422, prores_4444 and "
                + "hevc_10bit keep the compositor's 16-bit frames at 10 bits (ProRes 4444 at "
                + "12); h264, hevc and hevc_alpha are 8-bit. Pass a wrong one once and the "
                + "error lists them all.",
        ]
        let exportSizeProperty: [String: Any] = [
            "type": ["string", "array"],
            "items": ["type": "integer"], "minItems": 2, "maxItems": 2,
            "description": "Output size — the sheet's Size popup. A row id: document (the "
                + "default, the document's own size, evened on the formats that need it), "
                + "1080p, 720p, 1440p or 2160p (the number is the SHORT edge and the long "
                + "edge follows the document's aspect, rounded to even, so a vertical "
                + "project's 1080p is 1080 × 1920), or preset for an "
                + "image format's cap (gif and apng, where it is the default) — or an explicit "
                + "[width, height] in px, the sheet's Custom…. Every row exists on every "
                + "document — a 1920 × 1080 project's 1080p is its own size and is listed "
                + "anyway — so an id means the same thing wherever it is sent; only preset is "
                + "confined to gif and apng. Omit for the document size or the image format's "
                + "cap; a wrong id's error lists the ids. A movie is written at exactly the "
                + "size asked for, letterboxed if the shape differs by more than a pixel "
                + "(within a pixel the picture fills the frame instead) — except on "
                + "prores_4444 and hevc_alpha, where a size of a DIFFERENT SHAPE from the "
                + "canvas is refused rather than written, because the padding destroys the "
                + "alpha channel those rows are chosen for; every row id is already the "
                + "document's own shape, so this only bites on a [width, height] of another "
                + "shape. h264, hevc, hevc_alpha, hevc_10bit and prores_422 need "
                + "even dimensions: an odd width or height — the document size on a canvas "
                + "with an odd edge, or an odd [width, height] — is written one pixel smaller "
                + "on that edge, and the width and height reported back are the file's. "
                + "The shape is judged on that even frame: a [width, height] in the canvas's "
                + "own proportions is never refused for being odd, at any scale; one of "
                + "another shape is judged as the even size it becomes, which is the size "
                + "hevc_alpha's refusal names. "
                + "prores_4444, gif and apng keep an odd edge. On gif and apng a size — the "
                + "cap, a row, or [width, height] — is a box the picture is fitted inside, aspect "
                + "kept and never upscaled, and the width and height reported back are the "
                + "file's: a vertical 1080 × 1920 project's GIF default is 152 × 270.",
        ]
        return [
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
                    "ungraded": [
                        "type": "boolean",
                        "description": "Render as if no clip were graded — every clip's "
                            + "video.color (Light and Color) neutral, everything else kept: "
                            + "View ▸ Show Ungraded's picture. The view switch itself never "
                            + "reaches this tool or an export. Default false.",
                    ],
                    "selection": [
                        "type": "integer",
                        "description": "An adjustment clip's id: draw what its video.qualifier "
                            + "selects instead of grading — grey, white fully graded, black "
                            + "untouched, times any matte cutting it, its strength not applied "
                            + "— with every layer in front of it left out; black where the clip "
                            + "is not on the frame. View ▸ Show Selection's picture; the view "
                            + "switch itself never reaches this tool or an export. Refused "
                            + "unless it names an adjustment clip. Default: none.",
                    ],
                    "waveform": [
                        "type": "boolean",
                        "description": "Also measure the frame's luma waveform, View ▸ "
                            + "Scopes' Waveform: the text says what share of pixels clips high "
                            + "and low, and <image path>.waveform.json holds the 256 × 256 "
                            + "counts (one array per column bin, indexed by level), the clip "
                            + "marks and both percentages. Default false.",
                    ],
                    "parade": [
                        "type": "boolean",
                        "description": "Also measure the frame's RGB parade, View ▸ Scopes' "
                            + "Parade: R′, G′ and B′ each binned as the waveform bins Y′. The "
                            + "text says what share of pixels each channel clips high and low, "
                            + "and <image path>.parade.json holds the counts keyed red, green "
                            + "and blue (each 256 arrays by column bin, indexed by level) with "
                            + "each channel's clip marks and clip counts. Default false.",
                    ],
                    "vectorscope": [
                        "type": "boolean",
                        "description": "Also measure the frame's vectorscope, View ▸ Scopes' "
                            + "Vectorscope: Rec. 709 Cb and Cr of the encoded values in "
                            + "256 × 256 bins centred on neutral (bin 128). The text says what "
                            + "share of pixels is neutral, and <image path>.vectorscope.json "
                            + "holds the counts (256 arrays by Cr bin, indexed by Cb bin), the "
                            + "six 75 % targets' bins and the skin line's angle. Default false.",
                    ],
                    "histogram": [
                        "type": "boolean",
                        "description": "Also measure the frame's histogram, View ▸ Scopes' "
                            + "Histogram: R′, G′, B′ and Y′ counts per 256 levels. The text says "
                            + "what share of pixels clips high and low by Y′, and <image "
                            + "path>.histogram.json holds the four planes' counts and both "
                            + "percentages. Default false.",
                    ],
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
        ]
    }
}
