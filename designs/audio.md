# Road map "audio" — a professional audio toolset (tiers A and B)

**Opened 2026-10-30** (AP0), when the owner answered the five choices below ("Yes, lift scopes,
and allow Apple's built-in audio effects", then "OK" to each of the rest): AU-2…AU-4, and spec
§1's audio non-goal lifted. The brief
is `designs/audio-survey.md` (its tiers A and B; tier C is not in this road map). The worktree is
`.claude/worktrees/audio-updates`, branch `worktree-audio-updates`, from `33eeed0`. Decisions are
AU-2 onward, in `designs/spec/11-decisions/audio.md` (AU-1, the ×32 volume ceiling, is built).

## Goal

Frame Job's audio today is a creator-tier strip: volume, fades, clip-extent ducking, pan, mono,
a compressor, steady-noise reduction, peak Normalize, and an export loudness target that only
turns the mix down (`docs/guide/audio.md`, `docs/guide/export.md`). After this road map a person
can take a quiet, noisy or uneven voice recording to a delivery loudness with one command and
then refine it: loudness they can see and target, a true-peak limiter, EQ, a gate, a de-esser,
hum removal, voice isolation, parameters that move over time, J- and L-cuts, track faders and
buses, stems, speech-aware ducking, matching, scrubbing and voice effects. Every control has its
MCP mirror, as every control does today.

## What it delivers first

The owner's recording, `samples/Rode-usb-mic.m4a`, peaks at −18.6 dBFS with an integrated
loudness of −44.7 LUFS. Peak Normalize and the export's loudness target both stop near −27 LUFS
(the survey's §2), because neither can reduce a peak. **After AP2, one Normalize press in
Loudness mode takes it to the chosen target (−16 LUFS by default) at −1 dBTP.** After AP6, one
Enhance Voice press also cleans it: the high-pass, the noise floor in the pauses (about
−36 dBFS once lifted, 65 % of the file), the compressor set from the clip's own level, the
limiter and the target.

## The owner's choices (answered 2026-10-30: all five as recommended)

Recorded as AU-2 (choice 1), AU-3 (choices 4 and 5) and AU-4 (choices 2 and 3). The owner,
on the rest: "We'll address other questions as we progress. If builds can be run in multiple
lanes, do so."

1. **Scope (spec §1).** Lift "no EQ" and "no mix buses", and allow Apple's own audio units
   inside Frame Job (as `AVAudioUnitTimePitch` already runs for speed-ramp audio). Hosting
   third-party Audio Unit plug-ins stays out of this road map (tier C, C5). *Recommended.*
2. **Normalize's default.** Keep peak normalize as the button's default until AP2's limiter
   lands, then make **Loudness** the default with Peak a choice beside it. *Recommended.*
3. **The default loudness target.** −16 LUFS integrated at −1 dBTP (voice platforms and
   podcasts), with −14 (YouTube's playback reference) and −23 (EBU R 128) as quick picks.
   *Recommended.*
4. **Own DSP or Apple's units for the live stages.** Frame Job's own DSP for EQ, gate,
   de-esser, hum notch and limiter, written beside the compressor: live in the tap,
   deterministic, testable against analytic responses. Apple's units only where Frame Job cannot
   write its own: ML voice isolation (`AUSoundIsolation`) and E8's voice effects, both rendered
   offline as speed-ramp audio is. AP0's spike S1 confirms or overturns this. *Recommended.*
5. **One fixed chain order, not a user-ordered list.** Channels → high-pass and EQ → hum notch
   → isolation or noise reduction → gate → de-esser → compressor → limiter, each stage off by
   default and inert when off. A closed vocabulary like every other effect (§11 R5-1), and the
   order an engineer would choose for voice. *Recommended.*

Asked later, at the phase that needs them (each has a recommendation there): how the volume
line is edited (AP8), the split-edit model (AP9), track processing in the preview and the stem
format (AP10), and where speech spans live for ducking (AP11).

## The orchestrator's defaults (each one the owner can change)

- **Working arrangement:** this worktree is the integration branch; each phase is built
  through litecode in a lane of its own, gated, committed, rebased onto the integration branch
  one at a time and gated again there, as codec-export (CX-11) and grading (GR-25) merged
  phase by phase. Merging into main is done from the main checkout.
- **Lanes (the owner's "multiple lanes"):** after AP0, at most three at once, split by the
  files they touch. **Lane A, the voice block:** AP1 → AP2 → AP3 → AP4 → AP5 → AP6, then AP8
  and AP14, which build on its stages. **Lane B, editing and playback:** AP9 → AP13 → AP7
  (the meter after AP1 has landed, since both read `Loudness.swift`). **Lane C, the mix:**
  AP11 → AP10 (after AP2 has landed: both work in the export's float gain stage) → AP12
  (after AP3). A lane whose next phase waits on another lane's phase waits; it never builds
  against an unlanded one.
- **Collisions between lanes:** each phase numbers its decisions in its own block (APn's
  AU-n0…, AU-2's note), and a format bump is provisional until its phase lands: the
  integrator renumbers it (and its `schema_vN.rs`) when another lane landed one first.
- **Agent parity:** every new property is a `set_audio` key, every new command a tool, every
  new answer readable through `get_project`.
- **Proof currency:** exports decoded to PCM and measured by the proof's own arithmetic
  (`phase5_proof.py`'s BS.1770 and 4× true-peak oversampler), synthetic fixtures with known
  answers, and the owner's samples where present. What only ears can judge is a row in
  `docs/manual-checks.md`.
- **Samples:** the owner records the survey's §6 list. A phase uses a sample when it exists and
  a synthetic fixture otherwise; no phase waits for one.
- **Persisted fields** carry serde defaults and bump the format (`core/CLAUDE.md`); an older
  project opens unchanged and sounds the same.

## How it fits the tree (at `33eeed0`)

- **The clip strip runs in a tap, before the fader.** `AudioTap.swift` (595) puts one
  `MTAudioProcessingTap` (PreEffects) on each composition audio track and schedules each clip's
  settings by span (`AudioDSPSpan`). `AudioDSP.swift` (**890, over the cap**) holds pan, the mono
  fold, the compressor (default threshold −18 dB) and noise reduction, real-time safe. Volume,
  fades and ducking come after the tap, as the core's envelope played as volume ramps
  (`core/src/audio.rs` 537, `audio_duck.rs` 136). **A new live stage sees the clip at its
  recorded level**, so a level-relative stage (limiter, gate) must be told the clip's gain.
- **The preview has no post-mix insert; the export does.** One tap per input, already used by
  the meter (`LevelMeter.swift` 400, which sums per-track peaks as an upper bound, not the mix).
  The export measures a 32-bit float mix and gains it in `ExporterAudioGain.swift` (179); its
  write pass still decodes 16-bit integers (#86).
- **Offline renders have a pattern.** Speed-ramp audio renders into `cache/ramp-audio/` through
  `RampAudioRenders` (a serial queue, owners, a wait in the export, dry while pending).
- **Loudness exists once.** `Loudness.swift` (**674, over the cap**) is BS.1770-4 for the
  export; `ExporterLoudness.swift` (211) its measurement pass.
- **The model.** `AudioProps` lives in `core/src/model_props.rs` (551), checked by
  `props_check.rs` (526) and clamped by `actions_clamp.rs` (386); pan, mono, compressor, noise
  reduction, duck and keep pitch are BASE-only (`InspectorBinding+Writes.swift`'s
  `structural(audio:)`), and only volume, mute and the fades animate.
- **Caches.** Peaks, sync features and speech (Silero VAD) per media, on the cache lane
  (`MediaCacheLane.swift`); a loudness cache would be a fifth beside them.

## Phases

| Phase | Survey items | What a person gets |
|---|---|---|
| AP0 | — | Scope lifted, the spike's answers, the files split |
| AP1 | A2, A8 (readout) | A clip's LUFS shown; Normalize to a loudness |
| AP2 | A1, A13 | A true-peak limiter; the export reaches its loudness; 24-bit |
| AP3 | A3, A7, B7 | EQ and high-pass, hum removal, channel selection |
| AP4 | A5, A6 | Gate/expander, de-esser |
| AP5 | A4, B4 | Voice isolation; de-reverb if isolation does it |
| AP6 | B1, B3, B8 | Enhance Voice; the leveller; clean-up when a voice-over lands |
| AP7 | A8 | Live LUFS and true-peak meter |
| AP8 | A9 | Every audio parameter animates; the volume line on the clip |
| AP9 | A10 | J- and L-cuts that keep sync; reversible Detach |
| AP10 | A12, A11 | Track faders, track and master processing, stems |
| AP11 | B2, B9 | Ducking by speech; fade and crossfade shapes |
| AP12 | B6 | Match one clip's level and tone to another |
| AP13 | B5 | Audio while scrubbing |
| AP14 | B10 | Voice effects (E8, #123) |

AP1–AP6 are the voice block, in the order the owner's recording needs them. AP7 onward is the
mixing block and can be reordered freely; only AP12 needs AP3, and AP6 needs AP2–AP5.

### AP0 — scope, the record, the tolls and the spike

- **Decisions:** AU-2 (the scope, from choice 1), AU-3 (the chain, choices 4 and 5), AU-4 (the
  loudness defaults, choices 2 and 3). Spec §1's non-goal sentence rewritten; this road map
  opened.
- **Tolls, each a pure move landed and gated alone:** `AudioDSP.swift` cut at its MARKs (the
  compressor and noise reduction into their own files, the chain kept); `AudioTap.swift`'s
  schedule and parameters (its first two MARKs) out of the tap; `Loudness.swift` cut below the
  cap; `AudioProps` and its vocabulary out of `model_props.rs` into a new `model_audio.rs`.
- **Spike S, its rule fixed before its run, its record here:**
  - **S1 — own DSP or Apple units, live.** A biquad EQ and Frame Job's limiter against
    `AVAudioUnitEQ`, `AUNBandEQ` and `AUPeakLimiter` driven inside the tap: byte-identical
    exports run twice, preview against export, CPU per track at eight stages, latency.
  - **S2 — voice isolation.** `AUSoundIsolation` rendered offline over the owner's recording:
    speed against real time, latency, determinism across runs, the pause floor and the speech
    band against the shipped noise reducer, and whether it reduces reverberation (B4's
    question), on a reverberant sample if one exists.
  - **S3 — tracks and the master in the preview.** Whether one composition audio track ever
    carries two timeline tracks; the error of a track chain run per composition track during an
    overlap (zero for linear stages, measured for dynamics); the options for a preview master
    limiter (none and say so, per-track, or an offline premix); rebuilding the true mix from the
    taps for a LUFS meter.
  - **S4 — a loudness cache.** K-weighted 100 ms block energies per media: size, build time on
    a 20-minute file, and integrated LUFS over any window against `Loudness.swift` measuring an
    export of the same window (agreement within 0.1 LU).
- **Acceptance:** `make gate` after each toll; the spike's verdicts recorded here.

### AP1 — loudness you can see and target (A2, A8's readout)

- A per-media loudness cache (`cache/loudness/<id>.bin`, S4's format) on the cache lane after
  peaks, current by `CacheStamp` like the others.
- The Volume section reads the clip's integrated loudness (gated, over the window that plays)
  and its true peak beside the Gain row.
- Normalize gains a **Loudness** mode: a target in LUFS, each clip of a selection to the same
  target, which is what "match these clips" means. Until AP2, a clip whose peak would pass the
  ceiling stops short and says where it landed, as the volume ceiling does today.
  `normalize_clip` gains `mode` and `target_lufs`.
- **Proof:** exports of normalised fixtures measured by the proof's BS.1770 within ±0.5 LU;
  the owner's recording; a selection of two levels landing equal.

### AP2 — limiters, and an export that reaches its loudness (A1, A13)

- A **clip limiter** stage in the tap: lookahead, 4× oversampled true-peak detection, a ceiling
  in dBTP. Because the fader is downstream, the stage is told the clip's gain (decision AU-n:
  the base volume, with fades and ducks only ever lowering it), and its lookahead is a lead
  like noise reduction's (SY-25).
- The **export:** a float decode before the gain (#86, closing it), a master limiter in the
  float write pass so the loudness target limits instead of capping, and an `audio_bits` choice
  of 16 or 24 on WAV and AIFF.
- Loudness Normalize uses the clip limiter, so the owner's recording reaches −16 LUFS at
  −1 dBTP. If choice 2 says so, Loudness becomes the button's default here.
- **Proof:** every export's true peak at or under its ceiling by the proof's oversampler; the
  loudness target met within ±0.5 LU on `phase5_proof.py`'s crest fixture, which today lands
  quieter; a 24-bit file decoded with its low bits used; the owner's recording.
- **Manual check:** no pumping or distortion on speech and on music.

### AP3 — EQ, hum removal and channel selection (A3, A7, B7)

- **EQ:** a high-pass with a slope, a low-pass, low and high shelves and a number of parametric
  bands (set at AP3), with voice presets (rumble cut, de-mud, presence). An EQ section in the
  Sound sub-tab with the response curve drawn.
- **Hum:** notches at 50 or 60 Hz and its harmonics, depth and harmonic count.
- **Channels:** both, left only, right only, swapped, before the mono fold, so a mic recorded
  on one channel of a stereo file plays at its level.
- **Model:** `audio.eq`, `audio.hum`, `audio.channels`; format bump; MCP keys.
- **Proof:** tones and sweeps through each band against the biquad's analytic response
  (±0.1 dB); notch depth at each harmonic; a channel pick sample-identical to its source channel.

### AP4 — gate, expander and de-esser (A5, A6)

- A downward **expander/gate** sharing the compressor's envelope follower: threshold relative
  to the clip's measured level (AP1), ratio, range, attack, hold, release.
- A **de-esser:** a compressor keyed on a high band (frequency, threshold, range).
- **Model, inspector, MCP** as AP3; format bump.
- **Proof:** a tone burst over noise, the pause floor lowered by the range and the burst
  untouched; sibilant noise bursts reduced in band and the voice band untouched; the owner's
  recording's pause floor.

### AP5 — voice isolation (A4; B4's verdict)

- **Isolation** by `AUSoundIsolation` (S2), rendered offline per clip window into
  `cache/isolated/` on the ramp-audio pattern: an Amount (wet/dry), dry while pending, the
  export waiting for its render, re-rendered when the window or the file changes.
- **De-reverb (B4):** if S2 measured reverberation removed, it is this control and the guide
  says so; otherwise B4 is filed with tier C and the measurement.
- **Proof:** the render aligned with the dry clip within a sample (cross-correlation); the pause
  floor and the speech band against the dry clip; dry while pending; an export that waits.
- **Manual check:** artefacts on the owner's voice at Amount 100 % and 50 %.

### AP6 — Enhance Voice, the leveller, and clean-up when a voice-over lands (B1, B3, B8)

- **Enhance Voice** (Clip menu, a button in the Sound sub-tab, an `enhance_voice` tool): reads
  the clip's loudness, its peak and the noise floor over the VAD cache's non-speech spans, then
  writes ORDINARY settings a person can see and change — high-pass, isolation or noise
  reduction, gate, de-esser if the high band is hot, a compressor set from the clip's own
  level, the limiter and the loudness target. One undo step; pressing it twice changes nothing.
- **Leveller (B3):** a slow gain-rider stage for a speaker who moves on and off the mic, off by
  default, turned on by Enhance Voice when the speech's short-term loudness range calls for it.
- **At record time (B8):** a recorder setting, "Enhance the microphone when it lands", applying
  Enhance Voice to the Microphone clip in the landing's grouped edit.
- **Proof:** the owner's recording to −16 LUFS ±0.5 at −1 dBTP with its pause floor lowered;
  idempotence; one undo step; a voice-over that lands enhanced.

### AP7 — live loudness and true-peak metering (A8)

- Momentary, short-term and integrated LUFS and true peak while playing, over the true mix
  (S3's method), with a reset; the per-clip readout is AP1's.
- **Proof:** a probe compiled from `app/Sources` fed EBU Tech 3341's test signals, each within
  its tolerance.

### AP8 — every audio parameter animates; the volume line (A9)

- Pan, EQ gains and frequencies, gate, de-esser, compressor and limiter settings, isolation's
  Amount and the leveller's target as action ends; the tap's schedule carries per-parameter
  ramps from the core, not one constant per span. Switches (a stage on or off) still change at
  an action's end, as booleans do (§5.4).
- **The volume line:** each clip draws its envelope over its waveform; dragging it edits the
  level. **Asked at AP8:** edit through actions (a point is an action's end, which keeps §2's
  "Actions, not keyframes"; recommended) or add keyframes (lifting it).
- **Proof:** exports of an animated pan and EQ against analytic gains; the line drawn where
  the plan's ramps are.

### AP9 — split edits (A10)

- J- and L-cuts that keep sync, and Detach Audio made reversible (Attach Audio).
- **Asked at AP9:** a LINKED pair — Detach's two clips carrying one link id, moved, cut and
  deleted together, with ⌥-drag trimming one half alone (recommended: it fits one kind of
  track, and an audio lead on its own track cannot collide with "overlap is a transition") —
  or one clip whose audio window extends past its picture.
- **Proof:** core tests of every edit on a linked pair; exports with the audio leading and
  trailing the picture by a known amount.

### AP10 — tracks, buses and stems (A12, A11)

- A **track fader and pan** in the header and the Track menu (an envelope term in the core, as
  a track's mute is).
- **Track and master processing** by S3's verdict, asked at AP10: the master limiter in the
  export at least; in the preview, as S3 found possible, or said plainly where it differs.
- **Stems:** each track, or a chosen set, as its own file in one export; **asked at AP10:**
  separate files (recommended) or a multitrack movie if S3 measured it to work.
- **Proof:** fader arithmetic on an export; the stems summed against the full mix (a null within
  quantisation when no master dynamics run).

### AP11 — ducking by speech, and fade shapes (B2, B9)

- **Ducking by speech:** the ducking clip's speech spans from the VAD cache, with pre-roll, hold
  and release, drawn as the envelope it makes. **Asked at AP11:** spans persisted on the media
  (a detected field, as Camera Log's is; recommended, so the plan stays a function of the
  project) or handed to the plan by the host.
- **Fade and crossfade shapes:** linear, S-curve, +3 dB and −3 dB, sampled by the core like an
  eased action.
- **Proof:** the plan's ramps against fixture spans; exports of each fade shape against its
  formula.

### AP12 — match one clip to another (B6)

- **Match Loudness** to a reference clip (AP1's measurement) and **Match EQ:** the reference's
  and the target's average speech spectra fitted to AP3's bands. A command and a tool.
- **Proof:** pink noise tilted by a known EQ matched back within ±1 dB a band.

### AP13 — audio while scrubbing (B5)

- Short grains of the mix at the scrub position while the playhead is dragged, off when the
  drag stops; the design is set at AP13 against what AVFoundation allows.
- **Proof:** a probe of the grain scheduler. **Manual check:** the feel, and no clicks.

### AP14 — voice effects (B10, E8)

- E8 as designed and measured (`designs/adr/effects-survey.md`, #123): sixteen kinds as fixed
  chains of Apple units rendered offline, with an amount and a pitch. Closes #123.

### AP0's record (2026-10-30)

**Landed.** `9e47f56`: the survey, this plan, AU-2…AU-4 and spec §1's audio non-goal lifted. The
tolls, each a pure move gated alone (PASS 307, 246, 243 and 136 s) and checked line-identical
against `9e47f56`: `c67ccee` (`AudioDSP.swift` 890 → 368; `AudioCompressorStage.swift` 158,
`AudioNoiseReductionStage.swift` 376), `54e4649` (`AudioTap.swift` 595 → 328;
`AudioTapSchedule.swift` 273), `a0eb094` (`Loudness.swift` 674 → 511; `ExportLoudness.swift` 168,
which `phase5_chrome.py`'s section 9 now compiles too), `6a51bfc` (`model_props.rs` 551 → 459;
`model_audio.rs` 114); the map entries `fec5132`.

**Spike S.** Each record states its rule before its runs; records, logs and the instruments each
spike wrote are in `tools/proof/audio_spike/S1…S4/` (copies of product code they compiled are left
out: `git show 9e47f56:<path>` gives them back).

- **S2, voice isolation — viable, with the High Quality Voice model.** `AUSoundIsolation`
  (`aufx`/`vois`/`appl`) through `AVAudioEngine` manual rendering; parameter 1 = 0 selects High
  Quality Voice (the unit's default, Voice, loses everything above 10.5 kHz and 0.7–1.1 dB of the
  voice). Each channel renders as its own mono render; latency is a constant 4440 frames (92.5 ms)
  at 48 kHz mono, to be discarded and pinned by cross-correlation in a proof; 4 s of the media is
  fed before a window (the model adapts over 0.5–2 s; silence resets it). 28–51× real time at
  load 9. Whole-file renders are byte-identical; windows starting mid-file differ by about −51 dB,
  so proofs compare levels and alignment, never bytes, and a cache is never checked by
  re-rendering. On the owner's recording the pause floor falls 10.9 dB (mean) with speech moved
  +0.14 dB and every octave 63 Hz–8 kHz within ±0.3 dB; the shipped reducer reaches the same mean
  floor only by costing 1.3 dB of speech. The unit's 50 % equals a sample-aligned 50/50 mix of dry
  and a 100 % render (−84 dB), so Amount is a crossfade of one cached render and is not in the
  cache key. **De-reverb (B4) rides on it:** on a synthetic RT60 0.6 s room, C50 +5.2 dB and the
  late tail −5.3 dB ("reduces room echo"). Because it renders offline from the media, isolation
  runs before the live chain — AP5 amends AU-3's order. At 100 % the pauses become dead air.
- **S3, tracks and the master in the preview.** A composition audio track never carries two
  top-level timeline tracks (`evaluate.rs`), but a nest's inner tracks share one. Track gain, pan
  and EQ per composition track are exact (EQ −145 dB). Dynamics are not: a limiter misses its
  ceiling by +0.85 dB through a crossfade on the owner's speech, a nest bus by +1.4–1.8 dB. Nothing
  in the macOS 26.2 SDK reaches an AVPlayer's mixed audio; playing the preview's sound through
  `AVAudioEngine` (a reader into a ring, the player's audio off, the device clock) prototypes at
  0.02 ppm drift and 60–150 ms to start, at the cost of rewriting the transport; an offline premix
  runs 104–475× real time but lags edits. In the export, one reader with one mix output per
  timeline track gives sub-mixes that sum to the mix within −147.7 dB, so track and bus dynamics,
  the master chain and stems are exact there. Summing the existing taps by timestamp, each times
  the plan's envelope, matches the export's mix within 0.0067 LU momentary; today's sum of
  per-track peaks over-reads the true peak by up to 3.85 dB. `AVAssetWriter` writes multitrack
  `.mov`/`.mp4` stems (AAC or 24-bit LPCM) that AVFoundation and ffprobe read.
- **S4, the loudness cache — 10 ms blocks.** Against the export's own meter fed exactly the window:
  100 ms blocks miss by up to −0.139 LU, 25 ms by −0.149, 10 ms stay within 0.076 (97.5 % of 200
  random windows within 0.1 LU; the rest is where BS.1770's 400 ms grid falls, which moves the
  export's own figure by a median 0.17 LU). 10 ms is the peaks grid, so `MediaPeaks.window`,
  `ReverseMirror` and the source map apply unchanged. Records are Float32 per block (mono `z, tp`;
  stereo `zL, zR, zLR, tpL, tpR`, which answers any 2×2 channel matrix): 2.75 MB/h mono, 6.9 MB/h
  stereo, built at about 1 s per 20 minutes. Gating blocks are counted from the exact window length;
  a reversed clip's grid starts at the forward window's end; a ramped clip is measured on its ×1
  render. **The export copies a mono clip into both channels, +3.01 LU**: the owner's recording is
  −41.67 LUFS as exported (−44.7 is the mono file's own figure), and Normalize must use the
  exported figure. Speech-only loudness reads 1.1–1.7 LU above gated BS.1770 here; AU-4's gated
  target stands.
- **S1, own DSP or Apple's units live — own; AU-3 stands, no amendment.** The rule, fixed before
  the runs: a subject is admissible for a live stage when it allocates and locks nothing on the
  tap's thread, reads byte-identically twice AND whatever the buffer sizes, is within 0.1 dB of
  its analytic response (a limiter within 0.1 dB of a −1 dBTP ceiling), has one constant latency
  ≤ 512 samples, and an eight-stage stereo chain costs ≤ 1 % of real time. Frame Job's own stages
  (Double RBJ biquads, an expander, the shipped compressor, a lookahead true-peak limiter) pass all
  five; no Apple unit passes for any stage. Apple's output depends on how the stream is cut into
  render calls — at rounding level for `AUNBandEQ` and `AUPeakLimiter` (−145 to −223 dBFS), up to
  −34 dBFS for `AUDynamicsProcessor` on irregular slices, which `AudioTap`'s splits at cuts and the
  player's 4096-frame against the reader's 512-frame buffers both make. `AUPeakLimiter` limits
  sample peak at a fixed 0 dBFS (+3.10 dBTP on a crest signal, +2.10 with −1 dB after it) and its
  latency is its attack (48–1440 samples). `AUNBandEQ` is exactly the RBJ cookbook, but only
  1.5–1.6× cheaper than own biquads (under the 2× bar), its stacked high-passes make a
  Linkwitz-Riley slope, not Butterworth, and it smooths a parameter change itself over 3–27 ms. The
  own chain of eight stages costs 107.5 µs per 1024 stereo frames (0.50 % of real time); every own
  stage adds no latency but the limiter, 158 samples (3.3 ms at a 2 ms lookahead). Apple's units
  *can* run in the tap without allocating or locking (v2 `AudioUnitRender`; v3 only with its
  input bus enabled and block-typed calls); the record keeps that recipe. The tap's thread is
  AudioToolbox's real-time thread on the export's path too.

**What it changes in the phases.** AP1 measures the exported figure (mono counted twice). AP2's
master limiter in the export's float stage is required, not optional — two clips each under their
own limiter reached +1.49 dBTP through a crossfade — and the preview has none, which the guide and
the meter say. AP5 follows S2's recipe and moves isolation ahead of the live chain. AP7 rebuilds
the mix from the taps off the audio thread. AP10 labels each composition span with its timeline
track (and inner track), makes track dynamics exact in the export through per-track sub-mixes and
approximate in the preview, and asks the owner whether an exact preview (the `AVAudioEngine`
route) is wanted as a road map of its own.

From S1, for every live stage (AP2, AP3, AP4): scalar per-sample code or element-wise vDSP only —
`vDSP_biquad` and `vDSP_conv` give different bits for different buffer sizes; an FIR loops its taps
outermost (bit-identical to the scalar loop and 4.7× faster); a stage's `reset()` restores its fresh
state and `AudioTap` keeps resetting on StartOfStream, because the player's first callback is a
silent pre-roll that otherwise leaves a gate closed (−56 dBFS off the export). AP2's limiter takes
the maximum over a 64-tap Kaiser (β 10) detector's phases AND BS.1770 Annex 2's: a detector the
size of Annex 2's alone lets broadband onsets through up to +0.97 dB, while Annex 2 over-reads
speech by 0.14 dB, so a limiter exact by an accurate meter is reported at −0.86 dBTP by
`Loudness.swift` and `phase5_proof.py`. Like the noise reducer, it runs for the whole track once
any clip on it asks, so the track's delay never changes at a cut (670 samples with both).

### AP1's record (2026-10-30)

**Decisions:** AU-10…AU-17, recorded before the code. **Toll T1** (a pure move gated alone,
PASS 351 s): `thumbnails`' request arithmetic (`thumbnailSeconds`, `thumbnailRequests`,
`tileIndices`) and its "measured" paragraph into `MediaImporter+Thumbnails.swift`;
`MediaImporter.swift` 595 → 559, then 589 with the loudness pass.

**Landed.** The per-media loudness cache (`cache/loudness/`, S4's 10 ms format;
`MediaImporter+Loudness.swift`, `LoudnessBlocks.swift`) on the lane after peaks, its retry
riding the waveform's; the reader (`ClipLoudness.swift`: the export's dual mono, the clip's
own fold and pan on stereo, played-order steps through `sourceTick` and `ReverseMirror`, the
gates once) and the Volume section's Loudness and At volume rows behind a memo that holds
per handle, per file and through a live drag; Normalize's Loudness mode
(`AudioNormalize+Loudness.swift`: −16 LUFS by default, −1 dBTP and ×32 caps, `limited_by`),
its mode and target app-wide (`NormalizeChoice.swift`) and followed by the button and
Clip ▸ Normalize; `normalize_clip {mode, target_lufs}`. `AudioNormalize`'s admission and
segment index extracted for both modes. No core, FFI, op or format change.

**Measured** (Debug, then Release after the gate; the figures are the runs'):
`loudness_cache_probe.py` 11/11 rows — C3 forward windows within 0.076 LU and C4 reversed
within 0.087 LU of the meter (S4's figures), C5 stereo within 0.052, C6 44.1 kHz within
0.004; the owner's recording reads −41.672 LUFS, −18.526 dBTP, the meter's to three decimals.
`loudness_normalize_proof.py` 30/30: steady fixtures land at −16.00, −14.00 and −23.00
LUFS; the peaky fixture stops at −1.00 dBTP; two clips land at −16.00 and −16.00; **the
owner's recording measures −41.67 LUFS and lands at −24.15 LUFS, held by its true peak**
(−18.53 dBTP: ×7.52 puts it at −1 dBTP, 8.15 LU short of −16 — AP2's limiter is what closes
the gap); reversed and ×2 Keep pitch steady clips land at −16.00. `phase5_proof.py` 92/92;
`cache_pass_probe.py` 13/13. The same on Release after `make gate` (PASS 253 s, typecheck at
its four baseline warnings): `loudness_normalize_proof.py` 30/30, `phase5_proof.py` 92/92, the
log clean. **Mutants 8/8:** the probe's seven (`--mutants`) each failed its named row
(mono-not-doubled C2, reversed-forward-order C4, no-relative-gate C3, no-true-peak-cap C8,
limited-by-nil C8, tables-at-44k C6, version-unchecked C9), and `target_lufs`'s range check
dropped on a Debug build failed N2's −51 and −4 rows (restored after).

**Review fix.** N10's Peak leg read whatever mode the shared defaults domain held (AU-15
persists the choice), so it now runs on its own instance launched with
`-FrameJobNormalizeMode peak`, and both legs pin `-FrameJobNormalizeTargetLUFS -16`; the
pass moved `normalizePeakDB`'s doc back above it. Release after `make gate` (PASS 385 s):
`loudness_normalize_proof.py` 31/31, the log clean. The second review passed with three nits
left as written: N10's target pin holds because −16 is also the default (the argument
domain's string fails `NormalizeChoice`'s `NSNumber` read and falls back), the
`normalizeClips` doc's sentence on which pair runs, and another window's Normalize tooltip
keeping the old mode until its Volume section is rebuilt.

**Owed:** SE-23 (the read-out's look, the drag, the sound) for the owner.

### AP9's record (2026-10-30)

**Decided.** The owner answered "Asked at AP9" with (a), the linked pair, including the
deviation from the road map's "⌥-drag" (⌥ on an edge is Rate Stretch, so the half you grab
decides): AU-90…AU-97, recorded before the code. The adversary's three objections were taken:
a partner follows in time but keeps its own track (so a detached sound can reach a track of its
own and a J-cut between consecutive detached shots does not become a dissolve), one clamp over
the pair and a refusal for a shift that would take a leading sound below 0, and `delete` of a
sound half alone keeping its picture (Detach Audio then Delete stays the way to drop a sound).

**Landed.** The toll first, a pure move gated alone: `fit_scale` and `fill_scale` from
`edit_clip.rs` to `edit_fit.rs` (634 → 587; 61), `cargo test --release` green and `make lint`
clean. Then `Clip.linked` (format 28, provisional), `edit_link.rs` (the closure, the delete
closure, `settle_links` in `finish`, `check_links` in `validate`, split pairing, copy
re-pairing, carried edges, the rate refusal and `attach_audio`), `edit_time.rs`'s `shifted` and
the shift floor refusal, `alone` on `trim_start`, `trim_end` and `roll`, slip on both halves;
the app's `attach_audio` mirror, Clip ▸ Attach Audio (⇧⌥⌘D) and the Mix button, the sound-half
`alone` in the trim and roll sessions and W/E, Copy adding a picture's sound, the link glyph and
the echo ring. `edit_clip.rs` ends at 616 (over the cap, known debt, its next seam named in
`designs/adr/core-file-history.md`); `edit_time.rs` 595, `model.rs` 590, `edit_action.rs` 560,
`AgentCatalog+Clips.swift` 570.

**Measured.** `core/tests/link.rs` (27) and `link_edges.rs` (10) cover every op on a linked pair,
J and L variants, each refusal sentence, locks, a scoped move and identities; `schema_v28.rs` (5)
the format. Sixteen mutants, one per branch AU-91…AU-96 add, each killed by a named test (the
table in `tools/proof/README.md`). `make gate` PASS in 335 s (names 1, typecheck 6, fmt 3, lint
6, test 182, app 138; the four baseline warnings). `ap9_split_edits_proof.py` A0–A9 against
Release after the gate's `make app`: 10/10 (and 10/10 on Debug before it) — onset − first frame
−0.4999 s for the J-cut, offset − picture end +0.5000 s for the L-cut, through the move, the
ripple, the split + delete (head 0.0000 s once the lead is cut away) and the nest; the worst
click − flash 0.174 ms against the 1 ms tolerance; Attach's export equal to a never-detached
clip's, sample for sample. `op_catalog_proof.py` 23/23 and `op_argument_proof.py` 173/173 (its
pinned counts moved to 63 ops and 103 tools); `assistant_prompt_proof.py --probe` 14/14.

**Deviations.** `beginRoll` lives in `EditorViewController+Edge.swift`, not the frozen
`TimelineView.swift`, so the roll's `alone` is wired there. The assistant prompt's cut group was
reworded to "detach or attach audio" to stay under the search guide's 1,500 characters (1,498).
Because `split_clips` takes the closure, `freeze_frame`, `insert_clip` and `overwrite_clip` also
cut a linked partner at the same bound and pair it (AU-92); under an overwritten picture the
sound becomes three abutting pieces, the middle one unlinked. `ripple_delete_range` over a
J-cut's lead cuts the lead with the range rather than refusing (`link_edges.rs` pins it).

**Review.** The first review asked for one fix: the `insert_clip` and `overwrite_clip` rows
(`edit.rs`, `edit_insert.rs`, spec §6b, the two catalog descriptions, `editing.md`) still said
no other track is cut, which a linked partner now is. The fix pass corrected all of them;
`make gate` PASS 382 s, `spec_index_proof.py` 213/213; the Release proof was not re-run, the
pass changing prose only. The second review passed, three nits left as written: `editing.md`'s
exception names only the sound as the cut partner where the rule is symmetric; `shifted` and
`shift_clips` are O(n²) through linear `partner` lookups; and the roll's `alone` reads the grabbed
clip, not `right`, the clip the op names.

**Integrated.** AU-90…AU-97's index rows and the decisions file merged beside AP1's
AU-10…AU-17; the manual check renumbered SE-24, since AP1 took SE-23; format 28 was free and
stays; §5.2a's heading and its index cell now say format 28. No product code needed a hand
merge. `make gate` on the merged tree: PASS 470 s (names 1, typecheck 12, fmt 5, lint 12, test
234, app 204).

**Owed.** SE-24 in `docs/manual-checks.md` (the glyph, the echo, a J-cut heard in the preview).

### AP11's record (2026-10-30)

**The owner's answer.** Asked where a ducking clip's speech spans live, the owner chose (a),
saved in the project (`media[].speech`, written by `set_media_speech` in the same undo step that
turns Speech on), so the plan stays a pure function of the project. Recorded as AU-110, amending
§11's "Ducking is by clip extent"; AU-111…AU-116 hold the rest, all before the code.

**Landed.** The two tolls first, each a pure move gated alone — `ProjectSnapshot.swift` (1532 →
1423) gave `DuckProps`, `CompressorProps` and `AudioProps` to the new `AudioProps.swift` (gate
PASS 393 s), and `edit_transition.rs` (588 → 541) gave `set_transition_style` to the new
`edit_transition_style.rs` (gate PASS 187 s); then the decisions, the core, the app, the mirror,
the docs and the proof.

- **Core.** `model_audio.rs`: `DuckMode` (`extent`, `speech`), `Duck.mode`/`pre_roll`/`hold`
  (`DUCK_SPEECH_PAD` 300,000 ticks, 0.5 s), `FadeShape` and `AudioProps.fade_in_shape`/
  `fade_out_shape`; `model.rs`: `Media.speech`, `Transition.audio_shape` (its `Default`,
  `plus_3db`, in `audio_shape.rs`). Every new key is written only when not its default, so a
  project without them writes the text it did; format 29. `audio_duck_speech.rs` (new) maps the
  spans and answers the speech ducker's gain (the minimum over its spans of `audio_duck.rs`'s
  `extent_gain`), its breakpoints and the plan's `ducks`; `audio_shape.rs` (new) the four shapes
  and a shaped fade's samples; `media_speech.rs` (new) the op and its rules (`validate` too);
  `set_audio`'s one refusal reads the PATCH; a probed relink clips or clears `speech`. The patch
  template carries the new keys at non-default values, since a default is no longer written and
  the key check reads the template. 64 ops; 23 kinds with `FadeShape`.
- **App.** The Ducking section's Duck by (Clip Length / Speech), Pre-roll and Hold; the Fades
  section's In shape and Out shape; the Transition section's Crossfade Shape; all base-only.
  `DuckSpeech.swift` (new) turns the cached VAD into spans and the grouped ops, and `DuckCurves`
  reads the plan's `ducks` for `TimelineView+DuckCurve.swift`'s (new) yellow line. The Duck by
  popup is disabled, rather than its Speech item, while Speech cannot be chosen
  (`OptionPopupControl` has no per-item state).
- **Mirror.** `set_media_speech` (the 104th product tool); `set_audio` prepends
  `DuckSpeech.ops` when its patch sets `duck.mode: "speech"`; `set_transition_style` takes
  `audio_shape`.

**Measured** (the lane, `tools/proof/audio_ap11_proof.py` on Release after its gate, 11/11, and
11/11 on Debug before it): D1 the `say` voice's speech saved as 2 spans; D2 the bed inside both
held parts at −12.040 dB (want −12.041 ± 0.2); D3 both free parts at +0.000 dB; D4 an extent duck
holds −12.040 dB through the pause and +0.000 dB after its release; F1–F4 every fade shape within
0.117 dB of its formula (bound 0.5); X1 a linear crossfade within 0.100 dB of 1 − p; T1 a file cut
inside a word saves its last span ending at its duration (600,000 ticks). **The cost AU-110
accepted**, R1 on `samples/Rode-usb-mic.m4a`: 10 spans over 30.3 s, 188 bytes compact, 447 bytes
in the project file's pretty JSON. Ten mutants, each killed by a named core test: pre-roll sign,
hold dropped, min → product, reversed reflection skipped, the S-curve and −3 dB formulas, +3 dB's
outgoing side as `gain(1 − p)` (caught only by `fade_shapes.rs`'s bit-for-bit pin of R5-2's law),
the `set_audio` refusal removed, the refusal read from the merged props, and relink's `speech`
clip skipped (a first run let the reflection mutant live, so `duck_speech.rs` now samples the gain
every 1/100 s). Lane `make gate` PASS 326 s; `op_catalog_proof.py` 23/23, `op_argument_proof.py`
173/173; the parity log clean.

**Review.** One should-fix: the Ducking section's Level, Attack, Release, Pre-roll and Hold
re-sent the whole duck with its `mode`, so on a spanless Speech duck made by Paste Attributes the
core refused them while `set_audio` over MCP applied. Fixed: every duck edit of a Speech duck
carries `DuckSpeech.ops` first, the Duck by popup through the same path (a cache that cannot be
read now leaves the core's refusal rather than an edit that does nothing). `audio_ap11_probe.swift`
(`audio_ap11_proof.py --probe`): P1 and P2 2/2, and P1 fails over the pre-fix pane; fix pass
`make gate` PASS 476 s. The second review passed with one nit: the release/attack crossing's upper
bound in `audio_duck_speech.rs` does not also stop at a next span ending before `s2 + attack`, so
with Pre-roll and Hold near 0 the ramp across that corner is interpolated — filed as an issue.

**Integrated.** AP9 had taken format 28, so this phase is format 29 (`format.rs`, the header,
`schema_v29.rs`, AU-116, every doc line that named 28); AP9's `attach_audio` had taken the 63rd op
and 103rd tool, so `set_media_speech` is the 64th and 104th (`OP_COUNT`, `scope.rs`'s pin, both op
proofs, the count prose); AP1 and AP9 had taken SE-23 and SE-24, so this phase's checks are SE-25
and SE-26; the AU index row and decision rows merged beside AU-90…AU-97. On the merged tree:
`make gate` PASS 314 s (names 1, typecheck 5, fmt 3, lint 10, test 176, app 119); the merge
touched product code (the format number, `OP_COUNT`), so on Release after it
`audio_ap11_proof.py` 13/13 (P1–P2 and D1–R1, every figure as above), `op_catalog_proof.py`
23/23 and `op_argument_proof.py` 174/174, the parity log clean; `spec_index_proof.py` 213/213.

**Owed.** The person checks SE-25 (the speech duck by ear and its line's look) and SE-26 (the
shapes by ear) in `docs/manual-checks.md`; the crossing-bound nit as an issue.

### AP13's record (2026-10-30)

**Decided.** AU-130…AU-136, recorded before the code: grains of the player's mix read from a
composition built only for scrubbing, one `AVAssetReader` at a time on
`com.kgalligan.framejob.scrub-audio`, played through an `AVAudioEngine` only scrubbing uses;
80 ms with 5 ms sin² edges, forward from the frame-snapped playhead and forward when dragging
left; one grain ahead and only on a new frame, so a hold or the mouse-up goes silent; the scrub
build remade as its own never-dropped queue item when the player's composition object changes;
stateful stages fresh in each grain; no toggle, key or tool. The adversary's three objections
were taken before the code: a `move` on an inactive scheduler starts a scrub and `end()` forgets
the last start, the rebuild is its own queue item, and AU-134 rests on `AudioTapContext.prepare`
making a new chain per reader, scored on the scheduler's own adjacent grains (C3).

**Landed.** `ScrubGrains.swift` (174: `ScrubGrain`, `ScrubGrains`' window and `read`,
`ScrubGrainScheduler`), `ScrubAudio.swift` (262: `ScrubSource`, `ScrubGrainSink`,
`ScrubEngineSink`, `ScrubAudio`) and `EditorViewController+ScrubAudio.swift` (28). Wiring only in
the frozen files: `EditorViewController.swift`'s `scrubAudio` and its `invalidate()` in `deinit`,
`TimelineView.swift`'s `onScrubEnded` called in `endGesture`'s scrub arm;
`EditorViewController+Timeline.swift` (482) calls `scrubAudioMoved()` after `setPlayhead` and
installs `onScrubEnded`. `Playback.swift` and `AudioTap.swift` are untouched. No core, FFI,
format, op, tool or `UserDefaults` change.

**Measured.** `scrub_audio_probe.py` 15/15 on the final instrument: the window's edges
1.07e-5 and its largest step 0.0065449 (π/480 = 0.0065450); 14 back-to-back grains in a 1 s drag
at 60 Hz; the last grain ending 0.1067 s after a hold began; C1's grains at 1.0, 3.0 and 5.3 s
and C2's from 1.96 s equal to the export's float read (max |Δ| 0.0), C2's tail exactly 0; C3's
20 adjacent grains through a compressor and noise reduction each equal to a cold read on a fresh
build (max |Δ| 0.0), against an RMS of 0.0194 between those grains and the whole-timeline read,
so the stages do start fresh per reader; E1–E5 max |Δ| 0.0. Reported, not scored: a grain that
starts inside a gain ramp differs from the export's read at the same frames (max |Δ| 0.0988 for
a grain from 2.25 s inside a duck's attack), because AVFoundation evaluates a volume ramp from
where its reader starts; a diagnostic run (not kept) found the gain off by up to about a third at
the grain's first frame, converging toward its end, and a grain starting exactly on a ramp's last
tick off for its first 139 frames. The player seeking into a ramp is in the same position.
`--mutants` 8 of 9 killed, each by its named row; `read-by-arrival` survives as equivalent
(below), and the script now runs it unscored: 8/8 killed, exit 0. The spec's 9/9 bar is the
record's deviation. `make gate` PASS 473 s (names 1, typecheck 6, fmt 3, lint 15, test 299,
app 148; the four baseline warnings), then PASS 105 s after the docs' last edits (names and
test re-ran).
`make app-debug`, an instance launched by `proof_app.py`: its log printed no `Frame Job: ` line,
and a project opened and closed over MCP (the editor's `deinit` stopping the scrub sink) left it
running. There is no Release proof: the probe drives no app.

**Deviations.** The mutant `read-by-arrival` (frames placed in arrival order rather than by
presentation time) is EQUIVALENT: an `AVAssetReaderAudioMixOutput` with a `timeRange` stamps its
first buffer exactly at the range's start and fills a composition gap with silent buffers, so
arrival and presentation agree sample for sample, in C1 and in a grain across a gap's far edge
(2.96 s over a gap ending at 3.0 s), tried as a C2 extension to look for the one case that could
differ. That extension was then dropped from the probe: across the far edge the grain against the
export read max |Δ| 0.000195 in 2 of 5 runs of one binary and 0 in the other 3, a
nondeterminism in AVFoundation's mix at a segment that starts after empty time, under 1e-3 and
not scored. `read` keeps the presentation-time placement AU-131 asks for. G4 holds on the last
granted frame: a hand that stops on a frame the lead rule passed over gets that frame's one grain
first, which is AU-132's rule. C1's third start is 5.3 s, not 5 s: `DuckProps`' default 1 s
release puts a gain step at 5.0 s. `ScrubAudio.builds` is an `NSLock`-guarded computed property
rather than a stored one (written on the queue, read on main).

**Review.** One should-fix: `read-by-arrival` was still scored, so `--mutants` exited 1 on
every run, and AU-136 and its index row said nine mutants killed. Fixed: the probe's
`EQUIVALENT` set runs it and prints it unscored (8/8 killed, exit 0), and AU-136, its row, the
proof README and this record say eight plus one equivalent; fix pass `make gate` PASS 431 s,
`spec_index_proof.py` 213/213. Accepted as limits, not filed: `ScrubAudio` never reads a grain's
`at`, so the 0.12 s silence after a hold is proved on the scheduler's clock (G4), and a queue
lagging behind a scrub rebuild or a read longer than 80 ms plays its grains late (neither time is
measured in the app; PB-14 hears it); and an anchor or build failure of the unscored mutant does
not fail `--mutants`. The second review passed with those two nits and the docstring's "nine
mutants … scores each killed".

**Integrated.** AP11 had landed meanwhile, so its AU-110…AU-116, index rows, record, proof
README section and docs stand beside this phase's (AP13's block after AP11's, with the block's
own opening line), and the Lines cells were counted again (`audio.md` 366, `07.4` 65,
`11-decisions/` 15170; `spec_index_proof.py` 213/213). PB-14 was still free.
`EditorViewController+Timeline.swift` is 484 lines with AP11's line. No product code was touched
by the merge. On the merged tree: `make gate` PASS 280 s (names 1, typecheck 6, test 139,
app 134; fmt and lint unchanged), and `scrub_audio_probe.py` 15/15 with every figure as above.

**Owed.** PB-14 in `docs/manual-checks.md` (the feel of a drag, no clicks, silence on a hold).

### Closing the road map

The ADR in `designs/adr/audio.md`, this file and the survey archived with their rows in
`archive/INDEX.md`, the guide pages and README highlights, and every unfinished item filed as an
issue.

## Risks

- **CPU in the live tap.** Up to eight stages per clip on every composition track, real-time.
  S1 measured eight own stages at 0.50 % of real time per stereo track; a stage that cannot run
  live renders offline as isolation does.
- **Preview against export.** Master processing may exist only in the export (S3). If so, the
  guide and the meter say so rather than leave the two to differ silently.
- **Offline renders.** Isolation and voice effects add render time and cache space; both reuse
  the ramp-audio queue's owners, waits and pruning.
- **ML determinism.** If `AUSoundIsolation` is not byte-repeatable, its proofs measure levels
  and alignment, not bytes.
- **Format bumps.** AP3, AP4, AP8, AP9, AP10 and AP11 each add persisted fields; each bump has
  its `schema_vN.rs` test.
- **File caps.** `AudioDSP.swift` (890) and `Loudness.swift` (674) are over the 600-line cap
  and `AudioTap.swift` (595) is at it; `model_props.rs` (551) is close. AP0's tolls come
  first, and each later phase budgets its own.

## Not in this road map

Tier C (beat detection, retiming music, source separation, AI speech, third-party plug-in
hosting, round-trips to an audio editor, automatic tagging, a spectrum analyser, sample-level
repair, surround) and anything the owner's answers move out.
