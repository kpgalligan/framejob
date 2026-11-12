# Spec §11 — decisions: Audio, voice isolation onward (road map "audio")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the AU- series of [`audio.md`](audio.md), so a citation never has to say which
file; that file names the condensed record and the original. This file holds AU-50…AU-69. AU-70 on are in [`audio-3.md`](audio-3.md).
It is new because `audio.md` had passed the spec's ~500-line split rule (#424, 2026-11-09); the
entries moved here unchanged, each phase's opening paragraph with its decisions.

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
  `TimePitchFeeder`, dropping what the slowest has read), at most 4096 frames a block; a block
  whose engines answer different frame counts fails the render naming both counts ("the channels
  rendered different frame counts, 4096 and 4095"), carried by `isolationFailed` and the Status
  (`IsolationRenderer.roundFrames`; amended 2026-11-09, #409). A unit whose
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
  48 kHz passes dry. An Amount change rebuilds the composition, never the render. All of this is
  a ×1 segment's; a retimed segment's Amount is AU-55's, in a file (amended 2026-11-10, #387).
- **AU-54 — The order (amends AU-3).** isolation → channels → high-pass/EQ → hum → noise
  reduction → gate → de-esser → compressor → limiter → fader. Isolation and noise reduction do not
  exclude each other; noise reduction works on the crossfade.
- **AU-55 — Which segments are isolated: every one that sounds (amended 2026-11-10, #387).** A
  ×1 segment, forward or reversed with its copy ready, is isolated in the tap as AU-53 says. A
  reversed clip renders the reversed file itself, so it aligns by construction; its floor is
  measured and reported. Two clips cut from one take render two windows (S2: a seam about
  −30…−50 dB, accepted, not shown audible). As first decided, a retimed segment played dry and
  the Status said "Plays without it at this speed"; that limit is lifted:
  - **Two kinds of retimed segment** (`RetimedSound.kind`). RENDERED: the plan segment carries a
    `ramp` — a Speed action, or a constant speed with Keep pitch off (SR-28) — and the composition
    plays a file from `cache/ramp-audio/`. LIVE: a constant speed with Keep pitch on, which the
    composition inserts and scales itself (AVFoundation's time-pitch, or varispeed inside SY-39's
    band).
  - **The way: the processed window is what gets retimed.** The clip's sound is isolated BEFORE
    the retime and written to a file, and the retimer reads that file in the media's place. The
    other way — isolating the retimed sound — was not taken: a live segment's retimed sound exists
    only inside AVFoundation's player and reader; Apple's voice model would hear a pitch-shifted
    voice with Keep pitch off, and start cold on every render; and the model would run again
    after every rate edit, where this way it runs again only when the media it reads moves.
  - **The window `W`** (`RetimedSound.window`): the 48 kHz frames the segment plays — a ramp
    map's first to last source tick, else its source range — widened by 8,192 frames each side
    (Keep pitch on's 4,800-frame preroll, the resampler's reach at ×12, SY-24's 46 samples), and
    for a Keep pitch on render by what Apple's unit reads past the clip's end, (2,688 + 1,024)
    output frames at the map's last rate (measured 642 past the lead at ×2 and 288 at ×12); then
    rounded OUTWARD to whole seconds, its first frame never before 0. The rounding is so that an
    edit which moves the source range by less than the slack keeps the isolated render, whose
    name carries the window (AU-52): a rate edit on a clip that plays the same media does. An
    edit that moves the range further renders again.
  - **The chain** (`RetimedSound.chain`), each stage a job on `RampAudioRenders`, wanted only
    once the file before it is on disk (AU-143's pattern; every settle wants again): (1) the
    isolation of `W`, AU-51's job and AU-52's name unchanged; (2) the MIX, `dry + a·(iso − dry)`
    over `W` in the source's own channel count (`IsolationMix`), in `cache/isolated/`, named by
    the isolated file's name, a version and the Amount; (3) for a rendered segment, the ramp
    render of the mix through the segment's own map counted from `W`'s first frame, in
    `cache/ramp-audio/`, named as a dry render is plus the mix's name and `W`'s first frame — so
    a dry render's name is what it was. A live segment has no third stage: `fill` inserts the
    same source range of the mix, counted from `W`'s first frame, and scales it as it scaled the
    media, on a composition track of the mix's format (`audioFamilies` is handed the same map).
    The tap adds no span for a retimed segment.
  - **The Amount is in the file.** A changed Amount writes a new mix (and renders a rendered
    segment again), and the clip plays dry until it lands; at ×1 it stays AU-53's live crossfade.
    An Amount an action moves (AU-87) is evaluated per source frame: the frame's clip time through
    the inverse of the segment's map, then the straight line between the points; the map and the
    points are in the mix's name only then.
  - **Pending plays dry.** The document wants the dry ramp render of a rendered segment beside
    its chain, always, so the clip sounds while the chain renders; the builder takes the
    processed render when it exists, else the dry one. A live segment reads the media until its
    mix exists.
  - **What plays no sound is not isolated.** A freeze frame is a still, and a still has no audio
    properties: the core refuses `set_audio` and an audio paste on one. A clip above ×12 (the
    audio ceiling) has no audio segment. For a clip that asks while no plan sounds it, the
    Status reads "Plays no sound".
  - **Limits, recorded.** Disk: a processed rendered clip holds four files (the isolated window,
    the mix, the dry render, the processed render), about 11.5 MB a minute each in mono. A live
    segment's two reads differ as two reads of a dry Keep pitch on clip do (AVFoundation's
    time-pitch, #337); a rendered segment's are sample-identical. Preview and export build one
    composition from the same files, as before.
- **AU-56 — The section.** "Voice Isolation", in the Sound tab before Noise Reduction: an "Isolate
  voice" check (on sets `IsolationCache.defaultAmount`, 0.8: S2's pauses −14 dB with room tone
  kept, where 1.0 makes them dead air), an Amount row 0–100 % (quick 50, 80, 100), and a Status
  read-out — Rendering…, Ready, "Plays no sound" (AU-55 as amended, #387; it replaced "Plays
  without it at this speed"), "Waits for the reversed copy", "Not rendered: <why>" — refreshed on `.reversedMediaDidChange`, which the document posts when a
  render lands and when one fails. De-reverb (B4) is this control (S2: C50 +5.2 dB, the late tail
  −5.3 dB on an RT60 0.6 s room): the section says it "reduces room echo", and there is no
  separate control.
- **AU-57 — Export and agents.** An export wants and waits for its isolation renders as it does
  for ramps ("Preparing…"), and fails `isolationFailed` naming the clip when one cannot be
  rendered. A retimed clip's chain (AU-55 as amended) is waited for whole: the export asks for
  what can be rendered, waits, and asks again until a pass names nothing new (at most four
  passes; a failed mix is `isolationFailed`). An agent uses `set_audio {isolation}`: no new tool, and the render's status is not in
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
  ℓ ≥ L − 10. (`isolatable`, measured until #387, is gone: AU-55 as amended.) A clip
  needs at least 1 s (100 steps) of speech. Nothing measured depends on a key Enhance writes, so a
  second press measures the same and writes the same: the core answers an identity ("made no
  change").
- **AU-62 — The rules.** With F = floor − L:
  - **High-pass, always:** the EQ's Rumble Cut (`EqPreset.rumbleCut`, 80 Hz at 24 dB/octave)
    applied to the clip's own EQ, or to an empty one.
  - **Noisy pauses, F > −45 dB:** voice isolation at `IsolationCache.defaultAmount` (0.8) and
    noise reduction 0, at any speed (amended 2026-11-10, #387: the "noise reduction 0.5 where the
    clip is not isolatable" arm went with AU-55's limit); and
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
  with only those plans off the cache, byte for byte as before. Enhance always renders. An action's end counts too: AU-159 (a), and its limiter: AU-165 (a).
  (b) **The trial.** On main, `document.project` with one `set_audio {clips: [c], patch:
  chain}` scoped to the open nest, then `.scoped(nest)`. The first render's (R0) chain is
  Normalize's `{limiter: null}`, or Enhance's chosen patch with `limiter: null`. AU-159 (b).
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
  An action-end limiter verifies by render too, and the limiter can go on mid-loop: AU-165 (b).
  (f) **Idempotence.** A rendered clip that already carries the solved limiter and whose volume
  is within 0.05 dB of v keeps its volume, so a second press is an identity. 0.05 dB is twice
  the 0.025 dB a re-rendered isolation window differing by −51 dB (S2) can move a loudness. A
  clip planned off the cache is never kept this way.
  (g) **The readouts.** Loudness stays the material (AU-11). At volume on a clip that renders
  reads the last R0 measured for the clip's current plan and chain (`ProcessedLoudness.Memo`, 32
  entries, emptied when a loudness file or an offline render lands), through the limiter model at
  the current volume as AU-26 does; with none it shows the cache figure as "≈ …", its tooltip
  saying it is before the clip's processing. No background measurement. Amended: AU-159 (g),
  AU-165 (c).
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
  isolated render wiped before the third) and `audio_ap6b_proof.py`'s P5 hold it. A step's
  last bit did follow the reader's buffers under load, found and fixed by AU-160 (#567).
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
  clip plays un-levelled, its Status reads "Not leveling: speech detection is unavailable" (amended by #526), it is
  not in `pendingLevels`, and an export does not wait for it. The availability is read on each
  call (a pending answer is never memoised, as a missing loudness file is not), so a model
  marked unavailable mid-pass is seen by the export's next 0.1 s poll. **While pending** (no
  loudness file; or no spans and no VAD cache while speech detection is available) the clip plays
  un-levelled, Status reads "Waits for its loudness" or "Waits for its speech", and the clip is in
  `pendingLevels`, so an export — and AU-64's render, through `withOfflineAudio` — waits for it up
  to 300 s, then fails `loudnessUnmeasured`: "Clip N's loudness or speech has not been measured
  yet, so its gate, leveler and de-esser cannot be set. Wait for their Status rows to show the
  clip's loudness, then export again." (amended by #526) An unmeasurable clip plays un-levelled and says why. A
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
  (g) **The section.** "Leveler" (amended by #526), between Gate and De-esser, closed by default: a "Ride the
  level" check (on writes the defaults); Target (dB re loudness, −20…10, quick −6, −3, 0, 3), Max
  Boost (dB 0…24, quick 6, 12, 18), Max Cut (dB 0…24, quick 3, 6, 12), Response (s, 0.5…10, one
  decimal, quick 1, 2, 4); a Status read-out ("Aims at −41.7 LUFS", L + target; "Waits for its
  loudness"; "Waits for its speech"; "Not leveling: <reason>", amended by #526) and Loudness; the summary the
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
  out of the edit. Each case has its sentence ("Leveler: the speech's short-term loudness range
  is 9.4 LU, above 6 LU, so the leveler is on at its defaults.", amended by #526). The range is measured
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
  is absolute, within 0.01 LU of the export over the same frames, as the first play's row is
  (amended by AU-161, #405: it was held against a control, the levelled export played as a
  clip of its own, while the live meter placed the player's silent filler at the seek's
  frame).
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
  nothing. From that step until its answer, its refusal or the Cancel has landed the document is
  measuring (`RecordingEnhance.isMeasuring`; `isUnderWay` is the timer or the measurement), which
  the polish waits on, while `isPending` stays the timer alone (amended 2026-11-09, #546).
  Nothing to enhance, a stale answer and `.giveUp` are a refusal of `enhance_voice` at
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
  grants. Its panel door's `follow_wait` waits for, and its `enhance_pending` answers,
  `RecordingEnhance.isUnderWay`: the follow's timer or its measurement (amended 2026-11-09,
  #546). (f) The proof is `audio_ap6c_probe.py` (P1–P6, mutants M1–M10; P6, read from the
  sources by its runner, holds the follow to the press's one setup,
  `AudioMeasureDoor.enhanceSetup`, which `enhance_voice` reads in one main-thread hop, and M10
  restores the tool's second hop; amended 2026-11-09, #412) and `audio_ap6c_proof.py`
  (V1–V8, over MCP, `land_recording` and exports); how a real voice-over on the RØDE sounds is
  manual check REC-19.
