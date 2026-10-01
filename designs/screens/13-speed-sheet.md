```json screen
{
  "title": "Speed",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Speed…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}]
}
```

The Speed sheet (Clip ▸ Speed…) changes how fast the selected clips play. Here
one clip, the video, is selected.

Under the title "Speed", a paragraph says what a change does to its neighbours:
faster clips can leave gaps, slower ones can overlap, later clips stay in place,
a clip an allowed overlap reaches gains a transition, named below, and a clip
whose overlap is not allowed stays unchanged. Then "Rate:" with a field reading
"1", a "×", and a "Presets" pop-up; a checked "Preserve pitch"; and a summary
line, "1 clip · 00:00:05:07 → 00:00:05:07" — the selection's length before and
after. At ×1, as captured, no clip gains a transition, so no line follows it; a
slower rate that reaches a neighbour adds one line per such clip under it, such
as "clip 7 gains a 0.67 s cross dissolve". A transition that already plays and
gets longer or shorter is named too, as "clip 7's cross dissolve grows to
1.50 s". Bottom
left, in small grey type, the allowed range "×0.1 – ×10"; bottom right, "Cancel"
and a blue "Apply".

In the light capture the sheet is white with black text; the rate field is a
white box, the Presets pop-up a light-grey pill, "Preserve pitch" a dark tick in a
light-grey box, "Cancel" a white square button with a thin black outline and no
shadow, and "Apply" a flat blue block.
