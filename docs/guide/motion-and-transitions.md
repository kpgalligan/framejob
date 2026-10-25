# Motion, actions and transitions

Frame Job has three ways to make a clip move or change over time. An **action** animates a clip's properties from one state to another over a span you choose: a zoom into a screen recording, a fade of the volume, a title that slides and changes colour. **Motion presets** give a clip a ready-made entrance, exit or continuous movement that stays tied to the clip's two ends. A **transition** plays where two clips on one track overlap. This page covers all three, and what the Clip tab shows while you work on an action.

## Actions

An action is a span of time on one clip. Over that span, the clip's properties ease from whatever they were when the span began to the action's **end state**, along the action's curve. When the span is over, the clip holds the end state until a later action changes it again.

- An action's times are measured from the clip's own start (clip time), not from the start of the timeline.
- Actions on one clip may not overlap. A clip can have as many actions as fit end to end.
- Several actions run in time order. Each one starts from the state the earlier ones left behind.
- A new action's end state is empty, so it changes nothing until you edit it.

### How values change over an action

| Kind of value | What happens over the span |
|---|---|
| Numbers (position, scale, rotation, opacity, crop, volume, a filter's amount, a grade's sliders, a graphic's number properties) | Ramp along the action's curve |
| Colours (shadow, chroma key, text colours, word-caption colours, a graphic's colour properties) | Ramp in OKLab, which keeps the blend's midpoints even. A colour whose two ends are equal stays exact |
| Switches, popups and text (an on/off box, a filter's kind, a font, a graphic's string, boolean or image property) | Hold, then switch to the end value when the action ends |
| Lists (filters, obscure regions) | Ramp entry by entry while both ends have the same number of entries. If the list's length changes, the whole list switches at the end. If one entry changes kind (or a region its shape), only that entry switches at the end and the others still ramp |
| Curves | Always animate. Two curves with the same number of points ramp point by point; a neutral curve lines up with the other curve's points; two curves with different numbers of points blend their values over the action |

The four curves are the same everywhere an action or a transition is eased:

| Curve | Lane label | Feel |
|---|---|---|
| Linear | Linear | Constant speed |
| Ease In | In | Starts slowly, ends fast |
| Ease Out | Out | Starts fast, ends slowly |
| Ease In Out | In Out | Slow at both ends |

A new action from **Add Action** is **Linear**. A zoom action is **Ease In Out**.

### What an action can animate

- **Picture.** Everything in the Picture sub-tab that is a value: transform, opacity, crop, corner radius, shadow, reflection, spotlight, the amounts inside filters and obscure regions. See [Canvas and layers](canvas-and-layers.md).
- **Color.** Light, Colour, Wheels, Curves, Look amount and, on an adjustment clip, Strength and the Qualifier. See [Color grading](color-grading.md).
- **Sound.** The Sound sub-tab's Volume and Fades sections. See [Audio](audio.md).
- **Text.** The Text sub-tab's style, size and colours. See [Captions](captions.md) for word captions.
- **Graphics.** A graphic clip's properties. Numbers and colours ramp; strings, booleans, choices and images switch at the end. A property the graphic marks as not animatable cannot be put in an action. See [Graphics](graphics.md).
- **Speed.** A media clip's playback rate, which makes a speed ramp. See [Speed](speed.md).

Some things are never animated. These rows write the clip itself, whatever is selected, and are marked ⊘ in the Clip tab:

- The Motion presets section (below).
- In the Sound sub-tab: Pan, Mix to mono, Ducking, Noise Reduction and the Compressor.
- In the Clip sub-tab's Speed section: Keep pitch and Fit to.
- **Adding or removing** a filter or an obscure region. Changing a value inside an existing entry still animates.
- A shape's own properties in the Shape sub-tab (its kind, stroke, fill, gradient and arrows). Its position, scale and opacity animate like any clip's.

### Add an action

1. Select a clip and put the playhead over it.
2. Choose **Clip ▸ Add Action** (⌥⌘K), or click **+** (Add Action) in the Clip tab's action lane.

The new action starts at the playhead, lasts 1 second and is selected straight away, so the Clip tab is ready to edit its end state.

- **Clip ▸ Add Action** is unavailable (greyed out) unless the playhead is over a selected clip. The action lane's **+** button beeps in that case.
- With several clips selected, the action goes on the first selected clip under the playhead and is not selected, because only a single selected clip can have a selected action.
- **Clip ▸ Speed Ramp…** also makes actions: one for Ramp Up and Ramp Down, two for Speed Dip and Speed Burst. They show as bands and edit like any other action. See [Speed](speed.md).

The action is refused when it would overlap another action on the clip or run past the clip's end, so near the end of a clip move the playhead back first, or shorten an existing action.

*Agents:* `add_action` (clip, `at` in clip time, optional `duration`; answers the new id in `new_actions`).

### Zoom to a region

**Zoom to Region** is the screencast zoom: draw a rectangle on the picture, and the clip zooms so that rectangle fills the frame.

1. Select one clip and put the playhead over it.
2. Press **Z**, or click the zoom-in magnifier (Zoom to Region) in the action lane.
3. Drag a rectangle over the canvas. A hint reads "Drag a rectangle to zoom to it · ⇧ fills · Esc to cancel", and a second outline shows exactly what the canvas will show once the zoom lands.
4. Release the mouse.

Frame Job adds a 1-second **Ease In Out** action at the playhead whose end state is the scale and position that bring the rectangle to the canvas. It works through the clip's rotation and crop. The new action is selected.

- **Fit or fill.** By default the whole rectangle is shown (fit). Hold **⇧** while dragging to fill the canvas instead, cropping whatever doesn't match the canvas shape.
- **Scale limit.** The zoom stops at the largest scale a layer can take, and the rectangle stays centred even then.
- **Leaving the mode.** Press Esc, press **Z** again, or click the button again. The mode also closes when the selection changes or the playhead leaves the clip. A rectangle too small to mean anything beeps and leaves the mode on so you can draw again.
- **During motion.** If the clip has a During motion preset, the band shows "This clip has During motion — the zoom is solved without it", because the preset keeps moving the clip under the zoom.

The mode needs exactly one selected clip that is drawn at the playhead and is not on a locked track. Otherwise **Z** beeps.

**Zoom Back** (the zoom-out magnifier in the action lane) adds a 1-second **Ease In Out** action at the playhead whose end state is the clip's own base scale, x and y, whatever earlier actions did. Use it after a Zoom to Region to pull back out. It needs the same target as **Z** (one selected clip drawn at the playhead, not on a locked track) and beeps otherwise. The new action is selected.

*Agents:* `add_zoom_action` (`region` as centre and size in source pixels from the centre of the clip's cropped picture, `fit` or `fill`, optional `curve` and `duration`; `region: null` is a zoom back).

### Select an action

An action is selected when you:

- click its band in the timeline or in the Clip tab's action lane,
- add it (with Add Action, Zoom to Region or Zoom Back), or
- play or scrub the playhead **into** its span while its clip is the only one selected.

Clicking a band on a clip that is part of a multi-clip selection selects just that clip and its action.

Clicking a band also moves the playhead to the action's end, so the preview shows the state the Clip tab is editing (one frame short when the action ends with the clip).

Leaving the span keeps the action selected. To leave it, press **Esc**, click the **Clip** chip at the start of the action lane, or select a different clip. Only a single selected clip can have a selected action. Selecting an action is not an undo step and is not saved with the project.

### Edit an action's end state

While an action is selected, every field in the Clip tab shows and sets that action's **end state**, the values the clip reaches at the action's end. The same goes for the canvas: dragging the selected clip's handles, or nudging it with the arrow keys, writes the end state.

Unchecking a switch inside an action (a shadow or an outline, for example) turns that property off when the action ends.

The Clip tab marks each row so you can see what the action touches:

| Mark | Meaning |
|---|---|
| ◆ | This action animates the row. The label turns strong and the field gets a border in the action colour. A popup, checkbox or other on/off control also shows "at end", because it switches rather than ramps |
| ◇ | Another action on the clip animates this row. Its tooltip names the action |
| ○ | The row follows a value this action animates (for example, Gain follows Volume) |
| ⊘ | Actions don't animate this row. Edits change the clip |

A slider on an animated row fills in the action colour from the value at the action's start to the knob. When the playhead is inside the clip, a coral tick shows the value at the playhead. A row that is a field only shows that value as a "now …" tag instead.

Section headers carry the same marks, and a section where every row is ⊘ says "Actions don't animate this. Edits here change the clip." Each sub-tab's label shows **◆N** when the selected action animates N of its keys. When you select an action, the sections it animates on the current sub-tab open automatically.

To take a property back out of an action:

- Hover over a ◆ and click the × that replaces it ("Remove from action N").
- Click **Clear** in a section's header to remove all of that section's keys from the action. While an action is selected and keys the section, Clear takes the place of the header's **Reset**; otherwise Reset shows only while the section differs from its defaults.
- Right-click a row for its menu: **Remove from action N** on an animated row, **Go to action M** on a ◇ row (selects that action), and **Set end value to default** (on a row the selected action animates) or **Reset to default** (otherwise). The default item is disabled when the row already holds its default.

*Agents:* `set_action_end` (a `patch` with `video`, `audio`, `text` and `graphic` groups and a top-level `speed`, merged into the end state; `null` removes a key; `off` lists `"group.key"` paths to switch off at the end). `video.motion` and `text.words` are refused.

### Move, resize and re-curve an action

**In the action lane or the timeline:**

- Drag a band's **body** to move the action within its clip.
- Drag a band's outer 5 pt (its grips, shown on hover) to move that end. A band 15 pt wide or narrower has no grips and only moves.

A drag snaps to whole frames, keeps the action at least one frame long, and stops at the neighbouring actions and the clip's ends. A dashed outline marks where the band started. A readout replaces the lane's header text: "start → end +s:ff" for a move or a start resize, "len +Nf" for an end resize. The whole drag is one undo step (**Move Action** or **Resize Action**). Dropping the band selects the action. Bands don't snap to the playhead or other edits. If Frame Job would refuse a position, the band just stops there.

**In the action lane's detail row** (shown while an action is selected):

| Control | What it does |
|---|---|
| Start | Where the action starts, as a timecode measured from the clip's start |
| Length | How long it takes, 0.01–36000 s (quick picks 0.25, 0.5, 1, 2) |
| Curve | Linear, In, Out or In Out, with a glyph of the curve beside it |
| Trash button | Removes the action |

When Frame Job refuses a typed Start or Length, or an end-state edit, the reason appears at the foot of the inspector as "Refused: …" with the rule's own sentence. It stays until the project next changes or you click it. A band drag never shows one.

*Agents:* `set_action` (`start`, `duration`, `curve`; any left out keep their value).

### Remove an action

With an action selected, press **⌫**, or click the trash button in the action lane. ⌫ removes only the action, not the clip.

Careful: **⌘⌫** (Ripple Delete) still ripple-deletes the whole selected clip, even while an action is selected.

A speed action can't be removed if doing so would make the clip read past the end of its media. The refusal names the latest clip end that fits. See [Speed](speed.md).

*Agents:* `remove_action`.

### Actions on the timeline

Each clip that has an action shows an **action lane** directly under its name strip, with one band per action. How much a band shows depends on **View ▸ Timeline Track Height**:

| Track height | A band shows |
|---|---|
| Small | The bar only |
| Medium | Its number, a zoom glyph for a zoom action, and the curve on the selected band |
| Large | All of that, plus the properties it changes (for example `scale, x, y`, or `speed`) |

Actions are numbered in time order, and the number is the same on the timeline and in the Clip tab. The selected action's band is solid, a wash runs down the clip under its span, and the span is shaded on the ruler.

### The action lane in the Clip tab

The Clip tab opens with a pinned block above its sections: the selection header, the action lane, and the sub-tabs. The action lane is a small timeline of the selected clip:

- **Header row:** ACTIONS, then the count (or "none") and "· editing N" while action N is selected, then three buttons: Zoom to Region (Z), Zoom Back, and Add Action (⌥⌘K).
- **Lane row:** the **Clip** chip (highlighted while no action is selected; click it to leave the action), then the whole clip with its actions as numbered bands and the playhead. Under the bands the lane also shows the clip's transition overlap (hatched), its audio fades and its motion wedges, the same marks the timeline draws. An empty lane reads "no actions · ⌥⌘K adds one".
- **Detail row:** only while an action is selected (see above).

With several clips selected the lane reads "Select one clip to edit its actions."

### How edits move actions

| Edit | What happens to the clip's actions |
|---|---|
| Trim the start | Actions keep their clip time, so they stay put relative to the clip's new start |
| Trim the end | Actions stay put, so one can end up running past the clip's new end; only the part inside the clip plays. You can still move it earlier, shorten it or change its curve, but not make it end any later |
| Slip or Roll | Actions stay where they are in clip time |
| Change the speed, or rate-stretch | Actions keep their place as a fraction of the clip |
| Split | Actions after the cut go to the second half; one that spans the cut is divided between the halves |
| Add a transition at a hard cut | The incoming clip's actions move with its new first frame, so a zoom stays on the frame it was drawn over |
| Duplicate, Copy and Paste | The copies keep their actions |
| Nest | The clips keep their actions inside the nest |
| Detach Audio | The new audio clip gets a copy of every action, so volume actions keep working |
| Freeze Frame | The still has no actions; the look at the frozen frame is baked into its own properties |
| Add Blurred Background | The backdrop copy has no actions, so a zoom on the foreground doesn't zoom the backdrop |
| Paste Attributes | Actions are not copied |

## Motion presets

A motion preset says what a clip **does** rather than where it is. Each clip has three slots: an **In** (an entrance at its start), an **Out** (an exit at its end) and a **During** (a movement for its whole length). A preset is tied to the clip's ends, so it moves with a trim. It works on any clip that draws a picture: video, still images, text, shapes, graphics and nests.

Motion is applied on top of the clip's own placement and any actions, and it is never animated by an action. A preset works relative to the clip: its scale and opacity multiply the clip's own, and its rotation and offset add to them. Zoom and Spin turn about the clip's visible centre, after any crop. The inspector fields (and `get_project`) show the clip's own, un-moved values, even though the preview and export show it moving.

### Set a preset

Use the **Motion presets** section at the end of the Clip sub-tab, or **Clip ▸ Motion ▸ In**, **Out** or **During**. Each submenu lists the kinds, then **None** to clear the slot. A checkmark shows the kind every selected clip shares.

The section's rows:

| Row | What it does | Range | Default |
|---|---|---|---|
| In | The entrance kind, or None | None and nine kinds | None |
| In Duration | How long the entrance takes (disabled with None) | 0.1–10 s (quick picks 0.25, 0.5, 1) | 0.5 s |
| Out | The exit kind, or None | None and nine kinds | None |
| Out Duration | How long the exit takes (disabled with None) | 0.1–10 s (quick picks 0.25, 0.5, 1) | 0.5 s |
| During | The continuous movement, or None | None and five kinds | None |
| Amount | How strong the During movement is (disabled with None) | 0–100% (quick picks 25, 50, 75, 100) | 50% |
| Period | How long one cycle takes (disabled with None and for Drift) | 0.1–10 s (quick picks 0.25, 0.5, 1, 2) | 1 s |
| Preview | Sets the in/out range to the clip, turns Loop on and plays it | | |

Changing a slot's kind keeps the duration, amount and period it already had. The section is closed by default, and its summary reads, for example, "in fade · out slide left · pulse", or "off". **Reset** clears all three slots. With several clips selected, each one keeps its own other slots. Preview leaves the range and Loop on until you clear them.

**Clip ▸ Motion ▸ Preview** does the same as the Preview button. With several clips selected, both loop the first selected clip that has a picture.

*Agents:* `set_video` with `motion: {in: {kind, duration}, out: {kind, duration}, during: {kind, amount, period}}` (durations and period in ticks, amount 0–1; `motion: null` clears all three).

### Entrances and exits

The same nine kinds fill both In and Out. An exit is the entrance played the other way: the In eases out as it arrives, and the Out eases in as it leaves.

| Kind | As an entrance (In) | As an exit (Out) |
|---|---|---|
| Fade | Fades in | Fades out |
| Zoom In | Grows from 60% to full size while fading in | Grows to 140% while fading out |
| Zoom Out | Shrinks from 140% to full size while fading in | Shrinks to 60% while fading out |
| Slide Left | Slides in from the right edge | Slides out past the left edge |
| Slide Right | Slides in from the left edge | Slides out past the right edge |
| Slide Up | Slides in from the bottom edge | Slides out past the top edge |
| Slide Down | Slides in from the top edge | Slides out past the bottom edge |
| Spin | Spins half a turn into place from 30% size, fading in | Spins half a turn away to 30% size, fading out |
| Pop | Springs up past full size (to about 110%) and settles, fading in over the first quarter | Swells and springs away, fading out over the last quarter |

A slide measures the layer as it is drawn, so it starts or ends exactly off the edge of the canvas (or of the nest it is inside).

### During

| Kind | What it does |
|---|---|
| Pulse | Gently grows and shrinks once per period, up to 20% larger at 100% |
| Shake | Jitters in a pattern that never visibly repeats, up to 4% of the canvas's shorter edge at 100% |
| Spin | Rotates continuously; at 50%, one full turn per period |
| Bounce | Hops upward once per period, up to 8% of the canvas height at 100% |
| Drift | A slow push-in across the whole clip, ending up to 24% larger at 100%. It ignores Period |

Every During movement starts from the clip's own placement on its first frame. It runs under the In and Out, so a clip can, for example, slide in while it pulses.

### On the timeline

A clip with an In or Out preset shows a small wedge along the bottom of its name strip, as long as the preset's duration at the current zoom. If the wedges overlap, the two presets are longer than the clip together. In that case Frame Job shortens both in proportion to their lengths, so the entrance ends on the frame where the exit begins, rather than refusing.

A clip with a During movement shows a small wave symbol at the right end of its name strip.

### Inactive presets

An In or Out with a zero duration can come from an agent or an older project. It is kept but does nothing. The section, the summary and the Motion menu mark it "(inactive)" (or "(some inactive)" across a selection), it draws no wedge, and a note reads "Selection includes inactive In motion (zero duration). Increase Duration to reactivate; choose None to clear."

### Limits

- A preset is not part of any action. Motion rows are ⊘, and edits always write the clip, even with an action selected.
- A split gives the first half no Out and the second half no In, so the cut doesn't play an exit and an entrance. A During movement restarts at each cut, so Remove Silences on a clip with Pulse or Drift can make it jump at the cuts.
- Freeze frame and Add Blurred Background drop the motion. Duplicate, Detach Audio and Paste keep it. Changing the speed doesn't rescale the presets.
- A text clip has no measured size, so a slide starts or ends half a canvas past the edge. That clears any text narrower than the canvas.
- A canvas drag started mid-motion starts from the clip's un-moved position.

## Transitions

A transition plays across the **overlap** between two clips on the same track. The overlap's length is the transition's duration, and the later clip carries the transition (it is the transition *into* that clip). The overlap is drawn on the timeline as a hatched zone, with the transition's name in it when the word fits.

Two rules limit overlaps: a clip can overlap at most one neighbour on each side, and an overlap can be at most half as long as the shorter of the two clips. Clips never push each other out of the way. A move that would break either rule is refused.

### Transition styles

| Style | What it does |
|---|---|
| Cross Dissolve | The outgoing clip fades into the incoming one |
| Fade Through Black | The outgoing clip fades to black over the first half, then the incoming one fades up from black over the second half |
| Fade Through White | The same, through white (in an HLG project, the lifted SDR white) |
| Push Left | Both clips move: the outgoing leaves to the left as the incoming pushes in from the right |
| Push Right | The outgoing leaves to the right, the incoming comes in from the left |
| Push Up | The outgoing leaves upward, the incoming comes up from the bottom |
| Push Down | The outgoing leaves downward, the incoming comes down from the top |
| Wipe | An edge sweeps left to right, revealing the incoming clip |
| Wipe Left | An edge sweeps right to left |
| Wipe Up | An edge sweeps upward |
| Wipe Down | An edge sweeps downward |
| Slide | The incoming clip slides in from the right over the outgoing one, which stays put |
| Zoom | The outgoing clip grows toward you (to 125%) while the incoming one grows into place from 75%, and the two dissolve into each other |

A wipe's edge is measured in each clip's own frame, so two clips of different sizes don't meet at one line.

A fade through a colour changes the layer's own pixels toward the colour. On a clip smaller than the canvas (a picture-in-picture), the fade shows a black (or white) box over what is behind it, not a see-through fade.

### Add a transition

There are three ways:

- **Overlap two clips.** Whenever an edit makes a clip overlap the clip before it on the same track, and that clip has no transition stored, Frame Job adds a Cross Dissolve, eased (Ease In Out) and crossfading the sound. That holds whether you drag, trim an edge, paste, insert, close a gap or shift clips.
- **Clip ▸ Transition ▸ \<style\>.** Works on every selected clip at once:
  - A clip that already overlaps the clip before it gets the chosen style, keeping its curve and crossfade.
  - A clip at a **hard cut** (it starts exactly where the previous clip ends) gets a new half-second overlap, centred on the cut. The overlap is made from footage the two clips aren't showing: the source past the first clip's out point and before the second clip's in point. Nothing else on the timeline moves, and the pair's outer edges stay where they were. If there isn't half a second to spare, the transition comes out shorter.
  - A clip after a gap, or the first clip on its track, is skipped.

  A style is enabled only when at least one selected clip is at an overlap or a hard cut. The checkmark shows the first selected clip's style, or None when it has no transition. None is enabled for any selection.
- **The Transition section's Kind popup**, for a clip that already overlaps (below).

**When there is no footage to spare.** Two clips that each use their whole file have nothing beyond the cut to overlap with. Clip ▸ Transition ▸ then shows a sheet: "There's no extra footage at this cut for a transition." Choosing **Shift Clips Left** makes the overlap by sliding the second clip, and everything after it on unlocked tracks, left by half a second. The project gets that much shorter, and no clip's footage changes. Markers don't move. A clip on another track that ends up overlapping its neighbour gets a Cross Dissolve. The whole shift is one undo step. **Cancel** changes nothing.

*Agents:* `add_transition` (the hard-cut form: `kind`, `duration`, `align` `center`, `before` or `after`, and `ripple: true` for the Shift Clips Left form); `set_transition` (a kind onto a clip that already overlaps).

### The Transition section

The **Transition** section is on the Clip sub-tab when a single selected clip overlaps the clip before it. Its summary reads, for example, "cross dissolve · ease in out · 0.50 s", or "none".

| Row | What it does | Range |
|---|---|---|
| Kind | The style, or None | None and the thirteen styles |
| Curve | How the transition's progress is eased | Linear, Ease In, Ease Out, Ease In Out |
| Crossfade Audio | On: the outgoing sound fades out and the incoming fades in at constant power, eased by the Curve, so the level holds steady between two unrelated takes. A pair where only one clip has sound still fades that clip. Off: both clips play at their own level across the whole overlap, mixed together. Mute, solo, ducking and volume still apply on top | On or off |
| Duration | The length of the overlap. Changing it **moves** the later clip to match | 0.02–10 s (quick picks 0.25, 0.5, 1, 2) |

A transition Frame Job makes is eased (Ease In Out) and crossfades its sound. An overlap with no stored transition draws as a linear cross dissolve with no sound crossfade, and in that state the section shows **Linear** and **Crossfade Audio** off. Setting either of them then stores a transition with exactly the values shown.

The duration is refused on a track's first clip, and past half the shorter clip. The refusal names the limit.

Two overlapping clips with no picture (audio-only clips) get the same section. Only their sound changes: Crossfade Audio and Curve control the crossfade, and Kind has no visible effect.

*Agents:* `set_transition_style` (`curve` and `audio`, each kept when absent); `set_transition_duration`.

### Remove a transition

Choose **None** in the Kind popup, or **Clip ▸ Transition ▸ None**. None is always available, because a clip can hold a transition the timeline doesn't draw: one left behind when an overlap was dragged apart, for example.

None removes the stored transition but not the overlap. While two clips still overlap they keep blending as a plain linear dissolve, with no hatch on the timeline. To get a hard cut back, move or trim the clips so they no longer overlap.

*Agents:* `set_transition` with `kind: null`.

### Limits

- A transition only plays across an overlap on one track. A transition stored on a clip that overlaps nothing does nothing until there is an overlap.
- Adjustment clips can't take a transition.
- After **Detach Audio**, Crossfade Audio on the video clips' transition has no effect, because their own sound is switched off. To crossfade the sound, overlap the detached audio clips and give them a transition of their own.
- Remove Silences and Remove Filler Words never cut into a transition's overlap. See [Remove Silences and Remove Filler Words](cleanup-tools.md).
- A layer always blends normally while it is in a transition, whatever blend mode it has.
