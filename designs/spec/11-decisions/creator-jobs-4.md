# Spec §11 — decisions: Creator jobs, deleting words onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md) and [`creator-jobs-3.md`](creator-jobs-3.md) (CJ-, VR-,
TX-, SW-, CU- and CO-), so a citation never has to say which file; `creator-jobs.md` says what the
road map builds and how its IDs are made (CJ-7). This file is new because `creator-jobs-3.md`
passed the road map's ~500-line split rule with TX3a's entries (2026-11-02), which moved here;
each phase's decisions were appended here, before its code, until it passed the same rule with
CO3's entries, and the series continues in `creator-jobs-5.md`.

TX-30…TX-33 are TX3a's (delete words; road map TX3 split by size, the pause token is TX3b's
TX-34), recorded before its code but for `TranscriptCut.swift`, written first because TX-S3
measures it (TX2a's precedent). The owner's answers of 2026-11-01 for TX3: ⌫ ripples in the
transcript and lifts on the timeline — **yes**; a word selection sets the timeline's in/out range
— **yes**. Nothing here sends anything: no `ModelKeys` row (CJ-3).

- **TX-30 — A word's cut runs from its onset to the next kept word's onset; TX-S3 chose E0.**
  - **Reading (`TranscriptCut.swift`).** Everything is in the SOURCE ticks of the word's media,
    per instance (a shown word matched to its instance by clip id and nest path, the one whose
    segment holds its start first, and to its source word by source tick in order), the
    instance's words in source order. `lead` is `CaptionPages.lead(for:)` (0 under E0); a word's
    mid is `(source + max(source, sourceEnd)) / 2 + lead`. **E0** the onset is the transcript's
    start; **E1** the start plus the lead; **E2** the END of the latest run of at least two
    non-speech voice cells (`p < defaultVoiceConfidence`, cell k `[k·chunkTicks,
    (k+1)·chunkTicks)`, a run ending where a speech cell or the cache's end follows it) whose end
    lies in (the previous word's mid, this word's mid] — `windowStart` (`job.sourceIn`) for the
    instance's first word, the run free to begin before it, so a word that starts a clip after
    an earlier cut finds the same run — less G; with no run or no cache, E1. Every onset is then
    clamped to at least the previous word's corrected end (`max(source, sourceEnd) + lead`) and to
    at least `windowStart`. Onset, corrected start and corrected end are projected by
    `MediaTranscript.project(_:in: job)` plus a nested segment's `origin − clip.start`, as
    `TimelineTranscript.words` places a word.
  - **A run's cut** (`Table.cut`, shown tokens i…j): `[min onset, end)`, `end` the least of the
    next shown word's onset, the run's latest corrected end plus 1 s (`cap`), and the first start
    of a shown-track instance whose media has no words yet (`unread`) at or after the run's
    latest corrected start; with no next shown word, the latest corrected end plus G; never
    before the start. Unsnapped; TX-32 widens it, then it is snapped.
  - **Snapping.** Each bound goes to its nearest frame, the core's own snap (`ReelTime.snapToFrame`),
    so what is sent is on the grid and `ripple_delete_ranges` keeps it — but never past a word
    start it must keep on its side: the start never after the earliest cut word's start, the end
    never after the next shown word's start; past one, the bound is that start's frame floor
    (`TimelineTranscript.frameFloor`). TX-10 places a word in the clip that holds its start, so a
    start rounded past the cut word's start left it in the transcript as a sliver, and an end
    rounded past the next word's start dropped that word from the transcript and the next cut
    took its sound: measured by C2 on TX1's `say` fixture, where three words deleted one at a
    time left a one-frame clip that one Delete of the three did not. With this, one at a time
    and together give the same placements (C2).
  - **TX-S3's verdict: E0** (`TranscriptCut.shipped`). Run 2026-11-02 on the Debug app, Apple M2
    Max, OS build 25F80, on AC; `rule_sha256` `bede33d2…c5a0` matched CJ0a's table. Fixture (1):
    21 `say` phrases joined by 60, 120, 250, 500 and 1,000 ms of zero samples, four of each (20
    boundaries, 207 words, every boundary's word found by its spelling). Clipped onsets on (1):
    E0 0, E1 3, E2 at G 0 / 32 / 64 / 96 ms 10 / 3 / 3 / 3; the three are the first round's
    60, 120 and 250 ms boundaries, where the clamp to the previous word's corrected end put the
    onset 46–100 ms past the true onset whatever G. E0's error on (1) runs from −109.6 to
    −1,185.6 ms (always early). Fixture (2), o2 (58 edges): in voice-cache non-speech E0 3.4 %,
    E1 6.9 %, E2 3.4–8.6 %; E2 placed only 4 edges from a run, 0 % (G 0) and 75 % (G 32–96)
    of them in non-speech, so no guard met the 95 % half of the rule. (The rule's "keeps at least
    95 % of real-speech edges in non-speech" is read over the edges a run placed — those whose
    E2 onset moved off E1's — the edges a guard can keep or push out; the share over every edge
    is recorded beside it.) (3) S-TH1 and S-RT1 do not exist yet: skipped by name, owed, and
    TX-S3 re-runs when they land. So the rule's last arm: E0, with JOB-11 the only judge.
    **Measured and not in the rule:** E0 put 13 of the 20 edges on (1) inside the previous
    phrase's audio, 24–316 ms before its last sample over −40 dBFS (E1 2, E2 1): deleting a word
    can take the tail of the word before it. Recorded for JOB-11 and owed as an issue.
    **Amended 2026-11-02, by TX-15, TX-16 and TX-19:** E0's onset is the MOVED start; re-run on Release:
    on (1) 0 clipped, error −9.9 to 0.0 ms, 0 of 20 edges inside the previous phrase; on o2 (58
    edges) 5.2 % in non-speech, 13.8 % under −40 dBFS. E1's and E2's figures are not recorded.
  - A word's own `cut_start`/`cut_end` are its run of one AFTER TX-32's widening, snapped
    (`TranscriptCut.wordCut`), so they are what the tab cuts for that word alone, crosstalk
    included, and TX-33's sentence holds. Cutting words one at a time and together make the same
    timeline, except across a pause over 1 s.
  - **The pause clause** (a pause token cuts `[end of the speech before + 0.2 s, next onset −
    0.2 s)`) is recorded here and built in TX3b as TX-34.
    **Amended 2026-11-02, by TX-15:** "next onset" is the next word's moved start, at its sound, so
    the clause no longer meets a word that starts early inside the pause; TX3b keeps its no-sliver
    clamp (TX-19).
  - Risk accepted: in continuous speech a fragment of a deleted word can remain, and under E0 a
    cut can start inside the word before it (above).
- **TX-31 — A word selection is the in/out range, and ⌫ in the transcript ripples.** Every
  selection a person makes — a click (one word), a drag, ⇧-click, ⇧-arrows, the arrows, ⌘A — is
  planned (TX-32) and its snapped range set as the document's in/out range through `set_range`'s
  door (`inOutRange`, `viewStateDidChange`, `applyLoopRange`), so the timeline shades what will go
  and Loop plays it; the view adopts the widened selection without telling anyone. Esc, or any
  clear, clears the range only while it is still the one the selection set (`rangeSet`). When a
  rebuild re-maps the selection by identity and the document's range is still `rangeSet`, the
  pane plans again and sets the new range (clears it when the selection did not survive); a range
  set elsewhere is left alone. ⌫, ⌦, Edit ▸ Delete and Edit ▸ Ripple Delete, with the view first
  responder and words selected, plan again and send ONE `ripple_delete_ranges`, step "Delete
  Words" (Edit ▸ Delete's bare ⌫ resolves ahead of the first responder, so the editor's delete
  family forwards first and its validator arms answer true; ⌦ reaches the view's `keyDown`).
  Applied, the range clears and the playhead lands at the snapped start. (⌫ lifts on the
  timeline; deleting text closes the gap.)
- **TX-32 — The tab refuses a cut before sending it.**
  - **Widening.** Any shown word outside the selection whose `[onset, max(end, onset + 1))` meets
    the selection's UNSNAPPED cut is added, with the tokens between, unless it plays on a locked
    track; repeated to a fixpoint. The onset, not the corrected start, and the unsnapped cut, so
    the next word of the same instance — whose onset is where the cut ends — is never taken.
  - **Refusals, in order.** (1) a selected word that cannot be cut, in TX-11's own sentence (its
    `why`); (2) a read word on a locked track — every track, Words from ignored — whose corrected
    extent `[start, max(end, start + 1))` meets the snapped range: "Track <name> is locked and
    has words in this cut: unlock it to cut here." (the name as TX-11 spells it, the id when
    empty); (3) the clip ceiling on the PEAK count `check_caps` sees after `clear_range`'s second
    split (`core/src/edit_time.rs`, `clear_range`): `ShotSplit.clipCount(project.snapshot)` plus 1
    per unlocked-track clip of the container with start < s < end, plus 1 per one with start < e <
    end; past `RC_MAX_CLIPS`: "This cut would make <N> clips; a project holds at most
    <RC_MAX_CLIPS>. Lock a track that needs no cut, such as a music bed, or cut less.", N that
    peak. Nothing is sent; the refusal beeps and shows at the inspector's foot (CI-10's strip, op
    `ripple_delete_ranges`). The core's own check stays the backstop (`CaptionLayout.swift`'s and
    `ShotSplit`'s precedent).
  - **The count after** (answered, not refused on): `clipCount` plus 1 per unlocked-track clip of
    the container with start < s and end > e, less 1 per one with start ≥ s and end ≤ e. A
    talking head (picture and linked sound) cut mid-clip is N + 2 after and N + 4 at the peak.
  - This bet never raises `MAX_CLIPS` (CJ-9).
