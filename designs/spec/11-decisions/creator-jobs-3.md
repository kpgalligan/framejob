# Spec §11 — decisions: Creator jobs, the cutout onward (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) and
[`creator-jobs-2.md`](creator-jobs-2.md) (CJ-, VR-, TX-, SW-, CU- and CO-), so a citation never has
to say which file; `creator-jobs.md` says what the road map builds and how its IDs are made (CJ-7).
This file is new because `creator-jobs-2.md` passed the road map's ~500-line split rule with CO0's
entries (2026-11-01), which moved here; each phase's decisions are appended here from now on,
before its code.

CO-1…CO-9 are CO0's (bet 6's scope: Remove Background and the layouts), recorded before its code
and before its spikes ran; the spikes' verdicts were appended after the runs, and CO-S2's rewrote
CO-3 and CO-4 to the mask pack. The owner's answer of 2026-11-01 to the road map's CO0 question —
what happens if CO-S2 passes neither the mask track nor the mask pack — was *file the video
cutout, build CO10's stills, and go on with CO6–CO9*: recorded, with no stop, and not needed (the
pack passed). Nothing in this bet needs a key:
person segmentation is Vision on the Mac and hide-while-silent reads Silero's spans; no CO control
or tool is in `ModelKeys.keyed` (CJ-3).

