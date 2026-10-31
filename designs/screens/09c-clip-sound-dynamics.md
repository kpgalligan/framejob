```json screen
{
  "title": "Clip inspector — Sound, the Gate and De-esser sections",
  "project": "dynamics",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:tone"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "sound", "section": "audio.gate"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Hold"}]
}
```

The `dynamics` fixture's audio clip — "toneA.m4a" on the Music track — on the
Sound sub-tab, scrolled to the Gate section (road map "audio" AP4, spec §11
AU-48): where the person turns the pauses between phrases down and tames
sibilance, and sees where the clip's measured loudness puts each threshold.
The clip carries the gate and the de-esser at their defaults.

The preview is the black canvas (the clip has no picture). The timeline has one
track, Music, holding the selected "toneA.m4a" clip with its waveform band; the
timeline bar reads "toneA.m4a" over "Music · audio".

The inspector: the name field "toneA.m4a" over "audio · 00:00:04:29", the
actions row and lane, the two sub-tabs with Sound selected, then the pane
scrolled so the GATE section is at the top, open, its summary "−10 dB" beside a
Reset button. A ticked "Gate pauses" checkbox, then six rows, each a slider and
a field with a quick-pick chevron: Threshold "−10 dB", Ratio "4.0:1", Range
"20 dB", Attack "1 ms", Hold "50 ms" and Release "100 ms" (a wider field). Two
read-outs follow: Status "Opens above −31.8 dBFS" and Loudness "−21.8 LUFS" —
the threshold 10 dB under the clip's loudness. Below, the DE-ESSER section,
open, its summary "6.0 kHz" beside a Reset button, and its ticked "Reduce
sibilance" checkbox at the foot of the capture; its Frequency, Threshold and
Range rows and its own Status and Loudness read-outs lie below the captured
height.

In the light capture the inspector is white with black labels and the slider
fills blue; in the dark one the panel is near-black with white labels. The
section headers are light-grey bars in the light capture and dark-grey ones in
the dark.
