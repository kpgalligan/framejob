# Spec §11 — decisions: Audio sync (road map "audio-sync")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed (2026-10-15): its condensed record is
`designs/adr/audio-sync.md`, the original `archive/audio-sync.md` (AS-1 lines clips up and measures
drift, AS-2 corrects it). SY-1…SY-5 were recorded in AS-1, before its code, from the owner's three
answers of 2026-10-15 (quoted verbatim in the road map): placement frame-snapped; the clip with
video stays and the audio moves; drift reported first, correction straight after. SY-6…SY-10 were
recorded in AS-2 before its code; SY-8 was amended by the owner's choice after AS-2's STOP.

**Stands, and nothing here re-litigates it:** the overlap rule and `move_clip` (foundations,
spec §6); D2-1 (a composite that measures nothing makes no op and says why); #42's one-delta
shifts on the frame grid; `AudioNormalize`'s posture (peaks in, ops out; a missing peaks file is
never silence; the menu and the tool call the same `read` + `plan`).

- **SY-1 — Synchronize Audio is a composite, all or nothing, one undo step.** Clip ▸ Synchronize
  Audio and the tool `sync_audio {clips, anchor?}` line up two or more selected clips that play
  sound by their sound: one ANCHOR stays and every other clip moves along its own track by one
  `move_clip {clips: [id], delta}`, the whole list applied as ONE undo step ("Synchronize
  Audio"). There is no new op, no FFI and no format change: Swift measures the cached waveforms
  (`cache/peaks/<media id>.bin`, 1/100 s of source a bucket) and the core only moves clips. It is
  all or nothing: when any clip cannot be matched or placed, nothing moves and every reason is
  named at once — in the tool's error, and at the inspector's foot (CI-10) after a beep for the
  menu. A selection already in sync is no op: the tool answers `moved: false` and "already in
  sync", the menu beeps. A tool with no `scope` argument; it reads the open container's plan
  (`editedProject`), as `normalize_clip` does. AS-2 corrects drift; AS-1 only measures it
  (SY-5).

- **SY-2 — The anchor.** A caller may name `anchor`, which must be one of `clips` (refused by
  name otherwise). Without one: among the clips that have pictures — a video segment of positive
  duration in the plan — the earliest start, then the rearmost track (lowest index), then the
  lowest id; when none has pictures, the same order over all of them. The owner's use case is a
  camera clip and a separate recorder: the camera stays and the recorder moves. The menu always
  takes this rule; only the tool can name an anchor.

- **SY-3 — The match and its confidence.** Each file's whole peaks array (not the played window)
  becomes an onset envelope: `e = 20·log10(max(p, 1e-5))`, the rise `max(0, e[n] − e[n−1])` (0
  for the first bucket), the mean taken off. Two envelopes are compared by full cross-correlation
  over every lag (zero-padded FFT, `vDSP_fft_zrip`), each lag normalised by the energies of the
  two stretches that overlap there; a lag overlapping less than 1,000 buckets (10 s), or the
  shorter file when it is shorter, is not scored. The peak is refined parabolically (±0.5
  bucket). Its confidence is the peak's correlation r and the ratio q of r to the best scored lag
  more than 50 buckets (0.5 s) from it, that runner-up floored at 0 (so a runner-up ≤ 0 is q =
  +∞). A match is used when r ≥ 0.25 and q ≥ 1.5; with no scored lag outside ±50 there is no
  runner-up and the match is not confident ("too little room to compare its sound"); otherwise
  it is refused "no matching sound found between clip A and clip N (correlation r, peak ratio q;
  needs ≥ 0.25 and ≥ 1.5)". A file under 200 buckets (2 s) is too short to match. **Calibration
  rule:** when a proof's fixtures are misclassified at 0.25 and 1.5 the constants change, and the
  printed r and q are recorded in the road map and here. AS-1's fixtures were not
  misclassified: the delayed, filtered, noisy recorder against its camera read r 0.49, q 3.06
  (S1, Debug and Release, 2026-10-15), the same recorder drifting +200 ppm r 0.31, q 1.82 (S10,
  Release), and an unrelated recording r 0.14, q 1.10 (S3).

