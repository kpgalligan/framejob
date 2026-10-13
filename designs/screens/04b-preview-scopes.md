```json screen
{
  "title": "The editor — Scopes and Show Ungraded",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Scopes"]}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Show Ungraded"]}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "preview", "window": "editor", "view": "preview"}
  ],
  "after": [
    {"call": "perform_menu_item", "args": {"path": ["View", "Show Ungraded"]}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Scopes"]}}
  ],
  "expect": [
    {"capture": "preview", "visible_text": "Rec. 709 · encoded"},
    {"capture": "preview", "visible_text": "Ungraded"}
  ]
}
```

The editor of `04-editor` with the two ways of seeing the grade turned on (grading
GR3 and grading-2 G2-1, spec §11 GR-4, GR-5 and GR-10): View ▸ Scopes and View ▸
Show Ungraded. Neither is remembered: a window opens with both off, and the scopes'
two slots open as Waveform over Vectorscope.

The preview pane has given its right-hand 248 points to the Scopes panel, a fixed
column between the picture and the inspector, the pane's full height; the picture
has shrunk to fit what is left and is otherwise the frame of `04-editor` — the navy
video frame, the "Frame Job" ellipse and the "Jane Doe" lower third. Nothing in the
demo is graded, so Show Ungraded changes no pixel here; what shows it is on is the
small grey "Ungraded" tag in the top-left corner of the pane, in the margin above
the picture.

The panel holds two slots, one above the other. Each starts with a header: a
field-styled picker at the left reading the slot's scope with an up-down chevron
(it lists Waveform, Parade, Vectorscope and Histogram), and at the right, in faint
small monospaced type, "Rec. 709 · encoded".

The top slot is the Waveform: a near-black well with a narrow label gutter at its
left reading 100, 50 and 0 against faint horizontal lines at 100, 75, 50, 25 and
0 %. In the well, the frame's luma as a white density on a log scale: x is the
picture's columns, y the brightness. The black canvas around the card is a solid
white line along the bottom of the well, the navy card a second line just above it
in the middle columns, and the white ellipse, "Frame Job" and the title's text bright
dots at the top with a faint scatter of in-between levels from their anti-aliased
edges. Red marks run along the bottom edge over every column where at least 0.5 %
of the pixels are black (level 0), and along the top edge over the columns of the
white text and ellipse. Under the well two lines of monospaced text read
"Highlights clipped 1.8 %" and "Shadows clipped 52.7 %" (the figure is "—" for the
moment before the first frame is analysed).

The bottom slot is the Vectorscope: a near-black square, centred in the slot, with
Cb running right and Cr up. A faint cross marks neutral at its centre, where the
black canvas and the white text all land as one bright dot; the navy card is a
short smear from the centre towards the box labelled B. Six small square boxes mark
the 75 % colour-bar targets, labelled R, Mg, B, Cy, G and Yl, and a faint line runs
from the centre up and to the left to the edge: the skin line. The vectorscope has
no readouts.

This window's pane is shorter than the two slots' full sizes (a 200 pt waveform and
a 224 pt vectorscope), so both bodies have shrunk by the same factor to fit, the
vectorscope staying square — here a waveform about 190 pt tall over a square about
211 pt on a side. In a taller window both are at full size with space left below;
in a pane under 360 pt only the top slot shows.

In the light capture the panel and its headers are white and black with a grey
hairline at its left edge, the wells still near-black with white traces; in the
dark one the panel is dark grey with white text and the same wells.
