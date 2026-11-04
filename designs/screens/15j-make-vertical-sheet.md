```json screen
{
  "title": "Make Vertical Version",
  "project": "demo",
  "steps": [
    {"call": "perform_menu_item", "args": {"path": ["File", "Make Vertical Version…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Make Vertical Version"}]
}
```

The Make Vertical Version sheet (road map "creator-jobs" VR3b, spec §11 VR-39) comes up from
File ▸ Make Vertical Version… on any project with a clip, with no nest open — here the `demo`
fixture. Make makes the timeline's tall or square version: a new canvas, each full-frame movie
clip following its subject, stills and nests centred, everything else kept as placed, and a
blurred copy behind a clip where it shows the whole picture. With Make a copy ticked it opens as
a new untitled project, "<name> (9:16)", and the project behind the sheet does not change;
unticked, it is one undo step "Make Vertical" on this project.

Under the bold title "Make Vertical Version", a muted hint: "Makes a version of the timeline for
a tall or square canvas. Each full-frame movie clip follows its subject with eased moves (with
Speaker, whoever is talking on the ticked microphones), stills and nests are centred, and everything else is kept as placed, with a blurred copy behind a clip
where it shows the whole picture. With Make a copy it opens as a new project and this one does
not change. One undo step." Then a grid, each row with its right-aligned label:

- "Shape:" — a pop-up of the shapes whose size differs from the canvas, each with its size;
  from the fixture's 960 × 540 canvas, "9:16 (540 × 960)" (shown), "4:5 (540 × 676)" and
  "1:1 (540 × 540)"; from 1920 × 1080, 1080 × 1920, 1080 × 1350 and 1080 × 1080. A 1080 × 1920
  canvas would offer only 4:5 and 1:1.
- "Follow:" — a pop-up of Subject, Faces, People, Salient Region, Speaker and Center; Subject
  here (pinned by `FrameJobFollowKind`, the key Follow Subject's sheet shares; a stored Speaker
  opens this sheet on Speaker and Follow Subject's on Subject).
- "Zoom:" — a whole-number field and "%", always opening at 100, the fill.
- "Where Empty:" — a pop-up of Show Whole and Center; Show Whole here (pinned by
  `FrameJobFollowWhereEmpty`). It is dimmed while Follow is Center.
- a "Make a copy" checkbox, ticked whenever the sheet opens.

With Follow on Speaker (not shown: the catalog pins Subject; `vr6b_proof.py`'s Q6 reads its
layout dump), a second grid follows under the first, its labels in the same column:
"Microphones:" — one checkbox per track holding a sound file, named by the track ("Mic A",
"Mic B"), the first four ticked; "Faces:" — one row per ticked microphone, the track's name and
a pop-up of "Choose a face" and each face found, "Face 1 (42 % across)"; then a muted note, "Each
microphone is matched to the face that talks with it; change one if it is wrong." when the
pop-ups are preset from a sure match, else "The faces do not show clearly who is on each
microphone: choose each microphone's face." with every pop-up on "Choose a face". Make stays off
until two to four microphones are ticked and each has a face of its own.

Under the grid, one muted summary says what Make would do. The fixture's movie does not fill
the frame on either side, so no clip is a full-frame picture and nothing is to be analysed: here
it reads "Makes a 540 × 960 version. Keeps 4 clips as placed." (the movie, the title, the
graphic and the shape). With a full-frame movie whose analysis is still to be made it reads
"Finds the faces, people and shot changes in 1 file on this Mac first, then makes a 540 × 960
version."; with the analysis cached, "Reading the analysis…" for a moment and then, for example,
"Makes a 540 × 960 version. Follows 1 clip. Adds a Backgrounds track for the blurred copy.",
with one line per clip that is not followed and why. At the foot,
right-aligned, "Cancel" (Escape) and the primary "Make" (Return), enabled when there is a
version to make or an analysis to make first.