- **TX-33 — An agent cuts words with `ripple_delete_ranges`**, one range from the first word's
  `cut_start` to the last's `cut_end`, which `get_timeline_transcript` now answers on every word
  (TX-30's `wordCut` over a table of every read word of `tracks`, before the window and paging,
  against the container as the call read it, each needed media's voice cache read on the server
  thread); no new edit tool; the step is "Ripple Delete" (TR-12). Amends TR-11's prompt bullet;
  the paragraph, verbatim: "Cutting words: `get_timeline_transcript` answers the timeline's words
  in order, each with the `cut_start` and `cut_end` the Transcript tab cuts it by; cut a run of
  words with one `ripple_delete_ranges` range from its first word's `cut_start` to its last
  word's `cut_end`. `detect_fillers` answers the filler words as ranges. A false start that
  repeats no words is a judgement of meaning, so cut one only when the person asks: say which
  words you will cut, then cut them in one `ripple_delete_ranges` call." TX5, TX6 and TX7 extend
  it, each with its own Amended line.

CJ-51 and CJ-52 are CJ5b's (File ▸ New Project from Range…, the derived document VR3 and FC8a
build on), recorded before its code; CJ5a's CJ-50 is in `creator-jobs.md`. The owner's answer of
2026-11-01 for CJ5b: the new document opens with the range as its first state, with no undo back
to the whole source — **yes**. Nothing here sends anything: no `ModelKeys` row (CJ-3). No core,
FFI or format change.

