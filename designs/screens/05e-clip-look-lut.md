```json screen
{
  "title": "Clip inspector — Color, the Look section with imported LUTs",
  "project": "lut",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "color", "section": "video.look"},
     "until_absent": "look_thumbnails_pending", "within": 60}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Imported"},
             {"capture": "inspector", "visible_text": "Import LUT…"}]
}
```

The `lut` fixture's video clip on the Color sub-tab, scrolled to its last
section, Look (grading GR6b, spec §11 GR-8 [b]): where the person picks a `.cube`
LUT they imported by its picture, beside the eight built-in looks, and imports
another. The clip carries the imported "Warm Print" at 80%.

The preview shows the "speech.mov" card, a little more violet than 05d's navy,
on the black canvas under an orange selection frame with its handles. The
timeline has one track, Video, holding the selected "speech.mov" clip with its
waveform band.

The inspector: the name field, the actions row and lane, the four sub-tabs with
Color selected, then the pane scrolled so the LOOK section's header is at the
top, its summary "Warm Print 80%" beside a Reset button. Its gallery is the
three rows of three built-in tiles — None, Warm, Cool; Teal & Orange, Vivid,
Faded; Vintage, Dramatic, Black & White — none outlined. Under the grid a small
"Imported" label, then one short row of two tiles at the built-in tiles' width,
"Warm Print" (outlined in blue, the clip's own look) and "Bleach" (a greyer
card), in the order they were imported. Under them the "Import LUT…" button, a square bordered block;
the Amount row is below the captured height.

In the light capture the inspector is white with black labels and each unpicked
tile a thin grey frame; in the dark one the panel is near-black with white
labels, and the pictures are the same.
