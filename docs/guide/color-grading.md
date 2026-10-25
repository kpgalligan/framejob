# Colour grading

Frame Job grades a clip from the inspector's **Color** tab. You can set exposure and white balance, push the shadows, midtones and highlights toward a colour with three wheels, shape tones and hues with curves, and finish with one of eight built-in looks or your own `.cube` LUT. An **adjustment clip** grades everything behind it at once, and its **qualifier** can narrow that grade to one colour or tone range. To check your work, **Show Ungraded** gives a before/after view and **Scopes** shows a waveform, parade, vectorscope and histogram beside the preview.

Every grade setting can be animated in an action. The preview, **Save Frame…** and every export draw a grade the same way. A clip you haven't graded renders exactly as it would without one.

## The Color tab

Select one or more clips and open the inspector's **Clip** tab. The **Color** sub-tab appears when every selected clip can take a grade:

- a video clip, an image clip or a still (freeze frame), or
- an adjustment clip.

It does not appear for text, shape, graphic or nest clips, and a selection of nothing but audio-only clips has no Color tab. Mixing in a text, shape, graphic or nest clip hides the tab. An audio-only clip selected alongside a video clip does not hide it; the grade goes only to the clips that draw.

The tab's sections, from top to bottom:

| Section | Shown for |
|---|---|
| Adjustment | Adjustment clips only (every selected clip must be one) |
| Qualifier | Adjustment clips only (every selected clip must be one) |
| Light | Every gradable clip |
| Color | Every gradable clip |
| Wheels | Every gradable clip |
| Curves | Every gradable clip |
| Look | Every gradable clip |

Each section's header shows a short summary, such as "neutral", "adjusted", "Warm 80%" or "hue · sat · inverted", and has a **Reset** button that returns only that section to neutral. If no section is open, the tab opens the first one you haven't closed yourself.

**Working on several clips.** A control writes only the setting it governs. Dragging Exposure across three clips changes their exposure and leaves each clip's other values alone. When the selected clips have different values, the row shows a mixed badge.

**Undo.** Dragging a slider is one undo step, and so is a typed value. Each step is named after its control, for example **Undo Exposure**, **Undo Hue** or **Undo Strength**. A section's **Reset** is one step named after the section ("Light", "Color", "Look", "Adjustment", "Qualifier").

The order the grade is applied in is fixed: Color first, then Light, Wheels, Curves (tone curves, then the hue curves) and the Look. The clip's filters from the Picture tab's **Filters** section split around the grade: Pixelate, Blur and Sharpen act on the picture before it, and Sepia, Noir, Vignette and Invert act after the Look, in the order of their slots. That matters when you combine a filter such as Noir or Vignette with a grade. A camera-log conversion set on the media comes before all of them (see [HDR and colour management](hdr-and-color.md)).

## Light

Light holds the tone and white-balance controls. Each row is a slider with a number field beside it.

| Control | Range | What it does |
|---|---|---|
| Exposure | −3 to +3 EV | Brightens or darkens in stops, on linear light |
| Temperature | −1 to +1 | Positive makes the picture warmer (more red, less blue); negative makes it cooler. Applied on linear light |
| Tint | −1 to +1 | Positive shifts toward magenta; negative shifts toward green. Applied on linear light |
| Highlights | −1 to +1 | Lifts or lowers the brighter half of the tones |
| Shadows | −1 to +1 | Lifts or lowers the darker half of the tones |
| Whites | −1 to +1 | Stretches the tones toward white, with black held |
| Blacks | −1 to +1 | Raises (positive) or deepens (negative) the dark end of the tones, with white held |
| Vibrance | −1 to +1 | Changes saturation mostly in colours that have little of it |
| Fade | 0 to 1 | Lifts black toward 10 % and lowers white toward 95 %, for a washed-out film look |

All nine default to 0. Light's **Reset** sets all nine back to 0.

## Color

| Control | Range | What it does |
|---|---|---|
| Brightness | −1 to +1 | Raises or lowers every level |
| Contrast | −1 to +1 | Spreads the tones apart or pulls them together |
| Saturation | −1 to +1 | More or less colour overall; −1 is greyscale |
| Hue | −180° to +180° | Turns every colour around the colour wheel. Each pixel's brightness is kept, and greys stay grey |

