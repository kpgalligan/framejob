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
- **Built in two parts, by size.** Part 1: the clip limiter, `audio.limiter` (format 30), its
  Limiter section and `set_audio` key, and Loudness Normalize through it as the default
  (AU-20…AU-26; its record below). Part 2: the export's float decode (#86), the master limiter
  in the float write pass and `audio_bits` (AU-27 on).

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

### AP2's record (2026-10-30)

Part 1 of AP2: the clip limiter, and Normalize to a loudness through it. Part 2 (the export's
float decode and #86, the master limiter, `audio_bits`) is the next spec.

**Decided.** AU-20…AU-26, recorded before the code. The one objection was taken:
`refusal_proof.py` §3 called `normalize_clip` with no `mode`, which AU-25 turns into Loudness,
so its four calls (and every Peak call in `phase5_proof.py` and `peaks_proof.py`) name
`mode="peak"`. The lane's toll (`DuckProps`, `CompressorProps`, `AudioProps` out of
`ProjectSnapshot.swift` into `AudioProps.swift`, gated alone, PASS 421 s) was the same pure
move AP11's toll had already landed, so it merged as nothing and the limiter joined AP11's file.

**Landed.** `audio.limiter` (`{ceiling_db, release}`, written only when set, after
`fade_out_shape`; **format 30**, `schema_v30.rs`), its range checks (`ticks_in_range`) and
clamp, the patch template's `limiter`; the stage (`AudioLimiterStage.swift`, last in
`AudioDSPChain`), its settings told the base volume (`AudioLimiterSettings`), the track-wide
`usesLimiter`, the 1,975-tick placement lead (`AudioShift.limiterLead`) and the tap's lookup at
`t + lookupLead`; `ClipLoudness.Reading`'s `steps` and `stepPeaks`, `AudioLimiterModel` and
Loudness Normalize's AU-24 plan (the row's `limiter`, `limited_by` only `max_gain`); Loudness
the default of the button, Clip ▸ Normalize and `normalize_clip` (AU-25); the Limiter section
after Mix and At volume through the model (AU-26, `AudioPane+Limiter.swift`); `set_audio`'s
`limiter` in the catalog; SE-22 sets Mode to Peak first, SE-23 expects Loudness, SE-28 is new.
The lane wrote format 28; AP9 and AP11 had taken 28 and 29, so the integration renumbered it to
30 in `format.rs`, the header, the schema test (the lane's `schema_v28.rs` as `schema_v30.rs`),
AU-21, §5.2a/b and the file map, and `limiter_proof.py` P6 now reads the header's number.

**Two departures from S1's code, neither from its arithmetic.** (1) Each FIR tap is an
element-wise `vDSP_vsmul` then `vDSP_vadd` and the box mean `vDSP_sve` over the fixed 96-element
box: the scalar loops missed AudioToolbox's real-time deadline in the Debug app's `-Onone`
build (P2's export silent, P3's 18 dB short, then `EXC_BAD_ACCESS` on the RT tap thread in
`ProcessingTapManager`); L3 still holds the bytes across block sizes. (2) The release envelope
is a Double: a Float one-pole stalls under half an ulp near 1 before the 2⁻²⁰ snap. The lane
also defined N11–N13 (no `mode` is Loudness and `peak_db` alone Peak; a clip's own limiter kept
at −3 and lowered from 0 to −1; one undo for volume and limiter), changed N2's no-mode case to
`{peak_db: -1, target_lufs: -16}`, and added P4's second leg because M26 survived the spec's
first (the fader's slew at the cut, #87, holds the crest clip's first 3.3 ms near ×1).

**Measured** (the lane, Debug then Release after its gate): `limiter_probe.py` 9/9 (every L2
output at its ceiling to four decimals by both meters; L6 exact from 1.346 s; L7 188,416 samples
equal; L8 the model −16.001 against the stage −15.911, gap 0.090) and `--mutants` 6/6;
`loudness_cache_probe.py` 11/11 and `--mutants` 7/7; `limiter_proof.py` 19/19 (P2 −0.9995 /
−0.9998 dBTP, 7.80 dBTP unlimited; P3 −2.9993 / −2.9998); `loudness_normalize_proof.py` 37/37 —
**the owner's recording, measured −41.67 LUFS, gets volume 23.368 and the limiter at −1, and
exports at −15.91 LUFS, −0.9998 (Kaiser) / −0.9999 (Annex 2) dBTP**; `export_offset_proof.py`
E4, E22, E44, E45 4/4; `phase5_proof.py` 92/92; on Debug `peaks_proof.py` 21/21 and
`refusal_proof.py` 145/145; `make gate` PASS 346 s. By hand on Debug, M25 failed E44
(+3.292 ms) and M26 P4's second leg (+3.5363 dBTP).

**Review.** Pass, with three nits, all fixed at integration: P6's literal 28 (now
`format_version()` off the header), P2's docstring "+15" (now about +8, as measured), and
`peak_db`'s description, which now says −1 is what the button uses in Peak mode.

**Integrated.** AP9, AP11 and AP13 had landed: their decision blocks, index rows, records and
proof README sections stand beside this phase's (AP2's before AP9's), the union taken in
`AudioProps.swift`, `TypedPatches.swift`, `InspectorBinding+Writes.swift`, `model_audio.rs`,
`patch.rs`, the guide (the limit "Loudness mode has no limiter yet" removed), the README
highlight and the menus row, and the Lines cells counted again. On the merged tree: `make gate`
PASS 342 s (names 1, typecheck 6, fmt 3, lint 11, test 189, app 132; the four baseline
warnings); `limiter_probe.py` 9/9 (L8 gap 0.090); on Release `limiter_proof.py` 19/19 (P6 "the
file is version 30, the header's 30"), `loudness_normalize_proof.py` 37/37 (N6 −15.91 LUFS,
−0.9998 / −0.9999 dBTP), `export_offset_proof.py` E4, E22, E44, E45 4/4, `phase5_proof.py`
92/92 and AP11's `audio_ap11_proof.py` 13/13 over the merged audio group; the parity log
clean. No mutant's anchor moved, so none was re-run.

**Owed.** SE-23 (Loudness the default, −16 LUFS through the limiter) and SE-28 (no pumping or
distortion on speech and music) for the owner; AP2 part 2. Nothing to file.

### AP5's record (2026-10-30)

