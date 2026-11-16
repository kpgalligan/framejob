# Spec §11 — decisions: Creator jobs, the Transcript tab's bar onward (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-3.md`](creator-jobs-3.md), so a citation never has to
say which file. This file holds TX-24…TX-27 (TX2b), CO-10…CO-15 (CO1) and CO-20, CO-21 and CO-23
(CO2a1). The series goes on in [`creator-jobs-4.md`](creator-jobs-4.md), which is why this file is
lettered. It is new because `creator-jobs-3.md` had passed the spec's ~500-line split rule (#548,
2026-11-11); the entries moved here unchanged, and an "above" or "below" in one may now point into a
sibling file.

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
  **Amended 2026-11-04, by TX-36:** the notes and rows name each clip, its id beside the name:
  "“Interview.mov” (clip 5) — reason".
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
