```json screen
{
  "title": "A matte track — the header tag, the lane and the Clip tab's note",
  "project": "matte",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:window"]}},
    {"call": "set_playhead", "args": {"t": 900000}},
    {"call": "select_inspector_tab", "args": {"tab": "clip", "sub_tab": "picture"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "timeline", "window": "editor", "view": "timeline"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Matte for the track below (Alpha). Not drawn: its blend mode, drop shadow and reflection have no effect."}]
}
```

A matte pair (spec §11 MT-7): what a person sees once a track is switched to "matte
for the track below" with Track ▸ Matte. The `matte` fixture has three tracks, back to
front: Video (`speech.mov`, a navy card with speech), Window (a white 320×120 rectangle,
an Alpha matte, so it cuts Video) and Stray (a text clip "Reelcut", an Inverted Luma
matte with another matte behind it, so it cuts nothing). The Window clip is selected and
the Clip tab's Picture sub-tab is open.

The preview is black except the Window rectangle's box, which shows the navy video:
the matte's clips are never drawn, only what they cut. The selected clip's orange frame
and handles sit on that box as on any clip — on the canvas a matte clip is hit, selected
and dragged like any other. The Stray text draws nothing at all.

The timeline header names each matte track with a small accent-tinted tag (its words in the
ordinary label colour) on its own line
under the name, because the Medium row leaves room above the toggles: "Matte · Alpha"
under Window, and "Matte · nothing behind" under Stray, dimmed. Video has no tag. The two
matte lanes' clips are drawn at half opacity, so the lane shows through the tint; Stray's
clip has a dashed accent outline (Window's is under its orange selection ring). A short
accent bracket just right of the header column joins Window's lane to Video's — the
track it cuts; Stray, which cuts nothing, has none.

The inspector, under the sub-tab strip (Shape, Picture, Clip), opens with a note in the
accent colour: "Matte for the track below (Alpha). Not drawn: its blend mode, drop shadow
and reflection have no effect." Every control below it stays live — Blend still reads
Normal, SHADOW and REFLECTION are still there — and its values come back into play when
the track stops being a matte.

In the light capture the lanes are white and mid-grey, the tags are blue text on a pale
blue box, and the note is blue on white. In the dark capture the lanes are near-black;
the dimmed "nothing behind" tag is a dark blue that reads faintly against the header,
which is what dimmed means here.
