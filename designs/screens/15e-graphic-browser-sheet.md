```json screen
{
  "title": "Insert Graphic",
  "project": "demo",
  "steps": [
    {"call": "perform_menu_item", "args": {"path": ["Insert", "Graphic…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Insert Graphic"}]
}
```

The Graphic dialog (Insert ▸ Graphic…, spec §11 G-45) is where a person
picks a motion graphic to put on the timeline. The demo project holds one
graphic of its own, `lower-third`, so the dialog opens on This Project.

Under the title "Insert Graphic" are three panes side by side. On the left, a
bordered list of categories: "This Project" (selected, a grey row), then the
bundled templates' four, "Data & Time", "Screencast", "Social & YouTube" and
"Titles & Text". In the middle, a wider bordered list of the chosen
category's graphics by name — here the one, "Lower third", selected. On the
right, the preview: the chosen graphic playing over a grey checkerboard, at
the canvas's shape (16:9 for the demo), looping; under it the graphic's name
in bold and its one-line description in grey, cut short with "…" if it is
longer than the preview is wide. The capture catches whichever frame of the
loop was showing; early in Lower third's loop the bar may not have slid in
yet.

A line under the panes is empty until an Insert or an export is refused or
an export runs; then it holds the reason, word for word ("graphics/<name>.js
does not compile: …"), "Exporting <title>…" or "Exported <title> to <file>:
<the files>.", and the dialog stays open. That is not captured here.

Bottom left, "Export…", a square outlined button (spec §11 G-46): it asks
where to save the chosen graphic as a `.fjgraphic` package, in a save panel
that slides down over the dialog, which stays open; it is greyed when no
graphic is chosen or the chosen one does not compile. To its right "From
File…", the same kind of button: it closes the dialog and asks for a `.js`
file instead. Bottom right, "Cancel" (Esc) and a blue "Insert" (Return; a
double-click on a graphic does the same). Insert is greyed when no graphic is
chosen.

In the light capture the sheet is white with black text, the lists white
with a thin grey border and the selected rows light grey. In the dark capture
the sheet is near-black with white text, the lists near-black with a thin
grey border and the selected rows dark grey; the checkerboard is the same
grey in both.
