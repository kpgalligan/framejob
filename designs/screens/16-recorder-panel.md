```json screen
{
  "title": "New Recording",
  "project": "demo",
  "steps": [{"call": "perform_menu_item", "args": {"path": ["File", "New Recording…"]}}],
  "captures": [{"name": "panel", "window": "recorder"}],
  "expect": [{"capture": "panel", "visible_text": "saved in ~/Movies/Frame Job Recordings"}]
}
```

The New Recording panel (File ▸ New Recording…) is where a person sets up a screen recording before starting it. It is a small
floating panel of its own, not a sheet; the capture is its content, without the
title bar.

At the top, a paragraph: the recording is saved as a movie in the Frame Job
Recordings folder and added to the chosen project at the playhead, or opened as a
new project. The rows: Source, a pop-up naming the display to record ("Built-in
Retina Display" on the machine that captured this), and under it an
unticked checkbox, "Include Frame Job windows", then a second unticked
checkbox, "Record the camera too", live only with a display or a window as the
Source; Camera, a greyed pop-up naming
the default camera ("FaceTime HD Camera" on the machine that captured this),
live only when a camera is wanted — Source Camera, or "Record the camera too"
ticked; Format, a greyed pop-up reading "Best
(1760×1328 at 30 fps)" — the default camera's best format, then its other
formats as size and rate — with the same live rule; under Format, a row
holding the camera's live preview (a 200 × 150 pt well) appears only when a
camera is wanted, so it is absent here; Layout, a greyed pop-up reading "Corner" (its
other rows Rounded Corner, Circle, Side by Side and Camera Full), and under it a greyed,
unticked checkbox, "Remove the camera's background when it lands", both live only with "Record
the camera too" ticked (the screen catalog pins their keys at Corner and off); Microphone "Off", with an
empty level meter beside it, and under it a greyed, unticked checkbox, "Enhance the
microphone when it lands", live only with a microphone chosen; System Audio, a switch that is on (blue); Cursor,
a pop-up reading "Separate" — the pointer is kept out of the movie and drawn by Frame Job; the
other row is "In the picture", the default for a picked window; Show
Clicks, a switch that is off, and under it an unticked checkbox, "Record shortcuts", with a
small grey note: "Records each shortcut you press with ⌘ or ⌃, or ⌥ with an arrow, Delete,
Return, Tab or Esc, and when you type, never what you type. Nothing is recorded while an app
holds secure input."; "When it lands:" with three checkboxes stacked under it, "Zoom in on
clicks" (ticked and live), then "Show shortcuts" (ticked) and "Speed up typing" (unticked),
those two greyed because Record shortcuts is off; Rate "60 fps"; Size "Nominal (points)", with the
line "1728×1117 points · 3456×2234 pixels" under it — the recorded size of that
display; and Record Into "Demo.framejob". At the foot, "saved in ~/Movies/Frame Job
Recordings" in small grey type, a "Close" button, and an orange-red "Record"
button with a record symbol.

In the light capture the panel is white with black text; the pop-ups are
light-grey pills, the off switch a pale grey track, the level meter two pale grey
bars, and "Close" a white square button with a thin black outline and no shadow.
