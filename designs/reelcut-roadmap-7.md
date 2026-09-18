# Reelcut — road map 7: deepening

**Status: D1 IN PROGRESS — D1·1 to D1·5 built (§2.1 to §2.5); D1·6,
the contract step, not started.**

Road maps 2 to 6 each added something a person using the app can see. This
one does not. A **deepening** takes knowledge that is spread across callers
(a check repeated at every door, a rule the rulebook has to warn people to
repeat) and moves it behind one module's interface. The callers shrink, and
the tests move to that interface. Success means a person editing in the app
notices nothing, and an agent calling over MCP gets one set of rules with
one wording.

Each candidate is designed in a grilling session with the user. Its spec is
a GitHub issue labelled `spec`, and its tickets are issues labelled
`ready-for-agent` (`docs/agents/issue-tracker.md`). An issue is a snapshot of
the design conversation. This document holds what outlasts one: the rules
the series inherits (§0), each candidate's plan in the order it was built
(§1), and the record (§2).

---

## 0. Rules the series inherits

The vocabulary is the codebase-design skill's, used exactly: **module**,
**interface** (everything a caller must know, including its error modes, not
only the signature), **depth**, **seam**, **adapter**, **leverage**,
**locality**. `CONTEXT.md` holds the domain words (Op, Patch). Four rules
decide what a deepening is allowed to be:

- **Deep module.** A lot of behaviour behind a small interface. The deepest
  module in Reelcut is the core behind `rc_project_apply`: one JSON op goes
  in, and a project, "nothing changed" or a refusal comes out. A deepening
  moves knowledge toward an interface like that. It never adds a second,
  shallower way in beside it.
- **Seam.** The place where an interface lives. The series uses the seams
  that already exist: the op envelope through `rc_project_apply`, the MCP
  tools, and the FFI's three files in lockstep. It adds a new one only when
  something actually varies across it. One adapter is a hypothetical seam;
  two make a real one.
- **The deletion test.** Imagine deleting the module. If the complexity
  vanishes, the module was a pass-through. If it reappears across many
  callers, the module was earning its keep. A deepening is measured by what
  it lets the callers DELETE, and the record states that in lines.
- **The interface is the test surface.** A test crosses the seam a caller
  crosses. Rust tests go through the FFI (`core/tests/*.rs`), and proof
  scripts go through MCP against the built app (`tools/proof/`). A test that
  has to look past the interface means the module is the wrong shape. Tests
  are replaced, not layered: when the shallow checks go, a test that pinned
  their wording moves to the deep module's wording, with the reason written
  in the test.

The project's standing rules apply unchanged, and this series leans on four
of them:

- **Nothing in spec §11 is re-litigated**, and neither is a spec issue's
  Implementation Decisions section. Anything learned while building goes in
  §2 here, in a rulebook or in `CONTEXT.md`. It never goes back into the
  issue.
- **The prefactor lands first.** The first ticket of a candidate makes the
  deep module able to say what the shallow callers used to say. That turns
  every later ticket into a deletion.
- **Every ticket passes the gate for what it touched.** For the core that is
  `make test`, `make lint` and `cargo fmt --check`. For the app it is also
  `make typecheck` at 0 errors and the same 4 warnings, `make app`, an empty
  startup parity log and every proof green. A new proof claim is made to
  fail on purpose once, and its mutants are counted.
- **Size.** A file at the ~600-line cap gives something up before it takes
  anything on, and a new file is capped at 400 lines. A ticket that only
  deletes is a ticket that pays down `designs/reelcut-remaining.md` §3.

---

## 1. D1 — hand the core the caller's own patch

**Spec:** kpgalligan/reelcut#1.

**The problem.** An agent writing a property patch by hand over MCP could
make a mistake that got corrected or dropped instead of refused. The agent
door decoded the caller's object through the same lenient Swift types the
app uses to read what the core wrote, re-encoded the result and sent that
on. A misspelt enum became the vocabulary's first case, a wrong-typed
optional became a clear, and an incomplete filter entry was completed from
defaults. About four hundred lines of hand checks in the Swift handlers made
up for it, one door at a time. Two of those doors also disagreed with the
core about what a nested object means (replace against merge).

**The shape.** The seam is the existing one: every op reaches the core as
JSON through `rc_project_apply`. The agent door forwards the caller's object
verbatim, and the core becomes the one validator. A refusal names the dotted
path (with array indices) and the offending value, and leaves the project
untouched. A valid patch merges key by key at every depth: `null` clears a
key and an array replaces its list. The Swift checks, allow-lists and hand
readers are deleted. The rule "check enums and types by hand at every door"
becomes "lenient decoding is for what the core wrote; nothing a caller wrote
is decoded through it". There is no new export, no new tool and no format
bump. Agents will see two behaviour changes: a nested object merges where it
used to replace, and a colour must be four numbers where three were once
accepted.

**The tickets, in blocking order.** #2 → #3 → #4 → (#5 and #6, in either
order) → #7.

| Ticket | Title | Blocked by |
|---|---|---|
| kpgalligan/reelcut#2 | D1·1: the core names the path and the value in every patch refusal | — |
| kpgalligan/reelcut#3 | D1·2: the core changes what a patch may carry: filters, ticks, regions, end states | #2 |
| kpgalligan/reelcut#4 | D1·3: set_video forwards the caller's patch, and the patch-door proof is born | #3 |
| kpgalligan/reelcut#5 | D1·4: the remaining property doors forward raw; colours are four numbers | #4 |
| kpgalligan/reelcut#6 | D1·5: the end-state and region doors forward raw | #4 |
| kpgalligan/reelcut#7 | D1·6: contract and record: delete the launder, write the rule, fail the proof twice | #5, #6 |

D1·1 and D1·2 are core-only. Each proves its claims through the FFI. D1·3
creates the MCP proof that every later door ticket adds a section to. D1·6
is the contract step: the shared launder machinery goes, the rule is written
where the warning was, the proof is made to fail twice (once with the
launder restored at one door, once with the core's key walk disabled), and
the record below is closed with the lines deleted.

**Out of scope, and named so it is not rediscovered.** Deriving the catalog,
the typed factories and the parity check from the core's op table is a
separate candidate. So is a refusal that carries its reason for an op that
returns nothing (today an identity and a refusal look the same). The same
goes for the duplicated recipe key list and the other duplicates the
architecture review listed. What the core wrote (the project, the plan, the
recipe, export settings) stays leniently decoded.

---

## 2. D1 — the record

One entry per ticket, written when it lands.

### 2.1 D1·1 — the core names the path and the value (kpgalligan/reelcut#2)

**Commits.** `ebab0db` (the ticket) and `b02e4df` (what its review found,
below).

**What landed.** Core and documents only. No Swift changed, so an agent does
not see any of this yet: the agent door still decodes before the core does,
until D1·3.

- **The walk checks keys and kinds, with indices.** `edit_props.rs`'s
  `check_keys` builds the path per element, so a misspelt key on the second
  filter is `unknown key "filters[1].kindd" in a video patch`, where it used
  to say `filters.kindd`. At every step it also compares the value's JSON
  kind against the group's template. It refuses
  `bad value at "<path>" in a <group> patch: expected <kind>, not <value>`,
  where the kind is an object, a list, a string, a number, a whole number or
  true or false.
- **Why the kind check matters.** The review found that serde READS two
  wrong kinds. A struct deserializes from a JSON array of its fields in
  declaration order, so `{"duck": [0.9, 300000, 600000]}` stored a duck.
  A unit variant deserializes from a one-key object, so
  `{"blend": {"multiply": null}}` stored a blend. Both are refused now. The
  check also means a type refusal speaks the schema's words, not
  serde's `expected struct Duck`. A `null` always passes the walk, because
  in a patch it clears.
- **The read names its path.** `merge_group` is now typed
  (`merge_group<T>(base: &T, patch, group) -> Result<T, String>`): the
  object check, the walk, the deep merge, then a `serde_path_to_error` read.
  The read catches what only the type knows: a misspelt variant, a `null` a
  required field cannot take, a colour of the wrong length. It refuses them
  as ``bad value at "<path>" in a <group> patch: <serde's sentence>``, whose
  sentence names the value and, for a variant, what the vocabulary allows:
  ``bad value at "filters[1].kind" in a video patch: unknown variant `glw`, expected one of `blur`, …``.
  The path runs into the MERGED group, which gives the same path as the
  patch's. Its six callers (the four `set_*` arms, `add_text_clip` and
  `add_shape_clip`) each dropped their own `from_value` and their "… patch
  does not match the schema" message. A new clip's patch is therefore
  refused in exactly the words `set_text` / `set_shape` use.
- **The article is right:** "an audio patch", no longer "a audio patch".
  `set_clip` is unchanged, because it already named the key and the value
  (`"name" in a clip patch must be a string or null, not 5`).
