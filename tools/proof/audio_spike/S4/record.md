# Spike S4 — a per-media loudness cache (road map "audio", AP0 → AP1)

## The rule (fixed 2026-10-30 before any measurement was run)

**Subject.** A per-media cache from which AP1 reads any played window's BS.1770-4 integrated
loudness (gated) and true peak, fast enough for the inspector and Normalize. Candidate format:
K-weighted mean-square energy per channel-summed 100 ms block (a 400 ms gating block at 75 %
overlap is the sum of four consecutive 100 ms blocks), plus per-block true peak (4× oversampled
with `Loudness.swift`'s Annex 2 FIR) and sample peak. Blocks are placed by integer frame index,
`⌊f · blocksPerSecond / rate⌋`, the peaks cache's rule (`PeakBuckets`).

**Instruments** (all standalone, under `scratchpad/ap0/S4/`, nothing in the repo touched):
- `lcache` (Swift, `swiftc -O`): builds the cache from a file (AVAssetReader, 32-bit float at the
  file's own rate, as `writePeaks` decodes), queries a window from the cache, and measures a
  window DIRECTLY — a copy of `Loudness.swift`'s `LoudnessMeter` fed exactly the window's frames,
  filter state reset at the window's first frame and its blocks aligned there, which is what
  `Exporter.measureLoudness` does to an export of that window.
- ffmpeg 9.0.2 `ebur128=peak=true` over the same window cut with `atrim` (sample-exact), read
  through `metadata=1` for more than one decimal: the independent reference.

**Measurements and what passes:**
1. **Exactness.** Whole file and 10 random windows of 3–25 s with unaligned starts (seeded, so
   the windows are reproducible), on the owner's recording. The cache's answer, with the window
   snapped to the block grid, against DIRECT on the exact window. **Pass: |cache − direct| ≤ 0.1
   LU on every window.** If 100 ms fails, the same at 25 ms and 10 ms, and the recommendation is
   the coarsest grain that passes. Reported beside it, as the measure of what "the loudness of a
   window" can mean at all: DIRECT's own spread when the window's 400 ms block grid starts at
   ten phases 10 ms apart (a clip on a timeline sits at an arbitrary phase of the export's
   grid). ffmpeg against DIRECT reported per window, expected within 0.1 LU on the 48 kHz file.
   True peak: the cache's per-window maximum must be ≥ DIRECT's (snapping outward can only add
   samples), equal on the whole file, and within ±0.7 dB of ffmpeg (`Loudness.swift`'s own note
   on the two oversamplers).
2. **Size and build time.** Bytes per hour of audio for each layout considered. Build time on a
   20-minute file (the recording looped, re-encoded AAC), single-threaded, split into decode,
   K-weighting and true peak; the bare peaks-cache work (decode + max) timed alongside as the
   lane's existing cost; `uptime` load average printed with every timing, and each timing taken
   as the best of 3 runs. No pass line on time; reported against real time.
3. **Channels and rates.** A stereo file with different L and R content: channel sum with Table
   3 weights 1.0, cache vs DIRECT vs ffmpeg, pass ≤ 0.1 LU. A 44.1 kHz file: (a) resampled to 48
   kHz by the reader, then the 48 kHz coefficients, and (b) decoded at 44.1 kHz with K-weighting
   coefficients derived for that rate (the analog prototype through the bilinear transform,
   libebur128's method), each against ffmpeg (which resamples to 48 kHz itself), pass ≤ 0.1 LU;
   reader determinism of (a) across three runs reported. What a mono source reads in the
   export's stereo mix (does the mix duplicate it into both channels, +3.01 dB?) measured with
   `AVAssetReaderAudioMixOutput` as the export reads it.
4. **Speech-only loudness** (optional): integrated loudness over speech spans only (spans from
   an energy threshold, standing in for the Silero cache) against gated integrated, on the
   owner's recording. Reported, no pass line.
5. **Reversed, speed, ramp.** Reversed: the cache's mirrored window against ffmpeg on the same
   window of the reversed file (`areverse`), pass ≤ 0.1 LU. Speed: the source window's loudness
   against ffmpeg over the window played at ×0.5 and ×2 as varispeed (`asetrate`) and with pitch
   kept (`atempo`); reported, no pass line — it says whether "the source window's loudness" is
   the played loudness. Ramp: described from `SourceMap`/`MediaPeaks.sourceTick`, not measured.

---

## Verdicts against the rule

| measurement | verdict |
|---|---|
| 1. exactness, 100 ms | **FAIL**: −0.139 LU on 4.290–19.097 s (30.5 % of 200 short windows over 0.1 LU) |
| 1. exactness, 25 ms | **FAIL**: −0.149 LU on 2.282–10.475 s (9.5 % of 200) |
| 1. exactness, 10 ms | **PASS** on every named window (≤ 0.076 LU), once blocks are counted from the exact length; 2.5 % of 200 short windows exceed 0.1 (max 0.21), all inside the measurement's own grid-phase spread |
| 1. ffmpeg vs DIRECT | within 0.006 LU on every window |
| 1. true peak | cache = DIRECT on all named windows, never under on 200; 0.009–0.018 dB above ffmpeg (≤ 0.14 on reversed windows) |
| 2. size, time | 10 ms: 2.75 MB/h mono, 6.9 MB/h stereo; ~1 s per 20 min mono, ~1.6 s stereo 44.1 kHz, load 4–16 |
| 3. stereo | **PASS** (≤ 0.076 LU at 10 ms; channel matrices exact from the covariance) |
| 3. 44.1 kHz | **PASS** both ways: native coefficients +0.004 LU, the reader's 48 kHz conversion +0.000 |
| 3. mono in the export | the export's mix duplicates mono: **+3.01 LU** (−41.67, not −44.68) |
| 4. speech-only | +0.8 … +3.2 LU over gated BS.1770 by threshold, +1.1 … +1.7 at ~35 % speech |
| 5. reversed | **PASS** at 10 ms (≤ 0.087 LU) with the grid anchored at the played start; 100 ms fails (−0.305) |
| 5. speed | the source window is within ~0.5 LU of what plays at ×0.5–×2, not 0.1 |

## What ran (2026-10-30, after the rule)

Host: Apple M2 Max, 12 cores, on AC power, shared with other agents' builds; `uptime`'s load
averages are printed beside every timing. ffmpeg 9.0.2. Product code read as of `9e47f56`
(`git show`), copied into `S4/src/` for reading only; nothing in the repo was touched. Instruments
in `S4/tools/`: `lcache` (`main.swift`, `Core.swift`, and `LoudnessCopy.swift`, which is
`Loudness.swift`'s `LoudnessReport` and `LoudnessMeter` verbatim), `ffref.py` (the ffmpeg
reference), `join.py`, `table48.py`, `mirror_table.py`, `stats_table.py`, `speed_table.py`,
`lowrates.sh`, `speed.sh`. The `patch_*.py` files are the edits made to the instrument during the
run, kept so its history can be read. Outputs are in `S4/out/`, fixtures in `S4/media/`.

**Sanity first.** DIRECT (the spike's meter) equals the verbatim `LoudnessMeter` on the whole
recording to four decimals: I −44.6820 LUFS, TP −18.5261 dBTP, SP −18.5568 dBFS. The derived
48 kHz coefficients equal Tables 1 and 2 to 9·10⁻¹⁶.

**Two facts about the references, found before the windows ran.**
- **AVFoundation and ffmpeg disagree by 2112 samples (44 ms) on where this AAC file starts.**
  The file has no edit list that ffmpeg honours. AVAssetReader trims Apple's standard
  2112-sample priming and ffmpeg decodes it: 1 455 040 frames against 1 457 152, identical to
  −136 dB once aligned. A window cut from ffmpeg's own decode would be 44 ms off the app's, so
  every reference here is cut from AVFoundation's decode, written as raw f32 (`lcache decode`)
  and fed to ffmpeg.
- **ffmpeg 9's `ebur128` no longer resamples to 48 kHz.** At 44.1 kHz it inserts only a format
  converter and weights at the file's own rate. Its integrated figure is quantised by a 0.01 LU
  histogram, which is why it reads a steady ~0.005 LU under DIRECT.

**The rule's own run, then one instrument fix.** The first pass of measurement 1 counted the
gating blocks from the SNAPPED window, so a window end snapped outward could gain a whole 400 ms
block that the exact window does not have. At 10 ms that failed the rule on 2.282–10.475 s by
0.217 LU. The fix, which every result below uses and which is part of the recommendation: **lay
the gating blocks from the snapped played start, but take their NUMBER from the exact window
length** (`⌊(L − 0.4 s)/0.1 s⌋ + 1`, the count an export of the window keeps), so only the grid's
offset (at most half a block) is approximated. The pre-fix figures are in `out/win48_*.txt` and
`out/stats_rode_3_25.txt`.

## 1. Exactness — the owner's recording, 48 kHz mono

DIRECT is an export of exactly the window. ffmpeg is the independent meter on the same samples.
The cache columns snap the window to the grain (nearest) and count blocks from the exact length.
The band is DIRECT measured with the window at ten phases of its 400 ms grid (0–90 ms of digital
silence in front), which is what a clip at an arbitrary place on a timeline gets from the export.

| window (s) | length | DIRECT | ffmpeg (Δ) | cache 100 ms (Δ) | cache 25 ms (Δ) | cache 10 ms (Δ) | DIRECT's phase band | TP cache / DIRECT / ffmpeg (dBTP) |
|---|---|---|---|---|---|---|---|---|
| 0.000–30.313 | 30.3 | −44.682 | −44.687 (−0.005) | −44.682 (+0.000) | −44.682 (+0.000) | −44.682 (+0.000) | −44.682 … −44.618 | −18.526 / −18.526 / −18.544 |
| 2.282–10.475 | 8.2 | −43.513 | −43.519 (−0.006) | −43.587 (−0.074) | −43.662 (−0.149) | −43.589 (−0.076) | −43.728 … −43.513 | −24.853 / −24.853 / −24.863 |
| 2.882–14.596 | 11.7 | −44.447 | −44.451 (−0.004) | −44.398 (+0.049) | −44.386 (+0.060) | −44.388 (+0.059) | −44.489 … −44.350 | −23.850 / −23.850 / −23.859 |
| 10.381–14.844 | 4.5 | −48.456 | −48.461 (−0.005) | −48.465 (−0.010) | −48.455 (+0.001) | −48.455 (+0.000) | −48.636 … −48.272 | −23.850 / −23.850 / −23.859 |
| 5.698–28.893 | 23.2 | −45.894 | −45.900 (−0.006) | −45.898 (−0.005) | −45.898 (−0.005) | −45.898 (−0.005) | −45.894 … −45.728 | −23.850 / −23.850 / −23.859 |
| 2.326–22.159 | 19.8 | −45.178 | −45.184 (−0.006) | −45.131 (+0.046) | −45.177 (+0.000) | −45.180 (−0.002) | −45.206 … −45.048 | −23.850 / −23.850 / −23.859 |
| 4.290–19.097 | 14.8 | −44.763 | −44.769 (−0.006) | −44.902 (−0.139) | −44.902 (−0.139) | −44.762 (+0.000) | −44.889 … −44.763 | −23.850 / −23.850 / −23.859 |
| 2.497–9.296 | 6.8 | −42.881 | −42.886 (−0.005) | −42.880 (+0.000) | −42.880 (+0.000) | −42.880 (+0.000) | −43.073 … −42.873 | −24.853 / −24.853 / −24.863 |
| 20.958–28.675 | 7.7 | −56.858 | −56.863 (−0.005) | −56.820 (+0.038) | −56.864 (−0.006) | −56.856 (+0.002) | −56.907 … −56.858 | −35.347 / −35.347 / −35.359 |
| 7.322–28.558 | 21.2 | −48.516 | −48.521 (−0.005) | −48.516 (+0.001) | −48.466 (+0.050) | −48.466 (+0.050) | −48.516 … −48.363 | −23.850 / −23.850 / −23.859 |
| 1.877–22.487 | 20.6 | −45.213 | −45.219 (−0.006) | −45.187 (+0.027) | −45.212 (+0.001) | −45.176 (+0.038) | −45.238 … −45.100 | −23.850 / −23.850 / −23.859 |

**Verdict on the rule's windows: 100 ms FAILS (−0.139 LU on 4.290–19.097), 25 ms FAILS (−0.149
and −0.139), 10 ms PASSES (largest 0.076 LU).** ffmpeg agrees with DIRECT within 0.006 LU on
every window. True peak: the cache equals DIRECT on all eleven and reads 0.009–0.018 dB above
ffmpeg, well inside ±0.7 dB.

**Beyond the rule: 200 seeded windows of 3–25 s** (`lcache grains … 200 3 25 7`, `out/grains_rode.txt`),
|cache − DIRECT|:

| grain | median | p95 | max | share > 0.1 LU |
|---|---|---|---|---|
| 100 ms | 0.059 | 0.218 | 1.164 | 30.5 % |
| 50 ms | 0.035 | 0.174 | 1.164 | 16.0 % |
| 25 ms | 0.004 | 0.123 | 0.204 | 9.5 % |
| **10 ms** | **0.001** | **0.060** | **0.210** | **2.5 %** |
| 5 ms | 0.000 | 0.055 | 0.210 | 1.5 % |
| 1 ms | 0.000 | 0.044 | 0.152 | 0.5 % |

Over the same 200 windows, the measurement's own uncertainty: **DIRECT's phase spread has a
median of 0.167 LU, p95 0.476, max 3.341**, and is over 0.1 LU on 90 % of windows
(`out/stats_rode_3_25_ex.txt`). The 10 ms cache never lands more than 0.058 LU outside that band;
the 100 ms cache lands up to 0.433 outside it. **Why no grain reaches 100 %:** BS.1770 over a few
seconds of sparse speech is not a smooth function of where the window starts. DIRECT itself reads
−43.589 from 2.280 s and −43.513 from 2.282 s, 0.08 LU for 2 ms, because a 400 ms block near the
relative gate goes in or out (`out/wsens.txt`). So "±0.1 LU against one exact cut" is a bar the
quantity itself does not meet across positions on a timeline. A grain's job is to keep the
cache's offset small against that spread. 10 ms does (its residue stays inside the band), and
going to 1 ms buys only 2 more percent.

**Long windows** (30 seeded windows of 30–600 s, median 340 s, on the 20-minute file,
`out/stats_rode20_30_600.txt`): phase spread ≤ 0.059 LU, and every grain within 0.039 LU (100 ms)
or 0.018 LU (10 ms) of DIRECT. Snapping matters only for clips under about half a minute.

**True peak over the 200:** the 100 ms cache's outward-snapped peak never read under DIRECT
beyond Float32 storage rounding (17 windows lower by < 0.0001 dB), and no sample peak was ever
under.

## 2. Size and build time

**Build, 20-minute file** (the recording looped 40×, 1214.3 s, AAC re-encoded), single thread,
best of 3. The decode is AVAssetReader at the file's own rate, 32-bit float (`writePeaks`'
settings).

| file | load avg (1/5/15 min) before → after | decode | K-weighting | true peak (Double / Float) | total build incl. decode | × real time |
|---|---|---|---|---|---|---|
| mono 48 kHz | 4.81 12.20 12.12 → 4.20 11.70 11.94 | 0.521 s | 0.355 s | 0.170 / 0.081 s | 0.96 s (Float TP) | ~1 270× |
| stereo 44.1 kHz | 16.24 11.65 11.65 → 11.85 10.99 11.41 | 0.812 s | 0.650 s | 0.317 / 0.155 s | 1.62 s (Float TP) | ~750× |
| stereo 44.1 kHz, the reader converting to 48 kHz | 9.34 10.47 11.21 | 0.969 s | 0.695 s | 0.338 s (Double) | — | — |

- The grain does not change build time (100, 25 and 10 ms all take 0.55 s with Double TP,
  mono): the work is per sample. Float true peak equals Double to 2·10⁻⁶ dB per block and halves
  its cost (`lcache tpfloat`).
- For scale, the peaks pass is the decode plus a per-bucket max (0.004 s over memory). The
  loudness pass costs about 1.8× the peaks pass for mono and 2× for stereo: about 3 s an hour of
  mono and 5 s an hour of stereo, on this host under this load.
- **Reading is what the cache buys:** a whole 20-minute window reads in 1.5 ms from the 10 ms
  cache (0.28 ms from 100 ms), against 0.59 s to measure it directly after a 0.52 s decode
  (`lcache qtime`, load 6.29 8.47 10.13).

**Size** (Float32, per hour of audio; the peaks cache is 1 406 KB/h for comparison):

| layout | 100 ms | 25 ms | 10 ms |
|---|---|---|---|
| mono: z, TP | 281 KB | 1 125 KB | 2 813 KB |
| mono + sample peak (the brief's full list) | 422 KB | 1 688 KB | 4 219 KB |
| stereo: zL, zR, zLR, TPL, TPR | 703 KB | 2 813 KB | 7 031 KB |
| stereo + per-channel sample peak | 984 KB | 3 938 KB | 9 844 KB |

The mono rows are measured file sizes (`out/bench-*-*.bin`, less their 32-byte trial header);
the stereo rows are the same arithmetic, 4 bytes × columns × blocks.

## 3. Channels and rates

**Stereo** (`media/stereo.m4a`: L is the recording, R is the recording reversed at −6 dB, so the
channels differ and correlate little). Per-channel energies plus the cross term ΣyL·yR let the
cache answer any static 2×2 channel matrix exactly. On the whole file, cache = DIRECT to
0.0000 LU for identity (−45.361), the mono fold (L+R)/2 (−48.342), left only in both (−41.746),
swap (−45.361) and a balance of gL = 0.5 (−49.441). On the eleven windows, the 10 ms cache is
within 0.076 LU of DIRECT, the same snapping pattern as mono. ffmpeg reads 0.005 LU under
DIRECT on ten windows and 0.026 under on the whole file (one block at its histogram's relative
gate). TP equals DIRECT's; ffmpeg reads 0.0–0.02 dB lower. Table 3's weights are 1.0 for L and R,
so the channel sum needs no weights.

**A mono source in the export is dual mono: +3.01 LU.** The test went through an
`AVMutableComposition`, an `AVMutableAudioMix` at volume 1, and `AVAssetReaderAudioMixOutput`
with the export's own `ExportAudioGain.floatMixSettings` (48 kHz, 2 channels, float). The owner's
mono recording comes out with L = R = the mono samples, bit for bit (`lcache compmix`). So the
export's meter reads it at **−41.672 LUFS, not the −44.682 the file measures as mono**.
ffmpeg's −44.7, quoted in AU-1 and the road map, is the mono figure. A loudness cache that answers
the file's own BS.1770 number would make Normalize to −16 LUFS land at −13 in every export of a
mono clip, so the reader must apply the export's channel layout (mono: z × 2).

**44.1 kHz** (`media/rode44.wav`, the recording resampled by ffmpeg and stored as PCM, so both
decoders agree):

| path (DIRECT on each) | whole file | the ten windows against ffmpeg at 44.1 kHz |
|---|---|---|
| native 44.1 kHz decode, coefficients derived for 44.1 kHz (libebur128's bilinear transform) | −44.678 | +0.003 … +0.006 LU |
| the reader's own conversion to 48 kHz, then Tables 1/2 | −44.682 | −0.001 … +0.002 LU |
| ffmpeg 9 at 44.1 kHz | −44.683 | — |
| the 48 kHz original | −44.682 | — |

The native path reads exactly +0.004 LU above the converted (48 kHz, the export's) path on all
eleven windows; ffmpeg's steady −0.005 is its histogram, as at 48 kHz. The 10 ms cache on the
native decode is within 0.076 LU of DIRECT on the same windows, the 48 kHz pattern. Both paths
pass (≤ 0.1 LU). **At lower rates the derived coefficients drift** (whole file, native
against the reader's 48 kHz conversion, `tools/lowrates.sh`): 22.05 kHz +0.055 LU, 16 kHz
+0.096 LU. ffmpeg at the native rate agrees with the native figure within 0.005, so the cause is
the bilinear shelf's warping near Nyquist, not a bug. The reader's conversion was byte-identical
over three runs in one process on three 30 s files (44.1 kHz WAV, 44.1 kHz AAC stereo, 22.05 kHz
WAV), and across two processes for the last two. But SY-34 measured it writing different bytes on every pass on 10-minute
and one-hour files, so it is no basis for a cache that must reproduce (#285). **What the peaks
cache does about rates:** it decodes at the file's own rate and places frames by integer index
`⌊f·100/rate⌋` (`PeakBuckets`), never converting. A 10 ms loudness grid can use that rule
unchanged at any rate.

## 4. Speech-only loudness (energy spans standing in for Silero)

Spans are 100 ms blocks above a K-weighted threshold, with gaps under 300 ms closed and each span
widened 100 ms on both sides. Loudness is integrated over the 400 ms blocks that lie wholly
inside spans, gated as BS.1770.

| span threshold | speech share | BS.1770 gated | speech-only gated | difference |
|---|---|---|---|---|
| −60 LUFS | 45.7 % | −44.682 | −43.886 | +0.80 LU |
| −55 LUFS | 42.1 % | −44.682 | −43.591 | +1.09 LU |
| −50 LUFS | 31.9 % | −44.682 | −42.989 | +1.69 LU |
| −45 LUFS | 21.7 % | −44.682 | −41.512 | +3.17 LU |

At the thresholds that put speech near the survey's 35 % (65 % pauses), **speech-gated loudness
reads 1.1–1.7 LU louder than BS.1770's gate** on this recording. The relative gate drops the
pauses but keeps the blocks that straddle the edge of a word. AU-4's target is gated BS.1770 and
should stay so, because it is what platforms and the export measure. A dialogue-gated reading is
a later option, and the cache supports it once the Silero cache's 32 ms chunks are mapped onto
the 10 ms grid.

## 5. Reversed, speed, ramp

**Reversed** (eleven windows of the reversed stream; DIRECT and ffmpeg run on the sample-reversed
file, and the cache is read mirrored from the forward cache):

| reversed window (s) | DIRECT on reversed | cache 10 ms mirrored (Δ) | cache 100 ms mirrored (Δ) | ffmpeg (Δ) |
|---|---|---|---|---|
| 0.000–30.313 | −44.619 | −44.651 (−0.032) | −44.682 (−0.063) | −44.624 (−0.005) |
| 2.282–10.475 | −49.257 | −49.258 (−0.002) | −49.178 (+0.079) | −49.260 (−0.003) |
| 2.882–14.596 | −49.160 | −49.160 (+0.000) | −49.160 (−0.001) | −49.163 (−0.003) |
| 10.381–14.844 | −47.837 | −47.839 (−0.002) | −47.857 (−0.019) | −47.841 (−0.004) |
| 5.698–28.893 | −45.126 | −45.165 (−0.039) | −45.117 (+0.009) | −45.130 (−0.005) |
| 2.326–22.159 | −48.185 | −48.184 (+0.001) | −48.175 (+0.010) | −48.190 (−0.005) |
| 4.290–19.097 | −48.152 | −48.065 (+0.087) | −48.151 (+0.001) | −48.157 (−0.005) |
| 2.497–9.296 | −60.617 | −60.585 (+0.032) | −60.921 (−0.305) | −60.621 (−0.004) |
| 20.958–28.675 | −43.438 | −43.438 (+0.001) | −43.360 (+0.078) | −43.443 (−0.005) |
| 7.322–28.558 | −45.130 | −45.090 (+0.040) | −45.175 (−0.044) | −45.136 (−0.006) |
| 1.877–22.487 | −48.109 | −48.109 (+0.000) | −48.221 (−0.111) | −48.169 (−0.060) |

**10 ms passes (≤ 0.087 LU); 100 ms fails (−0.305).** One rule makes it pass: **the gating grid
is anchored at the PLAYED start, which for a reversed clip is the forward window's END**, with
the blocks laid backwards from there. Anchored at the forward start instead (the first run,
`out/mirror10ms.txt`), the 10 ms cache was off by up to 0.395 LU. Running the K-weighting over the
forward file rather than the reversed one costs nothing measurable at this grain. TP equals
DIRECT's on every window. The peaks cache mirrors through `ReverseMirror` inside
`MediaPeaks.window`. A 10 ms loudness grid is the same 6 000-tick grid, so the same call gives the
mirrored block range (its "one tick high" moves a boundary by 1/600 000 s), and only the gating
anchor is new.

**Speed** (ffmpeg on the window played at a speed, against two cache readings of the source
window; whole file, then the range over five windows, in LU; `out/speed.txt`,
`out/speed_cache.txt`):

| played − cache reading | ×0.5 | ×0.8 | ×1.25 | ×2 |
|---|---|---|---|---|
| varispeed − source reading (×1 gating) | −0.35; −0.51 … +0.11 | −0.07; −0.21 … +0.12 | −0.05; −0.03 … +0.26 | −0.13; −0.03 … +0.44 |
| varispeed − time-scaled gating | −0.89; −0.81 … −0.69 | −0.18; −0.29 … −0.20 | +0.15; +0.11 … +0.35 | +0.72; +0.67 … +0.78 |
| pitch kept (`atempo`) − source reading | +0.52; +0.17 … +0.79 | +0.33; −0.03 … +0.37 | −0.32; −0.32 … −0.01 | −0.71; −0.79 … +0.08 |
| pitch kept (`atempo`) − time-scaled gating | −0.02; −0.18 … +0.05 | +0.21; −0.14 … +0.06 | −0.13; −0.43 … +0.33 | +0.13; −0.54 … +0.34 |

"Time-scaled gating" means a played 400 ms block reads 400·s ms of source. Neither reading is
within 0.1 LU of what plays at ×0.5–×2; the better of the two is within about 0.5 LU. With pitch
kept, the spectrum is the source's, and time-scaled gating explains most of the change (ffmpeg's
`atempo` stands in for Apple's time-pitch here, so part of the residue is `atempo`'s own).
Varispeed also moves every frequency by s, and the K-weighting is not flat (a +4 dB shelf above
2 kHz, the RLB high-pass at 38 Hz), so no broadband block energy can predict it; there the plain
source reading happens to be the closer of the two. Exact needs a direct pass with the
coefficients derived at rate·s, about 1 ms per second of source. **How the peaks cache handles
speed:** `MediaPeaks.sourceTick` maps project time to source time at the segment's own
`sourceDuration/duration`, and a max does not care about time scale. Loudness does: the same
window mapping applies, and the reader must add the played-time gating.

**Ramp** (read from the code, not measured): a ramped clip's audio segment is one ×1 segment
playing a render in `cache/ramp-audio/` (`RampAudioCache`, SR-12), and `MediaPeaks.sourceTick`
reads `⌊S(t − start)⌋` off its source map. For loudness the render IS what plays, at ×1, so a
cache built over the render (or a direct pass when it lands, since the renderer holds the samples
anyway) is exact. Reading the media's cache through S(t), block by block with time-scaled gating
from the map, is the fallback while a render is pending, and it inherits the speed table's error.

---

## The proposed format (mirrors the peaks cache)

- **Files:** `cache/loudness/<media id>.bin` and a sidecar `cache/loudness/<media id>.complete.json`
  (`peaksMarkerURL`'s shape). They are cleared marker-first and published inside one
  `CacheLedger.publish` with a `mediaCacheDidChange` post of a new kind, `loudness`, exactly as
  `finishPeaks` does.
- **Marker:** `LoudnessStamp { source: CacheStamp, version: Int, channels: Int, sampleRate: Int,
  blocksPerSecond: Int, oversample: Int }`, the versioned wrapper of `PeaksStamp` and
  `SpeechStamp`. A marker of another `loudnessVersion`, or one that will not decode, reads as
  absent and the cache is made again (SY-34's no-migration posture). `channels` gives the record
  width. `blocksPerSecond` (100) and `oversample` (4) are in it so that a build changing either
  rebuilds.
- **The `.bin`:** headerless little-endian Float32 records, one per 10 ms block. The block count
  is `⌈duration·100⌉` from the marker's `source.duration` (`loadPeaks`' rule), so the reader
  checks `data.count == count × width × 4`, and that every value is finite and z and tp are ≥ 0
  (zLR may be negative).
  - mono, width 2: `z, tp`
  - stereo, width 5: `zL, zR, zLR, tpL, tpR`
  - `z` is the mean of the K-weighted samples squared over the block's frames (BS.1770's zᵢ for
    that block), and `zLR` is the mean of yL·yR. Storing MEANS keeps a gating block the plain
    average of forty records at any rate. `tp` is max(4× interpolated |x|, |x|) over the block,
    linear and unclamped (`LoudnessReport`'s rule that true peak is never below sample peak).
  - Sample peak is not stored: the peaks cache already has it per 10 ms.
- **Placement:** `PeakBuckets`' rule verbatim. Decode at the file's own rate, take the frame index
  from the buffer's PTS − the MP3 lead (SY-42), put frame f in block `⌊f·100/rate⌋`, and run the
  same `covers(expected)` check before publishing. An internal edit gap stays zero, which reads as
  silence, as it plays.
- **K-weighting:** Tables 1 and 2 at 48 kHz. At any other rate, the coefficients derived from the
  analog prototype (libebur128's derivation, which ffmpeg 9 uses too): ≤ 0.005 LU at 44.1 kHz,
  0.055 at 22.05 and 0.096 at 16 kHz against the export's 48 kHz path. The filter state runs
  continuously across the file. True peak is computed in Float (`vDSP_conv`) with the Annex 2
  table as `Loudness.swift` transcribes it, history carried across blocks.
- **More than two channels:** not measured. The export downmixes to stereo, so the simplest honest
  answer is to ask the reader for 2 channels (`AVNumberOfChannelsKey`) for such a file and store
  the stereo record, with a check that the reader's downmix matches the export's mix output.

## The reader (what AP1 computes from it)

1. **Window:** `MediaPeaks.window(of:from:to:reversedPivot:bucketTicks: 6000, count:)` gives the
   block range with the mirror and the source map already applied (the 10 ms grid IS the peaks
   grid).
2. **Gating blocks:** 40 records each (400 ms), hop 10. Their NUMBER comes from the exact played
   length, `⌊(L − 0.4)/0.1⌋ + 1`. They are laid from the played start: the range's low end for a
   forward clip, its HIGH end for a reversed clip, stepping backwards. At a constant speed s, use
   40·s records with a hop of 10·s (time-scaled gating; an estimate, see §5). The blocks of every
   segment a clip plays are pooled and gated once.
3. **Channels:** mono z × 2 (the export's dual mono, +3.01 LU). Stereo goes through the 2×2 matrix
   the clip's channel settings apply: identity today, and AP3's left, right, swap and the mono
   fold exactly.
4. **Gates:** −70 LUFS absolute, then −10 LU relative, once (`LoudnessMeter.integrated`).
5. **Gain:** add 20·log10(volume) for the base volume, which is exact. Fades, ducks and volume
   actions would weight each record by the envelope² (not measured; Normalize reads the material
   pre-fader, so it does not need it).
6. **True peak:** the max of `tp` over the range snapped OUTWARD. It never reads under, and it can
   over-read by up to 10 ms of neighbouring material. A channel pick reads its own channel's `tp`;
   a mix of channels (mono fold, pan) gets the bound |m₀|·tpL + |m₁|·tpR.
7. **What the cache cannot answer:** anything after a non-linear or spectral stage — the
   compressor and noise reduction today, and AP3–AP5's EQ, gate, de-esser, limiter and isolation.
   The readout is the material's loudness (pre-chain), as the peaks are pre-fader. A processed
   loudness needs a render.

## Recommendation for AP1

**Build the loudness cache at 10 ms, not 100 ms.** 100 ms fails the rule (0.139 LU on a named
window; 30 % of 3–25 s windows over 0.1 LU, up to 1.16), and so does 25 ms (0.149; 9.5 %). 10 ms
passes every named window: forward (≤ 0.076 LU), reversed (≤ 0.087), stereo (≤ 0.076) and
44.1 kHz (the same pattern). Over 200 short windows it lands within 0.1 LU of an exact cut on
97.5 % (max 0.21), its residue always inside the measurement's own grid-phase spread (never more
than 0.058 LU outside it); a 1 ms grain shrinks the 2.5 % only to 0.5 %. Long windows (30 s and
up) agree within 0.02 LU. A 10 ms grid is also the peaks grid, so `MediaPeaks.window`,
`ReverseMirror` and the source map are reused as they are.

**Store** per 10 ms block the K-weighted mean square per channel, the stereo cross term, and the
4× true peak per channel, all Float32: 2.75 MB an hour for mono and 6.9 MB an hour for stereo,
about 2× and 5× the peaks cache. **Build** it on the cache lane after peaks, as its own pass with
its own marker (`loudnessVersion` 1), decoding at the file's own rate. On this host under load
that took ~1 s per 20 minutes of mono and ~1.6 s for stereo at 44.1 kHz (about 750–1 300× real
time), with Float true peak. Folding it into the peaks decode would save the decode (about half
its cost) but would tie the two caches' versions together; at these numbers it is not worth it.

**The reader must carry three rules,** each measured here: the gating-block count comes from the
exact window length; the grid is anchored at the played start (a reversed clip's forward END);
and the export's channel layout applies. **A mono clip reads +3.01 LU in the export**, so the
owner's recording is −41.7 LUFS to Frame Job's export meter, not the −44.7 the road map and AU-1
quote. AP1's Normalize must target the export's figure.

**Say what the number is.** The readout is as accurate as the measurement itself. For a clip under
about 25 s of sparse speech, BS.1770 itself moves by a median 0.17 LU (p95 0.48) depending on where
the clip lands on the export's block grid. AP1's ±0.5 LU export proof is the right tolerance; a
±0.1 LU claim against a different window position is not. A clip at a speed other than ×1 reads
within about 0.5 LU (time-scaled gating suits Keep pitch; varispeed needs a direct pass at rate·s
to do better). A ramped clip should be measured on its ×1 render, which is exact. Sources at
22.05 kHz or below read 0.05–0.1 LU high against the export, unless AP1 adds its own deterministic
resampler for them (SY-34's `SyncResampler` pattern), because the reader's own conversion does not
reproduce on long files.

**Open for AP1 (not measured here):** files with more than two channels; the envelope weighting
for a post-fader readout; whether a constant-speed clip gets a direct measurement or the
time-scaled estimate; and Silero spans on the 10 ms grid, if a dialogue-gated reading is ever
wanted (+1.1–1.7 LU on this file).
