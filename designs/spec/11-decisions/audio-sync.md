# Spec §11 — decisions: Audio sync (road map "audio-sync")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is `designs/audio-sync.md` (open: AS-1 lines clips up and measures
drift, AS-2 corrects it). SY-1…SY-5 were recorded in AS-1, before its code, from the owner's three
answers of 2026-10-15 (quoted verbatim in the road map): placement frame-snapped; the clip with
video stays and the audio moves; drift reported first, correction straight after.

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
