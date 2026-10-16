# Audio sync: lining clips up by their sound (road maps "audio-sync" and "audio-sync-2")

- **Status:** Built and closed 2026-10-15. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-audio-sync` on branch `audio-sync`:
  - AS-1, Clip ▸ Synchronize Audio and `sync_audio`: the onset match, the anchor rule, frame-snapped placement, drift measured and reported (SY-1..SY-5) (`d92e1d3`)
  - AS-2, drift corrected by `set_speed` at varispeed, the rate band, the corrected span, `recording_probe.py`'s 7b rows, and the close (SY-6..SY-10) (the commit that moved this record to `archive/`)
- **Round 2 status:** Built and closed 2026-10-16, worked in `~/devel/framejob-sync2` on branch `sync-2`, one litecode pipeline per phase:
  - AS-3, the MFCC feature match, the played windows first, candidates and the refusal naming them, the head trim, speech-only matching, the confident and weak tiers and the Weak match sheet (SY-11..SY-19) (`a794639`)
  - AS-4, the GCC-PHAT refinement, drift on the features with a robust line, the plan off the main thread under the Synchronizing Audio sheet, #300's re-test, and the round's close (SY-20..SY-22) (the commit that moved round 2's record to `archive/`)
- **Original:** `archive/audio-sync.md` is round 1's full record and `archive/audio-sync-2.md` round 2's. Neither has section numbers, so each is cited by section title: "orig AS-2 record" is the first's "AS-2 — the record" section, "orig-2 AS-4 record" the second's "AS-4 — the record".
- **Spec decisions:** SY-1..SY-22 in spec §11 (`designs/spec/11-decisions/audio-sync.md`). They stay binding, and where the originals word them differently, §11's text wins:
  - SY-1: a composite, not an op. One anchor stays, every other clip moves (and, since SY-6, may change speed), all or nothing, one undo step, "already in sync" when no op is needed; no `scope`.
  - SY-2: the anchor is the named clip, else among clips with pictures (all of them when none has) the earliest start, then the rearmost track, then the lowest id.
  - SY-3: the match. Onset envelopes of the whole peaks files, a normalised FFT cross-correlation and parabolic refinement; it needs r ≥ 0.25 and a peak ratio ≥ 1.5 over the runner-up outside ±0.5 s. Files under 2 s are refused.
  - SY-4: placement is `snapToFrame(zeroA − zeroN + round(lag·6000))`. These are refused before the core sees them: before 0, never meeting the anchor, two clips on one track, an own-track neighbour.
  - SY-5: drift is measured over ≥ 60 s of overlap. Its two-window method is superseded by SY-7; its minimum stays.
  - SY-6: the correction is `set_speed {rate, keep_pitch: false}` (an exact f64 rate, AVFoundation's varispeed). Onsets are resampled to each clip's timeline grid. `s' = s·(1 − ρ)` and `δ = snapToFrame(round(zeroA + 6000·c/(1 − ρ) − S + I/s'))`.
  - SY-7: drift is an OLS line through windows of 2,000 buckets at a step of `max(500, ⌈(|O| − 2000)/63⌉)` (≤ 64 windows). The uncertainty is the slope's s.e. × √(2000/step). It is not measured from under 3 windows, or from windows whose centres span under half the overlap. The rule also sets the tolerances and the calibration rule.
  - SY-8: the significance test, the owner's choice of 2026-10-15. A drift is corrected when `|drift_ms| ≥ max(5, 3 × drift_error_ms)` and the new speed stays in the band; otherwise it is left with a sentence. The rule also lists the answer's keys.
  - SY-9: a clip within 0.2% of ×1 is matched at its rate; outside it, or reversed, or at speed ×1 with a time-scaled segment, it is refused. A corrected mover re-syncs as "already in sync".
  - SY-10: the corrected duration is `max(snapToFrame(round(round(d·s)/s')), one frame)`. The final-span checks apply. When the clip grows, `move_clip` runs before `set_speed`; otherwise `set_speed` runs first.
  - Amended: SY-1 and SY-5 by SY-6; SY-4 by SY-9 and SY-10; SY-5 by SY-7.
  - SY-11: the `cache/sync/` cache — 26 MFCCs per 16 ms of 8 kHz mono (BBC `audio-offset-finder`'s parameters), and since AS-4 the int16 samples beside them (`.pcm`, version 2); written in one publish after a completed read; one retry inside `retryPeaks`.
  - SY-12: the coarse match on features (supersedes SY-3's): standardised per coefficient, the correlation summed over coefficients, z over every lag, candidates only at ≥ 125 frames of overlap.
  - SY-13: the played windows are searched first, the whole files only when that chooses nothing — for the owner's competing stretch at −41.92 s.
  - SY-14: candidates (local maxima > 60 frames apart, ≤ 4) and the near placement (within 188 frames); the refusal names each search's candidates; its calibration stop.
  - SY-15: the synthetic pair with the owner's traits (S19) and the owner's own files as rows S20/S21, a scored FAIL when absent.
  - SY-16: the head trim, the owner's choice: a mover that would start before 0 loses that much of its head.
  - SY-17: speech-only matching on the cached Silero VAD when both stretches hold ≥ 125 speech frames.
  - SY-18: the confident (z ≥ 10, 1.5 above the next) and weak (the near placement at z ≥ 4) tiers; a weak match is never applied silently.
  - SY-19: the Weak match sheet and `accept_weak`, the owner's "Ask, then apply".
  - SY-20: the GCC-PHAT refinement: over the overlap's centre 30 s, along the drift line (else the coarse lag), 300–3,400 Hz, the peak within ±384 samples clear at z ≥ 15 (calibrated from 8), else the coarse offset; the tier untouched; `coarse_offset`, `refined`, `refine_confidence`.
  - SY-21: drift on the features (supersedes SY-5/SY-7's onsets): 1,250-frame windows searched ±62 frames against a mover slice ±62 wider, kept at z ≥ 6, a Theil–Sen + MAD inlier filter (k 3, fixed), SY-7's count and span rules, an OLS line; then each window refined by PHAT and refitted (`drift_on` "phat"); c in samples.
  - SY-22: ≤ 1.5 s of CPU for a one-hour pair on Release; one shared FFT setup per plan; `plan` off the main thread under the Synchronizing Audio sheet and in `sync_audio`, applied only to the project and scope `read` took; the dev hold `-RCDevSyncHold`.
  - Amended in round 2: SY-1 by SY-11, SY-20 and SY-21; SY-3 by SY-12, SY-13 and SY-21; SY-4 and SY-10 by SY-16; SY-5, SY-6 and SY-7 by SY-21; SY-11 by SY-17 and SY-20; SY-14 by SY-17..SY-19; SY-15 by SY-18 and SY-19; SY-8 and SY-9 re-checked in AS-4, unchanged.

## Context

The owner asked (2026-10-15) for selected clips with audio to be synced. Asked how, the owner answered:
1. frame-snapped is fine;
2. the clip with video stays and the audio moves ("a separate audio track synced to video is my plan");
3. report drift first, though correction would "almost certainly" be needed immediately.

AS-1 shipped the match and measured drift. AS-2 followed straight after and corrected it. (orig "The owner's answers")

Round 2 began when the owner tried it on a real project and it refused: a phone camera clip and a separate Mac recorder (165 s, heavy low-frequency rumble, about 5 s of clear speech), the recorder trimmed near the speech. The owner asked for research first, and said "Go ahead" to all five points of the proposal: MFCC features, the played windows first, candidates instead of a flat refusal, GCC-PHAT on the PCM around the chosen offset, and a fixture from the owner's files. The owner then chose the head trim and, after AS-3's calibration stop, "Ask, then apply" for weak matches. (orig-2 "The owner's words", "The owner's case, measured")

## Decisions

- **Onsets, not levels.** Two recordings of one event differ in gain, microphone, room and noise, so the levels are not compared. What is compared is where the sound RISES: the dB rise per 10 ms bucket, mean-free. (orig "AS-1 — the plan"; SY-3)
- **A composite on the peaks cache, as Normalize is.** The core only moves clips and sets speed; Swift measures. No op, FFI, format or tool argument changed in either phase. (SY-1)
- **The thresholds held on AS-1's fixtures.** The recorder against the camera read r 0.493, q 3.06. The +200 ppm recorder read r 0.307, q 1.82, the closest to the thresholds. An unrelated recording read r 0.14, q 1.10 and was refused. (orig AS-1 record; SY-3)
- **The correction is an existing op at an exact rate.** `set_speed` stores the rate as an f64, and the plan plays integer ticks over integer ticks. `rate_stretch` was rejected: its frame-snapped end is about 555 ppm on a 60 s clip. `keep_pitch: false` resamples with no phase vocoder. (SY-6)
- **The pivot is the clip's in point.** `set_speed` keeps the clip's start and in point, so the offset is recomputed: the mover is in sync along the whole fitted line, not only at the overlap's centre. A drift left uncorrected is placed by the line at the overlap's centre. (SY-6)
- **A line through many windows.** AS-1's two windows measured the +200 ppm fixture at 172.2 ppm. The line through many windows measured 197.358 ppm. The uncertainty is widened by √(2000/step) because the windows overlap, which is the adversary's objection 2. (orig AS-2 record; SY-7)
- **The significance test replaced a 2 ms cap on the uncertainty.** Under the cap, S10's 29.60 ms drift, uncertain by ±2.134 ms, was left uncorrected; it is 13.9× its own uncertainty. The phase stopped under SY-7's calibration rule, and the owner chose correction when the drift is at least max(5 ms, 3× its uncertainty). (orig AS-2 record, "The STOP and the owner's decision"; SY-8)
- **The final span is checked, and the op order keeps every intermediate span inside the old or final one.** `move_clip` and `set_speed` would each turn an overlap within the overlap rule into a dissolve rather than refuse it. (SY-4, SY-10)
- **Round 2: standardised MFCCs summed over coefficients.** On the owner's trimmed windows the onset matcher refused (r 0.14), BBC's published norm across coefficients put the best lag at 110.1 s, and the summed correlation at 118.68 s (z 4.3) against the owner's ≈ 118.7 s. A landmark fingerprint found nothing usable. (orig-2 "The owner's case, measured"; SY-12)
- **The played windows first.** The owner's files share an unrelated stretch at −41.92 s that wins any whole-file search; what the user trimmed is evidence of what they mean. (SY-13)
- **Two tiers, and a weak match is asked about.** No constant or statistic tried separated the owner's true match (z 4.2) from unrelated sound placed where it overlaps (up to 4.6); speech-only matching lifted the owner's to 7.9, and the owner chose that a person decides below the confident 10. (orig-2 AS-3 record, the stop and its resolution; SY-17..SY-19)
- **PHAT refines, never finds.** It whitens every bin, so any shared burst can own its global peak (whole-file PHAT in the round's `pcm.py` was fooled); it is searched only within 48 ms of the coarse match, used only when clear, and never changes the tier. `clearZ` moved 8 → 15 when the owner's recorder reversed (a null) read 10.24. (orig-2 AS-4 record; SY-20)
- **Drift on the features, with a wider slice and a robust line.** Equal-length slices pulled each window toward the coarse lag (P7 986.6 ppm for 999); widening the mover's slice by the search radius fixed it. Windows partly in noise passed the z floor and bent the least-squares line (211.43 ppm for 199.96; the phase stopped); Theil–Sen + MAD inliers read 201.06, and k is fixed at 3. (orig-2 AS-4 record, the stop; SY-21)
- **The plan off the main thread.** S10's call took 7.43 s on Debug on the main thread; with one shared FFT setup a one-hour pair costs 0.793 s of CPU on Release, and the menu runs it under a sheet, applying the answer only to the project it read. (SY-22)

## What it built — where it lives now

- Swift:
  - `AudioSync.swift`: `read` and `plan`; the readings carry each clip's speed and in point.
  - `AudioSync+Correction.swift`: the decision, the band (`rateProblem`), `durationAtSpeed`, `correctedDelta`, the op order.
  - `AudioSyncMatch.swift`: onsets, the FFT cross-correlation, the confidence.
  - `AudioSyncDrift.swift`: the line fit and `resampled`.
  - `EditorViewController+Audio.swift`: Clip ▸ Synchronize Audio and its validator arm, plus Normalize, moved out of the frozen `EditorViewController.swift`.
  - `sync_audio`: in `AgentCatalog+Audio.swift` and `AgentServer+Audio.swift`.
  - Menus: the menu row, `UIMenuTable`'s row and the inventory's row.
  - The Assistant prompt's audio topic.
- Proofs: `tools/proof/audio_sync_proof.py` (S1–S18; S18 decodes two `audio_wav` exports with ffmpeg), `tools/proof/audio_sync_probe.swift` (P1–P8) and eighteen mutants. `recording_probe.py`'s 7b now reads the catalog's last twelve rows, with `set_media_color` among the media rows.
- Person check: SE-10 in `docs/manual-checks.md`.
- Round 2 (AS-3, AS-4):
  - `SyncFeatures.swift` (the extractor) and `MediaImporter+SyncFeatures.swift` (the cache's await-free half: `.bin`, `.pcm`, marker), with `syncFeatures` in `MediaImporter.swift` between `peaks` and `speech`.
  - `AudioSyncMatch.swift`: the feature search, the speech masks, the summed correlation (the onsets are gone). `AudioSync+Search.swift`: the played windows, the order, the choice, the refusal. `AudioSync+Weak.swift`: the weak tier's question and note.
  - `AudioSyncPHAT.swift`: the refinement and the shared FFT setup. `AudioSyncDrift.swift`: drift on the features, the robust filter and the PHAT refit.
  - `AudioSyncSheetController.swift` and `EditorViewController+Audio.swift`: the Synchronizing Audio sheet, the stale test, the Weak match sheet. `AgentServer+Audio.swift`: `sync_audio` off main, `accept_weak`, the answer's keys.
  - Proofs: `audio_sync_proof.py` S1–S26 (S19 the synthetic owner-like pair, S20/S21/S23/S24 the owner's files, S25/S26 a held instance), `audio_sync_probe.swift` P1–P19 (P19 behind `--cost`), thirty-nine mutants.
  - Person checks: SE-10 (updated), SE-11 (the Weak match sheet), SE-12 (the Synchronizing Audio sheet).

**Headline numbers** (Release, 2026-10-15).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| S1: the recorder's placement | frame 206 exactly | frame 206, offset −1,881,359 ticks against −1,879,987.5 (2.3 ms) | `RC_PROOF_APP=release audio_sync_proof.py <sock>` |
| S10: the +200 ppm fixture corrected | `\|s·k − 1\|·150,000` ≤ 2 ms | 197.358 ppm, 29.60 ms ±2.13 ms → ×0.99980264, 0.39 ms | same |
| S17: re-measured after correction | `\|drift_ms\|` ≤ 2, no op | 1.24 ppm, 0.19 ms, "already in sync" | same |
| S18: the exported mix's lag across 136 s | `\|Δ\|` ≤ 3 ms; the ×1 control ≥ 20 ms | Δ −0.33 ms; control Δ −26.49 ms | same |
| P5: drift on smooth arrays | ±5 ppm | 199.88 / −150.08 / 0.01 / 100.39 for 199.96 / −150.02 / 0 / 99.99 | `audio_sync_proof.py --only P5` |
| P7: the correction at ±1,000 ppm | rate within 5 ppm of 1/k | 0.3 ppm and 1.5 ppm | `audio_sync_proof.py --only P7` |

**Round 2's headline numbers** (Release, 2026-10-16, the AS-4 recorded run, 44/44).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| S1: the refined offset | `refined` "phat", within 600 ticks (1 ms) | −1,880,019 for −1,879,987.5 (31.5 ticks, 53 µs; coarse 841.5), PHAT z 434.2 | `RC_PROOF_APP=release audio_sync_proof.py <sock>` |
| S19: the owner-like pair | frame 36 exactly, refined within 1 ms | frame 36, 118.70005 s for 118.70 (coarse 118.6945), z 15.22 confident | same |
| S20/S21: the owner's files | T within 1/30 s of 118.68 | weak on speech at z 7.91 / 7.99, T 118.7000 s, unsnapped 118.6864 / 118.6853 s, `refined` "coarse" (PHAT z 8.84 / 8.06) | same |
| S10: the +200 ppm fixture | `\|s·k − 1\|·150,000` ≤ 2 ms | 199.920 ppm on phat over 28 windows, ±0.022 ms → ×0.99980008, 0.006 ms | same |
| S18: the exported mix's lag across 136 s | `\|Δ\|` ≤ 3 ms | Δ 0.10 ms; control −26.49 ms | same |
| P5: drift on features alone, the mover's frames 4,000–7,000 noise | ±5 ppm | 201.06 for 199.96 (OLS before the filter: 211.43) | `audio_sync_proof.py --only P5` |
| P18 (#300): ±1,000 ppm over 160 s | confident, rate within 5 ppm of 1/k | z 41.23 / 41.36, 0.1 ppm / 0.0 ppm | `audio_sync_proof.py --only P18` |
| P19: a one-hour pair, loads + `plan`, -O whole module | ≤ 1.5 s of CPU | 0.793 s (`plan` 0.731) | `audio_sync_proof.py --cost` |

## Known limits

- **Frame-snapped placement.** After correction, one constant offset of up to half a frame remains (SY-4, the owner's answer 1).
- **The export's audio offsets (#298) — fixed in its phase 2** (spec §11 SY-23..SY-27): a non-48 kHz source is read from a 48 kHz copy, varispeed and the noise reducer are led by their fixed delays, and keep pitch near ×1 plays `time_domain`. On Release (2026-10-16) the 16 kHz recorder exports at +0.04 ms (×1) and +0.09 ms (×0.99999 varispeed), where #298 reported +25.71 and −2.81; S18's corrected mix reads 0.70 ms early in the take and 0.85 ms late; every pinned path in `export_offset_proof.py` is within 1.0 ms. An MP3 source is +13.084 ms (its decoder delay, #306). The preview plays the same composition but its output is not measured (SE-13).
- **Keep pitch at a near-×1 rate (#299).** Synchronize Audio never uses it. Since #298's phase 2, keep pitch at 0.98–1.02 plays `time_domain` (×0.99999: +0.010 ms, spread 0.138); outside the band `.spectral` still smears (×0.9: +3.170 ms, spread 7.458), and #299 stays open for it.
- **A large drift can defeat the coarse match (#300)** — fixed in round 2: on the features ±1,000 ppm over 160 s matches confidently (P18), and #300 is closed.
- **Real footage: the owner's one pair, otherwise synthetic.** The owner's camera and recorder are rows S20, S21, S23 and S24 (gitignored, never committed); every other fixture is generated. Their offset has no 1 ms ground truth, and PHAT cannot refine it (#303). Real footage at large is SE-10's.
- **The owner's files keep the coarse offset (#303)**; the refinement reads only the overlap's centre 30 s (#302); features-only drift loses about 20 ppm when a 120 s take's last third is unrelated sound (#304); a file under 64 ms reads "still being analysed" for good (#301).
- **A weak match needs a person** (SY-18, SY-19): the owner's own case is weak, so it is asked about every time.
- **The anchor is never corrected, and neighbours are never moved or trimmed** (SY-4, SY-10).

## Open items

Filed at AS-2's close, each `ai-drafted` and `low-priority`:
- #298: the export's per-path audio offsets (closed by its phase 2, SY-23..SY-27).
- #299: Speed with Keep pitch at ×0.99999 stops matching its source in the export.
- #300: a large drift over a long take can defeat the coarse match.

Not filed, each decided by the spec: a PCM-level refinement, a drift readout in the menu or the inspector, correcting the anchor, moving neighbours (AS-2's "Out of scope").

Round 2: #300 closed at AS-4 (P18). Filed at AS-4's close, each `ai-drafted` and `low-priority`:
- #301: a file with sound but under 64 ms reads "still being analysed" for good.
- #302: the PHAT refinement reads only the overlap's centre 30 s.
- #303: the owner's files are not refined (PHAT z 8–9 under `clearZ` 15).
- #304: features-only drift loses about 20 ppm when the last third of a 120 s take is unrelated sound.

#298 and #299 stayed open; neither was round 2's. #298's phase 2 closed #298 (SY-23..SY-27) and filed #306 (an MP3 source's decoder delay); #299 stays open for keep pitch outside 0.98–1.02.

## Where to look in the original

- "The owner's answers": the request and the three answers, verbatim.
- "AS-1 — the plan" and "AS-1 — the record": the files, the three refusal sentences the implementation wrote, the probe and MCP readings, the mutants, and the review fix pass (silence on the silent clip alone; ×N read from the time-scaled segment).
- "AS-2 — the plan" and "AS-2 — the record": what landed, the STOP and the owner's decision, the deviations (the closed band, P7's fixture), every probe and Release reading, the gate, the mutants, the export offsets found on the way, and the review fix pass (the catalog's significance wording; a ×1 clip with a time-scaled segment refused again).
- "Owed": the issues filed at the close.

In `archive/audio-sync-2.md` (round 2):
- "The owner's words", "The owner's case, measured", "Research", "What the owner approved": the request, the owner's files and ground truth, the methods table, the five points.
- "AS-3 — the record": what landed, the extractor against its numpy reference, every calibration z, the calibration stop and its statistics table and sweeps, S19's moved fixture, the owner's choice ("Ask, then apply"), the designer's speech-mask measurement, the fix passes and their recorded runs, the time to ready.
- "AS-4 — the record": what landed, the stop (the slice's envelope, P5's noise case) and the ruling, the `clearZ` calibration table, the owner's offset, SY-21's numbers, #300's P18, SY-22's budget, the Debug and recorded runs, the issues filed.
