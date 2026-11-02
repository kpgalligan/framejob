```json screen
{
  "title": "Clip inspector — Picture, the Background section",
  "project": "cutout",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "picture", "section": "video.cutout"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Analyzing 0 %"}]
}
```

The `cutout` fixture's video clip on the Picture sub-tab, scrolled to its
Background section (road map "creator-jobs" CO3, spec §11 CO-30): where the
person turns Remove Background on, tunes its edge and watches its person masks
being made on the Mac. The launch holds every analysis job, so the clip's masks
job waits before its first frame and Status reads "Analyzing 0 %".

The preview shows the navy "speech.mov" card on the black canvas under an orange
selection frame with its handles, drawn whole: a frame without its mask is drawn
uncut (CO-6). The timeline has one track, Video, holding the selected
"speech.mov" clip with its waveform band; the timeline bar reads "speech.mov"
over "Video · video".

The inspector: the name field, the actions row and lane, the four sub-tabs with
Picture selected, then the pane scrolled so the BACKGROUND section is at the top,
open, its summary "Analyzing 0 %" beside a Reset button. Its rows: a ticked
"Remove background" checkbox; Background, a popup reading "Remove"; Edge, a
slider with its block knob at the middle of the rail (−1…1) and a "0.00" field
with a chevron for the quick values; Feather, a slider at its start and a "0%"
field with a chevron; Status, the read-out "Analyzing 0 %"; then the "Analyze
Now" button on a row of its own. Below it the closed SHADOW, FILTERS,
REFLECTION, SPOTLIGHT and OBSCURE headers, summaries "off", "none", "off", "off"
and "none".

In the light capture the inspector is white with black labels and the section
headers light-grey bars with grey capitals; in the dark one the panel is
near-black with white labels and white knobs.
