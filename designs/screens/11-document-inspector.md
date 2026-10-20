```json screen
{
  "title": "Document inspector",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "select_inspector_tab", "args": {"tab": "document"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "after": [{"call": "select_inspector_tab", "args": {"tab": "clip"}}]
}
```

The inspector's Document tab: the settings of the project as a whole, which the
person changes when the whole video should be a different size, rate or
background.

The Document tab is selected at the top of the inspector, and nothing is selected
in the timeline ("No selection"). Four open sections: DOCUMENT, a read-out —
Resolution "960 × 540", Frame rate "30 fps", Duration "00:00:05:07", Tracks "5",
Background "Black", Colour "SDR — Rec. 709" (the project's dynamic range, spec §11
HD-13; "HDR — Rec. 2100 HLG" in an HLG project); CANVAS — a Preset pop-up set to
"Custom", Width "960 px", Height "540 px", an unchecked "Resize clips
proportionally", a Dynamic Range pop-up set to "SDR" (its other item "HDR
(HLG)") and a Blending pop-up set to "Encoded" (its other item "Linear light",
spec §11 HD-16 (g)); FRAME RATE — Rate
"30" in a pop-up and Duration "00:00:05:07"; and APPEARANCE, whose header is the last
row in view with the top of its black Background colour well below it.

In the light capture the inspector is white with black labels and values; the
Document tab is a light-grey cell with a blue underline beside the white Clip,
Media and Assistant cells, the pop-ups and the Width and Height fields are white with grey
borders, "Resize clips proportionally" is pale grey, and the section headers are
light-grey bars.