- **The dependency.** `serde_path_to_error` 0.1.20 (MIT OR Apache-2.0). Its
  own dependencies, `serde_core` and `itoa`, were already in the lock file.
  It is the core's FOURTH direct dependency, not its third as the ticket
  said: `tiny_http` was already there. `core/CLAUDE.md`'s new
  **Dependencies** rule says why each of the four is there.

**Tests.** A new file, `core/tests/patch_door.rs`, holds six table tests
through the FFI. Every refusal goes through `Handle::errors`, which is the
"project unchanged" claim at this seam: NULL with a message means no new
project and no undo step, and a correction or a clear would come back as a
new handle and fail the test. (The first commit also compared the handle's
JSON before and after. A handle is immutable, so that could never fail, and
the review had it removed.) Each message is compared exactly, or by its path
prefix plus serde's value. The cases covered:

- an unknown key with an index (`filters[1]`, `obscure[1]`,
  `gradient.stops[1]`) or at depth (`motion.during`, `compressor`,
  `animation`), at every group;
- a misspelt variant at every group that has one (`filters[1].kind`,
  `blend`, `motion.in.kind`, `obscure[0].kind`, `align`, `animation.kind`,
  shape `kind`, `gradient.kind`);
- a wrong kind where a nested object belongs: shadow, duck, outline and
  stroke. Each is STORED on the fixture, so a clear would have been a real
  edit. A clip name that is not a string is covered too;
- a wrong kind inside an object or a list (`filters[0].amount`,
  `duck.attack` as a fraction, `outline.color[1]`, `gradient.stops[1].at`),
  and a `null` for the required `crop`;
- a list or an object where the schema has another kind (duck, a filter
  entry, crop, blend, animation, stroke);
- the `text` and `shape` of a new clip.

`audio` has no list and no enum, and `set_clip`'s patch is two flat strings.
"At every group" therefore means the deepest place each group's own
vocabulary has. `text` gets its index through a colour component.

Five existing tests asserted the old wording. Each now asserts the path and
says why in a comment naming this ticket: `schema_v4.rs`'s region key (and
its comment that said the path deliberately carried no index),
`schema_v5.rs`'s animation kind, `schema_v6.rs`'s blend and gradient kind
and its gradient stop key, and `schema_v8.rs`'s motion kinds.

**Measured.**

- `make test`: 627 passed, 0 failed (621 before, plus the 6 new tests).
- `make lint` and `cargo fmt --check`: clean.
- Line counts: `edit_props.rs` went from 432 to 522, `edit_clip.rs` from
  1043 to 1038, and the new `patch_door.rs` is 390.
- Mutants, all caught:
  - The walk without the index failed `patch_door` tests (4 of the final 6)
    plus the `schema_v4` and `schema_v6` key tests.
  - `serde_json::from_value` back in place of the path-tracking read failed
    3 `patch_door` tests plus the `schema_v5`, `schema_v6` and `schema_v8`
    kind tests.
  - "a audio" failed 4 `patch_door` tests.
  - The kind check disabled failed 3 `patch_door` tests; the positional
    reads came back.
  - The whole-number refinement disabled failed 1.