All four default to 0. Color's **Reset** affects only these four.

*Agents:* `set_video` with `color`, which takes these thirteen keys: `exposure`, `temperature`, `tint`, `highlights`, `shadows`, `whites`, `blacks`, `vibrance`, `fade`, `brightness`, `contrast`, `saturation` and `hue`. It merges like the rest of a video patch.

## Wheels

**Wheels** shows three columns side by side, **Lift**, **Gamma** and **Gain**:

- **Lift** moves black and holds white, so it mostly affects the shadows.
- **Gamma** moves the middle tones and holds both ends.
- **Gain** moves white and holds black, so it mostly affects the highlights.

Each column has a colour disc, a strip under it, and a number field.

Hover a disc to see its push as a tooltip, such as "Hue 34° · 0.25" (the hue angle and the strength), or "Neutral" when the puck is centred. There is no number field for the push itself.

**The disc** pushes its tonal range toward a colour. The puck's direction picks the hue and its distance from the centre sets the strength. The disc is turned to match the vectorscope, so dragging toward a colour moves the vectorscope trace toward it.

- Press anywhere on the disc and drag. The puck moves by however far the pointer moves; it doesn't jump to where you clicked. Dragging one disc radius gives the full push.
- Hold ⌥ to move at a tenth of the speed.
- Past the rim, the puck slides along the rim.
- Double-click the disc to reset the push to the centre. This leaves the wheel's brightness alone.

**The strip and the field** set the wheel's master brightness, from −1 to +1 (two decimals in the field):

- Click off the knob to jump the value there, or drag the knob from where it stands.
- Hold ⌥ to drag at a tenth of the speed, relative to where you started.
- Double-click the strip to reset the master to 0. This is one undo step, even when the first click of the double-click moved the knob.

Each drag is one undo step, named after its wheel. **Reset** sets all three wheels back to neutral.

*Agents:* `set_video` with `wheels: {lift, gamma, gain}`, each `{x, y, master}` from −1 to 1. The point `(x, y)` must lie inside the unit circle, and its angle is the hue, with red at 0°.

## Curves

**Curves** is a square plot with a channel picker above it and the selected point's fields below it.

### Channels

The picker has six cells:

| Cell | Curve | Plot axes |
|---|---|---|
| Master | Tone curve on all three colours, for contrast and the black and white points | In 0–1 across, Out 0–1 up |
| Red | Red channel only | In 0–1, Out 0–1 |
| Green | Green channel only | In 0–1, Out 0–1 |
| Blue | Blue channel only | In 0–1, Out 0–1 |
| Hue | **Hue vs Hue**: shifts a chosen hue toward another, with brightness kept ("make the greens more teal") | Hue 0–360° across, shift −180° to +180° up |
| Sat | **Hue vs Sat**: saturates or mutes a chosen hue | Hue 0–360° across, gain 0× to 2× up (1× is unchanged) |

Channels you've changed in the same family appear as faint lines in their own colour behind the curve you're editing: the Master, Red, Green and Blue curves together, and Hue and Sat together.

The Hue and Sat plots have a spectrum strip under them. A hue curve never tints a grey, and its points never cross the 0°/360° wrap. A dot under a cell means that channel has been changed. Right-click a cell and choose **Reset Red** (or the name of whichever cell you clicked) to straighten that channel alone. The section's **Reset** straightens all six.

A new window starts on Master. The plot remembers its channel while the window stays open.

### Editing points

A curve holds from 2 to 16 points on a smooth curve that never overshoots.

| Action | Result |
|---|---|
| Click the plot away from a point | Adds a point on the curve at that x, selects it, and lets the same press drag it. A 17th point beeps |
| Drag a point | Moves it, held just inside its neighbours. You can drag the end points too, which sets the black and white points on a tone curve |
| ⌥-drag | Moves at a tenth of the speed |
| ⇧-drag | Locks the point to one axis. After a short movement, whichever direction you moved further wins and holds for the rest of the drag. ⌥ and ⇧ combine |
| Arrow keys | Nudge the selected point: 0.01 on a tone curve, 1° (or 0.01× on Sat) on a hue curve |
| ⇧-arrow keys | Nudge by ten times as much |
| ⌫ or ⌦, or double-click a point | Deletes it. A curve can't go below two points |
| Esc | Deselects the point |

