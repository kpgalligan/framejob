# Spec §11 — decisions: Audio sync, the clean-up (#301, #302, #304, #305)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the SY- series of [`audio-sync.md`](audio-sync.md) and
[`audio-sync-2.md`](audio-sync-2.md), so a citation never has to say which file; the first names
the condensed record and the originals, and what stands beneath every SY- decision. This file is
new because `audio-sync-2.md` reached the spec's ~500-line split rule (#308). SY-31…SY-34 were
recorded in the clean-up batch of Synchronize Audio's residue (#301, #302, #304, #305, #308),
from the owner's "Do the small followups" of 2026-10-16, each before its code; their numbers are
the implementer's printed runs of 2026-10-16, named where they are quoted. Round 3's verdicts
(SY-28) and the waveform gate (SY-29) stand unchanged: nothing here lets a match stand without a
clear GCC-PHAT peak.

- **SY-31 — A file too short for one frame publishes an empty cache (#301; amends SY-11's edge
  and its "positive" sizes).** A completed read that holds no whole frame (sound under 512
  samples, 64 ms) now publishes like any other: a zero-byte `.bin`, the `.pcm` of its samples
  (under 1,024 bytes) and the marker, in the same publish. A `.bin` is read when its size is a
  multiple of 26·4 bytes, 0 included (it loads as no frames); a `.pcm` when its size is even, 0
  included; and the features are current under those sizes. The marker's version is NOT bumped:
  an old pass never published a zero-frame file, so no old cache reads differently. `AudioSync.read`
  is unchanged: no frames is a frame count equal to the samples', so the file passes "still being
  analysed" and reaches SY-12's floor, "is too short to match: its file holds under 2 s of sound."
  — the sentence it always should have read. Not handled, and not wanted here: a file whose read
  does not complete still publishes nothing (SY-11), and the speech pass already publishes one
  chunk for any file (`MediaSpeech.chunkCount`'s floor of 1). **The rows:** the probe's P23 (a
  40 ms 16 kHz tone through the product's `writeSyncFeatures`: the marker present, no frames,
  samples whose frame count is 0, current; control: 1 s of the same tone gives its frames) and
  the proof's S31 (a 40 ms `short-v1.wav` beside CAMERA: refused "is too short to match", never
  "still being analysed"). **The risk it accepts:** none new; a zero-frame cache is 0 bytes plus
  under 1 KB.

