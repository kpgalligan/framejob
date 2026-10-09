# Spec §11 — decisions: Mattes (#240, road map "mattes")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/mattes.md`, and the
original, `archive/mattes.md`, holds each phase's record (MT0–MT5). MT-1..MT-6 were recorded in
MT0, before any code, and MT-6's choice of route was filled from MT0's spike
(`tools/proof/matte_spike/`); MT-7 (the chrome) was recorded at MT4's start, before its code.
They are not G- decisions: a matte is a track relation the compositor draws for any clip, not a
graphics decision (road map 10's own plan: "Mattes are compositor features",
`designs/adr/svg-motion-plan.md`). The video-input half of #240 is #251, and nothing here decides
it.

- **MT-1 — A matte is a track relation in a closed vocabulary, drawn by the one compositor; R5-1
  and G-1 stand.** A track's `matte` is `none`, `alpha`, `alpha_inverted`, `luma` or
  `luma_inverted`, set by `set_track {matte}` (`none` switches it off). A matte track's clips are
  never drawn on the canvas; at each instant what they show cuts every layer the track directly
  behind draws (MT-2). Any clip that draws can be one — text, shape, image, graphic, video, nest.
  Nothing is a package, a shader or an expression, and a graphic on a matte track is called with
  the same arguments and keyed the same way as anywhere (G-5, G-9 untouched). A clip is a matte
  only by the track it is on: moved off, it is ordinary; the tracks `paste` adds are ordinary;
  `duplicate` keeps its track. Persisted as `tracks[].matte`, written only when not `none` — the
  model's first `skip_serializing_if`, so every older file and every ordinary track round-trips
  byte for byte and the reader's default is the same answer. `RC_FORMAT_VERSION` 14, no migrate
  step. The video half of #240 is #251 and nothing here decides it.
- **MT-2 — What a matte cuts, and when it cuts nothing.** Its target is the track directly behind
  it in its own container (the timeline, or one nest's own tracks) when that track is not itself
  a matte track. With no such track (the back-most track, or a matte behind it) a matte cuts
  nothing and its clips still draw nothing. Where the matte track shows nothing at an instant — no
  clip, the track hidden, a clip's video off — the track behind shows uncut (owner, 2026-10-07,
  choice 5). Read per instant and per pair of tracks: no clip names another, so split, move,
  delete, paste, nest and undo cannot break a link; `add_track`, `move_track` and `remove_track`
  change which track is behind, visibly. A matte track's clips sound as on any track, and Mute
  Audio silences them (owner, 2026-10-08, O1): a matte is a picture rule, like Hide Video.
- **MT-3 — The four modes, and where the cut is applied.** At a pixel the matte's composite —
  premultiplied, in encoded sRGB like every stage of the compositor (§7.5) — gives: `alpha` its
  alpha a; `alpha_inverted` 1 − a; `luma` the Rec. 709 luma (0.2126, 0.7152, 0.0722, the weights
  the shader's saturation uses) of its premultiplied colour, so transparent counts as black;
  `luma_inverted` 1 − that. The value multiplies the matted layer's coverage at the fragment
  stage's step 7, beside the corner radius and the nest clip rectangle, sampled at the fragment's
  own canvas position. So the matted clip's own drop shadow follows the cut-out shape (its
  silhouette pass runs the same stage; owner choice 6), and its reflection is cut by the matte
  where the reflection lands — under an alpha matte, a reflection outside the window is gone — as
  the nest clip rectangle already cuts one (owner, 2026-10-08, O10). The outgoing half of a
  dissolve multiplies its partner's cover by the same value — on one matted track both halves are
  cut by the same matte — which keeps a dissolve under a soft matte exact. `TrackMatte`'s
  declaration order is a shader discriminant (`none` 0 to `luma_inverted` 4): append only.
- **MT-4 — A matte clip's own properties (owner, 2026-10-07, choice 6).** Its placement, crop,
  corner radius, opacity, colour, chroma, filters, spotlight, obscured regions, motion presets,
  actions and transitions with other matte clips shape the matte, because it is drawn by the
  ordinary layer pass. Its blend mode, drop shadow and reflection do nothing: the CORE emits a
  matte layer with `blend: "normal"`, `shadow: null` and `reflection: null`, the recipe's second
  deliberate override of model values after a transition's `normal` (§7.3). The inspector shows
  the model's values and says they are not drawn (MT-7). Amends G-10's "blend … apply" for a
  graphic on a matte track.
- **MT-5 — Mattes in nests.** The rule holds in every container. Walking from a layer's own track
  outward through the nest clips it is inside, the first level whose track is a matte track makes
  the layer draw into that matte (or nowhere, when the matte has no target or cuts no layer at
  that instant), and no level outside that applies to the layer; every level inside it whose
  track is a matte's target cuts the layer, each matte multiplying in. One matte is keyed by (the
  ids of the nest clips enclosing its track's container, outermost first — the instance path's
  prefix — and the matte track's id), so two clips showing the same nest at one instant (a split
  nest clip in a dissolve) each have their own matte. A nest clip on a matte track makes its whole
  composite the matte (a matte inside it included), and a nest clip on a matted track has every
  layer it draws cut — at a soft edge, overlapping inner layers show through each other, the
  recorded limit of nest opacity (§7.3). `nest` puts the nest clip on the front-most selected
  track that is not a matte track (the front-most when all are), and gives a nested track its
  source track's matte only when the nested track directly behind it is the copy of that matte's
  target. A selection that takes a matte's clips without its target, beside other clips, is
  nested as asked: the matte clips draw inside the nest and the picture changes; undo restores
  (owner, 2026-10-08, O9). `unnest` lines up the nest's front-most NON-matte track (the
  front-most when all are) with the nest clip's track, so carried matte tracks land on the tracks
  in front of it and nest-then-unnest restores the picture; it makes no track a matte, so a matte
  clip with no track in front lands on a new ordinary track, as any clip refused on the way out
  does.
