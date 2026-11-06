# Spec §11 — decisions: Audio (the owner's audio pass, from 2026-10-30)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The owner's pass over a clip's sound, begun 2026-10-30 to turn a desktop USB microphone's
recording into usable audio for a video. Its IDs are the AU- series. Each was recorded before
its code.

The road map that made AU-2…AU-156 is closed (2026-10-31): its condensed record is
`designs/adr/audio.md`, the original `archive/audio.md` (AP0 the plan and spikes S1–S4, then one
record per phase, in the order they landed), and the survey it came from
`archive/audio-survey.md`.

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

AU-2…AU-4 open road map "audio" (`archive/audio.md`, from `archive/audio-survey.md`'s tiers A
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
  **Amended by CJ-1** (2026-11-01): §1's clause keeping third-party Audio Unit hosting out is
  lifted. The decision stands as current design: none is hosted, and a road map that would host one
  amends this entry first.
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
spike S4 (`archive/audio.md`'s AP0 record).

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

AU-27…AU-29 are AP2's second part (the export's float decode and #86, the master limiter,
`audio_bits`), recorded before its code from AP0's spikes S1 and S3 and part 1's record.

- **AU-27 — The master.** Every export with sound (every row but GIF and APNG; image sequences
  have none) reads the mix as 32-bit float (`ExportAudioMaster.floatMixSettings`; no 16-bit
  decode is left), applies the export gain, then a master limiter — `AudioLimiterStage` exactly
  as AU-20 (the Kaiser β 10 64-tap and Annex 2 detector, the 159-sample hold, the box mean, one
  gain for both channels) — with its release 100 ms, fixed, and its ceiling the export's
  `peak_dbtp` (−20…0). It is **always on, at −1 dBTP by default** (AU-4's ceiling), for
  normalised and un-normalised exports alike; there is no off switch, and 0 dBTP is the loosest.
  Its 158 frames are compensated in the file: the head dropped and the tail flushed, so output
  frame k is input frame k, and a mix under the ceiling is written exactly as the float mix
  rounded. The master places its input by stamp before the limiter — a hole in the reader's
  stamps fed as zeros, an overlap's covered head cut, as CX-15 (5)'s `align` — so its
  count-based output stamps are the timeline's and the sound stays placed at its stamps. A
  ceiling alone is legal (amends spec §7.8's pairing rule: `peak_dbtp` without `loudness_lufs`
  is the master's ceiling, accepted and echoed). Nothing clips any more, so the report's
  "clipped" summary (`mixClipped`) is retired. It holds AU-22's accepted cases (an action above
  base, a nest clip's volume above 1, #87's slew at a cut, two overlapping limited clips). The
  preview has no master (S3); the loudness meter's footer says it reads the mix before the
  export's loudness and master limiter (amends AU-73's sentence).
- **AU-28 — The gain under the master.** Pass 1 also records 10 ms steps
  (`StepLoudnessMeter`: per 480-frame step the summed K-weighted mean square and the true peak);
  the gain is `AudioLimiterModel.gain` over them at the master's ceiling and 100 ms, capped at
  +40 dB, rounded to the NEAREST 0.01 dB (the cap's round-down rule is gone: the limiter holds
  the ceiling). Under 40 steps, or with no float read: the unlimited `target − integrated` (0
  with no loudness). The report: `integrated_lufs` the model's figure at that gain (also with no
  target), `true_peak_dbtp` min(measured + gain, ceiling), `limited_db` max(0, measured + gain −
  ceiling), `capped_by_gain` when the +40 dB cap decided; `capped_by_peak` is removed. A
  non-finite measured true peak keeps the old handling: the model is not run, the gain is 0,
  `integrated_lufs` is the measured figure, `true_peak_dbtp` passes through unclamped (the
  summary still says "Silent" for −∞ and "Peak not measurable (a non-finite sample in the mix)"
  for +∞), and `limited_db` is 0.
- **AU-29 — `audio_bits` and rounding.** 16 or 24 on `audio_wav` and `audio_aiff` only (ProRes
  keeps 16-bit), refused by name elsewhere, 16 by default; those preset rows list `[16, 24]`.
  24-bit is packed signed, in the container's byte order chosen by the writer as 16-bit is.
  Both depths are rounded to nearest once from float (`vDSP_vfixr16`, `vDSP_vfixr32`), clipped
  first, with **no dither** at either depth: 24-bit's rounding sits at −144 dBFS, and 16-bit
  follows the picture's rule (output not dithered; #375's part 2 dropped by the owner) and keeps
  every export deterministic. The Export sheet's Bit depth popup (16-bit, 24-bit) sits after
  Quality, live only on those rows and remembered in `ExportChoice`; the `export` tool takes
  `audio_bits`.

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

AU-60…AU-65 are AP6's first part (Enhance Voice; survey B1), recorded before its code. AP6 is
built in three parts, by size, as AP2 was: the leveller (B3) is the second, with AU-66 and AU-67;
Enhance at record time (B8) the third, with AU-68 and AU-69.