- **SY-4 — Placement on the frame grid, and what is refused before the core sees it.** `lag` is
  the anchor's bucket minus the mover's bucket of the same sound; the mover's `delta` is
  `snapToFrame(zeroA − zeroN + round(lag·6000))`, where a clip's zero is the project tick its
  file's source tick 0 would play at (`segment.start − segment.sourceIn`). Placement is
  frame-snapped (the owner's answer 1); the model stores no sub-frame time. Refused, each by name
  and before any op: a clip that is not a clip, a nest (its sound is its inner clips'), one that
  plays no sound (no audio segment: no media, no audio track, audio switched off, a still), one
  playing at a speed other than ×1 or time-scaled, one reversed, one whose waveform is still
  being analysed ("Try again in a moment"); fewer than two such clips; two of them on one track;
  a mover that would have to start before 0; a mover whose played window `[start + delta, end +
  delta)` would not meet the anchor's; and, when delta ≠ 0, a mover that would overlap another
  clip on its own track ("would overlap clip M on its track") — because `move_clip` clamps the
  earliest clip at 0 and turns an overlap within the overlap rule into a cross dissolve rather
  than refusing, neither of which is a sync. The core's own refusals stay the backstop. Moving or
  trimming a neighbour to make room is not done.

- **SY-5 — Drift is measured and reported by the tool only.** Over the overlap of the anchor and
  the placed mover (in anchor-source buckets), when it is at least 6,000 buckets (60 s): the
  same normalised correlation over a 2,000-bucket window at each end, each searched ±100
  buckets around the match's lag and refined parabolically, each needing r ≥ 0.25; rate =
  (lag₂ − lag₁) / (the windows' distance apart), reported as `drift_ppm` (rate·10⁶) and
  `drift_ms` (rate × the overlap, in ms). Otherwise `drift_ppm` and `drift_ms` are null with a
  `drift_note` sentence. The menu shows no drift in AS-1. **Minimum-overlap rule:** when the
  probe's 100 ppm stretch at exactly the minimum overlap misses ±50 ppm, the minimum rises until
  it holds and each value tried is recorded here. At 6,000 it held: 100.4 ppm measured for
  100.0 asked (P5, 2026-10-15). AS-1's drift fixture (a recorder resampled by +200 ppm, so
  199.96 ppm in this sign) measured 172.2 ppm over 150 s (S10, Debug and Release), and the
  undrifted recorder −14.6 ppm (S1).

- **SY-6 — Correction is `set_speed {clip, rate, keep_pitch: false}`; no new op (amends SY-1,
  SY-5).** AS-2 corrects each mover's clock drift with the existing op. **Why it is exact:** the
  model stores `speed` as an f64 (JSON round-trips it); the plan's segment is `source_duration =
  round(duration·speed)` over `duration`, integer ticks at 600,000/s, so the played rate is exact
  to one tick per clip length (0.03 ppm on 60 s), and `CompositionBuilder.fill` scales it with
  `scaleTimeRange` at that ratio. `rate_stretch` is not used: it derives the rate from a
  frame-snapped end (about 555 ppm on a 60 s clip). **Pitch:** `keep_pitch: false` is the plan's
  `pitch: "off"`, AVFoundation's `.varispeed` — a resample (≤ 2,000 ppm is ≤ 3.5 cents) with
  none of `.spectral`'s phase-vocoder processing; `AUDIO_SPEED_MAX` and `SpeedAudioDrop` never
  apply at ≤ ×1.002. **The pivot:** each reading's onsets are resampled to its timeline grid
  (`AudioSyncMatch.resampled`: bucket k is source bucket k·speed, linearly interpolated); the
  fitted line (SY-7) is `lag(a) = c + ρ·a`, a an anchor bucket and lag the anchor's bucket minus
  the mover's; the new speed is `s' = s·(1 − ρ)`. `set_speed` keeps `start` S and `in` I, so
  source tick μ then plays at `S + δ + (μ − I)/s'`, which is exact along the whole line when `δ =
  snapToFrame(round(zeroA + 6000·c/(1 − ρ) − S + I/s'))`. Snapping leaves one constant offset of
  at most half a frame (SY-4). A drift measured but not corrected places the mover by the line's
  value at the overlap's centre bucket aMid: `lag = c + ρ·aMid`, `δ = snapToFrame(zeroA − zeroN +
  round(lag·6000))`; a drift not measured places it by AS-1's coarse lag. The menu shows nothing
  new; the inspector shows the speed the correction wrote.

- **SY-7 — Drift is a least-squares line through many windows (supersedes SY-5's two windows;
  SY-5's 6,000-bucket minimum stays).** Windows of 2,000 buckets start at the overlap's start
  every `max(500, ⌈(|O| − 2000)/63⌉)` buckets, plus one flush with its end (at most 64); each is
  searched ±100 buckets around the coarse lag, refined parabolically and kept when r ≥ 0.25. The
  lags are fitted by ordinary least squares against each window's centre: ρ is the slope, c the
  intercept, and `errorMilliseconds` is the slope's standard error × √(2000 / step) × |O| × 10 —
  the factor counts windows that share buckets as no more independent data than they are, and
  applies whenever the step is under 2,000. It is not measured unless at least 3 windows matched
  ("only N of the overlap's windows matched; drift needs at least 3.") and their centres span at
  least (|O| − 2000)/2 ("the windows that matched cover too little of the overlap to measure
  drift."); the count is checked first. `ppm = ρ·10⁶`, `milliseconds = ρ·|O|·10` (SY-5's
  units). **Tolerance:** the probe's smooth arrays within ±5 ppm, including at the 6,000-bucket
  minimum (P5); the drift fixture's applied speed within 2 ms over its 150 s overlap (`|s·k − 1|
  · 150,000 ≤ 2`, S10); the re-measured residual `|drift_ms| ≤ 2` (S17); the exported mix's lag
  changing by at most 3 ms across the overlap (S18). **Calibration rule:** if S10 misses — its
  2 ms bound, or the drift left as uncertain — the phase stops and reports the run's numbers;
  the step is not changed and the tolerance is not loosened.

- **SY-8 — When a drift is corrected, and what the answer says.** A measured drift is corrected
  when `|drift_ms| ≥ max(5, 3 × drift_error_ms)` and the new speed stays in SY-9's band. In this
  order: `|milliseconds| < 5` is left as too small to matter ("a drift of X ms over the overlap is
  under the 5 ms Synchronize Audio corrects."); `|milliseconds| < 3 × errorMilliseconds` is left
  as not distinguishable from its uncertainty ("a drift of X ms over the overlap is under 3 times
  its uncertainty (±Y ms), so it cannot be told from no drift."); a new speed `s·(1 − ρ)` more
  than 0.002 from 1 is left as outside the band ("correcting it would play the clip at ×N, beyond
  the 0.2% Synchronize Audio corrects."); otherwise it is applied. **The significance test is the
  owner's choice of 2026-10-15**, replacing an absolute cap (`errorMilliseconds > 2` left) that
  the spec first carried: on S10's fixture (true +199.96 ppm over 150 s) the line measured
  197.358 ppm, 29.60 ms, whose correction would leave about 0.39 ms, but its conservative
  uncertainty (SY-7's √(2000/step) widening kept) was ±2.134 ms, so the cap left a drift
  fourteen times its own uncertainty uncorrected. The uncertainty is reported as
  `drift_error_ms`, never used as a cap; the tolerances that check the RESULT (SY-7's) stand. A drift not measured is left with its
  own note. Each `sync_audio` row adds `speed` (the speed after the command), `drift_corrected`,
  `drift_error_ms` (null when not measured), `residual_ms` (corrected: `drift_error_ms`; left:
  `drift_ms`; not measured: null) and `drift_note` (when not measured, or when left with a note).
  `moved` is true when any op is made; no ops is `moved: false`, "already in sync".

- **SY-9 — The rate band (amends SY-4's ×N refusal).** A clip within `|rate − 1| ≤ 0.002` (its
  `speed`, else its first time-scaled segment's ratio) is matched at its rate; outside it, it is
  refused "plays at ×N; Synchronize Audio lines up clips playing at ×1 or within 0.2% of it.";
  a reversed clip is still refused, and so is a clip whose speed is ×1 but whose segment is
  time-scaled, as AS-1 refused it ("plays at ×N though its speed is ×1; Synchronize Audio lines
  up clips whose speed is the rate they play at."): its zero and `set_speed` read the speed, not
  the stretch (AS-2's review). A mover already corrected re-measures about 0 and answers
  "already in sync" with no undo step; an anchor at a near-1 rate is resampled the same way.

- **SY-10 — The corrected mover's span (amends SY-4).** Its new duration is `content =
  round(d·s)`, `max(snapToFrame(round(content/s')), one frame)` — the core's `set_speed` without
  its hold to the file (the core stays the backstop). Start ≥ 0, meeting the anchor and the
  own-track neighbour check are made on the FINAL span `[S + δ, S + δ + d')`, the neighbour check
  whenever δ ≠ 0 or d' ≠ d. The op order keeps every intermediate span inside the old or the
  final one: when d' > d, `move_clip` then `set_speed`; otherwise `set_speed` then `move_clip`;
  each only when it changes something. The list is one undo step, "Synchronize Audio".
