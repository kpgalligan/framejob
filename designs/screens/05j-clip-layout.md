```json screen
{
  "title": "Clip inspector — Picture, the Layout section",
  "project": "layout",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:camera"]}},
    {"call": "set_playhead", "args": {"t": 300000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "picture", "section": "video.layout"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Duration"}]
}
```

The `layout` fixture's camera clip on the Picture sub-tab, scrolled to its
Layout section (road map "creator-jobs" CO7, spec §11 CO-71): where the person
picks how a camera clip and the screen recording behind it share the frame, and
switches to that layout from the playhead. It is the section's form of Clip ▸
Camera Layout ▸, and Switch at Playhead sends exactly what the menu sends, with
this clip as the camera.

The preview shows the navy "speech.mov" card on the black canvas under an orange
selection frame with its handles (the camera, in front, covers the screen at the
playhead). The timeline has two tracks, Camera in front of Screen, each holding a
"speech.mov" clip with its waveform band; the Camera clip is selected, and the
Screen clip's action lane shows its zoom ("1" and a magnifier) from 1 s. The
timeline bar reads "speech.mov" over "Camera · video".

The inspector: the name field, the actions row and lane, the four sub-tabs with
Picture selected, then the pane scrolled so the LAYOUT section is at the top,
open, its summary "Square, Bottom Right" — the layout the section would switch
to. Its rows: Layout, a popup reading "Corner" (Corner, Side by Side, Stacked,
Camera Full, Screen Only); Shape, "Square" (Square, Rounded, Circle); Corner,
"Bottom Right" (and Bottom Left, Top Right, Top Left) — Shape and Corner grey out
for any layout but Corner; Duration, a "0.50s" field with a chevron for the
quick values 0.25, 0.5, 1 and 2; then the "Switch at Playhead" button on a row of
its own. The section has no Reset: its choices are the window's, kept while it
is open and never saved. Below it the closed CROP ("none"), CORNER RADIUS
("0 px") and CHROMA KEY ("off") headers, then BACKGROUND, open, "off", with an
unticked "Remove background" checkbox and its greyed Background popup at the
foot.

In the light capture the inspector is white with black labels and the section
headers light-grey bars with grey capitals; in the dark one the panel is
near-black with white labels and the pop-ups dark fields with white text.
