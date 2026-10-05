```json screen
{
  "title": "Delete Graphic",
  "project": "demo",
  "steps": [
    {"call": "perform_menu_item", "args": {"path": ["File", "Delete Graphic…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Delete Graphic"}]
}
```

The Delete Graphic sheet (File ▸ Delete Graphic…) removes one of the project's
graphics. The demo project holds one graphic, `lower-third`, which a clip on
the timeline uses.

Under the title "Delete Graphic", a paragraph says what a delete does: a
graphic that clips still use cannot be deleted; its code is kept with its
earlier versions, so Restore Graphic Version… brings it back; and deleting is
not an Undo step. Then "Graphic:" with a pop-up reading "lower-third", the
sheet's only control. Bottom right, "Cancel" and a blue "Delete". There is no
second "are you sure?": Delete is the confirmation. Pressed here it would be
refused, because a clip uses `lower-third`; the sentence saying which clip
appears under the pop-up, the sheet grows to hold it and stays open. That is
not captured here.

In the light capture the sheet is white with black text, the pop-up a
light-grey pill with a pair of chevrons at its right end, "Cancel" a white
square button with a thin black outline and "Delete" a flat blue block. In the
dark capture the sheet is near-black with white text, the pop-up a dark-grey
pill and "Cancel" a dark button with a thin white outline.
