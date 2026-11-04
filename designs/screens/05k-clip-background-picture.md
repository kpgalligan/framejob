```json screen
{
  "title": "Clip inspector — Picture, the Background section on a picture",
  "project": "cutout_picture",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:picture"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "picture", "section": "video.cutout"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [
    {"capture": "inspector", "visible_text": "Subject"},
    {"capture": "inspector", "visible_text": "Analyzing 0 %"}
  ]
}
```

The `cutout_picture` fixture's image clip on the Picture sub-tab, scrolled to its
Background section (road map "creator-jobs" CO10b, spec §11 CO-108): where the
person turns Remove Background on for a photo, picks whether it keeps the person
or the photo's foreground subject, and watches its one mask being made on the
Mac. The launch holds every analysis job, so the picture's foreground mask job
waits before it starts and Status reads "Analyzing 0 %".

The preview shows the 320 × 180 picture at its own size in the middle of the
black 960 × 540 canvas — blue at the left turning red at the right, cyan and
yellow along the bottom — under an orange selection frame with its handles, drawn
whole: a picture without its mask is drawn
uncut (CO-6). The timeline has one track, Picture, holding the selected
"picture.png" clip; the timeline bar reads "picture.png" over "Picture · image".

The inspector: the name field, the actions row and lane, the three sub-tabs
(Picture, Color, Clip) with Picture selected, then the pane scrolled so the BACKGROUND section is at the top,
open, its summary "Analyzing 0 %" beside a Reset button. Its rows: a ticked
"Remove background" checkbox; Subject, a popup reading "Foreground" (the row
only a selection of pictures shows; the layout dump carries the row's label, not
the popup's title); Background, a popup reading "Remove"; Edge,
a slider with its block knob at the middle of the rail (−1…1) and a "0.00" field
with a chevron for the quick values; Feather, a slider at its start and a "0%"
field with a chevron; Status, the read-out "Analyzing 0 %"; then the "Analyze
Now" button on a row of its own. Below it the closed headers of the sections
that follow.

In the light capture the inspector is white with black labels and the section
headers light-grey bars with grey capitals; in the dark one the panel is
near-black with white labels and white knobs.