- **AU-60 — Enhance Voice is a composite, not an op, and owns eight keys.** Clip ▸ Enhance Voice,
  a button in the Volume section under Normalize's, and `enhance_voice {clips, target_lufs?}`
  measure each clip (AU-61) and write ORDINARY settings a person can see and change, by the rules
  of AU-62: `eq.high_pass` (with `bypass: false`, the rest of the EQ kept), `isolation`,
  `noise_reduction`, `gate`, `de_esser`, `compressor`, `limiter` and `volume`, each overwritten.
  Every other key of the audio group (hum, channels, pan, mono, fades, duck, mute, keep pitch, the
  EQ's other slots) is left as it is. It writes BASE props even inside an action (Normalize's
  reason), as one `set_audio` per clip — the settings differ per clip — committed as ONE undo
  step named "Enhance Voice". The target is `NormalizeChoice.targetLUFS` for the button and the
  menu (the Normalize row's Target field) and `target_lufs` for the tool (−50…−5, default −16,
  refused by name outside it, never clamped). Each clip of a selection is enhanced from its own
  measurements; a clip that cannot be is skipped by name and the rest are still enhanced:
  Normalize's own refusals (`admit`: not a clip, a nest, no audio segment, no audio props), its
  loudness cache not yet written, under 0.4 s played, gated out (under −70 LUFS), its speech not
  yet detected ("its speech has not been detected yet"), and under 1 s of speech; then, from the
  processed measurement (AU-64), its reversed copy still being made ("its reversed copy is still
  being made."), its processing failing to render ("its processing could not be measured: …")
  and its processed sound gated out ("is under −70 LUFS after its processing."). It is offered
  where Normalize is (`AudioNormalize.canOffer`). **The doors** (amended 2026-10-31, the owner's
  answer): the button and the menu share one body, `AudioMeasureDoor`, which reads, measures
  under the Measuring Sound sheet (AU-65) and commits only when the document's project and scope
  are still the ones it read — otherwise it beeps and puts "the project changed while its sound
  was being measured, so nothing changed. Choose Enhance Voice again." at the inspector's foot.
  The tool reads and commits on main and waits for the measurement off it, with the same test and
  "… Call enhance_voice again." With nothing to enhance, or no window, the button and the menu
  beep and the tool answers "Nothing could be enhanced." with every reason. No core, FFI, op,
  format or `UserDefaults` change.
- **AU-61 — What it measures, all pre-chain.** L and the true peak are the clip's `ClipLoudness`
  reading (AU-41's: the played window, the export's layout, pan · fold · pick, pre-fader), and the
  steps are that reading's 10 ms played steps. The speech spans are the media's saved
  `media.speech` when it has them (AU-111), else `DuckSpeech.spans` of its Silero VAD cache (the
  spans Duck by Speech would save; Remove Silences' threshold); a step is SPEECH when its source
  midpoint (`ClipLoudness.Reading.stepSources`, forward-file ticks after speed, a ramp's map and
  reversal) lies in a span, else a PAUSE. With ℓ(e) = `ClipLoudness.loudness(e)` of a step's
  energy: the FLOOR is the median of ℓ over the pause steps (−∞ allowed), measured only with at
  least 0.5 s (50 steps) of pause; the PAUSE PEAK the median of 20·log10 of the pause steps' true
  peaks (dBFS, nil with the floor); the SPEECH PEAK the median of the same over the speech steps;
  the SIBILANT SHARE the share of speech steps whose high band (`stepHighs`, AU-63) reads
  ℓ ≥ L − 10; `isolatable` that every segment of the clip is `IsolationCache.isolatable`. A clip
  needs at least 1 s (100 steps) of speech. Nothing measured depends on a key Enhance writes, so a
  second press measures the same and writes the same: the core answers an identity ("made no
  change").
- **AU-62 — The rules.** With F = floor − L:
  - **High-pass, always:** the EQ's Rumble Cut (`EqPreset.rumbleCut`, 80 Hz at 24 dB/octave)
    applied to the clip's own EQ, or to an empty one.
  - **Noisy pauses, F > −45 dB:** voice isolation at `IsolationCache.defaultAmount` (0.8) and
    noise reduction 0 when the clip is isolatable, else noise reduction 0.5 and isolation 0; and
    the gate at its defaults with `threshold_db = clamp(round(pause peak + 10 − L), −40, −6)` —
    10 dB above the pauses' median true peak, in the gate detector's own units (its peak
    follower, `AudioGateStage`), re L. F decides only WHETHER to clean and gate. **Quiet pauses,
    F ≤ −45 (−∞ too):** isolation 0, noise reduction 0, gate off. **No floor** (under 0.5 s of
    pause): those three keys are left out of the edit, and the row says why.
  - **Sibilance:** the de-esser at its defaults when the sibilant share is at least 5 %, else off.
  - **Compressor, always:** threshold `clamp(round(speech peak), −60, 0)` dBFS, ratio, attack and
    release at their defaults (3:1, 10 ms, 200 ms), and makeup `AudioDynamicsModel.makeupDB`
    (AU-64): the loudness the compression takes, given back, so the fader keeps its ×32 headroom
    (the owner's recording needs ×23.4 with the limiter alone, AP2's record).
  - **Limiter, always:** the clip's own kept with its ceiling at most −1 dBTP, else the default.
  - **Volume and limiter:** by AU-64's processed solve, at the target, with the limiter above
    (amended 2026-10-31).
  Each rule's sentence goes in the answer's `reasons`: the measurement, the threshold, what it set.
- **AU-63 — The loudness cache gains the high band (amends AU-10).** `loudnessVersion` 2; each
  record appends `h`: mono `z, tp, h`, stereo `zL, zR, zLR, tpL, tpR, hL, hR, hLR` (width 3 and
  8). `h` is the mean over the block's frames of x_hp² (`hLR` of xL_hp·xR_hp, which alone with
  `zLR` may be negative), x_hp the raw samples through two `AudioEQDesign.highPass(6000, q:
  butterworthQ(sections: 2, index: 0|1))` sections in Double — the de-esser's sidechain at its
  default frequency — their state carried across buffers; `h` is 0 where 6 kHz is at or above
  0.49·fs. A version-1 marker reads as absent and the cache is made again (no migration). A
  reading's `stepHighs` read `h` through the same 2×2 matrix as z (a mono record doubled); z, tp
  and every figure built on them are unchanged.
- **AU-64 — The volume is solved on the processed sound (amends AU-24 and AU-26; rewritten
  2026-10-31 by the owner's answer).** The first form ran the clip's compressor at block rate over
  the cache's steps (`AudioDynamicsModel`) and left the gate, de-esser, isolation and noise
  reduction out. Measured on the owner's recording, Enhance's export landed at −13.95 LUFS for a
  −16 target, and each cleaning stage alone moved the export: the gate +2.4 LU, isolation +2.6
  LU, the EQ −0.7 LU. The cause is that cleaning the pauses changes which blocks BS.1770's
  relative gate counts, which no per-stage model of the loudness alone can see. So the clip is
  measured as it will play. The owner chose this over modelling the gate, knowing a press takes
  seconds on a long clip.
  (a) **Which clips render.** `ProcessedLoudness.needsRender` is true when the clip's base audio
  has an `eq` with an active slot and not bypassed, `hum`, `isolation` > 0, `noise_reduction` >
  0, a `gate`, a `de_esser`, a `compressor` or a voice that is not inert. Pan, mono, channels
  and the limiter are already counted or modelled by the cache reading (AU-11, AU-24), so a clip
  with only those plans off the cache, byte for byte as before. Enhance always renders.
  (b) **The trial.** On main, `document.project` with one `set_audio {clips: [c], patch:
  chain}` scoped to the open nest, then `.scoped(nest)`. The first render's (R0) chain is
  Normalize's `{limiter: null}`, or Enhance's chosen patch with `limiter: null`.
  (c) **What is read.** The trial's plan with only the clip's audio segments (an emptied track
  dropped), each track's `ramps` and each segment's `track_pans` removed — pre-fader, AU-11's
  convention: no volume, fades, ducks, mute, track volume or pan — no video tracks or ducks, and
  one instruction over the plan. The read is the span of the clip's segments. A render puts
  back ONE constant ramp at the trial clip's base volume, the export's fader and nothing else of
  the envelope: R0's trial is at volume 1, so R0 is pre-fader, and a verify render's loudness is
  R as it stands. Measured on the owner's recording (AP6's record), a gated clip under a limiter
  read with no ramp at all landed 0.19–0.25 LU above its own export, and with the ramp to
  0.000 LU of it; an EQ or a compressor under the limiter agreed either way, and a gate with no
  limiter exports exactly 6.021 dB louder at volume 2 than at 1. The cause inside the mix was not
  found.
  (d) **The render.** On `ProcessedLoudness.queue`, under a fresh `RecipeSource` key holding the
  trial, with the document's reverse resolution published for it: the export's own waits
  (`Exporter.withOfflineAudio`: levels, then ramp, isolation and voice renders, wanted under the
  key), `CompositionBuilder.build`, and one `AVAssetReaderAudioMixOutput` of float stereo
  through the built mix, placed by stamp (gaps as zeros) into a `StepLoudnessMeter`. The key is
  dropped afterwards; its render wants are kept until the press finishes, so the verify renders
  find the same files. Speed, ramps and reversal are measured on what plays, because the
  composition is the export's. A reversed clip still pending, a failed wait and a gated-out
  result are skips (AU-60).
  (e) **The solve.** R0's steps make a reading (its integrated loudness, its largest step peak);
  AU-24's plan gives the volume v and the limiter. With no limiter the result is R0 + 20·log10 v,
  one render. With one, a verify render of the chain with `{volume: v, limiter}` (the stage told
  v, AU-22) read through the fader at v gives R; while |R − T| > 0.1 LU, the volume can still
  move toward T (not at ×32 and short) and fewer than three verify renders have run,
  v ← min(v·10^((T − R)/20), ×32) and render again.
  `limited_by` is `max_gain` when the last R is under T − 0.1 at ×32. Enhance and Loudness
  Normalize solve the same way, so Normalize after Enhance measures what Enhance measured.
  (f) **Idempotence.** A rendered clip that already carries the solved limiter and whose volume
  is within 0.05 dB of v keeps its volume, so a second press is an identity. 0.05 dB is twice
  the 0.025 dB a re-rendered isolation window differing by −51 dB (S2) can move a loudness. A
  clip planned off the cache is never kept this way.
  (g) **The readouts.** Loudness stays the material (AU-11). At volume on a clip that renders
  reads the last R0 measured for the clip's current plan and chain (`ProcessedLoudness.Memo`, 32
  entries, emptied when a loudness file or an offline render lands), through the limiter model at
  the current volume as AU-26 does; with none it shows the cache figure as "≈ …", its tooltip
  saying it is before the clip's processing. No background measurement.
  (h) `AudioDynamicsModel` stays only for Enhance's makeup (AU-62); nothing else reads it.
  (i) **Repeatability, measured (2026-10-31, AP6b step 3, the owner's order to fix the
  non-repeat).** AP6b's first build recorded three Enhance presses on the steady `say` fixture
  reading R0 −21.382, −21.373 and −21.321 LUFS. Measured again on the rebased tree: one trial of
  that fixture with Enhance's chain (Rumble Cut, isolation 0.8, a gate, the de-esser, a
  compressor) rendered five times in one process through the render's own path — the chain whole
  and each of its keys alone — gave byte-identical PCM every time (−21.2828 LUFS whole), with the
  reader's first buffer at offset 0 and 408 buffers each time, and the same with the isolated
  render deleted and made again before each render; the first build's own sources
  (`adb6cb5`) gave the same bytes; and in the app a first press and three Normalize rounds after
  it read −21.28278599304145 each on that fixture, placed at 0 s and at 7.3 s, and
  −21.61915860368329 on the off-mic one with the leveller on, presses 2 and 3 "made no change"
  each time. None of the suspects —
  the reader's head, a stage's state at a render's start, a re-rendered isolation window, a levels
  read racing the build, the stamp placement — moves a byte, so there was no cause in the render
  to fix, and the 0.05 dB keep stays. The first build's spread is not reproduced; its record
  does not say how its presses were set up. `audio_ap6b_probe.py`'s R5 (three renders, the
  isolated render wiped before the third) and `audio_ap6b_proof.py`'s P5 hold it.
