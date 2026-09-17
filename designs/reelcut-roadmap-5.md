# Reelcut — road map 5: transitions and motion (E1, E2)

**Status: BUILT — E1 and E2's core in `e8028a2` (2026-09-16),
`add_transition`'s `ripple` form in `5da056c` (2026-09-16), E2's chrome in
`6dda2c7` (2026-09-17); both phases' own proof instruments and the reader
review are still owed — §12 is the record.** Two phases, taken on
2026-09-15 from the
survey of another editor's transitions, effects and filters
(`designs/reelcut-effects-survey.md`): **E1**, transitions learn direction,
easing, an audio crossfade and a way to be added at a hard cut; **E2**, clips
get In / Out / During motion presets. The survey's other seven phases — tone,
filters, looks, adjustment clips, LUT import, voice effects, background
removal — are DEFERRED by the user's decision the same day ("we'll eventually
add color grading and LUT import, but not now"), and nothing here plans them.

The survey's E1 and E2 sections were reviewed by two readers against the tree
before this plan was written (survey §10), and two scouts then collected
every file:line this plan cites, on the working tree as of 2026-09-15 —
which carries road map 4's uncommitted S1. **Line numbers are a snapshot:**
every lane re-reads its files before it edits, and a number that moved is
not a finding. Where this plan and the survey disagree, this plan is the
later word; the disagreements are listed in §9. This plan was itself read
against the tree by one more reviewer before it was trusted, and its findings
are folded in (§10).

The build follows the shape that landed road map 2's phases and road map 3:
tolls as pure moves landed and gated alone, lanes on disjoint files with the
seam between them written into the tree first, proof and adversarial review
in parallel, fixers routed by the root file with a mutant each, the
orchestrator's lockstep pass, then the commit.

---

## 0. The two phases, in one paragraph each

**E1 — Transitions, second pass.** `Transition` grows `curve` and `audio`
(schema v7); three wipe directions join the vocabulary; the core eases the
progress it hands the renderer; an overlap whose transition says `audio:
true` crossfades its two clips' sound at constant power; `add_transition`
makes an overlap at a hard cut out of the two clips' handles without moving
anything else on the timeline; `set_transition_style` edits the curve and the
audio flag; Remove Silences never proposes a cut inside a transition. Two new
ops and tools (`OP_NAMES` 57, catalog 77), no FFI change, no shader change.

**E2 — Motion presets.** `video.motion` (schema v8) holds up to three presets
— an arrival, a departure and a motion during the whole clip — that the core
turns into placement at render time, RELATIVE to what the clip already is and
composing with its actions, its transitions and each other. The model and
every edit see the clip un-moved; the recipe draws it moving. No op, no tool
(a `set_video` key), no FFI change, no shader change.

---

## 1. Preconditions and the build's shape

### 1a. Before E1's first commit

1. **Road map 4's S1 is committed.** It has uncommitted edits in files both
   phases touch — `SilenceDetector.swift` and `SilenceDetector+Walls.swift`
   (E1's detector rule), `AgentCatalog+Clips.swift` (E2's `set_video`
   description), `tools/proof/harness/build.sh`, `designs/reelcut-design.md`,
   `app/CLAUDE.md` and `CLAUDE.md`. A lane that edits one of them on top of
   another session's uncommitted work cannot be reviewed or reverted on its
   own. If S1 is still open when E1 is wanted, the CODE lanes can run except
   the detector lane (§4d, S-silence) — but so much else waits with it that
   S1-first is the plan: the §11 entries (commit 1) and T0a's spec §7.10
   edit are in `designs/reelcut-design.md`, and wave 6's docs edit both
   `CLAUDE.md` files, all three dirty with S1.
2. **The spec §11 entries in §2 below are written** into
   `designs/reelcut-design.md` before any code, road map 3's rule.
3. **A reference build exists.** Several claims are "byte-identical to the
   pre-phase binary". The instrument is a `git worktree` at the commit before
   the phase's first toll, built with `make app` into its own `build/`, run
   on its own port beside the build under test — the phase 5 reference-build
   and phase 8 two-instance precedents. It is built once per phase and named
   in the proof's docstring by commit.

### 1b. The gate every commit passes

`make test`, `make lint`, `cargo fmt --check`, `make typecheck` (0 errors, the
same 4 AVFoundation warnings), `make app`, the startup parity log EMPTY
(`grep "Reelcut: "`), and every earlier proof re-run against the final
binary: over MCP 66, 85, 121, 8, 84, 88, 167, 92, 79, 214, 79, 187 (road map
3's `recording_proof.py`), and road map 4's once S1 has one; offscreen 26, 33,
59, 81, 70, 78, 150, 48, 62, 170, and `recording_probe.py` 876. A number that
moved is investigated before it is updated; §4e and §6e name the ones that
are EXPECTED to move and why.

### 1c. Wave shape, per phase

| Wave | What | Parallel? |
|---|---|---|
| 0 | Tolls — pure moves, one commit each, gated alone | no — in order |
| 1 | The schema lane: the new keys, the version bump, the seam types in Rust AND Swift | one lane |
| 2 | Core lanes on disjoint files | yes |
| 3 | Swift lanes on disjoint files | yes |
| 4 | `make app`, then proof scripts and adversarial review | yes (MCP proofs beside review; offscreen proofs after any harness build) |
| 5 | Fixers by ROOT file, each fix with its own mutant | yes |
| 6 | The orchestrator's lockstep and docs pass; the commit | no |

Lanes that measure against the built binary are sequenced after lanes that
need `make app`; concurrent lanes race `make typecheck` and are told to retry
a failure that names another lane's file. Every brief says the plan and the
scouts' facts are "to verify, not gospel", and asks for BLOCKERS explicitly.
A new Swift file is under 400 lines; a lane that crosses it splits the file
itself.

---

## 2. Decisions for spec §11 — recorded before E1's first line

**R5-1 — Effects are closed vocabularies, never a runtime.** Every transition
kind and motion preset is an enum variant or a struct the core range-checks,
the recipe carries, the MCP catalog mirrors and the one compositor draws.
There is no package format, no user shader, no expression language. (The
survey's D1; it is the reason neither phase adds a Metal pipeline.)

**R5-2 — A transition's sound is a constant-power crossfade, on by default
for NEW transitions and absent from old files.** The overlap a person adds a
transition at is two different moments — a Remove Silences cut, a jump
between takes — which is uncorrelated material, where constant power holds
the level and equal gain dips 3 dB; Premiere's and Final Cut's default
crossfades are the same law. A version-6 file has no `audio` key and sounds
exactly as it did; every transition the core mints from version 7 on says
`audio: true, curve: ease_in_out`. One constructor, `Transition::minted`,
is the only place those two values are written.

**R5-3 — `add_transition` builds the overlap from handles, clamps the
duration, and never moves a third clip.** A shorter transition is the same
edit at a size the media allows; a gap closed part-way (`close_gap`'s
refusal) is a different edit. Not being at a hard cut is a wrong ARGUMENT
(`Err`), because the op is pointed at one cut by a caller who meant that
cut — unlike `roll`, which a drag can reach at any edge; having no handle is
a domain refusal (`Ok(None)`).

**R5-4 — Motion is a presentation term.** `video.motion` is stored in the
model and drawn by the recipe, but `evaluate_clip`, `get_project`, the
inspector's fields and every edit read the clip un-moved. It is the second
place the recipe draws what the model does not say — the first being the
forced `normal` blend under a transition — and spec §5.3 says so. It is not
an animation target: an action cannot animate it, and a file that tries is
drawn with the base motion.

**R5-5 — Motion is a pure function of clip time.** No seed, no wall clock,
no previous frame: `render_frame` at a tick is byte-identical run after run,
preview and export agree, and two clips with the same preset at the same
clip time are displaced identically.

---

## 3. E1 — the specification

### 3a. Schema (version 7)

```json
"transition_in": { "kind": "wipe_up", "curve": "ease_in_out", "audio": true }
```

- `Transition` (`core/src/model.rs:396-400`, `#[derive(Copy, Eq, Default)]
  #[serde(default)]`) gains `curve: Curve` and `audio: bool` after `kind`.
  Both derive their defaults (`linear`, `false`), keep `Copy`/`Eq`, and
  serialise as `kind, curve, audio`.
- `TransitionKind` (`model.rs:402-415`) gains `WipeLeft`, `WipeUp`,
  `WipeDown`, APPENDED after `Zoom`. `wipe` keeps its name and meaning (the
  edge travels rightward). No migrate step: every new field defaults.
- `impl Transition { pub fn minted(kind: TransitionKind) -> Transition }`
  writes `curve: EaseInOut, audio: true`, in `model.rs`.
- `RC_FORMAT_VERSION` 6 → 7 in `core/src/format.rs:85` and
  `core/include/reelcut_core.h:56`; a version paragraph in `format.rs` in its
  own words (after the v6 paragraph at :63-84: the loss a version-6 build
  would write back is a transition's easing and its crossfade, and the minted
  values differ from the file defaults on purpose — R5-2), and the history
  comment in the header (:45-55). `format.rs`'s migration-hook comment
  (:257-263) gains "and 7".

### 3b. `set_transition` and `set_transition_style`

- **`set_transition {clip, kind?}` — unchanged in shape.** `kind` absent or
  `null` clears (`edit.rs:119`). With a kind: when the clip already HAS a
  `transition_in`, only its kind changes and its curve and audio stay; when
  it has none, it gets `Transition::minted(kind)`. This fixes the collision
  the scout found: a kind change from the popup, the menu or MCP must not
  reset a curve the person set.
- **`set_transition_style {clip, curve?: curve, audio?: bool}` — new.**
  Absent keeps (neither argument is nullable, so an absent key is
  unambiguous — the reason this is a separate op: `set_transition` cannot
  tell `{clip, curve}` from a clear). It behaves exactly like `set_transition`
  about WHERE it stores: on any clip, with or without an overlap (a stored
  transition on a clip with no overlap is undrawn, as it is today). With no
  stored transition and at least one of the two keys given, it stores
  `minted(cross_dissolve)` with the style applied. `{clip}` with NEITHER key
  is `None` whatever the clip holds — it never mints. `Err` for an unknown
  clip; `None` when nothing changes.

### 3c. `add_transition`

`add_transition {clip: u32, kind?: transition, duration: ticks, align?:
center | before | after = center}` in `core/src/edit_transition.rs`, with
`pub enum TransitionAlign` beside it (`edit_zoom.rs`'s `ZoomFit` is the
precedent for an argument enum living with its op). The steps:

0. **`duration` ≤ 0** → `Err("duration must be positive")`, before anything
   else.
1. **Find the cut.** `B` = `clip` (unknown → `Err`). `A` = the clip on B's
   track with `clip_end(A) == B.start` — `roll`'s test
   (`edit_edge.rs:141-148`). No such clip → `Err("clip N is not at a hard
   cut")`, with the message naming which of: no predecessor, a gap, an
   existing overlap (the predecessor ends after B starts — use
   `set_transition`).
2. **Handles, in timeline ticks** (the helpers already divide by speed —
   applying speed again is the bug to avoid):
   - B's head: `source_head(B)` for a `Source::Media` clip (`None` never
     occurs there; `Some(0)` for a bad speed); UNBOUNDED for still, image,
     text and shape; for `Source::Nest`, **0** — trimming a nest clip's head
     moves its contents (`nest.rs:22-28`), so a nest `B` gives nothing, exactly
     like a media clip already at `in` 0: under `center` the whole request
     moves to A's tail (step 3), under `before` it lands below a frame and
     is the domain refusal of step 7. One rule for "no handle", as R5-3
     states it — not an `Err` of its own.
   - A's tail: `source_length(A) − A.duration` for a media clip, where
     `source_length` returning `None` (unknown media, bad speed) means NO
     tail; unbounded for still, image, text and shape; for a nest `A`,
     `max(0, nest.duration() − A.duration)` (`model.rs:347`) — past the
     nest's own length it draws nothing (`nest.rs:29-33`).
3. **Work in whole frames.** `d` is snapped DOWN to whole frames first; each
   handle is floored to whole frames (A's tail with `snapped_down` of its
   end, B's head with `snapped_up` of its earliest start —
   `edit_clip.rs:248, 252`, `roll`'s snap-inward bounds at
   `edit_edge.rs:159-166`). Snapping two half-extensions separately would
   LOSE the odd frame (1.5 + 1.5 frames snap to 1 + 1), which is why the
   split happens after the snap, in frames.
4. **Split the request by `align`.** `center`: `b = ceil(d/2)` frames from
   B's head, `a = d − b` from A's tail (the odd frame goes to B); `before`:
   `b = d`, `a = 0`; `after`: `a = d`, `b = 0`. Each side is clamped to its
   handle; under `center`, a side's shortfall moves to the other side (up to
   that side's handle) before `d` shrinks.
5. **Neighbour bounds.** A's new end may not pass the start of B's successor
   on the track (if any); B's new start may not pass the end of A's
   predecessor. These are closed-form.
6. **The overlap rule.** Apply the extensions to a scratch copy of the track
   and run `check_overlap_rule` (`transition.rs:202-253` — it is NOT part of
   `validate`, so the op calls it itself, as `roll` does at
   `edit_edge.rs:204-209`). If it fails (the half-of-the-shorter-clip rule,
   whose bound moves as the durations grow), step the total down by one frame
   — taken from the larger side — and retry. The loop is bounded by the
   frame count of step 4's result.
7. **Below one frame** after steps 3–6 → `Ok(None)`, a domain refusal
   documented in the op's doc comment.
8. **Write.** A's `duration += a`. B's `start −= b`, `duration += b`, and its
   `in` moves back by `b × speed` in source ticks — the same arithmetic
   `trim_start` (`edit_clip.rs:770-791`) and `roll` (`edit_edge.rs:175-195`)
   inline; extract it into a `pub(crate)` helper in `edit_edge.rs` only if
   the lane finds a third copy would otherwise be written.
9. **Rebase B's actions.** Every action's `start += b`, so an action stays
   on the source frame it was drawn over (a screencast zoom stays on its
   click). `trim_start` deliberately leaves actions alone
   (`edit_clip.rs:750-754`); a transition is not a trim, and the op's doc
   says why they differ. B's `fade_in`, text reveal and (E2) motion `in` are
   measured from B's NEW first frame, so they begin under the transition.
10. **The kind.** `kind` given → used; absent → B's stored
    `transition_in.kind` if any (Clip ▸ Transition ▸ already stores an
    undrawn one at a hard cut, `edit_clip.rs:1185-1199`), else
    `cross_dissolve`. A stored transition keeps its style; a new one is
    `minted`.
11. `finish` (`edit_clip.rs:288`). One undo step. The landed duration is
    readable back through `get_project`.

### 3d. Easing

`transition.rs`'s `kind_of` (:86-88) becomes `transition_of_later(later:
&Clip) -> Transition` (still `unwrap_or_default` — the FILE default, so an
overlap with no stored transition stays linear and silent), and
`transition_among` (:114-133) applies `actions::ease(transition.curve, raw)`
(`actions.rs:75`, `pub`) before returning. Its only callers are
`recipe.rs:423, 436` inside `transition_of`, and both consumers of the
recipe's `progress` in Swift — the shader (`Compositor.swift:1311`) and the
zoom partner box (`:1359-1360`) — want the eased value, so `recipe.rs` is
untouched and a linear or absent curve is byte-identical.

### 3e. The audio crossfade

Nothing in Swift changes: `CompositionBuilder.audioParameters`
(`CompositionBuilder.swift:551-573`) turns `plan.ramps` into volume ramps,
and the level meter (`LevelMeter.swift:290`) and the silence detector read
the same ramps.

- **Stage learns its container.** `Stage {clip, origin, track_muted}`
  (`audio.rs:160-176`) gains `container: Option<&'a Nest>` (`None` = the
  timeline), filled in `Voice::of` (`audio.rs:199-224`), which already
  resolves the per-depth container for solo (:200-205, `inside[d-1].nest`).
  `evaluate.rs:345`, the only call, is unchanged.
