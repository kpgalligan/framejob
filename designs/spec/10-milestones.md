# 10. Milestones and the M1 build order

**M1 — Cut.** The point at which a screencast editor stops getting opened: open a
file into a project at the source's size and rate; import more; tracks;
move / trim / split / delete / ripple; play, scrub, JKL; transform, crop
and opacity on the canvas and in the inspector; markers; save and open
`.reelcut`; undo; export H.264 and HEVC.

**M2 — Compose.** Text, shapes, transitions, audio volume / fade / duck /
detach, freeze frame, speed, in/out range, chapters on export, the MCP
agent with parity for everything above.

**M3 — Polish.** Actions, corner radius / shadow / reflection, chroma key,
color controls, filters, nests, spotlight, GIF / APNG export, noise
removal, SRT captions (import and burn-in), Consolidate Media, ffmpeg-
assisted import.

## M1 in order, each step verified before the next

1. **Scaffold.** Copy and rename the build files (§8); `core` with
   `rc_project_new/free/to_json/from_json` + `rc_string_free`; the header;
   `main.swift`, `AppDelegate`, `ProjectDocument` (package type),
   `EditorWindowController`, `EditorViewController` with the three panes
   as empty `NSSplitView` children and `DS` chrome; welcome window.
   *Verify:* `make app` launches, `make test` runs a round-trip test,
   `make typecheck` is clean.
2. **Model, time, format** in Rust (`model.rs`, `time.rs`, `format.rs`,
   `edit.rs` skeleton with `add_media`, `add_track`, `add_clip`,
   `set_canvas`). *Verify:* the §7.10 round-trip and timecode tests.
3. **Import.** `MediaImporter.probe` → `add_media` → `add_clip`; opening a
   movie creates the untitled project; the Media tab lists it.
   *Verify:* project JSON in the debugger shows the right descriptor and
   one clip; a rotated iPhone clip reports its display size.
4. **Plan + playback, passthrough.** `composition_plan` for one track
   with no overlaps; `CompositionBuilder`; `Playback` with
   `AVPlayerLayer`; transport buttons, Space, JKL, timecode display.
   Use `passthroughTrackID` instructions for this step only.
   *Verify:* the clip plays with audio; seeking is frame-exact.
5. **Recipe + compositor.** `frame_recipe` (single layer),
   `Compositor` with the one-pipeline pass, instructions switched to the
   custom compositor, `RecipeSource`. *Verify:* changing `x`/`scale`
   through a debug op re-renders the paused frame without a rebuild;
   playback stays at 60 fps on a 1080p source (measure with the
   compositor's own timing log).
6. **Timeline view.** Ruler, tracks, clips from the snapshot, playhead
   drag, click-to-select, zoom, Fit, auto-scroll. *Verify:* visually,
   and the playhead time matches the timecode display.
7. **Edit ops + gestures + undo.** `move_clip`, `trim_*`, `split`,
   `delete`, `ripple_delete`, `insert_time`, `duplicate`; the drag/trim
   sessions; keyboard map; undo/redo; dirty flag. *Verify:* the §7.10
   op tests; in the app, every gesture is one undo step and undo restores
   the frame.
8. **Canvas overlay + Video tab.** Handles for move/scale/rotate, crop
   mode, snapping; `VideoPane` bound to `set_video` with the live-edit
   trio. *Verify:* dragging on the canvas updates the inspector live and
   commits one undo step.
9. **Markers + Document tab.** Add/move/rename markers, canvas size and
   fps ops with `rescale_clips`. *Verify:* op tests and the ruler.
10. **Export.** Presets (one per encoding) and sizes, the export sheet,
    `Exporter` over `ExportWriter`, progress, cancel. *Verify:*
    the exported file plays in QuickTime Player and matches `render_frame`
    at three times, and a project whose canvas is not 1920 × 1080 exports
    at its own size with the sheet's defaults.
11. **Multi-track + thumbnails + peaks.** A/B assignment and instruction
    ranges for several tracks, layer ordering, hidden/muted/locked
    tracks, filmstrips and waveforms from the cache. *Verify:* the tiling
    test; a three-track project composites in the right order.
12. **Files.** Save/open round-trip through the package, autosave, Recent,
    missing-media slate and Relink…, README. *Verify:* quit and reopen
    reproduces the timeline and the frame.
