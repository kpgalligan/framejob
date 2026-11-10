# Spec §11 — decisions: Audio, ducking by speech onward (road map "audio")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the AU- series of [`audio.md`](audio.md), so a citation never has to say which
file; that file names the condensed record and the original. This file holds AU-110…AU-158.
It is new because `audio.md` had passed the spec's ~500-line split rule (#424, 2026-11-09); the
entries moved here unchanged, each phase's opening paragraph with its decisions.

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
  is sampled at each span's four edges and wherever two spans' curves cross — a release meeting
  a later span's attack, or that span's own release when it ends inside its attack — for every
  pair whose curves overlap, not only neighbours (#386). `pre_roll` and `hold` default to 0.5 s (300,000 ticks) each, are ≥ 0, and are BASE-only like the rest
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
  D is removed (the level is Match Loudness's), and the curve is smoothed [1, 2, 1] over each
  weighted band and its weighted neighbours, renormalised to the taps present: [1, 2, 1]/4
  between two weighted bands, (2, 1)/3 at an end or beside a dropped band, the band alone between
  two. A dropped band (weight 0) reads 0 and contributes nothing to its neighbours (amended
  2026-11-09, #411).
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
  Audio again." and "… Call match_audio again."; a reference refusal, or nothing matched after
  the renders, beeps once and puts its sentence at the inspector's foot once
  (`AudioMeasureDoor.land`; amended 2026-11-09, #410). `match_audio` takes no `scope` (it follows the open container) and is
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
  twelfth, M12, AU-126 (a)'s shelf start, added with it at the build, P9's too), and since
  2026-11-09 P1–P12 with sixteen mutants: P10 a dropped band beside a tilted one (#411, M13),
  P11 `matchAnswer` and `land`'s one beep and one sentence (#410, M14, M15), and P12, read from
  the sources by the runner, the menu path landing through `land` alone (#410, M16); and
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
  the kind's own; a Status read-out in Voice Isolation's words. The Clip ▸ Voice ▸ menu E8 names
  is AU-158's (#390).
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
- **AU-158 — Clip ▸ Voice ▸ (#390).** The menu E8 names, the menu half of the Voice Effect section
  (AU-146) and a second UI path to `set_audio`'s `voice`: no new op, tool, FFI export or
  persisted field. (1) **Place and title.** "Voice", right after Look ▸ in the Clip menu, no key
  equivalent. (2) **Shape.** One level: a section header per group in E8's order ("Voice",
  "Tone", "Character", "Space", `NSMenuItem.sectionHeader`, which has no action), under each its
  kinds by their bare names ("Pitch" … "Cathedral"), then a separator and None. One level and not
  a submenu per group, because a submenu's parent item cannot carry the mark. The headers, the
  names and their order are `VoiceGroup` and `VoiceKind` (`VoiceProps.swift`), which the
  section's popup titles ("Voice: Pitch") are also built from, so the two cannot drift. The
  `perform_menu_item` path is `["Clip", "Voice", "Radio"]`; the selector is `setVoiceEffect:`,
  the tag an index into `VoiceKind.allCases` or −1 for None, any other tag a stranger that beeps.
  (3) **Targets** are the section's: the selected clips with sound (`InspectorTab.hasAudio`) in
  the open scope, a nest clip included (where the effect does nothing, AU-140). Every item, None
  included, is enabled exactly when there is a target. (4) **What a choice writes.** A kind
  writes `{kind, amount: the clip's own ?? 1, pitch: null}` to each target, one `set_audio` per
  clip: every clip keeps its own amount (Look ▸'s rule, GR-7 [b]; the popup gives every clip the
  first clip's, the inspector's model) and every kind starts at its own pitch (AU-146). None is
  one `set_audio {voice: null}` over the targets. The clip's own value whatever action is
  selected (AU-140); one undo step "Voice Effect"; a choice that changes nothing is an identity,
  a beep and no step. (5) **The mark is Look ▸'s** (GR-7 [b] (3)): a kind is checked when every
  target carries it, dashed when some but not all do, unmarked otherwise; None is checked when no
  target has an effect, dashed when some have none. Amount and pitch are not read. Proof:
  `voice_proof.py` V12–V14 (the one list, the mark, what a choice writes), M1–M5 over
  `perform_menu_item` (`--menu`) and seven mutants; manual check SE-45.
