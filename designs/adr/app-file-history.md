# App file history — why the Swift files are the shape they are

- **Status:** Closed, reference only (2026-09-26). The notes stopped at the playhead-echo fix
  (`538db30`). `app/CLAUDE.md` is the live rulebook. This record holds only the reasons and traps
  that file does not state.
- **Original:** `archive/reelcut-app-notes.md` (2,934 lines) is the full record. "orig §x" below
  points to one of its headed sections or file-map rows, quoted by name.
- **Spec decisions:** relies on D4-6 (the reversed mirror has one home, in the app), R2-1 (one
  composition audio track per source format), K-1 / K-2 (Space, and the text editor's Return/Esc),
  SH-2 / SH-4 (`drawBar` forked from Rasterize; `StickerButton` squared in place, its owner-filtered
  tracking areas kept), CI-1, CI-5..CI-10 (Clip tab: selected action, sub-tabs, marks, Reset/Clear,
  refusal strip), W-8 / W-10 (on-device `SpeechTranscriber`; one `word_style` writer), R6-3, R6-7,
  R6-9..R6-13 (cloud captions). None of these was introduced here. The notes file only recorded what
  they did to each file.

## Context

On 2026-09-17 `app/CLAUDE.md` was cut back to a map plus rules, and its old text moved into this
notes file word for word (orig lines 24–2023). The notes then grew dated entries, one per change
that altered a file's role or paid a size toll (orig lines 2025–2934). Most of it is a log of
moves: line counts, which member became internal, scores, mutants. Two large families are now dead
text:

- Road map 7's D1 deleted every hand reader and hand check on the agent side: `patchArg`,
  `checkVideoEnums`, `checkTextEnums`, `shapePatchArg`, `gradientArg`, `motionPatchArg` /
  `AgentServer+Motion.swift`, `withOpaqueColors`, the `T??` round-trip gaps.
- Road map 8's W2 deleted the `SFSpeechRecognizer` half of `Transcriber`: the grant, the
  one-minute ceiling, the `OperationQueue`.

What is kept below is what still explains code that exists today.

## Already stated in `app/CLAUDE.md` (not repeated here)

These rules started life in the notes and the rulebook now carries them: frozen files and their
pitfalls; a section factory is not a section until `makeSections()` calls it; `editedList`; the
collapsed-state polarity; the 249 bottom pin; a rebuild keeps no first responder; the find band
never rebuilds; `structural(video:for:)`; `armCanvasMode`; the paused refresh's one-tick round
trip; Preview Quality's exact aspect; the preview window as an `NSPanel` and undo delegate; the
export's two passes and the alpha guard; the `metering` flag; the Compositor's five pipelines,
padding tail and `canvasPerDest`; captions as text clips and the cue rules; the popups rule; undo
grouping and the "do not flush" trap; the `async` and `Synchronization` confinement; the
`DispatchQueue` seams; tracking areas; `offMainTools`; `target(_:)`; `rawPatchArg` and the
lenient-decoding rule.

## Decisions

### Core edge

- **`ReelOp` lives with its factories in `ReelOps.swift`. Only `ReelOp.coreNames()` stays in
  `ReelCore.swift`.** A change like adding `scope` edits the struct and its factories together.
  `coreNames()` calls `rc_*`, and only `ReelCore.swift` may do that. `OpArgs` stayed `private`
  because it moved along with every user it has (orig file map, `ReelCore` · `ReelOps`).
- **Any addition to `ReelCore.swift` pays for itself first with a pure move of a type that names
  no `rc_*` symbol.** The precedents are `RecipeSource.swift`, `TextPatch.swift` and
  `MediaDescriptor.swift`. The file is far over the cap (orig "ReelCore.swift toll", "graphics
  wrappers").

### Motion (E2)

- **The core, not the app, turns a motion preset into placement.** The inspector and the canvas
  therefore see the clip without its motion, so a canvas drag begun mid-motion starts from the
  base box (orig `MotionProps` row).
- **A Zoom to Region armed over a clip with a During motion shows a second hint pill.** The zoom
  is solved without the motion. `regionNote` is re-read in `syncRegionMode` because a stored value
  went stale while the mode stayed armed (orig "Three Motion files", N·3).
- **The Motion menu's None is exactly `motionNoneTag` (−1).** A tag that no builder writes answers
  nothing. The old check `tag < 0` let a tag of −7 clear a clip's arrival (N·1).
- **The timeline's During glyph reads `dotLeft`, the position the label-dot branch decided.** It
  no longer infers it from `nameEnd`. This moves no pixel, and only its mutant fails (N·2).
- **Motion's Preview sets the in/out range to the clip and turns Loop on, and both stay set
  afterwards** (orig `VideoPane+Motion` row).

### Document and nest scope

- **`selectedMedia` lives on `ProjectDocument` rather than `MediaPane`,** because the pane is
  rebuilt whole whenever the media list changes.
- **Double-clicking a nest clip opens the nest, so it no longer renames the clip.** The open
  branch sits above the rename branch in `beginGesture`. ⇧⌘R, Clip ▸ Rename… and the header field
  still rename it (orig `+NestScope` row).
- **`validateNestScopeAction` runs FIRST in the validator chain.** It is the only validator arm
  that overrides another file's answer. `addMarkerCommand` guards itself for the bare-M key, which
  no validator covers.
- **`revealPlayhead` is internal.** `setPlayhead` returns early when the time is unchanged, and a
  scope change can leave the number equal, so the scroll has to be asked for by name.
- **Panes read two projects.** `InspectorBinding.project/snapshot/canvas` are the scoped ones.
  `document*` are the document's, read by `DocumentPane` and by exactly one question in
  `MediaPaneCommands`: which clips use this file, for Remove's alert, because `remove_media` is
  document-level.

### Timeline

- **The room outside the lanes answers a hit case of its own, `.outside`.** It shares one
  `beginMarquee` with `.lane`, so the two start points cannot drift apart. A bare press clears the
  selection at the press; ⇧ keeps it. `.outside` carries no row, so a double-click there closes no
  gap (orig `TimelineView` marquee row).
- **Reversed clips go through one mirror, and it is one tick HIGH on purpose.**
  `TimelineView.sourceTime` has a reversed arm and takes `in media:`, so the filmstrip and the
  waveform cannot diverge. The mirror is `ReverseMirror.swift` (D4-6). It is one tick high because
  `silence2_proof.py` claim 9 walks the current numbers tick for tick. The defect went unseen from
  M3 until 2026-09-20 because `CompositionBuilder` swaps in the reversed asset, which makes it
  right for a different reason.
- **`TimelineCaches.invalidate` clears only thumbnail MISSES, unless the post says `replaced`.**
  Only then does it also drop that media's decoded hits. A pass that replaces a strip without
  saying so leaves the old film on screen until the 800-entry drop.

### Rendering

- **`wordOverlap` (0.5) and `lineRiseFraction` (0.35) are named constants, not schema.** Their
  values are the animations' identity.
- **A shape gradient is drawn by clipping to the path and running `CGGradient` inside one
  `saveGState`, with no transparency layer.** This was measured byte-identical to `fillPath()`,
  antialiased edge included.
- **The renderer sorts gradient stops.** The core deliberately does not police their order,
  because a refusal would break a drag of one stop past another.
- **Gradient geometry:** A linear ramp projects the stroke-inset box onto its direction. The angle
  is in degrees counter-clockwise from the right, which is `(cos θ, sin θ)` in this y-up context.
  A radial ramp fills the inscribed ellipse, guarded against the negative-width rect that a stroke
  wider than the box makes. `line` and `arrow` ignore gradients. The texture key needed no change:
  `Source::Shape` hashes the whole shape (orig `LayerRenderers` row).
- **Compositor uniforms: zero means one.** The shader reads a non-positive `canvasPerDest` as 1,
  so an all-zero uniform block still renders what it rendered before the field existed.
  `ShadowUniforms` has 12 floats rather than 10, because 40 bytes is not a multiple of 16. The
  four obscure regions are laid out REGION-MAJOR, in the model's field order, so the shader and
  the Swift struct can be checked against each other by eye.
- **The programmable-blend check reads the ALPHA channel over a destination whose alpha is below
  1** (`phase6_proof.py` 6b). A check made with a translucent LAYER over an opaque backdrop scored
  160/160 against the broken build.
- **`maskState` in the shadow's silhouette pass is defensive, not load-bearing.** It was measured:
  the premultiplied formula carries the source through an empty destination. Keep it, but do not
  claim it holds a bug back.
- **A shadow is drawn source-over. A reflection inherits the layer's blend mode.**
- **Where obscure regions overlap, each region's share of the cover is weighted by its own
  strength.** A region at amount 0 cannot pull a neighbour to full strength.
- **The amount-to-length mappings are written in `CompositorEffects.swift`'s header** (blur
  `amount × 24`, pixelate `1 + amount × 63`). Proofs read them from there.
- **Preview Quality leaves `preferredMaximumResolution` at the canvas size.** It is a decode
  ceiling, and lowering it would change the frame by more than the resample does. Shadows cost the
  same at every quality, because the mask is canvas-sized. Odd render dimensions are fine; never
  round them to even.
- **Audio families: family 0 keeps the plan track's id.** Later families take ids from
  `firstExtraTrackID`. A segment with no readable source joins family 0 (R2-1, #34).
- **Each composition audio track holds its first segment's gain from time 0 (#87, issue batch
  B59).** `volumeLegs` in `CompositionBuilder+AudioTracks.swift` holds the envelope's value at the
  track's own first segment from 0, because AVFoundation starts a mix input at 1.0 and slews every
  volume change at full scale per 1200 frames; a hard cut on one composition track keeps the slew
  (spec §11 #87). **The file paid first** by a pure move gated alone: `audioParameters` with its
  doc comment to `CompositionBuilder+AudioTracks.swift` (`CompositionBuilder.swift` 585 → 535
  lines; `+AudioTracks` 178 → 228, 284 with the hold).

### Playback

- **A refresh asked for during a seek is remembered in `refreshWanted` and run when that seek
  lands.** The old guard dropped it, and that could lose the last tick of a live drag.
- **Do not "fix" the end-parked refresh into a return to the end tick.** The end tick composes
  black.
- **`seekSerial` marks a completion from an older seek as stale.** Without it, a seek cancelled by
  the rebuild's item swap would end the newer one.
- **`stepFrames` depends on the asked seek's echo.** The timeline follows the arrow keys only
  through that echo (orig "The playhead echo").
- **A scope change seeks through `seekAfterRebuild(to:)`, never `setPlayhead` (#130, issue batch
  B21).** Entering or leaving a nest rebuilds the item for the other container, and
  `finishScopeChange` used to call `setPlayhead`, whose ASKED seek went to the item still on the
  player: the OUTGOING one, measured in the old container. A time past that item's end clamped
  there and was heard, and the rebuild then restored to the clamped time — `phase9_proof.py`'s
  "mapped back out" failed on every run and three rows now and then (216, 215 and 216 of 218 at
  HEAD `f6bc11f`; 217, 215 and 216 at `538db30^`, so 538db30 did not cause it). The time is the NEW
  container's: with a rebuild in flight (`rebuilding`) it is HELD (`holding`, `isSeeking` true so
  `currentTime` answers it) and the rebuild's existing restore lands there, heard once; with none,
  it is a restore on the current item. Two neighbours of the same race went with it. An asked
  seek that arrives while a restore is seeking (a paused refresh's round trip, a rebuild's
  re-land) no longer clears `restoring`: it queues and is heard once where it lands, where it
  used to report the restore's intermediate ticks. And `update`'s same-plan and empty-plan arms
  bump `generation`, so enter-then-leave in one turn no longer installs the NEST's item under the
  timeline. `rebuildHop` (nil in the app) is `scope_playhead_probe.py`'s seam: it holds a
  rebuild's finishing block so a row can force the interleaving.
- **`Playback.swift` paid for it first**, by pure moves gated alone: `previewComposition` to
  `Playback+PreviewQuality.swift`, `stepFrames` to `Playback+Step.swift`, `meterInterval` to
  `Playback+Meter.swift` (598 → 546 lines; 551 with the seam; 595 with the fix, no fallback).
  `setPreviewQuality`, `init` and `makePreviewLayer` stay: they read the private `player`, and
  `phase8_chrome.py` counts `AVPlayer()` and `AVPlayerLayer(player:` in this file.
- **A held scope change whose rebuild will not land drops the item (#185, issue batch B30).**
  A held rebuild that FAILED cleared the hold and left the OUTGOING item on the player under the
  new container's time, measured in the old one; and the empty-plan arm dropped the item but left
  `restoring` set with the held time never heard. Both now drop the item and call
  `endHoldWithoutItem()` (`Playback+Scope.swift`), which clears the hold and the seek flags and
  reports the kept time once through `startSeek`'s no-item branch. The failure arm also clears
  `built` and `builtPlanJSON`, so the next update rebuilds. Outside a hold both arms are as they
  were: a failed rebuild keeps the previous item playing. The seam's block now takes an error,
  which `finishRebuild` receives as the build's failure, so `scope_playhead_probe.py`'s S13 forces
  a failed build, S14 the edit after it and S15 a container emptied under the hold; the rows that
  expect a report now require one (`all_at`'s `at_least`). **The file paid first** by a pure move
  gated alone: `seekAfterRebuild(to:)` to `Playback+Scope.swift`, with `isSeeking`,
  `pendingSeek`, `restoring`, `rebuilding`, `holding`, `seekSerial`, `lastKnownTime` and
  `startSeek(to:)` widened from `private` for that file alone (595 → 581 lines; 590 with the seam
  and the fix).
- **While paused, a late observer callback is dropped (#204, #209 item 1, issue batch B53).**
  AVFoundation can deliver a periodic-observer callback for a seek since superseded or an item
  since swapped out, and `timeAdvanced` reported it, so `document.playhead` took a tick the player
  was neither at nor seeking to: D2's drop heard 1.5 s then 2.5 s and selected action 4 (6 of 8
  runs of `clip_inspector5_probe` at `c39efca`), and S1's move once heard 0 (1 of 8). While
  `player.rate == 0` a tick is now heard only when it equals `currentTime` and differs from
  `reported`; while playing nothing changed. Because the observer may now say nothing, every seek's
  landing in `seekFinished` reports its rest once when it differs from `reported` — an asked seek
  as well as a restore. `playhead_echo_probe.py`'s `twice·1` (two asked seeks in one turn) failed
  3 of 3 before with `[1200000, 300000]` and passes after; `pause·1` (a user's pause mid-play
  lands the document on the player's rest) passes, and fails with the guard hand-tightened to
  `if player.rate == 0 { return }`. S1 (1 of 8 before, 0 of 8 after) is not shown fixed; see the
  README's B53 record. **The file paid first** by a pure move
  gated alone: `onMain(_:)` to `Playback+Step.swift`, `private` dropped (590 → 579 lines; 587
  with the fix).

### Export and still frames

- **`renderFrame` stays in `Exporter.swift`.** It holds the app's only `copyCGImage` call, and the
  root `CLAUDE.md`'s warning baseline names that warning by file.
- **The alpha guard tests the fit itself, not a ratio.** Measured: padding inverts alpha (the
  picture comes out at alpha 0 and the bars at 255), while a pure scale is clean both up and down.
  The guard asks `encodedSize`, because the round-down to even let a 1001 × 667 transparent
  document through the default row.
- **The export card's controls:** Burn-in shows PROJECT time. A range export starting at
  00:00:10:00 reads that timecode from its first frame. `resolveCard()` copies Export…'s enabled
  state onto Add to Queue, rather than reading `resolved` twice. The Preset gear is a pull-down
  because the control column is 258 pt.
- **Export queue:** A cancelled job's file is removed and a failed job's file is kept, matching
  the progress sheet. `isLaunching` turns an early synchronous refusal into a loop instead of
  recursion. The window is not a copy of `WelcomeWindowController`: that one closes on becoming
  main and cannot be resized. `isExcludedFromWindowsMenu`, or the Window menu lists the queue
  twice. It persists nothing.
- **`FrameWriter`'s nil PNG properties dictionary is a guard.** On macOS 26.5.1, `[:]` writes
  byte-identical PNGs, so only `phase7_chrome.py`'s structural read can see the difference. A nil
  from `CGImageDestinationCreateWithURL` is two failures, reported apart: a format this Mac does
  not offer, and a file that could not be created. Renames go through `FrameWriter.renamed`,
  `CaptionExporter.renamed` and `ProjectDocument.displayStem` (whose set is `{reelcut}`), never a
  bare `deletingPathExtension`. "Board v1.2" became "Board v1.jpg". Save Frame validates on
  `duration > 0`, so a text-only timeline can be saved. It reads the project in the panel's
  completion, because a panel is not a sheet and the document stays editable while it is open.

### Media import and caches

- **`CacheLedger` (`MediaCacheLedger.swift`) is an `NSCondition`, not an actor.** Passes for one
  file run in call order; a pass for another file cancels the earlier ones, which write nothing
  more and are waited for at most 30 s; no marker, waveform or voice file is written while a save
  of the package is in flight (`ProjectDocument+CacheSaves.swift`, at most 120 s a save); a failed
  waveform pass is retried in the session after 2 s and 10 s (#115, #169).
- **One stamp per pass, shared by both halves,** so the two markers cannot disagree about one
  file.
- **`stripHolds`:** a marker is written only when at least one frame landed and every frame
  written is still present, the listing and the marker inside one publication no announced save
  overlaps; a frame lost to a save's swap leaves the strip unmarked until the next open.
- **`replaced` rides only the FIRST post of a replacing pass.** Since 2026-09-19, speech's
  pre-decode withdrawal carries it too.
- **The held tail uses the track's LAST SAMPLE time** (an `AVSampleCursor`), never the record's
  rate. A sparse recording's `nominalFrameRate` is meaningless: three frames in 50 s reads as 0.06
  fps. The held frame is requested at its exact time, because an ffmpeg sparse file fails (−11821)
  just past it.
- **`AppSupport` accessors create only the Application Support root.** The caller creates the leaf
  folder when it has something to put there.
- **`SileroVAD`:** The remainder is held across `feed` calls, so a chunk that straddles two
  buffers is not lost. It is not `async`. `bundledURL` looks in `Bundle.main`'s `Models` first,
  then beside `bundleURL`, which is the harness's layout.
- **`writeSpeech` reads 16 kHz mono FLOAT.** It must not reuse the old extractor's Int16 settings.
- **`SpeechStamp` wraps `CacheStamp` with the model name and chunk size,** so a model change
  rebuilds speech caches and no filmstrips.
- **The speech `.bin` is not bit-identical to `probabilities(of:)`.** `alwaysCopiesSampleData =
  false` changes the converter's block sizes. The difference is at most 0.0022 and every decision
  at 0.5 is the same. The row that proves the carried remainder is 1000-sample `feed` plus
  `flush`.
- **`MediaPeaks` never uses `TimelineView.sourceTime`.** That function multiplies by speed and
  rounds the rate a second time. `MediaPeaks` uses the plan segment's resolved rate.

### Silence

- **The level fallback is keyed per scoped VOICE, not per media.** A file that is voice and then
  tone, split in two, used to have its voice clip judged by level too. `judgedByLevel` still names
  MEDIA (the media sets are kept, and `judged_by_level` with them); since #107 `Outcome.answers`
  holds one `VoiceAnswer` per scoped voice, and the sheet's notes and `detect_silence` name the
  CLIP from it.

### Inspector and Clip tab

- **Section ids are shared across contexts:** `video.speed` is Speed for a video clip and the
  first group an audio-only clip gets. An "open the first section" rule therefore walks until it
  finds one the user has not stored.
- **`InspectorNameField` and the timecode field set `stringValue` directly when a commit ends,**
  because the refresh is skipped while the field editor is attached.
- **The slider knob is `DS.textStrong` at full alpha.** A translucent `labelColor` knob split into
  two colours over the two-colour rail.
- **The mark gutter sets its row's keyed border through `layer`,** so the files copied from
  Rasterize stay unforked.
- **`InspectorTextArea` hugs at priority 1.**
- **`retiredPinned` holds the outgoing pinned block for one generation,** because a sub-tab click
  lands inside that block's `mouseDown`.

### Media tab

- **Measured:** an `isHidden` arranged subview leaves `NSStackView`'s layout entirely, and
  `insertArrangedSubview(_:at:)` MOVES a view while keeping the first responder and the caret.
  `arrange()` rests on both facts.
- **The find band is not persisted.** A defaults key would have to be pinned in the harness.
- **Two usage questions:** `clipsUsing` answers over every clip: the timeline's plus every nest's,
  including a nest nothing points at, matching the core's `every_clip()`. Filtering the timeline
  alone made removing nest-only media a bare beep. `timelineClipsUsing` is what a selection can
  hold, so Reveal in Timeline validates FALSE for media used only inside nests.
- **Reveal:** It accepts being switched to the Clip tab. Its vertical scroll grows the rect upward
  by the ruler's height.
- **The row file was cut below the drag.** A drag source and its vocabulary (the pasteboard type,
  the drop targets) are one unit.

### Windows and keys

- **An `NSWindow` subclass declares an unavailable coder init.** That alone stops Swift inheriting
  `init(contentRect:styleMask:backing:defer:)`, so that init is declared beside it and only
  forwards (`EditorWindow`, K-1). `handleEditorCharacter`'s `case " "` stays for the preview
  panel's forward.
- **The preview window persists its frame under ONE fixed autosave name,** never one per document.
- **The archived AVFoundation guide says a second `AVPlayerLayer` blanks the first. Measured false
  on macOS 26.5.1.** `isReadyForDisplay` and `videoRect` are useless as instruments for it.
- **`NSPopUpButton` has no `item(withTag:)`.** Use `menu?.item(withTag:)`.

### Recording

- **API traps:** `NSObject` already has `finalize()`, so the recorder's is `settle()`. Reading
  `outputURL` off a fresh `SCRecordingOutputConfiguration` TRAPS; `make` assigns it first. Use the
  completion forms of `SCShareableContent`. The error type is `SCStreamError.Code`.
- **The microphone session starts first, in the same run-loop turn.** `startRunning()` blocks main
  for 100–180 ms, which was accepted. `prepareMicrophone` is paid during the countdown; without it
  the first voice arrived 421 ms late.
- **The recorder has no settable hook; `onFinish` is passed to `start`.** A panel press refused as
  `.busy` once erased the tool's hook.
- **The panel asks for both grants on every press.** A `canAsk` gate left a `notDetermined`
  microphone unrecoverable.
- **The panel side:** `land()` reads the outcome off the project HANDLE, because
  `performGroupedEdit` answers nothing. The countdown and the tick run in `.common` run-loop
  modes. The welcome window's New Recording… has its own selector, because `newRecording`'s first
  arm stops a recording.
- **`tooShortNote` follows the core's round-down snap through `SilenceDetector.snapDownToFrame`**
  (#22).
- **In `untitled(around:)`, the import count runs BEFORE the microphone edit.** Counted the other
  way round, one ⌘Z read clean and ⌘W closed the document without a prompt.
- **`RecordingToolChrome` is `AgentServer+RecordingChrome.swift`** (issue batch B27): the named
  cut out of `AgentServer+Recording.swift`, which sat at the 400-line cap, as a pure move with
  `private` dropped, before the chrome took its observer of the recorder's
  `pauseDidChangeNotification` (#181).

### Agent handlers (surviving after D1)

- **`fpsPair` / `rateTerm` are stricter than `intArg`.** A numeric string is refused. A whole
  double is accepted. Each term is bounded by u32 and named by its own path. The app refuses every
  term case itself, because the core names only a zero term in a sentence of its own. The fix also
  removed a live `Int(1e30)` trap.
- **`set_transition_style` with no keys is refused by name.** An identity would tell the caller
  the project was already in that state.
- **`detect_silence` stays on main.** It reads a few hundred KB.

### Captions

- **The caption round trip returns every cue to its tick.** Millisecond rounding is at most 300
  ticks, and half a frame is 10,000 ticks. Byte identity with the original file needs a
  whole-millisecond frame (25 or 50 fps), which is why the fixture is 25 fps and the same fixture
  at 30 fps must NOT come back byte-identical.
- **Placement refusals keep the producer's `tag`** (`line 12`, `clip 7`).
- **The speaker rule is tested BEFORE placement, in the same loop.** Tested inside placement it
  would never fire for a word that happened to fit.
- **`writeFLAC` streams 16,384-frame buffers.** Ten hours of 16 kHz mono is 1.1 GB of PCM.
- **`wholeAsset` is an infinite range.** `AVAsset.duration` is deprecated, its replacement is
  `async`, and the reader clamps the range anyway.
- **`CloudProgress.fraction` takes the phase ends EXACTLY,** because 0.65 + 0.30 × 1 ≠ 0.95 in
  floating point.
- **The transcribe sheet's `.apple` arms are verbatim moves.** `phase4_proof.py` reads their exact
  sentences.
- **The harness duplicates the `CaptionCues.Word(` call under `#if !HARNESS_REFERENCE_BUILD`,** so
  it still compiles against older trees.
- **`defaultLanguage(in:)` compares BCP-47.** The raw compare never matched and fell through to
  "English (Australia)".

### Shared chrome

- **`Controls.swift` sits over the cap (648) by the sync rule.** `BlockSlider` was copied verbatim
  from Rasterize. SH-2 is its only fork. SH-4 (#100) squared `StickerButton` in place to
  Rasterize's drawing; its owner-filtered tracking areas stay.

## What it built — where it lives now

Every file named above exists under `app/Sources/`. The one exception is
`AgentServer+Motion.swift`, deleted by D1·3 (`eb17289`).

Files that were split since the notes wrote them:

| Notes named | Now also |
|---|---|
| `MediaCacheFiles` | `MediaPeakBuckets.swift`, `MediaImporter+Peaks.swift` (#23) |
| `Playback` | `Playback+Meter.swift`, `Playback+PreviewQuality.swift`, `Playback+Step.swift` (B21; `onMain`, B53), `Playback+Scope.swift` (B30) |
| `ReelCore` | `RecipeSource.swift`, `TextPatch.swift`, `MediaDescriptor.swift`, `OpDictionaries.swift` (#190) |
| `InspectorPane` | `InspectorSection.swift`, `InspectorSectionHeader.swift`, `InspectorSlider.swift`, `InspectorBinding+Writes.swift`, `InspectorNameField.swift` (#171) |
| `ClipPane` | `ClipSelectionHeader.swift`, `ClipPane+Timing.swift` |
| `VideoPane` | `VideoPane+Obscure.swift`, `VideoPane+Speed.swift` (#190) |
| `Transcriber` | `+Languages`, `+Jobs`, `+Extract`; `SpeechEngine.swift` |
| `TranscribeSheetController` | `+Commit`, `+Cloud`, `+Download`, `+Style` |
| `SilenceDetector` | `SilenceDetector+Vocabulary.swift` (#107) |

`TimelineCaches` is a class inside `TimelineView.swift`.

## Known limits

Still true of the current code:

- `SileroVAD` marked unavailable never retries until relaunch.
- macOS hides status items that do not fit the menu bar, and Pause/Resume live nowhere else. "●"
  and "❚❚" differ in width, so the bar shifts at a pause.
- The picture and the microphone are ONE op list. A microphone track the caps refuse takes the
  picture down with it.
- `place: false` stores no microphone offsets.
- A second `PostEffects` meter tap cannot be built: there is one `audioTapProcessor` per input.
- Closing the transcribe sheet mid-download lets the download run on (a decision).
- The playhead echo has no MCP drive: no tool reads the live player's reports.
- The canvas text editor shows an UPPERCASE text as typed, so a capital wider than its letter can
  wrap where the render does not; a rotated clip is edited axis-aligned (spec §11 K-3, #117).
- `AssistantComposerField` refits on a width change inside its own `layout()`; moving the refit to
  its `setFrameSize` (B37) or to `AssistantView.layout()` (B47) lagged one pass (#182 item 3,
  accepted). B47's P13, one `layoutIfNeeded()` each with the 41-character message: 26.0 pt at
  480 (want 26.0), 26.0 at 263.0 (want 41.0), 41.0 at 480 again (want 26.0); the height
  constant 26.0, 26.0, 41.0 against text view widths 390.0, 156.0, 390.0 (inferred, not
  measured: the nested field's frame is not yet the new width when `AssistantView.layout()` runs).

## Named next cuts

The size rule is in the root `CLAUDE.md`; which files are over it is `wc -l`, never a table here.
What follows is only the SEAM each over-cap or at-edge file's record named, so the phase that has
to pay a toll starts from it. A file not listed has no named seam yet.

- `ProjectSnapshot.swift`: a property group's snapshot types out, whole. The precedents are
  `TextProps.swift` and `ProjectSnapshot+Graphic.swift`.
- `ReelCore.swift`: the typed patches (`// MARK: - Typed patches`). The `dictionary` extensions
  went to `OpDictionaries.swift` in issue batch B52b (#190), the media helpers earlier to
  `MediaDescriptor.swift`. It stays the only file that calls `rc_*`.
- `ProjectDocument.swift`: stored properties cannot move; the natural cut is the media/reverse
  machinery, in the shape of `+DisplayStem`, `+Import`, `+Graphics`.
- `InspectorPane.swift`: the precedents are `InspectorSection.swift`, `InspectorSlider.swift` and
  `InspectorBinding+Writes.swift`.
- `ExporterWriter.swift`: the settings/encoder half.
- `OptionControls.swift`: the precedent is `OptionControls+Choices.swift`.
- `VideoPane.swift`: a section out as an extension, the precedent `VideoPane+Obscure.swift`.
- `AgentServer+Clips.swift`: the clip-placement handlers against the property doors.
- `AgentServer+Scope.swift`: the envelope rule (`checkCallScope`, `effectiveScope`, `idScope`,
  `addressed`, `checkDocumentLevelTicks`, `scopeLanding`, `scopeFailure`) against `set_scope` the
  tool (`setScope`, `nestScopePath`, `pathToClip`, `applyNestScope`, `commonPrefix`,
  `scopeReport`).
- `SilenceDetector.swift`: the quiet test (`gain`, `level`, `isQuiet`, `isAudible`) with `Voice`,
  widened from private.
- `SilenceSheetController.swift`: the menu command extension (`removeSilencesCommand`,
  `validateSilenceAction`) into `EditorViewController+RemoveSilences.swift`, re-pinning
  `inventory.json`'s site.
- `CompositionBuilder.swift`: the orientation helpers (`orientationCodes`, `trackOrientations`,
  `orientationCode`) to `CompositionBuilder+Orientation.swift`.
- `Playback.swift`: `seekFinished()` and `report(_:)` to `Playback+Scope.swift`, with `reported`
  and `refreshWanted` widened from `private` for that file alone (B30's shape). `player` stays
  private.
- `AppDelegate+Menus.swift`: a submenu builder out (the precedent is
  `AppDelegate+GraphicMenu.swift`).
- `Controls.swift`: held to the sync rule with Rasterize's copy (`app/CLAUDE.md` "Shared chrome");
  7 of its lines are the SH-2 fork of `drawBar` (#101).
- `ReelOps.swift` is exempt (a table, one row per op). `TimelineView.swift`,
  `PreviewCanvasView.swift`, `EditorViewController.swift` and `AgentServer.swift` are frozen and
  take wiring only.

## Open items

- A real mouse band pressed from below the lanes. Tracked in #48 ("The marquee from below the
  lanes").
- A person drags a clip and sees no flash to 0 and no jump. Tracked in #48 ("Dragging a clip
  leaves the timeline still").
- Rasterize's `BlockSliderCell.drawBar` still has the SH-2 defect upstream. Tracked in
  kpgalligan/rasterize#335 (moved from #101).
- Pause/Resume live only in a status item that macOS can hide (#98).

## Where to look in the original

- Lines 1–23: the preface, and the list of what D1 deleted.
- Lines 30–1922: the archived file map, one row per file family, holding the measurements behind
  each decision above. Rows, in order: `ReelCore` · `ReelOps`; `MotionProps`; `ProjectDocument`;
  `+NestScope`; the marquee; the reversed mirror; `LayerRenderers`; `CompositionBuilder+…`;
  Playback / Compositor / Exporter (uniforms, blend rules, paused refresh); `MediaImporter` caches
  and the held tail; Captions and Transcriber (pre-W2); frozen files; Inspector pitfalls; Media
  tab; Export sheet and queue; `EditorWindow`; AgentCatalog / AgentServer (pre-D1 readers); Sound;
  SileroVAD and speech; SilenceDetector; Eyedropper and ZoomRegion; FrameWriter; Recording (setup,
  recorder, landing, panel); Preview Quality and the preview window; Rename, Identity, Clipboard,
  ClipLabel; the chrome files.
- Lines 1924–2023: the archived Rules section, superseded by `app/CLAUDE.md` Rules.
- Dated entries: "Three Motion files" (N·1..N·3); "Two frame-rate pair readers" (`fpsPair`, the
  `Int(1e30)` trap); "Three / Six / Nine / Thirteen caption files" (C1's tolls, parts, run and
  chrome, file by file); "Five caption files change role" (W2, `SpeechEngine`); "Three text files
  pay first", "Two sheet files…", "W4b residue" (road map 8); "Sharp chrome" (SH-1/SH-2 and the
  proof adjustments); road map 9 phases 2 / 3a / 3b (inspector moves and roles); `#36` / `#37`
  (the canvas text editor's frame and keys); G1a / G1d (the `ReelCore.swift` toll, the graphics
  wrappers); "The playhead echo" (cause, fix, measurement).

