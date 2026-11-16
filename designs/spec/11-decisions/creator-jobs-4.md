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

CO-22 (CO2b), CJ-30…CJ-35 (CJ3) and CO-30…CO-32 (CO3) are in
[`creator-jobs-4b.md`](creator-jobs-4b.md), moved there unchanged on 2026-11-11 because this file
had passed the spec's ~500-line split rule (#548).

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
    split (`core/src/edit_range.rs`, `clear_range`): `ShotSplit.clipCount(project.snapshot)` plus 1
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
