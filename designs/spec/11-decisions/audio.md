# Spec §11 — decisions: Audio (the owner's audio pass, from 2026-10-30)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The owner's pass over a clip's sound, begun 2026-10-30 to turn a desktop USB microphone's
recording into usable audio for a video. Its IDs are the AU- series. Each was recorded before
its code.

- **AU-1 — `audio.volume`'s ceiling is ×32 (+30.1 dB), not ×4; the Volume slider keeps its
  0–400 % travel and the field beside it takes the rest (owner, 2026-10-30: "400% should not be
  a hard max").** The owner's recording `samples/Rode-usb-mic.m4a` (a RØDE USB microphone,
  30.4 s of AAC mono at 48 kHz) peaks at −18.6 dBFS with an integrated loudness of −44.7 LUFS
  (ffmpeg's `volumedetect` and `ebur128`), so Normalize wanted ×7.55 to reach −1 dBFS and stopped
  at ×4, −6.5 dBFS. The ceiling stays — `MAX_GAIN` still bounds `check_audio`'s refusal,
  `clamp_audio` and the envelope, so one bad patch cannot send +80 dB to the mix — but at ×32:
  Normalize now reaches −1 dBFS from a peak as quiet as −31.1 dBFS, and 30 dB covers the gap
  between this microphone's −44.7 LUFS and a −14 LUFS delivery. 32 rather than 31.62 (exactly
  +30 dB) so the refusal reads a whole number: "audio.volume must be between 0 and 32".
  - Measured before the change: AVFoundation's audio mix applies a `setVolumeRamp` volume above
    4 exactly. The recording read through `AVAssetReaderAudioMixOutput` in 32-bit float peaks at
    4.000, 7.600, 16.000, 32.000 and 64.000 times its ×1 peak at those volumes (a scratch probe
    of 2026-10-30), so ×4 was the model's rule and nothing beneath it changes.
  - The Volume row: the slider keeps 0–400 %, where its resolution is useful (a 0–3200 % rail
    would put 100 % at a thirty-second of its width); the field takes 0–3200 %. A value above
    400 % pins the knob at the rail's end, and a drag writes the rail's own range. The quick
    picks are unchanged.
  - One Swift copy of the ceiling, `AudioNormalize.maxGain`, which the Volume row's field and
    the agent's sentences now read too, is held to the core's refusal by `core/tests/audio_gain.rs`,
    reading its `static let` line as `graphic_ffi.rs` reads `maxTextureSide`. No `rc_*` export:
    `ReelCore.swift` is over its cap, and one constant does not need the FFI.
  - No format bump. The file's shape is unchanged and the reader runs no range check
    (`Project::validate` does not call `check_audio`), so an older build opens a project with a
    volume above 4, plays it at ×4 through `audio.rs`'s clamp and writes the stored number back
    unchanged. A bump guards against a loss on that round trip, and there is none.
  - What it accepts: a mix can go further past full scale than before. The preview's output and
    an un-normalised export clip there (phase 5d's 16-bit decode, which says so); a normalised
    export gains in float (#86) and does not. Normalize itself still lands at −1 dBFS.

AU-2…AU-4 open road map "audio" (`designs/audio.md`, from `designs/audio-survey.md`'s tiers A
and B), recorded at its AP0 from the owner's answers of 2026-10-30 to the road map's five
choices ("Yes, lift scopes, and allow Apple's built-in audio effects", then "OK" to each of the
rest), before any of its code. **Numbering from here:** each phase records its decisions in a
block of its own, APn's as AU-n0…AU-n9 (AP1's AU-10…, AP10's AU-100…), so phases built in
parallel lanes never claim one ID; AP0's are AU-2…AU-9.

- **AU-2 — Audio beyond what shipped is in scope: EQ, track and bus processing, and Apple's
  built-in audio units (owner, 2026-10-30, choice 1; amends spec §1).** Spec §1's non-goal
  "audio beyond what shipped … so no EQ, mix buses or Audio Units, while offline voice effects
  are deferred rather than out" is lifted. In: Frame Job's own DSP stages, track and master
  processing, and the audio units macOS itself ships (`AUSoundIsolation`, `AVAudioUnitEQ`, the
  dynamics and time-pitch units), run in the process as `AVAudioUnitTimePitch` already runs for
  speed-ramp audio. Out, under §1's plugin system: hosting third-party Audio Unit plug-ins (the
  survey's C5). Tier C of the survey is not in the road map; it is neither in nor out until the
  owner asks.
- **AU-3 — Live stages are Frame Job's own DSP in the tap, in one fixed order; Apple's units
  only where Frame Job cannot write its own (owner, 2026-10-30, choices 4 and 5).** EQ and the
  high-pass, the hum notch, the gate/expander, the de-esser and the limiter are written beside
  the compressor: real-time safe in the `MTAudioProcessingTap`, deterministic, and proved
  against analytic responses. Apple's units are used for ML voice isolation (`AUSoundIsolation`)
  and E8's voice effects, both rendered offline per clip window into `cache/` on the speed-ramp
  audio pattern. AP0's spike S1 may overturn the first half by measurement, recorded as an
  amendment here. The clip chain's order is fixed: channels → high-pass and EQ → hum notch →
  isolation or noise reduction → gate → de-esser → compressor → limiter, then the fader (the
  core's envelope). Every stage is off by default and inert when off, so a project that uses
  none plays and exports byte-identical to today (a track whose clips ask for nothing still
  gets no tap). A closed vocabulary, as R5-1 has every effect: no user-ordered chain, no
  per-clip stage list.
- **AU-4 — Normalize targets loudness: −16 LUFS by default at −1 dBTP, Peak kept beside it
  (owner, 2026-10-30, choices 2 and 3).** AP1 adds Normalize's Loudness mode (a target in
  LUFS, gated BS.1770 over the window that plays) beside today's Peak; the button stays Peak
  until AP2's limiter can hold −1 dBTP, and from AP2 its default is Loudness. The default
  target is −16 LUFS integrated, with −14 (YouTube's playback reference) and −23 (EBU R 128)
  as quick picks; the ceiling is −1 dBTP. `normalize_clip` keeps `peak_db` and gains the
  loudness mode's arguments.

AU-10…AU-17 are AP1's (loudness you can see and target), recorded before its code from AP0's
spike S4 (`designs/audio.md`'s AP0 record).

- **AU-10 — A per-media loudness cache at 10 ms, S4's format, on the cache lane after peaks.**
  `cache/loudness/<id>.bin` beside a marker `cache/loudness/<id>.complete.json`
  (`LoudnessStamp {source, version, channels, sampleRate, blocksPerSecond, oversample}`,
  `loudnessVersion` 1). The `.bin` is headerless little-endian Float32 records, one per 10 ms
  block: mono `z, tp`, stereo `zL, zR, zLR, tpL, tpR`, where `z` is the MEAN of the K-weighted
  samples squared over the block's frames (`zLR` the mean of yL·yR) and `tp` is
  max(4× Annex 2 FIR, |x|) over the block, linear. The count is `⌈duration·100⌉` from the
  marker's `source.duration`; a load checks the size, every value finite and z, tp ≥ 0 (zLR may
  be negative), and a marker of another version, another `blocksPerSecond` than 100 or another
  `oversample` than 4, or one that will not decode, reads as absent (the cache is made again).
  Frames are placed by `PeakBuckets`' rule verbatim (the file's own rate, the PTS less the MP3
  lead, `⌊f·100/rate⌋`) and the same `covers` check runs before publishing; one
  `CacheLedger.publish` writes the file then the marker, and a `mediaCacheDidChange` of kind
  `loudness` is posted on a publish and on a withdrawal. The pass runs on the lane after peaks
  and before the sync features; `loudness` answers a Bool as `peaks` does (true: nothing to
  make, current, or published), and the in-session retry (SY-11's 2 s, then 10 s) runs while
  either peaks or loudness published nothing, each attempt running loudness only after peaks
  lands and returning when both have. K-weighting is Tables 1 and 2 at exactly 48 kHz and
  libebur128's bilinear derivation from the analog prototype at any other rate; the filter state
  and the FIR's history run continuously across the file. A file whose first buffer has more
  than two channels is read again from the start with `AVNumberOfChannelsKey: 2` and stored as
  stereo; that downmix is not measured against the export's.
- **AU-11 — What a reading counts.** The plan's audio segments of the clip (Normalize's window,
  what plays); the export's channel layout (a mono record's z doubled: dual mono, +3.01 LU);
  and, on stereo media, the clip's own base `mono` fold then `pan` (`AudioPanLaw.gains`) as one
  2×2 matrix over the records' `zL, zR, zLR` (mono media ignore both, as the tap does). It does
  not count noise reduction or the compressor, the volume, fades, ducks, mute or solo, or an
  enclosing nest's fold: the reading is the material's, pre-fader, as Normalize's peak is.
- **AU-12 — The window for every kind of clip.** The played time is walked in 10 ms steps
  `t_k = start + k·6000` ticks over each audio segment; each step's two ends go to source ticks
  through `MediaPeaks.sourceTick` (speed and a ramp's map) and `ReverseMirror.mirrored` (a
  reversed segment); the step reads the mean of records `[⌊a/6000+½⌋, ⌊b/6000+½⌋)` of its
  ordered ends, else the one record holding its midpoint. Steps are pooled in played order
  across the clip's segments (so a reversed clip's grid is anchored at its played start, the
  forward window's end); gating block j is the mean of steps `[10j, 10j+40)`, and their count
  is `⌊(N−40)/10⌋+1` for N whole steps (none under 0.4 s played). The gates are −70 LUFS, then
  −10 LU, once. The true peak is the max of `tp` over `MediaPeaks.window` of each segment
  (outward), bounded on a mixed output channel by Σ|m|·tp. Speed and ramps read within about
  0.5 LU (S4's measurement), recorded as a limit; an exact reading is not in AP1.
- **AU-13 — The loudness clamp.** `volume = min(10^((T−L)/20), 10^(−1/20)/tp, 32)` for target
  T, measured L and true peak tp; `limited_by` names the smaller cap that bit (`true_peak` on a
  tie), else null. It may turn a clip down. Each clip of a selection is taken to the one target,
  which is what matching clips means. A non-finite target falls back to −16 LUFS and is
  reported.
- **AU-14 — What Loudness mode skips, by name.** Normalize's own (a nest, no audio segment, no
  audio props); a cache not yet written ("still being analysed — its loudness has not been
  measured yet"); under 0.4 s played; gated out (every block under −70 LUFS).
- **AU-15 — The inspector.** The Volume section gains a Loudness row (the measured LUFS and
  dBTP; "measuring…" while the cache is pending; "—" when unavailable or several clips are
  selected) and an At volume row (the same plus 20·log10 of the base volume), and the
  Normalize row a Mode popup (Peak | Loudness) and a Target field (LUFS, −50…−5, quick picks
  −14, −16, −23, enabled in Loudness). The choice is app-wide in UserDefaults (default Peak and
  −16); the button and Clip ▸ Normalize follow it, and the menu title stays "Normalize". The
  readout's cost is held three ways by a memo: per project handle, per media file (each read
  once until a cache change invalidates it), and through a live gesture the held answer for the
  same clip, so a Volume or Pan drag neither decodes the plan nor reads a file per tick; the
  Loudness row updates at the gesture's end. At volume is arithmetic on the held answer and the
  current volume.
- **AU-16 — `normalize_clip`'s arguments.** `mode` (`peak` | `loudness`, default `peak`) and
  `target_lufs` (−50…−5, default −16). `target_lufs` with mode peak and `peak_db` with mode
  loudness are refused by name; a value out of range is refused, never clamped. The loudness
  answer is `{mode, target_lufs, ceiling_dbtp: -1, normalized: [{clip, media, measured_lufs,
  true_peak_dbtp, volume, result_lufs, result_true_peak_dbtp, limited_by}], skipped?, note?}`;
  the peak answer is today's plus `mode: "peak"`. No read-only measuring tool in AP1: the
  readout's mirror is the loudness answer's `measured_lufs` and `true_peak_dbtp`.
- **AU-17 — No format bump, no core, FFI or op change.** The cache is a display and analysis
  cache under `cache/`, made again when absent; the project's file is unchanged.

AU-20…AU-26 are AP2's first part (the clip limiter, and Normalize to a loudness through it),
recorded before its code from AP0's spike S1 and AP1's record. AP2 is built in two parts: the
export's float decode, its master limiter and `audio_bits` are the second, with their own
decisions from AU-27.

- **AU-20 — The clip limiter stage is S1's, last in the tap's chain.** `AudioLimiterStage`
  (`AudioLimiterStage.swift`), a port of S1's `OwnLimiter2.swift` at `taps: 64, beta: 10,
  annexToo: true, tapOuter: true` and nothing else. The detector is the maximum, per sample and
  over every channel, of |x|, the three fractional phases of a 64-tap Kaiser-windowed sinc
  (β 10) 4× interpolator, and BS.1770-4 Annex 2's four 12-tap phases; each FIR loops its taps
  outermost with element-wise vDSP only (never `vDSP_conv` or `vDSP_biquad`, which give
  different bits for different buffer sizes). The need `min(1, ceiling/peak)` is held by a
  sliding minimum over 159 samples; the release is a one-pole of `releaseSeconds` that never
  rises above the held value and snaps to it once within 2⁻²⁰; the gain is the box mean of the
  last 96 released values, summed afresh each sample (no running sum, so a released stage's
  gain is exactly 1 and it is an exact delay); one gain for all channels; the audio is delayed
  158 samples (lookahead 96 + taps − 2) at any rate. Every buffer is allocated in `init`, and
  `reset()` restores the fresh state. In the chain it runs last, after an enclosing nest's fold
  (AU-3's "limiter, then the fader"). With no settings its ceiling is +∞: a pure delay once
  released.
- **AU-21 — `audio.limiter`.** Null (absent) or `{ceiling_db, release}`: `ceiling_db` in dBTP,
  post-fader, −24…0, default −1; `release` in ticks, 600…600 000 (1 ms…1 s), default 60 000
  (100 ms). Written only when set (`skip_serializing_if`), so a project without one writes the
  text it did; format 30 (28 and 29 went to AP9 and AP11, which landed first), so an older
  build refuses a limited file instead of dropping its limiter on save. `set_audio {limiter:
  {}}` stores the defaults, `limiter: null` clears it, a value out of range is refused by name,
  and an action's end is clamped to the same ranges. Base-only like the compressor (`structural(audio:)`): an action does not move it.
  A NEST clip's limiter reaches nothing, as its compressor does (the plan names the innermost
  clip).
- **AU-22 — The stage is told the clip's gain: its base volume.** The fader is downstream of the
  tap, so the stage's linear ceiling is pre-fader: `10^(ceiling_db/20) / audio.volume` (base),
  +∞ at volume 0. Fades and ducks only ever lower the gain after it, so they keep the output
  under the ceiling. Accepted, each passing the ceiling: an action raising the volume above its
  base, an enclosing nest clip's volume above 1, the fader's slew at a hard cut from a louder
  clip (#87's limit), and two limited clips overlapping (a transition, two tracks), whose sum no
  clip limiter sees. AP2's second part's master limiter holds the export; the preview has none
  (S3).
- **AU-23 — The limiter's lead.** The stage runs for the WHOLE composition audio track once any
  clip on it has a limiter, so the track's delay never changes at a cut. Such a track's media is
  placed 1,975 ticks earlier (158 samples at 48 kHz; plus SY-25's 6,400 when it also runs noise
  reduction), and the tap looks its spans up at `t + 1,975`, so the compressor, the folds, the
  pan and the limiter meet their own clip's settings at their own samples. Noise reduction's
  amount keeps SY-25's cost at a cut. As SY-25: a clip starting under 3.3 ms into the track
  loses that much head, and the track's last 3.3 ms go unheard. A project with no limiter has
  no lead and no lookup shift, and exports byte-identical to before.
- **AU-24 — Normalize to a loudness writes the limiter when the peak needs it.** For target T,
  measured L and true peak tp: `v0 = min(10^((T−L)/20), 32)`. A clip with no limiter whose
  `tp·v0 ≤ 10^(−1/20)` gets `volume: v0` alone (AP1's result). Otherwise Normalize writes one
  `set_audio {volume: v, limiter}`: the clip's own limiter kept (its ceiling lowered to −1 when
  above it) or the default. `v` comes from `AudioLimiterModel`, a block-rate model of the stage
  over the reading's 10 ms played steps: per step `need = min(1, c/(peak·v))` for ceiling c and
  the step's true peak, `env = need < env ? need : env + (need − env)(1 − e^(−0.01/release))`,
  the step's energy times `v²·env²`, integrated by `ClipLoudness`'s gates; the gain is found by
  bisection on log gain to 0.001 LU and capped at 32 (`limited_by: "max_gain"`, the only limit
  left). The answer reports `result_lufs` as the model's figure and `result_true_peak_dbtp` as
  `min(tp·v, ceiling)`, and the row gains `limiter: {ceiling_db, release}` or null.
- **AU-25 — Loudness is Normalize's default (AU-4's AP2 step; amends AU-15 and AU-16).** The
  button and Clip ▸ Normalize default to Loudness (a stored choice still wins); `normalize_clip`
  with no `mode` is Loudness, except a call naming `peak_db` and no `mode`, which is Peak.
- **AU-26 — The Limiter section.** In the Sound sub-tab after Mix (the signal's order): a "Limit
  peaks" checkbox (on writes the defaults), Ceiling (dBTP, −24…0, one decimal, quick picks −1,
  −2, −3, −6) and Release (ms, 1…1000, quick picks 50, 100, 200, 500); its summary reads
  "−1.0 dBTP" or "off", and Reset clears it. While the clip's limiter is on, the Volume
  section's At volume row reads the model's LUFS (AU-24) and `min(tp·v, ceiling)`.

AU-30…AU-39 are AP3's (EQ, hum removal and channel selection; survey A3, A7, B7), recorded
before its code from AP0's spike S1 and the survey's measurements of the owner's recording.

- **AU-30 — The EQ stage: RBJ biquads in Double, 17 fixed positions, designed at the cut.**
  `AudioEQStage` (`AudioEQStage.swift`) runs RBJ cookbook biquads in Double, transposed direct
  form II, scalar per sample over raw pointers (sections outer, samples inner, one channel at a
  time; never `vDSP_biquad`, which S1 found gives different bits for different buffer sizes).
  It has 17 FIXED positions — high-pass sections 1 and 2, the low shelf, bands 1–3, the high
  shelf, low-pass sections 1 and 2, and hum harmonics 1…8 — so a slot present in two abutting
  clips keeps its state across the cut, and a position that turns on starts from zero; an
  inactive position is skipped and its state zeroed. Coefficients are designed in `process`
  only when the run's settings differ from the last designed (no allocation, no lock), so they
  switch at the cut sample (S1 measured the splatter of such a switch at −79 dB, accepted).
  AP8's seam is `design` and the swap point, where a per-sample glide would go. `reset()`
  zeroes every state and forgets the design. Two channels are not run in `SIMD2` lanes (untried
  in S1; not taken). One stage holds the EQ then the hum, AU-3's order.
- **AU-31 — `audio.eq`: named slots, two shelves and three bells.** `{high_pass, low_shelf,
  band_1, band_2, band_3, high_shelf, low_pass, bypass}`, each slot null (absent, off) or an
  object: a pass `{frequency, slope}` (Hz 20…20 000; 12 or 24 dB/octave; high-pass default
  `{80, 12}`, low-pass `{12000, 12}`), a shelf `{frequency, gain_db}` (gain −24…24 dB; low
  `{100, 0}`, high `{8000, 0}`), a bell `{frequency, gain_db, q}` (Q 0.1…10; `{1000, 0, 1}`).
  Named slots rather than a list, because `AudioProps` stays `Copy` (the plan evaluates it per
  sample point) and a patch merges per slot. Three bells because the voice's three moves each
  get one — low-mid mud near 300 Hz, a boxy 1 kHz, presence near 4 kHz — beside the two
  shelves; the worst case of 17 sections costs about 17 × 7.2 µs per 1024 stereo frames (S1),
  under 1 % of real time. A 12 dB/octave slope is one Butterworth section (Q 0.7071), 24 is two
  (Q 0.5412 and 1.3066) — never two stacked Q 0.7071 sections, which make a Linkwitz-Riley
  slope (−6 dB at the corner). Shelves are RBJ with S = 1. A shelf or bell at exactly 0 dB is
  not designed, and no section at or above 0.49·fs is designed. `bypass` keeps the settings
  and silences them.
- **AU-32 — Three presets, each writing only its own slot (and `bypass: false`), so they
  combine.** Rumble Cut: `high_pass {80, 24}` (survey §2: 80 Hz takes about 1 dB off the
  owner's pause noise; Premiere's Reduce Rumble cuts "below about 80 Hz", survey §3). De-mud:
  `band_1 {300, −3, 1.0}` (survey §2: 78 % of the pause noise lies below 300 Hz, the voice
  band's lower edge). Presence: `band_3 {4000, +3, 1.0}` (the voice band's upper edge, below the
  5–9 kHz sibilance band). The frequencies are the survey's; the ±3 dB gains are not measured,
  and manual check SE-29 judges them. The presets are the inspector's only; the catalog's prose
  gives an agent the values.
- **AU-33 — `audio.hum`: a comb of depth-scaled RBJ peaking cuts.** `{frequency, depth_db,
  harmonics}`: mains 50 or 60 Hz (default 60), depth 6…60 dB (30), harmonics 1…8 (4). Harmonic
  k is an RBJ peaking cut of −`depth_db` at k·f0 with Q = 10·k / A, where A =
  10^(−depth_db/40). The RBJ cut's pole damping is 1/(A·Q), so dividing by A holds every
  section's pole bandwidth at f0/10 at any depth, and scaling by k holds it constant across the
  harmonics, so an upper harmonic cuts no more of the voice than the fundamental. Plain
  Q = 10·k is not taken: cascaded, its skirts widen with depth and overlap — 60 Hz × 4 at 30 dB
  reads −30.18…−30.90 dB at the harmonics and −2.6…−2.8 dB between them, and 50 Hz × 8 at 48 dB
  reads −49.3…−54.9 dB and −11.9…−14.9 dB between, inside the voice's fundamental range. With
  the scaled Q the cascade reads −depth −0.00…−0.03 dB at every harmonic and −0.10 dB midway
  between, for both. A harmonic at or above 0.49·fs is not designed.
- **AU-34 — `audio.channels`, the chain's head.** `both` (the default, not written), `left`,
  `right` or `swapped`. On two or more channels `left` copies channel 0 into every channel,
  `right` channel 1, and `swapped` exchanges 0 and 1; a one-channel (mono) track ignores it, as
  it ignores pan. The clip chain's order, after AU-54's isolation crossfade, is channels → EQ
  and hum → noise reduction → compressor → mono fold → pan → an enclosing nest's fold →
  limiter. On a noise-reduced track the head stages see samples 6,400 ticks (SY-25's lead)
  ahead of what the stages after the reducer see, so the tap looks the head's clip up at
  `t + lookupLead + headLead` and splits a run at a cut of either lookup; a track with no noise
  reduction has no head lead.
- **AU-35 — What a reading counts, amended (AU-11).** On stereo media the 2×2 matrix is pan ·
  fold · pick: the channel pick counts, before the base mono fold and pan. EQ and hum are not
  counted, as noise reduction and the compressor are not. Peak Normalize keeps the maximum over
  the channels (an upper bound, as it is for pan).
- **AU-36 — The drawn curve is Swift's, from the stage's own design.**
  `AudioEQDesign.responseDB` evaluates the same `design` the stage runs, at 48 kHz (every
  composition audio track plays at 48 kHz, SY-23); the core does no sample work (spec §7), and
  one function means the drawn curve IS the stage's coefficients. 256 log-spaced points from
  20 Hz to 20 kHz, the EQ and the hum together; dimmed when bypassed; nothing drawn for a mixed
  selection.
- **AU-37 — Format 32, base-only, no op.** (31 went to AP5's voice isolation, which landed
  first.) `audio.eq` and `audio.hum` are written only when set (`{}` stores the slot's
  defaults, `null` clears a slot or the group), `audio.channels` only when not `both`, so a project without them writes the text it did and
  there is no migration step; the bump is so an older build refuses the file rather than
  dropping them on save. All three are base-only (`structural(audio:)`): an action's end is
  clamped (frequencies and gains to their ranges, a slope to 24 from 18 up else 12, the mains to
  60 from 55 up else 50, harmonics to 1…8) and the tap ignores it. A nest clip's three reach
  nothing, as its compressor does. `paste_attributes` carries them whole through `check_audio`.
  No op, tool, FFI or op-table change: `set_audio` takes the three keys.
- **AU-38 — The sections, in signal order.** The Sound sub-tab reads Volume, Fades, Ducking,
  Voice Isolation (AU-56), **Channels** (a popup: Both, Left Only, Right Only, Swap Left and
  Right; the summary its word), **EQ** (the drawn curve; Bypass; the three Presets buttons; per slot a checkbox writing
  that slot's default — bands 1, 2 and 3 at 300, 1000 and 4000 Hz — then Frequency (a field in
  Hz with quick picks), Gain (dB, −24…24, quick −6, −3, 0, 3, 6), Q (0.1…10, quick 0.5, 0.7, 1,
  2, 4) and a Slope popup (12 or 24 dB/oct); the summary "off", "bypassed" or "N on"; Reset
  clears `eq`), **Hum** (Remove hum, writing the defaults; a Mains popup 50 or 60 Hz; Depth dB
  6…60, quick 12, 24, 30, 48; Harmonics 1…8, quick 1, 2, 4, 8; the summary "60 Hz · 4" or
  "off"), Noise Reduction, Compressor, Mix, Limiter. Each control writes a whole `EqProps` or
  `HumProps`, the compressor's pattern.
- **AU-39 — The proof.** `eq_probe.py`'s rows Q1–Q11 over the DSP, the curve and the chain, with
  mutants M1–M10 each killed by its named row and M11 (the patch template without `hum`) by
  hand against `core/tests/audio_eq.rs`; `eq_proof.py`'s rows E1–E8 over MCP and exports; how
  the presets, the notch and a pick sound on the owner's voice is manual check SE-29.

AU-50…AU-57 are AP5's (voice isolation; survey A4, and B4's verdict), recorded before its code.

- **AU-50 — `audio.isolation` 0…1, 0 off, written only when not 0, format 31.** (30 went to
  AP2's limiter, which landed first.) How much of Apple's isolated voice replaces the clip's own
  sound: `set_audio` refuses a value outside 0…1 in `in_range`'s sentence
  (`audio.isolation must be between 0 and 1, not 1.5`), an action end's value
  is clamped there by the evaluator, and 0 writes no key, so every other project writes the text it
  did and there is no migration step. Base-only in this phase (AP8 animates it). Paste Attributes
  carries it, the audio group travelling whole. On a nest clip it reaches nothing, as the
  compressor does: set it on the clips inside.
- **AU-51 — The render is S2's recipe.** `AVAudioUnitEffect` (`aufx`/`vois`/`appl`), parameter 1
  = 0 (High Quality Voice) and parameter 0 = 100, in offline manual rendering at 48 kHz mono, one
  engine per channel in lockstep over one `RampSourceReader` (per-channel feeders shaped as
  `TimePitchFeeder`, dropping what the slowest has read), at most 4096 frames a block. A unit whose
  `latency × 48000` rounds to anything but 4440 fails the render. 4 s of the media is fed before the
  window (from frame 0 when the window starts sooner), then the media and zeros past the window's
  end until its last frame is out; the first preroll + 4440 output frames are discarded. The source
  is what the composition plays: `RampAudioCache.renderSource` (the 48 kHz copy) forward, the
  reversed file for a reversed clip.
- **AU-52 — The cache.** `cache/isolated/<media>-<16 hex>.caf`, FNV-1a 64 (as
  `RampAudioCache.name`) over the media file's path, size and modification second,
  `IsolationRenderer.version`, the reversal, the model (0), the preroll frames and the window — not
  the Amount; 32-bit float CAF through `RampCAFWriter`. It runs on `RampAudioRenders` (its owners,
  landing under the ledger, pruning, a failure once per launch, `-RCDevRampRenderHold`), whose owner
  is now called when a wanted render lands OR fails, so a failure reaches the pane. A cached render
  is never verified by re-rendering it (S2: windows starting mid-file differ by about −51 dB). AP14
  adds a job case beside it.
- **AU-53 — Amount is a crossfade in the tap, before the chain.** `out = dry + a·(wet − dry)`
  (exactly `wet` at a = 1), sample-aligned through the segment's own placement
  (`placement(of:shift:)`, so the noise reducer's and the limiter's leads compose). The wet/dry
  offset is rounded ONCE, from the placement's source-in minus its place, `⌊(2·(in − at) + 12) /
  25⌋ − window.firstFrame` in 48 kHz frames, so a place and a source-in off the 48 kHz grid (29.97
  fps) cannot round apart. The render is read into memory when the composition is built (about
  11.5 MB per channel-minute, the recorded cost). A missing render adds nothing — no span, and no
  tap earned by isolation — so the clip plays DRY while it is pending; a tap whose rate is not
  48 kHz passes dry. An Amount change rebuilds the composition, never the render.
- **AU-54 — The order (amends AU-3).** isolation → channels → high-pass/EQ → hum → noise
  reduction → gate → de-esser → compressor → limiter → fader. Isolation and noise reduction do not
  exclude each other; noise reduction works on the crossfade.
- **AU-55 — Which segments are isolated.** ×1 forward segments and reversed segments whose
  reversed copy is ready; a time-scaled segment (a constant speed with Keep pitch on), a
  ramp-rendered one (a ramp, or a constant speed with Keep pitch off) and a freeze play dry, and
  the pane, the guide and `set_audio`'s prose say so. A reversed clip renders the reversed file
  itself, so it aligns by construction; its floor is measured and reported. Two clips cut from one
  take render two windows (S2: a seam about −30…−50 dB, accepted, not shown audible).
- **AU-56 — The section.** "Voice Isolation", in the Sound tab before Noise Reduction: an "Isolate
  voice" check (on sets `IsolationCache.defaultAmount`, 0.8: S2's pauses −14 dB with room tone
  kept, where 1.0 makes them dead air), an Amount row 0–100 % (quick 50, 80, 100), and a Status
  read-out — Rendering…, Ready, "Plays without it at this speed", "Waits for the reversed copy",
  "Not rendered: <why>" — refreshed on `.reversedMediaDidChange`, which the document posts when a
  render lands and when one fails. De-reverb (B4) is this control (S2: C50 +5.2 dB, the late tail
  −5.3 dB on an RT60 0.6 s room): the section says it "reduces room echo", and there is no
  separate control.
- **AU-57 — Export and agents.** An export wants and waits for its isolation renders as it does
  for ramps ("Preparing…"), and fails `isolationFailed` naming the clip when one cannot be
  rendered. An agent uses `set_audio {isolation}`: no new tool, and the render's status is not in
  `get_project`.

AP9's decisions, split edits (J- and L-cuts) and a reversible Detach Audio (`designs/audio.md`
AP9, survey A10), recorded before its code.

- **AU-90 — The model is a LINKED PAIR: Detach Audio's two clips name each other in
  `Clip.linked` (format 28), every placement edit keeps both in step in time, trimming the sound
  half's edge alone makes the J- or L-cut, and Attach Audio merges a pair back (owner,
  2026-10-30, the road map's "Asked at AP9", answer (a)).** Each half stays an ordinary clip on
  its own track, so the pair fits spec §2's one kind of track; a sound lead on a track of its own
  cannot collide with "overlap is a transition"; and the plan, playback, export and the overlap
  rule are untouched. Option (b), one clip whose sound overhangs its picture, would have changed
  every one of them. **The half you grab decides, not ⌥**: ⌥-drag on an edge is already Rate
  Stretch (spec §4.4), so a drag on the sound half's edge trims the sound alone, and the owner
  accepted this deviation from the road map's "⌥-drag" wording. `linked` is the partner's id,
  written only when set; a link must be mutual and inside one container (the timeline or one
  nest), and the reader refuses a file with a one-sided link: "clip {a} is linked to clip {b},
  which is not linked back".
- **AU-91 — What follows the link: TIME, not track; one clamp over the pair; a ripple that would
  push a leading sound below 0 refuses; a sound half deleted alone keeps its picture.**
  `move_clip` moves the named clips and their partners by one delta, clamped so no clip of the
  closure starts before 0 (a J-cut picture dragged left stops where its sound reaches 0, so the
  lead is kept), and the track delta is anchored on and applied to the CALLER's clips only — a
  partner keeps its own track, so dragging a sound half to an empty track moves it alone
  vertically and its picture stays. That is what lets the sound of a second consecutive detached
  shot lead into the first without overlapping its neighbour's sound (which the overlap rule
  would turn into a dissolve). `split`, `duplicate`, `nest` and `ripple_delete` (its spans the
  union over the closure) take both halves. A timeline-wide shift (`shift_clips`: the ripples,
  `close_gap`, `insert_time`, `add_transition`'s ripple form) moves every clip on an unlocked
  track at or after the boundary AND each such clip's partner on an unlocked track
  (`edit_time.rs`'s `shifted`), and when a partner would start before 0 the op refuses — "clip
  {s} would start before 0: it leads its linked clip {p} by {lead} ticks" — because a ripple
  closes fully or not at all (`close_gap`'s rule); `insert_time` only moves right and never
  meets it. `delete` takes a picture's sound with it, but a sound half named alone is deleted
  alone and its picture stays silent (its link cleared): Detach Audio then Delete stays the one
  way the app drops a clip's sound. `ripple_delete` of either half removes both, since leaving
  half a pair behind a ripple would leave it out of sync with everything that moved. Locks win
  over links everywhere: a partner on a locked track is not moved, cut, copied or deleted, and
  stays linked.
- **AU-92 — A split pairs its halves.** When both halves of a pair are cut at one time, the two
  second halves name each other and the originals keep their link. When only one is cut (the
  time falls outside the other, as in a J- or L-cut), the uncut partner stays linked to the half
  sharing the longer stretch of time with it, the first on a tie, and the other half is unlinked.
- **AU-93 — Edges: a trim or roll carries to the partner whose same edge coincides, unless
  `alone`.** `trim_start` and `trim_end` without `alone`, on a linked clip whose unlocked
  partner's same edge equals this clip's edge before the edit, apply the same `to` to the
  partner after this clip, each through its own clamps; a refusal from either is the answer.
  `roll` without `alone` also rolls the partner to the same `to` when its start equals this
  clip's and it has a hard-cut predecessor. Otherwise the clip moves alone. `alone` (default
  false) is the J/L-cut: the timeline's trim and roll gestures send it when the clip grabbed is
  a linked SOUND half (linked, picture off), and W and E do the same, so dragging the sound's
  front edge earlier makes a J-cut and its back edge later an L-cut, while dragging the
  picture's edge trims both. A picture-alone gesture is out of scope; an agent sends `alone`.
- **AU-94 — Slip slips both halves; speed and direction are refused on a linked pair.** `slip`
  on a linked clip with an unlocked partner slips both by the smaller in magnitude of the two
  clamped amounts, so the sound stays on its picture. `set_speed`, `rate_stretch`,
  `set_reversed`, `add_speed_ramp`, `set_action`, `set_action_end` and `remove_action` are
  refused when they would change a linked clip's speed, its direction or its speed-naming
  actions (start, duration, curve, `end.speed`): "clip {c} is linked to clip {p}: Attach Audio
  before changing its speed or direction". Re-timing both halves identically is a second
  implementation of every rate op; Attach Audio, then the change, then Detach Audio is the way.
- **AU-95 — Attach Audio (`attach_audio {clip}`, Clip ▸ Attach Audio) merges a linked pair back
  into one clip.** Either half may be named. Refused, each in its own sentence: "clip {c} is not
  linked to a detached sound"; "clips {a} and {b} are not a picture and its detached sound" (the
  sound is the half with its audio on, the picture the half with it off); and "clip {v}'s picture
  and clip {s}'s sound do not cover the same time; trim them to match before Attach Audio" when
  their start, duration, source, speed or actions' spans and curves differ. Otherwise the
  picture's audio is switched on and takes the sound clip's `audio` group, and each of its
  actions' `end.audio` the sound's action at the same index (removed where that one has none);
  its link is cleared and the sound clip is removed. The sound's track stays, as after any
  delete. One undo step.
- **AU-96 — Links settle in one place; copies re-pair.** `Project::finish` clears, before its
  identity comparison, every `linked` whose clip is absent from its container or does not name
  this clip back (`settle_links`), so an op that removes, moves into a nest or replaces half a
  pair (`delete`, `overwrite_clip`, `remove_track`, `add_blurred_background`'s copy, a split's
  other half) needs no code of its own and never writes a one-sided link. `duplicate`, `paste`
  (the timeline and each copied nest) and `unnest` map each copied link through their old → new
  ids, and a link whose partner was not copied is cleared. Copy puts the partner of each selected
  PICTURE half in the payload, so a pasted detached clip arrives as a pair; a selected sound half
  is copied alone.
- **AU-97 — The chrome: a link glyph, an echo, and Clip ▸ Attach Audio (⇧⌥⌘D).** A linked clip's
  name strip shows the SF Symbol `link` after its kind symbol; each selected clip's partner is
  drawn with a dashed accent ring, so a selection shows what the core will move with it (the
  selection itself stays what was clicked). Attach Audio sits after Detach Audio in the Clip menu
  on ⇧⌥⌘D (Detach Audio's ⌥⌘D plus ⇧), and as a button beside Detach Audio in the Sound tab's
  Mix section; it sends one `attach_audio` per pair in the selection.

AU-110…AU-116 are AP11's (ducking by speech, and fade and crossfade shapes; survey B2, B9),
recorded before its code.

- **AU-110 — A duck can follow the ducking clip's SPEECH, from spans saved on its media
  (owner, 2026-10-30: "(a) Saved in the project"); amends "Ducking is by clip extent"
  (`foundations.md`).** `audio.duck.mode` is `extent` (the default, today's behaviour byte for
  byte) or `speech`. The spans are `media[].speech`: forward-file source ticks `[start, end)`,
  sorted, non-overlapping, `0 ≤ start < end ≤ duration`, at most `MAX_SPEECH_SPANS` (100,000),
  written by the op `set_media_speech {media, spans}` (document-level, refused inside a scope as
  the other media ops are). Saved rather than handed to the plan per build, so the plan stays a
  pure function of the project: the preview, every export, `get_project` and the core's tests
  see the same spans with no host input, and nothing changes the mix without an edit. Accepted:
  a format bump and the file's size for long media (measured on `samples/Rode-usb-mic.m4a` in
  AP11's record). A media's `speech` is refused, each in its own sentence, on an unknown media,
  a media without audio, a span with `start ≥ end`, a negative start, an end past `duration`,
  spans unsorted or overlapping, and more than the cap; equal spans are an identity. `validate`
  holds a file to the same rules. `add_media` and a relink's probe never carry it.
- **AU-111 — The spans come from the Silero VAD cache, frozen at their first write, in the same
  undo step that turns Speech on.** `DuckSpeech.spans`: runs of `cache/speech/` chunks with
  p ≥ `SilenceDetector.Settings.defaultVoiceConfidence` (0.5, one copy), gaps under 0.2 s
  bridged, chunk i = `[i, i + 1) × MediaSpeech.chunkTicks`, each end clamped to the media's
  `duration` (the cache rounds its chunk count up) and an empty span dropped. Choosing Duck by
  Speech (the Audio tab, or `set_audio` with `duck.mode: "speech"` over MCP) writes
  `set_media_speech` for each media that has no `speech` yet, then the `set_audio`, as ONE edit
  ("Ducking"); a media that already has spans keeps them (re-detection is out of scope). A
  missing cache refuses by name ("… its speech has not been detected yet"), as does a clip that
  is not a media clip with audio. `set_audio` itself refuses only a PATCH that sets
  `duck.mode: "speech"` on a clip that is not a media clip or whose media has no `speech`
  ("audio.duck.mode speech needs the clip's media to carry speech spans (set_media_speech)");
  any other edit of a clip already holding a spanless Speech duck (made by Paste Attributes)
  applies, and such a duck ducks nowhere.
- **AU-112 — The speech duck's gain rule.** The media's spans are reflected for a reversed clip
  (`[D − b, D − a]`, D the media's duration, since `in` is in the reversed stream), mapped to
  clip time at the base rate (`(s − in) / speed`, start floored, end ceiled) or through the
  speed map on a ramped clip, clipped to `[0, duration)`, put in project time over the part of
  the instance that plays, expanded to `[s − pre_roll, e + hold]`, and merged where they overlap
  or touch. Each merged span ducks exactly as an extent duck over it would (the attack from its
  start, the level held, the release after its end); the ducker's multiplier is the MINIMUM over
  its spans, so overlapping releases and attacks never multiply into a deeper dip. The envelope
  is sampled at each span's four edges and where one span's release crosses the next one's
  attack. `pre_roll` and `hold` default to 0.5 s (300,000 ticks) each, are ≥ 0, and are BASE-only like the rest
  of the duck (CI-3); level, attack and release keep their meaning and defaults.
- **AU-113 — The speech duck is drawn on the ducking clip.** The plan carries `ducks`: one entry
  per Speech ducker, `{clip, ramps}`, its multiplier alone over its expanded extent (omitted
  when there is none). The timeline strokes it as a 1 pt yellow line across the ducking clip's
  audio region, gain 1 at the top and 0 at the bottom, so a person sees where the bed goes down
  and comes back. Extent ducks draw nothing new.
- **AU-114 — Fades have four shapes: Linear (the default and today's), S-curve, +3 dB and
  −3 dB.** `audio.fade_in_shape` and `audio.fade_out_shape`; with u the fade's progress
  (`t / fade_in`, `remaining / fade_out`): Linear `u`, S-curve `(1 − cos πu) / 2`, +3 dB
  `sin(uπ/2)` (fast start, −3 dB at the middle), −3 dB `1 − cos(uπ/2)` (slow start). A
  non-linear fade is sampled on the action grid (1/30 s, at most 4,096 points), as an eased
  action is; a linear one adds no points, so its ramps are today's.
- **AU-115 — A transition's crossfade takes the same four shapes; `plus_3db`, R5-2's constant
  power, is the default, bit for bit.** `transition_in.audio_shape`, set by
  `set_transition_style`'s new `audio_shape`. Over the eased progress p the incoming clip gets
  `gain(p)` and the outgoing `gain(1 − p)`, except that +3 dB's outgoing side stays R5-2's
  `cos(pπ/2)` code path, so every transition with no `audio_shape` plans exactly as before. A
  minted transition keeps the default.
- **AU-116 — Format 29, and every new key written only when not its default.**
  `duck.mode`, `duck.pre_roll` and `duck.hold` are each written whenever they differ from their
  defaults, in either mode (a pre-roll set on an extent duck survives a save); `fade_in_shape`
  and `fade_out_shape` only when not `linear`; `audio_shape` only when not `plus_3db`; a media's
  `speech` only when present. A file with none of them reads and writes the text it did. A
  relink that probes the new file rewrites `speech` in the same edit — spans starting at or
  past the new `duration` dropped, ends clamped to it, the list cleared when it empties or the
  file has no audio — so a relink never fails `validate` over spans (no re-detection).

AU-130…AU-136 are AP13's (audio while scrubbing; survey B5), recorded before its code.

- **AU-130 — Scrub grains are read from a composition built only for scrubbing, one
  `AVAssetReader` at a time, and played through an `AVAudioEngine` only scrubbing uses.** The
  build is `CompositionBuilder.build(plan:planJSON:urls:recipeKey:)` with `metering: false`, from
  the player's plan, media and recipe slot, with fresh taps (for the reason `ExporterLoudness.swift`'s
  header gives for its own build). Each grain is one `AVAssetReader` with an
  `AVAssetReaderAudioMixOutput` over the build's `audioMix`, read in
  `ExportAudioGain.floatMixSettings`. The readers run strictly one at a time on a new serial queue,
  `com.kgalligan.framejob.scrub-audio`, and the grains play through an `AVAudioPlayerNode`. Spike
  S3's E8 measured a mid-file reader's first buffer at 7.4–13.7 ms with one AAC track and 31–71 ms
  with four (`tools/proof/audio_spike/S3/e8_premix.log`), and reused one mix across sequential
  readers. Rate bursts on the `AVPlayer` are rejected: playing moves and reports the playhead
  through `timeAdvanced`, fights `startSeek`'s one-in-flight rule, and
  `seekingWaitsForVideoCompositionRendering` holds the sound behind the picture, and S1 found a
  silent pre-roll. `audioTimePitchAlgorithm` and a scrubbing `AVAudioMix` are rejected because both
  are still the player. The scrub build is remade when the player's composition object changes
  (`===` against `Playback.built?.composition`), so a new plan, a DSP change, a landed reversal or
  a ramp render is heard. The rebuild is its own queue item: it is posted whenever a move sees a
  new composition, whether or not a grain is asked for, and it is never dropped by generation. No
  player composition means no grain.
- **AU-131 — A grain is 80 ms of the mix forward from the frame-snapped playhead, with 5 ms sin²
  edges, at unity.** 3,840 frames at 48 kHz; the gain is `sin²(π/2·(i+0.5)/240)` rising over the
  first 240 frames, 1 between, and the mirror over the last 240. A grain never reads past the
  timeline's duration: within 80 ms of the end it is shortened to the end, and when fewer than 480
  frames remain, or the playhead is at or past the end, there is none. Frames are taken by
  presentation time: frames before the start are skipped, frames past the end are dropped, and a
  short read is zero-padded.
- **AU-132 — When grains play: one ahead, only on a new frame, silent on hold and on mouse-up.**
  The press on the ruler and every drag position go to the scheduler through the same `move`; a
  `move` on an inactive scheduler starts a new scrub. A grain is asked for only when the snapped
  playhead differs from the last grain's start in this scrub (none at its start, so a press always
  qualifies) and no more than 0.04 s of sound is still queued. Its start of sound is the later of
  now and the end of what is queued, and the queue then ends one grain later. Holding still, or
  moving within one frame, asks for nothing, so silence follows within 0.12 s (the lead plus one
  grain). Mouse-up ends the scrub (the last start is forgotten, the queue's end is kept) and asks
  for nothing more: the grain already handed to the output plays out its fade, and requests not
  yet read are dropped by generation. The engine starts on demand on the scrub queue and stops 1 s
  after the end, by a run-loop `Timer` the next move cancels. A configuration change
  (`AVAudioEngineConfigurationChange`) makes the next start build a fresh engine. The engine's
  `inputNode` is never touched, because touching it would ask for the microphone.
- **AU-133 — Dragging left plays each grain forward from the playhead.** A reversed 80 ms of
  speech carries no word, and finding a word is the point.
- **AU-134 — A grain is the player's mix, and its stateful stages start fresh.** It carries the
  clip's volume, fades, ducks, pan, mono fold, mute and solo (the plan) and the PreEffects tap's
  DSP. It is sample-for-sample the export's float read at the same frames, except that stateful
  stages (the compressor, noise reduction, and every later live stage) start fresh in each grain,
  as an export starting at that frame would. That rests on the tap's `prepare` making a new
  `AudioDSPChain` for each reader (`AudioTapContext.prepare` in `AudioTap.swift`), and not on its
  0.1 s seek rule, which adjacent grains do not trip; `scrub_audio_probe.py`'s C3 scores it on the
  scheduler's own adjacent grains. Were C3 to fail, `ScrubAudio` would make a fresh scrub build for
  every grain while any track of the plan has an active DSP chain, with the measured build time
  per grain in the record. The export's loudness gain and any master stage do not apply, as in the
  player. The level meter does not move during a scrub, because the rate KVO arms it.
- **AU-135 — Scrub audio has no toggle, no key and no tool.** It is always on; a person silences
  it as they silence the preview, with mute or solo or the Mac's volume. So there is no
  `UserDefaults` key and no View item (Final Cut Pro's View ▸ Audio Skimming is not copied). It has
  no MCP mirror: a scrub makes no edit and no menu item, `set_playhead` is a seek and plays no
  grain, and an agent cannot hear. `scrub_audio_probe.py` drives the scheduler and the reader
  instead.
- **AU-136 — The proof is `scrub_audio_probe.py`'s rows and mutants and manual check PB-14.** Its
  rows G1–G7 score the window and the scheduler, C1–C3 the reader against the export's float read,
  and E1–E5 `ScrubAudio`'s queue (what is played, the drop by generation, the rebuild); eight
  mutants, each killed by its named row, plus `read-by-arrival`, which is equivalent (AVFoundation's
  mix reader delivers in presentation order) and is run but not scored. How the drag feels — no
  clicks, silence on hold — is the person's, PB-14 in `docs/manual-checks.md`.
