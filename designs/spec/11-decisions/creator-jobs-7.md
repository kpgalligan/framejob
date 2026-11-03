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
