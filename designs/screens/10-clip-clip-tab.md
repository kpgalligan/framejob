```json screen
{
  "title": "Clip inspector — Clip",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab", "args": {"tab": "clip", "sub_tab": "clip"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Reversed frames"}]
}
```

The same video clip as the Picture screen, with its third sub-tab, Clip, picked:
where the person trims the clip against its source, reverses it, changes its speed
and gives it a motion preset.

The preview shows the video clip's orange frame and handles, and the timeline
bar reads "speech.mov" over "Video · video".

The inspector: the name, the actions row and lane, and the sub-tabs Picture,
Sound and Clip, with Clip selected. The TIMING section is open, summary
"00:00:05:07": "In" and "Out" timecode fields ("00:00:00:00" and "00:00:05:07"),
"Duration 00:00:05:07", an unchecked "Reverse" checkbox, "Reversed frames —", and
a dimmed "Render Reverse" button. Closed below: SPEED "1.00×" and MOTION PRESETS
"off".

In the light capture the inspector is white with black labels; the In and Out
fields are white boxes with grey borders, the Reverse checkbox, its label and the
Render Reverse button are pale grey, and the section headers are light-grey bars.
