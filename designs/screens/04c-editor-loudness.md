```json screen
{
  "title": "The editor — the Loudness Meter",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "perform_menu_item", "args": {"path": ["View", "Loudness Meter"]}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "preview", "window": "editor", "view": "preview"}
  ],
  "after": [
    {"call": "perform_menu_item", "args": {"path": ["View", "Loudness Meter"]}}
  ],
  "expect": [
    {"capture": "preview", "visible_text": "Loudness"}
  ]
}
```

The editor of `04-editor` with View ▸ Loudness Meter turned on (road map "audio"
AP7, spec §11 AU-75 and AU-76), the window at rest: nothing has played, so the meter
has nothing to show yet. It is not remembered: a window opens with it off.

The preview pane has given its right-hand 132 points to the loudness column, a fixed
column between the picture and the inspector (left of where View ▸ Scopes would sit),
the pane's full height, with a grey hairline at its left edge; the picture has shrunk
to fit what is left and is otherwise the frame of `04-editor`.

At the top of the column, "Loudness" in small semibold type, and at the right a
small round-arrow Reset button. Under it, the scale: faint monospaced labels 0, −6,
−12 … −48 down its left edge with short tick marks, and two empty grey troughs side
by side, captioned "M" and "S" underneath. A thin accent-coloured line crosses both
troughs at −16, the Normalize target.

Below the scale, four pairs of lines: "Momentary", "Short-term", "Integrated" and
"True peak max" in small grey type, each over its value in monospaced type — all
"—" here, because nothing has been measured. While the preview plays at ×1 the bars
fill from the bottom to the momentary and short-term levels, and the values read
like "−18.4 LUFS" and "−0.6 dBTP" (the true peak in coral above −1 dBTP).

At the foot, wrapping over two or three lines in faint small type: "The mix as the
preview plays it, before the export's loudness and master limiter." While the preview plays at
another speed it reads "Measured only at normal speed." instead.

In the light capture the column is white with black and grey text; in the dark one
it is dark grey with white text, and the troughs are the meter's own trough grey in
both.
