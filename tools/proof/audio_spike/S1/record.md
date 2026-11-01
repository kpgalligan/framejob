# Spike S1 — own DSP or Apple's units for the live audio stages

Road map "audio", AP0 (`archive/audio.md`), decision AU-3 (`designs/spec/11-decisions/audio.md`).
Product code read at commit `9e47f56` (`AudioDSP.swift`, `AudioTap.swift`,
`CompositionBuilder+AudioTracks.swift`), never the working tree. Everything below lives in
`/private/tmp/claude-501/-Users-kevingalligan-devel-framejob/9bb0487d-a352-45e3-9da8-07b6f4762c27/scratchpad/ap0/S1/`.

## The rule (written 2026-10-30, before anything was built or run)

**Question.** AU-3 says the live stages (EQ and high-pass, hum notch, gate/expander, de-esser,
true-peak limiter) are Frame Job's own DSP inside the existing PreEffects
`MTAudioProcessingTap`, and Apple's units only for ML isolation and voice effects (offline). S1
may overturn the first half by measurement. It measures, stage by stage, (a) own DSP in Swift and
(b) Apple's units, both driven inside an `MTAudioProcessingTap` on an `AVMutableComposition`
audio track read through `AVAssetReaderAudioMixOutput` (the export's path).

**Subjects.**
- (a) Own, written for the spike in Frame Job's style (buffers allocated once, nothing allocated
  or locked in `process`): RBJ-cookbook biquads computed in Double (high-pass 2nd order Q=0.7071;
  4th-order Butterworth high-pass as two sections Q=0.5412/1.3066; peaking; low and high shelf
  S=1; notch), a downward expander, a copy of the shipped compressor, and a lookahead
  true-peak limiter (4× polyphase FIR peak detection, sliding minimum over the lookahead,
  release, box-filter attack; ceiling −1 dBTP).
- (b) Apple: `AUNBandEQ` (raw component and through `AVAudioUnitEQ`'s `audioUnit`),
  `AUPeakLimiter`, `AUDynamicsProcessor`; hosted three ways — v2 `AudioUnitRender` with a C input
  callback fed from the tap's buffer; v3 `AUAudioUnit.renderBlock` with a pull block built once
  outside the callback; `AVAudioEngine` in real-time manual rendering mode.

**Measurements.**
1. **Feasibility inside the tap.** Units created and initialised outside `process` (in
   `make`/`prepare`), rendered synchronously inside it. Instrument: an interposing dylib
   (`DYLD_INSERT_LIBRARIES`) counting `malloc`/`calloc`/`realloc`/`free`/`malloc_zone_*`,
   `pthread_mutex_lock`, `os_unfair_lock_lock`, `pthread_rwlock_*`, `dispatch_semaphore_wait` and
   `pthread_cond_wait` on the render thread, only while armed around the stage's own call (first
   call and steady state reported separately), plus the libmalloc `malloc_logger` hook as a
   second allocation count that also sees calls inside libsystem. Recorded: what fails, which
   error, which property must be set.
2. **Determinism.** The same composition read twice (fresh taps and units each read), float32
   output compared by SHA-256; also across two processes; also block-size invariance offline
   (the same signal processed at 1024, 4096 and irregular block sizes, bytes compared), because
   the preview's player and the export's reader hand the tap different buffer sizes. If the
   player can be run headless, the tap's output in the preview path against the export path.
3. **Correctness.** EQ magnitude at 20 log-spaced frequencies 20 Hz–20 kHz (stepped sine through
   the tap, single-bin DFT, wet/dry) against (own) the analytic RBJ response of the same
   coefficients' design and (Apple) the documented anchors: high-pass −3.01 dB at its frequency
   (documented "Butterworth 2nd order"), peaking gain at centre = the gain parameter, shelf
   plateau = the gain parameter, band-stop depth at centre; plus Apple's deviation from the RBJ
   response at the same nominal parameters. Limiter: maximum true peak of the output (my own 4×
   oversampler, 64 taps per phase, independent of the limiter's detector; ffmpeg `ebur128`
   true peak as a cross-check) against the −1 dBTP ceiling, over the RØDE file gained +28 dB in
   the tap and over a crest test signal (fs/4 sine at 45°, alternating impulses, abrupt noise
   bursts, a low tone with clicks).
