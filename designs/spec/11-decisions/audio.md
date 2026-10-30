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
