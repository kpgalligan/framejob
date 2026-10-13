```json screen
{
  "title": "Clip inspector — Text",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:text"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ]
}
```

A text clip — the title "Frame Job" — is selected. The Clip tab opens on its Text
sub-tab, where the person edits what the title says and how it is set.

In the preview the title has an orange frame with handles and a rotation handle,
drawn around the word inside the ellipse. The Titles clip in the timeline has an
orange outline, and the timeline bar reads "Frame Job" over "Titles · text".

The inspector: the name field "Frame Job" over "text · 00:00:05:00"; the actions
row and lane ("no actions · ⌥⌘K adds one"); three sub-tabs, Text (selected),
Picture and Clip. The CONTENT section is open, its summary "Frame Job", with the
words "Frame Job" in a multi-line text area. Then closed sections with their
summaries: FONT "72 px", STYLE "center", OUTLINE "off", BACKDROP "off", BOX
"auto", REVEAL "off" and PRESETS.

In the light capture the inspector is white with black text: the text area is
white, the section headers are light-grey bars with grey capitals and summaries,
and the Text sub-tab and the lane's Clip button are pale blue with a blue outline.
