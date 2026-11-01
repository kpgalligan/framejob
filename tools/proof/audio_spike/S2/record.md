# Spike S2 — voice isolation (`AUSoundIsolation`), rendered offline

Road map "audio", AP0's spike S2 (`archive/audio.md` AP0, AP5; `archive/audio-survey.md` §2, A4,
B4; spec §11 AU-3). Run 2026-10-30 on the owner's M2 Max (96 GB), macOS 26.5.1 (25F80),
Xcode's macOS SDK, against product code read at `9e47f56`. Scratch only: nothing in the tree
changed.

## The rule (written before any measurement ran)

Input: `samples/Rode-usb-mic.m4a` decoded once by ffmpeg to 48 kHz mono float32 WAV (`dry`),
and a reverberant copy made from it (`reverb`, below). Every condition reads one of those two.

**Measurements.**

1. **Driving it.** `AVAudioUnitEffect(audioComponentDescription: aufx/'vois'/appl)` between an
   `AVAudioSourceNode` and the main mixer, in `AVAudioEngine`'s offline manual rendering mode,
   as `RampAudioRenderer+TimePitch.swift` drives `AVAudioUnitTimePitch`. Parameter 0 Wet/Dry
   (percent), parameter 1 Sound to Isolate (0 High Quality Voice, 1 Voice). Recorded: whether it
   starts, the formats it renders (48 kHz mono and stereo; 44.1, 16 and 96 kHz), the reported
   `latency` and `tailTime`, the first `renderOffline`'s cost against later ones (warm-up), and
   whether its first output samples differ from steady state.
2. **Speed.** Wall time and process CPU time (`getrusage`) per render of the 30.4 s file, each
   model, three runs each; × real time = 30.36 s / wall. The load average is read before and
   after each batch (other agents build on this Mac).
3. **Latency.** Integer lag of the wet output against the dry input by FFT cross-correlation,
   over the whole file and separately over each of six 5 s segments; the lag is "constant" if
   all seven agree to the sample. Compared with the unit's reported `latency`.
4. **Determinism.** (a) Two renders in two processes, same settings: byte-compared. (b) The
   same render at `renderOffline` block sizes 256 and 4096. (c) A window rendered from 10.0 s
   with 0, 0.5, 1, 2 and 4 s of pre-roll against the same samples of the full-file render: the
   residual in dB below the signal, to find the pre-roll a per-clip-window render needs.
