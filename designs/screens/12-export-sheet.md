```json screen
{
  "title": "Export",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "perform_menu_item", "args": {"path": ["File", "Export…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}]
}
```

The Export sheet (File ▸ Export…, or the toolbar's Export… button) slides down
over the editor window. Here the person chooses what file to make from the
project — format, size, rate, quality, loudness and range — and either writes it
now or adds it to a queue.

Under the bold title "Export", a long paragraph explains the card: the format
decides the codec and container; size, frame rate and range start as the
document's; what loudness normalisation does; that a preset remembers choices
rather than numbers; how burned-in timecode reads; and what Add to Queue does.

Then a column of labelled rows: Preset "Custom", with a gear pop-up beside it;
Format "H.264 (MP4)"; Size "Document size · 960 × 540", with two dimmed number
fields, 960 × 540, under it; Frame rate "Project rate"; Quality "Format default";
Loudness "Off", with a dimmed "-14" field beside it; Range "Whole project",
dimmed; and an unchecked "Burn in timecode". A monospaced summary line reads
"960 × 540 · 30 fps · 00:00:05:07", and under it, on a line of its own, the
format line "H264 · MP4" in smaller grey monospaced type. Along the bottom, to
the right, the buttons "Add to Queue", "Cancel" and "Export…" (blue), with
nothing to their left.

The sheet is 480 pt wide, 60 more than the app's other sheets. The format line
reads longer on other formats and grows with a Quality tier or a loudness
target ("HEVC_ALPHA · MOV · 800 kbps · 320 kbps audio · −14 LUFS · alpha"), so
it has the sheet's full width rather than the gap beside the buttons, and is
drawn whole on every one (#243).

In the light capture the sheet is white with black text; the pop-ups are
light-grey pills, the dimmed number fields white boxes with pale grey numbers,
"Add to Queue" and "Cancel" white square buttons with a thin black outline and
no shadow, and "Export…" a flat blue block.
