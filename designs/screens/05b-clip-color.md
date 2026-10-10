```json screen
{
  "title": "Clip inspector — Color",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab", "args": {"tab": "clip", "sub_tab": "color"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Exposure"}]
}
```

The same video clip as `05-clip-picture`, on the Color sub-tab (grading GR2,
spec §11 GR-2): where the person corrects the clip's light and colour. The tab
is offered only for clips with pixels of their own — a movie, an image or a
still — and never for text, a shape, a graphic, a nest or an audio-only file.

The preview and the timeline are as on Picture: the navy "speech.mov" card under
an orange selection frame with its handles, the timeline bar reading
"speech.mov" over "Video · video".

The inspector: the name field, the actions row and lane, then four sub-tabs with
Color selected. The LIGHT section is open, its summary "neutral": nine rows, each
a label, a slider and a value field — Exposure ("0.00 EV", its knob in the middle
of the rail), then Temperature, Tint, Highlights, Shadows, Whites, Blacks and
Vibrance (each "0.00", knob in the middle), and Fade ("0.00", its knob at the
left end, since fade runs 0 to 1). Below it the COLOR section is closed, summary
"neutral" — the four Brightness, Contrast, Saturation and Hue rows that used to
sit on Picture.

In the light capture the inspector is white with black labels, the section
headers light-grey bars with grey capitals, the Color sub-tab pale blue with a
blue outline, and each slider a blue fill up to a black square knob; in the dark
one the panel is near-black with white labels and white knobs.
