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
  by hand-written JSON only, since every op holds speed in ×0.1 – ×10 and a
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
  holds a speed in ×0.1 – ×10), `evaluate.rs`'s clamp covers what it can
  produce, and reading it as "empty" would freeze an edge over a field no
  trim can fix. No persisted field changes, so `RC_FORMAT_VERSION` stays 8.
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
  clamps, a trim whose clamps crossed, a rate stretch outside ×0.1 – ×10),
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
