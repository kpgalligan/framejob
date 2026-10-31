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

AU-40…AU-49 are AP4's (the gate/expander and the de-esser; survey A5, A6), recorded before its
code.

- **AU-40 — The gate stage.** `AudioGateStage` follows the compressor's linked peak follower (the
  max of `|x|` over the channels, falling at its 10 ms floor). Per sample: a level at or above the
  threshold sets the hold counter to round(hold·fs) and the target to 0; else a counter above 0
  is decremented and the target is 0; else the target is min(range, (thrDB −
  20·log10(max(level, silence floor)))·(ratio − 1)). The reduction moves `reduction += (target −
  reduction)·c`, c the attack coefficient when the target is below the reduction (opening) and
  the release coefficient otherwise (closing), both one-pole from `AudioEnvelope.coefficient`;
  the gain `AudioDSP.gain(fromDecibels: −reduction)` multiplies every channel by `vDSP_vmul`.
  Scalar recursion and element-wise vDSP only, buffers allocated in `init`, chunks at capacity as
  the compressor's. Fresh state is OPEN (reduction 0, follower 0, counter 0); `reset()` restores
  it, and the tap keeps resetting at StartOfStream (S1: the silent pre-roll would otherwise start
  the preview closed, −56 dBFS off the export). Nil settings reset the stage and touch no sample.
  The follower and the coefficients are the compressor's, moved into `AudioEnvelope` and
  `AudioPeakFollower` with their exact Float arithmetic, so the compressor's output is
  byte-identical to before.
- **AU-41 — The reference level.** L is the clip's `ClipLoudness` reading — the Volume section's
  Loudness figure: gated BS.1770-4 integrated loudness over the clip's played window (its plan
  audio segments of its first media in 10 ms steps, AU-12), in the export's layout (mono counted
  twice, +3.01 LU) through pan · fold · pick (AU-11, AU-35), pre-fader (no volume, fades, ducks,
  EQ, hum, noise reduction or isolation), which matches where the tap sits. Both stages'
  thresholds are dBFS on their follower, L + `threshold_db`; a trim or a pan change moves L and
  the threshold with it. On the owner's recording L = −41.67 LUFS, so the gate's default opens at
  −51.67 dBFS, between the pause floor (−64.3 dBFS, the p10 of 50 ms RMS) and speech (−43.2, the
  p90); the defaults are not measured beyond that, and the manual check judges them.
