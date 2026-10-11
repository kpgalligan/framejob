```json screen
{
  "title": "Clip inspector — an adjustment clip's Qualifier, with Show Selection",
  "project": "qualifier",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:adjustment"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Show Selection"]}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "color", "section": "video.qualifier"},
     "until_absent": "look_thumbnails_pending", "within": 60}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"},
    {"name": "preview", "window": "editor", "view": "preview"}
  ],
  "after": [
    {"call": "perform_menu_item", "args": {"path": ["View", "Show Selection"]}}
  ],
  "expect": [
    {"capture": "inspector", "visible_text": "Centre"},
    {"capture": "preview", "visible_text": "Selection"}
  ]
}
```

The `qualifier` fixture's adjustment clip selected, the Color sub-tab scrolled
to the Qualifier section, and View ▸ Show Selection on (grading-2 G2-4, spec
§11 GR-13): where the person narrows an adjustment clip's grade to the pixels
of one colour — a hue band, a saturation band, a brightness band — and checks
what it picks. The clip greys at full strength, but only pixels within 25° ± 15°
of hue (with 15° of fall-off) and saturation 0.15–1 (fall-off 0.05): warm,
saturated colour, as skin is.

The preview pane's top-left void reads "Selection" in a small tag: the switch
is on, bound to this clip. The well itself is `snapshot_ui`'s fill — the frame
`render_frame` draws, which the switch never reaches — so it shows the graded
picture as an export would: the "speech.mov" card, navy, on the black canvas,
untouched because nothing navy is selected, with no selection frame (the
adjustment clip has no rectangle). The timeline has two tracks, Adjustment over
Video: the selected plum "Adjustment" clip, 0–5 s, and the navy "speech.mov"
clip with its waveform band.

The inspector: the name field ("Adjustment", a plum swatch), the actions row and
lane, the Color and Clip sub-tabs with Color selected, then the pane scrolled so
the QUALIFIER section is at the top, open, its summary "hue · sat" beside a
Reset button. The Hue row: a ticked "Hue" checkbox in the label column and its
strip, the hue spectrum from red through green and blue back to red, dimmed
except the band near the left end — two block knobs either side of orange at
10° and 40°, a small square at 55° where the fall-off ends, and a second small
square at the strip's right end, the fall-off's other edge wrapped round to
355°. Under it "Centre 25°", "Width 30°" and "Soft 15°". The Saturation row: a
ticked checkbox and a white-to-red ramp, dimmed left of a knob at 0.15, with
its fall-off square just left of it and the high knob at the red end; under it
"Low 0.15", "High 1.00", "Soft 0.05". The Luma row is unticked: its black-to-white
strip dimmed, its fields grey (0.00, 1.00, 0.10). Then an unticked Invert, then
the "Pick from Canvas" button beside a ticked "Show Selection". The LIGHT
section follows, open, summary "neutral", its first two rows Exposure and
Temperature at the bottom of the capture.

In the light capture the inspector is white with black labels and the knobs
black; in the dark one the panel is near-black with white labels and white
knobs. The strips' colours are the same in both looks.
