```json screen
{
  "title": "Rename Graphic",
  "project": "demo",
  "steps": [
    {"call": "perform_menu_item", "args": {"path": ["File", "Rename Graphic…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Rename Graphic"}]
}
```

The Rename Graphic sheet (File ▸ Rename Graphic…) gives one of the project's
graphics a new name. The demo project holds one graphic, `lower-third`, so the
sheet opens on it.

Under the title "Rename Graphic", a paragraph says what a rename does: every
clip that uses the graphic follows its new name, on the timeline and inside
nests; Undo renames it back when a clip uses it, and a graphic no clip uses is
renamed back by renaming it again. Then "Graphic:" with a pop-up reading
"lower-third", and "New name:" with a field holding the same name, selected so
that typing replaces it. Bottom left, in small grey type, what a name may hold:
"lowercase letters, digits and -"; bottom right, "Cancel" and "Rename". Rename
is dimmed, as captured, because the field still holds the graphic's own name;
it lights once the name differs. When Reelcut refuses a name — one already
taken, one that breaks the rule — its sentence appears under the two rows and
the sheet stays open; that is not captured here.

In the light capture the sheet is white with black text; the pop-up is a
light-grey pill with a pair of chevrons at its right end, the field a white box
with a thin dark outline and its text highlighted grey, "Cancel" a white square
button with a thin black outline, and "Rename" a pale blue block. In the dark
capture the sheet is near-black with white text, the pop-up a dark-grey pill,
the field a black box with a thin light outline, and "Rename" a muted blue.
