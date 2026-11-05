# Canvas, layers, text and shapes

The preview canvas is where you place a clip's picture. Select a layer on it,
then drag to move, scale, rotate or crop it. The Clip tab's **Picture**
sub-tab holds the same placement as numbers, along with opacity, blend modes,
shadows, filters and the effects that hide or highlight part of a frame. This
page also covers what you can put on the canvas besides footage: text clips,
shape clips, image clips, background plates, and matte tracks, which cut the
track behind them.

Every clip that draws can be edited the same way: video, image, still, text,
shape and graphic. A nest clip takes the same drags, though not crop. A track
never holds just one kind of clip.
Tracks stack back to front, and a track higher in the timeline draws in front.

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
- A nest clip has one box, the rectangle it is placed in, with an outline and
  handles like any clip. A click selects it only where something inside it
  draws, so a click on an empty part of the rectangle reaches the clip behind.
  A nest made with ⌘G fills the canvas whatever it holds, so a small picture
  inside it is the part to click, and its outline is the whole canvas.

The selected clips get an outline. The front-most selected clip also gets
handles.

### Move, scale and rotate

| Gesture | What it does |
|---|---|
| Drag inside the box | Move. Every selected clip moves by the same amount |
| Drag one of the eight square handles | Scale (see below) |
| ⌥ while scaling | Scale about the centre instead of pinning the opposite handle |
| Drag the round grip above the top edge | Rotate about the clip's centre |
| ⇧ while rotating | Snap the angle to 15° steps |
| Esc during any drag | Cancel the drag and put the clip back where it was, with no undo step |

With the canvas focused and a selected clip showing at the playhead, the arrow
keys nudge it 1 pixel, or 10 with ⇧. Each press is one undo step named Nudge,
and with an action selected it moves the action's end state. The canvas has
the focus from a click or drag on it until a click anywhere else in the window.
Otherwise ← and → step the playhead by a frame (⇧ for 10 frames), and ↑ and ↓
go to the previous and next edit point. During a canvas drag they do nothing.

How a scale drag behaves depends on the clip:

- **Video, image, still and graphic clips** have one uniform scale. Every
  handle scales the whole picture and keeps its aspect ratio.
- **Shape clips** change their box size instead. A corner handle keeps the
  aspect ratio and ⇧ frees it. An edge handle changes only the width or only
  the height.
- **Text clips**: the left and right edge handles set the text box's wrap
  width, which makes the box fixed-width. The corners and the top and bottom
  edges scale the text uniformly.

A drag scales between 1 % and 1000 %. A shape's box and a text clip's wrap
width stay within 4–20000 px. Each drag is one undo step, and a click that
doesn't move anything adds no step.

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
crop drag edits that action's end state, just as the inspector's fields do.
The box on screen still shows the frame at the playhead. There are two exceptions: a drag on a multi-clip selection, and a
shape's box resize, both edit the clip itself. See
[Motion and transitions](motion-and-transitions.md).