5. **Quality.** 400 ms windows of `dry`, classified ONCE on `dry` and applied to every
   condition (aligned to `dry` first): **pause** if the window's RMS is within 6 dB of the 10th
   percentile of window RMS; **speech** if it is at least 20 dB above it; the rest excluded.
   (a) Pause RMS in dBFS before and after, raw and after the +28.7 dB that −16 LUFS asks (the
   survey's §2). (b) Per-octave levels (63 Hz…16 kHz) over the speech windows, each condition
   minus `dry`; and the same over a noise-subtracted estimate (speech-window band power minus
   pause-window band power), so a band's drop is the voice's, not the hiss's. (c) The shipped
   noise reducer (`AudioNoiseReductionStage`, copied verbatim from `AudioDSP.swift` at
   `9e47f56`, its 512-sample latency removed) at Amount 25, 50, 75 and 100 % on the same
   metrics. (d) On `reverb`: the tail after word offsets (offsets found on `dry`: a 10 ms
   envelope falling from speech to 15 dB below; energy 50–250 ms after the offset relative to
   the 100 ms before it, `dry`'s own windows), and C50 and the late (> 50 ms) energy of the
   impulse response from `dry` to each output, estimated by Welch cross-spectra (H = Sxy / Sxx);
   on `reverb` itself this estimate must give back the synthetic room's C50 within 1 dB, or the
   method is not trusted.
6. **Wet/dry.** The unit's own 50 % render against 0.5·dry(t−L) + 0.5·wet(t) (is its dry path
   delay-compensated?); a host-side 50 % mix with and without the lag removed: its ripple across
   0.1–8 kHz (max − min of the dry→mix transfer magnitude in 1/3-octave-smoothed dB) and its
   first notch; and the coherence of aligned wet with dry over speech (is the wet in phase, so
   that even an aligned mix does not comb?).

**Verdict criteria.**

- **V1 drivable:** it instantiates, renders offline at 48 kHz (the ramp cache's rate) mono and
  stereo, and the High Quality Voice model is selectable. Otherwise not viable.
- **V2 fast enough:** the slower model at ≥ 5× real time on this host as loaded (a 10-minute
  clip in ≤ 2 minutes); 1–5× is "marginal, render on a background queue"; < 1× is not viable.
- **V3 alignable:** the lag constant across segments and equal to the reported `latency` (or a
  fixed number to discard) — then AP5 compensates by discarding L frames and feeding L frames of
  zeros after the end, and its proof "within a sample" can hold.
- **V4 cacheable:** byte-identical across processes and block sizes → the cache key needs no
  block size and its proofs can compare bytes; otherwise proofs measure levels and alignment
  (the road map's named risk). The pre-roll for a window starting mid-media is the shortest one
  whose residual is ≤ −60 dB against the full render.
- **V5 good enough:** at 100 %, (a) the pause floor after the lift drops ≥ 10 dB (about −36 to
  ≤ −46 dBFS), and (b) the speech windows' broadband level moves ≤ 1 dB and no noise-subtracted
  octave from 125 Hz to 4 kHz drops more than 3 dB; a drop over 6 dB at 8 or 16 kHz is reported
  as dulling. **It beats the reducer** if its pause floor is lower than the reducer's at a
  setting with no more speech-band loss than its own.
- **V6 de-reverb (B4):** on `reverb`, at 100 %, the post-offset tail falls ≥ 3 dB AND the
  estimated C50 rises ≥ 3 dB → B4 rides on isolation and the guide says so; neither → B4 is
  filed with tier C with these numbers; one → reported as partial, owner's call.
- **V7 wet/dry:** an aligned host-side mix ripples < 1 dB (the wet in phase, coherence ≥ 0.9
  over 250 Hz–4 kHz) → Amount can be a live crossfade of a 100 % render with the dry clip, no
  re-render per Amount; otherwise Amount must be baked into the render (and keyed).

**The reverberant sample.** A synthetic room impulse response at 48 kHz: a unit direct path at
0, then Gaussian noise from 2.5 ms under an exponential envelope with RT60 = 0.6 s (60 dB in
0.6 s), 1.0 s long, its energy scaled to a direct-to-reverberant ratio of 0 dB (a laptop
microphone about a metre away in a hard room), fixed seed. `dry` convolved with it, scaled so
its speech windows' RMS matches `dry`'s, plus pink noise (fixed seed) at −60 dBFS RMS, 4 dB
over the recording's own −64 dBFS floor.

## Verdict

**`AUSoundIsolation` is viable for AP5. Use the High Quality Voice model only (parameter 1 = 0;
the unit's default is 1, Voice, so set it explicitly). Frame Job's deployment target is macOS
26.0, so High Quality Voice is always available.** It passes V1, V2, V3, V5 and V7 outright.
V4 is partial: renders repeat, but window renders are not byte-stable, so proofs measure levels
and alignment, not bytes (the road map's named risk). V6 passes on the rule's numbers, as a
partial de-reverb.

| Criterion | Result | Pass |
|---|---|---|
| V1 drivable | `AVAudioUnitEffect` 'aufx'/'vois'/'appl' in offline manual rendering, as `+TimePitch`. 48 kHz mono and stereo, 16/44.1/96 kHz all render; both models selectable | yes |
| V2 speed | HQ 28–51× real time at load ≈ 9, 14–16× at load ≈ 44 (12-core M2 Max shared with other agents' builds); ≈ 0.5–0.7 s of CPU per 30 s; fixed setup 0.18–0.44 s | yes (≥ 5×) |
| V3 alignable | HQ lag 4440 frames (92.5 ms), the same to the sample in all six 5 s segments, and equal to `latency`. Voice: 2704, one less than its reported 2705 | yes (HQ) |
| V4 cacheable | Full-file renders byte-identical across processes, across about 20 min and across `renderOffline` blocks 256–8192. Windows mid-media differ at about −51 dB with incidental process state (argv length) and at −30…−52 dB with the feed-start phase | partial: levels, not bytes |
| V5 good enough | HQ 100 %: pause floor −10.9 dB (energy mean; median window −74 dB), speech +0.14 dB, octaves 63 Hz–8 kHz within ±0.3 dB | yes; beats the reducer |
| V6 de-reverb | HQ on the reverberant copy: tail after word ends −5.3 dB, estimated C50 7.0 → 12.2 dB (+5.2) | yes, partial (≈ 5–6 dB less late reverb, decay rate unchanged) |
| V7 wet/dry | Aligned host 50 % mix ripples 0.15 dB; wet in phase with dry (coherence ≥ 0.994); the unit's own 50 % = 0.5·dry + 0.5·wet to −84 dB | yes: Amount as a crossfade of one 100 % render |

**How AP5 should drive it** (each line measured below):

- **Graph.** `AVAudioSourceNode` → `AVAudioUnitEffect(aufx/vois/appl)` → main mixer, offline
  manual rendering at 48 kHz, `maximumFrameCount` 4096 (≥ 512: at 256 the Voice model renders
  differently, −53 dB; HQ does not care). Set parameter 1 = 0 (HQ) and parameter 0 = 100 (render
  wet; Amount is applied afterwards, below).
- **Channels.** Render each channel as its own **mono** render. The unit's stereo configuration
  is a different render: +40 ms latency (HQ 6360 frames), −19 dB different from the mono render,
  though its channels are independent (crosstalk below −48 dB). Mono is the unit's default
  format and the one this spike characterised.
- **Latency.** Discard the first `unit.latency` × 48 000 = **4440** output frames (HQ, 48 kHz
  mono) and feed 4440 frames of zeros after the window's last frame. That number is exact for HQ
  at 48 kHz. It is not exact everywhere: Voice at 48 kHz and both models at 96 kHz report one
  frame more than they delay, and the delay is fractional at 44.1 kHz (both models) and 16 kHz
  (Voice). So a proof pins lag 0 by
  cross-correlation (AP5's "within a sample"), and the renderer refuses a unit whose reported
  latency is not 4440, rather than trusting a changed model blindly.
- **Pre-roll.** The model adapts over its first 0.5–2 s. Without pre-roll, a window's first
  second differs from a converged render by −15 dB. With 2 s of media it is −46 dB (HQ), and
  4 s is as converged as it gets. **Feed 4 s of the media before the window** (from media frame
  0 when the window starts sooner). Zeros are no substitute: 4 s of digital silence leaves the
  output as it is with no pre-roll (the same −15.0 dB first-second residual; silence resets the
  model).
- **Amount.** Render 100 % once. The unit's own wet/dry is exactly a linear crossfade of the
  latency-compensated dry with the 100 % wet (−84 dB residual), and the wet is in phase with the
  dry. So an Amount applied outside the unit (two sample-aligned segments in the composition,
  dry at 1 − a and the render at a, or a crossfade wherever AP5 puts it) reproduces it without a
  re-render or an Amount in the cache key. It must be sample-aligned. Unaligned by the latency,
  a 50 % mix is a 92.5 ms echo with notches 36 dB deep every 10.8 Hz
  (`listen/08-…-echo.wav`). One sample off, a 50 % mix loses about 1.2 dB at 8 kHz
  (cos πf/fs).
- **Cache.** Key the render by the media file, the model, a renderer version, the window and
  the pre-roll. Not by block size (≥ 512), and not by Amount (applied outside). Its bytes are
  whatever the first render wrote: a re-render of a mid-media window can differ at about
  −51 dB, so the cache must never be checked by re-rendering and comparing bytes. Two clips
  split from one take render as two windows whose outputs differ at a cut by about −30…−50 dB
  relative to the signal. That is likely inaudible but unproven; rendering a contiguous
  same-media span once, or crossfading a few ms at such a join, removes it.
- **Cost.** About 1–2 s per 30 s on this Mac under load, plus 0.2–0.4 s per render to open the
  model: a 10-minute clip in roughly 12–43 s, on the ramp-audio queue, dry while pending.
- **Chain order (AU-3).** The chain puts isolation after EQ and the hum notch. An offline render
  of the media sees the media, not the tap's EQ, so in practice isolation comes first unless the
  render applies those stages to its input. Linear stages commute only with linear stages; this
  spike did not measure the difference (nor how isolation treats hum). AP3/AP5 should settle it,
  and AU-3's order may need a note.

**It beats the shipped noise reducer on this recording.** At no setting does the reducer
match isolation's speech fidelity: Amount 25 % already costs 0.45 dB of speech and lowers the
floor only 2 dB. At 100 % the reducer reaches the same energy-mean pause level (−73.0 vs
−73.4 dBFS) but costs 1.3 dB of speech (up to 2.4 dB in an octave), and its median pause window
is −87.7 dBFS against isolation's −137. Isolation's median pause window is effectively digital
silence. At 100 % the pauses become "dead air" between words; at Amount a the floor sits at
about the dry floor + 20·log₁₀(1 − a) (50 % measured −5.0 dB; 80 % would be about −14 dB, 90 %
about −20 dB). Whether 100 % sounds natural on the owner's voice is the manual check AP5 already
names. The two pause windows it keeps nearly whole (28.8 s and 4.8 s, −58 to −60 dBFS) look
like breaths or quiet voicing (unverified by ear).

**B4 (de-reverb).** By the rule's numbers B4 rides on isolation: the tail after word ends fell
5.3 dB (median per offset 8.0 dB) and the estimated C50 rose 5.2 dB, both over the 3 dB bar.
Be precise about what that is: about 5–6 dB less late reverberant energy (C50 7 → 12 dB,
50–500 ms energy −4.8 → −10.5 dB against the direct sound), not removal. On the noise-free
control the remaining tail decays at the same rate (estimated T20 0.58 → 0.68 s). The shipped
reducer gets half of it (+2.7 dB C50) and, like isolation, also cuts the tail in pauses. The
guide should say isolation "reduces room echo", not that it removes it. The room is synthetic
(frequency-independent decay, DRR 0 dB, a mild C50 of 7 dB), so the survey's §6 sample 4 (the
MacBook's microphone in a hard room) is the real check when it exists. A dedicated de-reverb
stronger than this stays tier C if the owner wants one.

**The Voice model is not recommended.** It loses everything above about 10.5 kHz (the 16 kHz
octave −60 dB, the dulling flag), costs 0.7–1.1 dB across the voice, misreports its latency by
one frame, and its own dry and wet paths sit one sample apart (dry 2705, wet 2704; its 0 %
output is the dry delayed 2705 to −78 dB). It mutes the first 100 ms of a window started on a
word without pre-roll. Its speed is about HQ's: faster under heavy load, no faster at load 9.
Its only use would be an OS below 15, which Frame Job does not support.

## Method

All code under `src/` in this folder; binaries in `bin/`, built with `swiftc -O`.

- `src/isolate.swift` (`bin/isolate`): the offline renderer above. It takes `--type`, `--mix`,
  `--block`, `--maxframes`, `--raw` (no latency discard, plus 1 s of pad), and
  `--start/--preroll/--length` for a window. It also takes `--zeropre` (pre-roll fed as zeros),
  `--leadzeros N` (zeros before the pre-roll) and `--repeat N` (fresh engines in one process).
  It prints the reported latency, tail time, setup, first-call and render times, CPU
  (`getrusage`) and frames.
- `src/nrtool/nr_stage.swift` is `AudioDSP.swift` lines 347–716 at `9e47f56`, verbatim, with
  the file's two imports prepended. `src/nrtool/main.swift` drives it in 1024-frame calls,
  and removes its documented 512-frame latency (`bin/nr`, 500–870× real time).
- `src/ana.py` (numpy only; no scipy on the host): FFT cross-correlation with parabolic
  sub-sample peak, the 400 ms classifier, octave band powers. The analyses are `quality.py`
  (5a–c), `pauses.py`, `reverb_ana.py` (5d), `mix_ana.py` (6), `fmt_ana.py` and `stereo_ana.py`
  (1), `warmup.py`, and `factor*.py` and `launchprobe.py` (determinism). `run.py` runs the
  batches; `make_reverb.py` and `make_listening.py` make the inputs and the listening files.
- `dry` is ffmpeg's decode of the m4a (1 457 152 frames; its first 1024 are digital silence,
  the AAC priming). Every condition reads `dry` or the reverberant copy.

**Deviations from the rule, and additions.**

1. **Offsets (5d).** The rule's wording ("a 10 ms envelope falling from speech to 15 dB below",
   held 250 ms) found one offset in 30 s. The measure used is the end of a speech run: the last
   10 ms frame at or above p10 + 20 dB (−45.6 dBFS), followed by ≥ 250 ms below it. It found 14
   offsets. The tail ratio is energy 50–250 ms after the offset over the 100 ms before.
2. **Pause RMS (5a)** is reported as the rule asks (the energy mean over pause windows). The
   per-window median is added because two windows dominate the mean once isolation empties the
   rest.
3. **Added controls:** a noise-free copy of the reverberant sample (the same room, no pink
   noise), so that de-reverb is not confused with noise removal. Also dry → isolation (the
   impulse-response method's floor on a non-linear system: C50 34 dB, far above the 12 dB
   measured), 50 % renders on the reverberant copy, the shipped reducer on the reverberant copy,
   and the determinism probes below.
4. **Sanity check (5d) passed:** the impulse-response estimate gives the synthetic room's C50 as
   7.0 dB against the true (band-limited) 7.0 dB. Its T20 is noise-inflated with the pink noise
   (1.16 s against 0.60) and right without it (0.58 s), so only the noise-free control's T20 is
   quoted.

## 1. Driving it

`auval -v aufx vois appl`: AUSoundIsolation 1.6.0, a version 2 Audio Unit. Cold open 27.8 ms,
initialisation 63.3 ms. Default format 1 ch 48 kHz Float32 in and out. Channel configurations N→N
only (1-1, 2-2, 4-4 … 8-8), and it renders at 11.025–192 kHz. Latency, tail time and bypass are
published. Parameters:

| ID | Name | Range | Default |
|---|---|---|---|
| 0 | Wet/Dry Mix (percent) | −100 … 100 | 100 |
| 1 | Sound to Isolate (indexed) | 0 High Quality Voice, 1 Voice | **1 (Voice)** |

A negative mix crossfades towards what the unit removed: −100 % is dry − wet to −64 dB
(`listen/07-…-what-it-removed.wav`), and −50 % is dry − 0.5·wet. `AudioUnitSetParameter` before
`engine.start()` returns 0, and the value reads back.

| Format | HQ reported / measured latency (frames) | Voice reported / measured |
|---|---|---|
| 48 kHz mono | 4440 / **4440.00** | 2705 / **2704.00** |
| 44.1 kHz mono | 4083 / 4083.15 | 2488 / 2488.20 |
| 96 kHz mono | 8833 / 8832.00 | 5361 / 5360.00 |
| 16 kHz mono | 1511 / 1511.00 | 932 / 932.70 |
| 48 kHz stereo | 6360 / 6360 (both channels) | 3665 / 3664 |

Bandwidth: the output is band-limited whatever the input rate. HQ is flat to 13 kHz, −2 dB at
13–14 kHz, −11 dB at 14–15 kHz, and gone above 15 kHz (above-16 kHz energy share −54 →
−145 dB). Voice is −1 dB to 10 kHz, −5 dB at 10–11 kHz, and gone above 11 kHz. Stereo: L and R
are independent (crosstalk −48 to −62 dB), identical inputs give outputs equal to −105 dB, but
the stereo render differs from the mono render by −19 dB and adds 40 ms (HQ) or 20 ms (Voice).

**Warm-up.** No render-call warm-up: the first `renderOffline` takes about 1 ms, like the rest.
The cost is opening the model, 0.18–0.44 s per engine. The output has a start-up transient,
measured on a 2 s window from 10.0 s against the full render's same samples:

| Start | HQ first 1 s residual | HQ second 1 s | Voice first 1 s | Voice second 1 s |
|---|---|---|---|---|
| no pre-roll | −15.0 dB | 0.0 dB* | −13.8 dB | −23.2 dB |
| 4 s of zeros, then the window | −15.0 dB | 0.0 dB* | −13.9 dB | −23.4 dB |
| 0.5 s of media | −24.0 dB | −18.3 dB | −39.8 dB | −38.3 dB |
| 2 s of media | −46.1 dB | −30.5 dB | −50.7 dB | −35.8 dB |

\* The 11–12 s second is a pause in which both renders are below −85 dBFS; the residual compares
two near-silences. Without pre-roll, the first 100 ms (on a word) comes out 5 dB quieter than
converged with HQ (−62.4 vs −57.5 dBFS), and 59 dB quieter with Voice (−117.3 vs −58.7, its onset
muted). After that the speech matches within 0.6 dB. The pauses differ by up to ±28 dB, but all
of them sit at −77 dBFS or below (`warmup.txt`). A clip that starts on a word at the media's
first frame has nothing to pre-roll with, so it keeps HQ's 5 dB dip.

## 2. Speed

30.36 s rendered, wall time from engine creation to the last frame. × real time = 30.36 / wall.

| Model | Load average (1 min) | Wall (3 runs) | × real time | CPU | Setup |
|---|---|---|---|---|---|
| HQ | 41.5–44.1 | 2.06, 2.19, 1.90 s | 14.7, 13.8, 16.0 | 0.68–0.73 s | 0.29–0.31 s |
| Voice | 44.1–44.5 | 1.27, 1.66, 1.81 s | 24.0, 18.3, 16.8 | 0.60–0.65 s | 0.19–0.24 s |
| HQ | 8.6–8.9 | 0.59, 0.89, 1.08 s | 51.1, 34.1, 28.2 | 0.49–0.67 s | 0.18–0.30 s |
| Voice | 8.9 | 0.91, 1.14, 1.04 s | 33.4, 26.5, 29.3 | 0.58–0.60 s | 0.23–0.44 s |

The process's CPU time is well under its wall time, so most of the inference runs off the
CPU's accounting (presumably the Neural Engine or GPU; not instrumented). The shipped reducer runs at
500–870× real time on the CPU.

## 3. Latency and alignment

FFT cross-correlation of the raw output (no discard) against `dry`, over the whole file and
each 5 s segment:

| | whole | seg 0 | 1 | 2 | 3 | 4 | 5 | peak corr. |
|---|---|---|---|---|---|---|---|---|
| HQ | 4440 | 4440.00 | 4440.01 | 4440.00 | 4440.01 | 4440.00 | 4440.00 | 0.92–0.996 |
| Voice | 2704 | 2704.00 | 2704.00 | 2704.00 | 2703.99 | 2704.00 | 2704.00 | 0.92–0.996 |

The lag is constant and an integer at 48 kHz. After discarding the reported latency, HQ sits at
lag 0 and Voice at lag −1 (one frame early). The first 4440 output frames of a raw render are
exactly zero.

## 4. Determinism

| Test | HQ | Voice |
|---|---|---|
| Full render, two processes; two fresh engines in one process | identical (`7a1e107a…`) | identical (`86bed556…`) |
| Same, 12 and about 20 min later, at another load | identical | identical |
| `renderOffline` block 256, 512, 1000, 4096, 8192 (max frames 256–8192) | identical | identical except max frames 256 (−53 dB, max \|d\| 2.5e-4) |
| Full render launched by absolute path, relative path, `./` path | identical | identical |
| Window 10–15 s, 4 s pre-roll, launched different ways (argv length 1, 7, 30, 100, 333 extra chars) | two outputs, −51 dB apart (`0deb838f…` / `a2534536…`) | two outputs, −52 dB apart |
| Window at 10 s + k frames, 4 s pre-roll, vs the full render's samples | k = 0, 9600: identical (in one launch identity); multiples of 240: −51 dB; others −30…−38 dB | multiples of 160: −52 dB; others −30…−43 dB |
| Same, residual against pre-roll 2, 4, 6, 8, 10 s | unchanged (a phase, not a convergence) | unchanged |
| Lead zeros (256/1024/4096) before the pre-roll | does not remove the launch dependence | same |

So a render is repeatable for a fixed process and input, and a full-file render repeated in
every way tried. But a mid-media window's last bits depend on the frame where feeding starts and
on incidental process state, at −30 to −52 dB. The road map's risk applies: AP5's proofs compare
a render with the dry by alignment (lag 0) and levels, and two renders by a residual bound
(≤ −40 dB for the same window), never by bytes.

Pre-roll, window at 10.0 s against the full render's samples (one launch identity):

| Pre-roll | 0 | 0.1 s | 0.25 s | 0.5 s | 1 s | 2 s | 4 s |
|---|---|---|---|---|---|---|---|
| HQ residual | −24.0 | −28.7 | −25.2 | −33.0 | −35.1 | −55.4 | identical |
| Voice residual | −22.8 | −31.8 | −42.4 | −48.6 | −56.4 | −90.5 | identical |

## 5. Quality

400 ms windows of `dry` (75): p10 −63.6 dBFS. There are 39 pause windows (52 %) and 10 speech
windows (13 %); the other 26 fall between and are excluded. The lift is +28.7 dB (−16 LUFS).

**(a) Pause floor and speech level**

| Condition | pause RMS (dBFS) | after +28.7 dB | floor lowered | median pause window | speech RMS | speech change | 50 ms p10 |
|---|---|---|---|---|---|---|---|
| dry | −62.5 | −33.8 | — | −63.2 | −40.4 | — | −64.3 |
| **isolation HQ 100 %** | −73.4 | −44.7 | **10.9** | **−137.0** | −40.2 | **+0.14** | −163.7 |
| isolation Voice 100 % | −75.3 | −46.6 | 12.8 | −113.6 | −41.1 | −0.76 | −145.5 |
| isolation HQ 50 % | −67.5 | −38.8 | 5.0 | — | −40.3 | +0.06 | −70.2 |
| isolation Voice 50 % | −67.7 | −39.0 | 5.2 | — | −40.8 | −0.39 | −70.3 |
| noise reduction 25 % | −64.5 | −35.8 | 2.0 | — | −40.8 | −0.45 | −66.6 |
| noise reduction 50 % | −66.8 | −38.1 | 4.3 | −68.7 | −41.1 | −0.73 | −70.0 |
| noise reduction 75 % | −70.2 | −41.5 | 7.7 | — | −41.4 | −1.03 | −76.1 |
| noise reduction 100 % | −73.0 | −44.3 | 10.5 | −87.7 | −41.7 | −1.30 | −94.8 |

Pause windows by percentile (dBFS), median / 75th / 90th / max: dry −63.2 / −62.4 / −60.4 /
−58.1. HQ −137.0 / −97.9 / −76.2 / −59.9. Voice −113.6 / −101.3 / −78.4 / −62.3. NR 100 % −87.7 /
−79.5 / −67.3 / −61.4.

**(b) The speech band:** speech windows, condition minus dry, per octave (dB).

| Condition | 63 | 125 | 250 | 500 | 1k | 2k | 4k | 8k | 16k |
|---|---|---|---|---|---|---|---|---|---|
| isolation HQ 100 % | +0.3 | +0.2 | +0.1 | +0.1 | −0.0 | +0.1 | +0.1 | +0.0 | −0.7 |
| isolation Voice 100 % | −0.8 | −1.1 | −0.7 | −0.7 | −0.9 | −0.7 | −0.7 | −1.1 | **−60.2** |
| isolation HQ 50 % | +0.2 | +0.1 | +0.1 | +0.1 | −0.0 | +0.1 | +0.1 | +0.0 | −0.5 |
| isolation Voice 50 % | −0.4 | −0.6 | −0.4 | −0.3 | −0.5 | −0.4 | −0.6 | −1.6 | −6.0 |
| noise reduction 25 % | −0.8 | −0.5 | −0.5 | −0.4 | −0.7 | −0.4 | −0.4 | −0.4 | −0.6 |
| noise reduction 50 % | −1.3 | −0.8 | −0.8 | −0.7 | −1.3 | −0.6 | −0.6 | −0.7 | −1.0 |
| noise reduction 75 % | −1.8 | −1.2 | −1.1 | −1.0 | −1.9 | −0.9 | −0.9 | −1.0 | −1.5 |
| noise reduction 100 % | −2.4 | −1.5 | −1.3 | −1.3 | −2.4 | −1.1 | −1.1 | −1.2 | −1.9 |

The noise-subtracted voice (speech-window minus pause-window band power) agrees with this table
to within 0.3 dB at every octave for every condition (`quality.txt`). These changes are the
voice's, not the hiss's: the dry voice stands 15–30 dB over the pause noise in every octave from
63 Hz to 8 kHz.

Pause windows, per octave (dB). HQ 100 %: −12.5, −20.2, −20.0, −18.8, −20.2, −12.6, −7.2,
−6.8, −15.3. NR 100 %: −15.8, −14.9, −11.7, −13.8, −15.0, −13.1, −9.5, −6.1, −7.2. The
smaller cut above 2 kHz fits breath-like content in the few windows isolation keeps (not
verified).

**(c) Against the shipped reducer:** see the verdict. At equal speech loss, no reducer setting
reaches isolation's (none loses ≤ 0.14 dB). At equal mean pause level (NR 100 %), the reducer
costs 1.3 dB of speech, and its median pause sits 49 dB above isolation's.

**(d) Reverberation** (`reverb.txt`): 14 word offsets. Estimated RIR is dry → output, Welch,
100 Hz–8 kHz.

| Condition | tail 50–250 ms after offsets | median per offset | est. C50 | late 50–500 ms vs direct | est. T20 | pause RMS |
|---|---|---|---|---|---|---|
| true room (band-limited) | — | — | 7.0 dB | −4.8 dB | 0.60 s | — |
| dry | −8.8 dB | −8.4 dB | 65.9 dB | −65.9 dB | — | −62.5 |
| dry → isolation HQ | −9.9 | −9.8 | 34.1 | −35.2 | — | −73.4 |
| reverb (room + noise) | −6.1 | −3.5 | 7.0 | −4.8 | (1.16, noise) | −57.9 |
| **reverb → isolation HQ 100 %** | **−11.4** | **−11.5** | **12.2** | **−10.5** | (1.09) | −76.5 |
| reverb → isolation Voice 100 % | −10.9 | −10.6 | 11.6 | −9.8 | (1.06) | −82.6 |
| reverb → isolation HQ 50 % | −8.5 | −6.9 | 9.1 | −7.1 | (0.82) | −63.7 |
| reverb → NR 50 % | −8.4 | −5.7 | 8.2 | −6.0 | (0.81) | −62.0 |
| reverb → NR 100 % | −12.0 | −8.6 | 9.7 | −7.6 | (1.37) | −68.5 |
| room only (no noise) | −6.8 | −4.4 | 7.1 | −4.9 | 0.58 s | −62.0 |
| room only → isolation HQ | −10.9 | −11.2 | 12.5 | −10.9 | 0.68 s | −76.1 |
| room only → isolation Voice | −10.6 | −10.8 | 11.8 | −10.1 | 0.80 s | −78.9 |
| room only → NR 100 % | −11.9 | −7.8 | 9.5 | −7.4 | 1.21 s | −73.0 |

The tail measure alone cannot tell de-reverb from noise removal: the reducer also cuts the tail
in the pauses. C50 and the late energy, which count the reverb under the words, are the
discriminating numbers. Isolation +5.2 to +5.4 dB, the reducer +2.4 to +2.7 dB.

## 6. Wet/dry (`mix.txt`)

| | HQ | Voice |
|---|---|---|
| The unit's 0 % vs dry | the dry delayed 4440, −78 dB residual (not a bit-exact delay) | the dry delayed 2705 (−78 dB), one frame behind its wet |
| The unit's 50 % vs 0.5·dry + 0.5·wet, aligned | **−84 dB** | −23 dB (the one-frame offset) |
| The unit's internal dry path at 50 % | compensated (lag 0) | lag +1 against the wet |
| Coherence² / real normalised cross-spectrum, aligned wet vs dry, speech, 125 Hz–8 kHz | ≥ 0.994 / ≥ +0.997 | ≥ 0.979 / ≥ +0.990 |
| Host 50 % mix, aligned: ⅓-octave ripple 100 Hz–8 kHz, per-bin 95 % spread 250 Hz–4 kHz, deepest bin | 0.15 dB, 0.3 dB, −0.5 dB | 0.20, 0.3, −0.9 dB |
| Host 50 % mix, latency not removed | ⅓-oct 1.9 dB, per-bin spread 20 dB, notches to −36 dB every 10.8 Hz: a 92.5 ms echo | 1.8 dB, 20 dB, −37 dB every 17.8 Hz: a 56.3 ms echo |

## Listening files

In `/private/tmp/claude-501/-Users-kevingalligan-devel-framejob/9bb0487d-a352-45e3-9da8-07b6f4762c27/scratchpad/ap0/S2/listen/`:
48 kHz mono 24-bit WAV, all aligned to the dry. Every file has the same +17.6 dB gain (the dry's
peak to −1 dBFS), so they compare at equal level; none clips. The pause floor sits about 11 dB
below where −16 LUFS would put it, so turn the volume up to judge pauses.

| File | What it is |
|---|---|
| `01-dry.wav` | the recording |
| `02-isolation-hq-100.wav` | High Quality Voice, Amount 100 % |
| `03-isolation-hq-50.wav` | High Quality Voice, Amount 50 % (the unit's own mix) |
| `04-isolation-voice-100.wav` | the older Voice model, 100 % (listen for the lost top end) |
| `05-noise-reduction-50.wav` | the shipped reducer at 50 % |
| `06-noise-reduction-100.wav` | the shipped reducer at 100 % |
| `07-isolation-hq-what-it-removed.wav` | Wet/Dry −100 %: what isolation took out |
| `08-mix-50-latency-not-removed-echo.wav` | a 50 % mix with the 92.5 ms latency left in |
| `09-reverb-room-and-noise.wav` | the synthetic room (RT60 0.6 s) plus pink noise |
| `10-reverb-isolation-hq-100.wav` | that, through High Quality Voice at 100 % |
| `11-reverb-isolation-hq-50.wav` | that, at 50 % |
| `12-reverb-isolation-voice-100.wav` | that, through Voice at 100 % |
| `13-reverb-noise-reduction-100.wav` | that, through the shipped reducer at 100 % |

## What this spike did not settle

- How it sounds: dead air at 100 %, any artefacts on the owner's voice, and whether the two
  kept pause windows are breaths. This is AP5's manual check; the files above serve it.
- Non-voice material (music, effects) through the unit, and whether it removes mains hum
  (bearing on AU-3's order).
- A real reverberant recording (survey §6 sample 4) and a 10-minute file (sample 13) for render
  time and cache size at length.
- Where the inference runs (Neural Engine, GPU or CPU) and why process state moves a window's
  low bits; the probes stop at "it does, by about −51 dB".

