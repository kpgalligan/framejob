```json screen
{
  "title": "Media tab",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "select_inspector_tab", "args": {"tab": "media"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "after": [{"call": "select_inspector_tab", "args": {"tab": "clip"}}],
  "expect": [{"capture": "inspector", "visible_text": "3 items"},
             {"capture": "inspector", "visible_text": "Log"}]
}
```

The inspector's Media tab: every file the project has imported, used or not,
which the person comes to when adding media, finding a file, or relinking or
consolidating what the project points at.

The Media tab is selected at the top of the inspector, and nothing is selected
in the timeline ("No selection"). One open section, MEDIA. Its first band holds
an "Add Media…" button with its shortcut "⇧⌘I" beside it and "3 items" at the
right; the next holds a "Search by name" field over a Sort row — a pop-up set
to "Import Order" and an unchecked "Unused only". Then the three rows, in import
order, each a bordered card with a thumbnail, the name, its length and a green
"audio" tag at the right: "speech.mov", a navy thumbnail, "00:00:05:07 · 640×360
· 30 fps"; "toneA.m4a", a grey waveform glyph, "00:00:04:29"; and "toneB.m4a",
the same glyph and length. toneB is the fixture's one unused file: no clip on
the timeline uses it, and its row looks like the others while "Unused only" is
off. Under the rows, the footer band holds "Consolidate…" and "Copies sources
into the package".

Below MEDIA is a second section, CAMERA LOG (spec §11 GR-16), there because
the project has a video file. Its "Log" row holds a pop-up reading "None",
dimmed because no row of the list is selected (it acts on the selected video
file), and under it a line reads "Select a video in the list". Selecting
speech.mov enables the pop-up — None, Apple Log, Apple Log 2, S-Log3 /
S-Gamut3.Cine, S-Log3 / S-Gamut3, V-Log / V-Gamut, C-Log2 / Cinema Gamut,
C-Log2 / BT.2020, C-Log3 / Cinema Gamut, C-Log3 / BT.2020, Use LUT… — and the line
then names the file's setting, "None" here. The rest of the panel is empty.

The two bands and the footer are drawn edge to edge across the panel while
their controls keep the panel's 10 pt gutter (`MediaPane.bar`): each band is
pinned 10 pt past both sides of its section row, so the layout dump reports
three `outside_superview` problems per capture, each a 10 pt overhang left and
right. They are that deliberate overhang, not a defect, and `screens.py`'s
`KNOWN` lists them as known.

In the light capture the inspector is white with black names and grey lengths;
the Media tab is a light-grey cell with a blue underline beside the white Clip,
Document and Assistant cells, the section header is a light-grey bar, the
buttons and cards are white with grey borders, and the "audio" tags are pale
green with green text. In the dark capture the panel is near-black with white
names, the cards and buttons have grey outlines, and the tags are dark green
with green text.
