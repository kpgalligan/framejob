```json screen
{
  "title": "Clip inspector — Graphic, an action selected",
  "project": "animated",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:graphic"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "at end"}]
}
```

The same lower third as 07, with an action on it: the person has selected the
action and is setting what the graphic's properties are at its END. The
playhead sits inside the action's span (2.5 s, three quarters of the way
through), which is what selected it.

In the picture the lower third reads "Jane Doe" over "Director of
Photography", its accent bar part way from the module's orange-red to the
end's blue, the title drawn between its start and end sizes. In the timeline
the Graphic clip holds the action band "1" from 1 s to 3 s, with its linear
curve drawn through it; at the M track size the band shows its number only.

The inspector: ACTIONS reads "1 · editing 1" in mint, the lane's band 1 is
solid mint with the coral playhead line across it, and the detail row reads
"00:00:01:00", "2.00 s" and Linear. The Graphic sub-tab carries a mint "◆3",
and so does the PROPERTIES header, whose button is now Clear instead of Reset.
Three rows carry a mint ◆ in their gutter: "accent", a blue well; "size",
whose field reads the END value "96" in a mint border, its slider showing a
mint segment from the start value to the end and the coral playhead tick on
it; and "boxed", unchecked, followed by a mint "at end" because a checkbox
switches at the end rather than ramping. "Title", "subtitle" and "align" are
unmarked: the action does not change them. SIZE and TIMELINE are closed, each
header with a faint ⊘ — actions do not animate a graphic's size or its own
timeline.

In the light capture the inspector is white with black labels, the band and
marks in a darker mint; in the dark capture it is near-black with white
labels and the band, marks and "at end" in a pale mint.
