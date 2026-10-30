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

### Closing the road map

The ADR in `designs/adr/audio.md`, this file and the survey archived with their rows in
`archive/INDEX.md`, the guide pages and README highlights, and every unfinished item filed as an
issue.

## Risks

- **CPU in the live tap.** Up to eight stages per clip on every composition track, real-time.
  S1 measures it; a stage that cannot run live renders offline as isolation does.
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
