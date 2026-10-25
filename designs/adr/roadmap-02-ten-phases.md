# Road map 2 — ten phases beyond the spec

- **Status:** Built. All ten phases were done between 2026-09-06 and 2026-09-10 (commits `febb324`
  (phases 0 and 1), `ccc5c34`, `3a64d85`, `17b80ba`, `4abad43`, `9d02cc6`, `488e55d`, `5083fde`,
  `2373567`). Three later fixes, #34, #35 and #36/#37, were recorded under it on 2026-09-24.
- **Original:** `archive/roadmap-2.md` (3601 lines) is the full record. Sections cited
  below as "orig §x" refer to it.
- **Spec decisions:** it introduced two unnumbered spec §11 entries. First, "`async`/`await` is
  allowed only in `MediaImporter`": speech used the callback API, and W-8 later amended this to
  add `SpeechEngine.swift`. Second, "Transcription reads EXTRACTED audio": a temporary mono
  16 kHz WAV per clip window, with the one-minute ceiling reported, and W-8 later removed the
  ceiling. It also introduced **R2-1** (one composition audio track per source audio format,
  #34), **K-1** (Space belongs to the transport unless something is typing, #35) and **K-2**
  (Return applies in the canvas text editor, a modified Return is a newline and Esc asks, #37).
  It relies on the overlap rule, timeline-wide ripple, "No left panel" and "Text and shapes are
  described, not rasterized".

## Context

After M1–M3, the op table, menus and key map were read against one question: what does a cutter
reach for and not find? The answer became ten phases, each closable on its own and each ending in
evidence: (0) groundwork; (1) cutting moves; (2) clip identity; (3) the screencast trio of remove
silences, zoom to region and obscure; (4) words: auto captions, caption export and text
animations; (5) sound: mono, meters, normalise, loudness and WAV/AIFF; (6) looks: blend modes,
gradients, backgrounds and filters as action targets; (7) output: Save Frame, ProRes 4444,
timecode burn-in, presets and a queue; (8) viewing and finding: preview quality, a preview window
and Media search; (9) editing inside a nest. The format went from v3 to v6 along the way.

§0 of the original also became the project's standing process rules. Later road maps still cite
those rules, so they are condensed first below.

## Decisions

### Inherited rules (orig §0, §5): still cited by later road maps

- **A new op is a JSON op through `rc_project_apply`, mirrored in every copy.** The copies are
  the `edit.rs` enum and table, an `impl Project` in a module of its own concern,
  `ReelCore.swift`'s builder, the agent catalog and handler, spec §6, and spec §7.10's module
  map whenever a MODULE is added. The header moves only for a new `rc_*` export.
- **A persisted field bumps `RC_FORMAT_VERSION`, with a serde default and a `schema_vN.rs` test.
  It lands in the same phase as its renderer.** A field that no renderer honours is a lie in the
  file. The "too new" fixture is written as "one past current", never as a literal number
  (orig §2 P6).
- **Every user-visible edit gets an MCP mirror.** A composite that the UI offers as one command
  gets one tool that performs the same composite. A pure nudge (`move_clip`) needs no mirror.
- **A file at the ~600-line cap gives something up before it takes anything on.** The cut is a
  pure move, landed and gated alone, and it is cut by CONCERN, not by line count. Budget it
  against the pessimistic estimate: a field's cost here has run at about 1.5× its estimate
  (P6, P8).
- **Frozen files take wiring only.** A feature goes in an extension file. An
  `extension TimelineView` in another file (`+Edge`, `+Rename`, `+Candidates`) is how the frozen
  view gains a gesture, an editor or a wash.
- **Proof means driving the built binary.** A frame claim is a BYTE comparison, an audio claim is
  a sample comparison of decoded exports, and the script lives in `tools/proof/`. A check that
  would pass against a build where the op did nothing is not a proof.
- **A proof must be made to fail (mutation testing).** Phase 6's three rules: restart the app
  between mutants (without a restart the harness scored a deleted feature 160/160); check that
  the mutant actually mutates; and assert a precondition before acting on it, because a crash is
  a worse detection than a failure. A verdict is named checks, never a fraction.
- **Every phase is read back adversarially before commit.** One reader per dimension. Every
  finding goes to sceptics who try to refute it, and every surviving finding gets a regression
  test that fails without the fix. This has never come back empty: 5, 6, 6, 12, 10 and 45
  survivors. Route a fix by the file it ROOTS in; tell the readers what is already known; and
  after a fix wave the orchestrator runs a lockstep pass over all mirror copies, because fixers
  move a source and cannot reach its mirrors.

### Phase 0–1: groundwork and cutting moves

- **`model.rs` holds only type declarations.** Lookups and `validate` went to `model_query.rs`,
  and the serde defaults stayed in `model.rs`, because an absent key's meaning is schema (orig
  §2 P0).
- **Counts live in one place.** The README no longer counts tools; `rc_op_names` and the parity
  check are the authority.
- **The six placement ops are core ops, and none goes in `edit_clip.rs`.** They are `slip`,
  `roll` (`edit_edge.rs`), `lift_range`, `close_gap` (`edit_time.rs`), `insert_clip` and
  `overwrite_clip` (`edit_insert.rs`). Insert and overwrite are single ops so that each is one
  undo step and one tool.
- **Locks.** `close_gap` and `insert_clip` refuse on a locked track, and `overwrite_clip` does
  not, because a lock only governs what may shift. `close_gap` checks overlap per touched track
  only, and it closes fully or not at all.
- **A source window's head, window and remaining length have one home.** That home is now
  `source_window.rs` (D4). A clamp BOUND snaps directionally (`time.rs`
  `snap_up_to_frame`/`snap_down_to_frame`), never to the nearest frame. `whole_media_length`
  returns a SNAPPED length: an unsnapped 5 s still made every overwrite on a /1001 timeline a
  silent no-op.
- **`lift_range` and `ripple_delete_range` share the same two helpers and differ only in the
  shift.** The helpers are `ordered_range` and `clear_range`.
- **The media selection is document view state.** `ProjectDocument.selectedMedia` is the fourth
  piece of view state and is clamped like the rest. `ProjectDocument.targetTrack` is the one
  rule for "which track does a command without a track act on".
- **A modifier-less menu key equivalent must be guarded against text editing.** AppKit resolves
  it ahead of the first responder. The same reasoning is why most later commands take no key.

### Phase 2: clip identity (v3)

- **`set_clip` takes a patch** (`{name?, label?}`: absent keeps, `null` clears), and an empty or
  blank string clears too. The name fallback lives in exactly one place,
  `ProjectSnapshot.name(of:)`.
- **The label is a badge and never a tint.** The kind owns the tint.
- **`paste_attributes` replaces each group WHOLE and never merges.** A text clip keeps its
  `content`; a shape keeps `kind`, size, `from` and `to`. Speed, `enabled`, actions, the
  transition, the source, the name and the label do not travel. A named group missing on either
  side is an `Err`, all or nothing. The source is the payload's EARLIEST clip, not the first in
  the array, and each copied group is re-checked with `check_group`.
- **Solo is a mixer switch on the set, and mute wins.** The rule is
  `silenced = muted || (any solo && !solo)` (`audio.rs`). It is judged per container and acts
  only as an envelope. "Solo A" gives a plan string byte-identical to "mute everything but A".
- **The inline rename editor drops unchanged and empty commits, and its field follows its
  target.** A `relocate` closure moves the field on every relayout instead of ending it.

### Phase 3: silences, zoom, obscure (v4)

- **Silences are cut by `ripple_delete_ranges` in one op; the singular form delegates to the
  plural.** A span is silent only where EVERY voice in scope is quiet, and a voice the mix
  silences (muted or soloed out) is dropped from the scope. A nest is a WALL: its sound counts,
  but no cut may intersect it. `detect_silence` runs on main, does not clamp its numbers to the
  sheet's ranges, and echoes them back. Road map 4 later replaced the level test with Silero VAD.
- **`add_zoom_action` is a core op, because the placement maths belongs to the core
  (`edit_zoom.rs`).** It reads rotation and crop evaluated at `at`; a null region zooms BACK to
  the stored base `scale`/`x`/`y`; the scale is clamped before the offsets follow it; and the end
  patch's keys are exactly `scale`, `x` and `y`. Its `curve` argument defaults to easing both
  ends, because adding it later would have split one gesture into two ops.
- **One region frame.** `model_regions.rs` defines one coordinate frame (the centre in source
  pixels, measured from the cropped rect's centre) and one `SpotShape`. A later region joins
  them.
- **The list-interpolation rule applies to LIST ENTRIES only (`actions.rs`,
  `ENTRY_DISCRIMINANTS`).** A list interpolates per index when the lengths match and each
  entry's discrete fields agree; otherwise it switches at the end. Named objects such as the
  spotlight keep the old rule.
- **Obscure runs between the sharpen and the point filters.** Running after the sharpen stops
  the unsharp term from putting detail back. Running before the filters makes the region graded
  like the picture around it.
- **Overlapping regions apply the stronger hiding alone.** Strength is measured as a length in
  source pixels × mix, and a tie goes to pixelate. The cover is weighted by each slot's own
  strength, so adding a region can never un-hide.
- **Defaults hide.** A region defaults to pixelate at amount 1 with feather 20, and a NaN amount
  clamps to 1. A list write whose LENGTH differs lands on BASE props.
- **Canvas modes are overlays whose presence is the mode.** `armCanvasMode` ends every other
  armed mode.

### Phase 4: words (v5)

- **The recipe computes the reveal.** The text layer carries `reveal`, `reveal_phase` and
  `reveal_kind` (by name), always emitted. `animation` is STRIPPED from the description, so an
  unanimated hash is unchanged (`recipe_text.rs` `Reveal`).
- **`reveal_phase` is the DRAW ORDER, and a tent keeps its first phase for life.** A tent is the
  case `in + out > duration`. The phase may turn only where the reveal is 1.
- **`text.animation` has three keys and no curve.** Overlapping phases degrade to the minimum of
  the two ramps rather than refusing, and both halves are measured on the clip's own duration.
  The layout cache key excludes the reveal, so the reveal cannot reflow the text.
- **The cue rules live in `CaptionCues` and apply only to producers that invent line breaks.**
  The rules are ≤2 lines, ≤42 characters, ≤6 s, and a gap of at least one frame. The SRT
  importer never applied them. `CaptionLayout` is the one place any producer lays out captions.
- **`transcribe` refuses a missing grant; only the sheet asks for it.** The caller's own mistakes
  are answered first, then an unknown language, then the grant, then a missing model. A job's
  failure is reported per job, and a clip with its audio switched off is skipped.
- **A partially revealed outlined line is drawn inside a transparency layer.** Otherwise the
  fill and the stroke fade separately.
- **Caption times round-trip at every rate.** Byte identity with a foreign file needs a
  whole-millisecond frame.
- **The inspector pane's bottom pin sits at priority 249, one below the sections' 250.** A tie
  made renders bistable across processes. Recognise that symptom by identical input scoring
  differently across runs.
- **A section exists only once `ClipPane.makeSections()` calls it.**
- **#36: the canvas text editor is sized from `LayerRenderers.measuredSize`, the same
  measurement that sizes the applied box.**
- **#37: K-2.** Apply goes through `performGroupedEdit`.

### Phase 5: sound (no schema change)

- **The meter reads the existing PreEffects tap and multiplies by the plan's envelope.** A
  second PostEffects tap cannot exist: an input has one `audioTapProcessor`, and the tap takes
  one flag or the other. Moving the DSP tap would reorder the channel strip. The number is exact
  per track but is a SUM of tracks, not a device measurement.
- **Metering happens only in the playback build** (`metering: true` from
  `Playback.startRebuild`), and that build taps every track. Export and `render_frame` are
  untouched.
- **`LevelMeter` publishes raw values; the view owns the ballistics.** It uses the app's only
  `import Synchronization`: relaxed atomics, because the render thread may neither lock nor
  allocate.
- **The mono fold goes after the compressor and before the pan.** After a pan it would
  self-cancel. It averages every channel.
- **Normalise REPLACES `volume`, writes BASE props and works per clip.** Replacing makes it
  idempotent. The source window comes from the PLAN segment, which refuses every case with no
  audio. The 4× clamp is reported where it applies, and failures come back under `skipped`.
- **Loudness is measured on EVERY export that has sound.** That costs about 0.1× the wall time
  of a picture export and 0.5× of an audio-only one.
  - The measurement uses its own composition, reads float and uses the BS.1770-4 gates.
  - The gain is gain only, with no limiter.
  - A bare `peak_dbtp` is refused.
- **WAV and AIFF are 16-bit only.** Their LPCM rows carry a non-null `avf_preset`, which now
  means only "AVFoundation writes this".
- **#34: R2-1.** One composition track per source stream description.

### Phase 6: looks (v6)

- **Blend is programmable blending through framebuffer fetch (`blendPremultiplied`).**
  Fixed-function blending must be DISABLED on those pipelines, and Metal does not complain if it
  is left on. Only a translucent-destination fixture catches that mistake.
- **Blending happens in encoded sRGB, deliberately.** The grade, the filters and the transitions
  all work in encoded space too. 50 % over 50 % multiplies to 64, where linear light would give
  about 61.
- **The CORE forces `normal` for a layer with a transition** (`recipe.rs::layer`). That keeps
  the dissolve's weight correction valid. The inspector shows the model's value in the meantime.
- **A nest clip refuses a non-normal MERGED blend, and the evaluator forces normal for nests**
  (`clamp_video(is_nest)`). A clip INSIDE a nest blends against the canvas below the whole nest.
- **The two background commands are core ops** (`edit_background.rs`: `add_background` and
  `add_blurred_background`). The rule: **a composite becomes an op when composing it from
  existing ops carries a constraint that no single op states**, here frame-exact sync with the
  source window.
  - The backdrop copy drops five things, starting with the audio switch.
  - The default plate is WHITE.
- **A gradient is painted by clipping to the path.** It is byte-identical to a fill only on fully
  covered pixels.
- **An inspector write reads `InspectorBinding.editedList`: the action's end list, else the
  base.** It never reads the evaluated list.
- **`maskState` (the shadow pass without the blend) is defensive, not load-bearing.** At
  destination alpha 0 the premultiplied formula reduces to the source.

### Phase 7: output (one new FFI export)

- **Save Frame and `render_frame` share one writer, `FrameWriter`** (a CGImage and a format in,
  a URL out). They are identical by construction; no test can measure it.
  - PNG gets a nil properties dictionary.
  - JPEG flattens onto BLACK.
- **`alpha` is a per-row CAPABILITY.** `prores_4444` and `apng` have it and `gif` does not. A
  ProRes 4444 export whose aspect changes is REFUSED
  (`ExportWriter.checkAlphaSurvivesTheSize`), because the padded letterbox came out with
  inverted alpha.
- **Burn-in is a RECIPE option, never an export override.** It goes through
  `rc_project_frame_recipe_opts`, `RecipeSource` and `renderFrame`, the last because GIF and
  APNG bypass the writer.
  - The layer is appended LAST, so a recipe without the option is byte-identical.
  - It is placed as a fraction of the canvas height.
  - The timecode is non-drop, in PROJECT time.
- **A user preset stores CONTROL CHOICES and never resolved values.** The core never learns about
  presets. The restore order in the sheet is load-bearing.
- **The export queue is a chain run on main with a fresh `Exporter` per job.** Two concurrent
  `Exporter`s deadlock.
  - `mediaURLs()` is captured at enqueue.
  - The controller contains no AppKit.
  - The queue has no MCP mirror, because it edits no project.

### Phase 8: viewing and finding (no new tool)

- **Preview Quality scales only the PLAYER's composition.** `Playback` varies a copy of the
  builder's configuration (a `mutableCopy()` until #91), so the export path cannot be reached
  from the setting at all. The size keeps the canvas's EXACT aspect, because the overlay maps
  through `videoRect`.
- **The preview window is an `NSPanel` retained by the editor controller.** A titled window left
  the editor's selectors dead, and `addWindowController` suppressed the save sheet (a data-loss
  shape). Two `AVPlayerLayer`s on one player both display; `displayedPixelBuffer` is the only
  honest instrument for that.
- **The find band hides and reorders rows and never rebuilds the pane.** A rebuild loses the
  caret. The sort is "Import Order", since no timestamp is recorded.
- **"Is this media used" has one answer, `MediaUsage`, and it walks nests.**
- **Fragment `[[position]]` is in DESTINATION pixels.** `LayerUniforms`/`ShadowUniforms` carry
  `canvasPerDest`. An invariant that holds because two numbers have always been equal is not an
  invariant.
- **#35: K-1** (`EditorWindow.sendEvent`).

### Phase 9: inside the nest (one new FFI export, `rc_project_scoped`)

- **An op gets a `scope` instead of teaching every op about nests.** `scope` is an envelope key,
  parsed in `edit.rs`'s existing two-pass parse because `deny_unknown_fields` forbids a top-level
  key. `scope.rs` builds a VIEW project, applies the op unchanged and merges the result back.
- **The view is built with care, and some checks run only on the merged parent.**
  - The view KEEPS the scoped nest's row, with its tracks emptied.
  - The write-back includes `media`.
  - Caps and depth are checked on the MERGED parent, so a valid inner op can still return `Err`.
  - A nest drop merges the union, and orphans are collected on the parent.
- **Seven ops are refused inside a scope:** the marker ops, `set_canvas` and the media ops.
  `refused_inside` is an exhaustive match. `nest` inside a scope is legal.
- **In the app, `nestPath` is a path of (nest, clip) steps.** The scoped handle is memoised.
  `editedProject` means the view, and `project` still means the parent for save and export.
- **A producer reads the container it writes into.** A range belongs to the container it was set
  in: it is refused, not mapped, because a nest clip is trimmed. This came from three findings
  of the same shape, a nest-local number spent as project time.

## What it built — where it lives now

- **Core:** `model_query.rs`, `source_window.rs`, `model_props.rs`, `model_regions.rs`,
  `model_text.rs`, `props_check.rs`, `patch.rs` (patch checking, `check_group`), `edit_edge.rs`,
  `edit_insert.rs`, `edit_time.rs`, `edit_zoom.rs`, `edit_background.rs`, `edit_paste.rs`,
  `edit_props.rs` (`check_blend`), `audio.rs` (`silenced`), `actions.rs` (the list rule,
  `clamp_video`), `recipe.rs`, `recipe_text.rs` (`Reveal`, the burn-in), `export.rs`,
  `export_table.rs`, `export_overrides.rs`, `scope.rs`, and `ffi_query.rs` (the recipe options
  and the scoped handle). Tests: `core/tests/{edge,insert,zoom,background,recipe,scope}.rs` and
  `schema_v3.rs`..`schema_v6.rs`.
- **App, timeline and canvas:** `EditorViewController+Edge.swift`, `TimelineView+Rename.swift`,
  `TimelineView+Candidates.swift`, `ClipLabel.swift`, `EditorViewController+ZoomRegion.swift`
  (with `CanvasRegionView`), `VideoPane+Obscure.swift`.
- **App, silences and captions:** `SilenceDetector.swift` and `+Walls.swift`,
  `SilenceSheetController.swift`, `MediaPeaks.swift`, `CaptionLayout.swift` (with `CaptionCues`),
  `CaptionExporter.swift`, `Transcriber.swift` (the engine is now `SpeechEngine.swift`),
  `AgentServer+Captions.swift`.
- **App, sound:** `AudioNormalize.swift`, `Loudness.swift`, `ExporterLoudness.swift`,
  `LevelMeter.swift`, `LevelMeterView.swift`, `CompositionBuilder+AudioTracks.swift`.
- **App, rendering and output:** `LayerRenderersText.swift`, `Compositor.metal`
  (`blendPremultiplied`), `Compositor.swift` (`maskState`), `FrameWriter.swift`,
  `EditorViewController+SaveFrame.swift`, `ExportQueueController.swift`,
  `ExportPresetsStore.swift`, `ExportSheetPresets.swift`, `AgentServer+Background.swift`.
- **App, preview, media and nests:** `PreviewWindowController.swift`, `MediaUsage.swift`,
  `MediaRowView.swift`, `MediaPaneCommands.swift`, `EditorViewController+NestScope.swift` (with
  `NestScope`).
- **App, keys and the canvas text editor:** `EditorWindow.swift`,
  `PreviewCanvasView+TextEditFrame.swift`, `PreviewCanvasView+TextEditKeys.swift`.
- **Proofs:** `tools/proof/phase{1..9}_proof.py`, `phase{2..9}_chrome.py`,
  `phase3_silence_scope.py`, `phase9_probe.py`, `mixed_audio_{probe,proof}.py`,
  `space_key_proof.py`, `text_edit_proof.py`, `text_apply_proof.py`, and `harness/` with its
  settle capture, cue mode and meter mode.

## Known limits

All of these were verified as still true on 2026-09-26.

- **Editing and the model:**
  - A solo on a non-front-most selected track stays behind when that selection is nested, and
    then silences the nest (`edit_nest.rs`). `unnest` carries no track flags back out.
  - The zoom does not track a rotation or crop animated between `at` and `at + duration`
    (`edit_zoom.rs:146`).
  - A PARTIAL `obscure` entry in an end patch interpolates and then takes
    `ObscureRegion::default()` at the switch. This is deliberate for regions and gradient stops
    (`patch.rs` `COMPLETE_ENTRIES`); a partial *filter* entry is refused since road map 7's D1.
  - A pixelated region takes ONE raw sample, so under a layer-wide blur its blocks are sharper
    than their surroundings. A blurred region combines in quadrature.
  - Stored obscure regions are not drawn on the canvas outside the region mode. `canvasQuad`
    (`CanvasSessions.swift:293`) is written and has no caller.
  - Remove Silences cannot cut inside a nest (a nest is a wall).
  - A text-animation tent with a tiny but non-zero `in` reports `"in"` for its whole life. An
    action can interpolate an animation's `in`/`out`, which slides its timebase.
  - An inspector blend popup shows the model's value while a transition overlap draws `normal`.
- **Sound:**
  - The meter is the sum of tracks × envelopes, not a device measurement.
  - Normalise sits under an animated volume, which overrides it for the action's span.
  - An UN-normalised export is written from an Int16 decode, so a mix past full scale stays
    clipped in it (`ExportLoudness.mixClipped` reports it). A normalised one is gained in float
    since #86 part 1 (issue batch B60, spec §11 #86). WAV and AIFF are 16-bit only.
- **Output:**
  - JPEG flattens alpha onto black. A ProRes 4444 export whose aspect changes is refused.
  - A burn-in timecode is non-drop, so at 29.97 it runs about 3.6 s behind the wall clock at the
    hour.
  - H.264 is not byte-deterministic. Two ProRes exports differ in 6 header bytes across a second
    boundary.
- **Preview, keys and the canvas editor:**
  - Preview Quality does not make the shadow passes cheaper (`shadowSilhouette` allocates at
    canvas size).
  - `selectedMedia` can point at a row the Media filter hides.
  - The canvas text editor (#36) draws without case, tracking or line spacing, and axis-aligned
    for a rotated clip, so its line breaks can differ from the render in those cases.
  - The instance deadlocks past about forty open documents; nothing closes one. Relaunch between
    proof sessions.
- **Measured and rejected:**
  - A second PostEffects meter tap cannot be created, and a PostEffects DSP tap would reorder
    the channel strip.
  - Blending in linear light would break every measured number.
  - A transparency layer for gradients would not close the last LSB.
  - `document.addWindowController` for the preview window suppressed the save sheet.
  - Rebuilding the Media pane on each keystroke loses the caret.
  - A settle capture alone did not fix the bistable renders; the 249 priority did.

## Open items

- **Person checks for phases 1–7:** gestures and keys (P1); the rename,
  label, solo and paste UI (P2); the Z mode and a face actually hidden (P3); captions legible and
  reveals in motion (P4); the meter in motion, mono and pan heard, −14 LUFS apparent (P5); blend
  and gradient on real footage and the blurred-background default (P6); relaunch keeping the
  export choice and the preview frame, and the queue window (P7/P8). Tracked in #47, #48, #51
  and #52.
- **Tracked in GitHub issues (defects and candidates):**
  - 24-bit WAV/AIFF through an `audio_bits` override (#86);
  - stored obscure regions drawn and draggable on the canvas (`canvasQuad` is the seed; #85);
  - `selectedMedia` pointing at a filtered-out row (#68);
  - the forty-document deadlock (#40);
  - the canvas text editor's line breaks against the render (#36), an accepted limit (#117);
  - #35's residue: other bare keys dead after a field commit, and Caps Lock (#60, #61).
- **Also tracked:** #34's built-in-speaker run and listen (#51), and the #35/#36/#37 and phase
  8/9 looks (#48, #47); the §4 left-outs — voice-over (#99), speed ramps (#111) and bins (#112),
  LUTs (deferred as E7, #122), motion blur and similar, multicam (out by decision, spec §1).

## Where to look in the original

| Section | What it holds |
|---|---|
| orig §0 (lines 25–172) | The inherited rules; the size-debt history; the mutation-run lessons; the session protocol and adversarial review. |
| orig §1 (173–233) | The status table with commits; "what phases 0–6 left behind", a table of shared seams (one row per helper and why a later caller joins it). |
| orig §2 P0 (236) | The `model.rs` split; the async decision. |
| orig §2 P1 (296) | The op table for slip/roll/lift/close/insert/overwrite; five review defects. |
| orig §2 P2 (487) | `set_clip`, `paste_attributes` and solo semantics; nine person checks; six review defects. |
| orig §2 P3 (753) | Silence, zoom and obscure design; shader stage order; the overlapping-region fix; the nest wall. |
| orig §2 P4 (1169) | Captions, the reveal recipe, tents, the one-minute ceiling, the 249 bistability. #36 at 1638, #37 at 1720. |
| orig §2 P5 (1798) | Why the meter design changed; loudness; true-peak tolerances. #34 at 2162. |
| orig §2 P6 (2252) | Blend, gradient and backgrounds; the mutant table (lines 2741–2749); the sRGB note. |
| orig §2 P7 (2796) | Save Frame, alpha, burn-in, presets and queue; 24 mutants. |
| orig §2 P8 (3063) | Preview quality, the panel spike, the destination-pixel blocker. #35 at 3230. |
| orig §2 P9 (3301) | The scope envelope; five places the plan could not be built; the review lesson. |
| orig §3 (3472) | The key and menu ledger, all promoted to spec §9. |
| orig §4 (3561) | Considered and left out. |
| orig §5 (3582) | What "done" means. |
