```json screen
{
  "title": "Transcript tab, Find",
  "project": "fillers",
  "steps": [
    {"call": "select_inspector_tab", "args": {"tab": "transcript"}},
    {"call": "transcript_view", "args": {"find": "er", "wait": 30}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "after": [{"call": "transcript_view", "args": {"find": null}},
            {"call": "select_inspector_tab", "args": {"tab": "clip"}}],
  "expect": [{"capture": "inspector", "visible_text": "1 of 3"}]
}
```

Find in the Transcript tab (Edit ▸ Find…, ⌘F): a bar above the transcript's
text that searches the words shown, marks every match and brings the current
one into view. It changes nothing in the project.

The Transcript tab is selected. Under its two rows, Words from and Language,
and above the text, is the find bar: one row with a bordered field on the left
holding the typed text ("er"), then small grey text counting the matches
("1 of 3" here; "No matches" when the words shown hold none), then three small
bordered buttons: "‹" for the previous match, "›" for the next, and "Done". A
thin line separates the bar from the text below it.

The fixture's words are "Hello there everyone um, Uh er welcome back", so the
letters "er" are found three times, inside "there" and "everyone" and as the
word "er". Each match sits on a pale yellow rectangle covering only the letters
found; the current match, the first, is a stronger yellow with a yellow outline. The word under the playhead
keeps its own tinted rectangle. Return in the field moves to the next match
and ⇧Return to the previous one; ⌘Return selects the current match's words, moves
the playhead there and gives the keys to the text, the bar staying open; Esc or
Done closes the bar and the marks go.

In the light capture the bar is white with black words; in the dark capture it
is near-black with white words, and the yellow marks stay readable under the
white text.
