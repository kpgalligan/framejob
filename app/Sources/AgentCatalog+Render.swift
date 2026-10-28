import Foundation

// MARK: - Catalog: rendering and export

/// The catalog's RENDERING rows: `render_frame`, the verification hook,
/// `export`, the movie, and since spec §11 #326 `export_status` and
/// `cancel_export`, which follow and stop the job `export` queued — four of
/// the thirteen `fileTools` publishes. The first two are the ones grading-2's
/// G2-1 went on to change (`render_frame`'s scope booleans, spec §11 GR-10).
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

    /// `render_frame`, `export`, `export_status` and `cancel_export`, in that
    /// order: the rows `fileTools` splices in after the Captions group and
    /// before Recording.
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
                + "12); h264, hevc and hevc_alpha are 8-bit. av1 is AV1 in an MP4 with AAC "
                + "and av1_webm the same AV1 in a WebM with Opus, both 10-bit, encoded by "
                + "the bundled SVT-AV1 at encoder_speed; Macs before M3 cannot play them "
                + "back. vp9_webm is VP9 in a WebM with Opus from the bundled libvpx, at "
                + "one speed: 8-bit (Profile 0) for an SDR picture, 10-bit (Profile 2) for "
                + "HLG and PQ. Pass a wrong one once and the error lists them all.",
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
                + "shape. h264, hevc, hevc_alpha, hevc_10bit, av1, av1_webm, vp9_webm and "
                + "prores_422 need even dimensions: an odd width or height — the document size on a canvas "
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
                    + "diagnostic; a failed graphic draws its error card in the picture. In an "
                    + "HLG project (set_canvas output) the frame is a 16-bit PNG or a 10-bit "
                    + "HEIC labelled BT.2100 HLG; a JPEG, and any frame asked with "
                    + "sdr_version, is the project's SDR version, labelled BT.709. Its scopes "
                    + "read the picture it draws: in an HLG project the HLG signal, each JSON "
                    + "adding signal \"hlg\" and, for the waveform, parade and histogram, scale "
                    + "(the HLG % ticks in cd/m², reference white at 75 %), the luma and "
                    + "vectorscope taking Rec. 2020's weights and targets; the SDR version's "
                    + "scopes are an SDR project's.",
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
                            + "video.color (Light and Color), video.wheels and video.curves "
                            + "neutral and no video.look: View ▸ Show Ungraded's picture. The view switch itself never "
                            + "reaches this tool or an export. Default false.",
                    ],
                    // View ▸ Show SDR Version's mirror (spec §11 HD-7, HD-14).
                    "sdr_version": [
                        "type": "boolean",
                        "description": "Draw an HDR (HLG) project's SDR version — what h264, "
                            + "hevc, hevc_alpha, gif, apng, JPEG frames and dynamic_range "
                            + "\"sdr\" write: the inverse of the lift, white titles near white, "
                            + "highlights above reference white rolled off. View ▸ Show SDR "
                            + "Version's picture; the switch itself never reaches this tool or "
                            + "an export. An SDR project's frame is its own SDR version, "
                            + "byte-identical. Default false.",
                    ],
                    "selection": [
                        "type": "integer",
                        "description": "An adjustment clip's id: draw what its video.qualifier "
                            + "selects instead of grading — grey, white fully graded, black "
                            + "untouched, its blurred selection when video.qualifier.blur is "
                            + "above 0, times any matte cutting it, its strength not applied "
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
                            + "zoom, off_plot (the pixels left off the plot at a zoom, 0 at 1), "
                            + "the six 75 % targets' bins at the zoom (null off the plot) and the "
                            + "skin line's angle. Default false.",
                    ],
                    // A vectorscope slot's zoom cells, "1× 2× 4×" (spec §11 GR-31).
                    "vectorscope_zoom": [
                        "type": "integer", "enum": [1, 2, 4],
                        "description": "The vectorscope's zoom, as a vectorscope slot's 1× 2× "
                            + "4× cells: each pixel is binned 128 + round(255 × zoom × Cb) (and "
                            + "Cr), so ×2 and ×4 spread a near-grey picture over more bins; at "
                            + "2 and 4 a pixel off the plot is not counted and the text says "
                            + "what share lie off it. Needs vectorscope: true. Default 1.",
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
                "Starts writing the timeline to a file and answers AT ONCE with "
                    + "{export_id, path, status} — ⌘E, the export sheet's six controls (format, "
                    + "size, frame rate, quality, loudness, range) in the sheet's own "
                    + "vocabulary, all but the frame rate — this exports at the document's "
                    + "rate, or on gif and apng at the format's own rate (12.5 and 25 fps). The "
                    + "export is a job in the Export Queue, run one at a time behind any other "
                    + "export already there; status is queued or running. An av1, av1_webm "
                    + "or vp9_webm job also waits while the app's other AV1 and VP9 exports "
                    + "would hold more than a quarter of this Mac's memory with it, and a later "
                    + "job may run first meanwhile (export_status's waiting says so). Follow "
                    + "it with "
                    + "export_status, which never waits — call it again after a pause until "
                    + "status is done, failed or cancelled — and stop it with cancel_export. "
                    + "The export_id lasts until Frame Job quits. Every refusal comes back "
                    + "from this call, before anything is queued: a bad argument, a missing "
                    + "folder, and a graphic clip whose module does not compile; a failure "
                    + "while writing comes back from export_status, failed with its reason "
                    + "(a graphic that fails during the export stops it with no file left, "
                    + "naming the graphic and the frame). The preset is the ENCODING only and "
                    + "the size a separate choice defaulting to the document's own, or on gif "
                    + "and apng to the format's cap; the core resolves both into concrete "
                    + "settings (container, codec, size, rate, range) and hands them to the "
                    + "same exporter the sheet uses, so an agent export and a menu export "
                    + "cannot disagree. An existing file at the path is replaced, and the "
                    + "container's extension is added when the path has none. In an HLG "
                    + "project (set_canvas output) hevc_10bit, av1, av1_webm, vp9_webm, "
                    + "prores_422 and prores_4444 write HLG unless dynamic_range says pq or sdr, and every "
                    + "other video preset writes the project's SDR version. What the finished "
                    + "file holds is export_status's done answer.",
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
                            + "APNG have no bitrate at all. On av1 and av1_webm it is a soft "
                            + "cap: SVT-AV1 "
                            + "encodes at a constant quality matched to HEVC at this rate (HEVC's "
                            + "0.07 bits per pixel per frame when omitted), and the file usually "
                            + "stays under it; very detailed footage can go up to about 1.25 "
                            + "times over. On vp9_webm it is a soft cap too: libvpx encodes at a "
                            + "constant quality matched to HEVC at this rate (HEVC 10-bit's in an "
                            + "HDR export), and the file usually stays under it; up to about "
                            + "1.15 times it was measured.",
                    ],
                    "audio_bitrate": [
                        "type": "integer", "minimum": 1,
                        "description": "Target AAC or Opus rate in BITS per second (192000 "
                            + "is 192 kbps) — the sheet's Quality popup. Omit for 192 "
                            + "kbps. Ignored where the sound is neither: ProRes, WAV and AIFF "
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
                    // The sheet's Dynamic Range popup (spec §11 HD-5, HD-14).
                    "dynamic_range": [
                        "type": "string", "enum": ["hlg", "pq", "sdr"],
                        "description": "An HDR (HLG) project's picture on hevc_10bit, av1, "
                            + "av1_webm, vp9_webm, prores_422 and prores_4444 — the sheet's Dynamic "
                            + "Range popup: hlg (the default; BT.2100 HLG, no Dolby Vision), pq (HDR10: "
                            + "BT.2100 PQ at 1,000 cd/m², mastering display P3-D65 0.005–1,000 "
                            + "cd/m², MaxCLL 1,000, MaxFALL 0) or sdr (the SDR version). Every "
                            + "other video preset writes the SDR version; hlg and pq are refused "
                            + "there and in an SDR project, where sdr changes nothing.",
                    ],
                    // The sheet's Speed popup (spec §11 CX-2, CX-12 (2)).
                    "encoder_speed": [
                        "type": "string", "enum": ["faster", "balanced", "smaller"],
                        "description": "av1's and av1_webm's encoder speed — the sheet's "
                            + "Speed popup: faster "
                            + "(SVT-AV1 preset 8), balanced (preset 6, the default) or smaller "
                            + "(preset 4, the smallest file for the picture and the slowest). "
                            + "Refused on every other preset, vp9_webm included (libvpx has one "
                            + "speed).",
                    ],
                ], required: ["preset", "path"]),
            // Window ▸ Export Queue's row for the job (spec §11 #326).
            tool(
                "export_status",
                "How an export this launch started is going — Window ▸ Export Queue's row "
                    + "for it, read now: it never waits, so call it again after a pause. "
                    + "Always export_id, status (queued, running, done, failed or "
                    + "cancelled), path and elapsed (seconds since export was called, or to "
                    + "the finish once it has finished). queued adds waiting, the queue row's "
                    + "sentence, while the job waits for memory behind other AV1 and VP9 "
                    + "exports; queued and running add estimated_seconds on av1, av1_webm and "
                    + "vp9_webm, the export sheet's estimate of the whole write, in whole seconds "
                    + "and only an estimate. running adds progress (0 to 1) and "
                    + "phase while the exporter names one (the loudness measurement). done "
                    + "adds what the file holds: ok, bytes, the settings that were used "
                    + "(preset, container, codec, width, height, fps [num, den], start, "
                    + "duration), burn_in_timecode, dynamic_range in an HLG project (the "
                    + "picture written), encoder_speed on av1 and av1_webm, loudness for "
                    + "every format "
                    + "that carries sound, normalised or not — summary, integrated_lufs, "
                    + "true_peak_dbtp, "
                    + "sample_peak_dbfs, gain_db, ceiling_dbtp, capped_by_peak and target_lufs "
                    + "when one was asked, read off the mix that was written — and "
                    + "graphic_warnings [{name, frame, message}], each distinct warning a "
                    + "graphic gave while the file was drawn, absent when none. failed and "
                    + "cancelled add reason, the queue row's sentence. Only ids export "
                    + "returned are known, until Frame Job quits.",
                [
                    "export_id": [
                        "type": "integer", "minimum": 1,
                        "description": "The export_id export answered.",
                    ]
                ], required: ["export_id"]),
            // The Export Queue row's Cancel (spec §11 #326).
            tool(
                "cancel_export",
                "Stops an export this launch started — the Export Queue row's Cancel. A "
                    + "queued one is cancelled before it starts; a running one stops and "
                    + "its half-written file is removed, though the answer may still read "
                    + "running until the writer has stopped (export_status then reads "
                    + "cancelled). A finished one is left alone. Answers as export_status "
                    + "does.",
                [
                    "export_id": [
                        "type": "integer", "minimum": 1,
                        "description": "The export_id export answered.",
                    ]
                ], required: ["export_id"]),
        ]
    }
}
