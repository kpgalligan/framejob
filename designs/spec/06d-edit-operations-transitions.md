# 6d Edit operations — transitions

Continues §6b: the transition ops, moved here whole to keep §6b under its size. The rules
every op shares are §6a.

## Transitions

- **`set_transition {clip, kind|null}`** — Sets `transition_in`. With a kind on a clip that already
  HAS a transition only the `kind` moves — its `curve` and `audio` stay where the person put them
  (format version 7), because a kind chosen from the popup, the menu or MCP must not reset a curve;
  a clip that had none gets a minted one (§11, R5-2). `set_transition_duration {clip, duration}`
  moves the clip so the overlap equals `duration` (subject to the overlap rule). It refuses, in its
  own sentence (§11 #88), on the first clip of a track, and on a duration past the pair's overlap
  limit — half the shorter clip, snapped down — naming the limit and saying when the start would be
  before the timeline or in front of the predecessor (#175).
- **`add_transition {clip, kind?, duration, align="center", ripple=false}`** — Makes an overlap at
  the HARD CUT before `clip` out of the two clips' unused handles and puts a transition on it —
  **nothing else on the timeline moves** and the pair's outer edges stay (§11, R5-3). `align`
  `center` takes half from each side (the odd frame to the incoming clip, and a side that cannot
  supply its share passes it to the other before the total shrinks), `before` takes it all from the
  incoming clip's head, `after` all from the outgoing clip's tail. The duration is snapped DOWN to
  whole frames before the split — snapping two halves separately would lose the odd frame — and then
  clamped: to each side's handle (a media clip's source window; UNBOUNDED for a still, an image,
  text, a shape or a graphic; **0 for a nest's head**, since trimming a nest clip's head moves its contents,
  and the nest's own remaining length for its tail), to the neighbours on the track, and to the
  overlap rule, which is held FIRST to `(A.duration + B.duration) / 3 frames` — the most that rule
  can pass at any split, so the step-down walks the CLIPS and not the caller's number — and then
  searched on that same larger-side reduction path without enumerating frames (D7-2). An
  already-invalid affected track refuses with the overlap rule before fitting. Each trial's two
  extensions are read off the frame GRID rather than taken as a multiple of one frame, because the
  canvas frame is a FALLBACK of 1/30 s at a rate that does not divide the timescale (7 fps) and a
  multiple of it is not a grid position there. A request under one frame of the real grid (in the
  handle form, also under that fallback, which its arithmetic still divides by) is REFUSED FIRST in
  both modes, right after
  the lock check (ripple) or the overlap-rule preflight (handles), naming the shortest duration that
  passes (§11 #88). A request that clamps below one frame of the real
  grid is REFUSED, in a sentence naming the cut, the frames asked for and `ripple: true` as the way
  past it. The incoming clip's `in` moves back by the extension times its speed, and its ACTIONS
  move with it, as do its `text.words` (§11 W-3) — where `trim_start` deliberately leaves actions
  alone, because a transition reveals material in front of a first frame nobody asked to move. A
  graphic's own `in` moves back by the extension too, saturating at 0 (UNBOUNDED like a still;
  §11 G-18·a). A ramped incoming clip's head is read at its base rate and its speed actions move
  with its first frame, so its out point stays; a ramped outgoing clip's tail is read through S∞
  (§11 SR-18 (a), (b)).
  `kind` absent uses the clip's own stored kind if it has one, else `cross_dissolve`; a stored
  transition keeps its style and a new one is minted. **Error** for a non-positive duration, an
  unknown clip, and for not being at a hard cut — naming which of: no predecessor, a gap, an overlap
  that already exists. **`ripple: true` makes the overlap by MOVING instead** (§11, R5-3's
  amendment): no handle is read and `align` is ignored; the incoming clip and every clip at or after
  the cut on every UNLOCKED track slide left by the duration counted in whole frames of the canvas's
  own grid, the incoming clip landing on the grid that many frames back from the cut (§11 #42) —
  `close_gap`'s set, through
  the same shift — so the timeline gets shorter, the outgoing clip keeps every frame and its place,
  and no source window or action moves. The duration is capped at half the shorter of the two clips
  and limited to the greatest whole-frame shift outside exact forbidden overlap intervals, including
  a feasible shift after clips cross; an already-invalid affected track refuses with the overlap
  rule before fitting; a clip on another track pushed into its neighbour gains a minted
  `cross_dissolve` (`close_gap`'s rule); markers do not move; an incoming clip on a locked track, or
  nothing left above one frame, is REFUSED, each in its own sentence. The same hard-cut `Err`s
  apply.
- **`set_transition_style {clip, curve?, audio?, audio_shape?}`** — Sets the transition's easing,
  whether it crossfades the sound and the crossfade's shape (`audio_shape`, format version 29, §11
  AU-115: `plus_3db` — R5-2's constant power, the default — `linear`, `s_curve`, `minus_3db`); an
  absent key KEEPS. A separate op rather than two more arguments on
  `set_transition`, because that one reads an absent `kind` and an explicit `null` as the same thing
  and so cannot spell "keep". It stores on the same terms — any clip, with or without an overlap —
  and a clip with no stored transition and at least one key given gets a minted `cross_dissolve`
  with the style applied. NO key given is an IDENTITY whatever the clip holds, and never mints
  — nothing was asked for, so there is nothing to explain. **Error** for an unknown clip.
