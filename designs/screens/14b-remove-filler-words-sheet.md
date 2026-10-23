```json screen
{
  "title": "Remove Filler Words",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Remove Filler Words…"]}}
  ],
  "captures": [
    {"name": "sheet", "window": "sheet"},
    {"name": "timeline", "window": "editor", "view": "timeline"}
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
nest or a transition is left in. Below it, "No cuts" in small monospaced type —
nothing in this project has been transcribed with filler words yet — and a grey
note: "No AssemblyAI API key is set — Frame Job ▸ Settings…".

Then the section for the files with no filler transcript: a bold sentence that
filler words are found only in an AssemblyAI transcript made with filler words,
that transcription on this Mac does not report them, and that these files have
none yet; then a smaller grey sentence saying the audio is uploaded to
AssemblyAI (United States), transcribed with Universal-3.5 Pro and deleted from
AssemblyAI once the words have been read back, and that nothing is uploaded
until Transcribe is pressed. Two rows follow, "speech.mov" and "toneA.m4a", each
with its estimate in monospaced grey under the name — "1 file to upload ·
00:00:05.249 of audio · under $0.01 at AssemblyAI's published rate" and the
same for 00:00:04.977 — and a dimmed outlined "Transcribe" button on the right,
off because no key is set. At the foot, "markers keep their place" in small grey
type, "Cancel", and a dimmed "Remove", since there is nothing to remove.

The second capture is the editor's timeline while the sheet is up: the timeline
bar ("No selection", the tools, Snap, the meter, zoom, S / M / L), the ruler with
the playhead at 00:00:00, and the Music, Shapes, Graphics and Titles tracks with
their clips. With no cuts found, nothing on the timeline is shaded.

In the light capture the sheet is white with black text, the two Transcribe
buttons pale outlined squares, "Cancel" a white square button with a thin black
outline and no shadow, and the dimmed Remove a pale blue block. In the dark
capture the sheet is near-black with white text, the Transcribe buttons grey
outlines, Cancel outlined in white and Remove a muted blue block.
