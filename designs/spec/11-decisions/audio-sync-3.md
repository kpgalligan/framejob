# Spec §11 — decisions: Audio sync, the clean-up (#301, #302, #304, #305), the export's audio residue (#307, #306, #299) and keep pitch (#299)

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
clear GCC-PHAT peak. SY-35…SY-38 were recorded in clean-up batch 3, the
export's audio residue (#307, #306, #299), each before its code; their numbers are the
implementer's printed runs of 2026-10-17 (`export_offset_proof.py`, `audio_sync_proof.py`) and,
where they say so, the designer's scratch runs of the same day, SY-22's precedent.
SY-39 and SY-40 were recorded for #299 from the owner's "Push. For 299, go with your
recommendation." of 2026-10-19: SY-39 before its code, SY-40's rule before the survey's first
run and its readings after, from the implementer's printed runs of 2026-10-19.

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

- **SY-35 — The late head's read range is pinned by a fixture that separates (#307; SY-23's head
  range unchanged).** X8's `clicks44-late` (its audio 0.5 s into the movie) read +0.023 ms with the
  copy's head range and −0.576 ms without it — inside SY-27's 1.0 ms, so no row failed when the
  range was taken out. `clicks16-late5` is the same recipe over clicks16 with the audio 5 s in
  (`-itsoffset 5`, a 16 s grey movie; Z0 reads its start_time 5.000000 s). X9 (F206, ×1, the
  in-process `audio_wav`) reads +0.000 ms, spread 0.000, 12/12 with `if head > .zero {` and
  +19.500 ms, spread 0.000, 12/12 without it; M10-no-head-range is killed (named X9, X9 failed, no
  other row failing). E32 is the same project exported by the app. The fixture separates by
  19.5 ms, so SY-27's pins stand and no 0.25 ms pin is added.

