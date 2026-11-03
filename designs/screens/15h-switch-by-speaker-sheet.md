```json screen
{
  "title": "Switch by Speaker",
  "project": "layout",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:screen", "$clip:camera"]}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Switch by Speaker…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Switch by Speaker"}]
}
```

The Switch by Speaker sheet (road map "creator-jobs" SW2b, spec §11 SW-26) comes up from
Clip ▸ Switch by Speaker… when two or more cameras and a clip with sound are selected — here
the `layout` fixture's Screen and Camera clips, both `speech.mov`, so each camera is its own
microphone and there is no third camera left for a wide shot. Switch writes a Program track
that cuts to whoever is talking, as one undo step.

Under the bold title "Switch by Speaker", a muted hint: "Cuts a Program track from the
cameras, showing whoever talks on each microphone. Run Synchronize Audio first. One undo
step." Then a grid of rows, each with its right-aligned label:

- "Speaker 1:" and "Speaker 2:" — each a Microphone pop-up (the tracks with sound), the muted
  word "on", and a Camera pop-up (the camera tracks); here Camera over Camera and Screen over
  Screen, front first.
- "Wide:" — a pop-up of "None" and the cameras; "None" here.
- "Minimum shot:" — a number field (2) and "s".
- "Cut:" — a number field (0.2) and "s before speech".
- "Crosstalk:" — the muted word "shows" and a pop-up of "Wide" and "Current speaker".
- "Ignore bleed:" — a number field (15) and "dB below a speaker's own level".
- A checkbox "Cut to the wide after", off, then a dimmed number field (20) and "s on one
  speaker".
- A checkbox "Mute the cameras' own sound", off here because the cameras are the microphones.

A "Write to:" row appears only when an earlier Program track could be replaced; this fixture
has none, so it is absent. Under the grid, one muted summary line says what Switch would do
or why it cannot yet (here it may say a microphone is still being analysed, since the
fixture's caches are made as it opens). At the foot, right-aligned, "Cancel" (Escape) and the
primary "Switch" (Return), which is enabled only when there is something to switch.
