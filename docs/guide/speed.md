# Speed, reverse and freeze frames

Frame Job can play a video or audio clip faster or slower, fit a clip to a
length you type, stretch it by dragging its end, ramp its speed up and down
over time, play it backwards, and hold one of its frames still. A constant
speed change moves the clip's end. A speed ramp leaves the clip where it is
and changes how much of the source it plays.

All of these work on **media clips** only, meaning clips of a video or audio
file. A still image, a freeze frame, text, a shape, a graphic, an adjustment
clip and a nest have no source to speed up, so the speed commands are dimmed
for them or leave them out.

## Speed limits at a glance

| Limit | Value |
|---|---|
| Slowest rate | ×0.1 |
| Fastest rate | ×1000 |
| Fastest rate that still has sound | ×12 (with Keep pitch on or off) |
| Freeze frame length, when none is given | 2 s |

Above ×12 the picture keeps playing but the clip's sound is left out of the
preview and the export. Frame Job asks before an edit takes a clip with sound
past ×12 (see [The ×12 question](#the-12-question)).

## Change a clip's speed

### The Speed sheet

Select one or more clips and choose **Clip ▸ Speed…**. The item is available
when the selection holds at least one media clip. Clips of other kinds in the
selection are skipped.

| Control | What it does | Default |
|---|---|---|
| **Rate** | The playback rate, typed as a number (1 = normal, 2 = twice as fast, 0.5 = half speed). The field does not accept a value outside ×0.1 – ×1000. | The rate the selected clips share, or ×1 if they differ |
| **Presets** | Fills in Rate with 0.25×, 0.50×, 1×, 1.5×, 2×, 4×, 10× or 100×. | — |
| **Preserve pitch** | Keeps the sound at its own pitch at the new speed. Turn it off and the pitch rises and falls with the speed, like tape. | The first selected clip's setting (on for a new clip) |

Under the controls, a readout shows the result before you apply it:

- the clip count and the total length before and after, for example
  `3 clips · 00:00:12:00 → 00:00:06:00`
- one line for each clip whose transition starts playing, gets longer or
  gets shorter because of the change, for example
  `clip 7 gains a 0.67 s cross dissolve`
- if a selected clip has a speed ramp:
  `Each speed ramp keeps its shape: the rates it names scale with the base rate.`

**Apply** sets the rate on every listed clip as one undo step, **Set Speed**.
If nothing would change, Apply just closes the sheet.

How the timeline responds:

- The clip's start stays put and its length changes. A faster clip can leave
  a gap after it, and later clips do not move up to fill it.
- A slower clip can run into the clip after it. If the overlap is allowed,
  that later clip gets a transition across the overlap, and the readout names
  it. If it is not allowed, that clip keeps its old speed, and the other
  selected clips still change.
- The new length snaps to a whole frame and never runs past the end of the
  file at the new rate.
- The clip's actions keep their places as fractions of the clip's length.

*Agents:* `set_speed` (a `rate`, or a `duration` to fit, plus an optional
`keep_pitch`).

### The Speed section in the inspector

With media clips selected, the inspector's **Clip** tab has a **Speed**
section on its **Clip** sub-tab. It starts collapsed, and its header shows
the rate, for example `2.00×`.

| Row | What it does |
|---|---|
| **Rate** | The rate, from ×0.1 to ×1000, to two decimal places. A typed value outside that range is clamped to it. Its quick-pick menu offers 0.5, 1, 2 and 4. |
| **Keep pitch** | The same setting as the Speed sheet's Preserve pitch. |
| **Fit to** | Type a length as timecode, and the rate changes so the clip plays in exactly that time. With several clips selected, each is fitted to that length. |
| Note | `Audio is silent above ×12` appears when a selected clip with sound is past the audio limit. |

**Reset** in the section header appears when no action is selected and the
rate is not ×1, and sets it back to ×1. Rate, Reset, Keep pitch and Fit to
each apply to every selected media clip as one undo step: **Set Speed** for
Rate and Reset, **Keep Pitch** for Keep pitch and **Fit to Duration** for Fit
to. While an action is selected, Rate edits that action instead: see
[Edit a ramp in the inspector](#edit-a-ramp-in-the-inspector).

*Agents:* `set_speed` with `duration` is Fit to.

### Rate stretch: ⌥-drag the end edge

Hold ⌥ and drag the **end** edge of a media clip. The clip gets longer or
shorter by changing its speed, not by trimming, so it still plays all of the
source it showed before. The drag snaps like any other edge drag (hold ⌘ to
turn snapping off), shows the result as you drag, and lands as one undo step,
**Rate Stretch**.

- Only the end edge stretches. ⌥ on the start edge is an ordinary trim.
- Only a media clip stretches. On a still, text, shape, graphic or any other
  clip, ⌥-dragging the end edge is an ordinary trim (undo step **Trim
  Clip**).
- A stretch that needs a rate outside ×0.1 – ×1000 does nothing.
- On a locked track the edge does not move.
- On a clip with a speed ramp, the whole ramp stretches with the clip. A
  stretch that would push any of its rates past the limits does nothing.

*Agents:* `rate_stretch` (`clip`, `to_end`).

### Keep pitch

Keep pitch belongs to the clip and is on by default.

- **On:** the voice or music keeps its own pitch at the new speed.
- **Off:** the pitch follows the speed, higher when faster and lower when
  slower, like tape or a record.

Keep pitch always applies to the whole clip, even when an action is selected.
It also controls how a speed ramp sounds (see [Ramp audio](#ramp-audio)).
Above ×12 there is no sound either way.

## Speed ramps

A speed ramp changes a clip's rate over time. For example, it can play at ×1,
speed up to ×4 over half a second, hold there, and slow back down.

A ramp is made of **Speed actions**. These are ordinary actions on the clip's
action lane whose end sets a rate. (For actions in general, see
[Motion and transitions](motion-and-transitions.md).) Each Speed action:

- starts from the rate the clip is playing at when the action begins (the
  clip's own rate, or the rate an earlier Speed action ended on)
- moves to its own end rate along its curve
- keeps that end rate after it finishes, until the next Speed action

A ramped clip **keeps its place and its length** on the timeline. Speeding
part of it up makes it play further into its file, and slowing it down makes
it play less of the file. Its start, its end and every clip around it stay
where they are.

On the timeline, a Speed action's band is labelled `speed` when the track is
tall enough to show labels. When the clip's rate changes, a white line across
its action lane draws the rate over the clip's length: higher where it plays
faster, lower where it plays slower, scaled from the clip's own slowest rate
to its fastest (so a gentle ramp draws as tall as a steep one; the Speed
section has the figures). The line shows at the Medium and Large track
heights and in the Clip tab's lane, and while it is drawn a selected Speed
band leaves out its curve. A clip whose rate never changes draws no line.
The clip's filmstrip and waveform follow the ramp.

### Make a ramp in one step: Clip ▸ Speed Ramp…

Select **one** media clip and choose **Clip ▸ Speed Ramp…**. The item is
available only when exactly one media clip is selected.

The ramp covers the timeline's in/out range if that range lies entirely inside
the clip. Otherwise it covers the whole clip.

| Shape | What it makes | Rate must be |
|---|---|---|
| **Ramp Up** | One action over the span, rising from the current rate to the target and holding it after. | above the rate where the span starts |
| **Ramp Down** | One action over the span, falling to the target and holding it after. | below the rate where the span starts |
| **Speed Dip** | Two actions: a ramp down to the target at the start of the span, a hold, and a ramp back to the starting rate at its end. | below the rate where the span starts |
| **Speed Burst** | Two actions: a ramp up to the target at the start of the span, a hold, and a ramp back to the starting rate at its end. | above the rate where the span starts |

| Control | What it does | Default |
|---|---|---|
| **Shape** | One of the four shapes above. Choosing a shape resets Rate to that shape's default. | Speed Dip |
| **Rate** | The target rate, from ×0.1 to ×1000, with the same **Presets** as the Speed sheet. | ×2 for Ramp Up and Speed Burst, ×0.5 for Ramp Down and Speed Dip |
| **Curve** | How each new action eases: **Ease In Out** or **Linear**. | Ease In Out |
| **Hold** | Dip and Burst only (dimmed for Ramp Up and Ramp Down): how much of the span stays at the target rate. **None**, **25%**, **50%** or **75%**. The rest is split evenly between the two ramps, each rounded down to whole frames and at least one frame long. | 50% |

The readout tries the ramp on every change, including each keystroke in Rate.
Its first line names the shape and the span in timecode, for example
`Speed Dip · the whole clip 00:00:02:00 – 00:00:08:00` (or `the range` when
the ramp covers the in/out range). Its second line shows
the rates it would make, for example `×1 → ×0.5, held 1.50 s, → ×1`. If the
ramp cannot be made, the second line gives the reason instead and **Apply**
is unavailable.

Apply adds the actions as one undo step named after the shape, for example
**Speed Dip**.

Speed Dip is the default because it plays less of the file, so it fits a clip
that already uses its whole file. A rise past the starting rate needs footage
beyond the clip's current end.

*Agents:* `add_speed_ramp` (`clip`, `shape` as `ramp_up`, `ramp_down`,
`speed_dip` or `speed_burst`, `rate`, optional `from` and `to` in clip time,
`curve` and `hold` from 0 to 0.9). It answers the new actions' ids as
`new_actions`.

### Build a ramp by hand

1. Select the clip, put the playhead where the ramp should start, and choose
   **Clip ▸ Add Action** (⌥⌘K). The new action is 1 s long and is selected.
2. Drag the band on the action lane to move or resize it. Set its **Curve**
   in the lane's detail row.
3. In the **Speed** section, set **Rate** to the rate this action should end
   on.

Repeat for each change of speed. Playing or scrubbing into an action selects
it. **esc**, or the lane's **Clip** chip, goes back to editing the clip
itself, and ⌫ removes the selected action.

*Agents:* `add_action`, then `set_action_end` with `patch: {speed: <rate>}`.
`set_action` retimes the action, and `remove_action` removes it.

### Edit a ramp in the inspector

While an action is selected, the Speed section edits that action:

- **Rate** shows the rate the action ends on. If the action does not set a
  rate, Rate shows the rate the clip is playing at the end of that action.
  Typing a rate, or choosing one from the quick-pick menu, sets the action's
  end rate. This turns any action into a Speed action.
- The section header shows no **Reset** while an action is selected. To end
  the action at ×1, type 1 or choose 1 from Rate's quick-pick menu.
- The section header's **Clear** button (shown when the action sets a rate), the row's × on hover, and the row's
  right-click **Remove from action** take the rate out of the action.
- **Keep pitch** still sets the clip's own setting, at the clip's own rate.
- **Fit to** is the clip's alone and cannot be set inside an action. Its row
  is marked ⊘.

### Changing the speed of a ramped clip

**Clip ▸ Speed…**, the Speed section's Rate with no action selected, Fit to
and the ⌥ rate stretch all scale a ramped clip's **whole** ramp by one
factor: the clip's own rate, every end rate and the length of every Speed
action. The ramp keeps its shape. For Speed…, Rate and Fit to, if scaling
would push any rate in the ramp past ×0.1 or ×1000, the scaling stops at that
limit, so the clip's rate can end up short of the rate you asked for. A ⌥
rate stretch that would do so does nothing.

Trims, slips, rolls, splits, freeze frames and transitions also follow the
ramp, so each cut or held frame is the frame the ramp actually plays at that
moment. **Edit ▸ Paste Attributes** never copies a speed or a ramp.
**Detach Audio** gives the separate audio clip the same ramp.

- **Splitting inside a Speed action** keeps the picture continuous at the
  cut, with no repeated or skipped frame. With an Ease Out or Ease In Out
  curve the rate can jump at the cut. With an Ease In or Ease In Out curve
  the second half can end on a different source frame.
- **An action past the clip's end.** After a trim, or after the ramp is
  scaled, a Speed action can lie partly or wholly past the clip's end. You
  can still re-curve it, move it earlier or shorten it; only a change that
  takes it further past the end is refused. Its end rate still counts for
  the ×12 rule, even though that part never plays.
- **Transcripts and captions.** Transcribing a ramped clip places each word
  where the ramp plays it. Captions and word captions made before you change
  a ramp keep their old times, so make them again after editing the ramp
  (see [Captions](captions.md)).

### When a ramp is refused

A ramp may never play past the end of the clip's media file. An edit that
would do so is refused, and the reason names what would fit:

- setting an end rate too high names **the largest end rate that fits**, or,
  if no rate down to ×0.1 fits, the latest clip end that would fit at ×0.1
- moving, resizing or removing a Speed action, or clearing its rate, names
  **the latest clip end that fits**
- a Speed Ramp… preset names **the largest rate that fits**

Speed Ramp… is also refused when:

- the span runs past the clip's end
- the span overlaps an action already on the clip, including one inside a
  Dip's or Burst's hold
- a Dip or Burst span is shorter than two frames
- the rate is on the wrong side of the starting rate (for example, a Ramp Up
  to a rate that is not faster)

A refusal changes nothing. The inspector shows the reason at its foot, and
the Speed Ramp… sheet shows it in its readout.

### Ramp audio

A ramped clip's sound is rendered into a separate file in the background and
saved in the project package. Renders run one at a time, and a new one starts
after each edit that changes a ramp. Each render covers the whole clip's
sound. Undo and redo render again too, because the file from before the edit
is not kept, so the clip is briefly silent after an undo as well.

- **Keep pitch off:** the sound glides smoothly up and down in pitch with the
  rate, like tape, and stays in step with the picture.
- **Keep pitch on:** the sound keeps its own pitch as the speed changes.
  After a steep slow-down (for example ×2 → ×0.5) it can run up to about
  22 ms behind the picture.

While a ramp's sound is still rendering, that clip plays silent in the
preview. An export waits for every ramp it needs (its progress reads
"Preparing…" during the wait) and never writes a silent ramp. If a render
fails, the export fails with "Clip N's speed ramp audio could not be
rendered: …". A failed render is not tried again while Frame Job stays open:
the clip stays silent and exports that need it keep failing until you change
the ramp (which starts a new render) or quit and reopen Frame Job.

## The ×12 question

A clip's sound is left out of the mix whenever it plays faster than ×12. For a
ramped clip, Frame Job looks at the **fastest rate the clip uses anywhere**:
if any rate in the ramp is above ×12, the whole clip is silent, not just the
fast part.

Before an edit takes a clip that has sound from ×12 or below to above ×12, an
alert asks first. For example: “Interview” will be silent at ×16. Frame Job
leaves a clip's audio out above ×12. The picture still plays.

When several clips would cross ×12, the alert counts them: “3 clips will be
silent at ×16.” (or “…at their new speeds.” when their rates differ), followed
by “Frame Job leaves a clip's audio out above ×12. The pictures still play.”

- **Set Speed** applies the edit as asked.
- **Cancel** changes nothing and adds no undo step. The Speed sheet and the
  Speed Ramp… sheet stay open.

The question comes from the Speed sheet, the Speed Ramp… sheet, the Speed
section (Rate, its quick picks, Keep pitch, Reset and Fit to) and the ⌥ rate
stretch. A stretch is put back while the question is up, and Set Speed applies
it again. A clip that was already above ×12, or whose sound is switched off,
is not asked about.

*Agents:* no question is asked. The answer to any edit that takes a clip past
×12 carries `audio_left_out` (the clip ids) and `audio_note` (a sentence
saying the clip is now silent in the preview and the export).

## Reverse a clip

Reverse lives in the **Timing** section of the inspector's **Clip** tab, on the
**Clip** sub-tab. With one clip selected, Timing shows In, Out and Duration
above the Reverse rows. With several media clips selected, it shows only the
Reverse rows, and they apply to every selected media clip as one undo step.

| Row | What it shows or does |
|---|---|
| **Reverse** | A checkbox: play the clip back to front, picture and sound, or forwards again. Undo step: **Reverse**. |
| **Reversed frames** | The state of the backwards copy: `—` (not reversed), `Rendering…`, `Rendered`, `Not rendered` or `Media missing`. |
| **Render Reverse** | Starts the render again after it was cancelled or failed. Available only in the `Not rendered` state. |

Reversing never moves the clip: it keeps its start, its length and its in
point. The in point is counted in the direction the clip plays, so reversing
a trimmed clip shows the other end of the file.

Reverse works together with Speed, Fit to, the ⌥ rate stretch and speed
ramps. The in point and the ramp both count in the direction the clip plays,
so a reversed ramped clip ramps through the file backwards.

### The Reversing sheet

The system's playback cannot play video backwards, so Frame Job renders a
backwards copy of the file once. The copy is kept in the project package and
shared by every reversed clip of that file. When you tick Reverse on a file
with no copy yet, the **Reversing** sheet appears with a progress bar and the
line "Rendering a reversed copy of “name”…" (or "Rendering reversed copies of
N files…"). The status reads "Preparing…" until the render starts.

- When it finishes, the sheet closes and the clip plays backwards.
- **Cancel** stops the render; the sheet reads "Stopping…" until it has. It
  then reads "Stopped. Clips that are still reversed show a slate until their
  frames are rendered — press Render Reverse in the Timing section of the Clip
  tab to try again." and offers **Close**.
- If a file cannot be reversed, the sheet says how many files failed and
  names the first.

Until a clip's backwards copy exists, it shows a slate instead of playing
forwards. Nothing restarts a stopped render by itself: press **Render
Reverse**. Each press renders one file, shared by every reversed clip of
that file, so press it once for each file whose clips still show `Not
rendered`. A reversed copy of a 10-bit source keeps
its 10-bit depth and its colour labels.

A still image needs no rendering, since it looks the same backwards.

*Agents:* `set_reversed` (`clip`, `reversed` true or false; it is required,
not a toggle).

## Freeze frame

**Clip ▸ Freeze Frame** (⇧⌘F) holds the frame under the playhead for 2 s:

1. The clip is split at the playhead.
2. 2 s of empty time opens at the playhead across every unlocked track, so
   everything after it moves later together and stays in sync.
3. A still of that exact source frame fills the gap on the clip's track.

The still keeps the clip's look exactly as it was at that moment, including
position, scale, crop and any action that was moving it, so the held frame
lines up with the frame it froze. The still has no actions of its own. On a
ramped or speed-changed clip it holds the frame actually playing at the
playhead.

To hold a different frame, ⌥⇧-drag the still's body (a slip, undo step
**Slip**). The still stays where it is and holds an earlier or later frame
of the source.

The command works on a **selected** clip under the playhead and is available
only when there is one. It needs a clip with a picture: an audio-only clip,
text, a shape or another still cannot be frozen. If the still would break the
overlap rule, the freeze is refused and nothing changes. Undo step: **Freeze
Frame**.

*Agents:* `freeze_frame` (`clip`, optional `at`, which defaults to the
playhead, and `duration`, which defaults to 2 s). `slip` on a freeze clip
moves the frame it holds.

## Limits

- Speed, Fit to, rate stretch, speed ramps, reverse and freeze frame work on
  media clips only. Via an agent, any other kind of clip is an error, not a
  refusal.
- A rate is always between ×0.1 and ×1000. The Speed and Speed Ramp…
  sheets do not accept a value outside that range, the inspector clamps a
  typed value to it, and a rate stretch beyond it does nothing.
- Above ×12 a clip has no sound. On a ramped clip, one rate above ×12 anywhere
  silences the whole clip.
- A speed ramp never changes the clip's start or length, and an edit that
  would make it play past the end of its file is refused.
- Speed Ramp… works on one clip at a time. From the menu it offers only the
  Ease In Out and Linear curves and four hold values. An agent can use any
  action curve and any hold from 0 to 0.9.
- A ramp's sound is silent in the preview until its render finishes, and
  every ramp edit, undo and redo renders the whole clip's sound again. A
  failed render stays failed until the ramp changes or Frame Job is reopened.
- With Keep pitch on, a ramp's sound can lag the picture by up to about
  22 ms after a steep slow-down.
- A reversed clip shows a slate until its backwards copy has been rendered.
- **Clip ▸ Synchronize Audio** does not take clips that are reversed,
  ramped, or more than 0.2% away from ×1 (see [Audio](audio.md)).
