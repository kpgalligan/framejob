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
