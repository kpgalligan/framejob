```json screen
{
  "title": "Clip inspector — Graphic",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:graphic"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ]
}
```

A graphic clip is selected: the lower third in the bottom left of the picture.
Its Graphic sub-tab is where the person fills in what the graphic shows.

The graphic covers the whole canvas, so its orange selection frame runs around
the entire preview picture, with handles at the corners and edge midpoints; the
lower third itself ("Jane Doe", "Director of Photography") sits bottom left. In
the timeline the Graphic clip is outlined and the bar reads "Graphic" over
"Graphics · graphic".

The inspector: the name field "Graphic" over "graphic · 00:00:05:00 · 960×540";
the actions row and lane; sub-tabs Graphic (selected), Picture and Clip. SOURCE
is closed with the summary "Lower third". PROPERTIES is open, "6 properties": a
"Title" field reading "Jane Doe", a "subtitle" field reading "Director of
Photography", an "accent" colour well in orange-red, "size" with a slider and
"64", a checked "boxed" checkbox, and "align" set to "left". SIZE ("960 × 540")
and TIMELINE ("00:00:05:00") are closed below.

In the light capture the inspector is white with black labels and white fields
with grey borders; the section headers are light-grey bars, the size slider has a
blue fill and a black knob, and "boxed" is a blue tick.