Below the plot, the **In** and **Out** fields let you type the selected point's position, and **Delete** removes it. On a tone curve both fields run 0–1 with three decimals. On a hue curve, In is in degrees (0–359.9°) and Out is degrees (−180° to +180°) on Hue or a gain (0× to 2×) on Sat. With no point selected, both fields are blank.

**Hover readout.** While the pointer is over the plot, and during a drag, a label shows the pointer's position and the curve's value there, such as "In 0.42 → Out 0.47", "Hue 34° → +12°" or "Hue 120° → ×0.80".

A point you add to a straight channel isn't saved until you first move it, nudge it or type a value, so clicking and releasing on a straight curve changes nothing. Each drag, nudge, deletion or typed value is one undo step, named "Curves". While a point is selected the plot has the keyboard, but keys it doesn't use still reach the editor, so Space still plays.

*Agents:* `set_video` with `curves: {master, red, green, blue, hue_hue, hue_sat}`. Each channel is a list of 2–16 `[x, y]` points with x strictly rising. Tone curves use 0–1 on both axes. A hue curve's x runs from 0 up to (but not including) 360, and its y is −180 to 180 for `hue_hue` or 0 to 2 for `hue_sat`. A list you send replaces that channel whole.

## Looks and LUTs

### Built-in looks

**Look** is a gallery of tiles. Each tile is a thumbnail of the first selected clip with that look applied: the frame at the playhead when the playhead is inside that clip, otherwise the clip's first frame. The thumbnails refresh a moment after the playhead stops or an edit lands, never during playback or scrubbing, and only while the Look section is open. **None** comes first, then the eight looks:

| Look | Character |
|---|---|
| Warm | Warmer white balance, golden highlights |
| Cool | Cooler white balance, blue shadows |
| Teal & Orange | Teal shadows, orange highlights, more contrast |
| Vivid | More contrast and vibrance, with deeper blacks and brighter whites |
| Faded | Low contrast, muted colour, lifted blacks |
| Vintage | Muted and warm, with a fade and split-toned shadows and highlights |
| Dramatic | Darker, contrasty and desaturated, with cool shadows |
| Black & White | Monochrome |

