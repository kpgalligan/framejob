```json screen
{
  "title": "Restore Graphic Version",
  "project": "demo",
  "steps": [
    {"call": "perform_menu_item", "args": {"path": ["File", "Restore Graphic Version…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Restore Graphic Version"},
             {"capture": "sheet", "visible_text": "1 version kept"}]
}
```

The Restore Graphic Version sheet (File ▸ Restore Graphic Version…) puts back
the newest earlier version Frame Job kept of a graphic's code. The demo project's
one graphic, `lower-third`, was written twice, so one earlier version is kept.

Under the title "Restore Graphic Version", a paragraph says what a restore
does: it puts back the newest kept version of the graphic's code; if the
graphic has code now, that code is kept in its place, so restoring again
returns to where you were; and restoring is not an Undo step. Then "Graphic:"
with a pop-up reading "lower-third", and under the pop-up, in small grey
monospaced type, "1 version kept" — how many versions the chosen graphic has,
with no list of them to pick from. A graphic that was deleted and still has
kept versions is listed here too, its row reading "(deleted)" after its name;
the demo has none. Bottom right, "Cancel" and a blue "Restore".

In the light capture the sheet is white with black text, the pop-up a
light-grey pill with a pair of chevrons at its right end, "Cancel" a white
square button with a thin black outline and "Restore" a flat blue block. In the
dark capture the sheet is near-black with white text, the pop-up a dark-grey
pill, the count a mid grey, and "Cancel" a dark button with a thin white
outline.
