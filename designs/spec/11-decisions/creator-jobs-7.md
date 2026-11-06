# Spec §11 — decisions: Creator jobs, sound events onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md),
[`creator-jobs-4.md`](creator-jobs-4.md), [`creator-jobs-5.md`](creator-jobs-5.md) and
[`creator-jobs-6.md`](creator-jobs-6.md) (CJ-, VR-, TX-, SW-, CU- and CO-), so a citation never has
to say which file; `creator-jobs.md` says what the road map builds and how its IDs are made (CJ-7).
This file is new because `creator-jobs-6.md` held CU7's entries at 475 lines, and FC3's would have
made it 609, past the road map's ~500-line split rule (2026-11-02); each phase's decisions are
appended here from now on, before its code.

## FC3 — sound events (2026-11-02)

Recorded before the code. FC-30…FC-34 are FC3's: Sound Analysis' `.version1` classifier, on the
Mac, gives agents six groups' confidence per window of a media's sound through
`get_media_analysis {kind: "sound_events"}`, an analysis kind on CJ2a's lane and store, made on
demand and cached per media. Nothing changes on screen, and no core, FFI, format (41 stands), op,
tool or key is added: Sound Analysis is on-device, so nothing is keyed (CJ-3). The owner's
answers that set it: 2026-11-01, "FC3: run the sound pass at import: NO. It runs when Find Clips
needs it."; and 2026-11-02, answering FC3's first attempt's STOP at FC-S1, option (a): the
spike's agreement test gains a ±0.1 value tolerance, under which the stream analyzer agrees and
FC3 uses it.

