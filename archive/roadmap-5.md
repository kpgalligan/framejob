# Reelcut — road map 5: transitions and motion (E1, E2)

**Status: BUILT AND PROVED — E1 and E2's core in `062091a` (2026-09-16),
`add_transition`'s `ripple` form in `00c74f7` (2026-09-16), E2's chrome in
`c00678b` (2026-09-17), and §4e's and §6e's four instruments on 2026-09-19.
What is left is §4g's and §6g's checks by a person — §12 is the record, and
both reader reviews are in it (2026-09-20), E1's and E2's, the latter
carrying the four `c00678b` nits.** Two phases, taken on
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
   `edit_clip.rs:248, 252`, `roll`'s snap-inward bounds in
   `edit_edge.rs`). Snapping two half-extensions separately would
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

Added by the E1 reader review (§12, R1·3 and R1·6): **`add_transition`'s two
step-downs are bounded by the CLIPS, and a clip's duration is the caller's.**
One `add_text_clip {duration: 9000000000000000}` — the MCP argument gate's own
bound — makes a clip that leaves the handle form's loop
`(A.duration + B.duration)/3·frame` passes long and the shift form's
`shorter/2/frame`; on a lopsided split that is ~6.7 hours of walking,
extrapolated from 0.181 s / 1.607 s / 16.134 s at d = 6e10 / 6e11 / 6e12, and
the run at 9.0e15 expired at 120 s. It is one op's tick argument bounded only
by `i64` — kpgalligan/reelcut#24's family — not transitions'. Filed as
kpgalligan/reelcut#25.

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

**`062091a` (2026-09-16) — E1 and E2's core, both in one commit** because
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

**`00c74f7` (2026-09-16) — `add_transition`'s `ripple` form and the sheet.**
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

**`c00678b` (2026-09-17) — E2's chrome.** The Clip tab's Motion section
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

**The proofs (2026-09-19).** §4e's and §6e's four instruments, written and
run against the tree as it stood — which carried road map 4's uncommitted S1
work, seven files: `app/CLAUDE.md` and, under `app/Sources/`,
`AgentCatalog+Audio.swift`, `AgentServer+Silence.swift`,
`MediaCacheFiles.swift`, `MediaImporter.swift`, `SilenceDetector.swift` and
`SilenceSheetController.swift` (captured to `tools/proof/work/e1-before.txt`
before the first edit). **Nothing under `app/` or `core/` was changed**: the
four scripts are new files and every claim below is a placement read back
through `get_project`, a byte comparison of two PNGs, a sample-for-sample
comparison of two decoded exports, or a number a mutant moves.

- `tools/proof/e1_proof.py` — **95/95**, over MCP against TWO instances: this
  build on 4825 and the build at `77934fe` on 4826. Sections 0–6 are §4e's
  table.
- `tools/proof/e1_chrome.py` — **14/14**, the harness on both trees plus a
  probe compiled from `app/Sources`.
- `tools/proof/e2_proof.py` — **61/61**, over MCP on one instance, sections
  1–7 being §6e's table (with a `0` for the two floors).
- `tools/proof/e2_chrome.py` — **24/24**, the harness and a second probe.

`tools/proof/README.md` has a section on all four saying what each measures.
The reference build is the whole tree at `77934fe` — the commit before E1's
first toll; `062091a` is E1 and E2 together — extracted with
`git archive | tar -x` into `tools/proof/work/e1-reference` and built there.
It reads only version-6 packages, so every cross-build fixture is
hand-written back to version 6, which is also exactly the file a person who
used the app last month has on disk.

**The twenty-five mutants**, each in a copy of the tree with the app rebuilt
in the copy on its own port, every patch asserting its replaced text occurs
exactly once, the original tree never mutated:

| Mutant | Score | The rows it took |
|---|---|---|
| `cos`/`sin` swapped | 88/95 | all seven §5 crossfade rows |
| the `Side` close removed | 92/95 | the outgoing clip's last 25 ms, and the summed power in both overlaps |
| `minted` writing linear | 87/95 | §3's minted kind and its seam, §5's minted flag, and five crossfade rows |
| `set_transition` minting over a stored style | 94/95 | §1's "a kind change keeps the style", alone |
| `align` ignored | 84/95 | §4's `before` and `after` (4), the speed and nest bullets built on them (4), and §5's nested pair (3) |
| the speed applied twice in `extended` | 94/95 | §4's speed row, alone |
| the action rebase removed | 92/95 | the action's `start`, its end, and the frame at it |
| the step-down removed | 93/95 | the clamped overlap and the overlap rule's bound |
| the overlap walls removed | 93/95 | §6(a)'s wall and §6(b)'s crossfade dip |
| the menu batch unfiltered | 12/14 | the batch's overlap and its "no sheet" |
| `wipe_up` given `(0, 1)` | 94/95 | §2's `wipe_up`, alone |
| the `NSNull` rule removed | 23/24 | During ▸ None, alone |
| the `rem_euclid` removed | 60/61 | the whole spin on a dissolve's incoming half, alone |
| the guards removed | 60/61 | the hand-written `period: 0`, alone |
| `motion::apply` in `evaluate_clip` | 39/61 | 22, including §6's "a split MID-ARRIVAL writes two pieces still at the origin" — the row it was built for |
| the totals replaced instead of multiplied | 60/61 | §5's two slots, alone |
| the text fallback used for a shape | 58/61 | the ROTATED card, the cropped zoom and the action's slide — NOT §2's plain card, whose half-extent IS `W/2` and so cannot tell the fallback apart |
| the period read as a clip fraction | 55/61 | §4's shake, the eighth-turn and the whole spin, the bounce, and two composition rows |
| the tent removed | 58/61 | §5's meeting frame and both of its 0.75 samples |
| the pivot compensation removed | 60/61 | §3's cropped visible centre, alone |
| the split rule removed | 57/61 | both split rows and both ripple-delete rows |
| the `evaluate_clip` restore removed | 60/61 | §1's end patch, alone |
| the `set_action_end` refusal removed | 60/61 | §1's refusal, alone |
| `structural` not widened | 23/24 | the popup inside an action, alone |
| `drift` using `P` | 60/61 | §4's drift, alone |

**Three mutants survived their first fixture, and the FIXTURE was
strengthened rather than the mutant excused.** Each is a fact about the tree
worth having written down:

1. **A whole `spin` is a rotation the compositor cannot see.** Without the
   `rem_euclid`, the layer reaches Swift at 360° and `Float(360·π/180)`'s
   `sin` is ~1.7e-7 — five hundredths of a pixel across the canvas. What it
   moves is a GUARD: `MetalRenderer.partnerBox` answers nil for a partner
   that is rotated at all, and the outgoing half of a cross dissolve then
   loses its coverage correction. So §4 measures the reduction on a
   dissolve's INCOMING clip, which is the case `motion.rs`'s module doc
   names.
2. **A NaN reaches Swift as a field's DEFAULT, not as a broken frame.** With
   both guards gone a degenerate `period` makes every placed field NaN,
   serde writes JSON `null`, and the decoder reads x 0 / scale 1 — which on a
   card already at the origin is the same picture. §1's fixture now sits at
   x 100 and scale 1.5.
