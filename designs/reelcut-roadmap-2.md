# Reelcut — road map 2: beyond the spec

**Status: phases 0, 1 and 2 are done (`4fb72c6`, `c1b5188`); the rest is
not. Pick up at phase 3.** Spec §10's three milestones are done
(`reelcut-roadmap.md` records how each was proved). This is the plan for
what a capable editor still lacks, found by reading the op table, the menus,
the key map and the code against the question "what does a cutter reach for
and not find". It is sized for **several sessions**: ten phases, each one to
two sessions, each closable on its own and each ending in evidence.

Companion relations, unchanged: `reelcut-design.md` stays normative for the
schemas (§5), the op table (§6) and the architecture (§7) — **a phase that
adds an op or a field updates §5.2 / §6 as it lands**, exactly as it updates
`edit.rs`'s module doc, `ReelCore.swift`'s builders and `AgentCatalog.swift`.
Phase 1 found one mirror this list forgot: **spec §7.10's Rust module map**,
which `core/CLAUDE.md` calls "the same list" — so a phase that adds a MODULE
updates it too, not only a phase that adds an op. `CLAUDE.md` holds the milestone status; its
paragraph for a phase is written when the phase's proof exists.
`reelcut-roadmap.md` is the record of M1–M3 and its "known limits" list
still stands.

## 0. Rules every phase inherits

These are the project's standing rules, restated only where a phase below
leans on them. `CLAUDE.md`, `core/CLAUDE.md` and `app/CLAUDE.md` are the
full text.

- **A new op is a JSON op through `rc_project_apply`.** It touches `edit.rs`
  (the enum, `OP_NAMES`, the module-doc table), a `impl Project` block in a
  module of its own concern, `ReelCore.swift`'s typed builder,
  `AgentCatalog.swift` + a handler with a comment naming the UI path, and
  spec §6. The header changes only when a phase adds an `rc_*` export
  (Phase 7's recipe options and Phase 9's scoped handle are the two).
- **A persisted field bumps `RC_FORMAT_VERSION`** in `format.rs` and the
  header, with a serde default so every earlier file opens, and a
  `schema_vN.rs` test that opens the previous version's fixture. One bump
  per phase that persists something (v3 … v6 below). **A field lands in the
  same phase as the thing that renders it** — a field a file can carry and
  no renderer honours is a lie in the file.
- **Every user-visible edit gets an MCP mirror**, and the startup parity
  check enforces it. A gesture that is only a `move_clip` (nudge) needs
  nothing; a composite the UI offers as one command (blurred background,
  zoom back, normalise clip) gets a tool that performs the same composite.
- **`edit_clip.rs` is over the size cap**, still, and `edit_track.rs` with
  it. `model.rs` no longer is: phase 0 brought it down from 1330 to 940 by
  moving the lookups and `validate` to `model_query.rs`, and phase 2 took
  it to 462 by moving the §5.2 property types (`VideoProps` and its
  friends) into `model_props.rs` — the cut this bullet used to promise —
  and moved `edit_props.rs`'s range checks into `props_check.rs` the same
  way, so phases 3, 4 and 6 have room for their fields. `core/CLAUDE.md`
  names the next cuts. No new op goes into `edit_clip.rs`.
- **Frozen files** (`EditorViewController.swift`, `TimelineView.swift`,
  `PreviewCanvasView.swift`, `AgentServer.swift`,
  `InspectorViewController.swift`) take wiring only; each feature below
  names its extension file.
- **Proof is driving the built binary over MCP** and comparing
  `render_frame` output or measured audio, plus black-box core tests against
  an oracle. Each phase's "Proof" list is its exit criterion.
  **The script goes in `tools/proof/`** as `phase<N>_proof.py`, over the
  dependency-free MCP client phase 1 left there, so a proof can be re-run
  after a later phase rather than believed on the strength of a paragraph.
  A frame claim is a BYTE comparison of two PNGs or it is not a proof; a
  check that would pass against a build where the op did nothing is not one
  either, and phase 1's review found two of those in its own script.
- **The baseline** is `make test` green, `make lint` clean and
  `make typecheck` at 0 errors / 4 deliberate warnings. A phase leaves it
  there.

**Session protocol.** A session picks one phase (or half of one), reads its
section here and the two side `CLAUDE.md`s, lands the work, runs the proof,
then updates: the status table below, `CLAUDE.md`'s milestone status, the
spec's §5.2 / §6 / §7.10 / §9 for anything they mirror, and the README's
feature bullets. Unfinished halves are written down here under the phase,
not left implicit.

**And then reads the change back adversarially, before committing.** Phase 1
did, and it found five real defects in work that already had 244 green tests
and a 63-check MCP proof behind it — including one that made every overwrite
of an imported still a silent no-op on a 29.97 timeline, and one that had
the bare-⌫ menu item eating Delete out of every text field. The shape that
worked: one reader per dimension (correctness, the core's rules, the app's
rules, the gestures, the MCP mirror, the docs), then every finding put to
sceptics told to refute it, then a regression test for each survivor that
fails without the fix. Green tests prove the cases someone thought of.

## 1. Status

| Phase | Theme | Sessions | Schema | Status |
|---|---|---|---|---|
| 0 | Groundwork | ½ | — | **done** 2026-09-06 (`4fb72c6`) |
| 1 | Cutting moves | 1–2 | — | **done** 2026-09-06 (`4fb72c6`) |
| 2 | Clip identity | 1 | v3 | **done** 2026-09-07 (`c1b5188`) |
| 3 | The screencast trio | 2 | v4 | not started |
| 4 | Words | 2 | v5 | not started |
| 5 | Sound | 1–2 | — | not started |
| 6 | Looks | 1–2 | v6 | not started |
| 7 | Output | 1–2 | — | not started |
| 8 | Viewing and finding | 1 | — | not started |
| 9 | Inside the nest | 2 | — | not started |

Order is by value over dependency. Phases 1–3 pay back first and share
nothing that later phases need; 6 depends on 3's list-interpolation rule; 9
is last because it is the largest and touches every op at once. Any other
order works if that one dependency is kept.

**What phases 0, 1 and 2 left behind for the rest**, so no later phase
invents a second one:

