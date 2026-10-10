```json screen
{
  "title": "Clip inspector — Color, the Look section",
  "project": "look",
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
  "expect": [{"capture": "inspector", "visible_text": "Amount"}]
}
```

The `look` fixture's video clip on the Color sub-tab, scrolled to its last
section, Look (grading GR5b, spec §11 GR-7): where the person picks one of the
eight built-in looks by its picture rather than by its name. The clip carries
Teal & Orange at 80%.

The preview shows the navy "speech.mov" card on the black canvas under an orange
selection frame with its handles. The timeline has one track, Video, holding the
selected "speech.mov" clip with its waveform band; the timeline bar reads
"speech.mov" over "Video · video".

The inspector: the name field, the actions row and lane, the four sub-tabs with
Color selected, then the pane scrolled down so the end of Light (the Vibrance
and Fade rows) shows above the closed COLOR section, summary "neutral". The LOOK
section below it is open, its summary "Teal & Orange 80%" beside a Reset
button. Its gallery is three rows of three tiles, each a small picture of the
frame at the playhead with its name beneath: None, Warm, Cool; Teal & Orange,
Vivid, Faded; Vintage, Dramatic, Black & White. Every picture is the navy card
on black, each tinted by its own look — the Faded and Vintage cards greyer, the
Dramatic and Black & White ones darker — and Teal & Orange's tile wears a blue
outline, the clip's own look. Under the grid the Amount row: a slider four
fifths along and an "80%" field with a chevron for the quick values.

In the light capture the inspector is white with black labels, the section
headers light-grey bars with grey capitals, and each unpicked tile a thin grey
frame; in the dark one the panel is near-black with white labels and white
knobs, and the pictures are the same.
