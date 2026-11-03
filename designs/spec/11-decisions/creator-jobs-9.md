# Spec §11 — decisions: Creator jobs, the framing op onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) …
[`creator-jobs-8.md`](creator-jobs-8.md) (CJ-, VR-, TX-, SW-, CU-, CO- and FC-), so a citation
never has to say which file; `creator-jobs.md` says what the road map builds and how its IDs are
made (CJ-7). This file is new because `creator-jobs-8.md` held SW1's entries past the road map's
~500-line split rule; each phase's decisions are appended here from now on, before its code.

## VR2a2 — coverage, cuts, loss, backdrops and the op `reframe_clip` (2026-11-03)

Recorded before the code. VR2a2 is the second half of the road map's fallback split (VR2a's
"Split" paragraph): VR2a1's planner (VR-20…VR-23) becomes an edit. VR-24, VR-25, VR-26 and VR-28
are the road map's drafts, settled here; VR-27 (composing into existing ends, `replace`) and
VR-29 (Clip ▸ Follow Subject…) are VR2b's. No FFI, no header and no format change (43 stands);
nothing sends anything anywhere, so nothing is keyed (VR-2, CJ-3). No owner question: the road
map expects none for VR2a.

- **VR-24 — Cuts, loss and two people** (`core/src/reframe_path.rs`, `write_keys`, which VR-23's
  key loop moves into whole; `reframe_tracks.rs`'s chooser). All times are clip ticks on the
  canvas's frame grid; VR2a1's clamp, snapping and strictly increasing keys hold throughout.
  (a) **Shots in clip time round up.** `in_clip_time` maps a shot with `Round::Up` (samples keep
  `Round::Down`), and a cut's key time `c` is `time::snap_up_to_frame` of that: the first canvas
  frame that shows the new shot at any media rate (a 25 fps shot at media 1.04 s on a 30 fps
  canvas is `c` = 1.0667 s, never 1.0333 s, which still shows the old shot). A cut with `c` at or
  under one frame, or at or past the clip's duration, is dropped.
  (b) **A shot change is a hard cut.** At `c`: a `linear` hold key at `c − frame` (the value in
  force; not written when the last key is already there), then a `linear` key at `c` holding VR-22's
  window on the per-axis median of the subject points of the new shot's samples before `c +
  CUT_MEDIAN` (1 s) that carry the identity and the kind of the shot's first chosen sample. With
  nothing chosen there, the key at `c` is the `where_empty` state and the path goes EMPTY; a
  framing equal to the one in force writes no key. No move or ease may end after `c − frame`, so a
  move that would is not started; a cut counts as a move's end for VR-23's spacing.
  (c) **The chooser holds an absent primary for `LOSS_HOLD` (1 s), amending VR-21's "with the
  primary absent, the best present track at once".** At a sample that is not its shot's first and
  where the primary has no present track in the chosen tier, the best present track is output
  with `lost: true`; the primary is not re-pointed and the rivals are not cleared. A primary back
  before `t0 + LOSS_HOLD` (t0 its first absent sample) is chosen again as staying, with no rival
  test; at the first sample at or after `t0 + LOSS_HOLD` with it still absent, the best present
  track becomes the primary. A shot's first sample still picks the best with no hysteresis, and
  one with nothing present clears the primary. `Chosen` carries `identity` (a body's is its
  face's), `lost`, and `second`: for a face or person pick, the best-scoring other present track
  of its tier with another identity.
  (d) **Loss.** It begins at the first sample with `lost` or with nothing chosen (t0). No move
  starts in `[t0, t0 + LOSS_HOLD)`, and the loss ends early when the identity followed before it
  is chosen again. At the first sample at or after `t0 + LOSS_HOLD`: a chosen subject is followed
  from there by VR-23; with nothing chosen an `ease_in_out` ease of `EMPTY_EASE` (0.8 s) to the
  `where_empty` state starts there with a hold key and the path goes EMPTY — unless it would pass
  the clip's end or end after the next cut's `c − frame`, when the window holds.
  (e) **Return from EMPTY.** Once a subject has been chosen at every sample for `RETURN_SEEN` (0.6
  s; a sample with nothing chosen restarts the count), a VR-23 move of `max(0.4 s, ‖desired −
  cropped centre‖ ÷ (speed · w))` starts at that sample, under the end and cut rules of (b) and
  (d).
  (f) **The first key** is VR2a1's (the first chosen sample's desired centre) when a subject is
  chosen within `LOSS_HOLD` of the clip's start in its first shot (the samples before any kept
  cut); otherwise it is the `where_empty` state and the path starts EMPTY. This replaces VR-23's
  "with no chosen subject the window holds" and its "the cropped picture's centre when nothing is
  chosen anywhere".
  (g) **Two people.** For a face or person pick with a `second`, both boxes are widened by
  `PAIR_WIDEN` (1.15) about their centres and mapped to the source canvas; when their union is no
  wider and no taller than the window, the subject point is the union's — its centre placed as a
  face, its top centre placed as a person — else the pick alone. The median of VR-23 reads these
  points.
  (h) **The `where_empty` states.** `center`: the follow window (fill × zoom) on the cropped
  rect's centre. `fit`: the whole cropped picture fitted to the canvas, `edit_zoom.rs`'s
  `zoom_scale(.., fit, 0)` of the cropped size and `zoom_offset` at θ = 0, written as a key of F
  (`k = scale′/s`, `dx = x′ − k·x`, `dy = y′ − k·y`); a path that holds it anywhere is
  `shows_fit`. `fixed_framing` answers either as one key at 0, for `follow` `center` and `fit`.
  **Choices left to the code:** a cut's median reads the new shot's samples from its own clip
  tick, not only from the snapped `c`; the chooser's absence is judged in the tier it chooses
  from, as VR2a1's `staying` was; samples a stand-in carries during a hold stay in VR-23's median
  (a one-sample blink is outvoted). `core/tests/reframe.rs` keeps its 22 cases; three change where (c) replaces VR-21's "at once" —
  `a_long_step_moves_for_its_distance`, the second half of
  `no_move_within_half_a_second_of_the_last_unless_outside` and
  `an_exception_move_on_the_last_end_drops_its_hold_key`, whose step is a jump no track links, so
  the new face stands in for 1 s before the move; `a_faces_body_carries_it_while_it_is_away` and
  `a_track_bridges_a_gap_of_0_9_s_and_not_1_1_s` read the same track ids, now with `lost: true`
  on the returning track for its first second.
- **VR-25 — `backdrop`: the blurred copy goes on a named track.** When the written path is
  `shows_fit` and `backdrop` is given, ONE copy of the original clip, built by
  `add_blurred_background`'s builder (`edit_background.rs`'s `blurred_copy`, lifted
  `pub(crate)`, the op's answers unchanged), spans the whole clip — the eases into and out of fit
  need it too. It goes on `backdrop` when that track is unlocked, not a matte, and holds no clip
  intersecting `[start, start + duration)` (touching allowed); otherwise on a new back-most track
  (`with_back_track`, lifted `pub(crate)`). Ids are minted in one order: the clip's actions in
  time order, then the new track when one is made, then the copy. Without `backdrop` no copy is
  made (VR-7's first exception). An existing backdrop or plate is VR-33's.
- **VR-26 — `reframe_clip {clip, follow, zoom?, where_empty?, from_width?, from_height?,
  backdrop?, subjects?}`** (`core/src/edit_reframe.rs`, writing through `reframe_cover.rs`).
  `follow` is `subject`, `face`, `person`, `salient` (the following kinds, VR-20's planner),
  `center`, `fit` (`fixed_framing`) or `keep`. Defaults: `zoom` 1, `where_empty` `fit`, `from_*`
  the canvas of the view (a nest's inside a `scope`). Only `keep` reads `from_*` — a followed,
  centred or fitted placement measures every offset from a canvas centre, so the source size
  cancels; `fit` and `keep` ignore `zoom`; only the following kinds read `where_empty` and
  `subjects`. `keep` is `set_canvas`'s rescale rule (`edit_canvas.rs`'s `rescale_video`, lifted)
  with `W/from_width` and `H/from_height` on the clip's base only. Writing a path (`framed`): the
  base takes key 0 composed (`scale′ = k·s`, `x′ = k·x + dx`, `y′ = k·y + dy`, raw values); each
  later key whose value differs from the one before is one action from the previous key to it,
  with its curve and the end `{"video": {"scale", "x", "y"}}` composed. A result equal to the
  input is an identity (`finish`). Allowed inside a nest, whose canvas is the view's.
  `Err`, in order: an unknown clip; `zoom` not finite or outside 1–4 ("zoom must be between 1 and
  4 times fill, not {z}"); a `from_*` of 0 ("from_width must be greater than 0, not 0"); an
  unknown `backdrop` track; and `subjects` that is not the strict object (an object required,
  `deny_unknown_fields` at every level, a wrong member named by its path under `subjects`, as
  `ZoomRegion` is read). Refused, in order, each in its own sentence: (1) a follow other than
  `keep` on a text, shape, graphic or adjustment clip; (2) a media clip whose media has no picture,
  or a picture clip whose crop or scale leaves none; (3) a nest clip with a following kind; (4) a
  still or image clip with a following kind; (5) unless `keep`, a clip on a matte track or on the
  track a matte cuts (`recipe_matte::matte_target`); (6) unless `keep`, a base rotation other than
  0, an action end turning the clip, or `spin` in any motion slot; (7) any action on the clip,
  unless the follow is `keep` and no action names `x`, `y` or `scale` ("clip {id} carries actions,
  which framing cannot compose with in this build" — speed and volume actions count, so a ramped
  clip is VR2b's); (8) for a following kind, bad `subjects`: over `MAX_SUBJECT_SAMPLES` (100,000)
  samples, over `MAX_SUBJECT_BOXES` (8) boxes of a kind in one sample, times not strictly
  increasing, an x, y, w, h or c outside 0…1, or a w or h ≤ 0; (9) only when a copy would be
  made: a nest clip (`add_blurred_background`'s sentence), or a `backdrop` track not behind the
  clip's ("track {t} is not behind clip {id}'s track, so a backdrop there would cover it"); (10)
  LAST, a following kind with no `subjects` or with no sample in the played window ("clip {id} has
  no subjects to follow; analyze it first"), so that the tool's trial meets every other refusal
  first (VR-28).
- **VR-28 — The tool fills `subjects` and answers within a bound** (`AgentServer+Framing.swift`,
  off main; `subjects` declared `filledByTheApp`, so the gate refuses a caller's own as a
  stranger). The first main hop resolves the target and the effective scope's view, reads every
  argument with the throwing readers, and TRIES the op with no `subjects`, scoped, on the
  document's project without committing (as the inspector's probe does): an `Err` throws, an
  applied or identity answer (`center`, `fit`, `keep`) goes straight to the last hop with no
  wait, and a refusal is the answer unless it is exactly refusal (10)'s sentence (one
  `FramingWant` helper builds it, pinned by `core/tests/reframe_clip.rs`). Only that refusal leads
  to `FramingAnalysis.requests(clips: [clip], in:, project: view)` (VR-12's kinds over the clip's
  window ± 1 s) and the wait: `split_at_shots`'s, a new owner, CJ-25's `AnalysisLane.callWaitLimit`
  (60 s); a Stop or a failure throws naming the kind and the media. Past the bound the same
  requests are wanted again on that owner with `alive: document.isOpenForAnalysis && !hold.done`,
  the hold (an `NSLock` of its own) is marked done from `settled` once every request has ended,
  the owner is never released, and the answer is `{"ok": true, "analyzing": {"media": [ids],
  "covered": fraction}, "note": "Still analyzing the media of clip 12 (40 %); call reframe_clip
  again to apply.", "project": …}` with no edit — `covered` the share of the requests' missing
  grid indices their kinds' markers now hold (`AnalysisStore.coveredCount`), `media` the media
  not landed. Once landed, `FramingSubjects.read` builds `subjects` off main: each index of the
  `faces` grid (shared by `subjects`, VR-11) inside the windows that both markers cover is one
  sample at `grid.ticks(of: k)`, each box clamped into the picture and dropped with no area left,
  each kind's first 8 in stored order; `shots` the pts of `AnalysisShots.cuts` over the covered
  windows. The last main hop throws when the project or scope changed ("… so nothing was framed.
  Call reframe_clip again.") and otherwise applies one op as one undo step, "Reframe Clip",
  answering `cached` (no analysis ran). Every refusal is the core's sentence; Swift copies none of
  VR-26's rules. It reads no key and no `UserDefaults`.
- **VR-S2's re-run after VR-24 (the owner's ruling, 2026-11-03).** VR-S2's rule, unchanged
  (`rule_sha256` matching the table), was re-run over the six canned inputs with VR-24 in the
  planner (attempt 1, at `05871b96`). It answered `VERDICT STOP`: at dead zone 0.10 every
  setting made 22 moves (8.25 a minute), so the second arm found none at 8 or fewer, and the first
  arm's best was dead zone 0.15, speed 0.8, headroom 0.38 at 1,260 of 1,380 contained (91.30 %)
  with 16 moves; the whole drop is input (c), two faces, at 194 → 80 of 200. The owner chose
  option (a): the run is confounded by VR-24 (g)'s pair framing, because VR-S2's instrument counts
  only the chosen face inside the window's central 60 % while the window now frames the pair's
  union. With the union off (a diagnostic scratch copy, not the recorded run) the first arm
  answers 98.84 % (1,364 of 1,380) with 16 moves. `FRAMING_TUNING` stays at VR2a1's verdict
  (0.15, 0.12, 0.8, 0.38), VR-23 and VR-S2's rule stay unamended, and nothing is re-run.
