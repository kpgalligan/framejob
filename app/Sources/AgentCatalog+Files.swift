import Foundation

// MARK: - Catalog: files

/// The catalog's FILE half: the thirteen tools whose every row is about a path
/// on disk — the six of Media (a file probed into the list, a caption file
/// read onto a track, the package consolidated, and the three raw media ops),
/// the two of Captions (a transcript made, a caption file written), the two
/// of Rendering and export (a frame, the movie, and the two that follow and
/// stop the movie's job) and, since road map 3, the one of Recording (a
/// movie the app wrote itself). Three of the thirteen
/// are ops (`add_media`, `relink_media`, `remove_media`), so they are built
/// with `opTool` — their arguments PRINTED from the core's published table
/// (road map 7's D3) — and get a `scope` as every op does; the other ten
/// are app-state tools of spec §7.9 with no op behind them and nothing to
/// read from that table, so they declare their schemas whole through `tool`.
/// `record_screen` is among those, declaring NO `scope` by construction,
/// since `tool` injects one for the core's op names only and the parity
/// check's fourth part reads those. Eight of the thirteen are built elsewhere
/// and spliced back in at the points they left, so the order is unchanged:
/// `import_captions`, `transcribe` and `export_captions` in
/// `AgentCatalog+Captions.swift`, `render_frame`, `export`,
/// `export_status` and `cancel_export` in `AgentCatalog+Render.swift`, and
/// `record_screen` in `AgentCatalog+Recording.swift`.
///
/// A pure move out of `AgentCatalog.swift`, which stood at 807 lines against
/// app/CLAUDE.md's ~600 cap — road map 2's phase 9 had put it back over the
/// cut `AgentCatalog+Clips.swift` bought — and whose own header named this
/// cut in advance. It is road map 3's R1·toll, paid first and alone. The
/// seam is the one the file had drawn: `// MARK: Media`, `// MARK: Captions`
/// and `// MARK: Rendering and export` came here whole, in their existing
/// order, with their bodies untouched, and so did the hoisted locals nothing
/// outside them reads. Those locals left again with their rows: the caption
/// format's for `AgentCatalog+Captions.swift` (road map 6's C1 toll 2), and
/// `render_frame`'s and `export`'s five for `AgentCatalog+Render.swift`
/// (grading-2's G2-0). `record_screen`'s four clauses left with their row
/// for `AgentCatalog+Recording.swift` (camera recording's CR1-0).
///
/// **One hoisted local IS shared, and it arrives as an argument**, exactly as
/// the clip rows take three: `render_frame`'s `t` row reads `ticks`, which
/// the Projects and Markers groups read as well, so `ticks` stayed on the
/// other side and is handed in here, and on to `renderTools`. The old
/// header's "none of them shares a hoisted local with the groups that stay"
/// was false by exactly that one, and it is corrected there.
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
                "Copies every file the project references into media/ inside the .framejob "
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
                    + "or conversion was made from — and color, a video file's Camera Log, as "
                    + "set_media_color takes it plus detected, and a PQ file's pq {file?, "
                    + "from?, peak?} as get_project shows it). Probing files is the host's "
                    + "job, so unless you are replaying a project's own JSON, call import_media "
                    + "and let it probe.",
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
                    + "unless with_clips, which removes those clips (a LUT's: clears their looks).",
                [
                    "media": "Media id.",
                    "with_clips": "Remove the clips using it, or a LUT's looks (default false).",
                ]),
            opTool(
                "set_media_color",
                "Sets how a video file's camera log footage is converted to Rec. 709 — the "
                    + "Media tab's Camera Log popup. Every clip of the file, and its reverse, "
                    + "follows it; it is converted before the chroma key and every grade, and "
                    + "Show Ungraded keeps it. color is {log, gamut?}: log apple_log (gamut "
                    + "bt2020), apple_log2 (apple_wide_gamut), slog3 (s_gamut3_cine or "
                    + "s_gamut3), vlog (v_gamut), canon_log2 or canon_log3 (Canon Log 2 and 3: "
                    + "cinema_gamut or bt2020), gamut defaulting to the first; or {lut: "
                    + "media id} to convert with an imported .cube (import_media it first); or "
                    + "null for none, which shows the log picture. An Apple Log or Apple Log 2 "
                    + "file is set at import (get_project's media[].color shows detected: "
                    + "true). Camera Log is refused on an audio, image or LUT media. A PQ "
                    + "(HDR10) file — a video, or a PQ still image — also takes peak, a whole "
                    + "number of cd/m² 1–10000 — the Media tab's HDR10 Peak field: where its "
                    + "highlights roll off to white. Import reads the file's own peak into "
                    + "media[].color.pq {file, from} (MaxCLL, else the mastering display's "
                    + "maximum; {} when the file names none, which means 1,000), and peak "
                    + "overrides it. color replaces the Camera Log and the peak together, so "
                    + "send both to keep both; null clears both and keeps the file's reading. "
                    + "A PQ still takes {peak} alone. A peak on a file that is not PQ is "
                    + "refused.",
                [
                    "media": "The video media's id, or a PQ still's for peak alone.",
                    "color": "{log, gamut?}, {lut} or {peak}, log or lut beside peak, or null to "
                        + "clear.",
                ]),
        ]
        // transcribe and export_captions are `AgentCatalog+Captions.swift`'s
        // as well, with their `// MARK: Captions` note and the one hoisted
        // local only they read, spliced in HERE for the same reason.
        rows += captionTools()
        rows += renderTools(ticks: ticks)
        rows += recordingTools()
        return rows
    }
}