- **`Side` is threaded.** `gain_at(a, Side)` (:502) passes its side to
  `voice_gain(v, t, side)` (:522) and `stage_gain(stage, t, side)` (:535);
  both signatures change.
- **A side-aware progress** in `transition.rs`: `pub(crate) fn
  crossfade_among(clips: &[Clip], clip: u32, t: Ticks, side: Side) ->
  Option<(Transition, f64, bool)>` — `(the later clip's transition, eased
  progress, is_incoming)`, CLOSED at the end on `Side::Left` so the outgoing
  clip's last sample reads p = 1 (`transition_among` is half-open and would
  answer `None` there, reading as gain 1 and undoing the fade on the last
  breakpoint). `Side` moves from private in `audio.rs` to `pub(crate)` so
  `transition.rs` can name it (no module cycle: `audio.rs` does not import
  `transition.rs` today).
- **The term**, in `stage_gain`: at container time `t − origin +
  stage.clip.start` (`recipe.rs:416-417`'s `local`), over the container's
  clips (`container.map(|n| &n.clips[..]).unwrap_or(&project.clips)`), when
  `crossfade_among` answers and the transition's `audio` is true: the
  outgoing stage × `cos(p·π/2)`, the incoming × `sin(p·π/2)`. Every stage's
  term multiplies, so a clip inside an overlap inside a nest that is itself
  in a transition gets both fades — where the recipe picks the clip's own
  transition first (`recipe.rs:409-445`). That difference is right for sound
  (both fades are audible) and is one sentence in `audio.rs`'s module doc.
- **Breakpoints.** `breakpoints` (:429-498) samples only audio actions today.
  It gains, per stage with an audio-true overlap, the overlap's two edges
  plus samples every `ACTION_SAMPLE` (`audio.rs:88`, already 1/30 s) across
  it, mapped from container time back to project time; the sine law is not
  linear and neither is an eased `p`.
- Mute, solo, ducking and volume keep their precedence: the term multiplies,
  as ducking does. A pair where only one clip has audio still fades that one.

### 3f. Remove Silences never cuts inside a transition

Candidate logic is Swift only. The rule that a hole in the timeline is never
a candidate lives in the detector's walk (`covered`); nests are "walls"
subtracted by `excludingNests` (`SilenceDetector+Walls.swift:29-54` in S1's
tree). E1 adds **overlap walls**: `read` builds, from
`ProjectSnapshot.clips(onTrack:)` (:1879), one wall per overlap on EVERY
unlocked track — not only the tracks in the detector's scope, because
`ripple_delete_ranges` cuts every unlocked track, and the nest walls are
already built that way (`SilenceDetector.swift:327-337`) — subtracted like
the nest walls, before the length filter, without being reported as
protected nests.

**A wall is the overlap WIDENED by its own length on each side**,
`[B.start − ov, A.end + ov]` with `ov = A.end − B.start`, snapped outward to
the frame grid. The nest walls can be exact because a cut at a nest's edge
splits nothing; an overlap's edges lie strictly INSIDE the other clip, and an
exact wall lets the transition be destroyed by a legal cut: a run `[x,
B.start]` survives a wall of exactly `[B.start, A.end]`, `clear_range`
splits A at `B.start` (`edit_time.rs:120-126`), the shift moves A's tail and
B to `x` together, and A's `ov`-long tail sits wholly under B — a project
that breaks the half rule, which neither `ripple_delete_ranges`
(`edit_time.rs:255-280`) nor `validate` checks. With the wall widened, the
nearest cut leaves each clip at least `2·ov` across the overlap, which is the
half rule's own bound. About 35 lines in `+Walls` and 8 in `read`.

The reason it is needed is not the one the survey gave: the walk requires
EVERY active voice to be quiet, and `max(cos, sin) ≥ 0.707`, so a two-voice
overlap is not made quiet by the fade alone. The real cases are a pair where
only one clip has audio (its gain reaches 0 across the overlap) and handles
pulled out of material Remove Silences already judged quiet — the common
case, since that is where a person adds a transition after cutting.

### 3g. Swift

- **Types** (`ProjectSnapshot.swift`): `TransitionKind` (:370-397) gains the
  three cases and display names ("Wipe Left", "Wipe Up", "Wipe Down");
  `TransitionSnapshot` (:1709-1721) gains `curve: Curve` and `audio: Bool`,
  decoded `lenient(.curve, .linear)` and `lenient(.audio, false)`.
- **Directions** (`Compositor.swift`): `TransitionCode.code` (:488-499) maps
  the three to the wipe shader code; `direction` (:503-515) gives
  `(−1,0)`, `(0,−1)`, `(0,1)`. Both switches are exhaustive, so this file is
  in the same lane as the enum. `Compositor.metal` is unchanged: its wipe
  branch (:1303-1312) takes `local.y` when `|dirY| > |dirX|` and flips on a
  negative component, and `local.y = 0` is the top, so the three sweep left,
  up and down.
- **The Transition section** moves, as a pure move, from
  `VideoPane.swift:1412-1463` to `VideoPane+Transition.swift` (no visibility
  change: `binding` is internal, the row builders are free functions); then
  gains a **Curve** popup (`Curve.allCases`, undo name "Transition Curve") and
  a **Crossfade Audio** check row (undo name "Transition Audio"), both writing
  `set_transition_style`. The summary becomes "kind · curve · N.NN s".
  `ClipPane.swift:152-154` still shows the section only for one clip with an
  overlap.
- **Clip ▸ Transition ▸ None** (tag −1, `EditorViewController+Inspector.swift:153`)
  sends `set_transition` with no kind — a clear — to EVERY selected clip, and
  stays enabled for any selection, as today; it must never reach
  `add_transition`, whose absent kind would ADD a dissolve (§3c step 10).
- **Clip ▸ Transition ▸ `<kind>`** (`EditorViewController+Inspector.swift:139-175`):
  per selected clip — an overlap before it → `set_transition`; a hard cut →
  `add_transition` (0.5 s, `center`, the kind given); anything else →
  skipped. Filter BEFORE
  building the batch: `ReelProject.applying([ops])` (`ReelCore.swift:349-355`)
  throws on the first `Err`, so one clip at a gap would abort the whole
  selection. A batch where every `add_transition` came back `None` beeps and
  says "not enough media beyond the cut". The validator is enabled when any
  selected clip has an overlap or a hard cut before it (Swift's copy of
  roll's test is `EditorViewController+Edge.swift:54`), and still checkmarks
  the first clip's kind. The menu is built from `allCases`
  (`AppDelegate+Menus.swift:344-356`), so the three wipes appear for free. No
  key equivalent (⌘T is Split; spec §9 unchanged).
- **Op builders** (`ReelOps.swift`, where `OpArgs` is file-private, :52):
  `static func addTransition(clip: UInt32, kind: TransitionKind?, duration:
  Int64, align: TransitionAlign) -> ReelOp`, `enum TransitionAlign: String {
  case center, before, after }`, `static func setTransitionStyle(clip:
  UInt32, curve: Curve?, audio: Bool?) -> ReelOp`, beside `setTransition`
  (:645-656); `addZoomAction` (:753-769) is the template. `ReelCore.swift`
  is unchanged.
- **Timeline drawing** needs nothing: `drawTransition`
  (`TimelineClipDrawing.swift:234-263`) draws `displayName`.

### 3h. MCP

- `AgentCatalog+Transitions.swift` (new): `transitionTools(ticks:)` returning
  the `add_transition` and `set_transition_style` rows, spliced into
  `catalogJSON()` in `AgentCatalog.swift:316-318` right after
  `clipAndActionTools(...)` — NOT appended at the very end, where
  `recording_probe.py`'s `names[-11:]` check reads, and NOT in
  `AgentCatalog+Clips.swift`, which S1 is editing. `transitionEnum`
  (`AgentCatalog+Clips.swift:54-59`) is built from `allCases` and gains the
  three kinds for free. Each op tool gets `scope` from `tool()`
  (`AgentCatalog.swift:52`).
- `AgentServer+Transitions.swift` (new, `AgentServer+Background.swift`'s
  89-line shape): the two handlers, using the throwing argument helpers;
  `add_transition`'s `align` refused by name when not one of three; a `None`
  result reworded from `performGroupedEdit`'s fixed text
  (`AgentServer.swift:592-597`) to "made no change: neither side of the cut
  has media beyond it". Two lines in the handler map (`AgentServer.swift:216`,
  beside the transitions at :268-269).
- Each handler's comment names its UI path (spec §7.9).

### 3i. Core tests

- `core/tests/schema_v7.rs` (new, `schema_v6.rs`'s shape): v6 fixture reads
  `curve: linear, audio: false`; round trip; every kind survives including
  the three new; `audio` is the LAST key of `transition_in`, read off the
  written TEXT; default equals absence; `minted` values; a v6 clip's overlap
  renders linear (recipe progress raw).
- `core/tests/model_tests.rs`: `TRANSITION_KINDS` (:46-57) to 13, the three
  new clips at ids **88–90** (30 + i collides at 40–42 with the nest and two
  text clips; 88–99 are free, `next_id` 100); the enum sweep (:535).
- **The version literals that break at 7** — the one-past fixtures
  (`model_tests.rs:958-961, 970-972`, `schema_v3.rs:118-123`, message text
  included) move to 8, and TWELVE current-version assertions move to 7:
  `model_tests.rs:679`, `schema_v2.rs:173`, `schema_v3.rs:87, 135`,
  `schema_v4.rs:128, 158`, `schema_v5.rs:122, 154`, `schema_v6.rs:174, 212`,
  and `model_tests.rs:984-992` — the prior-version sweep's `json!(6)` at :987
  and the absent-version case at :992, whose `[1..6]` list gains 6 → 7. The
  lane greps `core/tests` for `json!(6)`, `"version": 6`, `version 6` and
  `(version 7)` before it trusts this list.
- `core/tests/add_transition.rs` (new): each align on media, still, text and
  shape pairs; the clamp to the shorter handle; `center`'s shortfall moving
  sides; odd frame counts on the grid (3 frames centred → B 2, A 1); the
  neighbour bounds (a third clip never moves, its placement compared whole);
  the overlap-rule step-down; a nest `B` giving no head (`center` moves the
  whole request to A's tail, `before` is `Ok(None)`); a nest `A`'s tail
  handle; a reversed clip's handle in the reversed stream; action rebase;
  stored kind and style kept, `minted` otherwise; `Err` for a non-positive
  duration, no predecessor, a gap, an overlap, an unknown clip; `Ok(None)`
  for no handle; the document compared byte for byte after undo (apply →
  inverse state).
- `core/tests/crossfade.rs` (new): the ramps of two overlapping clips follow
  `cos`/`sin` at every sample within 1e-9; the outgoing clip's LAST
  breakpoint is 0 (the `Side` row); `audio: false` ramps equal the pre-phase
  ramps (a hard-coded expectation from `evaluate_tests.rs`'s helpers); an
  eased curve moves the breakpoints; a pair inside a nest and a nest pair
  (both fades); mute and solo precedence; a one-audio pair. The ramp helpers
  (`evaluate_tests.rs:282` `assert_ramps`) are copied, or moved to
  `tests/common/` if the lane prefers — the `content`/`contents` precedent.
- `core/tests/scope.rs`: `OP_NAMES.len() == 57` (:629); `every_op()`
  (:683-850) rows for both ops, each returning `Ok` inside `every_kind()`'s
  nest (:644), so that nest gains a hard cut with handles — which can change
  other rows, so every row is re-read, and the count in its comment ("the
  forty-eight") moves with it.
- `core/tests/edit_tests.rs`: `op_table` rows (~587-667) against `general()`.
  **`general()` (:46-95) has no two clips that abut** — its comment at
  :675-682 says so, which is why `roll` sits in `UNCHANGING` (:683) — and the
  table PANICS on `Err` (:716), which is what "not at a hard cut" now is. So
  `general()` gains an abutting pair with handles (a second clip on track 6
  ending where the first begins, or starting where it ends, e.g.
  3 000 000–4 200 000); `roll` then changes something and LEAVES
  `UNCHANGING`; every other test built on `general()` is re-run and read.
- `set_transition` keeping style, and `set_transition_style` on an undrawn
  clip, in `add_transition.rs` or a small `transition_style.rs`.

### 3j. Limits recorded

Wipes are measured in each layer's own box, so a different-size pair does not
meet at one edge (a canvas-space edge would break the common same-size pair
and every nested wipe — survey §10). A video pair whose audio is DETACHED has
`enabled.audio` off, so `audio: true` does nothing and the detached clips
stay a hard cut unless they get a transition of their own. Fades to colour
fade the layer's own RGB, so a picture-in-picture clip fades to a black box.
A spinning or otherwise rotated partner disables the dissolve's weight
correction (`Compositor.swift:1350`) and dips darker mid-dissolve — existing,
and newly reachable through E2.

---

## 4. E1 — the build

### 4a. Wave 0 — tolls, one commit each

| Toll | Move | Lines | Gate |
|---|---|---|---|
| **T0a** | `set_gained_transitions` (`edit_clip.rs:83-101`), `set_transition` (:1185-1200), `set_transition_duration` (:1202-1251) → new `core/src/edit_transition.rs`; `pub mod edit_transition;` after `edit_track` (`lib.rs:27`); `pub(crate) use crate::edit_transition::set_gained_transitions;` in `edit_clip.rs` so `edit_nest.rs:42`, `edit_time.rs:28` and `edit_paste.rs:84` keep their imports; `edit_clip.rs:42` drops `Transition, TransitionKind`; the banner at :1161 renamed for `set_enabled` alone; the new file's imports `crate::edit_clip::clip_end`, `crate::model::{Project, Transition, TransitionKind}`, `crate::time::Ticks` | 1252 → ~1165 | `make test`, `make lint`, `cargo fmt --check` |
| **T0b** | `Ducker` (`audio.rs:130-143`), `duck_gain` (:233-294), `duckers()` (:397-427) → new `core/src/audio_duck.rs`; `pub mod audio_duck;` in `lib.rs`; `Side`, `covers`, `MAX_GAIN`, `duck_gain` (still called by `gain_at`) and `Ducker`'s read fields `pub(crate)`; `pub use crate::audio_duck::Ducker;` in `audio.rs` so `evaluate.rs:40` is untouched; imports left unused in `audio.rs` removed (clippy runs `-D warnings`) | 587 → ~483 | same |
| **T0c** | `VideoPane.swift:1412-1463` (MARK and `transitionSection`) → new `VideoPane+Transition.swift`, as an `extension VideoPane` | 1465 → ~1412 | `make typecheck`, `make app`, `phase6_chrome.py` and `phase8_chrome.py` unchanged (they photograph the inspector) |

Docs that name the old homes change in the same commit as each move:
`edit_clip.rs:25-29`, `transition.rs:13-14`, `core/CLAUDE.md:117-130` and
:418-420 (the size note), spec §7.10's module rows.

### 4b. Wave 1 — the schema lane (T1)

**Owns:** `core/src/model.rs`, `core/src/format.rs`,
`core/include/reelcut_core.h`, `core/src/edit_transition.rs` (the two mint
sites: `set_gained_transitions`' `Transition::default()` becomes
`minted(CrossDissolve)`; `set_transition` keeps style when present),
`core/tests/schema_v7.rs`, `core/tests/model_tests.rs`, the schema test
files' version literals (§3i), `app/Sources/ProjectSnapshot.swift` (the enum,
the snapshot fields), `app/Sources/Compositor.swift` (the two switches), and
**the proof scripts that hard-code the version**, which fail the moment it
moves: `phase2_proof.py:316, 337, 358, 371`, `phase3_proof.py:1314, 1355`,
`phase4_proof.py:1068, 1096`, `phase6_proof.py:216` (`VERSION = 6`),
`phase8_proof.py:194` (`VERSION = 6`), `phase9_proof.py:1467` — each a
"the written version is current" check, moved to 7 (phases 3, 4 and 6 edited
earlier scripts the same way; `git log -- tools/proof/phase2_proof.py`). The
lane greps `tools/proof` for `6` near `version` before trusting the list.

**Why Swift is here:** the new `TransitionKind` cases break the exhaustive
switches in `Compositor.swift` the moment the snapshot enum grows, and a
schema that Swift cannot decode is not a landed schema. This lane writes the
SEAM every later lane compiles against:

```rust
// core/src/model.rs
pub struct Transition { pub kind: TransitionKind, pub curve: Curve, pub audio: bool }
impl Transition { pub fn minted(kind: TransitionKind) -> Transition }
pub enum TransitionKind { /* …ten…, */ WipeLeft, WipeUp, WipeDown }
```

```swift
// app/Sources/ProjectSnapshot.swift
struct TransitionSnapshot { let kind: TransitionKind; let curve: Curve; let audio: Bool }
```

**Gate:** wave 0's plus `make typecheck` and `make app`; every proof
unchanged but the version literals above. T1 only STORES `curve` and `audio`
— nothing eases or crossfades until T3 — so no picture or sound may move
here; a moved frame at T1 is a defect.

### 4c. Wave 2 — core lanes (parallel)

**T2 — the ops.** Owns `core/src/edit_transition.rs` (`add_transition`,
`set_transition_style`, `TransitionAlign`), `core/src/edit.rs` (op-table rows
after `set_transition` at :119 in the table's format, the vocabulary line
:122-124 gaining the three kinds, `Op` variants beside :458-466, dispatch
beside :758-761, imports :193-198, `OP_NAMES` 55 → 57 at :205-261),
`core/src/scope.rs` (`refused_inside` :173-259, both to the allowed arm beside
:245-246), `core/tests/add_transition.rs`, `core/tests/scope.rs`,
`core/tests/edit_tests.rs` (`op_table` and `general()`'s new abutting pair). If a head-extension helper is
extracted, it lands in `edit_edge.rs`, which this lane then owns.

Seam for Swift and MCP, frozen at the lane's start:

```text
add_transition        {clip: u32, kind?: transition, duration: ticks, align?: "center"|"before"|"after"}
set_transition_style  {clip: u32, curve?: "linear"|"ease_in"|"ease_out"|"ease_in_out", audio?: bool}
```

**T3 — easing and the crossfade.** Owns `core/src/transition.rs`
(`transition_of_later`, easing in `transition_among`, `crossfade_among`),
`core/src/audio.rs` (`Stage.container`, `Side` threading, the term,
breakpoints, the module doc), `core/tests/crossfade.rs` — which also holds
the eased-progress recipe tests (not `schema_v7.rs`, which is T1's) — and
`core/tests/evaluate_tests.rs`, if any ramp expectation there moves because
an op-made overlap now mints `audio: true`.
`recipe.rs` is NOT in the lane; if the lane finds it must be, it stops and
says so.

T2 and T3 are disjoint. **Gate:** `make test`, `make lint`, `cargo fmt
--check`.

### 4d. Wave 3 — Swift lanes (parallel, after T2's seam and T1)

| Lane | Owns | Needs |
|---|---|---|
| **S-ops** | `ReelOps.swift` (the two builders, `TransitionAlign`) | T2's seam — lands FIRST in the wave (minutes), the others compile against it |
| **S-inspector** | `VideoPane+Transition.swift` | S-ops; T1's snapshot |
| **S-menu** | `EditorViewController+Inspector.swift` | S-ops; T1's snapshot |
| **S-mcp** | `AgentCatalog+Transitions.swift` (new), `AgentServer+Transitions.swift` (new), two lines in `AgentServer.swift`, the splice in `AgentCatalog.swift` | S-ops |
| **S-silence** | `SilenceDetector.swift`, `SilenceDetector+Walls.swift` | S1 committed (§1a) |

No two lanes share a file. **Gate:** `make typecheck` (retry a failure naming
another lane's file), then one `make app` by the orchestrator after all five.

### 4e. Wave 4 — the proof, and the counts that move

**Pictures and sounds that are EXPECTED to move.** From T3 on, an overlap
made by an op mints an eased, crossfading transition, so any earlier MCP
proof that renders a frame inside such an overlap or exports sound across one
may move. The wave-4 gate lists which scripts moved and by what; the
orchestrator decides for each whether it is the feature or a defect before a
number is updated. (Phase 6's `transition_part`, `phase6_proof.py:792-822`,
renders every overlap frame and is the first place to look.)

**Exact counts hand over** (`tools/proof/README.md`'s rule: the newest phase
owns the exact count): `e1_proof.py` asserts 77 tools and 57 ops exactly;
`recording_proof.py`'s `TOOLS = 75` (:342, `==` at :712) and `OPS = 55` (:346,
`==` at :762) become floors; `phase9_proof.py`'s `OPS = 55` (:179, `==` at
:578-579) becomes a floor; `recording_probe.py:5989-5991` (55 ops, 75 tools)
becomes floors — all in the phase's commit, and the README's handover
paragraph gains a sentence.

**`tools/proof/e1_proof.py`** over MCP, against the build and the reference
build (§1a). Fixtures: shape cards (`phase6_proof.py`'s `Session.card` at
:515 and `decode_png` at :353, copied — helpers are per-script) and the two
tones (`toneA.m4a` 440 Hz, `toneB.m4a` 880 Hz, 5 s, 48 kHz, ~−21 dBFS —
**trimmed first**: placed whole they have no handles). PCM through
`phase2_proof.py`'s `pcm`/`samples` (:212-243, copied).

| § | Claims |
|---|---|
| 0 | tools 77 and ops 57 exactly; parity log empty; the reference build answers 75/55 (so the two instances cannot be confused) |
| 1 | a hand-written v6 project opens with `curve: linear, audio: false` in `get_project`; saving writes version 7 with `audio` as the last key; `set_transition` on an existing transition keeps a set curve; `set_transition_style` on a clip at a hard cut stores an undrawn minted transition |
| 2 | `wipe_left`, `wipe_up`, `wipe_down` at p = 0.25 on two full-canvas cards: the incoming colour on the named side, the boundary within one pixel of the eased position; `wipe` renders byte-identical to the reference build on the hand-written v6 fixture |
| 3 | `ease_in_out` puts a push's offset at `smoothstep(0.25)`; the v6 fixture's dissolve frames byte-identical to the reference build at five ticks |
| 4 | `add_transition` on trimmed tones: timeline end, every other clip and the pair's outer edges unchanged; `center` lands centred; a request longer than the shorter handle clamps; an odd frame count lands on the grid with the odd frame on B; `before`/`after`; a nest incoming clip under `center` takes the whole overlap from A's tail, and under `before` makes no change; a zoom action on the incoming clip renders the same source frame at its end before and after; the four `Err` refusals by name; the no-handle reply's text; one `undo` restores `get_project` byte for byte |
| 5 | audio, exported as **`audio_wav`** (16-bit PCM — `audio_m4a` is AAC and its file bytes carry container timestamps) and compared as DECODED samples: an `audio: true` overlap of the two tones, each tone's level measured by projection onto its OWN frequency (a Goertzel filter, road map 3's precedent) in **25 ms windows** — exactly 11 cycles of 440 Hz and 22 of 880 Hz at 48 kHz, so neither leaks into the other's bin — tracks `cos`/`sin` of the eased progress within 0.3 dB wherever the expected gain is ≥ 0.1, and the summed power is flat within 0.5 dB; with the INCOMING clip muted, the outgoing tone is below −60 dBFS in the last 25 ms of its clip (a window, not a sample: M3 measured AVFoundation's mix wobbling by one LSB within 8 ms of a ramp edge); `audio: false` on the hand-written v6 fixture decodes sample-identical to the reference build's export; a nested pair fades inside both nests; a muted incoming clip stays silent |
| 6 | `detect_silence` on a one-audio pair and on a pair built from pre-cut quiet material proposes no range intersecting the overlap; without the transition (the same clips butted) it does |

**`tools/proof/e1_chrome.py`** offscreen: the Transition section with
`expandSections = "video.transition"` shows the Curve and Crossfade Audio
rows (a pixel diff against the reference render scoped to the section's
rectangle); and a menu probe compiled from `app/Sources` (`phase6_chrome.py`'s
`PROBE_SOURCE` template, :497) reads Clip ▸ Transition's validator — enabled
at a hard cut and at an overlap, disabled at a gap and on a first clip — and
that its items include the three wipes.

**Mutants** (each run against a copy of the tree or a build flag, counted,
survivors reported): `cos`/`sin` swapped; the `Side` limit removed; `minted`
writing linear; `set_transition` minting over an existing style; `align`
ignored; speed applied twice to a handle; the action rebase removed; the
overlap-rule step-down removed (a third clip overlaps); the detector's
overlap walls removed; the menu batch unfiltered (one gap aborts the
selection); `TransitionCode.direction` for `wipe_up` given `(0,1)`.

### 4f. Wave 4 — the review (beside the MCP proof)

Four readers, each with ONE question and the diff: (1) the `add_transition`
arithmetic against every source kind, speed, reversal and track shape; (2)
the envelope — `Side`, containers, breakpoints, nests, mute/solo/duck
precedence — against the ramps it produces; (3) the Swift UI — the menu's
batch and validator, the section's writes, undo names; (4) the proof and the
tests — which claims would pass against a build without the feature. Findings
never judged by a refuter are NOT refuted; they are triaged by hand.

### 4g. What only a person at the machine can check

A crossfade across a Remove Silences cut sounds even, not dipped or bumped;
an eased push feels better than the linear one; the Transition submenu at a
hard cut does what a person expects; the three wipes read as the direction
their names say.

---

## 5. E2 — the specification

### 5a. Schema (version 8)

```json
"motion": {
  "in":     { "kind": "slide_up", "duration": 300000 },
  "out":    { "kind": "fade",     "duration": 300000 },
  "during": { "kind": "pulse", "amount": 0.5, "period": 600000 }
}
```

(Ticks: 600,000 per second, `time.rs:26` — so 0.5 s and 1 s.)

- `VideoProps` (`model_props.rs:64-97`) gains `pub motion: Option<Motion>` as
  its LAST key, `#[serde(default)]` → `null`. `Option` rather than a struct of
  three options, so a clip without motion writes `"motion": null` rather than
  three nulls, and `{"motion": null}` clears.
- `core/src/model_motion.rs` (new, `model_text.rs`'s `TextAnimation` shape at
  :190-252):

```rust
#[serde(default)] pub struct Motion {
    #[serde(rename = "in")] pub r#in: Option<MotionEdge>,
    pub out: Option<MotionEdge>,
    pub during: Option<MotionDuring>,
}
#[serde(default)] pub struct MotionEdge { pub kind: EdgeMotion, pub duration: Ticks }        // default {fade, 300_000}
#[serde(default)] pub struct MotionDuring { pub kind: DuringMotion, pub amount: f64, pub period: Ticks } // default {pulse, 0.5, 600_000}
#[serde(rename_all = "snake_case")] pub enum EdgeMotion {
    #[default] Fade, ZoomIn, ZoomOut, SlideLeft, SlideRight, SlideUp, SlideDown, Spin, Pop }
#[serde(rename_all = "snake_case")] pub enum DuringMotion {
    #[default] Pulse, Shake, Spin, Bounce, Drift }
```

  Both enums are closed (serde refuses an unknown kind), and their
  declaration order is NOT load-bearing — nothing crosses to a shader.
  `spin` is in both, like `OBSCURE_KINDS`' shared spellings in the enum
  sweep.
- **Normalisation:** a `Motion` whose three slots are all `None` is stored as
  `None` — by the patch path in `edit_props.rs` and by the split rule — so
  one clip has one spelling of "no motion".
- **Checks** (`props_check.rs::check_video` :118-220, the `text.animation`
  pattern at :275-285): `in.duration` and `out.duration` ≥ 0
  (`ticks_positive_or_zero`); `during.amount` in 0…1; `during.period` ≥ one
  tick (0 would divide by zero). Ticks are NOT snapped to the frame grid by
  the core, as `text.animation`'s are not; the inspector snaps
  (`TextPane.swift:328-330`'s precedent).
- `RC_FORMAT_VERSION` 7 → 8, a `format.rs` paragraph in its own words (the
  loss a v7 build writes back: every entrance and exit, with the clip still
  on screen and nothing to say it ever moved).

### 5b. The presets — every number

Notation: `D` the CLIP's duration (never the instance's — `recipe.rs:512`'s
rule for `text.animation`), `t` clip time, `W, H` the container's canvas
(the project's, or the enclosing nest's frozen canvas), `in′` and `out′` the
slot durations after the tent rule (§5c). `ease_in`, `ease_out` are
`actions::ease`. `back_out(u) = 1 + 2.70158·(u−1)³ + 1.70158·(u−1)²` (the
standard overshoot curve: above 1 from u ≈ 0.37, peak 1.100 at u ≈ 0.58). Each preset yields a
scale factor `F`, a rotation `φ` (degrees, the model's sign), an opacity
factor `O` and an offset `Δ` (canvas pixels, y down).

**Arrivals** — `a = ease_out(u)`, `u = t / in′`, active for `t < in′`:

| Kind | F | φ | O | Δ |
|---|---|---|---|---|
| `fade` | 1 | 0 | a | 0 |
| `zoom_in` | 0.6 + 0.4a | 0 | a | 0 |
| `zoom_out` | 1.4 − 0.4a | 0 | a | 0 |
| `slide_left` (moves left: enters from the RIGHT edge) | 1 | 0 | 1 | `(1−a)·S_right` |
| `slide_right` (enters from the left) | 1 | 0 | 1 | `(1−a)·S_left` |
| `slide_up` (enters from the bottom) | 1 | 0 | 1 | `(1−a)·S_bottom` |
| `slide_down` (enters from the top) | 1 | 0 | 1 | `(1−a)·S_top` |
| `spin` | 0.3 + 0.7a | −180·(1−a) | a | 0 |
| `pop` | `back_out(u)` | 0 | min(1, u/0.25) | 0 |

**Departures** — `d = ease_in(v)`, `v = 1 − (D − t)/out′`, active for
`t ≥ D − out′`, measured back from the EXCLUSIVE end so the last drawn frame
still shows a sliver (`recipe_text.rs:150`'s convention):

| Kind | F | φ | O | Δ |
|---|---|---|---|---|
| `fade` | 1 | 0 | 1−d | 0 |
| `zoom_in` (grows away toward the viewer) | 1 + 0.4d | 0 | 1−d | 0 |
| `zoom_out` (shrinks away) | 1 − 0.4d | 0 | 1−d | 0 |
| `slide_left` (leaves past the LEFT edge) | 1 | 0 | 1 | `d·S_left` |
| `slide_right` | 1 | 0 | 1 | `d·S_right` |
| `slide_up` (leaves past the top) | 1 | 0 | 1 | `d·S_top` |
| `slide_down` | 1 | 0 | 1 | `d·S_bottom` |
| `spin` | 1 − 0.7d | 180·d | 1−d | 0 |
| `pop` | `back_out(1−v)` | 0 | min(1, (1−v)/0.25) | 0 |

**During** — over the whole clip, `A = amount`, `P = period`,
`m = min(W, H)`:

| Kind | F | φ | Δ |
|---|---|---|---|
| `pulse` | `1 + 0.2A·(1 − cos(2πt/P))/2` | 0 | 0 |
| `shake` | 1 | 0 | `0.04A·m·( 0.6 sin(2πt/P) + 0.4 sin(2π·2.7t/P),  0.6 sin(2π·1.3t/P) + 0.4 sin(2π·3.1t/P) )` |
| `spin` | 1 | `720A·t/P` (A = 0.5 is one turn per period) — the TOTAL `φ` is reduced `rem_euclid(360)` (§5c) | 0 |
| `bounce` | 1 | 0 | `(0, −0.08A·H·|sin(πt/P)|)` — one hop per period |
| `drift` | `1 + 0.24A·t/D` (A = 0.5 ends at 1.12; `P` ignored) | 0 | 0 |

Every `during` term is 0 (or F = 1) at `t = 0`, so a clip starts where it is
placed. These numbers are Reelcut's own starting points, tuned by eye at
build time by a person at the machine (§6g) — not Concat's, whose values are
not to be consulted (survey §9).

**Slide distances — just outside the container edge.** With the clip's
source size `(sw, sh)`, crop `(l, t, r, b)`, scale `s`, rotation `θ`, and the
placement rule written at `edit_zoom.rs:38-57` (anchor at the container
centre plus `(x, y)`, the UNCROPPED centre, the pivot):

- visible size `cw = sw − l − r`, `ch = sh − t − b`; crop centre
  `c = ((l − r)/2, (t − b)/2)`;
- the scale and rotation the box is measured at are the DRAWN ones from the
  other slots at this `t`: `s″ = clamp(s·F_total, SCALE_MIN, SCALE_MAX)` and
  `θ″ = θ + φ_total` — the clamped scale, because that is the size drawn;
- with `k = |cos θ″|`, `n = |sin θ″|`: half-extents
  `hx = s″(cw·k + ch·n)/2`, `hy = s″(cw·n + ch·k)/2`;
- the visible centre `p = (x, y) + s·R(θ)·c` (container-centre coordinates)
  — the BASE one, because §5c's pivot compensation holds the visible centre
  at exactly that point whatever the other slots do to scale and rotation;
- `S_right = (W/2 + hx − p.x, 0)`, `S_left = (−(W/2 + hx) − p.x, 0)`,
  `S_bottom = (0, H/2 + hy − p.y)`, `S_top = (0, −(H/2 + hy) − p.y)`.

For TEXT, whose measured size the core never has (spec §11), `hx = W/2`,
`hy = H/2` and `c = 0`: the anchor starts half a canvas beyond the edge,
which clears any text narrower than the canvas. Recorded as a limit.

### 5c. Composition, pivot and the tent

- **Tent:** when `in + out > D`, `in′ = in·D/(in + out)` and `out′ = D − in′`,
  so the arrival ends on the frame the departure begins; nothing refuses.
- **Totals:** `F = F_in·F_out·F_during`, `φ = φ_in + φ_out + φ_during`,
  `O = O_in·O_out`, `Δ = Δ_in + Δ_out + Δ_during` — slides evaluated after
  `F` and `φ` are known.
- **Pivot — the VISIBLE centre.** The core's placement pivots on the
  uncropped anchor; a zoom or spin about it would make a cropped layer drift.
  So the moved position compensates:
  `(x, y)′ = (x, y) + s·R(θ)·c − s″·R(θ″)·c + Δ`, with `s″ = clamp(s·F,
  SCALE_MIN, SCALE_MAX)` (`props_check.rs:45-46`: 0.01, 10) and
  `θ″ = θ + φ`.
- **Rotation is reduced.** `φ` is taken `rem_euclid(360)` before it is added,
  so a whole turn is EXACTLY no turn: a rotation of 360 would reach Swift as
  `Float(360·π/180)`, whose `sin` is ~1.7e-7 rather than 0
  (`Compositor.swift:1270`), and `partnerBox`'s `rotation == 0` guard
  (`Compositor.swift:1350`) would treat it as rotated.
- **Guards — `motion.rs` never trusts the file.** `validate` range-checks no
  property and `evaluate_clip`'s restore (§5e) copies the base motion past
  `clamp_video`, so a hand-written `period: 0`, a negative duration or an
  amount of 5 reaches `apply`. A slot whose duration (after the tent) is
  ≤ 0 is inactive; a `during` with `period` ≤ 0 is inactive; `amount` is
  clamped to 0…1; every factor is checked finite, and a non-finite result
  leaves that field as evaluated. No NaN reaches the recipe.
- **Output:** `scale = s″`, `rotation = θ″`, `opacity = clamp(o·O, 0, 1)`,
  `x, y` as above. Every other field is the evaluated props unchanged.

### 5d. Where it is applied

`core/src/motion.rs` (new):

```rust
pub(crate) fn apply(
    video: &VideoProps,          // the EVALUATED props (actions already applied)
    clip_t: Ticks,
    duration: Ticks,             // the clip's own duration
    size: Option<(f64, f64)>,    // Project::source_size(clip); None = text
    container: (f64, f64),       // W, H
) -> VideoProps
```

It returns `video.clone()` untouched when `motion` is `None`, which is what
makes an unmoving clip byte-identical by construction. It uses
`nest::rotate` (`nest.rs:306`, `pub(crate)`).

Two call sites, both in `recipe.rs`:
- **The layer** (`Project::layer`, :305-375): between `let video =
  &evaluated.video` (:314) and `frame.place(video)` (:317), `let moved =
  motion::apply(video, clip_t, instance.clip.duration, self.source_size(clip),
  container); let video = &moved;` — container
  `instance.inside.last().map(|e| (e.nest.width, e.nest.height))` else the
  project canvas.
- **A nest clip** (`frame_of`, :389-396): each enclosing clip's evaluated
  video is moved before `frame.enter(...)` folds it into every inner layer —
  duration `enclosing.clip.duration`, size the nest's frozen canvas,
  container `instance.inside[i−1].nest`'s size or the project canvas; the loop
  gains the index it needs.

Consequences, stated so nobody "fixes" them:
- **Moves with the picture** (recipe-driven): shadow, reflection, the canvas
  overlay's boxes, hit-testing, handles and snapping
  (`CanvasLayerBox.boxes(recipe:)`, `CanvasSessions.swift:307-320`), the zoom
  region band, the dissolve partner box, `render_frame`, export.
- **Does NOT see motion** (evaluate-driven): `get_project`, `clip_state`
  (`actions.rs:551`), `split_clip`'s state, `edit_zoom.rs:385`,
  `freeze_frame`, the audio plan, the inspector's fields.
- **A canvas drag begun mid-motion starts from BASE props**
  (`PreviewCanvasView.swift:616-624`, `CanvasScaleSession.base` at
  `CanvasSessions.swift:528`), so the box jumps to the un-moved placement at
  mouse-down. Recorded, not fixed.
- **`add_zoom_action` on a clip with `during`** solves against un-moved props
  (`edit_zoom.rs:110-118` promises the region lands as drawn); no base value is
  right at every frame of a moving clip. The region band shows "This clip has
  During motion — the zoom is solved without it" while armed
  (`EditorViewController+ZoomRegion.swift` ~440-463).

### 5e. Model rules

- **Not an animation target.** `set_action_end` (`edit_action.rs:189-218`,
  lenient today) refuses a patch whose `video` object names `motion`:
  `Err("video.motion is not an animation target")` — the op's first refusal,
  so its docs at :16-21 and :186-188 change. And because a hand-written or
  pasted end patch reaches evaluation without that op, **`evaluate_clip`**
  (`actions.rs:475-538`) overwrites `state["video"]["motion"]` with the BASE
  value's JSON before `from_value` (:511-514) — at the `Value` level, because
  `clamp_video` never sees the base props, and because a malformed `motion`
  would otherwise fail the whole video group's decode and throw away every
  other animated property. ~12 lines; `actions.rs` 573 → ~585, which is its
  last headroom (the next addition cuts `clamp_video` and helpers to
  `actions_clamp.rs` first).
- **Key checks see inside it.** `Group::template`'s video arm
  (`edit_props.rs:94-102`) sets `motion: Some(Motion { in: Some(default),
  out: Some(default), during: Some(default) })`, or `check_keys` (:129-172)
  cannot see a misspelt key inside a null motion.
- **A raw core patch DEEP-MERGES `motion`.** `merge_group` calls
  `actions::merge` (`edit_props.rs:185`), which merges objects key by key, so
  `{"motion": {"in": {…}}}` keeps a stored `out` and `during`, and a slot is
  cleared only by an explicit `null`. The op table and spec §6 say so. The
  two Swift writers therefore send ALL THREE slots, nil ones as `null`
  (§5f), and the MCP argument REPLACES whole (§5g) — the replace-whole rule
  lives at those two edges, not in the core. After the merge, the
  all-`None` normalisation runs.
- **Copy ops** — a preset is anchored to a clip's two ends, and a copy has
  new ends:

| Op | Motion | Text animation |
|---|---|---|
| `split_clip` (`edit_clip.rs:152-236`; every splitter routes here: `split_clips`, `split_under_playhead`, `clear_range` → `ripple_delete_range(s)`, `lift_range`, `insert_clip`, `overwrite_clip`, `freeze_frame`) | first half's `out` → `None`, second half's `in` → `None`, normalised | first half's `out` → 0, second's `in` → 0, `None` when both are 0 — **fixing a defect since phase 4**: both halves kept the animation, so the first un-revealed at the cut and the second re-typed |
| `freeze_frame` (`edit_time.rs:432-525`, still's video at :506) | the still's `motion` → `None` | unchanged |
| `add_blurred_background` (`edit_background.rs:490-505` literal) | `None` | n/a |
| `duplicate_clips`, `detach_audio`, `paste`, `paste_attributes` | kept (clones; `paste_attributes` copies the video group whole) | kept |
| `set_speed`, `rate_stretch` | NOT rescaled (as `text.animation` is not) | not rescaled |
| `unnest` | dropped with the nest clip's other group props | — |

  There is no `join_clips` op; `edit_tests.rs`'s test oracle `join()` (:522,
  used by `split_then_join_is_the_identity` :861 and
  `nested_splits_join_back_to_the_original` :897) learns to restore the first
  half's `out` and the second's `in` when a fixture carries motion or an
  animation.

### 5f. Swift

- **Types.** `MotionProps.swift` (new): `struct MotionProps: Codable, Equatable
  { var inEdge: MotionEdge?; var out: MotionEdge?; var during: MotionDuring? }`
  (CodingKeys `inEdge = "in"`, the `TextAnimation` precedent at
  `ProjectSnapshot.swift:1121-1155`), `MotionEdge`, `MotionDuring`,
  `EdgeMotion`, `DuringMotion` with `displayName`s, all decoded leniently.
  `ProjectSnapshot.swift`'s `VideoProps` (:872-952) gains `motion:
  MotionProps?` as a defaulted last init parameter (so `CanvasSessions.swift:167`,
  `PreviewCanvasView.swift:617` and `ProjectSnapshot.swift:2313` compile) and
  one lenient decode line.
- **The patch.** `ReelCore.swift`'s `VideoPatch` (:901-1007) gains `motion:
  MotionProps??` in `dictionary` and `isEmpty` (`TextPatch.animation`'s
  precedent at :1085-1111). **Swift's patch idiom OMITS nil fields**
  (:963-1002), and the core deep-merges (§5e), so `MotionProps`' dictionary
  writes `NSNull` for every nil slot — `MotionProps(in: X, out: nil, during:
  nil)` must send `{"in": X, "out": null, "during": null}`, or choosing None
  from the menu or the section would leave the old slot in place and beep —
  and a `MotionProps` with all three nil is sent as `motion: null`.
  `ReelOps.setVideo` (`ReelOps.swift:595`) carries it unchanged.
- **Inside an action.** `InspectorBinding.split` (`InspectorPane.swift:1415-1439`)
  sends a video write to `set_action_end` while the playhead is in an action,
  which the core will refuse. `structural(video:for:)` (:1346-1364) gains
  `motion`, so motion writes always go to BASE props — the documented single
  exception it already is for list lengths. One condition in a file over the
  cap, argued in the commit as wiring.
- **The Motion section** — `VideoPane+Motion.swift` (new, `extension VideoPane`,
  `reflectionSection`'s shape at `VideoPane.swift:761`), id `video.motion`,
  `defaultExpanded: false`, registered in `ClipPane.makeSections()`
  (`ClipPane.swift:131-137`'s effects group):
  - **In** — kind popup (None + 9) and Duration (0.1–10 s, quick 0.25 / 0.5 /
    1, snapped to the frame with `ReelTime.snapToFrame`);
  - **Out** — the same;
  - **During** — kind popup (None + 5), Amount (0–1), Period (0.1–10 s,
    disabled for `drift`);
  - **Preview** — sets the DOCUMENT's in/out range to the clip and plays
    looping (`inspector?.onCommand?(#selector(...))`, `VideoPane.swift:1195`'s
    pattern). Not `playback.loopRange` directly: `applyLoopRange` rewrites it
    from `inOutRange` on the next change (`EditorViewController.swift:415-425`).
    The range it leaves behind is the person's to clear, and the button's
    tooltip says it sets the range.
  - Every row re-sends the WHOLE `MotionProps` (the Animation section's rule,
    `TextPane.swift:322-389`); its note is not `binding.actionNote`, since
    motion ignores actions.
- **The name strip** (`TimelineClipDrawing.swift:176-213`, `drawNameStrip`;
  395 lines, not frozen): a thin in-wedge at the left and out-wedge at the
  right whose widths are the STORED durations × `body.width / clip.duration`,
  clamped to the clip. A tent draws overlapping wedges, which IS the signal
  that the presets are too long for the clip — so Swift does not re-derive the
  tent arithmetic. A small wave glyph marks a `during` preset.
- **Clip ▸ Motion ▸ In ▸ / Out ▸ / During ▸** (`AppDelegate+Menus.swift`,
  `clipMenu()` :220-327, after Label at :296; tagged items from `allCases`
  with None as −1, `labelMenu()`'s shape at :363-374): commands in
  `EditorViewController+Motion.swift` (new, `EditorViewController+Identity.swift`'s
  shape — `setClipLabelCommand` :37, `validateIdentityAction` :73-96): for each
  selected clip, read its motion, change the one slot (a chosen In or Out
  takes the default 0.5 s, or keeps an existing duration), send the whole
  object; one `applyEdit`; checkmark the first clip's kind. The validator
  needs ONE line in frozen `EditorViewController.swift`'s chain (:1089-1116),
  wiring.
- **The zoom hint** in `EditorViewController+ZoomRegion.swift` (§5d).

### 5g. MCP

- `AgentServer+Motion.swift` (new): `motionPatchArg(_ raw: Any?) throws ->
  MotionProps??` — hand-built like `shapePatchArg` (`AgentServer+Clips.swift:1026-1080`)
  and `gradientArg` (:1113-1178): refuses a misspelt key at every level by
  name, a kind outside the vocabulary by name, a wrong type by name; `null`
  clears.
- `setVideo` (`AgentServer+Clips.swift:517-526`): removes `"motion"` from the
  dictionary, runs `patchArg` on the rest, then sets `patch.motion = try
  motionPatchArg(raw)`.
- `checkActionPatch` (:988-1020) refuses `motion` by name, mirroring the core.
- `AgentCatalog+Clips.swift`: `videoPatchDescription` (:100-119) gains a
  `motionClause` naming the kinds, units and the replace-whole rule (the
  handler fills an omitted slot with `null` before the patch reaches the
  core);
  `set_action_end`'s description says motion is refused. The parity check's
  schema part reads only top-level `properties` and `required`
  (`AgentServer.swift:374-392`), so nothing else changes; the tool count
  stays 77.

### 5h. Limits recorded

Text slides from half a canvas beyond the edge rather than from its own edge.
A `during` preset restarts at every cut, so Remove Silences on a clip with
`pulse` or `drift` makes it jump at each cut (add motion after cutting). A
split inside an arrival or departure window compresses the kept half's
preset through the tent rule. A freeze frame taken mid-motion jumps to the
un-moved placement. A drag begun mid-motion starts from the base box. A zoom
drawn on a `during` clip is solved without the motion. A spinning clip in a
dissolve dips darker (§3j). A layer's SHADOW or REFLECTION can be on canvas
at a slide's first frame while the layer itself is off it (a reflection hangs
into the canvas on `slide_down`), since the box measured is the layer's own. Motion is not drawn on the canvas as a path, and
presets have no parameters beyond duration, amount and period.

---

## 6. E2 — the build

### 6a. Wave 0 — tolls, one commit each

| Toll | Move | Lines | Gate |
|---|---|---|---|
| **T0d** | The SHAPE group — `ShapeProps`, `ShapeKind`, `Stroke`, `MAX_GRADIENT_STOPS`, `Gradient`, `GradientKind`, `GradientStop` (`model_props.rs:403-600`) → new `core/src/model_shape.rs`, re-exported `pub use crate::model_shape::*` in `model_props.rs` beside the `model_regions`/`model_text` re-exports (:52, :62), `pub mod model_shape;` in `lib.rs`; intra-doc links needing a `crate::model::` prefix (`[Shadow]`, `[Filter::default]`, `[ObscureRegion::default]`, `[Outline::default]`, `[MAX_FILTERS]`); imports `Color` only. Chosen over the survey's picture set because it is `model_text.rs`'s own precedent (a props struct moved whole with its types — text and shape are the two CPU-rendered, hash-keyed sources) and leaves the most room | 600 → ~425 | `make test`, `make lint`, `cargo fmt --check`; `cargo doc` has no broken links |
| **T0e** | `split_clip`, `state_patch`, `narrow_to` (`edit_clip.rs:103-236`) → new `core/src/edit_split.rs`, so E2's split rule does not grow a 1165-line file (after T0a); `pub mod edit_split;` in `lib.rs`; `split_clip` (and whichever of the other two its callers name) `pub(crate)`; `edit_clip.rs` imports it for its in-file callers and drops imports the move leaves unused (clippy `-D warnings`) | ~1165 → ~1030 | same |
| **T0f** | The two private pixel-size readers — `Project::source_size` (`edit_props.rs:237-258`, callers :351, :402; cited at `edit_zoom.rs:123`, `edit_track.rs:581`) and `source_pixel_size` (`edit_background.rs:207-230`, caller :456, whose doc at :180-206 asks for this) — collapsed into ONE `pub(crate) fn source_size(&self, clip) -> Option<(f64, f64)>` in `model_query.rs` (454 → ~490), with the background reader's guard (a shape's size must be `> 0`, catching NaN). **Not strictly pure**: `check_video`'s crop check on a degenerate 0-width shape — reachable only through a hand-written file — now answers `None`; the commit says so and a test in `core/tests/background.rs` (where the stricter reader came from) pins it | — | same, plus that test |

### 6b. Wave 1 — the schema lane (M1)

**Owns:** `core/src/model_motion.rs` (new), `core/src/model_props.rs` (the
field), `core/src/lib.rs` (`pub mod model_motion;` between `model` and
`model_props` at :39-40; `pub mod motion;` reserved for M2 — M1 adds the
line with an empty module so M2 owns only the file), `core/src/format.rs`,
`core/include/reelcut_core.h`, `core/src/props_check.rs`,
`core/src/edit_props.rs` (template, normalisation), `core/src/actions.rs`
(the `evaluate_clip` restore), `core/src/edit_action.rs` (the refusal),
`core/tests/schema_v8.rs` (new), `core/tests/model_tests.rs` (`full_project`
video at ~145-151 and ~203-204, the enum sweep at :535), `schema_v6.rs:273`
(asserts `blend` closes the video object literally — now `motion` does), the
version literals (one-past fixtures 8 → 9; E1's twelve current-version
asserts 7 → 8, including `model_tests.rs:984-992`'s sweep, plus
`schema_v7.rs`'s), the proof scripts' version literals again (§4b's list, 7 →
8) **and the two that read the video group's LAST key**, which `"motion":
null` now is: `phase3_proof.py:1325` (`keys()[-2:] == ["obscure", "blend"]`)
and `phase6_proof.py:1693` (`blend` is the last key) — and — the seam for
every Swift lane — `app/Sources/MotionProps.swift` (new),
`ProjectSnapshot.swift`'s field and decode line, `ReelCore.swift`'s
`VideoPatch.motion` with its `NSNull` rule.

**Gate:** `make test`, `make lint`, `cargo fmt --check`, `make typecheck`,
`make app`; every proof unchanged but those literals (no clip has motion yet,
so no picture may move). `add_blurred_background`'s literal
(`edit_background.rs:490`) spreads `..video` and so CARRIES motion until M3
drops it — a behaviour gap between waves, not a compile error, and no proof
has motion to see it.

### 6c. Wave 2 — core lanes (parallel)

**M2 — the semantics.** Owns `core/src/motion.rs`, `core/src/recipe.rs` (the
two call sites and the loop index), `core/tests/motion.rs` (new): every row
of both tables at `u` = 0, 0.5, 1 against the formulas; every `during` kind
at `t` = 0 is the identity; the slide distances for an unrotated, a rotated
and a cropped layer put the box's near edge exactly on the container edge at
the first frame; text's half-canvas rule; the tent; composition (an action
moving `x` plus `in: slide_up`); the visible-centre pivot for a cropped
layer under `zoom_in` (the visible rect's centre is fixed); re-clamping at
the scale ceiling; a nested layer under a nest clip with `in: zoom_in`
(scales about the nest clip's placed centre); a nest inside a nest;
`motion: None` recipe byte-identical to the pre-lane recipe text.

**M3 — the copy ops.** Owns `core/src/edit_split.rs` (the split rule for
motion and for `text.animation`), `core/src/edit_time.rs` (`freeze_frame`'s
still), `core/src/edit_background.rs` (the literal), `core/tests/edit_tests.rs`
(the `join()` oracle and new split tests), `core/tests/motion_copy.rs` (new):
a split in the middle leaves one `in` and one `out`; `ripple_delete_ranges`
over three spans leaves ONE arrival; the text-animation split fix (the first
half fully revealed at its end, the second from its first frame);
freeze and blurred background drop motion; duplicate, detach and paste keep
it; the existing split, freeze and background oracles unchanged for clips
without motion.

M2 and M3 are disjoint. **Gate:** `make test`, `make lint`, `cargo fmt
--check`.

### 6d. Wave 3 — Swift lanes (parallel, after M1)

| Lane | Owns |
|---|---|
| **W-inspector** | `VideoPane+Motion.swift` (new), `ClipPane.swift` (one registration), `InspectorPane.swift` (the `structural` condition) |
| **W-timeline** | `TimelineClipDrawing.swift` (wedges, the during glyph) |
| **W-menu** | `AppDelegate+Menus.swift` (the Motion submenu), `EditorViewController+Motion.swift` (new; the menu commands AND the section's Preview command), one line in `EditorViewController.swift`, `EditorViewController+ZoomRegion.swift` (the hint) |
| **W-mcp** | `AgentServer+Motion.swift` (new), `AgentServer+Clips.swift` (`setVideo`, `checkActionPatch`), `AgentCatalog+Clips.swift` (`motionClause`, `set_action_end` text) |

W-inspector's Preview button calls a selector W-menu defines; the seam is
declared first, by the orchestrator, as `@objc func previewClipMotion(_
sender: Any?)` in `EditorViewController+Motion.swift` with an empty body, so
both lanes compile against it. **Gate:** `make typecheck`, then one `make
app`.

### 6e. Wave 4 — the proof

No tool is added, so no count moves; `e2_proof.py` asserts 77 and 57 as
floors.

**`tools/proof/e2_proof.py`** over MCP (helpers copied from `phase6_proof.py`
— `Session`, `card`, `frame`, `image`, `pixel`, `box` — and `phase4_proof.py`'s
module-level column measurement, `columns` at :235 and `span` at :244):

| § | Claims |
|---|---|
| 1 | a v7 file opens with `motion: null`; `set_video` with a motion writes version 8 and `motion` as the last video key; all-None normalises to null; a misspelt key, an unknown kind, a negative duration and a zero period are refused by name; `set_action_end` with motion is refused; an end patch carrying motion written straight into a file draws the base motion |
| 2 | on a full-canvas card with no shadow or reflection: the first frame of `in: slide_left` is the backdrop alone; the frame at `in` is byte-identical to the clip with no motion; at `u` = 0.5 the card's leading column is where `ease_out(0.5)` puts it (±1 px); the same for `slide_up` on a ROTATED 30° card (the bounding box) and a CROPPED card |
| 3 | `fade` at half its duration draws the eased opacity (±1); `zoom_in` at `u` = 0.5 (a = 0.75: F = 0.9, O = 0.75 — at the first frame its opacity is 0 and there is nothing to measure) draws the card at 0.9 of its size about its visible centre, cropped or not, at the eased opacity; `pop` passes 1.0 and returns (a scale measured above the static size between `u` 0.5 and 0.9) |
| 4 | `during: spin` at one period (A = 0.5) byte-identical to no motion — exact by construction through the `rem_euclid(360)` rule — and at a QUARTER period a square card's bounding box is its 45°-rotated box (so the row also fails against a build whose spin does nothing); `shake` on a 60 s clip and a 5 s clip identical displacement at the same clip time; `drift` at the clip's end 1.12 ± 0.005; `bounce` at `t = P/2` lifted by 0.04·H ± 1 px |
| 5 | a tent (`in` 2 s, `out` 2 s, clip 3 s): arrived at 1.5 s, departing after; an action moving `x` keeps moving under `in: slide_up`; a nest clip with `in: zoom_in` scales every inner layer about the nest clip's placed centre |
| 6 | `get_project` un-moved while `render_frame` moves; `split_clip` in the middle leaves one `in` and one `out`; `ripple_delete_ranges` over three spans leaves ONE arrival; a split text-animated clip: first half ends fully revealed |
| 7 | motion reaches the export path: an `apng` export of an in/out range around a `slide_left` arrival (the image-sequence writer refuses past 600 frames, so the range is required) has the card's leading column, on the frame at `u` = 0.5, where `ease_out(0.5)` puts it (±2 px, the fit scale allowed for) — an independent measurement of the export, since no precedent compares the apng writer's frames to `render_frame`'s byte for byte |

**`tools/proof/e2_chrome.py`** offscreen: the Motion section with
`expandSections = "video.motion"` (the harness's argument 11,
`harness/main.swift:19-38`) — rows present, the During period disabled for
`drift`; the name strip's wedges measured in pixels against their durations
on a harness render of a clip with `in` 1 s and `out` 0.5 s; and a menu probe
(`phase6_chrome.py`'s template) reading Clip ▸ Motion's three submenus, their
items from `allCases`, and the checkmark for a selection.

**Mutants:** the `NSNull` rule removed from `MotionProps` (choosing During ▸ None leaves the old slot — a probe row); the `rem_euclid` removed (§4's one-period row); the guards removed (a hand-written `period: 0` — a §1 row renders without NaN); `motion` applied in `evaluate_clip` (§6 row fails); slots
merged by replacement instead of composed; the text fallback used for a
shape; `period` read as a fraction of the clip; the tent rule removed; the
pivot compensation removed (the cropped zoom drifts); the split rule removed
(twenty-four arrivals); the `evaluate_clip` restore removed; the
`set_action_end` refusal removed; `structural` not widened (the section's
write inside an action is refused — caught by a probe row); `drift` using
`P`.

### 6f. Wave 4 — the review

Four readers: (1) the preset arithmetic against the tables and the placement
rule (rotation sign, y-down, crop centre, nests); (2) the model rules — every
path an end patch, a paste or a split can bring motion through; (3) the Swift
— the section's writes inside and outside actions, the menu's batch, the
wedges; (4) the proof — which claims would pass against a build without the
feature.

### 6g. What only a person at the machine can check

Whether each preset's numbers look right at ordinary clip lengths (the
tables are starting points); whether `pop`'s overshoot reads as a pop; that
the Preview button loops the clip; that a drag begun mid-motion is tolerable;
that the wedges read at S, M and L track heights.

---

## 7. The commits

In order, each gated by §1b:

1. `Road map 5: record R5-1…R5-5 in spec §11` (docs only)
2. `Road map 5, E1 toll: edit_transition.rs, a pure move` (T0a)
3. `Road map 5, E1 toll: audio_duck.rs, a pure move` (T0b)
4. `Road map 5, E1 toll: VideoPane+Transition.swift, a pure move` (T0c)
5. `Road map 5, E1: transitions learn direction, easing, a crossfade, and a way in at a hard cut`
   (waves 1–6, the count handover, the proofs, the docs)
6. `Road map 5, E2 toll: model_shape.rs, a pure move` (T0d)
7. `Road map 5, E2 toll: edit_split.rs, a pure move` (T0e)
8. `Road map 5, E2 toll: one source_size in model_query.rs` (T0f)
9. `Road map 5, E2: In, Out and During motion presets`

**The lockstep pass** in 5 and 9 (the orchestrator's, after the fixers):
`edit.rs`'s op table (E1's rows land with T2), spec §4.3 (the Transition
section's rows; a Motion section), §4.4 (the transition hatch and — fixed
while there — the double-click claim at :643-646, which renames a clip or
enters a nest and never sets a kind), §5.2 (`transition_in` at :919-922;
`video.motion` after `blend`; the version in the heading and example), §5.3
(motion as the second recipe-only term), §5.4 (motion is not animatable),
§6 (the two op rows after `set_transition` at :1278; `move_clip`'s mint at
:1253; `set_action_end`'s refusal; `freeze_frame` and
`add_blurred_background` dropping motion; `split_clip`'s rule), §7.2 (the
crossfade term at :1467-1490), §7.3 (eased progress at :1641-1643), §7.4 (the
Swift file map), §7.5 (transitions at :1812-1816), §7.10 (the new modules),
`core/CLAUDE.md` (module map, the one-past fixture note),
`app/CLAUDE.md` (file map, the `structural` exception, the Motion section),
this document's record (§12 — never a status paragraph in the root
`CLAUDE.md`, which carries rules and maps only), `tools/proof/README.md`
(the count handover, the two scripts). Line numbers above are S1's working
tree; re-read before editing.

---

## 8. Numbers a person may want to change before the build

None blocks the plan; each is a constant in one place.

| What | Planned | Where it lives |
|---|---|---|
| Minted curve for new transitions | `ease_in_out` | `Transition::minted` |
| Crossfade law | constant power | `audio.rs` term |
| Menu's default transition length at a hard cut | 0.5 s, centred | `EditorViewController+Inspector.swift` |
| Default In/Out duration | 0.5 s | `MotionEdge::default` |
| Default During amount / period | 0.5 / 1 s | `MotionDuring::default` |
| Zoom start scales | 0.6 (in), 1.4 (out) | `motion.rs` |
| Spin | 180°, from 0.3 scale | `motion.rs` |
| Pulse peak at amount 1 | +20 % | `motion.rs` |
| Shake at amount 1 | 4 % of the shorter canvas side | `motion.rs` |
| Bounce at amount 1 | 8 % of canvas height | `motion.rs` |
| Drift at amount 1 | +24 % over the clip | `motion.rs` |

---

## 9. Where this plan differs from the survey

- `set_transition` is NOT unchanged in behaviour: it keeps an existing
  transition's style and mints only from none.
- `set_transition_style` stores on any clip, like `set_transition`.
- `add_transition`'s overlap-rule clamp is a frame-step loop over
  `check_overlap_rule`, not arithmetic, and neighbour bounds are explicit.
- `source_head` answers `Some(0)`, not `None`, for a bad speed; only
  `source_length` answers `None`.
- The crossfade's `Stage` container is captured in `Voice::of`, and `Side`
  is threaded through `gain_at` → `voice_gain` → `stage_gain`; easing lives
  inside `transition_among`, leaving `recipe.rs` untouched in E1.
- The detector rule's reason: not the fade dipping a two-voice overlap (it
  cannot), but one-audio pairs and handles pulled from quiet material.
- Twelve current-version test assertions, eleven proof-script version
  literals, two proof checks of the video group's last key, and a fixture id
  collision were missing from the survey's version-bump cost.
- A nest clip's head is a handle of 0 (the one "no handle" rule), not an
  `Err` of its own; the survey refused it.
- The overlap walls cover every unlocked track and are widened by the
  overlap's own length; the survey's exact, scope-only walls let a legal cut
  destroy the transition.
- A core patch DEEP-merges `motion`; replace-whole lives in the Swift patch
  (`NSNull` per nil slot) and the MCP handler, not in the core.
- E2's toll moves the SHAPE group (`model_shape.rs`), not the picture set,
  and adds `edit_split.rs` and the size-reader collapse as tolls.
- `join_clips` does not exist; the split rule is paired with the test oracle.
- The motion restore lives in `evaluate_clip` at the `Value` level, not in
  `clamp_video`.
- A drag begun mid-motion starts from base props — the survey said handles
  read un-moved props, which is half true.
- Shake is unseeded (R5-5), resolving the survey's D6 against its own proof.
- The Motion section needs `InspectorBinding.structural` widened, and MCP's
  `checkActionPatch` needs the refusal.
- Every preset's numbers are now stated (§5b); the survey had none.
- No canvas-space wipe (withdrawn in the survey's review, restated here).

## 10. The plan's own review

The survey's design was reviewed before this plan (survey §10). This plan was
then read against the tree by one reader asking what would make a LANE fail
or build the wrong thing if it followed the text literally: **8 blockers,
7 wrong claims, 8 gaps**, all folded in above. The ones that would have cost
a lane its gate or shipped a defect:

- `op_table`'s fixture `general()` has no hard cut, and the table panics on
  `Err` — T2's gate could not have passed.
- Eleven proof-script version literals and two last-key checks fail at the
  bumps with no lane owning them.
- Exact overlap walls let `ripple_delete_ranges` leave a clip wholly under
  its neighbour.
- Swift's patch idiom omits nil slots and the core deep-merges, so choosing
  None for a motion slot would have done nothing.
- Clip ▸ Transition ▸ None at a hard cut would have ADDED a dissolve.
- A proof row measured `zoom_in` at a frame whose opacity is 0.
- Snapping the two half-extensions separately loses the odd frame.
- The slide distance used a centre the pivot rule does not hold fixed.
- A 360° spin is not the identity in float trig, nor to `partnerBox`'s guard.
- `motion.rs` would have divided by a hand-written zero period.
- The audio proof's 10 ms windows mixed the two tones' bins, and `audio_m4a`
  file bytes carry timestamps.

## 11. Deferred

Tone controls, flip and masks; thirteen filter kinds; looks; adjustment
clips; LUT import; voice effects; background removal — the survey's E3–E9,
with their designs, two measured spikes and review findings, in
`designs/reelcut-effects-survey.md`. Nothing in road map 5 depends on them,
and nothing in them is planned.

---

## 12. E1 and E2 — the record (written 2026-09-17, after the fact)

The plan above is kept as written. What landed, from the three commits'
own accounts; the sections above say what each was meant to be.

**`e8028a2` (2026-09-16) — E1 and E2's core, both in one commit** because
they share the files a schema bump touches (`format.rs`, the header,
`model_tests.rs`, the `schema_v*` tests, the proof scripts' version
literals, both side `CLAUDE.md` maps, spec §5/§6) and no E1-only tree was
kept to verify a split against. 68 files, +7656 / −918.

- E1, schema v7, `OP_NAMES` 57, catalog 77. Tolls first as pure moves gated
  alone: `edit_transition.rs` (the three transition ops out of
  `edit_clip.rs`), `audio_duck.rs` (ducking out of `audio.rs`),
  `VideoPane+Transition.swift`; then `audio_crossfade.rs` mid-phase when
  `audio.rs` measured 635 with the crossfade in it. `Transition` gains
  `curve` and `audio`; `TransitionKind` gains `wipe_left` / `wipe_up` /
  `wipe_down`; `Transition::minted` writes `ease_in_out` + `audio: true`
  where a file's absent keys still read `linear` + `false`. Two ops:
  `add_transition` builds the overlap from handles at a hard cut with nothing
  else moving; `set_transition_style` sets curve and audio. The crossfade is
  constant power per stage, honours `Side` so the outgoing clip's last
  breakpoint is 0, and samples with the action loop's own step formula.
  Remove Silences never proposes a cut inside an overlap. Clip ▸ Transition
  at a hard cut calls `add_transition` (0.5 s, centred); the section gains
  Curve and Crossfade Audio rows. Both MCP handlers refuse every string
  argument by name (`curveArg` widened to internal). `phase9_proof.py`'s
  one-past-the-version fixture moved 7 → 8.
- E2 phase 1, schema v8, no op — core and MCP only. Tolls: `model_shape.rs`
  (`model_props.rs` 600 → 401), `edit_split.rs` (`edit_clip.rs` 1171 →
  1038), one `Project::source_size` in `model_query.rs` collapsing two
  private twins. `video.motion` is `{in, out, during}` (`model_motion.rs`).
  `motion.rs` is one pure function applied ONLY where placement is produced
  — `recipe.rs`'s `layer` and `frame_of` — never in `evaluate_clip`, so
  every edit path reads un-moved props; it short-circuits when no slot is
  active. `evaluate_clip` restores the base motion behind an Object guard;
  `set_action_end` refuses the key. A split clears `out` on the first half
  and `in` on the second, every splitter inheriting it (and `text.animation`
  got the same fix); join, freeze and the blurred background decide too.
  Swift: `MotionProps.swift`, the snapshot and `VideoPatch` fields,
  `AgentServer+Motion.swift` reading motion by hand so a misspelt key at any
  level is refused by name.
- Verified on that tree: `make test` 608 passed (494 at the previous HEAD),
  `make lint` and `cargo fmt --check` clean, `make typecheck` 0 errors and
  the same 4 AVFoundation warnings, `make app` building, the parity log
  empty, 77 tools with 57 ops. Over MCP, each on a fresh instance: phase1 66,
  phase2 85, phase3 121, phase4 84, phase5 88, phase6 167, phase7 92, phase8
  79, phase3_silence_scope 8, remaining 79, phase9 216. Offscreen:
  phase6_chrome 70, recording_probe 876 on a locked console (917 unlocked).
  Two host-state numbers, neither a regression: phase8_chrome 144/150 on a
  locked console, recording_proof 186/187 with a Bluetooth default input.

**`5da056c` (2026-09-16) — `add_transition`'s `ripple` form and the sheet.**
At a hard cut between two whole files there are no handles, so the menu
beeped; `setTransitionKindCommand` now tries the batch and, when no
`add_transition` in it would land, puts up a sheet saying why, whose Shift
Clips Left sends the same cuts with the new `ripple` flag as one undo step.
The user chose what moves: the incoming clip and every clip at or after the
cut on every unlocked track slide left (spec §11 R5-3's amendment). In the
core, `add_transition_by_shift` over `edit_time.rs`'s `shift_clips` (now
`pub(crate)`): no handle read, `align` ignored, the overlap capped at half
the shorter clip and stepped down a frame at a time until every moved track
passes the overlap rule; a pushed clip gains a minted `cross_dissolve`,
markers stay, a locked incoming track is `None`. No new op. Verified:
`make test` 621 (13 new in `core/tests/ripple_transition.rs`, four mutants
each killed); `tools/proof/transition_sheet_probe.py` 32/32 in a real window
(mutants: sheet never presented 14/32, ripple false 24/32, apply guard broken
28/32; one survivor — `applyEdit` for `performGroupedEdit` — recorded in
`tools/proof/README.md`). 12 files, +968 / −28.

**`6dda2c7` (2026-09-17) — E2's chrome.** The Clip tab's Motion section
(`VideoPane+Motion.swift`), shut by default and registered after Obscure:
In and Out (kind or None, duration), During (kind or None, Amount %, Period
— disabled for Drift) and Preview, which sets the in/out range to the clip
and turns Loop on. Clip ▸ Motion ▸ In / Out / During and Preview
(`EditorViewController+Motion.swift`), placed after Transition ▸ rather than
the plan's "after Label"; a row is checked only when every target agrees.
Every write is one `set_video` PER CLIP through `MotionProps.with(...)`,
because a motion patch replaces the whole object. `InspectorBinding.structural`
puts motion on the BASE props even inside an action. The name strip draws
in/out wedges and a During glyph for a clip `InspectorTab.hasPixels`
accepts; a zoom armed over a clip with a During motion draws a second hint
pill. `phase6_chrome.py`'s TALL went 1400 → 1600 (the new shut header pushed
the gradient fixture's open stack past the pane). Verified: `make typecheck`
at baseline, `make app`, the parity log empty; phase3_chrome 33/33,
phase4_chrome 59/59, phase6_chrome 70/70, phase7_chrome 78/78,
transition_sheet_probe 32/32; an UNTRACKED probe over `app/Sources` 17/17
(menu selectors, per-clip writes, one undo restoring `project.json` byte for
byte, checkmarks, Preview). 12 files, +503 / −11.

**Owed, as of this record:**

- E1's and E2's own proof instruments — `e1_proof.py`, `e1_chrome.py`,
  `e2_proof.py`, `e2_chrome.py` / probe — with their named mutants (§4e,
  §6e), and the reader review (§4f, §6f). Everything verified above is the
  pre-existing proofs re-run, 114 new core tests, and one tracked probe for
  the sheet.
- Four review nits from `6dda2c7`: any negative menu tag reads as None; the
  glyph infers the label dot from `nameEnd`; the zoom hint's note is fixed at
  arm time; `phase6_chrome.py`'s comment still says 1600 measures
  identically to 1400.
- §4g's and §6g's checks by a person at the machine.
