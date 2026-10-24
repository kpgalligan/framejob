```json screen
{
  "title": "Clip inspector — Clip, the Speed section in an action",
  "project": "ramp",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:video"]}},
    {"call": "set_playhead", "args": {"t": 600000}},
    {"call": "select_inspector_tab", "args": {"tab": "clip", "sub_tab": "clip"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "2.00×"}]
}
```

The `ramp` fixture's video clip, `speech.mov` cut to 2 s, with one action from 0.5 s to
1.5 s whose end names a rate of ×2: a speed ramp (spec §11 SR-21). The playhead at 1 s sits
inside the action, which selected it, so the Clip sub-tab's Speed section edits the action's
END rate rather than the clip's.

The preview shows the navy "speech.mov" card with its orange frame and handles. In the
timeline the Video track holds the clip from 0 to 2 s, its action band "1" from 0.5 s to
1.5 s with the linear curve drawn through it, and the coral playhead line at 1 s.

The inspector: ACTIONS reads "1 · editing 1" in mint, the lane's band 1 is solid mint with
the coral playhead across it, and the detail row reads "00:00:00:15", "1.00 s" and Linear.
The Clip sub-tab carries a mint "◆1". TIMING is open as on the plain Clip tab (In
"00:00:00:00", Out and Duration "00:00:02:00"). SPEED is revealed open because the action
keys it: its header carries a mint "◆1", the summary "2.00×" in mint and a Clear button in
place of Reset. "Rate" carries a mint ◆ in its gutter and its field reads the END rate
"2.00×" in a mint border, followed by the coral "now 1.50×" — the rate the clip plays at
under the playhead, halfway up the ramp. "Keep pitch" (checked) and "Fit to" ("00:00:02:00")
each carry a faint ⊘: they are the clip's, whatever action is selected.

In the light capture the inspector is white with black labels, the band and marks in a
darker mint; in the dark capture it is near-black with white labels and the band, marks and
summary in a pale mint.
