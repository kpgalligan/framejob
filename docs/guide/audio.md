# Audio

Frame Job mixes sound from every clip that has it: a camera clip, an audio-only file, a microphone recording or a nest. Each clip has its own level, fades, ducking, noise reduction, compressor, pan and mono fold, and each track can be muted or soloed. Two commands do the measuring for you. Normalize sets a clip's level from its loudest moment, and Synchronize Audio lines up a camera and a separate recorder by their sound. The preview and the export use the same mix, so what you hear while editing is what gets written.

## Where audio lives

There is only one kind of track. Any track can hold a clip with sound, whether it is a video file, an audio-only file (a voice-over, music, a recorder's take) or a clip you split off with Detach Audio. A clip with sound shows its waveform in the timeline.

The waveform shows the level of the file itself, so moving the Volume slider doesn't redraw it. It's drawn faded when the clip is muted, when its track is muted, or when another track's solo silences it. A track that holds only sound clips is drawn as a shorter lane than a track with pictures.

When the selection includes at least one clip that plays sound, the Clip tab of the inspector shows a **Sound** sub-tab. A clip counts as having sound when its file has an audio track and its audio is switched on, or when it is a nest that holds audio. The Sound sub-tab has six sections, in this order:

1. **Volume**: level, gain read-out, Mute and Normalize
2. **Fades**: fade in and fade out
3. **Ducking**: lowers every other clip while this one plays
4. **Noise Reduction**
5. **Compressor**
6. **Mix**: pan, mix to mono and Detach Audio

Noise Reduction, Compressor and Mix appear in the order the sound passes through them. Volume, the fades and ducking are applied last, like a fader.

Every section header has a summary and a Reset button that appears when the section differs from its default. The summaries read:

| Section | Summary |
|---|---|
| Volume | "muted", "silent" (at 0 %), or the gain, for example "+3.5 dB" |
| Fades | both lengths, for example "0.50 · 1.00 s", or "none" |
| Ducking | the duck level, for example "20%", or "off" |
| Noise Reduction | the amount, for example "50%", or "off" |
| Compressor | the ratio, for example "3.0:1", or "off" |
| Mix | "centre", "mono", or the pan position, for example "left 40" |

 When you change a control with several clips selected, the change goes to all of them. A control whose clips hold different values is marked mixed.

### Sound on a nest

A nest clip has the same Sound sub-tab, but not every control reaches the clips inside it:

- **Volume, Mute and the fades** on a nest clip scale everything inside it. Turning a nest down turns all of it down, and muting it silences all of it.
- **Mix to mono** on a nest clip folds the nest's whole mix.
- **Ducking** on a nest clip lowers the rest of the project for the nest's whole length.
- **Pan, the compressor and noise reduction** set on a nest clip have no effect. Open the nest (⌘↓) and set them on the clips inside.

*Agents:* `set_audio` (`clips`, `patch`) changes any of these properties on one or more clips. Its patch keys are `volume`, `muted`, `fade_in`, `fade_out`, `duck`, `mono`, `keep_pitch`, `pan`, `compressor` and `noise_reduction`. Setting `duck` or `compressor` to null turns it off. `get_project` reads them back.

## Volume

| Control | What it does | Range | Default |
|---|---|---|---|
| Volume | The clip's level as a percentage. Quick picks: 0, 50, 100, 150, 200, 400. | 0–400 % | 100 % |
| Gain | Read-only: the volume in dB (for example "+6.0 dB"), or "silent" at 0 %. | — | +0.0 dB |
| Mute | Silences the clip without changing its volume. | on / off | off |
| Normalize | Sets the volume from the clip's own loudest moment (see below). | — | — |

The section's summary reads "muted", "silent" or the gain in dB. Reset puts the volume back to 100 % and turns Mute off.

You can animate volume, Mute and the fades with actions. While an action is selected, the Volume row, the Mute checkbox and the Fade in and Fade out rows write that action's end state, so a level moves across the action's span. Pan, Mix to mono, Keep pitch, the compressor, noise reduction and ducking can't be animated. They always change the clip's own settings, even with an action selected.

### Normalize

**Normalize** sets each selected clip's volume so that its loudest moment reaches **−1 dBFS**. It's the button in the Volume section, and it's also **Clip ▸ Normalize**.

- **It measures the material, not the mix.** The level is read from the clip's cached waveform over the part of the file that actually plays. The clip's volume, fades, ducking, mute and solo don't affect the reading.
- **It replaces the volume** rather than multiplying it, so pressing it a second time changes nothing (the second press beeps).
- **Each clip gets its own gain.** Normalize doesn't match levels across a selection. However many clips are selected, it is one undo step, named "Normalize".
- **It writes the clip's base level**, even when the playhead is inside an action. With an action selected, the button carries a small boxed "clip" tag to show this.
- **It leaves Mute alone.**
- **The 400 % ceiling applies.** A clip whose peak is quieter than about −13 dBFS can't reach −1 dBFS. It is turned up to 400 % and stops there.

Some clips in a selection are skipped and the rest are still normalized: nests (their level lives in the clips inside them), shapes, titles and silent movies. Normalize also skips a clip whose waveform hasn't been analysed yet, and a clip that is silent over the part that plays. When nothing in the selection can be normalized, the button and the menu item are disabled, and a press that does nothing beeps.

*Agents:* `normalize_clip` (`clips`, optional `peak_db` from −60 to 0, default −1). It answers each clip's `result_db` and lists every skipped clip under `skipped` with the reason.

## Fades

| Control | What it does | Range | Default |
|---|---|---|---|
| Fade in | How long the sound takes to rise from silence at the clip's start. Quick picks: 0, 0.25, 0.5, 1, 2 s. | 0–10 s | 0 |
| Fade out | How long the sound takes to fall to silence at the clip's end. Same quick picks. | 0–10 s | 0 |

In the inspector, a fade length is stored as you type it, not rounded to whole frames. The section summary shows both lengths ("0.50 · 1.00 s"), or "none".

A fade is a straight-line ramp in level from silence (fade in) or to silence (fade out), measured from the clip's own edges. It travels with the clip when you move it, and it stays at the edge when you trim. Where a fade in and a fade out overlap, or a fade is longer than the clip, the two multiply, which gives a dip in the middle rather than a jump.

### Fade handles on the timeline

Every clip with sound has a small square handle at each top corner of its audio area. Drag the left handle inward to set the fade in, or the right handle inward to set the fade out. The handle then sits at the end of the fade.

- The fade length snaps to whole frames and can't be longer than the clip.
- Fade handles don't snap to clip edges, markers or the playhead, because a fade is a length, not a position.
- Each drag is one undo step.
- Fade handles don't respond on a locked track.

The handles and the inspector rows change the same two settings.

*Agents:* `set_audio` with `fade_in` / `fade_out` in ticks.

## Ducking

Ducking lowers every *other* clip while this one plays. The usual use is to turn on ducking for a voice-over clip so the music drops under it.

| Control | What it does | Range | Default |
|---|---|---|---|
| Duck other audio | Turns ducking on for this clip. | on / off | off |
| Level | How loud the other clips are while this one plays. Quick picks: 0, 10, 20, 30, 50 %. | 0–100 % | 20 % |
| Attack | How long the other clips take to fall to Level, starting from this clip's first frame. Quick picks: 0.1, 0.25, 0.5, 1 s. | 0–5 s | 0.5 s |
| Release | How long they take to come back up, starting after this clip ends. Quick picks: 0.25, 0.5, 1, 2 s. | 0–5 s | 1 s |

Level, Attack and Release are disabled until ducking is turned on.

Attack and Release are stored as you type them, not rounded to whole frames.

Ducking follows the clip's length on the timeline, not whether anyone is talking. The other audio stays lowered for the whole length of the ducking clip, through pauses, and comes back up only after the clip ends. You can therefore see exactly when ducking applies by looking at the timeline. If the attack is longer than the clip, the level never fully reaches Level, and the release starts from wherever it got to.

- **Overlapping duckers multiply.** Where two ducking clips overlap, their levels multiply: two at 50 % give 25 %.
- **A silent ducking clip still ducks.** Ducking is read from the clip's place on the timeline, so a ducking clip that is muted, silenced by a solo, or has its audio switched off still lowers the others. Turn ducking off to stop it.
- **Inside a nest**, a ducking clip lowers the rest of the project over the part of it that plays. Ducking on the nest clip itself lowers it over the nest's whole length.

*Agents:* `set_audio` with `duck: {level, attack, release}`, or `duck: null` to turn it off.

## Noise Reduction

| Control | What it does | Range | Default |
|---|---|---|---|
| Remove noise | How much steady background noise to remove. Quick picks: 0, 25, 50, 75, 100 %. | 0–100 % | 0 (off) |
| Depth | Read-only: the most any part of the spectrum is turned down, for example "6 dB at most". It reads "floor removed" at 100 % and "off" at 0. | — | off |

The noise reducer works out the background noise level from the clip itself, so you don't need to give it a sample of the noise or a stretch of silence. It then turns down whatever sits at that level. It works well on hiss, hum and fan noise.

It is not a gate. It doesn't silence the gaps between words, and it can't remove sudden sounds such as a door slam. A long held note may eventually be treated as noise.

*Agents:* `set_audio` with `noise_reduction` from 0 to 1.

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

## Mix: pan, mono and Detach Audio

| Control | What it does | Range | Default |
|---|---|---|---|
| Pan | Moves a stereo clip's balance left (−) or right (+). Quick picks: −100, −50, 0, 50, 100. | −100 to 100 | 0 |
| Position | Read-only: "centre", or the side and amount, for example "left 40". | — | centre |
| Mix to mono | Averages all of the clip's channels into one and sends it to every channel. | on / off | off |
| Detach Audio | Moves the clip's audio onto its own clip (see below). | — | — |

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
- After detaching, you can trim, move and adjust the two clips separately.

Detach Audio is refused, with the reason given, for a clip that isn't a media clip, a clip whose file has no audio track, and a clip whose audio is already switched off. It's also refused when the track below already has a clip where the new audio clip would go. A new track is added only when the clip is on the bottom track.

There is no control that switches a clip's audio back on. To get the original clip's sound back, use Undo, or ask an agent. A clip whose audio is off shows no waveform and no fade handles, and a clip with both its picture and its sound switched off is drawn dimmed.

*Agents:* `detach_audio` (`clip`). `set_enabled` (`clip`, `video`, `audio`) turns either half of a clip back on or off.

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

## The level meter

The level meter is in the timeline bar, just left of the zoom controls. While the timeline plays, it shows the mix you are hearing:

- **Two rows**, one per channel, on a −60 to 0 dB scale.
- **A solid bar** for the average (RMS) level, with a lighter wash behind it showing the instantaneous peak.
- **A peak-hold mark** that stays at the highest recent level for about 1.2 seconds and then falls.
- **A clip cell** at the right end of each row. It lights for 2 seconds whenever a sample reaches full scale.

The meter includes everything that shapes what you hear: each clip's volume, fades, ducking, mute and solo, and the compressor and other effects. When playback stops, the bars fall back to the floor. If two projects are open, the meter follows the one that is playing. On a very narrow window there isn't room for the meter, so it is hidden.

The screen recorder panel has its own meter for the microphone. See [Screen recording](screen-recording.md).

## Loudness on export

The level meter shows peaks, not loudness. To make an export hit a loudness target, such as integrated LUFS with a true-peak ceiling, use the export sheet's loudness option. Every export reports what its sound measured, whether or not you normalized it. See [Export](export.md).

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
- **It corrects drift.** If two clocks run at slightly different rates, the recorder slowly falls out of sync over a long take. When the clips overlap for at least 60 seconds, Frame Job measures that drift and corrects it by playing the clip at a slightly different speed, at most 0.2 % from ×1. The correction is a plain resample, so the pitch moves very slightly with it. Drift is left alone when it is under 5 ms over the overlap, when it is too small to tell from no drift (under three times its own uncertainty), or when the speed it needs is more than 0.2 % from ×1. The corrected speed appears in the clip's Speed section (for example ×1.0004), with Keep pitch turned off. The command shows no drift figure of its own; that speed is where the correction shows.
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

- Volume tops out at 400 % (about +12 dB).
- Pan has no effect on a mono source, and Mix to mono has no effect on a one-channel source.
- Ducking follows a clip's length on the timeline, not voice activity.
- Noise reduction removes steady noise only. It doesn't remove sudden sounds and doesn't gate.
- Only volume, Mute and the fades can be animated with an action. Pan, mono, Keep pitch, the compressor, noise reduction and ducking always apply to the whole clip.
- On a nest clip, pan, the compressor and noise reduction have no effect. Set them on the clips inside.
- No control switches a clip's audio back on after Detach Audio; use Undo.
- Above ×12 a clip's audio is left out of the mix ([Speed](speed.md)).
- Synchronize Audio corrects drift only up to 0.2 % from ×1. It doesn't work on nests, reversed clips, ramped clips, or clips playing at other rates.
- Normalize and Synchronize Audio both need the clip's sound analysis, which runs after import. Until it finishes, those clips are skipped or refused as "still being analysed".
