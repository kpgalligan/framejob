```json screen
{
  "title": "Clip inspector — an adjustment clip's Color tab",
  "project": "adjust",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:adjustment"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab", "args": {"tab": "clip", "sub_tab": "color"},
     "until_absent": "look_thumbnails_pending", "within": 60}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Strength"}]
}
```

An adjustment clip selected (grading GR4b, spec §11 GR-6): the clip Insert ▸
Adjustment Clip places, which draws nothing of its own and grades everything behind
it. The `adjust` fixture's one is at saturation −1 and Strength 75%. The person is
setting how strongly the grade applies and what it does; an adjustment clip's tabs are
Color and Clip only, never Picture.

The preview shows the speech.mov card behind it as a very dark navy rectangle on the
black canvas, with no selection frame or handles: the adjustment clip has no
rectangle of its own to frame. The timeline has two tracks, Adjustment over Video. The
Adjustment track holds one plum clip labelled "Adjustment" with a small badge before
its name, 0–5 s, selected with an orange outline. Below it is the navy "speech.mov"
clip with its waveform band. The timeline bar reads "Adjustment" over
"Adjustment · adjustment".

The inspector: the name field reads "Adjustment" beside a plum swatch, over
"adjustment · 00:00:05:00". Then the actions row ("none") and its lane ("no actions ·
⌥⌘K adds one"), and two sub-tabs, Color (selected) and Clip. The ADJUSTMENT section is
first and open, its summary "75%", with a Reset button. It has one row, Strength: a
slider three quarters along, and a "75%" field with a chevron for the quick values
0, 25, 50, 75 and 100. Below it the QUALIFIER section (grading-2 G2-4) is open,
summary "off": three ranges, each a row of its checkbox (Hue, Saturation, Luma), all
unticked, beside a dimmed strip — the hue spectrum, a white-to-red ramp, a
black-to-white ramp — over a row of three dimmed captioned fields holding the
defaults a tick would write (Centre 30°, Width 50°, Soft 25°; Low 0.00, High
1.00, Soft 0.10 twice), then an unticked Invert, then a "Pick from Canvas" button
beside an unticked "Show Selection" checkbox. Below it the LIGHT section is open,
summary "neutral", with 05b's nine rows: Exposure ("0.00 EV", clipped at the field's
edge as on 05b) through Fade, below the captured height. The COLOR section follows,
closed, then the WHEELS section (grading-2 G2-2), open, the CURVES section (G2-3),
open, and the LOOK section (GR5b), open, all below the captured height.

In the light capture the inspector is white with black labels, the section headers
light-grey bars with grey capitals, the Color sub-tab pale blue with a blue outline,
and each slider a blue fill up to a black square knob. In the dark capture the panel
is near-black with white labels and white knobs.
