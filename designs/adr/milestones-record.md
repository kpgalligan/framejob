# The milestone record, M1 to road map 3's R2

- **Status:** Closed record (2026-09-17). The "Milestone status" section the root `CLAUDE.md`
  carried until 2026-09-17 (`6f7ce4c`), moved verbatim and never maintained after. It stops at road
  map 3's R2 (2026-09-12). Its closing line, "Keep this file current as code lands", is a leftover
  from its `CLAUDE.md` days and contradicts its own header.
- **Original:** `archive/milestones.md` (1448 lines) — sections cited below as "orig
  <entry>" (M1, M2, M3, chrome, P0–P9 for road map 2's phases, remainder, R1, R2) refer to its
  bullets. Road maps 2 and 3 keep fuller per-phase records of their own
  and their own ADRs; this file duplicates them in part.
- **Spec decisions:** relies on the M1-era unnumbered spec §11 entries (see
  `designs/adr/roadmap-01-m1-m3.md`), "Transcription reads EXTRACTED audio", and road map 3's
  recorder entries — "Screen recording is IN", "A recording is ordinary media", "Microphone and
  system audio are two sources and stay two FILES", "A paused recording is a SEQUENCE of files over
  ONE stream", "The recorder panel goes away". SH-1 is the later amendment of the chrome's
  `StickerButton`.

## Context
Each bullet recorded one milestone or phase at the moment it landed: what shipped, what was
measured, what review found, and which limits were recorded rather than fixed. Every number in it
(test counts, catalog sizes, schema versions, line counts, proof scores) is as of that phase.
The decisions below are the ones still visible in the code's shape.

## Decisions
**M1–M3** (orig M1–M3; detail in `roadmap-01-m1-m3.md`)
- **One export writer**: `ExportWriter` replaced `AVAssetExportSession`, so chapters, bitrate and
  size cannot depend on which path ran. GIF/APNG go to ImageIO because `avf_preset` is null.
- **Schema v1→v2 has the one real migrate step** — a v1 nest clip's `project` path string becomes
  a named empty `Nest`. Later bumps (v3–v6 here) have none because every new field defaults; they
  bump anyway so an older build refuses a file it would silently lossy-rewrite (`format.rs`).

**Chrome cleanup** (orig chrome)
- **Toolbar is transport · timecode — view · Export only**; clip actions moved to the timeline bar,
  document meta to the title-bar subtitle. S/M/L drives real heights per track KIND, so
  `TimelineLayout.rowTop` is a prefix sum.
- **The Clip tab kept the panes' sections** rather than merging into the mock's five (merging would
  delete every per-section Reset); superseded by road map 9's sub-tabs.
- **Tooltips were dead app-wide** because `trackingAreas.forEach(removeTrackingArea)` removes
  `NSToolTipManager`'s area; an audio-only file read as video because the tint asked
  `enabled.video` — `ClipKindStyle` takes the snapshot.

**Road map 2** (orig P0–P9)
- **P0: `model.rs` is the schema only**; lookups, `validate` and the source-window arithmetic went
  to `model_query.rs`.
- **P1: `insert_clip`/`overwrite_clip` are single ops** (split + insert_time + add_clip) so a drop
  is one undo step; an insert cuts only the destination track and shifts every unlocked one.
  `lift_range` and `ripple_delete_range` share `ordered_range` + `clear_range`.
- **P2: `set_clip` takes a PATCH `{name?, label?}`**, not two top-level args — a patch already
  distinguishes absent (keep) from `null` (clear). **Solo is a zero envelope** decided in
  `audio.rs` (`muted || (any_solo && !solo)`), so solo touches ramps only. `ClipLabel.swift` is the
  one marker-colour vocabulary. `paste_attributes` copies the earliest clip's groups WHOLE.
- **P3: `video.obscure` defaults to pixelate at amount 1** (a half-hiding region has failed);
  `ObscureKind` is closed, not a narrowed `FilterKind`. **`ripple_delete_ranges` is merge-then-cut**,
  right to left, and the singular op is defined through it. **`add_zoom_action`** measures fit/fill
  through rotation, clamps scale before offsets, and takes a `curve` (default eased). The obscure
  shader stage sits between sharpen and point filters. **The list-interpolation rule** is stated
  once in `actions.rs` (per index when lengths and discriminants `{kind, shape}` match).
  **`detect_silence` reads the PLAN** (peak × envelope), never cuts into a nest or a silenced clip.
