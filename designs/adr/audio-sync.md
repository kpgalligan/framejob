# Audio sync: lining clips up by their sound (road map "audio-sync")

- **Status:** Built and closed 2026-10-15. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-audio-sync` on branch `audio-sync`:
  - AS-1, Clip ▸ Synchronize Audio and `sync_audio`: the onset match, the anchor rule, frame-snapped placement, drift measured and reported (SY-1..SY-5) (`d92e1d3`)
  - AS-2, drift corrected by `set_speed` at varispeed, the rate band, the corrected span, `recording_probe.py`'s 7b rows, and the close (SY-6..SY-10) (the commit that moved this record to `archive/`)
- **Original:** `archive/audio-sync.md` is the full record. It has no section numbers, so it is cited by section title: "orig AS-2 record" is its "AS-2 — the record" section.
- **Spec decisions:** SY-1..SY-10 in spec §11 (`designs/spec/11-decisions/audio-sync.md`). They stay binding, and where the original words them differently, §11's text wins:
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

## Context

The owner asked (2026-10-15) for selected clips with audio to be synced. Asked how, the owner answered:
1. frame-snapped is fine;
2. the clip with video stays and the audio moves ("a separate audio track synced to video is my plan");
3. report drift first, though correction would "almost certainly" be needed immediately.

AS-1 shipped the match and measured drift. AS-2 followed straight after and corrected it. (orig "The owner's answers")

## Decisions

- **Onsets, not levels.** Two recordings of one event differ in gain, microphone, room and noise, so the levels are not compared. What is compared is where the sound RISES: the dB rise per 10 ms bucket, mean-free. (orig "AS-1 — the plan"; SY-3)
- **A composite on the peaks cache, as Normalize is.** The core only moves clips and sets speed; Swift measures. No op, FFI, format or tool argument changed in either phase. (SY-1)
- **The thresholds held on AS-1's fixtures.** The recorder against the camera read r 0.493, q 3.06. The +200 ppm recorder read r 0.307, q 1.82, the closest to the thresholds. An unrelated recording read r 0.14, q 1.10 and was refused. (orig AS-1 record; SY-3)
- **The correction is an existing op at an exact rate.** `set_speed` stores the rate as an f64, and the plan plays integer ticks over integer ticks. `rate_stretch` was rejected: its frame-snapped end is about 555 ppm on a 60 s clip. `keep_pitch: false` resamples with no phase vocoder. (SY-6)
- **The pivot is the clip's in point.** `set_speed` keeps the clip's start and in point, so the offset is recomputed: the mover is in sync along the whole fitted line, not only at the overlap's centre. A drift left uncorrected is placed by the line at the overlap's centre. (SY-6)
- **A line through many windows.** AS-1's two windows measured the +200 ppm fixture at 172.2 ppm. The line through many windows measured 197.358 ppm. The uncertainty is widened by √(2000/step) because the windows overlap, which is the adversary's objection 2. (orig AS-2 record; SY-7)
- **The significance test replaced a 2 ms cap on the uncertainty.** Under the cap, S10's 29.60 ms drift, uncertain by ±2.134 ms, was left uncorrected; it is 13.9× its own uncertainty. The phase stopped under SY-7's calibration rule, and the owner chose correction when the drift is at least max(5 ms, 3× its uncertainty). (orig AS-2 record, "The STOP and the owner's decision"; SY-8)
- **The final span is checked, and the op order keeps every intermediate span inside the old or final one.** `move_clip` and `set_speed` would each turn an overlap within the overlap rule into a dissolve rather than refuse it. (SY-4, SY-10)

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

**Headline numbers** (Release, 2026-10-15).

| Measure | Bound | Measured | Command |
|---|---|---|---|
| S1: the recorder's placement | frame 206 exactly | frame 206, offset −1,881,359 ticks against −1,879,987.5 (2.3 ms) | `RC_PROOF_APP=release audio_sync_proof.py <sock>` |
| S10: the +200 ppm fixture corrected | `\|s·k − 1\|·150,000` ≤ 2 ms | 197.358 ppm, 29.60 ms ±2.13 ms → ×0.99980264, 0.39 ms | same |
| S17: re-measured after correction | `\|drift_ms\|` ≤ 2, no op | 1.24 ppm, 0.19 ms, "already in sync" | same |
| S18: the exported mix's lag across 136 s | `\|Δ\|` ≤ 3 ms; the ×1 control ≥ 20 ms | Δ −0.33 ms; control Δ −26.49 ms | same |
| P5: drift on smooth arrays | ±5 ppm | 199.88 / −150.08 / 0.01 / 100.39 for 199.96 / −150.02 / 0 / 99.99 | `audio_sync_proof.py --only P5` |
| P7: the correction at ±1,000 ppm | rate within 5 ppm of 1/k | 0.3 ppm and 1.5 ppm | `audio_sync_proof.py --only P7` |

## Known limits

- **Frame-snapped placement.** After correction, one constant offset of up to half a frame remains (SY-4, the owner's answer 1).
- **The export's audio offsets (#298).** A ×1 clip is late in an `audio_wav` export: +25.7 ms for a WAV, +37.9 ms for a camera `.mov`. A near-×1 varispeed clip is about 2–3 ms early. The measured gap between the two paths is about 28 ms, on the same 16 kHz WAV at ×1 and at varispeed; against this fixture's camera, an ffmpeg-muxed `.mov` with PCM audio, a corrected recorder exports about 40 ms ahead, a figure not confirmed for real camera files. The preview was not measured.
- **Keep pitch at a near-×1 rate (#299).** Synchronize Audio never uses it.
- **A large drift can defeat the coarse match (#300).** 1,000 ppm over 160 s was refused at r 0.26, q 1.27.
- **Synthetic fixtures only.** Real footage is SE-10's.
- **The anchor is never corrected, and neighbours are never moved or trimmed** (SY-4, SY-10).

## Open items

Filed at AS-2's close, each `ai-drafted` and `low-priority`:
- #298: the export's per-path audio offsets.
- #299: Speed with Keep pitch at ×0.99999 stops matching its source in the export.
- #300: a large drift over a long take can defeat the coarse match.

Not filed, each decided by the spec: a PCM-level refinement, a drift readout in the menu or the inspector, correcting the anchor, moving neighbours (AS-2's "Out of scope").

## Where to look in the original

- "The owner's answers": the request and the three answers, verbatim.
- "AS-1 — the plan" and "AS-1 — the record": the files, the three refusal sentences the implementation wrote, the probe and MCP readings, the mutants, and the review fix pass (silence on the silent clip alone; ×N read from the time-scaled segment).
- "AS-2 — the plan" and "AS-2 — the record": what landed, the STOP and the owner's decision, the deviations (the closed band, P7's fixture), every probe and Release reading, the gate, the mutants, the export offsets found on the way, and the review fix pass (the catalog's significance wording; a ×1 clip with a time-scaled segment refused again).
- "Owed": the issues filed at the close.
