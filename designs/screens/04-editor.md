```json screen
{
  "title": "The editor",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [{"name": "window", "window": "editor"}]
}
```

The editor with a small project in it and nothing selected: this is the screen
a person spends most of their time in, watching the preview while arranging clips
on the timeline.

The toolbar shows the playhead at "00:00:02:15" of "00:00:05:07". The preview
shows the frame under the playhead: a navy video frame, the white word "Reelcut"
inside a white ellipse outline over it, and a lower-third title in the bottom left
— a dark box with an orange bar at its left edge, "Jane Doe" in bold and "Director
of Photography" beneath. The inspector reads "Select a clip to edit its
properties." because nothing is selected.

The timeline shows four tracks, each a named row with the eye, speaker, lock and
headphone icons: Music, holding a green audio clip "toneA.m4a" with a pale level
line across it, its waveform band; Shapes, a teal clip "Ellipse"; Graphics, a taller teal clip "Graphic";
and Titles, an orange clip "Reelcut". Each clip's name sits in a darker strip
along its top with a small icon for its kind. The red playhead is at about the
2.5-second mark, a thin line through every track.

In the light capture the toolbar, the inspector and the track headers are white
with black text, the preview well is mid-grey, and the lanes alternate white
(Music, Graphics) and mid-grey (Shapes, Titles) behind the same coloured clips.