- **P4: the text reveal is computed by the core** and rides the text layer's `source` as `reveal`,
  `reveal_phase` (the draw ORDER, not a label) and `reveal_kind`; the hash covers all three or
  playback serves a stale texture. `in`/`out` are durations; an over-long pair degrades, never
  refuses. **Captions share `CaptionLayout.swift` (placement only)**; the four cue rules live in
  `CaptionCues`, used only by the producer that invents line breaks, so imported SRTs are never
  re-wrapped. Caption export never guesses the track.
- **P5: `mono` folds BEFORE the pan** (after it the fold cancels the pan). **The level meter
  computes peak × envelope from the existing PreEffects tap** — a second tap is impossible (one
  `audioTapProcessor` per input), and moving the DSP tap to PostEffects would change every
  compressor's sound. Do not "fix" it toward a second tap. Meter publish uses two relaxed atomics
  (`import Synchronization`, confined to `LevelMeter.swift`). **Loudness export is two passes**
  (BS.1770-4 in `Loudness.swift`, no AVFoundation, float measurement); with Loudness off the gain
  path is never entered. WAV/AIFF carry a non-null `avf_preset` so they don't route to ImageIO.
- **P6: `video.blend` declaration order is the shader discriminant, `normal` = 0 with no +1**, so a
  zeroed uniform renders source-over. Blend pipelines must have fixed-function blending OFF; the
  compositor blends in ENCODED sRGB deliberately. **A transition forces `normal` in the core**
  (`recipe.rs`); a nest clip cannot blend (`check_blend`). **`shape.gradient` stops are not
  order-checked** — the renderer sorts. **Backgrounds are core ops** (`edit_background.rs`), not an
  app composite (the clipboard payload has no `nests`); the blurred copy drops audio, duck,
  transition, actions and label. **A write reads the list it replaces** (`InspectorBinding.editedList`).
- **P7: Save Frame and `render_frame` share `FrameWriter.swift`**, so their PNGs are identical by
  construction. **`alpha` is a per-row capability**; ProRes 4444 at a padded size wrote inverted
  alpha, so `checkAlphaSurvivesTheSize` refuses an aspect change. **Burn-in is a recipe option,
  never an export override** (an unknown override is dropped silently), passed three ways so the
  ImageIO path burns too. **Presets store control choices**, not resolved overrides. **The export
  queue runs one job at a time** — two concurrent `Exporter`s deadlock; no MCP mirror.
- **P8: Preview Quality scales the player's render size on a copy inside `Playback`**, never via an
  argument on `CompositionBuilder.build` (the one constructor shared with export). The size keeps
  the canvas's exact aspect. **The preview window is an `NSPanel`** (a titled window kills editor
  selectors) retained by a stored property, not `addWindowController` (breaks the save sheet), and
  is its delegate for `windowWillReturnUndoManager`. **The Media find band never rebuilds the
  pane.** **8d: `[[position]]` is DESTINATION pixels**; the shaders carry `canvasPerDestX/Y`.
- **P9: an op gets a `scope`, not 55 ops taught about nests.** The core builds a VIEW project from
  the nest (`scope.rs`), applies unchanged, merges back. The view keeps the scoped nest's row with
  its tracks/clips EMPTIED. Caps and nesting depth are checked on the merged parent, so a valid
  scoped op can still `Err`. Seven ops refuse a scope via an exhaustive match. The read half
  `rc_project_scoped` calls the same `scoped_view`. The app holds a `nestPath`, not a nest id.
  **A range belongs to the container it was set in and is refused, never mapped, outside it.**
- **Remainder (§2a): a cache is certified by `CacheStamp`** (size + mtime + sizing constants,
  no path), written last, only for a strip the pass can vouch for; passes for one media serialise
  through `CacheLedger`. **§2b: `ProjectDocument.displayStem`** is the one title-bar stem.

