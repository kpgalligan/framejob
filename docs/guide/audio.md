# Audio

Frame Job mixes sound from every clip that has it: a camera clip, an audio-only file, a microphone recording or a nest. Each clip has its own level, fades, ducking, voice isolation, a voice effect, channel choice, EQ, hum removal, noise reduction, gate, de-esser, compressor, pan and mono fold, and a true-peak limiter, and each track can be muted or soloed and has its own volume and pan. Two commands do the measuring for you. Normalize sets a clip's level from its loudness (or its loudest moment), and Synchronize Audio lines up a camera and a separate recorder by their sound. The preview and the export use the same mix, so what you hear while editing is what gets written, except that every export also holds its peaks under −1 dBTP with a master limiter the preview doesn't have.

## Where audio lives

There is only one kind of track. Any track can hold a clip with sound, whether it is a video file, an audio-only file (a voice-over, music, a recorder's take) or a clip you split off with Detach Audio. A clip with sound shows its waveform in the timeline.

The waveform shows the level of the file itself, so moving the Volume slider doesn't redraw it. It's drawn faded when the clip is muted, when its track is muted, or when another track's solo silences it. A track that holds only sound clips is drawn as a shorter lane than a track with pictures.

When the selection includes at least one clip that plays sound, the Clip tab of the inspector shows a **Sound** sub-tab. A clip counts as having sound when its file has an audio track and its audio is switched on, or when it is a nest that holds audio. The Sound sub-tab has twelve sections, in this order:

1. **Volume**: level, gain read-out, loudness read-out, Mute and Normalize
2. **Fades**: fade in and fade out
3. **Ducking**: lowers every other clip while this one plays
4. **Voice Isolation**
5. **Voice Effect**: one of sixteen effects, from a pitch shift to a cathedral
6. **Channels**: which channels of a stereo file play
7. **EQ**: a high-pass, two shelves, three bands and a low-pass, with presets for voice
8. **Hum**: removes mains hum and its harmonics
9. **Noise Reduction**
10. **Gate**: turns the pauses between phrases down
11. **De-esser**: tames harsh "s" sounds
12. **Compressor**
13. **Mix**: pan, mix to mono, Detach Audio and Attach Audio
14. **Limiter**: holds the clip's peaks under a ceiling

Voice Isolation through Limiter appear in the order the sound passes through them. Volume, the fades and ducking are applied last, like a fader.

Every section header has a summary and a Reset button that appears when the section differs from its default. The summaries read:

| Section | Summary |
|---|---|
| Volume | "muted", "silent" (at 0 %), or the gain, for example "+3.5 dB" |
| Fades | both lengths, for example "0.50 · 1.00 s", or "none" |
| Ducking | the duck level, for example "20%", or "off" |
| Voice Isolation | the amount, for example "80%", or "off" |
| Voice Effect | the effect and its amount, for example "Space: Hall 100%", or "off" |
| Channels | "Both", "Left Only", "Right Only" or "Swap Left and Right" |
| EQ | how many parts are on, for example "2 on", "bypassed", or "off" |
| Hum | the mains and the harmonics, for example "60 Hz · 4", or "off" |
| Noise Reduction | the amount, for example "50%", or "off" |
| Gate | the threshold, for example "−10 dB", or "off" |
| De-esser | the frequency, for example "6.0 kHz", or "off" |
| Compressor | the ratio, for example "3.0:1", or "off" |
| Mix | "centre", "mono", or the pan position, for example "left 40" |
| Limiter | the ceiling, for example "−1.0 dBTP", or "off" |

 When you change a control with several clips selected, the change goes to all of them. A control whose clips hold different values is marked mixed.

### Sound on a nest

A nest clip has the same Sound sub-tab, but not every control reaches the clips inside it:

- **Volume, Mute and the fades** on a nest clip scale everything inside it. Turning a nest down turns all of it down, and muting it silences all of it.
- **Mix to mono** on a nest clip folds the nest's whole mix.
- **Ducking** on a nest clip lowers the rest of the project for the nest's whole length.
- **Pan, the compressor, noise reduction and the limiter** set on a nest clip have no effect. Open the nest (⌘↓) and set them on the clips inside.

*Agents:* `set_audio` (`clips`, `patch`) changes any of these properties on one or more clips. Its patch keys are `volume`, `muted`, `fade_in`, `fade_out`, `fade_in_shape`, `fade_out_shape`, `duck`, `mono`, `keep_pitch`, `pan`, `compressor`, `noise_reduction` and `limiter`. Setting `duck`, `compressor` or `limiter` to null turns it off. `get_project` reads them back.

## Volume

| Control | What it does | Range | Default |
|---|---|---|---|
| Volume | The clip's level as a percentage. The slider covers 0–400 %; type a higher value in the field, up to 3200 %. Above 400 % the slider's knob stays at the right end. Quick picks: 0, 50, 100, 150, 200, 400. | 0–3200 % | 100 % |
| Gain | Read-only: the volume in dB (for example "+6.0 dB"), or "silent" at 0 %. | — | +0.0 dB |
| Loudness | Read-only: the clip's integrated loudness and true peak over the part that plays, at volume 100 % (for example "−41.7 LUFS · −18.5 dBTP"). "measuring…" until the clip's loudness analysis has run; "—" with several clips selected or none that can be measured. | — | — |
| At volume | Read-only: the same with the clip's volume applied, and with its limiter when the Limiter is on (the true peak then reads no higher than the ceiling). It follows a Volume drag; the Loudness row itself updates when the drag ends. | — | — |
| Mute | Silences the clip without changing its volume. | on / off | off |
| Normalize (row) | The mode, Peak or Loudness, and the Loudness target in LUFS (quick picks −14, −16, −23; used in Loudness mode only). The choice is the app's, not the project's, and is kept between launches. | Peak / Loudness; −50 to −5 LUFS | Loudness; −16 LUFS |
| Normalize (button) | Sets the volume from the clip's own loudest moment, or from its loudness, by the mode (see below). | — | — |

The section's summary reads "muted", "silent" or the gain in dB. Reset puts the volume back to 100 % and turns Mute off.

You can animate volume, Mute and the fades with actions. While an action is selected, the Volume row, the Mute checkbox and the Fade in and Fade out rows write that action's end state, so a level moves across the action's span. Pan, Mix to mono, Keep pitch, the compressor, noise reduction, the limiter and ducking can't be animated. They always change the clip's own settings, even with an action selected.

### The volume line

Every clip with sound, except a nest clip, draws a thin white line over its waveform: the level you hear from that clip over time. It is the clip's volume and its volume actions, with the fades, crossfades, ducking and the track's volume folded in. The top of the clip's audio part is +30 dB (3200 %) and the bottom is −60 dB or quieter. A clip you can't hear, because it's muted, its track is muted, another track is soloed or its sound is switched off, has its line along the bottom. The line starts below the action lane and is drawn only where the audio part is at least 12 pt tall, so at the Small track height it may not show. A small square in the action colour marks each action end that sets the volume.

- **Drag the line** up or down to change the level in force at that point. Inside an action that sets the volume, the drag changes that action's end level. After such an action, it changes the end level of the last one before the point. Otherwise it changes the clip's own Volume. The drag is relative and in dB, and the new value is shown beside the pointer ("+2.5 dB", or "−∞ dB" at silence). Drag below where you pressed, all the way to the bottom of the line, to go to silence. The level stops at 3200 %. One drag is one undo step, "Set Volume".
- **⌥-click the line** to add a point there. A point is an action, not a keyframe: Frame Job adds an action that runs from the end of the previous action (or the clip's start) to where you clicked, ending at the level the line already has there, so the click on its own changes nothing you hear. Keep the mouse down and drag to move the new point's level. Inside an action that changes only the volume, the click splits that action in two at the point instead. Both halves keep its curve, so a linear action sounds the same until you drag, while an eased one is eased again on each side of the point. The click beeps, and adds nothing, inside an action that also changes something else or that runs past the clip's end (as one can after a trim), or within one frame of the start of the action it is in or of the previous action's end. Adding a point is one undo step, "Add Volume Point".
- To move a point in time, drag its action band. ⇧-click and double-click on the line act on the clip, as they do anywhere on it. The fade handles, the action lane and the clip's edges take a press before the line does.
- The line shows what this clip contributes, so it moves with the clip's track volume and ducking, but a drag changes only the clip's own level. On a silenced clip the line stays on the floor while the readout changes. Inside an open nest, the line is the nest's own mix: it doesn't include the volume, fades, mute or solo of the nest clip and the tracks outside it.

*Agents:* the line is edited with ordinary ops. A drag is `set_audio` with `volume`, or `set_action_end` with `{"audio": {"volume": …}}` on the action in force. A point is `add_action` (`at` the previous action's end, `duration` up to the point) and `set_action_end`, and splitting an action adds `set_action` to shorten it and, for an eased one, to give the new half its curve.

### Normalize

**Normalize** sets each selected clip's volume from a measurement of the clip. It's the button in the Volume section, and it's also **Clip ▸ Normalize**; both follow the mode chosen in the Normalize row.

- **Loudness** (the default) sets each clip's volume so its integrated loudness (BS.1770, as the export plays it) reaches the target, **−16 LUFS** unless you choose another. Every clip goes to the same target, so this is how you match clips. A clip whose true peak would pass **−1 dBTP** at that volume gets its **Limiter** turned on at −1 dBTP in the same step, and its volume is the one that reaches the target through the limiter; a clip that already has a limiter keeps it, with its ceiling lowered to −1 dBTP if it was higher. A clip that would need more than 3200 % stops there and lands quieter than the target. A volume can go down as well as up. A mono clip is measured as the export plays it, on both channels, which reads 3 dB louder than the file on its own. A quiet desktop USB microphone recording, for example, measures −41.7 LUFS with peaks at −18.5 dBTP; one press takes it to −16 LUFS with the limiter holding −1 dBTP.
- **Peak** sets each clip's volume so its loudest moment reaches **−1 dBFS**.

- **It measures the material, not the mix.** The level is read from the clip's cached waveform (Peak) or loudness analysis (Loudness) over the part of the file that actually plays. The clip's volume, fades, ducking, mute and solo don't affect the reading, and neither do noise reduction or the compressor. Mix to mono and pan on a stereo clip do count in Loudness mode.
- **It replaces the volume** rather than multiplying it, so pressing it a second time changes nothing (the second press beeps).
- **Each clip gets its own gain.** In Peak mode that doesn't match levels across a selection; in Loudness mode it does. However many clips are selected, it is one undo step, named "Normalize", which takes back the limiter it turned on along with the volume.
- **It writes the clip's base level**, even when the playhead is inside an action. With an action selected, the button carries a small boxed "clip" tag to show this.
- **It leaves Mute alone.**
- **It can go past 400 %.** A quiet recording, such as a desktop USB microphone's, is turned up as far as it needs, up to the 3200 % ceiling (about +30 dB). Only a clip whose peak is quieter than about −31 dBFS can't reach −1 dBFS. It is turned up to 3200 % and stops there.

Some clips in a selection are skipped and the rest are still normalized: nests (their level lives in the clips inside them), shapes, titles and silent movies. Normalize also skips a clip whose waveform (or, in Loudness mode, loudness) hasn't been analysed yet, and a clip that is silent over the part that plays. Loudness mode also skips a clip that plays for under 0.4 s and one that is quieter than −70 LUFS throughout. When nothing in the selection can be normalized, the button and the menu item are disabled, and a press that does nothing beeps.

*Agents:* `normalize_clip` (`clips`; optional `mode`, `"peak"` or `"loudness"`, default `"loudness"`, or `"peak"` when only `peak_db` is given; in Peak mode optional `peak_db` from −60 to 0, default −1; in Loudness mode optional `target_lufs` from −50 to −5, default −16). An argument of the other mode is refused by name. In Peak mode it answers each clip's `result_db`; in Loudness mode each clip's `measured_lufs` and `true_peak_dbtp` (the Loudness row's numbers), `volume`, `limiter` (the clip's limiter after the edit, `{ceiling_db, release}`, or null when only the volume was written), `result_lufs`, `result_true_peak_dbtp` (held at the limiter's ceiling) and `limited_by` (`"max_gain"` or null). Both list every skipped clip under `skipped` with the reason. The tool doesn't read the mode chosen in the Volume section; it uses its own `mode`.

## Fades

| Control | What it does | Range | Default |
|---|---|---|---|
| Fade in | How long the sound takes to rise from silence at the clip's start. Quick picks: 0, 0.25, 0.5, 1, 2 s. | 0–10 s | 0 |
| Fade out | How long the sound takes to fall to silence at the clip's end. Same quick picks. | 0–10 s | 0 |
| In shape | The curve of the fade in: Linear, S-Curve, +3 dB or −3 dB (see below). | four shapes | Linear |
| Out shape | The curve of the fade out, the same four. | four shapes | Linear |

In the inspector, a fade length is stored as you type it, not rounded to whole frames. The section summary shows both lengths ("0.50 · 1.00 s"), or "none".

A fade is measured from the clip's own edges. Its shape says how the level moves across it:

- **Linear**: a straight-line ramp in level, the same amount every moment. The default.
- **S-Curve**: starts and ends gently and moves fastest in the middle.
- **+3 dB**: rises quickly at first and levels off; halfway through it is 3 dB under full. Good for a fade in that should be heard straight away.
- **−3 dB**: starts slowly and gathers speed; halfway through it is far quieter. Good for a fade out that should feel long.

The shapes are always the clip's own setting, even with an action selected. It travels with the clip when you move it, and it stays at the edge when you trim. Where a fade in and a fade out overlap, or a fade is longer than the clip, the two multiply, which gives a dip in the middle rather than a jump.

### Fade handles on the timeline

Every clip with sound has a small square handle at each top corner of its audio area. Drag the left handle inward to set the fade in, or the right handle inward to set the fade out. The handle then sits at the end of the fade.

- The fade length snaps to whole frames and can't be longer than the clip.
- Fade handles don't snap to clip edges, markers or the playhead, because a fade is a length, not a position.
- Each drag is one undo step.
- Fade handles don't respond on a locked track.

The handles and the inspector rows change the same two settings.

*Agents:* `set_audio` with `fade_in` / `fade_out` in ticks, and `fade_in_shape` / `fade_out_shape` (`linear`, `s_curve`, `plus_3db`, `minus_3db`).

## Ducking

Ducking lowers every *other* clip while this one plays. The usual use is to turn on ducking for a voice-over clip so the music drops under it.

| Control | What it does | Range | Default |
|---|---|---|---|
| Duck other audio | Turns ducking on for this clip. | on / off | off |
| Duck by | **Clip Length**: the others stay down for the clip's whole length. **Speech**: they go down only while this clip's speech plays. | Clip Length / Speech | Clip Length |
| Level | How loud the other clips are while this one plays. Quick picks: 0, 10, 20, 30, 50 %. | 0–100 % | 20 % |
| Attack | How long the other clips take to fall to Level, starting from this clip's first frame. Quick picks: 0.1, 0.25, 0.5, 1 s. | 0–5 s | 0.5 s |
| Release | How long they take to come back up, starting after this clip ends. Quick picks: 0.25, 0.5, 1, 2 s. | 0–5 s | 1 s |
| Pre-roll | With Duck by Speech, how long before each stretch of speech the others start going down. Quick picks: 0, 0.25, 0.5, 1 s. | 0–5 s | 0.5 s |
| Hold | With Duck by Speech, how long after each stretch of speech the others stay down before the release. Same quick picks. | 0–5 s | 0.5 s |

Level, Attack, Release and Duck by are disabled until ducking is turned on, and Pre-roll and Hold until Duck by is Speech.

Attack, Release, Pre-roll and Hold are stored as you type them, not rounded to whole frames.

With **Clip Length**, ducking follows the clip's length on the timeline, not whether anyone is talking. The other audio stays lowered for the whole length of the ducking clip, through pauses, and comes back up only after the clip ends. You can therefore see exactly when ducking applies by looking at the timeline. If the attack is longer than the clip, the level never fully reaches Level, and the release starts from wherever it got to.

### Duck by Speech

With **Speech**, the others go down only while this clip's speech plays: the attack starts Pre-roll before each stretch of speech, the level holds until Hold after it ends, and the release follows. Stretches close enough that their pre-roll and hold meet count as one, and a breath under 0.2 s between words doesn't lift the music.

- **Where the speech is comes from the clip's file.** Frame Job detects speech in every file with sound when it's imported, on your Mac, the same detection Remove Silences uses. Choosing Speech saves where that file's speech is in the project, in the same undo step, so the preview, every export and an agent all hear the same thing. A file keeps the speech it was given; it isn't detected again.
- **Speech can't be chosen yet** while a selected file's speech is still being detected, or for a clip that isn't a file with sound (a nest, a title). Try again in a moment.
- **The timeline shows it.** A clip that ducks by speech has a thin yellow line across its waveform: high where the others play at full level, low where they're ducked. It follows the clip's speed, reverse and speed ramps.
- **Where one stretch's release meets the next one's attack**, the others follow whichever is lower, so the level never dips below Level.
- **Relinking** the clip's file to a shorter one keeps the speech that still fits, and relinking it to a file with no sound forgets it.

- **Overlapping duckers multiply.** Where two ducking clips overlap, their levels multiply: two at 50 % give 25 %.
- **A silent ducking clip still ducks.** Ducking is read from the clip's place on the timeline, so a ducking clip that is muted, silenced by a solo, or has its audio switched off still lowers the others. Turn ducking off to stop it.
- **Inside a nest**, a ducking clip lowers the rest of the project over the part of it that plays. Ducking on the nest clip itself lowers it over the nest's whole length.

*Agents:* `set_audio` with `duck: {level, attack, release, mode, pre_roll, hold}`, or `duck: null` to turn it off. `mode: "speech"` is Duck by Speech and saves the file's speech in the same step; `set_media_speech` (`media`, `spans`) sets a file's speech spans directly, and `get_project` shows them as `media[].speech`.

## Voice Isolation

Voice Isolation keeps the voice and removes what is around it: background noise, music, and the echo of the room. It uses Apple's on-device voice model, so nothing leaves your Mac.

| Control | What it does | Range | Default |
|---|---|---|---|
| Isolate voice | Turns isolation on at 80 %, or off. | on/off | off |
| Amount | How much of the isolated voice replaces the clip's own sound. Quick picks: 50, 80, 100 %. | 0–100 % | 0 (off) |
| Status | Read-only: "Rendering…", "Ready", "Plays without it at this speed", "Waits for the reversed copy", or "Not rendered:" and the reason. With several clips selected it reads "—". | — | Off |

At 80 % the pauses between words drop by about 14 dB and keep a little of the room, so the voice doesn't sit in dead silence. At 100 % the pauses are silent. Isolation also reduces room echo, so there is no separate de-reverb control.

The isolated voice is worked out once for each clip, in the background, when you turn it on. Until it is ready the clip plays without it, and the editor switches over by itself when it is. Changing Amount takes effect at once and doesn't work it out again; trimming or slipping the clip does, because the clip then plays a different part of its file. An export waits for every isolated clip to be ready ("Preparing…"), so a file is never written without it.

Isolation comes first, before the channel choice, the EQ, noise reduction and the compressor. You can use it together with Noise Reduction, which then works on the isolated sound.

Isolation plays only on a clip at normal speed. A clip with a speed change, a speed ramp or a freeze frame plays without it, and the Status says so. A reversed clip is isolated once its reversed copy is ready.

*Agents:* `set_audio` with `isolation` from 0 to 1 (0 is off). The render's status isn't in `get_project`; an export waits for it.

## Voice Effect

Voice Effect puts one of sixteen effects on the clip's sound, built from Apple's own audio units. The effects come in four groups:

| Group | Effects |
|---|---|
| Voice | **Pitch** shifts the voice up or down without changing its speed; **High** and **Deep** shift it up 5 or down 5 semitones and brighten or warm it; **Robot** makes it metallic and buzzing. |
| Tone | **Bass** and **Treble** boost the lows or the highs by up to 10 dB; **Bright** lifts the presence; **Telephone** and **Radio** squeeze it into a narrow band, the radio with some crackle. |
| Character | **Lo-Fi** makes it gritty and dull; **Distorted** overdrives it. |
| Space | **Echo** repeats it every quarter of a second; **Room**, **Hall**, **Plate** and **Cathedral** put it in a space, from a small room to a long cathedral tail. |

| Control | What it does | Range | Default |
|---|---|---|---|
| Effect | The effect, or None. The popup names each one with its group, for example "Space: Hall". Picking one keeps the Amount and sets Pitch back to the effect's own. | None or one of 16 | None |
| Amount | How much of the effect: 0 leaves the clip as it is, 100 % is the full effect. Every boost, mix and shift scales with it. Quick picks: 25, 50, 100 %. | 0–100 % | 100 % |
| Pitch | The shift in semitones, for Pitch, High and Deep only (greyed out for the others). Quick picks: −12, −5, 0, 5, 12. | −12 to 12 st | 0 for Pitch, +5 for High, −5 for Deep |
| Status | Read-only, in the same words as Voice Isolation's. With several clips selected it reads "—". | — | Off |

Each effect keeps the clip at about the loudness it had, so switching between them doesn't jump in level.

Like Voice Isolation, the effect is worked out once for each clip in the background, and until it is ready the clip plays without it. Changing the effect, Amount, Pitch, the Isolation amount, or trimming the clip works it out again. An export waits for every clip's effect to be ready ("Preparing…").

The effect comes right after Voice Isolation: an isolated clip's effect is made from its isolated voice, so it waits for that first. Everything after it in the list (the channel choice, the EQ, noise reduction and the rest) works on the effected sound.

The effect plays only on a clip at normal speed, as Voice Isolation does. A reverb or an echo stops at the end of the clip; it doesn't ring on into the next one.

*Agents:* `set_audio` with `voice`: `{kind, amount, pitch}`, where `kind` is `pitch`, `high`, `deep`, `robot`, `bass`, `treble`, `bright`, `telephone`, `radio`, `lofi`, `distorted`, `echo`, `room`, `hall`, `plate` or `cathedral`; `amount` 0–1 (1 if left out); `pitch` −12 to 12, for `pitch`, `high` and `deep`. A new `kind` keeps a stored `pitch` unless `pitch: null` is sent with it, and `voice: null` turns the effect off. The render's status isn't in `get_project`; an export waits for it.

## Channels

| Control | What it does | Default |
|---|---|---|
| Play | Both plays the file as it is. Left Only plays the left channel from both sides, Right Only the right channel, and Swap Left and Right exchanges them. | Both |

Use Left Only or Right Only for a microphone recorded onto one channel of a stereo file: the voice then plays from both speakers at its own level, and the Volume section's Loudness read-out counts it that way. The choice comes right after voice isolation, before the EQ and the mono fold. A mono file has only one channel, so the choice has no effect on it.

*Agents:* `set_audio` with `channels`: `"both"`, `"left"`, `"right"` or `"swapped"`.

## EQ

The EQ shapes the clip's tone. Its first row draws the response: how much each frequency from 20 Hz to 20 kHz is turned up or down, the hum notches included. The line is greyed while Bypass is on, and is not drawn when the selected clips' settings differ.

| Control | What it does | Range | Default |
|---|---|---|---|
| Bypass | Silences the EQ without losing its settings, to compare with and without. | on / off | off |
| Rumble Cut | Turns the High-pass on at 80 Hz and 24 dB/oct: takes out traffic, handling noise and desk thumps. | — | — |
| De-mud | Sets Band 1 to −3 dB at 300 Hz: less boom and boxiness. | — | — |
| Presence | Sets Band 3 to +3 dB at 4 kHz: words easier to follow. | — | — |
| High-pass | Turns down everything below its Frequency. Slope 12 or 24 dB/oct. | 20–20000 Hz | 80 Hz, 12 dB/oct |
| Low shelf | Turns everything below its Frequency up or down by its Gain. | ±24 dB | 100 Hz, 0 dB |
| Band 1, 2, 3 | Turns the frequencies around its Frequency up or down by its Gain; Q sets how narrow (higher is narrower). Quick picks for Q: 0.5, 0.7, 1, 2, 4. | ±24 dB, Q 0.1–10 | 300, 1000, 4000 Hz; 0 dB; Q 1 |
| High shelf | Turns everything above its Frequency up or down by its Gain. | ±24 dB | 8000 Hz, 0 dB |
| Low-pass | Turns down everything above its Frequency. Slope 12 or 24 dB/oct. | 20–20000 Hz | 12000 Hz, 12 dB/oct |

Each part has its own checkbox; ticking it turns that part on at its default. The presets each set only their own part and turn Bypass off, so they combine: Rumble Cut, De-mud and Presence together are a common starting point for a voice. A Gain of 0 dB changes nothing. Reset turns the whole EQ off.

The EQ runs after the channel choice and before hum removal and noise reduction. It doesn't change the Loudness read-out or what Normalize measures.

*Agents:* `set_audio` with `eq: {high_pass, low_shelf, band_1, band_2, band_3, high_shelf, low_pass, bypass}`: each part `null` (off) or an object — `high_pass` and `low_pass` `{frequency, slope}`, the shelves `{frequency, gain_db}`, the bands `{frequency, gain_db, q}`. A part you leave out keeps what is stored, `{eq: {high_pass: {}}}` turns one on at its defaults, and `eq: null` turns the EQ off.

## Hum

| Control | What it does | Range | Default |
|---|---|---|---|
| Remove hum | Turns hum removal on. | on / off | off |
| Mains | The mains frequency where the recording was made: 50 Hz in most of the world, 60 Hz in the Americas and parts of Asia. | 50 or 60 Hz | 60 Hz |
| Depth | How far each notch turns the hum down. Quick picks: 12, 24, 30, 48. | 6–60 dB | 30 dB |
| Harmonics | How many notches: the mains frequency and its multiples. Quick picks: 1, 2, 4, 8. | 1–8 | 4 |

Each notch is narrow — about a tenth of the mains frequency wide whatever the depth — so the voice between the notches is left alone. Hum removal runs after the EQ.

*Agents:* `set_audio` with `hum: {frequency, depth_db, harmonics}`, `hum: {}` to turn it on at the defaults, or `hum: null` to turn it off.

## Noise Reduction

| Control | What it does | Range | Default |
|---|---|---|---|
| Remove noise | How much steady background noise to remove. Quick picks: 0, 25, 50, 75, 100 %. | 0–100 % | 0 (off) |
| Depth | Read-only: the most any part of the spectrum is turned down, for example "6 dB at most". It reads "floor removed" at 100 % and "off" at 0. | — | off |

The noise reducer works out the background noise level from the clip itself, so you don't need to give it a sample of the noise or a stretch of silence. It then turns down whatever sits at that level. It works well on hiss, hum and fan noise.

It is not a gate. It doesn't silence the gaps between words, and it can't remove sudden sounds such as a door slam. A long held note may eventually be treated as noise.

*Agents:* `set_audio` with `noise_reduction` from 0 to 1.

## Gate

The gate turns the clip down in its pauses: when the sound falls below the threshold, it is pushed further down, so room noise and breaths between phrases get quieter while the speech itself is untouched. Its checkbox is labelled **Gate pauses**.

| Control | What it does | Range | Default |
|---|---|---|---|
| Gate pauses | Turns the gate on. | on / off | off |
| Threshold | How far under the clip's loudness the gate opens. Quick picks: −20, −15, −10, −6. | −40 to 0 dB | −10 dB |
| Ratio | How strongly sound under the threshold is turned down: at 4:1, each dB under the threshold becomes 3 dB further down. Quick picks: 2, 4, 10, 20. | 1–20 :1 | 4:1 |
| Range | The most the gate ever takes away. Quick picks: 10, 20, 40, 80. | 1–80 dB | 20 dB |
| Attack | How quickly it opens when the sound rises. Quick picks: 1, 5, 10 ms. | 0–100 ms | 1 ms |
| Hold | How long it stays open after the sound falls, so the ends of words aren't clipped. Quick picks: 0, 50, 100, 200 ms. | 0–500 ms | 50 ms |
| Release | How quickly it closes after the hold. Quick picks: 50, 100, 250, 500 ms. | 1–2000 ms | 100 ms |
| Status | Read-only: where the threshold lands, for example "Opens above −51.7 dBFS"; "Waits for its loudness" until the clip's loudness analysis has run; or "Not gating:" and why — "too short" (under 0.4 s), "too quiet" or "no sound". | — | — |
| Loudness | Read-only: the clip's loudness the threshold is measured from, for example "−41.7 LUFS". | — | — |

**The threshold follows the clip.** It is set in dB under the clip's own loudness — the Volume section's Loudness figure, measured before the volume, fades and ducking — rather than at a fixed level, so the same setting works on a quiet recording and a loud one. A trim, a pan change or a different channel choice moves the loudness, and the threshold moves with it. Until the clip's loudness has been measured the clip plays without the gate, and the preview picks it up by itself once the measurement lands; an export waits for it (see [Exporting](export.md)).

The gate runs after noise reduction and before the de-esser and the compressor. It acts on the clip's sound before the volume, so moving the Volume slider doesn't change where it opens.

*Agents:* `set_audio` with `gate: {threshold_db, ratio, range_db, attack, hold, release}` (the times in ticks), `gate: {}` to turn it on at the defaults, or `gate: null` to turn it off.

## De-esser

The de-esser tames sibilance — the hard "s", "sh" and "t" sounds a close microphone exaggerates. It listens to the sound above its frequency and, while that band is louder than the threshold, turns only that band down, so the rest of the voice keeps its level. Its checkbox is labelled **Reduce sibilance**.

| Control | What it does | Range | Default |
|---|---|---|---|
| Reduce sibilance | Turns the de-esser on. | on / off | off |
| Frequency | Where the sibilant band starts. Quick picks: 4000, 5000, 6000, 8000 Hz. | 2000–12000 Hz | 6000 Hz |
| Threshold | How loud the band must get, relative to the clip's loudness, before it is turned down. Quick picks: −6, −3, 0, 3. | −30 to +20 dB | 0 dB |
| Range | The most the band is turned down. Quick picks: 3, 6, 10. | 1–24 dB | 6 dB |
| Status | Read-only: "Acts above" and the threshold in dBFS, "Waits for its loudness", or "Not de-essing:" and why. | — | — |
| Loudness | Read-only: the clip's loudness the threshold is measured from. | — | — |

It never makes any frequency louder. Right at the Frequency it takes about half the range; the full range is reached about an octave above. Its threshold follows the clip's loudness the way the gate's does, and it runs after the gate and before the compressor.

*Agents:* `set_audio` with `de_esser: {frequency, threshold_db, range_db}`, `de_esser: {}` to turn it on at the defaults, or `de_esser: null` to turn it off.

## Compressor

The compressor evens out loud and quiet passages by turning down whatever goes above the threshold. Its checkbox is labelled **Smooth volume levels**.

| Control | What it does | Range | Default |
|---|---|---|---|
| Smooth volume levels | Turns the compressor on. | on / off | off |
| Threshold | The level above which the compressor starts turning the sound down. Quick picks: −30, −24, −18, −12, −6. | −60–0 dB | −18 dB |
| Ratio | How strongly it turns down sound above the threshold. 1:1 does nothing; 20:1 acts like a limiter. Quick picks: 1.5, 2, 3, 4, 8, 20. | 1–20 :1 | 3:1 |
| Attack | How quickly it reacts when the level rises. Quick picks: 1, 5, 10, 30, 100 ms. | 0–200 ms | 10 ms |
| Release | How quickly it lets go when the level falls. Quick picks: 50, 100, 200, 500, 1000 ms. | 10–2000 ms | 200 ms |
| Makeup | Gain added afterwards to make up what the compressor took away. Quick picks: 0, 3, 6, 12. | 0–24 dB | 0 dB |

The defaults are a gentle setting for speech. The section summary shows the ratio ("3.0:1"), or "off".

The compressor acts on the clip's sound before the volume, fades and ducking, so moving the Volume slider doesn't change how hard it compresses. If noise reduction is on, it runs before the compressor, which means the threshold is compared against sound that has already been cleaned. Attack and release are measured in milliseconds and aren't rounded to frames.

*Agents:* `set_audio` with `compressor: {threshold_db, ratio, attack, release, makeup_db}` (attack and release in ticks), or `compressor: null` to turn it off.

## Limiter

The limiter holds the clip's peaks under a ceiling, so a quiet recording can be turned up to a delivery loudness without its loudest moments clipping. It is a true-peak limiter: it looks between the samples, where a peak can sit higher than any sample, and it looks a little ahead, so it turns the sound down smoothly just before a peak rather than after it.

| Control | What it does | Range | Default |
|---|---|---|---|
| Limit peaks | Turns the limiter on. | on / off | off |
| Ceiling | The highest true peak the clip may reach, after its volume. Quick picks: −1, −2, −3, −6. | −24–0 dBTP | −1 dBTP |
| Release | How quickly the level recovers after a peak. Quick picks: 50, 100, 200, 500. | 1–1000 ms | 100 ms |

The limiter is last in the clip's chain, after the Mix section, and it knows the clip's volume: the ceiling is where the clip's peaks land *after* the Volume slider, so turning the volume up makes the limiter work harder rather than pushing the clip past the ceiling. Fades and ducking only turn a clip down, so they never take it over the ceiling either. Normalize in Loudness mode turns it on for you when a clip needs it.

Each clip's limiter holds that clip alone. Every export also runs a **master limiter** over the whole mix, the same kind of limiter at −1 dBTP (or the export's own ceiling), so two limited clips crossfading, a nest turned up or an action raising a clip's volume still can't take the file past it. The preview has no master limiter. See [Exporting](export.md#loudness).

A track that has a limited clip on it plays every clip on it 3.3 ms later inside Frame Job and places them 3.3 ms earlier to match, so everything still lands on its frame. As with noise reduction, a clip that starts within the first 3.3 ms of the timeline loses that much of its start, and the last 3.3 ms of the track are not heard.

*Agents:* `set_audio` with `limiter: {ceiling_db, release}` (`ceiling_db` from −24 to 0, `release` in ticks from 600 to 600000; `limiter: {}` turns it on at the defaults), or `limiter: null` to turn it off.

## Mix: pan, mono, Detach Audio and Attach Audio

| Control | What it does | Range | Default |
|---|---|---|---|
| Pan | Moves a stereo clip's balance left (−) or right (+). Quick picks: −100, −50, 0, 50, 100. | −100 to 100 | 0 |
| Position | Read-only: "centre", or the side and amount, for example "left 40". | — | centre |
| Mix to mono | Averages all of the clip's channels into one and sends it to every channel. | on / off | off |
| Detach Audio | Moves the clip's audio onto its own clip (see below). | — | — |
| Attach Audio | Merges a detached sound back into its picture (see below). | — | — |

The section summary reads "centre", "mono" or the pan position. Reset sets the pan back to centre and turns mono off.

- **On a stereo clip, Pan is a balance control.** At the centre, nothing changes. Moving it one way turns that side up and the other side down, keeping the total power steady. At hard left or hard right, the side it went to is about 3 dB louder than at the centre.
- **Pan has no effect on a clip whose source is mono.**
- **Turn on Mix to mono as well to get a true pan.** The mono fold happens before the pan, so both channels then carry the same signal and Pan places that one signal anywhere from left to right.
- **Mix to mono has no effect on a one-channel source.**

*Agents:* `set_audio` with `pan` from −1 to 1 and `mono`.

### Detach Audio

**Clip ▸ Detach Audio** (⌥⌘D), or the **Detach Audio** button in the Mix section, splits each selected clip's sound onto a clip of its own on the track below. If the clip is already on the bottom track, Frame Job adds a new track underneath for it.

- The original clip keeps its picture, and its audio is switched off.
- The new clip plays only sound. It has the same file, in point, length and speed as the original, and it keeps the original's audio settings and actions.
- The two clips stay **linked**. Each shows a link symbol after its kind icon, and selecting one draws a dashed ring around the other.

Detach Audio is refused, with the reason given, for a clip that isn't a media clip, a clip whose file has no audio track, and a clip whose audio is already switched off. It's also refused when the track below already has a clip where the new audio clip would go. A new track is added only when the clip is on the bottom track.

A clip whose audio is off shows no waveform and no fade handles, and a clip with both its picture and its sound switched off is drawn dimmed.

*Agents:* `detach_audio` (`clip`). `set_enabled` (`clip`, `video`, `audio`) turns either half of a clip back on or off.

### What stays in sync

A linked picture and sound stay in step in time through every edit:

- **Moving** either clip moves both by the same amount. Only the clip you drag changes track, so you can drag the sound onto another track and its picture stays where it is. When a move would take either clip before the start of the timeline, both stop together.
- **Split**, **Duplicate**, **Nest**, **Ripple Delete** and copy and paste take both clips. A split through both pairs the two halves on each side of the cut.
- **Ripple edits, Close Gap and Insert Time** move the other half too. One that would push a sound that starts before its picture past the start of the timeline is refused: "clip … would start before 0: it leads its linked clip … by … ticks".
- **Slip** slips both, as far as the one with less room allows.
- **Delete** on the picture deletes its sound too. Deleting the sound alone keeps the picture, silent. Detach Audio and then deleting the sound is how you remove a clip's sound.
- **Speed** and **Reverse** are refused on a linked clip: "clip … is linked to clip …: Attach Audio before changing its speed or direction". Attach Audio first, change the speed, then detach again.
- A clip on a locked track isn't moved, cut, copied or deleted with its partner.

### J-cuts and L-cuts

Trimming the picture's edge also trims the sound when their edges line up. Trimming the **sound's** edge moves it alone, which is how you make a split edit:

- **J-cut**: drag the sound clip's start edge earlier, so the next shot's sound begins before its picture.
- **L-cut**: drag the sound clip's end edge later, so the sound runs on under the next shot.

W and E trim a sound clip alone in the same way, and a roll (⌥⇧-drag on an edge) of a sound clip moves only the sound's cut.

When the shot before was detached too, its sound sits on the same track as this one's, so a lead would overlap it and become a cross dissolve. **Drag the sound to a track of its own first**, then trim it: on its own track, the lead overlaps nothing.

*Agents:* `trim_start`, `trim_end` and `roll` with `alone: true` move one clip's edge without its linked partner's.

### Attach Audio

**Clip ▸ Attach Audio** (⇧⌥⌘D), or the **Attach Audio** button in the Mix section, merges each detached sound in the selection back into its picture. Either clip can be selected. The picture's audio comes back on with the sound clip's audio settings, and the sound clip is removed. Its track stays.

Attach Audio is refused for a clip that isn't linked to a detached sound, and for a pair that no longer covers the same time, such as a J-cut or an L-cut: "clip …'s picture and clip …'s sound do not cover the same time; trim them to match before Attach Audio". Trim the two to the same start and end, then attach.

*Agents:* `attach_audio` (`clip`), either half.

## Keep pitch when the speed changes

When a clip plays faster or slower, its sound either keeps its pitch or changes pitch like tape. The **Keep pitch** checkbox is in the Speed section of the Clip sub-tab and is on by default. Above ×12 a clip's audio is left out of the mix. See [Speed](speed.md) for speed changes, speed ramps and how their audio is rendered.

*Agents:* `set_audio` with `keep_pitch`, or `set_speed`.

## Crossfading audio across a transition

When two clips on one track overlap with a transition, the transition can also crossfade their sound. Turn on **Crossfade Audio** in the clip's Transition section. The crossfade keeps the combined loudness steady across the overlap. See [Motion and transitions](motion-and-transitions.md).

## Muting and soloing tracks

Each track header has four toggles: eye (hide video), **speaker (mute audio)**, lock, and **headphones (solo)**. You can also right-click a track header or an empty part of a lane for the track's menu, which has the same toggles with checkmarks.

The **Track** menu has the same commands. They act on the track of the first selected clip, or on the front track when nothing is selected:

| Command | What it does |
|---|---|
| **Track ▸ Mute Audio** | Silences every clip on the track. The picture is unaffected. |
| **Track ▸ Solo** | Silences every *other* track in the same container. |
| **Track ▸ Hide Video** | Hides the track's picture and leaves its sound playing. |

How muting and soloing combine:

- **Mute always wins.** A track that is both muted and soloed stays silent.
- **You can solo several tracks.** All the soloed tracks play, and every track in the same container that isn't soloed is silenced.
- **Solo affects only tracks in the same container.** A solo on a timeline track silences the other timeline tracks, and a nest playing on one of them goes silent with it. A solo on a track inside a nest affects only that nest's other tracks.
- **Solo silences the others even if the soloed track is empty**, the way a mixer's solo button works.
- **Solo and mute affect sound only.**
- **Each toggle is one undo step** ("Mute Track", "Solo Track").

A clip's own **Mute** (in the Volume section) silences just that clip.

*Agents:* `set_track` (`track`, plus `muted`, `solo`, `hidden` or `locked`).

## Track volume and pan

Each track has its own **volume** and **pan**, applied on top of every clip on it. Click the fifth switch in the track header (the sliders), choose **Volume and Pan…** in the track's right-click menu, or choose **Track ▸ Volume and Pan…** for the current track. A small panel opens beside the header:

| Control | Range | What it does |
|---|---|---|
| **Volume** | Off, −60 dB … +12 dB | The track's level. The quick picks are −12, −6, −3, 0, +3 and +6 dB. Dragging to the left end turns the track off. The read-out beside it shows the level as a percentage, or "Off". |
| **Pan** | −100 (left) … 100 (right) | Leans the track's sound left or right. The quick picks are −100, −50, 0, 50 and 100. |
| **Reset** | | Puts the volume back to 0 dB and the pan to the centre. |

The sliders switch is lit while a track's volume or pan is not at its default.

How track volume and pan work:

- **They multiply what's on the track.** A clip at 200 % on a track at −12 dB plays at −6 dB. Two pans multiply too: a clip panned left on a track panned left leans further left.
- **Mute still wins.** A muted track is silent whatever its volume.
- **Pan is a balance, like a clip's pan.** It keeps the overall loudness steady as it moves, and it has no effect on a mono source.
- **Nests hear their tracks.** A clip inside a nest plays through its own track inside the nest and through the track the nest clip sits on. Nesting a selection from one track keeps its sound: the nest's copy of that track starts at 0 dB and centre, because the track the nest clip lands on still applies. Clips from the selection's other tracks keep their own track's volume and pan inside the nest, and also get the destination track's. Un-nesting puts the clips back on the timeline's tracks without the nest's track settings. If a nest clip has **Mix to mono** on, pans of the tracks inside it no longer apply.
- **What hears it.** The level meter, the timeline's bars and Remove Silences include track volume. Normalize, the Loudness read-out and a clip's limiter read the clip itself and don't, so a track turned up can take a limited clip past its ceiling.
- **Each change is one undo step**: a drag ("Track Volume", "Track Pan"), a typed value or quick pick, or **Reset** ("Reset Track Mix").
- **The preview and the export match.** Track volume and pan sound the same in both.

*Agents:* `set_track` with `volume` (0–4 as a linear gain, 1 being unity and 4 being +12 dB) and `pan` (−1 to 1).

## Hearing a scrub

When you click or drag along the ruler, you hear the sound under the playhead. Each time the playhead reaches a new frame, Frame Job plays about 80 ms of the mix forward from it, with a 5 ms fade at each end so the pieces don't click. Hold the mouse still and the sound stops within about a tenth of a second; let go and it stops.

- **It's the mix you'd hear playing:** each clip's volume, fades, ducking, pan, mono, mute and solo, and the compressor and noise reduction.
- **Dragging left plays each piece forwards** from the playhead, not backwards, so a word stays recognisable.
- **It's always on.** To silence it, mute or solo tracks, or turn down the Mac's volume.
- **Only a scrub on the ruler is heard.** Stepping with ← and →, clicking a marker in the Document tab's Markers list and an agent's `set_playhead` move the playhead silently.

*Agents:* there is no tool; `set_playhead` is a silent seek.

## The level meter

The level meter is in the timeline bar, just left of the zoom controls. While the timeline plays, it shows the mix you are hearing:

- **Two rows**, one per channel, on a −60 to 0 dB scale.
- **A solid bar** for the average (RMS) level, with a lighter wash behind it showing the instantaneous peak.
- **A peak-hold mark** that stays at the highest recent level for about 1.2 seconds and then falls.
- **A clip cell** at the right end of each row. It lights for 2 seconds whenever a sample reaches full scale.

The meter includes everything that shapes what you hear: each clip's volume, fades, ducking, mute and solo, and the compressor and other effects. At normal speed it shows the mix itself, so two tracks playing the same sound read as one louder sound, and a sound and its inverse read as silence. At other speeds it adds up each track's level, which can read a little higher than the mix. When playback stops, the bars fall back to the floor. If two projects are open, the meter follows the one that is playing. On a very narrow window there isn't room for the meter, so it is hidden.

The screen recorder panel has its own meter for the microphone. See [Screen recording](screen-recording.md).

## Live loudness

Choose **View ▸ Loudness Meter** (⌃⌘L) to show a column at the right of the preview, left of the scopes. While the preview plays at normal speed, it measures the mix you hear, the way loudness standards (EBU R 128, ITU-R BS.1770) do:

- **Two bars**, M and S, on a −48 to 0 LUFS scale. A thin line marks the Normalize target (−16 LUFS unless you changed it).
- **Momentary**: the last 0.4 seconds.
- **Short-term**: the last 3 seconds.
- **Integrated**: everything measured since the last reset, with quiet passages left out as the standard says.
- **True peak max**: the highest true peak since the last reset. It turns coral above −1 dBTP.

Click the **Reset** button at the top of the column to start measuring again. The meter also starts again on its own when you jump to another place: a seek, the loop going round, or playing from somewhere else. Pausing and playing on doesn't reset it, and nor does an edit, a gap between clips or holding a menu open. When playback stops, the figures stay where they were.

The meter measures only at normal speed. At any other speed, Momentary and Short-term show "—" and the column says "Measured only at normal speed."; Integrated and True peak max keep their values. A dash means there isn't a figure yet; "−∞" means digital silence.

The figures are the mix as the preview plays it, before the export's loudness setting and its master limiter, and the column says so. An export with a loudness target changes the level after this point, and the master limiter holds its peaks under the ceiling, so its report can differ. The column is per window and turns off when you close the window.

*Agents:* there is no product tool; an agent reads loudness from an export's report or a clip's loudness read-out.

## Loudness on export

The level meter in the timeline bar shows peaks, not loudness; the Loudness Meter column shows the preview's loudness. To make an export hit a loudness target, such as integrated LUFS with a true-peak ceiling, use the export sheet's loudness option: the export reaches it through its master limiter, which holds every export's peaks under −1 dBTP. A WAV or AIFF can be written at 24 bits. Every export reports what its sound measured, whether or not you normalized it. See [Export](export.md).

## Synchronize Audio

**Clip ▸ Synchronize Audio** lines up two or more clips by their sound. The usual case is a camera clip and a separate audio recorder that captured the same moment. Select the clips, each on its own track, and choose the command. One clip, the **anchor**, stays where it is. Every other clip slides along its own track until its sound plays at the same moment as the anchor's.

The anchor is chosen this way:

1. Among the selected clips that have a picture, the one that starts earliest. If none of them has a picture, all of the clips are considered.
2. If two start at the same time, the one on the rearmost track.
3. If they are still tied, the one created first.

In other words, a camera clip stays put and the recorder moves to it.

### What it does

- **It matches the sound itself.** Each file's sound is analysed once when it's imported, so differences in gain, microphone and room don't stop a match. When both clips contain enough speech, at least 2 seconds as judged by the on-device voice model, only the speech is compared.
- **It searches the trimmed parts first.** Frame Job first looks for a match within the parts of each clip you have trimmed it to. It searches the whole files only if that finds nothing and one of the clips is trimmed. If a recording contains more than one similar stretch, trim the recorder roughly around the camera's sound so it matches the right one.
- **It checks the waveforms.** A match is used only if the two waveforms also line up there, as a clear peak within 48 ms. This keeps two takes of the same words from being treated as one recording. The check also fine-tunes the offset to less than a frame.
- **It corrects drift.** If two clocks run at slightly different rates, the recorder slowly falls out of sync over a long take. When the clips overlap for at least 60 seconds, Frame Job measures that drift and corrects it by playing the clip at a slightly different speed, at most 0.2 % from ×1. The correction is a plain resample, so the pitch moves very slightly with it. Drift is left alone when it is under 5 ms over the overlap, when it is too small to tell from no drift (under three times its own uncertainty), or when the speed it needs is more than 0.2 % from ×1. The corrected speed appears in the clip's Speed section (for example ×1.0004), with Keep pitch turned off. The command shows no drift figure of its own; that speed is where the correction shows. Like any clip at a speed other than ×1 with Keep pitch off, the corrected clip's sound is rendered in the background, so it is briefly silent in the preview after the correction, and again after each trim, split or speed change of it (see [Speed](speed.md)); an export waits for it.
- **It trims the head if needed.** If a clip would have to start before 0:00 to line up, it loses just that much from its start instead, and starts at 0:00 in sync. The anchor is never moved or trimmed.
- **Moves land on whole frames.** Clips move by a whole number of frames. A whole command is one undo step, named "Synchronize Audio".

### The Synchronizing Audio sheet

Matching runs in the background while a **Synchronizing Audio** sheet is shown. The sheet has a progress bar and the line "Matching the sound of N clips…". **Cancel** (Escape) closes it and leaves everything as it was. Nothing moves until a match is found. If you change the project while matching is still running, nothing is applied. Frame Job beeps and the inspector says to choose Synchronize Audio again.

### Confident and weak matches

A match is **confident** when its best candidate is clearly stronger than every other offset: a confidence of at least 10 and at least 1.5 above the next candidate. A confident match is applied straight away.

A match is **weak** when no candidate is confident, but the best one within about 3 seconds of where the clip already sits has a confidence of at least 4. Because a weak match might be unrelated sound, it is never applied without asking. A **Weak match** sheet appears, for example:

> Weak match: move “record.aifc” 0.80 s earlier (trimming 0.80 s off its head)?

A clip that doesn't need to move, only to have its drift corrected, is asked about this way instead:

> Weak match: play “record.aifc” at ×1.0004, correcting its drift?

When several clips are weak, one sheet lists them all, separated by semicolons.

Under the question, the sheet gives the anchor's name, each match's confidence and the rule the match fell short of. **Apply** (the default button) makes every listed change as one undo step. **Cancel** leaves everything as it is.

When nothing matches, the command is refused. The refusal names the offsets it did find and their confidences, so you can move the clip near the right one and try again.

### When it refuses

From the menu, clips in the selection that play no sound (a still, a file with no audio track, a clip with its audio switched off) and nests are left out without a message, and the command needs at least two other clips with sound. To synchronize clips inside a nest, open it (⌘↓) and select them there.

Synchronize Audio is all or nothing. If any clip can't be matched, nothing moves. Frame Job beeps and lists every reason at the foot of the inspector. A clip can't be synchronized when it:

- has no sound to line up by (its analysis found no sound at all)
- is still being analysed. Its sound features or speech haven't been written yet, so try again in a moment.
- holds under 2 seconds of sound
- plays more than 0.2 % away from ×1
- plays at a rate other than its speed setting
- plays reversed
- ramps its speed (a speed action changes its rate over its length)
- would share a track with another clip being synchronized
- would never play at the same time as the anchor once lined up
- matches the anchor's sound, but the waveforms don't line up there (for example two takes of the same words), so they are not one recording
- matches the anchor's sound, but the two share less than 2 seconds of waveform there, too little to confirm it is one recording
- would overlap another clip on its own track after the move
- would lose so much of its head that less than a frame is left

If the clips are already in sync, nothing changes and Frame Job beeps. The menu item is enabled only when at least two selected clips that aren't nests can play sound.

*Agents:* `sync_audio` (`clips`, at least two; optional `anchor`; optional `accept_weak`). A weak match answers `moved: false` and lists its clips under `weak`. Call again with `accept_weak: true` only after the person has agreed to that move. The answer reports each clip's offset, confidence, search, drift and trim. Unlike the menu, the tool refuses a nest or a clip that plays no sound by name.

## Recording sound into a project

The screen recorder can record a microphone with the screen, or record the microphone alone as a voice-over using **Microphone Only**. Either way the voice lands on a new back track named **Microphone**: alongside the picture for a screen recording, or from the playhead for a voice-over. Those clips are ordinary audio clips with all the controls on this page. See [Screen recording](screen-recording.md).

## Related tools

- **Edit ▸ Paste Attributes** (⌥⌘V) copies the copied clip's look onto every selected clip in one step, including its whole sound setup: volume, mute, fades, ducking, noise reduction, compressor, pan, mono and Keep pitch. It's the quickest way to give many clips the same treatment. See [Editing](editing.md). *Agents:* `paste_attributes` with `groups: ["audio"]` for the sound alone.
- **Remove Silences** and **Remove Filler Words** cut by sound. See [Remove Silences and Remove Filler Words](cleanup-tools.md).
- **Generate Captions** transcribes a clip's audio. See [Captions](captions.md).
- **Settings ▸ Playback** holds Background render, which pre-draws graphics frames. It doesn't change the audio output. See [Settings](settings.md).

## Limits

- Volume tops out at 3200 % (about +30 dB). The slider covers 0–400 %; type in the field for more.
- Pan, a clip's or a track's, has no effect on a mono source, and Mix to mono has no effect on a one-channel source.
- Track volume tops out at +12 dB (×4). A track's volume and pan can't be animated, and a track has no EQ or effects of its own yet.
- Ducking follows a clip's length on the timeline, not voice activity.
- Noise reduction removes steady noise only. It doesn't remove sudden sounds and doesn't gate.
- Voice isolation plays only at normal speed: a clip with a speed change, a ramp or a freeze frame plays without it. Two clips cut from one take are isolated separately, and the join between them may differ very slightly.
- A voice effect also plays only at normal speed. A clip has one effect at a time. A reverb or echo tail ends with the clip, and a clip split from a take starts its effect fresh at the cut. The waveform, Normalize's reading and Remove Silences hear the clip without its effect. On a stereo file a reverb or an echo mixes the two channels, so the channel choice picks from the effected pair.
- Only volume, Mute and the fades can be animated with an action. Pan, mono, Keep pitch, the channel choice, the EQ, hum removal, the gate, the de-esser, the compressor, voice isolation, the voice effect, noise reduction, the limiter and ducking always apply to the whole clip.
- On a nest clip, pan, the channel choice, the EQ, hum removal, the gate, the de-esser, the compressor, voice isolation, the voice effect, noise reduction and the limiter have no effect. Set them on the clips inside.
- The gate and the de-esser act only once the clip's loudness has been measured; a clip shorter than 0.4 s, or too quiet to measure, plays and exports without them. An export waits up to five minutes for a measurement still running, then stops naming the clip.
- The gate has no lookahead, so a sound that starts loud after a long pause can lose its first millisecond while the gate opens. Neither stage has a listen or solo control for what it removes.
- The EQ's settings switch at a cut between two clips without a glide; the curve has no handles to drag.
- The channel choice counts in the Loudness read-out; the EQ and hum removal don't.
- Attach Audio needs the picture and its sound to cover exactly the same time. Undo a J-cut or L-cut, or trim the two to match, before attaching.
- A linked clip's speed and direction can't change until you attach its audio.
- Above ×12 a clip's audio is left out of the mix ([Speed](speed.md)).
- Synchronize Audio corrects drift only up to 0.2 % from ×1. It doesn't work on nests, reversed clips, ramped clips, or clips playing at other rates.
- Normalize, the Loudness read-out and Synchronize Audio need the clip's sound analysis, which runs after import. Until it finishes, those clips are skipped or refused as "still being analysed", and the read-out says "measuring…".
- The loudness read-out and Loudness mode read a clip played at a speed other than ×1, or ramped, to within about 0.5 LU of what plays. A file with more than two channels is measured from a two-channel mix of it.
- The limiter holds each clip on its own. Two limited clips that overlap (in a transition, or on two tracks) can add up past the ceiling, and so can a clip whose volume an action raises above its own Volume setting, a clip inside a nest whose volume is above 100 %, and the first moments after a hard cut from a louder clip on the same track, while the level settles. In an export the master limiter catches all of these; the preview has no master limiter, so they can sound louder while editing.
- Loudness mode's result for a limited clip is a model of the limiter, read from the loudness analysis; the export lands within a few tenths of a LU of it (−15.9 LUFS for the −16 example above).
- The Loudness Meter measures only at normal speed, and only the first two channels of a track with more. It doesn't follow the export's loudness setting or its master limiter.
- Scrubbing plays each piece forwards, even when you drag left, and the level meter stays still while you scrub. The compressor and noise reduction start fresh in each piece, so a scrub through a compressed clip can sound slightly different from playing it.
