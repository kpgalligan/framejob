# Reelcut — what is left

The live list of what is still open: §3 the size debt a phase consults before it pays a toll, §4
what only a person at the machine can check, §5 where the next work starts, §6 the Rust build
settings. **An item is deleted when it is done**; its history goes in the record of the road map
or issue that did it, never here. Section numbers are stable because code, proofs and the
`CLAUDE.md` files cite them. Rebuilt from the archived originals on 2026-09-26 (tree `538db30`).

Sources are cited by key. Key `roadmap-NN` is `archive/reelcut-roadmap-N.md` (`roadmap-01` is
`archive/reelcut-roadmap.md`), and its ADR is `designs/adr/roadmap-NN-*.md`. `survey` is
`archive/reelcut-effects-survey.md` (ADR `effects-survey.md`). `milestones` is
`archive/reelcut-milestones.md` (ADR `milestones-record.md`). `app-notes` and `core-notes` are
`archive/reelcut-app-notes.md` and `archive/reelcut-core-notes.md` (ADRs `app-file-history.md`
and `core-file-history.md`). `remaining` is `archive/reelcut-remaining.md` (ADR
`remaining-closed.md`).

## 1. Two fixes that shipped without a permanent proof — CLOSED

Closed — see `designs/adr/remaining-closed.md` (§1a, §1b there).

## 2. Two live defects, found and deliberately left — CLOSED

Closed — see `designs/adr/remaining-closed.md` (§2a, §2b there). The limits they recorded that
are still open are in §5.

## 3. The size debt

A file at the ~600-line cap gives something up before it takes anything on, as a pure move landed
and gated alone. New files are capped at 400. Frozen files take wiring only. Proof instruments in
`tools/proof/` are not held to either cap. The standing exemptions are `core/src/edit.rs` and
`app/Sources/ReelOps.swift`, which are tables with one row per op. This is consulted, not done.
**Measured 2026-09-26 at `538db30`**; regenerate rather than trust it:
`wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | awk '$1>600 && $2!="total"' | sort -rn`.

**Over the ~600 cap** (24 files). The seam is named where a record named one.

| File | Lines | Seam, or why it stays |
|---|---|---|
| `app/Sources/ProjectSnapshot.swift` | 2312 | A property group's snapshot types out, whole: the precedents are `TextProps.swift` and `ProjectSnapshot+Graphic.swift` |
| `app/Sources/TimelineView.swift` | 1682 | Frozen; wiring only |
| `app/Sources/Compositor.swift` | 1396 | — |
| `app/Sources/ReelCore.swift` | 1353 | The only file that calls `rc_*`. Next seam: the `dictionary` extensions (the media helpers already went to `MediaDescriptor.swift`) |
| `app/Sources/ProjectDocument.swift` | 1335 | Stored properties cannot move. The natural cut is the media/reverse machinery; `+DisplayStem`, `+Import`, `+Graphics` are the shape |
| `app/Sources/ReverseRenderer.swift` | 1311 | — |
| `app/Sources/ReelOps.swift` | 1191 | Exempt table |
| `app/Sources/InspectorPane.swift` | 1156 | The precedents are `InspectorSection.swift`, `InspectorSlider.swift`, `InspectorBinding+Writes.swift` |
| `app/Sources/PreviewCanvasView.swift` | 1132 | Frozen; wiring only |
| `app/Sources/EditorViewController.swift` | 1128 | Frozen; wiring only |
| `app/Sources/ExporterWriter.swift` | 1099 | The settings/encoder half, still unpaid |
| `app/Sources/CanvasSessions.swift` | 1090 | — |
| `app/Sources/OptionControls.swift` | 1082 | The precedent is `OptionControls+Choices.swift` |
| `app/Sources/VideoPane.swift` | 1001 | A section out as an extension, the precedent `VideoPane+Obscure.swift` |
| `core/src/edit.rs` | 893 | Exempt semantics table. If a cut is ever forced, the `Op` enum goes to `edit_ops.rs`, never in a feature phase |
| `app/Sources/AudioDSP.swift` | 890 | — |
| `app/Sources/AgentServer+Clips.swift` | 856 | The clip-placement handlers against the property doors |
| `app/Sources/AgentCatalog+Clips.swift` | 801 | — |
| `app/Sources/AgentServer.swift` | 794 | Frozen; wiring only |
| `app/Sources/FFmpegRewrap.swift` | 768 | — |
| `core/src/edit_clip.rs` | 757 | Known debt (`core/CLAUDE.md`) |
| `app/Sources/Loudness.swift` | 742 | — |
| `app/Sources/Controls.swift` | 651 | The sync rule with Rasterize's copy (`app/CLAUDE.md` "Shared chrome"); 7 lines are the SH-2 fork of `drawBar` (§5d) |
| `app/Sources/ExportSheetController.swift` | 639 | — |

**At the edge**: the next addition to any of these pays first.