**The review** (standards and spec, in parallel, against the ticket and
spec #1).

Fixed:

- An array where an object belongs, and an object where an enum belongs,
  were read, not refused. This is the kind check above; the spec review
  found the array case.
- The tautological "project unchanged" comparison is gone.
- `Group::article` no longer repeats the four names.
- The test helper is `patch_op`, not `patch`: it returns an op.
- Spec §7.10's `edit_props.rs` row now names `merge_group`, mirroring
  `core/CLAUDE.md`.
- Rust type names in type refusals are gone, except in the read's
  `null`-on-a-required-field sentence (`expected struct Crop`).

Judged not real:

- *The range check after `merge_group` is repeated at six sites.* Each
  group's check has a different signature: video needs the clip's source
  size and the nest-blend check. Folding them into the read would need a
  per-group trait for no caller that needs it.
- *"patch must be a json object" appears twice.* This predates the ticket,
  and both copies are needed. `patch_clips` checks before resolving ids, so
  an empty selection still refuses a non-object. `merge_group`'s copy guards
  the two new-clip ops.
- *"Third dependency" and "every group" do not hold literally.* Both
  readings are recorded above.

**The review** (standards and spec, in parallel, against the ticket and
spec #1).

Fixed:

- **An unknown key spelled with a `null` escaped the new door.** The end
  patch stripped its nulls BEFORE the walk, so `{"video": {"blurr": null}}`
  was dropped and answered as an identity rather than refused — the one
  thing a patch may never do (`CONTEXT.md`). The strip now lives inside
  `check_group_patch`, after the walk and before the typed read, which is
  where the two readings of a `null` actually part.
- **`add_text_clip` did not snap.** Spec #1 puts the snap "at the patch
  door", and a new clip's `text` is one of them. `snap_animation` is
  `pub(crate)` and `edit_clip.rs` calls it, so the two text doors land on
  the same grid.
- **Three sentences outside the diff were made false by it** and are
  corrected: `edit.rs`'s op table (an end patch "keeps what it does not
  know"), `model.rs`'s reader note ("kept as written by `set_action_end`")
  and `core/CLAUDE.md`'s `actions.rs` entry ("lenient by design"). The op
  table's `set_action_end` and `add_zoom_action` rows now say what spec §6
  says, which is the four-mirrors rule.
- **The Times rule was half kept.** The six audio ramp ticks
  (`audio.fade_in` / `fade_out`, the duck's and the compressor's attack and
  release) are not snapped and never were. They are envelope lengths
  sampled at the audio rate rather than positions in the picture — a 10 ms
  compressor attack quantised to a video frame rounds to nothing — so the
  rule in `core/CLAUDE.md` and `check_audio`'s doc now say so instead of
  leaving it unstated.
- **A field added to `Filter` would have joined the completeness rule** the
  day it landed and refused every patch an agent had already learnt to
  write. `COMPLETE_ENTRIES` spells `("filters", ["kind", "amount"])` rather
  than taking the template entry's keys.
- Three smaller ones: the `check_end_patch` doc link pointed at the module
  it had just left; `check_end_patch` re-spelled the three group names as
  string literals where `Group::name` owns them; and a `phase6_proof.py`
  docstring line ran past the file's wrap.

Judged not real:

- *`ZoomRegion`'s hand-written `Deserialize` is scope creep.* The ticket
  asks for the unknown and missing member, which serde already gave. The
  positional LIST read is the same defect D1·1 found and closed inside a
  patch, at the one op argument shaped like one, and spec #1's ninth user
  story asks for every such door to behave identically. Recorded as a
  deliberate addition rather than dropped.
- *`period`'s frame floor is not a snap.* A period of five ticks lands on
  one frame where the nearest grid point is zero. That is the point: the
  value has no zero (`props_check.rs` refuses one), so the smallest period
  on the grid is a frame.
- *`core/tests/patch_door.rs` is 597 lines, past the 400-line new-file
  cap.* The cap is about source modules: the ledger's own regeneration
  command reads `app/Sources/*.swift` and `core/src/*.rs` only, and this
  crate's test files run past 2 000 lines.
- *`without_nulls` duplicates `prune_removed`.* Same shape, different jobs
  — one copies a patch minus its nulls for a type read, the other removes
  those keys from the STORED end state — and they now sit in different
  modules for that reason.

**Mutants for the review fixes.** Three more, all caught: the walk moved
back behind the strip (1 test), `without_nulls` made the identity (2), and
`add_text_clip`'s snap removed (1).

**What the next tickets inherit.**

- The three sentence forms above are what D1·3's proof asserts over MCP.
- `merge_group` is the one read of a group patch. D1·2's end-state op and
  incomplete-filter refusal have the walk's path spelling to match, and the
  end-state op can reuse the kind check only against a template, since an
  end patch spans groups.
- **Range refusals are not indexed.** `props_check.rs` still spells a list
  entry as `video.filters[].amount` / `shape.gradient.stops[].at`, which
  names the field and the value but not which entry. Those refusals were not
  in this ticket's criteria, and `tools/proof/phase6_proof.py` asserts the
  `[]` spelling through the app. A ticket that wants indices there has to
  move that proof too.
- **A fraction where a tick count belongs** is refused by the walk, as serde
  already refused it. Any door that forwards raw JSON with tick values
  written as `600000.0` gets the refusal, not a rounding. D1·2's snap only
  moves whole-number ticks onto the frame grid.

**Documents.**

- Spec §6's row for the property patches now says a refusal names the path
  and the value, gives the three forms, and says a new clip's patch answers
  in the same words.
- Spec §7.10's dependency list, file tree and `edit_props.rs` row are
  updated.
- `edit.rs`'s op-table bullet says the same as spec §6.
- `core/CLAUDE.md`'s `edit_props.rs` entry names `merge_group`. Its "a patch
  of a nested object is a REPLACEMENT" was false about the core, which
  merges key by key, and now says so.

**Owed.** Nothing for this ticket.

### 2.2 D1·2 — what a patch may carry (kpgalligan/reelcut#3)

**Commits.** `a36314b` (the toll), `a5424cf` (the ticket) and `5157501` (what
its review found, below).

**What landed.** Core and documents only, again: the agent door still
decodes before the core does, until D1·3. Four changes to what a patch may
carry, and one toll paid first.

- **The toll.** `edit_props.rs` stood at 522 lines and this ticket owed it
  about another 150, so it gave something up first, as a pure move landed
  and gated alone: `Group` with its template, `check_keys`, `wrong_kind` and
  `merge_group` are now `core/src/patch.rs`. The seam is `props_check.rs`'s
  one step earlier — what a patch may CARRY is a fact about the vocabulary,
  not about an edit — and nothing in the new module is handed a clip or a
  project. Not one moved line differs.
- **A filter entry names both its keys.** `patch.rs`'s `COMPLETE_ENTRIES` is
  the rule and its argument: an array replaces its list, so an entry is
  merged over NOTHING and the keys it leaves out are completed from
  `Filter::default()` — a half-strength blur where the caller wrote "the
  same filter, more of it". `missing key "filters[0].kind" in a video patch`
  is the third sentence form the door gives, beside `unknown key` and
  `bad value at`. `video.obscure` and `shape.gradient.stops` are
  deliberately not in the list: their omitted keys leave an entry
  recognisably the thing the caller named, and the Swift handler this
  replaces made the rule for filters alone.
- **The end-state op walks like every other patch.** `set_action_end`
  refuses an unknown key, a wrong JSON kind and a misspelt variant, by a
  path carrying the group's name — `unknown key "video.filters[1].kindd" in
  an action end patch`. A `shape` object is an unknown key, because a shape
  is not animatable and the key would be stored, reported as success and
  animate nothing. What stays lenient is the VALUE: no range check, so
  `actions.rs`'s `clamp_video` is still the last line of defence and the
  phase-6 nest-blend back door still behaves exactly as its proof says. A
  `null` at any depth is still a REMOVAL, so it is stripped before the typed
  read rather than type-checked.
- **The ticks a patch carries are snapped.** `edit_props.rs`'s `snap_motion`
  and `snap_animation` put a motion preset's two edge durations, its
  `during` period and a text animation's `in` / `out` on the document's
  frame grid, so the core's own Times rule now holds for them and the
  comments in `props_check.rs` that said "the inspector snaps" are gone.
  They run AFTER the range check, which is the one ordering decision here:
  snapping first would turn a `duration` of −1 into a legal 0 and say
  nothing, where the check names what the caller sent. `period` is the one
  value with no zero — it divides in every `during` formula — so its snap
  floors at one FRAME rather than at the nearest boundary. The app is
  unaffected: `TextPane` already snaps both timings through
  `ReelTime.snapToFrame`, and the motion slots are a menu of KINDS whose
  durations come from the stored value or the type's default.
- **The zoom region is read like a patch.** `ZoomRegion`'s `Deserialize` is
  written out rather than derived. A missing and an unknown member were
  already refused by name (serde's own sentences), so that half of the
  ticket's criterion held before it was written and is now pinned. What was
  NOT refused is a region written as a four-number LIST, which serde read
  member by member in declaration order — the positional hole D1·1 closed
  inside a patch, still open at the one op argument shaped like one. A
  wrong-typed member names its path now too (`bad value at "region.width"`),
  where serde alone said only `invalid type: string "wide", expected f64`.

**Where the end-state door lives, and why not in `patch.rs`.** The walk and
the typed read of ONE group are `patch.rs`'s `check_group_patch`; WHICH
groups an end patch may name, and what a `null` in one means, are facts
about an action, so `edit_action.rs` composes the door out of that
primitive. `unknown_key` is exported beside it so that refusal has one
spelling rather than two. It also keeps `patch.rs` under the 400-line cap a
new file has — exactly 400, with `edit_action.rs` at 321 and `edit_props.rs`
down to 331 from 522. The next cut there, if one is ever forced, is
`Group` with its template: the vocabulary, where the rest of the file is the
reading.

**Tests.** Three new tests and five existing ones moved.

- `core/tests/patch_door.rs` gains the fixture's sixth door (an action on
  clip 11) and three tests: the incomplete filter entry at both doors and
  the complete entry that still lands; the end patch walked like every other
  patch (unknown key at depth with an index, `shape` as an unknown key, a
  wrong kind, a group that is not an object, and a misspelt variant at
  three depths); and what the end patch KEEPS (a sparse merge, `null`
  removing a key at depth including a required one, an out-of-range value
  still stored).
- `core/tests/schema_v8.rs` and `core/tests/schema_v5.rs` each gain a frame
  grid test beside the range checks they already own — an off-grid value
  landing on the grid, the period's frame floor, the negative value still
  named, and two identities (an on-grid rewrite and a sub-frame one that
  snaps onto what is stored). Both also pin that the FILE is not snapped.
- Five existing tests moved rather than being layered over.
  `schema_v2.rs`'s `a_partial_filter_entry_interpolates_and_then_takes_the_types_own_defaults`
  — the "known wart" — is now
  `a_partial_filter_entry_is_refused_at_the_door_and_completed_in_a_file`:
  it asserts the refusal at both doors and keeps the whole of the old
  behaviour for a patch written into a FILE, which is where the leniency
  now lives. Its neighbour, the filter budget test, spells its entries out
  and hands the "an omitted amount is the default" claim to that test.
  `edit_tests.rs`'s `set_action_end_merges_and_a_null_removes_a_key` asserts
  the refusal of `video.from_a_newer_build` where it used to assert the key
  was kept, and `model_tests.rs`'s `an_action_end_patch_keeps_the_keys_it_is_given`
  now round-trips that very key through a file, so the two halves of the
  promise name each other. `zoom.rs`'s
  `the_region_takes_four_named_numbers_and_only_those` asserts the member
  names instead of "the op is not valid".
- One test was WRONG rather than out of date, which is the ticket paying for
  itself: `scope.rs`'s op sweep sent
  `set_action_end {"patch": {"opacity": 0.0}}` — no group — and the op
  reported success and animated nothing for as long as it validated nothing.

**Measured.**

- `make test`: 632 passed, 0 failed (627 before).
- `make lint` and `cargo fmt --check`: clean.
- Line counts: `patch.rs` 400 (new), `edit_props.rs` 522 → 331,
  `edit_action.rs` 258 → 321, `edit_zoom.rs` 390 → 457, `edit_clip.rs`
  1038 → 1042 (the one call that makes a new text clip's animation snap;
  the file is back to the 1043 it stood at before D1·1 trimmed it).
- Four proof scripts green against the rebuilt app, with the startup parity
  log empty: phase2 85/85, phase3 121/121, phase4 84/84, phase6 167/167 —
  the four that touch filters, regions, end patches and text animations.
  They were run again after the review fixes.

**Mutants.** Nine, each run as `cargo test --release --no-fail-fast` so the
count is every failing test and not just the first failing binary. All
caught.

| Mutant | Failing tests |
|---|---|
| the filter completeness check disabled | 2 (`patch_door`, `schema_v2`) |
| `check_end_patch`'s result ignored | 4 (`patch_door` ×2, `schema_v2`, `edit_tests`) |
| `snap_motion` a no-op | 1 (`schema_v8`) |
| `snap_animation` a no-op | 1 (`schema_v5`) |
| the snap moved BEFORE the range check | 2 — the grid test and `schema_v8`'s `every_range_check_refuses_by_name`, which is the test that says a `duration` of −1 is still named rather than rounded into a legal 0 |
| `period`'s frame floor removed | 1 (`schema_v8`) |
| the region's "must be an object" removed | 1 (`zoom`) — the four-number list is read positionally again |
| `without_nulls` made the identity | 2 (`patch_door`, `edit_tests`) — a `null` reaches the typed read and a removal becomes a refusal |
| the completeness rule widened to EVERY list | 13, across `patch_door`, `schema_v4` and `schema_v6` — the measurement behind leaving `video.obscure` and `shape.gradient.stops` out of it: widening the rule is a behaviour change to two shipped vocabularies, not a tidy-up |

**The review** (standards and spec, in parallel, against the ticket and
spec #1).

Fixed:

- **An unknown key spelled with a `null` escaped the new door.** The end
  patch stripped its nulls BEFORE the walk, so `{"video": {"blurr": null}}`
  was dropped and answered as an identity rather than refused — the one
  thing a patch may never do (`CONTEXT.md`). The strip now lives inside
  `check_group_patch`, after the walk and before the typed read, which is
  where the two readings of a `null` actually part.
- **`add_text_clip` did not snap.** Spec #1 puts the snap "at the patch
  door", and a new clip's `text` is one of them. `snap_animation` is
  `pub(crate)` and `edit_clip.rs` calls it, so the two text doors land on
  the same grid.
- **Three sentences outside the diff were made false by it** and are
  corrected: `edit.rs`'s op table (an end patch "keeps what it does not
  know"), `model.rs`'s reader note ("kept as written by `set_action_end`")
  and `core/CLAUDE.md`'s `actions.rs` entry ("lenient by design"). The op
  table's `set_action_end` and `add_zoom_action` rows now say what spec §6
  says, which is the four-mirrors rule.
- **The Times rule was half kept.** The six audio ramp ticks
  (`audio.fade_in` / `fade_out`, the duck's and the compressor's attack and
  release) are not snapped and never were. They are envelope lengths
  sampled at the audio rate rather than positions in the picture — a 10 ms
  compressor attack quantised to a video frame rounds to nothing — so the
  rule in `core/CLAUDE.md` and `check_audio`'s doc now say so instead of
  leaving it unstated.
- **A field added to `Filter` would have joined the completeness rule** the
  day it landed and refused every patch an agent had already learnt to
  write. `COMPLETE_ENTRIES` spells `("filters", ["kind", "amount"])` rather
  than taking the template entry's keys.
- Three smaller ones: the `check_end_patch` doc link pointed at the module
  it had just left; `check_end_patch` re-spelled the three group names as
  string literals where `Group::name` owns them; and a `phase6_proof.py`
  docstring line ran past the file's wrap.

Judged not real:

- *`ZoomRegion`'s hand-written `Deserialize` is scope creep.* The ticket
  asks for the unknown and missing member, which serde already gave. The
  positional LIST read is the same defect D1·1 found and closed inside a
  patch, at the one op argument shaped like one, and spec #1's ninth user
  story asks for every such door to behave identically. Recorded as a
  deliberate addition rather than dropped.
- *`period`'s frame floor is not a snap.* A period of five ticks lands on
  one frame where the nearest grid point is zero. That is the point: the
  value has no zero (`props_check.rs` refuses one), so the smallest period
  on the grid is a frame.
- *`core/tests/patch_door.rs` is 597 lines, past the 400-line new-file
  cap.* The cap is about source modules: the ledger's own regeneration
  command reads `app/Sources/*.swift` and `core/src/*.rs` only, and this
  crate's test files run past 2 000 lines.
- *`without_nulls` duplicates `prune_removed`.* Same shape, different jobs
  — one copies a patch minus its nulls for a type read, the other removes
  those keys from the STORED end state — and they now sit in different
  modules for that reason.

**Mutants for the review fixes.** Three more, all caught: the walk moved
back behind the strip (1 test), `without_nulls` made the identity (2), and
`add_text_clip`'s snap removed (1).

**What the next tickets inherit.**

- **A fourth sentence form**, `missing key "<path>" in <subject>`, beside
  D1·1's three. D1·3's proof asserts all four over MCP.
- **The end patch's subject is `an action end patch`** and its paths carry
  the group (`video.filters[1].kind`). D1·5's proof asserts exactly that,
  and the ticket's "a misspelt variant refused with path and value" is what
  `check_group_patch`'s typed read gives.
- **Two proof scripts now say something false** and belong to the tickets
  that own their sections: `phase6_proof.py`'s "an end patch validates
  nothing but its shape" was corrected in place here (it is a comment, not
  an assertion), and the same file's Swift-worded refusals for the partial
  filter entry and the misspelt blend inside an end patch are still the
  Swift door's, because that door still runs first. They move in D1·3 to
  D1·5.
- **Range refusals are still not indexed** (D1·1's note stands):
  `props_check.rs` spells `video.filters[].amount`, and `phase6_proof.py`
  asserts that spelling. Nothing here made the index available there.
- **`paste_attributes` does not snap.** A payload written by hand can still
  carry a sub-frame motion duration or animation timing, because it is a
  copy of a stored group rather than a patch, and `check_group` only
  range-checks. The two doors that ARE patches — `set_video` / `set_text`
  and `add_text_clip` — both snap. The FILE reader does not snap either, deliberately: a file
  opens as what it says (`schema_v8.rs` states that rule for the long-hand
  motion).

**Documents.** Spec §5.4's leniency paragraph and the motion refusal
sentence, §6's preamble (the ticks a patch carries), the `set_video` row
(the filter entry, and "validates nothing" gone), the `set_action_end` row,
the `add_zoom_action` row (the region's refusals), the `actions.rs` row and
§7.10's `patch.rs`, `edit_props.rs` and `edit_action.rs` rows.
`core/CLAUDE.md`'s map entries for `patch.rs`, `edit_props.rs`,
`edit_action.rs`, `props_check.rs` and `edit_zoom.rs`. The two core comments
that said an end patch "validates nothing" (`actions.rs`, `edit_props.rs`)
and the two in `props_check.rs` that said "the inspector snaps".

**Owed.** Nothing for this ticket. The MCP proof of all of it is D1·3 to
D1·5's, by design: none of this is reachable through the agent door until
the Swift launder comes out.

### 2.3 D1·3 — `set_video` forwards the caller's patch (kpgalligan/reelcut#4)

**Commits.** `eb17289` (the ticket) and `439d083` (what its review found,
below).

**What landed.** The first door. `set_video` hands the core the object the
caller wrote, and an agent sees D1·1's and D1·2's work for the first time.

- **The handler is four lines.** `target` → `clipsArg` → `rawPatchArg` →
  `editResult`. What went: the decode into `VideoPatch`, the allowed-key set,
  `checkVideoEnums`' four closed vocabularies and its filter-completeness
  check, the `patch.isEmpty` refusal, and the whole of
  `AgentServer+Motion.swift` — 157 lines that read `motion` by hand because
  `patchArg` could not see two levels down.
- **`rawPatchArg`** (`AgentServer+Arguments.swift`) reads NOTHING about the
  value. Its one refusal is the ABSENT argument, which is a mistake about the
  CALL; a `null`, a number and a list are all forwarded, because
  `video patch must be a json object, not 5` names the group and this side
  would have to be told which one. It returns `Any`, not `[String: Any]`, so
  that stays true.
- **`ReelOp.setVideoRaw(clips:patch:)`** is the raw factory, beside the typed
  `setVideo(clips:patch:)` the inspector, the canvas sessions and Clip ▸
  Motion ▸ keep using. The paste payload factories (`paste`,
  `pasteAttributes`) are the precedent, and the rule they keep is why it is
  here: the op table stays the only place in the app where an op is spelled.
  **#5 and #6 copy this shape** — `patch: Any`, one `OpArgs.put`, the same
  op name.
- **The empty patch is the core's answer now.** `{}` used to be
  `patch names nothing to change.`; it is the identity refusal
  (`Video Properties made no change…`) since nothing on this side reads the
  object. No proof asserted the old sentence.

**What an agent sees change**, both named in the catalog:

- **A nested object MERGES.** `{"shadow": {"blur": 20}}` keeps the colour,
  the angle and the distance where the decode-and-re-encode replaced the
  whole object from defaults. `motion` is the loudest case: the MCP argument
  used to replace all three slots, so a patch naming `in` cleared a stored
  `out`. `MotionProps.dictionary` still writes three keys and is now the ONLY
  edge that does — the app's writers know all three slots, which is the same
  rule spelled out rather than a second one.
- **A colour is four numbers.** Nothing fills in an alpha
  (`bad value at "shadow.color" in a video patch: invalid length 3…`) and
  nothing clamps a component (`video.shadow.color must be between 0 and 1,
  not 2`). `colorArg`'s three-element form and its clamp are untouched: it
  has no video caller, and its callers — `set_canvas`'s background,
  `add_background_clip`'s colour and `set_shape`'s stroke, fill and stops —
  are #5's by that ticket's own criteria. So is `withOpaqueColors`, which
  `patchArg` still applies at the doors that have not moved.

**The proof is born.** `tools/proof/patch_door_proof.py`, **39/39**, exactly
400 lines (the cap a new file has, §0 — `patch.rs` landed on the same number), named for the SEAM and not for a phase. One section per door; this
one is the template, and a marked comment says where the next goes and what
has to change in the copy. Four helpers: `refused` (the sentence VERBATIM,
plus `get_project` identical either side), `landed` (a merge read back), and
`undo_marker` / `undo_claim`, whose pair is the stronger form of "a refusal
is not an undo step" — one real edit, then eleven refusals, then ONE undo
that has to put the project back. The fixture stores a shadow, a filter
stack and a motion BEFORE anything is refused, so every refusal names a key
the clip already has a value for and a door that dropped, cleared or
completed it would be making a real edit.

**Two other scripts said something that is no longer true.**
`phase6_proof.py`'s three `set_video` refusals asserted the Swift door's
`patch.`-prefixed key and went on passing after that door came out, because
a keyword check cannot tell the two apart; each is now the core's whole
sentence. `phase3_proof.py`'s printed NOTE that a misspelt key inside a
nested object is dropped is two CHECKS now, because it no longer is
(`obscure[0].amont` and `shadow.blurr`). The `set_action_end` refusals in
both files are still the Swift door's, until #6.

**Measured.**

- `make test`: 632 passed, 0 failed (no Rust changed). `make lint` and
  `cargo fmt --check` clean. `make typecheck` 0 errors and the 4 known
  warnings. `make app` succeeded; the startup parity log stayed empty across
  the whole proof run.
- Twelve proof scripts green against the rebuilt app: patch_door 39/39,
  phase1 66/66, phase2 85/85, phase3 123/123 (121 before, plus the two the
  note became), phase3_silence_scope 8/8, phase4 84/84, phase5 88/88,
  phase6 167/167, phase7 92/92, phase8 79/79, phase9 216/216,
  remaining 79/79. `recording_proof.py` is 186/187 with two counted
  host-state skips, and its one failure is the microphone file's length
  against the movie's on a host whose default output is a Bluetooth headset
  — that script never calls `set_video`.
- Line counts, after the review fixes below: `AgentServer+Clips.swift`
  1222 → 1205 (the toll: the handler lost fifteen lines of body, and
  `checkVideoEnums`' doc and its `blend` comment, which argue a function #6
  deletes, were cut to what governs them while they run),
  `AgentServer+Motion.swift` 157 → 0, `ReelOps.swift` 974 → 1008,
  `AgentCatalog+Clips.swift` 919 → 930, `AgentServer+Arguments.swift`
  554 → 587. That last one is the file to watch: it is the one #7 guts, and
  #5 and #6 add no reader to it, since they call `rawPatchArg`.

**Mutants.** Ten, each a rebuild of the app and a fresh instance on its own
port. Nine caught, one survivor with a reason.

| Mutant | Score |
|---|---|
| the Swift launder restored at `set_video` (decode through `VideoPatch`, typed factory) | patch_door **9/32, ABORTED**; phase3 120/123; phase6 164/167 |
| the core's key walk (`check_keys`) disabled | patch_door **29/39**; phase3 121/123; phase6 166/167 |
| `snap_motion` a no-op | patch_door **37/39** |
| the filter completeness rule disabled (`COMPLETE_ENTRIES` emptied) | patch_door **35/39**; phase6 166/167 |
| the path dropped from the typed read (`serde_path_to_error`'s path blanked) | patch_door **35/39**; phase3 122/123; phase6 165/167 |
| the colour range check (`color_ok`) disabled | patch_door **35/39** |
| a three-element colour laundered at the door again (`withOpaqueColors` back in `rawPatchArg`) | patch_door **35/39** |
| the deep merge made shallow (a nested object replaces) | patch_door **29/32, ABORTED** |
| `patch_clips`' "patch must be a json object" removed | patch_door **39/39 — SURVIVOR** |
| …and `merge_group`'s copy of it removed too | patch_door **38/39** |

The survivor is the one D1·1's review already argued: the sentence is
spelled twice, and both copies are needed — `patch_clips` checks before
resolving ids so an empty selection still refuses a non-object, and
`merge_group`'s copy guards the two new-clip ops. With a non-empty selection
the second answers in the identical words, so removing the first is
invisible from outside. Removing BOTH is caught: the walk answers instead,
with `bad value at "" in a video patch`, and the path is empty.

The two mutants D1·6 owes (the launder restored at one door, the key walk
disabled) are the first two rows above, run here against one door. #7 runs
them against all of them.

**The review** (standards and spec, in parallel, against the ticket and
spec #1). The spec axis found all eight of #4's criteria met, checked
against the code rather than the record, and the proof's 39 checks
reconstructed from its own structure. Everything below is the standards
axis's, plus two imprecisions the spec axis found in sentences this ticket
wrote.

Fixed:

- **Three sentences inside the files this ticket edited were made false by
  it.** `checkVideoEnums`' `blend` comment still said "`set_video` refuses
  `patch.blend` by name before this function is ever called" and counted
  "the two doors that round trip does not reach"; `patchArg`'s doc still
  opened "A patch object (`set_video` and its siblings) decoded into its
  typed Swift form"; and `videoPatchKeys`' doc still offered "let the core's
  lenient serde drop it" as the alternative. Each now names the doors that
  still launder and the ticket that takes them. This is the third ticket in
  a row whose review found exactly this, which is worth saying plainly: the
  sentence a deletion falsifies is usually in the file the deletion did not
  quite reach.
- **The op table's "one factory per row" is now "one typed factory per row,
  plus a raw one at each door D1 has moved".** `ReelOps.swift`'s module doc,
  `ReelOp.json`'s doc (a raw factory cannot carry a non-JSON value either:
  its argument came out of a parsed JSON-RPC call), `app/CLAUDE.md`'s
  `ReelOps.swift` entry and spec §7's "no untyped call site outside those
  two files" paragraph. The root rule — the table is the only place an op
  is spelled — is what the raw factory exists to keep, and it now says so.
- **`designs/reelcut-app-notes.md` described a DELETED file in the present
  tense.** Its body is a verbatim archive and is not edited, so the fix is
  one sentence in its own header: a file it describes may since have been
  deleted, and `app/CLAUDE.md`'s map is the list of files that exist.
- **The catalog over-promised the motion snap.** It said the two durations
  and the period are snapped "so what you send back is what get_project
  gives"; `period` FLOORS at one frame, so a period of 5 comes back as a
  whole frame. The sentence now says so, which §5.4 and the proof already
  did.
- **The proof's own docstring over-claimed its fixture.** "Every refusal
  below names a key the clip already has a value for" is not true of
  `spotlight.shape` or of the unknown `blurr`, which discriminate on the
  sentence alone; it now says which is which.
- The proof script was 408 lines against §0's 400-line cap for a new file,
  and its docstring was the place to pay it. It is 400 now.

Judged not real:

- *The `set_action_end` catalog entry says its groups have "the same keys as
  set_video", and that door still fills in a three-element colour.* True,
  and it is #6's door with #7 owning the catalog's remaining
  `[r, g, b]` sentences (spec #1's Documents decision). The promise is about
  KEYS, and the leniency that remains is a colour ACCEPTED where four are
  wanted, never a wrong picture.
- *`rawPatchArg` is a five-line Middle Man.* It is the seam #5 and #6 copy,
  and it holds the one refusal that is not the core's — the argument being
  absent. Inlining it would put that sentence at eight doors.
- *`patch_door_proof.py` at the 400-line cap.* §2.1's review already read
  the cap as being about source modules; this one lands on the number
  anyway, so the reading is not being leaned on.

**What the next tickets inherit.**

- **The raw factory's shape**, to copy verbatim: `static func
  set<Group>Raw(clips: [UInt32], patch: Any) -> ReelOp`, `patch` typed `Any`
  so a non-object reaches the core, one `a.put("patch", patch)`, the same op
  name as the typed factory beside it. `add_zoom_action`'s region is the one
  that will not fit the mould exactly — the region is an ARGUMENT, not a
  patch — and takes `region: Any` beside its other arguments.
- **The proof's section shape**, also verbatim: a `<door>_door(mcp)`
  function, a fixture that STORES a value for every key the refusals name,
  then `undo_marker` → the refusals → `undo_claim` → the merges → the snap.
  One line in `main`. The marker comment in the file names the doors owed.
- **A refusal is asserted as the whole sentence, never by keyword.** A
  keyword check passes against both doors, which is exactly how three
  phase-6 assertions survived D1·3 meaning nothing.
- **`checkVideoEnums` still runs**, from `checkActionPatch` alone. So do
  `patchArg`, `withOpaqueColors`, `colorArg`'s conveniences and the four
  allowed-key sets. #7's deletion list is unchanged by this ticket.
- **Three sentences outside this ticket's diff were false and were
  corrected** (listed under Documents): the biggest is spec §5.4's "the
  ticks are NOT snapped by the core", which D1·2 falsified and did not
  catch, and which §6's own preamble already contradicted.

**Documents.** Spec §5.4's motion paragraph (the snap, the period's frame
floor, and that a FILE is not snapped), §6's `set_video` row (the motion
sentence: it merges, and only the app's writers send the whole object),
§7.4's `MotionProps.swift` row, and §7.4's `AgentServer+Motion.swift` row,
deleted with the file. `app/CLAUDE.md`'s `AgentServer` family list (no
`Motion`), its `MotionProps.dictionary` note and its
`AgentServer+Arguments.swift` entry, which now leads with `rawPatchArg` and
says which doors still launder. The catalog's `set_video` description and
`videoPatchDescription` (merge at every depth, a list replaces, four-number
colours) and `motionClause` (merge, and the frame-grid snap).
`ReelCore.swift`'s `VideoPatch.motion` doc, `MotionProps.swift`'s
replace-whole paragraph, and `tools/proof/README.md`, which gains the new
script in the run list and a section of its own.

**Owed.** Nothing for this ticket. The other doors are #5 and #6 by design.

### 2.4 D1·4 — the remaining property doors forward raw (kpgalligan/reelcut#5)

**Commits.** `7144586` (the proof's harness, alone), `07a75eb` (the ticket)
and `f9b5276` (what its review found, below).

**What landed.** Eight doors, all of them copying D1·3's shape. Every
caller-authored object the agent can send is now the core's to read, bar
`set_action_end`'s and `add_zoom_action`'s (#6).

- **Five handlers are four lines.** `set_audio`, `set_text`, `set_clip` and
  `set_shape` are `target` → `clipsArg` → `rawPatchArg` → `editResult`, and
  `add_text_clip` / `add_shape_clip` are the same with `newClipPatchArg` in
  place of the third step. What went with them: `shapePatchArg` (all eleven
  keys by hand, three-state `stroke` and `fill` included), `gradientArg`
  (the gradient and every stop), `unitPoint`, `checkClipPatchTypes`,
  `textArg` and `shapeArg`, the `shapePatchKeys` and `clipPatchKeys` sets,
  three `patch.isEmpty` refusals and two `checkTextEnums` call sites —
  **194 lines out of `AgentServer+Clips.swift`** (1205 → 1011).
- **`colorArg` and `requiredColorArg` are deleted**, which is the payment
  `AgentServer+Arguments.swift` owed at 587 against the ~600 cap: it is 558,
  and #5 added no reader to it, exactly as §2.3 said it would not. Their
  three callers were all this ticket's. `set_canvas`'s `background` and
  `add_background`'s `color` are now `a["background"]` and `a["color"]`,
  forwarded whole — an explicit `null` included, which the core reads as
  absent under the envelope's own rule.
- **Nine raw factories** in `ReelOps.swift` (974 → 1090, a table with
  `edit.rs`'s standing exemption). Five are `setVideoRaw`'s five lines with
  another op name. The other four differ from their typed twin in ONE
  argument — a colour, or a new clip's patch — so the TYPED factory delegates
  to the raw one rather than keeping a second copy of seven `OpArgs.put`
  lines, mapping its optional explicitly: an `Optional<T>.none` widened
  straight to `Any?` is a non-nil `Any` wrapping a nil, and the key would go
  out as a null.
- **The bare-string shorthand stays** and is one reader for both new-clip
  ops (`newClipPatchArg`, 7 lines against the 46 `textArg` and `shapeArg`
  were). It PRODUCES `{"content": …}` or `{"kind": …}`, which is then
  forwarded; it judges nothing, so a bare `"square"` is the core's
  ``bad value at "kind" in a shape patch: unknown variant `square` ``.

**What an agent sees change**, all three in the catalog now:

- **A nested object MERGES at these doors too.** `{"duck": {"level": 0.7}}`
  keeps the attack and the release; `{"outline": {"width": 8}}` keeps the
  colour; `{"gradient": {"angle": 90}}` keeps the stops it was drawn with,
  where `gradientArg` replaced the whole gradient from `Gradient::default()`.
  The catalog's `animationClause` and `gradientClause` said "REPLACED whole
  rather than merged" in so many words; both now say what happens.
- **A colour is four numbers everywhere.** The three-element form is refused
  by length and an out-of-range component by name, at a patch key
  (`bad value at "outline.color" in a text patch: invalid length 3`), inside
  an array of objects (`gradient.stops[0].color`, which `withOpaqueColors`
  could never reach) and at the two colour-only ARGUMENTS
  (`canvas background must be between 0 and 1, not 2`,
  `shape.fill must be between 0 and 1, not 2` — the plate is a shape clip,
  so its own group answers and there is no second range rule to keep in
  step). `colorProperty`'s schema is `minItems: 4` rather than 3.
- **A wrong-typed `set_clip` key is refused rather than read as a clear.**
  `{"label": 7}` was `.some(nil)` through the lenient decode and REMOVED the
  label; it is `"label" in a clip patch must be a string or null, not 7`.

**The proof is 199/199** (39 before), and it is four files. D1·3 landed it at
400 lines exactly and eight sections is four hundred more, so the sections
split by kind and the harness went FIRST, alone, as a pure move:

| File | Lines | What is in it |
|---|---|---|
| `patch_door.py` | 196 | the harness: `Session`, `refused`, `landed`, `undo_marker`, `undo_claim`, `marker_gone`, `summary` |
| `patch_door_patches.py` | 519 | the five doors whose object is a PATCH |
| `patch_door_args.py` | 250 | the four whose object is an ARGUMENT |
| `patch_door_proof.py` | 104 | what a patch means, the sentence forms, and `main` |

**The 400-line cap is about SOURCE modules, and `tools/proof/` is not held
to it** — the reading §2.1's review settled and §2.3's repeated, and the
directory proves it: twenty-five of its twenty-nine scripts are past 400 and
`phase6_proof.py` is 1765. So `patch_door_patches.py` at 519 is not a debt,
and the splits above were taken for NAVIGATION rather than to satisfy a
number: a reader asking what `set_shape` answers opens one file, the doors
arrive one ticket at a time so the file that grows is not the one holding
the explanation, and the harness went first and alone because a pure move is
how this repo takes any split. D1·3 landing the script on 400 exactly was a
courtesy to a rule that does not bind it, not a precedent.

The split by KIND is not cosmetic: an argument door's refusals are the op
ENVELOPE's (`op "set_canvas" is not valid: invalid length 3, expected an
array of length 4`) rather than the patch walk's, because there is no group
to name, so its section is a different copy from a patch door's and the two
marker comments say which one #6 should take for each of its doors. Section
order is D1·3's throughout: fixture first — the clip must HOLD a value for
every key a refusal names, or "the project is unchanged" proves nothing —
then the undo marker, the refusals, the undo claim, the merges, the snap.

**Three older scripts said something that is no longer true**, and each was
moved to the core's WHOLE sentence rather than to a keyword, which is the
rule §2.3 left behind: `phase2_proof.py`'s three `set_clip` typos (two of
them asserted `patch.label` / `patch.name`, which the core does not say, so
those two were red rather than quietly passing); `phase4_proof.py`'s two
text-animation kinds (both keyword checks, both green against either door);
and `phase6_proof.py`'s three gradient refusals. Phase 6 also had a CLAIM
this ticket reverses — "a THREE-component stop colour is accepted and means
the four-component one, byte for byte" — which is a refusal now, and one
check longer for it (167 → 168). Its identity check moved with it: what the
clip still holds after the refusal is the UNSORTED pair sent before it, so
that is what re-sending is the identity of.

**Measured.**

- `make test`: 632 passed, 0 failed (no Rust changed). `make lint` and
  `cargo fmt --check` clean. `make typecheck` 0 errors and the 4 known
  AVFoundation warnings. `make app` succeeded; the startup parity log stayed
  empty across every run.
- Twelve proof scripts green on port 4824 — patch_door **199/199**, phase1
  66/66, phase2 85/85, phase3 123/123, phase3_silence_scope 8/8, phase4
  84/84, phase5 88/88, phase6 **168/168**, phase7 92/92, phase8 79/79,
  phase9 216/216, remaining 79/79. `recording_proof.py` is 121/121 with 66
  checks SKIPPED, the console being locked on this host; it calls none of
  these doors.
- Line counts: `AgentServer+Clips.swift` 1205 → 1011,
  `AgentServer+Arguments.swift` 587 → 558, `AgentServer+Tracks.swift`
  231 → 242, `AgentServer+Background.swift` 89 → 99, `ReelOps.swift`
  974 → 1090, `AgentCatalog+Clips.swift` 930 → 939, `AgentCatalog.swift`
  465 → 472. `designs/reelcut-remaining.md` §3's table is regenerated, which
  is the first time since road map 3.
- **An instance deadlocks somewhere past forty open documents**, and this
  ticket hit it: phase5 aborted at 48/88 with a peaks marker never written
  and phase6 then timed out, on an instance that had already run six
  scripts. Both were green on a fresh one. Relaunch between scripts, not
  only between sessions.

**Mutants.** Ten, each a rebuild of the app and a fresh instance on port
4824. All ten caught; no survivor.

| Mutant | Score |
|---|---|
| `set_audio` laundered again (`patchArg` + the typed factory) | patch_door **177/189** |
| `set_text` laundered again (`patchArg` + `checkTextEnums`) | patch_door **173/189**; phase4 83/84 |
| `set_clip` laundered, with the deleted type check NOT restored | patch_door **130/139, ABORTED**; phase2 79/85 |
| `colorArg` restored at the two colour-only arguments | patch_door **175/189** |
| both bare-string shorthands dropped | patch_door **151/151, ABORTED** |
| `snap_animation` made a no-op | patch_door **188/189** |
| the core's key walk (`check_keys`) disabled | patch_door **118/151, ABORTED**; phase3 121/123 |
| the deep merge made shallow (a nested object replaces) | patch_door **29/32, ABORTED** |
| `Group::Shape`'s template loses its `Gradient::default()` | patch_door **184/189**; phase6 ABORTED on an unhandled refusal |
| **D1·4's whole Swift half reverted** (the four files at `HEAD`) | patch_door **79/121, ABORTED**; phase2 82/85; phase4 82/84; phase6 163/168 |

The last row is the one #7 owes against every door at once, run here against
these eight; the first four are the same mutant aimed at one door each, which
is what says a section is discriminating rather than the batch. The one that
scores highest — `snap_animation`, at 188/189 — is a one-check claim by
construction, and that is the right size for it: the snap is one value.

**What the next ticket inherits.**

- **The raw factory's shape, in its second spelling.** A door whose
  caller-authored object is the WHOLE argument copies `setVideoRaw`; a door
  where it sits beside ordinary arguments (`add_zoom_action`'s `region`)
  copies `setCanvasRaw` — the raw factory holds the body and the typed one
  delegates with an explicit `.map { $0 as Any }`.
- **A colour is four numbers at every door**, and `colorArg` no longer
  exists to be called. #6's `set_action_end` reaches colours through
  `patchArg`'s `withOpaqueColors`, which is the last launder standing and
  is #7's to delete.
- **What is left uncalled after this ticket**, for #7's sweep: `patchArg`,
  `decodePatch` and `withOpaqueColors` (one caller, `set_action_end`);
  `checkVideoEnums`, `checkTextEnums` and `checkActionPatch` (the same one);
  `videoPatchKeys`, `audioPatchKeys` and `textPatchKeys` (read by
  `checkActionPatch` alone). Nothing this ticket left is dead today.
- **The proof's four files**, and the two marker comments that say which
  file each of #6's doors goes in.

**Documents.** `app/CLAUDE.md`'s `ReelOps.swift` entry (the nine raw
factories, and the delegation rule), its `ProjectSnapshot.swift` entry (ONE
handler still checks by hand) and its `AgentServer+Arguments.swift` entry
(no `colorArg`, and `patchArg`'s one remaining door). The catalog's
`colorProperty`, `textPatchDescription`, `shapePatchDescription`,
`animationClause` and `gradientClause`, plus the comment above the last of
those, which claimed the gradient was the only nested object that named its
own mistakes — true when phase 6 wrote it, false since D1·1.
`tools/proof/README.md`'s patch-door section (the four files, the new
sections, the older scripts' moved assertions).
`designs/reelcut-app-notes.md`'s header, which warned that a FILE it
describes may since have gone and now warns about a function too, naming the
family D1 deleted. Nothing in `designs/reelcut-design.md` needed changing:
§6's patch row and §7's raw-factory paragraph were both written generally by
D1·3, and no spec sentence promised a three-element colour.

**Where a criterion could not be met literally.** #5's first criterion asks
for "a misspelt variant, an unknown nested key and a wrong-typed value" at
each of the eight doors, and four of them have no such thing to get wrong:
`set_audio`'s group holds no enum at all, `set_clip`'s patch is two flat
strings with no nesting and no enum, and the two colour-only arguments have
neither. Each section covers every shape that EXISTS at its door and says in
its docstring which are missing and why, which is the honest reading of the
criterion.

**The review** (standards and spec, in parallel, against #5 and spec #1).
The spec axis found all eight criteria substantively met and nothing wrong;
everything below is what the two axes asked for and it landed in the
follow-up commit.

Fixed:

- **`withOpaqueColors`' doc was the sentence this deletion left behind** —
  the fourth ticket running to have one, which is worth saying again. Its
  whole justification was "the patch-shaped half of what `colorArg` does for
  a flat argument … `set_canvas`'s background and every `set_shape` colour go
  through `colorArg` and take three components", and this ticket deleted
  `colorArg` and both of those doors' leniency. It now says what it is: the
  LAST launder standing, the one door where three components are still taken,
  and #6/#7's to delete. Four more were found the same way before the review
  ran — `patchArg`'s caller list, `ReelOp.setClip`'s "the agent reads it
  through the same `patchArg`", `AgentServer+Background.swift`'s module doc
  ("grows again this phase for the gradient reader"), and
  `AgentServer+Clips.swift`'s ("the typed builders in `ReelCore.swift` are the
  only place that spells one", wrong on two counts).
- **Duplicated Code in the op table.** Four ops took the delegation rule and
  five did not: `setVideo`, `setAudio`, `setText`, `setShape` and `setClip`
  each kept a five-line body identical to their raw twin's but for
  `patch.dictionary`. All five delegate now, so a row really does have one
  body, and `setClipRaw` moved above `setClip` to match the other four.
- **`audioPatchDescription` was the one patch vocabulary not corrected.** The
  handler's own comment says the audio door's whole win is that a `duck` or a
  `compressor` MERGES; the agent reading the tool was never told.
- **Two readings of an explicit null in one ticket.** `newClipPatchArg`
  stripped an `NSNull` while the two colour arguments forwarded theirs. Both
  end in the same place — `Option<Value>` and `Option<Color>` each read a
  `null` as absent — so the stripping went, and all three doors now forward
  what the caller wrote.
- **The proof's own duplication**, which the standards axis was right to call
  out on a file whose whole subject is duplication: the sentence "…the marker
  edit itself is gone" was written out at six sites and is `marker_gone` in
  the harness now.
- **Two more refusals per new-clip door**, the spec axis's one partial: an
  unknown key inside a nested object and a number where that object belongs
  were proved at `set_text` and `set_shape` but not at `add_text_clip` and
  `add_shape_clip`. 189 → 197.
- **One behaviour change was documented and not asserted**: a `set_canvas`
  carrying nothing but `background: null` is the core's identity refusal
  where it used to be the handler's "nothing to change". §8d pins it. 197 →
  199.

Judged not real:

- *`patch_door_patches.py` is 519 lines against §0's 400-line cap for a new
  file.* The cap is about source modules, as §2.1's review settled — the
  argument is three paragraphs up, with the directory's own numbers.
- *`checkVideoEnums` and `checkTextEnums` still exist.* #5's criterion is
  "no enum, key or type checking FOR THESE GROUPS", and all five handlers
  are `rawPatchArg` plus a raw factory. Both functions run from
  `checkActionPatch` alone, which is #6's door.
- *`AgentCatalog+Clips.swift` still says `[r, g, b]` once.* That is
  `chroma.key`, which the core really does spell with three numbers
  (`model_props.rs`: `pub key: [f64; 3]`), and the sentence beside it now
  names it as the one exception.

**Owed.** Nothing for this ticket. `set_action_end` and `add_zoom_action`
are #6 by design, and the deletion sweep is #7's.

### 2.5 D1·5 — the end-state and region doors forward raw (kpgalligan/reelcut#6)

**Commits.** _(filled in below when they land.)_

**What landed.** The last two doors, and with them the last hand check in
any handler. Every caller-authored object the agent can send is now the
core's to read.

- **`set_action_end` is four lines** — `target` → `clipArg` → `actionArg` →
  `rawPatchArg` → `editResult` — and it is the door that gave up the most
  per line. What went with it: `checkActionPatch` (the three groups, each
  against its own allowed-key set, plus the `video.motion` refusal),
  `checkVideoEnums` (four closed vocabularies and the filter-completeness
  check), `checkTextEnums`, the `videoPatchKeys` / `audioPatchKeys` /
  `textPatchKeys` sets, the `patch.isEmpty` refusal and the `patchArg` call
  — **164 lines out of `AgentServer+Clips.swift`** (1011 → 847), which is
  what §3 of `designs/reelcut-remaining.md` records against the file.
- **`add_zoom_action`'s region is forwarded whole.** `zoomRegionArg` read
  the four members one at a time through `nestedNumberArg` and refused an
  unknown one by name; it is eight lines now and reads NOTHING about the
  value. The one judgement it keeps is the ABSENT key, and that one is not
  a mistake about the call the way `rawPatchArg`'s is — the op reads an
  absent argument and an explicit null identically, so a forgotten
  rectangle would be a zoom BACK, the opposite edit.
- **Two raw factories**, `setActionEndRaw` and `addZoomActionRaw`
  (`ReelOps.swift` 1090 → 1131, on its standing table exemption). The first
  is `setVideoRaw`'s five lines with another op name; the second is
  `setCanvasRaw`'s shape — the raw factory holds the body and the typed one
  delegates — because a region sits BESIDE ordinary arguments. Its `region`
  is `Any` and not `Any?`: both callers always have a value to send,
  `NSNull` for the zoom back, and an `Optional<ZoomRegion>.none` widened to
  `Any?` would be a non-nil `Any` wrapping a nil.
- **One core change, and it is a sentence rather than a rule.**
  `serde_path_to_error` prints the ROOT of a path as `"."`, not as the
  empty string, so a region missing a member read
  ``bad value at "region..": missing field `height` `` — a path no caller
  can act on. `ZoomRegion::deserialize` collapses both spellings onto `region`
  now, and `core/tests/zoom.rs` asserts the whole sentence where it used to
  assert ``missing field `height` `` alone. Everything else the two doors
  needed was already in the core: D1·2 built `check_end_patch` over
  `patch.rs`'s `check_group_patch` and wrote `ZoomRegion`'s `Deserialize`
  out by hand, and this ticket only had to stop the Swift side from
  answering first.

**What an agent sees change.**

- **The end patch's refusals name the GROUP in the path** and say
  `an action end patch`: `unknown key "video.filters[1].kindd" in an action
  end patch`, where this side said `Unknown patch.video key "kindd" — allowed
  keys are blend, chroma, color, …`. A misspelt filter kind, blend,
  spotlight shape or text animation kind is ``bad value at "<path>" in an
  action end patch: unknown variant `glow`, expected one of …``.
- **Three things that used to LAND do not** (all measured against the build
  at `09879b8`): `{"video": {"shadow": 5}}` was `.some(nil)` through
  `ActionPatch`'s lenient decode and REMOVED the shadow the action was
  animating, answering ok; `{"video": {"shadow": {"color": [1,0,0]}}}` had
  its alpha filled in by `withOpaqueColors`, the last door where a
  three-element colour was taken; and `{"audio": {"fade_in": 0.5}}` decoded
  to nothing at all and came back as "made no change".
- **A nested object MERGES.** `{"video": {"shadow": {"blur": 40}}}` keeps
  the colour, the angle and the distance; the old door decoded the whole
  group and re-encoded it, so the same call replaced the shadow from
  `ShadowProps`' defaults (measured: `opacity` 0.8 → 0.5, `distance` 30 →
  8).
- **An empty patch is the core's identity answer** rather than this side's
  "patch names nothing to change" — the same move `set_canvas`'s
  `background: null` made in D1·4.
- **The region's members answer in the envelope's sentence**:
  ``op "add_zoom_action" is not valid: bad value at "region.widht": unknown
  field `widht`, expected one of `x`, `y`, `width`, `height` ``, and a
  four-number LIST is `expected an object, not [0,0,480,270]` rather than a
  rectangle nobody spelled.

**The proof is 258/258** (199 before), still four files, with one section per
door and one line each in `main`:

| File | Lines | What changed |
|---|---|---|
| `patch_door.py` | 196 | untouched — the harness was complete |
| `patch_door_patches.py` | 695 | §10, `set_action_end`, the sixth and last patch door |
| `patch_door_args.py` | 341 | §11, `add_zoom_action`'s region, copied from §8 |
| `patch_door_proof.py` | 112 | the two imports, the two `main` lines, and the docstring's counts |

§10's order is D1·3's throughout, and its fixture is the reason the
"unchanged" half of `refused` bites: the action's end state holds a shadow, a
sepia filter, a blend, a spotlight, a fade and an animation before anything
is refused, so a door that dropped, cleared or corrected a key would be
merging a real edit. §11 copies §8 rather than §6, as D1·4's marker comment
said it should: a region is an argument the core reads as a TYPE, so its
refusals are the envelope's. Both files' foot markers now say there is no
door OWED and what a later phase's door would copy.

**Two older assertions moved to the core's wording**, which is the rule §2.3
left behind — the whole sentence, never a keyword. `phase6_proof.py`'s two
`set_action_end` refusals asserted `patch.video.filters[0]` and
`patch.video.blend`, spellings the core does not use, so both were RED
against the new door until they were moved (168/168 either way once moved).
`phase3_proof.py`'s region check asserted the word `region` appeared in the
refusal — true of every refusal at that door, before and after — and asserts
the whole of `Missing required argument: region` now, the one judgement the
handler kept.

**Measured.**

- `make test`: 632 passed, 0 failed. `make lint` and `cargo fmt --check`
  clean. `make typecheck` 0 errors and the 4 known AVFoundation warnings.
  `make app` succeeded; the startup parity log stayed empty across every
  run.
- Twelve proof scripts green on port 4825 — patch_door **258/258**, phase1
  66/66, phase2 85/85, phase3 **123/123**, phase3_silence_scope 8/8, phase4
  84/84, phase5 88/88, phase6 **168/168**, phase7 92/92, phase8 79/79,
  phase9 216/216, remaining 79/79. `recording_proof.py` is **185/186** with 3
  checks SKIPPED on this host, and the one failure is a MICROPHONE
  head-loss measurement that fails identically across runs (a flakier first
  run put three of the mic rows red); it calls neither of this ticket's
  doors — `grep -c "set_action_end\|add_zoom_action"` on it is 0 — so it is
  host state, not this change.
- Line counts: `AgentServer+Clips.swift` 1011 → **847**,
  `AgentServer+Arguments.swift` 558 → 562, `ReelOps.swift` 1090 → 1131,
  `AgentCatalog+Clips.swift` 939 → 945. The two that GREW and are over the
  cap are both mirrors: `ReelOps.swift` is the op table, exempt, and
  `AgentCatalog+Clips.swift`'s six lines are the `set_action_end`
  description's, the sentences this ticket made true (D1·4 added nine for
  the same reason). `AgentServer+Arguments.swift`'s four lines are doc on
  four functions #7 deletes, so the file's next move is down by about a
  hundred.
- `designs/reelcut-remaining.md` §3's table is regenerated: still thirty
  files, with `AgentServer+Clips.swift` down two rows.

**Mutants.** Seven, each a rebuild of the app and a fresh instance on port
4825. All seven caught; no survivor.

| Mutant | Score |
|---|---|
| `set_action_end` laundered again (`patchArg` + the typed factory) | patch_door **215/238, ABORTED**; phase6 166/168 |
| the region's hand reader restored (four members read, unknown ones dropped) | patch_door **251/256, ABORTED**; phase3 123/123 |
| the core's `check_end_patch` made a no-op | patch_door **229/258**; phase6 166/168 |
| the `video.motion` refusal deleted from `set_action_end` | patch_door **252/258** |
| `prune_removed` made a no-op (a null stops removing) | patch_door **256/258** |
| the region's root-path fix reverted (`region..` again) | patch_door **257/258** |
| **D1·5's whole Swift half reverted** (both files at `09879b8`) | patch_door **219/238, ABORTED**; phase3 123/123; phase6 166/168 |

Two rows are worth reading rather than counting. **phase3 stays green under
the region mutants**, and that is the honest reason §11 had to exist: its
only region assertion is about the absent KEY, which a laundering door
refuses too, so nothing outside the patch door discriminates a member the
handler quietly dropped. And the last row scores 219 rather than 0 because
the run ABORTS — an op that unexpectedly succeeds throws where a check was
waiting for a refusal — which is the shape §2.4 saw too: an aborted score is
a failure, and the number before it says how far the script got.

**What the next ticket inherits.**

- **Nothing is owed a door.** Every op that takes a caller-authored object
  forwards it, and both proof files' markers say so.
- **What is left UNCALLED after this ticket**, for #7's sweep, all four in
  `app/Sources/AgentServer+Arguments.swift` and each with a doc saying so:
  `patchArg`, `decodePatch`, `withOpaqueColors` and `nestedNumberArg`. The
  three that #5 listed in `AgentServer+Clips.swift` — `checkActionPatch`,
  `checkVideoEnums`, `checkTextEnums` — and the three key sets are gone
  HERE rather than left, because they lived in the handler file and the
  ticket's criterion was that the handlers hold no action-patch check.
- **The two mutants #7 owes** are spec #1's: the launder restored at one
  door (this ticket ran it at two, rows 1 and 2) and the core's key walk
  disabled (D1·4 ran it, at 118/151 ABORTED). Both are now measurable
  against every door at once.

**Documents.** `app/CLAUDE.md`'s `ReelOps.swift` entry (eleven raw factories,
and why `addZoomActionRaw`'s region is `Any` and not `Any?`), its
`ProjectSnapshot.swift` entry (NO handler checks a caller's enums or types by
hand any more) and its `AgentServer+Arguments.swift` entry (every door is
through; the four uncalled functions named for #7). The catalog's
`set_action_end` description, which said the patch "merges into it" without
saying at what depth and promised nothing about colours. `tools/proof/
README.md`'s patch-door section (the two files' new sections, the two doors
that answer in their own way, the moved assertions).
`designs/reelcut-app-notes.md`'s header, whose list of what D1 deleted grew
by six names. Nothing in `designs/reelcut-design.md` needed changing: §6's
`add_zoom_action` row already said the region is read the way a patch is
(D1·2 wrote it), §6's `set_action_end` row already said the end patch is
walked, and §7's raw-factory paragraph was written generally by D1·3.

**Where a criterion could not be met literally.** #6's fifth criterion says
the phase-3 region assertion moves "to the core's wording". It could not:
the assertion is about an ABSENT region, which is the one refusal the
handler still makes and must, since the core cannot tell an absent argument
from an explicit null and here they are opposite edits. It was moved from a
keyword to the whole sentence instead, which is the rule behind the
criterion, and the core's own region wording is asserted in §11 of the patch
door.

**Owed.** Nothing for this ticket. The deletion sweep, the rule in the app
rulebook and the spec's agent section, and the two proof mutants are #7's by
design.