With one clip selected and no action selected, a move, nudge, scale, rotate
or crop past an action that has ended and holds what the gesture changes (a
zoom's position and size, say) changes nothing. Frame Job beeps, and the
inspector's foot names the action: "Refused: action 1 on this clip's lane
holds its position at the playhead, so a move here would show only before it.
Select action 1 first." Select it, then drag. Dragging a text clip's left or
right edge still sets its wrap width when the action holds no width. Before
the action starts, or inside it after **Esc**, a drag edits the clip itself.

## Crop

Press **C**, or double-click a video, image or still clip, to enter crop mode
for the selected clip. The eight handles become crop edges, and the part being
cut away is shown as a faint white area inside the uncropped frame's dashed
outline. Press **Esc**, **Return** or the keypad's **Enter** from anywhere but
a text field, or click empty canvas, to leave crop mode. Clicking a video, image
or still clip that isn't selected keeps crop mode on and moves the crop handles
to that clip; clicking a text, shape or graphic clip ends it. With
several clips selected, crop mode ends if the clip you click isn't the
front-most selected clip afterwards. Crop mode doesn't open on a nest clip, so **C** and a double-click only beep on one, unless it's on a matte track.

A crop removes edges in place: the picture never shifts as you crop. Crop
amounts are in the source's own pixels, so they stay correct when you scale
the clip later. The core keeps at least one source pixel in each direction.

The Picture tab's **Crop** section has the same four insets as fields, plus a
**Crop on Canvas** button that enters crop mode. The section appears only for
clips with pixels of their own, which means video, image and still clips.

**C** beeps on a text, shape or graphic clip, and so does a double-click on a
shape or graphic, except on a matte track, where crop shapes the matte. There
they enter crop mode. They have no Crop section, so there are no fields and no
**Reset**. To take that crop off, undo or drag the handles back.

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
| Behind Subject | every clip that draws but an adjustment or nest clip, at the top level |
| Layout | one selected clip of a video file ([Camera layouts](#camera-layouts)) |
| Hide While Silent | every clip that draws but a nest clip ([Hide while silent](#hide-while-silent)) |
| Crop, Corner Radius, Chroma Key | video, image and still clips |
| Background | clips of a video file, freeze frames of one, and image clips |
| Cursor | clips of a movie whose cursor file the picture doesn't already show ([The cursor](screen-recording.md#the-cursor)) |
| Shadow, Filters, Reflection, Spotlight, Obscure | every clip that draws, text and shapes included. On a nest clip they show but draw nothing, so set them on the clips inside |

Each section folds open and shut and shows a one-line summary in its header.
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
| Motion Blur | 0–100 % of a frame (quick values 0, 25, 50, 100); greyed on a nest or adjustment clip ([Motion blur](motion-and-transitions.md#motion-blur)) | 0 % |

Two buttons sit under the rows:

- **Fit to Canvas** scales each clip so its whole picture fits, and centres it.
- **Fill Canvas** scales each clip until it covers the whole canvas, and
  centres it.

Text clips are skipped, because their size comes from the words. Reset
Transform sets position, scale, rotation, opacity, blend and motion blur back to
their defaults.

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

- Both clips of a transition draw as Normal for as long as they overlap, and a
  clip on a matte track always does.
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

### Remove Background

The Background section, right after Chroma Key, keeps the person in a clip of a
video file or a picture and makes the rest transparent, so whatever is on the
tracks behind shows through. No green screen is needed: the person is found in
every frame on this Mac (Vision's person segmentation), with no upload and no
key. **Clip ▸ Remove Background** turns it on or off for the selected clips
too.

| Row | What it does | Default |
|---|---|---|
| Remove background | Turns it on. Turning it on gives each selected clip without it the defaults; turning it off removes it from all of them | off |
| Subject | Only when every selected clip is a picture: **Person** keeps the person; **Foreground** keeps the photo's foreground subject, whatever it is (below) | Person |
| Background | **Remove** draws the person alone; **Keep** draws the whole picture | Remove |
| Edge | Pulls the outline in (below 0) or pushes it out (above 0), −1 to 1 | 0 |
| Feather | How soft the outline is, 0–100 % | 0 % |
| Status | Where the person masks stand (below) | — |
| Analyze Now | Makes the masks now; after a failure, tries again | — |

Edge works on how sure the person mask is at each point. With Feather at 0,
Edge 0 draws the outline where the mask is half sure it is the person; −1 pulls
it in to where the mask is 7/8 sure, and +1 pushes it out to where it is only
1/8 sure. Between −0.5 and 0.5 the outline sits where the mask is 1/2 − Edge/2
sure. Where the mask fades from background to person across a band of pixels,
Edge +1 or −1 moves the outline about three eighths of that band's width, and
raising Edge never removes anything a lower Edge kept.

Subject, Background, Edge and Feather are dimmed until every selected clip has
Remove Background on. With an action selected Background, Edge and Feather
animate like any other row (Background switches at the action's end); the
checkbox, Subject and **Reset** always change the clip itself, and their gutter
shows ⊘. Subject reads mixed when the selected pictures differ.

A picture's mask is made from the picture itself, once, as the preview draws
it: Person uses the same person segmentation as a video, and Foreground uses
Vision's foreground instance mask, which keeps every foreground subject it
finds. A picture is one frame, so its Status goes straight from Analyzing to
Ready, **No person found** or **No subject found**.

The masks are made as soon as Remove Background is on, for the frames the clip
plays, and kept in the project's cache, so they are never made twice. Until a
frame's mask is made, the preview draws that frame whole; an export waits for
every mask it draws. Status reads:

- **Analyzing N %** — the masks are being made.
- **Ready** — every frame the clip plays has its mask.
- **No person found** — every frame was looked at and no person is in the
  clip, so it draws whole.
- **No subject found** — a picture with Subject **Foreground** was looked at
  and no foreground subject was found, so it draws whole.
- **Failed:** and the reason — the media file is missing, cannot be read, or
  the masks could not be written. Fix the cause and press **Analyze Now**.
- **No picture to analyze** — the clip plays no frame of its file.
- **—** with several clips selected; the section's summary then reads "on".

### Text behind the subject

A title, shape, picture or graphic can sit behind the person in a camera clip
or a photo: the person stands in front of it while the room stays behind it.
**Insert ▸ Text Behind Subject** does it in one step at the playhead:

- It picks the clip of a video file or picture playing at the playhead on a
  shown track that is not a matte track: the front-most selected one, else the front-most
  with Remove Background on, else the front-most.
- It adds a track named "Behind Subject" directly above that clip's track
  (above any matte tracks in front of it), and on it a title with the Title
  preset, from the playhead for 4 seconds or to the clip's end if sooner.
- The title is put behind the subject. If the clip had no Remove Background,
  it is turned on with **Keep** background and Subject **Person**, so the
  camera picture or photo stays whole and the person still hides the title.
- The new title is selected; one **Undo** takes it all back.

The item is greyed while a nest is open and when no such clip plays at the
playhead.

Any clip that draws, but an adjustment or nest clip, can be put behind a
subject by hand: the Picture tab's **Behind Subject** section, right after
Transform, has one checkbox, **Behind subject**. A clip with it on is cut, at
every moment, by the person, or a picture's foreground subject, in every clip
with Remove Background on (Remove or Keep) that is on a track behind it —
inside a nest too, when the nest clip is behind it. A cut-out clip on a track
in front of it does not cut it. Its shadow is cut with it. Where no mask is
drawn yet, or no subject is found, the clip draws whole. With one clip selected and the box on, the section notes
"No cut-out clip is behind it at the playhead." when nothing cuts it there.
With an action selected the checkbox writes the action's end, and it switches
at the action's end.

*Agents:* `text_behind_subject {clip?, at?, content?}`, and `set_video
{behind_subject: true}`.

### Camera layouts

A screen recording with a camera in front of it can switch between layouts as
it plays. Put the playhead where the switch should happen and choose one from
**Clip ▸ Camera Layout ▸**:

- **Corner ▸**, **Rounded Corner ▸** and **Circle ▸**, each with **Bottom
  Right**, **Bottom Left**, **Top Right** and **Top Left** — the camera in a
  box a quarter of the canvas wide and a third tall, 5 % in from the edges, as
  a recording lands it. Corner shows the whole camera picture with square
  corners, Rounded Corner rounds them, and Circle crops the largest square of
  the picture to a circle. The screen goes where a new clip lands: centred, at
  Fit scale if it is bigger than the canvas and **Fit new clips to canvas** is
  on, otherwise at 100 %.
- **Side by Side** — the screen fitted in the left two-thirds, the camera
  cropped to fill the right third, with a margin around and between them and
  slightly rounded corners.
- **Stacked** — the screen across the top, the camera cropped to fill the rest
  below it.
- **Camera Full** — the camera fills the canvas.
- **Screen Only** — the camera is hidden where it is (its opacity goes to 0),
  and the screen is placed as in Corner.

**Which clips:** with two clips with a picture selected on different tracks,
the front one is the camera and the other the screen. With one selected, it is
the camera and the screen is the clip drawing behind it at the playhead (the
front-most one on a shown track that is not a matte track). With none
selected, the camera is the clip at the playhead on the front-most track named
"Camera" — the track a recording's camera lands on. The item is greyed when
there is no such camera at the playhead, or a sheet is open. It works inside
an open nest too. Side by Side and Stacked need a screen; the other three lay
out a camera alone.

**The switch** eases over half a second from the playhead — a layout action on
each clip, which you see on its action lane and can retime like any other. At
a clip's first frame it cuts instead: the layout becomes the clip's own
placement there. Choosing another layout while one is still easing ends the
first where the second begins. One **Undo** takes the whole switch back.

**How far it reaches:** a layout holds until the next switch. Every later clip
on the camera's track (and on the screen's) that starts before the next layout
action on that track takes the layout as its own placement — so a camera cut
into pieces stays in the corner — and keeps its own actions. Text and
adjustment clips are left out.

**Moving a laid-out camera:** a camera that landed with a recording has its
switch on its first frame, a one-frame layout action. With that one clip
selected, a move, nudge, scale or crop on the canvas changes the switch and the
clip's own values together, so the clip moves on every frame, with or without
the action selected. A rotate changes the clip's own values, which reach every
frame too.

A switch later in a clip takes more: a clip shows a layout action's end state
until a later action changes it. With the playhead past the switch and no
action selected, a move, nudge, scale or crop on the camera changes nothing:
Frame Job beeps, and the inspector's foot names the switch's action and asks
you to select it first. Before the switch, a drag changes the clip's own
values, which show only until the switch. To change the layout itself, put the playhead on the switch,
select the camera clip (which selects the action), press → until the playhead
is past the switch, then drag the camera or type in the Transform rows, and
press **Esc**.

Typing a first-frame switch is the one difference from a drag. The Transform
rows change one place, and the switch's first frame shows the clip's own values,
so with the action selected that frame stays in the old place. To move it too,
put the playhead on the first frame, press **Esc**, and type the same values in
the Transform rows.

**The Layout section:** with one clip of a video file selected, the Clip tab's
Picture sub-tab has a **Layout** section (after Transform and Behind Subject, shut
until you open it): **Layout** (Corner, Side by Side, Stacked, Camera Full,
Screen Only), **Shape** (Square, Rounded, Circle) and **Corner** (Bottom Right,
Bottom Left, Top Right, Top Left) — Shape and Corner only for Corner — a
**Duration** for the switch (0.5 s to start, 0.01–10 s) and **Switch at
Playhead**, which does exactly what the menu does with this clip as the camera
and the clip behind it as the screen. The section's choices stay while the
window is open and are not saved; there is no Reset. Pressed with the playhead
off the clip, the inspector's foot says the clip does not play there and
nothing changes.

**Centred on the person:** Circle, Side by Side and Stacked crop the camera.
When the camera clip's person masks are already made for every frame it plays
— Remove Background makes them, and they stay in the project's cache — the crop
centres on the person (the middle of where the masks find them, averaged over
the clip) instead of on the middle of the picture. A layout never starts that
analysis itself: with no masks, or masks for only part of the clip, the crop
centres on the picture. An image clip as the camera always centres on the
picture.

**Zooms:** a switch never fights a zoom. When a clip it would move holds a zoom
(or another action that moves it) after the playhead, the switch is refused.
A screen that is still at its full placement is not asked in Corner, Camera
Full and Screen Only, because those leave it where it is and its zooms keep
playing. When nesting those clips would let the switch go ahead, a sheet asks
**Lay out the clips in a nest?**, with the reason it was refused: **Nest and
Switch** puts the clips in a nest first, so the layout moves the nest and the
zooms keep playing inside it — the nest and the layout are one **Undo** —
and **Cancel** changes nothing. Otherwise the inspector's foot names the clip
and the action. A nest clip shows square corners only, so Rounded Corner and
Circle are refused on a nest clip camera.

*Agents:* `switch_layout {camera, screen?, layout, shape?, corner?, at,
duration?, curve?, focus?, nest?, through?}` — `focus` centres the camera's
crop on a point of its picture; left out, it is filled from the camera clip's
person masks as the menu fills it, and the answer's `focus` says what was sent
(null for none). It is never filled when `nest: true` nests the camera itself.
An agent is never offered the sheet: it sends `nest: true` to nest in the same
step. `through` stops the layout holding at a time.

**In a vertical version:** **File ▸ Make Vertical Version…** keeps the camera
layouts: each switch is made again on the new canvas at the same time, length
and curve, Side by Side becoming Stacked on a tall canvas, and the camera and
screen are never followed (see
[Vertical and framing](vertical-and-framing.md#make-vertical-version)). A
layout whose camera or screen was moved by hand after the switch is kept as
placed and named in the summary. *Agents:* `reframe_clip {follow: "layout",
from_width, from_height}` on the camera does the same for one camera.

### Hide while silent

A camera clip can fade out while nobody is talking and fade back in just before
speech starts. Select the camera and open the Clip tab's Picture sub-tab: the
**Hide While Silent** section comes after Layout, shut until you open it. It is
offered for any clip with a picture but a nest clip (set it on the clips inside
the nest).

- **Hide while silent** turns it on. The camera follows the first file in
  **Speech from** — the files with sound playing under the clip, the
  microphone (a file with no picture) first, then the one that plays under it
  longest. Off, or Reset, takes it away.
- **Speech from** picks another file to follow.
- **Pre-roll** (0.2 s to start) is how long before each run of words the
  camera is fully back; **Hold** (1.5 s) how long it stays after; **Fade**
  (0.3 s) how long it takes to fade out and in. Each is 0–5 s.

The speech is the same as Duck by Speech's: the runs of words Frame Job finds
in the file on this Mac when it is added (no key, nothing uploaded). The first
time a file is followed, those runs are saved in the project, in the same
**Undo** step. If the file's speech has not been found yet, the checkbox is
greyed, and its tooltip says to try again in a moment.

Where the file does not play at all, the camera shows. When the camera is
inside a nest and the microphone is not, the microphone outside is followed.
The timeline draws a teal line over the camera clip's picture: at the top the
camera shows, at the bottom it is hidden. The fade is only in the picture: the
Transform section's Opacity and the agent's `get_project` still show the
clip's own value, and an action cannot animate it.

*Agents:* `set_video {clips, patch: {hide_silent: {media, pre_roll?, hold?,
fade?}}}`, the times in ticks; `{hide_silent: null}` removes it. When the media
has no saved speech the tool saves it first in the same step, and it refuses a
media with no sound or one whose speech has not been found yet.

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

A clip can carry up to **four** filters. Pixelate, Blur and Sharpen act on the
picture first, wherever they sit in the list. Sepia, Noir, Vignette and Invert
come after them, in list order.

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

**Spotlight a region** dims the clip outside a rectangle or ellipse on it, and
can magnify what is inside. Only the clip's own picture darkens: the clips
behind it and the canvas around it stay as they are.

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
through every move, scale and rotation. A region is measured from the centre
of the cropped picture, so a crop that takes more off one side than the other
shifts it across the picture by half the difference. Each region's numbers can
be animated like any other property. **Add Region**, **Place on Canvas** and
**Remove** always change the clip itself, not the selected action.

## Text clips

Press **T**, or use the timeline bar's **Add Text** button, to add a text clip
at the playhead. It goes on the front-most track if there is room, or on a new
track in front of everything if there isn't. The new clip:

- reads "Title" in Source Sans 3 Bold at 72 px, white, centred
- lasts 5 seconds
- is selected, so the **Text** sub-tab opens on it (an inspector showing
  Transcript or Assistant stays there)

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
A text clip also gets the Picture tab's Transform, Behind Subject, Hide While
Silent, Shadow, Filters, Reflection, Spotlight and Obscure sections.

Every frame of a reveal is worked out by the same calculation for the
preview, a rendered frame and an export, so the three always agree. A text
clip made by word captions has a word style, and while it does, the Reveal
section is greyed with "Word style wins; the reveal does not apply." (see
[Captions](captions.md)).

### Text presets

Each preset sets the face, size, alignment, backdrop and position in one
undo step. It also sets **Vertical** to middle and **Opacity** back to 100 %.
Sizes are fractions of the canvas's shorter side and positions fractions of
its width and height, so a preset fits any canvas size and a vertical canvas
gets the same text height as a horizontal one. On a canvas taller than wide
the Caption preset sits higher, a quarter of the height below centre. With an
action selected on the action lane, a preset sets that action's end state,
like any other field.

| Preset | Face | Size (of the shorter side) | Placement | Backdrop |
|---|---|---|---|---|
| Title | Source Sans 3 Bold | 9 % | centred | none |
| Subtitle | Source Sans 3 SemiBold | 5 % | centred, 18 % of the height below centre | none |
| Lower Third | Source Sans 3 SemiBold | 4.5 % | left-aligned, left of centre and low | black at 55 %, padding 18, radius 6 |
| Caption | Source Sans 3 Regular | 3.5 % | centred, 38 % of the height below centre (a quarter on a tall canvas) | black at 60 %, padding 12, radius 8 |

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

A shape also gets the Picture tab's Transform, Behind Subject, Hide While
Silent, Shadow, Filters, Reflection, Spotlight and Obscure sections.

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
clips have everything on the Picture tab but Layout and Cursor, Crop, Corner
Radius and Chroma Key included, and a Color tab for grading. Remove Background works on a picture too,
keeping its person or its foreground subject (see
[Remove Background](#remove-background)).

When the Document tab's **Fit new clips to canvas** option is on, a new clip whose picture
is bigger than the canvas starts at Fit scale. Otherwise it starts at 100 %,
its native size.

## Backgrounds

Backgrounds are in the Clip menu. Each command puts a clip on a **new
back-most track** and selects it.

| Command | What it puts there |
|---|---|
| **Clip ▸ Add Background ▸ Solid Color** | A canvas-sized white rectangle named "Background", starting at 0 and as long as the timeline. White because the canvas is already black. Recolour it in the Shape tab's Fill row, or turn on Gradient for a full-canvas ramp |
| **Clip ▸ Add Background ▸ Image…** | A picture you choose (the panel offers only image files; see [What Frame Job reads](projects-and-media.md#what-frame-job-reads)), scaled to fill the canvas, as long as the timeline. The picture joins the Media tab in the same undo step, or is reused if it is already there. If it can't be read, an alert says so and nothing is added |
| **Clip ▸ Add Blurred Background** | A copy of the one selected clip, playing exactly the same frames, scaled to fill the canvas, centred, uncropped and blurred at full strength. It is muted so the sound doesn't play twice, and is named "Blurred Background". This is the usual backdrop for a screen recording or a vertical video that doesn't fill the frame |

Limits:

- Add Blurred Background needs exactly one selected clip. It is dimmed for a
  text clip, an adjustment clip, a clip of an audio-only file and a nest clip,
  none of which has a picture size to scale to the canvas. Video, image, still, shape
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

- Scale is uniform for pictures. Only shapes (box width and height), text
  (wrap width) and graphics (the Graphic tab's Width and Height) can change on
  one axis.
- At most four filters and four obscure regions per clip. Gradients have 2–8
  stops.
- The Crop, Corner Radius and Chroma Key sections are only for video, image and
  still clips. On a matte track, a text, shape or graphic clip can still be
  cropped on the canvas ([Crop](#crop)).
- A nest clip can't take a blend mode, and Add Blurred Background is not
  offered for one.
- Locked tracks can't be edited on the canvas, and hidden tracks can't be
  clicked there.
- The canvas text editor stays upright even for a rotated text clip. The text
  you apply is the same either way.