- **CO-1 — Remove Background uses Vision on the Mac.** Video uses
  `VNGeneratePersonSegmentationRequest`, a FRESH request per frame, on the device CJ-S2's rule 1
  picks for it (CO1 re-runs rule 1), never `.fast` (stateful). Pictures may use
  `VNGenerateForegroundInstanceMaskRequest` (CO10); video never does (it flickers). This adopts
  #124's D5. A matting model, shipped or downloaded, is allowed by CJ-1 and not built here; it is
  filed as a candidate only if JOB-60's verdict asks for it, and Frame Job being Apache-2.0, a
  GPL-3.0 or AGPL model (Robust Video Matting, Concat's) cannot ship in it.
  **Spike CO-S1 (2026-11-01, `rule_sha256` `035665d1…9fd05a`, matching CJ0a's table; S-KEY1 and
  S-TH1 missing, so speed only, and (a), (b), (d), (e) and (f) owed):** `VERDICT
  standard=person-balanced rate=every realtime_1080=1.81 realtime_4k=1.62@source,2.10@1920
  mask=512x384 first_call_ms=123.8 read_size=owed best=owed flicker=owed rotation=owed`.
  **Standard is person `.balanced` at every frame**, the first rate at which it reaches 1.0×
  realtime on the 1080p30 push-in (1.723, 1.810, 2.034 over three runs; 4.085× at 15 a second and
  5.413× at 10), a fresh request per frame on the Neural Engine (`ane(16 cores)`, request
  revision 1), its mask 512 × 384 whatever the frame's size. On the 4K push-in it ran 1.62× read
  at the source size and 2.10× at a long side of 1920. A fresh process's first request took
  123.8 ms. For the record (no rule reads them without S-KEY1): person `.accurate` ran 0.476× at
  every frame, 1.265× at 15 and 1.201× at 10 at 1080p (mask 2016 × 1512, first request 147.9 ms);
  the person instance mask, scaled, 0.696×, 1.457× and 2.260× (mask at the read size, first
  request 415.0 ms). Three lanes shared the machine (one-minute load 2.8…52 across the rows). Owed to
  S-KEY1, before CO4: J, B, flicker and rule (a), the rate by B (b), Best (d), the read size (e)
  and the rotated composite (f); S-TH1's speed rows; and CO-S3, at CO4's head.
  **CJ-S2 rule 1 re-run for the mask request (CO1's head, 2026-11-01, `rule_sha256`
  `c41417fb…95bb2b11`, matching CJ0a's table):** `VERDICT device=gpu branch=1
  identical=cpu:yes,gpu:yes,neural_engine:yes realtime=cpu:0.34,gpu:1.89,neural_engine:1.60
  compare=cross_run`. The mask request is pinned to the **GPU** (CO-11), not the Neural Engine
  CO-S1 measured on: all three devices' three runs were byte-identical, and the GPU's median was
  the fastest. The three devices' masks differ from one another.
- **CO-2 — The cutout is a property of the clip's own layer, not a matte track.** `video.cutout`
  on a media or still clip. A luma matte track holding a rendered mask has no link to the camera
  clip, so a trim, split, slip, speed change, ramp or reverse would slide the outline off it
  (MT-2); a per-layer mask is fetched the way the picture is and follows every edit. Closed
  vocabulary; R5-1 and G-1 stand.
- **CO-3 — The mask reaches the compositor from a per-media mask pack, looked up through the
  picture's own segment (rewritten at CO0: CO-S2 failed the mask track and kept the pack).** A
  cutout adds no composition track: the plan, the composition, `CompositionBuilder.firstExtraTrackID`
  and the eight-decoder warning are what they are without it. For each request, the compositor maps
  the composition time through the covering picture segment's linear map in ticks to the source
  time the picture shows there (a reversed clip's in the reversed stream it reads), takes the
  source frame shown at that time (the last at or before it, as AVFoundation holds a frame), and
  draws the mask of the NEAREST analysed source frame, ties to the earlier, in the stream the
  segment reads: exact at every-frame analysis, nearest at a capped rate. A reversed clip's
  analysed times are mirrored by `reversed_time(pts, end, T) = T − end`, `ReverseMirror`'s CMTime
  convention (the frame shown from `pts` until `end` lands at `T − end`), never `T − pts`. The
  mask's bytes go from the pack to the compositor as stored and never pass AVFoundation's colour
  path. **Spike CO-S2 (2026-11-01, `rule_sha256` `577a8f39…709eee`, matching CJ0a's table; S-TH4
  missing, so (1)'s HLG variable-frame-rate source is the `ffmpeg` fixture, and S-TH4 is owed):**
  `VERDICT route=mask-pack encoding=none chunk_s=none class=none registration=22/22 colour_max=0
  iou=none edge_mad=none mb_per_min=none playback=100.00 build_ms=+1.7 fixed_pct=none`. **The mask
  track failed.** Every one of its six (encoding, L) pairs registered 22 of 22 rows: eleven cases
  (a trim, ×0.5, ×2, ×1.37, a ramp, a freeze, a reverse with mirrored chunks, a split, a nest, a
  cross-dissolve and the HLG VFR source, each straddling a chunk boundary), at every frame and at
  15 a second. It played 601 of 601 frames with and without the mask track over 20 s crossing five
  boundaries. HEVC passed (2) at 0.062 levels with the plain class in SDR and the converting class
  in SDR and HLG, and (4) at 5.85 MB a minute. But it failed (3): over CO-S1's 1080p Standard
  masks, the decoded masks' mean IoU against Vision's was 0.9829 (pooled 0.9915, the worst frame
  0.565), under 0.995, though the edge band's mean difference was 1.14 levels. ProRes 422 Proxy failed (3) at 0.9802, (2) at 24.4 levels (full-range values in a
  video-range format) and (4) at 15.16 MB a minute. L was 30 s for both encodings: the build
  (60 minutes as 120 clips, median of 10) added 604.1, 170.1 and 47.6 ms with HEVC at 5, 10 and
  30 s, and 457.7, 202.7 and 59.1 ms with ProRes; one chunk's fixed cost (25.3 and 64.1 ms) came to
  0.15 % and 0.39 % of analysis time at 30 s. **The pack passed** (1) 22 of 22, (2) 0 levels over
  120 masks (the stored bytes read back outside any composition, which holds by construction),
  (5) 601 of 601 frames with its lookup and decompression in every request, and (6)
  1.7 ms over the build (7.05 against 5.38 ms), reading `long_60m`'s tables. Three lanes shared the
  machine (one-minute load 5.7…70.8).
- **CO-4 — Masks are an analysis kind on CJ2a's lane and store, one pack per media (rewritten at
  CO0 to CO-S2's pack).** Kinds `masks` (Standard) and `masks_best` (Best, only if CO-S1 keeps it).
  The store is CJ-22's: `cache/analysis/masks/<media id>.json` with the stamp (no path; the kind's
  version, the request digest and revision, rate, read size, OS build, device), and one payload
  file, the pack `cache/analysis/masks/<media id>/masks.pack`: a frame table (each source frame's
  time and the slot of its nearest analysed mask), an offset table (each distinct analysed mask's
  time, offset and length) and each distinct analysed mask once, 8-bit at Vision's own size,
  compressed with `NSData.compressed(using: .lzfse)`. The grid is CJ-23's analysed frames;
  CJ-22's coverage holds the analysed ranges, each run recording `subject_found`, and a publish
  rewrites the pack whole through CJ-22's `.partial` and rename. A reversed clip reads the same
  pack, mirrored at lookup (CO-3), never a second analysis and no mirrored file (D4-6). Masks are
  in DISPLAY orientation. `get_media_analysis {media, kind: "masks"}` answers runs (`from`, `to`,
  `subject_found`, frame count) and the stamp, never pixels. The package carries the folder.
  Clarifies CJ-22 (one payload file per media, in the media's folder); amends CJ5b's CJ-51
  (`cache/analysis/` copied whole, the packs included). Where CO-5 and CO-6 say "chunks", read the
  analysed ranges a run covers. **Spike CO-S2 (2026-11-01, `rule_sha256` `577a8f39…709eee`,
  matching CJ0a's table; S-TH4 missing, owed):** the pack has no chunk length and no encoding, so
  neither L nor an encoding is settled; the track's would have been 30 s and HEVC (CO-3). **A
  measured risk, no rule:** the pack of CO-S1's 1080p Standard masks (600 masks of 512 × 384, every
  frame) took 20,772,076 bytes, 62.32 MB a minute, against the HEVC track's 5.85: an hour of camera
  is a few gigabytes of masks.
- **CO-5 — "No person found" is decided per clip window.** A clip whose analysed chunks found no
  subject (no mask with ≥ 0.5 % of its pixels above 127) draws uncut, its status "No person
  found"; once any chunk of its window finds one, every analysed frame honours its mask, so a
  person who walks out leaves an empty picture. Swift decides it from the runs' `subject_found`;
  the core never reads analysis (CJ-20).
- **CO-6 — A frame without its mask draws uncut; a file waits (amends CJ-28).** Pending, cancelled
  and failed chunks draw the clip uncut, never blank and never the slate. An export waits for
  every chunk its range needs through `Exporter.withRampAudio` and fails with `cutoutFailed`
  naming the clip when one fails. `render_frame` and File ▸ Save Frame… wait up to 30 s for their
  one frame's chunks, then draw uncut and say so (`render_frame` in a sentence before its last;
  Save Frame in an informational sheet after saving). The eyedropper and the look gallery do not
  wait. A render-substituted kind shows no Analyzing sheet: the person keeps editing and the
  Background section says what is happening. A command that PLANS from masks (CO7's centroid)
  reads only what is cached.
- **CO-7 — The analysis sees the picture as SDR; the mask is not a colour (amends CJ-23).** A
  converting media is read by `AVAssetReaderTrackOutput`, every frame's presentation time kept,
  and each frame converted through step 0's own pass (`InputPass`) on the GPU — not through the
  one-clip composition, whose frames lose the source's times. The mask is a coverage 0…1
  multiplied in at step 7 like the corner radius and the matte, the same in SDR, HLG and
  linear-light projects; it never passes step 0 (mask track ids never reach `InputStage`; a mask
  buffer is wrapped raw). Which compositor class a composition with a mask track uses is CO-S2
  (2)'s verdict. Any edge refinement reads the picture as the chroma key reads it (`KeyReading`,
  HD-13 (h), HD-20). **Spike CO-S2 (2026-11-01, `rule_sha256` `577a8f39…709eee`, matching CJ0a's
  table; S-TH4 missing, owed):** no class is chosen for masks. The pack's masks never become a
  composition track, so they never pass AVFoundation or step 0 (0 levels off over 120 masks, read
  back outside any composition, so by construction), and a composition with a cutout is built with
  the class it would have without one; read "mask track ids" above as the pack's bytes, uploaded
  as stored. For the record, the track's row (2): HEVC full range read 0.062 levels off with the
  plain class in SDR and with the converting class in SDR and HLG, so the plain class did not
  conform it; ProRes 422 Proxy read 24.4 levels off in all three.
- **CO-8 — Where it is drawn.** The mask binds at `texture(4)` (CJ-8 (b)) on every layer,
  shadow-silhouette, reflection and matte draw, a 1×1 white placeholder when the layer has no
  cutout; sampled at the same DISPLAY-space coordinate as the picture (after the spotlight lens
  and the pixelate snap, before `orientedUV`). `LayerUniforms` gains one group of four (enabled,
  edge, feather, a spare): 132 → 136 floats, 528 → 544 bytes, if it lands first. In general the
  block is 132 + 4·g floats (528 + 16·g bytes) after g groups of four have landed, and CU3a2 adds
  several (the sprite rect, the ripples' positions and phases, their colour and size), counted at
  its own landing; the integrator re-pins the size proofs at each landing (CJ-8 (b)). The shadow
  and reflection follow the cut outline (MT-3).
- **CO-9 — The spikes' rules are CJ0's**; CO-S4 is retired into CJ-S3 (b), which CO1 re-runs with
  a masks job. Amendments recorded at CO0: CJ-22 (CO-4's clarification), CJ-23 (CO-7's third arm),
  CJ-28 (CO-6). CJ5b writes CJ-51 with the masks included (CO-4). Recorded in later phases: MT-1,
  MT-2, MT-4 (CO5), R5-4, AU-110 (CO9), CAM-10 (3), CAM-10 (5), CAM-4, CAM-11 (CO8). Standing:
  R5-1, G-1, R5-4's mechanism, R5-5, D4-6, W-8, #367, CU-5, MT-9, the Concat rule and its
  extension to AGPL recorders.

TX-20…TX-23 are TX2a's (the Transcript tab), recorded before its code but the view TX-S2 measures.
TX-S2 ran at the phase's head on 2026-11-01 (its rule's `rule_sha256` `543a3027…24dad40c09a`
matches CJ0a's table): candidate (b) meets every bound, the numbers in TX-21. The owner's TX2a
answers of 2026-11-01: (1) the host is the fifth inspector tab; (2) a timeline click while the
transcript shows: stay and scroll; (3) the title is "Transcript" if T1 passes, else "Words"; (4)
⌃⌘T, yes; (5) ⌘F later, unless it comes free (the last three minor, taken as recommended).

- **TX-20 — The Transcript is the inspector's fifth tab: Clip, Media, Document, Transcript,
  Assistant. View ▸ Transcript (⌃⌘T) shows it. Amends AI-4, AI-14 and AI-19.** The pane is
  `AssistantPane`'s shape (one view, built once, scrolling itself, exactly the visible height); the
  menu item is in `AppDelegate+ViewMenu.swift` directly before View ▸ Assistant. ⌃⌘T is free: ⌘T is
  Split, and no ⌃⌘T is bound in `AppDelegate*`. `InspectorTab`'s raw value is the strip index, so
  the Assistant moves from 3 to 4; every reader goes through `.assistant` or `allCases`. **The
  title** is "Transcript": at the 280 pt minimum each title's `DS.sans(12, weight: .semibold)` width
  fits its `tabRect` (`transcript_tab_probe.swift`'s T1). **A click on a clip** while the
  Transcript tab shows leaves it showing and scrolls the transcript so the clip's first word (for a
  nest clip, the first word whose `id.nest_path` starts with it) is at the top, with no seek
  (`clipPicked()`'s first line); from every other tab a click still shows Clip. A selection change
  that is not a click leaves the Transcript tab showing, as it leaves the Assistant's. **Find
  (⌘F)** is later, filed: a TextKit 2 view gets no `NSTextFinder` for free. AI-4's line: "the strip
  has five tabs; the Assistant is fifth, after Transcript." AI-14's line: "the Transcript tab is
  kept like the Assistant tab on a selection change that is not a click; a click on a clip also
  leaves it showing and scrolls the transcript to that clip's first word." AI-19's line: where the
  Assistant tab is too narrow for the dot right of its title (`title.maxX + gap + diameter > tab.maxX
  − 2`), the dot is raised at the title's top-right corner, `x = (tab.maxX − 2 − diameter).rounded()`,
  `y = max(1, (title.minY − diameter).rounded(.down))` in the flipped badge; at 280 pt the Assistant
  tab is about 56 pt and the old clamp put the dot on the word. Risk accepted: the transcript gets
  the inspector's 280–440 pt, and showing it hides the Clip tab.
- **TX-21 — The transcript view is not an `NSText`**, so the editor's bare keys still reach
  `handleEditorKey`, with no change to a frozen file. It is TX-S2's candidate (b): a custom `NSView`
  laid out by TextKit 2 (`NSTextLayoutManager` over `NSTextContentStorage`, viewport layout).
  **TX-S2's verdict (2026-11-01, OS build 25F80, macOS 26.5.1, Apple M2 Max, 12 cores, 96 GiB, on
  AC; three lanes sharing the machine, load average 21.05 30.45 28.38):** over 27,000 synthetic
  words in 900 paragraphs on two tracks (40 collapsed, 300 struck, 10 % not editable) in a 304 ×
  800 pt scroll view, medians of 20: the first layout and draw of the visible part 10.7 ms (rule ≤
  200), a rebuild with one word removed 24.9 ms with the anchor kept (≤ 100), a highlight moved to
  the adjacent word 0.036 ms and to one 5,000 words away 0.037 ms (≤ 2; moved, then
  `displayIfNeeded`), `tokenIndex(at:)` 0.0047 ms (≤ 1), a selection across three paragraphs drawn
  0.17 ms, 30.7 MB of added `phys_footprint` (≤ 1/256 of physical memory, 402.7 MB); the view is no
  `NSText`, `SpaceKey.route` answers `.transport` with it first responder, and J, K and L sent
  through `window.sendEvent` reach a sink past it. (c) and (a) were not built. Two findings shaped
  the view: TextKit 2 draws a dynamic colour (`labelColor`) into a `CGContext` as nothing, so the
  text is styled with colours resolved in the view's appearance and restyled when it changes; and
  one attributed string per word made a rebuild 131.8 ms on a busier machine (load average 44.70),
  so the text is built as one string and styled by ranges. **Keys**, as first responder: ← and →
  select one word and seek to it (`onActivate`); ↑ and ↓ select the word nearest in x on the
  adjacent laid-out line and seek; ⇧ with any of these extends the selection without seeking; ⌘A
  through `selectAll(_:)`, which the nil-target Edit ▸ Select All reaches first; Esc clears the
  selection, or passes the key up when there is none; ⌫, ⌦ and Return pass up unchanged until TX3
  and TX5. Every other key goes to `super.keyDown`, so J, K, L, I, O and M work as on the
  timeline, and Space never reaches the view (`SpaceKey.route` takes it at the window). Arrows
  deviate on purpose: words here, frames on the timeline. A click makes the view first responder.
- **TX-22 — The view.** **The highlight** is the latest word whose start is at or before the
  playhead, lit through the pause after it (a binary search over the tokens, which are in start
  order), an accent-tinted rect behind the word; a move invalidates only the old and the new rects.
  While playing the view keeps it in sight unless the person scrolled within the last 3 s
  (`NSScrollView.willStartLiveScrollNotification` or `didLiveScrollNotification`). **A click** on a
  word puts the playhead at the word's frame-snapped start (`setPlayhead`), playback continuing if
  it was playing. **Paragraphs:** consecutive tokens a and b are in different paragraphs when the
  track or the speaker label changes; across instances (clip or nest path) on one track when
  b.start − a.end ≥ 1.5 s; within one instance when the media's pause set holds a's source tick.
  The pause set comes from `TranscriptTokens.pauses`, once per media, off main: word w is in it
  when the voice cache has a run of 32 ms chunks inside [w.source, w′.sourceEnd) — w′ the next
  source word — all below `SilenceDetector.Settings.defaultVoiceConfidence` and lasting ≥ 1.5 s of
  SOURCE time; with no voice cache (`MediaImporter.loadSpeech` answers nil), when w′.source −
  w.sourceEnd ≥ 1.5 s. Each paragraph leads with `ReelTime.format(start, fps:, frames:)` in the
  canvas's timecode style, and a click on it seeks there. Words that cannot be cut are drawn in
  `DS.textFaint` with TX-11's sentence as the tooltip, one per contiguous run, on the visible line
  fragments only; clips with no words are listed above the text as "clip N — reason". **Rebuilds**
  happen on a new `editedProject` handle while the tab shows, never while `document.isLiveEditing`
  (the next refresh after the gesture rebuilds once), anchored on the top visible word's `Identity`
  at its offset, else the nearest later start. **The fill:** while it shows, the tab's fill owner
  (TX-12) wants the needed media ONE AT A TIME, the one under the playhead first, then by first
  start, in the Mac's default language (`Transcriber.defaultLanguage(in: Transcriber.languages())`,
  off main), each media's words shown as soon as its run is stored. The misses wait in a
  lock-guarded list the next `update()` replaces; one waiter, on a serial `.utility` queue of its
  own (never the load queue), wants the first, waits for it, and moves on; a media dropped from the
  list while it runs is released, and the waiter takes the next. A failed run shows its sentence
  and is not wanted again until the tab is next shown. Hiding the tab releases the want. **The
  status** reads "Reading “name” on this Mac… NN % (k of n)", polled every 0.25 s; with no model,
  "This Mac has no speech model installed. Choose File ▸ Generate Captions…, pick a language and
  press Download." Notes are the same-speech notes only. Risk accepted: a cloud transcript made
  while the tab shows appears the next time the tab is shown. (TX2b's bar — Words from, a
  per-window track filter, and Language — is not this phase's.)
  **Amended 2026-11-02, by TX-24:** the status, the same-speech notes and the clips with no words
  live in the tab's bar, pinned above the text, not in a stack scrolled with it.
- **TX-23 — `transcript_view` is a dev tool** (Debug and Release, never Distribution), off main
  with every step through `onMain`: `transcript_view {project?, focus?: boolean, select?: [integer,
  integer] | null, click?: integer, wait?: number}`. It applies `focus` (the view made first
  responder), then `select` (inclusive token indices; null clears), then `click` (the mouse-click
  path: the selection and `onActivate`), then polls every 0.05 s for up to `wait` seconds (0–60,
  default 0) until the tab's source is settled. It refuses a project with no window in
  `select_inspector_tab`'s sentence shape, and a tab that is not shown: "select_inspector_tab {tab:
  "transcript"} first." It answers `{ok, settled, tokens: [TX-13's word row + {index, paragraph,
  struck}], paragraphs: [{index, start, timecode, first_token}], highlight, playhead, playing,
  selection, first_responder, fill: {media, fraction} | null, owns_want, status, no_words: [{clip,
  nest_path, tag, reason}], notes, rebuilds, last_rebuild_ms, top_token, project}`. TX2b's buttons
  are not in it.
  **Amended 2026-11-02, by TX-27:** it also takes `words_from`, `language`, `stop_after` and
  `read`, answers `bar`, and its `status` may be `stopped`.

TX-24…TX-27 are TX2b's (the Transcript tab's bar), recorded before its code. No owner question
was asked: the road map names none for TX2b, and TX2a's answers of 2026-11-01 stand.

- **TX-24 — The bar.** It is pinned above the transcript's text and is the pane's ONE
  `makeHeader()` instance, built once in the pane's `init`, so the controller hosts it above the
  scroll view as it hosts the Clip tab's header (`ClipHeaderBlock`'s shape); it does not scroll.
  It has two rows in `InspectorMetrics` — an `InspectorRowLabel` at `labelWidth`, then an
  `OptionPopupControl` spanning the rest of the row — "Words from" and "Language". Below them is
  the status row: its sentence wraps, and at its right is Stop (shown while the tab's waiter
  reads) or Read (shown when stopped). Then come the wrapping notes: the same-speech notes, then
  at most 3 rows of "clip N — reason", then "…and N more clips with no words.", whose tooltip
  lists the rest. Everything collapses when empty. A popup is rebuilt only when its titles change.
  Amends TX-22: TX-22's status, notes and no-words rows live in the bar.
- **TX-25 — Words from and Language are per-window view state**, never saved, kept for the pane's
  life whether the tab is hidden or shown. **Words from** lists "All tracks", then each track of
  the edited container by name, in snapshot order; one choice. A chosen track that leaves the
  container falls back to All tracks. With a track chosen, the fill wants only the media with an
  instance on that track (`Instance.track`); the words are built from every instance with the
  media loaded, then kept where `word.track` matches, so the tokens and their ids equal
  `get_timeline_transcript {tracks: [id]}`'s. The same-speech notes come from the shown words;
  `no_words` is unfiltered, as in the tool. **Language** lists "Automatic (<the default's
  identifier>)" (its name, "Automatic (English (United States))", runs past the popup's chevron
  at 280 pt), then `Transcriber.languages()` by name, read once per show on the load queue; with none
  installed the popup is disabled. A choice drops the `.apple` words, their pause sets, the misses
  and the failures, and the waiter's want (as a hide does), then runs `update()`; device words are
  then read in that language (`<media>-<lang>.json`). A cloud transcript still wins (TR-11), as
  with the tool's `language`. The load queue resolves the choice by
  `Transcriber.language(matching:in:)`, else the default.
- **TX-26 — Stop withdraws only the tab's want** (`fill.release(owner:)`, on a line ending `//
  Stop: the tab's want only (TX-26)`); it never cancels another owner's run, so a waiting
  `get_timeline_transcript` call's run goes on. After Stop the status reads "Stopped. N file(s)
  not read on this Mac.", with Read. Stop holds through edits and through Words from or Language
  changes; only Read or the tab's next show resumes. **The order inside `stop()`:** set
  `stopped`; then, under `lock`, set `pending = []`, `pendingTotal = 0`, `waiting = []` (so a Read
  before the waiter wakes pends its media again, as a hide does) and `wanting = false`, then the
  anchored `fill.release(owner:)`, then unlock. `generation` is not bumped, so a run that stores
  as Stop lands is still loaded. The waiter, woken with `.cancelled` (or `.stored`), finds
  `pending` empty and exits without wanting the next media. With `stopped` set, nothing is
  pended; with no misses left the status is idle.
- **TX-27 — `transcript_view`'s bar arguments. Amends TX-23.** `transcript_view {…,
  words_from?: integer | null, language?: string | null, stop_after?: number (0…60), read?:
  boolean}` applies, in order, `words_from`, `language`, `read`, `focus`, `select`, `click`, then
  schedules `stop_after` (pressed on main that many seconds after the answer, through the bar's
  own Stop path), then `wait`. Refused before anything moves: a track not in the container,
  "words_from names track N; Words from lists a, b, c."; `language` through
  `AgentServer.checkSpelling` and then `transcriptionLanguage`; `select` or `click` together with
  `words_from` or `language`, "select and click name tokens of the view as it is; set words_from
  or language in a call of their own."; `read` together with `words_from` or `language`, "read
  presses the bar as it is; set words_from or language in a call of their own." (a new track or
  language empties the misses, so Read would be checked against a bar about to change, then not
  pressed); `stop_after` while Stop is not shown, "Stop is not shown:
  the tab is not reading on this Mac."; `read` while Read is not shown, "Read is not shown: the
  tab's reading was not stopped." The answer adds `bar: {words_from, tracks: [{id, name}],
  language, languages: [{identifier, name}], stop_shown, read_shown, stop_after: "pending" |
  "pressed" | "not shown" | null}`, and `status` gains `stopped`. The press is scheduled because
  every tool call holds `AgentLane`'s one lock, so no call can press Stop while
  `get_timeline_transcript` waits.

CO-10…CO-15 are CO1's (person masks on the Mac), recorded before its app code. CO-11 is its head
spikes' verdict: CJ-S2's rule 1 read for the mask request picked the GPU, so CO-S1's speed-only
rule was re-measured there. CO-12 was written pending CJ-S3 (b)'s run with a masks job, and its
verdict was appended after the run. Nothing here needs a key (CJ-3), and nothing is project
state (CJ-20).

- **CO-10 — The mask pack.** The `masks` kind's one payload file is
  `cache/analysis/masks/<media id>/masks.pack`. Its bytes are little-endian:
  - the mask blobs, each analysed mask once, 8-bit at the size Vision answered for the media,
    compressed by `NSData.compressed(using: .lzfse)`, in append order;
  - the frame table, 16 bytes a frame: `Int64` pts in source ticks, `Int32` grid index, `UInt32`
    slot (its nearest analysed mask). It is sorted by pts, each pts at most once;
  - the mask table, 24 bytes a mask: `Int64` pts, `UInt64` offset from the file's start,
    `UInt32` length, `UInt8` found, three zero bytes. It is in append order, so a slot never
    moves;
  - the footer, 40 bytes: `FJMP`, then `UInt32` version (1), width, height, frame count and mask
    count, then `UInt64` tables offset and `UInt64` 0.

  **The publish is an append-merge** (`AnalysisStore.publishFile`, the one door, CJ-22). It runs
  under the per-media lock inside `CacheLedger.publish(in:for: nil)`, and re-reads the marker. It
  deletes the marker, then the folder, when the stamp is stale or when the marker answers but its
  pack is missing. It removes any old `.partial`. The kind then writes the `.partial`:
  - When an on-disk pack parses at this version and the job's size, it is cloned to the partial
    (`FileManager.copyItem`, an APFS clone) and cut at its tables. Only the masks whose pts its
    mask table lacks are appended; a pts on disk keeps its slot and its bytes. The merged frame
    table follows (on disk wins at an equal pts), then the extended mask table and the footer.
    A publish that made no mask (a range of only dropped frames) has no size of its own, so it
    merges onto a pack that parses at the pack's own width × height.
  - Anything else (no pack, a pack that does not parse, another width × height when the job made
    masks) is written fresh.

  The rename comes next, and the marker last. Its coverage is the union of the on-disk and the
  job's only when the kind merged; otherwise it is the job's alone, so a coverage never claims
  frames its pack lacks. A throw removes the `.partial` and leaves marker and pack as they were. A
  lookup is a hit only when the marker answers, its first payload file is on disk, and the
  coverage holds the need (every kind; `shots` too, whose marker without its `frames.bin` now
  misses and rebuilds instead of answering no cuts).

  **What a pack holds:**
  - The width × height in the footer is what Vision answered for the media, never assumed. The
    job's first mask sets it, and a later mask of another size fails the job ("Vision answered a
    w × h mask, not W × H"). A frame with no observation gets an all-zero mask at that size; a
    frame before any mask has no mask, and the job fails naming its pts.
  - Measured: 512 × 384 for every landscape media read (the 640 × 360, 1080p and 4K push-ins)
    and 384 × 512 for the portrait pair (360 × 640 displayed, whether coded so or
    rotated by its track's transform), so the size follows the displayed orientation.
  - A mask's `found` is CO-5's flag: at least 0.5 % of its pixels above 127 (`count × 200 ≥ w ×
    h`).
  - The request is person `.balanced`, revision 1 pinned, read at the source size (the long side
    `max(width, height)`) until CO-S1 (e) settles a read size.
  - The stamp's `vision` field records the request, quality, revision, rate and read size, and is
    compared with the rest of the stamp (`matches`). It is nil, and absent from the marker, for
    `shots`.
- **CO-11 — The device and the rate.** The mask request is pinned to the **GPU**
  (`AnalysisMasks.computeDevice`). That is CJ-S2's rule 1 read for the mask request: every frame
  of `push_1080.mov`, three runs on each device, each run's SHA-256 over all mask bytes. All three
  devices were byte-identical across their runs, and the GPU's median was the fastest (CPU 0.34×,
  GPU 1.89×, Neural Engine 1.60×).

  The pick is not the Neural Engine, so Standard was re-measured on the GPU (`--only s1 --device
  gpu`), with this result: `VERDICT standard=person-balanced rate=every device=gpu
  realtime_1080=1.23 realtime_4k=1.59@source,1.98@1920 mask=512x384`. At 15 a second it ran
  3.93× and at 10 a second 5.44× at 1080p. CO-S1's speed-only rule keeps **every frame**
  (`AnalysisMasks.rate`), and **1.23× is the Standard factor** CO1's M9 reads (0.8 × it).

  Three lanes shared the machine: one-minute loads were 9.6…44 across the rows, and the GPU's
  1080p every-frame runs were 0.917, 1.228 and 1.971.

  The device a pinned request reads back is the stamp's `device` (`gpu`), read once per process.
  A job refuses to run when a request reads back another device, so the stamp never claims a
  device it did not use. Every proof compares runs across runs (rule 1's first branch).

  A capped rate r, if a later re-measure ever steps down, works as follows. The analysed frames
  are the first frame at or after each k / r s (CJ-23). The read is widened by ⌈fps / r⌉ indices
  each side, so every covered frame's nearest analysed frame (ties to the earlier) is in the job.
  Only the range's frames enter the frame table.

  A job publishes at each range's end and every 30 s. A mid-range publish covers only through the
  last analysed frame done (`AnalysisMasks.covered`), so no published frame's nearest mask is
  still to come.
- **CO-12 — CJ-S3 (b) with masks.** Rule (b) is re-run with a masks job: a
  1080p30 timeline's `play_preview` frames over 20 s, idle and with another document's masks job
  on the ten-minute still, three each, on a Release instance. If composed frames fall by more than
  2 %, the picture queue pauses while any transport plays, for a `masks` request only. `shots` and
  `split_at_shots` never pause; CJ-21 (b) stands for them, measured with a `shots` job.
  **Verdict (2026-11-01, `rule_sha256` `209c6f01…f0309ce830`, matching CJ0a's table; a Release
  instance; S-TH4 missing, the synthetic 1080p file):** idle 599, 600 and 600 frames composed;
  with a masks job wanted just before each play (on the GPU, over the still's first 120 s; each
  job had started and had not ended when its play returned) 600, 600 and 600; **a drop of 0.0 %, so
  no pause.** CJ-21 stands unamended for every
  kind, `BackgroundRender` takes nothing, and CO1 has no M11. Each busy run's document was closed
  after its play, which cancelled the job.
- **CO-13 — The third arm (CO-7, amending CJ-23).** A converting media is read for `masks` by
  `AnalysisFrames.decodeThroughInputPass` (`AnalysisFrames+InputPass.swift`,
  `AnalysisFrames.Source.arm = .inputPass`):
  - An `AVAssetReaderTrackOutput` over the first video track decodes to
    `Compositor.sourcePixelFormat`, Metal compatible, at the natural size scaled to the long side.
    Every frame keeps its track's presentation time, which is the reason for the arm: the one-clip
    composition's converted reader hands back the composition's grid.
  - The conversion is chosen once per read: `InputConversion.choose(input:)` on the media's
    Camera Log, else `choose(for:)` on the track's first format description.
  - A `.lut` is read through `LutTextures.texture(at:)`.
  - `InputPass.encode` runs unpremultiplied, with the range flag as the stamp records it
    (`readsRange` and the track's flag), a PQ media's effective peak, and output `.sdr`. It draws
    into a `.shared` `rgba16Float` target made per read.
  - The target is read back, rounded to 8-bit BGRA as `halfToBGRA` does, and turned upright as
    the direct reader is (`Upright`).

  `shots` keeps CJ-23's two arms. The stamp is CJ-22's converted stamp; nothing new is recorded.
- **CO-14 — `get_media_analysis {kind: "masks"}`'s answer.** It carries the common fields (`ok,
  kind, media, clip?, from, to, size, cached, stamp, run?, project`) and these kind fields:
  - `mask_size` [w, h], from the pack's footer, or null with no pack;
  - `frames`, the frames held in the window;
  - `subject_found`, true when any run's is;
  - `count`;
  - `runs` [{from, to, subject_found, frames}] in source ticks — never pixels.

  A run is a maximal span of consecutive pack frames inside the window and inside one coverage
  range whose masks' `found` agree. Its `from` is the first frame's pts and its `to` the last
  frame's pts plus one frame, rounded. When `runs` would pass 512 KiB of JSON, the call is refused
  as `cuts` is, naming the largest `to` that fits. A pack that does not parse is refused naming
  why (`MaskPackError`); packs are written only through a `.partial` and a rename, so that is hand
  damage. The tool count stays 107.
- **CO-15 — What CO1 settles for later phases.** These are recorded here and built later:
  - The owner's CO1 answer (2026-11-01): a cut-out clip's analysis starts **at once**, not after
    the Background render delay (G-38), with CJ-S3 (b)'s pause while playing if CO-12 turns it
    on. It is recorded for CO2b's CO-22.
  - The road map's M10, a reversed clip's mirrored mask, moves to CO2a2 (D16), where CO-3's
    mirror lives. CO1 writes no mirrored file (D4-6).
  - The mean centroid of a window's cached masks moves to CO3, its only prover (I6, reading
    `MaskPack`). CO7 reads CO3's.

CO-20, CO-21 and CO-23 are CO2a1's (the cutout in the model and the recipe), recorded before its
code at format version 39 — provisional until the phase lands, the integrator renumbering a
collision. CO-22 is CO2b's (masks made on demand); the owner's answer for CO2a is CO-15's, and
CO2a1 adds none.

- **CO-20 — `video.cutout`, a clip's Remove Background (CO2a1, format 39).** `Cutout` in
  `model_cutout.rs`, after `video.cursor`, written only when set, every field written in this
  order: `subject` (`person`; CO10 appends `foreground`), `quality` (`standard` | `best`),
  `background` (`remove`, the layer draws its subject alone, | `keep`, the layer draws whole),
  `edge` (0, −1…1, shrinks or grows the outline), `feather` (0, 0…1); `{}` reads as the five
  defaults. `set_video` refuses, through `in_range`, "video.cutout.edge must be between -1 and 1,
  not 2" and likewise `feather` (0–1), then "video.cutout.quality must be standard: Best masks are
  not made yet" (the vocabulary holds `best` so CO4 needs no bump; a file's `best` is read and
  kept). On a text, shape, graphic, adjustment or image clip (images until CO10) it refuses "clip
  {id} is a text clip and cannot take a cutout" (`a shape clip`, `a graphic clip`, `an adjustment
  clip`, `an image clip`), and on a nest "clip {id} shows a nest and cannot take a cutout" —
  checked in `settle_video`, so `paste` and `paste_attributes` meet them too. **In an action:**
  the key's presence, `subject` and `quality` are BASE-only. `set_action_end` refuses
  "video.cutout.subject is not an animation target" and the same for `quality` when the patch's
  `video.cutout` object names either (a `null` included, `subject` first), and an `off` path
  `video.cutout`: "video.cutout cannot be keyed off at an action's end; set_video {cutout: null}
  removes it". The evaluator restores the base over any end (`restore_base_cutout`, beside
  motion's): no base cutout evaluates `null`; a base cutout and an object state take the base's
  `subject` and `quality`; anything else is the base's whole. `edge` and `feather` lerp and
  `background` switches at the end, by §5.4's object rule; an end's cutout keys on a clip without
  one do nothing. The evaluator's clamp (`clamp_cutout`, never failing) bounds `edge` to −1…1 and
  `feather` to 0…1, NaN to 0. A split's halves and a freeze's still read the evaluated state, which
  the restore already holds to the base. `add_blurred_background`'s copy drops `video.cutout` as it
  drops `video.motion`: a backdrop cut down to the person is no backdrop.
- **CO-21 — The recipe's `cutout` key, a layer's 28th, after `cursor` (CO2a1).** `null` unless
  the clip's source is `media` or `still`, its media is in the project and the evaluated `cutout`
  is set; otherwise `{mask: {kind: "media", media, quality}, background, edge, feather}`, `media`
  the clip's own source media (a nested clip's inner media, a still's media) whose pack holds the
  masks (CO-3), `quality` `standard` or `best`. The time comes from the picture segment (CO-3), so
  the key carries no `at` and no `reversed`. Show Ungraded, Show Selection and a matte layer keep
  it; the burn-in's is `null`. The plan, the composition and `CompositionBuilder` take nothing:
  a cutout adds no track, segment or decoder. CO10 adds `{kind: "image", media}`.
- **CO-23 — A project with no cutout plans, saves and draws as before (CO2a1).** The key is never
  written unless set, so every older file writes the text it did at 38 with no migration step,
  plans byte-identically, and every layer gains only `"cutout": null`. Until CO2a2 a cut-out clip
  draws uncut, as CO-6 says a clip without its masks does.
