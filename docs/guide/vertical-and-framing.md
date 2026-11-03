# Vertical and framing

Frame Job can find who and what is in a clip's picture: faces, people and the
regions the eye is drawn to. It finds them on this Mac with Apple's Vision
framework — nothing is uploaded and no key is needed — and keeps what it found
in the project's cache, so it is found once per file. This page covers what is
found and how to see it. Reframing a clip for a vertical or square canvas
builds on it and arrives in later releases.

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
asks for it — today an agent (`get_media_analysis` with `kind: "faces"` or
`"subjects"`, see [MCP](mcp.md)); the framing commands that follow will ask
for the parts of a file their clips play. Analysis runs in the background and
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
says **Not analyzed** at the clip's top-left corner. Show Subjects never starts
an analysis itself, so turning it on costs nothing.

Show Subjects is a view of the window: it is off in a new window, it is not
remembered between launches, and it never changes an export or a saved frame.
Choose it again to turn it off. It has no shortcut and is always available.
