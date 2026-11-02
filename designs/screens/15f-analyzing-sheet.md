```json screen
{
  "title": "Analyzing",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "perform_menu_item", "args": {"path": ["Clip", "Split at Shot Changes"]}}
  ],
  "captures": [{"name": "sheet", "window": "sheet"}],
  "after": [{"call": "cancel_sheet", "args": {}}],
  "expect": [{"capture": "sheet", "visible_text": "Waiting"}]
}
```

The Analyzing sheet (spec §11 CJ-28) comes up when a command plans with
something Frame Job finds in the media on this Mac and the project's cache does
not hold it yet. Here the command is Clip ▸ Split at Shot Changes (CJ-29), with
the video clip selected, so the sheet is finding its hard cuts. Every screen's
instance is launched holding each analysis job before its first frame
(`-RCDevAnalysisHold 600`), so the sheet is caught before any work is done.

Under the title "Analyzing", a paragraph in grey says that Split at Shot
Changes needs what Frame Job finds in these files on this Mac, kept in the
project's cache, that nothing changes until it is found, and that Stop leaves
everything as it is. Then one row per file being analysed — here one: the
file's name, "speech.mov", a full-width progress bar still empty, and "Waiting"
in small grey type under it. Once the work starts the line reads the share done ("42 %") and
the bar fills; a finished file reads "Done". At the foot, on the right, one
button: "Stop". There is no Apply: when every file is done the sheet closes by
itself and the clips are split as one undo step.

In the light capture the sheet is white with black text, the bar a pale grey
track, and "Stop" a white square button with a thin black outline and no
shadow. In the dark capture the sheet is near-black with white text, the bar a
dark grey track, and Stop outlined in white.
