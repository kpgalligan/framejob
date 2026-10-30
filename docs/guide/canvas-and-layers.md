# Canvas, layers, text and shapes

The preview canvas is where you place a clip's picture. Select a layer on it,
then drag to move, scale, rotate or crop it. The Clip tab's **Picture**
sub-tab holds the same placement as numbers, along with opacity, blend modes,
shadows, filters and the effects that hide or highlight part of a frame. This
page also covers what you can put on the canvas besides footage: text clips,
shape clips, image clips, background plates, and matte tracks, which cut the
track behind them.

Every clip that draws can be edited the same way: video, image, still, text,
shape, graphic and nest. A track never holds just one kind of clip. Tracks
stack back to front, and a track higher in the timeline draws in front.

## The canvas

The canvas shows the composition at the playhead, at the project's size,
centred in the preview pane. Under it is a small caption with the canvas size
and frame rate, for example `1920 × 1080 · 30 fps`. You set the canvas size,
rate and background colour on the Document tab (see
[Projects and media](projects-and-media.md)).

### Zoom and pan

| Do this | To |
|---|---|
| Toolbar zoom popup: **Fit**, **50%**, **100%**, **200%** | Pick a zoom stop |
| **View ▸ Zoom In** (⌘+ or ⌘=), **View ▸ Zoom Out** (⌘-) | Step through the same four stops |
| **View ▸ Zoom to Fit** (⌘0) | Go back to Fit |
| Pinch on the trackpad, or ⌥-scroll / ⌘-scroll | Step through the stops |
| Hold Space and drag, or scroll | Pan, when the zoomed canvas is bigger than the pane |

A Space tap that does not pan still plays and pauses as usual.

**View ▸ Preview Window** (⇧⌘P) opens a second window with the same picture
and no handles, for a second display.

### Selecting

- Click a layer to select the topmost visible clip under the pointer at the
  playhead. Hit-testing follows the layer's rotation.
- ⇧-click adds a clip to the selection or removes it.
- Click empty canvas to clear the selection.
- Clips on hidden tracks are not drawn, so you can't click them. Clips on
  locked tracks are drawn but can't be selected or moved on the canvas.
