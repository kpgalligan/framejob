```json screen
{
  "title": "Clip inspector — Color, the Curves section",
  "project": "curves",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "color", "section": "video.curves"},
     "until_absent": "look_thumbnails_pending", "within": 60}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Out"}]
}
```

The `curves` fixture's video clip on the Color sub-tab, scrolled to the Curves
section (grading-2 G2-3, spec §11 GR-12): where the person shapes the picture's
tones with points on a curve — Master for contrast, or one colour at a time. The
clip carries a gentle S-curve on Master (points at 0.25 → 0.18 and 0.75 → 0.84)
and Red's shadows lifted (its first point at 0 → 0.08, a middle point at 0.5 →
0.52).

The preview shows the "speech.mov" card on the black canvas, its contrast raised
and a faint red cast in its darks, under an orange selection frame with its
handles. The timeline has one track, Video, holding the selected "speech.mov"
clip with its waveform band; the timeline bar reads "speech.mov" over
"Video · video".

The inspector: the name field, the actions row and lane, the four sub-tabs with
Color selected, then the pane scrolled so the CURVES section is at the top, open,
its summary "adjusted" beside a Reset button. Its one row starts with four square
cells — Master, Red, Green, Blue — with Master chosen (framed and labelled in the
strong text colour); a small dot sits under Master and under Red, the two
channels that are not straight. Below them the plot, a square the width of the
row (about 254 pt at the default pane): a 4 × 4 grid, the straight diagonal, a
faint red curve lifted at the bottom-left, and the Master S-curve in the strong
text colour through four small hollow square points, the two ends at the corners.
Under the plot the point row: "In" and "Out" beside two blank, dimmed fields (no
point is selected) and a dimmed Delete button. Below the row, the LOOK section is
open, summary "none", its gallery of looks.

In the light capture the inspector is white with black labels, the plot's well
white with light-grey grid lines and the S-curve black; in the dark one the panel
is near-black with white labels, the well dark grey and the S-curve white. The red
curve and the Red cell's dot are the parade's red in both.
