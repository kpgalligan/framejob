# Road map 7 — deepening: the core as the one validator, three answers, one op table

- **Status:** Closed (2026-09-21). D1 (2026-09-17), D2 (2026-09-18) and D3 (2026-09-18) built and
  reviewed; the source-window candidate built in three phases (2026-09-19/20); the handler-forward
  candidate measured and retired, its smaller argument gate built (#21, 2026-09-19); the six §12.2
  continuation parts built and reviewed (2026-09-21). No user-visible feature; GitHub #1–#26 and
  #31 are all closed.
- **Original:** `archive/reelcut-roadmap-7.md` (6577 lines) — the full record, ticket by ticket.
  Sections cited below as "orig §x" refer to it. Code comments across `core/` and `app/Sources/`
  cite it as "road map 7 §x"; the section map at the foot resolves those.
- **Spec decisions** (spec §11, `designs/spec/11-decisions/`, binding):
  - **D2-1** — a refused op says why in the CORE's words; a check that predicts a RULE goes, a
    check that names the CALL stays (the six "at least one key" guards, `normalize_clip`).
  - **D3-1** — the core says what an argument IS (name, kind, required, refused bound); the app
    says what it is FOR (prose, and declared differences). Written late, at D3·6.
  - **#21** — every call is checked at dispatch against the schema its tool published, all tools,
    in the app's sentence.
  - **#22** (relied on, from road map 2's review) — a media clip's window stays inside its file,
    on the grid. **D4-1..D4-6** extend it: D4-1 one content-length function the plan obeys; D4-2
    the bound takes `start`, `trim_end` on an unmeasured window stays unbounded; D4-3 `set_speed`
    snaps nearest then holds to the bound at the new rate; D4-4 one re-snap function, a timed plate
    held to its file; D4-5 a head bound snaps UP; D4-6 the reversed mirror is app arithmetic with
    one home and the Speed sheet readout is the core's answer.
  - **D7-1** one ±9e15-tick admission envelope for structural times; **D7-2** bounded transition
    searches; **D7-3** normalize clip times when crossing a frame grid (orig §12.6–§12.7).
  - **R5-3** only re-spelled (a no-handle transition is `Outcome::Refused`, not `Ok(None)`).

## Context

Road maps 2–6 each added something a person sees; this one added nothing visible. A **deepening**
takes knowledge spread across callers (a check repeated at every door, a rule the rulebook had to
warn people to repeat) and moves it behind one module's interface, measured by what callers can
DELETE (orig §0). The vocabulary is the codebase-design skill's: deep module, seam, adapter, the
deletion test, and "the interface is the test surface" — Rust tests go through the FFI, proofs
through MCP; tests are replaced, not layered.

Three concrete defects drove it. (D1) The agent door decoded a caller's patch through the lenient
Swift types meant for what the core wrote, so a misspelt enum became the first case, a wrong-typed
optional became a clear, and a partial filter was completed from defaults — ~400 lines of Swift
hand checks compensated, door by door. (D2) An identity and a refusal were the same NULL at the
FFI; three layers invented reasons, and every refusal got a lecture about the overlap rule. (D3)
An op was spelled twelve times across seven files and the parity check compared only NAMES. The
later candidates came from an architecture review: the source-window arithmetic (§10) and
"forward the whole op" (§11), each measured before it was designed.

## Decisions

### D1 — the core is the one validator of a caller-authored object (orig §1–§3)

**The agent door forwards the caller's patch verbatim; the core refuses by dotted path and value.**
Seam is the existing `rc_project_apply`; no new export, tool or format bump. Four sentence forms:
`unknown key "<path>"`, `bad value at "<path>" in a <group> patch: …`, `missing key "<path>"`,
`<group> patch must be a json object`. Paths carry array indices (orig §2.1–§2.2).

**Lenient decoding is for what the CORE wrote; nothing a caller wrote is decoded through it.**
The rule in `app/CLAUDE.md`. Exemptions: scalar enum ARGUMENTS parsed by name (`fit`, `curveArg`,
`set_transition.kind`), and `add_media`'s descriptor, a media row with no op to refuse it
(orig §2.6).

**A patch merges key by key at every depth; `null` clears; an array replaces its list.** Two
agent-visible changes, deliberate: a nested object MERGES where two doors replaced, and a colour
is exactly four numbers 0–1, refused not clamped (`video.chroma.key` is the one `[r, g, b]`)
(orig §3).

**The walk checks JSON KIND against the group's template before serde reads.** Serde reads a
struct from a positional array and a unit variant from a one-key object; both were silently
stored. The kind check closes them and speaks the schema's words (orig §2.1).

**`serde_path_to_error` is the core's fourth direct dependency** (MIT/Apache), for the typed read's
path. Its root prints `"."`; `patch.rs::path_under` is the one join (orig §2.5).

**A `video.filters` entry must name both keys (`COMPLETE_ENTRIES`), spelled out, not derived.**
An array replaces, so a partial entry would be completed from defaults into a half-strength blur.
Widening to every list was measured (13 test failures) and rejected: `obscure` and gradient
`stops` keep partial entries. A FILE still completes from defaults (orig §2.2).

**Motion and text-animation ticks are snapped in the core, AFTER the range check.** Snapping first
would turn `duration: -1` into a legal 0. `period` floors at one frame (it divides). Audio ramp
ticks are never snapped (envelope lengths at audio rate). Files are not snapped. `set_action_end`
does not snap: an end state is an animation target (orig §2.2, §2.5).

**The end patch is walked like any patch; its values are not range-checked.** `clamp_video` in
`actions.rs` stays the last line of defence. A `shape` key is an unknown key (not animatable)
(orig §2.2).

**Two absent-argument refusals stay in Swift, by design.** `rawPatchArg` refuses only an ABSENT
patch (a mistake about the call). `zoomRegionArg` requires `region` because the core reads absent
and `null` identically — both are a zoom BACK, the opposite edit (orig §2.5).

**Raw factories (`ReelOp.setVideoRaw` etc., `patch: Any`) sit beside typed ones in `ReelOps.swift`;
the typed factory delegates to the raw one.** Keeps `ReelOps.swift` the only place an op is
spelled. An `Optional.none` widened to `Any?` would go out as null, so it is mapped explicitly
(orig §2.3–§2.4).

**`tools/proof/` is not held to the 400-line new-file cap; that cap is for source modules.**
(orig §2.4). A refusal in a proof is asserted as the WHOLE sentence, never a keyword (orig §2.3).

### D2 — an op answers one of three ways (orig §4–§6)

**`Outcome` is an enum — `Applied(Project)`, `Identity`, `Refused(String)` — not a side channel.**
The compiler was the instrument: it forced 73 `Ok(None)` sites to choose, and found five composed
ops (`insert_clip`, `overwrite_clip`, `freeze_frame`, `add_zoom_action`, scoped apply) that would
have turned an inner refusal into "nothing happened". Invalid input stays `Err`, not a fourth arm
(orig §5.1).

**The sentence crosses the FFI on a fourth out-parameter, `reason_out`, never written with
`err_out`.** NULL + neither = identity; NULL + reason = refusal; NULL + err = invalid input.
`reason_out` may be NULL (orig §5.1).

**A rule with several sites writes its sentence once and the sites pass a clause** (`locked_track`,
`clip_list` capped at three ids plus a count, `overlapping_action`, `action_past_end`). **Where an
argument would let the op through, the sentence names it** (`with_clips: true`, `ripple: true`).
`remove_track` asks the last-track question first (orig §5.3).

**Eleven rules speak; two families deliberately stay identities.** Empty selections (fourteen ops,
nothing was asked for) and the clamped-edge family (a clamp that landed where the clip already
was). The one list lives in `Outcome::Identity`'s doc (orig §5.5, §6).

**`clear_range` folds a refusal into "nothing cut"** — a splitter has no rule to refuse with; the
comment says what must change if one gains one (orig §5.1).

**The app fold (`ReelProject.applying(_ ops:)`) does not stop on a refusal and answers `.applied`
if any op applied; the first refusal is surfaced only when nothing applied.** Aborting would change
what lands for a recording landing or a caption import. Accepted narrowing: a partial success drops
the refusal's sentence (orig §5.2).

**Two swallows are deliberate:** `ReelProject.scoped(_:)` drops `no nest with id N` (a view racing
an undo), and `updateLiveEdit` swallows every non-applied tick (a refused tick is normal mid-drag).
Written in `app/CLAUDE.md` (orig §5.4).

**The agent's reply is two fixed shapes:** `<Action> made no change: the project is already in
that state.` and `<Action> was refused at <op>: <sentence>`. No rule is named for an identity
(orig §5.2).

**D2-1's line** — see spec. Kept: six "no keys given" argument checks, `normalize_clip`'s
all-skipped answer (its measurement is Swift's peaks cache), `SilenceDetector+Walls.overlapWalls`
(it SHAPES proposals; `ripple_delete_ranges` never checks the overlap rule), the Inspector's
Shift-Clips-Left sheet trial-apply, and tool prose that teaches a rule before a call (orig §5.4).

### D3 — one op table, published (orig §7–§9)

**`core/src/op_table.rs` is the op table as DATA; `OP_NAMES` is a projection of it.** 57 rows,
145 arguments at D3's close, no prose. `edit.rs` keeps only semantics; defaults moved into its
Semantics column (orig §8.1).

**`Kind` is closed: exactly one kind per answer the decoder can give** (17 at close). Two kinds
serde refuses identically would be a distinction no test can prove. Every `Kind` match is
exhaustive — a catch-all would let a new kind skip the test meant to prove it (orig §8.1–§8.2).

**The table's test asks the DECODER, not a second list.** Unknown field → serde lists the real
ones; missing required → names it; wrong kind → names the Rust type. `Op` is internally tagged, so
serde cannot name the ARGUMENT in a type error (`serde_path_to_error` answers `.`); tests name it
by construction (one argument replaced per probe) (orig §8.1, §11.3).

**`op_schema.rs` publishes JSON Schema via `rc_op_schemas`, a separate module.** A patch is
`{"type":"object"}` and opaque (D1 owns it); a `Region` is closed (`additionalProperties: false`);
no op schema is closed, since `project`/`scope` merge in; `Ticks` has no minimum (deltas are
negative) (orig §8.2).

**A bound the core REFUSES outside belongs in the table (`Bound`, sourced from the refusing
constant); a bound it CLAMPS to, a null that MEANS something, a bare-string shorthand and an
app-state default are the app's — declared in `AgentCatalog+Declarations.swift`, one reason per
row.** Only `set_canvas` width/height carry a `Bound` (`CANVAS_MIN/MAX`); `set_speed.rate` clamps
so it is a declaration (orig §8.3; spec D3-1).

**The direction rule: a schema narrower than what a tool accepts costs nothing; wider is a broken
promise.** So `boolArg`'s string spellings are declared; `NSNumber`-as-bool, lone id as list,
id as string and `fps: 30` as `[30,1]` are accepted but deliberately NOT declared (orig §8.3–§8.4).

**Every op tool is `opTool(…)`: prose plus one sentence per argument; structure comes from the
core.** Typed Swift builders stay hand-written so the compiler guards call sites; no codegen
(orig §7, §8.3).

**The fifth parity part (`AgentServer+Parity.swift`) compares names both ways and complains about
prose: an undescribed argument, and a description for an argument no op has.** It reports like the
other four (debug assert, release `NSLog "Reelcut: "`) and does not stop launch (orig §8.5).

**A generated artefact is checked by asking the thing that generated it a question it did not
write the answer to.** Twice a constraint the app enforced silently vanished from the schema while
every instrument stayed green, because catalog and oracle read the same list. Hence
`op_argument_proof.py` calls the RUNNING app, and a core test hands every whole-number argument
out-of-range values to find a lost `Bound` (orig §8.3–§8.4, §9).

**Accepted loss:** `add_zoom_action.region`'s four members arrive undescribed (the core owns them;
a nested-properties merge was rejected) (orig §8.3).

### The source window (orig §10)

**Readers AND the mover in one module, `core/src/source_window.rs`; units in the NAMES, not a tick
newtype.** A newtype would touch every tick for a hypothetical seam. The `Option` whose `None` meant
"unbounded" in one caller and "zero handle" in another is `SourceBound` (`Unbounded`/`Unmeasured`/
`Timeline`) read by `or_unbounded` or `or_empty` (orig §10.6; D4-1).

**Phase A was a pure move** (one D4-1 behaviour change); **phase B** made the invariant true at
`set_speed`, `paste`, `absorb_nests`, `unnest`, `add_background` and `trim_start`'s head (D4-2..D4-5;
six overruns measured before, none after). `rate_stretch` needed no code: `round(d × c/d) == c`
(orig §10.7–§10.8).

**`evaluate.rs::segment_of` keeps its own `duration − 1` in-point clamp and a media-rate still
margin** — it answers "which tick can AVFoundation be handed", not "where may a window start";
swapping would re-frame every pre-#22 file (orig §10.8).

**The reversed mirror stays APP arithmetic, in one file, `ReverseMirror.swift`.** The core keeps
none: `in` is measured in the stream the clip plays; a second convention would leak into every
trim/split/reader (`set_reversed`'s doc). Phase C found `TimelineView.sourceTime` applied no mirror
(a reversed clip drew the forward waveform) and fixed it (orig §10.9; D4-6).

**The Speed sheet readout applies the sheet's own ops to the immutable handle** — no `rc_*` preview
export, no Swift quotient; `set_speed` does not hold a slowed clip to its neighbour (the overlap
rule applies or refuses) (orig §10.9; D4-6).

**The commit tail was split off as its own candidate** (purity/overlap/undo, not the window), later
built as §12.8 (orig §10.6, §12.3, §12.8).

### The handler forward, retired; the gate (orig §11)

**Forwarding a caller's whole op unread was measured and NOT done; the series ends at three
deepenings.** It would lose 21 app refusals (three correctness-critical: `checkDocumentLevelTicks`
places markers at the right time under an open nest; `add_zoom_action.region` and
`set_transition.kind` required so a forgotten key is not a zoom-back or a clear), 6 app-state
defaults and 11 per-op transforms; the core does not strip `"project"`; serde cannot name the
argument in a type error (orig §11.1–§11.3, §11.6).

**Instead, one comparison at dispatch (`AgentServer+Gate.swift`):** a caller's keys against the
tool's published properties, before scope or handler; all tools including app-state ones; the
APP's sentence (`add_track does not take nmae. It takes index, name, project and scope.`). Deletes
nothing, so no size toll (orig §11.6, §11.8; spec #21).

**Integer arguments refuse fractions** (`whole`, `rateTerm`/`fpsPair` in
`AgentServer+Arguments.swift`); `3.0` is still 3. Before, `clip: 3.7` was clip 3 in silence and
`fps: 1e30` could trap (orig §11.4, §11.8).

### Continuation (orig §12)

**D7-1/D7-2/D7-3** (see spec): `time_bounds.rs` is the one structural-time checker; transition
searches never walk frames (`transition_search.rs`); `frame_grid.rs` normalizes clip times for
canvas fps changes (nests included), paste and unnest, reusing `source_window.rs`'s bound
(orig §12.6–§12.7).

**Placement commit ownership:** `edit_commit.rs` (`commit_replacements`, `commit_additions`,
`finish_placement`, `finish`). `check_overlap_rule` stays the rule's owner and
`set_gained_transitions` the only minting algorithm; `paste`/`unnest` keep overlap checks as
fallback-track SEARCHES; roll and freeze still do not mint (orig §12.3, §12.8).

**Historical chrome comparisons build the old app with the old core and header**
(`tools/proof/reference_build.py`), never the current staticlib; a failed reference build is a
scored failure (orig §12.9; root `CLAUDE.md`).

**Contract precision:** `required: false` promises omission only; the four defaulted plain booleans
(`ripple`, both `with_clips`, `rescale_clips`) reject `null`; `Option<T>` fields accept it. Both
`add_transition` modes FLOOR a request to frames, unlike `set_transition_duration`'s nearest
(orig §12.11).

### Method (carried into later road maps)

Prefactor first (make the deep module able to say what the shallow callers said, so later tickets
are deletions); expand-then-migrate with the check turned on LAST; a before/after capture of the
published surface read in both directions; decision in spec §11 before code (D2-1 was nearly
reversed in a commit message); run EVERY proof script when the FFI changes; measure counts with
`wc -l`/grep at the end, never carry them (orig §0, §3, §6, §9, §10.10).

## What it built — where it lives now

- Core: `core/src/patch.rs` (walk, typed read, `COMPLETE_ENTRIES`, `path_under`,
  `check_group_patch`, `merge_group`), `core/src/edit_props.rs` (`snap_motion`, `snap_animation`),
  `core/src/outcome.rs` (`Outcome` and the one list of which refusals speak),
  `core/src/ffi_edit.rs` (`reason_out`), `core/src/op_table.rs`, `core/src/op_schema.rs`,
  `core/src/ffi_query.rs` (`rc_op_schemas`), `core/src/edit_canvas.rs` (cut out of
  `edit_track.rs`), `core/src/source_window.rs`, `core/src/time_bounds.rs`,
  `core/src/transition_search.rs`, `core/src/frame_grid.rs`, `core/src/edit_commit.rs`,
  `core/src/edit_clip_timing.rs`.
- Core tests: `patch_door.rs`, `refusal.rs`, `op_table.rs`, `op_schemas.rs`, `op_nullability.rs`,
  `op_default_booleans.rs`, `op_ticks.rs`, `op_tick_payloads.rs`, `source_window.rs`,
  `source_invariant.rs`, `source_edges.rs`, `time_bounds.rs`, `time_bounds_edits.rs`,
  `transition_bounded.rs`, `frame_grid_canvas.rs`, `frame_grid_transfer.rs`,
  `commit_placement.rs`, `commit_composed.rs` (all in `core/tests/`).
- App: `ReelEdit.swift` (the three arms, the list fold), `ReelOpSchema.swift`, `ReelCore.swift`
  (`coreSchemas()`, the one read of both message channels), `ReelOps.swift` (raw factories),
  `AgentServer+Arguments.swift` (`rawPatchArg`, `whole`, `rateTerm`), `AgentServer+Clips.swift`
  (`zoomRegionArg`, `newClipPatchArg`), `AgentCatalog.swift` (`opTool`),
  `AgentCatalog+Declarations.swift`, `AgentServer+Parity.swift`, `AgentServer+Gate.swift`,
  `ReverseMirror.swift`, `SpeedSheetController.swift` (`ops(for:)`, `lengths(of:)`),
  `TimelineView.swift` (`sourceTime(of:in:at:)`). Deleted: `AgentServer+Motion.swift`, `patchArg`,
  `colorArg`, `withOpaqueColors`, `checkVideoEnums` and the rest of the Swift launder.
- Proofs (`tools/proof/`): `patch_door*.py` (four files), `refusal_proof.py`, `refusal_probe.py`,
  `op_schema_probe.py`, `clip_catalog_proof.py`, `op_catalog_proof.py`, `op_argument_proof.py`,
  `source_mirror_probe.py`, `frame_grid_proof.py`, `op_contract_proof.py`, `reference_build.py`
  (+ `reference_build_selftest.py`); `mcp.py` gained `schemas()`.
- Documents: `CONTEXT.md` (Op, Patch, Identity, Refusal, Op table, Argument); spec §5.2, §5.5,
  §6 preamble ("how to read a 'refuses'"), §7.9, §7.10.

## Known limits

- **Range refusals are not indexed**: `props_check.rs` spells `video.filters[].amount`,
  `video.obscure[].*`, `shape.gradient.stops[].*`, so a refusal names the field and value, not
  which entry (orig §2.1). See Open items.
  Fixed since: the key names its index (`video.filters[2].amount`), issue #89.
- **A type error names the Rust type, not the argument** (internally tagged `Op`; measured).
  The Swift readers and the gate name arguments instead (orig §8.1, §11.3).
- **Nullability is not in the published table**: `set_transition.kind` and
  `add_zoom_action.region` are app declarations; a column was left as optional future design
  (orig §8.2, §9, §12.11).
- **The parity check cannot see a CALL**: an inert declarations row or an argument no handler reads
  is invisible to it; `op_argument_proof.py` and the gate cover those (orig §8.5).
- **The fold drops a refusal's sentence when another op in the list applied** (orig §5.2).
- **Clamped-edge ops answer `Identity`**, not a refusal: slip/roll clamped to nothing, roll with no
  predecessor, trim whose clamps cross, rate stretch outside ×0.1–×10, `detach_audio` with no
  audio, `set_transition_duration` with no predecessor or room (orig §5.3, §6).
- **The reversed mirror is one tick high** (`T − p`, not `T − 1 − p`): one blank waveform column at
  a whole-file reversed clip's head. Declined: `silence2_proof.py` walks these numbers tick-exact in
  Python on purpose (orig §10.9).
- **×2 then ×1 at a file's tail is not an identity** — D4-3's stated cost (orig §10.8).
- **The Speed sheet readout shows a length, not the cross dissolve a neighbour gains** (orig §10.9,
  §12.10).
- **An instance deadlocks past ~40 open documents**; relaunch per proof script (orig §2.4, §5.1).
- **Measured and rejected, do not retry blind:** widening `COMPLETE_ENTRIES` to every list (13
  failures, a behaviour change to two vocabularies, orig §2.2); a tick newtype (orig §10.6); a mirror
  in the core (orig §10.6); the whole-op forward (21 refusals lost, orig §11.2); a combinator over
  the three-arm matches (hides the decision the enum forces, orig §5.1); `serde_path_to_error` on
  op arguments (answers `.`, orig §8.1).

## Open items

- The clamped-edge family could answer `Refused` with a sentence — a candidate, not started, not
  owed by D2 — tracked in #88.
- Index range refusals (`filters[1].amount`), moving `phase6_proof.py`'s `[]` assertions with it —
  tracked in #89.
- `performGroupedEdit`'s empty undo group on an identity/refusal: reproduce with undo-stack
  assertions and re-audit the "unreachable" claim (inspector, canvas and add-clip paths call it) —
  tracked in #59.
- A partial success whose list also held a refusal drops the sentence; no tool produces the case
  today — tracked in #88.
- Nullability as an op-table column (optional design) — tracked in #90.
- ~~Residual argument-name literals in older proof scripts (app-state tools; `phase4`/`phase5` prose
  claims) — tracked in #82.~~ Struck (issue batch B7): since 77b0bb8 those scripts read `tools/list`
  through `mcp.schemas()`; the literals left are property names a check has to spell.
- Stale doc comment: `app/Sources/ReelEdit.swift` still says refusals answer `.identity` "until road
  map 7's D2·3 gives them their sentences" — fixed by 2026-09-26 (`ReelEdit.swift:64`).
- The Speed sheet showing a neighbour's dissolve rather than a length (a separate UI decision) —
  tracked in #109.
- Person checks for parts 1–6 (playback, layout of the Speed sheet hint) — tracked in #47 and
  #48.

## Where to look in the original

| Section | What it holds |
|---|---|
| orig §0 | The series' rules: deep module, seam, deletion test, interface is the test surface; prefactor first; gates; size. |
| orig §1 | D1's problem, shape and tickets (#2–#7); out-of-scope list. |
| orig §2.1 | D1·1 (#2): path + value in every refusal, the kind check, `serde_path_to_error`, `patch_door.rs`. |
| orig §2.2 | D1·2 (#3): `patch.rs` split out, `COMPLETE_ENTRIES`, end-patch walk, snaps after range checks, `ZoomRegion` deserialize; the widen-to-every-list measurement. |
| orig §2.3 | D1·3 (#4): `set_video` forwards raw, `rawPatchArg`, raw factory shape, `patch_door_proof.py` born; whole-sentence rule. |
| orig §2.4 | D1·4 (#5): eight more doors, four-number colours, `colorArg` deleted, proof split into four files; `tools/proof/` not held to the 400 cap; the 40-document deadlock. |
| orig §2.5 | D1·5 (#6): `set_action_end` and the region forward raw; root path `"."` → `path_under`; why `zoomRegionArg` stays; why end patches do not snap. |
| orig §2.6 | D1·6 (#7): launder deleted, the lenient-decoding rule written, spec §4.3/§5.2/§6/§7.9 and `CONTEXT.md` updated, the two mutants. |
| orig §3 | D1 closed: the two agent-visible changes, measured arithmetic (−617 handler lines, +470 core), tolls. |
| orig §4 | D2's problem, shape and tickets (#9–#13); out of scope (refusal UI, codes, empty selections, query exports). |
| orig §5.1 | D2·1 (#9): `outcome.rs`, 73 sites, five composed ops, `reason_out`, `refusal.rs`, `clear_range`'s fold. |
| orig §5.2 | D2·2 (#10): `ReelEdit.swift`, the fold's narrowing, the five app paths, reply shapes, `refusal_proof.py`/`refusal_probe.py`, the empty undo group. |
| orig §5.3 | D2·3 (#11): the rules' verbatim sentences table, shared writers, `edit_canvas.rs` toll, the clamped-edge family named. |
| orig §5.4 | D2·4 (#12): Swift trial-applies deleted; what stayed and why (D2-1's line); the two swallows. |
| orig §5.5 | D2·5 (#13): glossary Identity/Refusal, spec §6 "how to read a refuses", the fourteen empty-selection ops, rotted probes, cross-build skip (later repaired, §12.9). |
| orig §6 | D2 closed: eleven rules, measured arithmetic, owed items, lessons. |
| orig §7 | D3's problem, expand-then-migrate, tickets (#15–#20), out of scope (prose to the core, whole-op forward, codegen). |
| orig §8.1 | D3·1 (#15): `op_table.rs`, `Kind`'s one-kind-per-answer rule, decoder-as-oracle test, `rustfmt::skip`. |
| orig §8.2 | D3·2 (#16): `op_schema.rs`, `rc_op_schemas`, the Kind→Schema mapping table, nullability not published. |
| orig §8.3 | D3·3 (#17): `Bound`, `opTool`, the declarations list born, the before/after capture and verdicts, the region-prose loss, the `ranges` `minItems` lesson. |
| orig §8.4 | D3·4 (#18): remaining groups migrated, the fourth playhead row, `fps` items, the lost-`Bound` test. |
| orig §8.5 | D3·5 (#19): fifth parity part, the ten undescribed arguments, `op_argument_proof.py`, `mcp.schemas()`. |
| orig §8.6 | D3·6 (#20): documents, seventeen stale sentences swept, spec D3-1 written late. |
| orig §9 | D3 closed: measurements, 25 mutants, the drift table, lessons, where the next candidate starts (read with §11). |
| orig §10.1–§10.5 | The source-window scout: what was really duplicated (six core movers; Swift's five sites are not edits), the three clamp forms and the two meanings of `None`, #22's two road-map-2 bugs, unverified readings, the test surface. |
| orig §10.6 | The source-window decisions (readers + mover, names not newtype, commit tail split off, mirror stays app) and the three phases. |
| orig §10.7 | Phase A: `source_window.rs` pure move, D4-1, `core/tests/source_window.rs`. |
| orig §10.8 | Phase B: D4-2..D4-5, the before/after overrun vectors, why `segment_of` stays, three residues. |
| orig §10.9 | Phase C: `ReverseMirror.swift`, the unmirrored-timeline defect measured, the Speed sheet asks the core, three limits. |
| orig §10.10 | Source window closed: what was declined, the commit tail as next candidate. |
| orig §11.1–§11.5 | The whole-op forward measured: handler classification, 21 refusals, what the core would say, float round-trip and `intValue` truncation, the silent-drop defect. |
| orig §11.6–§11.7 | The decision to retire it and build a gate instead; what was not measured. |
| orig §11.8 | The gate landed (#21), fraction refusal, the audits and proof rows. |
| orig §12.1–§12.5 | 2026-09-21 review: status table, the six continuation items, commit-tail counts, deliberate behaviour, verification. |
| orig §12.6 | Part 1: D7-1/D7-2, `time_bounds.rs`, `transition_search.rs` (#24, #25, #31). |
| orig §12.7 | Part 2: D7-3, `frame_grid.rs`, stored nests (#26). |
| orig §12.8 | Part 3: `edit_commit.rs` placement interface, measured deletion. |
| orig §12.9 | Part 4: `reference_build.py`, historical chrome comparisons restored. |
| orig §12.10 | Part 5: the Speed sheet hint. |
| orig §12.11 | Part 6: nullability and tick coverage (`op_nullability.rs`, `op_ticks.rs`, `op_contract_proof.py`). |
| orig §12.12 | Unlocked recording verification. |