- **AU-42 — No level.** Pending (no loudness file yet, or no cache folder published) and
  unmeasurable (no reading: under 0.4 s played, or silent) leave the stage's settings nil: the
  clip plays ungated and un-de-essed, and the section's status says why. A pending answer is
  never memoised. When a loudness file lands or is withdrawn, `AudioDynamicsLevels` drops that
  media's memo and posts `.reversedMediaDidChange` for each open document with a gate or
  de-esser on that media, so the editor rebuilds with no edit. An export whose pending levels
  hold a clip that plays waits for them (polling every 0.1 s, never on main) up to 300 s, then
  fails `loudnessUnmeasured` naming the clip ("Clip N's loudness has not been measured yet, so
  its gate and de-esser have no threshold. Wait for the Volume section to show its loudness, then
  export again."); a cancel fails `.cancelled`. An unmeasurable clip exports ungated, as the
  preview plays it.
- **AU-43 — `audio.gate`.** `{threshold_db −40…0 (−10), ratio 1…20 (4), range_db 1…80 (20),
  attack 0…60 000 ticks (600, 1 ms), hold 0…300 000 (30 000, 50 ms), release 600…1 200 000
  (60 000, 100 ms)}`, threshold in dB re L; written only when set, `{}` stores the defaults,
  `null` clears; refused by name (`audio.gate.<field>`) and clamped in an action's end.
- **AU-44 — The de-esser is split-band, through a Linkwitz–Riley crossover.** Detection: the
  sidechain is a 24 dB/octave Butterworth RBJ high-pass at `frequency` (two Double TDF-II
  sections, Q 0.541 and 1.307, per channel), followed by a linked follower (10 ms fall); the
  target is min(range, 20·log10(level) − thrDB) above the threshold (∞:1, never deeper than the
  range) and 0 below it; attack 1 ms, release 60 ms; g = `AudioDSP.gain(fromDecibels:
  −reduction)`. Reduction: a 4th-order Linkwitz–Riley split at `frequency` — low two
  `AudioEQDesign.lowPass(f, q: 1/√2)` sections, band two `highPass(f, q: 1/√2)` sections, per
  channel, Double TDF-II — and out = low + g·band. LR4's outputs are in phase at every frequency
  and sum to a 2nd-order allpass, so |out/x| = 1 − (1 − g)·|band| lies in [g, 1]: no frequency
  is ever boosted. `x − (1 − g)·band` is not taken: a 4th-order Butterworth high-pass is 180°
  out at its cut, so subtracting it boosts (+2.6 dB at 6 kHz for a 6 dB range). At g = 1 the
  output is x's allpass — flat in magnitude, shifted in phase, not x's bytes. At the cut |band|
  = 0.5, so a 6 dB range takes 2.5 dB there, and the full range is reached about an octave
  above. All six sections are redesigned at the cut when the frequency changes, their state
  kept; a frequency at or above 0.49·fs is not designed and the stage passes x untouched.
  Split-band, not wide-band: wide-band turns the whole voice down on every "s" (lisping; the
  survey's flag). Nil settings reset the stage and touch nothing.
- **AU-45 — `audio.de_esser`.** `{frequency 2 000…12 000 Hz (6 000), threshold_db −30…+20 (0),
  range_db 1…24 (6)}`, written as AU-43's. The threshold is relative to L too: an absolute
  default would never act on a quiet recording (the survey's point about the compressor's
  −18 dB); 0 dB re L sits above ordinary speech's high band (median −22.4 dB under the voice
  band) and under sibilant peaks (p95 −0.2 dB).
- **AU-46 — Format 33, base-only, no op.** No migration step, the keys after `channels`;
  base-only (`structural(audio:)`), an action's end clamped and ignored; a nest clip's gate and
  de-esser reach nothing, as its compressor; `paste_attributes` carries them through
  `check_audio`; no op, tool, FFI or op-table change: `set_audio` takes the two keys.
- **AU-47 — The order (AU-54 unchanged).** … noise reduction → gate → de-esser → compressor →
  fold → pan → nest fold → limiter. Both stages read the clip's settings at the compressor's
  lookup, never the head's. Neither adds latency; both are built for every active track.
- **AU-48 — The sections, after Noise Reduction and before Compressor.** Gate: a "Gate pauses"
  check (on writes the defaults); Threshold (dB re loudness, −40…0, quick −20, −15, −10, −6),
  Ratio (1…20, quick 2, 4, 10, 20), Range (dB 1…80, quick 10, 20, 40, 80), Attack (ms 0…100,
  quick 1, 5, 10), Hold (ms 0…500, quick 0, 50, 100, 200), Release (ms 1…2000, quick 50, 100,
  250, 500); a Status read-out ("Opens above −51.7 dBFS", "Waits for its loudness", "Not
  gating: too short", "… too quiet", "… no sound") and a Loudness read-out ("−41.7 LUFS",
  "measuring…", "—") — two rows, because one read-out holds about 27 characters and "Opens
  above −51.7 dBFS · loudness −41.7 LUFS" was cut off in the capture; the summary "−10 dB" or
  "off". De-esser: a "Reduce sibilance" check; Frequency (Hz 2000…12000, quick 4000, 5000,
  6000, 8000), Threshold (dB re loudness −30…+20, quick −6, −3, 0, 3), Range (dB 1…24, quick 3,
  6, 10), Status ("Acts above …", "Not de-essing: …") and Loudness; the summary "6.0 kHz" or
  "off". Thresholds are whole dB in their fields. Each control writes a whole group, the
  limiter's pattern; Reset clears.
- **AU-49 — The proof.** `audio_ap4_probe.py`'s rows D1–D11 over the stages, the shared
  follower, the order and the levels, with mutants M1–M9 and M11 each killed by its named row and
  M10 (the `check_gate` call dropped) by hand against `core/tests/audio_dynamics.rs`;
  `audio_ap4_proof.py`'s rows P1–P7 over MCP and exports; whether the defaults chatter, pump or
  lisp on the owner's voice is a manual check.

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

AU-70…AU-78 are AP7's (live loudness and true-peak metering; survey A8), recorded before its
code.

- **AU-70 — The meter reads the TRUE mix, rebuilt from the taps off the audio thread.** Each tap,
  after its chain, copies its block (pre-envelope) and first frame
  (`round(time.value·rate/time.timescale)`; a buffer whose time is not numeric, the player's
  silent pre-roll, is skipped) into its sink's `MixRing`, a single-producer ring that takes no
  lock and allocates nothing. The consumer runs on the meter's existing 30 Hz main-thread timer
  (no new `DispatchQueue` seam): it drains every ring, sums by frame index each track ×
  `MediaPeaks.envelope(ramps, at: frame·600000/rate)` — a mono track at unity in both channels, a
  track's first two channels only — and feeds the stereo sum to a `LoudnessMeter` at the taps'
  rate. Frame f is summed once every track has delivered past it, except a track not sounding at
  f (f's tick outside every one of its own `sounding` spans — a gap between clips as well as past
  the last span; #65: the tap delivers nothing there) or more than `stallLag` (0.5 s) behind the
  leading track; such a track is silence at f and is not waited on, and a frame it does deliver
  after the sum has passed it is dropped. Frames a track delivers are summed as delivered. When
  no track sounds at the reached frame the sum fills silence up to what has been delivered, and
  with nothing delivered past it, it waits; that fill is never a `jump`, so a gap on one track or
  on every track neither holds the sum up nor resets it, and a seek across a stretch where
  nothing sounds is read as playing through it (its silence is below the absolute gate and does
  not move I). Tracks reporting different rates are not measured. AVFoundation's ≤ 25 ms slew at
  a volume step is not modelled (S3: ≤ 0.0067 LU).
- **AU-71 — What it shows: momentary, short-term, integrated and the true-peak maximum.**
  Momentary is the last completed 400 ms block, short-term the last 3 s (thirty 100 ms
  sub-blocks), integrated BS.1770-4's two gates over everything measured since the last reset,
  and the true peak the maximum since the reset (Annex 2 at 4×, which S1 found over-reads speech
  by 0.14 dB). All four are `Loudness.swift`'s `LoudnessMeter`, made rate-generic by `KWeighting`
  (moved into `Loudness.swift`): Tables 1–2 exactly at 48 kHz, libebur128's derivation at any
  other rate in 8–192 kHz, the Annex 2 FIR at 4× the taps' rate. The export's 48 kHz arithmetic
  is unchanged.
- **AU-72 — It measures only at ×1, and says when it resets.** At any other rate the chunks are
  discarded, M and S read "—", and I and TP hold. It resets on the panel's Reset and
  `loudness_meter {reset}` (`manual`); on its own when a chunk starts more than `behindTolerance`
  (1.0 s) before the frame the sum reached, or more than `aheadTolerance` (0.1 s) after it with
  some track sounding somewhere in between (`jump`: a seek, a loop's wrap, a play from elsewhere);
  and on a ring overrun (`overrun`). The rule is asked only of a chunk that MOVES its track —
  continues (within the same tolerances) neither what the track delivered last nor what it
  delivered to the measurement — once the chunks before it are summed. Measured in the player:
  after a seek or a play from elsewhere each track first hands over a buffer or two of the old
  position, not in step across tracks, so on a jump each track keeps what follows its own last
  move, and a track that has not moved yet drops what continues its old stream until it moves (for
  at most `stallLag` of frames); a move with no measurement running starts the measurement there
  the same way, uncounted. A chunk within the tolerances continues the measurement with frames
  before the reached frame dropped, so pause and continue and an edit's rebuild (new sinks, the
  restore seek landing behind) neither reset nor count a frame twice. A change of the taps' rate
  restarts the measurement as a `jump`. **A stop** (rate 0, `stopMetering` → `stop()`) drains and
  drops what is still in the rings or pending, never summed; what the sum already reached stays
  measured, and since the player renders ahead of the playhead that can be audio the stop left
  unheard (0.38 s in L1's run). M, S, I and TP hold their last ×1 values, `measuring` goes false
  and the panel is told. "—" for M and S is only while playing at another rate. The meter timer
  runs in the run loop's `.common` modes, so menu tracking and live resize drain the rings and do
  not overrun them. A new window starts empty.
- **AU-73 — Pre-master.** The preview has no master stage (S3; the master limiter AP2's second part
  adds is the export's alone, AU-22), so the meter reads the mix as the preview plays it — each
  clip's own chain, its clip limiter (AU-20) included, since the capture follows the chain — before
  the export's loudness setting, and the panel's footer says so. Running a master chain on the
  rebuilt sum is a later phase's decision.
- **AU-74 — The timeline bar's bars read the mix.** While the consumer is measuring (it summed
  frames within `liveWindow`, 0.15 s), `Playback.meterReading()` answers the mix's sample peak
  and RMS per channel over its last 100 ms; otherwise `LevelMeterTrack.mix` as before (#65
  intact). This removes S3's up-to-3.85 dB over-read at ×1. The view's ballistics and
  `LevelMeter.shared`'s claim rule are unchanged.
- **AU-75 — Where it shows: View ▸ Loudness Meter.** ⌃⌘L, a checkmark, always enabled, after
  Scopes: a 132 pt column at the preview pane's right edge, left of Scopes, full height, zero wide
  and hidden when off (its width constraint at priority 999, as Scopes'). Per window; nothing
  persists (GR-5's rule): no `UserDefaults` key.
- **AU-76 — The column.** A 1 pt `DS.border` leading edge on `DS.chromeBackground`. Header:
  "Loudness" (`DS.sans(11, .semibold)`, `DS.textStrong`) and a `GhostButton`
  (`arrow.counterclockwise`, tooltip "Reset", action `resetLoudnessMeter:`). Body: a −48…0 LUFS
  scale, linear, ticks every 6 LU labelled in `DS.mono(9)` `DS.textFaint`; two bars, M and S,
  `DS.meterFill` on `DS.meterTrough`; the target as a 1 pt `DS.accent` line at
  `NormalizeChoice.targetLUFS` (read at draw; −16 by default, AU-4, AU-15). Readouts: Momentary,
  Short-term, Integrated and True peak max in `DS.sans(10)` `DS.textMuted`, values in
  `DS.mono(11)` `DS.textStrong`, one decimal, U+2212, "LUFS"/"dBTP", "—" when there is none and
  "−∞" for digital silence; the true peak in `DS.meterClip` above −1 dBTP. Footer, `DS.sans(10)`
  `DS.textFaint`, wrapping: "The mix as the preview plays it, before the export's loudness
  setting." (at ×1, paused or stopped) or, while playing at another rate, "Measured only at
  normal speed." No animation: it redraws when the reading changes. Accessibility ids
  `loudness.panel|momentary|short|integrated|truepeak|reset`.
- **AU-77 — MCP: the dev tool `loudness_meter` only.** Reading the meter needs a playing preview,
  which only the dev tool `play_preview` starts; an agent's loudness answers are the export's
  report and AP1's per-clip readout. `loudness_meter {project?, reset?}` answers `{measuring,
  rate, momentary_lufs, short_term_lufs, integrated_lufs, true_peak_dbtp, from_frame, to_frame,
  sample_rate, resets, last_reset}`. The View item and Reset are view state, unmirrored (§7.9's
  Preview Quality exemption).
- **AU-78 — The proof.** `audio_ap7_proof.py`: the probe's rows T1–T16 (EBU Tech 3341 cases 1–5, 9
  and 12, true-peak sines, 44.1 kHz, the mix against a reference sum, continuity, the stall,
  overrun, rate, the bars, gaps) and eleven mutants, each anchoring a distinct branch AU-70, AU-72
  or AU-74 adds (the sum, the continuity rules, the rate gate, the bars), killed by its named row;
  L1–L4 over MCP against an export; SE-30 for what only a person can confirm.

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

AU-140…AU-149 are AP14's (voice effects; survey B10, E8 of `designs/adr/effects-survey.md`,
#123), recorded before its code.

- **AU-140 — `audio.voice` is `{kind, amount, pitch}`, one per clip, absent or null off, format
  34.** (32 went to AP3, 33 to AP4.) `kind` is one of sixteen, in E8's order and groups — voice: `pitch`,
  `high`, `deep`, `robot`; tone: `bass`, `treble`, `bright`, `telephone`, `radio`; character:
  `lofi`, `distorted`; space: `echo`, `room`, `hall`, `plate`, `cathedral` — with no default, as
  `video.look`'s. `amount` is 0…1, default 1. `pitch` is −12…12 semitones and optional: absent
  means the kind's own (0 for `pitch`, +5 for `high`, −5 for `deep`), and only those three read
  it. The field is written only when set, `pitch` only when set, so every other project writes
  the text it did and there is no migration step. `set_audio {voice: null}` clears it; a voice
  patch merges key by key, so a `kind` alone keeps a stored `pitch` and `pitch: null` drops it
  back to the kind's own; a patch with no `kind` over no voice is refused in serde's sentence.
  `set_audio` refuses `amount` or `pitch` out of range in `in_range`'s sentence
  (`audio.voice.amount must be between 0 and 1, not 1.5`), and an action end's values are
  clamped (amount to 0…1, falling back to 1; pitch to −12…12, falling back to 0). Base-only
  (AP8 animates), carried by Paste Attributes with the audio group, and nothing on a nest clip.
- **AU-141 — Each kind is a fixed chain of Apple units, scaled by `amount`.** Amount `a` scales
  every gain, wet mix, shift and band edge, an edge moving geometrically, `geo(x0, x1) =
  x0·(x1/x0)^a`, from where it does nothing (20 Hz, 20 kHz) at a = 0. The units run TimePitch →
  EQ → Distortion → Delay → Reverb:

  | Kind | Chain | m_k (dB) |
  |---|---|---|
  | pitch / high / deep | TimePitch at `100·s·a` cents (rate 1, overlap 8), s the semitones; high adds an EQ high-pass at `geo(20,150)` and a high shelf at 4 kHz, +3a dB; deep adds a low shelf at 150 Hz, +4a, and a high shelf at 5 kHz, −3a | 2.01 / 1.67 / 1.12 |
  | robot | Distortion with all 16 parameters set by address: ring mod 60 Hz on both oscillators, balance 50, ring mix 100; delay, decimation and polynomial mixes 0; linear term 1; soft-clip gain −6 dB; final mix 100a. Then Delay 8 ms, feedback 50, low-pass 15 kHz, wet 30a | 8.70 |
  | bass | Low shelf at 200 Hz, +10a dB | −3.88 |
  | treble | High shelf at 3 kHz, +10a dB | −1.67 |
  | bright | Parametric at 3 kHz, 1 octave, +4a, and a high shelf at 8 kHz, +6a | −0.63 |
  | telephone | High-pass ×2 at `geo(20,300)` and low-pass ×2 at `geo(20000,3400)` | 2.64 |
  | radio | High-pass ×2 at `geo(20,400)` and low-pass ×2 at `geo(20000,4500)`, then Distortion `speechRadioTower`, wet 40a | −2.95 |
  | lofi | High-pass at `geo(20,150)` and low-pass at `geo(20000,6000)`, then Distortion `multiDecimated2`, wet 100a | −3.08 |
  | distorted | Distortion `multiDistortedCubed`, wet 100a | 8.89 |
  | echo | Delay 0.25 s, feedback 40, low-pass 6 kHz, wet 50a | 0.34 |
  | room / hall / plate / cathedral | Reverb `mediumRoom` 35a / `largeHall` 40a / `plate` 35a / `cathedral` 45a | 1.47 / 1.56 / 1.20 / 2.89 |

  TimePitch is left out when its cents round to 0, and a unit is never put in at wet 0. A voice
  is INERT — it renders nothing and plays dry — when `a = 0` or its chain is empty (the kind
  `pitch` at 0 cents). Makeup gain is `10^(m_k·a/20)`, `m_k` a constant per kind measured at
  `a = 1` on `samples/Rode-usb-mic.m4a` (`voice_proof.py --measure`: the dry recording's gated
  BS.1770 loudness less the render's, with the kind's own pitch; the kind `pitch` at +7), so a
  voice keeps the clip's loudness. Both are read as I3's export reads them — the fader at ×4, the
  mono recording in both channels — because the recording is −44.7 LUFS and the −70 LUFS gate
  makes integrated loudness non-linear in level there: read at its own level, robot, telephone
  and distorted measured 7.90, 2.18 and 5.96 dB, and distorted then exported 3.0 LU low. The run
  (2026-10-30): dry −29.63 LUFS, every kind within 0.01 LU of it once the table was in. Every number is Frame Job's own (the Concat rule).
  `VoiceChain.version` names this table and AU-142's contract.
- **AU-142 — The render contract is E8's, with the chain's latency discarded.** 48 kHz STEREO
  connections (reverb given mono aborts the process) with an `AVAudioPlayerNode` playing an input
  file; schedule → `start()` → `play()`; every `renderOffline` call asks for 4,096 frames (the
  output is byte-identical only at a fixed call size); every preset set through
  `auAudioUnit.currentPreset` before start (`loadFactoryPreset` before start is ignored, after it
  lands about 43 ms late), and then only `wetDryMix` over it; every unit that takes no preset has
  every parameter set and clamped to the range its parameter tree publishes. Output is float CAF
  through `RampCAFWriter`. `L`, the sum over the chain's units of `round(auAudioUnit.latency ×
  48 000)` read after `start()`, is discarded as `IsolationRenderer` discards its 4440: the engine
  renders `L + (endFrame − firstFrame)` frames (the player gives silence once the input ends), the
  first `L` are dropped, and exactly the window's length is written, so kept frame 0 is the
  window's first frame and the tail is cut at the clip's end. The window renders cold, with no
  preroll. The input file is always stereo (a mono source in both channels); the output has the
  source's channel count, a mono output `(L+R)/2`. Makeup is applied in float before the write.
- **AU-143 — The order (amends AU-54): isolation → voice → channels → high-pass/EQ → hum → noise
  reduction → gate → de-esser → compressor → limiter → fader.** The voice render's input is the
  dry window when the clip does not isolate; when it does (amount `i`), it is `dry + i·(iso −
  dry)`, built from the isolated render, so the voice request exists only once that file is on
  disk, and a change to the Isolation amount re-renders the voice. In the tap, a ready voiced
  segment REPLACES the samples (a span at amount 1) instead of its isolation crossfade.
- **AU-144 — The cache.** `cache/voiced/<media>-<16 hex>.caf`, FNV-1a 64 (as `IsolationCache.name`)
  over the media file's path, size and modification second, `VoiceChain.version`, the reversal,
  the window, the kind, amount and semitones (never a `pitch` a kind does not read), and the
  isolation amount with the isolated file's name (or `none`). It renders as the `.voice` job on
  `RampAudioRenders` — its owners, its landing under the ledger, pruning on settle, a failure once
  per launch, `-RCDevRampRenderHold` — and every settle wants again, so a voice waiting for its
  isolation is wanted when that isolation lands. Deviations from E8, both AP5's: no marker file
  (the ledger's landing rename is the commit), and pruning on settle rather than sweeping on open.
- **AU-145 — Which segments are voiced: AU-55's rule.** ×1 forward segments and reversed segments
  whose copy is ready (`IsolationCache.isolatable`); a time-scaled, ramped or freeze segment
  plays without the effect. A pending render plays without its effect — with isolation, if that
  render is ready. A tap at a rate other than 48 kHz passes dry. Deviation from E8: the builder
  does not substitute an asset track; the voiced render is read into memory and played by AP5's
  pass.
- **AU-146 — The section.** "Voice Effect", in the Sound tab after Voice Isolation: an Effect popup
  — "None", then the sixteen in E8's order titled "Voice: Pitch" … "Space: Cathedral" (the groups
  in the titles, because `OptionControls.swift` is Rasterize's and not forked); choosing a kind
  writes `{kind, amount: current ?? 1, pitch: null}`, so every kind starts at its own pitch, and
  None writes null. An Amount row 0–100 % (quick 25, 50, 100); a Pitch row −12…12 st at one
  decimal (quick −12, −5, 0, 5, 12), enabled only for the kinds that read it, showing `pitch ??`
  the kind's own; a Status read-out in Voice Isolation's words. Deviation from E8: no Clip ▸
  Voice ▸ menu in this phase (filed).
- **AU-147 — Export and agents.** An export wants and waits for its voice renders after its ramp
  and isolation renders ("Preparing…"), and fails `voiceFailed` naming the clip when one cannot be
  rendered. An agent uses `set_audio {voice}`: no new op, tool or FFI, and the render's status is
  not in `get_project`.
- **AU-148 — Limits.** Tails end with the clip. One effect per clip. Waveforms, Normalize's
  reading and Remove Silences read the dry media. A split take's windows start cold. In a stereo
  source a reverb or a delay mixes the channels, so AP3's channel pick chooses from the effected
  pair. How each kind sounds is a person's (SE-32).
- **AU-149 — The proof.** `voice_proof.py`: probe rows V1–V11 over `app/Sources`, `--measure` for
  `m_k`, instance rows I0, K1–K16 (one per kind, against what E0 measured) and I2–I11, and eleven
  mutants — one per AU-14x decision plus latency-kept for AU-142's discard — each killed by its
  named row; manual check SE-32.
