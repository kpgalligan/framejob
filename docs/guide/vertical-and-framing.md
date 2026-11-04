# Vertical and framing

Frame Job can find who and what is in a clip's picture: faces, people and the
regions the eye is drawn to. It finds them on this Mac with Apple's Vision
framework — nothing is uploaded and no key is needed — and keeps what it found
in the project's cache, so it is found once per file. This page covers what is
found, how to see it, how **Clip ▸ Follow Subject…** frames the selected clips
on it, how **File ▸ Make Vertical Version…** makes a tall or square version of
the whole timeline, and how an agent reframes a clip with it.

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
asks for it — **Clip ▸ Follow Subject…** and **File ▸ Make Vertical
Version…** (below), an agent
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

A screen recording Frame Job made, with its cursor file, is not followed by
faces — a face on a screen is not what the viewer is looking at. Follow Subject
leaves it unanalysed and lists it under the summary with the reason: "Clip 3:
clip 3's media has a cursor file, so it follows the cursor, not faces; frame it
with cursor, center, fit or keep." **File ▸ Make Vertical Version…** (below)
follows its cursor instead.

Follow Subject does not offer `fit` or `keep` (an agent can send them), does
not frame stills or pictures, and does not change the canvas: set the vertical
canvas first in the Document tab, or let **File ▸ Make Vertical Version…**
(below) change the canvas and frame the whole timeline in one go.

## Make Vertical Version

Choose **File ▸ Make Vertical Version…** to make a tall or square version of a
landscape edit — for a phone, a reel or a square post. It works on the whole
timeline: it is offered when the project has a clip and no nest is open, and
not while a recording runs. The sheet has five controls:

- **Shape** — **9:16**, **4:5** or **1:1**, each with the size it makes. The
  new canvas keeps the old short side: from 1920 × 1080 they are 1080 × 1920,
  1080 × 1350 and 1080 × 1080. A shape the canvas already has is not offered.
- **Follow**, **Zoom** and **Where Empty** — as in Follow Subject (above),
  and Follow has one more choice here, **Speaker** (below). Follow and Where
  Empty are the same remembered choice as Follow Subject's (Speaker, which
  Follow Subject does not offer, opens Follow Subject on Subject); Zoom always
  starts at 100 %, the scale at which a picture just covers the new canvas.
- **Make a copy** — ticked whenever the sheet opens. With it, the vertical
  version opens as a new untitled project, named after this one with the shape
  — "Interview (9:16)" — and this project does not change; save the copy when
  you want to keep it. Unticked, this project itself becomes the vertical
  version.

Under them the sheet says what **Make** will do: the new size, how many clips
are followed, how many camera layouts it re-lays, how many are shown whole,
kept as placed or re-filled, the blurred copies it
removes, the graphics it re-sizes and the graphic modules it updates, the
tracks it adds and the actions that carry a move, then each clip that is not
followed and why, and each graphic module left as it is and why.

Each clip with a picture on the top-level timeline is treated by what it is:

- **A movie clip that fills the old frame** on one side — the usual full-frame
  shot, or one punched in a little — follows its subject, as Follow Subject
  frames it, with its own moves and actions kept inside the framing. Where the
  frame shows the whole picture, a blurred copy of it goes behind on a new
  **Backgrounds** track at the back. A movie whose file is missing is kept as
  placed.
- **With Follow Speaker, a wide shot of two to four people** that plays
  beside their microphones — a sound file each, on its own track, recorded
  with the shot (use **Clip ▸ Synchronize Audio** first) — cuts to whoever
  is talking, as Switch by Speaker reads the microphones, so the two agree.
  Each change of speaker is a cut, held at least 2 s, so a short reply does
  not cut away and back; two people talking at once are framed together when
  they fit, and while nobody talks the last speaker stays. Every other movie
  clip follows its faces. A shot whose faces cannot be framed by who is
  talking (it changes shot, say) follows its faces instead, and the summary
  says why.