| | |
|---|---|
| `core/src/model_query.rs` | the three source-window measurements — `source_head`, `content_length`, `source_length` — plus the lookups and `validate`. Any op that clamps against a media clamps against these. |
| `edit_clip.rs::whole_media_length` | how long a clip showing the whole of a media is, snapped. `add_clip`, `insert_clip` and `overwrite_clip` share it. |
| `time.rs::snap_up_to_frame` / `snap_down_to_frame` | directional frame snapping, for a clamp BOUND — which cannot be rounded to the nearest frame without letting a caller past what it protects. |
| `edit_time.rs::ordered_range` / `clear_range` | "put a range in order" and "empty it on every unlocked track", shared by `lift_range` and `ripple_delete_range`. Phase 3's `ripple_delete_ranges` is a loop over the second. |
| `ProjectDocument.targetTrack` | the one rule for "which track does a command with no track argument act on": the first selected clip's, else the front-most. Phase 6's Add Background… wants it. |
| `ProjectDocument.selectedMedia` | the Media tab's selected row, clamped like the other view state. Phase 8's Media-tab work builds on this rather than adding another. |
| `EditorViewController+Edge.swift` | carries an `extension TimelineView` as well as the controller's, which is how a gesture is added without touching the frozen view. Phases 3 and 9 need the same trick. |
| `tools/proof/` | the MCP client, the per-phase proof scripts, and `harness/` — the offscreen chrome renderer, for any claim about what the chrome SHOWS. |
| `ClipLabel.swift` | the marker-colour vocabulary — six names, their order, display names and inks — spelled once. A marker, a label, or anything else that carries a colour NAME reads it. |
| `Project::check_group` (`edit_props.rs`) | the range check for ONE property group of one clip, what a patch and `paste_attributes` both run. A composite that writes a group runs it too. |
| `audio.rs::silenced` | muted, or soloed-out within a container's track set. Any later per-track audio switch joins it rather than adding a second read of `track.muted`. |
| `TimelineView+Rename.swift` | the second `extension TimelineView` precedent (after `+Edge.swift`'s), and the shape for adding an in-place editor to the frozen view: the hook in the frozen file, the field in the extension. |
| `AgentServer+Arguments.stringsArg` | an optional list of strings from a tool call, a lone string counting as one. Phase 4's caption options and phase 7's export options want it. |

## 2. Phases

### Phase 0 — Groundwork

*Half a session. Makes room; changes no behaviour.*

- **Split `model.rs`.** Move the `// ---- lookups and invariants` section
  (id allocation, `clip`/`track`/`media`/`marker` lookups, `validate`) into
  `core/src/model_query.rs` as `impl Project` blocks, and the
  `// ---- serde defaults` section with it. `model.rs` drops to about 900
  lines of type declarations, which is what it was meant to be, and
  Phases 2, 3, 4 and 6 can add their fields without breaking the
  "take something out first" rule.
  **Landed** as `core/src/model_query.rs` (408 lines: `Project::new`, the
  five id lookups, `allocate_id`, `clips_on`, `clips_on_track`, `duration`,
  `source_length`, `is_missing_media`, `validate` and its nesting walk);
  `model.rs` is 939. **One deviation: the serde defaults stayed.** A
  `#[serde(default = "…")]` function is what an absent key MEANS, which is
  schema, and moving 43 lines would have cost seven fully-qualified
  `crate::model_query::…` paths and put `default_one()` in a module about
  lookups. The size goal was met without them. When the schema does outgrow
  the cap again — Phases 2, 3, 4 and 6 add about 145 lines between them —
  the next cut is the §5.2 property types into a `model_props.rs`, which is
  now written down in `core/CLAUDE.md`.
- **README.** The "Inspector" bullet still describes six pinnable tabs and
  the tool count says 50; the chrome cleanup made it three tabs and the
  catalog is 57. Fix both, and leave the counts in ONE place each so the
  later phases update one line.
  **Landed**: the Inspector bullet and the layout table now say three tabs
  and name the section factories; the tools section names the ops but no
  longer counts them — the count is `rc_op_names`' length and the catalog's,
  which the startup parity check already compares, so a phase that adds an
  op updates no number here. `import_captions`, `consolidate_media` and
  `set_selection` were missing from the app-state table and are in it.
- **Key-map ledger.** Add the proposed keys from §4 of this document to
  spec §9 as a "proposed" block, so a phase that binds a key checks it
  there and promotes the row.
  **Landed**: spec §9 carries a second table, "Proposed, not yet bound",
  with the phase number on every row. No conflict with the bound table was
  found; `,` `.` `Z` and ⌥⌘E / ⇧⌘P / ⇧⌘R / ⌥⌘V / ⌘↓ / ⌘↑ are all free.
- **Decide the `async` allow-list question** for Phase 4 (Speech) now, so
  that session does not open with a rules debate. Recommendation: the
  callback API, no new exception.
  **Decided, as recommended**, and written into spec §11 and `app/CLAUDE.md`
  so it is not reopened: `SFSpeechRecognizer`'s callback API is complete for
  a transcription, so `Transcriber.swift` uses it. `SpeechAnalyzer` is
  `async`-only and would earn the argument again — but only when the
  deployment target moves, and then as one more named file.

**Proof.** `make test`, `make lint`, `make typecheck` at baseline;
`rc_op_names` unchanged; the v2 fixture opens; `git diff --stat` shows
`model.rs` shrinking by what `model_query.rs` gained.

**Proved** on 2026-09-06: `make lint` clean, `make test` 222 passed / 0
failed (the schema-v1 and schema-v2 fixture tests among them), `make
typecheck` 0 errors and the same 4 AVFoundation deprecation warnings.
`edit.rs` was not touched, so `OP_NAMES` is the same 43. `git diff --stat`:
`model.rs` −403, `model_query.rs` +408 (the difference is the new module
doc and its imports).

---

### Phase 1 — Cutting moves

*One to two sessions. No schema change. Six ops, two gestures, three keys.*

The op table has trim, split, ripple and insert-time, and lacks the four
moves a cutter makes between them. All six below are placement ops; none
goes in `edit_clip.rs`.

| Op | Arguments | Semantics |
|---|---|---|
| `slip` | `clip: u32, delta: ticks` | Moves the source window under a fixed clip: `in += delta × speed`, start and duration unchanged. Clamped so `in ≥ 0` and `in + duration × speed ≤ media duration`; a delta the clamps reduce to nothing is `None`. A `still` moves its `at` instead. Any other source is an `Err` (the non-media rule). Actions are clip-relative and do not move. |
| `roll` | `clip: u32, to: ticks` | Moves a hard cut: the clip's start and its predecessor's end both become `to`. The predecessor is the clip on the same track that ends exactly at `clip.start`; with no such clip, or with an overlap (a transition's length is `set_transition_duration`'s job), refuses. Clamps to the predecessor's source tail, this clip's source head, and one frame on each. Front trim semantics for this clip (`in` follows), plain end trim for the predecessor. |
| `lift_range` | `from: ticks, to: ticks` | `ripple_delete_range` without the close: every unlocked clip is split at both bounds and the middles removed; nothing moves, markers stay. A reversed range is the same range. |
| `close_gap` | `track: u32, at: ticks` | The empty span on `track` that contains `at`, bounded by the nearest clip ends on that track. Shifts every unlocked clip on every track whose start ≥ the gap's end left by the gap's length — `ripple_delete`'s shift with the gap as the span, straddlers on other tracks staying put. **Refuses** when a shifted clip would break the overlap rule; deciding in-phase whether to clamp to the largest closable amount instead is allowed, but a screencast editor closes fully or not at all and so should we. No clip after the gap is `None`. |
| `insert_clip` | `track: u32, media: u32, at: ticks` | The insert edit: on `track`, a clip strictly containing `at` is split first; then `insert_time(at, media duration)`; then `add_clip`. One op so it is one undo step and one tool. |
| `overwrite_clip` | `track: u32, media: u32, at: ticks` | The overwrite edit: clears `[at, at + media duration)` **on `track` only** (split at both bounds, remove the middles), then `add_clip`. Other tracks are untouched. |

**Not ops.** *Nudge* is `move_clip` by ±1 frame on `,` / `.`, ±10 with ⇧
(read `charactersIgnoringModifiers`, since ⇧, is `<`); the overlap rule's
refusal beeps. *Select all on track* is view state: ⌥-click a track header,
and Edit ▸ Select All on Track for the selected clip's track.

**Gestures** (session structs in `TimelineSessions.swift`, logic in
`EditorViewController+Edge.swift`): **⌥⇧-drag a clip body = slip** (⌥ alone
duplicates; ⇧ turns the ⌥ gesture into its keep-the-neighbours cousin) with
the filmstrip scrolling under the cursor; **⌥⇧-drag an edge = roll** (⌥
alone rate-stretches), with the neighbour's edge drawn moving too. Both are
one undo step through the live-edit trio. *Lift*: ⌫ with an in/out range and
nothing selected (the ⌘⌫ path in `EditorViewController+Timeline.swift` is
the template). *Close gap*: double-click an empty lane span, and Clip ▸
Close Gap when the playhead is in one. *Insert / overwrite*: Edit ▸ Insert
at Playhead / Overwrite at Playhead for the Media tab's selected item, the
Media list's context menu, and ⌥-drop / ⇧⌥-drop from the list onto a lane
(decide the modifiers in-phase; only ⌥ alone is taken, by duplicate).

**Where.** `core/src/edit_edge.rs` (slip, roll), `edit_time.rs` (lift_range,
close_gap — it is the ripple family's home and has room),
`core/src/edit_insert.rs` (insert_clip, overwrite_clip); `edit.rs`;
`core/tests/edge.rs`, `core/tests/insert.rs`. Swift: `ReelCore.swift`,
`AgentCatalog.swift`, `AgentServer+Clips.swift`, `TimelineSessions.swift`,
`EditorViewController+Edge.swift`, `MediaPane.swift` (menu + drop
modifiers), `AppDelegate.swift`, two `case` lines in the frozen key switch.

**What landed.** All six ops, both gestures, all three keys, and one thing
the plan did not foresee: the Edit-menu pair needs a media SELECTION, which
the app did not have. `ProjectDocument.selectedMedia` is now the fourth
piece of view state beside the playhead, the clip selection and the in/out
range — clamped by `clampViewState` like the others, set by
`MediaRowView.mouseDown`, drawn by the row, and stored on the DOCUMENT
because `MediaPane` is rebuilt whole whenever the media list changes.

Three deviations, all small and all deliberate:

- **`close_gap` and `insert_clip` both refuse on a locked `track`.** The plan
  did not say. For `close_gap`, its own clips are the ones that would not
  move, so closing a gap on a locked track by shifting every OTHER track is
  not what anyone asked for. For `insert_clip`, `insert_time` will not shift
  a locked track at all, so the room the op promises cannot be made there —
  and leaving that to `add_clip` to notice would have refused only where the
  locked track happened to hold something at `at`, and quietly added a clip
  to a locked track everywhere else. `overwrite_clip` deliberately does NOT
  refuse: the caller named the track, exactly as `ripple_delete` removes the
  clips it was given, and a lock decides only what may shift, which for an
  overwrite is nothing.
- **The overlap check after `close_gap`'s shift is per touched track**, not
  timeline-wide: a rule violation on a track nothing moved on is not this
  op's to report, and refusing over one would make a gap uncloseable for a
  reason the user cannot see.
- **`ripple_delete_range` was refactored onto the same two helpers as
  `lift_range`** (`ordered_range`, `clear_range`), so the two cut
  identically and differ only in the shift. The alternative was a second
  spelling of "split both bounds and drop the middles".

Two pieces of shared arithmetic moved rather than being copied:
`content_length` went from `edit_clip.rs` to `model_query.rs` and
`source_head` was extracted out of `trim_start`'s body, so the three
measurements of a source window — head, window, remaining — have one home
and a slip and a trim cannot disagree about where a media ends.
`whole_media_length` came out of `add_clip` for the same reason: the room an
insert opens is the room `add_clip` would have needed.

**Proof.**
- `slip` by `+d` then `−d` is the identity; a slip past the source head
  clamps and reports the clamp as `None` when nothing moved.
- `roll` keeps `predecessor.start` and `clip.end` fixed and the pair's total
  duration constant; `render_frame` at `to − 1` and `to` shows the two
  sources meeting there.
- `lift_range` leaves every clip start ≥ `to` unchanged and `render_frame`
  inside the range shows the background.
- `close_gap` moves the next clip's start to the gap's start and every later
  unlocked clip by exactly the gap; a locked track's clips do not move.
- `insert_clip`: the frame at `at + len` after equals the frame at `at`
  before, on every track; `overwrite_clip`: frames outside the span are
  byte-identical before and after.
- Each key and gesture is one undo step (`undo` over MCP restores the frame).

**Proved** on 2026-09-06, and again after the review round below. Core:
`make test` **251 passed / 0 failed** — 222 before, plus `core/tests/edge.rs`
(16), `core/tests/insert.rs` (10) and three in `edit_tests.rs` for
`lift_range` and `close_gap`. `make lint` clean, `make typecheck` 0 errors
and the same 4 AVFoundation deprecation warnings. The identity claims are
whole-document byte comparisons, not field checks: slip-and-back and
roll-and-back both reproduce the input JSON exactly.

App: driven over MCP against `make app`'s binary — **66/66 checks**, and the
script is in the repo at `tools/proof/phase1_proof.py` so it can be re-run
after a later phase rather than believed on the strength of this paragraph.
The catalog is 63 tools and the startup parity check passed. Every frame claim is a byte comparison of `render_frame`
PNGs against ffmpeg-generated test cards:

- Slip: the frame at 3 s after a `+2 s` slip is byte-identical to the frame
  that was at 5 s; there and back is byte-identical to the start; the window
  travels exactly the 4 s a 6 s clip of a 10 s media has, and then reports
  no change.
- Roll: the frames at 6 s − 1 frame and at 8 s are byte-identical before and
  after — **a roll moves the cut, not the film** — while the frame at
  8 s − 1 frame changes, because that is the tick the cut crossed. The
  pair's outer edges and total length are unchanged; `undo` restores the
  frame. A roll across a gap changes nothing.
- Lift: the clip after the range is untouched and its frame is byte-identical;
  the range renders as the canvas background, byte-identical to a span that
  was always empty. The same range through `ripple_delete_range` moves that
  clip, which is the whole difference between the two.
- Close gap: the next clip lands on the gap's start, a locked track's clips
  do not move, and the three refusals (no gap, a time on a clip, a locked
  track) all report no change.
- Insert: the frame at `at + len` after is byte-identical to the frame at
  `at` before, on the destination track AND on another one; a straddler on
  another track is neither cut nor moved.
- Overwrite: frames before the span and on other tracks are byte-identical,
  the frame inside it is the new clip, and no other track moved at all.
- Every op is one undo step: `undo` restores both the placements and the
  frame bytes.

Not machine-checked, for the reason spec §10 gives about steps 6 and 8: the
two ⌥⇧ drags, the `,` / `.` nudge, the ⌫-with-a-range lift, the empty-lane
double-click, the ⌥-click on a track header and the ⌥ / ⇧⌥ drop are
event-driven UI. Their ops are proved above and their wiring typechecks; a
person at the machine is what is left.

**Reviewed, and five real defects fixed.** The change was then read by a
fan-out of reviewers — correctness, the core's rules, the app's rules, the
gestures, the MCP mirror and the docs, one per dimension — with every
finding put to three sceptics prompted to refute it. Thirty-one survived.
The five that were code, each now covered by a test that fails without the
fix:

1. **`whole_media_length` handed back an unsnapped constant.** Five seconds
   is 3 000 000 ticks, and 3 000 000 is not on the frame grid of a rate that
   does not divide the timescale — at 30000/1001 it is 3 003 000. So an
   image with no duration of its own made `overwrite_clip` clear a span that
   missed the fragment `split_clips` had just cut, the fragment survived,
   the new clip landed on top of it, and the overlap rule refused the whole
   op: **every overwrite of an imported still on a /1001 timeline was a
   silent no-op**, and every insert of one opened a hole a sliver wider than
   the clip it placed. `MediaImporter` writes `duration: 0` for every image,
   so this was the ordinary case, not a corner.
2. **`slip` answered `Ok(None)` for a text clip** when the delta rounded to
   nothing, because the zero-delta short circuit ran before the source-kind
   check — the one answer the non-media rule exists to stop the MCP agent
   being given.
3. **`roll` clamped a snapped `to` to UNSNAPPED bounds.** Both source bounds
   are floored divisions by a clip's speed, so a clamped roll could write a
   sub-frame time into two clips at once. `time.rs` gained the directional
   pair a bound needs — `snap_up_to_frame` and `snap_down_to_frame` — since
   a lower bound rounded to the nearest frame lets a caller past what it
   protects.
4. **`insert_clip` did not check the destination lock**, so an insert at a
   point where the locked track happened to be empty succeeded, adding a
   clip to a locked track and rippling every unlocked one.
5. **The bare-⌫ menu item had no "text is being edited" guard.** The item is
   a modifier-less key equivalent, which AppKit resolves ahead of the first
   responder; `AppDelegate`'s own comment on it asks for exactly this guard
   and nothing had ever supplied one. Widening the item to "selection OR
   range" made it worse, so the guard went in.

The rest were a snap guide computed and never drawn (a roll was the one
snapping gesture with no snap line), `selectedMedia` missing from the two
view-state resets on the read path, the row menu and the Edit menu
targeting different tracks under the same name (`targetTrack` moved to
`ProjectDocument`, so there is one rule), four doc statements that had gone
false, two handler comments naming selectors that do not exist, and seven
gaps in the tests: `roll` was never run at a speed other than 1, never on a
sourceless pair, `close_gap`'s and `insert_clip`'s lock guards were both
satisfied by a different code path, `overwrite_clip` on a locked track was
untested, `close_gap`'s `set_gained_transitions` branch was never taken, and
two of the MCP proof's cross-track frame checks were hashing a flat green
picture, which is the same at every time and could not have failed.

---

### Phase 2 — Clip identity

*One session. Schema v3: clip name, clip label, track solo.*

A clip has no name of its own — the strip shows its media's file name —
and there is no way to mark one. Solo is the one track switch missing.

**Schema.** `Clip.name: Option<String>` (absent → today's fallback);
`Clip.label: Option<String>` using the marker colour vocabulary;
`Track.solo: bool`. `RC_FORMAT_VERSION` 3.

**Correction to the plan, found while reading for phase 1:** the one
fallback is NOT in `ClipKindStyle`. It is
`ProjectSnapshot.name(of:)` — "the nest's name for a nest clip, the media
file name where there is one, else the kind" — and all three readers already
route through it (`TimelineClipDrawing`, `TimelineBar`'s selection block,
`ClipPane`'s header). So `Clip.name` goes at the HEAD of that one function
and nothing else changes. `ClipKindStyle` owns the kind WORD and the tint,
which is a different question and stays where it is.

| Op | Arguments | Semantics |
|---|---|---|
| `set_clip` | `clips: [u32], name?: string \| null, label?: string \| null` | Sets or clears (`null`) the name and label; omitted keeps. `None` when nothing changes. Lives in `edit_props.rs`. |
| `set_track` | gains `solo?: bool` | In `audio.rs`, when any top-level track is soloed every non-solo track is treated as muted. Audio only; the picture is unaffected (solo is a mixing word). Inside a nest the nest's own tracks follow the same rule among themselves. |
| `paste_attributes` | `clips: [u32], payload: object, groups?: [video \| audio \| text \| shape]` | Takes the payload's FIRST clip (the Copy payload of `edit_paste.rs`) and merges its props onto each target for the groups named (default: every group the source has and the target can take). Video and audio paste whole, transform included; text pastes everything but `content`; shape pastes everything but `kind`, `width`, `height`, `from`, `to`. Speed, enabled and actions do not travel. Lives in `edit_paste.rs`. |

**UI.** Rename: double-click the name strip in the timeline (an inline field
in a `TimelineView+Rename.swift` extension), the Clip tab's header name
becomes editable, Clip ▸ Rename… (⇧⌘R). Label: a 6 pt dot at the right end
of the name strip and a Clip ▸ Label submenu. **The tint stays the kind's**
— the label is a badge, never a tint override; the redesign's rule that the
colour says the kind is what made clips tell apart. Solo: an `S` toggle in
the track header beside eye / speaker / lock, Track ▸ Solo. Paste
Attributes: Edit ▸ Paste Attributes (⌥⌘V) over the existing
`com.kgalligan.reelcut.clips` pasteboard type in
`EditorViewController+Clipboard.swift`.

**Where.** `model.rs`, `format.rs` + header, `edit_props.rs`,
`edit_paste.rs`, `edit_track.rs`, `audio.rs`; `core/tests/schema_v3.rs`,
additions to `edit_tests.rs` and `paste.rs`. Swift: `ProjectSnapshot.swift`
(the fallback, and the `Codable` mirror of the two new clip fields),
`TimelineClipDrawing.swift` (the label dot on the name strip),
`TimelineView+Rename.swift`, `ClipPane.swift`, `TimelineBar.swift`,
`EditorViewController+Clipboard.swift`, `AppDelegate.swift`, the catalog and
`AgentServer+Clips.swift` / `+Tracks.swift`. `ClipKindStyle.swift` is NOT on
the list — see the correction above.

**What landed.** All of it — the three fields at version 3, the two ops
and the `solo` argument, the four UI surfaces and their mirrors — plus
the following, where the code differs from the table above or settled
what it left open:

- **`set_clip` takes a patch**, `{clips, patch: {name?: string | null,
  label?: string | null}}`, not the table's two top-level arguments. The
  op envelope's rule (`edit.rs`) is that an absent optional and an
  explicit `null` mean the same thing, and the crate has no tri-state
  argument idiom — while a patch already has exactly the one wanted
  (absent keeps, `null` clears) and the Swift side already had `T??`
  patches and `patchArg`. So it is the fifth patch op, in `edit_props.rs`
  beside the other four. Inside the patch an EMPTY string clears too,
  after the trim a name gets, because an unnamed clip is `None`, not
  `""`; an unknown key is an `Err`, checked before the clip ids, so it is
  refused even with an empty selection.
- **`paste_attributes` replaces a group whole, never merges**: "make this
  look like that" is the gesture, and a merge would leave the target's
  shadow under a source that had none. What a target keeps is what makes
  it the clip it is: a text clip's `content`; a shape's `kind`, `width`,
  `height`, `from`, `to`. `audio.muted` and `keep_pitch` travel with the
  audio group — properties like opacity — and `keep_pitch` only acts when
  the speed is not 1, which does not travel; neither do `enabled`, the
  actions, the transition, the source, the name or the label. `groups`
  absent means every group BOTH sides have, silently skipping the rest; a
  NAMED group the payload clip lacks (`payload clip has no audio
  properties`) or a target lacks (`clip 30 has no audio properties`) is
  an `Err`, all-or-nothing, because a caller who asked would otherwise
  never learn it did not happen; an empty explicit list is `None` in the
  core and a refusal by name over MCP. Each copied group then passes the
  range checks a patch does (`Project::check_group`, which checks only the
  group that was replaced), so a hand-written payload cannot smuggle in a
  value the inspector would refuse. Only ONE payload clip's four groups
  are read — the EARLIEST (at one start the front-most, then the lower
  id), which the review changed from the array's first, since that is
  Copy's creation order and invisible to the user; its ids, media rows
  and nests are irrelevant and nothing is minted.
- **Solo: mute wins, and a solo with nothing audible still silences.**
  `silenced(set, track) = muted || (set.any(solo) && !solo)` in
  `audio.rs`, judged per container in `Voice::of` (the timeline's tracks
  at depth 0, `inside[d − 1].nest.tracks` at depth d), an envelope like
  mute — the segments stay in the plan, `plays_audio` and `assign` are
  untouched, so a solo toggle changes ramps only. The rule is on the set,
  not on what plays, which is what a mixer's button does; and
  `plan_text()` of "solo A" is byte-identical to "mute every track but
  A", which is the string the composition rebuild is keyed on.
- **`nested_track` copies `solo`** as it copies hidden/muted/locked, so
  what played before nesting plays after, judged inside among the nest's
  own tracks. One consequence to know — a limit, not a bug: the nest clip
  lands on the selection's front-most source track, so a solo on a
  NON-front-most selected track stays behind on the emptied timeline
  track and then silences the whole nest, which is what moving that clip
  to an unsoloed track would do too, since a solo belongs to its track.
  `unnest` carries no track flag back out, as it never did for `muted`.
- **Two cuts under the size rule**, done before the fields went in:
  `model_props.rs` (the §5.2 property types, 531 lines, re-exported
  whole by `model.rs`, which went from 939 to 462) and `props_check.rs`
  (`edit_props.rs`'s range-check section, cut when `set_clip` and
  `check_group` took that file over the cap). Both are in spec §7.10 and
  `core/CLAUDE.md`.
- **The Clip tab's header field is the clearing path.** The shared inline
  editor `TimelineView` keeps for tracks and markers drops an EMPTY
  commit — right there, since those names cannot be cleared — so the
  strip's double-click and ⇧⌘R can rename but not clear. The header
  field (`ClipSelectionHeaderView`) shows the DISPLAYED name, own or
  fallback, and an emptied field on a named clip sends `{"name": null}`;
  on an unnamed one it sends nothing and the fallback is redrawn.
- **The mirror type-checks `set_clip`'s two keys itself.** `patchArg`'s
  round-trip guard cannot refuse a wrong-typed value for a `String??`
  field — `{"label": 7}` decodes as a CLEAR and passes — so
  `checkClipPatchTypes` runs after it and refuses with `patch.label must
  be a string, or null to clear it.` The same gap still exists for
  `TextPatch.width`, unfixed. The label's VALUE is not policed, by the
  `Marker.color` policy; `ClipLabel.swift` is the vocabulary's one home,
  and the catalog's description reads the six names from it.

**Proof.**
- A v2 fixture opens; every clip's displayed name is unchanged (the fallback
  is the old behaviour); write-read round-trips `name`, `label`, `solo`.
- A renamed clip shows its name in the three places at once — selection
  block, Clip header, name strip — in an offscreen render.
- A two-track project with one track soloed exports audio identical to the
  other track muted (sample-for-sample).
- `paste_attributes` leaves the target's props equal to the source's for
  the named groups and byte-identical elsewhere; one undo step.

**Proved** on 2026-09-07, and again after the review round. Core: `make
test` **284 passed / 0 failed** — 251 before, plus `core/tests/schema_v3.rs`
(8) and additions to `edit_tests.rs` (+7), `paste.rs` (+10, two of them
from the review), `evaluate_tests.rs` (+4) and `nest.rs` (+4). `make lint`
clean, `make typecheck` 0 errors and the same 4 AVFoundation deprecation
warnings. The solo claims in the core are hand-written ramp tables, and
`plan_text()` of "solo A" equals "mute every track but A".

App: driven over MCP against `make app`'s binary — **85/85 checks**,
`tools/proof/phase2_proof.py` (84 from the provers, plus a `set_track`
rename through the client's `call_with` from the review), re-run against
the reviewed build, with `phase1_proof.py` still at 66/66 beside it; the
catalog is 65 tools and the startup parity check passed. Every frame claim
is a byte comparison of `render_frame` PNGs and every audio claim a
sample-for-sample comparison of `audio_m4a` exports decoded to PCM:

- Schema: a saved `project.json` is version 3, every clip object ends
  `name` then `label` and every track `solo`; a byte copy of the package
  opened from disk reads them back; a hand-made version-2 fixture opens,
  reports version 3 and reads `null` / `null` / `false` everywhere.
- `set_clip`: `null`, `""` and a blank string all clear; a padded name is
  trimmed; identity, an unknown key and a wrong-typed `label` or `name`
  are refused by name and leave the clip unchanged; a top-level `name`
  with no patch is refused; a split carries name and label to both halves.
- `paste_attributes`: onto two targets, the video and audio groups equal
  the source's, the text's `content` and the eleven keys outside the four
  groups are byte-identical, and `undo` is one step that restores the
  whole document and the frame byte for byte.
- Solo: soloing the back track of a two-tone project exports
  sample-for-sample equal (0 of 477,056 samples differ) to muting the front
  track and to a project holding only that tone; soloed and muted together
  is digital silence, equal to muting both; the frame over a picture track
  is byte-identical before and after a solo. Two exports of the unchanged
  project decode byte-identical, so no tolerance was needed — the M3
  wobble is confined to duck edges.

Offscreen: `tools/proof/phase2_chrome.py`, **26/26**, over
`tools/proof/harness/` with six hand-written one-text-clip packages, every
claim a pixel diff of two renders measured against rectangles from the
layout constants:

- Two renders of one package are byte-identical, and a version-2 file
  renders byte-identical to its version-3 spelling.
- A rename changes exactly three pixel clusters, one inside each of the
  selection block, the Clip header and the name strip, and nothing outside
  them.
- A label changes the strip's right end and the header's right end,
  nothing outside the lanes and the header, and not the body's centre
  pixel (the tint stays the kind's); the same clip labelled red differs
  from blue only at those two ends, where the changed pixels read bluer
  under blue and redder under red — the label's VALUE reaches both dots,
  which a one-ink build (tried) fails.
- A solo changes pixels only inside the track header column, within ±1 pt
  of the headphones box.

Still owed by a person at the machine — event-driven UI a still frame
cannot answer: (1) double-click a clip → the field appears over its strip
with the current name, Enter commits "Rename Clip" and all three places
update; (2) the Clip-tab header field commits on Tab or click-away,
emptying it on a named clip returns the fallback in one undo step, and on
an unnamed clip nothing happens and nothing beeps; (3) the field's 12 pt
semibold text sits acceptably in its 20 pt box; (4) ⇧⌘R scrolls a far-off
clip into view before the field opens, clear of the header column and the
ruler; (5) the headphones toggle's box and tint match the other three at
S/M/L; (6) Track ▸ Solo's checkmark tracks the header; (7) Label ▸ Blue
puts the dot on the strip AND in the header, the checkmark moves, None
clears both; (8) ⌥⌘V after ⌘C of a styled clip changes another clip's look
and beeps when the two share no group; (9) a zoom or a resize while a
rename field is open moves the field with its clip and keeps what was
typed, and ⌘⌫ or the timeline bar's Delete under an open field closes
it with no rename sent and no sheet.

**Reviewed, and six real defects fixed.** The change was read by eight
readers — correctness, the core's rules, the audio rule, the app's
rules, the gestures and menus, the MCP mirror, the docs and the proofs
— who returned 71 findings; every one was put to three sceptics told
to refute it, and 30 survived. The six that were code, each now covered
by a test or a proof check that fails without the fix where one can be
written:

1. **The strip rename pinned the fallback as the clip's own name.** The
   field opens showing what the strip shows, and an unchanged Enter
   sent that back as `set_clip {name}` — an undo step and a dirty
   document for an accidental double-click, and a text clip's strip
   frozen at the words it had. The shared editor now drops an
   UNCHANGED commit as well as an empty one, for all three renames.
2. **The Clip-tab header field stayed blank after a clear.** A field's
   `refresh` is skipped while its field editor is attached, which it
   still is inside `controlTextDidEndEditing` — after Return or Tab
   AppKit even re-attaches it — so every refresh the commit ran was
   skipped and the field showed what was typed while the strip showed
   the fallback. `InspectorNameField` re-reads the model as the commit
   ends; app/CLAUDE.md records the pitfall beside the other one.
3. **Deleting the clip under an open rename field sent the rename to
   the dead id** and put up the core's refusal in a sheet after a
   delete that had succeeded. Every rename now hands `beginRename` a
   `relocate` closure answering its field's rect under the CURRENT
   layout; `rebuildLayout` ends with `relocateRename()` instead of
   `endRename()`, so the field FOLLOWS its target through a zoom, a
   resize and any document change, and a relocator answering nil ends
   the field with its commit dropped. The old `endRename()` had also
   meant an agent's edit mid-typing folded the half-typed name into the
   agent's undo step.
4. **`beginRename` installed the new field before the first-responder
   handoff**, so the previous editor's commit — which rebuilds the
   layout — ran with the new field already in place. It blurs whatever
   else is being typed into first, and gives up if the window refuses
   the field.
5. **A double-click on the visible part of a long clip whose start was
   scrolled off opened the field out of view** — AppKit does not scroll
   a timeline to a field editor's caret. The field is clamped to the
   visible lanes.
6. **`paste_attributes` read the payload's FIRST clip**, which is Copy's
   storage order — creation order, neither timeline nor selection order
   and invisible to the user. It now reads the EARLIEST, ties to the
   front-most and then the lower id, and the test
   `the_look_comes_from_the_earliest_copied_clip` fails on the old code.

The rest: two core gaps closed with tests (an explicit `groups` list
RESTRICTS the copy; an unknown patch key is refused before the ids are
resolved), the waveform dimming under a solo as it does under a mute,
the chrome proof telling one label colour from another (a one-ink
build now fails it), `mcp.py` gaining `call_with` so a tool argument
spelled `name` can be sent, the harness pinning one more defaults key,
and a dozen doc statements that had gone false or were missing —
`RC_CAPS`, which four documents named and nothing defined, among them.

---

### Phase 3 — The screencast trio

*Two sessions. Schema v4 (`video.obscure`). The three features that make a
talking-head or screen-recording cut fast; all three sit on infrastructure
that exists.*

#### 3a. Remove silences

Detection is Swift's, from the waveform peaks the package already caches
(`cache/peaks/<media id>.bin`, f32 max magnitude per 10 ms bucket), read
through the reader `ProjectDocument` already holds for the waveform. The
cut is one core op so it is one undo step and one tool.

- `SilenceDetector.swift`: for the clips in scope, map each clip's peaks
  through `in` and `speed` to project time; a bucket is quiet below a
  threshold (default −40 dBFS); a quiet run shorter than the minimum
  (default 0.5 s) is kept; the survivors lose a padding (default 0.1 s) at
  each end. A span is silent only where **every** clip in scope is quiet
  — a music bed would otherwise defeat it — so the scope is the selected
  clips, else every unmuted audible clip, and the sheet says which.
- Op `ripple_delete_ranges {ranges: [[from, to], …]}` in `edit_time.rs`:
  normalises and merges the ranges, applies `ripple_delete_range`'s logic
  right to left, returns one project. Empty after merging is `None`.
- UI: Clip ▸ Remove Silences… → `SilenceSheetController.swift`: threshold
  (slider with the dB readout), minimum length, padding, scope popup, a
  live "23 cuts · removes 0:42" line, and the candidate spans shaded on the
  ruler and lanes in the in/out style while the sheet is up.
- MCP: `detect_silence {clips?, threshold_db?, min_length?, padding?}` →
  the ranges (app-state tool, off-main: it reads files), and
  `ripple_delete_ranges` as the op's mirror.

#### 3b. Zoom to region

The screencast zoom is an action on scale / x / y; the maths that turns a
rectangle into that end state belongs in the core, where §5.3's placement
already lives, so the canvas, the inspector button and the tool all get
the same numbers.

| Op | Arguments | Semantics |
|---|---|---|
| `add_zoom_action` | `clip: u32, at: ticks, duration?: ticks = 1 s, region: {x, y, width, height} \| null, fit?: "fit" \| "fill" = "fit"` | Adds an action at CLIP time `at` whose end patch scales the layer so `region` (SOURCE pixels from the cropped rect's centre, the spotlight's frame) fills the canvas by `fit`, and positions it so the region's centre lands at the canvas centre, through the clip's rotation. `region: null` is **zoom back**: the end patch is the clip's base `scale`, `x`, `y`. Same overlap refusals as `add_action`. |

- UI: `Z` (unbound today; ⇧Z is fit timeline) enters a region mode on the
  canvas — drag a rectangle over the selected clip, release to add the
  action at the playhead, Esc cancels — as a `ZoomRegionSession` in
  `CanvasSessions.swift` with its logic in
  `EditorViewController+ZoomRegion.swift` (the eyedropper extension is the
  template for a modal canvas session). The Actions section gains "Zoom to
  Region…" and "Zoom Back".

#### 3c. Obscure a region (blur / pixelate)

The spotlight's inverse: hide a face or a password field. The shader has
the region maths (spotlight) and the kernels (the blur / pixelate fold in
the sample stage); this joins them.

**Schema.** `video.obscure: [ { "shape": "rect" | "ellipse", "x", "y",
"width", "height", "feather", "kind": "blur" | "pixelate", "amount": 0..1 } ]`,
at most **four** (the uniform budget, as for filters), all geometry in the
spotlight's source-pixel frame so a region rides with its layer through
scale, move and rotation. `RC_FORMAT_VERSION` 4.

- **Interpolation rule for lists**, defined once in `actions.rs` and reused
  by Phase 6 for filters: an action's end patch interpolates a list per
  index when the lengths match and each entry's discrete fields (`shape`,
  `kind`) agree, and switches at the end otherwise.
- Shader: a pass parallel to spotlight in `Compositor.metal`; the uniform
  block gains four regions, and `Compositor.swift`'s field order changes in
  the same edit (the order is a contract checked only by reading both).
  `CompositorEffects.swift` holds the Swift side.
- Range checks in `props_check.rs`, clamps in `clamp_video`; `set_video`
  carries the patch, so no new op.
- Inspector: a VideoPane "Obscure" section — rows with shape, kind,
  amount, feather, numeric box, add / remove — and "Place on Canvas",
  which reuses the region drag from 3b with a different commit.

**Where.** `SilenceDetector.swift`, `SilenceSheetController.swift`,
`edit_time.rs`, `model.rs`, `format.rs` + header, `actions.rs`,
`edit_props.rs` / `props_check.rs`, `evaluate.rs`/`recipe.rs` (the clamp), `Compositor.metal`,
`Compositor.swift`, `CompositorEffects.swift`, `VideoPane.swift`,
`CanvasSessions.swift`, `EditorViewController+ZoomRegion.swift`, a new
`core/src/edit_zoom.rs` for `add_zoom_action` (placement maths is a concern
of its own), `core/tests/zoom.rs`, `core/tests/schema_v4.rs`, catalog and
handlers.

**Proof.**
- Silence: a synthesised file with known quiet spans (`ffmpeg -f lavfi`
  sine with gaps) is detected within one bucket (10 ms) plus the padding;
  the export's duration equals the original minus the removed total; the
  frames either side of each cut are the frames that were either side of
  the span.
- Zoom: on a test-card clip, `render_frame` at the action's end shows the
  region's centre pixel at the canvas centre and the region's width equal
  to the canvas width (fit) ±1 px; zoom back returns a frame byte-identical
  to the base; each is one undo step; a rotated clip zooms to the right
  place.
- Obscure: pixels inside the region differ from the plain frame and pixels
  outside are byte-identical; pixelate at amount 1 yields flat blocks of the
  expected size; scaling the layer scales the region (measured centre
  offset); an action from amount 0 → 1 renders the midpoint between the two
  stills.

---

### Phase 4 — Words

*Two sessions. Schema v5 (`text.animation`). Captions in both directions,
and the text animations the spec promised.*

#### 4a. Auto captions

On-device speech recognition into caption clips, laid out exactly as the
SRT importer lays them out — a caption is an ordinary text clip, which is
what already makes burn-in free.

- `Transcriber.swift`: `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition = true` (gated on
  `supportsOnDeviceRecognition`; the language from the sheet), an
  `SFSpeechURLRecognitionRequest` over the media file, segments filtered to
  the clip's source window and mapped through `in` and `speed`. The
  callback API keeps the `async` rule intact (Phase 0's decision). When the
  deployment target reaches macOS 26, `SpeechAnalyzer` is the better
  engine and the swap is confined to this file.
- `NSSpeechRecognitionUsageDescription` in `project.yml`'s Info.plist
  properties, and `requestAuthorization` before the first run. An
  agent-driven app is never the active app, so the grant has to have been
  given once from the UI; the tool says so when it is missing.
- Cue building, shared with the importer as `CaptionLayout` (factored out
  of `CaptionImporter.swift`): ≤ 2 lines, ≤ 42 characters a line, ≤ 6 s a
  cue, at least one frame between cues; then the Caption preset on a track
  of their own, in one undo step (`applyEdit(_, ops)`).
- UI: File ▸ Generate Captions… → a sheet with language, scope (selection /
  in-out range / all), a progress bar and Cancel.
- MCP: `transcribe {clips?, language?, place?: bool = true}` → the cues,
  placed unless told not to. Off-main.

#### 4b. Caption export

`CaptionExporter.swift`: File ▸ Export Captions… picks a track (default:
the one whose clips are all text and which the importer or 4a made) and
writes `.srt` or `.vtt` — the same cues, a different header — with times
from ticks at millisecond precision. An imported SRT round-trips its cue
times exactly. MCP `export_captions {track?, path, format?: "srt" | "vtt"}`.

#### 4c. Text animations

**Schema.** `text.animation: null | { "kind": "typewriter" | "word_fade" |
"line_rise", "in": ticks, "out": ticks = 0 }` — reveal over `in` from the
clip's start, un-reveal over `out` before its end. `RC_FORMAT_VERSION` 5.

- Rust decides: `frame_recipe` gives the text layer a `reveal: f64` (0–1,
  with the direction) and the kind, computed from clip time, so an agent's
  `render_frame` and the export agree by construction. The recipe hash
  therefore changes per frame while animating; `LayerRenderers`' 64-entry
  LRU is enough for a one-second reveal at 60 fps.
- Swift draws it in `LayerRenderers.renderText`: the layout is always the
  FULL text's (the box must not reflow), and the reveal selects what is
  drawn — a glyph prefix (typewriter), per-word alpha with a stagger
  (word_fade), per-line rise and alpha (line_rise). The measured size the
  canvas overlay reads is the full text's.
- Inspector: a TextPane "Animation" section — kind popup, In, Out.

**Where.** `Transcriber.swift`, `CaptionLayout.swift`, `CaptionExporter.swift`,
`CaptionImporter.swift` (loses the layout it shares),
`TranscribeSheetController.swift`, `project.yml`; `model.rs`, `format.rs` +
header, `recipe.rs`, `LayerRenderers.swift`, `TextPane.swift`,
`AppDelegate.swift`, catalog and `AgentServer+Media.swift`;
`core/tests/schema_v5.rs`, recipe tests for `reveal`.

**Proof.**
- A fixture made with `say -o` and a known sentence transcribes to those
  words in order, each cue within ±0.3 s of where the word was spoken;
  Cancel leaves no clips.
- Import an SRT, export it: cue times identical; VTT differs only by header
  and separator.
- Typewriter at `reveal = 0.5` on a left-aligned single line has non-empty
  pixel columns only left of the midpoint; `reveal = 1` is byte-identical
  to no animation; the recipe at `clip.start + in` reports `reveal = 1`.

---

### Phase 5 — Sound

*One to two sessions. No project-schema change — mono already persists,
and the export additions live in the core's export table, not the file.*

- **Mix to mono.** `AudioProps.mono` is in the schema and ignored. Fold
  L+R → (L+R)/2 on both channels in the `AudioDSP` chain, so a track whose
  clips ask for it gets a tap and one that does not stays bit-identical.
  Default false, so no existing project changes sound.
- **Meters.** A second, read-only `MTAudioProcessingTap` per composition
  track created with `kMTAudioProcessingTapCreationFlag_PostEffects` (the
  DSP tap is `PreEffects`, ahead of the fader, and cannot see the mix
  level), publishing peak and RMS per channel at ~30 Hz to a `LevelMeter`
  model. The per-track peaks are summed for display — honest enough for a
  meter, and the writer measures the true mix on export. Placement: a
  two-channel meter at the right end of the timeline bar (the bar already
  holds the view-of-timeline controls; the toolbar keeps its four things)
  — decide in-phase against the design handoff's metrics.
- **Normalise clip.** An Audio-section button: the clip's peak over its
  source window from the peaks cache → `volume` that puts it at −1 dBFS
  (clamped to the model's 4×) → `set_audio`. MCP `normalize_clip {clips,
  peak_db?: -1}` as the composite's mirror.
- **Loudness on export.** `Loudness.swift`: BS.1770-4 integrated loudness
  (K-weighting, 400 ms blocks, −70 LUFS absolute and −10 LU relative gates)
  and true peak at 4× oversampling — about two hundred lines, checked
  against a reference tone. The export sheet gains "Loudness: Off /
  −14 LUFS (streaming) / −16 / −23 (broadcast) / Custom" and a −1 dBTP
  ceiling; the export is then two passes — measure the mix, then write with
  the gain `target − measured`, capped so true peak stays under the ceiling
  (gain only; the sheet says "no limiter"). The gain applies in
  `ExportWriter`'s audio path — export-only by definition, so the
  preview/export tap-sharing rule is not touched. Core:
  `export_settings` gains `loudness_lufs` and `peak_dbtp` overrides,
  validated like the bitrates and echoed in the resolved settings; the
  `export` tool takes the same keys. The final progress line reports
  "Peak −1.0 dBTP · −14.0 LUFS" on every export, normalised or not.
- **WAV and AIFF.** Two rows in `export.rs` — `audio_wav`, `audio_aiff`,
  LPCM 16- or 24-bit — with `audio_m4a`'s size rows; `ExportWriter` already
  writes LPCM for ProRes and needs only the file type.

**Where.** `AudioDSP.swift`, `AudioTap.swift`, `LevelMeter.swift` (model +
view), `Loudness.swift`, `ExporterWriter.swift`, `Exporter.swift` (the
two-pass pipeline), `ExportSheetController.swift`, `AudioPane.swift`,
`TimelineBar.swift`, `export.rs`, `ReelCore.swift` (`ExportSettings`),
`AgentServer+Render.swift`, catalog; `core/tests/export.rs` additions.

**Proof.**
- A mono export's left channel equals its right sample-for-sample; with
  `mono` off the export is byte-identical to before this phase.
- The meter reads −20 dBFS ±0.5 dB on a −20 dBFS tone.
- `Loudness.swift` measures the EBU reference fixture within ±0.1 LU; a
  normalised export lands within ±0.5 LU of the target and its true peak
  never exceeds the ceiling; with Loudness off the export is byte-identical
  to a pre-phase export of the same project (the known duck-edge
  non-determinism means: a fixture without a duck).
- `ffprobe` reports 48 kHz PCM for the WAV and AIFF rows.
- Normalise clip leaves the clip's peak at −1 dBFS ±0.1 in an export.

---

### Phase 6 — Looks

*One to two sessions. Schema v6 (`video.blend`, `shape.gradient`).*

- **Blend modes.** `video.blend: "normal" | "multiply" | "screen" | "add" |
  "overlay" | "darken" | "lighten" | "difference"`. The app is Apple
  Silicon only, so the fragment shader can read the destination through
  framebuffer fetch (`[[color(0)]]`) and every mode is one formula on
  premultiplied (src, dst) in the layer pass — one uniform, one code path,
  no ping-pong target. (Fixed-function factors would cover only multiply,
  screen and add; one path beats two.) The transition partner blends
  normal. A nest clip does not take a blend — its layers are flattened, and
  blending the group would need the offscreen pass the flattening avoids
  — so `set_video {blend}` on a nest clip is an `Err` naming that.
  Inspector: a Blend popup in the Transform section beside Opacity.
- **Gradient fills.** `shape.gradient: null | { "kind": "linear" |
  "radial", "stops": [{ "at": 0..1, "color": [r,g,b,a] }], "angle": deg }`,
  drawn by `LayerRenderers.renderShape` with `CGGradient` and taking
  precedence over `fill` when set. The canvas background stays a colour:
  a full-canvas gradient or image is a shape or image clip on the back
  track, and **Clip ▸ Add Background…** makes exactly that — a
  canvas-sized rectangle, or the chosen image, on a new track at index 0.
- **Blurred background fill** (the vertical-repurposing move). Clip ▸ Add
  Blurred Background: a composite over existing ops — a new track at
  index 0, the clip's payload `paste`d onto it at the same start, then
  `set_video` with Fill scale, `x`/`y` 0, crop cleared and
  `filters: [{blur, 1}]` — in one undo step. MCP `add_blurred_background
  {clip}` mirrors the composite.
- **Filters as action targets.** Phase 3's list rule makes `filters`
  interpolate per index; this phase lets `set_action_end` carry them and
  the Filters section write through `InspectorBinding` while the playhead
  is inside an action, as every other section does. `clamp_video` already
  bounds them.

`RC_FORMAT_VERSION` 6.

**Where.** `model.rs`, `format.rs` + header, `props_check.rs` (range checks
for the new fields), `actions.rs`, `Compositor.metal`, `Compositor.swift`,
`CompositorEffects.swift`, `LayerRenderers.swift`, `VideoPane.swift`,
`ShapePane.swift`, `EditorViewController+AddClips.swift` (the two
background commands), `AppDelegate.swift`, catalog and handlers;
`core/tests/schema_v6.rs`, action tests for the list rule.

**Proof.**
- Multiply of 50 % grey over 50 % grey measures 25 % ±1/255 at the centre;
  screen 75 %; add clamps at white; `normal` is byte-identical to before.
- A linear gradient 0 → 1 across a box measures monotonic per column and
  hits the stop colours at its ends.
- Add Blurred Background renders byte-identically to the same three ops
  applied by hand over MCP.
- An action from `blur 0` → `blur 1` renders at its midpoint byte-identical
  to a static `blur 0.5` (with `ease` linear).

---

### Phase 7 — Output

*One to two sessions. No project-schema change; the export table and app
state.*

- **Save Frame.** File ▸ Save Frame… (⌥⌘E) → save panel, PNG / JPEG /
  HEIC at document size, through `Exporter.renderFrame` — the one path.
  `EditorViewController+SaveFrame.swift`. MCP: `render_frame` gains
  `path?` so an agent can name the file.
- **ProRes 4444 with alpha.** A `prores_4444` row in `export.rs` (MOV; the
  writer already maps the codec at `ExporterWriter.swift:602` and nothing
  can ask for it), with `alpha: true` in the resolved settings whenever the
  canvas background's alpha is below 1. `ExportWriter` reads BGRA with
  alpha and writes `AVVideoCodecType.proRes4444`; the compositor already
  clears to the premultiplied background, so alpha 0 clears transparent.
  The Document tab's background well gains an alpha slider (or a
  "Transparent" switch). Confirm APNG keeps alpha on the same canvas.
- **Timecode burn-in.** An export option, never a preview one. The core
  appends the layer, so preview-vs-export stays one description:
  `rc_project_frame_recipe_opts(handle, t, opts_json)` — a new export, so
  header and `ReelCore.swift` move in lockstep — takes
  `{"burn_in_timecode": true}` and adds a text layer (mono face,
  bottom-centre, backdrop) whose `content` is `timecode_format(t)`. The
  export pipeline passes the option through `RecipeSource`; the `export`
  tool takes `burn_in_timecode`. The per-frame recipe hash churns the text
  texture cache, which is fine at export speed.
- **Remembered settings and user presets.** The sheet reopens on the last
  choice (UserDefaults); named user presets are a name → overrides map in
  `~/Library/Application Support/Reelcut/ExportPresets.json`, resolved by
  the core's `export_settings` like any overrides, so the core never learns
  about them. A Preset popup at the top of the sheet with Save… / Delete.
  The `export` tool stays on the core's vocabulary.
- **Export queue.** `ExportQueueController.swift`: the sheet's "Add to
  Queue", Window ▸ Export Queue, sequential jobs each holding an immutable
  project handle (so later edits do not change a queued job), per-row
  progress and Cancel. Last in the phase; drop to the next session if the
  rest ran long.

**Where.** `EditorViewController+SaveFrame.swift`, `export.rs`,
`ExporterWriter.swift`, `Exporter.swift`, `DocumentPane.swift`, `recipe.rs`
+ `ffi_query.rs` + header + `ReelCore.swift` (the recipe options),
`ExportSheetController.swift`, `ExportPresetsStore.swift`,
`ExportQueueController.swift`, `AgentServer+Render.swift`, catalog;
`core/tests/export.rs` and a recipe test for the burn-in layer.

**Proof.**
- Save Frame's PNG is byte-identical to `render_frame` at the same `t`.
- A ProRes 4444 export of a transparent canvas with one small clip:
  `ffprobe` reports an alpha pixel format and a corner pixel decodes with
  alpha 0; the clip's pixels are unchanged from the opaque export.
- The recipe at `t` with the option carries a text layer whose content is
  the document's timecode for `t` (core test); the burnt-in frame differs
  from the plain frame only inside the caption's box.
- Quit and relaunch keep the last export choice; a saved preset reproduces
  the same resolved settings JSON.
- Two queued jobs produce files identical to two single exports.

---

### Phase 8 — Viewing and finding

*One session. No schema; view state throughout.*

- **Preview quality.** View ▸ Preview Quality ▸ Full / Half / Quarter
  scales the PLAYER's `AVMutableVideoComposition.renderSize` only; the
  compositor already draws to whatever target it is handed
  (`render_frame`'s `maximumSize` path proves it — check
  `renderContextChanged` is honoured), the `AVPlayerLayer` upsamples, and
  the overlay maps through `videoRect` so the handles do not move. Export
  and `render_frame` ignore it. Persisted in UserDefaults. Measure 4K on
  the compositor's timing log before deciding whether "Auto — half while
  playing, full when paused" should be the default.
- **Preview window.** View ▸ Preview Window (⇧⌘P) opens
  `PreviewWindowController`: a second `AVPlayerLayer(player:)` on the same
  player (a player drives any number of layers), no overlay, black
  surround, full-screen capable, frame autosaved so it stays on a second
  display. Transport keys forward to the editor.
- **Media tab search and sort.** `MediaPane.swift`: a search field (name
  contains), a sort popup (name, duration, added, kind), an "unused only"
  filter, and a "Reveal in Timeline" context item that selects the clips
  using that media. Spec §11 names a growing library as the trigger for
  revisiting the no-left-panel decision; this is the cheaper answer first.

**Where.** `Playback.swift`, `CompositionBuilder.swift` (render size for the
player's composition only), `PreviewWindowController.swift`,
`MediaPane.swift`, `AppDelegate.swift`.

**Proof.**
- Half quality drops the compositor's per-frame time (its own log) and a
  paused frame differs from full only by resampling; an export is
  byte-identical whatever the setting.
- The preview window shows the frame the canvas shows, at all times,
  because both are one player.
- Search narrows the list; Reveal in Timeline selects exactly the clips
  whose source is that media.

---

### Phase 9 — Inside the nest

*Two sessions. No schema. The largest item, last because it touches every
op at once — and the one the spec designed and left (§4.4).*

The block is that every op's clip argument resolves through
`Project::clip`, which sees the top level only. The fix is not to teach
every op about nests; it is to give the op a **scope**.

- **Core.** The envelope gains `scope?: u32` (a nest id). With a scope,
  `Project::apply` builds a **view project** — canvas = the nest's frozen
  size at the parent's fps and background, `tracks`/`clips` = the nest's,
  `media` and `nests` = the parent's, `markers` = none, `next_id` = the
  parent's — applies the op to it unchanged, and writes `tracks`, `clips`,
  `next_id` and any nests added or dropped back into the parent. Every op
  works inside a nest without an edit to it, `Project::clip` keeps its
  meaning, and undo is still one stack of parent handles. Ops with no
  meaning inside (`set_canvas`, the marker ops, `add_media`,
  `relink_media`, `remove_media`, `nest` of the whole scope into itself)
  are an `Err` naming the scope. Caps are the parent's, as today.
- **Reading inside.** `rc_project_scoped(handle, nest_id)` returns a new
  immutable handle for the view project — one new export, so header and
  `ReelCore.swift` move in lockstep — and the app plays, plans, renders
  and snapshots it like any project: the composition plan, the frame
  recipe and the timeline all come from the scoped handle, while every edit
  goes to the PARENT's handle with `scope` set. Nest-local time is
  `t − nest_clip.start`; a nest has no speed, so nothing else maps.
- **App.** `EditorViewController+NestScope.swift`: double-click a nest clip
  (or Clip ▸ Open Nest, ⌘↓; Clip ▸ Close Nest, ⌘↑) sets a view-state scope;
  the timeline and canvas show the scoped snapshot; a breadcrumb
  ("Timeline › Intro", click to go out) sits at the left of the ruler over
  the track headers, where the 22 pt row has room; the canvas shows the
  nest at its own frozen size with the outer transform NOT applied (a
  compound clip is edited on its own terms). The playhead maps in and out
  so the frame stays. Leaving re-selects the nest clip. Entering and
  leaving is not an undo step. `ProjectDocument.applyEdit` is unchanged;
  the scope rides in the op JSON.
- **MCP.** Every op tool takes `scope?`, checked like any argument
  (`AgentServer+Arguments.swift`); `set_scope {nest?}` mirrors the
  double-click so `render_frame` and `get_project` can look inside;
  `get_project` reports the scope with the playhead and selection.

**Where.** `edit.rs` (the envelope and the view/write-back), a new
`core/src/scope.rs` for building the view and merging it back, `ffi_query.rs`
+ header + `ReelCore.swift`, `core/tests/scope.rs`; Swift:
`EditorViewController+NestScope.swift`, `TimelineView` extension for the
breadcrumb, `Playback.swift` / `CompositionBuilder.swift` taking the scoped
handle, `AgentServer+Arguments.swift`, `AgentServer+Project.swift`, catalog.

**Proof.**
- For a table of ops (slip, trim, split, set_video, add_text_clip, delete,
  move_clip), "apply inside with `scope`, then `unnest`" equals "`unnest`,
  then apply at top level" on clip content, ids aside.
- A frame rendered inside equals the corresponding region of the outer
  frame when the nest clip is at the identity transform.
- Entering, editing, leaving is exactly one undo step per edit, and undo
  restores the outer frame.
- A v2 file is untouched; `rc_op_names` is unchanged (scope is an envelope
  key, not an op).

## 3. Proposed keys and menu items

Checked against spec §9 for conflicts; a phase that binds one promotes its
row into §9.

Phases 1 and 2's rows have been promoted into spec §9's bound table and
are struck from this one; what is left is what is still only a claim on a
key.

| Keys | Action | Phase |
|---|---|---|
| `Z` | Zoom-to-region mode on the canvas | 3 |
| ⌥⌘E | Save Frame… | 7 |
| ⇧⌘P | Preview Window | 8 |
| ⌘↓ / ⌘↑ | Open / close nest | 9 |

Menus. **Landed in phase 1**: Clip ▸ Close Gap, and Edit ▸ Insert at
Playhead / Overwrite at Playhead / Select All on Track. There is no Edit ▸
Lift item and there should not be — a lift is what ⌫ does with a range and
nothing selected, so it is the Delete item's other half rather than a
second row saying almost the same thing. **Landed in phase 2**: Clip ▸
Rename… and Label ▸ (the six colours, each with its swatch, then None),
Edit ▸ Paste Attributes, and Track ▸ Solo — no key, a checkmark for the
current track, the header's S being the everyday path.

Still to come: Clip gains Remove Silences…, Add Background…, Add Blurred
Background, Open / Close Nest; File gains Generate Captions…, Export
Captions…, Save Frame…; View gains Preview Quality ▸ and Preview Window;
Window gains Export Queue.

## 4. Considered and left out

Named so the next reader does not re-derive them.

- **Voice-over recording.** Spec §1 excludes screen and camera recording;
  microphone capture is on the boundary and is the user's call. If wanted
  it is one session: an audio-only `AVCaptureSession` to a WAV inside
  `media/`, `add_media`, `add_clip` at the playhead, a record button with
  a meter (Phase 5's).
- **LUTs (`.cube`).** Colour grading beyond per-clip controls is a non-goal.
- **Speed ramps.** `speed` is not an action target; a ramp is several plan
  segments at different rates, which `scaleTimeRange` can do but the model,
  the plan and the audio envelopes would all have to learn. Feasible, not
  asked for.
- **Motion blur, stabilisation, optical-flow retiming, auto-reframe.**
  Heavy pixel work or ML; outside the compositor's one-pass shape.
- **Multicam, plugins, other platforms.** Spec §1.
- **A left-hand media browser with bins.** Phase 8's search and sort come
  first; §11 says when to revisit.

## 5. What "done" means here

The same as before: the phase's proof exists as measured output from the
built binary and from black-box core tests, `make test` and `make lint` are
clean, `make typecheck` is at its baseline, the status table above says
"done" with the date and the commit, and `CLAUDE.md`'s milestone status, the
spec's tables and the README say what now exists.

Phase 1 added one clause to that, having learnt it the hard way: **the
change has been read back adversarially and what that found is fixed and
covered.** A phase is not done because its own tests pass — those test the
cases whoever wrote them thought of. It is done when someone has gone
looking for what they did not.
