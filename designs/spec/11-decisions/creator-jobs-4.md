# Spec §11 — decisions: Creator jobs, deleting words onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md) and [`creator-jobs-3.md`](creator-jobs-3.md) (CJ-, VR-,
TX-, SW-, CU- and CO-), so a citation never has to say which file; `creator-jobs.md` says what the
road map builds and how its IDs are made (CJ-7). This file is new because `creator-jobs-3.md`
passed the road map's ~500-line split rule with TX3a's entries (2026-11-02), which moved here;
each phase's decisions are appended here from now on, before its code.

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
  - A word's own `cut_start`/`cut_end` are its run of one AFTER TX-32's widening, snapped
    (`TranscriptCut.wordCut`), so they are what the tab cuts for that word alone, crosstalk
    included, and TX-33's sentence holds. Cutting words one at a time and together make the same
    timeline, except across a pause over 1 s.
  - **The pause clause** (a pause token cuts `[end of the speech before + 0.2 s, next onset −
    0.2 s)`) is recorded here and built in TX3b as TX-34.
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
