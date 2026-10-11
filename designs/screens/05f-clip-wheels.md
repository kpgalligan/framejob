```json screen
{
  "title": "Clip inspector — Color, the Wheels section",
  "project": "wheels",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "color", "section": "video.wheels"},
     "until_absent": "look_thumbnails_pending", "within": 60}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Gamma"}]
}
```

The `wheels` fixture's video clip on the Color sub-tab, scrolled to the Wheels
section (grading-2 G2-2, spec §11 GR-11): where the person balances the picture's
shadows, middle and highlights by colour and brightness. The clip carries lift
pushed toward red-orange (x 0.3, y 0.2) at master 0.10, and gain at master 0.20.

The preview shows the navy "speech.mov" card on the black canvas under an orange
selection frame with its handles. The timeline has one track, Video, holding the
selected "speech.mov" clip with its waveform band; the timeline bar reads
"speech.mov" over "Video · video".

The inspector: the name field, the actions row and lane, the four sub-tabs with
Color selected, then the pane scrolled so the WHEELS section is at the top, open,
its summary "adjusted" beside a Reset button. Its one row is three columns,
titled Lift, Gamma and Gain. Each holds a hue disc in a thin square frame, about
78 pt across at the default pane: a ring of fully saturated colour at the rim,
paler towards a neutral centre, with a 1 pt crosshair through the middle. The
disc is turned so each hue sits where the vectorscope draws it (red up and a
little left of twelve o'clock, yellow to the left, cyan down, blue to the right).
Lift's small black square puck sits up and to the left of the centre, toward
orange; Gamma's and Gain's sit on the crosshair. Under each disc a master strip,
a thin rail with a blue fill up to a black block knob — Lift's a little right of
the middle, Gamma's in the middle, Gain's a little further right — and a field
under it: "0.10", "0.00", "0.20". Below the row, the LOOK section is open, summary
"none", its gallery of looks.

In the light capture the inspector is white with black labels, the section
headers light-grey bars with grey capitals, and each disc's centre near white; in
the dark one the panel is near-black with white labels, white pucks and knobs,
and each disc's centre a dark grey.