4. **Latency.** Cross-correlation of wet against dry (white noise for the EQs; a level below the
   threshold for the limiter and dynamics), per 4096-sample window, across two runs and across
   parameter values a clip can hold (e.g. the limiter's attack); compared with
   `kAudioUnitProperty_Latency`.
5. **CPU.** µs per 1024-frame buffer, mono and stereo, per stage and for an 8-stage chain
   (HPF4, hum notch, low shelf, peaking, high shelf, expander, compressor, limiter); Apple as one
   unit per stage (8 units) and as 3 units (one 6-band `AUNBandEQ`, one `AUDynamicsProcessor`,
   one `AUPeakLimiter`). Min of 3 runs, each run's mean over ≥ 2000 buffers; load average
   recorded at each run.
6. **Limits.** Sample rates 44.1/48/96/192 kHz and channel counts 1/2/6/8 accepted at
   initialisation; parameter changes mid-stream (an abrupt EQ gain step on a 1 kHz tone): the
   energy splattered outside the tone in the 50 ms after the step, for own unsmoothed, own with
   per-sample parameter smoothing, and Apple with `AudioUnitSetParameter` between renders.

**Verdict criteria, per stage, fixed now.** A subject is *admissible live* for a stage when it
passes all five:
- **F** zero allocations and zero lock acquisitions on the render thread in steady state (a
  first-call allocation is recorded and fails F only if it recurs), and it renders correctly
  inside the tap on the export path;
- **D** two reads byte-identical, AND block-size invariant (otherwise the preview and the export
  differ and no proof can compare bytes);
- **C** EQ within ±0.1 dB of its analytic/documented response at all 20 frequencies; limiter
  true peak ≤ ceiling + 0.1 dB on both signals with the ceiling settable to −1 dBTP;
- **L** latency constant (one value across windows, runs and every parameter value a clip may
  hold) and ≤ 512 samples at 48 kHz (the shipped noise reducer's accepted 10.7 ms);
- **P** the 8-stage chain on a stereo track ≤ 1 % of real time (≤ 213 µs per 1024 frames at
  48 kHz).

Then: own admissible and Apple not → **AU-3 stands** for that stage. Both admissible → AU-3
stands unless Apple is ≥ 2× cheaper for the stage, which would be recorded as an amendment
naming that stage. Apple admissible and own not → **amend AU-3**: that stage uses the Apple
unit. Neither → the stage cannot run live and renders offline (the road map's CPU risk line).

---

## Verdict

**AU-3's first half stands for every live stage: EQ and high-pass, hum notch, gate/expander,
de-esser and true-peak limiter are Frame Job's own DSP in the tap. No amendment.** No Apple unit
is admissible live for any stage under the rule:

| Stage | Own (F D C L P) | Apple unit | Apple (F D C L P) | Verdict |
|---|---|---|---|---|
| EQ: peaking, shelves, 2nd-order high-pass | ✓ ✓ ✓ ✓ ✓ | `AUNBandEQ` / `AVAudioUnitEQ` | ✓ **✗** ✓ ✓ ✓ | own |
| High-pass, 4th-order Butterworth | ✓ ✓ ✓ ✓ ✓ | `AUNBandEQ` (two HP bands) | ✓ **✗ ✗** ✓ ✓ — only Linkwitz-Riley | own |
| Hum notch | ✓ ✓ ✓ ✓ ✓ | `AUNBandEQ` band-stop | ✓ **✗** ✓ ✓ ✓ | own |
| Gate / downward expander | ✓ ✓ ✓ ✓ ✓ | `AUDynamicsProcessor` | ✓ **✗ ✗** ✓ ✓ | own |
| De-esser | (a sidechain biquad into the compressor; both parts proved here) | none ships in macOS | — | own |
| True-peak limiter | ✓ ✓ ✓ ✓ ✓ | `AUPeakLimiter` | ✓ **✗ ✗ ✗** ✓ | own |

Why each Apple ✗ (details in the sections below):
- **D, all of them:** not block-size invariant. Apple's output depends on how the stream is
  cut into render calls. For `AUNBandEQ` and `AUPeakLimiter` the difference is float rounding
  (−145 to −223 dBFS). For `AUDynamicsProcessor` it reaches **−34 dBFS** when slices are
  irregular. Irregular slices are what `AudioTap` itself produces when it splits a buffer at a
  cut, and the player and the export reader cut the stream differently (4096 against 512
  frames).
- **C, limiter:** `AUPeakLimiter` limits **sample** peak, at a fixed ceiling of about 0 dBFS. On
  the crest signal its output reaches **+3.10 dBTP**, and still +2.10 dBTP with a −1 dB trim
  after it.
- **C, dynamics:** `AUDynamicsProcessor` has no documented gain law, so nothing can be proved
  against an analytic response. Its compressor has no ratio parameter: the curve is defined by
  threshold and headroom.
- **C, 4th-order high-pass:** `AUNBandEQ`'s high-pass bands cascade to Linkwitz-Riley only
  (−6.02 dB at fc, as documented). A Butterworth-4 is 3.0 dB away from that.
- **L, limiter:** `AUPeakLimiter`'s latency *is* its attack time (48 / 96 / 1440 samples at
  1 / 2 / 30 ms, measured and reported alike). If a clip's attack differed from its
  neighbour's, the track's delay would jump at the cut. Measured: 48 → 1440 samples at a
  mid-stream attack change.

**Robustness of the verdict.** The one close call is EQ. `AUNBandEQ` is exact (it *is* the
RBJ cookbook), real-time clean, and its D failure is rounding-sized. If D were relaxed to
"within −140 dBFS", it would be admissible for EQ and the notch. Even then it is only
**1.5–1.6× cheaper** than own Double biquads (7.2 → 4.8 µs per band, stereo), under the 2× bar.
And its parameter changes are smoothed internally over 3–27 ms, out of Frame Job's control,
where own stages can switch at the cut sample or glide per sample (what AP8 automation
needs). So AU-3 stands even under that relaxation.

**The owner's other half of AU-3 is untouched.** Apple's units stay for ML isolation and voice
effects, offline (S2 measures `AUSoundIsolation`). Feasibility below also shows Apple's units
*can* be hosted in the tap without allocation or locks, should a later phase want one live. The
hosting recipe is recorded for that case.

## Method

All code is in this folder: `src/*.swift` (tool `bin/s1`, built by `build.sh` with `swiftc -O`,
Swift 6.2.3), `rtcheck/rtcheck.c` (`librtcheck.dylib`), `gen_signals.py` and `analyze_*.py`.
`run.sh <cmd>` runs the tool with the dylib inserted; `patches/` holds the edit scripts applied
during the run. Outputs are raw float32 and text in `out/`. Machine: Apple M2 Max (12 cores),
macOS 26.5.1.

- **The export's path, as the product builds it.** `AVMutableComposition` → one audio track →
  `AVMutableAudioMixInputParameters.audioTapProcessor` = an `MTAudioProcessingTap` created with
  `kMTAudioProcessingTapCreationFlag_PreEffects` (as `AudioTap.make` at 9e47f56) →
  `AVAssetReaderAudioMixOutput` in interleaved 32-bit float at 48 kHz. The stage runs inside the
  process callback after `MTAudioProcessingTapGetSourceAudio`, in place on the tap's planar
  buffers. The dry read through this path is byte-identical run to run, as `AudioTap.swift`
  records.
- **Own stages** (`OwnDSP.swift`, `OwnLimiter2.swift`):
  - RBJ biquads, transposed direct form II in Double, per sample.
  - A downward expander (linked peak follower, −50 dB threshold, 2:1, 24 dB range, 1 ms open,
    100 ms close).
  - The shipped compressor's arithmetic, copied.
  - The true-peak limiter: 2 ms lookahead, 100 ms release, −1 dBTP ceiling. A sliding minimum
    of the required gain over hold = look + 2H − 1 samples, a release that never rises above
    it, a look-sample box filter, and the audio delayed look + 2H − 2 samples. H is half the
    detector's taps, so every sample in a peak's interpolation support is gained by no more
    than that peak requires.
  - Buffers are allocated in `prepare`; nothing is allocated or locked in `process`.
- **Apple hosts** (`AppleHost.swift`):
  - v2: `AudioComponentInstanceNew` outside the tap. Formats, `MaximumFramesPerSlice`,
    `NumberOfBands` and the render callback are set in `prepare`, then `AudioUnitInitialize`.
    In `process`, a snapshot of the tap's buffer goes to the C input callback and
    `AudioUnitRender` writes into the tap's own buffer list.
  - The same through `AVAudioUnitEQ.audioUnit`.
  - v3: `AUAudioUnit.renderBlock`, called both the plain Swift way and block-typed.
  - `AVAudioEngine` in `.realtime` manual rendering.
- **Settings shared by both sides:**
  - HPF 80 Hz (Q 0.7071, and Butterworth-4 as Q 0.5412 / 1.3066).
  - Peaking 1 kHz +9 dB Q √2; `AUNBandEQ` gets the bandwidth in octaves from RBJ's digital
    relation.
  - Low shelf 200 Hz +6 dB S=1; high shelf 8 kHz +6 dB S=1.
  - Notch 60 Hz Q 10.
  - "eq6" is HPF4 + notch + the two shelves + peaking.
  - Expander as above. Compressor −18 dB, 3:1 (Apple: threshold −18, headroom 5).
  - Chains: own chain8 is the eight stages; Apple chain8 is one unit per stage; Apple chain3
    is eq6 + one `AUDynamicsProcessor` + `AUPeakLimiter`.
- **Fixtures:**
  - The owner's `samples/Rode-usb-mic.m4a`.
  - Synthetic signals from `gen_signals.py` (seeded):
    - a stepped sine: 20 log-spaced frequencies from 20 Hz to 20 kHz plus 6 anchors, 1 s each
      at −20 dBFS;
    - white noise at −20 dBFS RMS, mono and stereo, 10 s, and at −40 dBFS for 6 s;
    - a crest signal (a: fs/4 at 45°, sample peak 0 dBFS / true peak +3.01; b: +1+1−1−1 pairs;
      c: abrupt white bursts; d: 60 Hz with full-scale clicks; e: a −40 → +6 dBFS step at
      1 kHz; f: 3 s of pink noise);
    - a 1 kHz tone at −20 dBFS.
- **Instrument for F: the rtcheck dylib.**
  - It interposes the allocator, `pthread_mutex_lock`/`trylock`, `os_unfair_lock_lock`/
    `trylock`, `pthread_rwlock_*`, `dispatch_semaphore_wait` and `pthread_cond_*wait`.
  - It counts only on the armed thread, between arm and disarm around the stage call.
  - libmalloc's `malloc_logger` gives an independent second allocation count.
  - The positive controls (`run.sh control`) all fire: an array allocation, `NSLock`
    (lock 1), `os_unfair_lock` (lock 1) and `DispatchSemaphore` (lock 1). A Swift `String`
    interpolation also takes 1 lock.
  - Its blind spot: locks taken inside libsystem itself (a `DispatchQueue.sync` shows its
    allocation but no lock).

**What changed during the run.** The verdict criteria did not change. These were added or
fixed during the run:
- The own limiter's detector was revised: 12-tap Hann → 32 → 48 → 64-tap Kaiser → 64-tap plus
  Annex 2. The first version failed C.
- A tap-outer detector loop was added, after the block-invariant scalar loop failed P (281 µs
  stereo chain).
- The Annex 2 meter was added beside mine, and my meter's off-centre window was fixed (it had
  read +0.09 dB at fs/4).
- The EQ step was moved onto a block boundary; the first run never fired it.
- The `AVAudioUnitEQ` host stopped resetting the band count to 1.
- v3 hosting was fixed (input bus, block-typed calls).
- Added: the muted-player preview comparison (with `preview-skip` and `preview-reset`), the
  `reset()` real-time check (`resetrt`) and the `vDSP_biquad` slicing probe (`vdsp`).

Every number in this record comes from the final instrument.

## Results

### 1. Feasibility inside the tap (`out/feas.txt`, `out/resetrt.txt`)

The export path calls the tap 938 times over 10 s, in 512-frame buffers (one of 256).
`prepare` gives maxFrames 4096, on one thread. **That thread is AudioToolbox's
`ProcessingTapManager` real-time thread** (`caulk::thread_proxy … ProcessingTapManager::RTState`
in every backtrace), even for an `AVAssetReader`, so the real-time rules bind on the export too.
`MTAudioProcessingTapGetSourceAudio` itself allocates and locks nothing.

| Host | first call | steady state (937 calls) | output |
|---|---|---|---|
| own: every stage, chain8 | 0 alloc, 0 lock | 0, 0 | ok |
| v2 `AudioUnitRender` (`AUNBandEQ` 1–6 bands, `AUPeakLimiter`, `AUDynamicsProcessor`, chain3, chain8) | 0, 0 | 0, 0 | ok |
| v2 via `AVAudioUnitEQ.audioUnit` | 0, 0 | 0, 0 | ok |
| v3 `renderBlock`, plain Swift call | 1 malloc + 1 free | **937 + 937** (`_Block_copy` per call) | ok |
| v3 `renderBlock`, block-typed | 0, 0 | 0, 0 | ok |
| `AVAudioEngine` real-time manual rendering | 0, 0 | 0, 0 | ok |
| `reset()` on the render thread: own, `AudioUnitReset`, v3 `reset()` | 0, 0 | 0, 0 | — |
| `AVAudioEngine.reset()` | 3 locks | **3 locks per call** | — |

Mono and stereo give the same counts.

What broke, and the fix for each:
1. **v3, kAudioUnitErr_NoConnection (−10876) on every render.** The v2 bridge's input bus
   starts *disabled*. Set `au.inputBusses[0].isEnabled = true` before
   `allocateRenderResources()`.
2. **v3, one malloc per render.** Swift bridges the pull closure to a block with
   `_Block_copy` on every `renderBlock` call. Hold both as `@convention(block)` values: the
   render block taken as the Objective-C object (`value(forKey: "renderBlock")`) and the pull
   block made once. Then nothing is allocated.
3. **The v2 bridge pulls its input once per timestamp.** Four renders at the same
   `mSampleTime` pulled the input once and rendered stale input after that. Advance
   `mSampleTime` by the frame count on every render.
4. `AUNBandEQ`'s band bypass defaults to **1 (bypassed)**. It has 8 bands by default and 16 at
   most; `kAUNBandEQProperty_NumberOfBands` must be set before `AudioUnitInitialize`. My
   first `AVAudioUnitEQ` run was wrongly cheap because my host reset its band count to 1.
5. `AVAudioEngine.reset()` takes locks, so the engine route cannot reset at a seek or at
   StartOfStream from the render thread.

**Hosting recipe, if a later phase ever wants an Apple unit live:**
- v2: create the instance with the composition, not in the callback. In `prepare`, set the
  stream format (non-interleaved Float32) on the input and output scopes,
  `MaximumFramesPerSlice` ≥ max(maxFrames, 4096), the band count and the render callback;
  then `AudioUnitInitialize`, then the parameters.
- In `process`: copy the tap's buffer into preallocated input buffers, call
  `AudioUnitRender(unit, …, frames, tapBufferList)`, advance `mSampleTime`.
- `AudioUnitReset` on StartOfStream or a seek.

### 2. Determinism (`out/det_run1.txt` … `det_run5.txt`, `out/det_<pid>.txt`)

- **Two reads of the same composition, fresh taps and units:** byte-identical for **every
  subject, own and Apple**, over the RØDE file and stereo white noise.
- **Across two processes:** identical for all 42 subjects, every read and every block pattern
  (`diff det_98958.txt det_3559.txt`, and the earlier pair).
- **Block-size invariance:** the RØDE decode +20 dB, processed offline at 1024, at 4096 and at
  an irregular cycle (1, 7, 333, 4096, 128, 999, 2048, 17, 512, 3000).

| Subject | 1024 = 4096 = irregular? | worst difference |
|---|---|---|
| own Double biquads (every type, eq6), expander, compressor, scalar or tap-outer limiter, chain8 | **identical** | — |
| own limiter, `vDSP_conv` detector | 1024 = 4096; irregular differs | 1 LSB, −144.5 dBFS |
| own eq6 through `vDSP_biquad` | differs unless every block is a multiple of 4 | −96 to −101 dBFS |
| `AUNBandEQ`, `AVAudioUnitEQ`, `AUPeakLimiter` | the three patterns are not all equal for any of them, except the high-shelf band (identical in this run) | −145 to −223 dBFS |
| `AUDynamicsProcessor` (expander only) | 1024 = 4096; irregular differs | −93 dBFS |
| `AUDynamicsProcessor` (compressing), Apple chain3/chain8 | irregular differs | **−34 dBFS** / −33 dBFS |
| `AVAudioUnitEQ`, bands set through AVFoundation's API | irregular differs from sample 0 | −76 dBFS (its parameter changes ramp in) |

**Preview against export** (`out/preview.txt`, `out/preview_skip.txt`). The same composition
and tap run under a **muted `AVPlayer`** (no sound made), with the tap's output captured:
- The player calls the tap with **4096-frame buffers**, against the export's 512.
- Its **first callback has no valid time and carries silence**. **StartOfStream arrives on the
  second.**
- A muted player feeds the tap silence after about 4.0 s, so the comparison covers the first
  188,416 frames.

Results on the RØDE file:

| Subject | preview = export? |
|---|---|
| dry, own eq6, own limiters, `AUPeakLimiter` | **identical** |
| `AUNBandEQ` eq6 | 35 samples differ, at −199 dBFS |
| own chain8, the pre-roll processed like any buffer | differs from frame 158 (−56 dBFS) |
| `AUDynamicsProcessor`, the pre-roll processed like any buffer | differs from frame 256 (−46 dBFS) |
| own chain8, own expander, `AUDynamicsProcessor` (all three settings), with the pre-roll left unprocessed (`preview-skip`) | **identical** |
| own chain8, own expander, `AUDynamicsProcessor`, with the stage reset when StartOfStream arrives (`preview-reset`, as `AudioTap` does; `AudioUnitReset` for Apple) | **identical** |
| Apple chain3 / eq6, either way | −205 / −199 dBFS |

For own chain8 and `AUDynamicsProcessor`, the cause is that the silent pre-roll closes the
expander before the audio arrives. The shipped `AudioTap` resets on StartOfStream, so it
already escapes this, *provided every new stage's `reset()` restores its fresh state*: own
stages' resets and `AudioUnitReset` both do, as measured above.

### 3. Correctness

**EQ** (`out/resp_analysis.txt`). The stepped sine runs through the tap; amplitude comes from a
least-squares sine fit over the last 0.5 s of each step, wet against dry. The analytic response
is the RBJ cookbook, computed independently in numpy from the band parameters. The Swift
coefficients equal it to 0.00e+00 dB.

| Band | max \|own − RBJ\| | max \|AUNBandEQ − RBJ, same parameters\| | AUNBandEQ against its documented form | AVAudioUnitEQ − AUNBandEQ |
|---|---|---|---|---|
| HPF 80 Hz, 2nd order | 0.0000 dB | 0.000 | 0.000 ("Butterworth 2nd order"; −3.010 dB at 80 Hz) | 0.0000 |
| HPF 80 Hz, 4th order | 0.0000 (Butterworth) | 3.010 (−6.021 dB at 80 Hz) | 0.000 (two Butterworth-2 = Linkwitz-Riley) | 0.0000 |
| Peaking 1 kHz +9 dB, Q √2 | 0.0000 (+9.000 at 1 kHz) | 0.000 | 0.000 | 0.0000 |
| Low shelf 200 Hz +6 dB | 0.0000 (+3.000 at 200 Hz) | 0.000 | 0.000 | 0.0000 |
| High shelf 8 kHz +6 dB | 0.0000 (+3.000 at 8 kHz) | 0.000 | 0.000 | 0.0000 |
| Notch 60 Hz Q 10 | 0.0005 | 0.001 | 0.001 | 0.0000 |

The notch depth at 60 Hz reads −101.5 dB for both, which is the measurement floor. The
surprise is that **`AUNBandEQ` is the RBJ cookbook**, its bandwidth in octaves being RBJ's
digital BW. So EQ correctness does not separate the two.

**Limiter** (`out/lim_analysis.txt`). The true peak comes from my own 4× meter: 64 taps per
phase, Kaiser β 10, the window taken at each tap's own distance. Its self-checks: fs/4 at 45°
reads 0.0000 dBTP (sample peak −3.010); 997 Hz reads +0.0001; 12/18/20 kHz read −0.037/−0.037/
−0.006. Beside it are the BS.1770-4 Annex 2 12-tap meter that `Loudness.swift` and
`phase5_proof.py` use, and ffmpeg `ebur128`.

| Case | RØDE +28 dB: true pk / Annex 2 / ffmpeg | crest: true pk / Annex 2 / ffmpeg | LUFS (RØDE, ffmpeg) |
|---|---|---|---|
| dry | +9.461 / +9.474 / +9.5 | +8.974 / +8.934 / +9.0 | −16.7 |
| own, 64-tap Kaiser + Annex 2 detector (**chosen**) | **−1.000 / −1.000 / −1.0** | **−1.000 / −1.000 / −0.9** | −18.5 |
| own, 64-tap detector | −1.000 / −0.860 / −1.0 | −1.000 / −0.799 / −0.9 | −18.5 |
| own, 48-tap | −1.000 / −0.860 / −1.0 | −0.829 / −0.779 / −0.9 | −18.5 |
| own, 32-tap | −1.000 / −0.861 / −1.0 | −0.705 / −0.777 / −1.0 | −18.5 |
| own, 12-tap Hann (first version) | −1.000 / −0.860 / −1.0 | **−0.026** / −0.509 / −0.3 | −18.5 |
| `AUPeakLimiter` (default 2 ms) | +0.003 / +0.041 / 0.0 | **+3.102** / +3.093 / +3.1 | −17.8 |
| `AUPeakLimiter`, then −1 dB | −0.997 / −0.959 / −1.0 | **+2.102** / +2.093 / +2.1 | −18.8 |
| `AUPeakLimiter` attack 1 ms / 30 ms | −0.005 / +0.071 | +3.102 / +3.102 | −17.8 / −18.1 |

`AUPeakLimiter` leaves parts a (fs/4 at 45°) and b of the crest signal untouched at
**+3.10 dBTP**: its samples sit at 0 dBFS, so a sample-peak limiter sees nothing to do. Its
ceiling is fixed (no parameter), and its release only reaches 40 ms.

The own limiter passes C only with the 64-tap + Annex 2 detector. See builder notes 1–2: this
subject was revised during the run.

### 4. Latency (`out/lat_analysis.txt`)

Measured as the lag of the cross-correlation peak, per 4096-sample window, over two runs: 220
windows on white noise for the EQs, 126 on −40 dBFS noise for the dynamics. **Every subject had
exactly one lag across all windows and both runs, and it equalled the reported or claimed
value:**

| Subject | samples at 48 kHz | constant across parameters? |
|---|---|---|
| own biquads (every type), own expander, own compressor | 0 | yes |
| own limiter, 2 ms lookahead: 32-tap / 64-tap + Annex 2 | 126 / **158 (3.3 ms)** | yes (fixed by the design) |
| own chain8 | 158 | yes |
| `AUNBandEQ` / `AVAudioUnitEQ` | 0 | yes |
| `AUDynamicsProcessor` | 256 (5.3 ms; 256 samples at every rate, 44.1–192 kHz) | yes |
| `AUPeakLimiter` | = attack: 48 (1 ms), 96 (2 ms), 1440 (30 ms) | **no**: 48 → 1440 at a mid-stream attack change |
| Apple chain3 / chain8 | 352 / **608 (12.7 ms, over 512)** | — |

### 5. CPU (`out/cpu.txt`, plus the second run for the tap-outer rows)

µs per 1024-frame buffer, offline. Each figure is the minimum over 3 runs of the mean over
2,000 buffers, after 50 warm-up buffers, with the copy-in cost (0.8 µs mono, 1.4 µs stereo)
subtracted. Load average at the runs: 2.81–3.00 (1 min) and 7.2–8.1 (5 min); a build had
finished just before. The real-time budget is 21,333 µs.

| Stage | own mono | own stereo | Apple mono | Apple stereo | Apple faster by |
|---|---|---|---|---|---|
| one biquad band (HPF2, peak, shelf, notch) | 3.56 | 7.2 | 2.36 | 4.77 | 1.5× |
| HPF4 | 7.12 | 14.32 | 4.54 | 9.08 | 1.6× |
| eq6 (Double, per sample) | 21.52 | 42.89 | 13.20 | 26.42 | 1.6× |
| eq6 through `vDSP_biquad` (block-variant) | 4.81 | 9.86 | — | — | — |
| expander | 5.83 | 6.21 | 3.95 | 4.22 | 1.5× |
| compressor | 6.38 | 6.95 | 3.93 | 4.49 | 1.5× |
| limiter, 64-tap + Annex 2: tap-outer (invariant) / `vDSP_conv` / plain scalar | 27.26 / 15.42 / 114.78 | 47.57 / 24.00 / 225.18 | 2.40 (`AUPeakLimiter`, sample peak only) | 2.91 | (not the same job) |
| **chain8**: tap-outer limiter (invariant) / `vDSP_conv` limiter | **63.33 / 50.74** | **107.54 (0.50 % RT) / 82.77 (0.39 %)** | 25.19 (chain8) / 19.84 (chain3) | 41.99 / 34.09 | 2.6× |

Other Apple hosts cost the same as v2: v3 `AUPeakLimiter` 2.40 / 3.06; the engine running
`AUPeakLimiter` 3.05 / 3.75 and chain3 20.22 / 34.11; `AVAudioUnitEQ` eq6 13.30 / 26.53.

**P passes for own: 107.5 µs = 0.50 % of real time per stereo track at eight stages**, under the
1 % bar. Sixteen such tracks take about 8 % of one core.

### 6. Limits (`out/limits.txt`, `out/zip_analysis.txt`)

- **Formats.** `AUNBandEQ`, `AUPeakLimiter`, `AUDynamicsProcessor` and both own stages initialise
  and render finite output at 44.1, 48, 96 and 192 kHz, with 1, 2, 6 and 8 channels.
- **An abrupt step**, 2 kHz peaking 0 → +12 dB at a block boundary under a 1 kHz tone at
  −20 dBFS. Energy outside 700–1300 Hz in the 50 ms after the step, relative to the tone; the
  no-step baseline is −106.5 dB:

  | Case | splatter | 10–90 % settle | level change |
  |---|---|---|---|
  | own, coefficients swapped at the sample | −79.4 dB | instant | +2.49 dB |
  | own, gain gliding per sample (5 ms one pole) | **−86.6 dB** | 0–12 ms | +2.49 dB |
  | `AUNBandEQ`, `AudioUnitSetParameter` between renders | −64.3 dB | **3–27 ms** (it smooths internally) | +2.49 dB |

  Apple's units take parameters per render call and smooth them their own way, so a clip's
  setting starts up to 27 ms after its cut. Own stages can switch at the sample or ramp per
  sample, which is what AP8 needs.
- **Latency follows a parameter** only for `AUPeakLimiter` (attack); see §4.

## What a builder must know

1. **The limiter's detector must be long, and must include `Loudness.swift`'s own reading.**
   - A BS.1770 Annex 2-sized detector (12 taps per phase) lets broadband material through at
     up to +0.97 dB over the ceiling, by an accurate meter: abrupt onsets and noise reaching
     20–24 kHz. Its passband reads −1.37 dB at 20 kHz (`interp_design.py`).
   - The Annex 2 filter **over**-reads speech by 0.14 dB. A limiter that holds −1.000 dBTP by
     an accurate meter is *reported* at −0.86 dBTP by `Loudness.swift` and by
     `phase5_proof.py`, whose true peak is that filter (the proof allows ±0.3 dB).
   - The detector that holds −1.000 on both meters takes the maximum over the 64-tap Kaiser
     β 10 phases **and** the Annex 2 phases. It costs nothing in loudness: −18.5 LUFS on the
     RØDE file, as every own variant.
   - This spike's first limiter (12-tap) failed C on the crest signal, and its detector was
     revised during the run. The verdict uses the revised one. `AUPeakLimiter` had no such
     path: no parameter makes a sample-peak limiter a true-peak one.
2. **Block-size invariance holds only for scalar per-sample code and element-wise vDSP.**
   - `vDSP_biquad` diverges at about −96 dBFS whenever a block is not a multiple of 4 frames.
   - `vDSP_conv` differs by 1 LSB on odd block lengths.
   - Element-wise calls (`vDSP_vabs`, `vmax`, `vmul`, `vsmul`) are exact.
   - For an FIR, **loop the taps outermost** (`tmp[i] += c·x[i+k]` for each tap k). It is
     bit-identical to the scalar loop and invariant, and the compiler vectorises it: 4.7×
     faster than scalar (47.6 against 225.2 µs stereo).
   - Double biquads cost 1.6× `AUNBandEQ`. Running two channels in `SIMD2<Double>` lanes is
     the obvious next saving, untried.
   - This matters because `AudioTap` splits buffers at cuts into irregular runs, and the
     preview (4096) and the export (512) cut differently.
3. **`reset()` must restore a stage's fresh state, and `AudioTap` must keep resetting on
   StartOfStream.** The player's first callback is a silent pre-roll with no valid time, and
   StartOfStream comes on the second. A gate or expander that has run through the pre-roll
   starts the preview closed. Measured: own chain8 is −56 dBFS off the export when the pre-roll
   runs through it unreset, and byte-identical with a reset at StartOfStream (`out/preview.txt`,
   `out/preview_reset.txt`).
4. **Latency.** The limiter adds 158 samples (3.3 ms, 2 ms lookahead), constant. Like the noise
   reducer, it must run for the whole track once any clip on it asks for it, so the delay never
   changes at a cut. With noise reduction too, a track is 670 samples (14 ms) late. Every other
   own stage adds 0.
5. **The tap's thread is real-time on the export path as well** (AudioToolbox's
   ProcessingTapManager RT thread). Buffers are 512 frames on the reader and 4096 on the player;
   prepare's maxFrames is 4096 on both.
6. A muted `AVPlayer` drives the tap for about 4 s and then feeds it silence. A proof that
   compares preview and export bytes this way must stay inside that window.
7. **Not tested here:**
   - a de-esser as such (its parts are tested);
   - `AUMultibandCompressor`;
   - `AUDynamicsProcessor`'s static curve;
   - running Apple's units on a 4× oversampled stream;
   - Apple units' output on non-48 kHz *content* (only initialisation and finiteness at each
     rate).