- **SY-32 — The refinement's region is chosen by the features' evidence (#302; amends SY-20's
  and SY-29's "centred and capped").** The ONE region a plan refines over is still the played
  overlap (or, under 2 s, SY-29's files' overlap at the coarse lag, rounded outward) ×128, and
  still the whole of it when it holds at most W = 240,000 / 128 = 1,875 frames (30 s). A longer
  overlap no longer gives its centre 30 s: it gives the 1,875-frame window where the two files'
  features agree most along the line. Each anchor timeline frame f of the overlap scores
  `Σ_k A[f, k]·M[m(f), k]` — A and M the two readings' timeline-grid features standardised as
  the match standardised them (over their speech frames, the rest 0, when the match was on
  speech, SY-17; over every frame otherwise), `m(f) = f − round((c + ρ·128f)/128)` the mover's
  frame of the same sound along the line PHAT is about to use (SY-20: the drift's, else the
  coarse lag), and 0 when f or m(f) lies outside its file. The window start s, from the overlap's
  start to its end less W, maximises the score summed over `[s, s + W)` (prefix sums). The first
  candidate is today's centred start, `⌊(lo + hi)/2⌋ − ⌊W/2⌋` in frames, and it is replaced only by
  a strictly greater sum, or by an equal sum whose start is nearer it; the region is
  `[128·s, 128·(s + W))`. `AudioSync.refinementRegion` (`AudioSync+Region.swift`) does it, pure,
  for both the played overlap and SY-29's files' overlap. **What does not change:** it is one
  region and one refinement; its z, `clearZ` 15, the 48 ms reach, the `incoherent` and
  `unconfirmed` refusals and the 2 s floor are SY-29's; the region's size equals the old one's,
  so the floor reads it exactly as before. It never takes the clearest of several regions: a
  maximum over regions would raise every null's PHAT z, which is what SY-29 measured against.
  The features only say WHERE the shared sound is; PHAT still alone says whether it is one
  recording. **Why the features' agreement, not energy or the speech mask:** energy and speech
  say where either file has sound, not where they share it — a quiet centre beside an unrelated
  loud stretch would pick the stretch — while the features along the line the plan already
  found are the evidence of shared sound itself, at no new cost (the frames are in memory, one
  pass of 26 products a frame). **The rows:** the probe's P21 — (a) a 54 s pips pair (the
  anchor 1.204 s later, P17's construction) with the mover's [12 s, 42 s) replaced by seeded
  noise: confident, refinement clear, within 75 ticks of the truth (control: PHAT over the old
  centred 30 s of the same overlap is not clear); (b) the same gap at −60 dBFS (room tone): the
  same; (c) (a)'s features with unrelated anchor samples: refused, exactly `incoherent`.
  **Calibration rule:** SY-29's — S20, S21, S22, S23, S30, P13 and P20's refusals stay refused
  and S1, S19, S27–S29, P17 and P20's planned cases stay clear; a misclassification stops the
  batch at #302 with every z printed; no constant moves.

- **SY-33 — Features-only drift with unrelated sound late in a take: two rules measured, neither
  taken (#304 stays open; SY-21 unchanged).** The acceptance set: P17's +200 ppm pair over 120 s
  (seeds 176–178) on the features alone (no samples, so the line is SY-21's stage 1), the mover's
  [85 s, 115 s) seeded noise at 0.1 for seeds 404, 405 and 406, and its [100 s, 120 s) for 407,
  408 and 409 — each to read within ±5 ppm of 199.960 on `features` — with P5, P7, P8, P12, P17
  and P18 passing unchanged. Two candidates were written and measured on it (the implementer's
  Debug probe runs of 2026-10-16, a scratch copy of `app/Sources` each): **W**, stage 1's line
  weighted by each kept window's near-placement z² (weighted means, `ρ = Σw(x−x̄)(y−ȳ)/Σw(x−x̄)²`,
  `SE² = (Σw·r²/(n−2))/Σw(x−x̄)²`, the same √(1250/step) widening; stage 2 unweighted); and **S**,
  the survivor filter discarded, right after it and before SY-7's count and span rules, when the
  survivors' centres span less than the kept windows' span less 1,250·128 samples (the count and
  span rules, the OLS line and stage 2 then run on every kept window). The readings, ppm for the
  six cases in seed order, the windows fitted in brackets:

  | Rule | 404 | 405 | 406 | 407 | 408 | 409 | Others |
  |---|---|---|---|---|---|---|---|
  | SY-21 today | 178.348 (17) | 178.749 (17) | 177.852 (17) | 168.350 (19) | 185.665 (21) | 168.747 (19) | pass |
  | W (z² weights) | 178.906 (17) | 179.316 (17) | 178.517 (17) | 170.447 (19) | 183.521 (21) | 170.254 (19) | pass |
  | S (span fallback) | 178.348 (17) | 178.749 (17) | 177.852 (17) | 168.350 (19) | 185.665 (21) | 168.747 (19) | pass |

  Neither passes a single case. W moves each reading by at most 2.1 ppm: the windows that bias
  the line are the ones partly in the gap, and their features still match at a high z, so z
  cannot tell them from clean ones. S never fires on the set: the biased windows sit inside the
  Theil–Sen band and survive, so the survivors' span equals the kept span. So stage 1 stays SY-21's
  OLS line through the survivors, and the residue stays #304's. With samples, stage 2's PHAT
  points refit the line (P17's [40 s, 70 s) gap reads 199.908 on PHAT), so the error reaches a
  real sync only where stage 2 falls back to F — fewer than 3 clear PHAT windows, or too little
  span. A later rule needs a per-window measure of how much of the window is shared sound, not
  its z.

- **SY-34 — The sync pass decodes at the file's own rate and resamples to 8 kHz itself (#305;
  amends SY-11's "speech's output settings at 8 kHz"; cache version 3).** **The measurement**
  (P25, the proof's `--determinism`, its probe built -O whole-module; the implementer's runs of
  2026-10-16): four ffmpeg files — D1 one hour mono AAC at 48 kHz, 128 kb/s; D2 ten minutes
  stereo AAC at 44.1 kHz; D3 ten minutes mono 48 kHz WAV; D4 ten minutes mono 16 kHz WAV — each
  read twice by three arms. **T**, the pass as it stood (the reader converting to 8 kHz), wrote
  different bytes on EVERY file, PCM ones included, so it is not AAC-only: before the change,
  .pcm 850, 317, 396 and 630 samples differing (D1–D4) in 211, 77, 101 and 71 clusters, largest
  |Δ| 749, 576, 846 and 525; again after it, 382, 61, 103 and 209 samples, largest |Δ| 531, 143,
  533 and 512. **N**, the same reader with no `AVSampleRateKey` (the file's own rate: 48,000,
  44,100, 48,000 and 16,000 Hz), was byte-identical over two passes on all four, in both runs. So
  the variation is AVFoundation's rate conversion, not the decode. **The rule:** the pass's
  output settings drop `AVSampleRateKey` and nothing else; the first buffer's
  `CMAudioFormatDescriptionGetStreamBasicDescription(...).mSampleRate` is the input rate (a
  first buffer with none publishes nothing, the media still being analysed); `SyncResampler`
  (`SyncResampler.swift`) brings the samples to 8,000 Hz and they then go to the extractor and
  the `.pcm` exactly as before. Output n is the Kaiser-windowed sinc low-pass — cutoff 3,600 Hz,
  16 output samples each side, β 8.6, each kernel scaled to sum to 1 — at input position
  `n·rate/8000` exactly (integer arithmetic for a whole-hertz rate, one kernel per phase; a rate
  that is not a whole number of hertz has the position's fraction rounded to the nearest 1/1,024
  of an input sample, at most 1/2,048 of one off, so it too makes at most 1,024 kernels rather
  than one per output, each about 2·reach + 1 Bessel series): a symmetric kernel, so no delay,
  input outside the file 0, `⌈N·8000/rate⌉` outputs for N inputs,
  each summed in one fixed order so the answer does not depend on how the reader splits the
  file, and the identity at 8,000 Hz. The marker's version is 3, so every version-2 cache reads
  "still being analysed" until the next pass rewrites it (SY-11's posture, no migration). **The
  gate it passed** (the run after the change, the arms interleaved): P, the product's pass, wrote
  identical `.pcm` and `.bin` over two passes on D1–D4; its wall was 1.213× T's on D1 (fastest
  of two: 1.47 s against 1.21 s) and 1.157× on D2 (0.29 s against 0.25 s), under the 1.5× bound.
  A one-hour file's `.pcm` holds 28,800,000 samples where the reader's own conversion gave
  28,799,997. **The rows:** P24 (an impulse at 48,000, 44,100, 16,000 and
  44,099.5 Hz lands within ±0.05 output sample of `8000·t`; the whole input against pieces of 1,
  777 and 4,096 samples byte-identical; the count; 8,000 Hz the identity) and P25 (`--determinism`,
  scored on all four files identical, the native decode identical and P ≤ 1.5× T on D1 and D2).
  **The risk it accepts:** a resampler of Frame Job's own to keep — pure arithmetic, no
  AVFoundation — and a pass about 1.2× as long; and the matching moves by the resampler's
  slightly different band edge (3,600 Hz against AVFoundation's), which the S and P rows re-read.
