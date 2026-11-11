# Spec §11 — decisions: Audio sync, #298's export offsets and round 3's waveform gate

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the SY- series of [`audio-sync-2.md`](audio-sync-2.md), so a citation never has to
say which file. This file holds SY-23…SY-30. SY-31 on are in [`audio-sync-3.md`](audio-sync-3.md),
which is why this file is lettered. It is new because `audio-sync-2.md` had passed the spec's
~500-line split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below"
in one may now point into a sibling file.

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
  done. **Amended by SY-36 (#306):** an MP3 whose LAME/Xing encoder delay Core Audio leaves in is
  copied at any rate, 48 kHz included, its read starting past that delay (`version` 2).

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
  ≤ 1.0 ms. MP3's decoder delay is a filed residue, measured and not pinned. **Amended by SY-36
  (#306):** an MP3 is read past its own encoder delay and pinned like every other source (E30,
  E33, X10, X11, X13, X15); one with no tag keeps the delay (X14). The preview plays the
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
  8c0409d, -Onone, each file decoded by copies of `writeSyncFeatures`' and `writeSpeech`'s reader
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
  constant moves. **Amended by SY-32 (#302):** over 30 s, the region (played or the files') is
  the 30 s whose features agree most along the line; still one region and one refinement.

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
