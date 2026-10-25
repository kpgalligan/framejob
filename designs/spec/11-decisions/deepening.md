# Spec §11 — decisions: Deepening (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **D2-1 — A refused op says why in the CORE's words; a tool still names an
  argument the caller left out.** Deepening D2 gave every rule that refuses
  a sentence of its own and deleted the app's copies
  (`archive/roadmap-7.md` §4–§5), so no agent handler trial-applies
  an op in order to write a reason. The line between the two, drawn at D2·4
  because six handlers answer a caller before the core sees the call: **a
  check that predicts a RULE goes; a check that names the CALL stays.**
  `set_transition_style` with neither key, `ripple_delete_ranges` with an
  empty array, and `set_track`, `set_marker` and `set_canvas` with no keys
  are the second kind — the core answers an identity, correctly, and an
  identity says only that the project is already in that state, which tells
  a caller who forgot an argument nothing it can act on. So is
  `normalize_clip` with nothing it could MEASURE: the peaks are in the
  package's cache and not in the model, so that is a fact the core cannot
  have (§7). **This amends the seventh Implementation Decision of
  kpgalligan/framejob#8**, which had listed `set_transition_style`'s refusal
  and `normalize_clip`'s check among the deletions; the first is one of five
  of a shape, and deleting one of five would leave the tool surface
  inconsistent for a caller.
- **D3-1 — The core says what an argument IS; the app says what it is FOR.**
  Deepening D3 made the op table a published interface
  (`archive/roadmap-7.md` §7–§9): `core/src/op_table.rs` holds one row
  per op and one `Argument` per argument — name, `Kind`, required — and
  `rc_op_schemas` publishes it as JSON Schema, which all fifty-seven op tools
  PRINT instead of hand-writing a `"type"`, an `"enum"` or a `required` list.
  The app keeps what the core cannot know: the sentence naming the menu item a
  tool mirrors and what the argument is for. **Where the line falls in the
  hard cases**, drawn at D3·3 because two tools would otherwise have got worse
  on the way through: a bound the core REFUSES outside is the core's and is
  published from the table, sourced from the constant the refusal is written
  against and never retyped; a bound the core merely CLAMPS to, a null that
  MEANS something, and a bare-string shorthand are the APP's, each a row of
  `AgentCatalog+Declarations.swift` carrying the op, the argument, what the
  app adds and why. The direction is the whole of the rule: **a schema
  narrower than what a tool accepts costs a caller nothing; one wider is a
  promise the app breaks.** This is what makes the *One JSON op entry point*
  decision above true as it was written — "the MCP catalog is the same table"
  — where until D3 the catalog was a hand copy of one.
- **#21 — A call is checked against the schema its tool published, at the
  door, for every tool.** The agent handlers read a caller's arguments by
  name and build the op, so an argument no handler read collided with
  nothing and was dropped in silence — an optional argument misspelt, an
  argument no op takes, a required one misspelt and reported as the right
  name missing. The fix is one comparison at dispatch
  (`AgentServer+Gate.swift`): the caller's keys against the tool's published
  `inputSchema`, every stranger refused naming the tool, the strangers and
  the whole of what the tool takes. Two choices, taken with the fix
  (`archive/roadmap-7.md` §11.6): it covers **all seventy-seven
  tools** and not the fifty-seven ops, because the app-state tools have the
  same defect and the comparison reads a published schema either way; and it
  speaks the **app's** sentence rather than the core's serde wording, because
  twenty tools have no core sentence to borrow and `noSuchId` set the house
  style. **What it deliberately is not** is the handlers forwarding a
  caller's op to the core unread — §11 measured that at 21 named refusals, 6
  app-state defaults, 11 per-op transforms and one correctness guard, and the
  gate buys the same contract and gives up none of them. The same class one
  reader down went with it: a whole number is read exactly, so `3.7` where an
  id belongs is refused and never truncated to 3.

- **#22 — A media clip's window stays INSIDE its file, on the grid.** A
  clip's duration is written from its source at three sites —
  `whole_media_length` (what `add_clip` gives a clip, and therefore how much
  room `insert_clip` opens and how much span `overwrite_clip` clears),
  `set_canvas`'s fps `resnap`, and `trim_end`'s tail clamp — and all three
  snapped to the NEAREST frame, which rounds UP past the end of the file
  whenever the last frame is more than half a frame short. The plan then
  handed `evaluate.rs` a segment whose `source_duration` was the clamped
  remainder rather than the clip's duration, so the rate came out just under
  1 and AVFoundation RESAMPLED material nobody had asked to retime. All
  three now snap DOWN: a media clip satisfies `in + duration × speed ≤
  media.duration` by construction and its segment plays at rate exactly 1.
  Three costs, taken: a whole-file clip may end up to one frame before its
  file's last sample; a timed media shorter than one canvas frame cannot be
  a clip at all and `add_clip` says so in a second `Err` sentence naming the
  frame; and an fps change may shorten a whole-file clip by a frame. The
  shape DECLINED was holding the last partial frame — carrying a sliver
  through the plan and the compositor so the file's final sample always
  plays — which buys a sub-frame of picture at the price of a sub-frame time
  in the model, and nothing sub-frame lives in the model (§6). The sites this
  entry left uncovered are **D4-2 to D4-4**, which measured each one and made
  the rule true at every writer of a media clip's window through one bound
  function. `evaluate.rs`'s clamp stays: hand-written JSON, a version-8 file
  minted before this, and the one-frame floor `resnap` cannot go below still
  reach it. No persisted field changes, so `RC_FORMAT_VERSION` stays 8.
