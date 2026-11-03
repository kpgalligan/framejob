# Vertical and framing

Frame Job can find who and what is in a clip's picture: faces, people and the
regions the eye is drawn to. It finds them on this Mac with Apple's Vision
framework — nothing is uploaded and no key is needed — and keeps what it found
in the project's cache, so it is found once per file. This page covers what is
found, how to see it, how **Clip ▸ Follow Subject…** frames the selected clips
on it, and how an agent reframes a clip with it.

## What is found

Ten times a second of the media's own time, Frame Job looks at the picture and
keeps:

- **Faces** — each face's box, how it is turned, and how open the mouth is.
- **People** — each person's head and shoulders, as a box.
- **Salient regions** — the parts of the picture the eye goes to first, as
  boxes. In a talking-head shot this is usually the speaker; on a slide it is
  often the text.

Boxes are found in each sample on its own: Frame Job does not follow a person
from one moment to the next or put names to faces.

Nothing is looked at when you import a file. A file is analysed when something
asks for it — **Clip ▸ Follow Subject…** (below), an agent
(`get_media_analysis` with `kind: "faces"` or `"subjects"`, see [MCP](mcp.md)),
or `reframe_clip` (below); Follow Subject and `reframe_clip` ask for the part of
the file each clip plays. Analysis runs in the background and
keeps what it has found if it is stopped; asking again continues it.

## Show Subjects

Choose **View ▸ Show Subjects** to draw, over the preview, what has been found
for the selected clip at the playhead:

- faces outlined in yellow,
- people outlined in teal,
- salient regions outlined in purple with a dashed line.

The boxes sit on the clip's picture wherever it is placed on the canvas — moved,
scaled, rotated or cropped — and follow its speed, speed ramps and reversal, so
they show what the clip is showing at that moment. Select another clip to see
its boxes; move the playhead to see another moment.

When nothing has been found for the clip's picture at the playhead, the preview
says **Not analyzed — Clip ▸ Follow Subject… analyzes it** at the clip's
top-left corner. Show Subjects never starts
an analysis itself, so turning it on costs nothing.

Show Subjects is a view of the window: it is off in a new window, it is not
remembered between launches, and it never changes an export or a saved frame.
Choose it again to turn it off. It has no shortcut and is always available.

## Follow Subject

Select the clips to frame — say landscape recordings on a 1080 × 1920 vertical
canvas — and choose **Clip ▸ Follow Subject…**. It is offered when a selected
clip plays a movie (inside a nest too); a still, a picture, a nest, text, a
shape, a graphic or an adjustment clip in the selection is left alone. The
sheet has three controls:

- **Follow** — **Subject** follows a face, or where there is none a person, or
  where there is neither the region the eye goes to; **Faces**, **People** and
  **Salient Region** follow only that kind; **Center** holds the frame on the
  middle of the picture for the whole clip.
- **Zoom** — how tight the frame is, 100 to 400 %: 100 % is the scale at which
  the picture just covers the canvas. It starts at 100 %, or at 125 % when the
  picture is already the canvas's shape, and is not remembered.
- **Where Empty** — what the frame shows while there is nothing to follow:
  **Show Whole** (the whole picture) or **Center** (the middle of the
  picture). It is off while Follow is Center.

Follow and Where Empty are remembered for the next time. Under them, the sheet
says what **Follow** will do: how many clips it frames, the tracks it adds,
how many of the clips' actions are eased again or carry a move of the framing,
and each clip it cannot frame, with the reason. When the clips have not been
analysed, it says it will find the faces, people and shot changes first: Follow
then shows the Analyzing sheet while that runs on this Mac, and frames the
clips when it is done (Stop changes nothing). Center needs no analysis.