| File | Lines | Named next cut |
|---|---|---|
| `app/Sources/Playback.swift` | 598 | — (the meter already went to `Playback+Meter.swift`) |
| `core/src/recipe.rs` | 596 | — |
| `app/Sources/AudioTap.swift` | 595 | — |
| `core/src/evaluate.rs` | 593 | — |
| `core/src/actions.rs` | 592 | `clamp_video` and its helpers to a new `core/src/actions_clamp.rs` (core-notes "Modules and size"; roadmap-05 §5e) |
| `app/Sources/AgentServer+Scope.swift` | 592 | The envelope rule (`checkCallScope`, `effectiveScope`, `idScope`, `addressed`, `checkDocumentLevelTicks`, `scopeLanding`, `scopeFailure`) against `set_scope` the tool (`setScope`, `nestScopePath`, `pathToClip`, `applyNestScope`, `commonPrefix`, `scopeReport`) |
| `app/Sources/AgentServer+Render.swift` | 589 | — |
| `app/Sources/SilenceDetector.swift` | 586 | Needed before a per-voice `Outcome` (§5d) |
| `app/Sources/CompositionBuilder.swift` | 577 | `audioParameters` |
| `app/Sources/AppDelegate+Menus.swift` | 561 | A submenu builder out (the precedent is `AppDelegate+GraphicMenu.swift`) |
| `app/Sources/SettingsWindowController.swift` | 453 | **Over its 400 new-file cap** since `49af3f4` (#33): the Verify bookkeeping to `SettingsWindowController+Verify.swift` (app-notes) |
| `app/Sources/AgentServer+Recording.swift` | 400 | `RecordingToolChrome` (the status-item wrapper with `freeze()`) out (roadmap-03 R2) |
| `app/Sources/ScreenRecorder.swift` / `SpeechEngine.swift` / `MediaTranscript.swift` / `AssemblyAIClient.swift` | 399 / 399 / 399 / 398 | New-file cap |
| `core/src/model_graphic.rs` / `ffi_graphic.rs` / `source_window.rs` | 399 / 397 / 396 | New-module cap. For `ffi_graphic.rs`, nothing crate-free is left to move (`diag_json` and `diag_error` name `Diagnostic`) (roadmap-10 §10.7) |
| `core/tests/add_transition_edges.rs` | 400 | New-file cap; gives something up before it takes anything on |

## 4. What only a person at the machine can check

Run through at the machine once, in both appearances unless it says otherwise. No script can
answer these: each needs eyes, ears, a real pointer or keyboard, a real service, or a host state.

### 4a. Playback and the picture
- **A clip plays with audio in sync, and the preview holds 60 fps** (spec §10 steps 4–5). Also
  J/K/L, scrubbing, and the compositor's timing log. (from: roadmap-01 §2)
- **Preview Quality is actually faster.** `phase8_proof.py` §5 proves a smaller buffer is asked
  for; nobody has measured a frame time. The shadow passes do not get cheaper (`shadowSilhouette`
  allocates at canvas size). (from: remaining §4; roadmap-02 P8)
- **The two preview windows show the same frame**, looked at together (`isReadyForDisplay` and
  `videoRect` cannot tell). **The preview window's frame survives a relaunch**: move it to a second
  display, quit, relaunch. A `setFrameUsingName` mutant survives `phase8_chrome.py`. (from:
  remaining §4; roadmap-02 P8)
- **A nest plays once open**: the scoped composition's audio and frame rate. **⇧⌘P, ⌘↓ and ⌘↑
  from a real keyboard** (probes synthesise the menu items). (from: remaining §4)
- **A saved project opens quickly** on a long recording (the cache marker's point), and **a
  relinked clip's filmstrip changes on screen** through the Relink… sheet. (from: remaining §4)
- **Waveform peaks (#23)**: on AAC, the recorder's own files and WAV, the waveform shows no gap or
  flat tail where there is sound, and a part-decoded file stays "analysing". (from: roadmap-04 §9)

### 4b. Timeline, canvas and keys
- **M1–M3 transients never seen**: the snap guide during a drag, marker flags dragged and renamed,
  in/out shading, fade handles dragged; crop mode and its 30 % ghost, canvas snap guides, inline
  text editing; the feel of drag, trim, ⌥-drag duplicate, ⌥-drag rate stretch and a refused drop's
  animate-back; every tooltip (none has ever been read), the ghost-button hover fill, the trim
  cursor, the S/M/L relayout. (from: roadmap-01 §2)
- **Road map 2's cutting moves, felt**: ⌥⇧-drag a body slips (the filmstrip scrolls), an edge
  rolls (the neighbour's edge moves, a snap line shows); `,`/`.` nudge ±1 frame and ⇧ ±10, a
  refusal beeps; ⌫ with a range and nothing selected lifts it, and not while a field is edited;
  double-click an empty lane span closes the gap; ⌥-click a track header selects its clips;
  ⌥-drop / ⇧⌥-drop from Media insert / overwrite; each one ⌘Z. (from: roadmap-02 P1)
- **Road map 2's identity UI**: double-click a clip, the field opens with its name, Enter commits
  "Rename Clip" to strip, Clip tab header and selection block, an unchanged Enter makes no step;
  the header field commits on Tab or click-away and an emptied field restores the fallback (nothing
  on an unnamed clip); the 12 pt semibold sits in its 20 pt box; ⇧⌘R scrolls a far clip in first;
  the headphones toggle matches eye, speaker and lock at S/M/L; Track ▸ Solo's checkmark follows;
  Label ▸ Blue dots strip and header, None clears both; ⌥⌘V restyles and beeps with no shared
  group; zoom or resize with a rename open and the field follows, delete the clip and it closes
  with no rename. (from: roadmap-02 P2)
- **Road map 2's region mode**: `Z` puts up the crosshair, a drag paints the band with the
  resolved rectangle ghosted, ⇧ switches to fill, release adds one action; `Z`, Esc, a selection
  change or the chroma eyedropper end the mode, ⇧Z still fits; Place on Canvas appends where the
  band was and greys at four regions; an obscured region really hides a face at 100 %. (from:
  roadmap-02 P3)
- **The marquee from below the lanes with a real mouse**: the band draws and the selection block
  counts up (`marquee_probe.py` uses synthetic points). (from: remaining §4; app-notes)
- **The track context menu**: ⌃-click on a header and a lane shows the menu rather than a drag; it
  pops at the pointer and its checkmarks read. (from: remaining §4)
- **Space from anywhere (#35)**: commit an inspector number field with Return, press Space, no beep
  as play starts; with Full Keyboard Access, Tab to a button and Space presses it, not play. (from:
  roadmap-02 #35)
- **The canvas text editor (#36, #37)**: double-click a centred auto-sized text and type, the field
  widens about its centre with no wrap, commit moves nothing but the grey plate; a fixed-width text
  keeps its width and grows down. Return applies and ⌘Z takes it back, ⇧Return is a new line; Esc
  on a changed string asks, and Esc/Return on that sheet go back/apply. Also input-method marked
  text, which may not refit and whose Return/Esc the route leaves alone. (from: roadmap-02 #36, #37)
- **Dragging a clip leaves the timeline still**: with the playhead on screen it does not flash to
  0; scrolled off screen, the view does not jump back; arrows and a ruler click still reveal it.
  (from: app-notes "The playhead echo")
- **The Speed sheet's hint** (gaps, allowed overlap with a possible dissolve, a refused clip
  unchanged) wraps readably; the probe does not photograph the sheet. (from: roadmap-07 §12.10)

### 4c. The Clip tab and the chrome (road map 9, the sharp pass)
- **Phase 1, the lane and bands**: the lane's header row (ACTIONS, count, "· editing N", Zoom to
  Region, Zoom Back, Add Action), Clip chip and detail row (Start, Length, Curve, trash); the
  timeline bands at 5/12/18 pt for S/M/L (mint 34 % with 75 % ends, the selected band solid with
  its number in `#101010` and its curve, its span washed 12 % and shaded on the ruler over a 2 pt
  rule); whether the light mint `#1E8F6E` reads (the handoff's placeholder, `Theme.swift:105`); a
  real band click selects and parks the playhead at its end; esc leaves the mode and is not
  consumed with nothing selected; ⌫ removes the action before the clip. (from: roadmap-09 §2)
- **Phase 2, sub-tabs and pinned block**: the block stays while sections scroll; a sub-tab click
  switches at once and returns to the top; the choice survives picking an action and resets on
  another clip; the active cell's fill and the mint `◆N` read in light; a slider's block knob meets
  its fill on a pixel edge at every value. (from: roadmap-09 §4)
- **Phase 3a, row marks**: ◆ ◇ ○ ⊘ in gutter and headers (⊘ and ◇ may be too quiet in light); the
  keyed 1 pt border; the mint segment and coral tick while scrubbing; "now" on a field-only row;
  "at end" on a keyed popup; auto-open opens the keyed sections, a hand-closed one stays closed,
  leaving returns the person's layout. (from: roadmap-09 §6)
- **Phase 3b, Reset/Clear/×/menus/strip**: Reset appears when a section leaves default and goes on
  return; Clear takes its slot with an action selected; the summary's middle tier reads in light;
  the × and tooltip over a keyed gutter (key window); right-click on label, slider and empty space
  opens the row menu, on a field or popup their own; "Go to action M" lands; ⌥⌘K inside an action
  beeps and shows "Refused: …", at most three lines, gone on the next edit, undo or click, kept
  across a playhead move. (from: roadmap-09 §8)
- **Phase 4, retiming by drag**: the hover's 62 % fill and grips under the pointer; `.openHand`
  and `.resizeLeftRight`, none on a band too narrow; the band stops flush; the dashed ghost and the
  HUD (timeline 18 pt above the clip, lane in place of ACTIONS); the drop re-selects and parks the
  playhead; one ⌘Z; a lane click selects on release without a jump; lane hatch, fades and wedges
  against the timeline's; the curve glyph at the narrowest panel. (from: roadmap-09 §10)
- **Phase 5, the mode**: with an action selected a canvas move/scale/rotate/crop and an arrow
  nudge land on the END state while the box is drawn at the playhead (CI-13 accepts it; judge it);
  a text width drag starts from the end width; a shape box drag still resizes the shape; unchecking
  Drop shadow (outline, backdrop, stroke) shows ◆ "at end"; a header click collapses instantly
  with Reduce motion on and animates 0.22 s off, auto-open always instant. (from: roadmap-09 §12)
- **The sharp chrome**: the zoom slider's grey track and white (dark) / black (light) block beside
  the accent fill (SH-2); the square Export button, S/M/L, Snap box and fields beside the sheets'
  still-pill `StickerButton`s (SH-1); a `GhostButton`'s square hover fill (never rendered), press,
  a disabled `BlockSlider`, dragging the zoom knob. (from: remaining §4)

### 4d. Sound, looks and output (road map 2 phases 5–7, M3)
- **M3's UI**: ⌘G / ⇧⌘G; the reverse progress sheet's Cancel and failure path; the export sheet's
  Quality row; the Filters, Spotlight, Reflection and Audio-cleanup sections. (from: roadmap-01 §2)
- **The meter in motion** (hold and decay; a 30 Hz read of a 12–20 Hz buffer rate not reading as
  stutter); **Mix ▸ Mono sounds mono** and a pan across it sweeps; **a −14 LUFS export** sits level
  with commercial streaming material. (from: roadmap-02 P5)
- **Mixed audio formats on one track (#34)**: listen to the fixed preview, and run
  `mixed_audio_probe.py` §4 on the built-in speakers (only measured on Bluetooth). (from:
  roadmap-02 #34)
- **Blend modes on real footage; a gradient smooth, not banded; Add Blurred Background's look**
  and its `blur 1.0` at Fill default, before it is treated as settled. (from: roadmap-02 P6)
- **Export relaunch and queue**: quit and relaunch, the export sheet reopens on its last format,
  size, quality and loudness, and a user preset restores them; Window ▸ Export Queue shows per-row
  progress and Cancel and is listed once; Save Frame… (⌥⌘E) matches the preview. (from:
  roadmap-02 P7)

### 4e. Captions and word captions
- **Reveals and legibility**: each `text.animation` kind (typewriter, word_fade, line_rise) plays
  at 60 fps without stutter; a Caption-preset caption is legible over real footage. (from:
  roadmap-02 P4)
- **The on-device model**: what the Download row and `transcribe` say with no network; a real
  download on a Mac that never had one (the bar turning determinate, the percentage moving, the row
  then installed and Generate live); `Progress.cancel()` mid-download (prompt throw, nothing
  half-installed, "Download" back with no note); Language and Engine locked for the whole
  download, and a reopened sheet mid-download offering a second request; the model still
  installed straight after, after a relaunch and days later (the app releases its reservation);
  the row LOOKED AT (placement, indeterminate bar, "Downloading French (France)… 42%", "— not
  installed"). (from: roadmap-08 §10.3, §10.6)
- **The bundled faces** (Montserrat, Anton, Bebas Neue) resolve from the app bundle on a Mac
  without them in `/Library/Fonts`. (from: roadmap-08 §10.1, §10.7)
- **Sync by eye per engine**: `CaptionPages.lead(for:)` shifts on-device words +270 ms and
  AssemblyAI −60 ms; the two constants are where a correction goes. (from: roadmap-08 §10.9)
- **Each style on real footage** (Highlight, Pill, Karaoke, Build, One Word) at 9:16 and 16:9,
  and **60 fps with a pop on every word**, hand-written and generated. (from: roadmap-08 §10.7,
  §10.9)
- **The Generate Captions sheet as a sheet**: the Style row, the card's height, the popup opening
  on the last style after a relaunch, Replace over two caption tracks then one ⌘Z; the 258 × 80 pt
  preview reads as "this style, second word lit" on 9:16 and 16:9. (from: roadmap-08 §10.10)
- **Three style choices the user never confirmed** (#45): Karaoke's two-line exception, the bundled font
  set, the 80 % shrink floor (`CaptionPages.Rules.shrinkFloor`). Confirm or change. (from:
  roadmap-08 §6)

### 4f. Cloud captions (needs a real AssemblyAI key, which no proof may use)
- **Verify** answers "Key accepted" for a good key and the key sentence for a bad one; **a real
  402** carries the balance sentence the `.account` arm relays; **the `eu` region** with an account
  that has it; **the fallback's report card** on a Korean or Polish recording (every live call
  answered `universal-3-5-pro`). (from: roadmap-06 §5j, §10.9, §10.11)
- **A real twenty-minute recording over a home upstream**: whether "Waiting for AssemblyAI · 34 s"
  reads as patience or a hang, whether the four bands and the megabytes feel like progress, and
  the cue timing by eye. **A real media over ten hours** (the first 550 MB FLAC extract). **A held
  media** (R6-11's sentence when DELETE is down). (from: roadmap-06 §5j, §10.10)
- **The chrome**: the Settings window (button row balance, the 460 pt paragraph, Verify beside
  Save and Remove); the Generate Captions sheet with the three cloud rows appearing and going as
  Engine moves; the reasons tooltip on the summary label; ⌘, in a document window, not taking the
  bare `,` nudge or an inline rename; `FileStore`'s `0600` file in
  `~/Library/Application Support/Reelcut/` and whether Remove feels final. (from: roadmap-06
  §10.9, §10.11)
- **The Keychain prompt** a rebuilt ad-hoc binary blocks on (roadmap-06 §3 q7): what it says,
  whether "Always Allow" survives a rebuild, whether a Developer ID build avoids it. The answer
  decides whether the key can go back to the Keychain (§5f). Nothing was left in the Keychain.

### 4g. Silence, transitions and motion
- **Remove Silences by voice, listened to**: a narrated screencast recorded by the app, run through
  Voice mode with the truth marked by ear; a cut across a voice-mode boundary (is 60–100 ms of lag
  plus 0.1 s padding breathing room or a clipped word; should padding be 0.05 s — an answer of 0
  would reopen level-based edge refinement); the sheet's note with one file pending and another
  judged by level, read together. Also the sheet's shading on ruler and lanes, and its disabled
  "Selected clips" row with a silent selection. (from: roadmap-04 §4h; roadmap-02 P3)
- **Transitions**: a crossfade across a Remove Silences cut sounds even; an eased push feels
  better than linear; the Transition submenu at a hard cut does what a person expects; the three
  wipes read as their named directions. (from: roadmap-05 §4g)
- **Motion**: each preset's numbers at ordinary lengths; `pop` reads as a pop; Preview loops the
  clip; a drag begun mid-motion is tolerable; wedges read at S, M and L (measured at M only); a
  `spin` turns the way the table says; a slide inside a nest leaves by the nest's edge. (from:
  roadmap-05 §6g, §12)

### 4h. The recorder (road map 3)
- **R1**: the picker's window mode presenting from the non-activating panel and the choice
  arriving; the countdown's look; a display recording without the panel; timeline playback absent
  from the file; the menu bar's recording indicator naming Reelcut and its Stop landing the file;
  popups and switches on the panel while another app is frontmost; the microphone prompt from the
  signed bundle; the first shareable-content call of a fresh instance off main. (from: roadmap-03)
- **R2's pause**: Pause/Stop then Resume/Stop in the item's menu, the coral dot and the pause glyph
  with a frozen time; the system indicator staying up through a pause; the panel gone from the
  start for a display too and back only with a note; ⌘Q while paused opens the item's menu; a
  paused recording played across a segment boundary shows no cut but the paused span. (from:
  roadmap-03 R2)
- **Show Clicks**: record the main display with it on, click, and see rings in the file (none with
  it off). No file has ever contained a click. (from: roadmap-03 R0 q6a)

### 4i. Graphics (road map 10)
- **Graphics playing, watched**: `lower-third` and `kinetic-type` on a 1080p30 canvas at Preview
  Quality Full; Activity Monitor's memory while `kinetic-type` plays at 4K (the six-entry pool,
  `LayerRenderers.graphicCacheLimit`, ~33 MB a texture, was sized without it); the error card (dark
  red, message in white, never the last good frame) in the live preview; a slower machine or a
  heavier graphic (a stutter there is G6's trigger, §5f); and the three `tools/proof/work/
  playback-check/` projects with no video beneath: the preview shows, Play runs, scrub and an
  in/out loop look right. The user judged 4K smooth on an M2 Max on 2026-09-25. (from: roadmap-10
  §9a, §10.6, §10.8)

### 4j. Host state for the proofs, and housekeeping
- **`phase8_chrome.py` §4's six dispatch rows need an unlocked console** (they need a key window);
  locked, they skip by name and are unmeasured. (from: remaining §4)
- **`recording_proof.py`'s microphone rows want a wired or built-in input.** With a Bluetooth input
  the mic's first sample lands after the screen's and the mic file comes out 82–213 ms short, a
  FAIL (the script skips only a Bluetooth OUTPUT). Re-run wired, and say whether the row should
  skip by name. (from: roadmap-06 §10.12)
- **Two key-tainted `.xcbuilddata` directories** were left under an old session scratch
  `e2rev/copy/build/` (the delete was declined, 2026-09-21). Not found under `/tmp` on 2026-09-26;
  confirm gone. `unexport RC_ASSEMBLYAI_KEY` in the `Makefile` prevents new ones. (from:
  roadmap-06 §10.12)

## 5. Where the next work starts

Nothing is scheduled. §5a is defects that need code; §5b is proof residue; §5c is documentation
drift; §5d candidates; §5e limits a later phase may revisit; §5f work the user deferred.

### 5a. Open defects
- **No tool closes a document** (#40). An instance deadlocks somewhere past ~40 open documents, and two
  open documents at one path (possible through `new_project`/`save_project {path}`) make an
  explicit `project` pick one at random (`AgentServer.swift` `documents.first(where:)`). Done: a
  `close_project` tool (a spec §11 decision, since closing is not an edit) or `open_project`
  closing the agent's previous document, proved by a script opening 60. (from: roadmap-02 P3;
  milestones P3; app-notes AgentCatalog)
- **`performGroupedEdit` leaves an empty undo group** on an identity or refusal, a step ⌘Z has to
  pass (`ProjectDocument.swift:1159-1172`). The "no caller reaches it" claim is doubtful: the
  inspector, canvas, add-clip and timeline paths call it. Done: a probe on the undo stack after an
  identity through each caller, then a fix or a proof it cannot happen; `refusal_probe.py` prints
  it as a note. (from: roadmap-07 §5.2, §12.4)
- **Bare keys go dead after an inspector field commits** (J/K/L, W/E, I/O… until a click;
  `OptionControls.swift:244` `makeFirstResponder(nil)`), and **Caps Lock refuses every bare key**
  (`EditorViewController.swift:719`), where #35's Space route allows it. (from: roadmap-02 #35)
- **The rest of the app against a hand-written `speed`** (#41). Ops clamp `speed` to 0.1–10; the reader
  does not. Driven clean at 1e300 and 1e-300: `open_project`, `get_project`, `render_frame` at 0,
  `transcribe`, the harness. Unasked: the timeline, peaks window, reversed mirror, plan, exporter
  and `CompositionBuilder`'s `sourceIn + sourceDuration`. A bound in each or one in
  `Project::validate` (declined by R6-10) is undecided. (#31, the `duration` half, closed by
  D7-1.) (from: roadmap-06 §10.13 H·4)
- **`paste` stores its payload clips whole**: no range check, no motion normalising (`scale: 500`,
  `motion {}` as three nulls), so the next `set_video` on that clip is an `Err` and a Clip ▸ Motion
  batch lands nothing; a `words` count mismatch is refused only at the next `set_text`. Done:
  each payload group through `normalise_and_check_group`, or the payload refused by name
  (`edit_paste.rs:460-477`, `edit_props.rs:236`). (from: roadmap-05 §12 R2·2, R3·1; roadmap-08
  §10.5)
- **Ripple-family shifts store sub-frame starts at an inexact rate** (#42) (7 fps, the recorder's
  24981/1000): `add_transition_by_shift` (`edit_transition_shift.rs:95`) and `close_gap` move many
  clips by one delta. Done: a spec §11 decision accepting it, or each clip to `snap(start + delta)`
  with an overlap re-check. (from: core-notes; roadmap-05 §12 R1·1)
- **`relink_media` never re-probes** (`edit_track.rs:466-487`): a relink to a file of another
  length keeps the old `duration`, and the new strip and bucket count are sized from it. (from:
  remaining §2a; app-notes MediaImporter)
- **A reversed clip inside a nest is analysed unmirrored** (`MediaPeaks.reversedPivot` reads top
  level only), so Remove Silences and Normalize measure the wrong end; entering the nest is the
  escape. The plan must stay byte-identical for forward and reversed. (from: milestones P3)
- **The level meter holds its last buffer across empty time**: a track with no segment under the
  playhead stays lit (`LevelMeter.swift:225-248`, cleared only on stop and tap prepare). Done: age
  out a stale sink, proved by a probe playing across a gap. (from: roadmap-02 #34)
- **A transition zone paints over the previous clip's selection ring** (~20 pt of it): clips draw
  one by one, ring last. Done: bodies, then zones, then rings, with the loop in
  `TimelineClipDrawing.swift` since `TimelineView.swift` is frozen; proved by a harness byte
  comparison. (from: roadmap-01 §3.6)
- **`import_media` over MCP times out on a first ffmpeg transcode**: `AgentServer+Media.swift:78`
  waits 30 s on a probe that runs `FFmpegRewrap.assist` (up to 300 s copy, 1800 s encode); the
  conversion finishes and a second call is instant. (from: roadmap-01 §3.7)
- **`selectedMedia` can name a row the Media filter hides**, so Insert/Overwrite at Playhead and
  Reveal act on media the person cannot see. (from: roadmap-02 P8; milestones P8)
- **The timeline's rename field has no Escape**, and a rename committed by clicking a header toggle
  lands inside that toggle's undo step (`TimelineView+Rename.swift:35`). (from: milestones P2)
- **Word captions**: the W-5 note ("Word style and animation do not compose; the word style
  wins.") is truncated to one line in the 304 pt inspector (`InspectorPane.swift:313-338`); the
  sheet's preview plate goes stale on a light/dark switch (`PreviewKey` carries no appearance,
  `TranscribeSheetController+Style.swift:33`). (from: roadmap-08 §10.7, §10.10)
- **Cloud captions**: "retried at the next run" is promised for a poll-echoed id that is not a
  plain identifier, which the janitor skips as `notSent` for ever (`CloudTranscriber+Report.swift`
  `deletionWarnings`); the true sentence says the id could not be sent. (from: roadmap-06 §10.13)
- **Graphics, model and export**: `add_transition`'s handle form extends a graphic's head without
  advancing `graphic.in`; a canvas rate change does not re-snap `graphic.in`/`length`; `validate`
  accepts a `Source::Graphic` clip with no `graphic` (`model_query.rs:357`); the export gate walks
  one nest level (`ExporterGraphics.swift:34-49`); `Exporter.cancel()` still cancels the loudness
  reader from main (`Exporter.swift:287-293`, #38's shape, unmeasured); a pump starved in
  `copyNextSampleBuffer` cannot be woken by cancel (not seen in 70 runs). (from: roadmap-10 §10.5,
  §10.6)
- **Graphics, store and menus**: Insert ▸ Graphic names from the last scan and can overwrite a
  `.js` saved outside moments before (`EditorViewController+GraphicMenus.swift:87`, rescan first);
  From File… decodes non-UTF-8 silently (`:89`); a failed move in `GraphicStore.write()` leaves
  `<name>.js.partial`, which saves carry and `holdsContent` counts; untitled graphics roots are
  never deleted; an in-place rewrite of a font or asset is seen only at the next folder event.
  (from: roadmap-10 §10.6, §10.7, §10.9)

### 5b. Proof and instrument residue
- **`cloud_captions_probe.py` leaves `cloudprobe-*` suites** in `~/Library/Preferences` on every
  run (`removePersistentDomain` loses to cfprefsd; `:1035`, `:1498`). Done: the harness's
  `MemoryDefaults`, and the count unchanged across a run. (from: roadmap-08 §10.10)
- **`words_core_proof.py` hard-codes the format version** (`:150-158`, `:307`); read
  `RC_FORMAT_VERSION` as `phase9_proof.py:168-173` does before the next bump. (from: roadmap-10
  §10.5)
- **`e2_proof.py` has no row for a spin's direction or a slide inside a nest** (mutants reversing
  either score 61/61; the core tests pin both). Done: a cropped card on `during: spin`, and a nest
  whose canvas differs with an `in: slide_*` clip inside. (from: roadmap-05 §12 R4·1, R4·2)
- **`detect_silence`'s mixed note ending is unscored** ("spans inside N of them ARE proposed here
  and nothing inside the other M is", `AgentServer+Silence.swift:148`). Needs two waveform-waiting
  media, one ducked to 0.001. (from: roadmap-04 §8)
- **C1's reader review left unjudged**: the 21 pairs of `transcribe`'s seven refusals; the sheet's
  Stop during upload, submit, wait and save (only extract has a row); a server that drips a byte
  under the 60 s idle timeout; a second reader for fixes R1·1, R1·2, R1·3, R2·1, H·3 and a re-run
  of the re-aimed `any-id-on-the-wire` and `no-delete` mutants. (from: roadmap-06 §10.13)
- **Cloud probe nits**: two row-I checks say five and assert six (`cloud_captions_probe.py:4667,
  4674, 4679`); a stale "2.5 s" comment (`cloud_captions_proof.py:121`). (from: roadmap-06 §10.13)
- **Small proof nits**: grant-era comments in `harness/main.swift:135-136, 519` and
  `phase4_chrome.py:9, 31, 633-634`; `speech_engine_probe.swift` P8 exits without draining the
  gate; `words_spike/speech_rows.py:378` records "deleted" whatever the status;
  `media_less_playback_probe.py --sources <missing>` ends in a traceback; `graphics_menu_proof.py`
  M3 counts a separator for a missing item; older scripts still type app-state tool argument names
  (`phase9_proof.py`'s `trim_start` scope; `phase4`/`phase5` prose claims). (from: roadmap-08
  §10.6; roadmap-10 §10.8, §10.9; roadmap-07 §9)
- **Small test nits**: `graphic/tests/edges.rs:30`'s "over black" cannot fail (assert colour ≤
  alpha); `graphic/tests/render.rs:123` is timing-dependent; `core/tests/graphic_ffi.rs:421` reads
  only the top of `core/src`; `core/tests/graphic.rs` cannot tell the project canvas from a nest's
  and never checks `ctx`'s key order, and `graphic_starts`' doc says ids; `core/tests/words.rs:155`
  `a_rate_change_resnaps_the_words_under_d7_3` changes the canvas fps. (from: roadmap-10 §10.4,
  §10.5; roadmap-08 §10.5)

### 5c. Documentation and comment drift
- **Spec**: §7.7's format list was measured on macOS 15, not 26 (#46). (from: roadmap-08 §10.4)
- **A stale VALUE, not prose**: `ProjectSnapshot.formatVersion = 5` (`ProjectSnapshot.swift`)
  is the fallback a decode with no `version` key reports; `RC_FORMAT_VERSION` is 10. Changing it
  changes behaviour, so it was left out of the comment sweep. (from: survey §3)

### 5d. Candidates, unasked
- **Obscure regions on the canvas**: outside the modal mode a clip's regions have no outline or
  handles; `CanvasLayerBox.canvasQuad(ofSource:)` (`CanvasSessions.swift:293`) is the unused seed.
  Done: regions drawn through the layer transform with move/resize handles as one session struct.
  (from: roadmap-02 P3; milestones P3)
- **A float export write path, then 24-bit WAV/AIFF**: the write pass decodes 16-bit integer
  (`ExporterWriter.swift:877`) before the loudness gain, so a mix over full scale is measured right
  and stays clipped; 24-bit widens the same shared decode dictionary, as an `audio_bits` override
  (`export_table.rs:374`). A mismatch there is a file of noise, not an error. (from: roadmap-02 P5)
- **A lead-in for AVFoundation's first ~12 ms**: a mix input's first volume point is skipped, so
  an incoming clip's first 25 ms export at about half scale, muted or not. Try a ramp starting
  before the clip, re-measured by `e1_proof.py` §5's hard-cut row. (from: roadmap-05 §12)
- **The core's refusals**: the clamped-edge family (a slip/roll clamped to nothing, a roll with no
  predecessor, crossed trim clamps, a stretch outside ×0.1–×10, `detach_audio` with no audio,
  `set_transition_duration` with no room; `outcome.rs:69-78`) could refuse with a sentence;
  range refusals could name the entry (`video.filters[2].amount`, `props_check.rs:228, 264-269,
  465-466`, moving `phase6_proof.py`'s `[]`); a list fold with one op applied and one refused drops
  the sentence (`ReelEdit.swift` `applying`); a sub-frame `add_transition` duration refuses with
  "the 0 frames asked for"; nullability could become an op-table column (today two rows in
  `AgentCatalog+Declarations.swift`). (from: roadmap-07 §2.1, §5.2, §6, §12.2; roadmap-05 §12)
- **`AVVideoComposition.Configuration`** at `Playback.swift`, `ExporterWriter.swift` and
  `CompositionBuilder.swift`, taking the typecheck baseline from 7 warnings to 4. (from:
  roadmap-08 §5g)
- **Captions**: cut by transcript ("remove the ums and false starts", on the words' timings, the
  edges from the VAD); a per-speaker label/colour through `CaptionLayout.Cue`; an `endpoint` (base
  URL host) key in `transcribe`'s result, in a phase changing the tool anyway (R6-12); windowed
  transcription (`audio_start_from`/`audio_end_at`), deferred until the estimate is seen to bite.
  (from: roadmap-04 §2 q8; roadmap-06 §7, §10.11)
- **Word captions' not-built list**: AI emphasis and emoji (ruled out by W-9); a sliding pill (a
  new `mode` value, W-4 appends); an in-word karaoke fill and "dim during silence" (need `end` in
  the recipe, already stored); restyle in place (regenerate; a per-media on-device cache if slow);
  WebVTT inline timestamps; filler words (`disfluencies: true`, a cache change under R6-15);
  per-word confidence styling. (from: roadmap-08 §7)
- **The recorder**: land the readable segments when one fails (today a paused recording fails
  whole, files named and kept, including the empty movie a pause within ~10 ms of a resume closes;
  `ScreenRecorder+Pause.swift:39-51`), with it a per-segment mic note rather than the
  session-wide `microphoneProblem` a mic stopped before its first sample (−11805) sets; Pause/Resume in the File menu beside Stop and a
  fixed-width status title (macOS hides an item that does not fit, and "●"/"❚❚" differ in width);
  a pre-roll mic meter during the countdown; picture-less voice-over as its own command, "a Source
  popup entry away". (from: roadmap-03 R2a, §5; app-notes RecorderPanelController)
- **Chrome**: square `StickerButton` or move its 13 callers (SH-1, "a phase of its own"); port
  SH-2's `drawBar` to Rasterize (`~/devel/rasterize/app/Sources/Controls.swift:321-333` still dims
  with `withAlphaComponent`), after which Reelcut's fork can close; road map 9's handoff items not
  built — the 64 pt label (CI-7 chose 76), the dashed ⊘ border, the boxed "clip" tag, "now" on ○,
  colour and popup rows, a keyed colour-well border, `DS.textDim`, hover states, the 8/10 body
  padding. (from: app-notes "Sharp chrome"; roadmap-09 §6)
- **Graphics' not-built list**: keyframed props (G-10 refuses `graphic` as a target);
  `paste_attributes` within one module; a module revision history (`cache/graphics/<rev>.js`);
  HEVC with alpha (an export row); mattes and video input (R5-1); system fonts as an opt-in
  document setting (gives up G-6); path helpers (length, point at length, draw-on); `delete_graphic`
  and `rename_graphic`. (from: roadmap-10 §7; svg-plan)
- **Graphics engine and tools**: named CSS colours and `hsl()` in a `color` prop and in
  `interpolateColors`; generic families (`sans-serif`) mapped to bundled faces; the `font`
  shorthand scanned; `measureText` with `xml:space="preserve"`; an explicit `Times New Roman`
  warned as "no font-family" (`raster.rs:76`, `:198-210`); asset-name validation; the asset-name
  list rebuilt per unknown href; a cap on the SVG string (only the 64 MB heap bounds it); an LRU
  cap on per-thread engines; a warnings channel on `compile`; `MAX_SIDE` 8192 written in three
  places; every scan re-validates every font; `render_graphic {format: "svg"}` ignores
  `background`, `max_width` and `path`; `frames` past the length are drawn, not refused; the
  contact sheet peaks near 4 GB at 16 × 8192²; `graphic_reference` ignores `project`; the harness
  copies no manual; the import handlers ignore `graphicImportSource`'s `path`; a successful
  export's graphic warnings are dropped at unpin. (from: roadmap-10 §10.4–§10.7)
- **The Graphic sub-tab**: the Title field is taller and top-aligned; a changed default, `options`
  or bounds does not rebuild the pane (G-15); a number with no `step` shows 0 decimals
  (`GraphicSchemaRows.swift:238`); the signature re-parses `describeJSON()` and asks `recipe(at:)`
  on every refresh; its asset names and the popup's items are built differently. (from:
  roadmap-10 §10.9)
- **Smaller**: agree the panel and MCP spellings (#43) of a caption name carrying another container
  (`chart.png.srt` vs `chart.srt`) by a spec §11 decision; a per-voice `Outcome` so Remove
  Silences' notes name a clip (pays §3's `SilenceDetector.swift` toll); create
  `~/Library/Application Support/Reelcut/` at `0700` at every creator (`ExportPresetsStore.swift:
  278`, `FFmpegRewrap.swift:535`); the Speed sheet showing the dissolve a neighbour gains rather
  than a length (a separate UI decision); the wipe measured in the pair's union box, not each
  layer's (spec §7.5's accepted price); speed ramps (`speed` is not an action target); a left-hand
  media browser with bins, gated only on spec §11's trigger now that search and sort landed.
  (from: remaining §2b, §5; roadmap-04 §8; roadmap-06 §10.13; roadmap-07 §12.2; survey §6, §8;
  roadmap-02 §4)

### 5e. Accepted limits a later phase may revisit
- **#28**: a lost submit reply is recovered by reading the newest 200 transcripts three times; an
  outage, longer lag, >200 intervening transcripts, several matches or a crash can orphan one. A
  durable pending-submission journal and an account janitor are outside it. (from: roadmap-06
  §10.14)
- **The janitor treats a 404 as a failure** (#44), so a well-formed id from another account holds the
  media for ever; what AssemblyAI answers for a foreign id is unmeasured (needs a second account,
  then a spec §11 entry). Also: a malformed file's deletion ids cannot be recovered, and a safe-id
  retry needs the originating account/region key. (from: roadmap-06 §10.10, §10.20)
- **#30**: transcript identity is modification second plus recorded duration, no content hash or
  path; an older build cannot read the four-key marker. (from: roadmap-06 §10.19)
- **The cache ledger**: a pass stuck in one AVFoundation call (a stalled network volume) holds
  every later pass for that media; `stripHolds`' listing and the marker write are two steps, so a
  swap between them would certify holes. (from: remaining §2a)
- **Client log lines are block-buffered** under a file redirect, so an instance log under-reports
  (`AssemblyAIClient+Session.swift` `note`); anything counting them needs a pty. (from:
  roadmap-06 §10.12)
- **The canvas text editor's line breaks can differ from the render** for UPPERCASE `case`,
  non-zero `tracking`, `line_spacing` ≠ 1 and a clamped zoom (it draws the plain string at `size ×
  scale`, 8–300 pt), and a rotated clip edits axis-aligned. Done would be the editor adopting the
  renderer's attributed string. (from: roadmap-02 #36)

### 5f. Deferred by the user, or out by decision
- **The effects survey's E3–E9, DEFERRED BY USER 2026-09-15**: tone/flip/mask (E3), thirteen
  filter kinds and a clock (E4), looks through a baked 3D LUT (E5), adjustment clips (E6), `.cube`
  LUT import as media (E7, "LUT import, but not now" — so LUTs are deferred, not a non-goal),
  offline voice effects (E8), Remove Background through Vision (E9). Their decisions D2–D7 are
  proposals, to be written into spec §11 (and §1) before each phase's code. Concat is AGPL-3.0: no
  code, shaders, chains or tables may be carried over. `designs/adr/effects-survey.md` has each
  phase's shape and first measurement. (from: survey §4, §6)
- **C2, the relay, DEFERRED BY USER 2026-09-21**: the plan is the person's own AssemblyAI key.
  Blocked on caller identity; the recommended shape is a bucket relay with a per-job webhook
  secret, a second `TranscriptTransport` conformer. (from: roadmap-06 §6, §10.18)
- **`KeychainStore`** waits for a stable signing identity; the key is a `0600` file because a
  rebuilt ad-hoc binary cannot read its Keychain item without a modal (§4f). (from: roadmap-06 §5d)
- **G6, graphics performance, DEFERRED BY USER 2026-09-25**: playback prefetch and parallel export
  with an ordered writer, each measured before and after, plus an in-place raster when `stride ==
  width × 4`. Baseline (G0 q3, M2 Max): 7.62 ms p95 worst at 1080p; `title-card` 26.19 ms p95 at
  4K. Trigger: a stutter on a slower machine or a heavier graphic. (from: roadmap-10 §9)
- **QuickJS vs JavaScriptCore**: GitHub #39 (open), for `Intl`; weigh G-2's reasons and G-5's
  byte-identical frames across OS versions. (from: svg-plan)
- **`DictationTranscriber`** for locales `SpeechTranscriber` lacks: not until a locale asks (W-8).
- **Out by decision** (spec §1, §11): camera recording, keystroke/click callouts, motion blur,
  stabilisation, optical-flow retiming, auto-reframe, multicam, other platforms; plugins except
  graphics' JavaScript modules (G-1). (from: roadmap-02 §4; roadmap-03 §5)

## 6. The Rust build settings, measured 2026-09-19

`[profile.release] lto = true` did not reach the shipped staticlib and did reach every test
binary. Cargo passes no `-C lto` to a unit whose crate types include `rlib`, and the lib is
`["staticlib", "rlib"]`; with `staticlib` alone it does, but every integration test (which links
the rlib) then fails to compile. So product LTO would cost a shim crate and ~18 s per `make app`,
for a JSON/arithmetic core nothing says would repay it. Meanwhile the line fat-LTO'd each test
binary: **166 s** for a test build after one edit, against **26 s** with `lto = false` and
**3 s** with `incremental = true` added (M2 Max, 12 jobs). rust-lld, `opt-level = 1` in dev,
sccache and nextest bought nothing; `panic = "abort"` is out (`ffi_agent.rs` catches unwinds);
`make test` stays `--release` because dev is no faster and tests a configuration that does not
ship. The shipped `.a` is codegen'd in more units (22 MB, not 32);
`CARGO_INCREMENTAL=0 cargo build --release` is the one-off way back. Landed 2026-09-19 as
`2d69fa4`, in `core/Cargo.toml`, and in `graphic/Cargo.toml` since G1:

```toml
[profile.release]
# No LTO: cargo skips it for a staticlib+rlib unit anyway, and asking for it
# fat-LTOs each of the 32 test binaries (designs/reelcut-remaining.md §6).
incremental = true
```
