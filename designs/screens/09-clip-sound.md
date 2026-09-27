```json screen
{
  "title": "Clip inspector — Sound",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:tone"]}},
    {"call": "set_playhead", "args": {"t": 1500000}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Gain"}]
}
```

An audio-only clip — a music file, "toneA.m4a" — is selected. It has no picture,
so the Clip tab offers only two sub-tabs and opens on Sound: where the person sets
how loud the clip plays and how it is treated.

The preview shows the frame under the playhead with no selection frame on it. In
the timeline the toneA.m4a clip is outlined and the bar reads "toneA.m4a" over
"Music · audio".

The inspector: the name field "toneA.m4a" over "audio · 00:00:04:29"; the actions
row and lane; two sub-tabs, Sound (selected) and Clip. The VOLUME section is
open, summary "+0.0 dB": a Volume slider with "100%", "Gain +0.0 dB", an
unchecked "Mute" checkbox, and a "Normalize" button. Closed below: FADES "none",
DUCKING "off", NOISE REDUCTION "off", COMPRESSOR "off" and MIX "centre".

In the light capture the inspector is white with black labels; the Volume slider
has a blue fill and a black knob, the value box, the Mute box and the Normalize
button are white with grey borders, and the section headers are light-grey bars.
