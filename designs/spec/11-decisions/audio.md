# Spec §11 — decisions: Audio (the owner's audio pass, from 2026-10-30)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The owner's pass over a clip's sound, begun 2026-10-30 to turn a desktop USB microphone's
recording into usable audio for a video. Its IDs are the AU- series. Each was recorded before
its code.

AU-50 on are in [`audio-2.md`](audio-2.md) (AU-50…AU-69), [`audio-3.md`](audio-3.md)
(AU-70…AU-109) and [`audio-4.md`](audio-4.md) (AU-110…AU-157), moved there unchanged on
2026-11-09 because this file had passed the spec's ~500-line split rule (#424).

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
  audio props); a cache not yet written ("still being analyzed — its loudness has not been
  measured yet" (amended by #526)); under 0.4 s played; gated out (every block under −70 LUFS).
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
  2, 4) and a Slope popup (12 or 24 dB/oct); the summary "off" (no EQ, or one with no slot on; amended 2026-11-09, #407), "bypassed" or "N on"; Reset
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