3. **An end patch that differs only by a KIND leaves the same picture.** The
   action loop interpolates the whole state, and a string it can only take
   whole, so the restore's absence was invisible. §1's hand-written end patch
   now differs by a NUMBER (a two-second period against the base's one).

**Nine deviations from §4e's and §6e's text, each measured:**

(i) the tool counts are FLOORS here and exact on the reference, because since
road map 7's D3 `op_argument_proof.py` owns the exact number
(`tools/proof/README.md`); (ii) "writes version 7" is version 8, since both
phases landed in `062091a`; (iii) `spin`'s "quarter period" is an EIGHTH at
A = 0.5, where the turn is `720·A·t/P`; (iv) p = 0.25 is read on a TWO-second
overlap, because a one-second one puts it off the 30 fps grid; (v) §6(b)'s
control is a faded tail rather than an `audio: false` pair, since the walls
deliberately ignore `audio`; (vi) the version-6 export is compared within
this build's own measured wobble, which came out 0 — byte-identical;
(vii) the tent is a 4 s card with 3 s edges, since a 3 s card with 2 s edges
has its half-edges between frames; (viii) the action row's clip is `AV.mov`,
since an `.m4a` clip has no video group to render; (ix) the `apng` export is
at the CANVAS's size and not the preset's 960 × 540 — an image format is
written with the picture fitted inside the size, aspect kept and never
upscaled (`core/src/export_size.rs`), so a 640 × 360 canvas writes
640 × 360.

**Seven more, about the instruments rather than the claims:** the tools are
`split` and `set_speed {clip, rate}`, not the `split_clip` and
`set_speed {clips, speed}` §6e's prose used; `e1_chrome.py` measures the
section's body as the vertical EXTENT of what opening it changes rather than
by `shift_match`, because Transition is the LAST section in a shape clip's
stack and nothing below it moves (the difference between the two trees is
what cancels the insets, and it came out 129 − 71 = 58 = 2 × 29 pt); the
Crossfade Audio row carries NO `InspectorRowLabel` — `inspectorCheckRow`
passes nil and the title is inside the private `OptionCheckboxControl` — so
it is counted as a control rather than read by name; a row's LIVENESS is
read off `alphaValue` (1, or 0.42) because `OptionControl` has no
`isEnabled` and `isActive` is private; `e2_chrome.py` photographs the
INSPECTOR at 1600 pt and the timeline at §6e's 1440 × 862, because Motion is
the tenth section in a shape clip's stack and its header is below the fold at
862 (measured: opening it changed zero pixels); the During GLYPH is scored at
± 3 pt on its width and ± 6 pt from the clip's right edge where §6e's text
says 11 pt ± 1, because 11 pt is the BOX `TimelineClipDrawing.swift` lays out
and what a render can measure is the SYMBOL drawn in it, whose antialiasing
reaches about a point and a half past each edge — the claim kept is one mark
of that width at the strip's right end, inside the 16 pt strip; and both
proof scripts carry a `settle` helper for a call that sets a STATE rather
than making a change,
without which a mutant whose `minted` writes `linear` turns four set-up calls
into identities and the script ABORTS instead of scoring. No `private` member
was widened for any of them.

**Two limits measured and recorded, neither of them E1's:**

- **AVFoundation does not apply a mix input's first volume point for some
  twelve milliseconds.** The incoming clip of a crossfade reads about half
  of full scale over the first 25 ms whatever the ramp asks for, and the same
  burst appears at a HARD CUT with the clip MUTED — which is where it was
  pinned down and why it is not the crossfade's. §5 scores every window from
  25 ms on and PRINTS the first one. **The hard cut is a ROW** (added by the
  review pass below): the same fixture with no transition on it and the
  incoming clip muted reads 0.496 of the tone in its first 25 ms and
  −139.9 dBFS in every window after, beside the overlap's own 0.507 — so the
  exclusion of window 0 rests on a measurement and not on a paragraph. The
  row has no ramp in it, so it guards nothing about a ramp: the cut's edge
  against the overlap's own is printed beside it, not scored. §4e's own text
  anticipates the shape of it ("M3 measured
  AVFoundation's mix wobbling by one LSB within 8 ms of a ramp edge"); the
  size is larger than that sentence expects, which is why it is under Owed.
- **`toneA.m4a` and `toneB.m4a` are 2 986 400 ticks, not 3 000 000.** The
  README calls them five seconds and ffmpeg wrote them as five seconds; AAC's
  padding makes the decoded file 149 frames. So §4's "two-second handle" is
  really 59 frames, and `e1_proof.py` MEASURES each handle rather than
  assuming it — an expectation written against the nominal length would have
  been measuring the encoder.

**The review pass (2026-09-19), and what it moved.** The four instruments
were read whole against this section; the verdict was fix-required on three
rows and nothing under `app/` or `core/` was touched by any of the fixes.
(1) §5's exclusion of window 0 was PROSE — the hard cut it rests on was
asserted and printed but measured nowhere, so `e1_proof.py` §5 ends with a
hard-cut-muted session that scores it, and the script went 94 → **95**.
(2) `e2_chrome.py`'s "…and so is Amount, where there is no `during`" read
Amount's alpha only on a fixture that HAS one, so it now reads a third
fixture with no `during` at all and asserts 0.42 there beside the 1 — the
same shape as the In Duration row above it, and the score stays 24.
(3) `e2_proof.py` carried a superseded comment calling the end patch's motion
a spin whose whole turn is the identity, three lines above the `pulse` the
fixture actually writes; the stale lines are gone. **Every one of the
twenty-five mutants was re-run after those edits**, in the same tree copy on
the same port, which is where the scores in the table above come from: each
e1 score moved by exactly one on both sides (the new row is a hard cut with
no transition on it, so no patch in the eleven reaches it), the two
`e2_chrome` mutants stayed at 23/24 with the strengthened Amount row, and
every `e2_proof` score is unchanged. The three nits were taken as well: the
mix limit entered under Owed and in `designs/reelcut-remaining.md` §5, the
glyph's widened tolerance added to the instrument deviations above, and
`e1_chrome.py` and `e2_chrome.py` named in `tools/proof/README.md`'s launch
list and its offscreen paragraph. A second reading, after those fixes, found
the new hard-cut row's comment claiming a guard it does not give — a ramp
defect passes a row with no ramp in it — so the clause is gone from the
comment and from this record, and the edge comparison stays printed, not
scored. The same reading counted SEVENTEEN documents open on the build
instance by the end of `e1_proof.py`, one past the sixteen the plan
budgeted: harmless against the deadlock past forty, written down so the
number is true.

### The E1 reader review (2026-09-20)

The review §4f owes, run as four readers in sequence, each finished and
written up before the next began. **The named deviation:** §4f asks for
four parallel readers and earlier reviews put every finding to three
sceptics; this is ONE context reading four questions in turn and ONE
independent sceptic at the end, because litecode runs one agent at a time.
Every finding below was reproduced by BUILDING the input and RUNNING it —
a test through the FFI, an MCP call, or a compiled probe — before it was
kept, and the fixes are gated by rows made to fail on purpose.

The four questions, verbatim from §4f:

1. the `add_transition` arithmetic against every source kind, speed,
   reversal and track shape;
2. the envelope — `Side`, containers, breakpoints, nests, mute/solo/duck
   precedence — against the ramps it produces;
3. the Swift UI — the menu's batch and validator, the section's writes,
   undo names;
4. the proof and the tests — which claims would pass against a build
   without the feature.

**Which STATE each reading came from.** E1 landed in `062091a` (E1 + E2
core) and `00c74f7` (`ripple` and the sheet), its instruments in `74347b2`.
Since then D2/D3 rewrote the refusal sentences and published the op table,
and road map 7 §10's UNCOMMITTED phases A–B changed the handle arithmetic:
`extended` now runs `source_advanced(.., head.saturating_neg(), speed)`,
`head_handle_frames` reads `earliest_start_on_grid` and `tail_handle_frames`
reads `source_length_on_timeline(..).or_empty()`. The review is of the
WORKING TREE, and each line's bracket says where its reading came from —
**[E1]** the text is already in `git show 00c74f7:<path>`, **[D2-D3]** it
arrived by `HEAD`, **[SW]** it exists only in the working tree.

**The baseline, step 0, every command through rule H at a flat 1800 s.**
`make test` green (`wall=2.5`), `e1_proof.py` 95/95 with both instances up
and zero SKIP lines (`wall=7.3`), `e1_chrome.py` 14/14 (`wall=131.9`),
`transition_sheet_probe.py` 32/32 (`wall=75.8`), `make lint` and
`cargo fmt --check` clean, `make typecheck` 0 errors and exactly 4
AVFoundation warnings. No R0·1: the baseline was what the plan said it was.

**Toll T, paid first and alone.** Three of reader 1's fixes root in
`core/src/edit_transition.rs`, which stood at 571 of the ~600-line cap.
`add_transition_by_shift` and its doc comment moved out whole into a new
`core/src/edit_transition_shift.rs` (114 lines) — a pure move, already
`pub(crate)` with one caller, gated alone by `make test` and `make lint`
before any fix touched the file, with the map entries in `core/CLAUDE.md`,
spec §7.10 and `designs/reelcut-core-notes.md`. `edit_transition.rs` went
571 → 477, and 530 after the three fixes and the sceptic's pass.

#### Reader 1 — the arithmetic against every source kind, speed, reversal and track shape

- **R1·1** [E1] (lead L2) `core/src/edit_transition.rs:318,333` — a canvas at fps
  `[7, 1]` (valid; `time::frame_duration` answers `None` because
  600 000 / 7 is not whole, so `Project::frame` falls back to 1/30 s =
  20 000 ticks), two media clips at a hard cut at 3 600 000, `add_transition
  {clip: 11, duration: 1220000}` → clip 11's start is **2 980 000, frame
  34.7667** at 7 fps — a sub-frame time `time.rs:170` says the model never
  holds, and which `trim_start` on the same document does not produce
  (3 514 286, frame 41.0000 exactly). `add_transition` is the ONLY op in the
  crate that multiplies by `frame()` to make a POSITION; every other use of
  it is a minimum duration or a divisor. **FIXED** — each trial's two
  extensions are now read off the grid itself, inward
  (`snapped_down(A.end + a·frame) − A.end` and
  `B.start − snapped_up(B.start − b·frame)`), which at a rate that divides
  the timescale is exactly `a·frame` and `b·frame`. Rows
  `at_a_rate_the_timescale_does_not_divide_both_clips_still_land_on_the_grid`
  and `a_request_under_one_frame_of_the_real_grid_is_refused_rather_than_stored_flat`
  in the new `core/tests/add_transition_edges.rs`; the mutant that is the fix
  reverted (`tail = a * frame; head = b * frame`, one occurrence) scores
  **7 passed, 2 failed** in a tree copy. What it costs, measured by the
  sceptic on an OFF-GRID project at 30 fps (only hand-written JSON makes
  one): the two inner edges now land on the grid where they used to stay off
  it for ever, and a ONE-frame request against a start 3 ticks past a
  boundary reveals 3 ticks rather than a frame, because the first frame is
  spent on the landing.
  - The same multiplication in `add_transition_by_shift`
    (`shift_clips(.., -(frames * frame))`) is **REFUTED as this op's
    defect**: `shift_clips` moves many clips by ONE delta, and at a rate
    whose frame is not a whole tick count no single delta keeps them all on
    the grid. `close_gap` shifts by `end − start`, a difference of two
    on-grid positions, and is off the grid there for the same reason — it is
    the ripple family's posture, not E1's.
- **R1·2** [E1] `core/src/edit_transition.rs:283-300` — reader 1's own, not a
  lead. On the SHIPPED test
  fixture (`core/tests/add_transition.rs`'s `cuts()`, track 50),
  `add_transition {clip: 11, duration: 14400000}` → **`Err("clip 11 has
  negative start -3600000")`**, where `duration: 12000000` on the same pair
  clamps and applies. Clip 11 carries twenty seconds of head and starts at
  six, so the handle moved it to −3 600 000; there the trial pair sorts the
  OTHER way round, `check_overlap_rule` measures that other pair, passes on
  the FIRST trial, and `validate` complains about the crate's own state. The
  op's own doc promises the duration is "clamped rather than refused". Not
  monotone: 12 000 000 applies, 14 400 000 errors. **FIXED** by R1·3's
  ceiling, which closes it completely — a swapped pair passes the rule only
  at `a + b ≥ 3(A.duration + B.duration)/frame`, nine times the ceiling, so
  no trial the loop can reach has a negative start. **The `Err` is not the
  only form of that swapped pair, and the other one is worse**: on a SHORT
  pair it passes the rule with BOTH starts non-negative and the project is
  WRITTEN with the two clips out of order, which `validate` accepts — a
  one-frame clip at 2 000 000 before a seven-frame one, `center`, 40 frames,
  answers `78@2000000+420000 79@1620000+540000` with the ceiling reverted
  (the ids are the committed row's, track 64), clip 79 beginning before
  clip 78. That is 108 of the 981 answers the
  sceptic's differential sweep moved (below), and the ceiling's own comment
  now says it. Rows
  `a_request_longer_than_the_timeline_in_front_of_the_clip_clamps_rather_than_erroring`
  and `requests_either_side_of_the_timelines_edge_agree_and_never_swap_the_pair`,
  the second of which carries that short pair (track 64 of the `kinds()`
  fixture) because without it no row failed the revert for the out-of-order
  form; the ceiling reverted scores **6 passed, 3 failed**, the first with
  `this op was expected to apply, but: clip 11 has negative start -3600000`
  and the short-pair row with `left: (2000000, 420000) right: (2000000,
  40000)`.
  A SECOND fix, an explicit clamp of `b` at tick 0, was written, run, found
  to have no input left that reaches it once the ceiling is in — the revert
  scored 9/9 — and DELETED under the deletion test. That measurement is
  why R1·2 and R1·3 share one fix.
- **R1·3** [E1] (lead L1) `core/src/edit_transition.rs:302-330` — the
  step-down loop removes ONE frame per pass, and the pass count followed the
  caller's `duration`, not the clips. Measured ladder, each rung under rule
  H, on a TEXT clip (tail unbounded) before a MEDIA clip at `in` 0 (head
  empty), where `center`'s shortfall moves the whole request to the
  unbounded side — **one unbounded side is all it needs**: 3e4 frames in
  0.010 s, 3e5 in 0.087 s, 3e6 in 0.880 s, 3e7 in 8.608 s. Linear, 287 ns a
  pass; 9.0e15 ticks (the MCP argument gate's own bound) is 4.5e11 passes and
  **~36 hours**, `i64::MAX` is 4.6e14 passes and ~4 years. The doc's "bounded
  by step 4's own frame count" was true and was the problem. **FIXED** — the
  request is held to `(A.duration + B.duration) / 3·frame` before the split.
  That is the most the overlap rule can pass at ANY split (it wants
  `2(a+b)·frame ≤ A.duration + a·frame` AND `2(a+b)·frame ≤ B.duration +
  b·frame`; adding them gives the bound), so the clamp removes only trials
  that were going to fail and no answer moves. **The row that pins the same
  edit at and above the ceiling,
  `a_huge_duration_lands_the_same_overlap_a_request_at_the_ceiling_does`, is
  a CONTROL and is labelled one in its own comment**: `split` is
  `requested.min(ceiling)`, so every request at or above the ceiling is one
  `split` BY CONSTRUCTION, the row passes against the ceiling reverted too
  (measured, among that build's 6 passes), and it can never fail for the
  reason it is cited for. **The evidence that no answer MOVES is the
  sceptic's 18 144-combination differential sweep below, not this row.**
  Because fixed and unfixed AGREE on the answer, the regression row is the
  clock: `a_huge_duration_is_answered_in_the_time_a_small_one_takes`, SIZED
  from the ladder at 6e7 frames, with the three numbers it was chosen from —
  **fixed under 0.001 s, bound B = 1.0 s, unfixed 17.844 s** — and it fails
  by assertion, `add_transition took 17.844 s for a 1200000000000-tick
  request (bound 1 s)`.
  - Extremes, against the FIXED build only, each under rule H: `duration` 1
    tick → the refusal (`the 0 frames asked for`), one frame → applied,
    the ceiling and one frame either side → the same edit, **9.0e15 →
    applied in under a millisecond with the same answer**, `i64::MAX` → the
    same, `-1` and `i64::MIN` → `Err("duration must be positive, not …")`,
    and `ripple` at `i64::MAX` → applied. 9.0e15 and `i64::MAX` are
    deliberately NOT in the committed rows: against a build with the ceiling
    reverted they ARE the loop, and a row that hangs `make test` on a revert
    is worth less than the claim.
  - **The residual, recorded as a limit (§3j).** The ceiling is the CLIPS,
    and a clip's duration is the caller's: one ordinary
    `add_text_clip {duration: 9000000000000000}` makes a clip 9.0e15 ticks
    long. On a lopsided split (`align: "after"`, two such clips) the
    step-down still walks `(A + B)/3f − min/2f` passes — measured 0.181 s at
    d = 6e10, 1.607 s at 6e11, 16.134 s at 6e12, linear, so ~6.7 hours at
    9.0e15. The extreme run **expired at 120 s (pid 61383 killed)**, which
    is that row's measured answer. **FILED #25**
    (kpgalligan/reelcut#25), a defect of #24's family — a single op's tick
    argument bounded only by `i64` — not re-fixed here.
- **R1·4** [E1/SW] (lead L3) — §3i asked for "a reversed clip's handle in
  the reversed stream" and `grep -i revers core/tests/add_transition.rs
  tools/proof/e1_proof.py` finds nothing; an image, a shape and any speed at
  which the HANDLE is what clamps had no row either (`cuts()` has one
  `still` and one `text`, and its ×2 track has a 6 000 000-tick head against
  a ten-frame request). The ARITHMETIC is **REFUTED as a defect** — run, all
  four are right: a reversed pair moves `in` 3 000 000 → 2 900 000 for five
  frames at speed 1, which is correct because `in` is measured in the
  direction the clip plays (`edit.rs`, `set_reversed`), so the handle
  arithmetic is direction-agnostic by design; an image pair and a shape pair
  are unbounded and split five and five; and at ×2 with a five-frame head
  and an empty tail, five frames land, all on the incoming side, with `in`
  200 000 → 0 (times the speed, not divided by it). The GAP was real and is
  **FIXED** by four rows in `add_transition_edges.rs`. Two of the four are
  failed by X1, "handles never clamp": the ×2 row, and the reversed row
  after this pass sharpened it — clip 71 now sits at `in` 60 000, THREE
  frames of head, so the handle is what binds and `center`'s shortfall
  moves the other seven frames to the tail (X1 answers `(0, 1300000)` where
  the fix answers `(0, 1340000)`). The image/shape row has no such mutant
  and is named as a coverage row below.
- **R1·5** [E1] (lead L4) — the handle form WRITES on a locked track where
  the `ripple` form refuses. **REFUTED**: `core/src/edit_edge.rs` contains no
  `locked` at all, and `trim_start` on a locked track applies here too
  (clip 79 → start 1 400 000). An edge op that moves nothing but its own
  clip's edges ignores the lock; the ripple form refuses because it MOVES
  the timeline, which is `close_gap`'s and `ripple_delete`'s posture. The
  repo's posture, not a defect.
- **R1·6** [E1] (lead L5) `core/src/edit_transition_shift.rs` — the shift
  form clones the whole project once per frame from `allowed` down.
  **REFUTED as a defect**: `frames = asked.min(allowed)` already holds it to
  `shorter/2/frame`, the CLIPS and never the request. Measured on a pair
  whose shift breaks another track's overlap rule at every length, so the
  walk runs to the bottom: 15 000 passes in 0.022 s, 150 000 in 0.090 s,
  1 500 000 in 0.898 s. Same residual as R1·3's and recorded with it.
- Noticed in passing, no verdict: a `duration` under one frame refuses with
  "the **0** frames asked for", the request divided by the grid, which reads
  oddly for a caller who asked for 1 tick.

#### Reader 2 — the envelope against the ramps it produces

Read whole: `audio_crossfade.rs`, `audio.rs`'s `Voice`/`Stage`/`silenced`
walk, `breakpoints`, `gain_at`, `voice_gain`, `stage_gain`,
`audio_duck.rs`'s `duck_gain`, and `transition.rs`'s read half
(`overlap_of`, `progress_in`, `transition_of_later`, `overlap_before_of`,
`overlap_after_of`, `transition_among`, `crossfade_among`). No defect was
found; two promised shapes were measured for the first time.

- **R2·1** [E1] `core/src/audio_crossfade.rs` (lead L6, first half) — §3e's
  closing bullet promises "mute, solo, ducking and volume keep their
  precedence: the term multiplies, as ducking does", and `crossfade.rs` has
  a row for mute, one for solo and one for volume and none for a DUCKER —
  the only one of the four computed OUTSIDE the voice (`gain_at` applies a
  ducker after `voice_gain`, where the crossfade is inside `stage_gain`).
  **REFUTED as a defect by the reader's own run**: a step duck at level 0.25
  over `crossfade.rs`'s pair gives exactly `0.25 × cos(pπ/2)` and
  `0.25 × sin(pπ/2)` at every breakpoint — 0.176777 at p = 0.5, which is
  0.25/√2. The GAP was real and is **FIXED** by
  `a_ducker_on_another_track_multiplies_the_crossfade_rather_than_replacing_it`
  and `the_ducked_pair_still_sums_to_the_ducked_level` in the new
  `core/tests/crossfade_edges.rs`. Mutant X2 (no crossfade) scores **0
  passed, 6 failed** on that file.
- **R2·2** [E1] (lead L6, second half) — no row anywhere for a MIDDLE clip
  with an overlap at both ends whose two overlaps ABUT (each exactly half
  of it, the most the rule allows), where `Side::Left` reads one overlap's
  closed end and `Side::Right` reads the other's `p = 0` at the same tick.
  **REFUTED as a defect**: run, the middle clip reads exactly 1.0 from both
  sides at the seam, rises as `sin` over the first overlap and falls as
  `cos` over the second, and its two neighbours tile the SAME composition
  track (the A/B assignment puts 11 and 13 on one and 12 on the other)
  without a gap. The GAP was real and is **FIXED** by three rows
  (`a_middle_clips_two_overlaps_meet_at_full_gain`,
  `a_middle_clip_fades_in_over_one_overlap_and_out_over_the_other`,
  `the_middle_clips_neighbours_still_follow_the_law_around_it`).
- **R2·3** [E1] — a FADE OUT as long as the overlap and the crossfade cover
  the same second; `audio.rs` says both apply and nothing measured the
  product. Added as `a_fade_out_as_long_as_the_overlap_multiplies_the_crossfade`,
  which asserts `(1 − p)·cos(pπ/2)` and that the pair then does NOT hold
  its power — the thing a person is choosing when they leave a fade on a
  clip they put in a transition. **FIXED** (a gap), caught by X2.
- **A fix's own sentence, corrected by measuring it.** The seam row was
  first written claiming that only `crossfade_among`'s `Side::Left` closure
  could answer there. A mutant that disables the closure
  (`if side == Side::Left && …` → `if false && …`) leaves that row
  **passing** — a `None` reads as gain 1 and 1 is the right answer at that
  tick — while failing 8 of `crossfade.rs`'s 20. The comment and the file's
  module doc now say which row guards the closure
  (`the_outgoing_clips_last_breakpoint_is_zero`) and that this one does not.
- Refuted while reading, each by the code itself rather than by a run, and
  none re-reported: `Transition::default()` is `audio: false` and
  `Curve::Linear`, so a version-6 bare overlap stays silent and linear
  (R5-2); the two overlaps of a middle clip can abut but never cross, since
  the rule bounds each at half the clip and the `i`/`i+2` pass blocks the
  neighbours reaching each other; `crossfade_breaks` asking
  `crossfade_among(.., overlap.start, Side::Right)` for BOTH overlaps is
  right, because `progress_in` is half-open and the before-overlap has
  already ended at the after-overlap's start. K1, K4, K5, K7 and K10 were
  cited, not re-read.

#### Reader 3 — the Swift UI: the menu's batch and validator, the section's writes, undo names

Read whole: `EditorViewController+Inspector.swift`'s transition half
(`setTransitionKindCommand`, `presentNoFootageForTransition`,
`transitionPlacement`, `validateInspectorAction`), `VideoPane+Transition.swift`,
`ReelEdit.swift`'s `applying([ReelOp])`, `ProjectDocument`'s `applyEdit` /
`performGroupedEdit`, `AppDelegate+Menus.swift`'s Clip ▸ Transition ▸, and —
because findings route by ROOT file and no question names them —
`AgentServer+Transitions.swift`, `AgentCatalog+Transitions.swift` and §3f's
`overlapWalls`.

- **R3·1** [E1] `app/Sources/EditorViewController+Inspector.swift:268-276`
  (lead L7) — **the sheet's Shift Clips Left loses everything when two
  chosen cuts collide.** Input, reproduced in the core first and then in a
  real window: track 1 holds two whole six-second files butted at 3 600 000;
  track 2 holds one at 1 800 000 (so it SPANS that cut) and another at
  5 400 000. Both cuts have no handle, so both reach the sheet with its
  plural title, and the button maps them — in start order, which is
  `selectedClips`' order — to one `ripple` op each, built from the snapshot
  the sheet was made from. Op 1 slides every clip at or after 3 600 000 left
  by half a second, which moves the second cut's INCOMING clip but not its
  predecessor, which began earlier: that cut is now an overlap, with a
  minted `cross_dissolve` on it (`close_gap`'s rule, by design). Op 2 is then
  `Err("clip 7 is not at a hard cut: it already overlaps clip 6 — use
  set_transition or set_transition_duration")`, `ReelProject.applying`
  THROWS on an `Err`, and the throw discards `current` — so **op 1's shift is
  lost, nothing lands, no undo step is made, and the person is shown an error
  sheet naming a clip they never pointed at.** Op 1 had already given them
  the second overlap. **FIXED**: the button's ops are now re-decided one at a
  time against the project the earlier ones leave behind
  (`shiftingOps`), a cut that has become an overlap taking the
  `set_transition` Clip ▸ Transition ▸ sends for an overlap anyway, and an op
  the running project declines being dropped rather than carried. Row:
  `transition_sheet_probe.py` §8, **32/32 → 39/39**; the fix reverted scores
  **33/39** with that error sheet's text printed and nothing landed.
- **R3·2** [E1] `app/Sources/VideoPane+Transition.swift` (lead L8) — with an
  overlap and NOTHING stored the section shows Linear / off, and the Kind
  popup sends `set_transition` alone, which MINTS `ease_in_out` / `true`, so
  two rows the person did not touch change. **REFUTED**, by spec §11 R5-2:
  a clip that had no transition and gains one gets a MINTED one, and that is
  the decision, not an accident. The section's own doc sentence was then
  checked against every branch that could make it false and still reads
  true: it is scoped to `set_transition_style`, whose one-key form is
  exactly what the both-keys rule exists to stop, and it does not claim
  anything about the Kind popup.
- **R3·3** [E1] (lead L9) — undo names: the menu's batch says "Set
  Transition" even when every op in it is `add_transition`; the MCP tool
  says "Set Transition" with or without `ripple`; the sheet's button says
  "Add Transition" for the op the tool mirrors. **REFUTED**: each name
  describes the PATH it sits on rather than the op — the menu's batch can be
  all `set_transition`, the tool's primary mirror is that menu and its doc
  comment says so, and the sheet is its own gesture. Each is asserted by its
  own instrument (`e1_chrome.py`, `e1_proof.py`, the sheet probe), so
  changing one would move a row in another. Written down here because the
  same op does answer to two names depending on the door it came through.
- Refuted while reading: the validator is right to keep None enabled for any
  selection and a KIND enabled only where `transitionPlacement != .neither`,
  because the command SKIPS every other clip; `presentNoFootageForTransition`
  is right to go through `performGroupedEdit`, since a sheet completion is
  not an AppKit event (app/CLAUDE.md's undo pitfall); `overlapWalls` reads
  adjacent pairs of `clips(onTrack:)` on every unlocked track and widens
  each overlap by its own length, which is §3f's own argument. K11, K13 and
  §3j's notes were cited, not re-read.

#### Reader 4 — which claims would pass against a build without the feature

**No old binary was scored as "the build without the feature."** Run as the
BUILD port, the `77934fe` binary has 75 tools, `e1_proof.py`'s first
`set_transition_style` call raises `ToolError`, `main()` has no handler for
it, and the script aborts inside §1 with §2–§6 never run: it measures
nothing. (The reference instance keeps its designed role on the SECOND
port.) The builds are five NAMED MUTANTS of today's tree in a tree copy,
each patch asserting its replaced text occurs exactly once — all five checked
today, 1 each:

- **X1, handles never clamp** — `edit_transition.rs`: `|h| want.min(h)` →
  `|_| want`.
- **X2, no crossfade** — `audio_crossfade.rs`: the constant-power angle
  replaced by full gain both ways, breakpoints still emitted.
- **X3, no easing in picture or sound** — `transition.rs`'s
  `transition_of_later` forcing the default curve, so `get_project` still
  SAYS `ease_in_out`.
- **X4, walls exact, not widened** — `SilenceDetector+Walls.swift`: both
  `± width` terms dropped.
- **X5, the section's both-keys rule gone** — `VideoPane+Transition.swift`:
  `if stored() == nil {` → `if false {`.

None repeats §12's eleven E1 mutants (cited, not re-run) — **except that
"the speed applied twice in `extended`" no longer has a patch site**: that
multiplication is now `source_window.rs`'s `timeline_to_source`, shared by
six ops, so a patch there would be mutating every placement op in the crate
rather than this one.

One row per CLAIM GROUP, one column per mutant. `fails` = the group catches
it; `passes` = it does not; `control` = the group's own text claims something
did NOT move, so passing is what it is for. Core-only mutants were scored by
`cargo test` in the copy first, then the copy's app was built for MCP; every
run went through rule H and none expired, so there is no `expired` or
`unreached` cell in this table.

| Claim group | X1 | X2 | X3 | X4 | X5 |
|---|---|---|---|---|---|
| `e1_proof.py` §0 the two instances | passes | passes | passes | passes | passes |
| `e1_proof.py` §1 the schema | control | control | control | passes | passes |
| `e1_proof.py` §2 the three wipes | passes | passes | **fails** | passes | passes |
| `e1_proof.py` §3 the push, and version 6 unchanged | control | control | **fails** | control | control |
| `e1_proof.py` §4 `add_transition`'s handles | **fails** | passes | passes | passes | passes |
| `e1_proof.py` §5 the crossfade | passes | **fails** | **fails** | passes | passes |
| `e1_proof.py` §6 Remove Silences | passes | passes | passes | **fails** | passes |
| `e1_chrome.py` §1 the section as pixels | passes | passes | passes | passes | passes |
| `e1_chrome.py` §2 the menu, validator, rows, batch | passes | passes | passes | passes | passes |
| `e1_chrome.py` §3 the section's WRITES | passes | passes | passes | passes | **fails** |
| `transition_sheet_probe.py` | **fails** | passes | passes | passes | passes |
| `core/tests/add_transition.rs` | **fails** | passes | passes | passes | passes |
| `core/tests/add_transition_edges.rs` | **fails** | passes | passes | passes | passes |
| `core/tests/crossfade.rs` | passes | **fails** | **fails** | passes | passes |
| `core/tests/crossfade_edges.rs` | passes | **fails** | passes | passes | passes |
| `core/tests/ripple_transition.rs` | **fails** | passes | passes | passes | passes |
| `core/tests/schema_v7.rs` | control | control | control | control | control |

Totals, as run: X1 `e1_proof` **92/99**, `e1_chrome` 21/21, sheet **18/39**,
`add_transition.rs` **29/34**, `add_transition_edges.rs` **7/9**
(re-scored after this review's fix pass sharpened the reversed row; it was
8/9 when the table was first written),
`ripple_transition.rs` **12/13**. X2 `e1_proof` **92/99**, `crossfade.rs`
**8/20**, `crossfade_edges.rs` **0/6**. X3 `e1_proof` **92/99**,
`crossfade.rs` **16/20**. X4 `e1_proof` **97/99** (both in the new §6(c)),
everything else clean. X5 `e1_chrome` **19/21** (both in the new §3),
everything else clean.

Two cells were findings, and both are now `fails`:

- **R4·1** [E1] `tools/proof/e1_proof.py` §6 — **X4 scored 95/95: the walls
  were EXACT and every row passed.** §3f's whole argument for WIDENING is
  that an exact wall lets a legal cut destroy the transition, and no row
  measured it. The reason the three shipped rows cannot see it is
  arithmetical and worth recording: their quiet run is 2.0–3.0 s against an
  overlap at [2.25, 2.75], so an exact wall leaves two 0.25 s pieces, both
  BELOW the `min_length` of 0.5 s — the length filter hides the defect.
  **FIXED** by a new §6(c) whose run ends AT the cut and is long enough to
  survive the filter: it asserts no proposal reaches into the widened wall,
  then APPLIES the proposal with `ripple_delete_ranges`, finds the pair
  again by GEOMETRY (a split does not keep the ids) and measures the overlap
  left against half the shorter clip. **95/95 → 99/99**; X4 now scores
  **97/99**, the decisive row reading `1660000 ticks against half of the
  shorter clip (150000)` — a project outside the overlap rule, which is
  exactly §3f's sentence.
- **R4·2** [E1] `tools/proof/e1_chrome.py` (lead L10) — **X5 scored 14/14,
  95/95 and 32/32: nothing in any instrument reached `styleOps`, the Curve
  or Crossfade Audio WRITES, or the undo names "Transition Curve" and
  "Transition Audio".** `e1_chrome.py` measured the section's EXTENT and
  COUNTED its controls; neither notices what a control writes. **FIXED** by
  a new §3 that DRIVES them — the popup sent `itemPicked:`, which is what
  its own popped-up menu sends, and the checkbox a synthesized `mouseDown` —
  on the same clip with its transition stored and with it cleared.
  **14/14 → 21/21**; X5 now scores **19/21**, failing exactly the two
  cleared-clip rows, which read
  `None → {'audio': True, 'curve': 'ease_in_out', …}` where the section was
  showing Linear.
- Everything else in the table is `passes` on a group whose text says
  nothing about the mutated behaviour (a core test file says nothing about
  Swift; `e1_chrome.py` §1 and §2 say nothing about a handle or a ramp), or
  `control` on a group whose text claims something did NOT move — the
  version-6 byte comparisons in §3, §1's version-6 open, and
  `schema_v7.rs`, which is about the FILE and is meant to survive every one
  of the five.

#### The sceptic — every kept finding put back, every fix attacked

The deviation §4f allows for: ONE independent sceptic pass over the four
readers' work rather than three sceptics per finding, run in the same
context. Nothing below was judged by reading alone; each attack was built
and run.

- **The ceiling's derivation, fuzzed.** The claim that
  `(A.duration + B.duration) / 3·frame` can lose no answer rests on an
  inequality, so it was attacked with a fixture sweep instead: **41 472**
  combinations of A's start, both durations, six source-kind pairs
  (media/media, text/media, media/text, text/text, shape/nest, nest/text),
  three `in` points, three speeds, all three `align`s and four durations up
  to 9.0e15 — every one asserted to answer a hard-cut `Err`, a refusal, an
  identity or an APPLIED project whose every clip starts at or after tick 0.
  **Zero unexpected `Err`s, zero negative starts, 1.53 s for the sweep**, so
  no combination reached the loop either.
- **The ceiling, attacked DIFFERENTIALLY — the evidence that no answer
  moves.** One tree copy with `let split = requested.min(ceiling)` made
  switchable by `RC_NO_CEILING`, one build, two runs, the answers diffed
  over **18 144 combinations**: A's start × A.duration (1/5/60/301 frames)
  × B.duration (1/7/60/500 frames) × {text, media, image}² × with and
  without neighbours on the track × all three `align`s × requests of
  1/3/40/121/200/1 000/20 000 frames. **17 163 answers identical, the rest
  differing, and in every differing one the UNCLAMPED build is the wrong
  one** — 540 `APPLIED → ERR("negative start")`, 333 `REFUSED → ERR`, 54
  `REFUSED → APPLIED(swapped pair)` and 54 `APPLIED → APPLIED(swapped
  pair)`. Those four sum to **981**, which is exactly 18 144 − 17 163. The
  sceptic's own summary said "108 differ"; the second pass re-derived both
  numbers from the sweep's surviving outputs (18 144 lines each, no
  misaligned pair) and settled it: **981 differ, and 108 is the subtotal
  54 + 54**, the answers where the unclamped build APPLIED a swapped pair.
  **No input whose correct answer is larger than the clamp allows.**
  `sweep-fixed` wall = 1.1 s, `sweep-unfixed` wall = 5.8 s, both under rule
  H. It lived
  in a scratch tree copy and **is not a committed instrument**: this
  paragraph is the whole of it that survives, which is why the row R1·3
  used to cite is called a control instead.
- **The grid read, attacked with an OFF-GRID project at 30 fps.** Two clips
  at 1 200 003 and 3 600 003 — which only hand-written JSON can make, and
  `validate` accepts. The fix does what it says: A's new end and B's new
  start both land ON the grid (3 700 000 and 3 520 000 for a ten-frame
  request) where the old arithmetic kept them 3 ticks off it forever. **The
  cost, measured and recorded here rather than argued away**: a ONE-frame
  request against a start 3 ticks past a boundary reveals 3 ticks, not a
  frame, because the request's first frame is spent landing the edge. That
  is `snap_up_to_frame`'s own argument for a bound and the code comment now
  says so; it cannot bite a project any op in the crate could produce.
- **The `shiftingOps` fix, attacked on the paths its re-decision changes.**
  A cut that has become an overlap now takes `set_transition`, so: choosing
  the kind the shift already MINTED is an identity, the op is dropped, and
  the cut still ends up carrying that kind (`cross_dissolve` is what
  `set_gained_transitions` mints, which is what the person chose in that
  case); a locked track's op is refused in the trial, dropped, and an empty
  list is `applying([])` = identity = the beep the probe's §7 asserts
  (39/39, unchanged); and the trial reads `document.editedProject` where the
  replay reads `document.project` through `addressed`, which is the pattern
  `setTransitionKindCommand`'s own trial has used since E1.
- **The new rows put to their own mutants — and the control and the one
  COVERAGE row no named mutant fails, said here by name.** Every score in a tree copy, every run
  under rule H, each patch asserting its text occurs exactly once. Against
  `add_transition_edges.rs`: the grid read reverted **7 passed, 2 failed**;
  the ceiling reverted **6 passed, 3 failed** (17.6 s on the sized row,
  limit 120 s); X1, handles never clamp, **7 passed, 2 failed**. Against
  `crossfade_edges.rs`: X2 **0 passed, 6 failed**. Then the `shiftingOps`
  fix reverted (**33/39**), X4 against `e1_proof.py` (**97/99**) and X5
  against `e1_chrome.py` (**19/21**). Of
  `add_transition_edges.rs`'s nine rows that leaves two that no named
  mutant fails, and neither is a gap in the claim:
  `a_huge_duration_lands_the_same_overlap_a_request_at_the_ceiling_does` is
  a **CONTROL** (R1·3), and
  `an_image_pair_and_a_shape_pair_are_bounded_by_nothing_but_the_overlap_rule`
  is a **COVERAGE row** — what it pins is that an ABSENT handle imposes no
  bound, so X1 (which removes a clamp that is already absent) and the grid
  read (identity at a rate that divides the timescale) can only pass it.
  **The first writing of this bullet said every one of the seventeen new
  rows had a mutant that failed it; that was false for four of them, and
  this is the corrected sentence** — two were sharpened until a mutant did
  fail them (the either-side row now carries the short pair, the reversed
  row a three-frame head), one is the control and one is the coverage row.
- **A claim of the sceptic's own that DID break a row.** The seam row in
  `crossfade_edges.rs` was written claiming only `crossfade_among`'s
  `Side::Left` closure could answer at the abutting tick. The mutant that
  disables the closure leaves that row passing (a `None` reads as gain 1,
  and 1 is right there) while failing 8 of `crossfade.rs`'s 20. The row's
  comment and the file's module doc were rewritten to say which row guards
  the closure and that this one does not.
- **A fix of the reader's own that the sceptic deleted.** R1·2 was first
  fixed twice — by the ceiling and by an explicit clamp of `b` at tick 0.
  The clamp reverted scored 9/9, so no input reaches it; it is gone, and the
  arithmetic that makes it unreachable is in the ceiling's comment.
- **What the sceptic did NOT reach, and is therefore UNJUDGED**: §4g's four
  checks by a person (K17, `designs/reelcut-remaining.md` §4); whether
  kpgalligan/reelcut#25's residual can be closed by a closed form rather
  than a bound at the door, which needs a decision the loop's own doc argues
  against (it calls the predicate "not monotone in an obvious direction");
  and E2's files inside `062091a`, which are §6f's.

**Final scores.** `make test` green with two new files;
`core/tests/add_transition_edges.rs` **9/9** and
`core/tests/crossfade_edges.rs` **6/6**; `e1_proof.py` **95/95 → 99/99**;
`e1_chrome.py` **14/14 → 21/21**; `transition_sheet_probe.py`
**32/32 → 39/39**; `make lint`, `cargo fmt --check` clean and
`make typecheck` at 0 errors and exactly 4 AVFoundation warnings.

**The count, against this section's own numbered lines.** **FOURTEEN**
findings are recorded above — R1·1 to R1·6, R2·1 to R2·3, R3·1 to R3·3,
R4·1 and R4·2. **TEN are FIXED or gap-filled**: R1·1, R1·2 and R1·3 (two
lines, one fix), R1·4's missing rows, R2·1, R2·2 and R2·3 as gaps in the
instruments, R3·1, R4·1 and R4·2. **FOUR are REFUTED** by the reader's own
run: R1·5, R1·6, R3·2 and R3·3 — and R1·4 is refuted as an ARITHMETIC
defect inside the line that is counted once, above, for the gap it fixed.
Neither of the two remaining items is a numbered line: R1·3's residual is
FILED as kpgalligan/reelcut#25 and the same residual is the limit recorded
in §3j. (An earlier draft of this paragraph said "nine findings kept: five
FIXED …, four REFUTED …" and listed seven and five; it was recounted here
after the sceptic's review.) No command rule H covers was run outside it; one
expiry is in the record (the residual at 9.0e15, `expired at 120 s (pid
61383 killed)`) and nothing else expired.

### The E2 reader review (2026-09-20)

Road map 5 §6f's four questions, verbatim, against the tree as it STANDS —
not against `062091a` and `c00678b` as they landed. Every finding below was
reproduced by RUNNING it, every fix has a test or a proof row made to fail on
purpose, and the four `c00678b` nits each have a verdict.

**The deviation, named.** §6f asks for four readers and earlier reviews put
every finding to three sceptics. This ran as SEQUENTIAL single-context
readers — one question finished and written up before the next started — and
the reader was its own sceptic: it tried to refute each of its own findings
by building the input and running it. Where it could not reach something it
says so rather than calling it refuted. One verdict word is not in §6f's
list: **UNFIXED — recorded as a limit of the instrument**, used twice for a
gap in `e2_proof.py` that this run measured but did not close.

**Which STATE each reading came from.** `[E2]` the text is already in
`git show c00678b:<path>`; `[D1-D3]` it arrived by `HEAD` (road map 7's
deepening series); `[SW]` it exists only in the working tree.

**The baseline, before anything was read** (every command through rule H at a
flat 1800 s, on the untouched tree): `make test` green
(`DONE test rc=0 wall=12.4`), `e2_proof.py` **61/61** with zero SKIP lines
(`wall=6.2`), `e2_chrome.py` **24/24** (`wall=138.8`), `phase6_chrome.py`
**70/70** (`wall=274.1`); `make lint` and `cargo fmt --check` clean,
`make typecheck` 0 errors and exactly 4 AVFoundation warnings. There is no
R0·1. Every later limit is 5 × those numbers, floored at 120 s.

#### Reader 1 — "the preset arithmetic against the tables and the placement rule (rotation sign, y-down, crop centre, nests)"

Every row of §5b's three tables was read against `core/src/motion.rs` — nine
arrivals, nine departures, five continuous — and all twenty-three agree,
including which edge each slide names and that `pop` is the one arrival on
the RAW progress. The placement rule holds too: `nest::rotate` and
`Compositor.metal`'s `rotate2` are the same sign, `bounce`'s `−0.08A·H` is UP
on a y-down screen, the crop centre is `((l−r)/2, (t−b)/2)` and the
half-extents are the §5b expressions. The one thing that does not hold is the
REDUCTION.

- **R1·1** [E2] `core/src/motion.rs:380` — an arrival `spin` with
  `in.duration` 100,000,001 ticks, read at clip time 100,000,000 (frame 5000
  at 30 fps, an ordinary frame of a three-minute recording) → the recipe
  publishes `rotation: 360.0` (should be `0.0`). `f64::rem_euclid` is
  `let r = self % rhs; if r < 0.0 { r + rhs.abs() } else { r }`, and the
  smallest non-zero `1 − ease_out(u)` a double holds is `2⁻⁵³`, so
  `φ = −180 × 1.110e-16 = −1.998e-14` and `r + 360.0` ROUNDS UP to exactly
  360 (the spacing of doubles at 360 is 5.68e-14). 360 is the one value §5c
  says the reduction exists to prevent, because `partnerBox`'s
  `rotation == 0` guard cannot see it. Designer's lead L1, confirmed through
  the FFI: the un-fixed recipe printed
  `"rotation":360.0,"scale":0.4999999999999999`. **FIXED** — the reduction's
  own 360 maps back to 0;
  `core/tests/motion_edges.rs`'s
  `an_arrival_spin_one_tick_from_its_end_reduces_to_zero_and_not_to_a_whole_turn`
  and `no_arrival_spin_anywhere_near_the_window_publishes_a_whole_turn`, which
  the fix REVERTED fails 2 of 5 (mutant `R1rev`, in the tree copy).
  **The first fix was not enough, and the fix pass widened it** (the sceptic's
  finding 1): mapping the exact double 360 back to 0 leaves the NEIGHBOURS,
  and `t = in − 2` publishes `359.99999999999994`, which fails the guard's
  exact f64 `rotation == 0` just as 360 does. The reduction now publishes a
  BAND under a whole turn as 0 — every total that rounds to 360 as an f32 of
  DEGREES, a CHOSEN width of 2⁻¹⁶ of a degree (1.5259e-5°, at most 5.87e-4
  px at the corner of a 4K frame, 2202.9 px from its centre), which moves
  1.998e-14° at this arrival and 1.0e-5° at the `during` the seventh test
  pins (the reason first written here, "the precision the number is READ
  in", was false; the closing block below says what is true) — and the
  property test asserts `rotation as f32 < 360.0` plus an exact 0 on the
  last two ticks, over arrivals, departures, a `during` 1.0e-5° short of a
  turn and the reversed arm (a negative arrival φ added to two whole turns),
  the last two in the new
  `no_departure_no_during_and_no_reversed_sum_publishes_a_whole_turn`.
  The FIRST fix reverted fails 2 of 7 by assertion (mutant `R1rev2`, in a
  tree copy, 0.3 s under rule H at a 120 s limit). No recorded frame moved:
  `make test` green and `e2_proof.py` **61/61** on a fresh instance after
  `make app`, because every spin either instrument samples is a whole period
  (φ exactly 360, reduced to 0 before and after) or an eighth of a turn.
- **R1·2** [E2] `core/src/motion.rs:403-416` — a media descriptor with a zero
  dimension makes `source_size` answer `None`, and the TEXT fallback
  (`hx = W/2`) silently applies to a media clip: the reader built one and the
  layer came out at `x = 1920.0` where a measured 1280 × 800 source would put
  it at 1600. **REFUTED** by the reader's own run: the same layer carries
  `"source_size":[0,0]`, so nothing is drawn at either offset. A source the
  core cannot measure has no right answer, and the module doc already says
  `None` is the fallback. (Designer's lead L3, first half.)
- **R1·3** [E2] `core/src/recipe.rs:313`, `motion.rs:422-427` — a slide
  INSIDE a nest and a slide on a CROPPED nest clip. **REFUTED** by two runs.
  A `slide_left` on a clip inside a 640 × 360 nest starts at `x = 480.0`
  — `640/2 + 160`, the NEST's canvas, not the project's 1920 — and lands on
  `x = 0.0` at `in`. A `slide_left` on a nest clip cropped 200 px on the left
  puts its `clip_rect` at `x 2140, w 440` on a 1920-wide canvas, so its left
  edge is exactly on the canvas's right edge: the first frame IS the backdrop
  alone, and the crop is not counted twice. (Lead L3, second half.)

#### Reader 2 — "the model rules — every path an end patch, a paste or a split can bring motion through"

Every site that mints a clip was read (`grep -n allocate_id core/src/*.rs`:
`edit_clip.rs`, `edit_paste.rs`, `edit_nest.rs`, `edit_background.rs`,
`edit_time.rs`, `edit_track.rs`). The three that make a NEW clip out of an
old one say what §5e's table says they say — `edit_background.rs:473` and
`edit_time.rs:538` write `motion: None`, `edit_split.rs:125-139,183` anchors
each half to its own end and normalises — and the rest clone, which is K11.
Two of the four paste and end-patch paths hold; two do not.

- **R2·1** [E2] `core/src/edit_paste.rs:594` — `paste_attributes` with a
  payload whose `video` carries `{"motion": {}}`, or three explicit nulls,
  stores `{"in": null, "out": null, "during": null}` on the target, where the
  patch path (`edit_props.rs:272-282`) and the split rule
  (`edit_split.rs:133-134`) both store `null`. Two spellings of "no motion",
  against §5a's "one clip has one spelling"; a save writes the long one out.
  Designer's lead L4, first half, confirmed by running the op. **FIXED** —
  `Project::normalise_and_check_group` in `edit_props.rs` beside
  `check_group`, with the one call line at `edit_paste.rs:594` swapped, net
  zero on a file with one line of room. `core/tests/motion_edges.rs`'s
  `paste_attributes_stores_one_spelling_of_no_motion`, which the fix REVERTED
  fails (mutant `R2rev`), and `paste_attributes_still_copies_a_real_motion`,
  which a normalisation made too wide fails (mutant `R2wide`).
- **R2·2** [pre-E2] `core/src/edit_paste.rs` — `paste`'s payload clips are
  not range-checked, so a `motion` with `duration: -500`, `amount: 5.0` and
  `period: 0` is stored whole, each a value `set_video` refuses by name
  (`video.motion.in.duration must not be negative, not -500`). **REFUTED as
  an E2 finding** by the reader's own CONTROL: the same payload carrying
  `scale: 500.0`, `opacity: 9.0`, `corner_radius: -4.0` and
  `audio.volume: 99.0` stores all four as readily. `paste` range-checks
  NOTHING; motion is not special, and the hole predates E2 and belongs to
  `paste`'s own door. Noticed in passing, and R3·1 below is where it bites.
  (Lead L4, second half.)
- **R2·3** [D1-D3] `core/src/edit_canvas.rs:102-130` — `set_canvas {"fps":
  [24,1]}` on a 30 fps project re-snaps every clip, action and marker time
  and leaves `video.motion`'s `{"in": {"duration": 20000}, "during":
  {"period": 20000}}` exactly as they were, both now sub-frame on a 25,000
  tick grid. `text.animation`'s two timings are in the same position, and
  `paste`'s re-snap from another rate has the same hole
  (`grep -n "motion\|animation" core/src/edit_canvas.rs core/src/edit_paste.rs`
  prints nothing). It breaks `core/CLAUDE.md`'s Times rule, which road map
  7's D1·2 applied to motion at the patch door. Reproduced through the FFI.
  The root file is outside this review's list and the fix is not motion's
  alone, so **FILED kpgalligan/reelcut#26**. (Lead L5.)
- **R2·4** [SW] `core/src/edit_split.rs:166-169` — a split straddling an
  action whose hand-written `end` names `video.motion` writes
  `{"video": {"x": 150.0, "motion": {"in": {"kind": "fade", "duration":
  600000}}}}` into the first half: `narrow_to` re-derives the named key from
  the evaluated state, which the restore has already set to the BASE motion,
  so the value written is the base's `in` and not the patch's `pop`.
  **REFUTED** by the reader's own run on two counts: the `out` the lead
  expected is NOT carried (only the key the patch named is narrowed), and the
  fixture that produced it is a file no op can write — `set_action_end`
  refuses a motion. The split propagates a hand-written oddity; it does not
  invent one, and the restore keeps it inert. (Lead L6.)

#### Reader 3 — "the Swift — the section's writes inside and outside actions, the menu's batch, the wedges"

`MotionProps.dictionary`'s three keys and `VideoPatch.motion`'s
`.some(nil)` / empty-`MotionProps` arm both reach the wire in the spelling the
core's slot-by-slot merge expects (`ReelCore.swift:962,1056-1061`), and
`ProjectSnapshot.swift:968`'s `c.lenient(.motion)` answers a default for a
misspelt kind — K13's fixture already pins that. A finding rooted in either
file would have been FILED; none was.

- **R3·1** [E2] `app/Sources/EditorViewController+Motion.swift:85-87` — the
  comment "An all-identity batch is the core's refusal and beeps; a mixed one
  lands" is true of two of the three answers and silent about the third. A
  clip already carrying an out-of-range value — which R2·2 shows `paste` will
  give it — makes `set_video` an `Err`, because the op re-checks the WHOLE
  stored group; `ReelProject.applying` THROWS on an `Err`, and
  `ProjectDocument.applyEdit`'s `catch` presents the core's message, so the
  batch lands NOTHING and the clips that would have applied do not. Reproduced
  through the FFI: a pasted `scale: 500.0` makes a later motion patch answer
  `video.scale must be between 0.01 and 10, not 500`. **FIXED** — the sentence
  now names all three branches. `core/tests/motion_edges.rs`'s
  `a_motion_patch_on_a_clip_already_out_of_range_is_an_error` pins the
  mechanism the sentence describes, and the patch path's range check removed
  fails it (mutant `R3chk`). (Lead L7.)
- **R3·2** [E2] `app/Sources/TimelineClipDrawing.swift:245-247` — a stored
  `duration: 0` is legal (`ticks_positive_or_zero`), INACTIVE in the core
  (`motion.rs`'s `arrive > 0.0` filter) and LIVE in three places in the app:
  the strip draws the 2 pt minimum wedge, the section shows the kind with In
  Duration live, and Clip ▸ Motion checks it. A clip says in three places that
  it has an entrance and has none. Which of the three answers is right — refuse
  0, normalise it away, or stop claiming it — is a spec §11 decision, and
  `text.animation`'s deliberately 0-legal timings argue both ways, so
  **FILED kpgalligan/reelcut#27** with `bug` and `spec` rather than patched.
  (Lead L8.) **RESOLVED by E2-27 (§11 and §13 below):** zero stays stored and
  editable, while the timeline, inspector and menu disclose inactivity.
- **R3·3** [E2] `app/Sources/InspectorPane.swift:1364-1367`,
  `VideoPane+Motion.swift:77` — the three undo names for one write ("Set
  Motion" from the menu, "Motion In" … from the section's rows, "Video
  Properties" from the MCP mirror at `AgentServer+Clips.swift:491`), and
  whether Reset's ONE `set_video` over several ids still routes to base inside
  an action. **REFUTED** by reading the branch: `structural(video:for:)` tests
  `patch.motion != nil`, and `VideoPatch(motion: .some(nil))` is a non-nil
  `MotionProps??`, so Reset lands on the base props inside an action like every
  other motion write. Each of the three names describes its own path, which is
  the house convention, and the section's row names are what an inspector row
  is named after. (Lead L9.)

#### The four `c00678b` nits

- **N·1** [E2] `EditorViewController+Motion.swift:67,93,100,143-145` — any
  NEGATIVE menu tag read as None. `guard tag < 0 || tag < count` let a tag
  of −7 through, `edge(-7)` answered nil, and the write CLEARED a clip's
  arrival; `kindAt` returned nil for it too, so the validator checked it as
  None. The only builder is `motionSlotMenu`, which writes −1 and indices.
  **FIXED** in that file alone: None is exactly `Self.motionNoneTag`, and
  `slotAt` answers three-valued — `.some(kind)`, `.some(nil)` for None, nil
  for a stranger, which checks nothing. Two rows in `e2_chrome.py`, on the
  two fixtures where they can fail: the WRITE row on `one` (In set to
  `slide_up`) is byte-identical, and the VALIDATOR row on `none` (In empty)
  is `.off` where None is `.on`. The fix REVERTED fails both (mutant
  `N1rev`, 31/33 in the tree copy). **The EXTREMES this fix's own rule asks
  for now go through the BUILT binary** (the sceptic's Approach-7 gap,
  closed by the residue run of 2026-09-20, below): two more rows in
  `e2_chrome.py` put `Int.min`, `Int.max`, `count` (9) and `count + 1`
  through both doors, with tag `0` and None (−1) beside them as the positive
  controls — the tag VALUES live in the probe's own Swift source, since
  `Int.min` is not trusted through `JSONSerialization` either way, and the
  rows are keyed by name. The WRITE row, on `one` (In `slide_up`): the four
  strangers each leave `project.json` byte-identical, and tag `0` moves the
  arrival's kind to `fade` with `out` and `during` still null. The VALIDATOR
  row, on `none` (In empty): all five check `.off` where None checks `.on`.
  WHY they pass is still the inspection — `tag == -1 || (tag >= 0 && tag <
  count)` does no arithmetic and cannot overflow, and `slotAt` uses
  `Range.contains`, total for any `Int` — and the rows are what says it was
  RUN: the gate widened back to "any negative tag is None" (N·1's own
  defect, `guard tag < 0 || tag < count` and `if tag < 0 { return .some(nil)
  }`) fails both new rows naming `Int.min` (In `slide_up` → `None` on the
  write, `on` in the menu) and the two −7 rows with them (mutant `N1ext`,
  31/35 in a tree copy, 159.9 s with its own probe built and 51.4 s on a
  second run, under rule H at a 700 s limit). The UPPER extremes have no
  non-trapping mutant to name: a gate widened to accept `count` indexes
  `allCases[count]`, which TRAPS rather than answering, so `Int.min` is the
  only one of the five a mutant can carry through.
- **N·2** [E2] `TimelineClipDrawing.swift:219` — the glyph inferred the label
  dot's place from `nameEnd`. Read today it is EXACT (the dot branch is the
  only thing that moves `nameEnd` before it), so this is a fragility and not
  a defect, and the record says so. **FIXED** anyway, by carrying what the
  dot branch decided (`dotLeft`) rather than re-deriving it; the file keeps
  exactly one line beginning `let right = ` (`grep -c` → 1). Two rows in
  `e2_chrome.py` §1 measure a LABELLED card with a `during` against the same
  labelled card without one: the glyph's right edge is x 285.0 against the
  dot's left edge x 288, and 10.0 pt left of where it sits unlabelled
  (x 295.0). **The fix moves no pixel, so the fix REVERTED passes both rows
  by construction — measured, 33/33 (mutant `N2rev`).** The made-to-fail is
  the PINNED mutant §12 names: the one `let right =` line replaced whole by
  `let right = strip.maxX - padding`, which fails both rows (x 295.0 against
  a dot at 288, and 0.0 pt of give; mutant `N2mut`, 31/33).
- **N·3** [E2] `EditorViewController+ZoomRegion.swift:90-92,297` — the zoom
  band's second pill was computed once at arm time into a `let`, and
  `syncRegionMode` keeps the mode armed while the same clip stays the target,
  so a `during` added or cleared while armed left the pill stale. **FIXED** —
  `regionNote(_:clip:)` is re-read in `syncRegionMode`, which every
  `refreshCanvas` passes, and `note` is a `var` that redraws on change. The
  probe DID reach it (the lead doubted it could): armed with `zoomToRegion`,
  the trail is `['', 'This clip has During motion — the zoom is solved
  without it', '']` across a During ▸ Pulse and a During ▸ None. Two rows in
  `e2_chrome.py`; the fix REVERTED fails both (mutant `N3rev`, 31/33).
- **N·4** [E2] `tools/proof/phase6_chrome.py:185-188,1040-1041` — "1600
  measures identically to 1400, which is what says the number is a threshold
  and not a resonance", false since E2 (the same comment's next sentence says
  1400 scores 68/70), and a stale "1440 x 1400 … 2880 x 2800". **FIXED** —
  the size is corrected to 1440 × 1600 / 2880 × 3200, which the baseline
  run's own PNG confirms (`grad-2-open.png` is 2880 × 3200), and the
  threshold sentence GOES rather than stays: earning it back needs a render
  of one fixture at `TALL + 200` scored against `TALL`'s solved body height,
  no run in this review made that measurement, and the comment now says so by
  name. `phase6_chrome.py` re-run at **70/70**, its baseline.

#### Reader 4 — "the proof — which claims would pass against a build without the feature"

No old binary is scored (§12 already records why: the `77934fe` tree cannot
compile against the current header, and `e2_proof.py` has no handler for the
`ToolError` that would follow). The builds are eight NAMED MUTANTS of today's
tree in an `rsync` copy under a scratch directory, each patch asserting its
replaced text occurs exactly once — all checked, 1 each. Core mutants were
scored by the four core test binaries run ONE AT A TIME (`cargo test` stops
at the first failing binary, and a claim group never started is not a claim
group that answered), then by `e2_proof.py` against the copy's own build on
port 4893, then by `e2_chrome.py` in the copy. Every run went through rule H
and nothing expired.

The claim groups are the two scripts' own printed sections and the four core
test files. `e2_chrome.py` prints three numbered sections rather than the
five bullets `tools/proof/README.md` describes them in; the sections are what
was scored, because they are what a run counts.

| Claim group | Y1 no motion | Y2 spins reversed | Y3 y up | Y4 no departures | Y5 nest motion dropped | Y6 container = canvas | Y7 one op over every id | Y8 strip gate + measure |
|---|---|---|---|---|---|---|---|---|
| `core/tests/motion.rs` | fails 15/19 | fails 3/19 | fails 3/19 | fails 2/19 | fails 2/19 | fails 1/19 | not run — a Swift-only patch; `cargo test` links no Swift | not run — same |
| `core/tests/motion_edges.rs` (new; scored before R3·1's test was added — five tests then, seven now) | fails 1/5 | fails 2/5 | passes | passes | passes | passes | not run — same | not run — same |
| `core/tests/motion_copy.rs` | passes | passes | passes | passes | passes | passes | not run — same | not run — same |
| `core/tests/schema_v8.rs` | passes | passes | passes | passes | passes | passes | not run — same | not run — same |
| `e2_proof.py` §0 the instance | control | control | control | control | control | control | control | control |
| `e2_proof.py` §1 the schema | fails 2/13 | passes | passes | passes | passes | passes | passes | passes |
| `e2_proof.py` §2 the slides | fails 4/6 | passes | fails 2/6 | passes | passes | passes | passes | passes |
| `e2_proof.py` §3 fade, zoom_in, pop | fails 6/8 | passes | passes | passes | passes | passes | passes | passes |
| `e2_proof.py` §4 spin, shake, drift, bounce | fails 4/8 | **passes** | fails 1/8 | passes | passes | passes | passes | passes |
| `e2_proof.py` §5 tent, action, two slots, nest | fails 7/9 | passes | fails 1/9 | fails 1/9 | fails 3/9 | **passes** | passes | passes |
| `e2_proof.py` §6 what the model says | fails 1/11 | passes | passes | passes | passes | passes | passes | passes |
| `e2_proof.py` §7 the export path | fails 1/3 | passes | passes | passes | passes | passes | passes | passes |
| `e2_chrome.py` §1 wedges and glyph | passes | passes | passes | passes | passes | passes | passes | **fails 2/8** |
| `e2_chrome.py` §2 the section, open | passes | passes | passes | passes | passes | passes | passes | passes |
| `e2_chrome.py` §3 menu, rows, commands | passes | passes | passes | passes | passes | passes | **fails 1/23** | passes |

**How to read it.** A `control` is a row whose own text claims something did
NOT move: `e2_proof.py` §0's three are about the instance and the tool count,
and they are meant to pass in every column. The EIGHT `not run` cells are
ONE pair — Y7–Y8 against the four core test files — and the reason is the
only one there is: a Swift-only patch changes nothing `cargo test` links.
The runner prints those eight as `the binary did not run`, which is what
`not run` means here: nobody was told to run it, so it is a number no run
printed. **Every
other cell in the table was RUN.** In particular the Y1–Y6 × `e2_chrome.py`
cells are `passes` from a run and not `not run`: the plan allowed them to be
skipped on the grounds that the script reads no recipe and no render
(`grep -n "recipe\|render_frame" tools/proof/e2_chrome.py` still prints
nothing), but this review's own N·3 rows arm a canvas region whose target
comes from a recipe-derived box, so they were measured instead of argued.
They all pass, which is the answer that reason predicted. Nothing `unreached`
and nothing `expired` appears in the table, and no `not run` cell is counted
as caught.

**The two bold `passes` are findings**, by the plan's own definition: a claim
group whose text names the mutated behaviour and passes anyway.

- **R4·1** `tools/proof/e2_proof.py` §4 — **Y2 scores 61/61**. §4's rows are
  "an eighth of a turn as a 45° bounding box" and "one whole period of a
  `spin` is byte-identical to no motion", and neither can see WHICH WAY the
  clip turned: a rectangle's bounding box at +45° and −45° is the same
  rectangle, and a whole turn reduces to 0 either way. The uncropped card
  fixtures are symmetric about their own centre, so no render over MCP
  distinguishes the sign. The direction IS pinned, in
  `core/tests/motion.rs` (3 of 19 fail) and in this review's
  `core/tests/motion_edges.rs` (2 of 5 fail) — the `rotation` numbers the
  recipe publishes, read through the FFI. Designer's lead L2, confirmed.
  **UNFIXED — recorded as a limit of the instrument** in
  `tools/proof/README.md`: closing it needs a CROPPED fixture, where the
  pivot compensation makes the drawn position depend on the sign of φ, and
  the arithmetic for a 315°-rotated cropped card is a row this review did not
  write.
- **R4·2** `tools/proof/e2_proof.py` §5 — **Y6 scores 61/61**. §5's nest rows
  measure a nest CLIP's own arrival scaling every inner layer about the nest
  clip's placed centre; none measures a clip INSIDE a nest sliding against
  the nest's frozen canvas, which is what `Project::container` answers and
  what Y6 replaces with the project canvas. Caught by one test in
  `core/tests/motion.rs` and by nothing over MCP. **UNFIXED — recorded as a
  limit of the instrument** in `tools/proof/README.md`; R1·3 above is the
  same property, measured through the FFI by hand during this review.
- **R4·3** `tools/proof/e2_chrome.py` — **Y7 scored 30/30 before this
  review's rows**, exactly as designer's lead L10 predicted: the probe
  selected ONE clip for During ▸ None and reached no second clip, so a batch
  that sent one op over every id passed everything. **FIXED** — a new probe
  block selects BOTH cards of the `two` fixture (which disagree about their
  arrival) and sends During ▸ Pulse: each keeps its own arrival
  (`['slide_up', 'fade']`) while both gain the during. Y7 now fails that row
  (`['fade', 'fade']`, 32/33). Beside it, and NOT a made-to-fail row, is a
  CONTROL the same block reads: one undo puts `project.json` back byte for
  byte, under the name "Set Motion". It is a control in the plan's own sense
  — it claims something came BACK — and no mutant of E2's code can falsify
  it: a batch split into one `applyEdit` per op is still one undo step,
  because `NSUndoManager` groups by run-loop turn (measured: mutant `U1`,
  33/33).
- **R4·4** `tools/proof/e2_chrome.py` §1 — **Y8's first half was not
  caught**. Y8 is two patches, and at 30 rows only the wedge MEASURE
  (`MotionEdge().duration` for the stored one) failed; the strip's
  `InspectorTab.hasPixels` GATE removed changed nothing, because every
  fixture in the script is a shape clip and shape clips always have pixels.
  **FIXED** — a fixture whose media declares `has_video: false` (the shape a
  detached audio twin has, and the only one that exercises the gate), with a
  full motion in its props, rendered against the same clip with none: the two
  PNGs are byte-identical. Y8 now fails 2 of 8 in §1 rather than 1.

**Final scores.** `make test` green, 721 tests over 39 binaries, with the new
`core/tests/motion_edges.rs` at **7/7** (six from the review pass, the
seventh from the fix pass's widened reduction); `e2_proof.py` **61/61** with zero
SKIP lines; `e2_chrome.py` **24/24 → 33/33** (then **35/35** with the residue run's two
rows, below); `phase6_chrome.py` **70/70**.
The proofs the fixes feed, each re-run at full score on a fresh instance:
`phase6_proof.py` **168/168** and `patch_door_proof.py` **261/261** (the
renders for `motion.rs`, the patch door for `edit_props.rs`),
`phase2_chrome.py` **26/26** and `phase4_chrome.py` **59/59** (the name
strip). `make lint` and `cargo fmt --check` clean; `make typecheck` 0 errors
and exactly 4 AVFoundation warnings; `make app` building; the parity log
empty.

**The mutants this review added**, all in a tree copy, all killing the row
or test named beside them except the two said not to: `R1rev` (the
reduction's 360 not mapped back), `R1rev2` (the fix pass's widening reverted
to that first attempt — 2 of 7 in `motion_edges`), `R2rev` (the paste
normalisation removed), `R2wide` (the same normalisation made too wide),
`R3chk` (the patch path's range check removed), `N1rev` (both halves of the
negative-tag fix), `N2mut` (the pinned `let right =` replacement), `N2rev`
(N·2's fix REVERTED — 33/33, a mutant that kills nothing BY CONSTRUCTION,
which is the record's own reason for calling that fix a fragility and not a
defect), `N3rev` (the note not re-read) and `U1` (the batch split into
one `applyEdit` per op — the other one that did NOT kill its row, which is
why that row is called a control). TEN fix-REVERTED or pinned mutants in
all — nine from the review pass, `R1rev2` from the fix pass — beside the
eight NAMED mutants Y1–Y8 of the table above, eighteen together.

**The count, against this section's own numbered lines.** **EIGHTEEN**
findings are recorded above — R1·1 to R1·3, R2·1 to R2·4, R3·1 to R3·3, N·1
to N·4, and R4·1 to R4·4. **NINE are FIXED**: R1·1, R2·1, R3·1, N·1, N·2,
N·3, N·4, R4·3 and R4·4. **FIVE are REFUTED** by the reader's own run: R1·2,
R1·3, R2·2, R2·4 and R3·3. **TWO are FILED**: R2·3 as kpgalligan/reelcut#26
and R3·2 as #27. **TWO are UNFIXED and recorded as limits of `e2_proof.py`**
in `tools/proof/README.md`: R4·1 and R4·2. Nothing is UNREPRODUCED and
nothing is UNJUDGED. All ten of the designer's leads have a verdict: L1 is
R1·1, L2 is R4·1, L3 is R1·2 and R1·3, L4 is R2·1 and R2·2, L5 is R2·3, L6 is
R2·4, L7 is R3·1, L8 is R3·2, L9 is R3·3 and L10 is R4·3. No command rule H
covers was run outside it and NOTHING expired, so there is no expiry line to
write.

**The second sceptic pass, and the run that closed it (2026-09-20).** The
second sceptic pass over this review ended FIX-REQUIRED with one should-fix
and one nit; two earlier nits about `edit_props.rs`'s comments had been left
open by the fix pass's own choice, and N·1's extremes were recorded above as
owing a probe row. A residue run closed all four and changed no behaviour:
`make test` is still 721 tests over 39 binaries with none added or removed,
no assertion CONDITION moved, and the threshold `reduced as f32 >= 360.0` is
exactly what it was.

**Finding 1, the should-fix: the reduction's stated REASON was false in
seven places, and the threshold is right.** Every site said the recipe's
rotation is read into a `Float` on the Swift side, so a double near 360
"becomes exactly 360.0f over there". Nothing converts DEGREES to an f32: the
only two are `Compositor.swift:1277` and `CompositorEffects.swift:144`, both
`Float(deg * .pi / 180)` and therefore RADIANS, and `partnerBox`'s guard
(`Compositor.swift:1357`) compares `rotation == 0` on the `Double`
`RecipeLayer.rotation` (`ProjectSnapshot.swift:2271`). What is TRUE is that
the guard needs an exact zero for a layer that is unrotated to the eye, that
`rem_euclid` can hand back 360 or a hair under it, and that both fail the
guard alike — so a BAND under a whole turn is published as no turn, and the
band is a CHOSEN conservative width, "rounds to 360 as an f32 of DEGREES",
2⁻¹⁶ of a degree. The sceptic MEASURED that a threshold decided in the
renderer's real precision (radians: 3.64e-6° under a turn, a band 4.19×
narrower) FAILS the seventh test's `during` row, which sits 1.0e-5° under a
turn — so the wide band is what that test pins, and the threshold did not
move. The seven sites restated: spec §7.10's `motion.rs` row (normative,
done first), `motion.rs`'s module doc and its inline comment,
`core/tests/motion_edges.rs`'s comments and ONE assertion message,
`designs/reelcut-core-notes.md`, `designs/reelcut-remaining.md` §3, and R1·1
above.

**Finding 2, the nit: two figures.** "5e-4 px" is 5.87e-4 px, and "the 4e-14
the arithmetic actually produces here" is contradicted by the fix pass's own
fixture, where the rule moves 1.0e-5°. Both are now what a run printed:

```
band_deg=1.5259e-05 radius_px=2202.9 corner_px=5.867e-04 tie_is_360f=True
radians_band_deg=3.642e-06 ratio=4.19
during_P_t+1_deg=1.000e-05 during_P_t+100_deg=1.000e-03
```

2202.9 px is the CORNER's distance from a CENTRED pivot, and the pivot is
the layer's own anchor (`Compositor.swift:1274-1275`, `canvas/2 + layer.x`),
so no site states the bound of an unqualified pixel, or of every pixel:
nothing printed covers an off-centre layer. 1.998e-14° is R1·1's own
measured φ; "4e-14" was printed by nothing and is gone from the tree.

**The two nits the fix pass left open, closed.** `edit_props.rs`'s "a
payload is the third way a `Motion` enters a clip" told a reader the
invariant was closed. `normalise_and_check_group`'s doc now says THIS op's
payload is a third DOOR and names the two that are still open — `paste`'s
payload clips, stored whole and neither normalised nor range-checked (R2·2
above), and the FILE reader, deliberate until a patch touches it
(`core/tests/schema_v8.rs`'s
`a_motion_whose_slots_are_all_cleared_normalises_back_to_null`, road map 7
§2.2) — and spec §6's `paste_attributes` row mirrors it. `check_group`'s doc
no longer claims a range check SHARED with the patch path: its only caller
is `normalise_and_check_group` (`edit_paste.rs:594` behind it) and the patch
path calls `check_video` / `check_audio` / `check_text` / `check_shape`
directly. `core/CLAUDE.md`'s `edit_props.rs` map entry carried both
sentences and now says the same true thing; nothing else in that file was
touched. One passage of the same shape was left standing by the residue
run, outside its site list: `motion_edges.rs`'s
`paste_attributes_stores_one_spelling_of_no_motion` called
`paste_attributes` "the third way a `Motion` enters a clip". The residue
run's own review judged it: the clause is about how a `Motion` ENTERS, where
`paste`'s payload and the file reader are two more doors, so it now reads
"a third door for a `Motion`" like the rest (a comment, changed by hand
after the review; no test condition moved).

**N·1's extremes, run.** The two rows and the mutant are recorded at N·1
above. `N1ext` is the ELEVENTH fix-reverted or pinned mutant of this review
— nineteen with Y1–Y8 — where the paragraph above counts the review and fix
passes only; every mutant score quoted there out of 33 was scored on the
33-row script and none was re-run.

**Final scores, each as a run printed it.** `make test` green, 721 tests
over 39 binaries, `motion_edges` **7/7**; `make lint` and `cargo fmt
--check` clean; `make typecheck` 0 errors and exactly 4 AVFoundation
warnings; `make app` building; `e2_chrome.py` **35/35** (157.7 s with the
probe built, 65.2 s on a second run with it up to date), and the mutant
`N1ext` **31/35** in a tree copy (159.9 s with its own probe built, 51.4 s
on a second run). Both proof runs were under rule H — own process group, a
700 s hard limit (5× the recorded 138.8 s), `os.killpg` on expiry — and
NOTHING expired. `e2_proof.py`, `phase6_chrome.py` and the MCP proofs were
not re-run and are quoted above at their own runs' scores: no product code
changed, and the run's only edit under `app/` lives in the tree COPY the
mutant was built from.

**Owed, as of this record:**

- §4g's and §6g's checks by a person at the machine, now listed in
  `designs/reelcut-remaining.md` §4.
- **Two findings of the E2 reader review, filed rather than fixed**:
  kpgalligan/reelcut#26, an fps change leaving `video.motion`'s and
  `text.animation`'s ticks off the new grid (the root is `edit_canvas.rs`,
  outside that review's file list, and text's timings are in the same
  position); and #27, a motion slot with `duration: 0` — inactive in the core
  and live in the strip, the section and the menu — which needs a spec §11
  decision before a patch. Both are in `designs/reelcut-remaining.md` §5.
- **Two limits of `e2_proof.py`**, measured by that review's mutant table and
  recorded in `tools/proof/README.md`: no MCP row sees a spin's DIRECTION,
  and none measures a slide INSIDE a nest against the nest's own canvas.
  Both properties are pinned in the core tests; what is owed is a row.
- **The mix's first twelve milliseconds**, the limit measured above: it is
  bigger than §4e's own sentence expects and it is in the EXPORTED file, so
  it is owed a decision rather than only a paragraph. Entered in
  `designs/reelcut-remaining.md` §5 as one host limit a later road map would
  pick up — a lead-in on the first breakpoint, re-measured against
  `e1_proof.py` §5's hard-cut row. Nothing is filed on the tracker for it
  and no fix is attempted here: AVFoundation is what does it.

---

## 13. Issue #27 — zero-duration motion presentation (2026-09-22)

**Decision.** Spec §11's E2-27 keeps zero-duration In/Out legal, stored and
inactive, preserving D7-3 and the core's render-time contract. The UI names
the configured kind and its inactivity rather than treating the slot as
absent. A positive Duration reactivates it; None/Reset clears it. R3·2 above
is resolved on this basis.

**Implementation.** `MotionEdge.isActive` supplies the single presentation
test; its display and menu helpers attach `inactive` or `some inactive` to
stored kinds without changing Codable or defaults. The timeline gates both
wedges before the 2 pt positive-edge minimum. The Motion section shows the
first clip's inactive kind in its summary, keeps its popup and actual zero
Duration editable, and adds a selection-aware wrapping note before the rows.
Menu validation regenerates kind titles on every call and retains the
existing checkmark rules. Core motion, FFI, schema and format are unchanged.
The focused FFI test covers the write boundary, snapped sub-frame values,
first/middle/last recipe equality, one-frame In, exclusive-end one-frame Out,
two-frame Out at 0.75 × base opacity, persistence and final-slot clearing.

**Verification.** `cargo fmt --check`, `make test`, `make lint`, `make
typecheck` (zero errors, four existing AVFoundation warnings), `make app`
(`BUILD SUCCEEDED`) and `git diff --check` passed. The final offscreen
`e2_chrome.py` scored **52/52**: zero In/Out/both match the no-motion name
strip pixel for pixel; one-frame positive edges draw their minimum wedge;
the actual-source probe checks titles, notes, controls, per-clip preservation,
Reset and undo. The note measured 41 pt actual and intrinsic height at 271 pt
width, with 7 pt to the In row; the expanded `zero-open.png` was inspected
and shows two full lines without overlap. The owned Release app on port 5427
had no `Reelcut: ` startup complaint and `e2_proof.py` scored **69/69**,
including save/reopen, first/last PNG equality, reactivation and undo.

**Discrimination.** A complete copy of the current dirty author tree with
`MotionEdge.isActive` forced to `true` built successfully in isolation.
Its `e2_chrome.py` scored **41/52**, failing the zero-wedge, inactive title,
note and mixed-selection assertions while positive controls still ran.
The pristine tree reran **52/52** after that mutant. The litecode issue #27
handoff carries the full logs, mutant diff and issue-only diff against the
captured pre-edit working tree, including its pre-existing dirty documents.
The first focused Rust test attempt used the wrong fixture variant (`rect`),
fixed to `rectangle`; the first chrome probe attempted a Python constant in
generated Swift, and the second expected unsnapped 0.25 s rather than the
core's 160,000 ticks. All three mistakes were in instruments and were
corrected before the final scores above.

**Owed.** §6g's hands-on motion judgment remains for a person at the machine.
Final reader review passed with no findings (`02-issue-27/05-review.md`).