**Decided.** AU-50…AU-57, recorded before the code: `audio.isolation` 0…1, written only when
not 0, base-only, carried by Paste Attributes, nothing on a nest clip; S2's render
(`AUSoundIsolation` High Quality Voice at 100 %, one manual-rendering engine per channel over
one `RampSourceReader`, 4 s of preroll, the 4440-frame latency pinned and discarded) into
`cache/isolated/`, named without the Amount, on the ramp render queue; Amount a crossfade
`dry + a·(wet − dry)` in the tap before the chain (AU-54 amends AU-3's order), dry while
pending; ×1 and ready reversed segments only; the Voice Isolation section before Noise
Reduction (0.8 when turned on; de-reverb is this control); the export waits. The adversary's
two objections were taken before the code: a failed render now calls its owners too
(`want(_:owner:settled:)`, `rampAudioDidSettle`), so the Status leaves "Rendering…"; and the
wet offset is rounded ONCE from source-in minus place (`IsolationCache.wetOffset`), so a 29.97
fps placement off the 48 kHz grid cannot round apart.

**Landed.** Core: the field (after `limiter`), `check_audio`'s range, `clamp_audio`, the patch
template's 0.5, format 31, `schema_v31.rs` and `isolation.rs`. Swift: `OfflineAudioJob` on
`RampAudioRequest.job`, `RampAudioRenders` serving both kinds with `.failed` calling owners,
`IsolationRenderer.swift` (263), `IsolationCache.swift` (261, with the review's `Memo`),
`AudioIsolation.swift` (181), `AudioPane+Isolation.swift` (67), the tap's pass and
`AudioTap.make(for:isolation:meter:)`, `CompositionBuilder.isolatedAudio`, `isolationFailed`,
`ReverseResolution.isolated`, one wiring line in `ProjectDocument.swift`, `AudioProps`,
`AudioPatch`, `structural(audio:)` base-only and `set_audio`'s prose. Docs: the guide's Voice
Isolation section and limits, the README highlight, SE-27, spec §4.3b, §5.2a/b, §5.6, §7.2,
§7.4, §7.8. Deviations: `AudioDSPParameters.isolates`; `IsolatedAudio` reads in 65,536-frame
chunks (one whole read of P5's 288,000-frame CAF returned 287,744); P3 also checks Amount 0.25
(a swapped crossfade equals at 0.5); P2's noise reduction sits on a second clip of the track;
the pending-silent mutant has three anchors; I7's Keep pitch on leg is held to its pause floor
(±1 dB), AVFoundation's time-pitch measured nondeterministic between two dry exports (max |Δ|
0.095 over 331,924 of 726,400 samples); every I row sets volume ×4 (the recording is −44.7 LUFS)
so 16-bit quantisation stays under I3's bound; split-rounding is scored on P2b alone (on I1b's
numbers both roundings give 286,686).

**Measured** (the lane, Release after its gate): `audio_ap5_proof.py` 22/22 — P2 worst 0.0
(bound 1e-7), 2.0861626e-07 with noise reduction (1e-4); P2b 602 and −2602, the built span
start 1602, offset −1601; P3 0.0 at 0.5 and 0.25; P5 288,000 frames, lag 0, 0.34 s wall; P6
−293.5 dB (S2 recorded −51 dB for mid-file windows with another preroll); I1 lag +0.001 samples,
I1b +0.002 (offset 286,686.4 samples); **I2 on the owner's recording: the pause floor 14.9 dB
lower (S2: 10.9), speech +0.14 dB broadband, octaves 63 Hz–8 kHz within −0.02…+0.29 dB**; I3
−63.7 dB; I4 2.8 s to finish, floor −12.0 dB; I5 a new render, the old pruned, lag +0.000; I6
reversed lag +0.007, floor −10.9 dB; I7 no render at ×2 either way; I10 equal to the dry export
(1,454,400 frames). `--probe` 10/10, `--mutants` 10/10 killed, `cargo test` 8/8, `make gate`
PASS 459 s. `ramp_proof.py` on Release 36/43, the seven host state (no `speech.mov` /
`silence.mov`; the spike probe's work folder absent); with those made, 8/9, U1 needing a pre-SR2b
baseline no tree holds; `--only E1,K1` on Debug 4/4.

**Review.** One should-fix: the Status read-out decoded the plan (two with a nest open) and
stat'd the media on every pane refresh, about 30 a second in playback. Fixed by
`IsolationCache.Memo` (document, clip, the two handles held weak, the published
`ReverseResolution`; held through a gesture), dropped on `.reversedMediaDidChange`; the fix pass's
`--probe` 10/10, `make gate` PASS 623 s, Release 22/22. The second review passed with two nits
left: no row proves the memo invalidates, and `IsolationRenderer` takes the `min` of the lanes'
`frameLength`s where it could fail on a mismatch.

**Integrated.** AP2 had landed and taken format 30, so this phase's is 31: `format.rs`, the
header, `schema_v31.rs` (the lane's `schema_v30.rs`, with a check that `isolation` is written
after `limiter`; AP2's `schema_v30.rs` kept), `isolation.rs`'s fixture, AU-50, §4.3b, §5.2a/b.
The union taken in `model_audio.rs`, `patch.rs`, `AudioProps.swift`, `TypedPatches.swift`,
`InspectorBinding+Writes.swift`, `set_audio`'s prose, the guide (sections 1–8, Limiter last;
the limits) and the README highlight; in `CompositionBuilder+AudioTracks.swift` the hoisted
`AudioShift` carries AP2's `usesLimiter`, so the isolation spans compose the limiter's lead
too (§7.2 says so). AP5's block of `11-decisions/audio.md` moved between AU-26 and AU-90, and
the Lines cells were counted again (`spec_index_proof.py` 213/213). SE-27 was free. On the
merged tree: `make gate` PASS 196 s (names 1, test 71, app 124), the run before it having
passed typecheck (6 s, the four baseline warnings), fmt and lint and FAILed test on a §7.2
Lines cell this integration's own rewrap moved; on Release `audio_ap5_proof.py` 22/22 with every figure as above, and AP2's
`limiter_proof.py` 19/19 over the merged builder (P6 "the file is version 31, the header's
31"), its log clean. No mutant's anchor moved, so none was re-run.

**Owed.** SE-27 for the owner (artefacts on the owner's voice at Amount 100 % and 50 %). Filed
as issues: voice isolation on a time-scaled, ramped or freeze clip (AU-55's limit), and
`ramp_proof.py`'s spike probe needing its work folder made first (U1 and P1 in a fresh tree)
and U1's pre-SR2b baseline.

### AP3's record (2026-10-30)

EQ, hum removal and channel selection (survey A3, A7, B7), built in lane A.

**Decided.** AU-30…AU-39, recorded before the code. The one objection was taken: AU-33's
plain Q = 10·k comb missed −depth once cascaded and cut the voice between harmonics, so the
hum's Q is 10·k / A (A = 10^(−depth/40)), which holds every notch's pole bandwidth at f0/10;
Q1's oracle uses it and gains a cascade row, and M10 (plain Q = 10·k) runs beside M5.

**Landed.** `audio.eq` (seven named slots and `bypass`), `audio.hum` and `audio.channels`,
each written only when set (`channels` only when not `both`), after `isolation`; **format
32**, `schema_v32.rs`; their bounds and clamps in a new `audio_eq.rs`, called from
`check_audio` and `clamp_audio`; the patch template's every new key at a non-default value.
The stage (`AudioEQStage.swift`: 17 fixed positions, RBJ in Double, transposed direct form
II, designed at the cut) and its arithmetic (`AudioBiquad.swift`: `AudioEQSettings`,
`AudioEQDesign.design`, `magnitudeDB`, `responseDB`); the pick and the stage at the head of
`AudioDSPChain`, read through `process(…head:)`; `AudioTrackDSP.headLead` (SY-25's 6,400 on a
noise-reduced track) and the tap's runs split at both lookups; `ChannelMatrix` composing the
pick first (AU-35); the mirror (`AudioEQProps.swift`) and `AudioPatch`'s three keys, all
base-only; the drawn response (`AudioEQCurveView.swift`) and the Channels, EQ and Hum sections
after Voice Isolation (`AudioPane+HumChannels.swift`, `AudioPane+EQ.swift`); `set_audio`'s prose with
the presets' values; the guide's three sections and limits, the README highlight, spec
§4.3b, §5.2a/b, §7.2, §7.4 and §7.10; the screen 09b and the `eq` fixture; manual check
SE-29. AP2's limiter check had been written SE-24, which AP9 had taken, so it is SE-28 here
and in AP2's record.

**Found on the way.** `clip_inspector2_probe.swift`'s T2 still listed six Sound sections
(AP2 had added the Limiter), so it now names ten. `screens.py`'s P2 failed on the tree as
inherited: the four audio sections were unpinned, and so were AP1's Normalize keys and three
dev launch keys (`RCCodecProbe`, `RCDevExportFault`, `RCDevGraphicImportAccept`); the
Normalize keys are pinned at Loudness and −16, the three dev keys listed as not shown, and
`audio.eq` pinned open for 09b, which opens it on 09 too (its prose says so).

**Measured** (the lane, Debug then Release after its gate): `eq_probe.py` 11/11 — Q1 worst
0.000000 dB over 30 slot and hum cases at 48 and 44.1 kHz, the cascades −0.006…−0.034 dB from
−depth at the harmonics and −0.096…−0.105 dB midway; Q7 0.0000 dB; Q10 **135.9 µs per 1024
stereo frames at all 17 positions, 0.64 % of real time** (S1's estimate was 17 × 7.2 = 122 µs;
three lanes shared the machine, best of 3 × 2000 runs) — and `--mutants` 10/10; M11 by hand
failed five of `audio_eq.rs`'s six tests. `eq_proof.py` 33/33 on Debug, so the scalar stage
keeps AudioToolbox's deadline at `-Onone` (E2's export), and 33/33 on Release: E2 within
0.0154 dB (a) and 0.0020 dB (b) of analytic; E3 −0.005…−0.029 dB at 30 dB and +0.003…−0.054 dB
at 48 dB from −depth (its first run, with 1 s steps, read +0.07…+0.11 at 48 dB: the notch's
ringing had not decayed, so the hum fixtures' steps are 2 s); E5 the voice-on-left file
measured −43.09 (both) and −40.08 LUFS (left, +3.010 LU), normalised exports at −15.87 and
−15.96 LUFS; E6 the onset at sample 48,001 (+0.02 ms). **E8, the owner's recording through
Rumble Cut, De-mud and Presence:** the pause floor −64.30 → −66.65 dBFS (−2.34 dB); octave
bands 63 Hz −2.68, 125 Hz −1.11, 250 Hz −2.34, 500 Hz −1.50, 1 kHz −0.14, 2 kHz +0.86, 4 kHz
+2.51, 8 kHz +1.30 dB. On Release: `limiter_proof.py` 19/19, `loudness_normalize_proof.py`
37/37 (N6 −15.91 LUFS, −0.9998 / −0.9999 dBTP), `phase5_proof.py` 92/92,
`export_offset_proof.py --only E4,E22,E27,E44,E45` 5/5; `limiter_probe.py` 9/9,
`loudness_cache_probe.py` 11/11, `clip_inspector2_proof.py` 33/33, `screens.py --only
09b-clip-sound-eq,09-clip-sound` 7/7, `spec_index_proof.py` 213/213; `make gate` PASS 448 s
(names 1, typecheck 6, fmt 3, lint 12, test 284, app 142; the four baseline warnings); the
parity log empty on both builds.

**Review.** Passed with two nits, left as they are: `AudioBiquad.swift`'s `pass`/`shelf`
replace a NaN frequency with 1000 Hz where its comment says `clamp_eq` agrees (the core uses
each slot's own default; no JSON can carry a NaN), and an `eq: {}` with no slot on reads "0 on"
where "off" would read better.

**Integrated.** AP5 had landed and taken format 31 and SE-27, so this phase's format is 32
(`format.rs`, the header, `schema_v32.rs` — the lane's `schema_v31.rs`, its fixture carrying
`isolation` and the three keys read after it — AU-37, §5.2a/b, §7.10, the guide) and its check
SE-29, the limiter's SE-28. The union taken in `model_audio.rs` (the three after `isolation`),
`patch.rs`, `AudioProps.swift`, `TypedPatches.swift`, `InspectorBinding+Writes.swift`,
`set_audio`'s prose (channels "first in the clip's chain after isolation"), `ClipPane`'s Sound
list (Voice Isolation, then Channels, EQ, Hum: AU-54's order), the guide (sections 1–11, the
limits), the README highlight, §7.4 and the decisions index; AU-34 and AU-38 name AU-54's
crossfade and the Voice Isolation section ahead of the head, and AP3's block of
`11-decisions/audio.md` sits before AP5's. AP5's new `AudioTapContext(track:isolation:meter:)`
broke `eq_probe.swift` and AP2's `limiter_probe.swift`, which now pass `isolation: nil`;
`audio.isolation` is pinned in `screens.py` (P2) and listed in `clip_inspector2_probe.swift`'s
T2, and 09's prose names Voice Isolation, the EQ now below its captured height. On the merged
tree: `make gate` PASS 323 s (names 1, typecheck 5 with the four baseline warnings, fmt 3, lint
10, test 179, app 124); on Release `eq_proof.py` 33/33 with every figure as above (E7 "the file
is version 32, the header's 32"), AP5's `audio_ap5_proof.py` 22/22 over the merged tap (I2 the
pause floor 14.9 dB lower, I3 −63.7 dB), the parity log clean; `eq_probe.py` 11/11 (Q10 134.5
µs, 0.63 % of real time), `limiter_probe.py` 9/9, `clip_inspector2_proof.py` 33/33, `screens.py
--only 09b-clip-sound-eq,09-clip-sound` 7/7, `spec_index_proof.py` 213/213; `cargo test`
`schema_v32` 5/5, `schema_v31` 4/4, `audio_eq` 6/6, `isolation` 4/4, `schema_v30` 6/6. No
mutant's anchor moved, so none was re-run.

**Owed.** SE-29 for the owner (the presets' ±3 dB, the notch, a one-sided pick, by ear).
Nothing to file.

### AP7's record (2026-10-30)

**Decided.** AU-70…AU-78, recorded before the code: the true mix rebuilt on the main thread
from each tap's post-chain block (a lock-free single-producer `MixRing` per sink) by frame ×
the plan's envelope, a mono track in both channels, waiting for every track except one not
sounding at the frame (a gap as well as past its last span) or 0.5 s behind; momentary,
short-term, integrated and the true-peak maximum from `LoudnessMeter`, made rate-generic by
`KWeighting` (moved into `Loudness.swift`); measured only at ×1, with `manual`, `jump` and
`overrun` resets and a stop that holds the figures; pre-master (the preview has no master
stage; each clip's own chain, AP2's clip limiter included, is in what the taps copy); the
timeline bar's bars from the mix while measuring; View ▸ Loudness Meter (⌃⌘L), a 132 pt column
left of Scopes, per window; the dev tool `loudness_meter` only. The adversary's three
objections were taken before the code (gaps on one track, the timer in `.common` modes, what a
stop does).

**Landed.** `LevelMeter.swift` (564: `MixChunk`, `MixRing`, `LevelMeterSink.ring`/`capture`),
`AudioTap.swift` (the capture after the chain, a non-numeric time skipped), `Loudness.swift`
(582: `KWeighting` moved in verbatim from `LoudnessBlocks.swift`, `rateRange` 8–192 kHz,
`momentaryLUFS`, `shortTermLUFS` from a 30-entry ring, `gatedLoudness`), `LiveLoudness.swift`
(263) and `LiveLoudness+Sum.swift` (230), `LoudnessPanelView.swift` (227),
`EditorViewController+Loudness.swift` (62), `AgentServer+LoudnessMeter.swift` (71);
`Playback.swift` 593 → 592 (`let loudness`), `Playback+Meter.swift` (the tick consumes, the bars
prefer the mix, the timer added to `RunLoop.main` for `.common`, `stopMetering` stops the
meter); wiring in `EditorViewController+Seeing.swift`, the frozen `EditorViewController.swift`
(one validator line), `AppDelegate+Menus.swift`, `AgentServer+DevTools.swift` and
`UIMenuTable.swift` (the `toggleLoudnessMeter:` row `perform_menu_item` needs). No core, FFI,
format, op or `UserDefaults` change.

**Measured** (the figures are the runs'). `audio_ap7_proof.py --probe` 16/16: Tech 3341 case 1
M, S, I −22.9933; case 2 −32.9933; cases 3, 4, 5 I −23.0139, −23.0139, −22.9787; case 9 S worst
|Δ| 0.0137 LU over 121 reads; case 12 M worst 0.0396 LU over 97 reads; true peak fs/4 0°
−6.0206, fs/4 45° −5.9759, fs/6 60° −6.3160, fs/8 67.5° −6.0279, fs/4 45° at 0 dBFS +3.0550
dBTP; 44.1 kHz case 1 −22.9905 (0.0028 LU from 48 kHz) and fs/4 45° −5.9759; T10's mix
against Σ env·x |ΔI|, |ΔM|, |ΔS| 0.0000 over exactly [0, 480000); T11–T16 exact frame counts
and |ΔI| 0.0000. `--mutants` 11/11 killed, each by its named row. `loudness_cache_probe.py`
11/11 and its 7 mutants killed (the `tables-at-44k` anchor now in `Loudness.swift`). Over MCP
against Release (after `make gate`): L1 the meter over [0, 380928) at 48 kHz read I −13.6294,
M −13.4048, S −13.3853, TP −9.0215 against the export's −13.6297, −13.4048, −13.3853, −9.0215
(|ΔI| 0.0004, the rest 0.0000), the 0.4 s gap reset nothing, `measuring` false after the play;
L2 one `jump` for a seek; L3 no reset across two plays; L4 the log clean — 4/4, twice (before
and after the menu-table row). `phase5_proof.py` 92/92, `op_argument_proof.py` 175/175,
`phase5_chrome.py` 82/82, `seeing_proof.py` 19/19 (Release, on the gate's first build);
`screens.py --only 04c-editor-loudness,04b-preview-scopes,04-editor` captured all three light
and dark, 8/8 after the review's fix pass (the first run was 7/8: P2, the defaults pin check,
failed on keys other phases added; `FrameJobNormalizeMode` and `FrameJobNormalizeTargetLUFS`,
which the column's target line reads, are now pinned in `screens.py` and the harness's
`pinDefaults` at their defaults, and `RCCodecProbe`, `RCDevExportFault` and
`RCDevGraphicImportAccept` are in `NOT_SHOWN` with reasons). The harness drew `seeing=loudness` and
`loudness,loudnessfixed` light and dark (the column at 1003, 44, 132 × 517 pt in a 1440 × 862
window). `make gate` PASS 602 s (names 1, typecheck 13, fmt 6, lint 18, test 327, app 235;
three lanes' builds sharing the machine), then PASS 342 s after the `UIMenuTable` row (names 1,
typecheck 9, test 144, app 186; fmt and lint unchanged).

**Deviations.** (1) The player does not deliver a seek as the spike's 1,920-frame lockstep:
it hands each track 4,096-frame buffers and, after a seek or a play from elsewhere, first one
or two buffers of the OLD position (sometimes the same buffer twice), not in step across
tracks. The first L2/L3 runs reset five times for one seek and once for a plain play. AU-72 now
asks the reset rule only of a chunk that MOVES its track (continues neither the track's stream
nor what it delivered to the measurement), and a track that has not moved after a jump drops its
old stream until it does, for at most 0.5 s; T11 gained that case. (2) The stall guard compares
the first frame a track OWES (sounds at and has not delivered), not its last delivered frame, so
a track in a gap is not "stalled" by a leader past the gap. (3) `LiveLoudnessReading` carries
`offSpeed` so the footer can say "Measured only at normal speed."; the spec's interface had no
field for it. (4) `LiveLoudness` is two files (`+Sum`) under the 400-line rule. (5) T8 scores
Tech 3341's paired cases 15–19 rather than the 3 × 4 grid, which is printed (fs/4 at 60° reads
+0.204 dB, the Annex 2 filter's ripple), and each tone fades in over 20 ms: switched on from
silence, a sine rang the interpolator up to 0.7 dB past its own peak. (6) `screens.py`'s
`VIEW_SELECTORS` gained `toggleLoudnessMeter:`, which `04c` needs.

**Review.** The first review asked for one fix: `screens.py`'s P2 failed on defaults keys other
phases had added, so the fix pass pinned Normalize's two keys and listed `RCCodecProbe`,
`RCDevExportFault` and `RCDevGraphicImportAccept` in `NOT_SHOWN` (8/8; `make gate` PASS 215 s).
The second passed with three nits, each taken at integration: `stop()`'s doc and AU-72 said
audio rendered ahead of the playhead is never measured, but frames already summed past it stay
(L1's meter reached 7.936 s against a pause at 7.556 s), so both now say only what is still in
the rings is dropped; AU-73 said AP2 had not landed, and now names the clip limiter as part of
the chain the taps copy, with no master stage in the preview; and the target line repainted
only on a new reading, so a Normalize target changed while paused showed late — the panel now
redraws its scale on `UserDefaults.didChangeNotification`.

**Integrated.** AP2 (part 1), AP3 and AP5 had landed since the lane's base `720f0ea`. AU-70…AU-78
were free; SE-27 was AP5's, so this phase's check is SE-30. Conflicts were taken as unions: the
README highlight, §7.4 (the tap row keeps AP3's and AP5's chain and gains the `MixRing`; AP1's
loudness row drops `KWeighting`, now `Loudness.swift`'s), the decisions index (AP7's rows and
summary after AP5's, the Lines cells counted again), `11-decisions/audio.md` (AP7's block after
AP5's), the spec index's Lines cells, the guide's limits (AP2's two limiter lines kept, AP1's
"no limiter yet" line gone), `manual-checks.md`, `tools/proof/README.md` (AP7's section after
AP5's) and `loudness_cache_probe.py` (AP2's `limited-by-nil` anchor, AP7's file for
`tables-at-44k`). AP2 had already pinned `FrameJobNormalizeMode` in `screens.py` at
`"loudness"`, AU-25's default, which was kept, and the harness's `pinDefaults` now pins
`"loudness"` too. `AudioTap.swift` merged cleanly: the capture follows AP5's crossfade, AP3's
head stages and AP2's limiter, whose 1,975-tick lead leaves the tap's output at its own time.
On the merged tree: `make typecheck` 0 errors and the four baseline warnings; `--probe` 16/16
with the lane's figures (T10 |ΔI|, |ΔM|, |ΔS| 0.0000; T16 |ΔI| 0.0000); `loudness_cache_probe.py`
11/11 and its 7 mutants killed; `make gate` PASS 282 s (names 1, typecheck 6, test 144, app 131;
fmt and lint unchanged). Against Release, L1 read the meter over [0, 374400) at I −13.6325,
M −13.3803, S −13.3820, TP −9.0215 against the export's −13.6328, −13.3803, −13.3820, −9.0215
(|ΔI| 0.0004), the gap resetting nothing, and L4 was clean (the parity log empty). L2 and L3
failed: a seek counted two jumps (resets 2 → 4) and a play from the reached frame reset once
more (5, 6, 6; a second run 5, 6, 7). They failed the same way on the lane's own Release app,
launched from its worktree, with this host's default output AirPods Max over Bluetooth (the
lane's 4/4 runs did not record their output): a host state AU-72's admission was not measured
on, not the merge, and filed. No AP7 mutant's anchor moved, so none was re-run.

**Owed.** SE-30 (the column's look and motion, the resets a person sees) for the owner. Filed:
the live meter's extra `jump` resets on a Bluetooth output (L2, L3 above).

### AP4's record (2026-10-30)

The gate/expander and the de-esser (survey A5, A6), built in lane A.

**Decided.** AU-40…AU-49, recorded before the code. The one objection was taken: the draft's
de-esser output `x − (1 − g)·band` boosted the sibilant band (a 4th-order high-pass is 180°
out at its cut: +2.6 dB at 6 kHz for a 6 dB range), so the reduction goes through an LR4
crossover, `low + g·band`, whose magnitude stays in [g, 1]; the 24 dB/oct Butterworth stays as
the detection sidechain only. D6 gained the 2–12 kHz no-boost sweep and the allpass check, P5
moved its cut to 4 kHz and gained a no-band-louder check, and mutant M11 (the subtraction) was
added — eleven mutants, not ten.

**Landed.** `audio.gate` (`{threshold_db, ratio, range_db, attack, hold, release}`) and
`audio.de_esser` (`{frequency, threshold_db, range_db}`), each written only when set, after
`channels`; **format 33**, `schema_v33.rs`; their bounds and clamps in a new
`audio_dynamics.rs` (`ticks_in_range` now `pub(crate)`), called from `check_audio` and
`clamp_audio`; the patch template's two keys at their defaults. The compressor's linked peak
detector, follower and one-pole coefficients moved into `AudioEnvelopeFollower.swift`
(`AudioEnvelope`, `AudioPeakFollower`) with their exact Float arithmetic, the compressor on
them (D1: HEAD's bytes); the gate (`AudioGateStage.swift`) and the de-esser
(`AudioDeEsserStage.swift`, `butterworthQ` no longer private) after the reducers and before
the compressor in `AudioDSPChain`, built for every active track, read at the compressor's
lookup; `AudioClipDSP.gate`/`.deEsser` in `isInert`. The thresholds' reference level
(`AudioDynamicsLevels.swift`): each gated or de-essed clip's `ClipLoudness` reading, memoised
per cache folder, plan text and channel matrix (eight plans at most), pending never kept and
files read through a fresh loader; a `loudness` post drops the media's memo and file and posts
`.reversedMediaDidChange` for each open document gated on it; `AudioDSPParameters(snapshot:
levels:)`, `pendingLevels` and `.measured(project:cache:)`, used by `Playback` (one line) and
`AudioDSPSource`'s fallback (so the export and `render_frame`); `ReverseResolution.cache`,
published by one line in `ProjectDocument`; the export's wait (`Exporter.waitForLevels`, 0.1 s
polls, 300 s, then `loudnessUnmeasured` naming the clip). The mirror (`AudioDynamicsProps.swift`)
and `AudioPatch`'s two keys, base-only; the Gate and De-esser sections after Noise Reduction
(`AudioPane+Dynamics.swift`); `set_audio`'s prose; the guide's two sections, its export page
and limits, the README highlight, spec §4.3b, §5.2a/b, §6b, §7.2, §7.4, §7.6, §7.8 and
§7.10; the screen 09c and the `dynamics` fixture; manual check SE-31.

**Deviations, each recorded in AU-48 or here.** The Status read-out is two rows, Status
("Opens above −31.8 dBFS", "Waits for its loudness", "Not gating: too short | too quiet | no
sound") and Loudness ("−21.8 LUFS", "measuring…"): the planned one-line "Opens above −51.7
dBFS · loudness −41.7 LUFS" was cut off in 09c's first capture (a read-out holds about 27
characters). The thresholds' fields show whole dB and the Frequency and Release fields are
the wide ones, because "−10.0 dB" and "6000 Hz" were truncated in 09's capture. Both
followers fall at the 10 ms floor (`AudioEnvelope.fall(seconds: 0)`), the reading of "falling
at the 10 ms floor". `measured(project:cache:)` decodes the plan only when a clip wants a
level, in `AudioDynamicsLevels.levels`. T2 lists thirteen Sound sections, not twelve: AP5's
Voice Isolation was already in the list.

**Found on the way.** `screens.py`'s P2 scan of declared section ids did not read an
underscore, so `audio.de_esser` read as pinned-but-undeclared and `media.camera_log` had gone
unpinned unseen; the scan reads `_` now and `media.camera_log` is pinned at its default
(open).

**Measured** (the lane; three lanes shared the machine): `audio_ap4_probe.py` 11/11 — D2
1.000, 5.000, 15.000 and 19.995 dB against 1, 5, 15 and 20 (±0.05), D3 +0.025 ms and +0.006 ms, D6 2.492, 3.518, 4.953 and 5.600 dB at 6, 7, 9 and
11 kHz equal to the analytic figures to three decimals and the sweep's loudest −0.000 dB, D7
−35.995 dBFS, D10 188,160 samples equal, D11 **71.0 µs per 1024 stereo frames, 0.33 % of real
time** (best of 3 × 2000 runs, one run of the row); `--mutants` 10/10 (M2 killed by D10 alone);
M10 by hand failed two of `audio_dynamics.rs`'s five tests. `audio_ap4_proof.py` 30/30 on
Debug and on Release: P3 the gaps' floor 19.854 dB lower, the bursts' middles unchanged to
0.001 dB; P4 −0.32 ms at hold 50 and 200 ms, the fitted release 101.6 ms; P5 the 6–9 kHz
energy 5.42 dB lower, the tones −0.011 dB, between bursts −0.000 dB, the loudest third-octave
+0.176 dB; **P6, the owner's recording under the default gate: L −41.64 LUFS, the pause floor
−64.30 → −76.70 dBFS (−12.39 dB), speech p90 −43.16 dBFS unchanged.** On Release,
`phase5_proof.py` 92/92, `eq_proof.py` 33/33, `limiter_proof.py` 19/19; `eq_probe.py` 11/11,
`limiter_probe.py` 9/9, `clip_inspector2_proof.py` 33/33, `screens.py --only
09-clip-sound,09c-clip-sound-dynamics` 7/7, `spec_index_proof.py` 213/213; `make gate` PASS
428 s (names 1, typecheck 6 with the four baseline warnings, fmt 3, lint 7, test 259, app 152);
the parity log empty on both builds.

**Review.** It passed with two nits. D5 primes the used gate on the voice, which ends open,
so M2 (a reset that keeps the reduction) is killed by D10 alone: not taken, since D10 kills it
and the set stays complete. Three lines ran past the ~100-column wrap: the doc comment in
`AudioPane+Dynamics.swift` and the `guard` in `AudioDynamicsLevels.swift` were re-wrapped at
integration; `Playback.swift`'s one changed line (130 columns) was kept, because wrapping it
costs the file a line the spec held it to.

**Integrated.** AP7 had landed since the lane's base `3f7ed17`; it took no format number, so
33 stands, and it took SE-30, so this phase's check is SE-31. Conflicts were taken as unions:
§7.4's tap row (AP7's `MixRing` beside the gate and the de-esser), the decisions index's
`audio.md` row (AP4's segment between AP3's and AP5's, Lines 762), `manual-checks.md` and this
record (AP7's first). The spec index's Lines cells were counted again (§7.4 70, `11-decisions/`
15610 in 34 files; `spec_index_proof.py` 213/213). `AudioTap.swift`, `Playback.swift`,
`screens.py`, the guide, the README and `tools/proof/README.md` merged cleanly. No conflict
touched product code. On the merged tree: `make gate` PASS 383 s (names 1, typecheck 6 with
the four baseline warnings, fmt 3, lint 12, test 223, app 135); because AP7's tap is what D10
and the exports run through, `audio_ap4_probe.py` ran again, 11/11 with the lane's figures (D10
188,160 samples, 0 differ; D11 70.2 µs, 0.33 %), and `audio_ap4_proof.py` against Release,
30/30 with the lane's figures (P3 19.854 dB, P4 −0.32 ms, P5 5.42 dB, P6 −64.30 → −76.70
dBFS), the parity log empty. No mutant's anchor moved, so none was re-run.

**Owed.** SE-31 for the owner (the defaults by ear: chatter, pumping, lisping). Nothing to
file.

### AP14's record (2026-10-30)

Voice effects (survey B10, E8 of `designs/adr/effects-survey.md`, #123), built in lane C.

**Decided.** AU-140…AU-149, recorded before the code: `audio.voice` `{kind, amount, pitch}`
(sixteen kinds in E8's order, no default kind, amount 0…1 default 1, pitch −12…12 optional and
read only by pitch, high and deep, absent the kind's own 0, +5, −5), format 34, written only when
set, merged key by key, base-only; each kind a fixed chain TimePitch → EQ → Distortion → Delay →
Reverb scaled by the amount, with a per-kind makeup; E8's render contract with the chain's latency
discarded; isolation → voice (the voice rendered from the isolation crossfade, waiting for its
file); `cache/voiced/` on the ramp render queue; AU-55's segments; the Voice Effect section; the
export's second wait and `voiceFailed`; the limits; the proof. The adversary's two objections were
taken before the code: the latency discard (V10 and the latency-kept mutant) and a kind change
sending `pitch: null` (V11).

**Landed.** Core: `VoiceKind`, `Voice`, `VOICE_DEFAULT_AMOUNT` and `AudioProps.voice` after
`de_esser`, `check_audio`'s two ranges, `clamp_audio`, the patch template's voice, format 34,
`schema_v34.rs` and `voice.rs`. Swift: `VoiceProps.swift` (103), `VoiceChain.swift` (297),
`VoiceRenderer.swift` (262), `VoiceCache.swift` (183), `AudioPane+Voice.swift` (81); the voices
in `AudioDSPParameters`, the voiced span in `AudioIsolationTrack` (one `placement` call and the
crossfade line kept), `CompositionBuilder.voicedAudio` and its wiring, `OfflineAudioJob.voice`,
`RampAudioRenders`' arm, `IsolationCache.Memo(compute:)`, `ReverseResolution.voiced`,
`ProjectDocument+RampAudio`'s third folder and its settle wanting again, the export's second wait,
`voiceFailed`, `AudioProps`, `AudioPatch`, `structural(audio:)` and `set_audio`'s prose. Docs: the
guide's Voice Effect section and limits, the README highlight, SE-32, spec §4.3b, §5.2a/b, §5.6,
§6, §7.2, §7.4, §7.8, §7.10.

**Deviations.** The makeup is measured as I3's export reads it (the fader at ×4, both channels):
read at the recording's own −44.7 LUFS, the −70 LUFS gate made robot, telephone and distorted read
7.90, 2.18 and 5.96 dB, and distorted then exported 3.0 LU low; at ×4 they are 8.70, 2.64 and
8.89. K7 reads bright at its bell's 3 kHz octave (+3.3 dB): at 4 kHz the chain lifts +2.7 dB, under
the sketch's +3, and the row reports it; the chain is AU-141's, so a larger bell would be the
owner's change. The burst is −6 dBFS RMS, and V9 uses it where the sketch said a click. A failed
voice render whose source cannot be read says so in the voice's words ("The voice effect's source
cannot be read"), where `RampAudioCache.renderSource`'s sentence named retimed audio.
`clip_inspector2_probe.swift`'s T2 and `screens.py`'s `SECTIONS` list the new `audio.voice`
section.

**Measured** (the lane; Release after its gate): `voice_proof.py` 38/38 — V2 worst 0.0 alone and
2.09e-7 behind the reducer's lead; V5 and V7 equal to the reference sample for sample, every chain's
latency 0 frames; V9 room 0.45 s, cathedral 4.07 s; V10 both envelope peaks at 0 ms; K1–K3 and I2
within 0.00 cents; K4 the 940 and 1060 Hz sidebands +87.8 and +87.7 dB over the 1 kHz bin; K5
+9.8, K6 +9.8 dB; K8 −25.5 / −28.3, K9 −25.4 / −19.3 dB; K10 +60.6 dB; K11 −9.6 dB; K12 +0.02 and
+0.04 ms; K13–K16 0.430, 0.340, 1.600 and 3.650 s (E0: 239 ms, 246 ms, 2.20 s, 5.79 s, a different
measure); I3 dry −29.60 LUFS and every kind within 0.10 LU; I5 2.3 s to finish; I9 the floor 13.2
dB lower. `--measure` with the final table: every kind within 0.01 LU of −29.63 LUFS. `--mutants`
"10/10 mutants killed, 1 equivalent", exit 0: `latency-kept` survives and is scored equivalent,
every chain's latency measuring 0 frames (V10 prints pitch +7's). `cargo test` `voice` 7/7,
`schema_v33` 4/4 (now `schema_v34`), `schema_v32` 5/5, `schema_v31` 4/4, `isolation` 4/4.
`make gate` PASS 414 s (names 1, typecheck 6 with the four baseline warnings, fmt 3, lint 16, test
227, app 160). On Release `audio_ap5_proof.py --instance` 12/12 (I2 the floor 14.9 dB lower, I3
−63.7 dB), `--mutants` 10/10 over the re-anchored builder; `clip_inspector2_proof.py` 33/33;
`screens.py --only 09-clip-sound,09b-clip-sound-eq` 7/7. The parity log empty on both builds. One
Debug run of the instance rows read room's I3 export 12.10 LU low, exactly the ×4 fader missing
over the whole file; I3 alone again on Debug and the Release run read it at +0.00, and it did not
recur.

**Review.** Review 1's should-fix: `voice_proof.py --mutants` exited 1 on the equivalent
`latency-kept`. Fixed in the lane (`equivalence()` reads V10's pitch +7 latency from the mutant's
own output and leaves a surviving `latency-kept` at 48 frames or fewer out of the score; a build
failure or a missing anchor still scores a failure); `--mutants` then exit 0 and `make gate` PASS
296 s. Review 2 passed with two nits carried from review 1, both taken at integration: the doc
comment of `ensureRampAudio` now names voiced windows and a voice effect, and `model_audio.rs`'s
`//!` paragraph is wrapped again.

**Integrated.** AP7 and AP4 had landed since the lane's base `3f7ed17`. AP4 took format 33 and
`schema_v33.rs`, so this phase's format is 34: `format.rs` (598 lines), the header,
`schema_v34.rs` (versions 1–33 open stamped current, a file at 33 with no voice writes what it did,
the voice round-trips after `de_esser`), `voice.rs`'s fixture, AU-140, §5.2a/b's titles, §4.3b, §6
and the decisions index. AP7 and AP4 took SE-30 and SE-31, so this phase's check is SE-32.
Conflicts were taken as unions: the core's field, check, clamp and template (the voice after the
gate and the de-esser); `AudioProps`, `AudioPatch` and `structural(audio:)`; `AudioDSPParameters`
(the voices beside AP4's `pendingLevels` and `measured`); `ReverseResolution` (AP4's stored
`cache` beside the computed `voiced`); both `ExportError` cases; `Exporter+RampAudio` (AP4's
`waitForLevels` first, then the two render waits, P8's anchor line still once); `set_audio`'s
prose (both clauses; gate, de_esser and voice in the MERGE sentence); the Sound tab's order (Voice
Effect after Voice Isolation, Gate and De-esser after Noise Reduction) in T2, now fourteen
sections, and `screens.py`; the guide, the README highlight, §5.2b, §7.2, §7.4, §7.8 (the voice
wait after the isolation wait, then the loudness wait), the decisions index's `audio.md` row, the
proof README and this record (after AP4's). The spec indexes' Lines cells were counted again
(`spec_index_proof.py` 213/213). On the merged tree: `cargo test` `voice` 7/7, `schema_v34` 4/4,
`schema_v33` 5/5, `audio_dynamics` 5/5; `make typecheck` 0 errors and the four baseline
warnings; `make gate` PASS 369 s (names 1, typecheck 6, fmt 3, lint 25, test 175, app 159).
Because the merge touched product code, `voice_proof.py` ran again against Release: 38/38, every
figure the lane's (V5 and V7 worst |Δ| 0.0, V9 0.45 / 4.07 s, K7 +3.3 dB with 4 kHz +2.7, K13–K16
0.430, 0.340, 1.600, 3.650 s, I3 every kind within 0.10 LU of −29.60 LUFS, I9 13.2 dB), the
parity log empty. `clip_inspector2_proof.py` 33/33 on Release (T2's Sound tab fourteen sections in
order), and, over the merged `AudioDSPParameters`, `audio_ap4_probe.py` 11/11 (D10 188,160
samples compared, 0 differ; D11 68.4 µs, 0.32 %). No mutant's anchor moved, so none was re-run.

**Owed.** SE-32 for the owner (each kind on the owner's voice; Robot's character, the pitch
shifter's artefacts, lips and voice in sync). Filed at integration: a Clip ▸ Voice ▸ menu (E8's),
not built here. #123 closed by this phase.

### AP10's record (2026-10-30)

Part 1 of AP10: a track's volume and pan (survey A12), built in lane C. Part 2 — per-track
sub-mixes, track and bus dynamics, the master chain and stems — waits for AP2 part 2's float
write pass (AU-101).

**Asked.** The owner answered AP10's two questions on 2026-10-30: the preview stays approximate
for track dynamics and says so (1 (b)), and stems are separate files (2 (a)).

**Decided.** AU-100…AU-106, recorded before the code: the two answers with their reasons;
`tracks[].volume` (0…4, default 1) and `tracks[].pan` (−1…1, default 0), format 35, each written
only when not its default, refused outside by `set_track`, clamped where they play; `nest`
copying both from every source track but the destination, whose copy is unity and centre (the
adversary's objection, taken before the code: the destination track still applies over the nest
clip), and `unnest` keeping neither; volume an envelope term after mute at every stage, heard by
the meter, the bars and Remove Silences and not by Normalize, the Loudness read-out or the clip
limiter; pan a balance by `AudioPanLaw` carried as the plan segment's `track_pans` (innermost
first, cleared at a folded nest clip, zeros dropped), applied after an enclosing nest's fold and
before the limiter; the chrome; the proof.

**Landed.** Tolls first, gated together and committed alone (`make gate` PASS 400 s): T1 `Track`
out of `model.rs` (597 → 570) to `model_track.rs`, T2 the format version paragraphs out of
`format.rs` (598 → 250) to `format_history.rs`. Core: `volume`, `pan`, `TRACK_VOLUME_MAX` in
`model_track.rs`; `Track::ordinary`; `set_track`'s two arguments and their refusals, the op row
and `op_table.rs`'s two `Number` rows (and "The bound"'s sentence on a range not in whole
numbers); `nested_track`'s `keeps_mix`; `audio_track.rs` (`track_gain`, `Voice::track_pans`);
`Stage.track_gain` and `.track_pan` in `audio.rs`, multiplied in `stage_gain`; `Segment.track_pans`
in `evaluate.rs`, written by `to_json(true)` only when non-empty; format 35, the header,
`schema_v35.rs`, `track_mix.rs`. Swift: `TrackSnapshot.volume`/`.pan` (wiring only),
`PlanSegment.trackPans`, `AudioTrackBalance` and `AudioClipDSP.trackBalance` (in `isInert`) with
the chain's balance step, `AudioTrackDSP` setting each span's balance, the builder's gate,
`ReelOps.setTrack`, the handler and the catalog's prose and two descriptions;
`TimelineHeaderButton.mix` (the fifth switch, `slider.horizontal.3`, fallback V),
`TimelineView+TrackMix.swift` (97: the extension and `TrackMixPopover`), `TrackMixView.swift` (208:
`TrackMixLevel`, `TrackMixEdits`, `TrackMixViewController`), the context menu's and Track ▸
Volume and Pan… with its validator, `UIMenuTable` and `inventory.json`. Docs: spec §4.4, §5.2b,
§6c, §7.2, §7.4, §7.10, §9; the guide's Track volume and pan section and limits, timeline.md,
menus-and-shortcuts.md, the README highlight; SE-33; the proof README.

**Deviations.** `core/tests/op_nullability.rs`'s pinned count of optional arguments moved from 78
to 80 (70 to 72 not plain), the two new `set_track` arguments. M6 is killed by B3, whose second
half builds P1's project offline through `CompositionBuilder.build` and reads it in float, rather
than by P1 over a per-mutant app build. V1 plays 5 s of the 6 s tone: a first run that played 8 s
counted the meter's 0.44 s past the timeline's end, which the export does not hold, and read
0.11 LU apart; over frames all inside the export the two agree. The popover's open state is a
static table on `TimelineView`'s extension keyed by the view, because `TimelineView.swift` is
frozen and took only the two wiring lines. The Volume read-out shows the linear gain as a
percentage (and "Off" at the floor).

**Measured** (the lane; Release after its gate): `audio_ap10_proof.py` 16/16 — F1, F2 −6.020 dB
per channel, F3 −12.040, F4 silent, F5 +0.000 and no keys on the nest's track; P1 +3.010 dB and
0 at −1, (−5.333, +2.323) at 0.5; P2 (−3.010, −3.010); P3, P4 +0.000; P5 (+4.645, −10.666); U1;
V1 |dI| 0.0000 LU at −18.7034 LUFS; B1–B4 (B2 left 0.50045 under the 0.50119 ceiling). The same
16/16 on Debug before the gate. `--mutants` 2/2 (M6 by B3, M7 by B2); the core's eight by hand
against `track_mix.rs`, 8/8 killed. `cargo test` `track_mix` 16/16, `schema_v35` 5/5. `make gate`
PASS 287 s (typecheck the four baseline warnings, test 161, app 121) after one FAIL on
`op_nullability`'s count. The parity log empty on both builds.

**Review.** Passed, with two nits, both taken at integration: `format_history.rs`'s four
intra-doc links that resolved only inside `format.rs` (`migrate_1_to_2`, `GRADING_BRANCH_VERSION`,
`read`, `migrate_1015_to_15`) now name `crate::format`, and `buttonRect`'s doc in the frozen
`TimelineView.swift` says five switches.

**Integrated.** The lane's base `0096d13` was still I's head, so the two commits applied with no
conflict and format 35, SE-33 and AU-100…AU-106 stand as the lane wrote them. The CLAUDE.md
edits owed went in: core's map gains `model_track.rs`, `audio_track.rs` and `format_history.rs`
(`model.rs` without the track, `Track.matte` in `model_track.rs`, a bump's paragraph in the
format rules), app's `+TrackMenu` says five switches and gains `+TrackMix` with
`TrackMixView.swift`. On the merged tree `make gate` PASS 331 s (names 1, typecheck 6 with the
four baseline warnings, fmt 3, lint 10, test 190, app 121). Only doc comments changed in product
code at integration, so the lane's Release proof (16/16) stands.

**Owed.** SE-33 for the owner. Filed at integration: the road-map candidate, an exact audio
preview through `AVAudioEngine` (AU-100). Part 2 continues at AU-107.

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