- **FC-30 — Sound events: FC-S1's verdict.** macOS 26.5.1 (25F80), Apple M2 Max, on AC power,
  three lanes on the machine. `rule_sha256` `7fe7bcab…8fa8b06989`, matching CJ0a's table:
  **FC-S1's rule entry and its pin are unchanged.** The owner's amendment does not touch the
  rule's text ("The stream analyzer is used if its event times agree with the file analyzer's
  within one hop"); it defines that test in `sound_deciders.agreement`, which `results.json`
  states as `agreement_metric` with `value_tolerance` 0.1. The re-run's line: `VERDICT
  window=1.5 hop=0.75 groups=weak(all, no S-EV) labels=all stream_agrees=yes strict_unmatched=6
  deterministic=no rt_1.0_file=79.7 rt_1.0_stream=227.3 rt_1.5_file=261.0 rt_1.5_stream=277.6
  rt_3.0_file=187.6 rt_3.0_stream=102.4`. Attempt 1's (same host, before the amendment):
  `VERDICT window=1.5 hop=0.75 groups=weak(all, no S-EV) labels=all stream_agrees=no
  deterministic=yes rt_1.0_file=218.6 rt_1.0_stream=229.5 rt_1.5_file=276.4 rt_1.5_stream=297.6
  rt_3.0_file=353.7 rt_3.0_stream=390.3`.
  - **The window is 1.5 s and the hop 0.75 s** (overlap 0.5): every window × analyzer ran above
    60× real time in both runs (the medians above, over the 607.15 s ten-minute loop of
    `samples/Rode-usb-mic.m4a`, three runs each); with no S-EV there is no laughter recall, so
    every window ties and the tie goes to 1.5 s. The rule's "if none reaches 60×, the slowest
    acceptable is kept" is implemented as "the fastest is kept" in `window_rule`; that branch has
    not arisen.
  - **Every group is weak.** S-EV (the labelled laughter, applause and cheering), S-TH1 and S-ST1
    (ten minutes of speech only) and S-MU (music) do not exist yet, so no group has held-out
    events, no threshold is chosen and no false-call rate is measured: weak by rule. They are
    owed; `SoundEvents.thresholds` is empty and every group answers `first_class: false`.
  - **Labels:** all eleven of FC-31's labels are among `.version1`'s 303 known classifications;
    the window constraint is a range of 0.5…15 s, and 1.0, 1.5 and 3.0 s are set exactly.
  - **The owner's amendment and its evidence.** Under attempt 1's metric (a rising 0.5 crossing
    matched only by a crossing on the other side within one hop) six crossings were unmatched,
    each one window where the two analyzers sat either side of 0.5. Each pair below is the other
    side's value in the window before the crossing and at it; the first five are attempt 1's
    `FC-S1-near-threshold.log`, the sixth (the log has no block for it) the re-run's `tolerated`
    entry. The 1.0 s stream runs on the loop gave the same `sha256` (`b25647d9…`) in attempt 1's
    `FC-S1-results.json` and in this re-run, so that pair is attempt 1's too:
    1. 1.0 s, `filler`, speech, a stream crossing at 25.5 s: file 0.501 → 0.731;
    2. 1.0 s, loop, music, a file crossing at 317.5 s: stream 0.339 → 0.495;
    3. 1.0 s, loop, music, a file crossing at 365.5 s: stream 0.122 → 0.493;
    4. 1.0 s, loop, music, a stream crossing at 80 s: file 0.296 → 0.437;
    5. 3.0 s, loop, speech, a file crossing at 312 s: stream 0.506 → 0.849;
    6. 1.0 s, loop, music, a stream crossing at 530 s: file 0.3339 → 0.4913 (the re-run).

    Every one has a value within ±0.1 of 0.5, so all six are tolerated, and nothing is left
    unmatched at any `<window>/<input>`: the stream analyzer agrees. The re-run's `tolerated`
    list is exactly these six (to four places: 0.5010/0.7308, 0.3389/0.4952, 0.1223/0.4926,
    0.2959/0.4369, 0.5060/0.8489, 0.3339/0.4913). Over whole files |file − stream| had a median
    of 0.003–0.009 (attempt 1).
  - **Determinism.** Attempt 1 (load averages under 20) gave byte-identical stream values over
    three runs at each window. The re-run, while the one-minute load average climbed from 5.5 to
    129, gave identical values at 1.0 s, two of three at 1.5 s and none at 3.0 s. Four more 1.5 s
    and three 3.0 s stream runs at a load average of 239 differed from their first by at most
    0.0026 (1.5 s) and 0.0229 (3.0 s), with the same window starts and no value present on one
    run and absent on another. Sound Analysis picks its own device (FC-31's `device` `auto`), and
    its values move in the third decimal when the machine is busy, so a proof compares two runs
    within 0.01, never bit for bit.
- **FC-31 — `sound_events`, an analysis kind on the sound queue.** `AnalysisKind.soundEvents`
  (`"sound_events"`): `cache/analysis/sound_events/<media id>.json` and `windows.bin` in its
  folder. **The table** (`SoundEvents.labels`, `tableVersion` 1, which is the kind's `version`):
  laughter (`laughter`, `belly_laugh`, `chuckle_chortle`, `giggling`, `snicker`), applause
  (`applause`, `clapping`), cheering, crowd, music and speech (each its own label), a group's value
  the maximum `classification(forIdentifier:)` confidence over its labels, NaN when none.
  **The grid** is the hop grid, `AnalysisGrid(hopTicks: 450_000, duration:)` (num 600,000, den
  the hop): window k starts at k × 450,000 ticks of the forward media's source time and lasts
  900,000; `count` is ⌈duration / hop⌉, so on the 607.15 s media it is 810 and windows 808 and
  809 overhang the end. **`windows.bin`**, little-endian: `FJSE`, `UInt16` version 1, `UInt16`
  record bytes 24, `UInt32` windows, `UInt32` groups 6, then six `Float32` per window in
  `Group` order; a publish decodes the on-disk file and replaces the windows it covers, and a
  file that will not decode or holds another count is written fresh and keeps the job's coverage
  alone. **The stamp:** `parameters` (classifier `version1`, analyzer `stream`, `window_ticks`,
  `hop_ticks`, `overlap`, `sample_rate` 16000, decode `speech_reader_mono_f32`, `mp3_trim`,
  `file_version`, `record_bytes`, value `max_confidence_over_labels`), the OS build (the
  classifier ships with the OS), `device` `auto`, `vision` nil, margin 0, and reader always `raw`:
  `ProjectDocument.analysisRequest` gives a sound kind no `ThumbnailInput` and never calls
  `analysisInput`, so `set_media_color` does not invalidate it. Keyed by media and read from the
  first audio track (`CompositionBuilder.assetTrack(…, mediaType: .audio, …)`) until SW4a re-keys
  it per source (SW-40). **The job** (`AnalysisSoundEvents`, on `AnalysisLane`'s serial sound
  queue): one `SNClassifySoundRequest` `.version1` per job at the window and overlap; per missing
  range k0…k1 one `SNAudioStreamAnalyzer` over a 16 kHz mono Float32 `AVAudioFormat`, fed by
  `MediaImporter.speechReader(…, window: readWindow(k0…k1))` — the reader's `timeRange` is
  `leadingTrim + k0·hop` for `(k1 − k0)·hop + window + hop` (the two existing callers pass no
  window and are unchanged), so an MP3's encoder delay is skipped as every cache skips it (SY-42)
  — positions from the range's first sample, `cancelled()` checked per buffer. A result starting
  at s samples is window k0 + round(s / 12,000); one past k1 is dropped; results are collected
  under a lock. **Publication** through `AnalysisStore.publishFile`: every 30 s and at the range's
  end, an interim publish only through the contiguous answered prefix from the first unpublished
  window. At the range's end, after `completeAnalysis()`, coverage is that prefix plus **the NaN
  tail**: every window k of the range with no result and k·hop + window past the decoded sound
  (k0·hop plus the decoded sample count, in ticks), stored NaN and covered — only when the reader
  `.completed` at the media's end (its window reaches the media's duration, or the track ran out
  before the window did). Any other unanswered window stays uncovered. A reader that does not
  complete fails the job (CJ-25's failure sentence) and that range's end publishes nothing; a
  cancelled job publishes nothing more. **The lane:** a running sound job does not count against
  `pictureWidth` — `reconcileLocked` counts only running picture jobs — so `sound_events` never
  holds back `shots`, `masks` or `faces` (the queues' comment always said they were separate).
  **Clip times** go through `AnalysisClipTimes` (`SoundEvents.events(in:covered:grid:for:)`, for
  FC4); a reversed clip gets none, as `Transcriber+Jobs.swift` refuses its words. **The file's
  name** is `AnalysisSoundEvents.swift`, not the road map's `AnalysisKind+SoundEvents.swift`, to
  match `AnalysisFaces.swift` and `AnalysisShots.swift`.
- **FC-32 — On demand, never at import (CJ-20; owner, 2026-11-01: "NO").** No import pass, no
  cache pass and no `MediaCacheLane` work runs it; a `get_media_analysis` call (and, from FC4,
  Find Clips) wants the windows it needs. No reading of it is shown as a score.
- **FC-33 — The answer and its refusals.** The common fields (CJ-25) and `window`, `hop` (ticks),
  `groups` `[{name, labels, first_class, threshold}]` (`threshold` null while weak), `count` and
  `windows`: one row per COVERED window whose `source` (k × hop) lies in [from, to), `{source,
  laughter, applause, cheering, crowd, music, speech}`, each value rounded to 4 decimals and
  written as an `NSDecimalNumber` (`AgentServer.answerNumber`, moved out of `facesAnswer`, its
  bytes unchanged), null where there is no result; with `clip` also `clip_time` and `timeline`.
  Over 512 KiB of JSON it is refused in faces' sentence ("The sound event windows from F to T
  come to N bytes of JSON, … call with to at most S from from F."), S the first `source` that does
  not fit. In CJ-25's order two refusals are added: after "not a media clip", for this kind, "Clip
  C plays in reverse, so its sound events are not read: its sound plays backwards."; and in place
  of the moving-picture guard, for this kind only, "Media M has no sound, so it has no
  sound_events to find." — an audio-only media is accepted, and every picture kind keeps "has no
  moving picture". `analysis_job`'s media guard follows the kind the same way.
- **FC-34 — FC3's proof.** `sound_events_probe.swift` (P1–P9: `windows.bin` round trip and merge
  in either order, a damaged file replaced; the hop grid; the stamp; the MP3 window against the
  WAV; ×2 and ramped placement against `MediaPeaks.sourceTick`, a reversed clip none; a cancelled
  run's coverage and values; whole against halves within 0.01; the answer's decimals, nulls and
  cap; the NaN tail on media of three lengths) and `sound_events_proof.py` (E1 the speech onset
  moved 2.000 s ± a hop by prepended silence, E2 MP3 against WAV, E3 the cache and its stamp, E4
  the missing range only, E5 a cancelled job, E6 rows against `windows.bin`, E7 a ×2 clip, E8 the
  refusals, E11 a picture job not held back by a sound job, Z1; E9 S-EV recall and E10 S-MU
  confusion skipped by name and owed). Six mutants: `window-start` (P2, E6), `mp3-trim-skipped`
  (P4), `early-publish` (P6), `cover-whole-range` (P9, P7), `table-version` (P3),
  `sound-holds-picture` (E11). No manual check.

## CU8 — shortcut overlays (2026-11-02)

Recorded before the code. CU-80…CU-85 are CU8's: Clip ▸ Add Shortcut Overlays and the tool
`add_shortcut_overlays` place one `keyboard-keys` graphic clip per recorded shortcut of the
selected clips' cursor files, at its moment, on a front "Shortcuts" track, as one undo step "Add
Shortcut Overlays". The plan is a core planner, `plan_overlays`, an eighth `rc_cursor_query`
request (one track per clip and the project, as `plan_zooms`; no new `rc_*` export, op, format or
cursor-file version). The owner's answer (2026-11-01): "overlays sit at the bottom, in the dark
theme." Nothing here sends anything anywhere, so nothing is keyed (CJ-3). Only shortcuts are
placed: no typed key is recorded (CU-7).

- **CU-80 — Placement and timing.** A press is a `keys.shortcut` entry of a given clip's file
  whose source tick (`us_to_ticks(t)`) lies in the clip's played window `[in, in +
  content_length_in_source)`, placed at `clip.start + clip_time(clip, s − in)` — through S on a
  ramp, ⌊read ÷ speed⌋ otherwise (`cursor_zoom_run.rs`'s one mapping) — kept when inside `[from,
  to)` (container ticks), and snapped to the container's frame grid. Every clip's presses are
  merged in time order, ties in the given clip order. A chord's keycap count n is the count of
  non-empty, trimmed `+` tokens of its `keys`. **D_min(n) = 10n + 25 frames** of the container's
  canvas rate: the template's last keycap presses at frame `pressAt + 5(n − 1)` = 10n + 9
  (`keyboard-keys.js`; the road map's "5n + 14" is the FIRST keycap's press) and exits over the
  clip's last 15 frames, so the last press needs 16 frames before the end. Each overlay starts at
  its press s and lasts max(duration, D_min(n)), `duration` 1.5 s by default (0.5–10). The SAME
  `keys` pressed at p before the current overlay's end extends its end to max(end, p + duration),
  its count k + 1, its label "×k" (U+00D7) — else the label is "" (sent: the template's default
  label is "Screenshot a selection"). A DIFFERENT chord pressed at p before the current end would
  start at max(p, s + D_min(n_current)): more than 0.5 s after p it is dropped and counted
  (`dropped`), else the current overlay ends there and the new one begins there. A press at or
  after the current end starts a new overlay. Every start and end is a frame of the grid, no
  overlay is shorter than its D_min(n), and none overlap. Props: `keys` verbatim, `label`,
  `position` (`bottom` · `center` · `top`, `bottom` by default) and `theme` (`dark` · `light`,
  `dark` by default); `accent` is the template's.
- **CU-81 — The module.** A module of the document's `graphics/` whose bytes equal the bundled
  `keyboard-keys.js` is reused — the one named `keyboard-keys` first, else the lowest name —
  else, only when the plan places at least one overlay, the bundled template is written under
  `GraphicStore`'s free-name rule (`writeGraphicModule(from:)`, G-16 (b), which rescans), and the
  plan is made again when the written name differs from the predicted
  `uniqueModuleName("keyboard-keys")`. The clips carry the template's compiled schema. The write
  is not undoable (G-3); a run that places nothing writes nothing.
- **CU-82 — The token `plus`.** `keyboard-keys.js` reads a token spelled `plus` (any case) as the
  keycap `+` (CU-60 spells the plus key `plus`), for its text and its font; every other token is
  unchanged. A comment at `pressAt` names CU-80's D_min(n).
- **CU-83 — The track rule (in the core: it needs the planned span).** The span is [the first
  overlay's start, the last one's end). The overlays go on the front-most track named exactly
  "Shortcuts" when it is in front of every given clip's track, not locked, not hidden, has no
  matte and holds no clip meeting the span; otherwise on a new track named "Shortcuts" added at
  the front (`add_track` at index `tracks.len()`), its id the project's `next_id` (one id space
  inside a nest). This deviates from the road map's listing, which put the rule in Swift.
- **CU-84 — The doors and the refusals.** `plan_overlays {clips, duration?, position?, theme?,
  module, schema?, from?, to?}` → `{ops, added, dropped, merged, track, new_track, overlays:
  [{at, duration, keys, label}]}`; with nothing placed `ops` is `[]` and `track` null. Refusals,
  in order, each its own sentence: `duration` outside 0.5–10 ("duration is D s; it runs 0.5–10"),
  `to` not after `from`, no clips, a track count unlike the clip count, no project; then per clip
  named twice, unknown, not a media clip, its media with no cursor file, reversed ("clip C plays
  reversed; Add Shortcut Overlays places only clips that play forward" — CU-5); an unknown
  `position` or `theme` in serde's sentence. **Clip ▸ Add Shortcut Overlays** (right after Auto
  Zoom…, no key, no sheet) is on with at least one selected clip, each a media clip whose media
  has a cursor file (`AutoZoom.canOffer`), no sheet attached and no run pending for the document;
  the validator never reads a file. A run finds the files on main, reads them on a
  `.userInitiated` queue, and back on main refuses if the project or scope changed, then places
  with the defaults — bottom, dark, 1.5 s; nothing is remembered — through `performGroupedEdit`.
  An informational sheet shows a refusal, "No shortcut was recorded in the selected clips' played
  windows, so nothing was added." (no undo step, no module written), the changed-project sentence,
  or, after a placing run, "N shortcuts came too close to show." **The tool**
  `add_shortcut_overlays {clip | clips, from?, to?, duration?, position?, theme?}` takes no
  `scope` key (it acts in the container `set_scope` has open, as `auto_zoom`), runs on the server
  thread (resolved on main, files read off it, then on main refused if the project or scope
  changed, placed, `editResult`), and answers `added`, `dropped`, `merged`, `track`, `new_track`,
  `module`, `written` and `overlays`; with nothing placed `ok` with that `note`, and a `note` of
  the dropped sentence when any was dropped.
- **CU-85 — CU8's proof.** `cu8_proof.py` O0–O8 over MCP (O1 four shortcuts well apart; O1b at
  60 fps no overlap; O2 and O2b the drop; O3 the merge; O4 module and track reuse; O4b a new track
  in front of a clip's track; O5 `render_frame` bottom-half difference; O6 D_min over every
  fixture; O7 the menu equals the tool; O8 the refusals and the empty run), O9 in
  `core/tests/shortcut_overlays.rs` (S on speed 2 and a ramp, `from`/`to`), the template's `plus`
  in `graphic/tests/templates.rs`; seven mutants (`overlap-allowed`, `module-rewritten`,
  `times-without-s`, `dmin-ignored`, `repeats-not-merged`, `plus-not-mapped`,
  `track-behind-reused`). No person check: the look is judged at CU12's trial.

## VR1 — people and salient regions found on the Mac (2026-11-02)

VR-10…VR-16 are VR1's, recorded before its code after spike VR-S1 (verdicts in VR-11). The
owner's answers that set them: 2026-11-01, Batch 7 — Show Subjects is in the product (VR-13);
2026-11-02, answering VR1's first attempt's STOP — VR-4 is amended to `upperBodyOnly` true (the
amendment line under VR-4, with VR-S1's figures). Nothing here is keyed (VR-2, CJ-3): Vision is
on-device. No core, FFI, format or product-tool change; the dev tool `analysis_job` gains `clips`
and `lane_queued` (VR-16). CJ-20 stands: nothing runs at import.

- **VR-10 — `subjects`, one analysis kind holding people and salient regions.** It amends the road
  map's draft VR-10 (`upperBodyOnly` false; boxes as centre and size). Per sample of source time:
  each person box from `VNDetectHumanRectanglesRequest` revision 2 with `upperBodyOnly` true (VR-4
  as amended: a box covers the head and shoulders), and each salient box from
  `VNGenerateAttentionBasedSaliencyImageRequest` revision 2's `salientObjects`, each with its
  confidence; both requests FRESH per analysed frame, performed together on one fresh
  `VNImageRequestHandler`; no stateful request (VR-4). Boxes are x, y, w, h, 0…1 of the upright
  picture from its top-left, as `faces`' (`AnalysisFaces.topLeft`). Stored in CJ-22's store
  (`cache/analysis/subjects/<media>.json` and `<media>/samples.bin`): a 16-byte header (`FJSB`,
  `UInt16` version 1, `UInt16` 20, `UInt32` samples, `UInt32` boxes), a 16-byte row per sample
  (`Int64` pts, −1 none; `UInt32` first box; `UInt16` people; `UInt16` salient), then 20-byte boxes
  (`Float32` x, y, w, h, confidence), a sample's people first, each group in CJ-31's order; the
  publish merges as `faces`' does (CJ-33). The stamp: kind version 1; vision `{request:
  "human_rectangles+attention_saliency", quality: "upper_body", revision: 2, rate, read_size}`;
  device `people:<readback>;salient:<readback>`; the parameter digest names `upper_body_only`, both
  devices, the file version and record size, the sample rule, the order and `salient_objects`.
- **VR-11 — VR-S1's verdicts: the grid, the reader and the devices are `faces`'.** The run (macOS
  26.5.1 (25F80), Apple M2 Max, AC power; three lanes, one-minute loads 7.86…125.69):
  `VERDICT rate=10 every_other=no size=720 people=neural_engine(branch 1)
  salient=neural_engine(branch 1) identical=yes reader=converted realtime_1080=6.25
  realtime_4k=8.52`, `rule_sha256` `6650e95d…03c28ac` (matching; the entry names no
  `upperBodyOnly`, so the amendment did not move it).
  - CJ-S2 rule 1 per request, 600 samples of `faces_moving.mov` at 720, each alone: people CPU
    31.12, 19.31, 12.51 s, GPU 8.75, 9.06, 9.48 s, Neural Engine 4.98, 3.11, 3.66 s; salient CPU
    25.45, 24.98, 24.78 s, GPU 11.59, 10.12, 10.08 s, Neural Engine 4.98, 4.87, 4.92 s. Every
    stage read back its pin (people `VNComputeStageMain`; salient also
    `VNComputeStagePostProcessing`), each device's three digests were equal and the devices'
    differed: the Neural Engine for both (branch 1).
  - Size (CJ-S2 rule 3 as VR1 re-runs it): person recall on `faces_small.mov` 0/600 at 720 and
    0/600 at native — the upper-body request finds no person in that head-only crop at any size —
    so 720 holds (98 % of 0). VR-S1 rule 2 (S-TH1) is owed.
  - VR-S1 rule 1, decode and both requests at 720, 10 a second: 6.27, 6.25, 5.78× on 1080p30
    (median 6.25×), 7.67, 9.08, 8.52× on 4K30 (median 8.52×); both at least 4×, so `faces`' rate.
  - VR-S1 rule 3: three runs on the Neural Engine, digests equal (people `18433177…5d251881e9`,
    salient `aee490d5…135e09f65`): no tolerance. Rule 4 (S-TH1) owed, people stay; rule 5 and
    CJ-S2 rule 5 owed, converted.
  - Person recall (a person box holding the truth face's centre): `faces_moving.mov` 600/600
    (whole-body 238/600); `subjects_moving.mov` front 596/600, back 521/600 (whole-body 155/600,
    22/600) — VR-4's amendment's figures, run again.
  So: samples on a grid of `AnalysisSubjects.rate` = `AnalysisFaces.rate` (10) a second, sampled
  by CJ-33's rule (`AnalysisFaces.samples(at:after:grid:)`) through `AnalysisSampleJob`, the
  sampled-kind job loop lifted out of `AnalysisFaces.run` (a pure move; `faces` byte-identical);
  frames through `AnalysisFrames.read`'s standard arms (direct, or converted for a converting
  media) at min(720, the media's long side); both requests pinned to the Neural Engine, a job
  refusing a readback other than the stamp's (`SubjectError.device`). Nothing is linked (CJ-31);
  values raw. The instruments are flat files, `creator_spike/subjects_spike.swift`,
  `subjects_spike.py` and `subjects_deciders.py` (CJ3's `faces_spike.*` shape, not the road map's
  `vr_subjects/` folder); the results file is `VR-S1/results.json`, `rule_matches: true`.
- **VR-12 — What a VR command analyses: `FramingAnalysis`.** `windows(clips:in:)`: each media clip
  among the clips whose media has a moving picture, in order, its media grouped in order of first
  appearance; each window the clip's played window (`AnalysisClipTimes`: source map, speed,
  reversal) widened by `margin` (1 s) each side, clamped to 0…duration, merged per media where
  they overlap or touch; text, shape, graphic, adjustment, nest and still clips are skipped.
  `requests(clips:in:)`: over the open scope's project, kind-major in `kinds` order (`shots`,
  `faces`, `subjects`), then media, each kind's need the windows' grid indices widened by its read
  margin, through `ProjectDocument.analysisRequest(kind:media:url:urls:cacheDir:need:)`; a hit is
  omitted. Its callers: `analysis_job {clips}` (VR-16) now, Clip ▸ Follow Subject… at VR2b.
- **VR-13 — View ▸ Show Subjects draws only what is cached (owner, Batch 7: in the product).**
  After Show SDR Version and before Scopes, no key, always enabled, checked while on;
  `UIMenuTable` `.plain`, inventory verdict `none`. Per window (`PreviewCanvasView.subjects`, nil
  while off) and never persisted: no `UserDefaults` key. For the canvas's primary box when its clip
  is a media clip of a video media: the playhead's forward source tick
  (`SubjectsOverlay.sourceTick`, `TimelineView.sourceTime` with the clip's source map and
  `ReverseMirror`), the sample ⌊source · rate⌋ clamped to the grid, drawn per kind only when a
  marker that answers for the stamp `ProjectDocument.analysisRequest` would make covers it. Each
  box is placed in the layer's uncropped rectangle and turned with it (ProjectSnapshot's (★)
  through `CanvasLayerBox`), clipped to the cropped corners: faces in `DS.snapGuide`, people
  `.systemTeal`, salient regions `.systemPurple` dashed [4, 3], each over a black 40 % backing.
  With neither kind covering, "Not analyzed" at the layer's top-left corner; VR2b appends "— Clip
  ▸ Follow Subject… analyzes it" when that item exists. It never starts a job: no
  `analysisRequest`, no `want`, no `cacheDirectory` (which creates the folder); it reads under
  `intendedCacheDirectory`, memoised per kind on CO-25's key (the marker's inode, size and mtime,
  the media, its URL and its LUT's URL), and an `.analysisDidPublish` of `faces` or `subjects` in
  the document's folder drops the memo and redraws. No MCP mirror: view state, §7.9's Preview
  Quality exemption as Show Ungraded's; `get_media_analysis` answers what it draws.
- **VR-14 — `get_media_analysis {kind: "subjects"}` answers rate, count and samples** `[{source,
  frame, people: [{box, confidence}], salient: [{box, confidence}]}]`, with `clip_time` and
  `timeline` under `clip`; every value through `answerNumber` (CJ-34's 4 decimals, lifted out of
  `facesAnswer` with faces' bytes unchanged); over 512 KiB refused naming the `source` of the first
  row that does not fit. Measured (`vr1_probe` P4): a row with one person and one salient box is
  177 bytes, 222 with `clip`, so an answer holds 2,945 rows (294.5 s), 2,351 (235.1 s) with
  `clip`; the prose says about 294 s and 235 s.
- **VR-15 — CJ-S3 (b) with a `subjects` job: no pause.** `lane_spike.py --playback --kind
  subjects` on Release (`rule_sha256` `209c6f01…f0309ce830`, matching): idle 599, 600 and 600
  composed frames, busy 600, 600 and 600 with a `subjects` job over the ten-minute still running
  through each 20 s play — a 0.0 % drop, so CJ-21 stands and the picture queue does not pause
  (`CJ-S3-subjects/results.json`, `rule_matches: true`).
- **VR-16 — `analysis_job` gains `clips`, and every answer `lane_queued`; VR1's proof.**
  `analysis_job {clips: [int]}` (exclusive with `media`) wants every `FramingAnalysis.requests`
  request under the document's dev owner and answers `wanted: {project, clips, requests}`;
  `lane_queued` is `AnalysisLane.queuedTotal()`, the requests the lane queued since launch, never
  falling. `vr1_proof.py`: P1–P7 (`vr1_probe.swift`: the codec and merge, order and flip, the
  stamp and requests, the answer and cap, `FramingAnalysis.windows`, the grid and `sampleIndex`,
  the overlay's corners against (★) and its source tick against speed, `ReverseMirror` and the
  `SourceMap`); V1 a person box holds the `faces` face centre in ≥ 95 % of `faces_moving.mov`'s
  samples (`subjects_moving.mov` recorded); V2 two runs byte-identical, the stamp's device; V3 the
  portrait pair's person centres within 2 % of the width (RMS); V4 every `subjects` source a
  `faces` source; V6 after `analysis_job {clips}` each kind's coverage the windows ± 1 s; V8 Show
  Subjects and five playhead moves on an uncached clip: `lane_queued` unchanged, no
  `cache/analysis/subjects`, no defaults moved; V9 `-RCDevAnalysisHold 5`: the job lands at least
  5 s after it starts; V10 S-TH4 skipped by name; Z1. Mutants (5): `grid-by-frame-index` (V4),
  `orientation-not-applied` (V3), `framing-whole-media` (V6), `source-tick-no-mirror` (P7),
  `show-subjects-wants` (V8). No person check.

## CU9b — Speed Up Typing (2026-11-02)

Recorded before the code. CU-91…CU-94 are CU9b's: Clip ▸ Speed Up Typing… and the tool
`speed_up_typing` play each typing stretch of the selected clips' cursor files that has no speech
and no shortcut at ×4 (the default), keeping 0.3 s at ×1 at each end, as one undo step "Speed Up
Typing". The plan is a core planner, `plan_typing`, a ninth `rc_cursor_query` request (one track
per clip and the project, as `plan_zooms` and `plan_overlays`; no new `rc_*` export, op, format or
cursor-file version), answered as CU-90's `retime_range` ops. The owner's answer (2026-11-01):
"the sound in a sped stretch is sped with Keep pitch on." Nothing here sends anything anywhere,
so nothing is keyed (CJ-3); speech detection is on-device.

- **CU-91 — The stretch rule (`plan_typing`, `cursor_typing.rs`),** in this order.
  (1) Per given clip: each `typing_stretches(file.keys.typed.t)` stretch (`cursor_bursts.rs`,
  CU-25) `[first, last]`, clamped to the clip's played window `[in, in +
  content_length_in_source)`, mapped to container time through `cursor_zoom_run.rs`'s
  `clip_time` (so through S on a ramp), then intersected with `[from, to)`.
  (2) Subtracted, in container time: (a) every speech span of every media clip in the container
  whose media `has_audio` and that overlaps the stretch, on any track, muted or not — the
  media's `speech` through `audio_duck_speech.rs`'s `speech_in_clip`, plus the clip's `start`;
  (b) per recorded shortcut press p of the given clips — CU8's mapping (`clip.start +
  clip_time(clip, s − in)` for s in the played window) but with NO `[from, to)` filter, so a press
  before `from` whose span reaches into the window still counts: the union of the clips on tracks
  named exactly `cursor_overlays.rs`' `TRACK_NAME` ("Shortcuts") that hold p or start in (p, p +
  `MOST_LATE`], from min(p, their start) to their end; with none, `[p, p + DEFAULT_DURATION)`
  (CU-80's 1.5 s).
  (3) The remaining pieces of ALL given clips are united, overlapping AND touching pieces
  merged, so a stretch across a cut between two clips is one piece.
  (4) Only then: a merged piece shorter than `shortest` is dropped and counted (`short`); a kept
  piece `[a, b)` becomes `[snapped(a + 0.3 s), snapped(b − 0.3 s))`.
  (5) Sorted, the pieces are answered RIGHT TO LEFT as `{op: "retime_range", from, to, rate,
  keep_pitch}` (`retime_range` acts on the whole timeline, so a range across a cut is one op, and
  right to left no op moves a later one's range). `sped_to` = `snapped(from + round((to − from) ÷
  rate))` (CU-90 (a)'s f); `saved` = Σ (to − sped_to). If any media counted in (2a) has no
  stored `speech`, the answer is `needs_speech` (its ids, sorted) with no ops and no ranges — not
  a refusal. **All or nothing:** the ops are applied in order to a clone through
  `Project::retime_range`; the first refusal or error refuses the plan: "the typing from {a} to
  {b} ticks cannot be sped up: {sentence}". Answer: `{ops, needs_speech, stretches, short,
  ranges: [{from, to, sped_to}], saved}`.
- **CU-92 — Defaults and ranges.** Rate ×4 in ×2–×8; shortest stretch 3 s in 1–30 s; Keep pitch
  on (the owner's answer); the margin 0.3 s at ×1 each end; the overlay fallback CU-80's 1.5 s and
  its lateness 0.5 s. Refusals, lowercase, in order: "rate is ×R; it runs ×2–×8", "shortest is S
  s; it runs 1–30", "to (T) must be after from (F)", "plan_typing needs at least one clip", the
  track-count sentence in CU-84's wording ("plan_typing reads one cursor track per clip; …"),
  "plan_typing needs the project"; then per clip: named twice, unknown, not a media clip, no cursor
  file, reversed ("clip C plays reversed; Speed Up Typing speeds only clips that play forward" —
  CU-5).
- **CU-93 — The doors.** Swift's speech step (`SpeedUpTyping.speech`): for each `needs_speech`
  media, a current VAD cache (`MediaImporter.speechIsCurrent` with `CacheStamp.stamp(for:url:)`)
  becomes a `set_media_speech` op with `DuckSpeech.spans`; a media with no file is refused "{name}
  is offline, so its speech cannot be read."; not current while `SileroVAD.isAvailable` is
  pending, and every door that sees pending STARTS the pass through `ProjectDocument
  .generateCaches()` (idempotent: a current cache costs a stat, a running pass is waited for),
  because a pass that could not read the file leaves no marker and is not retried until the next
  open; detection unavailable is refused "Speech detection is unavailable on this Mac, so Speed
  Up Typing cannot tell typing from talking." `SpeedUpTyping.resolve` plans, makes the speech ops,
  applies them to a pure handle (scoped again inside a nest), plans again; the step's ops are the
  speech ops, then the retime ops. Stored spans are never rewritten (AU-111).
  **Clip ▸ Speed Up Typing…** (right after Add Shortcut Overlays, no key, no `ModelKeys` row) is
  on with at least one selected clip passing `AutoZoom.canOffer` and no sheet attached, inside a
  nest too. Its sheet: Rate (×), Shortest stretch (s), Keep pitch, opened at the remembered
  values (`FrameJobSpeedUpTypingRate`, `…Shortest`, `…KeepPitch`, each written only when changed
  from what the sheet opened with); the files are read off main ("Reading cursor files…"); every
  control change plans again; waiting calls `generateCaches()` once per sheet, shows "Waiting for
  speech detection on {names}…" with Apply disabled, and plans again on each
  `.mediaCacheDidChange` of `MediaImporter.speechKind`, bounded at `SpeedUpTyping.waitLimit`, 300
  s (AU-68's bound), past which it shows "Speech detection has not finished for {names}. Close
  this sheet and try again." with Apply disabled; the summary "N typing stretches sped up ×R,
  saving S s." or "No typing stretch without speech or a shortcut lasts S s or more in the
  selected clips, so nothing would change." (Apply disabled). Apply commits through
  `SpeedAudioDrop.commit` (Cancel on its question leaves the sheet up), then remembers.
  `-RCDevSpeedUpTypingAccept YES` (dev tools only) presses Apply once the first plan with ops
  exists. **The tool** `speed_up_typing {clip | clips, rate?, shortest?, keep_pitch?, from?, to?}`
  takes no `scope` key (it acts in the container `set_scope` has open, as `auto_zoom`), runs on
  the server thread (resolved on main, files read off it, back on main refused if the project or
  scope changed); pending starts the pass and is refused "{name}'s speech has not been detected
  yet. Try again in a moment."; the crossing is read by `SpeedAudioDrop.crossing(applying:to:)`
  over the retime ops on the speech-applied handle, and the step is `performGroupedEdit(document,
  "Speed Up Typing", ops)`. It answers `ok`, `stretches`, `short`, `ranges`, `saved`,
  `speech_saved` (media ids written), `created`, `audio_left_out`/`audio_note` when any, and
  `project`; with nothing to speed, `ok` with a `note` and no undo step.
- **CU-94 — CU9b's proof.** `cu9b_proof.py` Z0, R3, R9, R10, R11, R12, R13, R14, R15 over MCP,
  `cu9b_probe.swift` P1 (the speech step's five answers) and P2 (`gaveUp(waitingFor:)` false at
  299 s, true at 300 s), `core/tests/speed_up_typing.rs` (sync across three tracks after two
  ranges, a ×2 clip and a ramp through S, `from`/`to`, a press before `from`, the union of two
  clips, every refusal); eleven mutants (`speech-ignored`, `margins-dropped`, `shortcut-inside`,
  `sheet-rate-not-passed`, `needs-speech-skipped`, `left-to-right`, `no-prevalidation`,
  `unavailable-as-pending`, `shortest-per-clip`, `presses-window-filtered`, `wait-unbounded`) —
  above ten because the objections added three decisions, one each. No person check: the feel is
  judged at CU12's trial.

## VR2a1 — the subject-choosing planner (2026-11-02)

Recorded before the code. VR2a runs as the road map's fallback split (its "Split" paragraph):
VR2a1 lands the source-time helper and the core planner as a pure function answering a framing
path — no op, tool, FFI, format (41 stands), Swift or guide change; VR2a2 lands coverage
(`reframe_cover.rs`, VR-7), VR-24, VR-25, VR-26, VR-28 and the op `reframe_clip`, whose
signature stays the road map's draft VR-20. VR-20…VR-23 are VR2a1's. Nothing here is keyed (VR-2,
CJ-3). No owner question: the road map expects none for VR2a.

- **VR-20 — Source time to clip time is one helper, and the planner's input.** New
  `core/src/clip_source_time.rs`: `clip_time_of_source(clip, media, t, round)` is
  `speech_in_clip`'s mapping of one forward-file source tick lifted out whole — reflected over
  `media.duration` when the clip is reversed, `in` subtracted (both saturating), then
  `SpeedMap::time_at` when the clip is ramped, else divided by the speed and floored (`Down`) or
  ceiled (`Up`); no answer when the source is not media, or with no map and no positive finite
  speed. `in_played_window(clip, media, t)`: the reflected tick s′ has `in ≤ s′ < in +
  source_read_by(clip, clip.duration)`. `speech_in_clip` calls the helper and keeps its signature
  and early guard: it passes each span unreflected, a forward clip's start `(a, Down)` and end
  `(b, Up)`, a reversed clip's start `(b, Down)` and end `(a, Up)`, so its answers do not change.
  `cursor_zoom_run.rs`'s `clip_time` is not routed through it (it reads past the clip's end,
  CU7/CU8). The planner's input `Subjects {samples: [{t, faces, people, salient}], shots: [t]}`
  is in media source ticks of the forward file, its boxes `{x, y, w, h, c}` 0…1 of the upright
  picture from its top-left (CJ-22, VR-10). Into clip time: a sample is kept when
  `in_played_window`, at clip tick `clip_time_of_source(…, Down)`; shots likewise, a cut at clip
  tick 0 or at or past the clip's duration dropped; then the kept samples, and separately the
  shots, are sorted ascending (a reversed clip's arrive descending), of samples sharing a clip
  tick only the earliest media tick's kept, duplicate shots collapsed — only then do the choice
  and the median see them. A box point (bx, by) is `u = (bx·mw − mw/2, by·mh − mh/2)` px from the
  UNCROPPED centre (`mw × mh` the media's displayed size) and lands on the source canvas at
  `anchor + s·u` ((★) at θ = 0, `anchor` and `s` the clip's base `video`); the crop moves only
  the picture's extent, the cropped rect `anchor + s·(c ± (cw/2, ch/2))`, so a crop never
  invalidates the cache. `plan_framing(project, clip, subjects, request, tuning)` answers no path
  for no such clip, a clip that is not a media clip of a video media, a base rotation other than
  0, a media with no size, a crop or scale that leaves no picture, a zoom outside 1…4 or a zero
  `from_width`/`from_height`; VR2a2's op refuses each by name before calling it. The path is F,
  the similarity from the source canvas (`from_width × from_height`, `Ws × Hs`) to the current
  canvas `W × H`, keys `(t, scale k, x dx, y dy, curve)` composed into a placement as `scale′ =
  k·scale, x′ = k·x + dx, y′ = k·y + dy` (VR-3, VR-27): `k = zoom · fill / s`, `fill` from
  `Project::fill_scale` over the cropped size, `k·s` at most `SCALE_MAX`; the window on the
  source canvas is `W/k × H/k` centred at `wc`, `dx = k·(Ws/2 − wc.x)`, `dy = k·(Hs/2 − wc.y)`;
  every key's `wc` is clamped so the window lies inside the cropped rect (VR-7's covering key).
  Keys are strictly increasing in time, the first at 0, each snapped with `time::snap_to_frame` at
  the canvas rate and inside `[0, clip.duration]`; between keys the segment ending at a key eases
  with that key's curve through `actions::ease`.
  **Amended 2026-11-03 (VR2a2, VR-26):** the op lands without `replace`, which joins with VR-27
  in VR2b; VR-24 (a) maps shots with `Round::Up`.
- **VR-21 — Choosing the subject** (`core/src/reframe_tracks.rs`, `choose_subject`; tracks built
  by the planner over what it reads, CJ-31, nothing stored). Per kind, a box links to the track
  whose last box is at most `LINK_GAP` (1 s) earlier with the highest IoU at least `LINK_IOU`
  (0.3), one box per track per sample, else starts a track; every cut ends every track. Track ids
  are 0, 1, 2… in creation order, samples in time order and within one faces, then people, then
  salient. A track's score at a sample is over the samples in `[t − 1 s, t + 1 s]` of the
  sample's shot: presence (the share of those samples where it has a box) × the median area (w·h)
  of its boxes there × centrality `1 − min(1, ‖centre − (0.5, 0.5)‖ / (0.5·√2))` of its box at
  the sample. With `follow` `subject`, a present face track outranks people and people outrank
  salient regions, which count only at samples with no face and no person; a person track whose
  box holds a face track's centre in at least `BODY_SHARE` (80 %) of their shared samples is that
  face's body — never its rival — and carries the subject while the face is absent (the face
  takes it back on its return). Within a tier the primary stays while present; a rival replaces
  it only after scoring at least `RIVAL_MARGIN` (1.25) × the primary at every sample for
  `RIVAL_HOLD` (2 s); with the primary absent, the best present track at once; with nothing
  present, nothing is chosen. A shot's first sample picks the best, with no hysteresis. `face`,
  `person` and `salient` read only their own kind. Ties go to the lower track id.
  **Amended 2026-11-03 by VR-24 (c):** with the primary absent the best present track is output
  as a stand-in (`lost`) and the primary kept for `LOSS_HOLD` (1 s), instead of replaced at once.
- **VR-22 — Composition** (first numbers; VR-S2's verdict below). With the window `w × h` on
  the source canvas: a face's centre on the window's vertical centre line, at `headroom × h` (0.38) from the
  window's top when `h > w`, else at the window's centre; a person (no face chosen): the box's
  horizontal centre on the centre line and its top `0.12 × h` from the window's top; a salient
  region: its centre at the window's centre. **Amended 2026-11-02 by VR-S2's verdict (VR-23):**
  the headroom stays 0.38. The canned run could not measure it — at zoom 1 a 9:16 window on a
  16:9 picture is the picture's full height, so its centre's y is held at the picture's and every
  headroom contained the same samples — and the rule's tie went to the default's value. The
  person's 12 % was not in the grid and stands.
- **VR-23 — Moves** (first numbers, until VR-S2's verdict below: dead zone 0.10 of the window's
  width and 0.08 of its height, speed 0.5 windows a second; `FRAMING_TUNING` in `reframe.rs`).
  The subject point (a face's or a salient region's centre, a person box's top centre) is median-filtered per axis
  over the samples within ±0.5 s with the same chosen kind in the same shot, and the desired
  window centre is VR-22's from the filtered point, clamped. The first key, at 0, is the first
  chosen sample's desired centre (the cropped picture's centre when nothing is chosen anywhere).
  A move starts at a sample when the desired centre is beyond `dead_zone_width × w` or
  `dead_zone_height × h` of the current one; it targets that centre and lasts `max(0.4 s,
  distance ÷ (speed × w))` (Euclidean, source-canvas px); it is written as a hold key at its start
  (`linear`, the current value) and an `ease_in_out` key at its end. No move starts while one
  runs, nor within 0.5 s of the last one's end unless the filtered point is outside the current
  window. Snapped: a hold key whose tick is at or before the previous key's is not written (the
  move eases from that key); a move's end is at least one frame after its start; a move whose end
  would pass the clip's end is not started. With no chosen subject the window holds (VR2a2's
  VR-24 replaces this rule with loss, hard cuts and two people). **VR-S2's run and rule, fixed
  before it runs:** six canned inputs, each a 1080 × 1920 target at 30 fps from a 1920 × 1080
  source (the clip at scale 1, x = y = 0, no crop, forward ×1) at zoom 1 (the window 607.5 ×
  1080 source px, its centre's x clamped to 303.75…1616.25), samples every 100 ms, a face box
  0.08 × 0.14 of the picture at confidence 0.9, no randomness: (a) pan, 20 s, the face centre
  linear from x = 400 to 1520 px at y = 432; (b) exit, 10 s, still at (960, 432) for 4 s, absent
  2 s, back at (1100, 432) for 4 s; (c) two faces, 20 s, at x = 760 and 1160 for 10 s then 260 and
  1660 for 10 s, the left box 1.2 × the right's area; (d) still, 60 s, at (960, 432) with
  `x += 0.005·W·sin(7.3·t)`, `y += 0.005·H·cos(5.1·t)` (t in s); (e) cuts, 30 s, shots at frames
  300 and 600, the face still at x = 0.3, 0.7 then 0.5 of the width, y = 432; (f) card, 20 s, no
  boxes and no shots — 160 s in all. The grid: dead zone {0.06, 0.10, 0.15} of the width (the
  height's 0.8 × it) × speed {0.3, 0.5, 0.8} × headroom {0.33, 0.38, 0.42}. Per setting, pooled
  over the inputs: containment is the share of every sample where a face is chosen whose face
  centre lies inside the window's central 60 % in both axes at the path's value there; moves per
  minute is every move ÷ the 160 s. The rule: the highest containment at no more than 6 moves a
  minute, ties to fewer moves, then to (0.10, 0.5, 0.38); if no setting is at 6 or under, or that
  winner is under 97 %, the dead zone is fixed one step below the winner's (0.06 stays; with no
  winner, below 0.10) and the choice re-made among that dead zone's settings at no more than 8
  moves a minute, its containment recorded whatever it is; if none of them is at 8 or under, the
  verdict is STOP — recorded, `FRAMING_TUNING` left at the first numbers, and put to the owner.
  S-TH1, T1 and T2 do not exist yet: their rows are skipped by name and owed. **Amended
  2026-11-02 by VR-S2's verdict:** macOS 26.5.1 (25F80), Apple M2 Max, on AC power, three lanes
  on the machine; `rule_sha256` `f55e33e6…13cce3870e7`, matching CJ0a's table. The first arm:
  dead zone 0.15 of the window's width and 0.12 of its height, speed 0.8 window widths a second,
  headroom 0.38 — containment 1,358 of 1,380 counted samples (98.41 %), 15 moves in 160 s (5.62 a
  minute); `FRAMING_TUNING` is these. Containment moved only with the speed (0.3: 95.94 %, 0.5:
  97.46 %, 0.8: 98.41 %) and moves only with the dead zone (0.06: 25, 0.10: 21, 0.15: 15); the
  headroom moved neither (VR-22's amendment). The rule's last tie-break, "then to (0.10, 0.5,
  0.38)", did not say what a tie without that setting goes to; it goes to the tied setting
  sharing the most of its values, so 0.38 over 0.33 and 0.42 (the first run broke the tie by grid
  order and printed 0.33; the instrument was corrected and run again before this entry). The
  verdict's inputs: pan 200 of 200 contained, 11 moves; exit 80 of 80, 1; two faces 194 of 200, 1;
  still 600 of 600, 0; cuts 284 of 300, 2; card none counted, 0 (`VR-S2/results.json`,
  `rule_matches: true`). S-TH1's and T1's and T2's rows are owed; JOB-31 judges the feel.
  **Noted at CJ7b (the owner, 2026-11-06), not an amendment:** S-TH1's row ran at CJ7 (road map
  VR2a1's record) and stopped: the shipped (0.15, 0.8, 0.38) makes 8.45 moves a minute on S-TH1
  at 2,581/2,662 = 96.96 % contained, the grid's fewest is 8.04 at dead zone 0.15, and pooled with
  the six canned inputs the shipped setting makes 7.58 at 95.03 %. The owner: "Keep it; I'll judge
  it." The shipped setting stays, JOB-31 judges whether it is busy, and T1's and T2's rows stay
  owed.

## CJ6 — the clip ceiling (2026-11-02)

- **CJ-60 — CJ-S1's verdict: 4,096 kept.** No N in the bench passes CJ-S1's rule, so `MAX_CLIPS`
  and `RC_MAX_CLIPS` stay 4,096, CJ-9 keeps its first arm, and CJ6 ends with this verdict and no
  code: TX and SW design around the ceiling, reading `RC_MAX_CLIPS`.
  - **The run.** `tools/proof/creator_spike/ceiling_spike.py` (`rule_sha256`
    `e4ead1af…3c772d12e2f5`, matching CJ0a's table) against a scratch Release build with both caps
    at 65,536, never committed; macOS 26.5.1 (25F80), Apple M2 Max, 96 GiB (103,079,215,104 bytes),
    on AC, three lanes on the machine (one-minute load average 127.64 at the end). N one-second
    clips of the 1080p fixture over four tracks, `--headroom 0`. Every timed split answered
    applied (each MCP split added exactly 4 clips, the 50 of row (8) 200), and row (7)'s zoom
    assertions held in every sample.
  - **The figures** (medians; (4)–(6) over 3 runs), N = 4,096 · 8,192 · 16,384 · 32,768, the
    rule's bound in brackets:
    (1) split 2.7 · 5.3 · 30.2 · 42.4 ms [50];
    (2) open + plan 34.6 · 75.7 · 258.0 · 393.3 ms [500];
    (3) recipe 0.8 · 1.6 · 4.6 · 8.3 ms [2];
    (4) `ripple_delete_ranges` of 100 ranges 3,664 · 10,088 · 32,145 · 175,965 ms [1,000], its
    undo 56 · 110 · 230 · 598 ms [1,000];
    (5) the next `get_project` 164 · 265 · 996 · 2,117 ms [1,000];
    (6) the first frame after a split at most 0.9 · 1.0 · 2.4 · 2.6 s [2];
    (7) the timeline at the fit zoom 281 · 491 · 902 · 1,085 ms and at the default zoom 126 ·
    133 · 150 · 206 ms [33];
    (8) RSS growth over 50 splits 0.41 · 1.95 · 3.67 · 6.21 GB [6.44, a sixteenth of physical].
  - **What holds 4,096 down.** At N = 4,096 three rows fail: (4) at 3.7 s and (7) at both zooms.
    (7)'s time is the draw (`cacheDisplay`): 268 of 281 ms at fit and 116 of 126 ms at the
    default zoom, the view made, laid out and updated in under 12 ms. A smoke run at N = 512
    already drew in 94 ms (fit) and 123 ms (default), so the default zoom's cost is not the
    clip count's. (4) at 512 clips took 357 ms. Neither is CJ6's to speed up; both are filed.
  - **A discarded first run.** The instrument's first full run gave the same verdict (at 4,096,
    (4) 4.0 s, (7) 395 and 161 ms), but at 32,768 two of its three row-(6) splits answered an
    identity: an autosave in place during a three-minute ripple had written the last run's split
    into the package. The script now writes the package's own `project.json` back before every
    reopen; the recorded run is the second.
  - **What a raise would have needed** (recorded for a later ceiling): `TranscribeSheetController
    .refresh()`'s tick sum over clips does not saturate, so the bound in `Transcriber+Jobs.swift`
    leans on 4,096 × 10¹⁵ < 2⁶³; `shot_split_proof.py`, `transcript_cut_proof.py` and
    `cloud_captions_probe.py` spell the ceiling as a literal; five core tests spell 4,095–4,098.
