# Spike S3 — tracks and the master in the preview (road map "audio", AP0)

Run 2026-10-30 against the tree at `9e47f56`, on macOS 26.5.1 (25F80), SDK 26.2. Every code
citation is `file:line` at `9e47f56`. Experiments are standalone `swiftc -O` tools (and one
scratch Rust test over a copy of the core) under this folder; nothing in the repo was edited,
no `make`, Frame Job never launched.

## The rule, fixed before the run

Each question is answered by code citation or by measurement, never by reading API names alone.
The criteria, written down before any experiment ran:

1. **Mapping.** "One composition audio track carries clips of two timeline tracks" is answered
   YES only by a plan the core itself emits (a scratch test over the 9e47f56 core) showing one
   `audio_tracks` entry whose segments come from clips of two different tracks; NO only by a
   code path that makes it impossible. Top-level timeline tracks and a nest's inner tracks are
   answered separately.
2. **Per-composition-track approximation.** Linear stages are argued from algebra and checked
   numerically (error under −120 dB relative is "exact"). For dynamics the error of the chain run
   per composition track against the chain run on the track's sum is measured on a constant-power
   crossfade (the core's own law, `audio_crossfade.rs`) with the app's compressor copied
   verbatim (`AudioDSP.swift`) and a lookahead true-peak limiter at −1 dBTP. Reported: the output
   peak against the ceiling, the worst 50 ms level error, and the BS.1770 momentary loudness
   error. **Acceptable** for a preview if the per-track result stays under the limiter's ceiling
   + 0.5 dB and within 1 LU momentary of the sum; otherwise the preview must say it differs.
3. **A preview master insert.** An option counts as REAL only if a prototype here produced
   processed mixed audio from a composition with taps and volume ramps. Judged on: latency to
   first audio after play and after a seek (target ≤ 150 ms, AVPlayer's own order), drift against
   the AVPlayer over ≥ 60 s (target: bounded, under 1 frame at 30 fps = 33 ms after an hour, so
   ≤ 9 ppm unbounded drift or a shared clock), and how many app files it touches. An API is
   counted as existing only when it is in the macOS 26.2 SDK headers.
4. **True-mix meter.** The reconstruction from per-track taps passes if its BS.1770 momentary and
   short-term loudness are within 0.1 LU of the same measurement on the mix AVFoundation itself
   produces (`AVAssetReaderAudioMixOutput`, the export's read), on material that includes
   correlated tracks, a mono track and volume ramps; and only if the taps' callback order and
   timestamps make a lock-free real-time accumulation possible (one thread, aligned times).
5. **Stems.** A multitrack movie "works" if `AVAssetWriter` writes N audio tracks, `AVURLAsset`
   and `ffprobe` both list N audio tracks with the right lengths and contents (each track decoded
   and compared to its source), and the enabled flags say what a player will play.

## Verdicts against the rule

1. **Mapping** — answered both ways by the core's own plans (E1) and by code: a composition track
   never carries two TOP-LEVEL timeline tracks (impossible by `evaluate.rs:416-501`); it routinely
   carries two of a NEST's inner tracks (E1 A, B).
2. **Per-composition-track approximation** — linear stages PASS (exact, −145 dB; 0.01 LU even
   before the envelope). Dynamics FAIL the tolerance during an overlap (a limiter +0.85 dB over its
   ceiling on speech and +2.7 dB on tones; a compressor 3–5 LU), are borderline at a split cut (a
   0.1 s transient, 0.9–1.7 LU), and FAIL throughout a nest bus (+1.4–1.8 dB, ~5 LU). So where a
   track or bus has dynamics, the preview must say it differs (or use option c).
3. **A preview master insert** — (b) FAILS: no AVPlayer API reaches the mixed audio in the 26.2
   SDK. (c) PASSES as a prototype: mixed audio from a tapped, ramped composition through an
   engine insert, 60–150 ms to start, 0.02 ppm drift with `sourceClock` on the device clock
   (4.4–4.5 ppm without), no underruns — at the cost of the preview's whole audio path. (d) works
   but is not live. (a) is free.
4. **True-mix meter** — accuracy PASSES (0.0067 LU momentary, 0.0005 LU short-term against the
   export's own mix). The second half of the criterion does NOT hold as written: the player's taps
   run on one thread, but their timestamps in one cycle differ by up to 13 ms per track. So the
   sum cannot be added up buffer by buffer on the audio thread; it is summed by timestamp off it,
   which the taps' continuous, correct timestamps allow (the rebuild from the player's taps
   equalled the export's mix bit for bit).
5. **Stems** — PASSES: N audio tracks written, listed by AVFoundation and ffprobe at full length,
   each decoding to its own stem, the enabled flags obeyed by AVPlayer.

## The experiments

| # | Tool (under `tools/`) | Log | What it measures |
|---|---|---|---|
| E1 | `core9e/core/tests/s3_mapping.rs` (a copy of the 9e47f56 core, `cargo test --release`) | `e1_mapping.log` | the plan's `audio_tracks` for six fixtures: which clips share a composition track |
| E2 | `e2/main.swift` + `AppCompressor.swift` (the app's compressor, copied verbatim) + `Measure.swift` | `e2_dynamics.log` | a track chain per composition track against the chain on the track's sum: EQ, limiter, compressor; tones, the owner's speech, a hard cut, a nest bus |
| E3 | SDK header search (`xcrun --show-sdk-path`, SDK 26.2) | in this record | every API that could reach an AVPlayer's mixed audio |
| E4 | `e4/main.swift` + `Common.swift` | `e4_meter.log` | the mix rebuilt from PreEffects taps against `AVAssetReaderAudioMixOutput`'s mix; the mono rule; PostEffects; an AVPlayer's tap threads and timestamps |
| E5 | `e5/main.swift` | `e5_engine.log` | option (c): reader → ring → `AVAudioSourceNode`, AVPlayer started at the same host time; latency, offset, drift, underruns, three clock set-ups |
| E6 | `e6/main.swift` | `e6_stems.log`, `e6_ffprobe.log` | multitrack movies from `AVAssetWriter`, read back by AVFoundation and ffprobe |
| E7 | `e7/main.swift` | `e7_rates.log` | an AVPlayer's taps at shuttle rates, PreEffects and PostEffects |
| E8 | `e8/main.swift` | `e8_premix.log` | the composed mix's read speed with AAC sources (an offline premix's cost) and a mid-file reader's time to first buffer |
| E9 | `e9/main.swift` | `e9_submix.log` | one `AVAssetReader` with one `AVAssetReaderAudioMixOutput` per timeline track: sub-mixes in one pass, summed against the full mix |

## Q1 — can one composition audio track carry two timeline tracks?

**Top-level timeline tracks: never. A nest's inner tracks: yes, routinely.**

- The A/B assignment walks the timeline's tracks one at a time and gives each a FRESH set of
  composition tracks: `for track in &self.tracks` (`core/src/evaluate.rs:416`), `let mut audio:
  Vec<CompTrack> = Vec::new()` (`:418`), and only after the track's last instance is placed is the
  set appended, `assignment.audio.extend(audio)` (`:501`). `place` looks for a free track only in
  the set it is handed (`:248`). So no composition track is ever shared between two top-level
  timeline tracks.
- Swift only ever SPLITS a plan audio track (by source format, `CompositionBuilder+AudioTracks.swift:94-139`,
  iterated per plan track at `:156-160`); it never merges two. So the map composition track →
  plan audio track → top-level timeline track is a function (many-to-one).
- A nest flattens INTO the track its nest clip sits on: `instances_on_track` expands every clip of
  the timeline track (`core/src/nest.rs:196-209`), and `expand` walks every one of the nest's inner
  tracks into the same list (`nest.rs:295`); the list is sorted by start (`evaluate.rs:422`) and
  packed by `place`. So inner tracks of one nest — and the timeline track's own clips around the
  nest clip — share composition tracks freely.

E1 (the 9e47f56 core's own plans):

| Fixture | Composition audio tracks |
|---|---|
| A: nest on track 2; inner track 7 (clip 9, 0–1 s), inner track 8 (clip 10, 1–2 s) | **1001: clips 9 and 10** — two inner tracks on one composition track |
| B: A + top-level clip 11 on track 2 (2–3 s) + clip 12 on track 3 (3–4 s) | **1001: 9, 10, 11** (nested and top-level share); 1002: 12 (track 3 never shares, though sequential) |
| C: nest inner tracks 7 and 8 both 0–2 s | 1001: 9; 1002: 10 — one timeline track is TWO composition tracks for the whole span (a bus) |
| D: timeline tracks 2 (0–1 s) and 3 (1–2 s), sequential | 1001: 9; 1002: 10 |
| E: one timeline track, two clips overlapping 0.5 s | 1001: 9; 1002: 10 |
| F: one timeline track, ×1 clip abutting a ×1.5 Keep-pitch-off clip | 1001: 9; 1002: 10 (the pitch split, `evaluate.rs:234-237`) |

So: per-composition-track processing is CORRECT in its mapping for a timeline track's chain
(every composition track belongs to exactly one timeline track), and WRONG in its mapping for a
nest's inner tracks, even for linear stages — a composition track carrying clips 9 and 10 would
need inner track 7's chain for one span and track 8's for the next. A linear inner-track stage
can still be scheduled the way clip settings already are (`AudioDSPSpan` per clip span,
`AudioTap.swift:63-110`): each span looks up its clip's inner track's settings. That is exact but
for the filter tail that crosses a cut onto the next span's coefficients. A fader on an inner
track is an envelope term and exact (the core already multiplies a stage per nest level and knows
each stage's track, `audio.rs:178-206`). A nest clip IS a bus, and the codebase already says
nonlinear stages cannot ride down into it: "bus compression is the whole reason a bus has a
compressor" (`AudioTap.swift:145-156`).

Besides the overlap, one timeline track is several composition tracks in three other ways, each
measured below: a pitch split (F) and a format split (`CompositionBuilder+AudioTracks.swift:84-93`)
put abutting clips on different composition tracks, so a chain's STATE does not carry across that
cut; and a nest playing two inner tracks at once (C) is two composition tracks for as long as it
plays.

## Q2 — a timeline track's chain run per composition track

Three arrangements of one track's chain, computed offline (E2) at 48 kHz:
**REF** = chain(Σ cᵢ·G·xᵢ), the chain on the track's sum (what a mixer's track insert does);
**PER** = Σ chain(cᵢ·G·xᵢ), the chain in each composition track's tap with the envelope applied
INSIDE the tap first; **PRE** = Σ cᵢ·chain(G·xᵢ), the chain where today's PreEffects tap runs
(`AudioTap.swift:31-38`, `:586`), told the clip's static gain G as AP2 plans, the fades and
crossfade after it. cᵢ is the core's constant-power crossfade (sin in, cos out; `audio.rs:35-41`).
The compressor is the app's own, copied verbatim (`AudioDSP.swift:195-345`); the limiter is a
lookahead (1.5 ms) true-peak (4×) limiter at −1 dBTP with a 50 ms release, the shape AP2 plans.
Measured over the overlap (or the 2 s after a cut, or the whole bus): the output's true peak, the
worst 50 ms level error and how long it stays over 0.5 dB, the worst BS.1770 momentary error.

| Case | Stage | REF peak | PER peak / worst 50 ms / momentary | PRE peak / worst 50 ms / momentary |
|---|---|---|---|---|
| T1 two tones at −0.9 dBFS, 2 s crossfade | EQ (HP 80 Hz + 6 dB at 3 kHz) | — | exact (−145 dB error/signal) | 0.00 dB / 0.00 LU (−89 dB) |
| | limiter −1 dBTP | −1.10 | **+1.68 dBTP** / 2.78 dB / 2.74 LU | **+1.49 dBTP** / 2.59 dB / 2.56 LU |
| | compressor default (−18 dB, 3:1, 10/200 ms) | −11.42 | −7.97 / 3.43 dB / 3.40 LU | −9.71 / 1.72 dB / 1.70 LU |
| | compressor heavy (−30 dB, 6:1, 5/100 ms) | −24.68 | −20.21 / 4.44 dB / 4.41 LU | −22.55 / 2.14 dB / 2.11 LU |
| T2 the owner's speech ×2 at +29 dB (−16 LUFS), 1 s crossfade | EQ | — | exact (−146 dB) | 0.02 dB / 0.01 LU (−55 dB) |
| | limiter | −1.10 | **−0.25 dBTP** / 0.28 dB / 0.12 LU | −2.60 / 4.43 dB (0.85 s) / 3.13 LU |
| | compressor default | −3.35 | −2.87 / 9.07 dB (1.0 s) / 4.93 LU | −4.60 / 7.56 dB / 5.64 LU |
| | compressor heavy | −15.50 | −12.23 / 8.54 dB / 3.52 LU | −13.53 / 6.87 dB / 2.67 LU |
| T3 speech, hard cut onto another composition track (pitch/format split) | limiter | −1.10 | −1.10 / 0.01 dB / 0.00 LU (identical) | same |
| | compressor default | −3.72 | −3.72 / 10.2 dB **for 0.10 s** / 0.87 LU | same |
| | compressor heavy | −16.00 | −16.00 / 6.4 dB for 0.10 s / 1.72 LU | same |
| T4 a nest bus: the voice and a music bed (−21 dBFS RMS) together for 30 s | limiter | −1.10 | **+1.35 dBTP** / 1.18 dB / 0.80 LU, all 30 s | same |
| | compressor default | −0.91 | +1.79 / 9.87 dB / 4.76 LU, all 30 s | same |
| | compressor heavy | −12.26 | −7.02 / 11.7 dB / 4.95 LU, all 30 s | same |

What this says:

- **Linear stages (EQ, high-pass, gain, pan) are exact per composition track** — PER to float
  rounding, and even in today's PreEffects position, before the envelope, within 0.02 dB and
  0.01 LU (a time-varying gain and a filter do not commute, but only over the filter's impulse
  response, milliseconds). A track EQ or track pan can run in each composition track's tap.
- **A limiter per composition track does not hold its ceiling during an overlap**: two limited
  signals sum past it, +2.7 dB over on tones and +0.85 dB over on speech, for the crossfade's
  length. Its loudness error is small on speech (0.12 LU) and up to 2.7 LU on dense material.
- **A compressor per composition track is a different sound during an overlap**: 3–5 LU
  momentary error and up to 9 dB in a 50 ms window, for the whole crossfade (1–2 s), on both
  material types, in both positions.
- **A cut onto another composition track** (pitch or format split) costs the compressor its
  state: a 0.1 s transient (6–10 dB in one 50 ms window, ≤ 1.7 LU momentary); the limiter
  (state ≤ 50 ms) is unaffected.
- **A nest bus is wrong for its whole length**: +1.4 to +1.8 dBTP over the ceiling, 5 LU
  momentary. That is the case where track processing per composition track fails outright,
  and it is the one AP10's buses are about.
- The approximation therefore stays inside the rule's tolerance (ceiling + 0.5 dB, 1 LU) only for
  linear stages, and for dynamics only away from overlaps and nested buses.

## Q3 — a master insert in the preview

The export has one: it reads the whole mix as 32-bit float (`ExportAudioGain.floatMixSettings`,
`ExporterAudioGain.swift:36-44`, through `ExporterWriter+Settings.swift:62-73`) and gains each
buffer before quantising (`ExporterAudioGain.swift:117-125`, set up at `ExporterWriter.swift:178-181`).
A master limiter belongs beside that gain. The preview has none: the AVPlayer's item carries the
composition and its `AVMutableAudioMix` (`Playback.swift:463-469`) and nothing after the mix is
reachable.

### (b) An AVPlayer API for the mixed audio — none exists (E3, E4, E7)

Searched in the macOS 26.2 SDK (`AVFoundation`, `MediaToolbox`, `AudioToolbox`, `CoreAudio`
headers):

- `AVPlayerItemOutput`'s subclasses are Video, Legible, Metadata and RenderedLegible
  (`AVPlayerItemOutput.h:166, 321, 485, 581`); the newer `AVPlayerVideoOutput` is video only
  (`AVPlayerOutput.h`). No audio output exists for an item or a player.
- `AVAudioMix` holds only per-track `inputParameters` (`AVAudioMix.h:44, 69`), each with one
  `audioTapProcessor` (`:124, 194`). No mix-level tap.
- `MTAudioProcessingTap`'s PostEffects flag is still per TRACK (`MTAudioProcessingTap.h:35-38,
  313-316`). Measured: a PostEffects tap sees only its own track (E4: projection on another
  track's source −0.04), in the reader not even the volume ramp (gain 1.0000 where the envelope
  is 0.43), and in the player it sits after the time-pitch stage (E7: at ×2–×8 it receives one
  second of audio per wall second, where a PreEffects tap receives ×rate). It is never post-mix.
- `AVPlayer.audioOutputDeviceUniqueID` (`AVPlayer.h:543`) only picks a device; `sourceClock`
  (`:422`) only picks a clock.
- **Core Audio process taps** (`AudioHardwareCreateProcessTap`, `AudioHardwareTapping.h`, macOS
  14.2; `CATapDescription.h`, `muteBehavior`) are the one route to the REAL mixed output: tap Frame
  Job's own process, optionally muted, and re-play it processed. Not run here, because it raises
  the system's audio-capture permission prompt (`NSAudioCaptureUsageDescription`) on the owner's
  machine. On its face: it captures the whole PROCESS (every open document, every UI sound), it
  is a capture path rather than an insert, so a processed re-play adds a device round trip that
  the AVPlayer's own A/V compensation does not know about, and it asks a video editor's user for
  permission to record the computer's audio. Not a fit for an insert; possible, permission-gated,
  as a meter source — which Q4 makes unnecessary.
- `AVSampleBufferAudioRenderer` + `AVSampleBufferRenderSynchronizer` can play processed buffers
  in sync, which makes them an alternative OUTPUT for option (c), not a way into the AVPlayer.

### (c) The preview's audio through AVAudioEngine — works (E5, E7, E8)

The prototype: the composition read by `AVAssetReader` + `AVAssetReaderAudioMixOutput` with the
SAME `AVMutableAudioMix` (taps and ramps run there, as the export proves) on a reader thread into
a 2 s ring; an `AVAudioSourceNode` pulling the ring (where the master chain would run — or, better,
on the reader thread, ahead of real time, where lookahead is free); the AVPlayer kept for the
picture with its item's audio tracks disabled; both started at one host time 60 ms ahead,
`player.setRate(1, time:, atHostTime:)` (needs `automaticallyWaitsToMinimizeStalling = false`) and
the source node gating its first sample on that host time. 120 s composition, video + two tapped
audio tracks with ramps; engine output at volume 0. The insert point carried the mixed audio but
ran a pass-through: what a real-time master chain costs there is S1's measurement. Offset = the engine's composition time at a
render callback's host time minus the player item's timebase at the same host time.

| Player set-up | Offset at the 4 starts | Offset range over all runs | Drift over the 60 s run | Underruns | Player's own taps |
|---|---|---|---|---|---|
| audio enabled, `isMuted` | −0.003 … +0.005 ms | −0.004 … +0.033 ms | +0.02 ppm | 0 | run (925 calls): the DSP runs twice |
| audio tracks disabled, default clock | −0.010 … +0.005 ms | −0.010 … +0.264 ms | **+4.43 ppm** (0.26 ms/min, 16 ms/hour; re-anchored at each start) | 0 | none |
| audio tracks disabled, `sourceClock` = the output device's `CMAudioDeviceClock` | −0.008 … +0.004 ms | −0.024 … +0.015 ms | **+0.02 ppm** | 0 | none |

- **Sync:** with `sourceClock` set to the output device's clock, engine and player run on one
  clock: no drift, offsets within ±25 µs across a 60 s run and four seeks. Without it the host
  clock and the device clock part at 4.4–4.5 ppm — inside the rule's 9 ppm, but unbounded. A constant
  remains that this prototype cannot see: the engine's output latency after its render timestamp
  (`presentationLatency` reported 1.5 ms; the device's own latency on top), compensated by
  starting the engine that much earlier. Calibrating it needs an acoustic loopback, so it is a
  manual check.
- **Latency:** the reader's first buffer arrives 3–6 ms after it starts with LPCM sources, and
  30–70 ms with four to eight AAC tracks seeking mid-file (E8); 100 ms of ring is full 2 ms after
  that. Start and seek latency is therefore ~60–150 ms including the 60 ms scheduling margin —
  AVPlayer's order, inside the rule's 150 ms.
- **Throughput:** the reader produces the mix at 290–470× real time (LPCM, two tracks) and
  104–475× (one to eight AAC tracks, pass-through taps); real chains cost more.
- **What it costs the app.** Every transport path in `Playback.swift` (593 lines, at the cap) —
  play, pause, seek, loop wrap, the rebuild that swaps the item on every plan change
  (`Playback.swift:455-490`, where the engine must restart its reader at the same tick), and the
  shuttle (`setRate`, `:526-535`): the AVPlayer renders audio at ×2–×8 (E7: its PreEffects taps
  are fed ×rate audio and its PostEffects taps, after the time-pitch stage, real-time audio), so the engine must read at ×rate and
  time-stretch (`AVAudioUnitTimePitch`) to match; a new reader thread (a new thread seam
  where the app allows five, `Playback+Meter.swift:44-47`); the player composition built without taps; device
  changes (the engine follows the default device, the clock must follow it); the meter moved to
  the engine. It is the largest change of the four, and it replaces the audio path AV sync was
  designed around (spec §11's "`AVPlayerLayer`, not a self-driven view, so A/V sync … come from
  the player", `Playback.swift:44-48`).
- **What it buys:** the preview plays exactly the export's mix, master chain included, live, and
  the mix itself is in hand for metering and for AP13's scrub grains.

### (d) An offline premix — works, but not live

Render the mix (the reader as above, the master chain on it) into a cache file after each edit
and play that file as the preview's only audio track, dry (the live, unmastered taps) while
pending — the ramp-audio pattern (`RampAudioRenders.swift:1-23`: owners, one serial queue,
waits, landing). Cost: E8's throughput, 5.8 s for eight AAC tracks × 10 minutes, per render; the
plan changes on every volume edit (the ramps are in the plan JSON, `plan.rs:81`, and the preview rebuilds on any plan change, `audio.rs:86-89`), so a fader move
re-renders, unless renders are by dirty range with a pre-roll (a limiter's state is ≤ 1 s) and a
splice. Sync and shuttle are the AVPlayer's own. But the person mixing hears the OLD mix until the
render lands, which defeats live mixing; it suits "listen back to what will export", not
"adjust while listening".

### (a) None — master processing in the export only

Costs nothing in the preview. The preview plays the mix pre-master; where the master limiter acts
it plays louder and peakier than the file. The guide and the meter say so — and with Q4's meter
running the master chain on its rebuilt sum, the meter READS the post-master number while the
speakers play pre-master.

## Q4 — a true-mix LUFS meter from the taps

**Yes: the mix rebuilt from the PreEffects taps, each times the plan's envelope, IS the mix the
export writes, to within 0.007 LU momentary.** Today's meter sums per-track PEAKS
(`LevelMeterReading.adding`, `LevelMeter.swift:129-135`, folded by `LevelMeterTrack.mix`,
`:299-306`), an upper bound; nothing in it can give loudness, which needs the summed SAMPLES
(correlated tracks add in amplitude, uncorrelated in power).

E4: three composition tracks (stereo tone bursts held at 0.5; mono pink noise with a 1 → 0.25
ramp and a step to 0.8 at 12 s; the stereo bursts again, sample-aligned with track 1 so the two
are fully CORRELATED, fading in over 5–6 s to 0.7), each with a recording PreEffects tap, read by
`AVAssetReaderAudioMixOutput` with the same `AVMutableAudioMix` (the export's read,
`ExporterWriter+Settings.swift:62-73`). The rebuild: Σ envelopeₖ(t) · tapₖ(t) per sample.

| Comparison | Error/signal | Momentary (400 ms) max \|ΔLU\| | Short-term (3 s) max \|ΔLU\| |
|---|---|---|---|
| rebuild vs reader mix, 0–20 s | −52.8 dB | 0.0067 | 0.0005 |
| away from the 12 s step (0–11.9 s) | **−100.7 dB** (float rounding) | 0.0004 | 0.0001 |
| the step's 100 ms | −35.2 dB (worst sample 0.072) | — | — |
| whole programme (ungated mean) | −11.277 LUFS both | | |

- **The one difference is AVFoundation's slew at a gain STEP**: the mix slides to a new volume over
  ~25 ms where the envelope jumps (#87, `CompositionBuilder+AudioTracks.swift:254-268`). It costs a
  hundredth of an LU; a meter can ignore it, or model the slew (full scale per 1,200 frames).
- **The mono rule:** a mono composition track reaches the stereo mix at UNITY in both channels
  (L = R = 1.000000 × the tap's sample). So a mono track counts twice in BS.1770's channel sum,
  which is what the export measures too.
- **Today's peak sum over-reads** the true mix's peak by +0.38 dB on average and up to +3.85 dB
  (214 blocks of 4,096 frames).
- **PostEffects is no help**: a PostEffects tap sees only its own track (projection on another
  track's source −0.04) and, in the reader, NOT the volume ramp (gain 1.0000 where the envelope is
  0.43; E7 for the player). So no tap anywhere sees a post-fader or post-mix signal; the meter must
  multiply by the envelope, as it already does for peaks (`LevelMeter.swift:9-26`).

**How an AVPlayer calls the taps** (E4 part 3, muted player, play 4 s, seek to 9 s, play 3 s):
every tap of the player ran on ONE thread, 1,920 frames (40 ms) per call, first call 88 ms after
`play()`, one invalid-time call per track at each start (as `AudioTap.swift:419-421` says). But the
tracks' timestamps in one cycle are NOT equal: track 1 at 0.0400 s, track 2 at 0.0427, track 3 at
0.0534 — fixed per-track offsets of up to 13 ms (189 of 221 cycles differ). A track is called
through its gaps (track 3, whose media starts at 5 s, was called from 0.05 s), so every track's
stream is continuous. And the rebuild from the PLAYER's taps equals the reader's mix bit for bit
over what was played (−334.7 dB at 0.5–3.0 s; −138.6 dB after the seek, across the ramp).

At shuttle rates (E7) the PreEffects taps are fed ×rate: at ×2, ×4 and ×8 each tap received 3.4,
6.5 and 12.6 s of composition-time audio in 1.5 s of wall time, so a rebuilt sum stays in
composition time and measures the CONTENT's loudness at any forward rate (the taps' DSP also runs
×rate). Whether the meter shows anything off ×1 is AP7's choice; a PostEffects tap, after the
time-pitch stage, got real-time audio instead.

So a real-time true-mix meter is buildable on today's taps, without a new tap and without option
(c): each tap, after its chain, copies its block (pre-envelope) and timestamp into a per-track
single-producer ring (a copy; no lock, no allocation, the discipline `LevelMeterSink` keeps); a
non-real-time consumer (the meter's 30 Hz timer, or a utility queue) evaluates each track's
envelope per sample (`MediaPeaks.envelope`, already the meter's), sums the tracks BY TIMESTAMP,
completing a 100 ms block only when every sounding track has delivered past its end (the offsets
above are why it cannot simply add buffers as they arrive), K-weights the sum, and keeps 100 ms
block energies: momentary (4 blocks), short-term (30), integrated (BS.1770's gating, which
`Loudness.swift` already implements), and a 4× true peak on the sum. Accuracy is the table's: the
export's own mix within 0.01 LU. Because the sum exists off the audio thread, the meter can also
run the MASTER chain (AP2's limiter, the export's loudness gain) on it and read what the FILE will
measure, even though the preview does not play that chain — measurement and playback decouple.
Option (c) would give the mix for free, but at the price below; the rebuild costs a copy per tap.

## Q5 — stems as one multitrack movie

E6 wrote five 10 s movies with `AVAssetWriter`, one `AVAssetWriterInput` per stem (Dialogue: a
tone, Music: noise, Effects: clicks; stereo 48 kHz), interleaving appends 4,800 frames at a time,
each input titled (`.quickTimeUserDataTrackName` in a .mov, `.commonIdentifierTitle` in an .mp4)
and `languageCode = "eng"`:

| File | AVURLAsset | Each track decoded alone | ffprobe | What an AVPlayer plays (taps per track, 1 s) |
|---|---|---|---|---|
| `stems_aac.mov` (AAC 192k) | 3 audio tracks, 10.000 s, titles read back | its own stem, lag 0 (priming trimmed) | 3 × aac, 10.000 s, all `default=1` | all three (12/11/11): QuickTime plays them MIXED |
| `stems_lpcm24.mov` (24-bit LPCM) | 3 tracks | its own stem at 130–143 dB SNR (exact at 24 bits) | 3 × pcm_s24le | all three, mixed |
| `stems_aac.mp4` | 3 tracks, titles read back | its own stem, lag 0 | 3 × aac | all three, mixed |
| `mix_plus_stems_disabled.mov`: the mix enabled, 3 stems `marksOutputTrackAsEnabled = false` | 4 tracks, enabled true/false/false/false | each its own | 4 × aac, `default` 1/0/0/0 | **the mix only** (12/0/0/0) |
| `mix_plus_stems_altgroup.mov`: as above + one `AVAssetWriterInputGroup` | 4 tracks | each its own | 4 × aac, 1/0/0/0 | the mix only |

So a multitrack movie works: `AVAssetWriter` takes several audio inputs into one .mov or .mp4,
AVFoundation and ffprobe both see every track at full length, and each decodes to its own stem
sample-aligned. Two things to know: with every stem enabled, QuickTime (AVPlayer) plays the stems
summed — which is the mix again only if no master processing ran; and ffprobe does not show the
track titles (its `handler_name` is "Core Media Audio" for all), while ffmpeg/VLC pick one audio
stream by default, so a recipient outside Apple's tools must map tracks by index. The
"mix enabled, stems disabled" shape plays the mix alone in AVPlayer (so in QuickTime Player, which
is built on it), marks only the mix `default` for ffmpeg-based players, and still carries every
stem for an editor (whether Resolve and Premiere import them all was not run here).

## One more fact for the export: sub-mixes in one pass (E9)

One `AVAssetReader` takes several `AVAssetReaderAudioMixOutput`s, each over its own composition
tracks with its own `AVMutableAudioMix` (the taps and ramps of those tracks). Read alternately,
two outputs (composition tracks 1001 + 1003 as "timeline track X", 1002 as "Y") completed in one
pass (0.09 s for 20 s), each sub-mix equals its tracks' taps × envelopes (−102 dB, −108 dB), and
X + Y equals the full mix to float rounding (−147.7 dB, worst sample 1.2e-7). So the EXPORT can
read one sub-mix per timeline track or bus — Q1 says which composition tracks each one owns — run
true track and bus dynamics on each sum, add them, and run the master chain, all in the float
stage it already has; and the same pass writes stems.

## Recommendations

**AP7 — the live meter.** Build the true-mix meter on the taps the metering build already puts
on every composition track (Q4): each tap copies its post-chain, pre-envelope block and timestamp
into a per-track single-producer ring; a non-real-time consumer applies the plan's envelope
(`MediaPeaks.envelope`), sums by timestamp (completing a 100 ms block only when every sounding
track has passed it — the per-track offsets of up to 13 ms are why), K-weights, and keeps block
energies for momentary, short-term and gated integrated loudness, plus a 4× true peak of the sum.
It matches the export's mix within 0.01 LU (E4), counts a mono track in both channels, and needs
no new tap, no permission and no change to how the preview plays. Once a master chain exists
(AP2's limiter and loudness gain), the meter runs that chain on its rebuilt sum and labels the
reading as the export's; it can also run AP10's track dynamics on per-track sums (it knows each
composition track's timeline track). Do not move playback to option (c) to get a meter. Proof as
planned (EBU Tech 3341 through a probe of the consumer), plus E4's shape — the probe's rebuilt mix
against `AVAssetReaderAudioMixOutput` within 0.1 LU on a composition with correlated, mono and
ramped tracks. Decide at AP7 what the meter shows off ×1 (E7).

**AP2 — the export's master limiter against the preview.** Put the master limiter in the export's
float stage beside `ExportAudioGain` (lookahead is free there: the reader is offline), so the
loudness target limits instead of capping. It is NEEDED, not only convenient: a clip limiter in
the tap (PRE in E2) holds each clip under its ceiling, but two limited clips crossfading sum past
it — +1.49 dBTP on tones — so only a stage on the sum can promise the file's true peak. In the
preview, option (a): no master stage; the guide says the preview plays before the export's
limiter and loudness gain, and AP7's meter shows the post-master number. The clip limiter itself
is live and exact per clip (its position before the fader is its definition, so PRE is not an
error for a clip stage).

**AP10 — tracks, buses, stems.** Ask the owner at AP10, with this record:

- *Exact and live, recommended as built:* the track FADER and track PAN as envelope terms (the
  core's stage product, `audio.rs:178-206`) and the tap's pan; track EQ and other LINEAR stages in
  each composition track's tap (E2: exact; −55 dB error and 0.01 LU even in today's PreEffects
  position). The plan must say which timeline track each composition track belongs to (Q1 makes
  that one id per composition track; the plan does not publish it today) — and for a nest's inner
  tracks, which inner track each SPAN belongs to, scheduled like `AudioDSPSpan`.
- *Track and bus DYNAMICS (compressor, limiter on a track, a nest or a bus) and the master
  chain:* exact in the export by E9's one-pass sub-mixes. In the preview, the recommended
  answer is per-composition-track dynamics as an approximation, said plainly in the guide: exact
  away from overlaps; during a crossfade 3–5 LU momentary and a limiter over its ceiling by up to
  2.7 dB; a 0.1 s transient at a pitch or format split; and WRONG for the whole time a nest or
  bus sums two simultaneous tracks (+1.4–1.8 dB over the ceiling, ~5 LU). The meter (AP7) can show
  the export-exact number regardless.
- *The alternative, if the owner wants the preview to SOUND exactly like the export:* option (c),
  the preview's audio through `AVAudioEngine` fed by the same one-pass sub-mix reader, with
  `player.sourceClock` set to the output device's clock (E5: 0.02 ppm, ±25 µs, 0 underruns,
  60–150 ms to start). It works, but it replaces the preview's audio path: every transport path
  in `Playback.swift` (at its cap), the shuttle's time-stretch at ×2–×8, a new reader thread
  seam, device changes, and an output-latency calibration only a person can check. Worth its own
  phase or road map, not a corner of AP10; offline premix (d) is not recommended for mixing,
  because a fader move is not heard until the re-render lands.
- *Stems:* separate files remain the recommended default (every tool reads them). A multitrack
  movie is measured to work (Q5) and can be offered beside it: the mix as the enabled track and
  the stems disabled plays right in QuickTime and keeps every stem; with all stems enabled
  QuickTime plays them summed. Either way the stems come from E9's one-pass sub-mixes, and the
  stems sum to the mix only when no master or bus dynamics run (AP10's null proof holds then).

## What this spike did not measure

- The acoustic offset of the engine's output against the picture (option c): it needs a loopback
  or a person; a manual check if (c) is ever built.
- Core Audio process taps: not run, to avoid raising the audio-capture permission prompt on the
  owner's machine; their verdict above is from the headers and the API's documented shape.
- Reverse playback: E7 saw the taps called at −1 but did not characterise what an AVPlayer plays
  backwards.
- CPU of real chains in E5 and E8: the taps there pass audio through; S1 measures stage costs.
- Whether Resolve and Premiere import the multitrack movie's stems (Q5): not run here.