- **CJ-51 — The derived document.** `ProjectDocument+Derived.swift`'s
  `derived(from:handle:range:path:display:name:)` answers a new document built from a handle,
  and what it carried (`DerivedCarry.Report`: files, bytes, seconds). Main thread.
  - **(a) The handle.** With a range, `ReelOp.keepRange(from:to:)` is applied PURELY to
    `handle` (`ReelProject.applying`, never `applyEdit`: the source document never changes):
    `.applied` gives the new project, `.identity` keeps the handle, `.refused` is thrown with
    the core's own sentence, and an `Err` is thrown. With no range the handle is used unchanged
    (VR3's copy).
  - **(b) What is carried**, for each kept media id `m` (a media the derived snapshot still
    lists): `thumbs/m/`; `peaks/m.bin` and `peaks/m.complete.json`; `loudness/m.bin` and its
    marker; `speech/m.bin` and its marker; `sync/m.bin`, `sync/m.pcm` and their marker; every
    `device-transcripts/m-*.json`; for every folder `k` under `analysis/`, `analysis/k/m.json`
    and `analysis/k/m/` (masks and mirrored chunks included, CO-4); `transcripts/m.json` and
    `transcripts/m.complete.json` only when `MediaTranscript.read(for:in:)` records
    `remote_deleted: true` — one still owed a DELETE stays in the source, so R6-11 and R6-3 hold
    (N4); and `ReverseCache.existing(media:source:in:)` for each media a kept clip, top level or
    nest, plays reversed and is not an image — the digest is over the same media file, so it
    stays valid, and nothing renders a reverse for a windowless document (N5). Thumbnails join
    the draft's list because "no pass starts on open" needs them. Never carried: media files (a
    derived project points at the source's media; a consolidated source's shorts point into its
    package), `ramp-audio/`, `isolated/` and `voiced/` (the export waits for and makes them),
    and `graphics/history/`. It carries the graphics its clips draw (every graphic clip's
    module, top level and every nest, `reconcileGraphicNames`' set) plus every file of `fonts/`
    and `assets/`, through the started `GraphicStore` (G-14): each module by
    `write(name:bytes:)`, each font and asset by `importFile(from:into:as:)`, then one
    `rescan()`. (SW-44 later adds every per-source cache key.)
  - **(c) The order (N6).** 1. `P/project.json` is written (`handle.json`, atomic), P being
    `path` or a staging folder `NSTemporaryDirectory()/FrameJob/<UUID>-derived/`. 2. The
    document opens: with `path`, `NSDocumentController.shared.makeDocument(withContentsOf: P,
    ofType: projectTypeIdentifier)` then `addDocument`, so `cache/` lands once, in the package;
    untitled, `openUntitledDocumentAndDisplay(false)`, `read(from: P, ofType:
    projectTypeIdentifier)`, the staging folder removed, `displayName` the name, then
    `fileModificationDate = nil` and `countEditChange(.changeDone)`, so it opens dirty with no
    undo step (`untitled(around:)`'s shape). 3. With S the source's `intendedCacheDirectory`,
    `CacheLedger.shared.saveBegan(cacheDir: S)`; the carried paths listed in S and copied into
    the new document's `cacheDirectory`; `saveEnded(cacheDir: S, save:)` in a `defer`, so a
    throw ends it too. This is `ProjectDocument+CacheSaves.swift`'s bracket: the listing and
    the copy never straddle a publication into the source's cache. No ledger call is made on the
    derived directory, which nothing publishes into before step 4. 4. `makeWindowControllers()`,
    so `startCaches()` finds every carried marker current (markers carry no path) and starts no
    pass, and the graphic store starts. 5. The graphics carried through `document.graphicStore`
    from the source's `graphicStore?.folderURL`, else `<source fileURL>/graphics`. 6.
    `showWindows()` when `display`. 7. With `path`, `noteNewRecentDocumentURL`. `display: false`
    makes the window controllers (so caches and the graphic store start) and shows no window
    (N7). A source pass still running when the call is made leaves its kind for the derived
    document's own pass.
  - **(d) Failure.** A throw after the document exists closes it; with `path`, P — which this
    call created — is removed. The staging folder is removed on every exit.
  - **(e) Copies** are APFS clones where the volume allows (`copyfile` with `COPYFILE_CLONE`),
    else copies (N6). The copy runs on the main thread; its seconds are in the report.
- **CJ-52 — File ▸ New Project from Range… and `new_project_from_range {from, to, path?}`.**
  - **(a) The menu item**, in the File menu directly below Pause Recording, no key equivalent,
    is on only with an In–Out range set (`inOutRange`), no nest open (`scope == nil`) and no
    sheet on the window. The new document opens untitled and dirty with the range as its first
    state and no undo step, named "<source name> (range)" (`displayStem` plus " (range)") until
    saved; the source document never changes. A refusal or an error beeps and posts
    `.projectDocumentDidRefuse` with `ReelRefusal(op: "keep_range", reason:)`, its sentence at
    the inspector's foot (`refuseShotSplit`'s shape, CI-10).
  - **(b) The tool** mirrors it, off main (`creatorOffMainTools`), its body one main hop:
    `target(a)`; refused while a nest is open ("new_project_from_range works on the top-level
    timeline: set_scope with no nest first."); `from` and `to` read and snapped by `timeArg`;
    with `path` (`.framejob` added by `destinationURL`), `refuseHeldPath(url, except: nil,
    tool: "new_project_from_range")` (#40), then refused when anything exists at the path
    ("<path> already exists, so new_project_from_range did not write there: pass a new path."
    — the door never replaces a file; FC-82 picks free names); then the door with `display:
    true` and the same name. It answers `{project, saved (only with path), carried: {files,
    bytes, seconds}}`. A dev-only launch default, `-RCDevDerivedHidden YES` (dev tools only),
    makes the tool pass `display: false`, so a proof can see a windowless derived document.
  - **(c) Ask-first for the assistant only when it names `path`** (AI-7 amended): a package
    written where the model chose. The row carries `askOnlyWith: "path"`; a call without one
    runs unasked, and the system prompt names the row "`new_project_from_range` with `path`".

CO-24…CO-29 are CO2a2's (Remove Background drawn from the cached masks), recorded before its code.
The owner's answer for CO2a is CO-15's; CO2a2 adds none and asks none. No format bump, no `rc_*`
and no core change: the recipe's `cutout` key (CO-21) is what the compositor reads.

- **CO-24 — The per-request lookup.** For each composition request, `t` is
  `CompositionBuilder.ticks(request.compositionTime)`. Only a layer whose source is a `.track`, not
  drawn as a slate, with `cutout.background == remove` and `cutout.mask.kind == media` looks
  anything up; every other layer binds the placeholder. The plan is `CutoutMasks.plan(for:
  instruction.recipeKey, project: RecipeSource.shared.project(for:))`: the handle's plan's video
  tracks and its snapshot, decoded once per handle (`CutoutPlan`). The segment is the one of the
  layer's composition track that covers `t` (`duration > 0`, `start ≤ t < start + duration`), and
  its `media` must be the mask's; else a miss. The source tick is `s = sourceIn + (t − start) ·
  sourceDuration / duration`, rounded to the nearest tick, halves away from 0
  (`CutoutLookup.sourceTick`), in the stream the segment reads. **Forward:** the frame shown is
  `f = pack.shown(at: s)`, the last pack frame at or before `s`. **Reversed** (the clip, top level
  or inside a nest, plays its media reversed; T its media's model duration): `f = pack.shown(at:
  T − s − 1)` — `ReverseMirror.mirrored(s, about: T) − 1`, because the reversed stream shows
  forward frame f over `[T − end(f), T − pts(f))`. `f` is used only when its grid index and
  `grid.index(of:)` of the queried forward tick lie in the same coverage range; else a miss (a
  frame outside what was analysed is never borrowed from a neighbour across a gap). The mask's
  slot: forward, `f`'s own slot (CO-10's nearest analysed mask, ties to the earlier); reversed, the
  mask `a` minimising `|end(a) − end(f)|`, ties to the larger `end(a)` — the earlier in the
  reversed stream, CO-3's tie rule there — where `end(x)` is the pts of the pack frame after `x`,
  else `x.pts + round(grid.frameTicks)`. Every miss draws the layer uncut (CO-6).
- **CO-25 — When a pack answers.** The cache folder is `ReverseSource.shared.resolution(for:
  key).cache` and the media's URL `RecipeSource.shared.lookURLs(for:)`'s. The marker must
  `answers(for:)` the stamp made exactly as `ProjectDocument.analysisRequest` makes it
  (`AnalysisStamp.make` over `ProjectDocument.analysisInput`), canned markers included where they
  are honoured (CJ-26); its first payload file must read as a `MaskPack`. Per request a cut-out
  layer costs one `stat` of the marker: the marker, the stamp and the pack are read again only
  when the marker's (inode, size, modification time) or the media or its URL changes, and the
  stamp's asset read only when the media or URL does. Until then the old mapping is kept: a
  publish renames a new pack into place, so the mapped old one stays whole.
- **CO-26 — CO-5 as built.** A clip draws its masks only when a subject was found somewhere in
  its window: the forward source-tick hull of every plan video segment of that clip and media,
  mirrored about T for a reversed clip (`CutoutPlan.window`), read by `AnalysisMasks.runs` and
  checked for a run with `subject_found` (`CutoutLookup.subjectFound`) — once per (pack, clip,
  window), cached. None found: the clip draws uncut, every frame of it, a person walking out of
  an analysed window still leaving an empty picture where one was found.
- **CO-27 — How the mask is drawn.** The mask is uploaded as stored: `r8Unorm`, the pack footer's
  width × height, `replace(region:)` — never through AVFoundation, step 0, `InputStage` or
  `LayerLift`, so an HLG project's coverage is the SDR project's (CO-7). It is bound at
  `texture(4)` on every draw through the two layer fragments — a layer, its reflection, its
  shadow's mask pass, a matte member and a routed dissolve's half, all of which draw through
  `drawLayer` — the 1×1 white placeholder when none; an adjustment clip's pass never binds it.
  `cutoutCover` samples `.r` with the layer's sampler at the display-space `uv` captured after
  steps 1–2 (the spotlight's lens, the pixelate snap) and before `orientedUV`, and remaps it by
  r0: `c = 0.5 − 0.5·edge`, `w = 0.5 + 0.5·feather`, `lo = clamp(c − w/2, 0, 1)`, `hi = clamp(c +
  w/2, 0, 1)`, `cover = smoothstep(lo, hi, m)`. Step 7b multiplies `alpha` by it beside the corner
  radius, only when `cutoutEnabled > 0.5` — a uniform outside the effects sum, as `linearLight` —
  so a layer without a drawn mask is the same arithmetic as before. `LayerUniforms` gains the
  cutout group (`cutoutEnabled`, `cutoutEdge`, `cutoutFeather`, a spare): 156 → 160 floats, 624 →
  640 bytes, 40 × 16; the integrator renumbers at a collision (CJ-8 (b)). **A same-track dissolve
  whose incoming half has `cutout.background == remove` gets no `partnerBox`**, decided from the
  recipe whether or not its masks are found: the cutout is per-pixel coverage the box cannot see,
  as a corner radius or a clip rectangle is, so the outgoing half takes the uncorrected `alpha *=
  1 − p` and fades out across the overlap, rather than staying opaque through it and vanishing at
  its last frame.
- **CO-28 — What does not change.** The plan, the composition, its instructions,
  `CompositionBuilder` and `ReverseCache`; no request waits for masks (CO2b's CO-6 waits); no new
  tool. `render_frame` and every export draw through the same compositor, so each draws the cached
  masks the preview draws.
- **CO-29 — The proof.** `co2a_proof.py` keeps CO2a1's rows and adds: D1p, the lookup's slot for
  ten cases' plans (a trim, ×0.5, ×2, ×1.37, a ramp, a freeze, a reverse, a split, a nest and a
  cross-dissolve) at every frame and at a 15/s canned pack against `deciders.expected_mask`; D1,
  the same ten cases drawn from canned bar-code packs and exported as `prores_4444`, each frame's
  picture code and alpha code scored the same way, and the cross-dissolve's outgoing alpha
  `round(255·(1 − p))` within 1/255 where the incoming's mask is 0; D2, a real person pack's frames
  equal to the clip hidden where the mask neighbourhood is all 0 and to the uncut frame where all
  255; D3, a pack whose coverage misses the frame and a marker of another stamp drawing as
  cutout off; D4, a real pack with no person drawing uncut; D6, a blur-0 shadow's alpha the
  layer's shifted; D7, HLG coverage equal to SDR within 1/255; D11, a freeze drawing its held
  frame's mask; D12, a 90°-tagged clip's mask upright; D16, a reversed clip's frame k the forward
  mask at `T − end`; D15, a cutout-less project's frames and export byte-identical to the base
  app's. Nine mutants (the `partnerBox` clause, `orientedUV`, one frame late, the nearest frame,
  a miss drawing transparent, the shadow's placeholder, CO-5 per range, step 0, the pivot), each
  once on Release. **JOB-61**: a cut-out 1080p camera over a 4K screen recording plays without
  stutter at Full and Half Preview Quality.

CU-90 is CU9a's (Clip ▸ Retime Range… and `retime_range`), recorded before its code. The road map
names no owner question for CU9a. Nothing here sends anything: no `ModelKeys` row (CJ-3). No FFI,
header, format or persisted-field change. AU-94 is kept: a linked clip's rate is refused, in its
own sentence.

- **CU-90 — `retime_range {from, to, rate, keep_pitch?}`: one range played faster or slower on
  every unlocked track, everything after it moved up or back, one undo step "Retime Range".**
  - **(a) Semantics** (`core/src/edit_retime.rs`). `from` and `to` are snapped and clamped to 0;
    `f(t) = snapped(from + round((t − from) ÷ rate))` and `to′ = f(to)`. Both bounds are cut by
    `split_under_playhead` (`from`, then `to`), an identity there keeping the project as it is,
    so a straddler splits exactly as `split` splits it. The PIECES are the clips on unlocked
    tracks with start ≥ `from` and end ≤ `to`, found before the shift. Everything at or after
    `to` moves by `to′ − to` through `shift_clips`, which carries each moved clip's linked
    partner (AU-91); its refusal is the answer. Each piece starts at `f(s)` and lasts
    `d′ = f(e) − f(s)`, so touching pieces still touch: a constant media piece plays at speed ×
    `rate`, its duration then held to its media (`duration_resnapped`) and its actions rescaled
    to keep their fraction (`rescale_actions`); a ramped piece is `scaled_profile` of it at
    `f(s)` by `rate` into `d′` (SR-19); `keep_pitch`, when given, is set on every media piece's
    `audio`, as `set_speed` sets it; a text, shape, still, image, graphic (its `length` kept,
    G-9) or adjustment piece scales its start and duration and rescales its actions. Markers in
    `[from, to)` go to `f(m)`, markers at or after `to` move by `to′ − to`. The exit is
    `finish_placement` over the unlocked tracks. A `rate` of exactly 1 is an identity. Inside a
    nest (the envelope's `scope`) the nest's tracks are retimed and no marker moves or is
    checked: the view has none and the merge writes none back.
  - **(b) Errors, then refusals, in this order; nothing changes when one fires.** Errors: "rate
    must be a positive number, not {rate}"; `to` not after `from` once snapped, "retime_range's
    to must be after its from (from {f}, to {t} ticks, on the frame grid)". Refusals: (1) "a
    range can be retimed by ×0.1 to ×1000, not ×{rate}"; (2) "the range from {f} to {t} ticks is
    shorter than two frames"; (3) the first locked track holding a clip that ends after `from`,
    `locked_track(id, "its clips after the range's start would fall out of step with the
    retimed range")`; (4) each unlocked clip overlapping `[from, to)`, in clip order: a nest
    clip, "clip {c} is a nest, which has no speed; move the range off it, or retime inside the
    nest"; a text clip with `words`, "clip {c} is a caption page with timed words, which a
    retime cannot move; move the range off it" (SR-27's re-time is app-side, and
    `CaptionRetime.mayRetime` does not learn `retime_range`); a linked clip, AU-94's sentence
    (`linked_rate_sentence`, factored out of `linked_rate_refusal`); (5) an overlap on an
    unlocked track that meets the closed range `[from, to]`, "clip {later} has a transition from
    clip {earlier} from {os} to {oe} ticks, which touches the range; move the range off it or
    remove the transition"; (6) unscoped only, the first marker in list order whose new time
    equals an earlier marker's, "markers {a} and {b} would both be at {t} ticks after a retime
    by ×{rate}, and two markers may not share a time; move one of them first" — refused as
    `add_marker` and `set_marker` refuse a shared time, never dropped as `set_canvas` drops one,
    because a silent drop is not fixable (`ripple_delete`'s doc); (7) after the cuts, each piece
    named by its source clip (a piece not in the project before is the clip that straddled
    `from` on its track): "clip {c} would play at ×{r}, past ×{limit}, the {fastest|slowest} a
    clip can play" (`r` speed × `rate` on a constant piece, the peak or trough × `rate` when
    `rate` lies outside a ramp's `profile_factors`), and `d′` under a frame, "clip {c} would last
    under one frame at ×{rate}".
  - **(c) The door's question.** `SpeedAudioDrop.mayCross` learns `retime_range`. Its crossing is
    read on a BASELINE: the project with `split` at `from` and then at `to` applied for each
    `retime_range` op (the project itself when none applies), diffed against the baseline with
    the ops applied, so a split half taken past ×12 is counted under the id the core mints. No
    rate is computed in Swift (D2-1); every other caller's baseline is the project.
  - **(d) Clip ▸ Retime Range…** (after Close Gap, no key): a sheet with Rate (×2 to start, the
    Speed sheet's field, presets and footnote) and Preserve pitch (on, or the first media clip
    overlapping the range on an unlocked track's Keep pitch), and the hint "Every unlocked track
    between In and Out plays faster or slower, and everything after Out moves to stay in step.
    One undo step." Apply at ×1 closes the sheet; otherwise it commits through
    `SpeedAudioDrop.commit("Retime Range", …)`, always sending `keep_pitch`. It needs an In–Out
    range and no attached sheet, and is allowed inside a nest. `-RCDevRetimeAccept YES` (dev
    only) presses Apply when the sheet appears, AU-128's precedent.
  - **(e) The tool.** The op tool `retime_range` describes its four arguments and carries
    SpeedAudioDrop's agent note; its answer adds `audio_left_out` and `audio_note` from the
    baseline's crossing, read before the edit, beside `new_clips`.

CO-22 is CO2b's (masks made on demand, and files that wait), recorded before its code; the number
was reserved by CO0 for this phase. The owner's answers it builds on: analysis at once (CO-15, the
CO1 answer of 2026-11-01), and for CO2b a pending cutout drawn uncut in the preview — **yes**, with
the status saying so, which is CO3's Background section. No format bump, no core change, no `rc_*`.

- **CO-22 — Masks are made when a clip asks; a file waits for them.**
  - **(a) What is wanted.** Every plan video segment (duration > 0) of a clip — top level or inside
    a nest — whose BASE `video.cutout` is set (any `background`), from the document's `project`
    and, with a nest open, its `editedProject`; a media with no file (a slate) is not wanted. A
    window is in FORWARD source ticks: forward `[sourceTick(a), sourceTick(b))`, reversed (its
    pivot T from `ReverseMirror.pivot`) `[T − sourceTick(b), T − sourceTick(a))`, where `[a, b)` is
    the segment clipped to the range asked (none: the whole segment) and `sourceTick` is
    `CutoutLookup.sourceTick`. **The need rule** — what CO-24's lookup can ask of a window — is
    `⌊lower·rate + 1e-9⌋ … grid.index(of: max(lower, upper − 1))`, clamped to the grid: at most one
    frame past a frame-aligned window, so a ×0.5 clip's last frame is not a miss. One request per
    media, holding its merged missing ranges (`AnalysisStore.lookup` per need range).
  - **(b) When.** `ensureMasks()` is the last line of `ensureRampAudio()`, so it runs after every
    edit, at the open, when a reverse lands and when a ramp settles — never inside a live gesture —
    and at once (CO-15). Main reads the handles, `mediaURLs()` and `cacheDirectory` (only when a
    cut-out clip exists; with none it releases a want it made before); `CutoutWants.queue`, one
    serial `.utility` queue for every document, builds the requests and wants them. One lane owner
    per document (`AnalysisLane.newOwner()`), alive while `RecipeSource.shared.project(for:
    recipeKey)` is not nil; a settle calls `masksDidSettle()` on main:
    `packageContentsDidChangeOnDisk()`, then `ensureMasks()`.
  - **(c) The keep rule, for every role (document, export, frame).** The candidates are
    `AnalysisLane.openRequests(kind: .masks, cacheDir:)` — every owner's queued and running masks
    requests for that cache folder — so an export or a frame shares the document's job rather than
    queueing a second one behind it (`pictureWidth` 1). Of these, a **running** request (started,
    not ended) whose ranges meet its media's need is kept; a **queued** one only when every range
    of it lies inside its media's need, so a queued job never analyses frames nobody wants; an
    ended one never. Only a media with a miss is wanted at all. The caller wants the kept requests
    plus, per media, a new request holding only the needed, uncovered indices outside the kept
    requests' ranges. An edit never restarts a running job that has published.
  - **(d) A publish redraws.** `AnalysisStore.publishFile` posts `.analysisDidPublish` on main after
    each successful publish (`kind`, `media`, the standardized `cacheDir`); the editor of the
    document whose `intendedCacheDirectory` matches, for `masks`, calls
    `playback.refreshPausedFrame()` (CU3a2's path). No rebuild: the plan did not change and the
    compositor re-reads the pack on the marker's stat (CO-25). This replaces the road map's
    `.reversedMediaDidChange` line.
  - **(e) An export waits** in `Exporter.withRampAudio`, before its image-sequence guard, so a GIF
    or an APNG waits too, for `windows(plan:, range: start ..< start + duration)` of its settings,
    under a lane owner of its own (alive always, made at its first want, kept per export recipe key
    and released by `Exporter.releaseMasks(key:)` inside `releaseRecipeKey`'s `ramp` deferral).
    No cache folder, an unreadable media or a failed job fails it `cutoutFailed` — "Clip N's person
    masks could not be made: <why>." — naming the first window's clip of that media, the reason
    "the project has no cache folder to keep the analysis in", the request error's sentence, or
    the job's own. It wants and `AnalysisLane.wait`s on (c)'s kept requests plus the remainder,
    with no deadline but the export's `cancelled`; after `.landed` the store is read again, and a
    media still missing after a second landing fails it ("its masks do not cover the frames it
    plays").
  - **(f) A frame waits** only when asked (`cutoutWait > 0`): `render_frame` and File ▸ Save
    Frame… pass 30 s (`Exporter.frameCutoutWait`); the eyedropper, the look gallery, the qualifier
    pick, `snapshot_ui`, thumbnails and an image sequence's frames pass none (CO-6). Its windows are
    the recipe layers at t with `cutout.background == remove`, `mask.kind == media` and a `.track`
    source, through `CutoutPlan.covering`, over `[t, t + 1)`. It wants (c)'s requests under a
    fresh owner, polls the store every `AnalysisLane.pollInterval` until every need is covered, one
    of its requests failed, or the limit, then releases the owner. Drawn uncut, and named: those
    layers' clips still uncovered (an unreadable media at once; with no cache folder, every one).
    `render_frame` says "Clip N is drawn uncut: its person masks were not ready within 30 s." once
    per clip, ascending, before its last sentence; Save Frame, after a successful save, shows an
    informational sheet "Saved without Remove Background" — "<file names> drawn whole: the person
    masks were not ready within 30 seconds." A clip covered with no person found (CO-5) is not
    named.
  - **(g) The preview** draws a pending, cancelled or failed cutout uncut (CO-6, the owner's CO2b
    answer); the status saying so is CO3's Background section.
  - **(h) The dev log.** In a dev build every want of the three roles is logged once per (role,
    owner, request), the last 512 kept; `analysis_job` answers them as `mask_wants: [{role, owner,
    media, ranges, wanted, outcome?, error?, queued_at?, started_at?, ended_at?}]`, `wanted` true
    while that owner wants it now, always present.
  - **(i) The proof** is `co2b_proof.py`: P1 (the need rule), P2 (the keep rule), W1–W9 with W3b
    and W4b, Z1, and eight mutants; JOB-62 is the person's check that a paused picture redraws
    cut without play.

CJ-30…CJ-35 are CJ3's (face samples: the `faces` analysis kind), recorded before its code with
spike CJ-S2's verdicts; CJ-35 was recorded after CJ-S3 (b)'s run with a `faces` job, which needs
the built app, and CJ-34's measure after the probe's. The road map expected
no owner question for CJ3, and the owner's answers of 2026-11-01 hold none. Nothing here sends
anything: Vision runs on the Mac, so there is no `ModelKeys` row (CJ-3). No core, FFI or format
change (CJ-20); no tool is added.

- **CJ-30 — `faces`, the first machine-learning kind, at CJ-S2's rate, size and reader.** Per
  sample of source time, every face Vision finds: its box, confidence, roll and yaw
  (`VNDetectFaceRectanglesRequest` revision 3) and, from `VNDetectFaceLandmarksRequest` revision 3
  with `constellation = .constellation76Points` over those observations, the mouth's inner-lip gap
  and outer-lip width, each over the face box's height in picture pixels (CJ-33). Each request is
  FRESH, on a fresh `VNImageRequestHandler`, per analysed frame; no request is stateful.
  - **CJ-S2's run** (`faces_spike.py`, `rule_sha256` `c41417fb…95bb2b11`, matching; macOS 26.5.1
    (25F80), Apple M2 Max, on AC power, three lanes on the machine). The inputs were the face
    fixtures (`face_fixtures.py`); S-TH1…S-TH4 do not exist. `VERDICT rate=10 size=720
    landmarks=yes rectangles=neural_engine(branch 1) landmarks_device=neural_engine(branch 1)
    reader=converted compare=cross_run dropped=none realtime_1080=10.30 realtime_4k=8.88`.
  - **Rule 3, the size.** On `faces_small.mov` (the face box an eighth of the frame's height),
    recall was 1.0000 over 600 samples at 720, 1280, 1920 and native (1920), so the read's long
    side is **720**, or the media's own when smaller.
  - **Rule 2, the rate.** At 720 on rule 1's devices, decode + rectangles + landmarks ran at
    10.29, 10.30 and 10.31× real time on 1080p30 (`faces_moving.mov`) and 8.87, 8.88 and 8.95×
    on 4K30 (`faces_moving_4k.mov`), past 3× and 1.5×: **10 samples a second**.
  - **Rule 4, landmarks.** At that rate on 1080p30 the landmarks' median Vision seconds were
    1.51 against the rectangles' 4.02 (0.38×, under 2×): the mouth measures **stay in `faces`**,
    and SW8 builds no `mouths` kind.
  - **Rule 5, the reader.** No log or HLG sample exists, so face kinds read through the
    **converted** reader for a converting media — `AnalysisFrames.read`'s standard arms, direct
    or through `oneClip` and step 0 (CJ-23), not CO-7's third arm. The log and HLG rows are owed
    with S-TH2…S-TH4.
  - **Rule 6** (S-TH1's face share) and every S-TH row skip by name and are owed in CJ3's record.
    Run at CJ7b (2026-11-06) under rule 6's amended window (the owner: count from the first face
    in frame): 0.9967 (598/600), a pass; CJ-30 unchanged.
- **CJ-31 — No identity is stored.** Each sample's faces are stored as Vision found them, in a
  fixed order: by box centre x, then centre y, both in CJ-22's top-left frame, compared as exact
  `Float`s (`AnalysisFaces.ordered`). A consumer that needs a face followed links faces itself over
  the window it reads (VR in the core, VR-21; SW by each sample's largest face, SW-81). No face is
  named or compared across media. Values are raw; smoothing is a planner's.
- **CJ-32 — Each request is pinned to its device, read back per job and recorded in the stamp.**
  CJ-S2's rule 1 picks a device per request, and only among devices that EVERY stage of that
  request reads back after the pin (`AnalysisVision.pin`): a device left `auto` or `unavailable`,
  or read back as another, is dropped and listed. In the run both requests had one stage
  (`VNComputeStageMain`), and every run on each of the three devices read back that device, so
  none was dropped. Each device's three digests were identical, and the Neural Engine was the
  fastest for both: rectangles 5.15…5.21 s over 600 samples at 1280 (the GPU 6.69…6.97, the CPU
  13.90…13.99), landmarks 1.18…1.20 s (the GPU 2.76…5.79, the CPU 3.59…8.85). So **both requests
  run on the Neural Engine** (branch 1). The stamp's `device` is
  `rectangles:<readback>;landmarks:<readback>`, read once; a job re-pins every fresh request and
  refuses to run when one reads back other than the stamp says (`FaceError.device`). Branch 1
  means two runs on the pinned device write the same bytes, which `faces_proof.py`'s F2 checks
  across runs; under branch 3 the proofs would compare against the cache only (E9's rule).
- **CJ-33 — The sample grid and `samples.bin`.**
  - **The grid** is `AnalysisGrid(samplesPerSecond: 10, duration:)` (`AnalysisKind.grid(of:)`):
    the coverage and the payload are indexed by sample k, at `ticks(k) = round(k × 600000 / 10)`.
  - **Sample k** takes the first kept frame whose pts lies in `[ticks(k), ticks(k) + one sample
    interval)`; with none it holds pts −1 and no faces. A frame is tested against the kept frame
    before it, so the choice is the same whatever the job's bounds, and a frame serving two
    samples is analysed once (`AnalysisFaces.samples(at:after:grid:)`).
  - **The read** covers the frame indices from `ticks(k0)` through one sample interval plus one
    frame past `ticks(k1)`, clamped to the media, through `AnalysisFrames.read` with its pre-roll
    (so the frame before the first is known), at CJ-30's size.
  - **The mouth.** The gap is the vertical extent of `innerLips.pointsInImage`, the width the
    horizontal extent of `outerLips.pointsInImage`, each divided by the face box's height in the
    read picture's pixels; image axes, raw. NaN when Vision gives no lips.
  - **The file** (`cache/analysis/faces/<id>/samples.bin`, little-endian): a 16-byte header —
    ASCII `FJFS`, `UInt16` version 1, `UInt16` face record bytes (36, or 28 without landmarks),
    `UInt32` sample count, `UInt32` face count; one 16-byte row per sample index from 0 — `Int64`
    the frame's pts in ticks (−1: none), `UInt32` its first face, `UInt32` its face count; then
    the face records — `Float32` x, y, width, height (0…1, top-left, display orientation),
    confidence, roll, yaw (radians), mouth gap, mouth width (NaN: absent).
  - **The publish.** A job publishes through `AnalysisStore.publishFile` every 30 s, through the
    samples decided (a sample is decided once a frame past its interval, or the frame serving it,
    has been read), and at each range's end. Its write decodes the on-disk file and replaces the
    covered samples; a file that does not decode, or holds another sample count or record size,
    is written fresh and answers false, so the marker keeps the job's coverage alone.
- **CJ-34 — `get_media_analysis {kind: "faces"}`'s answer.** Beside the common fields (CJ-25):
  `rate` (10), `count` and `samples`, one row per COVERED sample in the window:
  `{source, frame, faces: [{box: [x, y, w, h], confidence, roll, yaw, mouth_gap, mouth_width}]}`,
  `source` the sample's instant `ticks(k)`, `frame` the read frame's pts or null; with `clip` also
  `clip_time` and `timeline` from `source` (`AnalysisClipTimes`). Every float is rounded to 4
  decimals in the ANSWER only (`AgentServer.answerValue`; ≤ 0.4 px of a 4K frame's width), NaN
  answering null; the cache stays raw. The rounded value is written as a decimal number
  (`NSDecimalNumber` of its shortest spelling): `JSONSerialization` prints a `Double` to 17
  significant figures, so a rounded `Double` alone came out as `0.43219999999999997` (P5's first
  run). CJ-25's default window (the whole media, or the clip's played window) and its 512 KiB cap
  stand: over the cap the call is refused naming as the largest `to` the `source` of the first row
  that does not fit, as masks' runs are. **Measured** (`faces_probe.swift` P5, a one-face row at a
  late source): 176 bytes without `clip` and 221 with it, so a default call holds 2,962 rows, 296 s
  of samples (2,361, 236 s, with `clip`), less with more faces in frame. The catalog's prose and
  spec §7.9e state that length and tell an agent to read a longer media in `from`/`to` windows of
  at most that (the prose's example is 2 minutes).
- **CJ-35 — CJ-S3 (b) with a `faces` job: no pause.** `lane_spike.py --playback --kind faces`
  (`rule_sha256` `209c6f01…f0309ce830`, matching) on a Release instance: `play_preview`'s composed
  frames over 20 s of a 1080p30 timeline, idle and then with a `faces` job wanted on another
  document over the moving still, three of each. The recorded run, with the job over the whole
  ten-minute still and running through every play: idle 600, 600, 600 and busy 600, 600, 600, a
  0.0 % drop. Three earlier runs on the same instance: a 120 s window (597, 599, 600 against 598,
  600, 600; each job landed in about 9 s, inside the play, so the window was widened); the whole
  still with the job rows read wrongly (600, 599, 600 against 600, 600, 600); and once more (600,
  599, 600 against 224, 600, 600, the 224 while the machine's load average was 32.85 with the other
  lanes' builds; the median still 600). No run passed the 2 % rule, so **the picture queue does not
  pause** for `faces`, and CJ-21 stands unamended.

CO-30…CO-32 are CO3's (Remove Background in the inspector and the menus), recorded before its
code. The owner's answer for CO3 (2026-11-01): Clip ▸ Remove Background has **no key
equivalent**. No format bump, no core change, no `rc_*`: Swift, the documents and the proofs on
top of CO2a1, CO2a2 and CO2b. Vision runs on the Mac, so nothing here is keyed (CJ-3).

- **CO-30 — The Background section and Clip ▸ Remove Background.**
  - **(a) The rows, in order.** The Picture sub-tab's **Background** section (`video.cutout`),
    right after Chroma Key, shown when every selected clip can be cut out (a media or still clip
    of a video file with pictures, `CutoutStatus.canCutOut`): "Remove background" (a checkbox);
    Background (a popup, Remove / Keep); Edge (−1…1, two decimals, a slider, quick values −0.5,
    −0.25, 0, 0.25, 0.5); Feather (0–100 %, quick 0, 10, 25, 50); Status (a read-out 170 pt wide,
    its tooltip the full words); and a button row, Analyze Now. The road map's draft is set aside
    twice: there is **no Quality row** (CO-S1 kept no Best and CO-20 refuses `best`; CO4 owes it)
    and **no "Paused while playing"** (CO-12: a masks job does not pause). Background animates as
    CO-20 says — it switches at an action's end — superseding the draft's "Background
    base-only".
  - **(b) Where each row writes.** The checkbox and the section's Reset write the clip's BASE
    `set_video` only, so inside an action their gutter is ⊘: turning on writes a whole default
    cutout (`{cutout: {}}`'s five defaults) only to the selected clips that have none, turning off
    writes `cutout: null` to them all. `InspectorBinding.structural(video:for:)` sends `cutout`
    (its presence, a whole one or null) to the base, always. Background, Edge and Feather are
    enabled only when every selected video clip has a base cutout (`allCutOut`) and write a sparse
    `VideoPatch.cutoutPart`, which animates: with an action selected an end gets only the row's
    own key (`set_action_end {video: {cutout: {edge}}}`), never `subject`, `quality` or a null.
  - **(c) The summary and the Status words.** The summary is "off" while no selected clip is cut
    out; else the Status words for one clip, or "on". Status: no cutout "Off"; no frame to analyse
    "No picture to analyze"; analysing "Analyzing N %" (N = ⌊progress × 100⌋, at most 99); every
    needed frame covered "Ready", or "No person found" when no run of the clip's window found one
    (CO-26); a failure "Failed: <why>" — "the media file is missing", "the media file cannot be
    read", "no cache folder", or the lane's own sentence; several clips "—". Analyze Now is
    enabled when a selected cut-out clip is analysing or failed; it runs
    `ProjectDocument.analyzeMasksNow()`: `ensureMasks()` (CO-22 stays the one want path), then,
    on `CutoutWants.queue` after that want, `AnalysisLane.retry(owner:)`, which clears the
    `.failed` or `.cancelled` outcome of the owner's requests that are neither running nor queued
    (as `want` does for a request wanted anew) and reconciles; a running or queued request is
    untouched, and `want`'s reset rule and `wait` are unchanged.
  - **(d) The read-out's life.** The pane holds its status (`CutoutStatus.Memo`) while the
    document's handles and its `ReverseSource` resolution are unchanged, and through a live
    gesture. While the held state is analysing or failed and the read-out is in a window, a 0.5 s
    main-run-loop ticker re-reads only the lane — each of the owner's requests' runs (outcome and
    `endedAt`) and the running job's progress; a changed run, or a `masks` `.analysisDidPublish`
    for the document's cache folder, recomputes the status, refreshing the pane when the state
    changed and the read-out alone otherwise. The pane's Analyze Now drops the held status.
  - **(e) The menu.** Clip ▸ Remove Background, right after Look ▸, no key equivalent (the
    owner's answer): enabled when the selection in the open scope holds a clip that can be cut
    out; its checkmark is on when every such clip is cut out, mixed when some are, off when none
    is; it toggles them (all on → all off; otherwise the off ones on, a cut-out clip's own values
    kept) as one undo step, "Remove Background", one base `set_video` per clip as Clip ▸ Motion ▸
    writes.
- **CO-31 — `analyze_cutout` and the status rule.**
  - **(a) The status of a clip** (`CutoutStatus.status`, main thread). Its windows are
    `CutoutWants.windows` of the document's handles (`[project]`, with a nest open `[project,
    editedProject]`) for that clip; `frames` is the count of their merged needs (CO-22 (a));
    `covered` the needed indices the store covers for the stamp the analysis would make (the stamp
    made once per cache folder, media and URL, on main); `subject_found` CO-26's, over the clip's
    hull window. The order: no base cutout → off; `frames` 0 → no picture; `covered == frames` →
    ready, or no person — before any failure check, so a clip whose masks are all stored is never
    failed by another window's job; no file, no cache folder or no stamp → failed; a `.failed` run
    among the document owner's (`maskOwner`) requests of the media whose ranges meet the clip's
    needed, uncovered indices → failed with the lane's sentence; else analysing. **Progress** is
    `(C_out + f · R_in) / N`: N the needed indices, R_in those inside the ranges of the owner's
    running masks request of that media, C_out the covered needed indices outside them, f that
    request's `AnalysisLane.progress` (0 before its first frame); with no running request R_in is
    0 and C_out is every covered needed index. A running job's mid-job publishes count through f
    alone, never twice.
  - **(b) The tool.** `analyze_cutout {clips?, wait?}` is an app-state tool, off the main thread,
    with no `scope`: it acts in the open scope and names its clips there. Refusals, in order:
    `wait` that is not a number or lies outside 0…60 — "wait must be from 0 to 60 seconds."; a
    named clip that does not exist (`optionalClipsArg`'s sentence); a named clip with no base
    cutout — "Clip N has no Remove Background; set_video {cutout: {}} turns it on."; with none
    named and no cut-out clip in the open scope — "No clip in the open scope has Remove Background
    on; set_video {cutout: {}} turns it on.". Then one main hop runs `analyzeMasksNow()` (the
    pane's Analyze Now), then `CutoutWants.queue.sync {}` off main, so the want and the retry have
    run before the first read; then it reads the statuses every 0.25 s (main hops) until every
    clip is ready, no person, failed or no picture, `wait` seconds pass (0 when absent: the status
    now), or the assistant's Stop — never a timeout refusal.
  - **(c) The answer.** `{ok, clips: [{clip, media, state, progress, quality, frames, covered,
    ready, subject_found, centroid, error?}], project}`: `state` one of `analyzing`, `ready`,
    `no_person`, `failed`, `no_picture`; `progress` to three decimals (`covered / frames` outside
    analysing); `quality` the clip's; `ready` whether `covered == frames > 0`; `error` the tool's
    sentence when failed, "Clip N's person masks could not be made: <why>." **`centroid`** is null
    unless the clip is ready and a subject was found: the mean, over the needed and covered pack
    frames whose mask is `found`, of each frame's value-weighted centroid `(Σ v·(x + 0.5) / Σ v,
    Σ v·(y + 0.5) / Σ v)` in mask texels, scaled by the media's width over the mask's and its
    height over the mask's — `{x, y}` in the media's upright display pixels, top-left origin, y
    down — computed off main from values captured on it. CO7's `focus` reads it.
- **CO-32 — CO3's proof.** `co3_proof.py`, its probe `co3_probe.swift`: I1 the section registered
  after Chroma Key and its checkbox committing one `set_video {cutout: {five defaults}}` step; I2
  Status reading "Analyzing 0 %" under `-RCDevAnalysisHold`, then "Ready" on the person fixture
  and "No person found" on the screen recording, from `snapshot_ui`'s layout dump; I3 with an
  action selected Edge writing `set_action_end {video: {cutout: {edge}}}` alone, Background
  `{background}` alone, the checkbox ⊘ and its write the base `set_video`; I4 `analyze_cutout
  {wait: 0}` under the hold answering analysing, not ready, `covered < frames`, centroid null, and
  `{wait: 60}` without it ready with `covered == frames ==` `get_media_analysis`'s `frames`; I5
  the menu item's state off, mixed and on, and a mixed toggle turning on only the off clip (the
  other's edge kept) in one undo step; I6p and I6 the centroid against the probe's own reading of
  the pack, within 1e-6 px; I7 a clip ready beside a clip of the same media failed by a read-only
  masks folder, then, the folder restored, `analyze_cutout {wait: 0}` taking the failed clip's
  Status out of "Failed" within 2 s and `{wait: 60}` answering ready; I8 the progress rule's three
  cases; Z1 an empty parity log. Eight mutants, once, on Release. No JOB row: the screen catalog's
  `05i-clip-background` is the section's look.
