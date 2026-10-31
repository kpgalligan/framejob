```json screen
{
  "title": "Clip inspector — Sound, the EQ section",
  "project": "eq",
  "steps": [
    {"call": "set_selection", "args": {"clips": ["$clip:tone"]}},
    {"call": "set_playhead", "args": {"t": 1500000}},
    {"call": "select_inspector_tab",
     "args": {"tab": "clip", "sub_tab": "sound", "section": "audio.eq"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "expect": [{"capture": "inspector", "visible_text": "Slope"}]
}
```

The `eq` fixture's audio clip — "toneA.m4a" on the Music track — on the Sound
sub-tab, scrolled to the EQ section (road map "audio" AP3, spec §11 AU-36,
AU-38): where the person shapes the clip's tone — cutting rumble, mud or hum and
lifting presence — and sees the response they asked for. The clip carries
Rumble Cut (a 24 dB/oct high-pass at 80 Hz), Presence (+3 dB at 4 kHz), the hum
notch at its defaults (60 Hz and three harmonics above it, 30 dB deep) and the
left channel picked.

The preview is the black canvas (the clip has no picture). The timeline has one
track, Music, holding the selected "toneA.m4a" clip with its waveform band; the
timeline bar reads "toneA.m4a" over "Music · audio".

The inspector: the name field "toneA.m4a" over "audio · 00:00:04:29", the
actions row and lane, the two sub-tabs with Sound selected, then the pane
scrolled so the EQ section is at the top, open, its summary "2 on" beside a
Reset button. Its first row is the drawn response, a well the width of the
row: faint lines at 100 Hz, 1 kHz and 10 kHz and at ±12 dB, a stronger 0 dB
line across the middle, and the curve in the accent blue — pinned to the
bottom edge at the left, rising steeply through the high-pass, dipped by four
narrow notches at 60, 120, 180 and 240 Hz, flat through the middle and lifted
in a gentle bump near 4 kHz. Under it an unticked "Bypass" checkbox, then three
buttons, "Rumble Cut", "De-mud" and "Presence". Then the slots: "High-pass"
ticked, with Frequency "80 Hz" in a field with a quick-pick chevron and Slope
"24 dB/oct" in a popup; "Low shelf" unticked, its Frequency "100 Hz" and its
Gain slider and "0.0 dB" field dimmed. The bands, the high shelf and the
low-pass continue below the captured height.

In the light capture the inspector is white with black labels and the response
well white with light-grey lines; in the dark one the panel is near-black with
white labels and the well dark grey. The curve is the accent blue in both.
