# Spec §11 — decisions: Creator jobs, the framing op onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) …
[`creator-jobs-8.md`](creator-jobs-8.md) (CJ-, VR-, TX-, SW-, CU-, CO- and FC-), so a citation
never has to say which file; `creator-jobs.md` says what the road map builds and how its IDs are
made (CJ-7). This file is new because `creator-jobs-8.md` held SW1's entries past the road map's
~500-line split rule; each phase's decisions are appended here from now on, before its code.

CU-117…CU-119 (CU11b), VR-27 (VR2b1), CU-31 and CU-36 (CU3c) and TX-35 and TX-36 (docs bugs c2) are
in [`creator-jobs-9b.md`](creator-jobs-9b.md), moved there unchanged on 2026-11-11 because this file
had passed the spec's ~500-line split rule (#548).

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
  *Amended by VR-27 (VR2b1, 2026-11-03):* refusal (7) is removed — a clip with actions is
  framed by composing into them — and (8)–(10) keep their order and their numbers.
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

## SW2a — the switch's planner and its numbers (2026-11-03)

Recorded before the code. SW2a builds Switch by Speaker's pure planner and nothing visible: the
inputs it reads off a document, which microphone is active on a 10 ms grid, the shots those turns
make, and every refusal at once; spike SW-S4 tunes SW-21's thresholds on F-TURNS. The owner's
answer (2026-11-01) was "the defaults as SW-S4 tunes them". SW-23, SW-26, SW-28 and SW-29 are
SW2b's (the sheet, the tool, the Program track and the edit). No menu, sheet, tool, op, FFI or
format change. SW-35's stream guard is not added here: SW3a has not landed, and whichever of SW3a
and SW2a lands second adds it.

- **SW-20 — The inputs and the pairing** (`SpeakerSwitch.defaults`, `SpeakerSwitch.read`).
  - Angles are tracks (SW-13): each track holding a selected `.media` clip whose media has a
    picture (`sourceSize(of:) != nil`), front first. A clip with `enabled.video` off and `linked`
    set (a `detach_audio` sound half) never makes its track an angle. An angle's spans are
    `SwitchAngle.pictureClips`, unchanged, so SW-13's covering still counts such a clip.
  - Microphones are tracks holding a selected `.media` clip that plays sound and whose media has
    no picture (`hasVideo` false). Only when there are none, each angle track holding a selected
    clip that plays sound is its own microphone. A detached camera sound is never a default: it
    is a microphone only when the sheet's Microphone popup picks it or the tool names it (SW2b).
    In `defaults`, which reads no plan, a clip plays sound when its media has audio, its
    `enabled.audio` is on and it is not a detached camera sound; `read` reads the plan's audio
    segments.
  - The pairing: a microphone that is an angle pairs with itself. The remaining microphones,
    front to back, pair with the remaining angles, front to back. The wide is the single angle
    left over; with two or more left over there is no wide. A microphone left without an angle is
    a speaker with no angle, which SW-24 refuses.
  - The range is the one given, else the document's In–Out range, else the first selected angle
    clip's start to the last one's end. The grid is anchored at its start: step k is
    `[from + k·step, from + (k+1)·step)`, `step` = 6,000 ticks (10 ms, `MediaPeaks.bucketTicks`),
    `count = (to − from) / step`, a partial last step dropped. A microphone's steps outside its
    clips are silent and not covered.
  - The switch trusts the placement and does not check sync (the guide says to run Synchronize
    Audio first).
  *Amended by SW-83 (SW8, 2026-11-03):* one microphone with two or more angles pairs every angle,
  front first, with it and no wide (the faces mode).
