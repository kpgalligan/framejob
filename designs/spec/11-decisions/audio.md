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
