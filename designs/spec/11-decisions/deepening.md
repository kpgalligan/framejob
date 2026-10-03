# Spec §11 — decisions: Deepening (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **D2-1 — A refused op says why in the CORE's words; a tool still names an
  argument the caller left out.** Deepening D2 gave every rule that refuses
  a sentence of its own and deleted the app's copies
  (`archive/reelcut-roadmap-7.md` §4–§5), so no agent handler trial-applies
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
  kpgalligan/reelcut#8**, which had listed `set_transition_style`'s refusal
  and `normalize_clip`'s check among the deletions; the first is one of five
  of a shape, and deleting one of five would leave the tool surface
  inconsistent for a caller.
- **D3-1 — The core says what an argument IS; the app says what it is FOR.**
  Deepening D3 made the op table a published interface
  (`archive/reelcut-roadmap-7.md` §7–§9): `core/src/op_table.rs` holds one row
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
  (`archive/reelcut-roadmap-7.md` §11.6): it covers **all seventy-seven
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
  `archive/reelcut-roadmap-7.md` §10.3's unverified reading is confirmed:
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
  `archive/reelcut-roadmap-7.md` §10.8: it writes `speed = content / duration`
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
  `archive/reelcut-roadmap-7.md` §10.6's fourth decision, built as phase C.
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
  which removes two documents at one path at its source. A save to the
  document's own file stays a plain save (#138). The tool is withheld from
  the assistant (AI-7, amended). Risk accepted: an agent that wants a path
  another document holds closes that document first.
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
    `paste_attributes` carries no speed (`edit_paste.rs:79`). **Cancel adds
    no undo step**, and one question covers every clip a multi-clip edit
    takes over. **A rate stretch that crosses is put back before the
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
  limits: they landed in f5571fd (issue batch B29) — `awaitPass` cancels
  its sleeper (`cache_pass_probe.py` W1, mutant `no-cancel-sleeper`) and
  the doc lines say one CURRENT pass per key. **The bound it keeps by
  design:** a relink away from a stuck pass starts only after the full
  30 s wait (S1a measured 30.32 s).
- **#216 — Every Reelcut process opts in to macOS's supplemental VP9 and AV1
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
  **Always `.mov`**, in `~/Library/Application Support/Reelcut/Rewrapped/`
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
  video track with no DefaultDuration is refused at open. **What is
  dropped:** every video and audio track after the first of each kind,
  subtitles, chapters, attachments and VP9 alpha. **The risks it accepts:**
  no progress or Cancel in this phase (a copy runs at about disk speed); a
  document opened from the Finder blocks the main thread for the copy, as
  ffmpeg's conversion already does; the Media tab names the copy, not the
  original; the copy lives outside the package until Consolidate.
  **Amended by #228-V** (issue batch B77): Vorbis is copied.
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
  takes the keyboard from a Reelcut window:** while any window is key it is
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
  person to cancel a tool call's copy. **The risks it accepts:** an agent's
  `open_project` of a WebM still copies on the main thread and freezes the
  window for the copy's length (O7, #231); a quit during a copy
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
  audio, which Reelcut cannot copy …") and falls through to the opt-in
  ffmpeg step. **The risks it accepts:** the movie's 1/600 s edit grid
  (a remuxed libvorbis click read 1.0017 s against ffmpeg's 1.003, 1.0027
  with a 48 kHz movie timescale), which affects every copy (#232); no end
  trim, so the copy's sound may run up to one packet past the source's
  (144384 samples decoded where ffmpeg decodes 144000); and the headers'
  parse on every open.
