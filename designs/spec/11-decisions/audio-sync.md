# Spec §11 — decisions: Audio sync (road map "audio-sync")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

Both road maps that made these are closed (2026-10-15 and 2026-10-16): their condensed record is
`designs/adr/audio-sync.md`, the originals `archive/audio-sync.md` (AS-1 lines clips up and measures
drift, AS-2 corrects it) and `archive/audio-sync-2.md` (AS-3 matches on features, AS-4 refines,
moves drift onto the features and takes the plan off the main thread). SY-1…SY-5 were recorded in AS-1, before its code, from the owner's three
answers of 2026-10-15 (quoted verbatim in the road map): placement frame-snapped; the clip with
video stays and the audio moves; drift reported first, correction straight after. SY-6…SY-10 were
recorded in AS-2 before its code; SY-8 was amended by the owner's choice after AS-2's STOP. SY-11…SY-16 were
recorded in round 2's AS-3 (`archive/audio-sync-2.md`) before its code, from the owner's "Go ahead" to
all five points of 2026-10-15 and the owner's choice of the head trim (SY-16). SY-17…SY-19 were
recorded in AS-3's second fix pass, before its code, from the owner's "Ask, then apply" of
2026-10-15, which resolved SY-14's calibration stop. SY-20 and SY-21 were recorded in round 2's
AS-4 before its code, from point 4 of the owner's "Go ahead"; SY-21's slice and robust filter and
SY-22 were recorded after AS-4's stop, from the orchestrator's ruling of 2026-10-16. SY-23…SY-27
were recorded in #298's phase 2 before its code: the export's audio offsets phase 1 measured and
located (`tools/proof/export_offset_proof.py`), removed at their causes; their numbers are the
designer's scratch measurement of 2026-10-16, SY-22's precedent. SY-28…SY-30 were recorded in
round 3 (the waveform gate) before its code; their numbers are the designer's scratch measurement
of 2026-10-16, SY-22's precedent, and SY-29's fail-closed clause is the orchestrator's ruling of
2026-10-16 on the round's spec review.

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
  (SY-5). **Amended by SY-11 (AS-3):** the match measures each file's cached sync FEATURES
  (`cache/sync/<media id>.bin`, SY-11) as well as its waveform; the waveform's onsets still carry
  drift (SY-5/SY-7) until AS-4. Nothing else here changes. **Amended by SY-20 and SY-21 (AS-4):** no
  peaks are read at all: the features carry the match and the drift, and the decoded samples
  (`cache/sync/<media id>.pcm`) the refinement.

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
  Release), and an unrelated recording r 0.14, q 1.10 (S3). **Superseded for the coarse match by SY-12 and
  SY-13 (AS-3):** the onset envelope, its 1,000-bucket overlap, its ±50-bucket runner-up, the
  peak ratio and the 200-bucket file minimum are gone. Its r ≥ 0.25 stays as SY-7's per-window
  floor (`minimumCorrelation`), and the onsets stay as drift's input. **Amended by SY-21 (AS-4):**
  its onsets are no longer drift's input, and the r ≥ 0.25 floor went with them.

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
  trimming a neighbour to make room is not done. **Amended by SY-16 (AS-3):** "a mover that would have to start
  before 0" is no longer refused; its head is trimmed (SY-16), and the meeting and neighbour
  checks are made on the trimmed span. The "no sound" sentence for a silent file is now "has no
  sound to line up by." (SY-12). Every other refusal here stands.

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
  undrifted recorder −14.6 ppm (S1). **Superseded by SY-21 (AS-4):** drift is measured on the
  features and refined by PHAT; the 60 s minimum (3,750 frames) and its sentence stay.

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
  new; the inspector shows the speed the correction wrote. **Amended by SY-21 (AS-4):** the
  features (and their masks) are what is resampled, not the onsets, and the line's `a` is an anchor
  timeline SAMPLE (8 kHz) with c in samples, so `δ = snapToFrame(round(zeroA + 75·c/(1 − ρ) − S +
  I/s'))` and the centre line places by `round((c + ρ·aMid)·75)`, aMid the overlap's centre sample.

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
  the step is not changed and the tolerance is not loosened. **Superseded by SY-21 (AS-4):** the
  windows are 1,250 feature frames matched on the features, then refined by PHAT; the 60 s
  minimum, the count rule then the span rule and their sentences, the √(window/step) widening and
  the tolerances (P5, S10, S17, S18) stay.

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
  `moved` is true when any op is made; no ops is `moved: false`, "already in sync". **Re-checked
  in AS-4 (Release, 2026-10-16), the 5 ms and the 3× unchanged:** on the features and PHAT the
  drift fixture (S10, true +199.96 ppm over 150 s) read 199.920 ppm, 29.978 ms ±0.022 ms (about
  1,400 times its uncertainty) and was corrected to ×0.99980008, 0.006 ms from the truth over the
  overlap; the undrifted recorder (S1) read −0.077 ppm, −0.012 ms, left under 5 ms; S10's corrected
  recorder re-measured 0.084 ppm, 0.013 ms (S17), "already in sync". No fixture was misclassified.