**Road map 3** (orig R1, R2)
- **R1: the microphone is a second FILE** through `AVCaptureSession`, because `SCRecordingOutput`
  folds it into system audio. `CompositionBuilder.fill` holds a video track's last frame past its
  end (a recording's video stops at the last screen change). The recorder never prompts; the panel
  asks. `ScreenRecorder` is a state machine with one `onFinish`.
- **R2: pause = remove/re-add the recording output on one stream** (a sequence of files); the
  landing places pictures back to back, reading every `add_clip` back, never overlapping. The
  panel orders out for every recording; the status item is the chrome.

## What it built — where it lives now
Core: `core/src/model_query.rs`, `model_props.rs`, `model_regions.rs`, `model_text.rs`,
`edit_edge.rs`, `edit_insert.rs`, `edit_time.rs`, `edit_paste.rs`, `edit_zoom.rs`,
`edit_background.rs`, `actions.rs`, `audio.rs`, `recipe.rs` + `recipe_text.rs`, `export_table.rs`,
`export_overrides.rs`, `scope.rs`. App: `TimelineSessions.swift`, `ClipLabel.swift`,
`SilenceDetector.swift`, `CaptionLayout.swift`, `CaptionExporter.swift`, `LevelMeter.swift`,
`AudioNormalize.swift`, `MediaPeaks.swift`, `Loudness.swift`, `ExporterLoudness.swift`,
`FrameWriter.swift`, `ExportQueueController.swift`, `PreviewWindowController.swift`,
`EditorViewController+NestScope.swift`, `MediaCacheFiles.swift`, `ScreenRecorder+Pause.swift`,
`RecordingLanding+Placing.swift`.

## Known limits
Still true of the code (verified 2026-09-26):
- The obscure band commits a rect only (ellipse via the popup). Overlapping
  regions: the greater hiding wins, no blend. A pixelated region on a blurred
  layer shows unblurred blocks; a region on a slated layer does nothing.
- Adding or removing a filter/region inside an action writes BASE props (a different-length list
  cannot interpolate).
- A tent text animation whose `in` is tiny but non-zero reads `"in"` for its whole life.
- Loudness: a mix over full scale is measured honestly (float); an UN-normalised export of it is
  written from an Int16 decode, so it stays clipped and `ExportLoudness.mixClipped` reports it. A
  normalised one is gained in float since #86 part 1 (issue batch B60). WAV/AIFF are 16-bit only.
- During a transition the inspector shows the model's blend while the frame composites `normal`;
  a blend inside a nest blends against the canvas below the whole nest.
- The inline rename editor has no Escape and cannot clear a name (the Clip tab header can); a solo
  stays with its track when its clip is nested off it.
- `selectedMedia` can point at a row the Media filter has hidden.
- `relink_media` never re-probes: a relink to a file of another length keeps the old `duration`.
- An instance deadlocks past ~40 open documents (nothing closes one).
- Export: a padded ProRes 4444 is refused rather than written with inverted alpha.
- Measured and not to retry: a second `MTAudioProcessingTap` for the meter (impossible); the
  archived claim that only the newest `AVPlayerLayer` displays (false on macOS 26.5.1 —
  `isReadyForDisplay`/`videoRect` are useless instruments, `displayedPixelBuffer` discriminates).
Fixed since: the MCP decoder dropping misspelt/omitted keys in nested patches and partial list
entries in end patches (road map 7's D1); the one-minute `SFSpeech` ceiling (W-8, `SpeechTranscriber`);
the Remove Silences sheet's stale spans after an MCP relink (road map 4); the obscure regions'
canvas grips (#85, CI-16).

## Open items
- R1/R2 recorder person checks and `phase8_chrome.py`'s unlocked-console rows — tracked in #55
  and #57.
- `relink_media` re-probing (#63) and the panel/MCP caption-name spelling (`chart.png.srt` vs
  `chart.srt`, #43).
- `AgentServer+Clips.swift` over the cap (856) — its seam is in `designs/adr/app-file-history.md` "Named next cuts".
- `selectedMedia` pointing at a hidden row (#68); rename Escape / undo-merge (#69); the
  ~40-document deadlock (#40); 24-bit WAV/AIFF (#86).

## Where to look in the original
- orig M1–M3 — the milestone bullets: export writer, shadow math, GIF/APNG, schema v2–v6 history,
  nests, reverse, audio DSP, captions, consolidate, ffmpeg.
- orig chrome — the chrome cleanup and identity, its two deviations, the tooltip fix.
- orig P0–P9 — road map 2 per phase: ops, UI paths, deviations, measured proof scores, review
  findings with teeth (P3's region erasure, P4's tent phase, P6's double blend, P8's 8d, P9's
  nest-local numbers).
- orig remainder — the cache completion marker (§2a) and `displayStem` (§2b), with mutant scores.
- orig R1, R2 — the recorder spike's findings, the state machine, the pause landing rules.