Click a tile to put that look on every selected clip. The tile of the look every selected clip shares is outlined. If a clip already had a look, it keeps its amount; a clip with no look gets 100 %. **None** (or the section's **Reset**) removes the look. The thumbnails always show the graded picture, even while Show Ungraded is on.

**Amount** (0–100 %, with presets at 0, 25, 50, 75 and 100 % behind the field's chevron) sets how much of the look applies. The row only appears when every selected clip has a look.

**Clip ▸ Look ▸** does the same from the menu: the eight looks, then any imported LUTs, then **None**. A checkmark marks the look every selected clip carries, and a dash marks one that only some carry. The menu items have no shortcut, and the menu is unavailable when no selected clip can take a grade.

### Imported .cube LUTs

A `.cube` 3D LUT is media in your project. You can add one three ways:

- **Import LUT…**, the button under the gallery, picks a `.cube` file and applies it to the selected clips, all in one undo step ("Import LUT").
- **File ▸ Add Media…** (⇧⌘I) adds it to the project.
- Dropping the file on the Media tab also adds it.

Each LUT gets a tile in the gallery's **Imported** group, named after its file without `.cube`. It also gets an item in **Clip ▸ Look ▸** between the eight looks and None. A LUT is applied at the same step as a built-in look and uses the same **Amount** row.

Frame Job reads 3D LUTs whose `LUT_3D_SIZE` is from 2 to 65. It refuses any other file in its own words, for example "“Film.cube” is not a LUT Frame Job reads: line 2: LUT_3D_SIZE 200 is outside 2–65." Output values are clamped to 0–1. If you change the file on disk, the new table is read at the next frame drawn. If the file goes missing, the clip draws without its look until you relink it; the rest of the grade still applies.

The Look section warns you in two cases:

- "This clip's file is converted by Camera Log; a camera LUT here converts it twice." A creative LUT is fine there; a camera LUT would convert the footage a second time.
- "This project is HDR (HLG): a .cube LUT reads its values as Rec. 709."

See [HDR and colour management](hdr-and-color.md) for camera log and HLG projects.

**Removing a LUT.** A LUT counts as used by every clip whose look it is, and by every file whose Camera Log it is. Removing it from the Media tab asks first, naming those uses, and its **Remove and Clear Looks** button removes the LUT and clears the look from those clips (they keep their place) and the Camera Log from those files. An action whose end names the removed LUT simply stops changing the look.

*Agents:* `set_video` with `look: {kind, amount}`. `kind` is one of `warm`, `cool`, `teal_orange`, `vivid`, `faded`, `vintage`, `dramatic`, `black_white` or `lut`, and `look: null` removes the look. For a LUT, call `import_media` with the `.cube` file, then `set_video {look: {kind: "lut", media: <id>}}`.

## Adjustment clips

An adjustment clip has no picture of its own. For as long as it lasts, it grades everything already drawn behind it: every lower track and the canvas background. It never affects a track in front of it.

**Insert ▸ Adjustment Clip** (no shortcut) places one, as one undo step named "Add Adjustment Clip":

- **Span:** the In/Out range when one is set; otherwise the selected clips' span from first start to last end; otherwise the whole timeline.
- **Track:** the front track when it has room and isn't a matte track; otherwise a new front track named "Adjustment".

The new clip is selected and the inspector opens on **Clip ▸ Color**. The item is greyed out while a nest is open, and when there is nothing to cover.

The adjustment clip's Color tab has the full grade (Light, Color, Wheels, Curves and Look) plus two sections of its own:

- **Adjustment ▸ Strength** (0–100 %, presets behind the chevron) sets how much of the grade is mixed over the picture behind it. Animate or fade the strength rather than adding a transition.
- **Qualifier** narrows the grade to the pixels you pick (see below).

There is no Picture tab for an adjustment clip, because it has nothing to place or crop. Point filters (Sepia, Noir, Vignette, Invert) given to it by Paste Attributes or by an agent also apply to the picture behind it.

### Adjustment clip limits

- It can't go inside a nest, and the Insert item is off while a nest is open.
- It can't take a transition or overlap another clip on its track. Fade its Strength instead.
- Blur, sharpen, pixelate and blend modes are refused on it.
- On a track cut by a matte, it grades only inside the matte. On a matte track itself it does nothing, and the Clip tab says so.

*Agents:* `add_adjustment_clip` (`track`, `at`, `duration`, which defaults to 5 s). Then use `set_video` with `color`, `wheels`, `curves`, `look`, `filters`, `qualifier` and `opacity`, which sets the strength.

## Qualifiers

The **Qualifier** section appears on adjustment clips only, after Adjustment. It limits the clip's grade to the pixels behind it that match up to three ranges. Matching uses the picture as it was before the grade, so the grade never changes what it selects.

### Ranges

Each range has a checkbox, a strip and three fields. Turning a checkbox on starts the range at its default.

| Range | Strip | Fields | Default when turned on |
|---|---|---|---|
| Hue | The colour spectrum, 0–360° | Centre (0–360°), Width (0–360°), Soft (0–180°), in whole degrees | Centre 30°, Width 50°, Soft 25° |
| Saturation | Neutral to fully saturated | Low, High, Soft (0–1, two decimals) | Low 0, High 1, Soft 0.1 |
| Luma | Black to white | Low, High, Soft (0–1, two decimals) | Low 0, High 1, Soft 0.1 |

The strip dims everything outside the range (the soft edges half as much), so you can see on the scale what is picked. A range that is off has a dimmed strip that ignores presses and greyed-out fields; tick its checkbox first. Low and High never cross: a typed Low is held at or below High, and a typed High at or above Low.

A pixel must fall inside every range that is on. Each range falls off smoothly across its softness outside each edge. Greys are never picked by hue, and near-black pixels are never picked by saturation.

On a strip:

- Drag a block knob to change the width (on Hue, symmetrically about the centre) or the low or high edge.
- Drag a small square to change the softness.
- Drag the band's middle to move the whole range. Hue wraps around.
- Hold ⌥ to move at a tenth of the speed.
- Double-click to reset the range to its default.

Below the ranges:

| Control | What it does | Default |
|---|---|---|
| Invert | Grades everything except what the ranges pick | Off |
| Blur | 0–100 %. Smooths a speckled selection on noisy footage into a clean one | 0 % |
| Pick from Canvas | Click the preview to centre the ranges on that colour | — |
| Show Selection | Shows the selection in the preview instead of the graded picture | Off |

### Pick from Canvas

Press **Pick from Canvas**, then click the picture in the preview. Frame Job samples the picture *behind* the adjustment clip, leaving out the clip's own grade and anything in front of it:

- The Hue range is centred on the colour you clicked. If Hue was off, it is turned on at 30° wide with 15° softness. If you click a near-grey, Hue is turned off.
- The Saturation range is turned on if needed (0.3 wide, softness 0.1) and centred on the colour's saturation, kept inside 0–1.
- Luma is re-centred only if it was already on.
- A range that was already on keeps its width and softness.

The pick is one undo step named "Qualifier". Press Esc or the button again to cancel; changing the selection also cancels. A click outside the canvas beeps and leaves the mode armed. The button works only when every selected clip is an adjustment clip. Arming it cancels any other canvas mode that is armed, such as the chroma key's eyedropper or a Zoom to Region drag. With an action selected, the picked ranges go to the action's end state.

### Show Selection

**Show Selection** (the checkbox in the section, or **View ▸ Show Selection**, which has no shortcut) draws the qualifier's selection in grey. White is fully graded, black is untouched, and grey is in between. The blur and any matte cutting the clip are included, and the Strength is not applied. Layers in front of the clip are left out, and the preview is black where the clip is not on the frame. A "Selection" tag appears in the preview's top-left corner.

Show Selection follows the first selected adjustment clip. It moves to another adjustment clip when you select that one, and turns off when no adjustment clip is selected. The menu item is disabled while it is off and no adjustment clip is selected. It only affects this window's preview and the Preview Window, never an export or Save Frame….

*Agents:* `set_video` with `qualifier: {hue: {center, width, softness}, saturation: {low, high, softness}, luma: {low, high, softness}, invert, blur}`. A range set to `null` turns off. `render_frame {selection: <adjustment clip id>}` draws Show Selection's picture.

## Seeing the grade

### Show Ungraded

**View ▸ Show Ungraded** (⌃⌘U) shows this window's preview, and the Preview Window, as if no clip were graded. Every clip's Light, Color, Wheels, Curves and Look are set to neutral, nested and matte clips included. An "Ungraded" tag appears in the preview's top-left corner. It's a before/after switch: a checkmark item that is per window and not saved.

Some things are not part of the grade, so Show Ungraded leaves them on: a camera-log conversion on the media, filters, the chroma key, and placement. Exports, **Save Frame…** and the look gallery's thumbnails never see the switch.

*Agents:* `render_frame {ungraded: true}`.

### Scopes

**View ▸ Scopes** (⌃⌘W) opens a 248-point panel at the right edge of the preview area. It has two stacked slots, each with a pop-up menu that picks one of four scopes. A new window opens the panel off, set to **Waveform** over **Vectorscope**. Your choices and zooms last while the window is open and are not saved.

| Scope | What it shows |
|---|---|
| Waveform | Luma (Y′) by position across the frame, with lines at 0, 25, 50, 75 and 100 %. Red marks on the top and bottom edges show where highlights and shadows clip |
| Parade | Red, green and blue as three side-by-side waveforms, each with its own clip marks |
| Vectorscope | Colour (Cb across, Cr up) with the six 75 % colour-bar targets (R, Mg, B, Cy, G, Yl) and the skin line. The **1× 2× 4×** cells in its bottom-right corner zoom in on a low-saturation picture. At a zoom that pushes a target off the plot, a tick on the rim points toward it |
| Histogram | Red, green and blue counts per level as tinted fills, with luma as a white line |

Below the Waveform and the Histogram, two readouts show **Highlights clipped** and **Shadows clipped** as a share of the frame. The slot's caption says what the scope reads: "Rec. 709 · encoded" in an SDR project. In an HDR (HLG) project it reads "HLG · cd/m²" or "Rec. 2100 HLG", with a cd/m² scale (0, 10, 51, 203, 1000), a dashed line at reference white and Rec. 2020 vectorscope targets. See [HDR and colour management](hdr-and-color.md).

The scopes measure every frame the preview composes: they follow the picture live while it plays, and update after each edit while paused. Their readouts show "—" until a frame has been measured. Because they read the preview's frame, they follow Show Ungraded, and with **View ▸ Show SDR Version** on in an HLG project they measure the SDR picture and switch to the Rec. 709 caption and targets. If the preview area is too short for both slots, they shrink together. Below a 360-point pane, only the top slot shows.

*Agents:* `render_frame` with `waveform`, `parade`, `vectorscope` (plus `vectorscope_zoom` 1, 2 or 4) and `histogram`. The text answer gives the clipping percentages, and a JSON file next to the image holds the counts.

## Grading inside an action

Every grade setting can be animated. Select an action on the clip's action lane, then change a control. The change goes to the action's end state, and the value ramps there from the clip's own value. The row marks (◆) and the Color tab's badge show which settings the selected action animates. See [Motion and transitions](motion-and-transitions.md) for actions.

- **Light, Color, wheels, Strength, the look's Amount and the qualifier's numbers** ramp smoothly. An animated hue centre takes the short way round the colour wheel; 350° to 10° passes through 0°.
- **Curves** animate between any two curves, even with different numbers of points, and from or to a straight line. Inside an action, a channel cell's **Reset Red** (or whichever channel) and the row's **Set end value to default** write a straight curve to the action's end, so the curve animates back to neutral.
- **Turning a look on or off, or changing it, applies to the clip itself, not to the action**, even with an action selected. A look that differs between start and end switches at the action's end. Amount is what animates.
- **Turning a qualifier range on or off** switches at the action's end.

While an action is selected, a grade section's header shows **Clear** in place of **Reset**, and only when the action animates one of that section's rows: it removes the section's settings from the action. Right-click a grade row for **Remove from action N** or **Set end value to default**.

The grade controls show the action's animation in their own way:

- **Wheel disc:** a hollow square at the action's start value, the puck in action colour, and a coral mark at the value under the playhead.
- **Wheel strip:** filled in action colour from the start value, with a coral tick at the playhead's value.
- **Curve plot:** the action's start curve dashed, and the edited curve and its points in action colour.
- **Qualifier strip:** the band outlined and its knobs drawn in action colour.

Sliders carry the same marks as everywhere else in the inspector; see [Motion and transitions](motion-and-transitions.md).

*Agents:* `add_action`, then `set_action_end` with a `video` patch carrying `color`, `wheels`, `curves`, `look.amount` or `qualifier`.

## Copying a grade: Paste Attributes

Copy a graded clip (⌘C), select other clips, and choose **Edit ▸ Paste Attributes** (⌥⌘V). The copied clip's video settings replace each selected clip's in one undo step: its grade, look, filters and the rest of its picture settings, including position and scale. Where the copied clip has sound, its audio settings come too. A clip's place, speed, actions, transitions, name and label are never copied.

Qualifiers follow the clip type:

- Pasting onto an ordinary clip drops the qualifier.
- Pasting from an ordinary clip onto an adjustment clip keeps the adjustment clip's own qualifier.
- Between two adjustment clips, the qualifier is copied.

Pasting a clip that has blur, sharpen, pixelate or a blend mode onto an adjustment clip is refused.

*Agents:* `paste_attributes`, which takes `groups` (`video`, `audio`, `text`, `shape`, `graphic`) to copy only some of them.

## Limits

- The Color tab needs every selected clip to be gradable. Deselect text, shape, graphic and nest clips first.
- Qualifiers exist only on adjustment clips. To grade one colour, put an adjustment clip above the picture for the span you want. It grades every track behind it, so a matte track cutting its track is how you confine it to one area (see [Canvas and layers](canvas-and-layers.md)).
- There is no Offset wheel. Use Color's **Brightness** for an overall lift.
- Show Ungraded, Show Selection and the scopes affect only the window's preview. Nothing about them is saved or exported.
- A curve holds at most 16 points and at least 2.
- Only 3D `.cube` LUTs with a size of 2 to 65 are read.

See also: [Canvas and layers](canvas-and-layers.md) for blend modes, filters and mattes, [Export](export.md) for writing the graded film, and [Menus and shortcuts](menus-and-shortcuts.md) for every key.