- **AU-65 — The chrome, the tool, the proof.** An "Enhance Voice" button row under the Normalize
  button in the Volume section (its tooltip the rules in a sentence); Clip ▸ Enhance Voice right
  after Normalize, no key equivalent (Normalize's reason). `enhance_voice` takes `clips` and
  `target_lufs`, no `scope` (it follows the open container, as `normalize_clip`), and answers
  `{target_lufs, ceiling_dbtp, enhanced: [{clip, media, measured_lufs, true_peak_dbtp,
  speech_seconds, floor_lufs, floor_gap_db, pause_peak_dbfs, sibilance_share, set, reasons,
  volume, result_lufs, result_true_peak_dbtp, limited_by}], skipped?, note?}`, `set` exactly the
  edit's keys in `set_audio`'s spelling, plus `processed_lufs` (R0's loudness) and `renders`;
  `result_lufs` and `result_true_peak_dbtp` are the last verify render's. **The sheet**
  (amended 2026-10-31): while any clip renders, the button and the menu (Enhance Voice, and
  Normalize in Loudness mode) put up the Measuring Sound sheet — a bar, "Clip n of N…" and
  Cancel, which changes nothing — in the Synchronizing Audio sheet's shape (SY-22); with no
  clip to render, Loudness Normalize commits at once as before, and Peak mode never renders.
  `enhance_voice` and `normalize_clip` become off-main tools (`syncAudio`'s pattern: read and
  commit on main, the wait off it, the assistant's Stop cancelling it); `normalize_clip`'s
  Loudness rows gain `processed_lufs` (null off the cache) and `renders` (0 there). The proof is
  `audio_ap6_probe.py` (E1–E3, E6–E11, mutants M1–M6 and M8–M12), the loudness probe's C1 and
  C12 with M7, and `audio_ap6_proof.py` V1–V15 over MCP and exports; how the result sounds on
  the owner's voice is manual check SE-38 (AP8a, AP10b and AP8b took SE-35…SE-37).

AU-66 and AU-67 are AP6's second part (the leveller; survey B3), recorded before its code. The
first build (a live K-weighted rider that held through pauses) stopped on its proof: a segment
after a distance change started up to 12 dB off for about 3 s. Both are rewritten whole on
2026-10-31 (AP6b, the owner's answer: look ahead).

- **AU-66 — The leveller: a gain curve made ahead of time, applied statelessly in the tap,
  `audio.leveller`, format 37.** (2026-10-31, AP6b, the owner's answer: look ahead.)
  (a) **The order (amends AU-143):** isolation → voice → channels → high-pass/EQ → hum → noise
  reduction → gate → **leveller** → de-esser → compressor → limiter → fader. The leveller is a
  gain on the clip after the gate, so the de-esser's and the compressor's thresholds see the
  levelled voice.
  (b) **What the curve measures** is the material, pre-chain, as L is: the clip's `ClipLoudness`
  reading — its 10 ms played steps, in the export's layout through pan · fold · pick, over the
  segments the reading walked (the clip's first media's, by start); L, the gated integrated
  loudness of that reading; and the speech mask by AU-61's rule (`media.speech`, else
  `DuckSpeech.spans` of the VAD cache; a step's source midpoint), through
  `AudioEnhance.speechSpans` and `speechMask`. Speed, ramps and reversal are measured on what
  plays, as AP1's readout is. Nothing is rendered.
  (c) **The curve.** Over the played steps, with ℓ(e) a step energy's loudness: a step is SPEECH
  when the mask holds and ℓ(e) ≥ −70 LUFS. A BREAK is a run of at least 50 non-speech steps
  (0.5 s); a PHRASE runs from a speech step to the last speech step before the next break. A
  LONG phrase has at least 100 speech steps (1 s). For each step k of a long phrase,
  u_k = ℓ(mean e over the phrase's speech steps j with |j − k| ≤ 150) − L: a 3 s window,
  speech-only and truncated at the phrase's edges, so it never reaches across a break. r =
  `smooth(u, tau: response / 2 in steps)` within the phrase — a one-pole pass forward then one
  backward, each primed with its first input — which is zero-phase, so a change is anticipated
  as much as it is followed. A short phrase takes the previous long phrase's last r, else the
  next one's first. Steps before the first long phrase take its first r; steps after the last
  hold its last r. A break between phrases A and B holds A's last r and, over its last 25 steps
  (0.25 s), moves linearly in dB to B's first r, reaching it at B's first speech step. No long
  phrase is unmeasurable ("it has no phrase with 1 s of speech"). The stored curve
  (`AudioLevellerCurve`) is r per step, keyed by segment start: the material's level relative to
  L. It does not depend on the target or the limits.
  (d) **The stage.** A run's gain at a step centre is g_k = 10^(clamp(target − r_k, −max_down,
  +max_up)/20), with the run's settings — the base's, or AU-87's anchor point's. A sample's gain
  is the linear interpolation of g between the step centres around its tick, the tick being
  (firstFrame + i)·perSecond/rate, the lookup frame AU-87 uses (the samples after the reducer
  belong to t + lookupLead); one gain multiplies every channel. It is stateless: no reset, and
  nothing carries across a cut, a seek or a clip; the output is a pure function of the absolute
  frame, so block size, seeks, preview, export and AU-64's render agree by construction. Nothing
  is allocated or locked on the audio thread, and `exp` runs once per step centre per run.
  (e) **Where it is computed and what invalidates it (amends AU-42).** In Swift, in
  `AudioDynamicsLevels`, beside L, from the same memoised reading. A clip's curves are made for
  every `response` its base and its ends name; the memo entry keeps the curves and the spans
  used. They are made again on a new plan text (window, trim, speed, reversal, map, media), a new
  channel matrix, a new response, a changed `media.speech`, or a `loudness` or `speech` cache
  post, which also rebuilds every open document levelling that media. Target, Max Boost and Max
  Cut are applied in the tap and remake nothing. **Speech detection unavailable:** no spans (no
  `media.speech`, no VAD cache) while `SileroVAD.isAvailable` is false — a build without the
  model, or a model marked unavailable this process, after which `MediaImporter.speech` writes no
  cache and never retries — is `.unmeasurable(reason: "speech detection is unavailable")`: the
  clip plays un-levelled, its Status reads "Not levelling: speech detection is unavailable", it is
  not in `pendingLevels`, and an export does not wait for it. The availability is read on each
  call (a pending answer is never memoised, as a missing loudness file is not), so a model
  marked unavailable mid-pass is seen by the export's next 0.1 s poll. **While pending** (no
  loudness file; or no spans and no VAD cache while speech detection is available) the clip plays
  un-levelled, Status reads "Waits for its loudness" or "Waits for its speech", and the clip is in
  `pendingLevels`, so an export — and AU-64's render, through `withOfflineAudio` — waits for it up
  to 300 s, then fails `loudnessUnmeasured`: "Clip N's loudness or speech has not been measured
  yet, so its gate, leveller and de-esser cannot be set. Wait for their Status rows to show the
  clip's loudness, then export again." An unmeasurable clip plays un-levelled and says why. A
  nest clip's leveller reaches nothing.
  (f) **The model.** `audio.leveller` `{target_db −20…10 (0), max_up_db 0…24 (12), max_down_db
  0…24 (12), response 300 000…6 000 000 ticks (1 200 000, 2 s)}`, target in dB re L, after
  `voice`, written only when set; format 37, no migration. `set_audio` takes it (`{}` stores the
  defaults, null clears it, each field refused by name as `audio.leveller.<field>`, an unknown
  field such as the first build's `threshold_db` refused as an unknown key), and
  `paste_attributes` carries it whole through `check_audio`. It is `TAP_KEYS`' twelfth key
  (amends AU-85's deferral): the target and the limits interpolate, and **`response` joins
  `HELD_AUDIO_NUMBERS`** (amends AU-86): it switches at an action's end, because each response
  is its own curve made ahead of time. `clamp_leveller` holds an evaluated end to the ranges.
  (g) **The section.** "Leveller", between Gate and De-esser, closed by default: a "Ride the
  level" check (on writes the defaults); Target (dB re loudness, −20…10, quick −6, −3, 0, 3), Max
  Boost (dB 0…24, quick 6, 12, 18), Max Cut (dB 0…24, quick 3, 6, 12), Response (s, 0.5…10, one
  decimal, quick 1, 2, 4); a Status read-out ("Aims at −41.7 LUFS", L + target; "Waits for its
  loudness"; "Waits for its speech"; "Not levelling: <reason>") and Loudness; the summary the
  target ("0 dB") or "off". Each control writes the whole group; inside an action Response
  writes the end like the other rows and takes effect at the end.
- **AU-67 — Enhance turns the leveller on by the speech's short-term loudness range; the proof.**
  (2026-10-31, AP6b, the owner's answer: look ahead.)
  (a) **The range.** The clip's 10 ms steps where `speechMask` is true, concatenated, in 3 s
  windows (300 steps) at a 0.1 s hop (10 steps); each window's loudness is
  `StepLoudness.loudness` of its mean energy. EBU Tech 3342's gating applies: absolute −70 LUFS,
  then relative −20 LU under the energy mean of what passed. The range is p95 − p10, linearly
  interpolated (numpy's default). Under 300 speech steps there is none.
  (b) **The rule.** Enhance owns `leveller` (AU-60's eight keys become nine). Over 6 LU it writes
  `LevellerProps()` (the defaults); at or under 6 LU it writes null; with no range the key is left
  out of the edit. Each case has its sentence ("Leveller: the speech's short-term loudness range
  is 9.4 LU, above 6 LU, so the leveller is on at its defaults."). The range is measured
  pre-chain, so a second press measures the same (AU-61's idempotence holds). `enhance_voice`'s
  rows gain `speech_range_lu` (a number, or null).
  (c) **Rendering (amends AU-64 (a)).** `ProcessedLoudness.needsRender` is true for a
  `leveller`, and its memo key carries it. The solve renders the chain with the curve, so the
  processed loudness counts the levelled voice.
  (d) **Measured before the rule** (`audio_ap6b_probe.py`'s step-2 figures, each through a
  probe document's own loudness and speech caches): the owner's recording 4.610 LU (so Enhance
  writes the leveller off there: the owner's level is already even), the proof's off-mic fixture
  (six 10 s `say` segments peaking at −6 and −18 dBFS by turns) 13.144 LU, the steady fixture
  (all six at −6) 2.108 LU.
  (e) **The proof.** `audio_ap6b_probe.py` rows L1–L9 and R1–R5 over `app/Sources`, with mutants
  M1–M10, M12–M15 and M17 each killed by its named row (M16 has no edit: AU-64 (i)) and M11
  ("leveller" out of `TAP_KEYS`) by hand against `core/tests/audio_automation.rs`;
  `audio_ap6b_proof.py` P1–P8 over MCP and exports.
  P2 (b) holds each segment's first 0.5 s mean gain within **±3 dB** of its settled gain (the
  owner, 2026-10-31; ±1.5 dB was asked first): on the off-mic fixture it reads 0.56–2.41 dB,
  because each `say` sentence's speech begins 0.06–0.29 s into its segment, so the window holds
  the glide's end on the bed, and the sentences open 0.2–3.1 dB louder than their middles, which
  AU-66 (c)'s window and smoothing follow as decided; a carry-over across a pause like v1's (a
  segment starting ~12 dB off) still fails it. P3's seek row (8 s from 20 s after 12 s from 0)
  holds the leveller's own part against a CONTROL on the same play sequence — the levelled
  export itself placed as a clip with nothing on it, against its own export — its signed ΔI
  less the control's within 0.01 LU, because after a seek the player hands every tap a silent
  zero-duration buffer carrying the seek's time, which the live meter places at the seek's
  frame (filed), so a seek's ΔI depends on the material's level there; the first play's row
  stays absolute.
  Whether a speaker moving off the mic sounds even, the pauses do not swell and a phrase after a
  pause starts at its level with no audible glide is manual check SE-41.

AU-68 and AU-69 are AP6's third part (Enhance the microphone when a recording lands; survey B8),
recorded before its code.

- **AU-68 — A follow-up, not part of the landing.** The landing commits at once and is unchanged:
  `RecordingLanding`, `ProjectDocument.untitled(around:)`, the step names, the notes, the panel's
  note and reveal, and `record_screen`'s fields. Enhance Voice (AU-60…AU-65, unchanged) follows as
  its OWN undo step, "Enhance Voice", once the voice's caches exist.
  (a) **The voice clips** are every clip in the open container whose media path is one of the
  recording's voice paths: each segment's `micDescriptor`, each `unreadable[].micDescriptor`, and
  for a voice-over each segment's `descriptor` (`RecordingEnhance.voicePaths`). Never the
  picture's, the camera's or the system audio's; none without a microphone.
  (b) **Readiness.** Each voice clip's media has a current loudness cache
  (`MediaImporter.loudnessIsCurrent`), and `media.speech`, or a current speech cache
  (`speechIsCurrent`), or `SileroVAD.isAvailable` false — Enhance then skips the clip in its own
  sentence.
  (c) **Busy** is any of: `document.isLiveEditing`; `document.scope` other than the landing's;
  and at the panel only, no editor window or a sheet already on it.
  (d) **`decide`**, in this order: no voice clip still present → `.drop` (quietly at the panel);
  analysed and not busy → `.enhance`; 300 s since the landing (`waitLimit`) → `.giveUp`;
  otherwise `.wait`.
  (e) **The panel** runs a repeating 0.5 s timer (`RecorderPanelController.landingRetryInterval`)
  in the run loop's DEFAULT mode, the landing's retry trick, so it pauses during a drag. On any
  step but `.wait` the timer is invalidated and the landing's pending entry removed FIRST, then
  the step acts, so nothing the sheet does (Cancel, no outcome, a stale answer) can leave a timer
  that puts it back up. `.enhance` runs `AudioMeasureDoor.enhanceLanded`: the press's own
  `measure` under the Measuring Sound sheet at `NormalizeChoice.targetLUFS`, committed with
  `performGroupedEdit` (a timer is not an AppKit event) as "Enhance Voice"; Cancel changes
  nothing. Nothing to enhance, a stale answer and `.giveUp` are a refusal of `enhance_voice` at
  the inspector's foot (`projectDocumentDidRefuse`); nothing beeps and the panel's note is not
  touched. `.giveUp`'s sentence: "Enhance Voice did not run on the recording: its microphone was
  not ready to measure within 5 minutes. Select its clip and choose Clip ▸ Enhance Voice."
  (f) **The tool** (`record_screen {enhance: true}`) polls `decide` through `onMain` every 0.5 s
  on the server thread, then runs `enhance_voice`'s own body at −16 LUFS
  (`AudioNormalize.defaultTargetLUFS`; a tool reads no `UserDefaults`). The answer gains
  `enhance`, the `enhance_voice` answer object, or `enhance_error`, a string: any refusal of that
  body, "No microphone clip landed on the timeline, so there was nothing to enhance." for
  `.drop`, and `.giveUp`'s sentence ending "Call enhance_voice with its clips." for `.giveUp`.
  The top-level `project` is read again after the enhance.
  (g) **Undo.** Edit ▸ Undo reads "Undo Enhance Voice", then for a document landing "Undo Add
  Recording"; for a new project it then reads the remainder's step (Add Microphone, Add
  Camera…, Add Recording Segments), or nothing when the first file is the document.
  (h) **Why.** The loudness and speech caches, and isolation's render, cannot exist before the
  media is in a project. Holding the landing for them would hold the files' landing, the note and
  the answer behind analysis that can fail; a separate step lets ⌘Z take the processing off and
  keep the recording.
- **AU-69 — The setting, the argument and the proof.** (a) A checkbox, "Enhance the microphone
  when it lands", on a row with no label directly under Microphone; enabled only while the panel
  is idle with a microphone chosen (any source), greyed otherwise with its value kept; its tooltip
  names AU-68's step. `RecordingChoice.enhanceMicrophone` is true only when it is ticked and a
  microphone is chosen. (b) Its key, `FrameJobRecordingEnhanceMicrophone`, is the panel's
  eleventh: written on change, restored on show, absent reading off; the harness and `screens.py`
  pin it. (c) **Default off**: Enhance writes eight settings, renders isolation and puts up a
  sheet, so a recording lands as recorded unless asked; the tool's default matches. (d)
  `record_screen` gains `enhance` (boolean, default false), read after `place` and before the
  Microphone grant, so both of its refusals are among the caller's own mistakes: "enhance: true
  enhances the microphone's clip, so it needs microphone: true (or source voice_over)." and then
  "enhance: true needs place: true — with place: false the microphone lands as media with no clip
  to enhance."; a non-boolean is `boolArg`'s sentence. (e) **The dev tool `land_recording`**
  (Debug and Release only) hands fixture files to the product's own code after `onFinish` — the
  panel's `recordingEnded` or the tool's landing — because the recorder needs the Microphone grant
  and a voice at the microphone, while a proof's instance records room tone under the terminal's
  grants. (f) The proof is `audio_ap6c_probe.py` (P1–P5, mutants M1–M9) and `audio_ap6c_proof.py`
  (V1–V8, over MCP, `land_recording` and exports); how a real voice-over on the RØDE sounds is
  manual check REC-19.

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

AU-80…AU-84 are AP8's first part, AP8a (the volume line; survey A9), recorded before its code.
AP8 is built in two parts: AP8a draws a clip's gain envelope and edits it through actions; AP8b
(every other audio parameter as action ends) continues at AU-85.

- **AU-80 — The volume line edits through ACTIONS, not keyframes (owner, 2026-10-30, the road
  map's "Asked at AP8", option (a)).** A point on the line is an action's end (`end.audio.volume`);
  a drag writes `set_audio {volume}` or that end; nothing is persisted that actions do not already
  persist. Reason: it keeps spec §2's "Actions, not keyframes", which every phase since has built
  on; it is app-only (no core, FFI, op, tool, format or `UserDefaults` change); and AP8b animates
  every other audio parameter as action ends through the same model. What it costs, accepted
  with it: each point is a span, one action band per point; a point joins the previous one by a
  ramp from it (the clip's start counts as the first); a point cannot go inside an action that
  also animates another property; a point inside an EASED volume action reshapes the ease on both
  sides (AU-83); a point's time moves with its band, not on the line; and an agent makes in two to
  four tool calls (`add_action`, `set_action`, `set_action_end`) what the gesture makes in one
  step. Keyframes (option (b), lifting §2) were declined.
- **AU-81 — What is drawn: what is heard from the clip, within the handle the timeline shows.**
  Every clip with sound — not a nest clip — draws, over its waveform, the gain of the plan audio
  track holding its audio segment, cut to that segment: the plan's ramps, which carry the clip's
  volume and its actions, fades, crossfades, ducks, its track's volume (AU-103) and every
  silencing (clip mute, track mute, a solo elsewhere, `enabled.audio` false: `core/src/audio.rs`'s
  module doc), so a silenced clip's line lies on the floor. A drag edits only the clip's OWN
  volume, relatively (AU-82), so on a silenced clip the line stays on the floor while the readout
  moves. Inside an open nest the timeline reads the scoped handle, whose plan is the nest's own
  mix: the line there leaves out the enclosing nest clip's and tracks' volume, fades, mute and
  solo. The scale is dB, top `20·log10(32)` = +30.103 dB (`AudioNormalize.maxGain`) and bottom
  −60 dB; a gain at or under 0.001 draws at the bottom and one above 32 (a track's volume can carry
  the plan there) at the top. The line's rect is the clip's audio region with its top raised to
  the action lane's bottom where they overlap, inset 1 pt top and bottom; drawn when it is at
  least 12 pt tall and the plan has the clip's segment. A polyline through every ramp's (start,
  from)–(end, to), white 85 %, 1 pt, clipped to the rect; a 5 pt square in the action colour at
  each action end naming `audio.volume` inside the clip, centred on the line — drawing only, not a
  hit target. The envelope is the core's, read through the plan and memoised per handle as the
  speech duck's line is (AU-113); never recomputed in Swift.
- **AU-82 — The drag: vertical, relative, in dB, on the level in force.** A plain press on the
  line selects the clip and edits the level in force at the press: inside an action naming
  `audio.volume`, that action's end; else the latest action ENDED at or before the press naming
  it; else the clip's base `set_audio {volume}`. Each tick the value is
  `clamp(max(v0, 0.001)·10^(Δ/20), 0, 32)` for Δ the dB the pointer moved on the line's scale, and
  0 when the pointer is below the press AND at the rect's bottom (1 pt above it or lower) — the
  "below the press" keeps a press on a floor line (a silenced clip's) from writing 0 without a
  downward move. Beside the pointer, the clip's own resulting value: "+2.5 dB", one decimal,
  "−∞ dB" at 0. One undo step, "Set Volume"; none when nothing moved. Live through the
  document's live edit, so `check_audio`'s 0…32 is met by the clamp before the core sees a value.
- **AU-83 — ⌥-press on the line adds a point, as an action.** At the press's clip time snapped to
  the frame, t: inside an action A whose end names ONLY `audio.volume` (no other group, no other
  audio key), A is split at t — A shortened to `t − A.start`, a new action `[t, A.end)` ending at
  A's end volume and carrying A's curve when it is not linear — and the point dragged is A's new
  end, starting at the evaluated volume at t; a press under one frame from A's start beeps (a
  zero-length action is refused, and a live edit swallows refusals). For a linear A the click
  alone leaves what is heard unchanged; for an eased A both halves carry its curve, so the values
  at t and at A's end are kept and the shape between is re-eased on each side. Inside any other
  action or one a trim left running past the clip's end (`add_action` would refuse the split's
  second half), or under one frame after the latest action end at or before t (any kind: actions never
  overlap), a beep and nothing. Otherwise a new action `[prevEnd, t)` (prevEnd that latest end,
  else 0; the core's default curve, linear) ending at the evaluated volume at t, so the click alone
  changes nothing heard. The new id is the base's `next_id`. The click adds the point at once; the
  drag continues as AU-82 on that end; one undo step, "Add Volume Point".
- **AU-84 — The line's hit, the modifiers, the mirror and the proof.** The hit test asks for the
  line after the fade handles, the action band and the two edge grabs, and before the clip body:
  within the line's rect and 3 pt of the line at the pointer's x. A locked track's clip is the
  clip, as before. A press on the line with ⇧ (toggle membership; ⌥⇧ slip) or a double-click
  (rename) goes to the clip's own arm unchanged; only a plain press and one whose modifiers
  include ⌥ but not ⇧ are volume gestures, and ⌥-drag on the body away from the line stays
  Duplicate. The agent's mirror is the ops the gesture sends — `set_audio`, `add_action`,
  `set_action`, `set_action_end` — whose handlers name the volume line; no new tool. The proof is
  `volume_line_proof.py`: probe rows V1–V9 over `app/Sources` (the drawn line against the plan,
  the scale, targets, the drag's arithmetic, points added and split, one undo step, the hit order
  and modifiers, the paint) and thirteen mutants, each killed by its named row; manual check SE-35.

AU-85…AU-89 are AP8's second part, AP8b (every other audio parameter as action ends; survey A9),
recorded before its code. The leveller's target is left out: AP6 part 2, which adds it, has not
landed (`git log` at `e55de46` has no AP6).

- **AU-85 — The plan carries each audio segment's automation.** An audio segment carries
  `automation`, a list of `{at, audio}` points, when its innermost clip (`voice.stages[0]`) has an
  action whose end's `audio` names a tap key — `mono`, `pan`, `compressor`, `noise_reduction`,
  `limiter`, `isolation`, `eq`, `hum`, `channels`, `gate`, `de_esser` (`TAP_KEYS`,
  `core/src/audio_automation.rs`); otherwise the key is absent and the plan is the text it was.
  The points are at the voice's start and end, at each such action's start and end, and on
  `ACTION_SAMPLE` / `MAX_ACTION_SAMPLES`'s grid (1/30 s, the envelope's) inside a non-linear one,
  clipped to the voice, sorted and deduplicated; `at` is project ticks. Each point is
  `evaluate_clip` at `at − origin`, its audio filtered to `TAP_KEYS`. Swift only interpolates,
  linearly between two points: a number when its group is present on both sides, a tick field
  rounded; everything else — presence, a switch, an enum, `bypass` — comes from the left point,
  and so do the four `HELD_AUDIO_NUMBERS` (`eq.high_pass.slope`, `eq.low_pass.slope`,
  `hum.frequency`, `hum.harmonics`), Ints in Swift and switches by AU-86. Not animated, each for
  its reason: volume, mute and the fades (the envelope, `audio.rs`); the duck and the fade shapes
  (read from the base by `audio.rs`); `keep_pitch` (the plan's `pitch`); `voice` (an offline
  render); a nest clip's own keys (a segment names the innermost clip). The leveller's target is
  deferred to AP6 part 2.
- **AU-86 — Evaluation.** The evaluated audio group writes `isolation` even at 0
  (`actions_audio.rs`'s `audio_json`), so an action toward 0.8 ramps from 0 rather than
  switching at its end. The two slopes, the hum's mains and its harmonics are switches: they hold
  their start value until the action's end, in the core (`hold_audio_steps`, after the lerp) and
  in Swift. Every other rule is §5.4's.
- **AU-87 — The tap reads the automation on an absolute sample grid.** For an automated span the
  settings of a run come from the points at the run's ANCHOR: the latest of the 32-frame grid
  boundary at or before the run's first frame, the frame of the point to its left and the span's
  start, all in lookup frames, `round(time·rate) + offset + lead·rate/perSecond`. A run never
  crosses a grid boundary or a point frame, its own or the head's (at `+ headLead`), so the
  settings of a sample do not depend on how the buffers fall: preview and export agree, and a
  render at 512, 4096 or irregular buffers is byte-identical. Pan is computed per sample from the
  two points around the sample's tick (`AudioPanRamp`), isolation's Amount per input frame
  (`AudioIsolationSpan.amounts`). A switch takes effect at its point's frame, with no glide, as at
  a cut (AU-30; S1 measured its splatter at −79 dB). `usesLimiter` and `usesNoiseReduction` are
  true when any point asks, so a limiter switched on at an action's end has its lead for the
  whole track (AU-23). A span with no automation runs today's path unchanged.
- **AU-88 — Wanted renders, what stays on the base, and the EQ slot keyed off.** An isolation
  render and a gate or de-esser level are wanted when the base or any action end asks
  (`AudioDSPParameters.wantsIsolation`, `AudioDynamicsLevels.wanting`), so a clip whose base
  isolation is 0 is requested, loaded and crossfaded by its automation's amounts. A voiced clip
  keeps its base isolation (AU-143); the limiter keeps its base volume as its divisor (AU-22),
  and the level L keeps the base pan, fold and pick (AU-41). Inside an action the inspector sends
  pan, mono, compressor, noise reduction, limiter, isolation, EQ, hum, channels, gate and
  de-esser to the action's end, and a switch turned off there becomes `off` (CI-14). The duck,
  Keep pitch, the fade shapes, the voice effect and a NEST clip's mono stay with the base. This
  amends CI-3, AU-21, AU-37, AU-46 and AU-50. It extends CI-14: `off` accepts
  `audio.eq.<slot>`, one of the seven slots (`high_pass`, `low_shelf`, `band_1`, `band_2`,
  `band_3`, `high_shelf`, `low_pass`), which stores `null` at that slot of the end's `eq` — the
  only three-part path; any other path of more than two parts keeps the "group.key" sentence, an
  unknown slot is refused naming the seven, and a slot the patch also names is refused in the
  both-sentence. `ReelOp.setActionEnd` lifts an `NSNull` slot inside `audio.eq` into that path.
  Agents use `set_action_end`; there is no new tool, op or format.
  Extended by GR-36: `off` also accepts `video.qualifier.<range>`, a second three-part path.
- **AU-89 — The proof.** `audio_ap8b_proof.py`: probe rows A1–A8 over `app/Sources` (the
  interpolation and its held numbers, an automated EQ and pan block-size invariant, the per-sample
  pan, the track-wide stages from a point, the Amount per frame, the routing, the wanted sets,
  the EQ lift); MCP rows E1–E6 against 24-bit WAV exports (a pan, an EQ gain, a compressor
  threshold, a limiter switched on at an end, isolation's Amount from base 0, an EQ slot keyed
  off), V1 the live meter against the export, U1 one undo step; thirteen mutants, each killed by
  a named row or core test; manual check SE-37.

AP9's decisions, split edits (J- and L-cuts) and a reversible Detach Audio (`archive/audio.md`
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

AU-100…AU-106 are AP10's (tracks, buses and stems; survey A12, A11), recorded before its code.
AP10 is built in two parts: part 1 is a track's volume and pan; part 2 (per-track sub-mixes, track
and bus dynamics, the master chain, stems) continues at AU-107 once AP2 part 2's float write pass
has landed.

- **AU-100 — The preview stays approximate for track dynamics, and says so (owner, 2026-10-30,
  answer 1 (b)).** Linear track stages — the fader, the pan, later a track EQ — are exact per
  composition track in the preview and the export alike. Track and bus dynamics run per
  composition track in the preview, where S3 measured the difference: a limiter's ceiling
  +0.85 dB over through a crossfade, a nest bus +1.4–1.8 dB; the preview has no master chain; the
  guide and the meter say where preview and export differ. The export is exact through per-track
  sub-mixes (S3: −147.7 dB against the reference). Reason: an exact preview — S3's
  `AVAudioEngine` route, 0.02 ppm of drift, 60–150 ms to start — means rewriting the transport
  (Playback's audio, AP7's meter feed, AP13's scrub, picture-to-audio sync), so it is a road-map
  candidate issue, not part of AP10.
- **AU-101 — Stems are separate files (owner, 2026-10-30, answer 2 (a)).** One file per track, or
  per chosen set of tracks, written by one export job. Reason: every NLE and DAW reads separate
  files, where many apps import only a multitrack movie's first audio track. Stems are part 2's.
- **AU-102 — `tracks[].volume` and `tracks[].pan`, format 35.** `volume` is linear, 0…4 (+12.04 dB,
  `TRACK_VOLUME_MAX`), default 1, written only when not 1; `pan` is −1…1, default 0, written only
  when not 0 — after `matte`, on the timeline's tracks and a nest's alike, so every other project
  writes the text it did and there is no migration step. `set_track` takes both and refuses
  outside the range in `in_range`'s sentence (`volume must be between 0 and 4, not 5`, `pan must be
  between -1 and 1, not 2`); a hand-written value outside is clamped where it plays. `nest` copies
  volume and pan from every source track EXCEPT the nest clip's destination (`front_track`),
  whose copy is unity and centre: the destination track still applies over the nest clip, so a
  selection taken off one track sounds the same nested. (Mute is copied from every track, the
  destination's too, because muting twice is muting once; a fader applied twice is not.) A
  selection's clips from the OTHER source tracks then also get the destination track's volume and
  pan on top of their own, as they already get its mute. `unnest` keeps neither on the way out,
  as it keeps no mute: the clips land on the timeline's own tracks.
- **AU-103 — Volume is an envelope term after mute, at every stage.** It multiplies each stage's
  gain in `audio.rs` exactly where the track's mute zeroes it — the stage per track, the container
  per depth — so a nested clip's sound is scaled by its own track's volume and by every enclosing
  nest clip's track's. Solo and mute precedence are unchanged. Being in the envelope, the live
  meter, the timeline bar's bars and Remove Silences hear it; Normalize, the Loudness read-out and
  the clip limiter do not (they read the clip, AU-11, AU-22), so a track at ×4 can take a limited
  clip past its ceiling.
- **AU-104 — Pan is a balance by `AudioPanLaw`, after an enclosing nest's fold and before the clip
  limiter.** Each audio segment of the plan carries `track_pans`: the pans of the tracks its voice
  passes through, innermost first, clamped to ±1, zeros dropped, the key absent when none remain.
  A stage whose nest clip's base `audio.mono` is true clears the pans collected inside it, since
  that fold flattens them. The tap applies the product of the pans' constant-power pairs to
  channels 0 and 1 after the clip's own pan and an enclosing nest's fold, and before the limiter;
  it is skipped at unity, so an untouched project's samples stay bit-identical, and a segment with
  `track_pans` gets a tap even when no clip asks for DSP. A track pan has no effect on a mono
  source (its composition track has one channel, as a clip pan has none). A nest CLIP's own pan
  still reaches nothing; only track pans travel, through the plan.
- **AU-105 — The chrome.** A fifth header switch, `slider.horizontal.3` (fallback "V"), lit when
  a track's volume is not 1 or its pan not 0, opens a popover on the track: Volume in dB, −60…+12
  (the floor reads "Off" and writes 0; quick picks −12, −6, −3, 0, 3, 6) and Pan −100…100 (quick
  picks −100, −50, 0, 50, 100, writing `pan / 100`), each a slider and a field, and Reset. A drag
  is one undo step ("Track Volume", "Track Pan"); a field commit is one, and Reset is "Reset Track
  Mix". Track ▸ Volume and Pan… (no key) and the header's context menu open the same popover on
  the current track. Agents use `set_track {volume, pan}`: no new op, tool or FFI export.
- **AU-106 — The proof.** `audio_ap10_proof.py`: export rows F1–F5 (fader arithmetic: track,
  track × clip, inner × outer through a nest, the nest's unchanged level, a muted track at ×4),
  P1–P5 (pan: the law, inner × outer, a folded nest, a mono source, clip × track), U1 (one undo
  step, the read-back, no keys at defaults), V1 (the live meter against the export), and probe rows
  B1–B4 (the balance, the chain order, `isInert`, `TrackMixLevel`); ten mutants, each killed by a
  named row or `core/tests/track_mix.rs`; manual check SE-33 for the popover's feel.

AU-107…AU-109 are AP10 part 2a's (stems; survey A11), recorded before its code. Part 2 is built
in two: 2a labels the plan and writes stems; 2b (track and bus dynamics, the master chain, the
preview's statement) records its decisions from AU-150.

- **AU-107 — The plan labels its audio tracks.** Each `audio_tracks[]` entry is `{"id", "track",
  "segments", "ramps"}`: `track` (u32) is the id of the `Project::tracks` entry whose walk in
  `assign` placed it, so a nest's contents carry the nest clip's track. Written always; the plan
  is not persisted, so there is no format bump. Swift keeps the map composition track → timeline
  track per build (`BuiltComposition.audioOwners`), the family split by source format included:
  a composition track never carries two top-level timeline tracks (S3 Q1), so a selection by
  timeline track is a selection of whole composition tracks.
- **AU-108 — Stems (AU-101's).** (a) On the three audio rows only (`audio_m4a`, `audio_wav`,
  `audio_aiff`, whose presets list `stems: ["tracks", "names"]`); a movie row refuses (`<id> has
  no stems; stems applies to audio_m4a, audio_wav and audio_aiff`), and a value but the two words
  is refused by name on any row. (b) `tracks`: one stem per heard timeline track; `names`: heard
  tracks whose trimmed names match case-insensitively are one stem, named by the first's
  spelling, and an unnamed track is its own. Heard = has a plan audio track labelled with it and
  is not `silenced` (mute, solo) among the timeline's tracks; none heard is refused (`stems: no
  track is heard, so there is no stem to write`). Order: timeline order of each stem's first
  track. (c) A name is the trimmed track name, else `Track N` (N = index + 1, the header's label),
  `/` and `:` replaced by `-`; a name equal case-insensitively to an earlier stem's gets
  ` (Track N)`, and one still equal to an earlier stem's ` (Track N, 2)`, ` (Track N, 3)` and on,
  the first no earlier stem holds, so no two stems share a file. The settings end with `stems: [{name, tracks}]` only when asked. (d) Files
  `<mix name without extension> - <name>.<mix extension>` beside the mix; an existing file at a
  stem's path is replaced without asking (the save panel asks only about the mix), except that a
  stem path naming one of the project's media files (symlinks resolved, case-insensitive) refuses
  the job before any stem file is touched, with `ExportStemsPipeline.SourceCollision`'s sentence
  (`The stem “<file name>” would replace media this project uses; export under another name.`);
  the guide says both. (e) **Pre-master:** a stem is its tracks' sub-mix exactly as the mix plays
  them (clips, envelope, ducks, track volume and pan, taps), with no loudness gain and no master
  limiter (`ExportAudioMaster(limits: false)`), rounded once at the job's depth and clipped only
  at full scale — so the stems sum to the mix within rounding wherever the master neither gains
  nor limits; the guide says so. (f) One job: the mix, then each stem in order, each from a fresh
  build of the same plan on the export's key (fresh taps, `ExporterLoudness.swift`'s reason)
  reading only its composition tracks, on one serial queue `com.kgalligan.framejob.export.stems`;
  progress is `(finished + current) / (1 + N)` of the write's share; a failure or a cancel leaves
  nothing (the pipeline removes the mix and each stem it finished); the line reads "Exported
  “Mix.wav” and 3 stems."; the `export_status` result lists each stem's `{name, tracks, path}`.
  (g) Not measured: the loudness report is the mix's.
  **Amended by #470** (docs bugs b3): (f)'s "leaves nothing" means nothing the job wrote. A mix the
  job has not yet replaced stays, so the source collision that stops a job before writing leaves
  an existing mix as it was.
- **AU-109 — The proof, and part 2b.** Part 2a's proof is `audio_ap10b_proof.py`: S1–S8 (two
  tracks' stems summing to the mix within 2 LSB at 24 bits, `names` grouping, a loudness target
  leaving every stem byte-identical, mute and solo, a real recording's stem against the soloed
  export, a stem's peak above the master's ceiling, the refusals, a source collision), C1 (a
  cancel inside the last stem leaving nothing) and probe rows B1–B2 (the unlimited master, the
  file names, the summary and the collision test); seven mutants, each killed by a named row or
  `core/tests/export_stems.rs`; manual check SE-36. Part 2b (track and bus dynamics exact in the
  export through sub-mixes summed before the master, approximate in the preview and stated, the
  master chain's decision) records its decisions from AU-150, the first block no phase holds
  (AU-110… are AP11's).

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
  **Amended by CO-90** (road map creator-jobs CO9): a second reader, `video.hide_silent`, reads a
  media's spans to show a picture while that media's speech plays.
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

AU-120…AU-129 are AP12's (match one clip to another; survey B6), recorded before its code.

- **AU-120 — Match Audio is a composite, not an op, and owns the level and the EQ's tonal
  slots.** Clip ▸ Match Audio… and `match_audio {reference, clips, loudness?, eq?}` write
  ORDINARY settings, Enhance Voice's pattern (AU-60): `volume` and `limiter` (Match Loudness,
  AU-123) and the EQ's `low_shelf`, `band_1`, `band_2`, `band_3` and `high_shelf` with
  `bypass: false` (Match EQ, AU-126, AU-127); every other key is left as it is. BASE props even
  inside an action (Normalize's reason), one `set_audio` per target, all committed as ONE undo
  step named "Match Audio". No core, FFI, op, format or `UserDefaults` change.
- **AU-121 — The reference is picked in a sheet.** Clip ▸ Match Audio… is enabled with at least
  two selected clips that `AudioNormalize.canOffer` passes, and opens the Match Audio sheet: a
  "Match to" popup of those clips in timeline order (start, then track order; the first by
  default), a Loudness and an EQ checkbox (both on, not remembered; Match disabled with both
  off), Cancel and Match. Each item's title is `<clip name> — <track name> — m:ss (clip <id>)`
  and each is an `NSMenuItem` carrying the clip id in `representedObject`, added through the
  menu, never `addItem(withTitle:)` (which drops a row of the same title); the choice is read
  from the selected item's `representedObject`, never its index or title. The other selected
  clips are the targets. The sheet hands its choice back as the Measuring Sound sheet does:
  stored on Match, delivered once from `viewDidDisappear` on the next main-queue turn, never
  after Cancel; only then is the measurement pressed, so the window has no sheet attached.
  Chosen over a "Set as Match Reference" item (session state) and the first selected clip (the
  selection is a set, with no order).
- **AU-122 — The reference is read from its cache, then rendered once as it plays.** It needs its
  loudness cache reading (`ClipLoudness.answer`): Normalize's skips (not a clip, a nest, no
  audio, still being analysed, under 0.4 s, gated out) are refusals naming the reference. It is
  rendered ONCE through `ProcessedLoudness.render` of the press's own project, with no trial edit:
  its chain, its limiter and its base volume as the one constant fader (AU-64 (c)), and no fades,
  ducks or mute. T is that render's `StepLoudness.integrated`; a render gated out is a refusal.
  T is not range-checked: it is what the reference plays at.
- **AU-123 — Match Loudness is Loudness Normalize to T.** AU-24 and AU-64 unchanged: an inner
  `LoudnessMeasureRun` with target T over the targets. A target's job chain is `AudioPatch(eq:
  the matched EQ)` when EQ is on (so the volume is solved through the EQ it will have), else
  `normalizeJobs`' rule. A target equal to the reference is skipped ("is the reference."). With
  Loudness off, `volume` and `limiter` are not written.
- **AU-124 — The spectra are speech-only, measured on renders.** The reference's is AU-122's
  render. A target's is a trial `set_audio {eq: trialEQ(current), volume: 1, limiter: null}`
  rendered pre-fader (its high- and low-pass kept, its tonal slots off). The speech mask is
  AU-61's (`media.speech`, else the VAD cache's spans; `AudioEnhance.speechMask` over the cache
  reading's `stepSources`); render frame f is in played step ⌊f/480⌋. An STFT of 8192 points,
  Hann, hop 4096, at 48 kHz, power |X_L|² + |X_R|²; a frame counts when the step at its centre
  is speech; at least 12 frames (about 1 s), else the clip lacks the speech to match. Bands
  n = −11…+11: centre 1000·2^(n/3) (about 79 Hz to 12.7 kHz), bins in [c·2^(−1/6), c·2^(1/6));
  each band's level 10·log10 of the mean over counted frames of the band's power.
- **AU-125 — The curve.** D_b = Lref_b − Ltgt_b. A band's weight is 1 where both levels are
  within 50 dB of their own loudest band, else 0; under 12 weighted bands skips the target (a
  reference with under 12 bands within 50 dB of its own loudest is refused). The weighted mean of
  D is removed (the level is Match Loudness's), and the curve is smoothed [1, 2, 1]/4 inside and
  (2, 1)/3 at the ends.
- **AU-126 — The fit.** The model is `AudioEQDesign.responseDB` of the five tonal slots at
  48 kHz at the band centres, the drawn curve's own function. Every residual is offset-invariant:
  r = (curve − model) − the weighted mean of (curve − model); the cost is Σ w·r², and the shelf
  solve, the bell placement, the Levenberg–Marquardt step and `rmsDB` all use this r (the
  broadband offset is Match Loudness's, never fitted or written). (a) The shelves first, low at
  150 Hz and high at 6 kHz, their gains solved; then the two shelves alone, corners too, by
  (c)'s Levenberg–Marquardt, taken as the start only when they leave no weighted band's |r| at
  0.5 dB or above (a tilt that is one shelf then places no bell), else the corners stay at
  150 Hz and 6 kHz (added at the build: with the corners fixed, a lone 4 kHz shelf left 1.7 dB
  for a bell to chase and LM kept it; with the refined shelves always taken, a five-slot EQ's
  low shelf ran to 53 Hz; P5 and P9 hold only with the test). (b) Up to three bells, greedily, at the weighted
  band of largest |r| ≥ 0.5 dB, none within 3 bands of an earlier bell, Q from the run W of
  adjacent same-sign bands with |r| ≥ |r_b|/2: BW = W/3 octave, Q = clamp(2^(BW/2)/(2^BW − 1),
  0.5, 4); bands 1–3 assigned in frequency order. (c) Levenberg–Marquardt over every placed
  parameter (log f, gain, log Q) on the weighted residual, a central-difference Jacobian, λ from
  1e−2 (÷10 on a better step, ×10 on a worse one), clamped after each step, at most 40
  iterations or until the relative cost change is under 1e−6; the bounds: low shelf 40–500 Hz,
  high shelf 2–16 kHz, bells 60 Hz–12 kHz, gains ±12 dB, Q 0.5–4. (d) Rounded: f to 1 Hz, gain to
  0.1 dB, Q to 0.01; a slot whose |gain| < 0.1 dB is nil; `rmsDB` the weighted RMS of r over the
  rounded model.
- **AU-127 — The target's own EQ.** Its five tonal slots are REPLACED by the fit; `high_pass` and
  `low_pass` are kept (rendered through, so the fit is around them); `bypass: false`; hum is
  untouched. A second press measures the same trial and writes the same EQ, and the solve's
  0.05 dB keep rule (AU-64 (f)) holds the volume: an identity, "Match Audio made no change".
- **AU-128 — The chrome and the tool.** The menu item, the Match Audio sheet, then the Measuring
  Sound sheet (always: the reference renders); the stale test and its sentence, "… Choose Match
  Audio again." and "… Call match_audio again."; a reference refusal beeps and puts its sentence
  at the inspector's foot. `match_audio` takes no `scope` (it follows the open container) and is
  an off-main tool (`awaitMeasurement`'s pattern, generic over the run). `loudness: false, eq:
  false` is refused by name; a target that cannot be matched is skipped by name and the rest are
  matched; with nothing matched, "Nothing could be matched." with every reason. It answers
  `{reference: {clip, media, lufs, speech_seconds|null}, target_lufs|null, matched: [{clip, media,
  set, eq|null, eq_fit_rms_db|null, volume|null, measured_lufs|null, processed_lufs|null,
  result_lufs|null, result_true_peak_dbtp|null, limited_by|null, renders}], skipped?, note?}`,
  `set` exactly the patch's keys in `set_audio`'s spelling. The dev-only launch default
  `-RCDevMatchAudioAccept YES` presses Match once the sheet is up.
- **AU-129 — The proof.** `audio_ap12_probe.py` P1–P9 over `app/Sources` with twelve mutants
  (M1–M11, one per independent decision of the speech gate, the curve, the fit and the write;
  the eleventh, M11, the offset-invariant residual, which only a one-sided tilt (P9) can see; the
  twelfth, M12, AU-126 (a)'s shelf start, added with it at the build, P9's too), and
  `audio_ap12_proof.py` A1–A8 over MCP and exports (third-octave bands by the proof's own numpy,
  loudness by `phase5_proof.integrated`): pink noise tilted by a known EQ matched back within
  ±1 dB a band from 100 Hz to 10 kHz and ±0.5 LU. How a match sounds on a real voice is manual
  check SE-39.

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

AU-150…AU-156 are AP10's part 2b (track and bus dynamics, the master chain; survey A12),
recorded before its code, continuing AU-109's block.

- **AU-150 — `tracks[].compressor` and `tracks[].limiter`, format 36.** The clip's own two types
  (`Compressor`, `Limiter`), after `pan`, each written only when set, so every other project
  writes the text it did and there is no migration step. `set_track` takes both: an absent key
  keeps the track's value, `null` clears it, and an object REPLACES the whole value — the keys it
  leaves out take the type's defaults, never the stored value's. Refused, each in its own
  sentence: a value neither an object nor `null` (`compressor must be a json object or null, not
  5`), an unknown key (`unknown key "compressor.knee" in set_track`), a mistyped member (`bad
  value at "limiter.release" in set_track: <serde's reason>`), and a value outside the clip's
  ranges in `in_range`'s sentence under the track's key (`compressor.ratio must be between 1 and
  20, not 30`); the clip's own sentences are unchanged (`check_compressor`, `check_limiter`
  shared, prefix `audio.compressor` / `audio.limiter`). **Timeline tracks only:** inside a
  `scope` either key is refused (`a track's compressor or limiter has no meaning inside nest 5`),
  `nest` gives the nest's tracks none — the destination's own still apply over the nest clip — and
  one written by hand on a nest's track is ignored where it plays. **Base-only, never animated:** a
  track has no actions. **Normalize, Loudness, Enhance Voice and Match Audio solve pre-track** and
  hear none of it: AU-64's renders are clip renders.
- **AU-151 — Where it runs: post-fader on the track's sub-mix.** After every clip's chain, the
  envelope (clip volume, fades, crossfades, ducks, the track's volume) and the track's pan —
  compressor, then limiter, the ceiling in dBTP on what the track hands the mix (absolute: the
  limiter is told volume 1); then the tracks are summed, then the master (AU-27). A nest's whole
  mix plays through the track holding its nest clip, so that track is the nest's bus. Both stages
  are the clip's (`AudioCompressorStage`, `AudioLimiterStage`), compressor then limiter, one
  `AudioTrackDynamicsStage`; its latency is 158 frames with a limiter, else 0.
- **AU-152 — The export: per-track sub-mixes read in lockstep (S3).** When no owner in the read
  (honouring a stem's `audioSelection`) has settings, the export reads exactly what it did — one
  `AVAssetReaderAudioMixOutput`, byte-identical. Otherwise `ExportMixRead` puts on the one reader
  one mix output per timeline track with settings plus one for every other selected track
  (omitted when empty), each over only its own tracks' input parameters (one tap per composition
  track, each in exactly one output). Per group the buffers are placed by stamp from the range's
  origin at 48 kHz (a hole is zeros, an overlap cuts the covered head, `ExportAudioMaster`'s rule),
  run through the group's stage as they arrive, the stage's latency dropped at the head and a
  zero flush at the group's end; `next()` reads from the group with the least buffered, an ended
  group counting as zeros, and emits up to 4,096 summed frames stamped `origin + frame` until
  every group is drained. The mix's writer, its stems (`ExportStemsPipeline`, unchanged), the
  WebM writer and the loudness measurement all read through it; a sub-mixed build's measurement
  reads float through it with no 16-bit fallback.
- **AU-153 — The preview: per composition track, approximate (AU-100), and said.** On a metering
  build only (`Playback`'s), a composition track whose owner has settings gets the stage in its tap
  after the chain and before the meter. The tap is PreEffects, so the fader is downstream: the tap
  multiplies frame `g` by the track's envelope E at grid frame `g + L` (L the stage's latency in
  frames at the tap's own rate), runs the stage, and divides by E at `g` (0 where E < 2⁻²⁰), so a
  sample's ×E and its ÷E, L frames later, are the same number at any rate and a step in the
  envelope is never a gain burst. E is `volumeLegs(ramps:onset:)` exactly as `audioParameters`
  sets it, read on the tap's absolute frame grid (AU-87's). With a track limiter the media is
  placed 1,975 ticks earlier and the tap's lookups lead by as much (AU-23's pattern, summed with a
  clip limiter's): placement only, so at a rate other than 48 kHz the audio is misplaced by the
  difference as the clip limiter's lead already is, and the gain pairing is untouched. Every other
  build — export, measurement, stems, `ProcessedLoudness`, scrub grains, thumbnails — has no track
  stage in its taps (`AudioDSPParameters.isEmpty` excludes track dynamics). The preview runs the
  stage per composition track, so where a track's clips share one composition track it is exact
  and where they split (a crossfade, a nest's inner tracks) it is not: the live meter says
  "approximate" whenever the build carries any (`tracks_approximate`), and the guide gives the
  measured difference.
- **AU-154 — The master chain is AU-27/AU-28's and nothing more.** The export's master is the
  loudness gain and the true-peak limiter at `peak_dbtp`. A master bus compressor is the whole
  timeline nested on one track with a track compressor — exact in the export — so a master stage
  would be a second spelling of it, and the preview has no master to hear one (S3 (b)); delivery
  needs loudness and true peak, which AP2b meets. No master compressor, EQ or trim.
- **AU-155 — The chrome.** The track header's mix popover gains, under Pan, a Compressor section
  (a "Compressor" checkbox; Threshold, Ratio, Attack, Release, Makeup) and a Limiter section
  ("Limit peaks"; Ceiling, Release), with the clip sections' units, ranges and quick picks; each
  control writes the whole object through `set_track`; a drag or a commit is one undo step
  ("Track Compressor", "Track Limiter"); Reset ("Reset Track Mix") clears volume, pan, compressor
  and limiter. Inside an open nest both sections are disabled with the tooltip "A nest's mix
  plays through the dynamics of the track that holds it." The header switch is lit when any of
  the four is set. Track ▸ Volume and Pan… and the context menu's item are renamed "Mix…" (the
  same actions). Agents use `set_track {compressor, limiter}`: no new tool or FFI export.
- **AU-156 — The proof.** `audio_ap10c_proof.py`: export rows T1–T6 (a track limiter through a
  crossfade, compressor arithmetic and post-fader, a nest bus, stems summing with dynamics on
  both tracks, a loudness target, WebM), P1 (the preview's measured overshoot and
  `tracks_approximate`), U1 (undo, read-back, refusals, `nest`, the parity log), probe rows B1–B5
  (the stage at any buffer size, `ExportMixRead` against the single read, a nest bus, the tap's
  ×E/÷E at 48 and 44.1 kHz, the leads and the footer); ten mutants, each killed by a named row or
  `core/tests/track_dynamics.rs`; manual check SE-40.
- **AU-157 — A linked pair's duck belongs to its sound half.** `detach_audio` drops `audio.duck`
  from the picture half, and `duckers` skips a linked clip whose picture is on and whose audio is
  off, so a pair saved earlier, or a duck pasted or set on the picture half, ducks nothing. An
  unlinked clip with its audio off, and a linked sound half switched off, still duck: a duck is
  otherwise a fact about the timeline. Decides what `edit_background.rs` left open. Before this
  the picture half kept its copy, so the pair ducked the mix twice and pushed its own sound down
  to the duck level (#468). `attach_audio` takes the sound's whole group, so nothing is lost on
  the way back. `is_linked_picture` reads the clip alone, not its partner, because a pair inside
  a nest is out of `Project::clip`'s reach. No format change: the read rule makes a stale duck
  inert, and `set_audio` on a picture half still applies.
