# Reelcut — road map 7: deepening

**Status: BOTH CANDIDATES BUILT AND CLOSED. D1** — all six tickets landed
(§2.1 to §2.6), and §3 is what they add up to: the core is the one validator
of every caller-authored object, and 617 lines are out of the agent's
handlers. **D2** — all five landed on `d2-refusal-reason` (§5.1 to §5.5), and
§6 is what they add up to: an identity and a refusal are two different
answers, eleven rules say why in their own words, and the app has no way to
write a refusal sentence at all. §6 also says where a next candidate starts.**

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
(§1, §4), the record ticket by ticket (§2, §5), and what a closed candidate
added up to (§3, §6).

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

**Commits.** `d8b9c58` (the ticket) and `8c156da` (what its review found,
below).

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
  answering first. The review then found the same join written twice and
  made `patch.rs`'s `path_under` the one implementation of it, which is why
  `patch.rs` is 400 → 414 and the region reads its path through the patch
  module.

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

**The proof is 261/261** (199 before), still four files, with one section per
door and one line each in `main`:

| File | Lines | What changed |
|---|---|---|
| `patch_door.py` | 196 | untouched — the harness was complete |
| `patch_door_patches.py` | 709 | §10, `set_action_end`, the sixth and last patch door |
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
- Twelve proof scripts green on port 4825 — patch_door **261/261**, phase1
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
  `AgentCatalog+Clips.swift` 939 → **941**, `ReelCore.swift` 1508 → 1508,
  `core/src/patch.rs` 400 → 414. `ReelOps.swift` is the op table and exempt.
  `AgentServer+Arguments.swift`'s four lines are doc on four functions #7
  deletes, so its next move is down by about a hundred.
  **`AgentCatalog+Clips.swift`'s two lines are an unpaid toll and are named
  as one**: it is over the cap, it is a MIRROR of the op table but has no
  standing exemption (§3 of `designs/reelcut-remaining.md` grants one to
  `edit.rs` and `ReelOps.swift` alone), and what it took on is the
  `set_action_end` description saying what is now true — the merge depth
  (spec #1 US25), the four-number colour (US10) and the refusal's shape
  (US18). The review made the whole description one line SHORTER per fact
  than the first draft; two lines is what is left, and the next phase to
  touch that file pays or takes the exemption on purpose.
- `designs/reelcut-remaining.md` §3's table is regenerated: still thirty
  files, with `AgentServer+Clips.swift` down two rows.

**Mutants.** Seven, each a rebuild of the app and a fresh instance on port
4825. All seven caught; no survivor.

| Mutant | Score |
|---|---|
| `set_action_end` laundered again (`patchArg` + the typed factory + the `isEmpty` refusal) | patch_door **216/239, ABORTED**; phase6 166/168 |
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
by six names. In `designs/reelcut-design.md`, §7.9's raw-factory
parenthetical, which named only "the agent's property patches" where the
factories have taken three kinds of object since D1·4. §6 needed nothing:
its `add_zoom_action` row already said the region is read the way a patch is
and its `set_action_end` row already said the end patch is walked, both
written by D1·2 against a core the Swift side was still answering for.

**Where a criterion could not be met literally.** #6's fifth criterion says
the phase-3 region assertion moves "to the core's wording". It could not:
the assertion is about an ABSENT region, which is the one refusal the
handler still makes and must, since the core cannot tell an absent argument
from an explicit null and here they are opposite edits. It was moved from a
keyword to the whole sentence instead, which is the rule behind the
criterion, and the core's own region wording is asserted in §11 of the patch
door.

**The review** (standards and spec, in parallel, against #6 and spec #1).
The spec axis found criteria 1–4 and 6 met and 5 met with one gap;
everything below landed in the follow-up commit.

Fixed:

- **Two claims the record made and the proof did not.** The empty patch is
  the core's identity refusal now, a behaviour change D1·4 PINNED for
  `set_canvas` (§8d) and this ticket only described — §10e asserts it, with
  the end state unchanged after. And the two `video.motion` refusals were
  the only new checks a LAUNDERING door could also pass, because `refused`
  matches a substring and the deleted handler's sentence CONTAINED the
  core's (`patch.video.motion is not an animation target — set it with
  set_video.`); §10b now also asserts the message ENDS at the core's
  sentence. 258 → 261, and the laundering mutant re-run took all three
  (215/238 → 216/239).
- **The docstring this deletion left behind** — the fourth ticket running,
  and this time in the proof rather than the code.
  `patch_door_patches.py` still said "five PATCH-OP sections", listed five
  subjects without `an action end patch`, and estimated "about five hundred
  lines" at 709. Its sibling `patch_door_args.py` had been updated four →
  five in the same commit; this one was missed.
- **One sentence in `app/CLAUDE.md` was too strong.** "NO handler checks a
  caller's enums or types by hand" is false: `add_zoom_action`'s `fit`,
  `curveArg` and `set_transition`'s `kind` are scalar enum arguments parsed
  by name twelve lines under it. The rule is about caller-authored OBJECTS
  and now says so.
- **Two spellings of one join.** `edit_zoom.rs` learnt that
  `serde_path_to_error`'s ROOT prints as `"."` while `patch.rs`'s
  `read_merged` still matched `("", inside)` / `(prefix, "")` — the same
  prefixing written twice, with only one of them knowing the trap, so the
  next group type to fail at its root would have said `bad value at
  "video."`. `patch.rs`'s `path_under` is the one implementation and both
  call it (core/CLAUDE.md's "one implementation per algorithm").
- **Spec §7.9's raw-factory parenthetical** still said the factories were
  for "the agent's property patches", which has been three kinds since
  D1·4 — a patch, a colour, and now a region. The claim above that no spec
  sentence needed changing was wrong by one.
- **`ReelCore.swift` grew by two lines** for a paragraph this ticket made
  false; it is back at 1508.

Judged not real:

- *`zoomRegionArg` is a Middle Man — `rawPatchArg`'s body with a different
  message — and the shared argument vocabulary lives in
  `AgentServer+Arguments.swift`.* Its message is the DOOR's, not a patch's,
  and it is the one refusal the core cannot make; `newClipPatchArg` (D1·4)
  is the precedent for a door-specific reader staying in the handler file.
  Moving it would also grow the one file here that owes a reduction.
- *`set_action_end` does not SNAP the ticks an end patch carries, against
  spec #1's "a text animation's timing … at the patch door".* Two reasons
  it is not a defect: `audio.fade_in` is deliberately OFF the grid at every
  door (core/CLAUDE.md's Times rule exempts the audio ramps), and an end
  state is an animation TARGET rather than a value written into a property
  group — the evaluator produces off-grid values all the way along the ramp
  by construction, so snapping its endpoint would buy nothing. D1·2 scoped
  `snap_animation` to the five `set_*` patches and `add_text_clip` and its
  record says so; nothing here changes it.

**Owed.** Nothing for this ticket. The deletion sweep, the rule in the app
rulebook and the spec's agent section, and the two proof mutants are #7's by
design. `AgentCatalog+Clips.swift` carries two lines of unpaid toll, named
above.

---

### 2.6 D1·6 — contract and record (kpgalligan/reelcut#7)

**Commits.** `89ace12` (the ticket) and `cc9ab58` (what its review found,
below).

**What landed, and what deliberately did not.** No behaviour changed at any
door — every door was through after D1·5 — and that is the claim this ticket
had to make good on rather than the one it had to avoid: the patch door
scores **261/261 before and after**, the same checks, and no proof assertion
moved. What changed is that the machinery a later door could have reached
for is gone, and the rule that replaced the old warning is written where
someone will meet it.

- **The sweep is four functions and one initialiser.** All four in
  `AgentServer+Arguments.swift` — `patchArg` with its round-trip check,
  `decodePatch`, `withOpaqueColors` and `nestedNumberArg` — were verified
  uncalled and deleted: **562 → 445**, 140 lines removed for 23 added, 65 of
  the removed being code and the rest the doc that argued for them. Beside
  them went `ClipPatch`'s lenient `init(from:)` and its `Codable`
  conformance (`ReelCore.swift` 1508 → **1507**), dead since D1·4 sent
  `set_clip`'s argument raw and the last `nullable()` reading of a value a
  CALLER wrote — `ShapePatch`, `Equatable` and nothing more, is the shape it
  takes now. The twelve names D1·4 and D1·5 listed were checked against the
  tree and are indeed gone; `zoomRegionArg` is NOT among them and survives
  as eight lines that read nothing about the region.
- **The lenient helpers keep honest callers, which is the other half of the
  rule.** `lenient` has some three hundred call sites and `nullable` eleven,
  and every one of them decodes what the CORE wrote: the project, the plan,
  the recipe, export settings, and — the one that looks like a patch and is
  not — `ActionSnapshot.end`, an `ActionPatch` of `VideoPatch` /
  `AudioPatch` / `TextPatch` read out of the project JSON. Deleting them
  would refuse a file a newer build wrote, which is the reason they exist.
- **The file's header says what is left**, which was the ticket's own test of
  the deletion: target and scope, an id checked against the CONTAINER it
  names, a time on the document's frame grid, the scalar coercions, and the
  in-band refusal — what the core cannot know. "Nothing here reads a
  caller-authored OBJECT" is the sentence, with `rawPatchArg` named as the
  way past and the three measured reasons the family went named beside it.
- **The rule replaces the warning in the app rulebook.** `app/CLAUDE.md`'s
  Rules section had no rule about this at all — D1·1 to D1·5 corrected the
  file-map prose and left the old pitfall paragraph deleted rather than
  replaced. It now carries one: *lenient decoding is for what the CORE wrote;
  nothing a caller wrote is decoded through it*, with what it is FOR
  (a newer build's file), what it forbids (a caller's object), and the
  exemption spelled out so it cannot be read too widely — a scalar enum
  ARGUMENT parsed by name (`add_zoom_action`'s `fit`, `curveArg`,
  `set_transition`'s `kind`) is not this, and the core refuses those too.
- **The spec says it in four places, each about its own subject.** §7.9 gains
  the rule as a paragraph of its own at the section's foot. §5.2 gains what a
  PATCH against the schema means — merge at every depth, `null` clears, an
  array replaces, a refusal by dotted path — beside the sentence that says
  colours are `[r, g, b, a]`, now reading FOUR numbers and never clamped,
  with `video.chroma.key` named as the one `[r, g, b]` in the schema. §6's
  preamble gains the same rule against the op table, so a row does not have
  to carry it. And §4.3 lost the two bullets that said a patch of a nested
  object is a REPLACEMENT — `text.animation`'s and, two paragraphs down, the
  gradient's, which the first pass missed and both reviews caught. Both
  sections send the whole object because they KNOW every key, and there is a
  second reason the old sentence hid: a stored `null` is not an object, so
  turning a reveal or a gradient ON replaces the null and the keys left out
  come from the struct's defaults. A section that spells all of them is
  right whichever case a clip is in.
- **The README repeated neither**, so nothing there was false; it gained a
  short paragraph anyway, under the tool list where an agent meets it: a
  patch is your own object, it merges, an unknown key or a misspelt value is
  an error naming the path, and a colour is four numbers.
- **`CONTEXT.md`'s two entries were sharpened, not rewritten.** **Op** now
  says an op can be REFUSED with a sentence saying what was wrong, and that a
  refusal leaves the project exactly as it was and makes no undo step — which
  is the whole of what D1 added to an op's meaning and was missing from a
  definition that said only "yields a new project or changes nothing".
  **Patch** now names its three targets (a clip's property group, a clip's own
  name and label, an action's end state), says a value is never CLAMPED as
  well as never dropped or corrected, and ends "the core is the one that reads
  it, wherever it came from". Still a glossary: no implementation detail, no
  file names.
- **The handler docs still NAME the deleted functions, in the past tense**,
  and that is deliberate rather than rot: `set_clip`'s doc says the check it
  needed was one the launder could not make, `set_shape`'s says what
  `shapePatchArg` read by hand, and the new header of
  `AgentServer+Arguments.swift` lists all four it deleted. The precedent is
  D1·4's and D1·5's, both reviewed: a door explains itself by what it stopped
  doing, and §2 here is where those names are defined. What is NOT allowed to
  survive is a sentence in the present tense about a function that is gone,
  and the three that were (the map entry, `scalarArg`'s doc and the
  app-notes header) were rewritten.
- **`designs/reelcut-app-notes.md`'s header** claimed `zoomRegionArg` was
  deleted (it is not), left `requiredColorArg` out of the list (it is), and
  said the four functions were still owed. All three corrected, and the rule
  named so the archived paragraphs below it are read as history.

**Measured.**

- `make test`: **632 passed, 0 failed**. `make lint` and `cargo fmt --check`
  clean. `make typecheck` 0 errors and the 4 known AVFoundation warnings.
  `make app` succeeded and the startup parity log was empty on every launch.
- **Every proof script in the tree**, not only the twelve this series has been
  running, on port 4826. Over MCP: patch_door **261/261**, phase1 66/66,
  phase2 85/85, phase3 123/123, phase3_silence_scope 8/8, phase4 84/84,
  phase5 88/88, phase6 168/168, phase7 92/92, phase8 79/79, phase9 216/216,
  remaining 79/79. `recording_proof.py` **187/187 with 2 skipped** — the tone
  rows, because this host's audio output is MUTED and the tap gets the tone
  unreliably; it is a host-state skip the script reports by name, and it is a
  better score than D1·5's 185/186 on the same tree.
  Offscreen: recording_probe 917/917, remaining_probe 170/170, phase9_probe
  48/48, transition_sheet_probe 32/32, preview_validity_probe 19/19 (5
  skipped) and preview_refresh_probe 0/0 (58 skipped) — both skip-sets are
  the LOCKED CONSOLE, which displays nothing in any layer. Chrome: phase2
  26/26, phase3 33/33, phase4 59/59, phase5 81/81, phase6 70/70, phase7
  78/78, phase9 62/62 and phase8 **144/150**, which is the documented
  locked-console score for that script (`designs/reelcut-remaining.md` §4;
  its section 4 activates a probe and needs a screen).
- Line counts. `AgentServer+Arguments.swift` 562 → **445**, `ReelCore.swift`
  1508 → **1507**. Nothing else in the app changed size. Across the whole of
  D1 the `AgentServer*` family is **6651 → 6034, 617 lines smaller than
  before the series**, and `AgentServer+Arguments.swift` is 109 lines below
  where it started.
- `designs/reelcut-remaining.md` §3 is regenerated by comparing EVERY row
  against `wc -l` rather than by eye: still the same thirty files, with two
  rows wrong — `ReelCore.swift` 1510 → **1507** (this ticket's line, and the
  table was two stale besides) and `AgentCatalog+Clips.swift` 945 → **941**,
  stale since D1·4 and caught by the review rather than by the first pass.
  The `AgentServer+Clips.swift` note now carries the family's total.

**Mutants.** Two, the pair spec kpgalligan/reelcut#1 asks for, each a rebuild
of the app and a fresh instance on port 4826, each reverted afterwards and
the proof shown green again (261/261, 123/123, 168/168). Both caught.

| Mutant | Score |
|---|---|
| the decode-and-re-encode launder restored at ONE door (`set_video`'s patch decoded through the lenient `VideoPatch`, sent on through the typed factory) | patch_door **11/32, ABORTED**; phase3 120/123; phase6 165/168 |
| the core's key walk (`check_keys`) disabled | patch_door **120/155, ABORTED**; phase3 121/123; phase6 **ABORTED** at 101 on an unhandled refusal |

Three readings, since a mutant table is only worth the rows somebody reads.
**The launder at one door aborts in §1**, the section for that very door,
which is why 11 is a smaller number than D1·3's 9/32 was over a proof a
quarter the size: the run stops the first time an op that should have been
refused succeeds instead. The last four failures it prints before it stops
are the leniency itself — a one-key `shadow` patch REPLACED from
`ShadowProps`' defaults (`opacity` 0.8 → 0.5, `distance` 30 → 8), a `motion`
patch naming only `in` that drops the stored `out`, a null slot that clears
the whole motion — and an undo claim, because the edit that should not have
happened leaves a marker behind. **The key-walk mutant reaches four times as
far** (120/155 against 11/32) and that is the honest shape of the two halves:
disabling the walk breaks the UNKNOWN-key half only, while a misspelt
VARIANT is still refused by the path-tracking typed read D1·1 built, so the
proof keeps scoring until it reaches an unknown key that now lands. **phase3
and phase6 barely move** under either — 120/123 and 165/168, 121/123 and an
abort — which is the same finding D1·5 recorded about the region: outside
`patch_door.py` almost nothing in the tree discriminates a door that quietly
corrects a caller from one that refuses. The patch door is the instrument,
and the older scripts are a guard rail rather than a second opinion.

**What an agent sees change: nothing.** This is the one ticket of the six
with no behaviour to announce. The two changes agents do see — a nested
object MERGES where it used to replace, and a colour must be FOUR numbers —
landed in D1·3 to D1·5 and are named in §3 below.

**The review** (standards and spec, in parallel, against #7 and spec #1).
The spec axis found the deletion, the rule, the glossary and every line
count it spot-checked correct, and both axes found the same two things
wrong. Everything below landed in the follow-up commit.

Fixed:

- **A sentence the first pass missed, and the claim that there were none
  left.** §4.3's GRADIENT bullet still read "a patch of a nested object is a
  REPLACEMENT (§5.2) and a key left out comes back as its default" — two
  paragraphs under the `text.animation` bullet that had just been rewritten,
  with a cross-reference pointing straight at the §5.2 sentence that now
  refutes it. Worse, the record claimed the rewrite had taken "the last
  sentence in the tree that said replace, checked by grep": the grep was for
  the lower-case spelling and missed four, because three of them SHOUT the
  word. A claim made by grep is only as true as the pattern, and this is the
  second ticket running where an unproved sentence in the record was the
  finding.
- **The other three were code docs making the claim in the present tense** —
  the thing this ticket's own record says is not allowed to survive.
  `ReelCore.swift`'s `ShapePatch` doc said a gradient "inherits the
  replacement rule" AND that "this patch is the one read by hand in
  `AgentServer`, so a key misspelt inside a gradient can be refused by name
  there" — `shapePatchArg` and `gradientArg` died in D1·4. `TextPane.swift`
  and `ShapePane.swift` said it too, one of them citing `app/CLAUDE.md` for a
  rule the same commit made say the opposite. All three now say what is
  actually true and keep the behaviour they justify: the whole-object write
  is right because a stored `null` is not an object, so turning a reveal or a
  gradient ON replaces the null and the keys left out come from the struct's
  defaults.
- **The ledger was regenerated by eye and one row stayed stale.**
  `AgentCatalog+Clips.swift` read 945 against a tree holding 941, wrong since
  D1·4. It is compared row by row against `wc -l` now, which is what
  "regenerated" should have meant the first time.
- **The series toll was undercounted.** §3 named "two lines" in
  `AgentCatalog+Clips.swift`, which is D1·5's own figure; across D1 that
  over-cap file went 919 → 941. A series roll-up quotes the series.
- **`app/CLAUDE.md` had become a history.** Its agent entries narrated which
  ticket moved which door and what D1·6 deleted — the root `CLAUDE.md` says
  the three rulebooks "hold no status and no history", and every one of those
  sentences was already in §2 here and in `reelcut-app-notes.md`. The map
  entries now state the rule and point at this document for what it cost.
- **Two clauses that would have refused an agent who believed them.** The
  README's new paragraph said a colour is four numbers without naming
  `video.chroma.key`, the one `[r, g, b]` the model really has; and the new
  rule in `app/CLAUDE.md` did not name the one caller-authored object the app
  still reads by hand — `add_media`'s descriptor, which is a media ROW rather
  than a patch and has no op of its own to refuse it. Both are named now, the
  second as an exception on purpose rather than an oversight.

Judged not real:

- *`zoomRegionArg` duplicates `rawPatchArg`'s absent-argument shape
  (Duplicated Code, nine lines).* D1·5's review judged the same finding and
  the answer has not changed: its message is the DOOR's, and an absent region
  is the one refusal the core cannot make, since it reads an absent argument
  and an explicit null identically and there they are opposite edits.
- *The README gained a paragraph though #7 says it follows "if it repeats
  either", and it repeated neither.* True, and it stays: the README is where
  an agent meets the tool list before the catalog, and a rule with no home
  there is a rule found only after the first refusal. The record says it was
  unasked.

**Owed.** Nothing. The two tolls D1 leaves are named in §3.

---

## 3. D1 — closed

Six tickets on `d1-patch-door`, every one landed and reviewed on
2026-09-17. **The core is the one validator of every caller-authored object
the app can be sent**, and the Swift side no longer has a way to be a second
one.

**What landed, in one paragraph per ticket.** D1·1 taught `patch.rs` to name
the dotted path and the offending value in every refusal, array indices
included, over a path-tracking deserialise (`serde_path_to_error`, the one
crate the series added to the core). D1·2 changed what a patch may CARRY: a
`video.filters` entry must name both its keys, an action's end patch is
walked like any other, a zoom region is an object with four named members,
and the ticks a motion preset or a text animation carries are snapped in the
core after the range checks. D1·3 took the first door — `set_video` forwards
the caller's object — and built `tools/proof/patch_door.py`, the instrument
the rest of the series is measured with. D1·4 took eight more doors and made
a colour four numbers everywhere, deleting `colorArg`, `shapePatchArg`,
`gradientArg` and the rest of the hand readers. D1·5 took the last two,
`set_action_end` and `add_zoom_action`'s region, and with them the last hand
check in any handler. D1·6 deleted the shared launder, wrote the rule where
the warning was, and made the proof fail twice on purpose.

**The two behaviour changes an agent sees**, both deliberate, both in the
catalog's own text now:

1. **A nested object MERGES**, where at two doors it used to replace.
   `{"video": {"shadow": {"blur": 40}}}` keeps the colour, the angle and the
   distance; before D1·5 the same call rebuilt the shadow from
   `ShadowProps`' defaults (measured: `opacity` 0.8 → 0.5, `distance` 30 →
   8). `{"motion": {"in": …}}` keeps a stored `out`. `null` still clears a
   key at any depth, and an array still replaces its whole list.
2. **A colour is four numbers, `[r, g, b, a]`, each 0–1.** The three-element
   form is refused by length and a component outside 0–1 is refused rather
   than clamped, at every door including the two colour-only arguments
   (`set_canvas`'s background, `add_background`'s colour). `chroma.key` is
   the one colour the model really does spell `[r, g, b]`, and it is
   unchanged.

Everything else an agent meets is a refusal where a silent correction used
to be: a misspelt enum at any depth, an unknown key by its dotted path with
the array index in it, a wrong-typed value in an optional slot, an
incomplete filter entry, and a region member spelled `widht`.

**Measured, across the series.**

| | Before D1 | After D1 |
|---|---|---|
| `AgentServer*` (the handlers and the argument vocabulary) | 6651 | **6034** (−617) |
| — `AgentServer+Clips.swift` | 1222 | 847 |
| — `AgentServer+Arguments.swift` | 554 | 445 |
| — `AgentServer+Motion.swift` | 157 | deleted |
| — `AgentServer+Background` / `+Tracks` / `+Render` | 89 / 231 / 561 | 100 / 242 / 563 |
| `AgentCatalog*` (the tool prose) | 2222 | 2251 (+29) |
| `ReelOps.swift` (the op table, exempt) | 974 | 1131 (+157 — eleven raw factories) |
| `ReelCore.swift` | 1503 | 1507 |
| `core/src/patch.rs` | — | **414** (new) |
| `core/src/edit_props.rs` | 432 | 331 |
| `core/src/edit_action.rs` / `edit_zoom.rs` / `props_check.rs` | 258 / 390 / 383 | 321 / 457 / 396 |
| `make test` | 621 | **632** (`core/tests/patch_door.rs`, 9 tests over 597 lines) |
| the patch-door proof | — | **261/261** over eleven doors, four files, 1368 lines |

So the deepening's arithmetic is: **617 lines out of the agent's handlers
and 470 into `core/src`** (687 added against 217 deleted), of which 414 is
the new patch module — knowledge
moved behind one interface rather than deleted outright, which is what §0's
deletion test predicts and what makes the next property the core gains cost
the Swift side nothing at all.

**The two mutants the series owed**, run in D1·6 against every door at once:
the launder restored at one door, patch_door **11/32 ABORTED**; the core's
key walk disabled, patch_door **120/155 ABORTED**. Both reverted, both green
again.

**What is owed.**

- **Twenty-two lines of unpaid toll in `AgentCatalog+Clips.swift`**
  (919 → 941 across the series, over the cap and with no standing
  exemption): what it took on is tool descriptions saying what is now true —
  the merge depth, the four-number colour and the refusal's shape. Each
  ticket named its own handful; the SERIES total is this one, and the next
  phase to touch that file pays it or takes the exemption on purpose.
- **Four lines in `ReelCore.swift`** (1503 → 1507, also over the cap), from
  the raw factories' delegation notes in D1·3 and D1·4 less the initialiser
  D1·6 deleted. Smaller than the toll above and in a file whose named seam
  (the media and reverse machinery) is a phase of its own.
- **Nothing else.** No format bump, no new tool, no new export, no change to
  the tool count, and the startup parity check is untouched — which was
  spec kpgalligan/reelcut#1's US27 and is why every older fixture still
  passes.

**What a later deepening should take from this one.** The prefactor-first
order held: D1·1 and D1·2 made the core able to SAY what the Swift checks
were saying, so every ticket after them was a deletion and each could be
reverted on its own to be scored. The proof was born with the first door and
grew a section per door, so the last three tickets could each be measured
against every door at once. And the mutant tables are worth more than their
counts: three of them found that nothing OUTSIDE the new proof discriminates
the behaviour being deepened, which is the honest reason the instrument had
to exist rather than a claim that the old scripts would have caught it.

**Where the next candidate starts.** The two spec kpgalligan/reelcut#1 named
as out of scope and did not close: deriving the catalog, the typed factories
and the parity check from the core's op table (three mirrors of one list
that a startup check compares by name only), and a refusal that carries its
REASON for an op that returns nothing — today an identity and a refusal are
indistinguishable at the FFI, which is why `editResult`'s "made no change"
sentence has to guess at the cause and name the overlap rule to a caller who
sent a patch.


---

## 4. D2 — a refusal that says why

**Spec:** kpgalligan/reelcut#8.

**The problem.** An op that changes nothing and an op a rule refused look
the same from outside the core: NULL with `err_out` untouched. The reason
EXISTS at the moment of the refusal — the overlap rule writes a full
sentence naming the two clips and the exact tick counts — and fourteen sites
threw it away and answered "nothing" instead. Three layers then invented
answers to fill the silence: the agent's shared reply guessed a paragraph
(the action "made no change", then "either the project is already in that
state, or the edit was refused", then a lecture about the overlap rule, sent
even to a caller who changed a font size); three Swift handlers trial-applied
the op first so they could write a better sentence themselves, one of them
re-deriving the overlap rule's own arithmetic; and the core's own test helper
for "this op changes nothing" could not tell a no-op from a rejection either.
While verifying D1, every deliberately sabotaged door produced the same
paragraph about the overlap rule in reply to a PROPERTY patch, which is the
clearest demonstration of the problem.

**The shape.** The seam is the existing one again: the op envelope through
`rc_project_apply`. An op answers one of three ways — applied with the new
project, an identity, or refused with the rule's own sentence — as a Rust
enum rather than a side channel, so a site that has not decided which answer
it gives does not compile. The sentence crosses the FFI on a NEW
out-parameter of the same entry point, beside `err_out` and never with it;
"no handle and no message" still means an identity and still means no undo
step, so the five app paths that rely on that are unaffected. The
invalid-input tier is unchanged in meaning and in wording. The Swift
compensation is then deleted: the trial-applies, the hand-written sentences
and the re-derived arithmetic, leaving the tool prose that TEACHES a rule
before the call (which is not the same thing as explaining a refusal after
it) and the two places that swallow a refusal on purpose — a scoped view and
a live drag — with the reason written into the app's rulebook. There is no
new export, no new tool and no format bump, and a person at the machine sees
exactly what they saw before: a beep, and no undo step.

**The tickets, in blocking order.** #9 → #10 → #11 → #12 → #13.

| Ticket | Title | Blocked by |
|---|---|---|
| kpgalligan/reelcut#9 | D2·1: the core answers in three arms, and the overlap rule speaks | — |
| kpgalligan/reelcut#10 | D2·2: the app switches on three arms, and an agent hears the overlap rule | #9 |
| kpgalligan/reelcut#11 | D2·3: the remaining rules speak | #10 |
| kpgalligan/reelcut#12 | D2·4: the app's guesses are deleted | #11 |
| kpgalligan/reelcut#13 | D2·5: contract and record | #12 |

D2·1 is the prefactor and is core-only: the type change, the FFI's third
answer, and the first rule to find its voice. D2·2 is the other wide change —
the app's five "nothing happened" paths and the agent's reply — and it is
where the MCP proof for this seam is born, with the overlap section every
later ticket copies. D2·3 gives the remaining rules their sentences (a
locked track, the last track, a media row still in use, a cut with nothing
left to give, an action that would overlap another). D2·4 is the deletion
ticket the prefactor pays for. D2·5 is the contract step: the glossary, the
spec and both rulebooks, the proof failed twice on purpose, and the record
closed. The two wide changes are deliberately not mixed with anything else.

**Out of scope, and named so it is not rediscovered.** Showing a refusal's
sentence to the person using the app — the beep stays, and where such a
message would live is a design question of its own. Turning refusals into
machine-readable codes: the sentence is prose, as D1's refusals are. The
roughly nine "empty selection" answers, which are TRUE identities and stay
that way. Any change to the invalid-input tier, the op table, the tool
count, the startup parity check or the persisted format. A refusal arm for
the QUERY exports, which keep returning nothing with no message. And the
other architecture-review candidates, in particular deriving the catalog and
the typed builders from the core's op table.

---

## 5. D2 — the record

One entry per ticket, written when it lands.

### 5.1 D2·1 — the core answers in three arms (kpgalligan/reelcut#9)

**Commits.** `5cd4fcf` (the ticket) and `2148190` (what its review found,
below).

**What landed.** Core, the FFI's three files, and the documents those
sentences live in. The app's BEHAVIOUR is unchanged — `ReelCore.swift`
passes NULL for the new channel — so neither a person nor an agent sees any
of this yet; D2·2 is where they do.

- **`core/src/outcome.rs` is new, 75 lines**: `Outcome`, with
  `Applied(Project)`, `Identity` and `Refused(String)`, and the doc that
  says what each arm means, what a composed op must do with the two it did
  not expect, and why the invalid-input tier is NOT a fourth arm. Every
  `impl Project` edit now answers `Result<Outcome, String>` — 65 signatures
  across fourteen modules.
- **The compiler found the sites, which is the reason it is a type and not
  a flag.** 73 `Ok(None)`s in the edit modules were each made to say which
  answer they are, and the type change also surfaced the composition sites
  no one had listed: `insert_clip`, `overwrite_clip`, `freeze_frame`,
  `add_zoom_action` and the scoped apply each consumed an inner op's answer
  through `let Some(…) else`, `if let Some(…)` or `unwrap_or_else`, which
  would have turned an inner refusal into "nothing happened". They now match
  all three arms, in **eleven** pass-through arms, so a composition answers
  in the words of whichever step declined. `clear_range` is the one place
  that deliberately folds a refusal into "nothing was cut": it answers a
  `Project` rather than an `Outcome`, a splitter has no rule to refuse with,
  and the comment says a splitter that ever gains one has to be given a way
  out of there first.
- **The overlap rule speaks, at all fourteen sites that dropped its
  sentence.** Each now reads `if let Err(why) = … {
  return Ok(Outcome::Refused(why)) }` and hands the rule's own words on
  verbatim: nine in `edit_clip.rs`, two in `edit_time.rs`, one each in
  `edit_edge.rs`, `edit_nest.rs` and `edit_transition.rs`. The other four
  `check_overlap_rule` call sites are SEARCHES, not refusals —
  `edit_paste.rs` and `edit_nest.rs`'s `unnest` looking for a track a clip
  will fit on, and `edit_transition.rs`'s two step-down loops — and are
  unchanged.
- **The FFI's fourth parameter.** `rc_project_apply(p, op, err_out,
  reason_out)`: a handle means applied, NULL with neither channel written
  means an identity, NULL with `reason_out` set is the refusal, NULL with
  `err_out` set is invalid input and is untouched. The two channels are
  never both written, and `reason_out` may be NULL for a caller that does
  not want the sentence — which is exactly what `ReelCore.swift` passes
  until D2·2. `ffi_util.rs`'s `set_err` is now `set_message`, because it is
  the one spelling of BOTH channels: what they mean differs, how they
  allocate must not.
- **Which refusals can say why.** Only the overlap rule, per the spec's
  third Implementation Decision. The rules whose words are owed to D2·3 — a
  locked track, the last track, a media row a clip still shows, a cut with
  nothing left to give a transition, an action that would overlap another —
  answer `Outcome::Identity` for now. A doc comment that says an op
  "refuses" is describing the DOMAIN and stays; `Outcome::Identity`'s own
  doc is the ONE place that lists which of them can say so out loud, so the
  next reader does not have to grep for a marker in ten modules.

**Tests.** A new file, `core/tests/refusal.rs`, nine tests through the FFI:
the overlap rule's sentence from a move, from a trim and from the
two-neighbours case, the same sentence coming back out of a `scope`, a
refusal that still passes `refuses` (the no-undo-step claim 91 call sites
make), a refusal against a NULL `reason_out`, an applied op with no
sentence, three true identities with no sentence, and invalid input
unchanged in wording. Every expected sentence is written out WHOLE, ids and
tick counts included, hand-computed from a one-tick-per-frame fixture: a
keyword match would pass on a sentence that had lost exactly the part a
caller reads.

`core/tests/common/mod.rs` learned the third arm. `Handle::try_apply` now
answers a test-side `Outcome` mirroring the core's, and is where the
header's invariants are asserted once for the whole suite: a handle never
comes back with a message on either channel, and the two channels are never
both written. `Handle::refuses` keeps its meaning — "no handle, so no undo
step" — and all 91 of its call sites, accepting either non-applied arm. The
new `Handle::refuses_with(op, sentence)` is the one that pins WHICH and in
what words, and it compares the whole sentence. `Handle::errors` and
`Handle::apply` each gained an arm that now names a refusal's sentence in
its panic, which is a better failure message than either had.

**Mutants.** Three, all caught:

| Mutant | Score |
|---|---|
| the sentence discarded at the FFI (`Refused` returns NULL without writing `reason_out`) | 4 of 9 tests failed |
| a rule's refusal turned back into a bare identity (`move_clips`' overlap check) | 3 of 9 failed |
| a handle returned WITH a sentence (the invariant `try_apply` asserts) | 1 of 9 failed |

The third failed nothing until `an_applied_op_carries_no_sentence` was
added: the other eight tests never apply an op successfully, so the
invariant was being asserted for the rest of the suite but not by this file.
That test is the reason the mutant is scored rather than a claim.

**Verification.** `make test` 641 passed / 0 failed (632 before, plus the
nine new), `make lint` clean, `cargo fmt --check` clean, `make typecheck` 0
errors and the 4 known AVFoundation warnings, `make app` built, and the
startup parity log empty (`grep "Reelcut: " /tmp/reelcut-4841.log` printed
nothing at every launch below).

Every existing proof script was run against the rebuilt binary, each on a
freshly launched instance of its own: phase1 **66/66**, phase2 **85/85**,
phase3 **123/123**, phase3_silence_scope **8/8**, phase4 **84/84**, phase5
**88/88**, phase6 **168/168**, phase7 **92/92**, phase8 **79/79**, phase9
**216/216**, patch_door **261/261**, remaining **79/79**, recording
**121/121** with the granted tier skipped by name (a locked console, no
shareable display: 66 checks). **A run per instance is not optional**: the
first pass shared one instance across phases 1 to 5 and phase 6 then hung
on the known past-forty-documents deadlock, which reads exactly like a
regression and is not one. The relaunch is now by tracked pid file, because
`pkill -f` on the absolute binary path does not match an instance launched
by a relative one.

**Size.** `core/src/edit_clip.rs` 1042 → 1028, `edit_track.rs` 674 → 671,
`edit_transition.rs` 553 → 547 and `edit_paste.rs` 600 → 596: every
over-cap core file this touched came DOWN, because the retired `(\`None\`)`
spelling was longer than the domain words that replaced it.
`app/Sources/ReelCore.swift` is back at **1507**, its size before the
ticket: the doc comment the FFI lockstep rule requires it to rewrite was
tightened until the file paid for what it took on, which is what the rule
asks of a file at the cap. **`core/src/edit.rs` 887 → 895** is the one
unpaid growth, under its standing table exemption: the eight lines are the
Results section of the contract this ticket changed, which is what the
acceptance criteria asked for. The new module is 75 lines and the new test
file 220, against a 400-line cap.

**Documents.**

- `core/CLAUDE.md` gains the `outcome.rs` map entry; its Purity rule says
  `Outcome::Identity` where it said `None`, and its Errors rule now states
  three arms and one tier with the full FFI mapping.
- Spec §5.5 states the three answers; §7's header quote carries the new
  signature; the sentence that said a scope "widens the third arm" now says
  it widens the invalid-argument answer, since `Err` is no longer third.
  The op table (§6), the glossary and `app/CLAUDE.md` are D2·5's.
- `README.md`'s FFI bullet says three distinguishable NULLs.
- About thirty doc comments that spelled an op's answer `None` now speak in
  domain words ("an identity", "refuses", "in the rule's own sentence"),
  including `edit.rs`'s Results section, `edit_clip.rs`'s three rules,
  `scope.rs`'s contract, `edit_track.rs`'s module doc and
  `check_overlap_rule`'s own.

**What its review found.** The two-axis review ran against `a981bbd`.
Fixed:

- **Five doc comments still spelled an op's answer `None`** after the
  sweep, and two of them MISNAMED the arm — `set_video`'s "Refuses
  (`None`) when nothing changes" and `split_clips`' "when nothing can be
  cut the whole op refuses (`None`)" are identities, which is the very
  ambiguity this ticket removes, re-created in prose. With them,
  `ripple_delete`, `move_track` and `set_transition_style`.
- **`edit.rs`'s op table was half-converted**: `slip` and
  `set_transition_style` had been updated and `paste_attributes`,
  `set_clip` and `add_transition` had not. It is the caller-facing table
  and the worst place to leave a retired spelling.
- **`clear_range` guarded its two bounds differently** — an exhaustive
  `match` at the first and an `if let` at the second, which would not stop
  compiling if an arm were added. Both are exhaustive now.
- **`ReelCore.swift` had taken on three lines** with nothing given up,
  against the rule for a file at the cap. The doc comment the FFI lockstep
  requires it to rewrite was tightened until the file was back at 1507.
- **Numbers in this record were wrong**: "89 `Ok(None)`s" was the raw grep
  count including doc comments and three unrelated modules (the real
  figure is 73 code sites in the edit modules); "ten of fourteen overlap
  sites" was miscounted (all fourteen speak, and the four left alone are
  searches); `edit_clip.rs` is 1028, not 1029. The commit message carries
  the first two wrong numbers; this paragraph is the correction.
- **The Verification paragraph ended in a dangling clause** ("the proof
  scripts run below") with no scores below it. The scores are there now.
- **Spec §5.5 said `fn(&Project, args) -> Outcome`**, dropping the
  `Result`; it now names all four answers and says why the fourth is not
  an arm.

Judged not real:

- *The eleven composition arms are a Repeated Switch that wants a
  combinator.* Writing all three arms at every site is the enum's stated
  reason for existing: a combinator would hide the decision the compiler is
  there to force, and D2·3 copying the shape is the point, not a cost.
- *`Handle::refuses` is now a mysterious name — it passes on an identity
  OR a refusal.* It asserts "no undo step", which is what its 91 call
  sites mean, and the ticket settled that it keeps its name and its sites.
  `refuses_with` is the sharp one.
- *`clear_range` folding a refusal into "nothing was cut" is a third
  swallow, where the spec sanctions two.* The spec's two are app-side, and
  this one is unreachable: a splitter has no rule to refuse with. It is
  named here and at the site rather than hidden, with the condition that
  would make it real.
- *Rewriting `core/CLAUDE.md`'s Purity and Errors rules and `README.md`'s
  FFI bullet is D2·5's work.* Leaving them would leave the core's own
  rulebook false about the type every edit now returns, and the header
  change forces spec §7's quote anyway. Recorded as a deliberate
  pull-forward; the op table (§6), the glossary and `app/CLAUDE.md` are
  still D2·5's.

**What the next tickets inherit.**

- **The three-armed shape, verbatim**, for D2·3 to copy: a rule refuses with
  `if let Err(why) = <the rule> { return Ok(Outcome::Refused(why)) }`, and a
  composed op matches all three arms and returns the two it did not expect
  unchanged.
- **The test shape, verbatim**: `Handle::refuses_with(&op, "<the whole
  sentence>")`, with the numbers hand-computed in the test.
- **`reason_out` is already wired and already tested against NULL**, so
  D2·2's Swift change is a read at one call site, not a contract change.
- The mutant that matters for D2·2 is the first one above: discard the
  sentence at the FFI and the old ambiguity comes straight back.

**Owed.** The eight lines in `edit.rs`, named under Size above. Three rows
of `designs/reelcut-remaining.md` §3 are stale by this ticket
(`edit_clip.rs` 1042 → 1028, `edit_track.rs` 674 → 671, `edit.rs` 887 → 895,
`ReelCore.swift` is back where it was); the ledger already says to regenerate
rather than trust its numbers, and D2·5 is where it is regenerated. No proof
script: this ticket adds no app behaviour to photograph, and D2·2 is where
the seam's proof is born.

### 5.2 D2·2 — the app switches on three arms (kpgalligan/reelcut#10)

**Commits.** `25d3030` (the ticket) and `3042b3e` (what its review found,
below).

**What landed.** The app side of the seam D2·1 opened, and the seam's proof.
`ReelCore.swift` reads `reason_out` at last, the five app paths that read
"nothing happened" each say which arm they handle, and an agent stops being
handed a paragraph of guesses. No core change, no FFI change, no new tool.

- **`app/Sources/ReelEdit.swift` is new, 122 lines**, mirroring
  `core/src/outcome.rs` module for module: `ReelEdit`
  (`.applied` / `.identity` / `.refused`), `ReelRefusal` (the op the core
  declined and the rule's own sentence), and the fold that applies a LIST —
  which names no `rc_*` symbol, so it belongs here rather than next door.
  `.project` is the spelling for a caller that deliberately treats a refusal
  as nothing happened, with a second one on `ReelEdit?` for the `try?`
  probes, and the sixteen call sites that only ever wanted the handle read
  exactly as they did before.
- **The wrapper answers three arms.** `rc_project_apply(ptr, op.json, &err,
  &reason)`, read in the header's own order: a sentence is a refusal, an
  error message is invalid input, neither is an identity. The refusal
  carries `op.name` with it, because the fold has to be able to say WHICH op
  of a list was refused.
- **The fold keeps its old decision and adds a reason.** A refusal does not
  stop the list — a later op still runs after one, exactly as after an
  identity, so a compound gesture is not thrown away because one step was
  declined — and `.applied` still comes back whenever ANY op applied, which
  is byte for byte what the method decided before. What is new is that the
  FIRST refusal is remembered and answered when nothing applied at all.
  **That is a NARROWING of the ticket's sixth line, said plainly**: a list
  where one op applied and another was refused answers `.applied`, and that
  refusal's sentence is dropped. Making a refusal abort the list instead was
  considered and rejected — it would change what LANDS for a recording's
  landing and a caption import, which is not this ticket's business — and no
  tool can produce the case today (below). A ticket that wants the dropped
  sentence reported beside a partial success is a ticket of its own.
- **The five paths each say which arm they handle.** `applyEdit` switches,
  and its two non-applied arms are one case: a beep, and no undo step, which
  is what makes a person's experience of the two identical. `updateLiveEdit`
  is one guard whose `else` names all three swallowed answers — an invalid
  tick, an identity and a rule's refusal — with the reason a drag must not
  go chatty. `endLiveEdit` says the arms reach it already collapsed, because
  `updateLiveEdit` replaces the handle only on `.applied`.
  `reanchoringConsolidatedMedia` and `makeProject` each say why both other
  arms leave the document as it was.
- **The agent's reply stops guessing.** One paragraph became two sentences:
  `<Action> made no change: the project is already in that state.` for an
  identity, which names no rule; and
  `<Action> was refused at <op>: <the rule's own sentence>` for a refusal,
  carrying the clips and the tick counts verbatim and naming the op, since a
  call may carry several. The phrase "made no change" is kept in the
  identity, on purpose: twenty assertions across seven proof scripts match
  on it and every one of them is about an identity today.
- **Two swallows stay, deliberately**: `ReelProject.scoped(_:)` still drops
  the core's `no nest with id N` (a view asking about view state it has
  already clamped), and the live drag still swallows a refused tick. Neither
  grew a word. The rulebook line about them is D2·4's.
- **Three comments this ticket made false were fixed** rather than left:
  `add_transition`'s "`performGroupedEdit`'s fixed text talks about the
  overlap rule" (it does not any more), and two that called an identity a
  refusal at the eyedropper and the Add Clip door — the very ambiguity this
  candidate removes, re-created in prose.

**The proof, born here.** `tools/proof/refusal_proof.py`, named for the seam
and not for a phase (the patch door is the precedent), **40/40**. Three
sections: the overlap rule speaking out of `move_clip`, out of `duplicate`
(which names the copy it never made) and out of a SCOPED call, with an
overlap one frame under the limit still applying so the number in the
sentence is the rule's own boundary; an identity at four doors, asserted as
a WHOLE equal string, which is the only way to measure "says only that"; and
a call carrying several ops, through `normalize_clip`, which sends one
`set_audio` per clip. Every refusal and every identity also asserts the
ABSENCE of two fragments of the deleted paragraph — it also began "<Action>
made no change", so a check looking only for the new words would pass
against a build that still sent it. **Section 1 is the template D2·3
copies.**

**And a probe beside it**, `tools/proof/refusal_probe.py`, **15/15**, for
the three app paths no MCP call can reach: the agent refuses at its own
trial and never asks the document, so `applyEdit`, `updateLiveEdit` and
`endLiveEdit` never see a refusal over the wire. It drives a live
`ProjectDocument` over two abutting text clips and scores that neither
non-applied arm moves the handle or renames the undo step, that a refused
tick mid-drag is swallowed and the gesture ends with no step of its own,
that ONE undo afterwards puts the project back to before the marker, and
that the invalid tier still throws. **"No error dialog" is measured by the
probe answering at all**: `present(_:)` with no window runs a modal alert
nobody can dismiss, so a build that treated a refusal as the invalid tier
would block, and the runner's timeout scores that as the failure it is.

**What the probe found and did not fix.** `ProjectDocument.performGroupedEdit`
opens an undo group and balances it whatever the edit answered, so an edit
that changes nothing leaves an EMPTY group behind — a step a person would
press ⌘Z twice past. It is PRE-EXISTING (an identity has always done it) and
no caller reaches it: the agent refuses at its trial first, and the menu path
does not use that entry point. It is printed as a note by the probe rather
than scored, and named here so the next reader finds it written down.

**Mutants.** Five, all caught. The first is the one D2·1's record named as
the one that matters here; the second is the fold, which every agent call
goes through because `performGroupedEdit` always passes a list.

| Mutant | Score |
|---|---|
| the sentence discarded at the FFI (`ReelCore.applying` passes NULL for `reason_out` again, the D2·1 state) | 3 of 39 proof checks failed |
| the fold forgets the refusal (`ReelEdit.applying(_ ops:)` answers `.identity` when nothing applied) | 3 of 39 failed |
| the agent's identity arm keeps guessing (the deleted paragraph restored) | 10 of 39 failed |
| the op name dropped from the refusal reply | 3 of 39 failed |
| `applyEdit` registers an undo step for a refusal (the phantom step) | 4 of 15 probe checks failed |
| a lecture APPENDED after the rule's sentence (the sixth, added by the review) | 3 of 40 failed |

The third is the widest because every identity in §2 and §3 is an equality
against the whole sentence: a build that appends a lecture moves the string
and is caught at four doors, not just at the one an eye would check. The
fifth is scored by the probe rather than the proof, which is the reason the
probe exists — no MCP call can put a refusal in front of `applyEdit`. The
sixth exists because the review found the refusal helper asserting its
sentence with `in` while its own docstring promised the reply ENDS in it: it
is the mutant only the fix catches, and the `in` it replaced passed it.

**Verification.** `make test` 641 passed / 0 failed (no core change, so the
number is D2·1's), `make lint` and `cargo fmt --check` clean, `make typecheck`
0 errors and the 4 known AVFoundation warnings, `make app` built, and the
startup parity log empty at every launch below.

Every proof script was run against the rebuilt binary, each on a freshly
launched instance of its own: **refusal 39/39** (40/40 after the review's
fix), phase1 **66/66**, phase2
**85/85**, phase3 **123/123**, phase3_silence_scope **8/8**, phase4
**84/84**, phase5 **88/88**, phase6 **168/168**, phase7 **92/92**, phase8
**79/79**, phase9 **216/216**, patch_door **261/261**, remaining **79/79**,
recording **121/121** with the granted tier skipped by name (a locked
console, no shareable display: 66 checks). The probe, which needs no running
app, is **15/15**. One run lost phase5 to `cache/peaks/2.bin was never
written` and it was not a regression: a `swiftc` build of the probe was
running beside it and the fifteen-second wait for a fire-and-forget cache
lost the race. Re-run alone it is 88/88. **Do not build anything while a
proof runs.**

**Size.** `app/Sources/ProjectDocument.swift` back to **1353**,
`AgentServer.swift` to **771** (one under), `ReelCore.swift` to **1500**
(seven under): all three are over the ~600 cap, so each gave something up
before it took anything on. What they gave up is the same thing in three
places — the ARGUMENT for each arm moved into `ReelEdit.swift`, which is the
new module's whole job, and the sites kept one sentence each. The new module
is 122 lines against a 400-line cap; the proof script is 484 and the probe
369, neither held to that cap (`tools/proof/README.md`, §2.4's precedent).

**Documents.** `app/CLAUDE.md`'s file map gains `ReelEdit.swift` under "the
core's edge"; `tools/proof/README.md` gains a section for the proof and one
for the probe, and both are in its run list. Spec §6's op table, the
glossary and `app/CLAUDE.md`'s Rules are still D2·5's.

**What its review found.** The two-axis review ran against `25d3030`, twice
on each axis (the first pair of agents was re-run after a lost hand-off, and
the second pair found one thing the first had not). Fixed:

- **The refusal helper was weaker than its own docstring.** `refused()`
  promised the reply "must END in the rule's own sentence" and asserted it
  with `in`, so a build that appended a lecture after the sentence would
  have passed — the exact failure this candidate exists to prevent. It is
  `message.endswith(tail)` now, and the sixth mutant is that lecture.
- **The boundary claim rested on an absent error.** "an overlap one frame
  UNDER the limit is allowed" scored only that nothing threw; it now reads
  the clip's start back through `get_project` (the README's rule that a
  claim is a placement read back, a byte comparison or a sample
  comparison). That is the fortieth check.
- **Two more doc comments this ticket made false**, both missed by the first
  sweep and both in files it was already editing:
  `EditorViewController+Inspector.swift`'s transition batch ("can come back
  `Ok(None)`") and `EditorViewController+Nest.swift`'s ⌘G, which listed the
  overlap rule's REFUSAL among the identities `applyEdit` beeps for — the
  very distinction this ticket draws, blurred in prose.
- **`tools/proof/README.md` still quoted the deleted paragraph as live
  behaviour** in its phase 8 section, although `phase8_proof.py`'s own
  docstring had been re-read. The mirror is re-read now, and says which
  script the negative check is measured against.
- **`updateLiveEdit`'s merged guard made its comment cover a case that is
  not an answer** (no gesture in progress). The guard is two again, one line
  SHORTER than the merged form, and the comment is about the three answers
  only.
- **A forward-looking clause in `AgentServer+Transitions.swift`** promising
  what D2·3 would do, and two slips of my own in `ReelEdit.swift` (a doubled
  conjunction, and `move_clips` where the op table says `move_clip`).
- **The record said `SHA1`/`SHA2`.** Both are filled.

Judged not real:

- *The size toll was not "landed and gated alone".* It was a tightening, not
  a pure move, and D2·1's own review set that precedent (`2148190` tightened
  `ReelCore.swift` back to 1507 inside the fix commit). No file grew.
- *`ReelEdit.swift`'s doc names a future ticket* ("until road map 7's D2·3
  gives them their sentences"). It mirrors `Outcome::Identity`'s doc, which
  D2·1 shipped and its review accepted as the ONE place that list lives; a
  Swift mirror that pointed nowhere would be worse.
- *The `.project` accessor at sixteen call sites is a Message Chain, and a
  third arm would be Shotgun Surgery across all of them.* The sixteen are
  the callers that never wanted anything but the handle, and collapsing
  them in one named accessor is what keeps the five paths that DO decide
  legible. A fourth arm is a core change first.
- *The "byte-identical project" is a canonical re-encoding of `get_project`
  rather than the package bytes.* That is the patch door's own definition
  and its argument (`Session.text`): two encodings of one project compare
  equal and two different projects cannot.
- *Checkbox 3 is only partly demonstrated.* Agreed, and said so above and in
  §3 of the proof rather than papered over: the mechanism is there, and no
  tool can reach the case.

**What the next tickets inherit.**

- **The proof section's shape, verbatim**, for D2·3: a fixture whose numbers
  are hand-computed, a marker edit, `refused(s, tool, op, what, sentence,
  …)` for each rule with the WHOLE sentence, and one `undo_claim` closing
  the batch. A new rule is a function shaped like `overlap_rule` plus one
  line in `main`.
- **The two reply shapes, verbatim**: an identity is
  `"\(actionName) made no change: the project is already in that state."`
  and a refusal is
  `"\(actionName) was refused at \(refusal.op): \(refusal.reason)"`. A rule
  that starts speaking at D2·3 changes nothing here; its sentence simply
  arrives through the second one.
- **Where the multi-op fixture goes when one exists.** No tool today can send
  a list where nothing applied and something was refused — `normalize_clip`'s
  ops have no rule to decline them, `CaptionLayout` probes its own batch and
  refuses app-side, and `consolidate_media` short-circuits an empty plan.
  §3 of the proof says so, and is where such a fixture lands.

**Owed.** Nothing from this ticket is unpaid on size: all three over-cap
files came down or held. Three things are named rather than done:

- **The empty undo group `performGroupedEdit` leaves** when the edit it wraps
  changes nothing, above. It belongs in `designs/reelcut-remaining.md` when
  somebody opens that document next; it is pre-existing and unreachable.
- **The multi-op refusal has no fixture**, because no tool can produce one.
  Named in §3 of the proof and above.
- **`Ok(None)` still appears in app-side doc comments** (`RecordingLanding`'s
  `addMedia`, a handful more) where it is describing the core's old spelling.
  Only the comments this ticket made FALSE were fixed; the sweep is D2·5's,
  with spec §6, the glossary and `app/CLAUDE.md`'s Rules.

### 5.3 D2·3 — the remaining rules speak (kpgalligan/reelcut#11)

**Commits.** `1f8cf38` (the size toll, alone and pure), `a531fb0` (the
ticket) and `0b91795` (what its review found, below).

**What landed.** Core only, plus the tests and the proof that measure it and
four app comments the change made false. No FFI change, no new export, no op
added or reworded in any of the four mirrors, no format bump, no new tool,
and nothing a person at the machine sees differently: a refused edit still
beeps and still leaves the undo stack alone.

**The sentences, verbatim**, because #12 and #13 quote them:

| Rule | Where | The sentence |
|---|---|---|
| a locked track | `edit_time::locked_track`, one function for three callers | `track 5 is locked, so the gap on it cannot be closed` · `…so an insert cannot open room on it` · `…so clip 13 cannot be shifted left to make the overlap` |
| the last track | `edit_track::remove_track` | `track 4 is the only track left, and a project must always have one` |
| a track that still holds clips | `edit_track::remove_track` | `track 5 still holds clips 12 and 13; pass with_clips: true to remove the track and its clips` |
| a media row a clip still shows | `edit_track::remove_media` | `media 1 is still used by clips 10, 11, 12 and 1 more; pass with_clips: true to remove the media and its clips` |
| a cut with nothing left to give | `edit_transition::add_transition` | `the cut before clip 16 has no room for an overlap: the 100 frames asked for clamp to nothing against the two clips' unused material, their neighbours and the overlap rule; pass ripple: true to make the overlap by shifting the timeline left instead` |
| a rippled cut with nowhere to shift | `edit_transition::add_transition_by_shift` | `clips 19 and 22 have no room to overlap by shifting: the overlap asked for is 1 frames and half of the shorter clip is 0 frames` · `clips 15 and 16 cannot overlap by shifting: no overlap from 1000 frames down to one leaves every track the shift moves inside the overlap rule` |
| an action that would overlap another | `edit_action`, one function for `add_action` and `set_action` | `action 20 on clip 10 already runs from 0 to 400 ticks, and two actions on one clip may not overlap` |
| an action past its clip | the same pair | `an action of 200 ticks at 900 would end at 1100, past clip 10's own end at 1000 ticks` |
| a move off the track stack | `edit_clip::move_clips` | `clip 17 would land on track index 5, which is out of range (0..5)` |

Four things about that table are decisions, not accidents:

- **A rule with more than one site writes its sentence once.** Three ops
  refuse over a lock and pass a clause to `locked_track`; two ops ask the
  same two questions of an action and call the same two writers; two ops are
  the way past a `with_clips` refusal and both name their clips through
  `clip_list`. Two ops cannot drift apart on one rule.
- **Where an argument would let the op through, the sentence names that
  argument** — `with_clips: true`, `ripple: true`. That is the part a caller
  ACTS on, and it is the difference between a reason and a description.
- **A clip list is capped at three ids and a count** (`clip_list`). A media
  used by two hundred clips would otherwise answer with a sentence nothing
  could read; three ids plus the total is everything a caller needs to start.
- **`remove_track` asks the last-track question FIRST**, because
  `with_clips: true` is the way past its other refusal and past this one it
  is not: a caller told about the clips would send it and be refused again.
  The proof sends it and scores the same sentence either way.

**Two rules beyond the ticket's five, and one short of the brief's seven.**
`remove_track`'s "still holds clips" and `add_action`'s "past the clip's
end" are siblings of two of the five — the same `if` chain, the same doc
sentence, the same op — and a function that speaks for one of its two
refusals and not the other re-creates the ambiguity this candidate exists to
remove. The brief also named two smaller ones from `Outcome::Identity`'s
doc; the move to a track index the document has not got landed (its own
comment had called it a refusal since it was written, over a line that
answered an identity), and **a trim whose two clamps crossed did not**. It
is one of a family — a slip or a roll the clamps reduce to nothing, a rate
stretch outside ×0.1 – ×10 — where the clamp landing on where the clip
already is makes an identity the honest answer too, none of them is on the
spec's list (#8, decision 3), and paying `edit_clip.rs`'s toll to add them
would be a second pure move in a ticket that already made one. The family is
named in `Outcome::Identity`'s doc as where a next ticket starts.

**The ticket's first criterion is met through the FFI for every rule and
over MCP for five of them.** Said plainly, because the review said it
plainly: of the ticket's five named rules, a locked track, the last track
and the action rule arrive over MCP in the core's words; **a media row a
clip still shows and a cut with nothing left to give do not**, and neither
does the locked-track rule's third caller. An
app-side guard asks the same question one step earlier and answers in its
own words: `AgentServer+Media.swift`'s and `AgentServer+Tracks.swift`'s
`with_clips` guards, and `AgentServer+Transitions.swift`'s trial-apply,
which catches `.project == nil` and so catches a refusal exactly as it
caught an identity. Behaviour is therefore UNCHANGED at those four doors,
which is this ticket's other claim. The proof scores them through a
`shadowed` helper rather than `refused`, asserting the app's sentence WHOLE,
so the checks D2·4 has to move are already written and their old answers are
on record. #12's own acceptance criterion — "the proof asserts the core's
wording at each of those ops" — is where they change.

**`Outcome::Identity`'s doc is rewritten**, and is still the one place that
says which refusals can say why. It now lists the rules that speak, the
family that does not (above), and the nine or so empty-selection answers
that stay identities on purpose.

**Tests.** `core/tests/refusal.rs` goes from 220 lines to 514: one fixture
(`rules_project`, five tracks at 600 000 fps — ONE TICK per frame — so every
expected number is hand-computed and no snap moves it) and twelve tests, each
asserting a WHOLE sentence through `Handle::refuses_with` and each with a
BOUNDARY beside it that applies: an unlocked track closes its gap, a cut with
handles takes its transition, an abutting action lands, a move onto a track
the stack has lands. `make test` 641 → **653 passed / 0 failed**.

**The proof.** `tools/proof/refusal_proof.py` **40/40 → 113/113**, six new
sections (4 to 9) each shaped like §1's `overlap_rule`: a fixture with
hand-computed numbers, `undo_marker`, the refusals with their whole
sentences and the absence of the deleted paragraph, a boundary read back
through `get_project`, and `undo_claim`. §4 also scores the distinction the
whole candidate is about at ONE op: `close_gap` on a locked track is the
rule's sentence and `close_gap` on a time that is on a clip is still the
identity's.

`tools/proof/phase1_proof.py` keeps its **66/66** with two checks rewritten:
its locked-track `close_gap` and `insert_clip` asserted "made no change",
which is now the wrong answer, and they assert the rule's whole sentence
through a new `refused_with` helper (`endswith`, and the identity's phrase
ABSENT). Its old `refuses` helper keeps its meaning for genuine identities.

**Mutants.** Eight, all caught, and the seventh is the one worth reading.

| Mutant | Score |
|---|---|
| `close_gap`'s locked refusal back to a bare identity | refusal 112/113, phase1 65/66 |
| `locked_track` drops the track id ("a track is locked") | refusal 111/113, phase1 64/66 |
| the last-track refusal back to a bare identity | refusal 111/113 |
| the past-the-end sentence reports the CLIP's end where the action's belongs | refusal 111/113 |
| the overlap sentence drops the action id | refusal 111/113 |
| the off-the-stack refusal back to a bare identity | refusal 112/113 |
| the transition's "no room" refusal back to a bare identity | **refusal 113/113** — and `core/tests/refusal.rs` 20/21 |
| `clip_list` loses its three-id cap | `core/tests/refusal.rs` 20/21 |

The seventh is the shadow measured rather than asserted: the app's
trial-apply answers before the core is asked, so the MCP proof cannot tell
that rule's refusal from its identity and the core test is the only
instrument that can. The eighth is the same shape for a sentence no MCP
caller can reach at all. Both are the reason those sections are `shadowed`
and not `refused`, and both become proof mutants at D2·4.

**Size.** The toll was paid first and alone (`1f8cf38`): `edit_track.rs` was
671 and had to take three refusals, so `set_canvas` with `check_dimension`,
`rescale` and `resnap` left for `core/src/edit_canvas.rs` (**224** lines,
under the 400-line new-file cap) — the cut `core/CLAUDE.md` had already
named, not one line of logic changed. `edit_track.rs` 671 → 473 → **520**
with the ticket, off the over-cap list for the first time.

`edit_clip.rs` is over the cap with no named seam, so the five lines its
refusal added were paid for INSIDE the file — fifteen added against fifteen
deleted, a net nothing — the way D2·1's and D2·2's reviews set the
precedent:
`split_under_playhead` was a second copy of `split_clips`'s loop and now
CALLS it, which the crate's own "one implementation per algorithm" rule
wanted anyway. The file is **1028**, exactly where it started. Nothing else
this ticket touched is near the cap: `edit_time.rs` **560**,
`edit_transition.rs` **584**, `edit_action.rs` **357**, `edit_insert.rs`
**145**, `outcome.rs` **105**.

**Verification.** `make test` 653 passed / 0 failed, `make lint` and
`cargo fmt --check` clean, `make typecheck` 0 errors and the 4 known
AVFoundation warnings, `make app` built, the startup parity log empty at
every launch. Every proof script run against the rebuilt binary on a freshly
launched instance of its own: **refusal 113/113**, phase1 **66/66**, phase2
**85/85**, phase3 **123/123**, phase3_silence_scope **8/8**, phase4
**84/84**, phase5 **88/88**, phase6 **168/168**, phase7 **92/92**, phase8
**79/79**, phase9 **216/216**, patch_door **261/261**, remaining **79/79**,
recording **121/121** with the granted tier skipped by name (a locked
console, no shareable display: 66 checks). `refusal_probe.py`, which needs no
running app, is **15/15** and still prints its note about the empty undo
group `performGroupedEdit` leaves.

**Documents.** `core/CLAUDE.md`'s module map gains `edit_canvas.rs` and
`edit_track.rs` loses its "next cut" note and its place on the over-cap list;
`tools/proof/README.md` gains the six sections in the proof's table, the
paragraph naming the four shadowed checks, and a correction to its phase 8
section. Spec §6's op table needs no change — every row already describes
these refusals, and what moved is the CHANNEL, not the semantics. The
glossary, spec §5.5 and both rulebooks' Errors rules are D2·5's.

**Owed.**

- **The four shadowed rules**, above: D2·4's, and the proof's `shadowed`
  helper is where each check becomes a `refused`.
- **The clamped edge family** — a slip or a roll the clamps reduce to
  nothing, a roll with no predecessor, a trim whose two clamps crossed, a
  rate stretch outside ×0.1 – ×10, `detach_audio` with no audio,
  `set_transition_duration` with no predecessor — still answers `Identity`,
  named in `Outcome::Identity`'s doc.
- **`designs/reelcut-remaining.md` §3's table** still lists
  `core/src/edit_track.rs` at 674 and `core/src/edit_clip.rs` at 1042. D2·5
  regenerates it against the tree; `edit_track.rs` comes off it.

**What its review found.** The two-axis review ran against `a531fb0`. The
standards axis found no hard violation of a documented standard; both axes
found real things. Fixed in `0b91795`:

- **A latent panic in `clip_list`.** `some[..some.len() - 1]` underflows on
  an empty slice, which `core/CLAUDE.md`'s "no input may panic" forbids
  however unreachable it is today. It is `split_last` now, with the empty
  arm written out, and the tests gained the two counts that were untested:
  ONE clip (the singular arm) and THREE (the longest list that is still a
  list). Found twice, once by the adversarial read-back this repo's recipe
  asks for and once by the standards axis.
- **The record named a commit that is not on the branch** (`c9875f3`, from
  an amend), and claimed `edit_clip.rs` grew by five lines where the diff is
  fifteen added against fifteen deleted. Exactly the slip D2·2's record had
  to fix, made the same way.
- **The "verbatim" table was not verbatim.** It quoted `clip 12 would land
  on track index 5` where the code and the test say `clip 17`. In a table
  the next two tickets are told to quote from, a wrong id is the whole
  defect.
- **`actions_overlap` read as a predicate** after it was changed to answer
  the offending action; it is `overlapping_action`, and its doc says what it
  answers rather than what it tests.
- **`phase1_proof.py`'s new `refused_with` was weaker than its docstring** —
  it promised the whole sentence and matched the tail alone, which is the
  finding D2·2's review made about `refused()` one ticket earlier. It pins
  `was refused at <op>: <sentence>` now, the same bar `refusal_proof.py`
  holds.
- **Two sentences read badly to the caller they are for.** "1 frames were
  asked for" is now "the overlap asked for is 1 frames" (the crate does not
  pluralise a unit — "500 ticks" — but the verb can agree with the noun),
  and "an action at 900 ticks for 200" is "an action of 200 ticks at 900",
  so both numbers carry their unit.
- **A comment claimed a sentence names the number the caller sent.** It
  names the request in whole FRAMES, which is the unit every clamp above it
  is measured in; the comment says so.
- **The module map was not updated for two shared helpers.**
  `core/CLAUDE.md`'s `edit_time.rs` entry names `locked_track` and its three
  callers, and its `edit_track.rs` entry names `clip_list`.

Judged not real:

- *Three rules beyond the spec's list are scope creep.* Two are siblings in
  the same `if` chain of the same op as a rule the ticket named, where
  silence on one of two would re-create the ambiguity inside one function;
  the third is a site whose own comment had called it a refusal for as long
  as it has existed. All three are argued above and named in the record,
  which is what decision 3's "only refusals that already have a reason" is
  protecting.
- *`split_under_playhead` rewritten to call `split_clips` is unasked.* It is
  the size toll, which the cap rule requires a file at the cap to pay before
  it takes anything on, and it is the crate's own "one implementation per
  algorithm" rule applied to a second copy of one loop. Behaviour-preserving,
  and both reviews verified that independently.
- *AC1 is unmet for two of the five rules.* Agreed and not fixed here: the
  shadows are `AgentServer`'s, deleting them is #12's whole subject, and
  #12's own criterion is that this proof asserts the core's wording at those
  ops. Doing it here would change the sentences `phase8_proof.py` asserts,
  which is the other half of that ticket. Stated above rather than papered
  over, and measured by mutant 7.

### 5.4 D2·4 — the app's guesses are deleted (kpgalligan/reelcut#12)

**Commits.** `06dd67b` (the ticket), `aefb0b9` (the mutant table) and
`4d54d69` (what its review found, below).

**What landed.** App only — three agent handlers, two proof scripts, the
app's rulebook and the proof README. No core change, no FFI change, no op
added or reworded in any of the four mirrors, no format bump, no new tool,
and nothing a person at the machine sees differently. D2·3 gave all four of
these rules their words; this is the deletion that prefactor paid for, and
the whole app-side change is three functions getting shorter.

**What went.**

| Where | What it was | Lines |
|---|---|---|
| `AgentServer+Transitions.swift` | `addTransition`'s trial-apply (`.project == nil`, which caught a refusal exactly as it caught an identity) and the two sentences it chose between — the handle form's "neither side of the cut has media beyond it…" and the rippled form's "with ripple the shift clamped below one frame — … or … or …" | −27 +6 |
| `AgentServer+Tracks.swift` | `removeTrack`'s clip count and `Track 1 ("Track 1") still holds 1 clip. Pass with_clips: true to remove them too.` | −6 |
| `AgentServer+Media.swift` | `removeMedia`'s user count and `A.mov is used by 1 clip. Pass with_clips: true to remove them too.` | −6 |

Thirty-nine lines of code and inline comment out, six back. The three files
go 140 → **123**, 247 → **243** and 327 → **320**: twenty-eight lines
smaller with their doc comments counted, and what a caller hears at those
four refusals is now the core's own sentence through `performGroupedEdit`'s
one format string. The sentences the app used to write are kept in the table
ABOVE and in the comments of the proof sections that assert the new ones, so
a reader can still see what they said; §5.3's table is the core's own
sentences, which is a different list.

**What stayed, and why each is not a duplicate.** The spec's seventh
decision named five things to delete. Three are above; the other two were
verified against the code and kept. The line the whole server can be read by
is: **a check that predicts a RULE's refusal goes; a check that names the
CALL, or reports something the core cannot know, stays.**

- **`SilenceDetector+Walls.overlapWalls`** re-derives the half rule
  (`[B.start − ov, A.end + ov]`, so the nearest legal cut leaves `2·ov`
  across the overlap) and is NOT predicting a refusal: it shapes the ranges
  Remove Silences PROPOSES, before any op exists. The op those ranges go to,
  `ripple_delete_ranges`, does not check the overlap rule at all
  (`core/src/edit_time.rs` clears, shifts and calls
  `set_gained_transitions`; `validate` has no overlap check either), so
  deleting the walls would not move a refusal into the core — it would let
  Remove Silences quietly build a project the rule forbids. A
  proposal-shaper, not a second copy of a refusal.
- **`normalizeClip`'s all-skipped answer** reports what could not be
  MEASURED, and the measurement is Swift's: the level comes from
  `cache/peaks/<media id>.bin`, which is not in the model and which the core
  has never seen (spec §7). With no reading there is no op to send, so the
  shared reply would be the identity's — and "the project is already in that
  state" would send a caller to look at its volumes when what happened is
  that its peaks were not there to read.
  The check is restated against `input` rather than `plan`, so that it
  asks about the READ and not about what the core would answer, and its old
  justification — the shared message "goes on to talk about the overlap
  rule" — is gone, because since D2·2 it does not.
- **Six argument checks** answer a caller who left something out, and none
  is a rule's refusal restated: `set_transition_style` with neither key,
  `ripple_delete_ranges` with an empty array, and `set_track`, `set_marker`
  and `set_canvas` with no keys. The core answers `Outcome::Identity` for
  each — correctly, since nothing was asked for — and an identity has
  nothing to say beyond that. **The spec named `set_transition_style`'s
  among the deletions and this ticket did not make it**: the other five are
  the same shape and are untouched, so deleting one of six would leave the
  server inconsistent for a caller and the record with no line to draw. What
  its doc comment CLAIMED — that the shared reply "would be the wrong one" —
  was the false part, and is rewritten to say it names an argument. The same
  false claim was found and fixed in `ripple_delete_ranges`, which is not on
  the spec's list at all and said the shared reply "would report [it] as the
  overlap-rule refusal".

  **A ticket does not reverse a spec decision in a commit message**, so the
  line this paragraph draws is written where decisions live: spec §11's
  **D2-1**, added before the fix and naming the amendment to #8's seventh
  decision. Its rule is the one above — a check that predicts a RULE goes, a
  check that names the CALL stays — and it covers `normalize_clip` too. The
  code-review's spec axis is what asked for it, in those words: the reason
  was sound and the order was wrong.
- **`EditorViewController+Inspector.setTransitionKindCommand`'s trial-apply**
  stays. It is a UI path deciding whether to put up the Shift Clips Left
  SHEET for a person, which is the one thing spec #8 puts out of scope
  ("showing a refusal's sentence to the person using the app"), and it
  writes no refusal sentence for any caller — a throw is left to `applyEdit`,
  which presents the core's own. Named here so the next reader does not find
  it and think it was missed.
- **The tool descriptions that teach the overlap rule** — five, in
  `AgentCatalog+Clips.swift`, `+Transitions.swift` and `+Files.swift` — stay,
  as the ticket says: prose that teaches a rule BEFORE a call is not prose
  that explains a refusal after it.

**All four `shadowed` checks are real assertions now**, which is the
ticket's third criterion, and the helper is deleted with them.
`refusal_proof.py` **113/113 → 116/116**: §5d and §6b assert the core's
sentence naming the CLIP where the app named a file or a count, §7b asserts
the request in whole FRAMES (15, hand-computed from half a second at 30 fps
and scored as a line of its own), and §7d asserts `locked_track`'s third
caller — the one §4 could not reach. The three added checks are §7b's frame
arithmetic and a new §5e, which sends the argument the new sentence NAMES
(`with_clips: true`) and reads back that the track and its clip both went.

`phase8_proof.py` keeps its **79/79** with three checks rewritten. Its §2 is
phase 8c's defect fix — "is this media used" walks the nests — and it
asserted the handler's `is used by N clips.`; the same fixture asserts the
core's whole sentence now, and the both-levels check has MORE teeth than
before: media used once at the top level and once inside a nest is refused
naming BOTH clip ids, where a count of the top level alone names one.
`MediaUsage.swift` stays with the Media tab's alert as its only caller,
which is where a person reads a file name.

**The rulebook line the ticket asked for** is two paragraphs in
`app/CLAUDE.md`'s Rules. The first says a refusal is the core's sentence and
no handler writes one, with what a handler may still refuse by name (the
call, and a composite's own reading). The second says why the two deliberate
swallows swallow: `ReelProject.scoped(_:)` drops `no nest with id N` because
every caller is a VIEW asking about view state `clampViewState` has already
cleared, so a nil there is a race with an undo; and `updateLiveEdit`
swallows every answer but `.applied` because a refused tick is NORMAL
mid-drag — the edge is past a neighbour for a moment — and recovers on the
next tick with the last good frame still on screen, where a drag that spoke
would interrupt the gesture to say something the person is already fixing
with the mouse. `endLiveEdit` registering no step when every tick was
swallowed is what makes the two consistent.

**Mutants.** Five, all caught, and the fourth is the one worth reading.

| Mutant | Score |
|---|---|
| `addTransition`'s trial-apply and its two sentences put back (the D2·3 state) | refusal **114/116** |
| `removeMedia`'s `with_clips` count put back | refusal **115/116**, phase8 **76/79** |
| `removeTrack`'s `with_clips` count put back | refusal **115/116** |
| the transition's "no room" refusal back to a bare `Outcome::Identity` | refusal **115/116** |
| the same sentence reporting the request in TICKS where it says frames (300000 for 15) | refusal **115/116** |

The fourth is D2·3's own mutant 7, which that ticket's proof scored
**113/113** — it could not see the rule at all, because the trial-apply in
front of it answered the same either way, and `core/tests/refusal.rs` was
the only instrument that could take it. It is caught here. That is the
shadow closing, measured rather than asserted, and it is the reason the
first mutant above is worth its build: with the app's answer back, two
sections stop measuring the core.

The second mutant is also the one that shows why the app's sentence was the
worse one for a caller: `C.mov is used by 2 clips.` names neither clip, and
the core's names both.

**Size.** Nothing grew: every file this ticket touched is smaller or the
same. `AgentServer+Clips.swift` is at **847**, over the ~600 cap, and its
one comment was reworded three lines for three, so the file at the cap took
nothing on. `AgentServer+Audio.swift` is **162**, six longer than the 156 it
started at: a doc paragraph that says why its check is not a guess, where
the six it replaced said the shared reply lectured about the overlap rule.
It is nowhere near the cap. `designs/reelcut-remaining.md` §3's two `AgentServer` rows are
unchanged by this ticket and are still D2·5's to regenerate.

**Verification.** `make test` **653 passed / 0 failed** (D2·3's number; no
Rust changed), `make lint` and `cargo fmt --check` clean, `make typecheck` 0
errors and the 4 known AVFoundation warnings, `make app` built, the startup
parity log empty at every launch. Every proof script run against the rebuilt
binary on a freshly launched instance of its own: **refusal 116/116**,
phase1 **66/66**, phase2 **85/85**, phase3 **123/123**, phase3_silence_scope
**8/8**, phase4 **84/84**, phase5 **88/88**, phase6 **168/168**, phase7
**92/92**, phase8 **79/79**, phase9 **216/216**, patch_door **261/261**,
remaining **79/79**, recording **121/121** with the granted tier skipped by
name (a locked console, no shareable display: 66 checks). `refusal_probe.py`
is **15/15** and still prints its note about the empty undo group
`performGroupedEdit` leaves.

**Documents.** `app/CLAUDE.md` gains the two Rules paragraphs above.
`tools/proof/README.md`: the refusal section's score line, §5 to §7 of its
table, the `shadowed` paragraph (now the account of what was deleted), and
the phase 8 section's §2 paragraph. Spec §6's op table needs no change —
every row already describes these refusals, and what moved is which SIDE
says them. The glossary, spec §5.5 and both rulebooks' Errors rules are
still D2·5's.

**Owed.**

- **Nothing about the six argument checks**: spec §11's D2-1 settles them,
  and `app/CLAUDE.md`'s new rule says the same thing where a Swift author
  will read it. Named here only so D2·5 does not re-open it.
- **The clamped-edge family** still answers `Identity`, named in
  `Outcome::Identity`'s doc — D2·3's bequest, untouched here.
- **`Ok(None)` in app-side doc comments** where they describe the core's old
  spelling. Only the comments this ticket made FALSE were fixed; the sweep
  is still D2·5's.

**What its review found.** The two-axis review ran against `aefb0b9`. Both
axes found real things; neither found a hard violation of a documented
standard in the CODE. Fixed in `4d54d69`:

- **A spec decision reversed in a commit message.** The spec axis put it
  exactly right: the reason for keeping `set_transition_style`'s refusal was
  sound and the ORDER was wrong, because the root rulebook says a phase that
  needs a new decision records it BEFORE the code. Spec §11 gains **D2-1**,
  which draws the line for all six argument checks and for `normalize_clip`
  and names the amendment to #8's seventh decision; `app/CLAUDE.md`'s rule
  and `AgentServer+Audio.swift`'s doc point at it.
- **A false pointer, three times.** "the app's old wording is kept in road
  map 7 §5.3's table" — §5.3's table is the CORE's sentences, and the app's
  deleted ones are in §5.4's own "what went" table. In
  `tools/proof/README.md`, in `refusal_proof.py`'s section comment and in
  this record: every reader sent for the old answers would have found the
  new ones.
- **`MediaUsage.swift` was left stale by its own neighbour's fix.** Its
  header still said the question is asked in THREE places (two now) and
  `usesMedia`'s doc still called itself "the question `remove_media` asks
  before it refuses". The ticket updated the comment POINTING at that file
  and not the file.
- **History in a rulebook.** The new `app/CLAUDE.md` rule said "deepening
  D2·4 deleted the last of those", which is a record's sentence, not a
  rule's. Both paragraphs are tighter as well: +25 lines rather than +30.
- **A quoted sentence that was not verbatim.** This record's table and §5d's
  comment both said `Track 1 ("Video 1")` where the fixture's track is
  called "Track 1" — the same defect D2·3's review caught one ticket
  earlier, in a table the next ticket is told to quote from.
- **Two claims this record made about its own change.** The Audio file's
  growth was called "all doc" when three lines were the guard's comment, and
  the identity's sentence was called FALSE where what is wrong with it is
  that it points a caller at its volumes instead of its cache. Both are
  rewritten, and the file is **162** against the 156 it started at.
- **`designs/reelcut-app-notes.md` still described the deleted rewording**
  as live behaviour, and `aefb0b9` was not named in the Commits line.

Judged not real:

- *`phase8_proof.py`'s `with_clips: true` check is implied by the
  whole-sentence check above it.* True while that check passes; when it
  fails, this one still says whether the reply tells a caller how to go on,
  which is what a transcript is for — and it did exactly that under mutant
  2.
- *§5's batch needs two undos now.* §6d and §7e already do that, for the
  same reason: a boundary that LANDS is a real edit and is undone by name
  before `undo_claim` makes the single-undo claim about the marker.
- *`AgentServer+Audio.swift` grew in a ticket whose criterion is that the
  handlers get smaller.* The criterion is about the three handlers that
  wrote refusal sentences, and all three shrank. The fourth file gained a
  paragraph saying why its check is not one of them, which is what the
  ticket asked the record and the rulebook to make legible.

### 5.5 D2·5 — contract and record (kpgalligan/reelcut#13)

**Commits.** `315b7f6` (the ticket), `dcdc7fc` (the mutant table), `bfbc2ac`
and `33a8ecc` (the adversarial read-back: four corrections to the record, and
the one design document that is not a closed record), and `c91c6fc` (what
its review found, below).

**What landed.** Documents, doc comments and two rotted instruments. No
behaviour changed anywhere — no core logic, no FFI, no op added or reworded
in any of the four mirrors, no format bump, no new tool — and that is the
claim this ticket had to make good on: **every proof scores exactly what it
scored before** (refusal 116/116, patch_door 261/261, the nine phase scripts
unchanged), because what moved is what the tree SAYS about itself.

**The glossary gained the two words the candidate is about.** `CONTEXT.md`'s
**Op** now says an op answers one of exactly three ways and that a request
the core could not read is none of the three — "a mistake in the asking
rather than an answer about the project". Beside it are two new entries, in
the glossary's own register (no file names, no types):

- **Identity** — understood, and nothing to change: the project already says
  what was asked, or the op was handed an empty selection. No undo step and
  *nothing to explain*, because a caller told about a rule here would go
  looking for one it did not break. *Avoid*: no-op, failure, "nothing
  happened" — all three hide the difference from a refusal.
- **Refusal** — a rule declining an op, in that rule's own sentence, naming
  what a caller could send instead rather than restating the rule. Like an
  identity it leaves the project as it was and makes no undo step; unlike an
  identity it says why. *Avoid*: error, rejection, failure, "invalid" — an
  error is a request that could not be read.

**Spec §6 DID need changing, and its op table did not.** D2·3's and D2·4's
records both say "§6's op table needs no change — what moved is the
channel"; that is true of the rows and false of the section, because §6's
preamble carried the definition the whole candidate retires:
*`"Refuses" = returns `None` at the FFI`*. It is now a paragraph headed
**how to read a "refuses" below**: the three answers, then the reading rule —
a row names the RULE, a row that says an op refuses on an empty selection or
when nothing changes is naming an identity, and which of the rest speak out
loud is a list §5.5 says where to find. That rule is what lets fifty-seven
rows stay as they are. Three rows still spelled an ANSWER and were wrong
either way: `add_transition`'s "a request that clamps below one frame is
`None`" and its rippled twin's "an incoming clip on a locked track, or
nothing left above one frame, is `None`" are refusals with sentences since
D2·3, and `set_transition_style`'s "NEITHER key given is `None`" is an
identity. Each now says which.

**The rest of the contract texts.**

- **Spec §5.5** gains the paragraph the reading rule points at: an identity
  and a refusal are identical to the person at the machine and differ only
  in what a caller can be told; which of §6's "refuses" carry a sentence is a
  list that GROWS and `Outcome::Identity`'s doc is the one place it is kept;
  and the two families that will never join it — an empty selection (twelve
  ops through eight guards) and a clamp that landed where the clip already
  was.
- **Spec §7.10** had no row for `outcome.rs` or `edit_canvas.rs` at all, and
  still typed `apply` as `Result<Option<Project>, String>`. All three fixed;
  the module map is the root rulebook's own list of what a phase updates.
- **Spec §8** listed "pure ops returning `Option` (identity is `None`)" among
  the rules carried over from Rasterize verbatim. They are not carried over
  verbatim any more, and it says so.
- **Spec §11's R5-3** said a transition with no handle is "a domain refusal
  (`Ok(None)`)". The DECISION is untouched — only the spelling of the answer,
  which is `Outcome::Refused` and has been since D2·3.
- **The root `CLAUDE.md` was the one with the flatly false rule**, not the
  two the ticket named: its FFI contract said every edit "returns `Option`"
  and its Errors bullet said "NULL with `err_out` untouched is a refusal or
  an identity" — the ambiguity itself, written as a rule. Both now state the
  three arms and the three distinguishable NULLs, and say that the two
  message channels are never both written.
- **`core/CLAUDE.md`'s Errors and Purity rules were already right** (D2·1
  pulled them forward and its review recorded that as deliberate). Verified
  line by line against `ffi_edit.rs` and the header; nothing to do.
- **`app/CLAUDE.md`** gains the app side of the same two facts: the
  `ReelCore.swift` map entry names the ONE read of `rc_project_apply`'s two
  message channels and the order the header reads them in, and the hygiene
  line that said "Refusals beep, errors never crash" now says a refusal and
  an identity BOTH beep and neither makes an undo step — which is what makes
  a person's experience of the two identical, and is deliberate.
- **`core/src/edit.rs`'s Results section** was already three-armed; it gains
  the same two-line reading rule for its own table, pointing at
  `Outcome::Identity`. **The file is 895, exactly where this ticket found
  it**: the identity bullet and the non-media paragraph were tightened to pay
  for the two lines, because a standing table exemption is for TABLE rows and
  not for contract prose. D2·1's own eight lines are still unpaid, and §6
  names them.
- **`README.md`** repeated the FFI contract correctly already. It gains a
  short paragraph where an agent meets the tool list: an edit that did not
  happen says which of the two it was, an identity names no rule, a refusal
  carries the rule's own sentence and the argument that would let the call
  through, and neither leaves an undo step.

**The `Ok(None)` sweep: fifteen comments, not seven.** Seven app-side, the
number the ticket predicted — `MediaUsage`, `MediaPaneCommands`,
`RecordingLanding`, `EditorViewController+AddClips`,
`EditorViewController+Clipboard`, `VideoPane` and `ClipPane`. Four more in
`core/tests` (`scope.rs`, `schema_v8.rs`, `zoom.rs`, `add_transition.rs`),
which D2·1's sweep of `core/src` had not reached, one in `core/src/export.rs`
(a QUERY, which has neither middle arm — it says so now), and three in
`tools/proof` where a comment called an IDENTITY a documented refusal
(`phase2_proof.py`'s `refuses` helper, `phase3_proof.py`, `phase9_proof.py`).
`designs/reelcut-effects-survey.md`'s E1 paragraph — the one DESIGN document
that is not a closed record, since E3–E9 are still live there — quoted the
app's deleted sentence as the tool's answer and called `roll`'s gap refusal
`Ok(None)`; the design is left as it was written and a dated **Superseded**
note says what D2 changed, which is the shape spec §11's own amendments take.
Two of the seven app comments were saying the opposite of the code rather
than merely spelling it the old way, which is the reason for the sweep:

- **`ClipPane.swift` on the typed In and Out fields** listed the clamp
  landing where the edge already is, the two clamps crossing, and the overlap
  rule as one answer. The first two are identities — a clamp landing where
  the clip already is has no rule to name — and the third is a refusal
  carrying that rule's sentence; the comment draws the line now, and the file
  is back at 609 (it is over the cap, so the sentence was shortened to pay).
- **`EditorViewController+AddClips.swift` QUOTED `add_media`'s doc**: "The
  caller that gets `None` looks the path up to find the id that is already
  there". D2·1 rewrote that sentence in `edit_track.rs` and the quotation was
  left pointing at words that are no longer there. A quotation is the one
  kind of stale comment a reader cannot correct for themselves.

**The empty-selection identities, counted rather than estimated.** The spec
says "roughly nine sites"; the family is **fourteen ops, eight of them
behind a guard of their own** —
`edit_clip`'s `move_clips`, `delete_clips` and `duplicate_clips`,
`edit_props`'s `patch_clips` (the one guard behind all five patch ops),
`edit_nest`'s `nest_clips`, `edit_paste`'s `paste` (an empty payload), and
`edit_time`'s `ripple_delete` and `ripple_delete_ranges` (ranges that merge
to nothing), with `split_clips` and `paste_attributes` reaching the same
answer through `finish` and no guard at all. They stay identities because
**nothing was asked for**, so there is no rule a sentence could name. The list is in
`Outcome::Identity`'s doc, which is where the core keeps every such list, and
the two families are named in spec §5.5 so a reader meets them without
grepping. **The clamped-edge family** — a slip or a roll the clamps reduce to
nothing, a roll with no predecessor, a trim whose two clamps crossed, a rate
stretch outside ×0.1 – ×10, `detach_audio` with no audio,
`set_transition_duration` with no predecessor — is where a next ticket
starts, and is named in that same doc and in §6 below.

**Two rotted instruments, found by running every script rather than the
twelve.** Both were broken by D2·2's Swift change and neither was noticed,
because D2·2 to D2·4 ran the MCP proofs and `refusal_probe.py` and nothing
else. `preview_validity_probe.py` force-unwrapped `applying(_:)`'s answer
(`…)!`) where a `ReelEdit` is not optional, and `recording_probe.py` read
`raw?.snapshot` off one. Both are one-line fixes to the probes' embedded
`main.swift` (`.project`, the accessor `ReelEdit.swift` exists for), and both
score what they scored before: **19/19 with 5 skipped** and **858/858**.
The repo's rule is that a probe that will not build is a scored FAILURE and
not an exit, and it earned its keep twice here.

**And two cross-build references that can never build again.**
`phase5_chrome.py`'s sections 3–7 and `recording_probe.py`'s §6b compile an
OLD `app/Sources` against the CURRENT core — one core, two app trees, so the
two binaries differ by the phase's own changes and nothing else. **D2·1's
fourth parameter on `rc_project_apply` ends that**: the reference commits'
own `ReelCore.swift` calls the three-argument export, no guard in
`harness/main.swift` is the fix, and nothing in this repo can make a 2026 app
tree call a 2026-09 header. Both scripts now recognise that one cause by name
— the error must name `rc_project_apply` AND the reference tree's
`ReelCore.swift`; anything else is still the failure it was — and SKIP it
with the reason and the count printed, which is the same discipline the
locked-console skips already use. `phase5_chrome.py` is **36/36 with
sections 3 to 7 skipped** where it was 81/81, and `recording_probe.py`
**858/858 with 43 skipped** (41 the console, 2 this) where it was 917/917.
A skip is not a pass, so both numbers and both reasons are in
`tools/proof/README.md` as well as here. **What is lost is real**: the meter's
byte comparison against the tree before it existed, and the welcome window's.
A phase that wants them back has to give the reference build a core of its
own era, which is a different instrument.

**The ledger, regenerated row by row against `wc -l`** (not by eye — that is
D1·6's review's lesson, made the rule here). **Thirty rows became
twenty-nine**: `core/src/edit_track.rs` came off it, 674 → **522**, because
D2·3 cut `edit_canvas.rs` out of it and paid the toll first and alone. Six
counts were stale: `ReelCore.swift` 1507 → **1500**, `ProjectDocument.swift`
1353 → **1352**, `AgentServer.swift` 772 → **771**, `core/src/edit_clip.rs`
1042 → **1028**, `core/src/edit.rs` 887 → **895** (which also moves it above
`AudioDSP.swift` in the order), and the header's date and count. Nothing
joined the list. The section also gains the one thing D2·2 said belonged
here: `performGroupedEdit`'s EMPTY undo group for an edit that changes
nothing — pre-existing, unreachable by any caller, and printed as a note by
`refusal_probe.py` so the day a caller does reach it the probe already says
so.

**Verification.** `make test` **653 passed / 0 failed** (D2·3's number; no
Rust logic changed), `make lint` and `cargo fmt --check` clean, `make
typecheck` 0 errors and the 4 known AVFoundation warnings, `make app` built,
and the startup parity log empty at every launch below.

**Every proof script in the tree**, each MCP one on a freshly launched
instance of its own on port 4845. Over MCP: refusal **116/116**, phase1
**66/66**, phase2 **85/85**, phase3 **123/123**, phase3_silence_scope
**8/8**, phase4 **84/84**, phase5 **88/88**, phase6 **168/168**, phase7
**92/92**, phase8 **79/79**, phase9 **216/216**, patch_door **261/261**,
remaining **79/79**, recording **121/121** with the granted tier skipped by
name (a locked console, no shareable display: 66 checks). Offscreen:
refusal_probe **15/15** (still printing its note about the empty undo group),
remaining_probe **170/170**, phase9_probe **48/48**, transition_sheet_probe
**32/32**, preview_validity_probe **19/19** (5 skipped, the locked console),
preview_refresh_probe **0/0** (58 skipped, the same), recording_probe
**858/858** (43 skipped, above). Chrome: phase2 **26/26**, phase3 **33/33**,
phase4 **59/59**, phase5 **36/36** (sections 3–7 skipped, above), phase6
**70/70**, phase7 **78/78**, phase9 **62/62**, phase8 **144/150** — the
documented locked-console score for that script
(`designs/reelcut-remaining.md` §4).

**Size.** `core/src/edit.rs` **895**, exactly where it started, paid inside
the file. `app/Sources/ClipPane.swift` **609** and `VideoPane.swift` **1411**,
both at their starting counts for the same reason. `core/src/outcome.rs` 105
→ **114**, well under the cap and the file whose whole job is holding that
list. Nothing else changed size.

**Mutants.** Two, the pair spec kpgalligan/reelcut#8 asks for, each a rebuild
of the core and the app and a fresh instance on port 4845, each reverted
afterwards and every score shown green again (refusal 116/116, phase1 66/66,
phase8 79/79, `core/tests/refusal.rs` 21/21, refusal_probe 15/15). Both
caught, at every level that can see them.

| Mutant | Score |
|---|---|
| the reason DISCARDED as it crosses the FFI (`ffi_edit.rs`'s `Refused` arm returns NULL without writing `reason_out`) | `core/tests/refusal.rs` **7/21**; refusal **100/116**; phase1 **64/66**; phase8 **74/79**; refusal_probe **14/15** |
| a rule's refusal turned back into a bare identity (`edit_track::remove_media`'s `with_clips` refusal) | `core/tests/refusal.rs` **20/21**; refusal **115/116**; phase8 **74/79** |

Three readings, since a mutant table is only worth the rows somebody reads.
**The first mutant is the whole candidate, undone in four lines**, and what
it prints is the ambiguity itself: every refusal in the tree comes back as
`Remove Media made no change: the project is already in that state.`,
`Set Transition made no change…`, `Add Action made no change…` — the identity's
sentence, word for word, for eleven different rules. Fourteen of `refusal.rs`'s
twenty-one tests fall and sixteen proof checks, and the seven tests that
survive are the identity, the boundary and the invalid-input ones, which is
exactly right: the mutant takes away the ability to SAY, not the ability to
refuse. **It reaches three older scripts as well** — phase1's two rewritten
locked-track checks and phase8's five `remove_media` ones — which is a
different shape from D1, where three mutant tables in a row found that nothing
outside the new proof discriminated the behaviour. Here the older scripts
moved with D2·3 and D2·4 and are a second opinion now.
**The second mutant is the narrow one and is the more interesting of the
two**: it is D2·3's mutant 7 read the other way round. That ticket could not
score `remove_media` over MCP at all, because `AgentServer+Media.swift`'s own
`with_clips` count answered a step earlier and answered the same whichever arm
the core took. D2·4 deleted that count, so the same sabotage now costs five
checks in `phase8_proof.py` — including the nested-media one that is the whole
point of phase 8c — where a year's worth of scripts would once have passed it.
**And the probe's one failing check is the one no MCP call can reach**: a
refusal in front of `applyEdit`, which is where a person meets it.

**What its review found.** The two-axis review ran against `bfbc2ac`, and
everything below landed in `c91c6fc`. The
spec axis found all seven acceptance criteria met; both axes found the same
two numbers wrong, and the standards axis found two lines of my own making.
Fixed in the follow-up commit:

- **The one number the ticket's own claim rests on was not regenerated.**
  `core/src/edit_track.rs` is **522**, and both this record and the ledger's
  header said 520 — D2·3's record's figure, which was its TICKET commit's;
  its review fix (`0b91795`) took the file to 522 and the number was never
  chased. §6's measured table below had it right, so the document
  contradicted itself. "Regenerated row by row against `wc -l`" has to
  include the prose, not only the table.
- **A stale op count on a line this ticket rewrote.** Spec §7.10's `edit.rs`
  row still said an envelope key "would be a typo to all fifty-five";
  `OP_NAMES` is **57** and the table has 57 rows. Corrected there, in §6's
  preamble (`rc_op_names` is 57, not 55), and in the four mirrors that
  repeat it — `edit.rs`'s own three, `ReelOps.swift`, `AgentCatalog.swift`,
  `scope.rs` and `AgentServer+Scope.swift`, whose sentence is now "was
  unchanged" so it cannot rot again. `edit.rs`'s "all forty-eight work
  inside a nest" is **fifty** (57 less `refused_inside`'s seven). This is a
  rot from whichever road map added ops 56 and 57 rather than D2's, and it
  was taken because the op table's own text is a contract this ticket owns.
- **Two doc lines over the ~100-column rule**, at 124 and 104, both made by
  jamming a reflowed tail onto one line so `ClipPane.swift` would stay at
  609. The rule was met in the letter and broken in the spirit; both
  paragraphs are rewritten inside 100 columns and the file is still 609.
- **`phase5_chrome.py` printed a skip with no COUNT**, where
  `recording_probe.py` prints an integer that totals into the tail. It is
  `CROSS_BUILD_ROWS = 45` now — what sections 3 to 7 scored the last time
  the reference built (81/81 against today's 36) — hard-coded with the
  reason, because those rows cannot be counted without running them and a
  skip that prints no number is what `tools/proof/README.md` forbids.
- **Dead state in `recording_probe.py`**: `skip_reason` was still written
  and read nowhere once `skips` took over, and two `global` declarations
  named a variable the new helper owns. Gone.
- **Spec §5.5 understated the empty-selection family** at twelve ops, where
  its own source says fourteen — `split_clips` and `paste_attributes` reach
  the answer with no guard. Consistent at fourteen now in all three places.
- **A rule-adjacent decision with nowhere to live.** The spec axis was right
  that turning a failed reference build into a skip brushes against the root
  rulebook's "a probe that will not build is a scored FAILURE, never an
  exit". It is in the ROOT `CLAUDE.md` beside that sentence rather than in
  spec §11: §11 is the product's decision record and this is a verification
  rule, and the rulebook is where a verification rule is read. The clause
  says the rule is about the INSTRUMENT and not about a reference tree it
  compares against, and that every other build failure is still a failure.
- **`designs/reelcut-core-notes.md`'s archived Purity and Errors rules**
  still teach the two-outcome answer. The archive is not rewritten — that is
  what an archive is — but its header now names those two paragraphs as
  superseded, so a grep that lands there knows it is looking at 2026-09-17.
  Same shape as D1·6's fix to `reelcut-app-notes.md`'s header.

Judged not real:

- *The `ffi_drift` rationale is duplicated between the two scripts
  (Duplicated Code).* `build_reference` itself was already duplicated
  between them before this diff, and a `tools/proof` script is deliberately
  standalone — `mcp.py` is the only thing any of them imports. Extracting
  six lines of comment into a new shared module would leave the real
  duplication and add an import to two scripts that have none. The comment
  in `recording_probe.py` is shortened to point at `phase5_chrome.py`, which
  states it in full, which is the cheap half of the fix.
- *The skip's guard is a substring match on compiler output, so a future FFI
  break mentioning both strings is absorbed.* A future FFI break in the
  reference tree's own `ReelCore.swift` IS this cause; a break anywhere else
  does not name both, and the note it reads is the reference build's own
  error text. Narrow enough, and the alternative — parsing swiftc — is worse.

**Owed.** Nothing from this ticket. What D2 leaves is §6 below.

---

## 6. D2 — closed

Five tickets on `d2-refusal-reason`, every one landed and reviewed on
2026-09-18. **An op that changed nothing and an op a rule
refused are two different answers now**, and the reason a rule gives is the
rule's own sentence, written once, carried out through the FFI and printed to
the caller unaltered.

**What landed, in one paragraph per ticket.** D2·1 is the prefactor and is
core-only: `core/src/outcome.rs`, `Outcome` with `Applied` / `Identity` /
`Refused`, 65 signatures across fourteen modules changed to answer it, and
the compiler used as the instrument — it found 73 `Ok(None)`s that had to
decide which answer they were and five COMPOSED ops that would have turned an
inner refusal into "nothing happened". It also added `rc_project_apply`'s
fourth parameter, `reason_out`, in the FFI's three files in lockstep, and
gave the overlap rule its voice at all fourteen sites that had been throwing
its sentence away. D2·2 is the app side: `app/Sources/ReelEdit.swift` mirrors
the enum, the wrapper reads the two message channels, the five app paths that
read "nothing happened" each say which arm they handle, and the agent's
one-paragraph guess became two sentences. It is also where the seam's proof
and probe were born. D2·3 gave the remaining rules their sentences — ten more
of them, two beyond the spec's list because a function that speaks for one of
its two refusals and not the other re-creates the ambiguity inside itself —
and paid `edit_track.rs`'s toll first and alone by cutting `edit_canvas.rs`
out of it. D2·4 is the deletion the prefactor paid for: three agent handlers'
trial-applies and hand-written sentences went, the four `shadowed` checks
became real assertions, and spec §11 gained **D2-1** to draw the line the
spec's seventh decision had drawn in the wrong place. D2·5 made the documents
say what the code does, swept fifteen stale doc comments, counted the
empty-selection identities instead of estimating them, regenerated the
ledger, and failed the proof twice on purpose.

**The eleven rules that speak**, each in its own sentence, each written once
however many ops ask it: the overlap rule, a locked track, the last track, a
track that still holds clips, a media row a clip still shows, a cut with
nothing left to give a transition, a rippled cut whose two clips have no room
to overlap by shifting, a rippled cut where no overlap between the whole
request and one frame leaves every track it moves inside the overlap rule, an
action that would overlap another, an action that would run past its clip,
and a move to a track index the document has not got. Their sentences are
written at **fourteen sites** and passed through unaltered at **twenty-seven**
more — the compositions and the scoped apply, each matching all three arms so
a composed op answers in the words of whichever step declined.

**The two behaviour changes a caller sees**, both for an agent and neither
for a person at the machine:

1. **A refused op says which rule refused it, and what to send instead.**
   `move_clip` into a neighbour comes back
   `Move Clip was refused at move_clip: clips 3 and 4 would overlap by 8000
   ticks, more than half of the shorter clip (6000 ticks)`, and where an
   ARGUMENT would let the call through the sentence names it —
   `with_clips: true`, `ripple: true`. Four of those sentences used to be the
   APP's, written a step earlier from a trial-apply, and two of those were
   worse for a caller: `C.mov is used by 2 clips.` names neither clip, and
   the core's names both, nests included.
2. **An op that genuinely changed nothing says only that.** `<Action> made no
   change: the project is already in that state.` — no rule named, and in
   particular no lecture about the overlap rule, which every refused op used
   to get whatever it had asked for. That was not hypothetical: while
   verifying D1, every deliberately sabotaged door answered a PROPERTY patch
   with the overlap rule's paragraph.

**Measured, across the series.**

| | Before D2 | After D2 |
|---|---|---|
| `core/src` | 17 941 | **18 269** (+328) |
| — `core/src/outcome.rs` | — | **114** (new) |
| — `core/src/edit_canvas.rs` | — | **224** (new, a pure move out of `edit_track.rs`) |
| — `core/src/edit_track.rs` | 674 | **522** (off the over-cap list) |
| — `core/src/edit_transition.rs` / `edit_action.rs` / `edit_time.rs` | 553 / 321 / 537 | 586 / 359 / 560 |
| — `core/src/edit_clip.rs` | 1042 | **1028** |
| — `core/src/edit.rs` (exempt) | 887 | 895 |
| — `core/src/ffi_edit.rs` | 70 | 86 |
| `AgentServer*` (the handlers and the argument vocabulary) | 6034 | **6029** (−5) |
| — `AgentServer+Transitions.swift` | 133 | **123** |
| — `AgentServer+Media` / `+Tracks` / `+Audio` | 321 / 242 / 156 | 320 / 243 / 162 |
| `app/Sources/ReelEdit.swift` | — | **122** (new) |
| `app/Sources/ReelCore.swift` / `ProjectDocument.swift` | 1507 / 1353 | 1500 / 1352 |
| `make test` | 632 | **653** (`core/tests/refusal.rs`, 21 tests over 530 lines) |
| the refusal proof | — | **116/116** over nine sections, 876 lines |
| the refusal probe | — | **15/15**, 369 lines |

**So D2's arithmetic is the opposite shape to D1's, and it is worth saying
plainly.** D1 moved 617 lines OUT of the agent's handlers. D2 moved **five**,
and the code it actually deleted is thirty-nine lines across three functions
— a trial-apply and four hand-written sentences — with six back and the rest
of the difference made up by doc paragraphs saying why the checks that stayed
are not guesses. The deletion test still passes, but what it measures here is
not volume: **the app has no WAY to write a refusal sentence any more**, and
the arithmetic of the one rule it used to re-derive exists in one place. The
cost is +328 lines in `core/src`, of which 114 is the new module and most of
the rest is eleven rules' worth of prose that did not exist in any layer
before — the sentences are new information, not moved information. That is
the honest reading: D1 was a deduplication and D2 is a capability, and a
deepening can be either.

**The mutants the series ran: three in D2·1, six in D2·2, eight in D2·3,
five in D2·4 and two in D2·5 — twenty-four, every one caught.** D2·5's pair
is the spec's own: the reason discarded at the FFI (`core/tests/refusal.rs`
7/21, refusal 100/116, and three older scripts moving too) and a rule's
refusal turned back into a bare identity (refusal 115/116, phase8 74/79). And
D2·3's seventh mutant is the row worth reading: the transition's "no room"
refusal turned back into a bare identity scored **113/113** under D2·3's
proof, because the app's own trial-apply in front of it answered the same
either way, and only `core/tests/refusal.rs` could take it. D2·4 deleted that
trial-apply and the same mutant is caught by the proof now. A shadow closing,
measured rather than asserted.

**What is owed.**

- **The clamped-edge family still answers `Identity`** — a slip or a roll the
  clamps reduce to nothing, a roll with no predecessor, a trim whose two
  clamps crossed, a rate stretch outside ×0.1 – ×10, `detach_audio` with no
  audio, `set_transition_duration` with no predecessor or no room in front.
  Every one is a clamp that landed where the clip already was, which is the
  case where an identity is also an honest answer; none was on the spec's
  list; and `edit_clip.rs` and `edit_edge.rs` would have to pay a toll to
  take them on. Named in `Outcome::Identity`'s doc, which is the one place
  that list lives.
- **The empty-selection identities stay identities**, deliberately: fourteen
  ops, eight of them behind a guard of their own, named in that same doc and
  in spec §5.5.
- **A refusal's sentence is still not shown to the person at the machine.**
  The beep stays, which is spec kpgalligan/reelcut#8's own out-of-scope, and
  where such a message would live is a design question of its own.
- **Eight lines of unpaid toll in `core/src/edit.rs`** (887 → 895, over the
  cap under the table exemption, which is for TABLE rows): D2·1's, the
  Results section of the contract this candidate changed. D2·5 took two more
  and paid them inside the file; the SERIES total is these eight, and the
  next phase to touch that module doc pays them or takes the exemption on
  purpose. `AgentServer+Audio.swift` is 162 against the 156 it started at and
  is nowhere near the cap.
- **Two cross-build references cannot be built again** — `phase5_chrome.py`'s
  sections 3–7 and `recording_probe.py`'s §6b, both skipped by name since
  D2·5, both a consequence of the FFI's fourth parameter. The coverage lost
  is the meter's and the welcome button's byte comparison against the tree
  before each existed.
- **Nothing else.** No format bump, no new export, no new tool, no change to
  the tool count or to the startup parity check, and the invalid-input tier
  means and says exactly what it did.

**What a later deepening should take from this one.**

- **The compiler is the instrument when the change is "which answer is
  this".** An enum rather than a side channel was the whole of D2·1's
  argument, and it paid immediately: the five composed ops that would have
  swallowed an inner refusal were not on anybody's list, and no grep would
  have found them.
- **A rule with more than one site writes its sentence once and the sites
  pass a clause.** `locked_track`, `clip_list`, `action_past_end`,
  `overlapping_action`. Two ops cannot then drift apart on one rule, which is
  the same argument as the core being the one validator in D1.
- **Where an argument would let the op through, the sentence names that
  argument.** That is the difference between a reason and a description, and
  it is what a caller acts on.
- **Run EVERY script, not the ones the phase touched.** D2·2 to D2·4 ran the
  MCP proofs and one probe; D2·5 ran the tree and found two instruments that
  had not compiled since D2·2 and two reference builds that will never
  compile again. A phase that changes the FFI has broken something that
  reaches backwards in the history, by construction.
- **A ticket does not reverse a spec decision in a commit message.** D2·4's
  review put it exactly right — the reason was sound and the order was wrong
  — and spec §11's D2-1 is where the line got drawn. The next candidate that
  finds its spec half a step off writes the decision first.

**Where the next candidate starts.** The two D1 named and did not close, less
the one D2 just took: **deriving the catalog, the typed builders and the
parity check from the core's op table** — three mirrors of one list that a
startup check compares by name only, and the candidate the architecture
review of 2026-09-17 rated beside this one. Beside it, from this series' own
findings: the **clamped-edge family** above, which is the last place an
identity and a refusal are still told apart by reading the source; the
**source-window arithmetic written ten times**, which spec kpgalligan/reelcut#8
also left on the list; and the **cross-build reference instrument**, which
needs a core of the reference's own era if the meter and the welcome window
are to be photographed against their "before" again.

## 7. D3 — one op table, published

The candidate D1 and D2 both named and left: **an op is spelled twelve times
across seven production files and the startup parity check compares NAMES
only**, so a tool can declare an argument the core has never heard of, or the
wrong JSON kind for one, and pass every part of the check. The argument, the
measurements behind it and the sixteen implementation decisions are spec
kpgalligan/reelcut#14 and are not restated here. In one sentence: **the core
says what an argument IS, the app says what it is FOR**, and everything
downstream reads the core's table instead of restating it.

The shape is expand-then-migrate rather than tracer bullets: the table lands
beside everything that exists, the catalog is migrated group by group behind
it, and the fifth part of the parity check is turned on last — because until
every group is migrated it would complain about the ones that are not.

## 8. D3 — the record

### 8.1 D3·1 — the op table, and a test that asks the decoder (kpgalligan/reelcut#15)

**Commits.** `589d5b1` (the ticket) and `ade23da` (what its review found,
below).

**What landed.** Core only. No Swift file, no FFI export, no catalog entry,
no proof script, no format bump; `OP_NAMES` is 57 and the catalog 77, as
before. The app is byte-for-byte the app it was.

- **`core/src/op_table.rs` is new, 276 lines** — under the 400-line cap for
  a new module, and it does NOT take `edit.rs`'s standing table exemption,
  which was a hard acceptance criterion. One `OpRow` per op, in table order,
  and one `Argument` per argument: its name, its `Kind`, and whether the
  decoder requires it. **145 arguments over 57 rows.** Nothing else is in a
  row — no prose, no semantics, no default spelled a second time.
- **`Kind` is closed, with 17 variants**, four more than the ticket's list of
  spellings, and the module doc states the rule that fixes the number:
  **exactly one kind per answer the decoder can give**. Two kinds serde
  refuses identically would be a distinction the table claims and no test
  could prove. The four beyond the list are each undecodable as one of the
  thirteen: `Index` (`usize`, which serde names differently from `u32`),
  `Ranges` (`Vec<[Ticks; 2]>`, the silence cut's pairs), `Region`
  (`ZoomRegion` — a caller-authored object whose members the core DECLARES,
  so not an opaque one), and `Groups` (`Vec<Group>`, the one vocabulary that
  arrives as a list). `Kind::values` carries each vocabulary's members, and
  its match is EXHAUSTIVE for `refused_inside`'s reason.
- **A caller-authored patch is `Kind::Object`, and nothing more** — the five
  property patches, the action end patch, the two new-clip bodies, the two
  paste payloads and the media descriptor. Deepening D1 made the core the one
  validator of what a patch may carry and this table does not restate a word
  of it.
- **`OP_NAMES` is a compile-time projection of the table**, re-exported from
  `edit.rs` under the name and path it has always had. No caller in the core,
  the FFI, the tests or the app moved, and `core/tests/op_names.rs` passes
  untouched.
- **`edit.rs` lost its Arguments column, 895 → 838.** Every default that
  lived ONLY in that column was folded into the Semantics sentence, because
  what an absent argument MEANS is semantics: `add_text_clip`'s and
  `add_shape_clip`'s 5 s, `add_background`'s timeline length,
  `freeze_frame`'s 2 s, `add_action`'s 1 s, `add_zoom_action`'s 1 s with its
  `fit` and `ease_in_out`, `add_track`'s front, `add_marker`'s `Marker <n>`
  and red, `nest`'s `Nest <n>`, `add_transition`'s `center` and
  `ripple: false`, and `set_canvas`'s `rescale_clips: false`. The two
  vocabulary lists under the tables now point at `Kind::values` instead of
  repeating themselves.

**The test is the interesting half.** `core/tests/op_table.rs`, 350 lines,
six tests, and **the instrument is the decoder itself** — no second list is
written down for the first to be compared against:

- an argument no op has makes serde answer with the arguments it DOES have,
  and the answer is compared to the row in both directions AND in order;
- a required argument left out is answered `missing field`, naming it, and
  the baseline envelope — which carries no optional argument at all — is read
  without complaint, so an argument called optional that the decoder really
  needs fails here;
- each argument handed a value of another JSON kind is refused with the
  phrase that kind's own Rust type produces (`expected i64`, `expected u32`,
  `expected usize`, `expected an array of length 4`, …);
- a closed vocabulary handed a non-member answers with its whole list, and
  the list is compared to `Kind::values`;
- an opaque object is proved opaque by being READ as a string, a number and
  a list.

**One acceptance criterion could not be met as written, and the reason is
measured.** It asks the kind proof to assert that the decoder refuses a wrong
value *"naming that argument"*. `Op` is internally tagged, so serde buffers
each variant's content and re-reads it through a `ContentDeserializer` of its
own, and `serde_path_to_error` — which D1 uses inside a patch — answers `.`
for every field of every op. Tried and recorded, not assumed. The test names
the argument by CONSTRUCTION instead: every probe is the op's baseline
envelope, which the required-ness test proves readable, with exactly ONE
argument replaced, so the only thing that can have failed is the one the
probe changed. What it asserts in place of the name is the TYPE serde
wanted, which pins the kind harder than a name would.

**`#[rustfmt::skip]` on `OP_TABLE`** is the first in the tree. rustfmt's
60-character budget for a call's arguments breaks all but the shortest row
into four lines, which costs about 165 lines and the 400-line cap the ticket
made a criterion. The table is laid out by hand, one line per op where one
fits, inside the same 100 columns rustfmt keeps; `cargo fmt --check` is
clean.

**Verified.** `make test` **659 passed / 0 failed** (653 before, +6);
`cargo fmt --check` clean; `make lint` clean; `make typecheck` 0 errors and
exactly the four known AVFoundation warnings; `make app` BUILD SUCCEEDED;
the built binary launched on port 4831 and `grep "Reelcut: "` on its log
printed nothing — so the startup parity check still reads the DERIVED
`OP_NAMES` as the catalog's 57 ops, which is the projection proved in the
shipped binary rather than in a unit test.

**An independent oracle, beside the tests.** A throwaway script parsed the
`Op` enum out of `edit.rs` — every variant, every field and every
`#[serde(default)]` — and compared it to the table parsed out of
`op_table.rs`: 57 rows against 57 variants, 0 mismatches in argument name,
order or required-ness, and exactly one Rust type per `Kind` (modulo
`Option<…>`), which is the "one kind per answer" rule checked rather than
asserted.

**The mutants.** Five deliberate failures, each caught by exactly one test
and by no other:

| Mutant | Score |
|---|---|
| `add_transition`'s `align` removed from its row | `the_decoder_lists_exactly_the_arguments_the_table_lists` FAILED, 5 passed |
| `trim_start`'s `to` changed from `Ticks` to `Id` | `every_argument_is_refused_a_value_of_another_kind` FAILED, 5 passed |
| `set_reversed`'s `reversed` called optional | `every_required_argument_is_missed_and_every_optional_one_is_not` FAILED, 5 passed |
| `wipe_down` dropped from `Kind::Transition`'s members | `every_closed_vocabulary_answers_with_its_own_members` FAILED, 5 passed |
| `set_video`'s `patch` called a string rather than an object | `every_argument_is_refused_a_value_of_another_kind` FAILED, 5 passed |

**What the review found.** The Standards axis found the phase record missing
with three documents already pointing at it (this section), the ledger row
edited in place and out of its `sort -rn` order, three documents saying the
catalog *reads* the table when nothing outside it reads a row yet, and a
`Kind` match with a catch-all that would let a new vocabulary kind be
silently skipped by the very test meant to prove it — the inversion of
`scope.rs`'s `refused_inside`, and the one finding that changed code. The
Spec axis re-derived all 57 rows against the enum independently, reproduced
two mutants of its own, and raised the four extra kinds and the unproven
"naming" half, both answered above. Three findings were judged not real: the
table having no production consumer YET is the spec's own expand-then-migrate
sequence; `Kind::Object` having no wrong-kind probe IS the claim the kind
makes; and `OP_COUNT` having no compile-time tie to the enum's arm count is
the exposure the old `[&str; 57]` already had. The fixes are `ade23da`.

**Owed.** The whole of D3 past this ticket: the JSON Schema function over the
17 kinds, the query export, the catalog's migration, the fifth part of the
parity check, the widening list, and the proof scripts that stop re-typing
argument names in Python.