- **A screen recording with its cursor file** follows the pointer instead of
  a face: the frame sits on the pointer and moves only when it strays from
  the middle of the frame, arrives on each click — the move ends on the
  click's frame, so the click lands in view — and holds still while you type.
  Any zoom and pan of its own (say **Clip ▸ Auto Zoom…**'s) is replaced, since
  the tall frame is already a close-up. When the cursor file cannot be read
  (it was moved or deleted), the recording is shown whole on a blurred copy,
  and the summary says so. Center centres it as any other movie.
- **A screen recording and its camera in camera layouts** (**Clip ▸ Camera
  Layout ▸**, or the layout a recording landed in) keep their arrangement:
  each switch is made again for the new canvas, at the same time, length and
  curve — a Corner stays a Corner in the same corner, Camera Full stays
  Camera Full, and **Side by Side becomes Stacked** on a tall canvas (the
  screen across the top, the camera below it), so the screen is not squeezed
  into two-thirds of a narrow frame. Side by Side stays side by side on a
  square. The camera, the screen and the cut pieces of either are never
  followed and get no blurred copy, and a zoom on the screen keeps showing the
  same part of the picture. The summary lists each switch: "Re-laid: Side by
  Side → Stacked at 00:00:10:00." When a layout was changed by hand — its
  camera moved or resized after the switch, so it is no longer one Frame Job
  made — the camera and its screen are kept as placed instead, and the summary
  says "Clip 6 is not followed: its camera layout was edited by hand, so it is
  kept as placed." A circle or panel crop is re-centred on the middle of the
  crop it had, so a crop that had room to move may sit nearer the middle of
  the camera picture than a switch made directly on the new canvas would.
- **A still or a picture that fills the frame, and a nest that does**, is
  centred.
- **A graphic exactly the old canvas's size** (a full-frame lower third or
  title card) is re-sized to the new canvas, so it lays itself out again on
  the narrow frame; its position and its actions' positions shrink and stretch
  with the two sides, and its scale stays as it was (see
  [Motion graphics](graphics.md#in-a-vertical-version)).
- **Everything else is kept as placed** — titles, other graphics, shapes, a
  picture-in-picture — moved and scaled from the old canvas to the new one as
  the Document tab's canvas change does when it rescales clips.
- **A blurred copy** already behind a clip is removed when that clip now
  follows its subject (the framing makes a new one where it is needed), and
  otherwise re-filled to cover the new canvas; a **background** plate
  (**Clip ▸ Add Background**) is re-filled too.
- **Word captions are re-paged** for the narrow frame from the words their
  pages hold, every correction kept, as **File ▸ Re-lay Captions for This
  Canvas** does (see [Captions](captions.md#re-lay-captions-for-a-new-canvas)).
  A caption track it cannot re-lay — Subtitles, a page with no word timings,
  a style Frame Job does not make, or pages that would not fit — is kept as
  placed, and the summary names it and why: "Caption track "Captions 2" is
  kept as placed: it holds a page with no word timings."
- **Older copies of the bundled Lower third, Title card, Callout, Bar chart,
  Counter and Kinetic type** in the project, from before those templates
  measured themselves by the short side, are rewritten with the current
  template in the copy, the old text kept as the module's previous version.
  Applied in place they are left as they are, and the summary names each:
  "Graphic module "intro" is left as it is: it is an older copy of the bundled
  template "lower-third"; Make Vertical updates it only in a copy." A module
  of your own that sizes itself by the canvas's height is named too, and
  never rewritten.

### Follow Speaker: who is on each microphone

With **Speaker** chosen the sheet shows two more rows:

- **Microphones** — a checkbox for each track holding a sound file (a track
  of a recorder's or a lavalier's file, not a camera), named by the track,
  the first four ticked. Tick the ones that belong to the people in the shot:
  two to four.
- **Faces** — one row per ticked microphone, with a pop-up of the faces Frame
  Job found in the longest such shot, numbered left to right with where each
  is across the picture: "Face 1 (42 % across)". Frame Job matches each
  microphone to the face whose mouth moves while it talks. When the match is
  clear the pop-ups are already set, and the note under them says "Each
  microphone is matched to the face that talks with it; change one if it is
  wrong."; check each row names that microphone's person. When the faces do
  not show who is whose — mouths too still or too small to read — each
  pop-up says **Choose a face** and the note asks you to choose: pick each
  microphone's face yourself.

**Make** is offered once two to four microphones are ticked, a shot plays
beside two of them and every ticked microphone has a face of its own. When a
microphone is still being measured (just imported), the sheet says so in
Switch by Speaker's words; choose the command again in a moment.

When the movies have not been analysed, the sheet says it will find the faces,
people and shot changes first: **Make** then shows the Analyzing sheet while
that runs on this Mac, and makes the version when it is done. With **Speaker**
the sheet comes back once the analysis is done, with your choices kept, so you
can confirm who is on each microphone; nothing is made until you press
**Make** there. **Stop** makes
nothing: no project opens and this one does not change. What was found is kept
in this project's cache (and carried into the copy), so making another shape
afterwards needs no analysis. **Center** needs no analysis.

The whole change is one undo step, **Make Vertical**: in the copy, **Edit ▸
Undo Make Vertical** gives back the landscape edit; in place, it takes the
command back on this project.

A vertical canvas shows the middle of a landscape picture enlarged: a 1080p
source framed on 1080 × 1920 is enlarged ×1.78, which can look soft on a
phone. Shoot 4K for footage you mean to make vertical.

## Reframing a clip (for agents)

An agent frames one clip on the current canvas — say a landscape recording on
a 1080 × 1920 vertical canvas — with `reframe_clip` (see [MCP](mcp.md)). It
chooses what to follow with `follow`:

- **`subject`** follows a face; where there is none, a person; where there is
  neither, a salient region.
- **`face`**, **`person`** and **`salient`** follow only that kind.
- **`cursor`** follows a screen recording's recorded pointer, from its media's
  cursor file: the frame sits on the pointer, moves only when it strays more
  than 20 % of the frame's width (12 % of its height) from the middle,
  arrives on each click outside that in a move that ends on the
  click's frame, and holds still while you type. It needs no analysis and
  never waits; `where_empty` and `backdrop` do nothing with it, since the
  frame never shows the whole picture.
- **`speaker`** frames a wide shot of two to four people on whoever is
  talking, each with a microphone of their own: name the microphone clips in
  `mics` (a sound file each, or a camera's detached sound, each on its own
  track). Who talks when is read from those microphones exactly as **Clip ▸
  Switch by Speaker…** reads it, so the two agree; each microphone is matched
  to the face whose mouth moves while it talks (faces are numbered 1, 2, …
  from left to right). Each change of speaker is a cut, held at least 2 s;
  two people talking at once are framed together when they fit, and while
  nobody talks the last speaker stays. When the faces do not show who is
  whose — mouths too still or too small to read — the call is refused,
  naming where each face is across the picture; name each microphone's face
  with `mic_faces`, in `mics`' order, and call it again. A clip that changes
  shot is refused: split it at its shot changes first. **File ▸ Make Vertical
  Version…**'s Follow **Speaker** (above) is its menu: it frames each such
  shot with this, its microphones and their faces confirmed on the sheet.
- **`center`** holds the frame on the middle of the picture for the whole clip.
- **`fit`** shows the whole picture for the whole clip, scaled to fit the
  canvas.
- **`layout`** re-lays a camera clip's camera layouts, and its screen's, on
  the current canvas: each switch made on `from_width` × `from_height` is
  recognised and switched again here, as Make Vertical Version does (above).
  A switch edited by hand is refused, naming the clip and the action.
- **`keep`** rescales the clip from the canvas it was placed on
  (`from_width` × `from_height`) to the current one, as `set_canvas` does with
  `rescale_clips`: its position follows each axis's change and its scale the
  smaller of the two.

`zoom` (1 to 4, default 1) is how tight the frame is: 1 is the scale at which
the picture just covers the canvas. `center` and the four following kinds read
it, and so do `cursor` and `speaker`; `fit` and `keep` do not.

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
`fit` and `keep` need no analysis. `speaker` also needs its microphones'
loudness and speech, which Frame Job measures when a file is added; while
they are still being measured it is refused in Switch by Speaker's words —
try again in a moment.

Not every clip can be framed. A clip on a matte track or cut by one and a
rotated or spinning clip are refused, and — for the following kinds,
`cursor` and `speaker` — so are a nest, a still or a picture. A recording whose media has a
cursor file is refused by the following kinds (it follows its cursor, never
faces), and `cursor` is refused on a clip whose media has none. Each refusal
says why. `keep` frames any of them,
rescaling the clip's position and scale, and every position and scale its
actions set, from the canvas it was made for.
