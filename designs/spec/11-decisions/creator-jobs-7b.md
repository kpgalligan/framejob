# Spec §11 — decisions: Creator jobs, Speed Up Typing onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-7.md`](creator-jobs-7.md), so a citation never has to
say which file. This file holds CU-91…CU-94 (CU9b), VR-20…VR-23 (VR2a1) and CJ-60 (CJ6). The series
goes on in [`creator-jobs-8.md`](creator-jobs-8.md), which is why this file is lettered. It is new
because `creator-jobs-7.md` had passed the spec's ~500-line split rule (#548, 2026-11-11); the
entries moved here unchanged, and an "above" or "below" in one may now point into a sibling file.

## CU9b — Speed Up Typing (2026-11-02)

Recorded before the code. CU-91…CU-94 are CU9b's: Clip ▸ Speed Up Typing… and the tool
`speed_up_typing` play each typing stretch of the selected clips' cursor files that has no speech
and no shortcut at ×4 (the default), keeping 0.3 s at ×1 at each end, as one undo step "Speed Up
Typing". The plan is a core planner, `plan_typing`, a ninth `rc_cursor_query` request (one track
per clip and the project, as `plan_zooms` and `plan_overlays`; no new `rc_*` export, op, format or
cursor-file version), answered as CU-90's `retime_range` ops. The owner's answer (2026-11-01):
"the sound in a sped stretch is sped with Keep pitch on." Nothing here sends anything anywhere,
so nothing is keyed (CJ-3); speech detection is on-device.

