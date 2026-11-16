```json screen
{
  "title": "Remove Filler Words",
  "project": "fillers",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Remove Filler Words…"]}}
  ],
  "captures": [
    {"name": "sheet", "window": "sheet"},
    {"name": "timeline", "window": "editor", "view": "timeline"}
  ],
  "expect": [
    {"capture": "sheet", "visible_text": "1 cut · removes 00:00:00:16"}
  ],
  "after": [{"call": "cancel_sheet", "args": {}}]
}
```

The Remove Filler Words sheet (Clip ▸ Remove Filler Words…) finds the ums, uhs
and ers in the project's speech and cuts them out in one edit. Unlike Remove
Silences it has nothing to tune: it shows what it found, and for each file it
cannot read fillers from yet, what it would cost to find them.

Under the title, a paragraph explains that each run of filler words is cut and
the timeline closes over it as one edit, that a cut is widened to the 32 ms
speech grid but never into the words beside it, with its edges snapped inward
to the frame grid, and that a filler which would cut into another clip's word, a
nest, or an overlap between two clips on one track or the area around it is left in. Below it, "1 cut · removes 00:00:00:16" in small monospaced
type: the fixture's `speech.mov` has a cached transcript with one run of
fillers ("um," "Uh" "er"), which becomes one cut of sixteen frames. Under it a
grey note: "No AssemblyAI API key is set. Set one in Frame Job ▸ Settings… ▸ Transcription."

Then the section for the files with no filler transcript: a bold sentence that
filler words are found only in an AssemblyAI transcript made with filler words,
that transcription on this Mac does not report them, and that these files have
none yet; then a smaller grey sentence saying the audio is uploaded to
AssemblyAI (United States), transcribed with Universal-3.5 Pro and deleted from
AssemblyAI once the words have been read back, and that nothing is uploaded
until Transcribe is pressed. One row follows, "toneA.m4a", the file that has no
transcript, with its estimate in monospaced grey under the name — "1 file to
upload · 00:00:04.977 of audio · under $0.01 at AssemblyAI's published rate" —
and a dimmed outlined "Transcribe" button on the right, off because no key is
set; hovering it shows the same sentence as its tooltip. `speech.mov` has no row:
its transcript is already there. At the foot, "markers keep their place" in small grey
type, "Cancel", and "Remove", enabled now that there is a cut to make.

The second capture is the editor's timeline while the sheet is up: the timeline
bar ("No selection", the tools, Snap, the meter, zoom, S / M / L), the ruler with
the playhead at 00:00:00, and the Music, Shapes, Graphics and Titles tracks with
their clips. The cut the sheet found is shaded in red on the ruler and in the
lanes behind the clips, a narrow band between two and three seconds: pale red in
the light capture, a dark red in the dark one.

In the light capture the sheet is white with black text, the Transcribe
button a pale outlined square, "Cancel" a white square button with a thin black
outline and no shadow, and Remove a solid blue block with white text. In the dark
capture the sheet is near-black with white text, the Transcribe button a grey
outline, Cancel outlined in white and Remove the same blue block.