- **SY-9 — The rate band (amends SY-4's ×N refusal).** A clip within `|rate − 1| ≤ 0.002` (its
  `speed`, else its first time-scaled segment's ratio) is matched at its rate; outside it, it is
  refused "plays at ×N; Synchronize Audio lines up clips playing at ×1 or within 0.2% of it.";
  a reversed clip is still refused, and so is a clip whose speed is ×1 but whose segment is
  time-scaled, as AS-1 refused it ("plays at ×N though its speed is ×1; Synchronize Audio lines
  up clips whose speed is the rate they play at."): its zero and `set_speed` read the speed, not
  the stretch (AS-2's review). A mover already corrected re-measures about 0 and answers
  "already in sync" with no undo step; an anchor at a near-1 rate is resampled the same way.
  **Re-checked in AS-4 (2026-10-16), the 0.2% unchanged:** the probe's ±1,000 ppm pairs over 160 s
  (P18, #300's case) were matched confidently and corrected inside the band (`set_speed` 0.9990011
  and 1.0010010 for 1/k 0.9990010 and 1.0010010); P8's ×1.002 / ×1.0021 and ×0.998 / ×0.9979
  boundaries hold.

- **SY-10 — The corrected mover's span (amends SY-4).** Its new duration is `content =
  round(d·s)`, `max(snapToFrame(round(content/s')), one frame)` — the core's `set_speed` without
  its hold to the file (the core stays the backstop). Start ≥ 0, meeting the anchor and the
  own-track neighbour check are made on the FINAL span `[S + δ, S + δ + d')`, the neighbour check
  whenever δ ≠ 0 or d' ≠ d. The op order keeps every intermediate span inside the old or the
  final one: when d' > d, `move_clip` then `set_speed`; otherwise `set_speed` then `move_clip`;
  each only when it changes something. The list is one undo step, "Synchronize Audio". **Amended by SY-16 (AS-3):** a mover
  whose final start would be before 0 is trimmed instead, and its ops are `set_speed` (when
  corrected), `trim_start`, `move_clip`, in that order; with no trim this order stands.

- **SY-11 — The sync-features cache (`cache/sync/`).** Each media file with audio gets
  `cache/sync/<media id>.bin`: f32 little-endian MFCC frames, 26 coefficients each, one frame per
  128 samples at 8,000 Hz (16 ms of source, 9,600 ticks; about 6.5 KB a second, 23 MB an hour),
  frame-major. The recipe is BBC R&D's `audio-offset-finder` (github.com/bbc/audio-offset-finder:
  8 kHz, a hop of 128, 26 coefficients, the correlation of standardised MFCCs), as the round's
  `mfccsync.py` wrote it: mono 8 kHz float, a 512-point frame holding a Hann(256) window centred
  in it, the power spectrum through 40 triangular HTK-mel bands from 0 to 4 kHz, `log(P·FB +
  1e-10)`, a DCT-II (unnormalised) to c0…c25. Frame f starts at sample 128·f; a file of n
  samples holds `(n − 512)/128 + 1` frames (0 under 512). Its marker `<id>.complete.json` is
  `{"source": CacheStamp, "version": 1}`, `PeaksStamp`'s shape; the version is bumped on ANY
  change to a recipe constant. The pass reads the first audio track (the one `peaks` reads) with
  speech's output settings at 8 kHz, keeps nothing unless the reader ends `.completed`, and writes
  the `.bin` and then the marker inside one `CacheLedger.publish`. It runs in `generateCaches`
  after `peaks` and before `speech` (which stays last), clears at its head when stale or when the
  media has no audio, and posts NO `.mediaCacheDidChange`: nothing memoises features. A
  `.bin` is read only under a current-version marker, its size a positive multiple of 26·4 bytes,
  every value finite; anything else is "still being analysed", never silence. **Its one retry:**
  `retryPeaks` runs the pass once, with that attempt's fresh stamp, straight after an attempt whose
  `peaks` answers true — so a file unreadable on the first pass and readable on a retry gets its
  features in the same session. Nothing else retries it. **The edge:** a file with sound but
  under 512 samples (64 ms) holds no whole frame, so the pass publishes nothing for it and it
  reads "still being analysed" for good rather than "too short to match" (AS-3's review, finding
  6; recorded, not handled). **Amended by SY-17 (AS-3's second fix pass):** the same retry also
  runs `speech` once, straight after the features, with the same stamp, so a file whose speech
  pass failed with its waveform gets its VAD probabilities in the same session too. **Amended by
  SY-20 (AS-4):** the marker's version is 2, and the pass also keeps the samples it fed the
  extractor as `cache/sync/<media id>.pcm` (int16 little-endian mono at 8 kHz, each `round(clamp(x,
  −1, 1)·32767)`; 16 KB a second, about 58 MB an hour), written after the `.bin` and before the
  marker inside the same publish; a failed write removes both files. A `.pcm` is read only under a
  current-version marker, its size a positive even number of bytes, and the features are current
  only when it is; clearing removes the marker, then both files. A version-1 marker is another
  version, so its media reads "still being analysed" until the next cache pass rewrites both — no
  migration.

- **SY-12 — The feature match and its confidence (supersedes SY-3 for the coarse match).** The
  two stretches compared (SY-13) are taken onto the timeline grid (SY-6's resampling, applied to
  each frame vector) and standardised per coefficient over the stretch (mean 0, sd 1; a
  coefficient with sd under 1e-6 is 0, so a silent stretch is all zeros). The correlation is the
  SUM over the 26 coefficients of each coefficient's full cross-correlation, `c(L) = Σ_k Σ_m
  x_k[m + L]·y_k[m]` (L the anchor frame minus the mover frame), by one zero-padded `vDSP_fft_zrip`
  per coefficient and ONE inverse transform of the summed cross-spectrum. The confidence of a lag
  is its z-score, `(c(L) − mean)/sd` with the mean and sd taken over EVERY lag (every overlap of at
  least one frame), as `mfccsync.py` does; z is 0 when sd is 0. A lag may be a candidate only when
  its overlap is at least 125 frames (2 s), or the shorter stretch when that is shorter. The
  summed correlation, not BBC's norm across coefficients, is the one the owner's files told apart:
  on the owner's trimmed windows the norm put the best lag at 110.1 s (z 2.7), the sum at
  118.68 s (z 4.3), the owner's own ground truth being about 118.7 s (round 2's request, its
  table). BBC's README reads its z-score as "> 10 trustworthy, < 5 check"; landmark
  fingerprinting then cross-correlation (Bryan, Smaragdis & Mysore, "Clustering and
  synchronizing multi-camera video via landmark cross-correlation", ICASSP 2012; and `audalign`)
  was tried by the round's `landmark.py` and found nothing usable on the owner's files. A file
  under 125 frames is "too short to match: its file holds under 2 s of sound."; a file whose
  every coefficient is constant is "has no sound to line up by.", named on that clip alone (SY-4's
  rule). **Corrected by SY-28:** "the owner's own ground truth" of about 118.7 s was never a true
  offset — the owner's two files are two takes of similar words, not one recording.

- **SY-13 — The played windows first (reverses SY-3's whole files).** Each clip's PLAYED window is
  the frames `[⌊(start − zero)/9600⌋, ⌈(end − zero)/9600⌉)` of its file on its timeline grid,
  clamped to the file. When both hold at least 125 frames they are searched first; only when that
  search chooses nothing (SY-14) and either window is a strict part of its file are the whole files
  searched. AS-1 searched the whole files because a user's trim could cut the shared sound out.
  **The reversal's reason is the owner's case:** the owner's recorder (165 s) and camera (55 s)
  share a second, unrelated stretch — the recorder's first ~13 s against the camera's last ~13 s,
  at −41.92 s — and that stretch wins any whole-file search (z 6.3 against the true 118.64 s's
  3.7, `mfccsync.py`), while the owner's trims hold only the real utterance. Where the user put
  the clips is evidence of what they mean to line up. **Corrected by SY-28:** −41.92 s is the
  only sound the owner's files SHARE and 118.64 s is not a true offset; the rule stands on its
  own reason, that the trims are the evidence.

- **SY-14 — Candidates, the choice and the refusal.** A search answers its CANDIDATES: the local
  maxima of c among the lags that may be candidates (a lag above its left neighbour and at least
  its right, a neighbour that may not be a candidate counting as no rival — so at an overlap of
  exactly 125 frames the last scorable lag of a slope rising into the unscorable edge is a
  candidate though it is a flank; recorded from AS-3's review, finding 5), highest first, each more than 60 frames
  (0.96 s) from every one already kept, at most 4, each refined parabolically; and its NEAR
  PLACEMENT: the highest local maximum of c (both neighbours scorable and strictly lower) within
  188 frames (3.008 s) of the lag at which the mover already sits, `(zeroN − zeroA)/9600`, refined
  — nil when there is none, so the flank of a peak outside the radius is never chosen. **The
  choice:** the best candidate when its z ≥ 6 and it stands at least 1.5 above the second (or
  there is no second), chosen "by confidence"; otherwise the near placement when its z ≥ 4,
  chosen "by placement"; otherwise nothing. **The refusal**, when no search chooses: "no matching
  sound found between clip A and clip N: in the played windows, moving clip N by +0.77 s
  (confidence 4.31) or −12.40 s (3.90); in the whole files, …. A match needs confidence ≥ 6 and
  1.5 above the next candidate, or ≥ 4 within 3 s of where clip N sits now." — each search that
  ran, with its candidates as the frame-snapped move each would make, and the rule printed from
  the constants; with no candidate in any search, "…: too little room to compare their sound."
  **The answer:** each `sync_audio` row drops `correlation`; `confidence` is the chosen lag's z;
  it adds `search` ("played" | "whole"), `chosen_by` ("confidence" | "placement"), `candidates`
  (`[{offset, delta, confidence}]`: the chosen search's candidates, plus the near placement when
  that was chosen and is not among them) and `trimmed` (SY-16). **Calibration rule:** the
  constants (6, 1.5, 4, 188 frames) are initial; when the proof's fixtures (S1, S3, S9, S10,
  S19, S20, S21, and from AS-3's review S22 and the probe's P13, unrelated sound placed where it
  overlaps) are misclassified they change, and every value tried is recorded here and in the
  road map; when no set classifies them all, the phase stops and reports the printed z's.
  **AS-3 stopped here (2026-10-15).** S22 (CAMERA and UNRELATED both at 0) is synced by
  placement at z 4.59 and P13's unrelated pairs at 4.14 and 4.39 by placement and at 6.83 by
  confidence, while the owner's true match is z 4.19 with a competitor at 4.15: no `plausibleZ`
  separates them, and neither does z taken over the scored lags, z of `c(L)/√overlap(L)` (the
  owner 3.57, S22 3.46; unrelated sound at the owner's window lengths reaches ≥ 3.5 in 5–32% of
  placements), a margin guard (the owner's margin is 0.07) or the mean per-coefficient
  correlation (the owner 0.057, unrelated windows up to 0.13). The numbers are in road map
  "audio-sync-2"'s AS-3 record; the choice rule waits on the designer and owner.
  **Resolved by SY-17..SY-19 (the owner's choice of 2026-10-15):** "chosen by confidence" is now
  the CONFIDENT tier and its z is 10, not 6 (BBC's own "> 10 trustworthy"); "chosen by
  placement" is now the WEAK tier (SY-18), which is never applied without asking (SY-19); and a
  search between two stretches that both hold speech correlates their speech frames only (SY-17).
  The refusal's rule sentence now reads "A match applies on its own at confidence ≥ 10 and 1.5
  above the next candidate; one ≥ 4 within 3 s of where clip N sits now is offered as a weak
  match." The 1.5, the 4 and the 188 frames are unchanged. **Corrected by SY-28, amended by
  SY-29:** "the owner's true match" here was a false pair; a choice of either tier now stands only
  on SY-29's clear GCC-PHAT peak, and the rule sentence gains "Either counts only when the two
  waveforms line up there (a clear GCC-PHAT peak of at least 15 within 48 ms)."

- **SY-15 — The fixtures and the owner's rows.** Beside AS-1's, a committed SYNTHETIC pair with
  the owner's traits, made by the proof from a seed (16 kHz, `camera2-v1.mov`,
  `recorder2-v2.wav`): a 60 s camera with a 5 s speech-like utterance at 31.2 s and a 13 s
  competing stretch at its end, and a 165 s recorder of heavy low-frequency rumble holding the
  competing stretch at 0 s and the utterance 118.70 s later than the camera does. S19 places them
  as the owner did (trimmed to the utterance, the camera at 2 s) and must land the recorder
  exactly on the snapped true offset by the played search. **Amended in AS-3's fix pass:** the
  offset was 118.71 s (`recorder2-v1.wav`), whose true landing (35.7 frames) sat 6.7 ms from a
  snap boundary, inside the coarse match's measured error of about 8 ms (the numpy reference of
  `mfccsync.py` erred the same way), so S19 missed by a frame. At 118.70 s the true landing is
  1.2 s, a whole frame, half a frame (16.7 ms) from either boundary; the exact-landing claim is
  kept, not loosened. **Amended by SY-18 and SY-19 (AS-3's second fix pass):** S20 and S21 are
  weak matches: a first call answers `moved: false` naming the recorder (or the camera) in
  `weak`, and a second with `accept_weak: true` must meet the landing below. S22, S23 (the owner's
  recorder time-reversed, placed where it overlaps the camera — a null that does run the
  speech-only search, both windows holding at least 125 speech frames) and P13 must never apply
  without `accept_weak` and never be confident; S24 puts the Weak match sheet up and cancels it.
  **The owner's own files**
  (`tools/proof/media/owner-sync/IMG_0018.MOV`, `record.aifc`; gitignored, never committed or
  copied out) are rows S20 (the camera the anchor) and S21 (the recorder the anchor), placed as the
  owner placed them; each needs recorder − camera within one 30 fps frame of 118.68 s. A row
  whose files are absent is a scored FAIL, never a skip: the owner's case is the reason for the
  round, and a proof run without it has not shown the round works. **Corrected by SY-28, amended
  by SY-30:** the owner's files are two takes, so S20 and S21 are refused nulls with no 118.68 s
  bound; the one-recording rows are owner-sync-2's (S27–S29).

- **SY-16 — The head trim (amends SY-4 and SY-10; the owner's choice of 2026-10-15).** Asked what
  Synchronize Audio should do when syncing would push the audio clip before the start of the
  timeline, the owner chose: "**Trim the audio's head** — the audio clip stays at 0:00 and drops
  its first 0.77 s, so what remains plays in sync. The video doesn't move. Only trims the moving
  clip, and only by the amount that would fall before 0." So with S the mover's start, I its in
  point, δ the final snapped delta, s' its final speed and d' its SY-10 duration: when `S + δ <
  0`, the excess `e = −(S + δ)` (on the frame grid) is trimmed off its head. Its span becomes
  `[0, d' − e)` and its in point `I + e·s'` (`trim_start`'s own arithmetic at s'), so source tick
  μ still plays at `S + δ + (μ − I)/s'`, SY-6's line. The ops are `set_speed` (only when
  corrected), `trim_start {clip, to: S + e}`, `move_clip {delta: δ}`, in that order, one undo
  step; `trimmed` is e (0 with no trim). The anchor never moves or trims. Refused by name before
  any op: `d' − e` under one frame ("would have to lose X s of its head to start at 0, leaving
  under a frame of it."); the trimmed span not meeting the anchor's (SY-4's sentence); a neighbour
  on the mover's track meeting the trimmed span or, when it is corrected and grows, `[S, S + d')`
  (SY-4's sentence). With `S + δ ≥ 0` nothing is trimmed and SY-10 stands.

- **SY-17 — Speech-only matching (AS-3's second fix pass; the owner's choice of 2026-10-15).** A
  search whose two stretches each hold at least 125 SPEECH frames (2 s) correlates their speech
  frames only: frame f of a file is speech when the cached Silero VAD probability of the chunk
  holding its centre, `cache/speech/<id>.bin` at `⌊(f·9600 + 19200)/19200⌋` (the frame's centre is
  256 samples at 8 kHz, 19,200 ticks, after its start; one chunk is 19,200 ticks), is at least
  0.5 (Silero's default, and `detect_silence`'s default `voice_confidence`); a mask is resampled
  onto the timeline grid as the frames are (frame k is source frame `round(k·speed)`). Each
  stretch is then standardised per coefficient over its own speech frames, and every other frame
  is 0, so only frames speech in BOTH stretches correlate; everything after the standardisation
  (SY-12's sum, z over every lag, SY-14's candidates and near placement) is unchanged. Otherwise,
  or when the model cannot be used this process (`SileroVAD.isAvailable` false), the search is on
  every frame, as SY-12 says. Each `sync_audio` row says which, `matched_on` ("speech" |
  "sound"). With the model available, a clip whose speech cache is not yet written is "still
  being analysed", as one with no features is. **Why the VAD and not an energy gate:** the app
  already caches Silero per media for `detect_silence` (road map 4), so a mask costs no new
  pass, and an energy gate would mark the owner's recorder rumble as sound. **The measurement**
  (a numpy reproduction of `search` over the S20 session's own `cache/sync/` and
  `cache/speech/`): the owner's true match is z 4.18 at 118.672 s unmasked (the app's own
  number), **7.92 at 118.688 s with both stretches masked** (next candidate 4.43), 5.50 with the
  recorder's mask only, 6.95 with the camera's only, and 4.12 when a pair is kept where EITHER is
  speech (it then loses to 113.856 s). The owner's recorder reversed, against 47 camera windows,
  reached at most z 6.04 masked. The owner's played windows hold 244 speech frames (the camera)
  and 248 (the recorder); REC2 holds no speech chunk, so S19 matches on sound, and the burst
  fixtures hold 0–1, so S1–S18, S22 and P13 match on sound. **Corrected by SY-28:** the 7.92
  "true match" is a false pair (two takes); SY-30 keeps speech-only matching on other evidence.

- **SY-18 — The two tiers (resolves SY-14's stop).** A search's choice (SY-14's shape) is
  CONFIDENT when its best candidate's z is at least 10 and 1.5 above the second (or there is no
  second) — `chosen_by` "confidence" — and WEAK when it is not but the near placement's z is at
  least 4 within 188 frames — `chosen_by` "placement"; otherwise nothing, and the refusal names
  the candidates (SY-14). The search order (SY-13) is unchanged: a played search that chooses
  either tier ends the search. A confident match applies as before. **A weak match is never
  applied silently** — the owner's reason: "Unrelated clips are never moved silently." AS-3's
  stop showed noise near a placement reaching z 4.6 and the owner's true unmasked match 4.2, so
  the near placement alone cannot tell them apart and a person must. A run's WEAK MOVES are its
  movers chosen by placement whose plan changes something (a non-zero delta, a trim, or a
  corrected drift); a weak mover already in place is not asked about. One tier decision serves
  both callers (`AudioSync.weakMoves`), so the menu and the tool cannot disagree. **Amended by
  SY-29, corrected by SY-28:** either tier stands only on a clear GCC-PHAT peak; "the owner's true
  unmasked match 4.2" was a false pair.

- **SY-19 — The Weak match sheet and `accept_weak` (the owner's choice of 2026-10-15).** Asked
  "When Synchronize Audio finds only a weak match, what should it do?", the owner chose **"Ask,
  then apply"**: "Strong matches apply as now. A weak match near where you placed the clip shows
  'Weak match: move the recorder 0.77 s (trim 0.77 s)? Apply / Cancel'. Over MCP the tool
  returns the candidate and applies only with an explicit accept_weak flag. Also add
  speech-only matching (it lifted your match from z 4.3 to 5.9). Unrelated clips are never
  moved silently." So: **the menu**, when a plan has weak moves, puts up one alert sheet on the
  editor's window — "Weak match: move “record.aifc” 0.77 s earlier (trimming 0.77 s off its
  head)?", its detail naming the anchor, each confidence, the 10 a match needs to apply on its
  own and the 3 s radius — with Apply (the default) and Cancel (Escape). Cancel changes nothing
  and makes no undo step. Apply commits the plan's ops as one grouped undo step ("Synchronize
  Audio") only when the project and the open scope are the ones the sheet was asked about;
  otherwise it beeps and puts "the project changed while the weak match was being asked about,
  so nothing moved. Choose Synchronize Audio again." at the inspector's foot. With no window, or
  a sheet already up, it beeps. **`sync_audio`** takes a new optional boolean `accept_weak`
  (default false). Every success answer carries `weak`, the clip ids of its weak moves; with weak
  moves and `accept_weak` not true it answers `{ok: true, moved: false, anchor, synced, weak,
  note, project}` — no op, no undo step, not an error — the note naming each move and saying to
  call again with `accept_weak: true`. With `accept_weak: true` it applies, as the sheet's Apply
  does. **An agent passes `accept_weak: true` only after the person has agreed to that weak
  match, naming the move** (the orchestrator's ruling): the catalog's description and the weak
  answer's note both say so, and there is no per-argument ask-first machinery in the assistant's
  lane (AI-7 names tools, not arguments); the edit is one undo step.

- **SY-20 — The GCC-PHAT refinement (round 2's AS-4; point 4 of the owner's "Go ahead").** Each
  chosen match's offset is refined on the two files' decoded samples (`cache/sync/<id>.pcm`, SY-11
  as amended). The REGION is the coarse overlap — the anchor timeline frames both clips play once
  the mover sits at the coarse delta — ×128, in anchor timeline samples, centred and capped at
  240,000 samples (30 s). Along the LINE `lag(a) = c + ρ·a` (a an anchor timeline sample at 8 kHz;
  c and ρ the measured drift's, SY-21, else c the coarse lag ×128 and ρ 0), the anchor's samples
  over the region and the mover's at `a·(1 − ρ) − c`, each read at `position·speed` of its file
  by linear interpolation (0 outside it), are correlated by band-limited GCC-PHAT: one zero-padded
  `vDSP_fft_zrip` each (the least power of two holding every lag), the cross-spectrum `X·conj(Y)`
  kept only on bins whose frequency `k·8000/n` lies in [300, 3,400] Hz (the speech band), each
  divided by its magnitude (0 under 1e-20), DC and Nyquist 0, and one inverse. Its z is taken over
  EVERY lag, as SY-12's. The PEAK is the highest r within ±384 samples (±3 feature frames, 48 ms)
  of the line; it is CLEAR when its z ≥ 8, it lies strictly inside the reach and it is strictly
  above both neighbours. A clear peak, refined parabolically (SY-3's ±0.5), shifts the line's
  intercept (or, not measured, the coarse lag) by its sub-sample shift, so the true lag is
  `line(a) + shift`. Without a clear peak, or with a region under 16,000 samples (2 s), or a slice
  all zero, the coarse value stands: the FALLBACK, which is a designed answer, not a failure.
  **Why only near the coarse lag:** GCC-PHAT whitens every bin, so any shared stretch can own its
  global peak however little of the speech it holds: round 2's analysis ran whole-file GCC-PHAT
  on the owner's files (`pcm.py`, the AS-3 handoff) and it was fooled by a burst, where the summed
  MFCC correlation found the owner's offset. PHAT is the refiner, never the finder. **The tier is
  untouched:** `confidence`, `chosen_by`, the candidates and SY-18's tiers are the coarse match's,
  and placement stays frame-snapped (SY-4). **The answer:** each `sync_audio` row's `offset` is the
  refined lag at the overlap's centre in ticks (the line's value there when drift was measured),
  and it adds `coarse_offset` (the coarse lag, ticks), `refined` ("phat" when the peak was clear,
  else "coarse"), `refine_confidence` (the peak's z; null when no refinement ran) and `drift_on`
  (SY-21). **Calibration rule:** `clearZ` 8 is initial. The positives (S1, S2, S8, S10, S19, the
  probe's planted delay in P16, and P17) must be clear, and the negatives (S22, S23, P16's
  unrelated pips) must not; on a misclassification only `clearZ` moves, to a value that classifies
  them all, every value tried recorded here and in the road map; when none does the phase stops and
  reports every printed z. S20 and S21 (the owner's files) are recorded, never calibration inputs:
  they have no 1 ms ground truth and hold only about 5 s of clear speech. **Calibrated (AS-4,
  Debug, 2026-10-16):** at 8, S23 (a null) read z 10.24 and was clear — a misclassification; 15 was
  tried and classifies every fixture (positives S1 433.8, S2 433.5, S8 433.9, S10 423.3, S19 131.5 and 187.9 (two runs),
  P16's planted delay 162.5, P17 514.1 and 516.0; negatives S22 4.03, S23 10.24, P16's unrelated
  pips 4.71). The owner's files read 9.00 (S20) and 9.01 (S21), so they keep the coarse offset.
  **Amended by SY-29, corrected by SY-28:** the refinement is now the gate — not clear, or with
  samples not run, refuses — its region falls back to the files' overlap under 2 s, and "the tier
  is untouched" no longer holds; S20's 9.00 and S21's 9.01 were PHAT reading a false pair
  correctly.

- **SY-21 — Drift on the features, each window refined by PHAT (supersedes SY-5's and SY-7's
  onsets; amends SY-6's units).** Drift's inputs are the readings' timeline-grid features and
  speech masks (SY-12, SY-17) and their samples (SY-20), the coarse lag in frames and the overlap O
  in anchor timeline frames. Under 3,750 frames (60 s) it is not measured, with SY-5's sentence
  ("the two play together for under 60 s, too short to measure drift."). Windows of 1,250 frames
  (20 s) start at O's start every `max(312, ⌈(|O| − 1250)/63⌉)` frames, plus one flush with O's
  end (at most 64). **Stage 1, the features:** each window is searched by `search` (SY-12, SY-17)
  against the mover's frames `[s − round(lag) − 62, s − round(lag) + 1250 + 62)` clamped to its
  file (the masks sliced alike), so every lag within the search overlaps the whole anchor window,
  its near placement taken within ±62 frames (0.992 s) of the coarse lag; a window whose near
  placement is missing or under z 6 is skipped. A kept window gives the point (its centre ×128,
  its near placement's lag ×128), in samples. When at least 3 windows are kept they pass through
  the ROBUST filter below; then SY-7's count rule (at least 3 windows, the count the survivors')
  then its span rule (their centres spanning at least (|O| − 1250)/2 frames), with their
  sentences, then an ordinary least-squares line F through the survivors. **Stage 2, PHAT:** each
  kept window is refined (SY-20) along F over its own samples (the window ×128); each CLEAR one
  gives the point (centre ×128, F(centre) + shift). When at least 3 are clear they pass through the
  same filter; when at least 3 survive and their centres span at least (|O| − 1250)·128/2 samples,
  those points are refitted by least squares; otherwise F stands. **The robust filter:** the
  Theil–Sen line (its slope b the median of `(yⱼ − yᵢ)/(xⱼ − xᵢ)` over every pair with xⱼ ≠ xᵢ, its
  intercept the median of `y − b·x`; a median the middle value, or the mean of the middle two),
  the residuals r about it and `MAD = median |r|`; a point is an inlier when `|r| ≤ max(3 × 1.4826
  × MAD, 1 sample)`. **Why the slice is wider** (the implementer's runs, 2026-10-16): with equal
  1,250-frame slices the overlap shrinks as `1250 − |d|` away from the coarse lag, and that
  triangular envelope pulled every window's peak toward it (about σ²/W, 0.02 frame): P7 read
  986.6 ppm for 999 (its `set_speed` 12.4 ppm off, P7 failed), P8's ×0.9999 and P12's +1,000 ppm
  cases failed, and P5's clean cases read 199.21, −148.83 and 95.88 ppm (for 199.96, −150.02,
  99.99). Widened: 200.18, −150.01, 0.05 and 99.99; P7 0.9990022 for 0.9990010 and 1.0010019 for
  1.0010010; P8 and P12 pass. **Why the robust filter** (the STOP of 2026-10-16): with the
  mover's frames 4,000–7,000 seeded noise (P5), the windows only partly in noise passed the z
  floor (z 12.8–16.9) with lag errors of 0.06–0.42 frame, and the least-squares line read 211.43
  ppm for 199.96; no window floor short of the clean windows' own z band (17.3–17.7) helped.
  Fitting each point at its window's matched-sound centroid read 209.68 (the error is the noise's,
  not the point's place), so it was not taken. Theil–Sen with MAD inliers read 201.06 (15 of 21
  windows); −150 ppm with noise −150.09, a 2,000–3,500 gap 201.10, +1,000 ppm with noise 998.47,
  noise at the end 202.06; every k from 2 to 6 passed and 7 or more failed (5.79 ppm off). **Units:** ρ is samples per sample and c samples
  at anchor timeline sample 0; `ppm = ρ·10⁶`, `milliseconds = ρ·|O|·128/8`, and
  `errorMilliseconds` the slope's standard error × √(1250/step) (when the step is under 1,250) ×
  |O|·128/8. **The answer** adds `drift_on` ("features" | "phat"; null when not measured) and
  `drift_windows` (the windows the line was fitted through; null when not measured). **Calibration
  rule:** S10's 2 ms, S17's 2 ms, P5's ±5 ppm and S18's 3 ms stand; on a miss only the window floor
  `driftWindowZ` (6) may move, every value tried recorded here; a miss that no value fixes stops
  the phase. The inlier scale k (`driftInlierScale`) is FIXED at 3 and the floor at 1 sample: a
  miss is a stop, never a new k (the measured passing band, 2–6, is recorded above).

- **SY-22 — The call's cost and its background run (AS-4, the orchestrator's ruling of
  2026-10-16).** **The budget:** a whole sync of a one-hour pair — the cached features and samples
  of both files loaded, then `plan` — costs at most 1.5 s of CPU on Release (-O, whole module),
  measured by the probe's P19 behind `--cost` on a generated one-hour pips pair (written under the
  gitignored `tools/proof/work/audio-sync/cost/` and removed after). The designer's scratch
  measurement (host load 36–76): `plan` 2.177 s, of which drift 1.803 s over 64 PHAT windows; one
  30 s refine 27.3 ms of which `vDSP_create_fftsetup` (log2n 19) was 24.0 ms; each file's `.bin` and
  `.pcm` load 0.035 s. **The reuse:** `plan` makes ONE `AudioSyncPHAT.FFT` (a vDSP setup of log2n 19,
  524,288 ≥ 2 × 240,000 − 1) before its movers and lends it to every drift window's refinement and
  the final one; each correlation still transforms at its OWN least power of two, so its bins, r, z
  and SY-20's `clearZ` are unchanged; with it the scratch `plan` was 0.891 s. `summedCorrelation`
  keeps its own setups. **The background run:** `read` stays on the main thread (it reads the
  document; its loads are cheap) and `plan`, pure, runs on a background queue. **The menu** puts up
  a Synchronizing Audio sheet ("Matching the sound of N clips…", an indeterminate bar, "Nothing
  moves until the match is found; Cancel leaves everything as it is.", Cancel) while `plan` runs,
  so the window never beach-balls and every editor action, Synchronize Audio included, is disabled
  while it is up; Cancel drops the late answer and changes nothing. When the answer comes, the
  sheet goes, and it is applied only when the document's project and scope are still the ones
  `read` took (the weak sheet's test, SY-19); otherwise it beeps and puts "the project changed
  while Synchronize Audio was matching, so nothing moved. Choose Synchronize Audio again." at the
  inspector's foot. A weak answer then asks as SY-19 says. **`sync_audio`** joins the server's
  off-main tools: the read and the stale test run on the main thread, `plan` on the server's thread,
  and a project changed meanwhile is the error "the project changed while Synchronize Audio was
  matching, so nothing moved. Call sync_audio again."; the call still blocks until it answers.
  The lane admits one call at a time, so no script can edit during one: the MCP stale test is
  proven by no row. **The dev hold:** a Debug or Release build's dev-only launch default
  `-RCDevSyncHold <seconds>` holds the menu's background run that long before `plan`, so a proof
  can reach the sheet (S25 edits under it, S26 cancels it); Distribution has no such default.

- **SY-23 — Non-48 kHz audio is read from a 48 kHz copy (#298 phase 2).** **The cause:** an empty
  edit before a non-48 kHz segment on its composition track is rate-converted wrongly, so the
  segment's sound lands off its place by an amount that grows with the placement. The designer's
  scratch measurement, 2026-10-16, read at 48 kHz: 16 kHz +3.833 ms at 1 s, +26.854 at frame 206,
  +39.125 at 10 s, lost past ±60 ms at 60 s; 44.1 kHz −1.215 at 1 s, −12.685 at 10 s; 22.05 kHz
  +51.084 at 60 s; 32 kHz +58.625 at 60 s; 96 kHz −0.010 everywhere; 48 kHz 0. The same segment at
  0, after a contiguous 16 kHz segment, or with the gap filled by real 16 kHz silence reads
  ≤ 0.021 ms. Every copy read +0.000 (16 kHz) / +0.023 (44.1 kHz, WAV and AAC) / +0.045 (22.05 kHz)
  ms at 0, frame 206, 10 s and 60 s. **The copy** (`AudioRateCopy`): LPCM 24-bit signed integer,
  48 kHz, `min(source channels, 2)` channels, CAF, keyed by the FILE — `<16-hex FNV-1a of
  "path|size|mtime-second|v<version>">.caf` — in `NSTemporaryDirectory()/FrameJob/AudioRate48/`:
  regenerable, outside the package, purged by the OS, and not a §5.6 cache entry. It is made on
  first need by the build on its own queue (blocking), serialised process-wide by one lock with an
  unlocked existence check first, written to `<name>.partial-<pid>.caf` and moved into place by
  `rename(2)`. **Its timing:** the copy's sample 0 is the source audio track's time 0 — the read
  starts where an empty edit at the track's time 0 ends (`loadSegment(forTrackTime:)`, waited for),
  because the reader fills that edit itself at the wrong length (a 0.5 s edit before a 44.1 kHz
  track read −0.576 ms, and +0.023 once the read starts after it); a gap before or between the
  reader's buffers, that edit included, is written as zeros, and a buffer that starts before 0 or
  overlaps the one before (by more than one sample) abandons the copy. A failed or abandoned copy
  falls back to the source with one `NSLog` line that never starts with "Frame Job: ". **Its
  cost:** 1.66 s and 494 MiB for 30 min of stereo 44.1 kHz AAC, accepted as one blocking first
  build. `rate != 48000` converts every other rate, 96 kHz included. A reversed clip already reads
  a 48 kHz intermediate (`ReverseRenderer+Audio.swift`), so its branch stays first. Video never
  reads the copy. Pre-making the copy in the import's cache pass and pruning the folder are not
  done.

- **SY-24 — The varispeed lead.** A time-scaled segment on a plan audio track whose pitch is `off`
  reads its source 575 ticks (46 samples at 48 kHz) earlier. Measured (the designer's scratch,
  2026-10-16), the output was early by −0.958 (×0.99999), −1.938 (×0.5), −3.896 (×0.25), −9.772
  (×0.1), −0.469 (×2) and −0.224 (×4) ms, the same at 0, frame 206 and 30 s and with an in point of
  2 s; with 575 ticks the residual is at most 0.189 ms (×0.1). A segment whose in point is under
  the lead starts with empty time instead — its head cut by the timeline ticks that bring the read
  to source 0, and their share of source — since 48 kHz empties are exact. ×1 segments are
  untouched: the algorithm was measured inert at ×1.

- **SY-25 — The noise reducer's lead.** A composition track whose tap runs noise reduction has its
  media placed 6,400 ticks (512 samples at 48 kHz, `AudioNoiseReductionStage.window`) earlier,
  the reducer's one-window delay. Volume ramps apply AFTER a PreEffects tap (measured: a step at
  2.95 s with a 100 ms delay tap passed the click delayed to 3.0 s), so fades now align with the
  sound. **Accepted:** a clip starting under 10.667 ms loses that much of its head; the track's
  last 10.667 ms stays unheard as before (a tap is not pulled past its track's end, measured); a
  cut between clips of different amounts switches the reducer 10.667 ms early.

- **SY-26 — Keep pitch at a near-unity speed plays `time_domain`.** Keep pitch at 0.98 ≤ speed ≤
  1.02 (speed ≠ 1) plays `time_domain`; the plan names it (`evaluate.rs`'s `Pitch`, three names:
  `spectral`, `time_domain`, `off`), and a plan audio track holds one pitch NAME (amends §11 #190's
  split by `keep_pitch`). Measured (the designer's scratch, 2026-10-16): `.spectral` drifts within
  a clip (×0.999 +0.343 → +56.665 ms over 60 s; ×0.9 → +43.4; ×1.01 → +13.9) and `.timeDomain` is
  bounded (×0.999 −0.021, ×0.99 −0.287, ×1.01 +0.239, ×0.98 −0.594, ×1.02 +0.469 median; ×0.9
  −3.3, ×0.5 −32.8). Outside the band `.spectral` stays; #299 stays open for it.

- **SY-27 — The tolerance, and the preview.** `export_offset_proof.py` pins every export path:
  |median| ≤ 1.0 ms and spread ≤ 0.5 ms for ×1, varispeed, in-band keep pitch, LPCM and AAC
  sources, gain, pan, noise reduction and range exports; |median| ≤ 5.0 ms for keep pitch outside
  the band; the video presets' flashes on exactly their timeline frames with every |click − flash|
  ≤ 1.0 ms. MP3's decoder delay is a filed residue, measured and not pinned. The preview plays the
  same composition (the copy and the leads apply); its output latency and its behaviour at a
  44.1 kHz output device are unmeasured (phase 1's L7: a 48 kHz composition read at 44,100 Hz is
  +3.402 ms at frame 206), so the manual check SE-13 is run at both device rates.

- **SY-28 — The record corrected: the owner's first pair is two takes, not one recording (round
  3; the designer's scratch measurement of 2026-10-16, SY-22's precedent).** Both projects' recorders
  are one file, `record.aifc` (165.0 s; `tools/proof/media/owner-sync/` and `owner-sync-2/` hold
  the same 23,764,480 bytes). `IMG_0019.MOV` (owner-sync-2) is one recording with it: today's
  `plan`, both at 0 untrimmed, is confident at recorder − camera 148.2658 s (z 46.39 masked, 29.62
  unmasked), PHAT 98.65, clear. `IMG_0018.MOV` (owner-sync, 55.27 s) is the EARLIER take of
  similar words, so 118.68 s was never a true offset: the only sound the two share is the
  recorder's first 13 s ≈ the camera's last 13 s, at −41.92 s (the recorder's [0, 17.34 s) at 0
  against the camera's trims is confident on sound at z 11.39, PHAT 27.5 clear; over the files'
  overlap there PHAT reads 25.98, clear). So SY-17's 7.92, SY-18's "the owner's true unmasked
  match 4.2", SY-20's 9.00 and 9.01 and #303 were a false pair, which PHAT read correctly as not
  one recording. The measurement (the probe built by `swift_build.py` over `app/Sources` at
  e8add54, -Onone, each file decoded by copies of `writeSyncFeatures`' and `writeSpeech`'s reader
  loops, then the app's own `AudioSync.plan`, `AudioSyncMatch.search` and `AudioSyncPHAT.refine`;
  "PHAT" the refinement along the coarse lag over the played overlap, "files" over the files'
  overlap at that lag, centred, capped 30 s; 30 fps):

  | Case (placement) | today's `plan` | z masked / unmasked | PHAT z |
  |---|---|---|---|
  | owner-sync, the owner's trims (cam 0 from 29.72 s for 25.52; rec 0 from 147.63 for 17.34), anchor cam / rec | weak, played, speech | 7.99 / 4.19 | 9.00 / 9.11 (not clear) |
  | same, whole-file search | — | 17.63 confident / best −41.92 s at 6.30 | 8.34; −41.92 s: files 25.98 clear |
  | owner-sync both at 0 untrimmed | confident 17.63, applied silently | 17.63 / none (−41.92 at 6.30) | 8.34 |
  | owner-sync-2 both at 0 untrimmed (anchor cam; anchor rec) | confident, rec − cam 148.2658 s | 46.39 / 29.62 | 98.65 clear (98.74) |
  | S23 (rec reversed, from 8.0 s for 17.34) | weak 5.54; whole masked confident 12.42 | 5.54 / none | 10.235 (10.52; files 5.61) |
  | S22 / S3 | weak 4.64 / refused (best 6.05) | — | 4.83 / — |
  | S1, S8 / S19 | confident 44.31 / 15.23 | same | 434.3 / 180.5 |
  | owner-sync rec [0, 17.34) at 0 vs cam trims (the real −41.92 s overlap) | confident 11.39 on sound | 11.39 | 27.5 clear |
  | owner-sync-2 short windows (16 placements; cam 2.5–4 s, rec 3–5 s, 1 s from truth) | 9 weak, 2 confident, 5 confident via whole | weak 7.86–9.94; 10.11/10.77 masked vs 8.41/9.03 unmasked | 65.3–100.8 clear; the 5: played < 2 s, files 98.38 clear |

  The owner-sync rows are retargeted as nulls (SY-30); `archive/` is untouched.

- **SY-29 — The waveform gate (amends SY-18 and SY-20).** A chosen match of EITHER tier stands
  only when the plan's refinement (SY-20) is CLEAR. When it ran and is not clear the command is
  refused, all or nothing (SY-1): "no matching sound found between clip A and clip N: moving clip
  N by −0.80 s matches their sound (confidence 7.99), but their waveforms do not line up there
  (GCC-PHAT confidence 9.00; a match needs a clear peak of at least 15 within 48 ms), so they are
  not one recording." — the move the coarse snapped delta, both confidences to two places, the 15
  `clearZ` and the 48 ms `reachSamples` printed from the constants (`AudioSync.incoherent`). **The
  region** is SY-20's played overlap; when that is under 16,000 samples (2 s) it is the files'
  overlap at the coarse lag instead, the anchor timeline frames `[lo, hi)` ×128 with
  `lo = max(0, ⌊lag⌋)` and `hi = max(lo, min(anchor frames, mover frames + ⌈lag⌉))`, centred and capped at 30 s — rounded OUTWARD
  (the round's spec review, objection 1; a slice reads 0 past a file's end), so every lag a search
  can score (an overlap of at least 125 frames) holds at least 16,000 samples. **Fail closed (the
  orchestrator's ruling of 2026-10-16):** when the readings carry samples and the refinement cannot
  run (a region under 2 s, an all-zero slice, any other nil) the match is not applied or offered
  either: refused with "…: moving clip N by −0.80 s matches their sound (confidence 7.99), but
  they share too little sound there to confirm it is one recording (GCC-PHAT needs 2 s of both
  waveforms)." (`AudioSync.unconfirmed`). Only a pair whose readings carry no samples at all (the
  probe's feature-only rows) keeps the features' tier unrefined. SY-14's rule sentence gains
  "Either counts only when the two waveforms line up there (a clear GCC-PHAT peak of at least 15
  within 48 ms)." A played-window choice refused here does NOT fall back to the whole files
  (SY-13: the trims are the evidence). `find`, `choose`, `weakMoves`, the sheets, `accept_weak`,
  the tool's keys, every op, the FFI and the format are unchanged; `refined` "coarse" now means
  that no refinement ran. **Why `clearZ` stays 15:** sweeps over owner-sync (74 recorder windows
  every 2 s; 50 of the reversed recorder every 3 s; the camera at the owner's trims) and the
  table's rows give 127 null placements, of which today's `plan` offers 15 weak and applies 14
  confidently (2 with no PHAT run, a played overlap under 2 s; their files' overlaps read 8.25 and
  5.61); every null's PHAT at its chosen lag is ≤ 10.36, every true match's ≥ 27.5 — 15 is ×1.45
  the highest null and ×1.83 under the lowest true match. **Why joint, not PHAT alone:** at random
  lags (≥ 10 s of overlap) PHAT reads on owner-sync a median of 3.75 and a maximum of 19.18 over 200
  lags, 2 of them ≥ 15 (15.49, 19.18); owner-sync-2 off the truth at most 12.34; the reversed
  recorder 11.51; CAMERA against UNRELATED 6.25. PHAT confirms; it never finds (SY-20).
  **Calibration rule:** a fixture misclassified stops the round, which reports every z; no
  constant moves.

- **SY-30 — Speech-only matching kept; the fixtures retargeted.** SY-17 stays: masking lifted two
  true short-window pairs of owner-sync-2 into the confident tier (8.41 → 10.11 and 9.03 → 10.77
  unmasked → masked), and every null it lifted is refused by SY-29. The rows: S20 (owner-sync at
  the owner's trims, the camera the anchor) and S21 (the recorder the anchor) refused naming the
  waveforms, again with `accept_weak: true`; S20's menu item puts up no Weak match sheet and leaves
  "Refused: no matching sound found…" at the inspector's foot; S30 (owner-sync both at 0
  untrimmed, today's confident 17.63) refused the same; S3 refused, S22 and S23 refused by the
  gate (S23 keeping its speech-frames control); S27 and S28 (owner-sync-2 both at 0 untrimmed, each
  anchor) confident, `refined` "phat", recorder − camera within one 30 fps frame of 148.27 s; S29,
  the weak positive (IMG_0019 on track 0 from 2 s for 3 s at frame 188, 6.2667 s; `record.aifc` on
  track 1 from 150 s for 3 s at 5 s; measured weak 8.52 masked, PHAT 90.49, speech 162 and 166
  frames): weak first, then applied with `accept_weak`, the recorder moving 0.9–1.1 s, the same
  bound; S24 the Weak match sheet on S29's placement; the probe's P13 (each pair with its own
  samples) refused, never weak; P20 the gate through `plan`. A row whose files are absent is a
  scored FAIL (SY-15's rule, for both owner folders).
