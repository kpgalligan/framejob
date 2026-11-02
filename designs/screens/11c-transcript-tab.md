```json screen
{
  "title": "Transcript tab",
  "project": "demo",
  "steps": [
    {"call": "select_inspector_tab", "args": {"tab": "transcript"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "after": [{"call": "select_inspector_tab", "args": {"tab": "clip"}}],
  "expect": [{"capture": "inspector", "visible_text": "Words from"},
             {"capture": "inspector", "visible_text": "Language"}]
}
```

The inspector's Transcript tab (View ▸ Transcript, ⌃⌘T): the timeline's
words in paragraphs, read on this Mac or from a cloud transcript, the spoken word
lit as the playhead passes it. A click on a word moves the playhead to it.

The Transcript tab is selected at the top of the inspector, between Document and
Assistant. Under the tabs is the bar, which does not scroll with the text. Its
first row reads "Words from" in small grey text on the left and, spanning the
rest of the row, a bordered popup in monospace showing "All tracks" with an
up-and-down chevron at its right end; the popup lists each track of the timeline
by name. The second row reads "Language", its popup "Automatic (en-US)", the
Mac's own default language, listing every recognition language this Mac
has installed; with none installed it is dimmed. While the tab reads a file on
this Mac, a line under the rows reads "Reading “name” on this Mac… NN % (k of
n)" in the accent colour, wrapping, with a small bordered "Stop" button at its
right; after Stop it reads "Stopped. 2 files not read on this Mac." with a
"Read" button instead. Under that, when they apply, come notes in the accent
colour: that two clips say the same thing, then at most three rows "clip N —
reason" for clips with no words, then "…and N more clips with no words.", whose
tooltip lists the rest. Each line wraps at the panel's width; a bar with nothing
to say shows only its two rows.

Below the bar the transcript fills the tab: each paragraph led by its timecode,
then its words, the one under the playhead on a tinted rectangle, words that
cannot be cut in a fainter grey.

In the light capture the tab strip and the panel are white with black words and
the popups white with grey borders; in the dark capture the panel is near-black
with white words and the popups a dark grey.
