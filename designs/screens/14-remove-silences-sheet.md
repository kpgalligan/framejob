```json screen
{
  "title": "Remove Silences",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "detect_silence", "args": {}, "until_absent": "pending_peaks", "within": 60},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Remove Silences…"]}}
  ],
  "captures": [
    {"name": "sheet", "window": "sheet"},
    {"name": "timeline", "window": "editor", "view": "timeline"}
  ],
  "after": [{"call": "cancel_sheet", "args": {}}]
}
```

The Remove Silences sheet (Clip ▸ Remove Silences…) finds the quiet stretches
in the project and cuts them out in one edit. The person tunes what counts as
quiet and sees how many cuts that makes before pressing Remove.

Under the title, a paragraph explains that the quiet spans are cut and the
timeline closes over them as one edit, that quiet is measured in the mix, and
that nothing inside a nest is cut. The controls: Judge by "Voice"; Level if no
voice, a slider at "-40 dBFS"; Longer than "0.5" seconds; Keep at ends "0.1"
seconds; and In "All audible clips". Below them, "No cuts" — this project has no
quiet stretch long enough — and a grey note: "1 file(s) hold no voice in at least
one clip and are judged by level there: toneA.m4a." At the foot, "markers keep
their place" in small grey type, "Cancel", and a dimmed "Remove", since there is
nothing to remove.

The second capture is the editor's timeline while the sheet is up: the timeline
bar ("No selection", the tools, Snap, the meter, zoom, S / M / L), the ruler with
the playhead near 00:00:02, and the Music, Shapes, Graphics and Titles tracks
with their clips. With no cuts found, nothing on the timeline is marked.

In the light capture the sheet is white with black text; the pop-ups are
light-grey pills, the two number fields white boxes, the level slider a pale grey
track with a white knob, "Cancel" a white button with a black outline and a hard
black shadow, and the dimmed Remove pale blue. The timeline is white, with the
Shapes and Titles lanes mid-grey behind their clips.
