```json screen
{
  "title": "Follow Subject",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Follow Subject…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Follow Subject"}]
}
```

The Follow Subject sheet (road map "creator-jobs" VR2b2, spec §11 VR-29) comes up from
Clip ▸ Follow Subject… when a selected clip plays a movie — here the `demo` fixture's video
clip. Follow frames each selected clip on its subject with eased moves on its action lane, and
a blurred copy on a Backgrounds track where the frame shows the whole picture, as one undo
step "Follow Subject".

Under the bold title "Follow Subject", a muted hint: "Frames each selected clip on its subject
with eased moves on its action lane, and a blurred copy behind it where it shows the whole
picture. Replaces the clips' own position and scale. One undo step." Then a grid of three rows,
each with its right-aligned label:

- "Follow:" — a pop-up of Subject, Faces, People, Salient Region and Center; Subject here
  (pinned by `FrameJobFollowKind`).
- "Zoom:" — a whole-number field and "%"; 125 here, because the fixture's picture (a 16:9
  movie on a 16:9 canvas) is already the canvas's shape; a picture of another shape opens at
  100, the fill.
- "Where Empty:" — a pop-up of Show Whole and Center; Show Whole here (pinned by
  `FrameJobFollowWhereEmpty`). It is dimmed while Follow is Center.

Under the grid, one muted summary says what Follow would do. Every screen's instance holds each
analysis job before its first frame, and the fixture's clip has never been analysed, so here it
reads "Finds the faces, people and shot changes in 1 file on this Mac first, then frames 1
clip." With the analysis cached it reads "Reading the analysis…" for a moment and then, for
example, "Frames 1 clip. Adds a Backgrounds track for the blurred copy.", with one line per
clip that cannot be framed and why. At the foot, right-aligned, "Cancel" (Escape) and the
primary "Follow" (Return), enabled when there is something to frame or an analysis to make
first.
