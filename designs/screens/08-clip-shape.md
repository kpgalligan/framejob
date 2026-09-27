```json screen
{
  "title": "Clip inspector — Shape",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:shape"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ]
}
```

A shape clip — the white ellipse outline around the title — is selected. The
Shape sub-tab is where the person picks the kind of shape and how it is drawn.

In the preview the ellipse has an orange frame with handles and a rotation
handle; in the timeline the Ellipse clip is outlined and the bar reads "Ellipse" over
"Shapes · shape".

The inspector: the name field "Ellipse" over "shape · 00:00:05:00 · 320×120";
the actions row and lane; sub-tabs Shape (selected), Picture and Clip. The SHAPE
section is open, summary "ellipse": Kind ("Ellipse" in a pop-up), Width "320 px",
Height "120 px", and a Corner radius slider with "0 px", both dimmed. Closed below:
STROKE "6.0 px", FILL "off", GRADIENT "off" and ARROWHEADS "none".

In the light capture the inspector is white with black labels; the Kind pop-up
and the Width and Height fields are white boxes with grey borders, the dimmed
Corner radius slider and its value are pale grey, and the section headers are
light-grey bars.
