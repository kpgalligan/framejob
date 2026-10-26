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
takes. A later change records its rule as a new entry here (SR-27 on) or as an Amended-by line,
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
- **SR-27 — A speed or ramp edit of a clip with sound re-times, in the same undo step, the
  caption clips over it (#341), amending SR-20 (g) and rule O.** The owner's answer
  (2026-10-25): option B, "Re-time automatically", for a person and an agent alike.
  - **(a) The gate.** Only an edit holding `set_speed`, `rate_stretch`, `add_speed_ramp`,
    `set_action`, `remove_action`, or a `set_action_end` whose patch names `speed` (any value)
    re-times; every other edit is untouched. Synchronize Audio's `set_speed` rides a `move_clip`
    and is not wired: captions following a move are a later road map's.
  - **(b) The edited clips.** The edit is applied to the container it addresses; a clip is edited
    when it is in both answers, speaks before the edit (a `media` source, not reversed, media
    with sound, its audio enabled: `Transcriber.jobs`' eligibility) and its source map's points
    or its start differ between the two handles.
  - **(c) The captions.** A caption track is one named "Captions"/"Captions N"
    (`CaptionLayout.isCaptionTrackName`), holding at least one clip, only text clips, and not
    locked. A caption belongs to the edited clip whose old span `[start, start + duration]`
    holds it wholly, the lowest id when two do; a straddling caption is left alone. A nest is
    never crossed: a scoped edit reads only its own container.
  - **(d) The mapping.** Each time goes clip tick → the old map's source → the new map's clip
    tick, through `SourceMap` alone (no rate in Swift, D2-1), into the new window
    `[sourceIn, sourceIn + sourceLength]`. A subtitle whose source lies wholly outside the window
    is removed, else both ends map with the source clamped into it. A word page keeps the words
    whose source start is before the window's end and the prefix of its content through the last
    kept token (W-2); none kept removes it. Start and end snap to the frame grid; an end not after
    its start removes the caption. Word times are written relative to the new start, unsnapped
    (`set_text` snaps them). A word time at or after its page's old start is written at least 0;
    one before it (W-3's "already said") keeps its mapped time.
  - **(e) Cut back (sub-rule 3).** On its track a re-timed caption is cut back to abut a caption
    that was not re-timed, at its place after the edit; one whose new start lies inside such a
    caption, or left under a frame, is removed.
  - **(f) The ops**, appended after the edit's own in one step: one `delete` of the removed; a
    one-frame stub (`trim_end`) of every re-timed caption whose start or end changes, before any
    move; `move_clip`s, those moving earlier ascending, then those moving later descending;
    `trim_end` to the new ends; `set_text` only where words or content changed. `trim_start` is
    never used (it rebases words, W-3). An unchanged caption gets no op.
  - **(g) The check.** The whole list is tried, and every planned start, duration and word count,
    and every removal, is read back; on any mismatch the edit goes alone, as before SR-27.
  - **(h) The doors.** The Speed and Speed Ramp sheets and the inspector (`SpeedAudioDrop.commit`),
    the timeline's and the Clip tab's live gestures at their end (the captions jump at mouse-up),
    ⌫ Remove Action, and the six op tools. The step is named "<edit> and Re-time Captions" when
    anything re-times; an agent's answer gains `captions_retimed` and `captions_removed`, each
    only when non-empty. No op, argument, tool, menu item or format changes. A door that asks the
    ×12 question first plans again on Set Speed when the document changed while the question was
    up.
  - **(i) Newly revealed source** (sub-rule 2) is left uncaptioned: Generate Captions again
    captions it.
  - **Why:** captions drifting off the speech after every speed edit made the person regenerate
    them, losing any hand edits to their text; the map the core already answers places them again
    with no second rate rule, and the trial-and-read-back keeps a plan the core would not take
    from ever reaching the document.
  - Risk accepted: a caption made from another clip's speech that happens to lie inside the
    edited clip moves with it; transcripts, fillers and silences are not re-timed (they read the
    current map); the person check is `docs/manual-checks.md`'s CRT-1.
- **SR-28 — Every constant Keep pitch off time-scaled media segment's audio is rendered offline
  as a ramp's is, and played as one ×1 segment (#334, option (a)), amending SR-6, SR-12 and
  SR-20 (b).** The owner's answer (2026-10-26): option (a).
  - **(a) The core's rule.** A constant (not ramped) clip's AUDIO plan segment carries
    `"ramp": {"keep_pitch": false, "map": [[0, in], [D, in + sd]], "constant": true}` exactly
    when its source is a `media`, its Keep pitch is off, D > 0 and D ≠ sd, where `in`, `sd` and D
    are the segment's own `source_in`, `source_duration` and `duration` (lifted: a nest clip's
    tail cut shortens D and sd alike, a reversed clip's `in` is its own). Its `pitch` stays
    `off`; the ×12 rule and the still exclusion come first, as before. The video segment is
    unchanged. A ramped clip's `ramp` object carries no `constant` key.
  - **(b) Swift renders and plays it exactly as SR-6 and SR-12 say:** `RampAudioRenderer`
    version 4 unchanged, the same file name rule, owners, serial queue, cache ledger and prune;
    a failure not retried; every export waiting for it or failing `rampAudioFailed`; the segment
    silent until its file exists; `-RCDevRampRenderHold` holding it. A constant clip and a flat
    Speed action with the same map share one file.
  - **(c) `constant` shapes no file and is not keyed** (`RampSegmentKey`, `RampAudioCache.name`).
    It sends a reader to SR-20 (b)'s constant arithmetic byte for byte: `PlanSpeedRamp.source`
    is nil for it, so `MediaPeaks.sourceTick` and silence read as before.
    `rc_project_source_map` is unchanged (`ramped: false`).
  - **(d) Keep pitch on**, in or out of SY-39's band, stays as it is (SY-41). SY-24's lead now
    applies only to the segments still played `off` unrendered: Keep pitch on inside SY-39's band.
  - **(e) Synchronize Audio's drift-corrected clips** (SY-6, Keep pitch off near ×1) are
    included: after the correction such a clip is silent in the preview until its sound is
    rendered, and every edit that changes its map (a trim, a split, a rate) renders the whole
    clip again.
  - **(f) The failure sentence** names the retimed audio, not a ramp: "Clip N's retimed audio
    could not be rendered: …", and the renderer's own sentences say "the retimed audio".
  - **(g) The proof rows.** `constant_render_proof.py`'s C1 (a render lands at ×0.25, ×0.5, ×2
    and ×4), C2 (none for Keep pitch on ×2 or Keep pitch off ×1), E-x0.25…E-x4 (the plain
    `set_speed` export: frames exact, no step, max |x − ideal| ≤ 5e-4 on sine, clicks found at
    |median| and spread ≤ 0.005 ms), WOK and U1; `retimed_audio_proof.py`'s B1 scored;
    `ramp_mapper_probe` F4's Keep pitch off constant twin (`source` nil). On the old tree C1 and
    E-x4 fail.
  - **Why:** #334's measurements (the issue's last comment, 2026-10-25): AVFoundation's own read
    of a ×4 varispeed segment had 32 step events (max |diff| 0.517) that Frame Job's writer
    cannot remove, and rendering offline took it to 0 (0.000031) and every rate's placement to
    +0.000 ms, for 0.62–4.18 s of render per output minute and the same cache as a ramp.
  - Risk accepted: the silent window and the cache per output minute grow with the clip's length
    and rate (0.55–4.09 s for a 60 s clip on the spike's host, 11.5 MB a minute mono, 23.0 MB
    stereo); the person check is `docs/manual-checks.md`'s SE-16.