- **D4-1 — A clip's content length is ONE function, and the plan obeys it.**
  `archive/roadmap-7.md` §10.3's unverified reading is confirmed:
  `evaluate.rs`'s `segment_of` held a second copy of `content_length`, and
  the two differed in the degenerate case. The `clip.duration` fallback
  there against the reader's `clip.duration.max(1)` is NOT observable —
  `validate` refuses a non-positive duration and `segment_of`'s own
  `.max(1)` covers what is left. The observable difference is the
  THRESHOLD: `> 0.0` in the plan against `>= 1.0` in the reader. For a
  finite `0 < duration × speed < 1` — under one tick of source, reachable
  by hand-written JSON only, since every op holds speed in ×0.1 – ×10 (×0.1 – ×1000 since #190) and a
  duration at a frame or more — the plan's `source_duration` was 1 and is
  now `min(duration, remaining).max(1)`, which is the 1:1 fallback `slip`,
  `set_speed`, `rate_stretch` and the app's `Transcriber.contentLength`
  already read. The plan is the caller here: there is one function,
  `Project::content_length_in_source` (`core/src/source_window.rs`), and the
  plan reads it. **Declined**: letting the plan's threshold win, which would
  change three ops' arithmetic and put the Swift mirror out of step with the
  core for the sake of the same degenerate clip. No persisted field changes,
  so `RC_FORMAT_VERSION` stays 8.
- **D4-2 — THE bound takes the pieces, and `start` is one of them.**
  `Project::longest_duration_on_grid_of(start, media, in, speed)`
  (`core/src/source_window.rs`) is the one arithmetic every writer of a
  media clip's window now reads:
  `Timeline((snapped_down(start + floor((media.duration − in).max(0) /
  speed)) − start).max(0))`, and `Unmeasured` for a speed that is not
  positive and finite. At `start = 0` it is `snapped_down(available)`, a
  grid LENGTH — what a site writing a DURATION wants, and exactly what
  `longest_duration_on_grid(clip)` has always answered. At
  `start = clip.start` the END lands on the grid — what `trim_end` and
  `roll` write today. **The two differ**, for an off-grid start and by a
  tick at a rate whose frame is not a whole number of ticks (24981/1000),
  which is why `start` is a parameter and no existing answer moves: #22's
  three sites and `roll`'s tail read the new function with the same answers,
  `trim_end` with an off-grid start included (its end stays on the grid, a
  pinned row in `core/tests/source_edges.rs`). The unsnapped division is
  `source_length_on_timeline`'s and is not written twice.
  **`trim_end` on an `Unmeasured` window STAYS unbounded**: it is reachable
  by hand-written JSON only (`validate` refuses unknown media and every op
  holds a speed in ×0.1 – ×10, ×0.1 – ×1000 since #190), `evaluate.rs`'s clamp covers what it can
  produce, and reading it as "empty" would freeze an edge over a field no
  trim can fix. No persisted field changes, so `RC_FORMAT_VERSION` stays 8.
  **Amended 2026-10-01 by R6-10's amendment (#41):** `validate` now refuses
  a speed outside ×0.1–×10 (×0.1 – ×1000 since #190) on read and in every edit's `finish`, so a
  speed-made `Unmeasured` window is reachable by no file and no edit. The
  reading stays as the defence it describes, pinned at the `SourceBound`
  level in `core/tests/source_window.rs` and `source_edges.rs`.
- **D4-3 — `set_speed` snaps NEAREST and is then held to the bound AT THE
  NEW RATE.** #22's own trade applied to speed. Measured before the change:
  a whole-file clip of a 6 233 613-tick media at ×2 had a duration of
  3 120 000 and a plan `source_duration` of 6 233 613 — a segment rate of
  1.99795, AVFoundation resampling material nobody asked to retime
  (`tools/proof/silence2_proof.py` claim 1(d)). `Project::duration_at_speed`
  reads the content length off the clip AS GIVEN, divides by the new rate,
  snaps to the NEAREST frame as it always did, and then holds the result to
  the bound measured at the NEW rate: 3 100 000, whose segment rate is
  exactly 2. Three costs, taken: a clip at the tail of its file gets up to
  one frame shorter than the nearest snap asked for; ×2 followed by ×1 at
  that tail is no longer an identity; and the one-frame floor still wins
  over the bound, which is what `evaluate.rs`'s last-line clamp stays for.
  `rate_stretch` needed no change and its vector is in
  `archive/roadmap-7.md` §10.8: it writes `speed = content / duration`
  and leaves both the content length and `in` alone, so
  `round(d × (c/d)) == c` and the window it had is the window it keeps.
  No persisted field changes, so `RC_FORMAT_VERSION` stays 8.
- **D4-4 — every re-snap of a media clip's duration is one function, and a
  timed plate is held to its file.** `Project::duration_resnapped` —
  `snapped(duration).max(frame)`, then `.min(bound).max(frame)` — is what
  `set_canvas`'s `resnap`, `paste`'s clip loop, `paste`'s `absorb_nests` and
  `unnest_clip` write. Each was measured overrunning first: a 650 000-tick
  payload clip of a 655 000-tick media landed at 660 000, and a nested
  whole-file clip of a 645 000-tick media opened at 650 000 after an fps
  change to 24. And `add_background`'s `media` plate, for a Video or Audio
  file, is `duration.min(whole_media_length(media))`, default duration or
  given: a 6 000 000-tick video on a 12 000 000-tick timeline was a plate of
  12 000 000 whose segment played at rate 0.5. That **overturns**
  `edit_background.rs`'s "the one thing it does NOT do is clamp a timed
  media to its own length" paragraph, whose "shows nothing for fifty-five
  seconds" was false — the plan stretched the file over the whole plate — so
  the plate now ends where its file does and the backdrop's own two `Err`
  sentences are `add_clip`'s, through the same function. An image plate is
  unchanged: it has no source bound at all. No persisted field changes, so
  `RC_FORMAT_VERSION` stays 8.
- **D4-5 — a head bound is snapped UP, in one spelling.**
  `Project::earliest_start_on_grid` is `snapped_up(clip.start − head)`, the
  timeline POSITION a front edge may not pass, and it is what `trim_start`,
  `roll` and `add_transition`'s `head_handle_frames` each read — the third
  was already this arithmetic, `roll` had the snap, and `trim_start` did
  not. Measured: a ×2 clip with `in` 130 000 starting at 200 000, dragged to
  the far left, landed at 135 000 — six and three quarter frames, a
  sub-frame time in the model, which nothing else in the crate writes. It is
  a POSITION and therefore NOT a `SourceBound`: `or_empty`'s `Some(0)` is a
  LENGTH and would read as "back to tick 0". `None` means no window and no
  clamp, an `Unmeasured` head is EMPTY (all three callers' reading today),
  and the value may be negative, so each caller keeps its own `.max(0)`.
  The one other corner it changes: a far-left trim of a clip whose start is
  ALREADY off the grid with no head left now lands on the next frame INSIDE
  the source, where it used to be an identity — `roll`'s answer at the same
  edge, taken on purpose. No persisted field changes, so
  `RC_FORMAT_VERSION` stays 8.
- **D4-6 — the reversed mirror is APP arithmetic with ONE home, and the
  Speed sheet's readout is the core's own answer.**
  `archive/roadmap-7.md` §10.6's fourth decision, built as phase C.
  The core keeps no mirror — `edit_clip.rs`'s `set_reversed` argues why: `in`
  is measured in the stream the clip PLAYS, and a second convention would
  have to be known by every trim, split and source-length reader in the
  crate. Swift therefore owns it, and `app/Sources/ReverseMirror.swift` is
  the one place it is written: **a reversed-stream tick `p` reads the forward
  file at `pivot − p`, where the pivot is the media's MODEL duration** — the
  number `ReverseRenderer` renders against and the number `in` is measured
  from. `MediaPeaks.window`, `ReverseRenderer.walkBackwards` and
  `TimelineView.sourceTime` all call it; they agreed by convention before and
  nothing asserted that they did. Two costs, taken: the shared spelling is
  ONE TICK HIGH (a reversed tick `p` covers forward tick `T − 1 − p`, and the
  answer is `T − p`), which can take in one extra bucket at an exactly
  aligned window end and leaves one blank waveform column at the head of a
  whole-file reversed clip, and it is not fixed here because
  `tools/proof/silence2_proof.py`'s claim 9 walks the current numbers
  tick-exact; and the pivot was nil for a clip inside a CLOSED nest until
  #64, which looks a segment's clip up through `nests` as well.
  **The timeline now draws a reversed clip MIRRORED.** It did not before:
  `TimelineView.sourceTime` took no `media` and applied no mirror, so a
  reversed clip's filmstrip and waveform indexed the FORWARD cache
  unmirrored and showed the wrong end of the file — measured, and the mirror
  now lives inside that one function so the filmstrip and the waveform cannot
  diverge. `CompositionBuilder` still applies none, deliberately: it
  substitutes the pre-rendered reversed asset, so its times are already in
  the played stream.
  **The Speed sheet's "→ duration" readout is what the core would write**,
  obtained by applying the sheet's OWN `set_speed` ops to the immutable
  handle and reading the durations back (`ReelProject.applying`), not by a
  second copy of the arithmetic in Swift. An edit is pure (§5.5), so asking
  costs a discarded handle and needs no new `rc_*` export. It therefore says
  the three things `set_speed` really answers, which the quotient it replaced
  could not: the new duration is `duration_at_speed` — nearest frame, then
  held to what the FILE still holds at the new rate (D4-3) — and is NEVER
  held to a neighbour, so a clip slowed into the clip after it is (i)
  APPLIED at its full new length when the overlap is at most half the shorter
  of the two clips and reaches one neighbour only, the neighbour gaining a
  minted cross dissolve, and (ii) REFUSED in the overlap rule's own sentence
  past that half or on reaching two neighbours, where the clip keeps the
  length it had. A mixed selection sums the applied clips' new lengths and
  the refused clips' old ones, because `applying` runs past a refusal — which
  is exactly what Apply writes. **Declined**: an `rc_*` query for a speed
  preview (the handle already answers), holding a slowed clip to its
  neighbour in the core (a speed change opens or leaves a gap, §6), and
  fixing the one-tick offset. No persisted field changes, no op-table change
  and no new export, so `RC_FORMAT_VERSION` stays 8.
- **D7-1 — Structural times have one admission envelope.** Every stored media
  duration, marker time, top-level or nested clip start, duration and source
  position, and action start and duration must lie in the inclusive interval
  ±9,000,000,000,000,000 ticks. A clip or action endpoint must lie there too,
  calculated without signed overflow. Existing positive duration and
  nonnegative clip start rules keep their precedence. Files from all supported
  versions remain readable if admitted; an out-of-envelope file fails by
  named path without being rewritten. The same rule applies to writes and
  completed edits, without changing format version 8 or the accepted range of
  finite positive speeds. Property vocabulary times are outside this rule,
  except `text.words` (format version 9, W-3): each word's `start` and `end`
  is held to the same envelope by `check_text` at every patch door, and a
  refusal names the path (`text.words[2].end`).
- **D7-2 — Transition searches are bounded while retaining their chosen
  result.** On an initially valid affected track, handle transitions retain
  the larger-side decrement path and ripple transitions retain the greatest
  passing whole-frame shift. An already invalid affected track now refuses
  with the overlap rule's sentence before fitting; unrelated tracks do not
  participate. Handle fitting uses the monotone path and ripple fitting uses
  exact forbidden intervals, so neither enumerates timeline frames. Existing
  argument, cut, lock and under-one-frame checks retain their precedence.
- **D7-3 — Normalize clip times when crossing a frame grid.** Changing the
  document fps normalizes top-level clips and each stored nest's clips once
  on the new rate, including orphaned and multiply referenced nests. A size
  change alone preserves frozen nest layouts, and an unchanged fps does not
  rewrite legacy off-grid values. Starts and vocabulary times use nearest
  frame, half away from zero; starts stay nonnegative. Durations use the
  existing one-frame floor and source-tail bound, actions keep their existing
  nearest/floor/inside-clip clamps, motion edge and text animation durations
  may be zero, and a motion period has a one-frame floor. Motion edge
  durations remain independent of clip length. Source positions, media
  metadata, audio envelopes and action-end payloads do not change. A rate
  change preserves existing overlap tolerance, tracks, transition styles,
  action order and the first marker in storage order when markers collide;
  nests have no markers. Paste and unnest retain their placement, fallback
  and transition rules while normalizing returned clips to the target grid.
  No load-time migration is performed.
- **#42 — A shift moves every clip it moves by ONE delta, counted on the
  canvas's own grid.** `ripple_delete`, `ripple_delete_range(s)`,
  `close_gap`, `insert_time` and `move_clip` move every clip they move by
  the same number of ticks (`edit_time.rs`'s `shift_clips`), so relative
  placement stays exact: two clips that abutted still abut, and no overlap
  is made that was not there. At a canvas rate whose frame is not a whole
  number of ticks (7 fps, 5994/100, 24981/1000) the delta is a difference of
  two grid positions and a grid position is rounded to the tick, so a moved
  start may sit off the grid by up to a tick per shift. **Snapping each
  moved clip on its own is rejected**: at 7 fps, `ripple_delete` of a clip
  at [171429, 257143) with two abutting clips after it at 428571 (85715
  ticks long) and 514286 lands them at 342857 and 428571 if each start is
  snapped apart — a one-tick overlap that `set_gained_transitions` mints a
  `cross_dissolve` on — and at 342857 and 428572 with one delta, abutting.
  **Snapping both edges of each clip is rejected** as well, because it
  rewrites durations, and a media clip's duration is held to its file's
  bound (#22). The risk accepted: such a cut is first drawn one frame later,
  because the compositor samples at the grid's own ticks and a start one
  tick past a grid tick is not yet on at that tick. A canvas rate change
  re-snaps every clip (D7-3) and restores the grid. **`add_transition`'s
  ripple form counts the request as whole frames of the REAL grid**
  (`time::frames_in`) and lands the incoming clip that many grid frames
  back from the cut (`time::frames_back`); its pair limit counts the frames
  that fit in half the shorter clip from the cut (`time::frames_within`), and
  `transition_search.rs`'s forbidden intervals are counted the same way — no
  longer multiples of `Project::frame`'s 1/30 s fallback, which put the
  incoming clip off the grid at such a rate. At a rate that divides the
  timescale nothing moves: with the cut on the grid the three functions are
  `div_euclid(frame)` and `cut − k·frame`. D7-2 and R5-3 stand.
- **#88 — A non-edit a rule declined names the rule's value; a clamp that
  lands where the clip was stays an identity; a list that applied answers
  applied.** Five ops answered an identity where a rule had declined them,
  and now refuse in their own sentence (§5.5, `core/src/outcome.rs`):
  - `roll` with no clip ending exactly at the clip's start — `no clip on
    track {track} ends where clip {clip} begins ({start}), so there is no
    cut to roll`;
  - `detach_audio` with nothing to detach — `clip {clip} has no audio to
    detach: {why}`, where `why` is `it is not a media clip`, `media {media}
    has no audio track` or `its audio is switched off`, asked in that order.
    A non-media clip is a refusal and not the non-media rule's `Err`,
    because Detach Audio is enabled for any selection
    (`validateTimelineAction`) and an `Err` is an error sheet
    (`commitEdit`'s `present(error)`);
  - `set_transition_duration` with no clip before it — `clip {clip} is the
    first clip on track {track}, so there is no clip before it to overlap` —
    and with a duration past the pair's overlap limit, `limit` being half
    the shorter clip snapped DOWN to the grid: `clip {clip} would start at
    {start}, before the timeline, to overlap clip {previous} by {duration}
    ticks; the two can overlap by at most {limit} ticks` when the start is
    below 0, `…, before clip {previous} starts at {previous_start}, …` when
    it lands in front of its predecessor (#175: at 30 fps, P [2400000,
    3000000), X [3000000, 3300000) and 900000 used to APPLY and put X at
    [2100000, 2400000), the pair's order flipped), and with no clause
    otherwise. One condition, `duration > limit`, covers all three, so the
    number named is always one that applies when sent;
  - `close_gap` aimed at no gap — `clip {clip} runs from {start} to {end}
    on track {track}, so {at} is not in a gap` (the first clip in track
    order under `at`) and `no clip on track {track} starts after {at}, so
    there is no gap to close`. It refuses because spec §6 (normative) and
    `edit.rs` already said it did; it is the same case as `roll`'s missing
    cut — the op's target is not there — and it is in neither of §5.5's
    identity families. `refusal_proof.py`'s §4d scored the code of its day,
    not a decision. Clip ▸ Close Gap on a clip, and a double-click past a
    lane's last clip, now show the sentence in CI-10's strip;
  - `add_transition` with a request under one frame — `a transition of
    {duration} ticks is too short to make at the cut before clip {clip};
    pass a duration of at least {one} ticks`, `one` being the smallest
    duration that passes (20000 at 30 fps, 85714 at 7 fps, 20020 at
    5994/100, where the handle form also needs one `Project::frame`;
    **Amended 2026-09-29, by #174**: 10010 at 5994/100, both forms). The
    app cannot reach it at 30 fps: both the inspector and MCP send grid
    values.

  **What stays an identity**: §5.5's two families (an empty selection; a
  clamp that landed where the clip already was — `roll`'s and `slip`'s
  clamps, a trim whose clamps crossed, a rate stretch outside ×0.1 – ×10,
  ×0.1 – ×1000 since #190),
  the unreachable `position` misses in `add_transition` and
  `set_transition_duration`, and `close_gap`'s `end <= start` guard, which
  no `at` reaches. **The list fold is unchanged** (`ReelEdit.swift`'s
  `applying`): a list in which anything applied answers applied, and a
  refusal is named only when nothing did, because CI-10's strip means
  "nothing changed" and the list's own applied edit clears it, and no MCP
  tool sends a list that can be partly refused (`refusal_proof.py` §3).
  Detach Audio over a mixed selection is the one app path that drops a
  sentence.
- **#63 — A relink takes the new file's probe, and a media clip whose
  window runs past the file's end is held to it.** `relink_media` takes an
  optional `probe`, the media descriptor of the new file, from import's own
  `MediaImporter.probe`, with ffmpeg's opt-in step. All three doors take it
  — the Media tab's Relink…, the missing-media sheet and the
  `relink_media` tool — and the tool does not publish it: the host probes
  `path`, G-4's shape. An absent `probe` keeps the record, because
  Consolidate and the open-time re-anchor point at a copy of the same file.
  The entry takes `duration`, `width`, `height`, `fps` and the three flags;
  a different `kind` is refused, because each clip's source kind was
  chosen from it. **Declined: LEAVE**, which breaks #22 at a new writer,
  because the plan's last-line clamp would resample or hold a frame.
  **Declined: REFUSE**, which turns the recovery path for moved media into
  a refusal over one clip. **Chosen, CLAMP**: each `media`-source clip of
  that media, on the timeline and in every stored nest, orphans included
  (D7-3's walk), whose duration exceeds `source_length_on_timeline`'s
  `Timeline` value gets `duration_resnapped` (D4-4). Everything else on the
  clip is kept (`trim_end`'s posture). The one-frame floor wins (D4-3), so
  a clip whose `in` is past the new end is one frame long with its `in`
  kept. Stills keep `at` (D7-3). The overlap rule is not re-checked
  (D7-3): a shortened clip may hold a transition longer than half its
  length, and the next edit on that track refuses until it is fixed; that
  risk is accepted. The missing-media sheet alerts each refused relink's
  sentence after its one grouped edit, #88's fold unchanged (#180). No
  persisted field changes; the format stays 10.
- **#174 — One frame is the grid's own first frame at every rate, and the
  handle form counts grid frames.** `Project::frame` is `time::one_frame`,
  the first grid boundary after tick 0: 85714 ticks at 7 fps and 10010 at
  5994/100. It falls back to 1/30 s only at a degenerate rate, which
  `validate` refuses. Every minimum and floor that reads it follows: a
  clip's, an action's, a transition's. `add_transition`'s handle form
  counts its request, both handles, its ceiling and both neighbour rooms
  in whole frames of the grid (`time::frames_in`, `time::frames_between`),
  and its two edges step from inward grid bases (`time::frames_back`), as
  #42's ripple form does. At a rate that divides the timescale, with
  positions on the grid, nothing moves. **Accepted**: at 7 fps, an edge
  clamped one frame from another (the trims, `roll`) may sit a tick off
  the grid. That is #42's class, and D7-3 restores it.
- **#40 — `close_project` closes a document as File ▸ Close does;
  `save_project {path}` and `new_project {path}` refuse a path another open
  document holds.** `open_project` closes nothing. A window with a sheet
  attached is refused first: the sheet is window-modal work in progress,
  the rule `handleEditorKey` follows (`EditorViewController.swift`).
  Unsaved changes are refused unless `discard: true`, and the tool never
  writes the package. Under autosave in place, "unsaved" means "not yet
  autosaved", and that is all `discard` loses. A closed path named later is
  refused by name. The held-path check runs after `destinationURL`,
  compares canonically, and comes before `new_project` creates anything,
  which removes two documents at one path at its source. (Amended by #234:
  the same check then refuses a path a person's open is still reading.) A
  save to the document's own file stays a plain save (#138). The tool is
  withheld from the assistant (AI-7, amended). Risk accepted: an agent that
  wants a path another document holds closes that document first.
- **#43 — `export_captions` replaces only `srt`/`vtt` (`knownExtensions`)
  in a name; any other extension is part of it (`chart.png` →
  `chart.png.srt`), which is the panel's rule.** The other tools keep
  `replaceableExtensions`, `srt` and `vtt` included, so a still or a movie
  named `.srt` is still renamed. Risk accepted: `talk.mp4` becomes
  `talk.mp4.srt`.
- **#190 — A clip's speed runs ×0.1–×1000; above ×12, in both pitch modes,
  the plan leaves the clip's audio out, and the inspector says so.** The
  range replaces ×10 in R6-10, D4-1 and D4-2: `SPEED_MIN` and `SPEED_MAX`
  (`core/src/edit_clip_timing.rs`) are 0.1 and 1000, `set_speed` clamps to
  them, `rate_stretch` stays inside them, and the reader refuses a speed
  outside them. **What B52a measured** (`tools/proof/README.md`'s B52a
  section): preview at ×120 showed 841 of 869 frames with a 3.445 s stall;
  preview at ×1000, 14 of 936 frames with a 30.285 s stall; export at ×120
  took 157.0 s for 30 s of output; export at ×1000 took 1480.5–1624.5 s for
  32.3 s in the earlier complete run. **The owner's decisions of
  2026-10-01:** keep ×1000, accept that the preview cannot keep up past
  about ×120, and test it later (`docs/manual-checks.md`, SE-7); and leave a
  clip's audio out above ×12, in both pitch modes.
  - **Why ×12.** An h264 export's loudness pass ("Measuring loudness…")
    never finishes once a clip's audio plays fast enough (B52b's notes; all
    on a 320x180 200 Hz tone). First round, at B52a's ×24/×32: a lone
    180 s clip missed a 45–60 s deadline at ×20 and ×24 in either pitch
    mode and at ×28 varispeed (B52a's binary does the same at ×24), and after a 2 s ×1
    clip a ×32 varispeed clip missed 120 s every time, while ×24 (both
    modes) and ×31 varispeed finished there. Second round, at ×16: a
    keep-pitch clip that starts its audio track stalled at ×15 and ×16
    (180 s, 600 s, and trimmed to 2 s), while ×14 (3.4 s) and ×12 (2.8 s)
    finished, as did ×16 varispeed and every ×16 after a ×1 clip. ×12
    leaves a margin below both stalls; `tools/proof/README.md`'s B52b
    section proves ×12 finishes in both modes and every shape. **Background,
    not the ceiling:** B52a's mixer limits — L.speech.spectral = 24 (the
    spectral algorithm hangs at ×31–×32) and L.speech.time_domain =
    L.speech.off = 32 (above ×32 no algorithm produces audio) — hold only
    for the mixer and an audio-only export, and are retired as the
    product's ceiling. The one number is `AUDIO_SPEED_MAX` = 12.0.
  - **The ceiling rule:** `assign` (`core/src/evaluate.rs`) places a clip's
    audio segment only when its speed is at or below `AUDIO_SPEED_MAX`. The
    video segment, the recipe and persisted state do not change, so crossing
    the ceiling is a plan difference and nothing else. The Speed section
    shows "Audio is silent above ×12" under the first selected clip that has
    crossed it.
  - **One pitch per plan audio track.** `place` puts an audio segment only
    on a track whose last segment has the same `keep_pitch`, so every plan
    audio track has one `pitch`, `CompositionBuilder`'s first-segment read
    of the algorithm is correct, and each clip's own pitch setting holds
    (#211). With the ceiling at ×12 no hang depends on it. **Accepted
    cost:** `audio_ramps` exempts only duckers on the voice's own
    COMPOSITION track, so a neighbour abutting a ducking clip on the same
    timeline track, with the other pitch mode, now sits on another
    composition track and is ducked by the ducker's extent and release.
    Today's exemption already depends on A/B placement (an overlapping
    neighbour on the B lane is ducked), so it is accepted, not avoided, and
    pinned in `core/tests/speed_x1000.rs`.
  - **The Fit arm:** `set_speed` takes a `rate` or a `duration`, exactly one;
    a duration is snapped to the grid, held to a frame, and turned into the
    rate that plays the clip's content in it, which is then clamped like any
    rate. The current duration keeps the current rate (no phantom step). The
    Speed section's "Fit to" row sends it, and the Speed sheet's presets gain
    ×10 and ×100.
  - **One home for the numbers:** `speed_limits()` publishes
    `{"min":0.1,"max":1000.0,"audio_max":12.0}` through `rc_speed_limits`,
    and no Swift file types a speed bound. No persisted field changes; the
    format stays 10.
  - **The question (#212, the owner's ask of 2026-10-01).** A person who
    sets a speed that takes a clip with sound from at or below `audio_max`
    to above it is asked first, once, on a sheet: "“N” will be silent at
    ×S." (or "k clips will be silent at ×S." / "… at their new speeds."),
    with Set Speed (the default) and Cancel — the owner's wording, option
    B, 2026-10-02. **The doors:** the Speed sheet's Apply (the question on
    the sheet's own window), the inspector's Speed section — Rate, its
    presets, Keep pitch, Reset and Fit to — through `inspector.onEdit`, and
    the timeline's ⌥-drag rate stretch at its live end
    (`SpeedAudioDrop.swift`, `EditorViewController+SpeedAudio.swift`).
    **The rule** is judged on the core's trial answer against `audio_max`
    (D4-6), never a rate computed in Swift (D2-1): a media clip whose audio
    is enabled, whose media has sound, that plays above `audio_max` after
    the edit and at or below it before. **Not asked about:** a clip already
    above, a clip without sound or with its audio off, and a clip new in
    the answer — a paste, split, duplicate or detach mints it, and
    `paste_attributes` carries no speed (`edit_paste_attributes.rs`'s
    module doc). **Cancel adds no undo step**, and one question covers
    every clip a multi-clip edit takes over. **A rate stretch that
    crosses is put back before the
    question** (`endLiveEdit(_:cancelled: true)`, no step, no change
    count), so nothing is live while the question is up: a save writes the
    base and an agent call is not held (AI-12). Set Speed re-applies the
    gesture's last applied ops as one step named "Rate Stretch". **An agent
    gets no dialog:** every op tool's answer gains `audio_left_out` (the
    clip ids) and `audio_note` (a sentence naming them and the ceiling) when
    its edit crossed, and neither key otherwise (`AgentServer.editResult`).
    The export's loudness stall itself stays unfixed; ×12 keeps it
    unreachable.
- **#87 — On one composition audio track, a gain change with sound on both
  sides takes up to 25 ms — accepted; a track's first segment is held from
  time 0.** AVFoundation's audio mix slews every volume change on an input
  by at most full scale per 1200 frames (25 ms at 48 kHz), starting AT the
  change, and an input sits at the default 1.0 before its first ramp.
  Measured by B59's design spike on a standalone composition read at
  48 kHz in 2 ms blocks: a step 1 → 0 at a cut reads 0.96 0.88 0.80 … 0.08
  0.01 and is silent from cut + 1200 samples, and the same step mid-clip
  slides the same way. **What is done:** `CompositionBuilder.volumeLegs`
  holds each composition track's envelope at its own first segment's value
  from time 0, per composition track as `addAudioTracks` builds it. That
  includes a second source format's track, which carried the plan track's
  ramps up to its own first segment. So a clip that opens its composition
  track muted, fading in, or as a crossfade's incoming clip starts at the
  gain it asks for: in B59's runs, e1's overlap edge went from 0.507 to
  0.002 of full scale, a muted clip alone on its track from −27.2 to
  −240.0 dBFS in its first 25 ms, and `mixed_audio_proof.py`'s muted WAV
  after an AAC clip from −28.8 to −200.0 dBFS. The hold reaches the preview
  too, because `Playback` and the exporter read the same `audioMix`.
  **What is accepted:** every gain change on one composition track slides
  for up to 25 ms. At a hard cut to a muted clip on the same track, e1's
  limit row reads `cut_edge` 0.496 of the tone in the incoming clip's first
  25 ms, then −139.9 dBFS. A volume or mute step mid-clip slides the same
  way, and at a step up after a gap it is a 25 ms attack: the 0 → 1 step
  at a WAV's start that `mixed_audio_proof.py` measured before B59 at
  3.000–3.026 s (3.0000208–3.0249896 s). **Rejected:** starting the step
  25 ms early, which silences the incoming clip at the cut but leaves the
  OUTGOING clip reading 0.13 at cut − 4 ms and 0.04 at cut − 2 ms; an A/B
  composition track per format family, so that no two clips share a track,
  which changes family assignment (R2-1) for a 25 ms edge; and an envelope
  applied in the processing tap, which breaks "no tap on an untouched
  export". The owner decided this on 2026-10-01. **Amended by #217**
  (issue batch B61): the hold ends at the track's first SOUNDING segment,
  one whose source resolved; a missing-media or pending-reverse segment
  before it is held over, because it is empty time — `mixed_audio_proof.py`'s
  `missing-first` row, whose muted WAV after a missing AAC copy read
  −28.8 dBFS in its first 25 ms before the fix and −200.0 dBFS after.
- **#86 — A normalised export reads the mix as float, gains it and
  quantises once to the unchanged 16-bit encoder format; an un-normalised
  export keeps the Int16 decode.** Before B60 the write pass decoded the mix
  to 16-bit integer and applied the loudness gain to that, so a mix past full
  scale was clipped by the decode before the gain turned it down, and every
  normalised sample was rounded twice. Now `ExportWriter` reads a gained
  export through `ExportAudioGain.floatMixSettings`, the same dictionary the
  measurement pass reads, so the gain is applied to the signal that was
  measured. `ExportAudioGain` multiplies, clips and rounds to 16-bit once,
  and the encoder gets the format it always got. **Why this shape:** the
  encoders' input format does not change, and neither do any
  un-normalised export's bytes. `export_gain_proof.py`'s G1 proves that
  byte for byte, per audio preset, against a reference from the build
  before. And the gain now sees what was measured: the true-peak ceiling is
  at most 0 dBTP, so a gained hot mix cannot clip. **The risk it accepts:** an
  un-normalised hot mix is still clipped by the Int16 decode, and
  `ExportLoudness.mixClipped` (true only for a mix past full scale written
  with no gain) is what reports it. #86's part 2, a 24-bit WAV/AIFF option,
  is not decided here, and nothing here closes it off: the 16-bit output is
  one constant in `ExportAudioGain`.
- **#178 — The cache passes' save gate has five accepted limits** (issue
  batch B14, #115, #169; the owner, 2026-10-01). The save bracket is
  `ProjectDocument+CacheSaves.swift` and the ledger `MediaCacheLedger.swift`
  (`CacheLedger.publish`, `waitLimit` 30 s, `saveLimit` 120 s);
  `cache_pass_probe.py` is the probe. (1) A first save or a Save As loses,
  for the session, any cache file published after its listing: nothing
  swaps, and nothing re-runs the passes after a save that moves
  `cacheDirectory`. (2) Frames lost between a save's listing and its swap
  leave the strip unmarked, with holes, until the next open. (3) The head
  clears are not gated, so a withdrawal in that window is undone by the
  swap until the pass publishes again. (4) A write that began before its
  pass was superseded, and outlasts `waitLimit`, can land after the
  successor's clear. (5) A save whose completion never arrives gates its
  package's publications until `saveLimit`, 120 s after it began — the
  undo-flush hang `app/CLAUDE.md` names; publications and peaks retries in
  that window are lost for the session, and the expiry is not probed.
  **Why accepted:** each is a cache — regenerable, never required to open
  (§5.6) — lost or stale for at most the session, and each window is
  bounded by a save or by the two limits. The review's two nits are not
  limits: they landed in 9cfa035 (issue batch B29) — `awaitPass` cancels
  its sleeper (`cache_pass_probe.py` W1, mutant `no-cancel-sleeper`) and
  the doc lines say one CURRENT pass per key. **The bound it keeps by
  design:** a relink away from a stuck pass starts only after the full
  30 s wait (S1a measured 30.32 s).
- **#216 — Every Frame Job process opts in to macOS's supplemental VP9 and AV1
  decoders, and an import of a video track is a one-frame decode** (issue
  batch B72; the owner, 2026-10-02). `DecoderSupport.enable()` calls
  `VTRegisterSupplementalVideoDecoderIfAvailable` for VP9 and AV1 once per
  process: at launch, before a cache pass, before a composition looks up a
  track, and in the harness and the formats probe. **What is accepted:** a
  file whose first video frame decodes to 32BGRA through an `AVAssetReader`
  — VP9 Profiles 0 and 2 in MP4 on every Apple-silicon Mac, AV1 on an M3 or
  later — alongside everything that imported before. **What is refused**, at
  `probeAsset`, as `ImportError.undecodable`, with nothing added and no undo
  step: AV1 without hardware decode ("`<file>` is AV1 video, which needs an
  M3 or later Mac."), VP9 Profile 1 or 3 ("`<file>` is VP9 Profile `<n>`
  video, which this Mac cannot decode; VP9 Profiles 0 and 2 import."), VP8
  ("`<file>` is VP8 video, which this Mac cannot decode.") and any other
  codec with no decoder, named by its four-letter code. **Only a reader
  failure whose error is `AVError.decoderNotFound` (-11833) or
  `AVError.undecodableMediaData` (-11855) refuses** (`refusingErrorCodes`).
  Damaged or truncated data in a codec this Mac decodes (measured: -11821,
  -11880) imports as it did before; the check cannot and does not judge a
  file's damage, and a track that yields no sample but completes imports.
  **No bundled decoder:** AV1 software decoding is dropped and VP8 is out of
  scope (the owner, 2026-10-02). **No ffmpeg offer** for `.undecodable`: the
  refusal is final, since a rewrap would carry the same codec. **The risks
  it accepts:** one extra frame decode per import, relink and recording
  segment; VP9's alpha is lost in MP4; HDR VP9 is treated as HDR HEVC is;
  AV1 on an M3 is unmeasured until manual check HS-6; AV1 media already in
  a project on an M1/M2 still shows black, since nothing re-checks at open.
- **#216-R — A WebM or Matroska file is opened by a built-in rewrap, with no
  question: the Rust core indexes the container and Swift copies its first
  video and audio streams, unchanged, into a QuickTime movie** (issue batch
  B73, #216 stage 2 phase 1; the owner, 2026-10-02). **The core reads the
  container** (`container*.rs`, `ffi_container.rs`): it is byte parsing of
  untrusted input, bounds-checked, panic-caught at the FFI and testable
  black-box in `make test`, and the frame grid, the decode times, a laced
  frame's time, the codec setup records and the space estimate are
  DECISIONS. It opens the file read-only and reads no payload but the first
  VP9 keyframe's header and each Opus packet's TOC. **Swift does the rest** (`ContainerRewrap.swift`,
  `ContainerRewrapWriter.swift`): `AVAssetWriter` passthrough, the
  destination and its folder, the free-space query and the refusals' words.
  Neither side touches a pixel or a sample. **Its own walker, not
  `matroska-demuxer`** (measured): the crate reads every payload and exposes
  no file offsets, drops a BlockGroup's keyframe flag (`is_keyframe: None`),
  and its frame-at-a-time order deadlocked a single-thread writer feed.
  **Always `.mov`**, in `~/Library/Application Support/Frame Job/Rewrapped/`
  beside ffmpeg's conversions, under `FFmpegRewrap.destination(for:)`'s
  digest name, so a re-import reuses the copy: `AVAssetWriter` refuses
  Vorbis in `.mp4`, which phase 2 needs, and vp09, av01, avc1, hvc1, Opus
  and AAC all write to `.mov` and read back. **The space check comes first:**
  the core's `required_bytes` (the copied payload, 64 bytes a sample and
  16 MiB) is compared with `volumeAvailableCapacityForImportantUsage` on the
  destination's nearest existing folder, and a copy that will not fit
  writes nothing. **The pre-check:** the codec facts in the Tracks element
  feed #216's sentences — VP8, AV1 without hardware decode, VP9 Profile 1
  or 3 — so nothing is copied that would then be refused; #216's one-frame
  decode stays as the backstop after the copy. **A codec that is not
  copied** (Vorbis, FLAC, MP3, AC-3, MPEG-2 and the rest, or a compressed
  or encrypted track) is refused in its own sentence and FALLS THROUGH to
  the opt-in ffmpeg step; every other refusal is final. **Timing:** video
  is snapped to its frame grid (`nominal_fps` from DefaultDuration, else
  the median gap) when every frame is within a quarter frame of a grid
  point and no two share one, and is written at that grid's timescale, so
  an exact-time request lands on its frame; otherwise — most browser
  recordings — the raw millisecond times and their timescale are kept.
  Decode times are the sorted presentation times shifted back by the
  largest reorder. Audio is timed in samples from the Block time less
  CodecDelay; an Opus packet's sample count is its TOC's. A laced frame is
  its Block's time plus the frames before it in the lace; a laced COPIED
  video track with no DefaultDuration is refused at open. **Amended by
  #232** (issue batch B79): the movie's own timescale, the grid of each
  track's edit and duration, is the least common multiple of 600 and the
  tracks' timescales, where it was the writer's default 600. **What is
  dropped:** every video and audio track after the first of each kind,
  subtitles, chapters, attachments and VP9 alpha. **The risks it accepts:**
  no progress or Cancel in this phase (a copy runs at about disk speed); a
  document opened from the Finder blocks the main thread for the copy, as
  ffmpeg's conversion already does; the Media tab names the copy, not the
  original (amended by #228-O); the copy lives outside the package until Consolidate.
  **Amended by #228-V** (issue batch B77): Vorbis is copied.
  **Amended by NM-4 and NM-5** (rename R0):
  `~/Library/Application Support/Reelcut/Rewrapped/` is now
  `~/Library/Application Support/Frame Job/Rewrapped/`; a codec that is not
  copied is refused in a sentence ending "… which Frame Job cannot copy out
  of a WebM or Matroska file.", where it was "… which Reelcut cannot copy
  out of a WebM or Matroska file.".
- **#228-P — A person's WebM or Matroska copy shows its progress in a small
  window with Cancel, and a tool call's copy shows nothing** (issue batch
  B76, #228 part 1; the owner, 2026-10-03, O1–O8). **Every click door
  reports:** File ▸ Add Media…, a drop into a project, the Media tab's and
  the missing-media sheet's Relink (`ProjectDocument.probeNext` and
  `relinkNext`, through `copyWatch`), and File ▸ Open, a Finder double-click
  and a drop on the Dock or the welcome window (`readMediaFile`, through
  `probeForOpening`). Each hands `ContainerRewrap.assist` a watch, called
  once when a copy really starts (a reused copy calls none), and the copy
  reports its bytes to a `RewrapProgress` (`RewrapProgress.swift`).
  **The window** (`RewrapProgressWindowController.swift`) is a non-modal,
  titled panel with no close box, the same for every door, titled
  "Copying Movie", headed "Copying “`<file>`”", with the bar, "Reading the
  file…" until the copy begins and then "`<copied>` of `<total>`", and one
  Cancel button. **It appears only when the copy is still running 1 s after
  it starts**, so a copy of a few hundred megabytes shows nothing. **It never
  takes the keyboard from a Frame Job window:** while any window is key it is
  ordered front and not made key, so typing and Escape keep reaching the
  editor during an Add Media copy; it becomes key only when no window is
  (File ▸ Open, a Finder double-click), or when the person clicks into it,
  and only then does Escape cancel. It raises no modal and no sheet, and the
  project stays usable. **Cancel** reads "Cancelling…" and is disabled; the
  copy stops at once (each pump stops before its next sample, so at most the
  append in flight lands), the half-written `.partial.mov` is deleted, the
  file is not added and no alert appears; the other files of a multi-file
  import or drop still land; File ▸ Open of the file opens no project (the
  read answers `CocoaError(.userCancelled)`, which no door presents). A
  Cancel while the index is still being read takes effect when the read
  ends. **A re-import** reuses a finished copy silently; a cancelled copy
  leaves nothing, so the next import copies again. **A tool call passes no
  watch:** `import_media`, `relink_media`, `record_screen` and
  `open_project` (which reads on the main thread inside `withoutAsking`,
  where `probeBlocking` drops any watch and `probeForOpening` passes none on
  main) show no window, wait as before and answer exactly as before. MC-5
  holds: there is no MCP progress message and no way for an agent or the
  person to cancel a tool call's copy. **Amended by #231** (issue batch
  B79): `open_project` reads on the lane's thread, not main, still inside
  `withoutAsking`, where `probeBlocking` drops any watch; it shows no window
  and answers as before. **The risks it accepts:** an agent's
  `open_project` of a WebM still copies on the main thread and freezes the
  window for the copy's length (O7, #231; amended by #231: it copies off
  main and the windows stay usable); a quit during a copy
  leaves its `.partial.mov` in `Rewrapped/` until the next import of that
  file removes it (O8); ffmpeg's opt-in conversion still shows no progress.
- **#228-V — A WebM or Matroska file's Vorbis sound is copied into the
  rewrap's `.mov` unchanged, as Opus is** (issue batch B77, #228 part 2).
  **The format:** subtype `vorb` with `mFramesPerPacket` 0, the track's
  CodecPrivate — Matroska's Xiph-laced three header packets — verbatim as
  the cookie, and no channel layout. AVFoundation's own Ogg reader describes
  Vorbis the same way (cookie `02 1e 1c 01 'vorbis'…`); `AVAssetWriter`
  writes it into `.mov` (`.mp4`: `canAdd` false), and the copy decodes
  through `AVAssetReaderTrackOutput` and through `AVMutableComposition` +
  `AVAssetReaderAudioMixOutput`, mono, stereo and six channels (measured,
  macOS 26.5.1, ffmpeg 9.0.2, libvorbis 1.3.7). **The core reads the three
  headers** (`container_vorbis.rs`): the identification header gives the
  rate, the channels and the two block sizes; the setup header is walked to
  its mode table for each mode's block flag. **Each packet carries its own
  sample count**, by the overlap rule: n = prev/4 + cur/4, a packet's block
  size read from its mode number. **Packet 0 is bs0/4 + its own
  blocksize/4**, ffmpeg's convention (ffprobe reads 1024 for ffmpeg's
  2048/2048 encoder and 128 for libvorbis's short first packet), because
  the writer refuses a later append after a 0-frame packet (-11800/-12633);
  counts of 32–2048 there all decode the whole stream. A packet whose mode
  cannot be read — empty, not an audio packet, or past the mode table —
  counts as a short block. **Every packet is placed lead = packet 0's count
  later** than its Block time less CodecDelay, because packet 0 decodes to
  nothing and AVFoundation starts the decoder's output at the track's first
  sample time: on an ffmpeg WebM remuxed so its first Block is at 0 ms (its
  picture 22 ms in), a click ffmpeg places at 1.022 s decoded at 1.020 s
  shifted and at 1.000 s unshifted; where the first Block is at −21 ms, as
  ffmpeg's encoder writes it, both decode at 1.000 s, the writer laying the
  track out from 0 (the probe's T22 and T20). **Rate and channels come from the
  identification header**, over the TrackEntry's; a rate of 0 or above
  10,000,000 is unreadable, as the TrackEntry rate is capped today. **A
  track whose headers do not parse** keeps #216-R's sentence ("… has Vorbis
  audio, which Frame Job cannot copy …") and falls through to the opt-in
  ffmpeg step. **The risks it accepts:** the movie's 1/600 s edit grid
  (a remuxed libvorbis click read 1.0017 s against ffmpeg's 1.003, 1.0027
  with a 48 kHz movie timescale), which affects every copy written before
  #232 (amended by #232, issue batch B79: a copy written from then on has a
  movie timescale that contains its tracks' grids); no end
  trim, so the copy's sound may run up to one packet past the source's
  (144384 samples decoded where ffmpeg decodes 144000); and the headers'
  parse on every open. **Amended by #235** (issue batch B81): **the lead's
  reading holds, and the copy is not wrong.** The 0.000667 s B79 measured
  between the copy's click and ffmpeg's (#232) was the reference's, not
  the copy's. Read from the fixture (ffprobe, 2026-10-03, the designer's
  run and the batch's own): `p22.webm`'s audio Blocks are stamped 0, 22, 43, 64, 86 and
  107 ms for packets 1024 samples apart, with the picture at 22 ms, and
  `p22.ogg`'s packets sit at −1040, −16, 1008 … /48000, each 1024 long.
  ffmpeg's first decoded frame carries the SECOND Block's stamp, 22 ms, so
  its timeline reading puts the click at sample 49056 (1.022 s) where its
  plain decode puts it at sample 48000. The copy puts it at the first
  Block's time, 0 ms, plus (1024 + 48000) / 48000 s: the lead, then the
  decode, 1.021333 s. The 32 samples between the two readings are the two
  stamps' millisecond rounding — the first Block's true time is 16 samples
  (stamped 0), the second's 1040 (stamped 22 ms, 1056) — so each reading is
  0.333 ms from the source and neither is the better one; the lead stays as
  it is. **T22's reference is now sample-exact** (`click_reference` in
  `container_rewrap_probe.py`): the first audio Block's `pts_time` in
  `p22.webm`, plus (the first packet's duration in `p22.ogg`, in samples,
  plus the sample of ffmpeg's plain decode of `p22.webm` that first passes
  0.3) / 48000, held to 0.0001 s; the row prints ffmpeg's timeline reading
  and its difference beside it, held to nothing.
  **Amended by NM-5** (rename R0): "… has Vorbis audio, which Reelcut cannot
  copy …" is now "… has Vorbis audio, which Frame Job cannot copy …".
- **#228-O — A WebM or Matroska copy remembers its original: the media
  is named after it, Reveal in Finder opens it, a relink to another WebM
  records the new one, and a copy that is gone is copied again on open**
  (issue batch B78, #228 part 3; the owner, 2026-10-03, O10–O13 and Q1–Q4).
  **What is stored:** the media key `original`, `{path, bookmark}`, last in
  the media object, written `null` when there is none — format version 11,
  because an older build would drop it. The built-in copy records it on the
  descriptor (`MediaImporter.probeCopy`, the original's path and a
  bookmark of it); `path` and `bookmark` stay the copy's, so everything that
  plays, caches or consolidates reads the `.mov` as before. ffmpeg's opt-in
  conversions record none and keep the `.mov`'s name (Q4; amended by #233:
  a conversion records its original too). **Display:**
  `MediaSnapshot.name` is the one spelling of a media's display name — the
  original's last path component, else the path's — so the Media tab, clip
  labels, the relink sheets, Consolidate's messages and the search all read
  `talk.webm`. **The tooltip** of a Media tab row says where the copy lives,
  on its own line above the drag hint: "`<original path>` — copied into
  Frame Job's Rewrapped folder." while the copy's folder is
  `…/Frame Job/Rewrapped`, and "`<original path>` — copied into this
  project's package." otherwise, as after Consolidate (Q1, Q2). There is no
  badge and no path line. **Reveal in Finder** opens the original, or the
  copy when the original is gone (O11). **Relink:** the probe carries
  `original`, so a relink to a WebM records the new original (copied again,
  with #228-P's window) and a relink to any other file clears it (O12).
  Consolidate and the open-time re-anchor relink with no probe and keep it;
  Consolidate still copies the `.mov`, and the name stays the original's
  (Q2). **The re-copy on open** (`ProjectDocument+MissingCopies.swift`,
  after the re-anchor): a media whose copy is gone — `mediaURL(for:)`
  resolves nothing, or resolves inside the Trash, where Finder's delete
  moves the copy and its bookmark follows — whose original resolves and is
  still a Matroska file is copied again by the built-in copy only (never
  ffmpeg, never a question) and relinked to it with its probe, with no undo
  step, nothing dirtied and no alert. Each copy has #228-P's window after
  1 s, unless the read is on the main thread (amended by #231: or inside
  `withoutAsking`, an agent's `open_project`). A Cancel or a failure skips
  that media: it opens missing (the slate, the badge, Relink…), with no
  alert, and the next open tries again (Q3); a copy in the Trash keeps
  playing from there. The Trash counts as gone for this re-copy only; every
  other reader of `mediaURL(for:)` is unchanged. **Tool calls:**
  `open_project` reads on main inside `withoutAsking`, so its re-copy shows
  no window and raises no question (MC-5) and blocks the main thread for the
  copy's length (#231). **Amended by #231** (issue batch B79): it reads on
  the lane's thread inside `withoutAsking`, so its re-copy still shows no
  window and raises no question, and main is free for its length.
  `import_media` and `relink_media` answer
  `"original"`, the original's path, when one is recorded; `add_media`'s
  descriptor takes `original` as `{path, bookmark?}`; `get_project` carries
  it as the model's own JSON. **The risks it accepts:** a copy that is gone
  while its original has also moved stays missing until a Relink; a re-copy
  on an agent's `open_project` freezes the window, as #228-P's does (amended
  by #231: it no longer does); the
  copy's folder is still Application Support until #226.
  **Amended by NM-5** (rename R0): the tooltip's "copied into Reelcut's
  Rewrapped folder." is now "copied into Frame Job's Rewrapped folder."; the
  folder it is shown for, `…/Reelcut/Rewrapped`, is now
  `…/Frame Job/Rewrapped`.
- **#232 — A WebM or Matroska copy's movie timescale is the least common
  multiple of 600 and its tracks' timescales, so a track's start no longer
  rounds to 1/600 s** (issue batch B79; amends #216-R's Timing and #228-V's
  first risk). **The rule** (`ContainerRewrapWriter.movieTimeScale`, pure):
  `video` and `audio` are the described `timescale` of each track that is
  written, absent when the track is not written or its timescale is not
  positive. The candidates, in order, are lcm(600, video, audio); then,
  only when audio is present, lcm(600, audio); then none. The first
  candidate `s` with (seconds + 1) × `s` ≤ 2³¹ − 1 is set as the writer's
  `movieTimeScale` before `startWriting()`; none leaves the writer's default
  alone. A video-only copy takes lcm(600, video), else none. Overflow in the
  arithmetic is a candidate that does not fit. `seconds` is the largest,
  over the written tracks, of the last decode-order sample's end —
  max(pts, dts) + duration for video, pts + its sample count for audio (the
  described `frames_per_packet` when the packet carries 0) — over the
  track's timescale. **What does not change:** sample times stay in each
  track's media timescale (`mediaTimeScale` on the video input, the sample
  rate on audio, where it is never set); the movie timescale is only the
  grid of each track's edit and duration. The new grid contains the old
  1/600 grid and each track's own, so no time that was exact becomes
  inexact. **The 31-bit guard** exists because what `AVAssetWriter` does
  with a movie duration past it was not measured. **Accepted limit:** it
  reaches only a copy written after it. `ContainerRewrap.assist` answers a
  copy already on disk by its digest name (`FFmpegRewrap.existingRewrap`)
  before the writer runs, so a file copied before #232 keeps its 1/600 grid
  until that copy is deleted or copied again on open (#228-O); the name is
  `FFmpegRewrap`'s and old copies are not invalidated here. **Measured**
  (2026-10-03, macOS 26.5.1, Apple M2 Max; `python3
  tools/proof/container_rewrap_probe.py`, three runs alike, and its
  `--mutant movie-600`, which leaves the writer's default): each copy's
  `mvhd` timescale, read from the file, is 48000 for VP9 at 30 fps with
  Opus (P1), 240000 at 30000/1001 with Opus (P2), 48000 for H.264 with AAC
  (P3), 48000 for Opus alone (P14), 48000 for a variable-rate file's
  millisecond times with Opus (P15) and 30000 for 30000/1001 alone (P23),
  and 600 for all six under the mutant (G24). A Vorbis click whose first
  Block is at 0 ms (P22, T22) decodes at 1.021333 s from the copy against
  ffmpeg's 1.022 s on the source's timeline, 0.000667 s apart; under the
  mutant it decodes at 1.020 s, 0.002000 s apart. The other three clicks
  (P17 AAC, P18 Opus, P20 Vorbis; T17, T18, T20) decode at 1.000 s against
  1.000 s, 0.000000 s apart, with and without the mutant. The probe's
  bounds are therefore 0.0007 s for T22 and 0.0001 s for the other three
  (amended by #235, issue batch B81: T22's 0.000667 s was ffmpeg's timeline
  reading's own millisecond rounding, #228-V; its reference is sample-exact
  now and its bound 0.0001 s like the others).
- **#231 — An agent's `open_project` reads off the main thread and answers
  when the read ends, with no window and no question** (issue batch B79;
  amends #228-P's and #228-O's tool-call and risk sentences; MC-5 holds).
  `open_project` is an `offMainTools` member, in three steps. **Step A, on
  main** (`onMain`): the already-open answer, else the file's type. **Step
  B, on the lane's thread inside `MediaImporter.withoutAsking`:**
  `makeDocument(withContentsOf:ofType:)`, the whole read, as AppKit's own
  concurrent read does it (`canConcurrentlyReadDocuments`). **Step C, on
  main:** the holder re-check — a document that came to hold the path
  during the read wins: the made document is closed, never added and never
  shown, and the call answers `already_open` — then add, window
  controllers, show, the recent note and the answer (amended by #234: steps
  A and C also see a person's open of the path still in flight, and wait
  for it). `withoutAsking` is a
  property of the reading thread and every reader of it runs synchronously
  on that thread (`MediaImporter.isWithoutAsking`), so it covers the probe,
  the copy, the ffmpeg policy and the re-copy on open, which passes no
  watch inside it as it passes none on main. **During the wait:** main is
  free — every window usable; the person may edit, open, close, quit;
  every other tool call, MCP's or any window's assistant's, waits on the
  lane's lock, as during `export` (AI-2); a quit ends the process with the
  call unanswered, as `agent_socket_proof.py`'s K14 shows for `export` and
  its K15 for `open_project` (amended by issue batch B81, which measured
  what B79 argued from K14), and leaves the `.partial.mov` (#228-P O8).
  **The copy lock cannot deadlock:** it is
  never held across a wait on main (a watch only posts to main, and a tool
  call passes none), and the lane's lock is never taken on main or by a
  person's import. **The risks it accepts:** no progress and no cancel for
  the agent (MC-5); other tool calls wait the copy's length; a read AppKit
  itself runs on main still copies there, with no window. **Measured**
  (2026-10-03, macOS 26.5.1, Apple M2 Max; `python3
  tools/proof/agent_open_proof.py`, a 278.8 MiB VP9+Opus WebM, a 10 ms
  main-thread timer counting during each call, three runs): `open_project`
  of the WebM answered in 3.018 s, 1.501 s and 1.403 s, with 107, 50 and 52
  main-thread ticks that saw the copy's `.partial.mov` (A2); the re-copy on
  `open_project` of its package answered in 1.187 s, 0.796 s and 9.504 s,
  with 69, 57 and 373 such ticks (A5); no tick of either saw a progress
  controller (A3, A6); and a document that took the package's path during
  the read was answered as `already_open`, one document at the path (A7).
  With `"open_project"` out of the off-main set (`--mutant open-on-main`) 0
  ticks saw the partial in either call. On the built app,
  `container_import_proof.py`'s M12 opens a WebM by `open_project`.
  **Amended by #235** (issue batch B81): **the spread of those seconds is
  the disk's, not the app's.** The designer ran B79's probe 43 times in a
  scratch home over the same 278.8 MiB fixture (2026-10-03; the data volume
  98 % full, 23 GiB free of 926; load average 7–81): 57 copies answered in
  0.383–8.898 s, five of them in 3 s or more (3.601, 3.704, 6.447, 7.995,
  8.898). In the four slow ones timed, the `.partial.mov` existed for 3.45
  of 3.601 s, 5.99 of 6.447, 7.87 of 7.995 and 8.54 of 8.898 — so the wait
  is not the copy lock, the lane, the index or step C — and it grew the
  whole time, with stalls of up to 1.56 s; `iostat -d -w 1 disk0` read
  45–134 MB/s through the three longest against 289–519 MB/s at the peak of
  a fast copy; `sample <pid> 3 5` of two slow copies found AVAssetWriter's
  `com.apple.coremedia.formatwriter.qtmovie` thread inside `pwritev` in 302
  of 469 and 455 of 464 samples (30–71 of 35–77 in fast runs); and main
  kept ticking through them (77–547 ticks a call, longest gap 94–885 ms).
  Nothing in the product changes for it. **A2 and A5 are counts, not
  timings:** each wants at least 3 main-thread ticks that saw the partial
  (a re-copy's went as low as 13 on that host, so B79's floor of 10 was the
  host's), and each call's row prints where its seconds went: before the
  partial was first seen, while it was written, after it was last seen. One
  run of this batch's (the data volume then 88 % full, 112 GiB free):
  `open_project` of the WebM took 1.146 s — 0.252 s before, 0.210 s while
  the partial was written, 0.684 s after — with 22 partial ticks, and the
  re-copy 0.452 s — 0.065, 0.208 and 0.179 s — with 19. **A quit during
  the read is measured** (`python3 tools/proof/agent_socket_proof.py`, row
  K15: the built app in a scratch home, a 532.2 MiB WebM, K14's quit event
  sent by a sender armed before the call): the event went when the copy's
  `.partial.mov` appeared, 0.099 s into the call, with nothing yet to read
  on the call's connection; the app exited in 0.07 s, its socket file was
  gone, the connection read 0 bytes and closed by EOF, and `Rewrapped/`
  held exactly `big-<16 hex>.partial.mov`. The next launch's `open_project`
  of the same file answered a project whose one media is `big-<16
  hex>.mov`, on disk, with no partial left (#228-P O8).
- **#233 — A file the opt-in ffmpeg step converts records the file it was
  made from as the media's `original`, exactly as the built-in copy does;
  the re-copy on open stays the built-in copy's alone** (issue batch B80;
  amends #228-O's "ffmpeg's opt-in conversions record none" sentence).
  `MediaImporter.probeConverted` sets `original {path, bookmark}` on the
  descriptor of every conversion that probes, on every door through
  `probeAllowingRewrap`, so the name (`MediaSnapshot.name`), the Media tab
  row's tooltip, Reveal in Finder, and `import_media`'s and
  `relink_media`'s `original` are #228-O's, unchanged, and a relink to a
  file ffmpeg converts records it. The tooltip of a re-encoded conversion
  keeps B78's sentence, "`<original path>` — copied into Frame Job's Rewrapped
  folder." (the owner's choice 1, the default kept). **The re-copy on open
  is unchanged: the built-in copy only, never ffmpeg, never a question.** A
  missing ffmpeg-made copy stays missing (the slate, the badge, Relink…): a
  non-Matroska original fails `isMatroska`, and a Matroska one is refused
  `.unsupported` by `ContainerRewrap.rewrap`. The one free case, already in
  the code: a Matroska original whose conversion is still on disk under its
  digest name is relinked to it by `ContainerRewrap.assist`'s
  `existingRewrap`, with no ffmpeg run. **The risk it accepts:** a
  non-Matroska original with its conversion still on disk is not relinked
  (O41's rule). **Measured** (2026-10-03, macOS 26.5.1, Apple M2 Max,
  ffmpeg 9.0.2; `python3 tools/proof/ffmpeg_rewrap_proof.py`, a VP9 + FLAC
  MKV under a scratch home with `-RCFFmpegImport always`): the import's
  descriptor carries `original.path` and a bookmark that resolves to the
  MKV (O1); `import_media` answers `original` and `get_project` carries it
  (O2); the media is named `v0.mkv`, the tooltip's first line is
  "`<the MKV's path>` — copied into Reelcut's Rewrapped folder." and Reveal
  is the MKV (O3); with the conversion discarded the re-copy on open
  answers the same project, ffmpeg's log gains no line and `Rewrapped/` no
  file (O4), and with it still on disk the media's path becomes the digest
  file with no ffmpeg run (O5). With the re-copy sent through the whole
  import funnel (`--mutant recopy-ffmpeg`) O4 fails: the log gains a line
  and `Rewrapped/` a file.
  **Amended by NM-5** (rename R0): the tooltip's "copied into Reelcut's
  Rewrapped folder." is now "copied into Frame Job's Rewrapped folder."; the
  measured run above is quoted as it printed.
- **#227 — The opt-in ffmpeg step copies a VP9 Profile 0 or 2 video stream
  instead of re-encoding it, only when the copy's frame times are exact,
  which the product checks on the copy itself before keeping it; every
  other source re-encodes as before** (issue batch B80; amends
  Foundations' "AVFoundation, not ffmpeg"). **Copies:** the first video
  stream is `vp9`, ffprobe's `profile` is 0 or 2
  (`FFmpegRewrap.vp9CopyProfiles`), its `r_frame_rate` is `N/D` with both
  positive integers, ffmpeg's snapped copy exits 0, the copy's video
  packets sit at `p0 + k·D/N` s for every k with `p0` a whole number of
  frames (the frame check, `FFmpegRewrap.keepsFrameGrid`), and the file
  then probes and decodes its first frame. **Re-encodes, as before:** VP9
  Profile 1, 3 or unknown; no usable `r_frame_rate`; every variable-rate
  source — dropped frames, jittered times, a header rate that is not the
  true rate — because its copy fails the frame check; a user's ffmpeg whose
  `setts` has no `prescale` (the copy fails); a copy that will not decode;
  every non-VP9 codec, untouched. **The file** is MP4-format (`-f mp4`:
  §7.7 measured that ffmpeg writes VP9 into no `.mov`, and B72's V10/V17
  that VP9 Profile 0 and 2 MP4s decode) under the unchanged
  `<stem>-<16 hex>.mov` digest name and `.partial.mov`, so `existingRewrap`,
  `discard` and the built-in copy's reuse are untouched; sound: `aac` and
  `alac` are copied, everything else is AAC at 256k. **The snap:** the
  copy's command is the stream copy's with `-bsf:v
  setts=time_base=D/N:prescale=1` directly after `-c:v copy` (one argv
  element, never a shell). **Frame accuracy does not regress against the
  re-encode:** `setts … prescale=1` rounds each packet's time to the
  nearest 1/rate, which is what the re-encode's encoder time base does, and
  the frame check (`ffprobe -v error -select_streams v:0 -show_entries
  stream=time_base:packet=pts -of csv=p=0`, read before the partial is
  moved into place) refuses any copy where that did not yield consecutive
  frames, so no unchecked copy ever holds the digest name. **The
  fallback** is the frame check, the product's own probe (`waitForProbe`,
  which runs `DecoderSupport.decodesFirstFrame`) or ffmpeg's failure — then
  the re-encode, once (`FFmpegRewrap.assist(…, reencodingVP9: true)`, which
  reuses no file (amended by issue batch B81: but a re-encode this process
  made and kept, below), obeys the policy as the first call does and, under
  `ask`, asks again with the Convert text; a timeout is not retried). The question
  for a copy keeps the stream-copy texts (the owner's choices 2 and 3, the
  defaults kept). **Measured at spec time** (ffmpeg 9.0.2, 128×72
  `testsrc2`, `AVAssetImageGenerator` at zero tolerance asked for frame k
  at exactly k·D/N; "exact" = the answer's time equals the request's): an
  unsnapped copy is exact for 20 of 60 requests at 30 fps (packets 0, 528,
  1072 /16000) and 2 of 60 at 30000/1001, where the re-encode is 60 of 60
  on both; the snapped copy is 60 of 60 at 30 (Profile 0 and 2) and at
  30000/1001 (packets 0, 1001, 2002 /30000), and n of n at 24, 25, 60, 120,
  24000/1001 and 19001/317 (what Matroska reports for 59.94), with packet
  times identical to the re-encode's on each, and a video starting 100 ms
  late keeps p0 = 3 frames in both. Rejected snaps: `-video_track_timescale
  30000` alone on 30000/1001 is 2 of 60 (packets 0, 990, 2010);
  `setts=time_base=…:ts=round(TS*TB/TB_OUT)` exits 0 and 56 of 60 requests
  fail, which is why the product checks the file and not the exit code.
  Variable rate: a source with every fifth frame dropped, and one with
  times jittered by 0/9/18 ms, both report `r_frame_rate` =
  `avg_frame_rate` = 30/1, so no header field tells them apart; their
  snapped copies (0, 512, 1536 … and 0, 512, 1536, 1537 …) fail the frame
  check at k = 2 and re-encode. The frame check on a 10-minute,
  18,000-frame, 101 MB copy took 0.11 s. **Measured by the proof**
  (2026-10-03, macOS 26.5.1, Apple M2 Max, ffmpeg 9.0.2; `python3
  tools/proof/ffmpeg_rewrap_proof.py`, 30-frame 128×72 fixtures, the same
  count over frames 0–29): the command's own output is 30 of 30 right and
  30 distinct times at 30/1 (T1), at 30000/1001 (T2) and for Profile 2 at
  30/1 (T3); the product's kept copies of the same three sources are `vp09`
  after one `-c:v copy … -f mp4` run and count 30 of 30 (V1, V2, V6), the
  first two with an `mp4a` sound entry and a first frame that decodes to
  128×72 BGRA; a Profile 1 source is re-encoded in one run (V3); a copy
  that ffmpeg fails (V4), a copy that will not decode (V5), a jittered
  source (V7) and a gapped one (V8) each import as `avc1` after two runs,
  the copy and then the re-encode, leaving one file and no partial. Without
  the snap (`--mutant no-snap`) the command's output is 10 of 30 right at
  30/1 (T1, T3) and 1 of 30 at 30000/1001 (T2), and the frame check sends
  all three product copies to the re-encode; without the frame check
  (`--mutant no-check`) the jittered and the gapped copies are kept as
  `vp09`. **The risks it accepts:** a
  variable-rate VP9 costs one discarded copy before its re-encode, and
  under `ask` it is asked about a copy and then about the conversion; VP9
  alpha is dropped (#216); a cached VP9 copy re-imported through the
  Matroska door that no longer decodes is refused once and converted on the
  next import. **Amended by issue batch B81**, which closes the two risks
  B80 recorded here (a wait that counted one conversion, and two imports of
  one failing VP9 file each discarding the other's re-encode) and two
  smaller debts. **The wait covers what one import's own runs can take:**
  `import_media`'s and `relink_media`'s wait (`AgentServer.probeCeiling`) is
  `FFmpegRewrap.longestAssist` plus three header probes
  (`MediaImporter.probeTimeout`, 30 s each: the source, the copy, the
  re-encode), and `longestAssist` is the sum of every bound the step has:
  the plan's ffprobe (`planTimeout`, 20 s), the frame check
  (`frameCheckTimeout`, 300 s), the encoder query (`encoderQueryTimeout`,
  20 s), two conversions (`longestConversion`, 4 h each: the copy, then the
  re-encode) and `run`'s grace on each of those five runs (`runGrace`, 20 s,
  half for the tool to exit after `terminate` and half for its pipes). The
  sum counts ONE plan because the second attempt takes the first attempt's
  (`assist`'s `planned`). **One re-encode per file:** under the conversion
  lock the second attempt first asks whether the file at the destination is
  a re-encode this process made and kept — the path's file number
  (`FileAttributeKey.systemFileNumber`) equals the one noted when that
  re-encode finished (`isKeptReencode`, `noteReencode`) — and answers it;
  only otherwise does it discard and re-encode. A conversion that will not
  probe is thrown away only while the file at its name is still the one
  that was probed (`discard(_:ifStill:)`, the file number read before the
  probe), so one import's failed probe never removes a file another import
  has since put there. **A source whose first plan copies no VP9 gets no
  second attempt** (`MediaImporter.probeConverted`): the first attempt's
  error is thrown with no second `assist`, which is the ffprobe run that
  call used to make before answering nil. **The frame check's arithmetic is
  `FFmpegRewrap.onFrameGrid`,** pure: the next expected time is computed
  with `addingReportingOverflow`, only before a further packet, and an
  overflow answers false, where B80 added unchecked after every packet, the
  last included. **The risks that stay:** the note of a kept re-encode is
  this process's own, so a second Frame Job process importing the same failing
  file at the same moment still discards and re-encodes; and the wait counts
  one import's own runs, not the time it queues behind another import —
  conversions are serialised by one lock held for a whole ffmpeg run
  (`FFmpegRewrap.conversionLock`), so an `import_media` that arrives while a
  person's conversion runs can still answer a timeout before its own
  conversion ends (read from the code, not measured).
  **Measured by the proof, B81** (2026-10-03, macOS 26.5.1, Apple M2 Max,
  ffmpeg 9.0.2; `python3 tools/proof/ffmpeg_rewrap_proof.py`, `passed
  22/22`, and `passed 23/23` on 2026-10-04 with #234's row M1 added, with an
  `ffprobe` wrapper beside the ffmpeg one that logs each run): the jittered
  source imports after its two runs with exactly one plan of it in
  `ffprobe.log` (V7); two imports of one jittered file started together both
  import `avc1` at one digest path after 1 encoder run and 1 or 2 copy runs,
  leaving 1 file and no partial, and the second attempt then called directly
  answers that path, `ffmpeg.log` gaining no line and the file's number
  unchanged (V9); `discard(_:ifStill:)` leaves a file that replaced the one
  numbered and removes the one numbered (V10); `onFrameGrid` answers true
  for one packet at 9223372036854774000, the largest multiple of a 3000-unit
  step not above `Int64.max`, and false for two packets from there (G1);
  `probeCeiling` reads 29330 s and `longestAssist` 29240 s (C1); and a
  Profile 1 source whose re-encode will not open imports nothing, with the
  source's own refusal, after one plan and one run, no file left (P1).
  Without the kept check (`--mutant discard-kept`) only one of V9's two
  imports lands, after 2 encoder runs, and the direct call re-encodes again;
  with the second attempt planning again (`--mutant plan-twice`) V7 and P1
  each count 2 plans; `--mutant pure-rows` fails V10, G1 and C1, where the
  ceiling reads 14930 s.
- **#234 — While either side's read of a file is in flight, an agent's
  `open_project` and a person's open of it end as one document at the path,
  or the agent is refused by name past a bound; `new_project {path}` and
  `save_project {path}` refuse a path a person's open is reading** (issue
  batch B81; amends #231's steps A and C and #40's held-path check; MC-5
  and #231's `withoutAsking` hold). **The hole it closes is AppKit's:** a
  document added for a URL while
  `openDocument(withContentsOf:display:completionHandler:)` is reading it
  is not seen when that read ends, so the controller adds a second document
  at the path (measured, below); #231's step C looked only at documents
  already added, and a person's open still reading was invisible to it.
  **The controller knows what AppKit is reading**
  (`ProjectDocumentController`, the app's `NSDocumentController`, made in
  `main.swift` before any other controller can be): its overrides of the
  two public asynchronous opens,
  `openDocument(withContentsOf:display:completionHandler:)` and
  `reopenDocument(for:withContentsOf:display:completionHandler:)`, add one
  to a count for the path's canonical spelling (`AgentServer.canonical`) on
  the main thread before `super`, and take one off in a wrapped completion
  handler before the caller's runs, the key removed at 0; a reopen with no
  URL is not counted. `isOpening(url)` is "the count is above 0", and
  answers false when the shared controller is not this class (a proof probe
  with its own). A launch whose shared controller is not this class logs
  `Frame Job: …`, the startup complaint every MCP proof requires absent.
  **`open_project`** (#231's three steps): **step A**, one main-thread
  block: a holder → `already_open`; else an open in flight → wait; else the
  file's type. **Step B** is unchanged: the read on the lane's thread
  inside `withoutAsking`, never through AppKit's open. **Step C**, one
  main-thread block: a holder → the made document is closed and the call
  answers `already_open`; else an open in flight → wait; else add, window
  controllers, show, the recent note and the answer. **Waiting** is a
  50 ms sleep on the calling thread and the same block again, until
  `AgentServer.personOpenWait` (30 s) after that step's first "wait"; on
  the main thread the deadline is at once, and nothing sleeps there. Past
  it step A refuses — "`<name>` is being opened in a window; call
  open_project again once it has opened." — and step C closes the document
  it made, which was never added or shown, and refuses in the same
  sentence. **`new_project {path}` and `save_project {path}`**
  (`refuseHeldPath`, after #40's holder check, both callers): a path whose
  open is in flight is refused before anything is created or written —
  "`<path>` is being opened in a window, so `<tool>` did not write there:
  call `<tool>` again once it has opened, or pass another path." **Why a
  step is whole:** each is one block on the main thread; the count rises on
  main before AppKit's own already-open check and falls in the completion,
  which AppKit calls on main after `addDocument:`. So a block sees a
  holder, or an open in flight, or neither with no AppKit open begun — and
  in the last case step C adds in that same block, so a person's open that
  begins afterwards finds the document. **The doors, and how each is
  known.** *Driven* (`agent_open_proof.py`): File ▸ Open's own action,
  `openDocument(_:)`, with the panel answered by a probe override (A8);
  the direct call Welcome's Recent row and `FileDropView`'s drops make
  (A10); `reopenDocument(for:withContentsOf:display:completionHandler:)`
  (A11). *Read* (static, this AppKit — macOS 26.5.1 — from a disassembly of
  the 3,513 AppKit methods and blocks whose names match `NSDocument`,
  `NSApplication(NSAppleEventHandling)`, `RecentItemsMenuController`,
  `Seamless`, `DocumentOpen`, `NSPersistentUI`, `NSWindowRestor` and
  `NSWorkspace`; nothing run): `addDocument:` is sent by six functions — a
  block of `_openDocumentWithContentsOfURL:requestedBySourceApp:display:completionHandler:`
  (sent only by the public open), a block of the public reopen,
  `openUntitledDocumentAndDisplay:error:`,
  `_finishOpeningDocument:andShowWindows:` (sent only by the two deprecated
  synchronous opens and `duplicateDocument…`) and two deprecated methods.
  File ▸ Open, an open-documents Apple event (a Finder double-click, a Dock
  drop: `_handleCoreEvent:` → `_handleAEOpenDocumentsForURLs:` →
  `_openURLs:requestedBySourceApp:completionHandler:`), the Open Recent
  menu (`_openRecentDocument:` → `_openURLs:…`) and `_doOpenFile:` →
  `_openFile:` all reach
  `_openDocumentsWithContentsOfURLs:requestedBySourceApp:presentErrors:completionHandler:`,
  whose block sends the public open or the public reopen; its only other
  branch, the deprecated synchronous open, is behind
  `_canPerformBatchedDocumentOpening`, which is
  `_CFExecutableLinkedOnOrAfter`. Restoration
  (`_restorePersistentDocumentWithState:`) and
  `_autoreopenDocumentsFromRecords:` send the public open or reopen.
  *Read* (the app's own source): `WelcomeWindowController`'s Recent row and
  `FileDropView`'s drops call the public open; `AppDelegate` implements no
  `application(_:open…)`; `openUntitledDocumentAndDisplay` (File ▸ New
  Project, the dev assistant launch, `new_project`) adds a document with no
  path; a recording's landing adds its document and gives it its movie in
  one main-thread turn; no product caller reaches `openProject` on the main
  thread (`AgentLane.serve` asserts off main, `submit` runs on a queue).
  **The risks it accepts:** the lane is held for up to `personOpenWait` at
  each of the two steps, so every other tool call waits that long behind an
  `open_project` that is waiting; a hop to main is `onMain`'s
  (`AgentLane.onMainWhenIdle`, unbounded while a gesture is live) and is
  not counted in the bound; the person's open wins, and at step C the
  agent's finished read — a WebM's copy included, which stays in
  `Rewrapped/` — is thrown away; an open whose completion AppKit never
  calls leaves the path refused until quit; an AppKit that routes an open
  around the two public methods reopens the hole, and only A8 would say so;
  and a tool's main hop is not served while the ffmpeg conversion question
  is on screen when the question was asked from a background thread (read
  from the source, not measured: the import queue and a read on AppKit's
  read queue ask there): `consent` runs its modal inside its own
  `DispatchQueue.main.sync`, and a main-queue block is not served from
  inside another, so the tool call waits for the person's answer. Measured
  (2026-10-04, macOS 26.5.1; `ffmpeg_rewrap_proof.py` row M1, `passed
  23/23`, in a `.prohibited` probe that activates nothing): with `consent`
  called on a background thread and the question ended by
  `NSApp.abortModal()` 2.009 s after it came up, `AgentServer.onMain {}`
  called as it came up ran at 2.019 s, the question gone; with `consent`
  called on the main thread itself, from outside any main-queue block — what
  a read AppKit runs on main does unless AppKit runs it inside one, which
  was not looked at — the same hop ran at 0.008 s with the question still
  up; with no question up it is served in under a millisecond. With the
  question put up from a run-loop block instead (`--mutant ask-in-run-loop`)
  the first hop too runs with the question up, at 0.008 s, and M1 fails.
  Where a person's read ran (2026-10-04; `agent_open_proof.py`, `passed
  15/15`, in its `.prohibited` probe, whose two `makeDocument` overrides
  note `Thread.isMainThread` as a person's read is entered): at File ▸
  Open's own action (A8), at the direct call (A10) and at reopen (A11) the
  person's read entered `makeDocument` 1 time, 0 of them on the main thread;
  with the probe's note inverted those three rows fail and no other
  (`passed 12/15`). No row put the question up from a person's read, the
  doors that were read and not driven (an open-documents Apple event, Open
  Recent, `_openFile:`, restoration, autoreopen) were not measured, and no
  door at which a person's read runs on main was found or looked for beyond
  A8, A10 and A11; whether AppKit runs such a read inside a main-queue
  block is still not looked at. It is every tool's behaviour, not this
  decision's. **One window stays:**
  `refuseHeldPath`'s check and the save it guards are two main-thread hops
  (`newProject`, `saveProject`), and the save itself is asynchronous, so a
  person's open of the path that BEGINS after the check — between the hops,
  or while the save writes — is not seen, and by R6 (a Save As onto a URL
  mid-open) ends as two documents at the path. Read from the code and from
  R6, not driven in the product. **Not changed:** two untitled projects of
  one movie made one after the other (no read is in flight; spec §1's own
  behaviour); a person's Save As onto a path a person's own open is reading
  (AppKit's, between two of a person's actions); there is no cancel for the
  agent's wait and no progress over MCP (MC-5). **Measured** (2026-10-03,
  macOS 26.5.1, Apple M2 Max). *That it happens in AppKit:* in a standalone
  `.prohibited` `NSDocument` app whose first read lasts 1.5 s, a document
  added for the URL 0.3 s into the public open's read is not seen when the
  read ends ("documents at URL mid-read 1, at the end 2"), while two such
  opens of one URL are de-duplicated by AppKit ("wasOpen true, documents 1,
  reads 1") — the designer's run. The reviewer's run, over these two
  overrides: a reopen runs off main in a `.prohibited` process and its
  completion is called on main with the document already in `documents`
  (R1); the hole exists through reopen ("documents at the end 2", R2); a
  read that throws calls both completions and leaves the count empty (R3);
  two opens mid-read count 2, then none (R4); a reopen with a nil URL is not
  counted (R5); a document given the URL mid-open, a Save As onto it, makes
  2 (R6). *In the product* (`python3 tools/proof/agent_open_proof.py`: a
  probe over `app/Sources` whose controller is the app's own with seams — a
  finished read is held, off main, until the other side has got as far as
  the row needs, each hold bounded at 120 s; `passed 15/15`, no hold
  expired): File ▸ Open's own action with the agent's call mid-read answers
  `already_open: true`, with one document at the path, the one the person's
  open's completion carries, and the agent reads nothing (A8, A9); the
  agent's read first and the person's open mid-read answers `already_open:
  true`, one document, the person's, and the document the agent made is
  never among the open ones (A10); the same through reopen (A11); with
  `personOpenWait` at 1 s and the person's open held past it, step A refuses
  after 1.136 s having read nothing (A12) and step C refuses 1.201 s after
  the person's open was called, its made document never added (A13), each
  then leaving one document, the person's; and `new_project {path}` onto the
  path being opened is refused with `project.json`'s bytes unchanged (A14).
  With `isOpening` answering false (`--mutant no-inflight`, the app as it
  was before this decision), A8, A10 and A11 each end with "2 open documents
  at the package's path", the agent reads during A8 (A9), A12 and A13 are
  answered a project and leave 2 documents, and A14's `new_project` answers
  "Timed out saving a4.reelcut." with a second project left open. `--mutant
  no-recheck` (step C's holder check off) fails A7 and A10, and `--mutant
  open-on-main` fails A8 and A10–A13 beside its B79 rows, because on the
  main thread the wait's deadline is at once.
  **Amended by NM-5** (rename R0): the startup complaint `Reelcut: …` is now
  `Frame Job: …`; a project is a `.framejob` package (NM-3), so A14's mutant
  now reads "Timed out saving a4.framejob."; the measured runs above are
  quoted as they printed.
- **#326 — An agent's `export` is a job in the Export Queue and answers at
  once; `export_status` follows it and `cancel_export` stops it.** (Amends
  AI-16.) Every refusal `export` had stays synchronous — the arguments, the
  core's settings, the folder — and so does the graphics gate
  (`Exporter.graphicsRefusal`, its "The export was not started: …"), run in
  the handler before anything is queued, so a call that could only fail
  enqueues nothing. Then the handler pauses the editor's playback and
  enqueues in `ExportQueueController.shared` exactly as Add to Queue does
  (the queue captures the media URLs, the reverse resolution and the
  graphics itself), and answers `{export_id, path, status}`, nothing else.
  The status words are the queue's states in the agent's spelling:
  `queued` (waiting), `running`, `done` (completed), `failed`,
  `cancelled`. `export_status {export_id}` never waits: it answers
  `export_id`, `status`, `path` and `elapsed` (seconds, three decimals,
  from the `export` handler's entry to now, or to the finish); `running`
  adds `progress` and the exporter's `phase` when it has one; `done` adds
  every key `export` answered before this (the settings used, `bytes` read
  at the finish, `burn_in_timecode`, `dynamic_range`, `loudness`,
  `graphic_warnings`); `failed` and `cancelled` add `reason`, the queue
  row's sentence. `cancel_export {export_id}` is the row's Cancel
  (`ExportQueueController.cancel`) for a queued or running job, answered as
  `export_status` answers then, and leaves a finished one alone. **The
  records live in memory for the launch** (`AgentExports`,
  `AgentServer+ExportStatus.swift`), for ids `export` returned only — a
  person's own queued job is not reachable — and are copied from the queue
  inside its own change notification, synchronously on main, so a record
  outlives the row's Remove and Clear Finished; a record holds no project
  handle or graphic set. The Export Queue window is not opened for an agent
  export. The queue runs one job at a time, so an agent export waits
  behind a person's (`queued`), and the queue's quit question now covers an
  agent's export as it does a person's. Stop no longer reaches an export
  (AI-16 as amended): the call has already answered; a queued or running
  export stops by `cancel_export` or the Export Queue's Cancel. **Risk
  accepted:** an agent that never asks never learns the outcome, and the
  assistant cannot sleep between polls, so it asks again when its turn
  allows. `tools/proof/export_status_proof.py` (A1–A8, Z1) is the proof;
  every proof that expected the file on return follows the job through
  `MCP.export_with` in `tools/proof/mcp.py`, which returns an older build's
  blocking answer as it is.
- **#336 — A composition audio track none of whose segments has a source
  (missing media, a pending reverse, a pending ramp render) holds bundled
  silence over [0, its last segment's end).** Measured at bb73b35
  (`tools/proof/missing_audio_proof.py --baseline`): with one audio track
  whose only clip's media file is missing, or whose reverse is pending, and
  no other track that sounds, both `audio_wav` and `prores_422` failed with
  "export: The operation could not be completed" (M1, M2, R1, R2), as did a
  missing `AV.mov` alone (V0); beside a track that sounds, both exports
  finished and matched that track alone (M3, M4, R3, R4). A composition
  audio track of nothing but empty edits is what the writer could not read.
  The silence is `app/Resources/Silence.caf`, 10 s of ALAC zeros at 48 kHz
  in two channels (spec §11 SY-23: an empty edit before a non-48 kHz segment
  is rate-converted wrongly, so the silence is 48 kHz), inserted back to back
  from 0 (`CompositionBuilder.fillSilence`, `CompositionBuilder+Silence.swift`)
  and never scaled, the last copy cut at the end. The track's id, its input
  parameters, its envelope, its onset (still nil, so no hold), its meter and
  its `sounding` spans (still empty, so the meter counts nothing there) are
  unchanged; only the empty edits become silent media. Every track with a
  resolved segment builds byte for byte as before. Where the resource is
  absent (the probes and the harness, which bundle no app resources), or its
  extent is not numeric or floors to 0 ticks, the track keeps its empty
  edits, as today. It applies to the preview and every export alike, through
  `addAudioTracks`. **Risk accepted:** one edit per 10 s of such a track;
  and the length is scored against the same project with its media present
  (control C), not the timeline (owner, 2026-10-24): every composition whose
  picture is the Blank placeholder exports one frame short of its timeline —
  814,400 frames for a 17 s timeline at 30 fps, the same in C and T before
  and after this change, and none short for a missing `AV.mov`, which has a
  video track — a shortfall beside #337.
- **#355 — The Audio inspector's Fade in, Fade out and Ducking Attack and
  Release write the typed length off the frame grid, as `set_audio` stores
  it (core/CLAUDE.md Times); dragging a fade handle on the timeline still
  snaps the length to whole frames, a deliberate gesture exception (owner,
  2026-10-25).** The four rows each snapped the seconds typed to the
  canvas's frame grid before the op was built (`AudioPane`'s two local
  `ticks`), so at 30 fps a 10 ms attack was written as 0 and a 0.26 s fade
  as 0.2667 s; the same `set_audio` from an agent is stored as sent,
  because the core's Times rule keeps the audio ramps — the fades, the
  duck's and the compressor's attack and release — off the grid on
  purpose: they are envelope lengths sampled at the audio rate, not
  positions in the picture. The rows now convert seconds to ticks with no
  snap (`AudioPane.rampTicks`), as the Compressor's millisecond rows
  already did. Three reasons: the core's rule; agent parity, one length
  stored for one length asked, whichever side asks; and the compressor
  rows, the same family, already unsnapped. The fade handle's drag
  (`FadeHandleSession`) keeps its snap, because a drag lands on whatever
  pixel the pointer reaches and a whole frame is what a person can see.
  The inspector's other seconds→ticks copies that do snap — Motion's In
  and Out Duration and Period, the transition's Duration, Reveal's In and
  Out, the action lane's duration field — become one
  `InspectorBinding.frameTicks(seconds:)`, which changes nothing stored:
  its only addition, a negative read as 0, is below every one of those
  fields' minimums.
  `tools/proof/audio_ramp_grid_proof.py` (A1–A5, G1–G3) is the proof;
  `--baseline` shows A1–A4 snapped on the old tree. **Risk accepted:** a
  field shows 2 decimals, so 10 ms is the smallest length a person can
  type, and a stored 0.083 s reads 0.08; a later handle drag re-snaps a
  typed length.
