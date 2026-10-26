# Spec §11 — decisions: Speed ramps, the presets onward (#340)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the SR- series of [`speed-ramps.md`](speed-ramps.md) and
[`speed-ramps-2.md`](speed-ramps-2.md), so a citation never has to say which file; the first
names the condensed record and the original, and what stands beneath every SR- decision. This
file is new because `speed-ramps-2.md`, at 468 lines, would pass the spec's ~500-line split rule
with these entries. SR-23..SR-25, #340's speed ramp presets, and the Amended-by lines on SR-21
(e) and (g), were recorded before its code. The owner's design answers (2026-10-24): the four
shapes Ramp Up, Ramp Down, Speed Dip and Speed Burst, a dip and a burst being two Speed actions
in one undo step; the span the timeline range when one is set inside the selected clip, else
the clip's whole length; the controls the target rate (×0.1–×1000), the curve (ease in-out by
default, or linear) and, for a dip and a burst, how much of the span the hold at the target
takes. A later change records its rule as a new entry here (SR-26 on) or as an Amended-by line,
before its code.

- **SR-23 — A speed ramp preset is one core op, `add_speed_ramp`, making ordinary Speed
  actions (`end.speed`, SR-1, SR-10) in one step; the core places it, refuses it and reads
  every rate.**
  - **(a) The arguments.** `clip`, `shape` (`ramp_up`, `ramp_down`, `speed_dip`,
    `speed_burst`), `rate`, and the optional `from`, `to`, `curve` and `hold`. Every time is
    CLIP time, as `add_action`'s `at` is. `from` and `to` are both absent, meaning [0, D) for
    the clip's duration D, or both present; each is snapped to the frame grid.
  - **(b) The base.** b is `rate_in_force(clip, from)` before the edit: the rate the clip plays
    at `from`, which after an earlier speed action is that action's end rate and not
    `clip.speed`.
  - **(c) The shapes.** Ramp Up and Ramp Down make ONE action [from, to) ending at
    `{speed: rate}`: it ramps from b and holds after. Speed Dip and Speed Burst take
    r = max(snapped_down((to − from)·(1 − hold)/2), one frame), with `hold` clamped to
    0…`HOLD_MAX` (0.9) and defaulting to `HOLD_DEFAULT` (0.5), and make TWO actions:
    [from, from + r) ending at `rate`, and [to − r, to) ending at b. The span between them holds
    the target; at hold 0 the two abut. The curve, `ease_in_out` when absent, is every new
    action's. The whole op is one `Applied`, so one undo step.
  - **(d) "Mirror" is about the base rate.** Up and Burst need rate > b; Down and Dip need
    rate < b. A time mirror would have to change the clip's own `speed`, and a preset makes only
    Speed actions.
  - **(e) An overlapped action is a refusal naming it** (`action_overlaps`), never a
    replacement: the action lane refuses rather than repairs (spec §5.4), and a replacement would
    drop the action's other keys. The overlap is tested ONCE, over the whole span [from, to),
    for all four shapes, so an action inside a dip's or a burst's hold gap is refused: the gap
    must hold the target.
  - **(f) Errs, in this order:** `require_clip`'s; a clip that is not a media clip,
    `read_speed_end`'s sentence; `rate must be a positive number, not {r}` (a positive rate is
    then clamped to ×0.1–×1000); `from and to are given together or not at all`;
    `from must not be negative, not {from}`; `to must be after from, not {to} against {from}`
    (after snapping); `hold is for speed_dip and speed_burst only`.
  - **(g) Refusals, in this order:** `to` past D, `action_past_end(clip, from, to − from, D)`;
    the overlap (e); a dip or a burst over less than two frames, `{a speed dip|a speed burst}
    needs a span of at least two frames ({2f} ticks); {from} to {to} ticks is {len}`; the
    direction (d), `{a ramp up|a ramp down|a speed dip|a speed burst} needs a rate
    {above|below} ×{b}, the rate clip {c} plays at {from} ticks into it; ×{rate} is not`; the
    overrun (SR-2), `{name} to ×{rate} would read clip {c} {over} ticks past the end of its
    media; the largest rate that fits is ×{fit}`, or, when nothing fits, ending `, and no rate
    {above ×{b}|down to ×0.1} fits`. The fit is R1's affine solve over the shape's own clip
    (`largest_fitting_rate`, which `largest_fitting_end_rate` now delegates to, its results
    unchanged), floored to 0.001 and below `rate`, stepped down to ⌊b·1000⌋ + 1 thousandths for
    Up and Burst and to ×0.1 for Down and Dip.
  - **Why:** the core decides (spec §7, D2-1): b, the overlap and the fit are all the core's
    reads, so a preset composed of `add_action` + `set_action_end` in Swift would have to read b
    and solve the fit itself; `add_zoom_action` is the precedent for one op over a sequence. The
    clip keeps its slot (SR-2) because every new action is an ordinary Speed action.
  - Risk accepted: a dip or a burst whose hold is shorter than one frame each side still takes a
    frame each side (r is at least one frame), so at hold near `HOLD_MAX` on a short span the
    hold is a little shorter than asked.