- **MT-6 — How the compositor draws a matte.** Before the destination pass opens, each matte the
  recipe lists (`mattes`, deepest container first) is drawn by the ordinary layer pipelines into
  a destination-sized `bgra8Unorm` target, so a matte never suspends the destination pass as a
  shadow does. Each distinct set of mattes a layer is cut by is resolved into one
  destination-sized `r8Unorm` coverage texture, cleared to 1, each matte's mode multiplied in by a
  full-frame pass. The layer stage samples it at `texture(1)` at the fragment's
  canvas-normalised position, so Preview Quality, a shadow's canvas-sized silhouette pass, a
  reflection and every export read one coverage. An unmatted layer binds the existing 1×1 white
  placeholder at `texture(1)`, chosen by MT0's spike (2026-10-08; Apple M2 Max, macOS 26.5.1,
  `pmset` powermode 0, on AC power; 200 frames a sample, three interleaved runs, the median of the
  runs' medians): one full-bleed unmatted layer (S1) cost 0.014 ms more than the tree's shader
  with the placeholder route and 0.019 ms more with the function-constant route at 1920×1080,
  against a V0-against-V0 noise floor of 0.038 ms, and 0.052 ms and −0.003 ms more at 3840×2160,
  against 0.002 ms — the placeholder within its bound plus the noise at both sizes (0.02 ms at
  1080p, 0.08 ms at 4K). With it a matte cost (S3 − S2, the text as an alpha matte) −0.082 ms at
  1080p, a negative figure larger than that size's noise floor, so the 1080p series do not
  resolve a matte's cost, and 0.066 ms at 4K; two mattes in one coverage (S4 − S2)
  0.040 ms and 0.542 ms, within the 0.50 ms and 2.00 ms budget. Risk accepted: at 4K every
  unmatted full-bleed layer pays 0.05–0.07 ms for the sample (S1: 0.052 ms over the tree's
  shader; two layers, S2: 0.887 ms with the placeholder against 0.752 ms with the function
  constant), for one pipeline per layer
  specialization instead of two. `LayerUniforms` stays 104 floats. Targets are pooled per destination
  size and allocated on the first matted frame (at 3840×2160, 33.2 MB per matte and 8.3 MB per
  coverage). The deferred E5 and E9 take the next free texture slots.
- **MT-7 — The chrome (owner, 2026-10-08, O2–O8).** No fifth header toggle and no shortcut. Set
  by Track ▸ Matte ▸ Off / Alpha / Inverted Alpha / Luma / Inverted Luma on the current track,
  and by the same submenu in the track's context menu after Solo, each checked for the track's
  mode; undo "Track Matte"; re-choosing the current mode is an identity. The header shows a
  tag by the name — "Matte · Alpha", "Matte · Inverted Alpha", "Matte · Luma", "Matte ·
  Inverted Luma" — in the primary label colour over a faint accent tint, so its legibility never
  depends on the accent the person picked; dimmed (muted words, a fainter tint) and reading
  "Matte · nothing behind" when the track has no target (MT-2); on its own line under the name when the row leaves room above the toggles (every Medium
  and Large row, and the Small video row), else on the name's line, right-aligned, the name
  clipped before it — and there, when its full words would leave the name less than 40 pt, the
  tag reads "Matte" alone. A matte track's clips are drawn at half opacity with a dashed outline,
  and an accent bracket joins its lane to
  the track below when it has a target. Every Clip sub-tab opens with a note when every selected
  clip sits on a matte track and those tracks share one mode: "Matte for the track below
  (<mode>). Not drawn: its blend mode, drop shadow and reflection have no effect.", or, when none
  of those tracks has a target, "Nothing is behind this matte track, so it cuts nothing."; every
  control stays live, its values kept for when the track stops being a matte. On the canvas a
  matte clip is the topmost hit inside its box, selected and dragged like any clip.
- **MT-9 — The matte pool keeps what recent frames used, and no cap drops a picture (#253;
  owner, 2026-10-08).** Amends MT-6's pooling sentence.
  - **Planning.** A frame's mattes are planned before any is drawn (`MattePlan`). Each cut set
    is resolved as soon as the last matte it names is drawn. A matte's `bgra8Unorm` composite
    goes back to the pool once every cut set naming it is resolved, so a later matte in the same
    frame draws into it. A frame therefore holds as many composites at once as mattes are live
    (one, for any number of mattes that each cut their own set). It also holds one `r8Unorm`
    coverage per distinct cut set, and those all outlive the destination pass.
  - **Between frames.** A frame is one `render` call. The pool keeps, of each kind, as many
    targets as the most any of the renderer's last 30 frames held at once
    (`MattePool.keepFrames`), and releases the rest when a frame ends. A frame with no matte
    counts as holding none, and a destination size change still empties the pool. At 3840×2160,
    ten matte pairs in one frame hold 33.2 MB + 10 × 8.3 MB = 116.1 MB, where MT-6's pool held
    414.7 MB.
  - **No cap.** A frame that needs more targets gets them, and a target Metal cannot make fails
    the frame as before (`MatteError.noTarget`). A renderer that stops drawing keeps what its
    last 30 frames held until it draws again or is released with its player item or export.