Each clip is framed as `reframe_clip` frames it (below), starting from the
whole picture: the clip's own positions and scales, in its base and its
actions, are replaced, and its volume and other actions stay. Where the frame
shows the whole picture, a blurred copy of the clip goes on a new
**Backgrounds** track at the back, so the canvas around it is not empty; no
track is added when no clip needs one. Where two selected clips overlap in
time, the second copy goes on a further new track behind Backgrounds.

Every move is an ordinary action on the clip's action lane: select one and drag
the picture on the canvas to nudge where its frame ends, as with any action.
**Edit ▸ Undo Follow Subject** takes the whole command back in one step.

Follow Subject does not offer `fit` or `keep` (an agent can send them), does
not frame stills or pictures, and does not change the canvas: set the vertical
canvas first in the Document tab.

## Reframing a clip (for agents)

An agent frames one clip on the current canvas — say a landscape recording on
a 1080 × 1920 vertical canvas — with `reframe_clip` (see [MCP](mcp.md)). It
chooses what to follow with `follow`:

- **`subject`** follows a face; where there is none, a person; where there is
  neither, a salient region.
- **`face`**, **`person`** and **`salient`** follow only that kind.
- **`center`** holds the frame on the middle of the picture for the whole clip.
- **`fit`** shows the whole picture for the whole clip, scaled to fit the
  canvas.
- **`keep`** rescales the clip from the canvas it was placed on
  (`from_width` × `from_height`) to the current one, as `set_canvas` does with
  `rescale_clips`: its position follows each axis's change and its scale the
  smaller of the two.

`zoom` (1 to 4, default 1) is how tight the frame is: 1 is the scale at which
the picture just covers the canvas. `center` and the four following kinds read
it; `fit` and `keep` do not.

When it follows, the frame:

- eases onto the subject and moves only when the subject leaves the middle of
  the frame, so a speaker who sways stays put;
- cuts with the picture at each shot change, landing on the first frame of the
  new shot;
- holds for a second when the subject is lost — so a blink or a turned head
  changes nothing — then follows someone else in the shot, or eases over 0.8 s
  to the whole picture (`where_empty: "fit"`, the default) or to the middle of
  the picture (`where_empty: "center"`);
- comes back once a subject has been in view for 0.6 s;
- frames two people together when both fit in the frame.

The framing is written as ordinary edits: the clip's position and scale, and
one action per move, which you can change afterwards like any other. Undo
takes the whole framing back in one step, **Reframe Clip**.

A clip that already has actions keeps them. The framing is composed into them:
a zoom or pan the clip already makes still happens, inside the new framing, and
a volume or speed action still does what it did. The framing's own moves go in
the gaps between the clip's actions; a move that would overlap one is moved up
to half a second earlier, or else made part of that action, along its curve. A
shot change that falls inside an action cuts it in three around the one-frame
cut, so a steady (linear) change of volume still sounds exactly as it did and
an eased one eases again on each side of the cut; a speed action, or one a trim
left running past the clip's end, is never cut, and takes the framing's change
across its length instead. Send `replace: true` to start from the whole picture
instead: every position and scale the clip's actions set is removed first
(volume and everything else stay, and an action left with nothing is removed),
then the clip is framed.

Where the framing shows the whole picture, the canvas around it shows too. Name
a track behind the clip as `backdrop` and a blurred copy of the clip goes there
for the clip's whole length — the copy **Clip ▸ Add Blurred Background** makes —
or on a new track at the back when that track is locked, a matte, or busy over
the clip. A clip with speed actions keeps them on its copy, so the copy shows
the same frames.

The tool analyses the part of the file the clip plays, if it has not been
analysed, and waits up to a minute. If that is not enough it changes nothing,
says how much is done, and keeps analysing: ask again to apply. `center`,
`fit` and `keep` need no analysis.

Not every clip can be framed. A clip on a matte track or cut by one and a
rotated or spinning clip are refused, and — for the following kinds — so are a
nest, a still or a picture. Each refusal says why. `keep` frames any of them,
rescaling the clip's position and scale, and every position and scale its
actions set, from the canvas it was made for.