- A clip on a matte track can be selected and dragged like any other clip
  inside its own box, even though it draws nothing there (see
  [Matte tracks](#matte-tracks)). Because it is topmost inside that box, a
  click there selects the matte clip. To select the clip it cuts, click
  outside the matte clip's box, or use the timeline.

The selected clips get an outline. The front-most selected clip also gets
handles.

### Move, scale and rotate

| Gesture | What it does |
|---|---|
| Drag inside the box | Move. Every selected clip moves by the same amount |
| ← → ↑ ↓ (canvas focused) | Nudge the selection 1 canvas pixel |
| ⇧ + arrow | Nudge 10 pixels |
| Drag one of the eight square handles | Scale (see below) |
| ⌥ while scaling | Scale about the centre instead of pinning the opposite handle |
| Drag the round grip above the top edge | Rotate about the clip's centre |
| ⇧ while rotating | Snap the angle to 15° steps |
| Esc during any drag | Cancel the drag and put the clip back where it was, with no undo step |

How a scale drag behaves depends on the clip:

- **Video, image, still, graphic and nest clips** have one uniform scale. Every
  handle scales the whole picture and keeps its aspect ratio.
- **Shape clips** change their box size instead. A corner handle keeps the
  aspect ratio and ⇧ frees it. An edge handle changes only the width or only
  the height.
- **Text clips**: the left and right edge handles set the text box's wrap
  width, which makes the box fixed-width. The corners and the top and bottom
  edges scale the text uniformly.

A drag scales between 1 % and 1000 %. Each drag is one undo step, and a click
that doesn't move anything adds no step.

There is no separate anchor-point control. Rotation, the Picture tab's Scale
field and a ⌥ scale drag pivot on the centre of the clip's uncropped picture.
A plain handle drag keeps the opposite handle in place by moving the clip as
it scales.

### Line and arrow endpoints

A line or arrow shape has a round handle at each end. Drag a handle to move
that end. The scale handles and the rotation grip still work on the line's
box.

### Snapping

While you drag a clip to move it, the box snaps to:

- the canvas edges, its centre lines and its thirds
- the edges and centres of every other visible layer

Scaling, rotating and cropping do not snap (⇧ while rotating snaps the angle
to 15° steps instead). A guide line is drawn across the canvas on each axis that snapped. Press
**N** or choose **View ▸ Snapping** to turn snapping on or off. The timeline
uses the same setting. Hold ⌘ during a drag to stop snapping for that drag.

### Safe areas

**View ▸ Safe Areas**, or the toolbar's **Safe** checkbox, draws two guide
frames over the canvas, at 90 % and 80 % of its size. They are guides only
and never appear in an export. The app remembers the setting.

### Editing an action's end state on the canvas

With an action selected on the clip's action lane, a move, scale, rotate or
crop drag, or an arrow-key nudge, edits that action's end state, just as the
inspector's fields do. The box on screen still shows the frame at the
playhead. There are two exceptions: a drag on a multi-clip selection, and a
shape's box resize, both edit the clip itself. See
[Motion and transitions](motion-and-transitions.md).

## Crop

Press **C**, or double-click a clip that is not text, to enter crop mode for
the selected clip. The eight handles become crop edges, and the part being
cut away is shown as a dim ghost inside the uncropped frame. Press **Esc** or
**Return**, or click empty canvas, to leave crop mode.

A crop removes edges in place: the picture never shifts as you crop. Crop
amounts are in the source's own pixels, so they stay correct when you scale
the clip later. The core keeps at least one source pixel in each direction.

The Picture tab's **Crop** section has the same four insets as fields, plus a
**Crop on Canvas** button that enters crop mode. Crop appears only for clips
with pixels of their own, which means video, image and still clips.

## Inline text editing

Double-click a text clip on the canvas to type into it in place. The editor
uses the clip's own font, tracking and line spacing at the canvas's zoom, and
it grows and wraps as you type, the way the text will once you apply it.
UPPERCASE text is edited as you typed it.

| Key | In the canvas text editor |
|---|---|
| Return (or keypad Enter) | Apply the text and close the editor |
| ⇧Return, ⌥Return, ⌘Return or ⌃Return | New line |
| Esc | Close at once if nothing changed. Otherwise a sheet asks **Apply** (the default), **Revert** or **Cancel** |
| Click elsewhere | Apply |

While an input method is composing, Return and Esc go to the input method.

## The Picture tab

Select a clip and open the inspector's **Clip** tab. Its sub-tabs depend on
what is selected:

- Text clips start on **Text** and shapes on **Shape**.
- Any clip that draws has **Picture**.
- **Color**, **Sound** and **Clip** follow where they apply.

An adjustment clip has no Picture tab, because it has no picture of its own
(see [Color grading](color-grading.md)).

Picture's sections, in order:

| Section | Shown for |
|---|---|
| Transform | every clip that draws |
| Crop, Corner Radius, Chroma Key | video, image and still clips |
| Shadow, Filters, Reflection, Spotlight, Obscure | every clip that draws, text and shapes included |

Each section folds open and shut and shows a one-line summary while closed.
Transform starts open. **Reset** appears only while a section differs from its
default. With several clips selected, a field shows the first clip's value and
a mixed badge when the others differ. An edit applies to every selected clip.
Colour swatches open the macOS Colors panel, with opacity.

*Agents:* `set_video` (merges a patch into each clip's video properties: `x`,
`y`, `scale`, `rotation`, `opacity`, `blend`, `crop`, `corner_radius`,
`shadow`, `chroma`, `filters`, `reflection`, `spotlight`, `obscure`).

### Transform

| Row | Range | Default |
|---|---|---|
| Scale | 1–1000 % (quick values 25–400) | 100 % |
| Position X / Y | −20000 to 20000 canvas px, measured from the canvas centre, X right and Y down | 0, 0 |
| Rotation | −180° to 180° | 0° |
| Opacity | 0–100 % | 100 % |
| Blend | the eight blend modes below | Normal |

Two buttons sit under the rows:

- **Fit to Canvas** scales each clip so its whole picture fits, and centres it.
- **Fill Canvas** scales each clip until it covers the whole canvas, and
  centres it.

Text clips are skipped, because their size comes from the words. Reset
Transform sets position, scale, rotation, opacity and blend back to their
defaults.

#### Blend modes

| Mode | What it does |
|---|---|
| Normal | Draws over what is underneath |
| Multiply | Darkens by multiplying with what is underneath |
| Screen | Lightens, the inverse of multiply. A screened white blob reads as a glow |
| Add | Adds the colours together |
| Overlay | Multiplies the darks and screens the lights |
| Darken | Keeps the darker of the two colours |
| Lighten | Keeps the lighter of the two colours |
| Difference | The absolute difference of the two colours |

A blend needs something under the layer. Over the empty black canvas,
Multiply, Darken and Overlay read black, and Screen, Add, Lighten and
Difference change nothing. When that is what is happening, the section says
so, for example "Nothing behind this clip — multiply reads black here." The
note looks at the clip's whole span, not just the playhead. It ignores hidden
tracks and clips with their video turned off, and it appears only while the
canvas background is opaque black. To get a layer to blend against, use
**Clip ▸ Add Background** (see [Backgrounds](#backgrounds)), or set a
non-black canvas background on the Document tab. The Blend popup's tooltip
gives the same explanation.

Limits:

- A cross dissolve draws as Normal for as long as the clips overlap.
- The Blend popup is greyed on a nest clip, because a nest has no pixels of its
  own to blend. Un-nest it (⇧⌘G) to blend the clips inside.
- Blend is an ordinary property, so an action can change it. Like any
  on/off-style value, the change happens at the action's end.

### Corner Radius

Radius: 0–500 px in source pixels (quick values 0–64). It rounds the cropped
picture's corners. Default 0.

### Chroma Key

Chroma Key removes a background colour, such as a green screen.

| Row | What it does | Default |
|---|---|---|
| Key out a color | Turns the key on | off |
| Key Color | The colour to remove | pure green |
| Pick from Canvas | Arms an eyedropper ("Click to pick the key color · Esc to cancel"). One click on the preview sets the key colour and turns the key on. A second press of the button, Esc or a change of selection cancels it | — |
| Tolerance | How far from the key colour still counts as background, 0–100 % | 20 % |
| Softness | How gradual the edge of the key is, 0–100 % | 10 % |
| Spill | How much of the key colour's spill is removed from the edges that remain, 0–100 % | 50 % |

### Shadow

A drop shadow cast by the layer's own shape: the picture, the letters of a
text clip, or a shape's outline and fill.

| Row | Range | Default |
|---|---|---|
| Drop shadow | on / off | off |
| Color | any | black |
| Opacity | 0–100 % | 50 % |
| Blur | 0–200 px | 12 px |
| Angle | 0–360° | 315° |
| Distance | 0–200 px | 8 px |

### Filters

A clip can carry up to **four** filters. They are applied in list order, so
blur-then-sepia looks different from sepia-then-blur.

- **Add Filter** appends a Blur at 50 %.
- Each filter's row starts with a number popup that is its place in the
  stack. Pick a different number to move the filter.
- The kind popup has **Blur**, **Sharpen**, **Pixelate**, **Sepia**, **Noir**,
  **Vignette** and **Invert**.
- **Amount** is 0–100 %.
- **Remove** takes a filter off.

An action can animate a filter's amount, for example a blur that ramps up
across a clip. Adding or removing a filter always changes the clip itself,
even while an action is selected.

### Reflection

**Mirror the layer below itself** hangs a mirrored copy under the layer. The
reflection rotates with the layer, and the layer always draws over its own
reflection.

| Row | Range | Default |
|---|---|---|
| Opacity | 0–100 % | 35 % |
| Height | 0–100 % of the layer's height | 50 % |
| Gap | 0–200 px | 0 px |
| Falloff | 0–100 % | 100 % |

### Spotlight

**Spotlight a region** dims the canvas outside a rectangle or ellipse on the
clip, and can magnify what is inside.

| Row | Range | Default |
|---|---|---|
| Shape | Rectangle, Ellipse | Rectangle |
| Center X / Y | px from the centre of the clip's picture | 0, 0 |
| Width / Height | 1–20000 px | 480 × 270 |
| Feather | 0–200 px | 40 px |
| Dim | 0–100 % | 60 % |
| Zoom | 1.00–2.00× | 1.00× |

The spotlight's centre and size are measured in the clip's own source pixels.
The spotlight therefore stays on the same part of the picture when you move,
scale or rotate the clip.

### Obscure

Obscure hides a face, a password field or a phone number behind up to **four**
blurred or pixelated regions per clip.

- **Add Region** adds a 480 × 270 pixelated box at the centre of the layer.
- **Place on Canvas** arms a drawing mode ("Drag a rectangle to obscure · Esc
  to cancel"). Drag a rectangle over the selected clip to add a region there.
  A drag smaller than 6 px is treated as a miss, and the mode stays armed. The
  mode needs exactly one selected clip that is drawing at the playhead and has
  a free slot. Esc, a second press of the button, or a change of selection
  ends the mode, and so does the playhead leaving the clip.
- Only one canvas mode can be armed at a time: Place on Canvas, Zoom to
  Region (**Z**, see [Motion and transitions](motion-and-transitions.md)),
  Chroma Key's Pick from Canvas, and the qualifier's Pick from Canvas (see
  [Color grading](color-grading.md)). Arming one ends whichever other was
  armed.
- Each **Region N** row has a kind popup, **Pixelate** (hides) or **Blur**
  (softens), and a **Remove** button. Under it are **Shape** (Rectangle,
  Ellipse), **Amount** (0–100 %, default 100 %), **Feather** (0–200 px,
  default 20 px), **Center** (x, y) and **Size** (width, height, at least
  1 px).

On the canvas, the selected clip's regions are drawn as dashed outlines.
Drag a region's centre cross to move it. Drag one of its eight handles to
resize it, holding ⌥ to resize about its centre. The clip's own handles win
where they overlap a region, and a drag inside a region moves the clip. Esc
cancels the drag.

Regions are stored in the clip's own source pixels, so they follow the layer
through every move, scale, rotation and crop. Each region's numbers can be
animated like any other property. **Add Region**, **Place on Canvas** and
**Remove** always change the clip itself, not the selected action.

## Text clips

Press **T**, or use the timeline bar's **Add Text** button, to add a text clip
at the playhead. It goes on the front-most track if there is room, or on a new
track in front of everything if there isn't. The new clip:

- reads "Title" in Source Sans 3 Bold at 72 px, white, centred
- lasts 5 seconds
- is selected, so the **Text** sub-tab opens on it

A text clip has no source file, so you can trim it to any length.
Double-click it on the canvas to type (see
[Inline text editing](#inline-text-editing)).

*Agents:* `add_text_clip` (track, at, optional duration and text, either a
plain string or a text patch); `set_text` to restyle.

### The Text tab

| Section | Rows |
|---|---|
| **Content** | A multi-line text area. Return, Tab or a click away applies it and gives the keys back to the editor; ⇧Return, ⌘Return, ⌥Return or ⌃Return starts a new line |
| **Font** | **Family** (every font installed on the Mac, plus the faces the app ships with: Source Sans 3, Source Serif 4, Montserrat, Anton, Bebas Neue, Darker Grotesque and IBM Plex Mono), **Style** (that family's faces), **Size** 6–800 px |
| **Style** | **Color**, **Align** (L / C / R), **Vertical** (top / middle / bottom within the box), **UPPERCASE**, **Line spacing** 0.5–4× (default 1), **Tracking** −20 to 100 px (default 0) |
| **Outline** | **Outline** on/off, **Width** 0–40 px (default 2), **Color** (default black) |
| **Backdrop** | A plate behind the text: **Backdrop** on/off, **Fill** (default black at 60 %), **Padding** 0–200 px (default 12), **Radius** 0–200 px (default 8) |
| **Box** | **Mode**: **Auto-size** (the box fits the words) or **Fixed width** (the words wrap). **Width** is 20–20000 px, starting at 60 % of the canvas width |
| **Reveal** | How the text arrives and leaves: **None**, **Typewriter**, **Word Fade** or **Line Rise**, with separate **In** and **Out** durations (0–10 s; In defaults to 1 s and Out to 0) measured from the clip's first and last frame |
| **Presets** | One-click looks, described below |

UPPERCASE changes only how the text is drawn: what you typed is kept as typed.
A text clip also gets the Picture tab's Transform, Shadow, Filters,
Reflection, Spotlight and Obscure sections.

Every frame of a reveal is worked out by the same calculation for the
preview, a rendered frame and an export, so the three always agree. A text
clip made by word captions has a word style, and while it does, the Reveal
section is greyed with "Word style wins; the reveal does not apply." (see
[Captions](captions.md)).

### Text presets

Each preset sets the face, size, alignment, backdrop and position in one
undo step. It also sets **Vertical** to middle and **Opacity** back to 100 %.
Sizes and positions are fractions of the canvas, so a preset fits any canvas
size. With an action selected on the action lane, a preset sets that
action's end state, like any other field.

| Preset | Face | Size (of canvas height) | Placement | Backdrop |
|---|---|---|---|---|
| Title | Source Sans 3 Bold | 9 % | centred | none |
| Subtitle | Source Sans 3 SemiBold | 5 % | centred, 18 % of the height below centre | none |
| Lower Third | Source Sans 3 SemiBold | 4.5 % | left-aligned, left of centre and low | black at 55 %, padding 18, radius 6 |
| Caption | Source Sans 3 Regular | 3.5 % | centred, near the bottom | black at 60 %, padding 12, radius 8 |

## Shape clips

Click the timeline bar's **Add Shape** button and pick **Rectangle**,
**Ellipse**, **Line** or **Arrow**. Like text, the shape goes on the front-most
track if there is room, lasts 5 seconds, can be trimmed to any length, and
opens on the **Shape** sub-tab.

A new shape is a 320 × 120 box with a 6 px white stroke and no fill, so it
shows up over any footage. A new arrow has its head at the end turned on. A
new line or arrow runs diagonally across its box. A rounded rectangle is a
Rectangle with a corner radius, not a separate kind.

*Agents:* `add_shape_clip` (track, at, optional duration and shape, either a
kind name or a shape patch); `set_shape` for geometry and paint.

### The Shape tab

| Section | Rows |
|---|---|
| **Shape** | **Kind** (Rectangle, Ellipse, Line, Arrow), **Width** and **Height** 1–20000 px, **Corner radius** 0–2000 px (rectangles only) |
| **Stroke** | **Stroke** on/off, **Width** 0.5–200 px (default 6), **Color** (default white) |
| **Fill** | **Fill** on/off (white when first turned on), **Color**, **Opacity** 0–100 % |
| **Gradient** | Fills the shape with a colour ramp in place of the flat fill (below) |
| **Arrowheads** | **Arrowhead at start**, **Arrowhead at end** (lines and arrows only) |

A shape also gets the Picture tab's Transform, Shadow, Filters, Reflection,
Spotlight and Obscure sections.

### Gradients

Tick **Gradient** to fill a rectangle or ellipse with a colour ramp. A new
gradient is **Linear**, black to white, at 0°.

- **Kind**: **Linear** or **Radial**.
- **Angle**: 0–360°, linear only. 0° runs to the right and the angle turns
  counter-clockwise.
- **Stop N** rows: a colour swatch, a position (0–100 % along the ramp) and
  **Remove**. A gradient keeps at least two stops.
- **Add Stop** puts a new stop in the middle of the widest gap, in the colour
  the ramp already has there. A gradient can have up to **eight** stops.

Past the first and last stops, the end colours continue to the shape's edge.
While a gradient is on it covers the Fill colour, and the section says so.
Reset turns the gradient off and brings the flat fill back. Lines and arrows
have no area to fill: the Gradient section is greyed for them and they keep
their stroke colour.

### Animated colours

When an action changes a colour (the text colour, its outline or backdrop, a
word-caption colour, the drop shadow or the chroma key colour), the colour
blends through the OKLab colour space. This avoids the muddy midpoint a
straight RGB blend gives. See [Motion and transitions](motion-and-transitions.md).

Shape colours (stroke, fill and gradient stops) cannot be animated: a
shape's styling always changes the clip itself, even while an action is
selected.

## Image clips

You import an image the same way as a movie (see
[Projects and media](projects-and-media.md)), and it lands as a 5-second clip.
An image has no length of its own, so you can trim it to any duration. Image
clips have everything on the Picture tab, Crop, Corner Radius and Chroma Key
included, and a Color tab for grading.

When the Document tab's **Fit new clips to canvas** option is on, a new clip whose picture
is bigger than the canvas starts at Fit scale. Otherwise it starts at 100 %,
its native size.

## Backgrounds

Backgrounds are in the Clip menu. Each command puts a clip on a **new
back-most track** and selects it.

| Command | What it puts there |
|---|---|
| **Clip ▸ Add Background ▸ Solid Color** | A canvas-sized white rectangle named "Background", starting at 0 and as long as the timeline. White because the canvas is already black. Recolour it in the Shape tab's Fill row, or turn on Gradient for a full-canvas ramp |
| **Clip ▸ Add Background ▸ Image…** | A picture you choose (the panel offers only image files), scaled to fill the canvas, as long as the timeline. The picture joins the Media tab in the same undo step, or is reused if it is already there. If it can't be read, an alert says so and nothing is added |
| **Clip ▸ Add Blurred Background** | A copy of the one selected clip, playing exactly the same frames, scaled to fill the canvas, centred, uncropped and blurred at full strength. It is muted so the sound doesn't play twice, and is named "Blurred Background". This is the usual backdrop for a screen recording or a vertical video that doesn't fill the frame |

Limits:

- Add Blurred Background needs exactly one selected clip. It is dimmed for a
  text clip, an adjustment clip, an audio-only clip and a nest clip, none of
  which has a picture size to scale to the canvas. Video, image, still, shape
  and graphic clips can all take one.
- The blurred copy takes no transition, actions, label or ducking from the
  original.
- When an agent places a video plate, the plate stops where its file ends.

*Agents:* `add_background` (optional `color`, `media` or `duration`; with no
arguments it adds the white plate); `add_blurred_background` (`clip`).

## Matte tracks

A matte track cuts the track directly behind it. Its own clips are never
drawn. Instead, what they show decides where the track behind can be seen. Any
clip that draws can be a matte: text, a shape, a graphic, an image, a movie or
a nest. That makes it a window onto the footage beneath, in the preview,
rendered frames and every export.

Set the mode with **Track ▸ Matte**, or with the **Matte** submenu of a
track's context menu (right-click its header):

| Mode | The track behind shows where the matte clip is… |
|---|---|
| **Off** | (an ordinary track) |
| **Alpha** | opaque |
| **Inverted Alpha** | transparent |
| **Luma** | bright |
| **Inverted Luma** | dark |

How a matte behaves:

- Where the matte track has no clip, the track behind shows uncut.
- Hiding the matte track, or turning off a matte clip's video, turns the cut
  off, and the track behind shows whole.
- A matte with no target cuts nothing and still draws nothing. That happens
  for a matte on the back-most track, or one directly in front of another
  matte track.
- A matte clip's position, scale, rotation, crop, opacity, colour, filters,
  actions and transitions all shape the matte, so a moving title can wipe
  footage on.
- A matte clip's blend mode, drop shadow and reflection have no effect. The
  values are kept, and apply again when the track stops being a matte.
- A matte clip's sound still plays.
- An adjustment clip on a matte track has no effect.

When the selection sits on a matte track, every Clip sub-tab shows a note
under its sub-tab strip, and every control stays live:

| Selection | Note |
|---|---|
| Clips on a matte track with a track behind it | "Matte for the track below (Alpha). Not drawn: its blend mode, drop shadow and reflection have no effect." (with the track's mode) |
| Clips on a matte track with nothing behind it | "Nothing is behind this matte track, so it cuts nothing." |
| Adjustment clips on a matte track | "An adjustment clip on a matte track has no effect." |

### Mattes inside nests

A matte track works inside a nest just as it does on the timeline. A clip
inside a nest that sits on a matte track (directly, or because the nest clip
does) becomes a matte at the first matte track found going outward.

- **Nest** keeps a track's matte only when the track it cuts is nested with
  it. A matte nested without its target becomes an ordinary track inside the
  nest. The nest clip goes on the front-most of the nested clips' tracks
  that is not a matte track.
- **Un-nest** lines the nest's front-most non-matte track up with the nest
  clip's track, so the picture comes back as it was.

See [Editing](editing.md) for nesting itself.

On the timeline, a matte track's header carries a tag such as "Matte · Alpha",
or a dimmed "Matte · nothing behind" when there is nothing to cut. Its clips
are drawn at half opacity with dashed outlines, and a bracket joins it to the
track it cuts.

*Agents:* `set_track` (`matte`: `none`, `alpha`, `alpha_inverted`, `luma` or
`luma_inverted`).

## Copying a look between clips

**Edit ▸ Paste Attributes** (⌥⌘V) puts the look of the clip you copied onto
every selected clip, in one undo step. The look is its picture settings, its
sound settings, and its text or shape styling. A text clip keeps its own words
and a shape keeps its kind and size. **Edit ▸ Paste Graphic Properties**
does the same for graphic clips. See [Editing](editing.md) for exactly what
is copied.

*Agents:* `paste_attributes`.

## Limits

- Scale is uniform for pictures. Only shapes (box width and height) and text
  (wrap width) can be stretched on one axis.
- At most four filters and four obscure regions per clip. Gradients have 2–8
  stops.
- Crop, Corner Radius and Chroma Key are only for video, image and still
  clips.
- A nest clip can't take a blend mode, and Add Blurred Background is not
  offered for one.
- Locked tracks can't be edited on the canvas, and hidden tracks can't be
  clicked there.
- The canvas text editor stays upright even for a rotated text clip. The text
  you apply is the same either way.
