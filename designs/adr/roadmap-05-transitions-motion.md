# Transitions second pass (E1) and motion presets (E2)

- **Status:** Built and proved (2026-09-16/17; instruments 2026-09-19; reader
  reviews 2026-09-20; issue #27 follow-up 2026-09-22). Only a person's
  watched-and-heard checks remain.
- **Original:** `archive/reelcut-roadmap-5.md` (2678 lines) — the full record;
  sections cited below as "orig §x" refer to it.
- **Spec decisions:** R5-1 (effects are closed vocabularies, never a runtime),
  R5-2 (a transition's sound is a constant-power crossfade; minted
  `ease_in_out` + `audio: true`, absent from old files), R5-3 and its
  amendment (`add_transition` from handles, clamped, no third clip moves; the
  `ripple` form moves the timeline instead), R5-4 (motion is a presentation
  term), R5-5 (motion is a pure function of clip time), E2-27 (a
  zero-duration edge is configured but inactive). Later decisions that closed
  this road map's filed defects: D7-2 (bounded transition searches, #25) and
  D7-3 (normalize timing when crossing a frame grid, #26).

## Context

Taken from `archive/reelcut-effects-survey.md` (E1 and E2 of its nine
phases; E3–E9 — tone, filters, looks, adjustment clips, LUT import, voice
effects, background removal — are DEFERRED by the user and not planned
here). E1 made transitions usable for the editor's main job: an overlap at a
Remove Silences cut or a jump between takes needed direction, easing, a
sound crossfade, and a way to be added at a hard cut without hand-trimming.
E2 gave clips In / Out / During motion presets (fade, slide, zoom, spin, pop,
pulse, shake, bounce, drift) that compose with what the clip already is.

Both landed in one commit (`e8028a2`) because they share every file a schema
bump touches: E1 is format v7, E2 is v8. No FFI change and no shader change
in either.

## Decisions

**`Transition` grows `curve` and `audio`; one constructor mints the new
defaults.** File defaults stay `linear`/`false` so a v6 file looks and
sounds exactly as before; everything the core mints from v7 on goes through
`Transition::minted` (`ease_in_out`, `audio: true`) (orig §2, §3a; R5-2).

**Three wipe directions appended to the closed kind enum** (`wipe_left`,
`wipe_up`, `wipe_down`); `wipe` keeps its meaning. The existing wipe shader
branch already handles any direction vector, so only `TransitionCode` grew
(orig §3a, §3g; R5-1).

**Wipes are measured in each layer's own box**, not canvas space. A
canvas-space edge would break the common same-size pair and every nested wipe
(orig §3j, survey §10).

**`set_transition` with a kind keeps a stored curve and audio flag; it mints
only from none.** A kind change from the popup, menu or MCP must not reset a
style the person set (orig §3b, §9).

**`set_transition_style` is a separate op.** `set_transition` treats an absent
`kind` as a clear, so it cannot tell `{clip, curve}` from a clear. The new
op's arguments are non-nullable; `{clip}` alone never mints; it stores on any
clip, overlapped or not, like `set_transition` (orig §3b).

**Easing is applied inside `transition_among`, so `recipe.rs` is untouched.**
Both recipe consumers (the shader and the zoom partner box) want the eased
value; a linear or absent curve is byte-identical (orig §3d).

**The crossfade is a per-stage term in the audio envelope, closed at the
outgoing end.** `Stage` learns its container; `Side` is threaded through
`gain_at → voice_gain → stage_gain`; `crossfade_among` is closed on
`Side::Left` so the outgoing clip's last breakpoint is 0 (the half-open
`transition_among` would read gain 1 there). Every stage's term multiplies, so
a clip in an overlap inside a nest that is itself in a transition gets both
fades — deliberately different from the picture, which takes the clip's own
transition first. Mute, solo, duck and volume keep precedence by multiplying.
Breakpoints are sampled across the overlap at the action step (the law is not
linear). Nothing in Swift changed (orig §3e).

**`add_transition` works in whole frames and splits after snapping.**
Snapping two half-extensions separately loses the odd frame; `center` gives
the odd frame to the incoming clip and passes a side's shortfall to the other
before the total shrinks (orig §3c steps 3–4).

**Handles: a nest's head is 0, not an error; still/image/text/shape are
unbounded.** Trimming a nest clip's head moves its contents, so a nest gives
no head — one "no handle" rule rather than a separate refusal (orig §3c step
2, §9).

**Not at a hard cut is `Err`; no handle is a domain refusal.** The op is
pointed at one cut by a caller who meant it (unlike `roll`) (R5-3).

**The incoming clip's actions rebase with it.** `trim_start` deliberately
leaves actions alone; a transition is not a trim, so a screencast zoom stays
on its source frame (orig §3c step 9).

**The overlap-rule clamp is held to the clips first, then searched.** The
request is capped at `(A.duration + B.duration) / 3·frame` — the most the
overlap rule can pass at any split, so no answer moves (18 144-combination
differential sweep: every differing answer was the unclamped build's error or
swapped pair). The remaining step-down was a frame-at-a-time loop until
D7-2 replaced it with a bounded search (`transition_search.rs`) (orig §12
E1 review R1·2/R1·3; #25).

**Each trial's extensions are read off the frame grid, not as `n·frame`.**
At a rate that does not divide the timescale (7 fps) `Project::frame` is a
1/30 s fallback and a multiple of it is off-grid. Cost accepted: on a
hand-written off-grid project a one-frame request can reveal only the ticks
spent landing on the grid (orig §12 R1·1).

**The `ripple` form (Shift Clips Left) moves the timeline instead of reading
handles.** Whole files butted at a cut have no handles, so the menu beeped;
the user chose that the incoming clip and everything at or after the cut on
every unlocked track slide left (`close_gap`'s set). `align` ignored; capped
at half the shorter clip; a locked incoming track is refused. Lives in
`edit_transition_shift.rs` (orig §12 `5da056c`; R5-3 amendment).

**The menu's sheet re-decides each ripple op against the running project.**
Two chosen cuts can collide (the first shift turns the second cut into an
overlap); a batch built from one snapshot then threw and lost everything.
`shiftingOps` now converts such a cut to `set_transition` and drops declined
ops (orig §12 R3·1).

**Remove Silences never proposes a cut inside a transition: overlap walls,
widened by the overlap's own length, on every unlocked track.** An exact wall
lets a legal ripple cut leave A's tail wholly under B (breaking the half rule,
which `ripple_delete_ranges` does not check). The real cases are one-audio
pairs and handles pulled from already-quiet material — not the fade dipping a
two-voice overlap, which it cannot (`max(cos, sin) ≥ 0.707`) (orig §3f, §9).

**Clip ▸ Transition ▸ None always sends `set_transition` with no kind.** It
must never reach `add_transition`, whose absent kind would ADD a dissolve
(orig §3g, §10).

**`video.motion` is one `Option<Motion>` of three optional slots, last key of
`VideoProps`; all-`None` normalises to `null`.** One spelling of "no motion"
per clip, kept by the patch path, the split rule and (after R2·1)
`paste_attributes` (orig §5a, §12 E2 R2·1).

**Motion is applied only where placement is produced: `recipe.rs`'s layer and
nest-clip frame, never in `evaluate_clip`.** Everything evaluate-driven
(`get_project`, `clip_state`, split, zoom solving, freeze, the inspector)
sees the clip un-moved; everything recipe-driven (render, export, canvas boxes,
partner box, shadow, reflection) sees it move (orig §5d; R5-4).

**Motion is not an animation target.** `set_action_end` refuses the key, and
`evaluate_clip` overwrites the end state's `motion` with the base value at the
JSON `Value` level (not in `clamp_video`, which never sees base props, and so a
malformed motion cannot throw away the rest of the video group) (orig §5e).

**The core deep-merges a motion patch; replace-whole lives at the edges.**
Swift's `MotionProps` writes `NSNull` for each nil slot and the MCP handler
fills omitted slots with `null`. Without it, choosing None would leave the
old slot and beep (orig §5e–§5g, §10).

**Presets are relative to the evaluated props and compose:** scale and
opacity multiply, rotation and offset add, slides are evaluated after scale
and rotation. The tent rule (`in + out > D` scales both to meet) refuses
nothing. Zoom/spin pivot on the VISIBLE (crop) centre by compensating
position. Slide distances put the layer's drawn box just outside the
container edge (the enclosing nest's frozen canvas inside a nest) (orig §5b,
§5c).

**Rotation is reduced so a whole turn is exactly no turn — including a band
just under 360°.** `partnerBox`'s `rotation == 0` guard would otherwise treat
a 360° layer as rotated and drop the dissolve's coverage correction.
`rem_euclid` alone can return 360.0 or `359.99999999999994`; totals within
2⁻¹⁶° of a turn publish 0 (a chosen conservative width, ≤ 5.87e-4 px at a 4K
corner). The reason is the Double guard, not any f32 of degrees (orig §5c,
§12 E2 R1·1 and "Finding 1").

**`motion.rs` never trusts the file.** Durations ≤ 0 and periods ≤ 0 make a
slot inactive, amount is clamped, non-finite results leave the field as
evaluated; no NaN reaches the recipe (orig §5c).

**Motion is unseeded and depends only on clip time** — `shake` is a fixed sum
of sines; preview and export agree byte for byte (R5-5, orig §9).

**Copy ops re-anchor presets to new ends.** A split clears the first half's
`out` and the second's `in` (every splitter routes through `edit_split.rs`);
the same fix was applied to `text.animation`, a defect since phase 4. Freeze
frame and blurred background drop motion; duplicate/detach/paste keep it;
`set_speed`/`rate_stretch` do not rescale it (orig §5e).

**Inspector motion writes always go to BASE props, even inside an action**
(`InspectorBinding.structural` widened) since the core refuses motion on an
end state (orig §5f).

**The name strip draws the STORED durations as wedges without re-deriving the
tent**; overlapping wedges are the signal that presets are too long (orig
§5f).

**Zero-duration In/Out stays legal, stored and inactive, and the UI says so**
("inactive" titles, no wedge, a note) rather than hiding the slot (E2-27,
orig §13).

## What it built — where it lives now

Core (`core/src/`):
- `model.rs` — `Transition { kind, curve, audio }`, `Transition::minted`, the
  13-kind `TransitionKind`.
- `edit_transition.rs` — `set_transition`, `set_transition_duration`,
  `set_transition_style`, `add_transition` (handle form), `TransitionAlign`.
- `edit_transition_shift.rs` — `add_transition_by_shift` (the `ripple` form).
- `transition_search.rs` — the bounded searches (D7-2, since road map 7).
- `transition.rs` — `transition_of_later`, easing in `transition_among`,
  `crossfade_among`.
- `audio.rs`, `audio_crossfade.rs`, `audio_duck.rs` — the envelope, the
  constant-power term and its breakpoints, ducking (split out as tolls).
- `model_motion.rs` — `Motion`, `MotionEdge`, `MotionDuring`, the two enums.
- `motion.rs` — `apply`, the only place presets become placement; called from
  `recipe.rs` twice.
- `actions.rs` (the base-motion restore), `edit_action.rs` (the refusal),
  `props_check.rs` (ranges), `edit_props.rs` (template, normalisation,
  `normalise_and_check_group`), `edit_split.rs` (split rule),
  `edit_time.rs` / `edit_background.rs` (drop motion), `model_query.rs`
  (`source_size`, the collapsed reader), `model_shape.rs` (toll).

Tests: `core/tests/schema_v7.rs`, `schema_v8.rs`, `add_transition.rs`,
`add_transition_edges.rs`, `ripple_transition.rs`, `transition_bounded.rs`,
`crossfade.rs`, `crossfade_edges.rs`, `motion.rs`, `motion_edges.rs`,
`motion_copy.rs`, `motion_zero.rs`.

App (`app/Sources/`): `VideoPane+Transition.swift` (Curve, Crossfade Audio),
`EditorViewController+Inspector.swift` (Clip ▸ Transition, the no-footage
sheet, `shiftingOps`), `SilenceDetector+Walls.swift` (`overlapWalls`),
`Compositor.swift` (`TransitionCode`, `partnerBox`), `MotionProps.swift`,
`VideoPane+Motion.swift`, `EditorViewController+Motion.swift` (Clip ▸
Motion, Preview), `InspectorBinding+Writes.swift` (`structural`),
`TimelineClipDrawing.swift` (wedges, During glyph),
`EditorViewController+ZoomRegion.swift` (the During hint pill);
MCP: `AgentCatalog+Transitions.swift`, `AgentServer+Transitions.swift`,
`AgentServer+Motion.swift` (hand-built `motionPatchArg`).

Proofs (`tools/proof/`): `e1_proof.py` (two instances: the build and a v6
reference build), `e1_chrome.py`, `e2_proof.py`, `e2_chrome.py`,
`transition_sheet_probe.py`; described in `tools/proof/README.md` §
"Transitions and motion".

## Known limits

Still true of the current code:
- A different-size pair's wipe does not meet at one edge (each layer's own box).
- A video pair with DETACHED audio has `enabled.audio` off, so `audio: true`
  does nothing; the detached clips need their own transition.
- Fades to colour fade the layer's own RGB: a picture-in-picture clip fades to
  a black box.
- A rotated or spinning partner disables the dissolve's coverage correction
  (`Compositor.swift` `partnerBox` guard) and dips darker mid-dissolve.
- Text slides from half a canvas beyond the edge (the core never has text's
  measured size).
- A `during` preset restarts at every cut, so Remove Silences on a `pulse` or
  `drift` clip jumps at each cut; a split inside an arrival/departure window
  compresses the kept half through the tent; a freeze frame taken mid-motion
  jumps to the un-moved placement.
- A canvas drag begun mid-motion starts from the base box; a zoom region drawn
  on a `during` clip is solved without the motion (a hint pill says so).
- A shadow or reflection can be on canvas at a slide's first frame while the
  layer is off it (the box measured is the layer's own).
- Presets have no parameters beyond duration, amount and period, and no path
  drawn on canvas.
- `paste`'s payload clips are stored whole: not range-checked and not
  normalised (pre-E2, `paste`'s own door; `edit_props.rs` doc at
  `normalise_and_check_group`). A clip holding an out-of-range value then
  makes every `set_video` on it an `Err`, so a Clip ▸ Motion batch over it
  lands nothing.
- AVFoundation does not apply a mix input's first volume point for ~12 ms:
  the first 25 ms of an incoming clip export at about half scale whatever the
  ramp says, and the same burst appears at a muted hard cut — host behaviour,
  not the crossfade.
- The undo name for the same op differs by door ("Set Transition" from the
  menu/tool, "Add Transition" from the sheet; "Set Motion" / "Motion In" /
  "Video Properties") — each names its path, by convention.

Measured and rejected (do not re-try blind):
- Exact (unwidened) overlap walls — a legal ripple cut then leaves a clip
  wholly under its neighbour; the shipped proof rows could not see it because
  the length filter hid the pieces, so `e1_proof.py` §6(c) was added.
- An explicit clamp of the incoming start at tick 0 alongside the ceiling —
  unreachable once the ceiling is in (revert scored 9/9); deleted.
- Deciding the rotation band in radians (the renderer's real precision) —
  3.64e-6°, 4.19× narrower, fails a `during` 1.0e-5° under a turn.
- Clamping `shift_clips` to the grid in the ripple form at non-dividing
  rates — no single delta keeps many clips on-grid; it is the ripple family's
  posture, as `close_gap`'s is.
- Honouring a track lock in the handle form — no edge op that moves only its
  own clip's edges checks the lock (`trim_start` does not); only the ripple
  form refuses.

## Open items

- Person checks, E1 (§4g) and E2 (§6g) — tracked in #54.
- ~~`e2_proof.py` cannot see a spin's DIRECTION or a slide inside a nest against
  the nest's canvas over MCP (core tests pin both; the MCP rows are owed) —
  tracked in #78.~~ Struck (issue batch B21): §4 reads a spin's direction off a
  cropped card and §5 a slide inside a nest after `set_canvas`, each made to fail
  by a core mutant (`tools/proof/README.md`, B21).
- AVFoundation's first-~12 ms mix point at a clip's start (a lead-in ramp is
  the candidate fix) — tracked in #87.
- `paste`'s payload clips are neither range-checked nor normalised — tracked
  in #62.
- ~~A sub-frame `add_transition` duration refuses with "the 0 frames asked
  for" — tracked in #88 (the core's refusals' sentences).~~ Struck (issue
  batch B12): it refuses as too short, naming the shortest duration that
  passes (spec §11 #88).
- `core/src/actions.rs` is at 592 lines; the plan's pre-agreed toll is to move
  `clamp_video` and helpers to `actions_clamp.rs` before its next addition —
  see `designs/adr/core-file-history.md` "Named next cuts".
- `add_transition`'s handle form does not advance `graphic.in` for a graphic
  incoming clip — road map 10's G2b item, tracked in #72.
- Issues #25, #26, #27 filed from this road map are CLOSED (D7-2 and D7-3 in
  `e1411be`; E2-27 in `71f3a8d`).

## Where to look in the original

- orig §0–§1 — the two phases in a paragraph each; preconditions, gates, wave
  shape.
- orig §2 — R5-1..R5-5 as first written.
- orig §3a–§3j — E1 spec: schema v7, the two new ops, `add_transition`'s
  eleven steps, easing, the crossfade envelope, overlap walls, Swift, MCP,
  tests, limits.
- orig §4 — E1 build: tolls T0a–T0c, lanes, proof tables (§4e), mutants,
  person checks (§4g).
- orig §5a–§5h — E2 spec: schema v8, every preset number (§5b), composition /
  pivot / tent / guards (§5c), where applied and what does not see motion
  (§5d), model rules and the copy-op table (§5e), Swift, MCP, limits.
- orig §6 — E2 build: tolls T0d–T0f, lanes, proof tables (§6e), mutants,
  person checks (§6g).
- orig §8 — the tunable constants and where each lives.
- orig §9 — where the plan differs from the survey; §10 the plan's own
  review.
- orig §12 — the record: the three commits, the four instruments and their
  25 mutants, three strengthened fixtures, two host limits (the 12 ms mix
  point; the tones are 2 986 400 ticks, not 5 s), the E1 reader review
  (R1·1–R4·2, the sceptic's sweeps) and the E2 reader review (R1·1–R4·4, the
  four `6dda2c7` nits, the rotation-band restatement).
- orig §13 — issue #27, zero-duration motion presentation.
