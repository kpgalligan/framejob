```json screen
{
  "title": "The editor — Waveform and Show Ungraded",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Waveform"]}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Show Ungraded"]}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "preview", "window": "editor", "view": "preview"}
  ],
  "after": [
    {"call": "perform_menu_item", "args": {"path": ["View", "Show Ungraded"]}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Waveform"]}}
  ],
  "expect": [
    {"capture": "preview", "visible_text": "Waveform"},
    {"capture": "preview", "visible_text": "Ungraded"}
  ]
}
```

The editor of `04-editor` with the two ways of seeing the grade turned on (grading
GR3, spec §11 GR-4 and GR-5): View ▸ Waveform and View ▸ Show Ungraded. Neither is
remembered: a window opens with both off.

The preview pane has given its right-hand 248 points to the Waveform panel, a fixed
column between the picture and the inspector, the pane's full height; the picture
has shrunk to fit what is left and is otherwise the frame of `04-editor` — the navy
video frame, the "Reelcut" ellipse and the "Jane Doe" lower third. Nothing in the
demo is graded, so Show Ungraded changes no pixel here; what shows it is on is the
small grey "Ungraded" tag in the top-left corner of the pane, in the margin above
the picture.

The panel: the heading "Waveform" in bold, then a square near-black well with a
narrow label gutter at its left reading 100, 50 and 0 against faint horizontal lines
at 100, 75, 50, 25 and 0 %. In the well, the frame's luma as a white density on a log
scale: x is the picture's columns, y the brightness. The black canvas around the
card is a solid white line along the bottom of the well across its whole width, the
navy card a second line just above it in the middle columns, and the white ellipse,
"Reelcut" and the title's text bright dots at the top with a faint scatter of
in-between levels from their anti-aliased edges. Red marks run along the bottom
edge over every column where at least 0.5 % of the pixels are black (level 0), and
along the top edge over the columns of the white text and ellipse. Under the well
two lines of monospaced text read "Highlights clipped 1.8 %" and "Shadows clipped
52.7 %" (the figure is "—" for the moment before the first frame is analysed).

In the light capture the panel and its heading are white and black with a grey
hairline at its left edge, the well still near-black with a white trace; in the dark
one the panel is dark grey with white text and the same well.