- **CU-91 — The stretch rule (`plan_typing`, `cursor_typing.rs`),** in this order.
  (1) Per given clip: each `typing_stretches(file.keys.typed.t)` stretch (`cursor_bursts.rs`,
  CU-25) `[first, last]`, clamped to the clip's played window `[in, in +
  content_length_in_source)`, mapped to container time through `cursor_zoom_run.rs`'s
  `clip_time` (so through S on a ramp), then intersected with `[from, to)`.
  (2) Subtracted, in container time: (a) every speech span of every media clip in the container
  whose media `has_audio` and that overlaps the stretch, on any track, muted or not — the
  media's `speech` through `audio_duck_speech.rs`'s `speech_in_clip`, plus the clip's `start`;
  (b) per recorded shortcut press p of the given clips — CU8's mapping (`clip.start +
  clip_time(clip, s − in)` for s in the played window) but with NO `[from, to)` filter, so a press
  before `from` whose span reaches into the window still counts: the union of the clips on tracks
  named exactly `cursor_overlays.rs`' `TRACK_NAME` ("Shortcuts") that hold p or start in (p, p +
  `MOST_LATE`], from min(p, their start) to their end; with none, `[p, p + DEFAULT_DURATION)`
  (CU-80's 1.5 s).
  (3) The remaining pieces of ALL given clips are united, overlapping AND touching pieces
  merged, so a stretch across a cut between two clips is one piece.
  (4) Only then: a merged piece shorter than `shortest` is dropped and counted (`short`); a kept
  piece `[a, b)` becomes `[snapped(a + 0.3 s), snapped(b − 0.3 s))`.
  (5) Sorted, the pieces are answered RIGHT TO LEFT as `{op: "retime_range", from, to, rate,
  keep_pitch}` (`retime_range` acts on the whole timeline, so a range across a cut is one op, and
  right to left no op moves a later one's range). `sped_to` = `snapped(from + round((to − from) ÷
  rate))` (CU-90 (a)'s f); `saved` = Σ (to − sped_to). If any media counted in (2a) has no
  stored `speech`, the answer is `needs_speech` (its ids, sorted) with no ops and no ranges — not
  a refusal. **All or nothing:** the ops are applied in order to a clone through
  `Project::retime_range`; the first refusal or error refuses the plan: "the typing from {a} to
  {b} ticks cannot be sped up: {sentence}". Answer: `{ops, needs_speech, stretches, short,
  ranges: [{from, to, sped_to}], saved}`.
- **CU-92 — Defaults and ranges.** Rate ×4 in ×2–×8; shortest stretch 3 s in 1–30 s; Keep pitch
  on (the owner's answer); the margin 0.3 s at ×1 each end; the overlay fallback CU-80's 1.5 s and
  its lateness 0.5 s. Refusals, lowercase, in order: "rate is ×R; it runs ×2–×8", "shortest is S
  s; it runs 1–30", "to (T) must be after from (F)", "plan_typing needs at least one clip", the
  track-count sentence in CU-84's wording ("plan_typing reads one cursor track per clip; …"),
  "plan_typing needs the project"; then per clip: named twice, unknown, not a media clip, no cursor
  file, reversed ("clip C plays reversed; Speed Up Typing speeds only clips that play forward" —
  CU-5).
- **CU-93 — The doors.** Swift's speech step (`SpeedUpTyping.speech`): for each `needs_speech`
  media, a current VAD cache (`MediaImporter.speechIsCurrent` with `CacheStamp.stamp(for:url:)`)
  becomes a `set_media_speech` op with `DuckSpeech.spans`; a media with no file is refused "{name}
  is offline, so its speech cannot be read."; not current while `SileroVAD.isAvailable` is
  pending, and every door that sees pending STARTS the pass through `ProjectDocument
  .generateCaches()` (idempotent: a current cache costs a stat, a running pass is waited for),
  because a pass that could not read the file leaves no marker and is not retried until the next
  open; detection unavailable is refused "Speech detection is unavailable on this Mac, so Speed
  Up Typing cannot tell typing from talking." `SpeedUpTyping.resolve` plans, makes the speech ops,
  applies them to a pure handle (scoped again inside a nest), plans again; the step's ops are the
  speech ops, then the retime ops. Stored spans are never rewritten (AU-111).
  **Clip ▸ Speed Up Typing…** (right after Add Shortcut Overlays, no key, no `ModelKeys` row) is
  on with at least one selected clip passing `AutoZoom.canOffer` and no sheet attached, inside a
  nest too. Its sheet: Rate (×), Shortest stretch (s), Keep pitch, opened at the remembered
  values (`FrameJobSpeedUpTypingRate`, `…Shortest`, `…KeepPitch`, each written only when changed
  from what the sheet opened with); the files are read off main ("Reading cursor files…"); every
  control change plans again; waiting calls `generateCaches()` once per sheet, shows "Waiting for
  speech detection on {names}…" with Apply disabled, and plans again on each
  `.mediaCacheDidChange` of `MediaImporter.speechKind`, bounded at `SpeedUpTyping.waitLimit`, 300
  s (AU-68's bound), past which it shows "Speech detection has not finished for {names}. Close
  this sheet and try again." with Apply disabled; the summary "N typing stretches sped up ×R,
  saving S s." or "No typing stretch without speech or a shortcut lasts S s or more in the
  selected clips, so nothing would change." (Apply disabled). Apply commits through
  `SpeedAudioDrop.commit` (Cancel on its question leaves the sheet up), then remembers.
  `-RCDevSpeedUpTypingAccept YES` (dev tools only) presses Apply once the first plan with ops
  exists. **The tool** `speed_up_typing {clip | clips, rate?, shortest?, keep_pitch?, from?, to?}`
  takes no `scope` key (it acts in the container `set_scope` has open, as `auto_zoom`), runs on
  the server thread (resolved on main, files read off it, back on main refused if the project or
  scope changed); pending starts the pass and is refused "{name}'s speech has not been detected
  yet. Try again in a moment."; the crossing is read by `SpeedAudioDrop.crossing(applying:to:)`
  over the retime ops on the speech-applied handle, and the step is `performGroupedEdit(document,
  "Speed Up Typing", ops)`. It answers `ok`, `stretches`, `short`, `ranges`, `saved`,
  `speech_saved` (media ids written), `created`, `audio_left_out`/`audio_note` when any, and
  `project`; with nothing to speed, `ok` with a `note` and no undo step.
- **CU-94 — CU9b's proof.** `cu9b_proof.py` Z0, R3, R9, R10, R11, R12, R13, R14, R15 over MCP,
  `cu9b_probe.swift` P1 (the speech step's five answers) and P2 (`gaveUp(waitingFor:)` false at
  299 s, true at 300 s), `core/tests/speed_up_typing.rs` (sync across three tracks after two
  ranges, a ×2 clip and a ramp through S, `from`/`to`, a press before `from`, the union of two
  clips, every refusal); eleven mutants (`speech-ignored`, `margins-dropped`, `shortcut-inside`,
  `sheet-rate-not-passed`, `needs-speech-skipped`, `left-to-right`, `no-prevalidation`,
  `unavailable-as-pending`, `shortest-per-clip`, `presses-window-filtered`, `wait-unbounded`) —
  above ten because the objections added three decisions, one each. No person check: the feel is
  judged at CU12's trial.

## VR2a1 — the subject-choosing planner (2026-11-02)

Recorded before the code. VR2a runs as the road map's fallback split (its "Split" paragraph):
VR2a1 lands the source-time helper and the core planner as a pure function answering a framing
path — no op, tool, FFI, format (41 stands), Swift or guide change; VR2a2 lands coverage
(`reframe_cover.rs`, VR-7), VR-24, VR-25, VR-26, VR-28 and the op `reframe_clip`, whose
signature stays the road map's draft VR-20. VR-20…VR-23 are VR2a1's. Nothing here is keyed (VR-2,
CJ-3). No owner question: the road map expects none for VR2a.

- **VR-20 — Source time to clip time is one helper, and the planner's input.** New
  `core/src/clip_source_time.rs`: `clip_time_of_source(clip, media, t, round)` is
  `speech_in_clip`'s mapping of one forward-file source tick lifted out whole — reflected over
  `media.duration` when the clip is reversed, `in` subtracted (both saturating), then
  `SpeedMap::time_at` when the clip is ramped, else divided by the speed and floored (`Down`) or
  ceiled (`Up`); no answer when the source is not media, or with no map and no positive finite
  speed. `in_played_window(clip, media, t)`: the reflected tick s′ has `in ≤ s′ < in +
  source_read_by(clip, clip.duration)`. `speech_in_clip` calls the helper and keeps its signature
  and early guard: it passes each span unreflected, a forward clip's start `(a, Down)` and end
  `(b, Up)`, a reversed clip's start `(b, Down)` and end `(a, Up)`, so its answers do not change.
  `cursor_zoom_run.rs`'s `clip_time` is not routed through it (it reads past the clip's end,
  CU7/CU8). The planner's input `Subjects {samples: [{t, faces, people, salient}], shots: [t]}`
  is in media source ticks of the forward file, its boxes `{x, y, w, h, c}` 0…1 of the upright
  picture from its top-left (CJ-22, VR-10). Into clip time: a sample is kept when
  `in_played_window`, at clip tick `clip_time_of_source(…, Down)`; shots likewise, a cut at clip
  tick 0 or at or past the clip's duration dropped; then the kept samples, and separately the
  shots, are sorted ascending (a reversed clip's arrive descending), of samples sharing a clip
  tick only the earliest media tick's kept, duplicate shots collapsed — only then do the choice
  and the median see them. A box point (bx, by) is `u = (bx·mw − mw/2, by·mh − mh/2)` px from the
  UNCROPPED centre (`mw × mh` the media's displayed size) and lands on the source canvas at
  `anchor + s·u` ((★) at θ = 0, `anchor` and `s` the clip's base `video`); the crop moves only
  the picture's extent, the cropped rect `anchor + s·(c ± (cw/2, ch/2))`, so a crop never
  invalidates the cache. `plan_framing(project, clip, subjects, request, tuning)` answers no path
  for no such clip, a clip that is not a media clip of a video media, a base rotation other than
  0, a media with no size, a crop or scale that leaves no picture, a zoom outside 1…4 or a zero
  `from_width`/`from_height`; VR2a2's op refuses each by name before calling it. The path is F,
  the similarity from the source canvas (`from_width × from_height`, `Ws × Hs`) to the current
  canvas `W × H`, keys `(t, scale k, x dx, y dy, curve)` composed into a placement as `scale′ =
  k·scale, x′ = k·x + dx, y′ = k·y + dy` (VR-3, VR-27): `k = zoom · fill / s`, `fill` from
  `Project::fill_scale` over the cropped size, `k·s` at most `SCALE_MAX`; the window on the
  source canvas is `W/k × H/k` centred at `wc`, `dx = k·(Ws/2 − wc.x)`, `dy = k·(Hs/2 − wc.y)`;
  every key's `wc` is clamped so the window lies inside the cropped rect (VR-7's covering key).
  Keys are strictly increasing in time, the first at 0, each snapped with `time::snap_to_frame` at
  the canvas rate and inside `[0, clip.duration]`; between keys the segment ending at a key eases
  with that key's curve through `actions::ease`.
  **Amended 2026-11-03 (VR2a2, VR-26):** the op lands without `replace`, which joins with VR-27
  in VR2b; VR-24 (a) maps shots with `Round::Up`.
- **VR-21 — Choosing the subject** (`core/src/reframe_tracks.rs`, `choose_subject`; tracks built
  by the planner over what it reads, CJ-31, nothing stored). Per kind, a box links to the track
  whose last box is at most `LINK_GAP` (1 s) earlier with the highest IoU at least `LINK_IOU`
  (0.3), one box per track per sample, else starts a track; every cut ends every track. Track ids
  are 0, 1, 2… in creation order, samples in time order and within one faces, then people, then
  salient. A track's score at a sample is over the samples in `[t − 1 s, t + 1 s]` of the
  sample's shot: presence (the share of those samples where it has a box) × the median area (w·h)
  of its boxes there × centrality `1 − min(1, ‖centre − (0.5, 0.5)‖ / (0.5·√2))` of its box at
  the sample. With `follow` `subject`, a present face track outranks people and people outrank
  salient regions, which count only at samples with no face and no person; a person track whose
  box holds a face track's centre in at least `BODY_SHARE` (80 %) of their shared samples is that
  face's body — never its rival — and carries the subject while the face is absent (the face
  takes it back on its return). Within a tier the primary stays while present; a rival replaces
  it only after scoring at least `RIVAL_MARGIN` (1.25) × the primary at every sample for
  `RIVAL_HOLD` (2 s); with the primary absent, the best present track at once; with nothing
  present, nothing is chosen. A shot's first sample picks the best, with no hysteresis. `face`,
  `person` and `salient` read only their own kind. Ties go to the lower track id.
  **Amended 2026-11-03 by VR-24 (c):** with the primary absent the best present track is output
  as a stand-in (`lost`) and the primary kept for `LOSS_HOLD` (1 s), instead of replaced at once.
- **VR-22 — Composition** (first numbers; VR-S2's verdict below). With the window `w × h` on
  the source canvas: a face's centre on the window's vertical centre line, at `headroom × h` (0.38) from the
  window's top when `h > w`, else at the window's centre; a person (no face chosen): the box's
  horizontal centre on the centre line and its top `0.12 × h` from the window's top; a salient
  region: its centre at the window's centre. **Amended 2026-11-02 by VR-S2's verdict (VR-23):**
  the headroom stays 0.38. The canned run could not measure it — at zoom 1 a 9:16 window on a
  16:9 picture is the picture's full height, so its centre's y is held at the picture's and every
  headroom contained the same samples — and the rule's tie went to the default's value. The
  person's 12 % was not in the grid and stands.
- **VR-23 — Moves** (first numbers, until VR-S2's verdict below: dead zone 0.10 of the window's
  width and 0.08 of its height, speed 0.5 windows a second; `FRAMING_TUNING` in `reframe.rs`).
  The subject point (a face's or a salient region's centre, a person box's top centre) is median-filtered per axis
  over the samples within ±0.5 s with the same chosen kind in the same shot, and the desired
  window centre is VR-22's from the filtered point, clamped. The first key, at 0, is the first
  chosen sample's desired centre (the cropped picture's centre when nothing is chosen anywhere).
  A move starts at a sample when the desired centre is beyond `dead_zone_width × w` or
  `dead_zone_height × h` of the current one; it targets that centre and lasts `max(0.4 s,
  distance ÷ (speed × w))` (Euclidean, source-canvas px); it is written as a hold key at its start
  (`linear`, the current value) and an `ease_in_out` key at its end. No move starts while one
  runs, nor within 0.5 s of the last one's end unless the filtered point is outside the current
  window. Snapped: a hold key whose tick is at or before the previous key's is not written (the
  move eases from that key); a move's end is at least one frame after its start; a move whose end
  would pass the clip's end is not started. With no chosen subject the window holds (VR2a2's
  VR-24 replaces this rule with loss, hard cuts and two people). **VR-S2's run and rule, fixed
  before it runs:** six canned inputs, each a 1080 × 1920 target at 30 fps from a 1920 × 1080
  source (the clip at scale 1, x = y = 0, no crop, forward ×1) at zoom 1 (the window 607.5 ×
  1080 source px, its centre's x clamped to 303.75…1616.25), samples every 100 ms, a face box
  0.08 × 0.14 of the picture at confidence 0.9, no randomness: (a) pan, 20 s, the face centre
  linear from x = 400 to 1520 px at y = 432; (b) exit, 10 s, still at (960, 432) for 4 s, absent
  2 s, back at (1100, 432) for 4 s; (c) two faces, 20 s, at x = 760 and 1160 for 10 s then 260 and
  1660 for 10 s, the left box 1.2 × the right's area; (d) still, 60 s, at (960, 432) with
  `x += 0.005·W·sin(7.3·t)`, `y += 0.005·H·cos(5.1·t)` (t in s); (e) cuts, 30 s, shots at frames
  300 and 600, the face still at x = 0.3, 0.7 then 0.5 of the width, y = 432; (f) card, 20 s, no
  boxes and no shots — 160 s in all. The grid: dead zone {0.06, 0.10, 0.15} of the width (the
  height's 0.8 × it) × speed {0.3, 0.5, 0.8} × headroom {0.33, 0.38, 0.42}. Per setting, pooled
  over the inputs: containment is the share of every sample where a face is chosen whose face
  centre lies inside the window's central 60 % in both axes at the path's value there; moves per
  minute is every move ÷ the 160 s. The rule: the highest containment at no more than 6 moves a
  minute, ties to fewer moves, then to (0.10, 0.5, 0.38); if no setting is at 6 or under, or that
  winner is under 97 %, the dead zone is fixed one step below the winner's (0.06 stays; with no
  winner, below 0.10) and the choice re-made among that dead zone's settings at no more than 8
  moves a minute, its containment recorded whatever it is; if none of them is at 8 or under, the
  verdict is STOP — recorded, `FRAMING_TUNING` left at the first numbers, and put to the owner.
  S-TH1, T1 and T2 do not exist yet: their rows are skipped by name and owed. **Amended
  2026-11-02 by VR-S2's verdict:** macOS 26.5.1 (25F80), Apple M2 Max, on AC power, three lanes
  on the machine; `rule_sha256` `f55e33e6…13cce3870e7`, matching CJ0a's table. The first arm:
  dead zone 0.15 of the window's width and 0.12 of its height, speed 0.8 window widths a second,
  headroom 0.38 — containment 1,358 of 1,380 counted samples (98.41 %), 15 moves in 160 s (5.62 a
  minute); `FRAMING_TUNING` is these. Containment moved only with the speed (0.3: 95.94 %, 0.5:
  97.46 %, 0.8: 98.41 %) and moves only with the dead zone (0.06: 25, 0.10: 21, 0.15: 15); the
  headroom moved neither (VR-22's amendment). The rule's last tie-break, "then to (0.10, 0.5,
  0.38)", did not say what a tie without that setting goes to; it goes to the tied setting
  sharing the most of its values, so 0.38 over 0.33 and 0.42 (the first run broke the tie by grid
  order and printed 0.33; the instrument was corrected and run again before this entry). The
  verdict's inputs: pan 200 of 200 contained, 11 moves; exit 80 of 80, 1; two faces 194 of 200, 1;
  still 600 of 600, 0; cuts 284 of 300, 2; card none counted, 0 (`VR-S2/results.json`,
  `rule_matches: true`). S-TH1's and T1's and T2's rows are owed; JOB-31 judges the feel.
  **Noted at CJ7b (the owner, 2026-11-06), not an amendment:** S-TH1's row ran at CJ7 (road map
  VR2a1's record) and stopped: the shipped (0.15, 0.8, 0.38) makes 8.45 moves a minute on S-TH1
  at 2,581/2,662 = 96.96 % contained, the grid's fewest is 8.04 at dead zone 0.15, and pooled with
  the six canned inputs the shipped setting makes 7.58 at 95.03 %. The owner: "Keep it; I'll judge
  it." The shipped setting stays, JOB-31 judges whether it is busy, and T1's and T2's rows stay
  owed.

## CJ6 — the clip ceiling (2026-11-02)

- **CJ-60 — CJ-S1's verdict: 4,096 kept.** No N in the bench passes CJ-S1's rule, so `MAX_CLIPS`
  and `RC_MAX_CLIPS` stay 4,096, CJ-9 keeps its first arm, and CJ6 ends with this verdict and no
  code: TX and SW design around the ceiling, reading `RC_MAX_CLIPS`.
  - **The run.** `tools/proof/creator_spike/ceiling_spike.py` (`rule_sha256`
    `e4ead1af…3c772d12e2f5`, matching CJ0a's table) against a scratch Release build with both caps
    at 65,536, never committed; macOS 26.5.1 (25F80), Apple M2 Max, 96 GiB (103,079,215,104 bytes),
    on AC, three lanes on the machine (one-minute load average 127.64 at the end). N one-second
    clips of the 1080p fixture over four tracks, `--headroom 0`. Every timed split answered
    applied (each MCP split added exactly 4 clips, the 50 of row (8) 200), and row (7)'s zoom
    assertions held in every sample.
  - **The figures** (medians; (4)–(6) over 3 runs), N = 4,096 · 8,192 · 16,384 · 32,768, the
    rule's bound in brackets:
    (1) split 2.7 · 5.3 · 30.2 · 42.4 ms [50];
    (2) open + plan 34.6 · 75.7 · 258.0 · 393.3 ms [500];
    (3) recipe 0.8 · 1.6 · 4.6 · 8.3 ms [2];
    (4) `ripple_delete_ranges` of 100 ranges 3,664 · 10,088 · 32,145 · 175,965 ms [1,000], its
    undo 56 · 110 · 230 · 598 ms [1,000];
    (5) the next `get_project` 164 · 265 · 996 · 2,117 ms [1,000];
    (6) the first frame after a split at most 0.9 · 1.0 · 2.4 · 2.6 s [2];
    (7) the timeline at the fit zoom 281 · 491 · 902 · 1,085 ms and at the default zoom 126 ·
    133 · 150 · 206 ms [33];
    (8) RSS growth over 50 splits 0.41 · 1.95 · 3.67 · 6.21 GB [6.44, a sixteenth of physical].
  - **What holds 4,096 down.** At N = 4,096 three rows fail: (4) at 3.7 s and (7) at both zooms.
    (7)'s time is the draw (`cacheDisplay`): 268 of 281 ms at fit and 116 of 126 ms at the
    default zoom, the view made, laid out and updated in under 12 ms. A smoke run at N = 512
    already drew in 94 ms (fit) and 123 ms (default), so the default zoom's cost is not the
    clip count's. (4) at 512 clips took 357 ms. Neither is CJ6's to speed up; both are filed.
  - **A discarded first run.** The instrument's first full run gave the same verdict (at 4,096,
    (4) 4.0 s, (7) 395 and 161 ms), but at 32,768 two of its three row-(6) splits answered an
    identity: an autosave in place during a three-minute ripple had written the last run's split
    into the package. The script now writes the package's own `project.json` back before every
    reopen; the recorded run is the second.
  - **What a raise would have needed** (recorded for a later ceiling): `TranscribeSheetController
    .refresh()`'s tick sum over clips does not saturate, so the bound in `Transcriber+Jobs.swift`
    leans on 4,096 × 10¹⁵ < 2⁶³; `shot_split_proof.py`, `transcript_cut_proof.py` and
    `cloud_captions_probe.py` spell the ceiling as a literal; five core tests spell 4,095–4,098.
