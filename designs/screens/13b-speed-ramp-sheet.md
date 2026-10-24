```json screen
{
  "title": "Speed Ramp",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Speed Ramp…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}]
}
```

The Speed Ramp sheet (Clip ▸ Speed Ramp…, spec §11 SR-24) makes a speed ramp
preset on the one selected media clip in one step. Here the video clip is
selected and no in/out range is set, so the preset spans the whole clip.

Under the title "Speed Ramp", a paragraph says what the shapes do: Up and
Burst rise above the clip's rate where the ramp starts, Down and Dip fall below
it, Dip and Burst return to it holding the rate between, and the clip keeps its
place and length while playing more or less of its media. Then four rows, their
labels right-aligned: "Shape:" with a pop-up reading "Speed Dip" (the shape the
sheet opens on); "Rate:" with a field reading "0.5", a "×", and a "Presets"
pop-up; "Curve:" with a pop-up reading "Ease In Out"; and "Hold:" with a pop-up
reading "50%" — greyed out for Ramp Up and Ramp Down, which hold nothing.

Under the rows, in small monospaced grey type, the readout the core answers for
the preset as it stands: first the shape and its span, "Speed Dip · the whole
clip" and the clip's two timeline timecodes; then the rates, "×1 → ×0.5, held
… s, → ×1" — the rate where the ramp starts, the target, how long the target
holds, and the rate it returns to. When the core refuses the preset (an action
already in the span, a rate on the wrong side, a ramp that would read past the
media's end) the second line is the core's own sentence instead and Apply is
disabled. Bottom left, in small grey type, the allowed range "×0.1 – ×1000";
bottom right, "Cancel" and a blue "Apply".

In the light capture the sheet is white with black text; the pop-ups are
light-grey pills, the rate field a white box, "Cancel" a white square button
with a thin black outline and no shadow, and "Apply" a flat blue block.
