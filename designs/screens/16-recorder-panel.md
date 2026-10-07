```json screen
{
  "title": "New Recording",
  "project": "demo",
  "steps": [{"call": "perform_menu_item", "args": {"path": ["File", "New Recording…"]}}],
  "captures": [{"name": "panel", "window": "recorder"}],
  "expect": [{"capture": "panel", "visible_text": "saved in ~/Movies/Reelcut Recordings"}]
}
```

The New Recording panel (File ▸ New Recording…) is where a person sets up a screen recording before starting it. It is a small
floating panel of its own, not a sheet; the capture is its content, without the
title bar.

At the top, a paragraph: the recording is saved as a movie in the Reelcut
Recordings folder and added to the chosen project at the playhead, or opened as a
new project. The rows: Source, a pop-up naming the display to record ("Built-in
Retina Display" on the machine that captured this), and under it an
unticked checkbox, "Include Reelcut windows"; Microphone "Off", with an
empty level meter beside it; System Audio, a switch that is on (blue); Show
Clicks, a switch that is off; Rate "60 fps"; Size "Nominal (points)", with the
line "1728×1117 points · 3456×2234 pixels" under it — the recorded size of that
display; and Record Into "Demo.reelcut". At the foot, "saved in ~/Movies/Reelcut
Recordings" in small grey type, a "Close" button, and an orange-red "Record"
button with a record symbol.

In the light capture the panel is white with black text; the pop-ups are
light-grey pills, the off switch a pale grey track, the level meter two pale grey
bars, and "Close" a white square button with a thin black outline and no shadow.
