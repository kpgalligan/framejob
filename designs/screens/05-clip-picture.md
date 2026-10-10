```json screen
{
  "title": "Clip inspector — Picture",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ]
}
```

A video clip is selected, so the inspector's Clip tab shows that clip. Picture
is the sub-tab it opens on: where the person places, sizes and styles the clip's
image in the frame.

In the preview the selected clip carries an orange frame with square handles on
its corners and edges and a round rotation handle above it. The timeline bar reads
"speech.mov" over "Video · video" beside a slate-coloured swatch.

The inspector, top to bottom: the clip's name, "speech.mov", in an editable field,
with "video · 00:00:05:07 · 640×360 · 30 fps" under it; an "ACTIONS none" row
with zoom-in, zoom-out and add (+) buttons, then a lane showing a "Clip" button,
"no actions" and the hint "⌥⌘K adds one"; then four sub-tabs, Picture
(selected), Color, Sound and Clip. Below them the TRANSFORM section is open, its summary
"100%" on the right: Scale (a slider and "100.0%"), Position X and Position Y
("0 px" each), Rotation (a slider and "0.0°"), Opacity (a slider and "100%"),
Blend ("Normal"), and two buttons, "Fit to Canvas" and "Fill Canvas". Closed
sections follow, each a header with a summary on the right: CROP "none", CORNER
RADIUS "0 px", CHROMA KEY "off" and SHADOW "off", the last header in view. (The
clip's colour controls are the Color sub-tab's, `05b-clip-color`.)

In the light capture the inspector is white with black labels; the section
headers are light-grey bars with grey capitals, the Picture sub-tab and the lane's
Clip button are pale blue with a blue outline, the lane is mid-grey, and the Scale,
Rotation and Opacity sliders have a blue fill and a black square knob.
