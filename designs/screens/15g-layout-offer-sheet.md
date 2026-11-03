```json screen
{
  "title": "Lay out the clips in a nest?",
  "project": "layout",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:camera"]}},
    {"call": "set_playhead", "args": {"t": 300000}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Camera Layout", "Side by Side"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Lay out the clips in a nest?"}]
}
```

The nest offer (road map "creator-jobs" CO7, spec §11 CO-72) comes up when a
camera layout cannot be laid out because a clip it would move zooms or moves on
its own after the playhead — here the `layout` fixture's screen clip, which
zooms at 1 s, under Clip ▸ Camera Layout ▸ Side by Side at 0.5 s with the
camera selected. Laying the screen out would fight its zoom, so instead of only
refusing, Frame Job offers to put the screen's clips in a nest first; the
layout then moves the nest and the zoom keeps playing inside it.

Under the bold title "Lay out the clips in a nest?", two paragraphs: first the
reason the switch was refused, in the editor's own words — "The screen clip 8
at 00:00:00:00 zooms (action 10); nest the screen's clips so the layout moves
the nest and the zoom stays inside it." — then "Nest and Switch puts those clips
in a nest first, so the layout moves the nest and the zoom keeps playing inside
it. One Undo takes both back." At the foot two full-width buttons, stacked:
"Nest and Switch" and "Cancel" (Escape). Nest and Switch makes the nest and the
layout as one undo step, "Camera Layout"; Cancel changes nothing.

In the light capture the sheet is white with black text and the buttons pale
grey capsules with black titles. The dark capture comes out as a plain white
panel: the alert's dark backdrop is a material the capture does not draw, so its
white text and buttons land on white (its layout dump still lists the title, the
two paragraphs and both buttons where the light one has them). On screen the dark
sheet is near-black with white text.