- **SW-21 — A microphone is active when its voice is its own** (`SpeakerSwitch.labels`,
  `ClipLevelSeries`).
  - Energy: e(k) is `ClipLoudness.energy` (the K-weighted mean square through the clip's
    `ChannelMatrix`, AU-35) over the source window of step k, taken through the audio segment
    covering the step's midpoint (the later-starting one when two do), mapped by
    `MediaPeaks.sourceTick` and, for a reversed clip, `ReverseMirror` about `reversedPivot`. A
    step no segment covers has e = 0 and is not covered. Where two selected clips of one track
    cover a step, the later-starting clip's reading stands.
  - Level: ℓ(k) = 10·log10 of the mean of e over the CENTRED window k − 5 … k + 4, clipped to
    `[0, count)`; −∞ when that mean is 0.
  - Voice: v(k) is the speech cache's probability for the 32 ms chunk holding the source tick
    under the step's midpoint (`bucketIndex(sourceTick(mid), chunkTicks)`), mirrored when the clip
    plays reversed; 0 outside the cache or where not covered.
  - P is the 90th percentile of ℓ over the covered steps with v ≥ `voice_threshold` (0.5); F the
    10th percentile over the covered steps with v below it, −∞ when there are none. A percentile
    is the nearest rank, `sorted[⌈p·n⌉ − 1]`.
  - m is active at k when v ≥ `voice_threshold`, ℓ ≥ P − `bleed_db` and ℓ ≥ F +
    `floor_margin_db`. When two or more are active and one's ℓ − P exceeds every other active
    one's by `dominance_db` or more, only it is active.
  - One active microphone labels the step as that person, two or more as crosstalk, none as
    nobody. Drafted at `bleed_db` 15, `dominance_db` 8, `floor_margin_db` 6; SW-S4's verdict
    follows.

    Amended 2026-11-03 (the owner's second answer, option 1). SW-S4's second run, after SW-22
    (a)'s amendment, still found no passing setting (0/75). Every setting missed b24_f45 (bleed
    −24 dB, floor −45 dBFS) by the same one cut, at all 75 settings: expected shot 17 (b), onset
    73,560,687 ticks (122.601 s, the manifest's `expected_shots[17]`), onset − lead 73,440,687,
    the planned start 73,540,000 (122.567 s), late by 99,313 ticks (165.52 ms) against τ = 88,400
    ticks (147.33 ms), 10,913 ticks (18.19 ms) past it. The owner accepted that cut as a named
    limit, in SW-S4's amended rule: b24_f45's shot 17 passes when it is on the frame grid and late
    by at most 99,313 ticks after onset − lead (an early error past τ still misses). Every other
    cut of every variant is held to τ; τ is never widened, and this rule's tests and values are
    unchanged.

    SW-S4's verdict (2026-11-03, its third run, rule `c206847c…a03981a0`): `59/75 settings pass on
    all 6 variants` and `CHOSEN bleed_db 15, dominance_db 8, floor_margin_db 6 (0 grid steps from
    the draft)`, so the defaults are the drafted ones. At the chosen setting each variant's largest
    |error| from onset − lead is 75.6 ms on b12_f45, b12_f55, b18_f45 and b24_f55, 42.2 ms on
    b18_f55, and 165.5 ms on b24_f45: its shot 17 (b), the one cut passed by SW-S4's named limit.
    The 16 settings that fail all miss b12_f45 (dominance 12 at bleed 12–21 and dominance 10 at
    bleed 18 or 21 with margin 3 or 6), and at dominance 12 b12_f55 as well. The excerpt arm
    (S-PC1) is owed: until it agrees on ≥ 90 % of single-speaker seconds with no false cut of
    `min_shot` or more, SW2b shows the bleed row by default (the rule's else branch).
- **SW-22 — Turns become shots** (`SpeakerSwitch.shots`), in this order:
  - (a) Each maximal stretch of runs that are not crosstalk, lying between two crosstalk runs and
    shorter than `bridge` (0.5 s) in total, takes the crosstalk label, whatever it holds (a
    person's runs, nobody's, or both). Then a run of nobody shorter than `bridge` between two
    runs of the same label takes that label. A stretch is measured as the nobody bridge is,
    `steps · step < bridge`, strictly less; a stretch before the first crosstalk run or after the
    last one is never bridged. The measure is the stretch, not a single run, because the
    interruptions this answers are runs like "B 0.04, nobody 0.23", two runs.

    Amended 2026-11-03 (the owner's option 1). SW-S4's first run found no passing setting (0/75).
    SW-21's dominance test flips the label during crosstalk every few tens of milliseconds
    (b12_f55: X 0.34, B 0.04, nobody 0.23, X 0.26 … s), so no crosstalk turn reached
    `crosstalk_min`. SW-21 is untouched and τ is never widened.
  - (b) The maximal runs are turns.
  - (c) A person turn shorter than `min_turn` (1.0 s), or a crosstalk turn shorter than
    `crosstalk_min` (1.0 s), starts nothing.
  - (d) A qualifying person turn starts a shot on its speaker's angle. A qualifying crosstalk
    turn starts a shot on the wide when `crosstalk` is `wide` and there is a wide; otherwise it
    starts nothing (holds). A shot starts at `max(the current shot's start, from,
    snapToFrame(turn start − lead))`, `lead` 0.2 s. A turn whose angle is the current shot's
    starts nothing; nobody holds. A shot starting where the current one starts replaces it.
  - (e) The range opens on the wide when there is one; otherwise the first shot is pulled back to
    `from`. With no wide and no shot, the range is one shot on the front-most angle.
  - (f) `wide_after` (off by default; with a wide): once a person's shot has run `wide_after`,
    the wide is inserted at that frame-snapped tick for `min_shot`, then the speaker's angle
    returns at the frame-snapped tick after it; this repeats to the shot's end.
  - (g) Shots tile `[from, to)`: each ends where the next starts, the last at `to`. Covering is
    SW-13's rule over the angle tracks' picture clips. Each maximal sub-span a shot's angle leaves
    uncovered is reassigned piece by piece from its start: to the wide as far as the wide covers
    it; else to the shot before's angle as far as that covers it (the shot before extends); else
    to the front-most angle covering from that tick, as far as it covers. The first shot has no
    shot before. SW-24's gap refusal guarantees some angle covers every tick.
  - (h) Merges, repeated until none applies: the earliest shot shorter than `min_shot` (2.0 s)
    that can merge merges into the shot before when that shot's angle covers the merged span; the
    first shot, or one the shot before cannot cover, merges into the shot after (which takes its
    start) when that angle covers it; a short shot neither neighbour covers stays. Equal
    neighbours are coalesced.
  - Every planned shot's angle covers its whole span: the invariant SW2b writes from.
  - `crosstalk` `hold` makes crosstalk hold the current shot even with a wide. SW-22's values
    stay as drafted: no sample measures them yet (SW-S4's excerpt arm is owed).
- **SW-24 — It refuses, naming every reason at once (SY-1's form),** one list in this order (T a
  track id; A and B timecodes `ReelTime.format(_, fps:, frames: true)`):
  - "Switch by Speaker needs at least two angles: tracks holding a selected clip with a
    picture."
  - "Switch by Speaker takes at most nine angles; N tracks hold a selected clip with a picture."
  - "The speaker on track T has no microphone." — a speaker whose microphone is none or names no
    microphone track (T the speaker's angle).
  - "The microphone on track T has no angle to show its speaker." — a speaker whose angle is
    none or not an angle.
  - "Track T is the microphone for N speakers; each person needs their own microphone." (until
    SW8).
  - From `read`, per microphone, front first: "The microphone on track T is still being analyzed
    — its loudness has not been measured yet. Try again in a moment." and "… — its speech has not
    been detected yet. Try again in a moment." (amended by #526); then, once, "Speech detection is unavailable on
    this Mac, so Switch by Speaker cannot tell who is talking." A missing cache file is "still
    being analyzed" (amended by #526), never silence.
  - "The microphone on track T has no speech between A and B, so it never says who is talking."
    — a microphone with no covered step at v ≥ `voice_threshold`.
  - "No angle has a picture between A and B." — the first stretch of the range no angle covers.
  - Only when nothing above is refused: "Switch by Speaker would add N clips to M; the most is
    4096 — raise the minimum shot.", the number `Int(RC_MAX_CLIPS)`, M
    `ShotSplit.clipCount` of the document's project. N counts, per shot, the angle clips it
    overlaps (one piece each, the later clip taking over where two overlap, as SW-15 (d)), plus
    one split for each angle clip straddling `from` and each straddling `to`. Refused when M + N
    exceeds `RC_MAX_CLIPS`.
  *Amended by SW-83 (SW8, 2026-11-03):* the shared-microphone refusal applies only in the
  microphones mode; SW-84 adds the faces mode's pending and no-face refusals.
- **SW-25 — The switch reads caches and computes nothing else.** `plan`, `labels`, `shots` and
  `defaults` read no document, file or clock; `read` is the only reader (the edited project's
  plan and snapshot, the loudness and speech caches through `MediaImporter.loadLoudness` and
  `loadSpeech`, `SileroVAD.isAvailable`). The planner is `SpeakerSwitch.swift`,
  `SpeakerSwitch+Shots.swift` and `SpeakerSwitch+Read.swift`, the series `ClipLevelSeries.swift`;
  all are probe-callable and name no `rc_*` but `ReelTime.snapToFrame` and `format`.
  `ClipLoudness.energy(_:from:to:_:)` loses its `private` so the series reuses it.
  *Amended by SW-84 (SW8, 2026-11-03):* `readFaces` and `facesWanted` are its second and third
  readers; `FaceActivity` and the faces mode's labels are pure.
- **SW-27 — The proof's speech is made on the Mac, its truth measured.** F-TURNS
  (`tools/proof/creator_spike/f_turns.py`, into `tools/proof/media/creator/f_turns/`, reused
  while its manifest's `generator_sha256` equals the script's): Samantha (A) and Daniel (B) read
  a scripted turn table of about 150 s through `say -v` — turns of 3 s or more, two replies of
  0.6 s or less in 0.8 s gaps, one crosstalk passage of 2.5 s or more followed by a pause of
  0.6 s or more, one silence of 3 s or more. Each voice's SOLO stem is written before mixing;
  each microphone is its own stem at 0 dB plus the other at the bleed (12, 18 or 24 dB) plus
  seeded pink noise at the floor (−55 or −45 dBFS RMS), six variants, 48 kHz 24-bit. A turn's
  onset is the first sample of its solo stem above −40 dBFS. The cameras are flat colour cards
  with a 16-block binary frame code, 1920×1080 at 30 fps, A in two files abutting mid-way. The
  manifest's expected shots are written from the script's design, never by the planner. A cut
  passes when it is on the frame grid and within τ of onset − `lead`: τ = 64 ms (two VAD chunks)
  + 50 ms (half the window) + one frame (147.3 ms at 30 fps), except SW-S4's named limit:
  b24_f45's shot 17 late by at most 99,313 ticks (165.5 ms); R6 scores it so. The probe's R6 and the spike are
  skipped by name when `say -v Samantha` or `say -v Daniel` is missing. The probe is
  `tools/proof/switch_speaker_probe.swift` (R1–R6, and a `spike` mode), scored by
  `switch_speaker_probe.py`, with seven mutants (the bleed test removed, R1; the dominance test
  removed, R1; a trailing window, R1; a short shot merged into the next first, R2; a camera's own
  sound taken beside picture-less files, R4; the crosstalk bridge removed, R2 and R6; the
  crosstalk bridge taking only a single run, R2). A trailing window fails R1 alone: R6's τ
  budgets the half-window's 50 ms by design. No manual check.

## SW2b — Switch by Speaker's sheet, tool and Program track (2026-11-03)

Recorded before the code. SW2b makes SW2a's planner visible: Clip ▸ Switch by Speaker… and the
tool `switch_by_speaker` run `SpeakerSwitch.read` and `plan` unchanged (SW-25) over the selected
angles and microphones and write the shots onto a Program track as one undo step. The owner's
answers (2026-11-01): the program track — *yes*; `wide_after` — *offered, off*; cut to the wide
on laughter (FC's `sound_events`) — *not here; a candidate* (filed as an issue). No core, FFI,
header, op or format change. SW-35's stream guard is not added here (SW3a has not landed).

- **SW-23 — What the switch writes, as one undo step "Switch by Speaker"** (`SpeakerSwitch.edit`,
  `SpeakerSwitch+Edit.swift`). Every op is tried ONE at a time on the container's handle through
  `SwitchAngle.Trial.require` (`applying([ReelOp])` does not stop at a refusal); the first refusal
  refuses the whole switch, nothing committed: "Switch by Speaker was refused at <op>: <reason>".
  - (a) The destination. With no `track`: `add_track {index: trackIndex(the front-most angle) + 1,
    name: "Program"}`, directly in front of the front-most angle; its id is read from the trial's
    snapshot. With `track` (Replace the shots on): `split {clips: [c], at: from}` for each clip on
    it strictly straddling `from`, then the same at `to`, then one `delete` of every clip on it
    wholly inside `[from, to)` — a `lift_range` of that track alone.
  - (b) The pieces: one `copy_pieces {clip, track: the destination, ranges, video: true, audio:
    false}` per angle clip a shot crosses, its ranges the union over the shots of
    `SwitchAngle.pieceRanges(angle: shot.angle, from: shot.start, to: shot.end)` for that clip
    (cut at the clip's ends, the later clip taking over where two overlap, SW-15 (d)), the ops in
    the order of their first range's start.
  - (c) The angles hidden without touching anything outside the range, per angle track, front
    first: when every clip on the track is one of its picture clips wholly inside `[from, to)`,
    `set_track {hidden: true}` (none when it is hidden already); otherwise each picture clip
    straddling `from`, then each straddling `to`, is `split` there, and each picture clip then
    wholly inside gets `set_enabled {video: false}`.
  - (d) "Mute the cameras' own sound": every angle picture clip wholly inside the range, on a
    track that is not a microphone, gets `audio: false` in that same `set_enabled` (on a hidden
    track, a `set_enabled {audio: false}` of its own). On by default when no microphone is an
    angle (`muteDefault`). A track that is only a microphone is never edited.
  - (e) Replace's tracks (`replaceable`): unlocked, in front of the front-most angle, holding no
    selected clip, with at least one clip overlapping the range, every such clip a media clip
    whose media an angle picture clip plays. `replaceRefusal` names the first test that fails, in
    this order: "Track T cannot take the shots: it is locked." · "…: it holds a selected clip." ·
    "…: it is not in front of the angles." · "…: it has nothing between A and B to replace." ·
    "…: clip C is not a piece of an angle." (A and B `ReelTime.format(_, fps:, frames: true)`).
  - (f) The selection after: the selection before plus every new clip a `split` made from a
    selected clip, so a second run reads the same angles.
  - (g) The command is offered (`canOffer`) when SW-20's defaults over the selection hold two or
    more angles and some selected `.media` clip has `enabled.audio` on and a media with audio.
  - (h) A linked angle clip is refused before any op is tried: when an angle picture clip
    crossing `[from, to)` has `linked` set, the first such clip in track-then-start order refuses
    the switch: "clip C on track T is linked to clip P (Detach Audio's pair); Switch by Speaker
    cuts between cameras with no link — Attach Audio first" (SW-15 (c)'s rule: `split` acts on
    the link closure and would edit the microphone, `audio: false` on a picture half mutes
    nothing, and `video: false` makes it read as a detached sound). The sheet shows it in its
    summary; the tool throws it after "Switch by Speaker was refused: ".
- **SW-26 — The sheet and the tool take the same arguments, one set of values, ranges and
  defaults.**
  - (a) The sheet (`SwitchSpeakerSheetController`), opened by the command when `canOffer` and no
    sheet is up; title "Switch by Speaker", hint "Cuts a Program track from the cameras, showing
    whoever talks on each microphone. Run Synchronize Audio first. One undo step." One row per
    default speaker: a Microphone popup (every track holding a selected `.media` clip with sound
    on, a detached sound half included) and a Camera popup (the angles). A Wide popup ("None" and
    the angles); Minimum shot (s); Cut before speech (s); Crosstalk shows (Wide, Current speaker);
    Ignore bleed (dB below a speaker's own level), in the main grid (SW-S4's excerpt arm is owed,
    so its else branch); "Cut to the wide after [20] s on one speaker", off; "Mute the cameras'
    own sound" (`muteDefault`); "Write to:" ("A new Program track" and "Replace the shots on
    <name>" per `replaceable`), the row shown only when a track qualifies; the summary; Cancel and
    Switch. A track is its name, with " (n)" when two listed share it (SW-13's rule).
  - (b) Every control change and every field's end of editing runs `read` (the selection, the
    popups' pairing, no range, the settings) → `plan` → `edit` on main; the summary shows "N
    shots: k on <name>, …. Adds M clips." or the refusals one per line, and Switch is enabled
    only on an edit. Switch runs `read` → `plan` → `edit` again on the document's current handle
    (the ops name ids predicted on a trial), shows any refusal and stays open; otherwise it
    dismisses, applies the ops through `applyEdit` as "Switch by Speaker", sets the selection (f)
    and writes the remembered values that changed. Remembered: `FrameJobSwitchSpeakerMinShot`,
    `…Lead`, `…Crosstalk` ("wide" or "hold") and `…Bleed`, each read clamped, an absent key the
    default, written only when changed. `-RCDevSwitchSpeakerAccept YES` (dev tools only) presses
    Switch once the first edit exists.
  - (c) The tool `switch_by_speaker` (app-state, no `scope` key, main thread; the container
    `set_scope` has open): `speakers` `[{mic, angle}]` (track ids, both required per item);
    `wide` (an angle's track id, or null for none; absent: SW-20's leftover rule over the
    speakers used); `from` and `to` (ticks, both or neither, snapped to the frame grid, `to`
    after `from`); `min_shot` 0.5–30 s, `min_turn` 0.2–10 s, `lead` 0–1 s, `bleed_db` 3–40,
    `dominance_db` 0–30, `wide_after` 2–600 s or null, `crosstalk` "wide" or "hold",
    `mute_cameras` (default `muteDefault`), `track` (Replace), `apply` (default true). Argument
    errors in auto_zoom's form ("min_shot is 0.1 s; it runs 0.5–30 s"), "no track with id N",
    "wide: track T is not an angle"; then `read` (nil: the plan could not be read), `track`
    through `replaceRefusal`, `plan` (refused: "Switch by Speaker was refused: " and the reasons
    joined by spaces), `edit`; `apply: false` answers without editing; otherwise one
    `performGroupedEdit`, the selection set, and the answer `{ok, applied, step, track, shots:
    [{angle, start, end}], ops, added, speakers: [{mic, angle}], wide, mute_cameras, project}`
    (`step` only when applied; `track` the Program track's id, null when not applied and no
    `track` was named).
  - (d) The sheet never sets `min_turn` or `dominance_db`; they keep SW-21's and SW-22's
    defaults there. (e) The step and the undo name are always "Switch by Speaker".
  *Amended by SW-86 (SW8, 2026-11-03):* the tool runs on the server thread (`creatorOffMainTools`)
  and waits for missing faces up to 60 s; its answer gains `mode` and, in the faces mode, `note`.
- SW-28 reserved for SW2c; SW-29 the owner's verdict on JOB-51 (owed).