- **SY-36 — An MP3 is read past its own LAME/Xing encoder delay when Core Audio leaves it in
  (#306; amends SY-23's "every rate but 48 kHz" and SY-27's MP3 residue).** **The cause** (the
  designer's scratch runs of 2026-10-17): an MP3's first frames are the encoder's priming. Core
  Audio always removes its decoder's own 529 samples, and the encoder's delay only when it reports
  a packet table — from an iTunSMPB comment, or from a LAME/Xing tag whose CRC passes LAME's rule
  (CRC-16, 0xA001, over the frame's bytes before the CRC field). ffmpeg's muxer computes that CRC
  over the frame's first 190 bytes with the field zeroed, which agrees only when the field sits at
  byte 190 (MPEG-1 stereo), so Core Audio ignores ffmpeg's tag on a mono or MPEG-2 file and every
  AVFoundation reader — the export's, the copy's, the sync pass's, `AVAudioFile` — places the
  sound the tag's encoder delay late: 576 frames, +13.061 ms at 44.1 kHz, +12.000 at 48 kHz,
  +24.000 at 24 kHz. ffprobe's start_time is 1,105 samples (576 + 529), so what Apple leaves is
  exactly the tag's delay. Rewriting the fixtures' CRC by LAME's rule makes them read +0.000;
  ffmpeg's stereo file is accepted (and reads +13.061 with its CRC broken); `lame` 4.0's mono
  file stays accepted even with its CRC broken, so Core Audio's exact rule is not reproducible and
  Frame Job asks Core Audio instead of re-deriving it. A delay that is not 576 is applied as
  written, by Core Audio (a tag edited to 1,000 with a good CRC reads −9.615 ms, priming 1,000) and
  by ffmpeg alike, so Frame Job applies it as written too. **The rule** (`MP3Gapless.swift`):
  `leadingTrim` answers the tag's encoder delay, `CMTime(delay, rate)`, only for a track whose
  format is MPEG Layer III, whose file's first frame (after any ID3v2 tag) holds a Xing/Info header
  with a LAME extension (encoder "LAME", "Lavf" or "Lavc"; the CRC not checked) of the track's
  rate and a delay above 0, and for which `kAudioFilePropertyPacketTableInfo` does not answer —
  a packet table is never second-guessed. Every other file is read as before: no tag (ffmpeg's
  `-write_xing 0`) is today's +13.061 ms, Apple having nothing to apply; a container's MP3 track
  never parses, so it keeps the head range. The reads are bounded — 10 bytes, then at most 2,048
  at the first frame — and nothing is sized from the ID3 header. **Where:** the 48 kHz copy
  (`AudioRateCopy`, `version` 2, so every v1 copy is re-made once) is now made for an MP3 with a
  trim at ANY rate, 48 kHz included, its reader starting at the trim and its frame 0 the first
  buffer's first frame; the sync pass reads from the same trim (SY-38). Preview reads the same
  copy (`Playback.swift`'s build → `CompositionBuilder.build` → `audioURLs`), so SE-13's row is
  unchanged. **The tail:** the copy ends `delay` frames before AVFoundation's duration, which the
  media record keeps; that remainder plays silence, because `insertTimeRange` does not clamp
  (`CompositionBuilder.swift`). **The cost:** per build, per MP3 media, at most 2,058 bytes read
  and one `AudioFileOpenURL`; a non-MP3 stops at the format signature. **The limit:** an iTunSMPB
  whose priming counts Apple's 529 (1,105) is applied by Core Audio as written and reads 12 ms
  early (the designer's scratch run: −11.995 ms); it is a packet table, so it is not
  second-guessed. Trimming the end padding and the import's duration are not done. **The
  measurement here** (the implementer's run, `--only Z0,L10,L12`, no app): `afinfo` prints no
  packet table for clicks44-mp3, clicks48-mp3, clicks24-mp3 (MPEG-2, 24 kHz, 64 kb/s) or
  clicks44-mp3-noxing, and `audio 441000 valid frames + 576 priming + 792 remainder = 442368` for
  clicks44s-mp3 (ffmpeg stereo) and clicks44-mp3-itunsmpb (noxing behind a hand-written iTunSMPB);
  L10 reads clicks44-mp3 +13.084 (asset48) / +13.061 (native) / +13.061 (`AVAudioFile`),
  clicks48-mp3 +12.000 / +12.000 / +12.000, and from the trim (576 frames each) clicks44-mp3
  +0.000, clicks48-mp3 −0.000, clicks24-mp3 −0.000, each within 0.1 ms of ffmpeg's read of the
  same file; natively clicks44s-mp3 +0.000, itunsmpb +0.000, noxing +13.061 and clicks24-mp3
  +24.000. L12 answered all 41 of its cases as expected: the four tags (576/792 at 44.1 kHz,
  576/960 at 48, 576/768 at 24, 576/792 stereo), nil for every other fixture, the trim 576 frames
  for the three untabled MP3s and zero for every other fixture, the tabled two included, and nil
  for every prefix under 177 bytes of the first frame, a foreign encoder, a smeared header, a
  200-byte file, an ID3 size past the file, a size byte ≥ 0x80, an empty and a 3-byte file and
  4,096 bytes of noise. **The rows:** X10, X11 and X15 (clicks44-mp3, clicks48-mp3, clicks24-mp3
  through the copy), X13 (the tabled two, untouched), X14 (noxing left 576/44.1 ms late, against
  X2), E30 and E33 (the app's exports), all but X14 on SY-27's 1.0 ms pin; M11 (no MP3 copy at
  48 kHz), M12 (no trim in the copy), M14 (padding read as the delay) and M15 (a packet table
  second-guessed). **The recorded run** (Release, 2026-10-17, after `make gate`): E30 +0.023, E33
  −0.000, X10 +0.023, X11 −0.000, X13 +0.023 / +0.023, X14 +13.084 (X14 − X2 +13.061) and X15
  −0.000 ms, each spread 0.000, E32 +0.000; `--mutants` 13/13 killed.

- **SY-37 — Keep pitch, measured on a real recording: a defect, left open for the owner (#299).**
  **The rule, fixed before R4 and R5 ran:** `stretched_lag` (the export against the media's 1 ms
  envelope stretched by the speed) on the recorder's media windows [12 s, 22 s) and
  [128 s, 138 s), reach ±200 ms; a **defect** when at ×0.9 or ×1.1 keep pitch any window has
  r < 0.8, |lag| > 5.0 ms, or a lag on the ±200 ms edge; otherwise an accepted limit within
  SY-27's 5.0 ms. R3 (×0.99999 keep, the in-band `time_domain`) was to be pinned at 1.0 ms with
  the controls R6 and R7 (×0.9 and ×1.1 with keep pitch off). **The readings** (the implementer's
  Debug run of 2026-10-17; lag on [12 s, 22 s) / [128 s, 138 s)): R3 −8.899 (r 0.950) / −0.129 ms
  (r 0.952); R4 (×0.9) +12.213 (r 0.960) / +94.193 ms (r 0.935); R5 (×1.1) +6.080 (r 0.966) /
  +43.118 ms (r 0.936); the controls R6 +0.019 / −0.000 and R7 +0.013 / −0.005 ms (r ≥ 0.982).
  R3's own export swept in 10 s media windows reads −0.185 to −8.899 ms (mostly early), where
  R6's reads within ±0.027 ms in every window. **The class: DEFECT** — AVFoundation's time-pitch
  algorithms move real sound against its timeline, `time_domain` inside the band included,
  which the click fixtures (E10 +0.010 ms, X6) do not show. Fixing it means choosing how Keep
  pitch is rendered, a product behaviour change and the owner's call (the orchestrator's
  ruling 3), so it is not fixed here and #299 stays open. **So R3, R4, R5 and E34 (clicks48
  ×1.1 keep) are measured rows:** they run on every pass and print `measured` with their
  readings, scored on the instrument only (both windows found at r ≥ 0.5 inside the ±200 ms
  reach; for E34 ≥ 10 clicks found) and never pinned to a lag; R6 and R7 stay pinned at 1.0 ms,
  r ≥ 0.8. SY-26's band and SY-27's 5.0 ms for the KEEP rows on clicks are unchanged.

- **SY-38 — The MP3's other readers (#306).** **The sync pass** reads from the same
  `MP3Gapless.leadingTrim` as the copy, its reader's time range starting there, and its marker's
  version is 4: every media's sync cache reads "still being analysed" once and is re-made on the
  next pass (SY-34's no-migration posture); a file with no trim decodes the same bytes as at
  version 3. Measured before the change (X12, the product's `writeSyncFeatures` → `loadSyncSamples`,
  the implementer's run of 2026-10-17): clicks44-mp3 +13.061 ms and clicks48-mp3 +12.000 ms, the
  WAV controls +0.000 — the export's delay, so the export and the sync cache would have disagreed
  with the file by the same amount and with each other not at all; after it X12 is pinned with
  them, and M13 (no trim in the sync pass) is killed by it.
  **The residue readers, by a rule fixed before they were read:** peaks (10 ms buckets: the
  waveform, Normalize's window peak, level-mode silence spans snapped to the 33 ms frame grid),
  speech (32 ms VAD chunks: voice-mode spans and SY-17's mask on 64 ms feature frames), the
  transcription extract (word timings) and the reverse renderer's decode (L1's asset48) are each
  an **accepted residue** when both MP3s read |median − their WAV control's| ≤ 16.7 ms (half a
  30 fps frame), and a reader over it is filed. L11 (the implementer's run of 2026-10-17, the
  unfixed decode): peaks +13.061 / +12.000 (controls +0.000 / +0.000), speech +13.039 / +11.958
  (−0.023 / −0.042), the extract +13.039 / +11.958 (−0.023 / −0.042), the reverse decode +13.084 /
  +12.000 (+0.023 / +0.000); the largest |MP3 − control| is 13.062 ms, so all four are accepted
  residues. **An MPEG-2 MP3 is over it, and filed (#309):** L11 extended to clicks24-mp3 (the
  orchestrator's ruling 3; its control clicks44, the WAV it was made from) reads peaks +24.000,
  speech +23.958, the extract +23.958 and the reverse decode +24.000 ms — |MP3 − control| 24.000,
  23.981, 23.981 and 23.977 ms, the tag's 576 frames at 24 kHz — so all four readers are over
  16.7 ms for such a file, and one issue names them. The recorded run (Release, 2026-10-17) reads
  the same; X12 ±0.000 ms for all five reads, and `audio_sync_proof.py`'s S32 (an MP3 recorder) syncs
  on frame 206, 32.5 ticks from the truth, its export +0.047 / +0.041 ms. **Why they do not take the trim:** in each it is a placement change,
  not one line — peaks place by presentation time and certify their coverage against the track's
  range (`MediaPeakBuckets.swift`); VAD sizes its chunks from the media's duration; the extract's
  range is the clip's source range; and `ReverseRenderer.swift` places by presentation time and
  is over the file cap. Loudness is not a timing reader.

- **SY-39 — Keep pitch within ±0.1% of ×1 plays varispeed (#299; amends SY-26's near-unity
  part).** A clip with Keep pitch on at 0.999 ≤ speed ≤ 1.001 (speed ≠ 1, both ends inclusive)
  plays `off` — varispeed, no time-pitch — exactly as a clip with Keep pitch off. The pitch it
  moves is bounded by 1200·log2(1.001) = +1.730 cents and 1200·log2(0.999) = −1.732 cents, under
  1.74 cents either way, which nobody hears; in exchange its sound stays on its timeline, where
  SY-37 read `time_domain` at ×0.99999 move real speech by up to −8.899 ms. SY-26's band is now
  0.98 ≤ speed ≤ 1.02 outside this one: there keep pitch still plays `time_domain`, and outside
  0.98–1.02 `spectral` (SY-37's defect for real speed changes stays open, measured by SY-40). ×1
  is unchanged: unscaled, it plays `spectral` and is inert (SY-24). The plan's three pitch names
  are unchanged — only which name a speed gets moves — so a near-unity keep clip shares plan
  audio tracks with keep-off clips and gets SY-24's varispeed lead, and preview and export, which
  share the plan, agree. The band is tested with the inclusive range of its two constants
  (`PITCH_VARISPEED_MIN`, `PITCH_VARISPEED_MAX` in `evaluate.rs`), never as |speed − 1| ≤ 0.001,
  which in binary floating point excludes 0.999. No persisted field moves: no format bump. **The
  pins:** R3 (the recorder at ×0.99999 keep) is pinned at SY-27's 1.0 ms with r ≥ 0.8;
  `core/tests/pitch_band.rs` holds the band's edges (0.999, 1.001 `off`; 0.99899, 1.00101
  `time_domain`) and a near-unity keep clip sharing a track with a keep-off one; mutants M16 (the
  band's branch removed), M17 (`PITCH_VARISPEED_MAX` 1.0009) and M18 (`PITCH_VARISPEED_MIN`
  0.9989) each fail it. E35 (clicks16 ×0.99 keep, the app's one remaining `time_domain` export) is
  a measured row beside R4, R5 and E34.

- **SY-40 — Every pitch-keeping method macOS offers, measured at real speed changes before one is
  chosen (#299).** **The rule, fixed before the survey's first run:** `keep_pitch_survey.py`
  reads the RECORDER fixture (`audio_sync_proof`'s, 16 kHz) at frame 206, in 0, at the rates
  ×0.5, ×0.9, ×0.99, ×1.01, ×1.1, ×1.5 and ×2, by four methods and one control:
  `spectral` and `timeDomain` (`AVAudioTimePitchAlgorithm`, set on the export's audio mix as
  the product's mix read takes it, `export_offset_probe.swift`'s T1), `timepitch`
  (`AVAudioUnitTimePitch`, AVAudioEngine's offline manual rendering of `AudioRateCopy`'s 48 kHz
  copy into a CAF of the copy's format, inserted unscaled into a composition, T2) and
  `autimepitch` (the older AUTimePitch, `kAudioUnitSubType_TimePitch`, the same render, T2);
  the CONTROL is keep pitch off, the product's varispeed with SY-24's lead (T1). A unit that
  does not instantiate is `unavailable` and leaves the comparison, not the run. Each read is
  measured by `stretched_lag` (reach ±200 ms) on 15 media windows: the sweep [12 s, 22 s),
  [22 s, 32 s) … [142 s, 152 s) and [128 s, 138 s) (R4/R5's late window). Each (method, rate)
  is classed over all 15 windows, the first that applies: **lost** — any r < 0.8 or a lag on
  the ±200 ms edge; **on time** — every |lag| ≤ 1.0 ms; **constant** — max − min ≤ 1.0 ms (a
  lead of the median leaves every window within 1.0 ms); **bounded** — max − min ≤ 10.0 ms
  (within SY-27's 5.0 ms after a lead); **drifts** — otherwise. A method is **adoptable at
  1.0 ms** when every rate is `on time` or `constant`, and **at 5.0 ms** when every rate is at
  worst `bounded`. The control must be `on time` at every rate, else the run is a failed
  instrument. Adopting a method is phase 2, designed from these numbers; this decision changes
  no behaviour.
  **The readings** (the implementer's run of 2026-10-19 on the final instrument, `python3
  tools/proof/keep_pitch_survey.py`, exit 0, 290 s; a first run's ×2 reads were dropped by the
  survey's own key, JSON writing 2.0 as 2, and it exited 1 as a failed instrument). Per rate:
  lag on [12 s, 22 s) / [128 s, 138 s), max − min over the 15 windows, the class; ms.
  **Control (`off`):** within ±0.077 ms in every window at every rate (max − min 0.032–0.116,
  least r 0.956): `on time` at every rate, so the run held. **`spectral`:** ×0.5 +0.709 /
  −0.776, 3.255 bounded; ×0.9 +12.213 / +94.193, 92.654 drifts; ×0.99 +13.064 / +99.405, 96.681
  drifts; ×1.01 +4.289 / +30.382, 29.558 drifts; ×1.1 +6.080 / +43.118, 40.975 drifts; ×1.5
  −0.070 / −0.656, 2.064 bounded; ×2 +0.709 / −0.610, 3.455 bounded — not adoptable.
  **`timeDomain`:** ×0.5 −41.648 / −41.604, 1.641; ×0.9 −12.177 / −13.015, 3.137; ×0.99 −5.929 /
  −8.791, 3.382; ×1.01 −5.286 / −2.630, 4.368; ×1.1 −1.956 / −2.886, 4.822; ×1.5 +2.972 /
  +3.913, 3.292; ×2 +8.104 / +7.341, 1.915 — `bounded` at every rate: **adoptable at 5.0 ms**,
  its per-rate medians −41.620 … +7.505 ms (spread 49.125), so its lead is per rate.
  **`timepitch`** (`AVAudioUnitTimePitch`, latency 0, render 0.25–0.90 s, the CAF 11.0–44.1 MB):
  ×0.5 −2.144 / −1.722, 5.560 bounded; ×0.9 −8.326 / −64.463, 62.252 drifts; ×0.99 −4.562 /
  −32.156, 30.474 drifts; ×1.01 +4.416 / +31.070, 29.807 drifts; ×1.1 +5.944 / +43.725, 41.163
  drifts; ×1.5 +0.432 / +0.281, 1.824 bounded; ×2 +0.258 / +0.774, 1.916 bounded — not
  adoptable (the same drift as `spectral`, sign flipped below ×1). **`autimepitch`** (the older
  AUTimePitch; it instantiates; latency 0.041–0.079 s, render 2.69–5.38 s, the same CAF sizes):
  ×0.5 +77.929 / +77.933, 2.439 bounded; ×0.9 +62.560 / +62.241, 0.951 constant; ×0.99
  +60.041 / +59.969, 0.127 constant; ×1.01 +45.355 / +45.412, 0.474 constant; ×1.1 +45.941 /
  +45.244, 2.451 bounded; ×1.5 +43.954 / +43.287, 0.851 constant; ×2 +43.114 / +42.516, 1.276
  bounded (least r 0.894) — **adoptable at 5.0 ms**, its per-rate medians +42.895 … +77.484 ms
  (spread 34.589), near its reported latency at each rate. The run's last line: `VERDICT:
  timeDomain, autimepitch adoptable at 5.0 ms`. No method is adoptable at 1.0 ms. Phase 2
  chooses between them (a per-rate lead for either; `autimepitch` as an offline-rendered copy)
  from these numbers.