- **SR-24 — The sheet: Clip ▸ Speed Ramp…, after Speed…, no key.**
  - **(a) The item** is live iff exactly one clip is selected and that clip `hasSourceBound`
    (a media clip), and puts up `SpeedRampSheetController`. No key equivalent: a bare letter is
    `keyDown`'s (the comment at Remove Silences…). Spec §9 lists it.
  - **(b) The span** is `document.inOutRange`, as clip time, when it lies inside the clip
    (start ≥ the clip's start, end ≤ the clip's end, end > start); otherwise none, the whole
    clip.
  - **(c) The controls.** A shape popup opening on Speed Dip, the shape that fits a clip already
    playing its whole media; choosing a shape sets the rate to its default (×2 for Up and Burst,
    ×0.5 for Down and Dip). A rate field over `ReelSpeed.limits` with `SpeedSheetController`'s
    presets as a pull-down. A curve popup, Ease In Out (the default) or Linear. A hold popup —
    None, 25%, 50% (the default), 75% — disabled for Up and Down.
  - **(d) The readout** runs one trial `applying` of the op on `editedProject` on every change.
    Line 1 is "{Shape} · the range {tc} – {tc}" or "{Shape} · the whole clip {tc} – {tc}" in
    timeline timecode. On an applied trial line 2 is "×{b} → ×{e}" or
    "×{b} → ×{e}, held {s} s, → ×{b2}": b is `clip_state`'s `speed` at the span's start before
    the edit, e and b2 the new actions' `end.speed`, the hold the gap between them, every rate
    printed with `%g` and the hold with two decimals. On a refused or thrown trial line 2 is the
    core's sentence and Apply is disabled. No rate is computed in Swift (D2-1).
  - **(e) Apply** asks the ×12 question once (`SpeedAudioDrop`) when the preset takes a clip
    with sound across ×12, then commits the op as one undo step named for the shape ("Ramp Up",
    "Ramp Down", "Speed Dip", "Speed Burst").
  - **Why:** the owner's answers fix the shapes, the span and the controls; the readout is the
    Speed sheet's rule (D4-6), the core's answer read off a discarded handle, so the sheet shows
    a refusal before it applies.
  - Risk accepted: the sheet opens on one clip only; a preset over several clips is several
    applies.
- **SR-25 — The mirror is an op tool, `add_speed_ramp`, not `add_action` + `set_action_end`.**
  An `opTool` row in `AgentCatalog+Actions.swift` whose prose covers CLIP time, the four shapes,
  b, the hold, the refusals, `new_actions`, and `audio_left_out` / `audio_note`; a declaration
  publishes `rate`'s ×0.1–×1000 as `set_speed.rate`'s does. Its handler names Clip ▸ Speed
  Ramp… as its UI path, and the answer carries the new actions' ids and, when the preset takes a
  clip with sound above ×12, `audio_left_out` and `audio_note` (SR-21 (e)). The gate and the
  parity check need no change: they read the published schema and the core's table.
  - **Why:** the pairing is two or four undo steps where the sheet makes one, and Swift would
    have to read b and solve the fit; one op is one call, one step and the core's own refusals.
- **SR-26 — A ramped clip's rate is drawn as a line across its action lane (#339), amending
  SR-1's risk line.** The core answers the profile: `rc_project_source_map`'s `rate`, a list of
  `[clip_tick, rate]` at every piece edge and 33 samples across each ramp piece (its edges
  included, 32 chords), on a ramped clip only; a constant clip's answer is unchanged. Swift maps
  it to pixels and computes no rate (SR-21 (b)).
  - **(a) The scale** is linear in rate, from the clip's own slowest to its fastest over
    [0, D], the fastest at the top. The line is drawn only when the rate moves inside the clip:
    a constant clip, and a ramped clip whose rate never moves, draw exactly as before.
  - **(b) Where.** The timeline at track heights M and L (not S), the lane inset 2 pt top and
    bottom, after the bands; the Clip tab's lane inset 4 pt (the bands' rows), after the bands.
    Both through one painter (`RateGraph`, CI-4's shared-painter rule).
  - **(c) The look.** White at 1.25 pt over a black 50 % under-stroke at 2.75 pt, round joins,
    clipped to the lane. A selected Speed band drops its ease stroke while the line is drawn.
  - **(d) Nothing else moves:** no interaction, label, op, tool or menu change.
  - **Why:** the band shows where a ramp is, not what the rate does across it; a line read off
    the core's own profile shows the shape of every ramp, held span and step at once without a
    second source of truth.
  - Risk accepted: the scale is the clip's own, so a ×1→×1.1 ramp looks as tall as ×1→×10; the
    figures stay the Speed section's.
