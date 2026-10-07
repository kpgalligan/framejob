```json screen
{
  "title": "Generate Captions",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "perform_menu_item", "args": {"path": ["File", "Generate Captions…"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}]
}
```

The Generate Captions sheet (File ▸ Generate Captions…) turns the speech in the
project into caption text clips. The person picks the language, where the
recognition runs, which clips to caption and how the captions look.

Under the title, a paragraph: the words are recognised on this Mac and land as
ordinary text clips on a track of their own, so they show in the preview and burn
into an export; nothing is uploaded. The rows: Language "English (United States)";
Engine "On this Mac"; From "Whole timeline"; Style "Subtitles"; under Style,
three dimmed, unticked checkboxes, one per line — "Slide the pill", "Fill words
as spoken" and "Dim in pauses" — which apply only to the word caption styles and
so are greyed with Subtitles; then a dark
preview box showing a sample caption, "This is how it looks", in a black band.
"Replace:" has a dimmed checkbox, "existing captions". A summary line reads
"2 clips · 00:00:10.200 of audio". At the foot, a grey note "captions go on a new
track", then "Cancel" and a blue "Generate".

In the light capture the sheet is white with black text; the pop-ups are
light-grey pills, the sample-caption box keeps its dark picture and black band,
"Cancel" is a white square button with a thin black outline and no shadow, and
"Generate" a flat blue block.
